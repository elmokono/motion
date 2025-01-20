#!/bin/bash

# Path to the folder containing the videos and images
ROOT_FOLDER="/media/hdd2/Camara/Recordings/"

# move file from ramdisk to hdd
mv "$1" "$ROOT_FOLDER"

# Change to the root directory
cd "$ROOT_FOLDER" || exit 1

# Iterate over both .mp4 and .jpg files in the folder
for FILE in *.mp4; do
    # Check if the file exists (to handle cases where no .mp4 or .jpg files are found)
    if [ -e "$FILE" ]; then
        # Extract the filename without extension
        FILENAME="${FILE%.*}"

        # Extract the date from the filename (format: 0-01-YYYYMMDDHHMMSS.mp4 or .jpg)
        DATE=$(echo "$FILE" | grep -oP '\d{8}' | head -n 1)

        # Format the date as YYYY-MM-DD
        DAY="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}"

        # Create the subfolder if it doesn't exist
        mkdir -p "$DAY"

        # Move the file to the corresponding subfolder
        mv "$FILE" "$DAY/"

        FULL_PATH="$(realpath "$DAY/$FILE")"

        #generate thumbnail
        ffmpeg -i "$FULL_PATH" -frames:v 1 "$DAY"/"$FILENAME".jpg
    fi
done