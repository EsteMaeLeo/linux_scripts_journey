#!/bin/bash

# Script to download files from GitHub raw URLs listed in a text file

# file path
URL_LIST="set the path of your fonts"

# Optional: folder to save downloads (creates it if missing) create .local if dont exist
SAVE_DIR="/home/user/.local/share/fonts"

if [ ! -d "$SAVE_DIR" ]; then
    mkdir -p "$SAVE_DIR"
    echo "Folder created successfully."
else
    echo "Folder already exists."
fi

# Check if the list file exists
if [ ! -f "$URL_LIST" ]; then
    echo "Error: File '$URL_LIST' not found!"
    exit 1
fi
clear
echo "Starting downloads from $URL_LIST..."
echo "Saving files to: /$SAVE_DIR/"
echo "************************************"

#read file line by line
while IFS= read -r url; do
#skip empty lines or lines starting #
  [[ -z "$url" || "$url" =~ ^# ]] && continue
    
    echo "Downloading: $url"

    #-P = save to directory 
    wget -q --show-progress -P "$SAVE_DIR" "$url"

done < "$URL_LIST"

echo "************************************"
echo "All downloads finished"
echo "************************************"
echo "Extract the files"
cd "$SAVE_DIR" || { echo "Cannot cd into $SAVE_DIR"; exit 1; }

#process the zip files
for zipfile in *.zip; do
#skip if no zip files found
  [[ "$zipfile" == "*.zip" ]] && continue
  
  ##get the folder name without .zip
  folder="${zipfile%.zip}"

  echo "Extracting zip -> $folder"

  #create the folder
  mkdir -p  "$folder"
  unzip -q "$zipfile" -d "$folder"

  #remove the file
  if $REMOVE_ARCHIVE_AFTER_EXTRACT; then
     rm -f "$zipfile" && echo " -> REMOVED $zipfile"
  fi
done

echo "************************************"
echo "Extraction finished!"
echo "fonts on $SAVE_DIR"
echo "************************************"
sudo fc-cache -fv