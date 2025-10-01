#!/bin/bash

# ############################################################################
# deb-injector: A tool to inject a custom script into a .deb package's
# post-installation lifecycle.
#
# Usage: ./deb-injector.sh <source-package.deb> <your-script.sh>
# ############################################################################

# --- Configuration & Colors ---
set -e  # Exit immediately if a command exits with a non-zero status.
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
NC=$(tput sgr0) # No Color

# --- Input Validation ---
echo "${GREEN}Step 0: Validating inputs...${NC}"

if [ "$#" -ne 2 ]; then
    echo "${RED}Error: Invalid number of arguments.${NC}"
    echo "Usage: $0 <source.deb> <script.sh>"
    exit 1
fi

if ! command -v dpkg-deb &> /dev/null; then
    echo "${RED}Error: 'dpkg-deb' command not found.${NC}"
    echo "Please install it with: ${YELLOW}sudo apt update && sudo apt install dpkg-dev${NC}"
    exit 1
fi

SOURCE_DEB="$1"
INJECT_SCRIPT="$2"

if [ ! -f "$SOURCE_DEB" ]; then
    echo "${RED}Error: Source package not found at '${SOURCE_DEB}'${NC}"
    exit 1
fi

if [ ! -f "$INJECT_SCRIPT" ]; then
    echo "${RED}Error: Injection script not found at '${INJECT_SCRIPT}'${NC}"
    exit 1
fi

echo "✅ Inputs are valid."

# --- Setup a Clean Workspace ---
echo "${GREEN}Step 1: Setting up a temporary workspace...${NC}"
# Create a temporary directory that will be automatically cleaned up on exit
TEMP_DIR=$(mktemp -d)
trap 'echo "${YELLOW}Cleaning up temporary files..."; rm -rf "$TEMP_DIR"' EXIT

echo "✅ Workspace created at '${TEMP_DIR}'"

# --- Unpack the Source Package ---
echo "${GREEN}Step 2: Unpacking '${SOURCE_DEB}'...${NC}"
CONTROL_DIR="${TEMP_DIR}/DEBIAN"
FILES_DIR="${TEMP_DIR}/files"

mkdir -p "${CONTROL_DIR}"
mkdir -p "${FILES_DIR}"

dpkg-deb -x "$SOURCE_DEB" "$FILES_DIR"
dpkg-deb -e "$SOURCE_DEB" "$CONTROL_DIR"

echo "✅ Package unpacked successfully."

# --- Inject the Custom Script ---
echo "${GREEN}Step 3: Injecting custom script as 'postinst'...${NC}"
POSTINST_PATH="${CONTROL_DIR}/postinst"

# Create a compliant postinst script that wraps the user's script.
# This ensures it runs during the 'configure' phase of installation.
{
    echo '#!/bin/sh'
    echo 'set -e'
    echo 'case "$1" in'
    echo '    configure)'
    # Append the user's entire script content here
    cat "$INJECT_SCRIPT"
    echo '    ;;'
    echo 'esac'
    echo 'exit 0'
} > "$POSTINST_PATH"

# CRITICAL: The postinst script must be executable
chmod 755 "$POSTINST_PATH"

echo "✅ Script injected and made executable."

# --- Repackage into a New .deb File ---
echo "${GREEN}Step 4: Repackaging into a new .deb file...${NC}"
# Generate the output filename, e.g., 'mypackage_1.0_amd64-modified.deb'
OUTPUT_DEB_NAME="$(basename "${SOURCE_DEB}" .deb)-modified.deb"

# Rebuild the package from our temporary directory structure
# Note: We build from 'files' directory after moving DEBIAN dir inside it
mv "$CONTROL_DIR" "$FILES_DIR/DEBIAN"
dpkg-deb --build "$FILES_DIR" "$OUTPUT_DEB_NAME"

echo "-----------------------------------------------------"
echo "${GREEN}🎉 Success! 🎉${NC}"
echo "New package created: ${YELLOW}${OUTPUT_DEB_NAME}${NC}"
echo "-----------------------------------------------------"

# The 'trap' command will handle the cleanup automatically upon exit.