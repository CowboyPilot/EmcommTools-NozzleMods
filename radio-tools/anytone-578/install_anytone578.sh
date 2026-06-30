#!/bin/bash
# Anytone 578 Support Installer for Emcomm Tools R6
#
#   USE AT YOUR OWN RISK
# This script modifies system files.
# While tested, it may cause issues with your Emcomm Tools installation.
# Always ensure you have backups before proceeding.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Directories
ET_HOME="/opt/emcomm-tools"
RADIOS_DIR="${ET_HOME}/conf/radios.d"
AUDIO_DIR="${RADIOS_DIR}/audio"
SBIN_DIR="${ET_HOME}/sbin"
BACKUP_DIR="${HOME}/.anytone578-backup"

# Backup files
BACKUP_FILE_UDEV="${BACKUP_DIR}/udev-tester.sh.backup"

# Script directory (where the downloaded files are)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         WARNING - USE AT YOUR OWN RISK                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "This script will modify system files for Emcomm Tools R6 to add"
echo "support for the Anytone 578 with Digirig Mobile."
echo ""
echo "Changes to be made:"
echo "  • Install radio configuration to ${RADIOS_DIR}"
echo "  • Install audio script to ${AUDIO_DIR}"
echo "  • Patch udev-tester.sh to recognize Anytone 578 as Digirig Mobile"
echo ""
echo "Backups will be saved to:"
echo "  ${BACKUP_DIR}"
echo ""

# Check for existing backup and offer restore
if [ -f "${BACKUP_FILE_UDEV}" ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           BACKUP FOUND - RESTORE OPTION AVAILABLE             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Backup files were found from a previous installation:"
    echo "  ${BACKUP_DIR}"
    echo ""
    read -p "Do you want to RESTORE the backups and exit? (y/N): " restore_choice

    if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Restoring backups..."

        # Restore udev-tester.sh if backup exists
        if [ -f "${BACKUP_FILE_UDEV}" ]; then
            sudo cp "${BACKUP_FILE_UDEV}" "${SBIN_DIR}/udev-tester.sh"
            sudo chmod +x "${SBIN_DIR}/udev-tester.sh"
            echo -e "${GREEN}✓ udev-tester.sh restored${NC}"
        fi

        # Remove installed files
        if [ -f "${RADIOS_DIR}/anytone-578.json" ]; then
            sudo rm "${RADIOS_DIR}/anytone-578.json"
            echo -e "${GREEN}✓ Radio configuration removed${NC}"
        fi

        if [ -f "${AUDIO_DIR}/anytone-578.sh" ]; then
            sudo rm "${AUDIO_DIR}/anytone-578.sh"
            echo -e "${GREEN}✓ Audio script removed${NC}"
        fi

        echo ""
        echo "Restore complete. Exiting."
        exit 0
    fi
fi

read -p "Do you want to proceed with installation? (y/N): " choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo "Starting installation..."
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}✗ Please do not run this script as root directly.${NC}"
    echo "  The script will ask for sudo privileges when needed."
    exit 1
fi

# Verify required files exist
echo "Checking required files..."
required_files=(
    "anytone-578.json"
    "anytone-578.sh"
    "udev-tester.patch"
)

for file in "${required_files[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${file}" ]; then
        echo -e "${RED}✗ Required file not found: ${file}${NC}"
        echo "  Please ensure all files are downloaded to the same directory."
        exit 1
    fi
done
echo -e "${GREEN}✓ All required files found${NC}"

# Verify Emcomm Tools installation
echo "Verifying Emcomm Tools installation..."
if [ ! -d "${ET_HOME}" ]; then
    echo -e "${RED}✗ Emcomm Tools installation not found at ${ET_HOME}${NC}"
    exit 1
fi
if [ ! -d "${RADIOS_DIR}" ]; then
    echo -e "${RED}✗ Radios directory not found at ${RADIOS_DIR}${NC}"
    exit 1
fi
if [ ! -f "${SBIN_DIR}/udev-tester.sh" ]; then
    echo -e "${RED}✗ udev-tester.sh not found at ${SBIN_DIR}/udev-tester.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Emcomm Tools installation verified${NC}"

# Create backup directory
echo "Creating backup directory..."
mkdir -p "${BACKUP_DIR}"
echo -e "${GREEN}✓ Backup directory created${NC}"

# Backup original udev-tester.sh
echo "Backing up original udev-tester.sh..."
cp "${SBIN_DIR}/udev-tester.sh" "${BACKUP_FILE_UDEV}"
echo -e "${GREEN}✓ Backup saved to ${BACKUP_FILE_UDEV}${NC}"

# Install radio configuration
echo "Installing radio configuration..."
sudo cp "${SCRIPT_DIR}/anytone-578.json" "${RADIOS_DIR}/"
sudo chown root:et-data "${RADIOS_DIR}/anytone-578.json"
sudo chmod 644 "${RADIOS_DIR}/anytone-578.json"
echo -e "${GREEN}✓ Radio configuration installed${NC}"

# Install audio script
echo "Installing audio script..."
sudo mkdir -p "${AUDIO_DIR}"
sudo cp "${SCRIPT_DIR}/anytone-578.sh" "${AUDIO_DIR}/"
sudo chown root:et-data "${AUDIO_DIR}/anytone-578.sh"
sudo chmod 755 "${AUDIO_DIR}/anytone-578.sh"
echo -e "${GREEN}✓ Audio script installed${NC}"

# Patch udev-tester.sh
echo "Checking if udev-tester.sh needs patching..."
if grep -q '"anytone-578"' "${SBIN_DIR}/udev-tester.sh"; then
    echo -e "${YELLOW}⚠ udev-tester.sh already patched for Anytone 578, skipping${NC}"
else
    echo "Patching udev-tester.sh..."
    sudo patch "${SBIN_DIR}/udev-tester.sh" < "${SCRIPT_DIR}/udev-tester.patch"
    sudo chmod +x "${SBIN_DIR}/udev-tester.sh"
    echo -e "${GREEN}✓ udev-tester.sh patched${NC}"

    # Verify the patch worked
    echo "Verifying udev patch..."
    if grep -q '"anytone-578"' "${SBIN_DIR}/udev-tester.sh"; then
        echo -e "${GREEN}✓ udev patch verified successfully${NC}"
    else
        echo -e "${RED}✗ udev patch verification failed!${NC}"
        echo "  Restoring udev-tester.sh backup..."
        sudo cp "${BACKUP_FILE_UDEV}" "${SBIN_DIR}/udev-tester.sh"
        sudo chmod +x "${SBIN_DIR}/udev-tester.sh"
        echo -e "${YELLOW}⚠ Backup restored. Installation failed.${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo "║                  ✓ INSTALLATION COMPLETE ✓                     ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Select the Anytone 578 in Emcomm Tools (using et-radio or GUI)"
echo "  2. Connect your Anytone 578 via Digirig Mobile USB"
echo "  3. Verify the devices were created:"
echo "       ls -la /dev/et-cat /dev/et-audio"
echo "  4. Run et-audio to configure audio settings:"
echo "       et-audio update-config"
echo ""
echo "Radio configuration notes:"
echo "  • Set VFO A Active in VFO Mode"
echo "  • Settings - (1) Radio Set - (4) Other Func - (6) Ana Sq Level to 0"
echo "  • Do not enable VOX on radio"
echo "  • Do not enable mic volt det (Leave as UART)"
echo ""
echo "Audio settings (applied by audio script):"
echo "  • Speaker (TX): 21% unmuted"
echo "  • Mic Playback: Muted"
echo "  • Mic Capture (RX): 13% unmuted"
echo "  • Auto Gain Control: Disabled"
echo "  Adjust these with alsamixer if needed"
echo ""
echo "Backup location: ${BACKUP_DIR}"
echo "  Run this script again and choose 'restore' to revert changes"
echo ""
