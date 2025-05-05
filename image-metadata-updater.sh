#!/bin/bash

# Check if exiftool is installed
if ! command -v exiftool >/dev/null 2>&1; then
  echo "Error: exiftool is not installed. Install it using 'brew install exiftool'."
  exit 1
fi

# Check if ImageMagick (magick) is installed for color space conversion
if ! command -v magick >/dev/null 2>&1; then
  echo "Error: ImageMagick is not installed. Install it using 'brew install imagemagick'."
  exit 1
fi

# Check if at least one argument (image path) is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <image-path> [image-path...]"
  echo "Example: $0 image.jpg or $0 images/*"
  exit 1
fi

# Check if metadata-config.txt exists in the same directory as the script
CONFIG_FILE="$(dirname "$0")/metadata-config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: metadata-config.txt not found in $(dirname "$0")."
  exit 1
fi

# Path to sRGB ICC profile (adjust if needed)
SRGB_ICC="$(dirname "$0")/sRGB.icc"
if [ ! -f "$SRGB_ICC" ]; then
  echo "Error: sRGB.icc not found in $(dirname "$0"). Please download it or adjust the SRGB_ICC path."
  exit 1
fi

# Check and convert image to sRGB if not already sRGB
check_and_convert_srgb() {
  local image="$1"
  local icc_profile="$2"
  # Check current ICC profile
  local profile
  profile=$(magick identify -format "%[profile:icc]" "$image" 2>/dev/null)
  if [ "$profile" != "sRGB" ]; then
    echo "Converting '$image' to sRGB color space..."
    # Create a temporary file for conversion
    local temp_file
    temp_file=$(mktemp "${image%.*}_temp.XXXXXX.${image##*.}")
    if magick "$image" -strip -profile "$icc_profile" -quality 100 "$temp_file" 2>/dev/null; then
      mv "$temp_file" "$image"
      echo "Successfully converted '$image' to sRGB."
    else
      echo "Warning: Failed to convert '$image' to sRGB. Continuing with original image."
      rm -f "$temp_file"
    fi
  else
    echo "Image '$image' is already in sRGB color space."
  fi
}

# Function to generate a 5-character random alphanumeric string
generate_random_string() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5
}

# Function to validate and add metadata field
add_metadata_field() {
  local key="$1"
  local tag="$2"
  local validate_type="$3"
  local value="$4" # Use provided value instead of config for PRESERVED_FILE_NAME
  if [ -n "$value" ]; then
    case "$tag" in
    "XMP:Identifier")
      local random_string
      random_string=$(generate_random_string)
      if [ -n "$random_string" ]; then
        EXIFTOOL_ARGS+=("-$tag=$value-$random_string")
      else
        echo "Warning: Failed to generate random string for $key"
        EXIFTOOL_ARGS+=("-$tag=$value")
      fi
      ;;
    "OriginalTransmissionReference")
      if [ "${#value}" -le 32 ]; then
        EXIFTOOL_ARGS+=("-$tag=$value")
      else
        echo "Warning: Skipping $key: Value exceeds 32 characters ($value)"
      fi
      ;;
    "Category")
      if [ "${#value}" -le 3 ]; then
        EXIFTOOL_ARGS+=("-$tag=$value")
      else
        echo "Warning: Skipping $key: Value exceeds 3 characters ($value)"
      fi
      ;;
    *)
      case "$validate_type" in
      "date")
        if echo "$value" | grep -qE '^[0-9]{4}(:[0-9]{2}:[0-9]{2}|[0-9]{4})$'; then
          EXIFTOOL_ARGS+=("-$tag=$value")
        else
          echo "Warning: Skipping $key: Invalid date format ($value)"
        fi
        ;;
      "time")
        if echo "$value" | grep -qE '^[0-2][0-9]:[0-5][0-9]:[0-5][0-9]([+-][0-9]{2}:?[0-9]{2}|Z)?$'; then
          EXIFTOOL_ARGS+=("-$tag=$value")
        else
          echo "Warning: Skipping $key: Invalid time format ($value)"
        fi
        ;;
      "number")
        if echo "$value" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
          EXIFTOOL_ARGS+=("-$tag=$value")
        else
          echo "Warning: Skipping $key: Not a number ($value)"
        fi
        ;;
      "integer")
        if echo "$value" | grep -qE '^[0-9]+$'; then
          EXIFTOOL_ARGS+=("-$tag=$value")
        else
          echo "Warning: Skipping $key: Not an integer ($value)"
        fi
        ;;
      "gps")
        if echo "$value" | grep -qE '^[0-9]+(\.[0-9]+)? [NSWE]$|^[0-9]+(\.[0-9]+)?$'; then
          EXIFTOOL_ARGS+=("-$tag=$value")
        else
          echo "Warning: Skipping $key: Invalid GPS format ($value)"
        fi
        ;;
      *)
        EXIFTOOL_ARGS+=("-$tag=$value")
        ;;
      esac
      ;;
    esac
  fi
}

# Load metadata-config.txt
while IFS='=' read -r key value; do
  [ -z "$key" ] || [ "${key#\#}" != "$key" ] && continue
  key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  eval "$key=\"$value\""
done <"$CONFIG_FILE"

# Process each provided image
for IMAGE_PATH in "$@"; do
  echo "Processing '$IMAGE_PATH'..."

  # Check if the file exists
  if [ ! -f "$IMAGE_PATH" ]; then
    echo "Warning: File '$IMAGE_PATH' does not exist. Skipping."
    continue
  fi

  # Check if the file is a valid JPEG or PNG using exiftool
  FILE_TYPE=$(exiftool -filetype -b "$IMAGE_PATH" 2>/dev/null)
  EXTENSION=$(echo "${IMAGE_PATH##*.}" | tr '[:upper:]' '[:lower:]')
  if [ "$FILE_TYPE" = "JPEG" ] && [ "$EXTENSION" != "jpg" ] && [ "$EXTENSION" != "jpeg" ]; then
    echo "Warning: '$IMAGE_PATH' is a JPEG but has extension .$EXTENSION. Skipping."
    continue
  elif [ "$FILE_TYPE" = "PNG" ] && [ "$EXTENSION" != "png" ]; then
    echo "Warning: '$IMAGE_PATH' is a PNG but has extension .$EXTENSION. Skipping."
    continue
  elif [ "$FILE_TYPE" != "JPEG" ] && [ "$FILE_TYPE" != "PNG" ]; then
    echo "Warning: '$IMAGE_PATH' is not a valid JPEG or PNG image (detected as $FILE_TYPE). Skipping."
    continue
  fi

  # Get current date and time for each image to ensure unique timestamps
  CURRENT_TIME=$(date +"%Y:%m:%d %H:%M:%S")
  CURRENT_DATE_IPTCS=$(date +"%Y%m%d")
  CURRENT_TIME_IPTCS=$(date +"%H:%M:%S%z" | sed 's/\([0-9]\{2\}\)\([0-9]\{2\}\)$/\1:\2/')

  # Convert image to sRGB
  check_and_convert_srgb "$IMAGE_PATH" "$SRGB_ICC"

  # Remove all existing metadata, preserving ICC profile
  if ! exiftool -overwrite_original -all= -ICC_Profile:all= "$IMAGE_PATH" >/dev/null; then
    echo "Error: Failed to remove existing metadata from '$IMAGE_PATH'. Skipping."
    continue
  fi

  # Build exiftool command for new metadata
  EXIFTOOL_ARGS=(
    "-overwrite_original"
    "-CreateDate=$CURRENT_TIME"
    "-ModifyDate=$CURRENT_TIME"
    "-IPTC:DateCreated=$CURRENT_DATE_IPTCS"
    "-IPTC:TimeCreated=$CURRENT_TIME_IPTCS"
    "-IPTC:DigitalCreationDate=$CURRENT_DATE_IPTCS"
    "-IPTC:DigitalCreationTime=$CURRENT_TIME_IPTCS"
  )

  # Add metadata fields
  add_metadata_field "ARTIST" "Artist" "" "$ARTIST"
  add_metadata_field "AUTHOR" "Author" "" "$AUTHOR"
  add_metadata_field "CREATOR" "Creator" "" "$CREATOR"
  add_metadata_field "CREATOR_ORGANIZATION" "XMP-photoshop:Source" "" "$CREATOR_ORGANIZATION"
  add_metadata_field "COPYRIGHT" "Copyright" "" "$COPYRIGHT"
  add_metadata_field "DESCRIPTION" "Description" "" "$DESCRIPTION"
  add_metadata_field "COMMENT" "Comment" "" "$COMMENT"
  add_metadata_field "KEYWORDS" "Keywords" "" "$KEYWORDS"
  add_metadata_field "SOFTWARE" "Software" "" "$SOFTWARE"
  add_metadata_field "URL" "URL" "" "$URL"
  add_metadata_field "WEB_STATEMENT" "XMP:WebStatement" "" "$WEB_STATEMENT"
  add_metadata_field "CATEGORY" "Category" "" "$CATEGORY"
  add_metadata_field "SUPPLEMENTAL_CATEGORIES" "SupplementalCategories" "" "$SUPPLEMENTAL_CATEGORIES"
  add_metadata_field "TITLE" "Title" "" "$TITLE"
  add_metadata_field "GPS_LATITUDE" "GPSLatitude" "gps" "$GPS_LATITUDE"
  add_metadata_field "GPS_LONGITUDE" "GPSLongitude" "gps" "$GPS_LONGITUDE"
  add_metadata_field "GPS_ALTITUDE" "GPSAltitude" "gps" "$GPS_ALTITUDE"
  add_metadata_field "OBJECT_NAME" "ObjectName" "" "$OBJECT_NAME"
  add_metadata_field "BY_LINE" "By-line" "" "$BY_LINE"
  add_metadata_field "BY_LINE_TITLE" "By-lineTitle" "" "$BY_LINE_TITLE"
  add_metadata_field "CREDIT" "Credit" "" "$CREDIT"
  add_metadata_field "SOURCE" "Source" "" "$SOURCE"
  add_metadata_field "CONTACT" "Contact" "" "$CONTACT"
  add_metadata_field "CITY" "City" "" "$CITY"
  add_metadata_field "PROVINCE_STATE" "Province-State" "" "$PROVINCE_STATE"
  add_metadata_field "COUNTRY" "Country-PrimaryLocationName" "" "$COUNTRY"
  add_metadata_field "TRANSMISSION_REFERENCE" "OriginalTransmissionReference" "" "$TRANSMISSION_REFERENCE"
  add_metadata_field "RIGHTS" "XMP:Rights" "" "$RIGHTS"
  add_metadata_field "SUBJECT" "XMP:Subject" "" "$SUBJECT"
  add_metadata_field "CREATOR_PHONE" "XMP:CreatorWorkTelephone" "" "$CREATOR_PHONE"
  add_metadata_field "CREATOR_EMAIL" "XMP:CreatorWorkEmail" "" "$CREATOR_EMAIL"
  add_metadata_field "CREATOR_URL" "XMP:CreatorWorkURL" "" "$CREATOR_URL"
  add_metadata_field "LOCATION_CREATED" "XMP-iptcExt:LocationCreatedCity" "" "$LOCATION_CREATED"
  add_metadata_field "LOCATION_SHOWN" "XMP-iptcExt:LocationShownCity" "" "$LOCATION_SHOWN"
  add_metadata_field "EVENT" "XMP:Event" "" "$EVENT"
  add_metadata_field "PRESERVED_FILE_NAME" "XMP:PreservedFileName" "" "$(basename "$IMAGE_PATH")"
  add_metadata_field "IDENTIFIER" "XMP:Identifier" "" "$IDENTIFIER"
  add_metadata_field "COLOR_SPACE" "ColorSpace" "" "$COLOR_SPACE"

  # Run exiftool to apply new metadata
  if exiftool "${EXIFTOOL_ARGS[@]}" "$IMAGE_PATH"; then
    echo "Metadata successfully added to '$IMAGE_PATH'."
    echo "Verifying metadata for '$IMAGE_PATH'..."
    exiftool "$IMAGE_PATH"
  else
    echo "Error: Failed to add metadata to '$IMAGE_PATH'."
  fi
done
