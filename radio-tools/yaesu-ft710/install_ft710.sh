#!/bin/bash
# Yaesu FT-710 Support Installer for Emcomm Tools R7
# Author: Generated for FT-710 support
# Date: Jan 31, 2025
#
#   USE AT YOUR OWN RISK 
# This script modifies system files and udev configuration.
# While tested, it may cause issues with your Emcomm Tools installation.
# Always ensure you have backups before proceeding.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories
ET_HOME="/opt/emcomm-tools"
RADIOS_DIR="${ET_HOME}/conf/radios.d"
UDEV_RULES_DIR="/etc/udev/rules.d"
SBIN_DIR="${ET_HOME}/sbin"
BIN_DIR="${ET_HOME}/bin"
BACKUP_DIR="${HOME}/.ft710-backup"

# Backup files
BACKUP_FILE_UDEV="${BACKUP_DIR}/udev-tester.sh.backup"
BACKUP_FILE_AUDIO="${BACKUP_DIR}/et-audio.backup"

# Script directory (where the downloaded files are)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         WARNING - USE AT YOUR OWN RISK                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "This script will modify system files for Emcomm Tools R7 to add"
echo "support for the Yaesu FT-710."
echo ""
echo "Changes to be made:"
echo "  • Install udev rules to ${UDEV_RULES_DIR}"
echo "  • Install radio configuration to ${RADIOS_DIR}"
echo "  • Patch udev-tester.sh to support FT-710"
echo "  • Patch et-audio to configure FT-710 audio settings"
echo "  • Reload udev to activate changes"
echo ""
echo "Backups will be saved to:"
echo "  ${BACKUP_DIR}"
echo ""

# Check for existing backup and offer restore
if [ -f "${BACKUP_FILE_UDEV}" ] || [ -f "${BACKUP_FILE_AUDIO}" ]; then
    echo -e "╔════════════════════════════════════════════════════════════════╗"
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
        
        # Restore et-audio if backup exists
        if [ -f "${BACKUP_FILE_AUDIO}" ]; then
            sudo cp "${BACKUP_FILE_AUDIO}" "${BIN_DIR}/et-audio"
            sudo chmod +x "${BIN_DIR}/et-audio"
            echo -e "${GREEN}✓ et-audio restored${NC}"
        fi
        
        # Remove installed files
        if [ -f "${RADIOS_DIR}/yaesu-ft710.json" ]; then
            sudo rm "${RADIOS_DIR}/yaesu-ft710.json"
            echo -e "${GREEN}✓ Radio configuration removed${NC}"
        fi
        
        if [ -f "${UDEV_RULES_DIR}/78-et-ft710.rules" ]; then
            sudo rm "${UDEV_RULES_DIR}/78-et-ft710.rules"
            echo -e "${GREEN}✓ udev rules removed${NC}"
        fi
        
        echo ""
        echo "Reloading udev..."
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        echo -e "${GREEN}✓ udev reloaded${NC}"
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

# Check if running as root for initial check
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}✗ Please do not run this script as root directly.${NC}"
    echo "  The script will ask for sudo privileges when needed."
    exit 1
fi

# Verify required files exist
echo "Checking required files..."
required_files=(
    "yaesu-ft710.json"
    "78-et-ft710.rules"
    "udev-tester.patch"
    "et-audio.patch"
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
if [ ! -f "${BIN_DIR}/et-audio" ]; then
    echo -e "${RED}✗ et-audio not found at ${BIN_DIR}/et-audio${NC}"
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

# Backup original et-audio
echo "Backing up original et-audio..."
sudo cp "${BIN_DIR}/et-audio" "${BACKUP_FILE_AUDIO}"
sudo chown $USER:$(id -gn) "${BACKUP_FILE_AUDIO}"
echo -e "${GREEN}✓ Backup saved to ${BACKUP_FILE_AUDIO}${NC}"

# Install radio configuration
echo "Installing radio configuration..."
sudo cp "${SCRIPT_DIR}/yaesu-ft710.json" "${RADIOS_DIR}/"
sudo chown root:et-data "${RADIOS_DIR}/yaesu-ft710.json"
sudo chmod 644 "${RADIOS_DIR}/yaesu-ft710.json"
echo -e "${GREEN}✓ Radio configuration installed${NC}"

# Install udev rules
echo "Installing udev rules..."
sudo cp "${SCRIPT_DIR}/78-et-ft710.rules" "${UDEV_RULES_DIR}/"
sudo chown root:root "${UDEV_RULES_DIR}/78-et-ft710.rules"
sudo chmod 644 "${UDEV_RULES_DIR}/78-et-ft710.rules"
echo -e "${GREEN}✓ udev rules installed${NC}"

# Patch udev-tester.sh
echo "Checking if udev-tester.sh needs patching..."
if grep -q "test_yaesu_ft710" "${SBIN_DIR}/udev-tester.sh" && \
   grep -q "yaesu-ft710)" "${SBIN_DIR}/udev-tester.sh"; then
    echo -e "${YELLOW}⚠ udev-tester.sh already patched, skipping${NC}"
else
    echo "Patching udev-tester.sh..."
    sudo patch "${SBIN_DIR}/udev-tester.sh" < "${SCRIPT_DIR}/udev-tester.patch"
    sudo chmod +x "${SBIN_DIR}/udev-tester.sh"
    echo -e "${GREEN}✓ udev-tester.sh patched${NC}"
    
    # Verify the patch worked
    echo "Verifying udev patch..."
    if grep -q "test_yaesu_ft710" "${SBIN_DIR}/udev-tester.sh" && \
       grep -q "yaesu-ft710)" "${SBIN_DIR}/udev-tester.sh"; then
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

# Patch et-audio
echo "Checking if et-audio needs patching..."
if grep -q '"FT-710")' "${BIN_DIR}/et-audio"; then
    echo -e "${YELLOW}⚠ et-audio already patched, skipping${NC}"
else
    echo "Patching et-audio..."
    sudo patch "${BIN_DIR}/et-audio" < "${SCRIPT_DIR}/et-audio.patch"
    sudo chmod +x "${BIN_DIR}/et-audio"
    echo -e "${GREEN}✓ et-audio patched${NC}"
    
    # Verify the patch worked
    echo "Verifying et-audio patch..."
    if grep -q '"FT-710")' "${BIN_DIR}/et-audio"; then
        echo -e "${GREEN}✓ et-audio patch verified successfully${NC}"
    else
        echo -e "${RED}✗ et-audio patch verification failed!${NC}"
        echo "  Restoring backups..."
        sudo cp "${BACKUP_FILE_UDEV}" "${SBIN_DIR}/udev-tester.sh"
        sudo chmod +x "${SBIN_DIR}/udev-tester.sh"
        sudo cp "${BACKUP_FILE_AUDIO}" "${BIN_DIR}/et-audio"
        sudo chmod +x "${BIN_DIR}/et-audio"
        echo -e "${YELLOW}⚠ Backups restored. Installation failed.${NC}"
        exit 1
    fi
fi

# Reload udev
echo "Reloading udev configuration..."
sudo udevadm control --reload-rules
sudo udevadm trigger
echo -e "${GREEN}✓ udev configuration reloaded${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo "║                  ✓ INSTALLATION COMPLETE ✓                     ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Select the Yaesu FT-710 in Emcomm Tools (using et-radio or GUI)"
echo "  2. Connect your FT-710 via USB"
echo "  3. Verify the devices were created:"
echo "       ls -la /dev/et-cat /dev/et-audio"
echo "  4. Run et-audio to configure audio settings:"
echo "       et-audio update-config"
echo ""
echo "Radio configuration notes:"
echo "  • Set CAT RATE to 38400bps (menu 031)"
echo "  • Set CAT TOT to 100ms (menu 032)"
echo "  • Set DATA MODE to OTHERS (menu 062)"
echo "  • FUNC → RADIO SETTING → MODE PSK/DATA:"
echo "      - USB OUT LEVEL = 30"
echo "      - USB MOD GAIN = 70"
echo "  • Select operating mode: DATA-U"
echo ""
echo "Audio settings (applied by et-audio):"
echo "  • Speaker (TX): 60% unmuted"
echo "  • Mic Playback: Muted"
echo "  • Mic Capture (RX): 60% unmuted"
echo "  • Auto Gain Control: Disabled"
echo "  Adjust these with alsamixer if needed"
echo ""
echo "Troubleshooting:"
echo "  • Monitor udev: sudo udevadm monitor"
echo "  • Test script: ${SBIN_DIR}/udev-tester.sh yaesu-ft710"
echo "  • Check logs in /var/log/syslog"
echo "  • View audio settings: alsamixer -c <card_number>"
echo ""
echo "Backup location: ${BACKUP_DIR}"
echo "  Run this script again and choose 'restore' to revert changes"
echo ""
