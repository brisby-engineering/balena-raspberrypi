#!/bin/bash

# SCP script to sync balena images from remote server
# Downloads all missing images and always downloads the main image

REMOTE_HOST="root@64.225.54.68"
REMOTE_PATH="/root/brisby_custom"
REMOTE_PATTERN="*.balenaos-img"
MAIN_FILE="balena-image-raspberrypi5.balenaos-img"
LOCAL_DIR="/Volumes/BRISBY/custom_imgs"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== Brisby Image Sync Script ==="
echo "Remote: ${REMOTE_HOST}:${REMOTE_PATH}"
echo "Local: ${LOCAL_DIR}"
echo ""

# Check if local directory exists
if [ ! -d "$LOCAL_DIR" ]; then
    echo -e "${RED}Error: Local directory does not exist: ${LOCAL_DIR}${NC}"
    exit 1
fi

# Get list of remote files
echo "Fetching remote file list..."
REMOTE_FILES=$(ssh ${REMOTE_HOST} "ls -1 ${REMOTE_PATH}/${REMOTE_PATTERN} 2>/dev/null" | xargs -n1 basename)

if [ -z "$REMOTE_FILES" ]; then
    echo -e "${YELLOW}Warning: No remote files found matching pattern ${REMOTE_PATTERN}${NC}"
    exit 1
fi

# Get list of local files (check both .balenaos-img and .img extensions)
LOCAL_FILES_BALENA=$(ls -1 "${LOCAL_DIR}"/*.balenaos-img 2>/dev/null | xargs -n1 basename)
LOCAL_FILES_IMG=$(ls -1 "${LOCAL_DIR}"/*.img 2>/dev/null | xargs -n1 basename | sed 's/\.img$/.balenaos-img/')
LOCAL_FILES=$(echo -e "${LOCAL_FILES_BALENA}\n${LOCAL_FILES_IMG}" | grep -v '^$' | sort -u)

echo "Found $(echo "$REMOTE_FILES" | wc -l | tr -d ' ') remote file(s)"
echo "Found $(echo "$LOCAL_FILES" | wc -l | tr -d ' ') local file(s)"
echo ""

# Find missing files
MISSING_FILES=""
FILES_TO_DOWNLOAD=""

for remote_file in $REMOTE_FILES; do
    if ! echo "$LOCAL_FILES" | grep -q "^${remote_file}$"; then
        MISSING_FILES="${MISSING_FILES}${remote_file}"$'\n'
        FILES_TO_DOWNLOAD="${FILES_TO_DOWNLOAD}${remote_file}"$'\n'
    fi
done

# Always add main file to download list (even if it exists locally)
if echo "$REMOTE_FILES" | grep -q "^${MAIN_FILE}$"; then
    if ! echo "$FILES_TO_DOWNLOAD" | grep -q "^${MAIN_FILE}$"; then
        FILES_TO_DOWNLOAD="${FILES_TO_DOWNLOAD}${MAIN_FILE}"$'\n'
    fi
    echo -e "${YELLOW}Main file (${MAIN_FILE}) will always be downloaded${NC}"
else
    echo -e "${RED}Warning: Main file (${MAIN_FILE}) not found on remote server${NC}"
fi

# Remove empty lines and duplicates
FILES_TO_DOWNLOAD=$(echo "$FILES_TO_DOWNLOAD" | grep -v '^$' | sort -u)

if [ -z "$FILES_TO_DOWNLOAD" ]; then
    echo -e "${GREEN}All files are already synced locally!${NC}"
    exit 0
fi

# Display files to download
echo ""
echo "Files to download:"
echo "$FILES_TO_DOWNLOAD" | while read -r file; do
    if [ "$file" == "$MAIN_FILE" ]; then
        echo -e "  ${GREEN}* ${file} (main file)${NC}"
    else
        echo -e "  ${YELLOW}  ${file} (missing)${NC}"
    fi
done

echo ""
read -p "Proceed with download? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Download cancelled."
    exit 0
fi

# Download files
echo ""
echo "Starting downloads..."
DOWNLOADED=0
FAILED=0

for file in $FILES_TO_DOWNLOAD; do
    echo -n "Downloading ${file}... "
    if scp "${REMOTE_HOST}:${REMOTE_PATH}/${file}" "${LOCAL_DIR}/"; then
        # Rename from .balenaos-img to .img (Raspberry Pi OS image extension)
        local_file_path="${LOCAL_DIR}/${file}"
        if [ -f "$local_file_path" ]; then
            new_file_path="${local_file_path%.balenaos-img}.img"
            if mv "$local_file_path" "$new_file_path"; then
                echo -e "${GREEN}✓ (renamed to .img)${NC}"
            else
                echo -e "${YELLOW}✓ (download succeeded, rename failed)${NC}"
            fi
        else
            echo -e "${GREEN}✓${NC}"
        fi
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        echo -e "${RED}✗ Failed${NC}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Summary ==="
echo -e "${GREEN}Successfully downloaded: ${DOWNLOADED} file(s)${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED} file(s)${NC}"
fi
