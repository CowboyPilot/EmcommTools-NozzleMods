#!/bin/bash
# Custom Hamlib Build for Anytone AT-D578UVIII
#
# Builds and installs a custom Hamlib fork with the AT-D578UVIII driver
# from https://github.com/CowboyPilot/Hamlib
#
# This replaces the system Hamlib with the custom build. The installer
# backs up the existing Hamlib libraries so they can be restored.
#
#   USE AT YOUR OWN RISK

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

REPO_URL="https://github.com/CowboyPilot/Hamlib.git"
BUILD_DIR="${HOME}/hamlib-anytone-build"
BACKUP_DIR="${HOME}/.hamlib-backup"
INSTALL_PREFIX="/usr/local"

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         WARNING - USE AT YOUR OWN RISK                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "This script will build and install a custom Hamlib fork with"
echo "support for the AnyTone AT-D578UVIII radio."
echo ""
echo "Source: ${REPO_URL}"
echo "Install prefix: ${INSTALL_PREFIX}"
echo ""
echo "Changes to be made:"
echo "  • Clone/update Hamlib source to ${BUILD_DIR}"
echo "  • Build Hamlib from source"
echo "  • Install to ${INSTALL_PREFIX} (replaces system Hamlib)"
echo "  • Backup existing Hamlib libraries"
echo ""
echo "Backups will be saved to:"
echo "  ${BACKUP_DIR}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}✗ Please do not run this script as root directly.${NC}"
    echo "  The script will ask for sudo privileges when needed."
    exit 1
fi

# Check for existing backup and offer restore
if [ -d "${BACKUP_DIR}" ] && [ "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           BACKUP FOUND - RESTORE OPTION AVAILABLE             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Backup files were found from a previous installation:"
    echo "  ${BACKUP_DIR}"
    echo ""
    read -p "Do you want to RESTORE the original Hamlib and exit? (y/N): " restore_choice

    if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Restoring original Hamlib libraries..."

        if [ -d "${BACKUP_DIR}/lib" ]; then
            sudo cp -a "${BACKUP_DIR}/lib/"* "${INSTALL_PREFIX}/lib/" 2>/dev/null || true
            echo -e "${GREEN}✓ Libraries restored${NC}"
        fi

        if [ -d "${BACKUP_DIR}/bin" ]; then
            sudo cp -a "${BACKUP_DIR}/bin/"* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
            echo -e "${GREEN}✓ Binaries restored${NC}"
        fi

        if [ -d "${BACKUP_DIR}/include" ]; then
            sudo cp -a "${BACKUP_DIR}/include/"* "${INSTALL_PREFIX}/include/" 2>/dev/null || true
            echo -e "${GREEN}✓ Headers restored${NC}"
        fi

        sudo ldconfig 2>/dev/null || true
        echo ""
        echo -e "${GREEN}Restore complete.${NC}"
        echo "Verify with: rigctl -l | grep -i anytone"
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

# Check build dependencies
echo "Checking build dependencies..."
MISSING_DEPS=()
for cmd in git make gcc automake autoconf libtool pkg-config; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        MISSING_DEPS+=("${cmd}")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing build dependencies: ${MISSING_DEPS[*]}${NC}"
    echo ""
    read -p "Install build dependencies now? (Y/n): " install_deps
    install_deps=${install_deps:-Y}

    if [[ "${install_deps}" =~ ^[Yy]$ ]]; then
        echo "Installing build dependencies..."
        sudo apt update
        sudo apt install -y git build-essential automake autoconf libtool pkg-config libusb-1.0-0-dev
        echo -e "${GREEN}✓ Build dependencies installed${NC}"
    else
        echo -e "${RED}Cannot proceed without build dependencies.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ All build dependencies found${NC}"
fi

# Also check for libusb dev headers
if ! dpkg -s libusb-1.0-0-dev >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing libusb development headers...${NC}"
    sudo apt install -y libusb-1.0-0-dev
    echo -e "${GREEN}✓ libusb-dev installed${NC}"
fi

# Backup existing Hamlib
echo ""
echo "Backing up existing Hamlib installation..."
mkdir -p "${BACKUP_DIR}"

if [ -d "${INSTALL_PREFIX}/lib" ]; then
    mkdir -p "${BACKUP_DIR}/lib"
    for f in "${INSTALL_PREFIX}/lib/"libhamlib*; do
        [ -e "$f" ] && cp -a "$f" "${BACKUP_DIR}/lib/" 2>/dev/null || true
    done
fi

if [ -f "${INSTALL_PREFIX}/bin/rigctl" ]; then
    mkdir -p "${BACKUP_DIR}/bin"
    for cmd in rigctl rigctld rigctlcom rigctltcp rotctl rotctld ampctl ampctld; do
        [ -f "${INSTALL_PREFIX}/bin/${cmd}" ] && cp -a "${INSTALL_PREFIX}/bin/${cmd}" "${BACKUP_DIR}/bin/" 2>/dev/null || true
    done
fi

if [ -d "${INSTALL_PREFIX}/include/hamlib" ]; then
    mkdir -p "${BACKUP_DIR}/include"
    cp -a "${INSTALL_PREFIX}/include/hamlib" "${BACKUP_DIR}/include/" 2>/dev/null || true
fi

echo -e "${GREEN}✓ Backup saved to ${BACKUP_DIR}${NC}"

# Clone or update repository
echo ""
if [ -d "${BUILD_DIR}/.git" ]; then
    echo "Updating existing Hamlib source..."
    cd "${BUILD_DIR}"
    git fetch origin
    git reset --hard origin/master
    echo -e "${GREEN}✓ Source updated${NC}"
else
    echo "Cloning Hamlib source..."
    rm -rf "${BUILD_DIR}"
    git clone "${REPO_URL}" "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    echo -e "${GREEN}✓ Source cloned${NC}"
fi

# Build
echo ""
echo -e "${BLUE}Building Hamlib (this may take several minutes)...${NC}"
echo ""

echo "Running bootstrap..."
./bootstrap
echo -e "${GREEN}✓ Bootstrap complete${NC}"

echo ""
echo "Running configure..."
./configure --prefix="${INSTALL_PREFIX}"
echo -e "${GREEN}✓ Configure complete${NC}"

echo ""
echo "Compiling..."
NPROC=$(nproc 2>/dev/null || echo 2)
make -j"${NPROC}"
echo -e "${GREEN}✓ Build complete${NC}"

# Install
echo ""
echo "Installing..."
sudo make install
sudo ldconfig
echo -e "${GREEN}✓ Installation complete${NC}"

# Verify
echo ""
echo "Verifying installation..."
if rigctl -l 2>/dev/null | grep -qi "anytone"; then
    echo -e "${GREEN}✓ AnyTone AT-D578UVIII driver found:${NC}"
    rigctl -l | grep -i anytone
else
    echo -e "${YELLOW}⚠ AnyTone driver not found in rigctl -l output${NC}"
    echo "  This may indicate a build issue. Check the output above for errors."
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo "║                  ✓ INSTALLATION COMPLETE ✓                     ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "The custom Hamlib with AT-D578UVIII support is now installed."
echo ""
echo "Usage:"
echo "  # PTT only (default, no radio lockout)"
echo "  rigctl -m 37001 -s 115200 -r /dev/et-cat"
echo ""
echo "  # Full control (freq/vfo/clock, locks radio display)"
echo "  rigctl -m 37001 -C commode=1 -s 115200 -r /dev/et-cat"
echo ""
echo "Verify installation:"
echo "  rigctl -l | grep -i anytone"
echo ""
echo "Build directory: ${BUILD_DIR}"
echo "  (kept for future updates — rerun this script to pull and rebuild)"
echo ""
echo "Backup location: ${BACKUP_DIR}"
echo "  Run this script again and choose 'restore' to revert to original Hamlib"
echo ""
