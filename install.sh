#!/bin/bash
################################################################################
# NozzleMods Installer for EmComm Tools R7
#
# This script clones the NozzleMods repository and installs all tools:
#   - nozzle-menu → /opt/emcomm-tools/bin/
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
#
# Cubic ISO builder mode (auto-detected or forced):
#   ./install.sh --cubic
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
ETC_HOME="/opt/emcomm-tools"
ETC_BIN_DIR="${ETC_HOME}/bin"
TEMP_CLONE_DIR="/tmp/NozzleMods_install_$$"

# Cubic mode flag
CUBIC_MODE=false

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
# Cubic Detection
################################################################################

detect_cubic() {
  # Cubic chroot: root user, no systemd as PID 1, ETC filesystem present
  if [ "$EUID" -eq 0 ] && [ -d "${ETC_HOME}" ]; then
    local pid1_comm=""
    if [ -f /proc/1/comm ]; then
      pid1_comm=$(cat /proc/1/comm 2>/dev/null || true)
    fi
    if [ "${pid1_comm}" != "systemd" ]; then
      return 0
    fi
  fi
  return 1
}

################################################################################
# Cubic ISO Builder Mode
################################################################################

cubic_show_selection_menu() {
  # Selection state arrays — all off by default
  local -a radio_sel=(0 0 0 0)
  local -a desktop_sel=(0 0 0 0 0 0 0)

  local radio_labels=(
    "Xiegu G90 Mod"
    "Yaesu FT-710 Support"
    "Anytone 578 Support (includes custom Hamlib)"
    "AIOC Support"
  )

  local desktop_labels=(
    "ARDOP Log Viewer"
    "Direwolf Log Viewer"
    "AlsaMixer"
    "ET Kill All"
    "ET Mode"
    "ET Radio"
    "Nozzle Menu"
  )

  while true; do
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║          NozzleMods ISO Builder — Cubic Mode               ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Toggle items with their number/letter, then press G to go.${NC}"
    echo

    echo -e "${BLUE}Radio Mods:${NC}"
    echo
    local i
    for i in 0 1 2 3; do
      local mark=" "
      [[ "${radio_sel[$i]}" -eq 1 ]] && mark="X"
      echo "  $((i+1))) [${mark}] ${radio_labels[$i]}"
    done

    echo
    echo -e "${BLUE}Desktop Shortcuts:${NC}"
    echo
    local letters=(A B C D E F N)
    for i in 0 1 2 3 4 5 6; do
      local mark=" "
      [[ "${desktop_sel[$i]}" -eq 1 ]] && mark="X"
      echo "  ${letters[$i]}) [${mark}] ${desktop_labels[$i]}"
    done

    echo
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    echo "  S) Select All"
    echo "  X) Deselect All"
    echo "  G) Go — Apply selected mods"
    echo "  Q) Quit"
    echo
    echo -n "Enter choice: "

    read -r choice
    choice=$(echo "${choice}" | tr '[:lower:]' '[:upper:]')

    case "${choice}" in
      1) radio_sel[0]=$(( 1 - radio_sel[0] )) ;;
      2) radio_sel[1]=$(( 1 - radio_sel[1] )) ;;
      3) radio_sel[2]=$(( 1 - radio_sel[2] )) ;;
      4) radio_sel[3]=$(( 1 - radio_sel[3] )) ;;
      A) desktop_sel[0]=$(( 1 - desktop_sel[0] )) ;;
      B) desktop_sel[1]=$(( 1 - desktop_sel[1] )) ;;
      C) desktop_sel[2]=$(( 1 - desktop_sel[2] )) ;;
      D) desktop_sel[3]=$(( 1 - desktop_sel[3] )) ;;
      E) desktop_sel[4]=$(( 1 - desktop_sel[4] )) ;;
      F) desktop_sel[5]=$(( 1 - desktop_sel[5] )) ;;
      N) desktop_sel[6]=$(( 1 - desktop_sel[6] )) ;;
      S)
        for i in 0 1 2 3; do radio_sel[$i]=1; done
        for i in 0 1 2 3 4 5 6; do desktop_sel[$i]=1; done
        ;;
      X)
        for i in 0 1 2 3; do radio_sel[$i]=0; done
        for i in 0 1 2 3 4 5 6; do desktop_sel[$i]=0; done
        ;;
      G)
        # Pass selections to the apply function
        cubic_apply_selections radio_sel desktop_sel
        return
        ;;
      Q)
        echo "Cancelled."
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid choice${NC}"
        sleep 1
        ;;
    esac
  done
}

cubic_apply_selections() {
  local -n _radio="$1"
  local -n _desktop="$2"

  local any_selected=false
  for i in 0 1 2 3; do
    [[ "${_radio[$i]}" -eq 1 ]] && any_selected=true
  done
  for i in 0 1 2 3 4 5 6; do
    [[ "${_desktop[$i]}" -eq 1 ]] && any_selected=true
  done

  if [[ "${any_selected}" == false ]]; then
    echo
    print_warning "Nothing selected. Exiting."
    exit 0
  fi

  echo
  print_header "Applying NozzleMods to ISO"

  # Clone repo to get the files
  print_info "Fetching NozzleMods..."
  if ! clone_repository; then
    print_error "Failed to clone repository. Exiting."
    exit 1
  fi

  local src="${TEMP_CLONE_DIR}"

  # Always install nozzle-menu and bin scripts to the ISO
  print_info "Installing nozzle-menu to ${ETC_BIN_DIR}..."
  cp "${src}/bin/nozzle-menu" "${ETC_BIN_DIR}/"
  chmod +x "${ETC_BIN_DIR}/nozzle-menu"
  print_success "nozzle-menu installed"

  # Install helper scripts that desktop shortcuts depend on
  for helper in direwolf-log-viewer ardop-log-viewer et-alsamixer; do
    if [ -f "${src}/bin/${helper}" ]; then
      cp "${src}/bin/${helper}" "${ETC_BIN_DIR}/"
      chmod +x "${ETC_BIN_DIR}/${helper}"
    fi
  done

  # Install NozzleMods to /etc/skel so every new user gets them
  local skel_nozzle="/etc/skel/NozzleMods"
  print_info "Installing NozzleMods to ${skel_nozzle} (skeleton for new users)..."
  rm -rf "${skel_nozzle}"
  mkdir -p "${skel_nozzle}"
  cp -r "${src}/bin" "${skel_nozzle}/"
  cp -r "${src}/radio-tools" "${skel_nozzle}/"
  cp -r "${src}/linux-tools" "${skel_nozzle}/"
  [ -f "${src}/install.sh" ] && cp "${src}/install.sh" "${skel_nozzle}/"
  find "${skel_nozzle}" -type f -name "*.sh" -exec chmod +x {} \;
  chmod +x "${skel_nozzle}/bin/nozzle-menu" 2>/dev/null || true
  print_success "NozzleMods installed to skeleton"

  echo

  # Radio mods
  if [[ "${_radio[0]}" -eq 1 ]]; then
    print_header "Applying Xiegu G90 Mod"
    if [ -f "${src}/radio-tools/xiegu-g90/update-g90-config.sh" ]; then
      bash "${src}/radio-tools/xiegu-g90/update-g90-config.sh" || \
        print_warning "G90 config script returned non-zero (may need interactive input)"
    else
      print_error "G90 config script not found"
    fi
  fi

  if [[ "${_radio[1]}" -eq 1 ]]; then
    print_header "Applying Yaesu FT-710 Support"
    if [ -f "${src}/radio-tools/yaesu-ft710/install_ft710.sh" ]; then
      cd "${src}/radio-tools/yaesu-ft710"
      bash install_ft710.sh || \
        print_warning "FT-710 installer returned non-zero"
      cd /
    else
      print_error "FT-710 installer not found"
    fi
  fi

  if [[ "${_radio[2]}" -eq 1 ]]; then
    print_header "Applying Anytone 578 Support"

    # Build and install custom Hamlib first
    if [ -f "${src}/radio-tools/anytone-578/install_hamlib_anytone.sh" ]; then
      print_info "Building custom Hamlib with Anytone 578 driver..."
      cd "${src}/radio-tools/anytone-578"
      bash install_hamlib_anytone.sh || \
        print_warning "Custom Hamlib build returned non-zero"
      cd /
    else
      print_warning "Custom Hamlib installer not found, skipping"
    fi

    # Then install the Anytone 578 profile
    if [ -f "${src}/radio-tools/anytone-578/install_anytone578.sh" ]; then
      cd "${src}/radio-tools/anytone-578"
      bash install_anytone578.sh || \
        print_warning "Anytone 578 installer returned non-zero"
      cd /
    else
      print_error "Anytone 578 installer not found"
    fi
  fi

  if [[ "${_radio[3]}" -eq 1 ]]; then
    print_header "Applying AIOC Support"
    if [ -f "${src}/radio-tools/aioc/install_aioc.sh" ]; then
      cd "${src}/radio-tools/aioc"
      bash install_aioc.sh || \
        print_warning "AIOC installer returned non-zero"
      cd /
    else
      print_error "AIOC installer not found"
    fi
  fi

  # Desktop shortcuts — install to /etc/skel/Desktop and /usr/share/applications
  local desktop_files=(
    "ardop-log-viewer"
    "direwolf-log-viewer"
    "et-alsamixer"
    "et-kill-all"
    "et-mode"
    "et-radio"
    "nozzle-menu"
  )

  local any_desktop=false
  for i in 0 1 2 3 4 5 6; do
    [[ "${_desktop[$i]}" -eq 1 ]] && any_desktop=true
  done

  if [[ "${any_desktop}" == true ]]; then
    print_header "Installing Desktop Shortcuts"

    local skel_desktop="/etc/skel/Desktop"
    local apps_dir="/usr/share/applications"
    mkdir -p "${skel_desktop}" "${apps_dir}"

    for i in 0 1 2 3 4 5 6; do
      if [[ "${_desktop[$i]}" -eq 1 ]]; then
        local df="${desktop_files[$i]}"
        local desktop_src="${src}/bin/${df}.desktop"
        if [ -f "${desktop_src}" ]; then
          cp "${desktop_src}" "${skel_desktop}/${df}.desktop"
          chmod +x "${skel_desktop}/${df}.desktop"
          cp "${desktop_src}" "${apps_dir}/${df}.desktop"
          print_success "Desktop shortcut: ${df}"
        else
          print_warning "Desktop file not found: ${df}.desktop"
        fi
      fi
    done
  fi

  echo
  print_header "Cubic ISO Build Complete"
  echo "Selected NozzleMods have been applied to the ISO filesystem."
  echo
  echo "Items installed to:"
  echo "  • nozzle-menu and helpers → ${ETC_BIN_DIR}/"
  echo "  • NozzleMods scripts     → /etc/skel/NozzleMods/"
  echo "  • Desktop shortcuts      → /etc/skel/Desktop/"
  echo "  • App entries            → /usr/share/applications/"
  echo
  echo "New users created from this ISO will have NozzleMods ready to use."
  echo
  echo -e "${GREEN}73!${NC}"
  echo
}

################################################################################
# Pre-flight Checks (normal install mode)
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
# Installation Functions (normal install mode)
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
  print_info "Copying bin..."
  cp -r "${TEMP_CLONE_DIR}/bin" "${NOZZLE_DIR}/"

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

  local nozzle_menu_src="${NOZZLE_DIR}/bin/nozzle-menu"

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

install_desktop_shortcuts() {
  print_header "Installing Desktop Shortcuts"

  local desktop_dir="${HOME}/Desktop"
  local apps_dir="/usr/share/applications"
  mkdir -p "${desktop_dir}"

  # Install log viewer scripts to ET bin
  if [ -d "${ETC_BIN_DIR}" ]; then
    for viewer in direwolf-log-viewer ardop-log-viewer et-alsamixer; do
      local viewer_src="${NOZZLE_DIR}/bin/${viewer}"
      if [ -f "${viewer_src}" ]; then
        if sudo cp "${viewer_src}" "${ETC_BIN_DIR}/" 2>/dev/null && \
           sudo chmod +x "${ETC_BIN_DIR}/${viewer}" 2>/dev/null; then
          print_success "Installed ${viewer} to ${ETC_BIN_DIR}"
        else
          print_warning "Could not install ${viewer} to ${ETC_BIN_DIR}"
        fi
      fi
    done
  fi

  # Place new desktop icons starting from the top-left corner (GNOME / Desktop Icons NG)
  if command -v gsettings >/dev/null 2>&1; then
    if gsettings set org.gnome.shell.extensions.ding start-corner 'top-left' 2>/dev/null; then
      print_success "Desktop icons will arrange from the top-left"
    fi
  fi

  # Install .desktop files
  for desktop_file in direwolf-log-viewer ardop-log-viewer et-alsamixer et-radio et-mode et-kill-all nozzle-menu; do
    local src="${NOZZLE_DIR}/bin/${desktop_file}.desktop"
    if [ -f "${src}" ]; then
      local dest="${desktop_dir}/${desktop_file}.desktop"
      if cp "${src}" "${dest}" 2>/dev/null && chmod +x "${dest}" 2>/dev/null; then
        # Mark as trusted so it launches without the "Allow Launching" prompt
        gio set "${dest}" metadata::trusted true 2>/dev/null || \
          gio set "${dest}" metadata::trusted yes 2>/dev/null || true
        print_success "Desktop shortcut: ${desktop_file}"
      else
        print_warning "Could not create desktop shortcut: ${desktop_file}"
      fi

      sudo cp "${src}" "${apps_dir}/${desktop_file}.desktop" 2>/dev/null
    fi
  done
}

################################################################################
# Post-Installation Instructions
################################################################################

show_next_steps() {
  print_header "Installation Complete!"

  echo "All tools have been installed to:"
  echo "  ${NOZZLE_DIR}"
  echo
  echo "Run nozzle-menu to launch VARA with Pat or access Radio/System options."

  print_header "Quick Start"

  echo -e "${BLUE}To access all features:${NC}"
  echo "  nozzle-menu"
  echo
  echo -e "${BLUE}Or run tools directly:${NC}"
  echo
  echo -e "${YELLOW}Radio Configuration:${NC}"
  echo "  sudo ${NOZZLE_DIR}/radio-tools/xiegu-g90/update-g90-config.sh"
  echo "  sudo ${NOZZLE_DIR}/radio-tools/yaesu-ft710/install_ft710.sh"
  echo "  ${NOZZLE_DIR}/radio-tools/anytone-578/install_anytone578.sh"
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
  # Check for --cubic flag
  for arg in "$@"; do
    if [ "${arg}" = "--cubic" ]; then
      CUBIC_MODE=true
    fi
  done

  # Auto-detect Cubic environment
  if [ "${CUBIC_MODE}" = false ] && detect_cubic; then
    echo
    echo -e "${YELLOW}Cubic chroot environment detected.${NC}"
    echo -e "${YELLOW}Switching to ISO builder mode...${NC}"
    sleep 1
    CUBIC_MODE=true
  fi

  if [ "${CUBIC_MODE}" = true ]; then
    cubic_show_selection_menu
    return
  fi

  clear
  echo
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                                                            ║${NC}"
  echo -e "${GREEN}║              NozzleMods Installer for ETC R7               ║${NC}"
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

  # Install desktop shortcuts
  echo
  install_desktop_shortcuts

  # Show next steps
  echo
  show_next_steps
}

# Run main installation
main "$@"
