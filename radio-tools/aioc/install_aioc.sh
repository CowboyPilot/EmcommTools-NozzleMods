#!/bin/bash
# Yaesu AIOC Support Installer for Emcomm Tools R7
# Author: Generated for AIOC support
# Date: Dec 22, 2025
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
DIREWOLF_CONF_DIR="${ET_HOME}/conf/template.d/packet"
BACKUP_DIR="${HOME}/.aioc-backup"
SBIN_DIR="${ET_HOME}/sbin"
BIN_DIR="${ET_HOME}/bin"

# Backup file
BACKUP_FILE="${BACKUP_DIR}/udev-tester.sh.backup"

# Script directory (where the downloaded files are)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ⚠️  WARNING - USE AT YOUR OWN RISK ⚠️        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "This script will modify system files for Emcomm Tools R7 to add"
echo "support for the AIOC (All-In-One-Cable)."
echo ""
echo "Changes to be made:"
echo "  • Install udev rules to ${UDEV_RULES_DIR}"
echo "  • Install radio configuration to ${RADIOS_DIR}"
echo "  • Install Direwolf configurations to ${DIREWOLF_CONF_DIR}"
echo "  • Reload udev to activate changes"
echo ""
echo "A backup of the original files will be saved to:"
echo "  ${BACKUP_DIR}"
echo ""

# Check for existing backup and offer restore
if [ -f "${BACKUP_FILE}" ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗"
    echo "║           BACKUP FOUND - RESTORE OPTION AVAILABLE             ║"
    echo "╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "A backup was found from a previous installation:"
    echo "  ${BACKUP_DIR}"
    echo ""
    read -p "Do you want to RESTORE the backup and exit? (y/N): " restore_choice
    
    if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Restoring backups..."
        
        # Remove installed files
        if [ -f "${RADIOS_DIR}/aioc.json" ]; then
            sudo rm "${RADIOS_DIR}/aioc.json"
            echo -e "${GREEN}✓ Radio configuration removed${NC}"
        fi
        
        if [ -f "${UDEV_RULES_DIR}/93-aioc.rules" ]; then
            sudo rm "${UDEV_RULES_DIR}/93-aioc.rules"
            echo -e "${GREEN}✓ udev rules removed${NC}"
        fi
        
        # Remove Direwolf configs
        for conf_file in direwolf.aioc-simple.conf direwolf.aioc-packet.conf direwolf.aioc-aprs.conf; do
            if [ -f "${DIREWOLF_CONF_DIR}/${conf_file}" ]; then
                sudo rm "${DIREWOLF_CONF_DIR}/${conf_file}"
                echo -e "${GREEN}✓ ${conf_file} removed${NC}"
            fi
        done
        
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
    "aioc.json"
    "93-aioc.rules"
    "direwolf.aioc-simple.conf"
    "direwolf.aioc-packet.conf"
    "direwolf.aioc-aprs.conf"
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
if [ ! -d "${DIREWOLF_CONF_DIR}" ]; then
    echo -e "${RED}✗ Direwolf configuration directory not found at ${DIREWOLF_CONF_DIR}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Emcomm Tools installation verified${NC}"

# Create backup directory
echo "Creating backup directory..."
mkdir -p "${BACKUP_DIR}"
echo -e "${GREEN}✓ Backup directory created${NC}"

# Install radio configuration
echo "Installing radio configuration..."
sudo cp "${SCRIPT_DIR}/aioc.json" "${RADIOS_DIR}/"
sudo chown root:et-data "${RADIOS_DIR}/aioc.json"
sudo chmod 644 "${RADIOS_DIR}/aioc.json"
echo -e "${GREEN}✓ Radio configuration installed${NC}"

# Install aioc-direwolf launcher
echo "Installing AIOC DireWolf Launcher..."
if [ -f "${SCRIPT_DIR}/aioc-direwolf" ]; then
    sudo cp "${SCRIPT_DIR}/aioc-direwolf" "${BIN_DIR}/"
    sudo chown root:et-data "${BIN_DIR}/aioc-direwolf"
    sudo chmod +x "${BIN_DIR}/aioc-direwolf"
    echo -e "${GREEN} aioc-direwolf script installed${NC}"
else
    echo -e "${YELLOW} aioc-direwolf script not found, skipping${NC}"
fi

# Install udev rules
echo "Installing udev rules..."
sudo cp "${SCRIPT_DIR}/93-aioc.rules" "${UDEV_RULES_DIR}/"
sudo chown root:root "${UDEV_RULES_DIR}/93-aioc.rules"
sudo chmod 644 "${UDEV_RULES_DIR}/93-aioc.rules"
echo -e "${GREEN}✓ udev rules installed${NC}"

# Install Direwolf configuration files
echo "Installing Direwolf configuration files..."
for conf_file in direwolf.aioc-simple.conf direwolf.aioc-packet.conf direwolf.aioc-aprs.conf; do
    sudo cp "${SCRIPT_DIR}/${conf_file}" "${DIREWOLF_CONF_DIR}/"
    sudo chown root:et-data "${DIREWOLF_CONF_DIR}/${conf_file}"
    sudo chmod 644 "${DIREWOLF_CONF_DIR}/${conf_file}"
    echo -e "${GREEN}✓ ${conf_file} installed${NC}"
done

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
echo "  1. Select the AIOC radio in Emcomm Tools (using et-radio or GUI)"
echo "  2. Connect your AIOC device via USB"
echo "  3. Verify the devices were created:"
echo "       ls -la /dev/et-cat /dev/et-audio"
echo ""
echo "Radio configuration notes:"
echo "  • The AIOC provides both CAT and audio interfaces"
echo "  • Multiple Direwolf configurations have been installed:"
echo "      - direwolf.aioc-simple.conf"
echo "      - direwolf.aioc-packet.conf"
echo "      - direwolf.aioc-aprs.conf"
echo ""
echo "Troubleshooting:"
echo "  • Monitor udev: sudo udevadm monitor"
echo "  • Test script: ${SBIN_DIR}/udev-tester.sh aioc"
echo "  • Check logs in /var/log/syslog"
echo ""
echo "Backup location: ${BACKUP_DIR}"
echo "  Run this script again and choose 'restore' to revert changes"
echo ""