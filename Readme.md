# Image Metadata Updater [DEPRECATED]
(for mac)


This Bash script (image-metadata-updater.sh) processes JPEG and PNG images to:

- Convert images to sRGB color space using ImageMagick.
- Remove existing metadata while preserving the sRGB ICC profile.
- Apply new metadata from metadata-config.txt, including copyright, IPTC, and XMP fields.
- Add a unique identifier with a random 5-character suffix.

Requirements
ExifTool: brew install exiftool
ImageMagick: brew install imagemagick

metadata-config.txt: Configuration file in the same directory. - create it based on metadata-config-example.txt


## Usage

1. git clone this repo
2. chmod +x image-metadata-updater.sh
3. (!important) copy placeholder data from "metadata-config-example.txt"" and save it as a new file "metadata-config.txt" with your own info.
3. ./image-metadata-updater.sh <image-path>


## Examples

### Process a single image:
bash
./image-metadata-updater.sh image.jpg

### Process multiple images:

bash
./image-metadata-updater.sh images/*


## Features
- Validates JPEG (.jpg, .jpeg) and PNG (.png) files, skipping mismatched extensions (e.g., JPEG with .png).
- Ensures sRGB color space with ICC profile preservation.
- Sets metadata like Original Transmission Reference: EMK-SEOLITIC-LOCALHOST-4123 and Identifier: SM20250504-001-[random 5 chars].
- Uses dynamic timestamps based on system time.
- No backup files (_original) or log files created.

## Notes
- Place images in a directory (e.g., images/) for batch processing.
- Ensure images are writable (chmod u+rw images/*).
- Check metadata-config.txt for customizable metadata fields.
- We are using sRGB.icc v4 standard downloaded from (https://www.color.org/srgbprofiles.xalter#v4pref)
- For issues, verify sRGB.icc or download another to properly apply sRGB color profile and verify image formats (exiftool -filetype image.png).
