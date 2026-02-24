#!/bin/bash

# SCP script to sync balena images from remote server
# Always downloads balena-image-raspberrypi5.balenaos-img; also the most recent other .balenaos-img if not already local.

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

# Get remote files sorted by modification time (newest first)
echo "Fetching remote file list (by modification time)..."
REMOTE_FILES_BY_TIME=$(ssh ${REMOTE_HOST} "ls -t ${REMOTE_PATH}/${REMOTE_PATTERN} 2>/dev/null" | xargs -n1 basename)

if [ -z "$REMOTE_FILES_BY_TIME" ]; then
    echo -e "${YELLOW}Warning: No remote files found matching pattern ${REMOTE_PATTERN}${NC}"
    exit 1
fi

# Get list of local files (check both .balenaos-img and .img extensions)
LOCAL_FILES_BALENA=$(ls -1 "${LOCAL_DIR}"/*.balenaos-img 2>/dev/null | xargs -n1 basename)
LOCAL_FILES_IMG=$(ls -1 "${LOCAL_DIR}"/*.img 2>/dev/null | xargs -n1 basename | sed 's/\.img$/.balenaos-img/')
LOCAL_FILES=$(echo -e "${LOCAL_FILES_BALENA}\n${LOCAL_FILES_IMG}" | grep -v '^$' | sort -u)

# Helper: already have this file locally?
have_locally() {
    local f="$1"
    echo "$LOCAL_FILES" | grep -q "^${f}$"
}

# Build download list: always MAIN_FILE (if on remote) + most recent *other* file only if missing locally
FILES_TO_DOWNLOAD=""

# 1) Main file — always add when on remote (always re-download to get latest)
if echo "$REMOTE_FILES_BY_TIME" | grep -q "^${MAIN_FILE}$"; then
    FILES_TO_DOWNLOAD="${FILES_TO_DOWNLOAD}${MAIN_FILE}"$'\n'
else
    echo -e "${RED}Warning: Main file (${MAIN_FILE}) not found on remote server${NC}"
fi

# 2) Most recent *other* file (first in time-sorted list that is not MAIN_FILE)
MOST_RECENT_OTHER=""
for f in $REMOTE_FILES_BY_TIME; do
    if [ "$f" != "$MAIN_FILE" ]; then
        MOST_RECENT_OTHER="$f"
        break
    fi
done
if [ -n "$MOST_RECENT_OTHER" ] && ! have_locally "$MOST_RECENT_OTHER"; then
    FILES_TO_DOWNLOAD="${FILES_TO_DOWNLOAD}${MOST_RECENT_OTHER}"$'\n'
fi

# Remove empty lines
FILES_TO_DOWNLOAD=$(echo "$FILES_TO_DOWNLOAD" | grep -v '^$')

echo "Remote files (newest first): $(echo $REMOTE_FILES_BY_TIME | tr '\n' ' ')"
echo "Local files: $(echo $LOCAL_FILES | tr '\n' ' ')"
echo ""

if [ -z "$FILES_TO_DOWNLOAD" ]; then
    echo -e "${GREEN}Main image and most recent other are already synced locally. Nothing to download.${NC}"
    exit 0
fi

# Display files to download
echo "Files to download:"
echo "$FILES_TO_DOWNLOAD" | while read -r file; do
    if [ "$file" == "$MAIN_FILE" ]; then
        echo -e "  ${GREEN}* ${file} (main file)${NC}"
    else
        echo -e "  ${YELLOW}  ${file} (most recent other)${NC}"
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
                balena os configure $new_file_path --fleet brisby/casco_smart --config-wifi-ssid TellMyWifiILoveHer --config-wifi-key B0ssF4mily! 
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
