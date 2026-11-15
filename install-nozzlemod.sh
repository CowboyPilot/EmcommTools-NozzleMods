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
#   curl -fsSL https://raw.githubusercontent.com/CowboyPilot/EmcommTools-NozzleMods/main/install-nozzlemod.sh | bash
#
# Or download and run:
#   wget https://raw.githubusercontent.com/CowboyPilot/EmcommTools-NozzleMods/main/install-nozzlemod.sh
#   chmod +x install-nozzlemod.sh
#   ./install-nozzlemod.sh
#
# Cubic ISO builder mode (auto-detected in chroot, or forced with --cubic):
#   wget -O /tmp/install-nozzlemod.sh https://raw.githubusercontent.com/CowboyPilot/EmcommTools-NozzleMods/main/install-nozzlemod.sh && bash /tmp/install-nozzlemod.sh
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
  # Cubic chroot: root user + one of these signals
  if [ "$EUID" -eq 0 ]; then
    # Check hostname from every available source
    local hn=""
    hn="${HOSTNAME:-}"
    [ -z "${hn}" ] && hn=$(hostname 2>/dev/null || true)
    [ -z "${hn}" ] && hn=$(cat /etc/hostname 2>/dev/null || true)
    [ -z "${hn}" ] && hn=$(cat /proc/sys/kernel/hostname 2>/dev/null || true)
    if [ "${hn}" = "cubic" ]; then
      return 0
    fi

    # ischroot utility (from debianutils)
    if command -v ischroot >/dev/null 2>&1 && ischroot 2>/dev/null; then
      return 0
    fi

    # Chroot detection: / has a different device or inode than host root
    if [ -r /proc/1/root ] 2>/dev/null; then
      local root_dev host_dev
      root_dev=$(stat -c '%d:%i' / 2>/dev/null || true)
      host_dev=$(stat -c '%d:%i' /proc/1/root/. 2>/dev/null || true)
      if [ -n "${root_dev}" ] && [ -n "${host_dev}" ] && [ "${root_dev}" != "${host_dev}" ]; then
        return 0
      fi
    fi
  fi
  return 1
}

################################################################################
# Cubic ISO Builder Mode
################################################################################

cubic_bootstrap_etc() {
  # Called when ETC hasn't been installed yet (no rigctl → no hamlib → no ETC)
  print_header "EmComm Tools Not Detected"
  echo "rigctl was not found, which means EmComm Tools has not been"
  echo "installed in this Cubic environment yet."
  echo
  echo -e "${YELLOW}This wizard will download ETC R7 and run its installer first,${NC}"
  echo -e "${YELLOW}then continue with NozzleMods.${NC}"
  echo

  # 1) Get the ETC archive URL from the user (default to R7 release)
  local default_etc_url="https://github.com/thetechprepper/emcomm-tools-os-community/archive/refs/heads/release/r7.zip"
  echo -e "${BLUE}ETC R7 archive URL (.zip or .tar.gz):${NC}"
  echo -e "  Default: ${default_etc_url}"
  echo -e "${BLUE}Press Enter to use the default, or paste a different URL:${NC}"
  echo -n "> "
  read -r etc_url </dev/tty

  if [[ -z "${etc_url}" ]]; then
    etc_url="${default_etc_url}"
  fi

  # Validate extension
  local etc_file
  etc_file=$(basename "${etc_url}" | sed 's/?.*//')
  local ext=""
  if [[ "${etc_file}" == *.tar.gz ]]; then
    ext="tar.gz"
  elif [[ "${etc_file}" == *.tgz ]]; then
    ext="tgz"
  elif [[ "${etc_file}" == *.zip ]]; then
    ext="zip"
  else
    print_error "URL must point to a .zip or .tar.gz file"
    exit 1
  fi

  # 2) Download
  local dl_dir="/tmp/etc-download"
  rm -rf "${dl_dir}"
  mkdir -p "${dl_dir}"
  local dl_path="${dl_dir}/${etc_file}"

  print_info "Downloading ETC R7..."
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fSL -o "${dl_path}" "${etc_url}"; then
      print_error "Download failed. Check the URL and try again."
      exit 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q -O "${dl_path}" "${etc_url}"; then
      print_error "Download failed. Check the URL and try again."
      exit 1
    fi
  else
    print_error "Neither curl nor wget found. Install one and try again."
    exit 1
  fi
  print_success "Downloaded ${etc_file}"

  # 3) Extract
  local extract_dir="/tmp/etc-extract"
  rm -rf "${extract_dir}"
  mkdir -p "${extract_dir}"

  print_info "Extracting..."
  case "${ext}" in
    tar.gz|tgz)
      tar xzf "${dl_path}" -C "${extract_dir}"
      ;;
    zip)
      if ! command -v unzip >/dev/null 2>&1; then
        print_info "Installing unzip..."
        apt-get update -qq && apt-get install -y -qq unzip
      fi
      unzip -q "${dl_path}" -d "${extract_dir}"
      ;;
  esac
  print_success "Extracted"

  # 4) Find the scripts directory
  local root_dir
  root_dir=$(find "${extract_dir}" -maxdepth 1 -mindepth 1 -type d | head -1)
  if [[ -z "${root_dir}" ]]; then
    print_error "Could not find extracted directory"
    exit 1
  fi

  local scripts_dir="${root_dir}/scripts"
  if [[ ! -d "${scripts_dir}" ]]; then
    print_error "Expected scripts directory not found at ${scripts_dir}"
    echo "Contents of extracted archive:"
    ls -la "${root_dir}"
    exit 1
  fi
  print_success "Found scripts directory: ${scripts_dir}"

  # 5) Prompt user to copy custom packages into the scripts directory
  cd "${scripts_dir}"
  echo
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║              Copy Custom Packages (Optional)              ║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
  echo
  echo "If you have custom packages (e.g. pfte, xara-1.2.0.tar.gz),"
  echo "use the Cubic copy button (top-left) to copy them now."
  echo
  echo "The current directory is set to the ETC scripts directory:"
  echo -e "  ${BLUE}${scripts_dir}${NC}"
  echo
  echo "Cubic will drop copied files here so install.sh can find them."
  echo
  echo -e "${BLUE}Press Enter when ready to continue...${NC}"
  read -r </dev/tty

  # 6) Ask about NozzleMod Hamlib (AT578 branch)
  echo
  echo -e "${BLUE}Will you be installing the NozzleMod AT578 Hamlib branch? (Y/n):${NC}"
  echo -n "> "
  read -r hamlib_choice </dev/tty
  hamlib_choice=$(echo "${hamlib_choice}" | tr '[:upper:]' '[:lower:]')

  local use_nozzle_hamlib=true
  if [[ "${hamlib_choice}" == "n" || "${hamlib_choice}" == "no" ]]; then
    use_nozzle_hamlib=false
  fi

  if [[ "${use_nozzle_hamlib}" == true ]]; then
    # Remove ETC's hamlib installer so it doesn't build twice
    if [[ -f "${scripts_dir}/install-hamlib.sh" ]]; then
      print_info "Removing ETC install-hamlib.sh (NozzleMods will build custom Hamlib later)..."
      rm "${scripts_dir}/install-hamlib.sh"
      print_success "ETC Hamlib installer removed"
    else
      print_warning "install-hamlib.sh not found in scripts dir — may have a different name"
      echo "Contents of scripts directory:"
      ls "${scripts_dir}"/*.sh 2>/dev/null || ls "${scripts_dir}/"
      echo
      echo -e "${YELLOW}If you see a hamlib install script above, enter its filename to remove it${NC}"
      echo -e "${YELLOW}(or press Enter to skip):${NC}"
      echo -n "> "
      read -r hamlib_script </dev/tty
      if [[ -n "${hamlib_script}" && -f "${scripts_dir}/${hamlib_script}" ]]; then
        rm "${scripts_dir}/${hamlib_script}"
        print_success "Removed ${hamlib_script}"
      fi
    fi
  fi

  # 7) Run ETC's install.sh from the scripts directory
  print_header "Running ETC Installer"
  print_info "Running install.sh from ${scripts_dir}..."
  echo

  cd "${scripts_dir}"
  if bash install.sh; then
    print_success "ETC installation complete"
  else
    print_warning "ETC install.sh exited with non-zero status"
    echo -e "${YELLOW}Some components may not have installed correctly.${NC}"
    echo -e "${YELLOW}Press Enter to continue with NozzleMods anyway, or Ctrl+C to abort.${NC}"
    read -r </dev/tty
  fi
  cd /

  # Cleanup
  rm -rf "${dl_dir}" "${extract_dir}"

  # 8) Patch et-xara with additional flags
  patch_et_xara

  # 9) Prompt to copy files to the ISO desktop
  echo
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║              Copy Files to ISO Desktop (Optional)         ║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
  echo
  echo "If you have files you'd like on every user's desktop in the ISO,"
  echo "use the Cubic copy button (top-left) to copy them now."
  echo
  echo "The current directory has been set to /etc/skel/Desktop so"
  echo "Cubic will place copied files directly on the desktop."
  echo
  if command -v xara >/dev/null 2>&1; then
    echo -e "${BLUE}Xara was installed successfully.${NC}"
    echo "The default search directories for keying files will be:"
    echo "  • Desktop/xara/hf_keying"
    echo "  • Desktop/xara/fm_keying"
    echo
    mkdir -p /etc/skel/Desktop/xara/hf_keying /etc/skel/Desktop/xara/fm_keying
    print_success "Created xara keying directories in skeleton desktop"
    echo
  fi
  cd /etc/skel/Desktop
  echo -e "${BLUE}Press Enter when ready to continue...${NC}"
  read -r </dev/tty
  cd /

  echo
  print_success "ETC bootstrap complete — continuing with NozzleMods..."
  echo
}

cubic_show_selection_menu() {
  # Selection state arrays — all off by default
  local -a radio_sel=(1 1 1 1)
  local -a desktop_sel=(1 1 1 1 1 1 1)

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

    read -r choice </dev/tty
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
  local radios_dir="${ETC_HOME}/conf/radios.d"
  local audio_dir="${radios_dir}/audio"
  local sbin_dir="${ETC_HOME}/sbin"
  local udev_dir="/etc/udev/rules.d"
  local direwolf_dir="${ETC_HOME}/conf/template.d/packet"

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
  [ -f "${src}/install-nozzlemod.sh" ] && cp "${src}/install-nozzlemod.sh" "${skel_nozzle}/"
  find "${skel_nozzle}" -type f -name "*.sh" -exec chmod +x {} \;
  chmod +x "${skel_nozzle}/bin/nozzle-menu" 2>/dev/null || true
  print_success "NozzleMods installed to skeleton"

  echo

  # ── Radio Mods (done inline — sub-scripts reject root / need interactive input) ──

  # 1) Xiegu G90 — set CAT PTT in existing config
  if [[ "${_radio[0]}" -eq 1 ]]; then
    print_header "Applying Xiegu G90 Mod"
    local g90_json="${radios_dir}/xiegu-g90.json"
    if [ -f "${g90_json}" ]; then
      if command -v jq >/dev/null 2>&1; then
        cp "${g90_json}" "${g90_json}.backup"
        jq '.rigctrl.ptt = "RIG"' "${g90_json}.backup" > "${g90_json}"
        print_success "G90 config set to CAT PTT"
      else
        print_warning "jq not available — install it (apt install jq) and re-run, or configure G90 manually"
      fi
    else
      print_warning "G90 config not found at ${g90_json} — radio may not be in this ETC build"
    fi
  fi

  # 2) Yaesu FT-710 — install JSON, udev rules, patch udev-tester and et-audio
  if [[ "${_radio[1]}" -eq 1 ]]; then
    print_header "Applying Yaesu FT-710 Support"
    local ft710_dir="${src}/radio-tools/yaesu-ft710"

    # Radio config
    if [ -f "${ft710_dir}/yaesu-ft710.json" ]; then
      cp "${ft710_dir}/yaesu-ft710.json" "${radios_dir}/"
      chown root:et-data "${radios_dir}/yaesu-ft710.json" 2>/dev/null || true
      chmod 644 "${radios_dir}/yaesu-ft710.json"
      print_success "FT-710 radio config installed"
    fi

    # udev rules
    if [ -f "${ft710_dir}/78-et-ft710.rules" ]; then
      cp "${ft710_dir}/78-et-ft710.rules" "${udev_dir}/"
      chmod 644 "${udev_dir}/78-et-ft710.rules"
      print_success "FT-710 udev rules installed"
    fi

    # Patch udev-tester.sh
    if [ -f "${ft710_dir}/udev-tester.patch" ] && [ -f "${sbin_dir}/udev-tester.sh" ]; then
      if grep -q "test_yaesu_ft710" "${sbin_dir}/udev-tester.sh"; then
        print_warning "udev-tester.sh already patched for FT-710"
      else
        patch "${sbin_dir}/udev-tester.sh" < "${ft710_dir}/udev-tester.patch" && \
          print_success "udev-tester.sh patched for FT-710" || \
          print_warning "FT-710 udev-tester patch failed"
      fi
    fi

    # Patch et-audio
    if [ -f "${ft710_dir}/et-audio.patch" ] && [ -f "${ETC_BIN_DIR}/et-audio" ]; then
      if grep -q '"FT-710")' "${ETC_BIN_DIR}/et-audio"; then
        print_warning "et-audio already patched for FT-710"
      else
        patch "${ETC_BIN_DIR}/et-audio" < "${ft710_dir}/et-audio.patch" && \
          print_success "et-audio patched for FT-710" || \
          print_warning "FT-710 et-audio patch failed"
      fi
    fi
  fi

  # 3) Anytone 578 — build custom Hamlib, then install profile
  if [[ "${_radio[2]}" -eq 1 ]]; then
    print_header "Applying Anytone 578 Support"
    local at578_dir="${src}/radio-tools/anytone-578"

    # ── Build custom Hamlib ──
    print_info "Checking Hamlib build dependencies..."
    local hamlib_deps_missing=false
    for cmd in git make gcc automake autoconf libtool pkg-config; do
      if ! command -v "${cmd}" >/dev/null 2>&1; then
        hamlib_deps_missing=true
      fi
    done

    if [ "${hamlib_deps_missing}" = true ]; then
      print_info "Installing build dependencies..."
      apt-get update -qq
      apt-get install -y -qq git build-essential automake autoconf libtool pkg-config libusb-1.0-0-dev
    fi

    local hamlib_build="/tmp/hamlib-anytone-build"
    local hamlib_repo="https://github.com/CowboyPilot/Hamlib.git"

    print_info "Cloning custom Hamlib..."
    rm -rf "${hamlib_build}"
    git clone --depth 1 "${hamlib_repo}" "${hamlib_build}"

    print_info "Building Hamlib (this may take several minutes)..."
    cd "${hamlib_build}"
    ./bootstrap
    ./configure --prefix=/usr/local
    local nproc_val
    nproc_val=$(nproc 2>/dev/null || echo 2)
    make -j"${nproc_val}"
    make install
    ldconfig
    cd /

    if rigctl -l 2>/dev/null | grep -qi "anytone"; then
      print_success "Custom Hamlib installed — AnyTone driver verified"
    else
      print_warning "Hamlib installed but AnyTone driver not found in rigctl -l"
    fi

    rm -rf "${hamlib_build}"

    # ── Install Anytone 578 profile ──
    if [ -f "${at578_dir}/anytone-578.json" ]; then
      cp "${at578_dir}/anytone-578.json" "${radios_dir}/"
      chown root:et-data "${radios_dir}/anytone-578.json" 2>/dev/null || true
      chmod 644 "${radios_dir}/anytone-578.json"
      print_success "Anytone 578 radio config installed"
    fi

    mkdir -p "${audio_dir}"
    if [ -f "${at578_dir}/anytone-578.sh" ]; then
      cp "${at578_dir}/anytone-578.sh" "${audio_dir}/"
      chown root:et-data "${audio_dir}/anytone-578.sh" 2>/dev/null || true
      chmod 755 "${audio_dir}/anytone-578.sh"
      print_success "Anytone 578 audio script installed"
    fi

    # Patch udev-tester.sh
    if [ -f "${at578_dir}/udev-tester.patch" ] && [ -f "${sbin_dir}/udev-tester.sh" ]; then
      if grep -q '"anytone-578"' "${sbin_dir}/udev-tester.sh"; then
        print_warning "udev-tester.sh already patched for Anytone 578"
      else
        patch "${sbin_dir}/udev-tester.sh" < "${at578_dir}/udev-tester.patch" && \
          print_success "udev-tester.sh patched for Anytone 578" || \
          print_warning "Anytone 578 udev-tester patch failed"
      fi
    fi
  fi

  # 4) AIOC — install JSON, udev rules, direwolf configs, launcher
  if [[ "${_radio[3]}" -eq 1 ]]; then
    print_header "Applying AIOC Support"
    local aioc_dir="${src}/radio-tools/aioc"

    # Radio config
    if [ -f "${aioc_dir}/aioc.json" ]; then
      cp "${aioc_dir}/aioc.json" "${radios_dir}/"
      chown root:et-data "${radios_dir}/aioc.json" 2>/dev/null || true
      chmod 644 "${radios_dir}/aioc.json"
      print_success "AIOC radio config installed"
    fi

    # udev rules
    if [ -f "${aioc_dir}/93-aioc.rules" ]; then
      cp "${aioc_dir}/93-aioc.rules" "${udev_dir}/"
      chmod 644 "${udev_dir}/93-aioc.rules"
      print_success "AIOC udev rules installed"
    fi

    # DireWolf configs
    mkdir -p "${direwolf_dir}"
    for conf in direwolf.aioc-simple.conf direwolf.aioc-packet.conf direwolf.aioc-aprs.conf; do
      if [ -f "${aioc_dir}/${conf}" ]; then
        cp "${aioc_dir}/${conf}" "${direwolf_dir}/"
        chown root:et-data "${direwolf_dir}/${conf}" 2>/dev/null || true
        chmod 644 "${direwolf_dir}/${conf}"
        print_success "${conf} installed"
      fi
    done

    # Launcher script
    if [ -f "${aioc_dir}/aioc-direwolf" ]; then
      cp "${aioc_dir}/aioc-direwolf" "${ETC_BIN_DIR}/"
      chmod +x "${ETC_BIN_DIR}/aioc-direwolf"
      print_success "aioc-direwolf launcher installed"
    fi
  fi

  # ── Desktop Shortcuts ──

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
          # Mark trusted so GNOME skips "Allow Launching" for new users
          setfattr -n user.trusted -v true "${skel_desktop}/${df}.desktop" 2>/dev/null || true
          cp "${desktop_src}" "${apps_dir}/${df}.desktop"
          print_success "Desktop shortcut: ${df}"
        else
          print_warning "Desktop file not found: ${df}.desktop"
        fi
      fi
    done
  fi

  # ── Desktop icon placement: top-left via dconf system override ──
  local dconf_dir="/etc/dconf/db/local.d"
  mkdir -p "${dconf_dir}"
  cat > "${dconf_dir}/01-nozzlemods-desktop" <<'DCONF'
[org/gnome/shell/extensions/ding]
start-corner='top-left'
DCONF
  if command -v dconf >/dev/null 2>&1; then
    dconf update 2>/dev/null || true
  fi
  print_success "Desktop icons set to arrange from top-left"

  # ── XARA Enhancements ──
  patch_et_xara
  if command -v xara >/dev/null 2>&1 || [ -f "${ETC_BIN_DIR}/et-xara" ]; then
    install_xara_desktop_shortcut "/etc/skel/Desktop" "${src}/bin/xara-status.desktop" ""
    setup_xara_keying_dirs "/etc/skel/Desktop"
  fi

  echo
  print_header "Cubic ISO Build Complete"
  echo "Selected NozzleMods have been applied to the ISO filesystem."
  echo
  echo "Items installed to:"
  echo "  • nozzle-menu and helpers → ${ETC_BIN_DIR}/"
  echo "  • Radio configs/patches   → ${radios_dir}/"
  echo "  • NozzleMods scripts      → /etc/skel/NozzleMods/"
  echo "  • Desktop shortcuts       → /etc/skel/Desktop/"
  echo "  • App entries             → /usr/share/applications/"
  echo
  echo "New users created from this ISO will have NozzleMods ready to use."
  echo
  echo -e "${GREEN}73!${NC}"
  echo
}

################################################################################
# Shared: XARA Enhancements (used by both Cubic and live install)
################################################################################

patch_et_xara() {
  local et_xara="${ETC_BIN_DIR}/et-xara"
  if [ ! -f "${et_xara}" ]; then
    return 0
  fi
  print_info "Patching et-xara with keying directory and UI flags..."
  if grep -q -- '--ui-port' "${et_xara}"; then
    print_warning "et-xara already patched"
  else
    local use_sudo=""
    [ ! -w "${et_xara}" ] && use_sudo="sudo"
    ${use_sudo} sed -i 's|--ptt ${PTT}$|--ptt ${PTT} \\\n  --ui-port 8081 \\\n  --ui-addr 127.0.0.1 \\\n  --waveform auto \\\n  --hf-keying-dir="${HOME}/Desktop/xara/hf_keying" \\\n  --fm-keying-dir="${HOME}/Desktop/xara/fm_keying"|' "${et_xara}"
    if grep -q -- '--ui-port' "${et_xara}"; then
      print_success "et-xara patched"
    else
      print_warning "et-xara patch may not have applied — check manually"
    fi
  fi
}

install_xara_desktop_shortcut() {
  # $1 = desktop directory, $2 = source .desktop file, $3 = "sudo" or ""
  local desktop_dir="$1"
  local desktop_src="$2"
  local use_sudo="${3:-}"

  if [ ! -f "${desktop_src}" ]; then
    return 0
  fi

  mkdir -p "${desktop_dir}"
  ${use_sudo} cp "${desktop_src}" "${desktop_dir}/xara-status.desktop"
  ${use_sudo} chmod +x "${desktop_dir}/xara-status.desktop"

  # Mark as trusted so GNOME doesn't show "Allow Launching" prompt
  gio set "${desktop_dir}/xara-status.desktop" metadata::trusted true 2>/dev/null || \
    gio set "${desktop_dir}/xara-status.desktop" metadata::trusted yes 2>/dev/null || true
  setfattr -n user.trusted -v true "${desktop_dir}/xara-status.desktop" 2>/dev/null || true

  # Also install to applications menu
  ${use_sudo} cp "${desktop_src}" "/usr/share/applications/xara-status.desktop" 2>/dev/null || true

  print_success "Desktop shortcut: XARA Status"
}

setup_xara_keying_dirs() {
  # $1 = base desktop directory
  local desktop_dir="$1"
  mkdir -p "${desktop_dir}/xara/hf_keying" "${desktop_dir}/xara/fm_keying"
  print_success "Created xara keying directories"
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
    echo "  ./install-nozzlemod.sh"
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
  print_header "Fetching Repository"

  if command -v git >/dev/null 2>&1; then
    print_info "Cloning from ${REPO_URL}..."
    print_info "Branch: ${REPO_BRANCH}"
    if git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${TEMP_CLONE_DIR}"; then
      print_success "Repository cloned successfully"
      return 0
    else
      print_error "Failed to clone repository"
      return 1
    fi
  else
    # No git — download tarball (works in Cubic chroot)
    local tarball_url="https://github.com/CowboyPilot/EmcommTools-NozzleMods/archive/refs/heads/${REPO_BRANCH}.tar.gz"
    local tarball_path="/tmp/nozzlemods-archive.tar.gz"
    print_info "Downloading tarball (git not available)..."

    local dl_ok=false
    if command -v wget >/dev/null 2>&1; then
      wget -q -O "${tarball_path}" "${tarball_url}" && dl_ok=true
    elif command -v curl >/dev/null 2>&1; then
      curl -fSL -o "${tarball_path}" "${tarball_url}" && dl_ok=true
    else
      print_error "Neither git, wget, nor curl found"
      return 1
    fi

    if [[ "${dl_ok}" != true ]]; then
      print_error "Failed to download repository tarball"
      return 1
    fi

    mkdir -p "${TEMP_CLONE_DIR}"
    tar xzf "${tarball_path}" --strip-components=1 -C "${TEMP_CLONE_DIR}"
    rm -f "${tarball_path}"
    print_success "Repository downloaded and extracted"
    return 0
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
  if [ -f "${TEMP_CLONE_DIR}/install-nozzlemod.sh" ]; then
    print_info "Copying installer script..."
    cp "${TEMP_CLONE_DIR}/install-nozzlemod.sh" "${NOZZLE_DIR}/"
    chmod +x "${NOZZLE_DIR}/install-nozzlemod.sh"
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

  # XARA enhancements
  patch_et_xara
  if command -v xara >/dev/null 2>&1 || [ -f "${ETC_BIN_DIR}/et-xara" ]; then
    install_xara_desktop_shortcut "${desktop_dir}" "${NOZZLE_DIR}/bin/xara-status.desktop" ""
    setup_xara_keying_dirs "${desktop_dir}"
  fi
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
    # Check if ETC has already been installed (rigctl = hamlib = ETC ran)
    if ! command -v rigctl >/dev/null 2>&1; then
      cubic_bootstrap_etc
    fi
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
