#!/bin/bash
# Mercury Modem Installer
#
# Builds and installs the Mercury HF modem from source.
# https://github.com/Rhizomatica/mercury
#
# Internal Hamlib is disabled (HAVE_HAMLIB=0) so Mercury does not conflict
# with custom Hamlib builds. Use rigctld for rig control instead.
#
#   USE AT YOUR OWN RISK

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

REPO_URL="https://github.com/Rhizomatica/mercury.git"
BUILD_DIR="${HOME}/mercury-build"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║               Mercury Modem Installer                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "This script will build and install the Mercury HF modem."
echo ""
echo "Source: ${REPO_URL}"
echo "Build directory: ${BUILD_DIR}"
echo ""
echo "Internal Hamlib is disabled — use rigctld for rig control."
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}✗ Please do not run this script as root directly.${NC}"
    echo "  The script will ask for sudo privileges when needed."
    exit 1
fi

# Check if already installed and offer reinstall/update
if command -v mercury >/dev/null 2>&1; then
    echo -e "${YELLOW}Mercury is already installed: $(which mercury)${NC}"
    echo ""
    read -p "Reinstall/update Mercury? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
else
    read -p "Do you want to proceed with installation? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

echo ""
echo "Starting installation..."
echo ""

# Check and install dependencies
echo "Checking build dependencies..."
MISSING_PKGS=()
for pkg in build-essential pkg-config libasound2-dev libpulse-dev libhamlib-dev make git; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
        MISSING_PKGS+=("${pkg}")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing packages: ${MISSING_PKGS[*]}${NC}"
    echo ""
    read -p "Install missing dependencies now? (Y/n): " install_deps
    install_deps=${install_deps:-Y}

    if [[ "${install_deps}" =~ ^[Yy]$ ]]; then
        echo "Installing dependencies..."
        sudo apt-get update
        sudo apt-get install -y build-essential pkg-config libasound2-dev libpulse-dev libhamlib-dev make git
        echo -e "${GREEN}✓ Dependencies installed${NC}"
    else
        echo -e "${RED}Cannot proceed without dependencies.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ All dependencies found${NC}"
fi

# Clone or update repository
echo ""
if [ -d "${BUILD_DIR}/.git" ]; then
    echo "Updating existing Mercury source..."
    cd "${BUILD_DIR}"
    git fetch origin
    git reset --hard origin/main
    echo -e "${GREEN}✓ Source updated${NC}"
else
    echo "Cloning Mercury source..."
    rm -rf "${BUILD_DIR}"
    git clone "${REPO_URL}" "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    echo -e "${GREEN}✓ Source cloned${NC}"
fi

# Disable internal Hamlib in Makefile
echo ""
echo "Disabling internal Hamlib (HAVE_HAMLIB=0)..."
if grep -q "^HAVE_HAMLIB" Makefile; then
    sed -i 's/^HAVE_HAMLIB.*/HAVE_HAMLIB = 0/' Makefile
    echo -e "${GREEN}✓ Internal Hamlib disabled${NC}"
else
    echo -e "${YELLOW}⚠ HAVE_HAMLIB not found in Makefile, may already be configured${NC}"
fi

# Build
echo ""
echo -e "${BLUE}Building Mercury (this may take a few minutes)...${NC}"
echo ""

NPROC=$(nproc 2>/dev/null || echo 2)
make -j"${NPROC}"
echo ""
echo -e "${GREEN}✓ Build complete${NC}"

# Install
echo ""
echo "Installing..."
sudo make install
echo -e "${GREEN}✓ Installation complete${NC}"

# Verify
echo ""
echo "Verifying installation..."
if command -v mercury >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Mercury installed: $(which mercury)${NC}"
else
    echo -e "${YELLOW}⚠ 'mercury' not found in PATH after install${NC}"
    echo "  It may have been installed to /usr/local/bin — check your PATH"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo "║                  ✓ INSTALLATION COMPLETE ✓                     ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Mercury is installed with internal Hamlib disabled."
echo "Use rigctld for rig control:"
echo "  rigctld -m 37001 -s 115200 -r /dev/et-cat &"
echo ""
echo "Build directory: ${BUILD_DIR}"
echo "  (kept for future updates — rerun this script to pull and rebuild)"
echo ""
