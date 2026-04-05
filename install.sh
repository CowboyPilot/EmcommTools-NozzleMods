#!/bin/bash
################################################################################
# NozzleMods Installer for EmComm Tools R5
#
# This script clones the NozzleMods repository and installs all tools:
#   - nozzle-menu → /opt/emcomm-tools/bin/
#   - wine-tools/ → ~/NozzleMods/wine-tools/
#   - radio-tools/ → ~/NozzleMods/radio-tools/
#   - linux-tools/ → ~/NozzleMods/linux-tools/
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CowboyPilot/EmcommTools-NozzleMods/main/install.sh | bash
#
# Or download and run:
#   wget https://raw.githubusercontent.com/CowboyPilot/EmcommTools-NozzleMods/main/install.sh
#   chmod +x install.sh
#   ./install.sh
################################################################################

set -euo pipefail

# GitHub repository
REPO_URL="https://github.com/CowboyPilot/EmcommTools-NozzleMods.git"
REPO_BRANCH="main"

# Colors for output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Installation paths
NOZZLE_DIR="${HOME}/NozzleMods"
ETC_BIN_DIR="/opt/emcomm-tools/bin"
TEMP_CLONE_DIR="/tmp/NozzleMods_install_$$"

################################################################################
# Helper Functions
################################################################################

print_header() {
  echo
  echo -e "${GREEN}================================================================${NC}"
  echo -e "${GREEN}  $1${NC}"
  echo -e "${GREEN}================================================================${NC}"
  echo
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}! $1${NC}"
}

print_info() {
  echo -e "${BLUE}→ $1${NC}"
}

check_command() {
  if ! command -v "$1" &> /dev/null; then
    print_error "Required command '$1' not found"
    return 1
  fi
  return 0
}

cleanup_temp() {
  if [ -d "${TEMP_CLONE_DIR}" ]; then
    print_info "Cleaning up temporary files..."
    rm -rf "${TEMP_CLONE_DIR}"
  fi
}

# Trap to ensure cleanup on exit
trap cleanup_temp EXIT

################################################################################
# Pre-flight Checks
################################################################################

preflight_checks() {
  print_header "Pre-flight Checks"
  
  local missing_deps=0
  
  # Check for required commands
  for cmd in git chmod; do
    if check_command "$cmd"; then
      print_success "$cmd found"
    else
      missing_deps=1
    fi
  done
  
  if [ $missing_deps -eq 1 ]; then
    print_error "Missing required dependencies"
    echo
    echo "Please install missing packages and try again:"
    echo "  sudo apt update"
    echo "  sudo apt install git coreutils"
    exit 1
  fi
  
  # Check if running as root
  if [ "$EUID" -eq 0 ]; then
    print_error "Do NOT run this script as root"
    echo
    echo "Run as your normal user:"
    echo "  ./install.sh"
    exit 1
  fi
  
  # Verify we can access GitHub
  print_info "Checking GitHub connectivity..."
  if git ls-remote "${REPO_URL}" &>/dev/null; then
    print_success "GitHub accessible"
  else
    print_error "Cannot reach GitHub repository"
    echo
    echo "Please check your internet connection and try again"
    exit 1
  fi
  
  echo
  print_success "All pre-flight checks passed"
}

################################################################################
# Installation Functions
################################################################################

clone_repository() {
  print_header "Cloning Repository"
  
  print_info "Cloning from ${REPO_URL}..."
  print_info "Branch: ${REPO_BRANCH}"
  
  if git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${TEMP_CLONE_DIR}"; then
    print_success "Repository cloned successfully"
    return 0
  else
    print_error "Failed to clone repository"
    return 1
  fi
}

backup_existing() {
  if [ -d "${NOZZLE_DIR}" ]; then
    print_header "Backing Up Existing Installation"
    
    local backup_dir="${NOZZLE_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Creating backup at ${backup_dir}..."
    
    if mv "${NOZZLE_DIR}" "${backup_dir}"; then
      print_success "Existing installation backed up"
      print_info "Old version saved to: ${backup_dir}"
    else
      print_warning "Could not backup existing installation"
      print_info "Proceeding with installation anyway..."
    fi
  fi
}

install_files() {
  print_header "Installing Files"
  
  # Create main directory
  print_info "Creating ${NOZZLE_DIR}..."
  mkdir -p "${NOZZLE_DIR}"
  
  # Copy all directories from the cloned repo
  print_info "Copying wine-tools..."
  cp -r "${TEMP_CLONE_DIR}/wine-tools" "${NOZZLE_DIR}/"
  
  print_info "Copying radio-tools..."
  cp -r "${TEMP_CLONE_DIR}/radio-tools" "${NOZZLE_DIR}/"
  
  print_info "Copying linux-tools..."
  cp -r "${TEMP_CLONE_DIR}/linux-tools" "${NOZZLE_DIR}/"
  
  # Copy the installer itself for future use
  if [ -f "${TEMP_CLONE_DIR}/install.sh" ]; then
    print_info "Copying installer script..."
    cp "${TEMP_CLONE_DIR}/install.sh" "${NOZZLE_DIR}/"
    chmod +x "${NOZZLE_DIR}/install.sh"
  fi
  
  # Make all shell scripts executable
  print_info "Making scripts executable..."
  find "${NOZZLE_DIR}" -type f -name "*.sh" -exec chmod +x {} \;
  
  print_success "Files installed successfully"
}

install_nozzle_menu() {
  print_header "Installing Nozzle Menu"
  
  local nozzle_menu_src="${NOZZLE_DIR}/wine-tools/bin/nozzle-menu"
  
  # Check if source file exists
  if [ ! -f "${nozzle_menu_src}" ]; then
    print_error "nozzle-menu not found at ${nozzle_menu_src}"
    print_info "You can install it manually later if the file becomes available"
    return 1
  fi
  
  # Check if we can write to /opt/emcomm-tools/bin
  if [ ! -d "${ETC_BIN_DIR}" ]; then
    print_warning "Directory ${ETC_BIN_DIR} does not exist"
    print_info "This is normal if EmComm Tools is not fully set up"
    print_info "You can install nozzle-menu manually later with:"
    echo "  sudo cp ${nozzle_menu_src} /opt/emcomm-tools/bin/"
    echo "  sudo chmod +x /opt/emcomm-tools/bin/nozzle-menu"
    return 0
  fi
  
  if [ ! -w "${ETC_BIN_DIR}" ]; then
    print_warning "Cannot write to ${ETC_BIN_DIR} (need sudo)"
    print_info "Attempting to install with sudo..."
    
    # Try with sudo
    if sudo cp "${nozzle_menu_src}" "${ETC_BIN_DIR}/" 2>/dev/null && \
       sudo chmod +x "${ETC_BIN_DIR}/nozzle-menu" 2>/dev/null; then
      print_success "Installed nozzle-menu with sudo"
    else
      print_error "Failed to install nozzle-menu"
      print_info "You can install it manually later with:"
      echo "  sudo cp ${nozzle_menu_src} /opt/emcomm-tools/bin/"
      echo "  sudo chmod +x /opt/emcomm-tools/bin/nozzle-menu"
      return 1
    fi
  else
    # Can write without sudo
    print_info "Copying nozzle-menu to ${ETC_BIN_DIR}..."
    if cp "${nozzle_menu_src}" "${ETC_BIN_DIR}/" 2>/dev/null && \
       chmod +x "${ETC_BIN_DIR}/nozzle-menu" 2>/dev/null; then
      print_success "Installed nozzle-menu"
    else
      print_error "Failed to install nozzle-menu"
      return 1
    fi
  fi
  
  echo
  print_success "nozzle-menu installed successfully"
}

################################################################################
# Post-Installation Instructions
################################################################################

show_next_steps() {
  print_header "Installation Complete!"
  
  echo "All tools have been installed to:"
  echo "  ${NOZZLE_DIR}"
  echo
  echo "Place the VarAC installer in ~/Downloads then run nozzle-menu to install"
  echo "the VARA Apps and optional System/Radio options."
  echo
  echo "If you have already installed VARA from the menu you can run"
  echo "~/NozzleMods/wine-tools/wine-setup.sh to install VarAC"
  
  print_header "Quick Start"
  
  echo -e "${BLUE}To access all features:${NC}"
  echo "  nozzle-menu"
  echo
  echo -e "${BLUE}Or run tools directly:${NC}"
  echo
  echo -e "${YELLOW}Wine/VARA Tools:${NC}"
  echo "  ${NOZZLE_DIR}/wine-tools/wine-setup.sh"
  echo "  ${NOZZLE_DIR}/wine-tools/fix-varac-13.sh"
  echo
  echo -e "${YELLOW}Radio Configuration:${NC}"
  echo "  sudo ${NOZZLE_DIR}/radio-tools/xiegu-g90/update-g90-config.sh"
  echo "  sudo ${NOZZLE_DIR}/radio-tools/yaesu-ft710/install_ft710.sh"
  echo "  sudo ${NOZZLE_DIR}/radio-tools/aioc/install_aioc.sh"
  echo
  echo -e "${YELLOW}Linux System Tools:${NC}"
  echo "  sudo ${NOZZLE_DIR}/linux-tools/fix-sources.sh"
  echo
  
  print_header "Notes"
  echo "• nozzle-menu has been installed to /opt/emcomm-tools/bin/"
  echo "• Run 'nozzle-menu' from anywhere to access the main menu"
  echo "• All other tools remain in ${NOZZLE_DIR}"
  echo "• You can re-run this installer to update all scripts"
  echo
  echo "73!"
  echo
}

################################################################################
# Main Installation Flow
################################################################################

main() {
  clear
  echo
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                                                            ║${NC}"
  echo -e "${GREEN}║              NozzleMods Installer for ETC R5               ║${NC}"
  echo -e "${GREEN}║                                                            ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo
  
  # Run pre-flight checks
  preflight_checks
  
  # Clone the repository
  echo
  if ! clone_repository; then
    print_error "Failed to clone repository. Exiting."
    exit 1
  fi
  
  # Backup existing installation if present
  echo
  backup_existing
  
  # Install files
  echo
  if ! install_files; then
    print_error "Failed to install files. Exiting."
    exit 1
  fi
  
  # Install nozzle-menu
  echo
  install_nozzle_menu || {
    print_warning "nozzle-menu installation failed, but other tools are installed"
    echo "Continuing..."
  }
  
  # Show next steps
  echo
  show_next_steps
}

# Run main installation
main
