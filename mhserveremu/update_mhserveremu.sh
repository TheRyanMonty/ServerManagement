#!/bin/bash

# --- CONFIGURATION ---
# Set the directory where the files will be saved.
DOWNLOAD_DIR="/opt/mhserver/downloads/"
# The URL to the nightly.link landing page.
LANDING_PAGE_URL="https://nightly.link/Crypto137/MHServerEmu/workflows/nightly-release-linux-x64/master"

# --- SCRIPT LOGIC ---
# Create the directory if it doesn't exist.
mkdir -p "$DOWNLOAD_DIR"

# Download the HTML content of the landing page to a temporary file.
echo "$(date) Starting update process for mhserveremu..."
echo "$(date) Fetching the download link..."
HTML_CONTENT=$(curl -sL "$LANDING_PAGE_URL")

# Extract the direct download link from the HTML using grep and awk.
# The screenshot shows the link is in the 'a' tag. We'll look for the permanent link
# inside the <ul> tags as they are more consistent.
DOWNLOAD_URL=$(echo "$HTML_CONTENT" | grep -o -E 'https?://nightly.link/[^"]+\.zip' | head -n 1)

# Check if a URL was found.
if [ -z "$DOWNLOAD_URL" ]; then
        echo "$(date) Error: Could not find a valid download URL on the page."
        exit 1
fi

echo "$(date) Found download URL: $DOWNLOAD_URL"
echo "$(date) Downloading the latest nightly build..."

# Navigate to the download directory.
cd "$DOWNLOAD_DIR"

# Download the file using the extracted URL.
# We don't need the -L flag now as this is the final download link.
/usr/bin/wget -nv "$DOWNLOAD_URL"

echo "$(date) Download complete."


# This finds all files with a .zip extension, sorts by modification time,
# and deletes all but the most recent one.
zip_count=$(find . -type f -name "*.zip*" -printf '%T@ %p\n' | wc -l)
if (( $zip_count > 1)); then
        echo "$(date) Cleaning up older files..."
        find ${DOWNLOAD_DIR} -type f -name "*.zip*" -printf '%T@ %p\n' | sort -n | head -n -1 | awk '{print $2}' | xargs rm --
else
        echo "$(date) No older files to remove"
fi

echo "$(date) Unpacking downloaded files...."

filename=$(ls -alrt *.zip* | awk -F ' ' '{print $9}' | head -1)

/usr/bin/unzip -o $filename -d /opt/mhserver

echo "$(date) Unpacking completed!"

exit 0
