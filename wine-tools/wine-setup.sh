#!/bin/bash
# wine-setup.sh
#
# Version: 1.3.0
#
# Installs into a dedicated 32-bit Wine prefix:
#   - Winlink Express
#   - VarAC (VARA Chat)  (if VarAC_Installer*.exe is present in ~/Downloads directory)
#   - VARA HF (auto-downloads if not found)
#   - VARA FM (auto-downloads if not found)
#
# Wine prefix used:
#   ~/.wine32
#
# GNOME menu entries placed under:
#   Applications → Ham Radio
#
# Rerunnable:
#   - If prefix exists → reused
#   - If Winlink present → skipped
#   - If VARA HF/FM present → skipped
#   - VarAC can be added later by rerunning the script
#

set -euo pipefail

VERSION="1.3.0"

PREFIX="${HOME}/.wine32"
WINLINK_ZIP_URL="https://downloads.winlink.org/User%20Programs/Winlink_Express_install_1-7-29-0.zip"
WINLINK_ZIP_FILE="Winlink_Express.zip"
USER_CONFIG="${HOME}/.config/emcomm-tools/user.json"
VARA_KEY_FILE="${HOME}/vara_key"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# VARA download settings
VARA_BASE_URL="https://downloads.winlink.org"
VARA_INDEX_URL="${VARA_BASE_URL}/VARA%20Products/"
VARA_HTML_FILE="${SCRIPT_DIR}/vara-index.html"

echo
echo "============================================================="
echo "   Installer: Winlink + VarAC + VARA HF/FM  v${VERSION}"
echo "             Wine prefix: ${PREFIX}"
echo "============================================================="
echo

if [[ "${EUID}" -eq 0 ]]; then
  echo "ERROR: Do NOT run this script as root."
  exit 1
fi

for cmd in wine wineboot winetricks wget unzip curl jq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command '${cmd}' is missing."
    echo "       Please install '${cmd}' and rerun."
    exit 1
  fi
done

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "ERROR: Must run from a graphical desktop session."
  exit 1
fi

# -------------------------------------------------------------
#   VARA Download Functions (integrated download logic)
# -------------------------------------------------------------

cleanup_vara_html() {
  [[ -f "${VARA_HTML_FILE}" ]] && rm -f "${VARA_HTML_FILE}"
}

trap cleanup_vara_html EXIT

# Download VARA installer using integrated download logic
download_vara_installer() {
  local pattern="$1"  # e.g. "VARA%20HF%20v" or "VARA%20FM%20v"
  local mode="$2"     # "HF" or "FM" for display purposes

  echo "[*] Attempting to download latest VARA ${mode} installer..." >&2
  echo "    Working directory: $(pwd)" >&2

  # 1. Fetch main VARA download page as HTML
  echo "    Fetching VARA product index: ${VARA_INDEX_URL}" >&2
  if ! curl -s -f -L -o "${VARA_HTML_FILE}" "${VARA_INDEX_URL}"; then
    echo "[!] Error fetching VARA index page: ${VARA_INDEX_URL}" >&2
    return 1
  fi

  # 2. Extract links matching the pattern (case-insensitive)
  local vara_file_path=""

  vara_file_path=$(
    grep -oi 'href="[^"]*'"${pattern}"'[^"]*"' "${VARA_HTML_FILE}" 2>/dev/null | \
      sed -E 's/^[Hh][Rr][Ee][Ff]="//; s/"$//' | \
      grep -i '\.zip$' | \
      head -n 1 || true
  )

  if [[ -z "${vara_file_path}" ]]; then
    echo "[!] Error: Could not find VARA ${mode} file matching pattern: ${pattern}" >&2
    echo "    First few hrefs from index (debug):" >&2
    grep -oi 'href="[^"]*"' "${VARA_HTML_FILE}" 2>/dev/null | head -n 10 >&2 || true
    return 1
  fi

  # 3. Construct full URL and download
  local full_url
  if [[ "${vara_file_path}" =~ ^https?:// ]]; then
    full_url="${vara_file_path}"
  else
    full_url="${VARA_BASE_URL%/}/${vara_file_path#/}"
  fi

  local zip_filename
  zip_filename="$(basename "${vara_file_path}")"

  echo "    Found path: ${vara_file_path}" >&2
  echo "    Downloading: ${full_url}" >&2
  echo "    Saving as: ${zip_filename}" >&2

  if ! curl -s -f -L -o "${zip_filename}" "${full_url}"; then
    echo "[!] Failed to download VARA ${mode} installer" >&2
    return 1
  fi

  echo "    Downloaded: ${zip_filename}" >&2

  # 4. Extract the ZIP file into current directory
  echo "    Extracting ${zip_filename}..." >&2
  if ! unzip -o "${zip_filename}" >/dev/null 2>&1; then
    echo "[!] Failed to extract ${zip_filename}" >&2
    return 1
  fi

  # 5. Find the extracted .exe (after download & extract)
  local exe_file=""
  if [[ "${mode}" == "HF" ]]; then
    exe_file=$(
      find . -maxdepth 1 -type f -name "*.exe" 2>/dev/null | \
        grep -i "vara" | \
        grep -iv "varac" | \
        grep -iv "fm" | \
        grep -iE "setup|install|^./VARA" | \
        head -n 1 || true
    )
  else
    exe_file=$(
      find . -maxdepth 1 -type f -name "*.exe" 2>/dev/null | \
        grep -i "vara" | \
        grep -i "fm" | \
        grep -iE "setup|install" | \
        head -n 1 || true
    )
  fi

  if [[ -z "${exe_file}" ]]; then
    echo "[!] No .exe installer found after extracting ${zip_filename}" >&2
    echo "    .exe files currently in directory:" >&2
    find . -maxdepth 1 -type f -name "*.exe" 2>/dev/null >&2 || true
    return 1
  fi

  exe_file="$(basename "${exe_file}")"
  local exe_path
  exe_path="$(realpath "${exe_file}")"

  echo "    Extracted installer: ${exe_file}" >&2
  echo "    Returning installer path: ${exe_path}" >&2

  # *** IMPORTANT: stdout is ONLY the path ***
  echo "${exe_path}"
  return 0
}


# -------------------------------------------------------------
#   Early Download: VARA HF and VARA FM
# -------------------------------------------------------------

echo
echo "============================================================="
echo "   Step 1: Checking for VARA Installers"
echo "============================================================="
echo

# Check for existing VARA HF installer
VARA_HF_INSTALLER=""
for f in "${SCRIPT_DIR}"/VARA*setup*.exe "${SCRIPT_DIR}"/VARA*.exe; do
  if [[ -f "$f" ]] && [[ ! "$f" =~ [Ff][Mm] ]] && [[ ! "$f" =~ [Vv]ar[Aa][Cc] ]]; then
    VARA_HF_INSTALLER="$f"
    echo "[*] Found existing VARA HF installer: $(basename "${VARA_HF_INSTALLER}")"
    break
  fi
done

# If not found, download it
if [[ -z "${VARA_HF_INSTALLER}" ]]; then
  echo "[*] VARA HF installer not found locally. Downloading..."
  if VARA_HF_INSTALLER=$(download_vara_installer "VARA%20HF%20v" "HF"); then
    echo "[✓] VARA HF installer ready: $(basename "${VARA_HF_INSTALLER}")"
  else
    echo "[!] Failed to download VARA HF installer"
    echo "    You can manually download from: https://rosmodem.wordpress.com/"
    echo "    Place VARA HF setup file in: ${SCRIPT_DIR}"
    VARA_HF_INSTALLER=""
  fi
fi

echo

# Check for existing VARA FM installer
VARA_FM_INSTALLER=""
for f in "${SCRIPT_DIR}"/VARA*FM*.exe "${SCRIPT_DIR}"/VaraFM*.exe; do
  if [[ -f "$f" ]]; then
    VARA_FM_INSTALLER="$f"
    echo "[*] Found existing VARA FM installer: $(basename "${VARA_FM_INSTALLER}")"
    break
  fi
done

# If not found, download it
if [[ -z "${VARA_FM_INSTALLER}" ]]; then
  echo "[*] VARA FM installer not found locally. Downloading..."
  if VARA_FM_INSTALLER=$(download_vara_installer "VARA%20FM%20v" "FM"); then
    echo "[✓] VARA FM installer ready: $(basename "${VARA_FM_INSTALLER}")"
  else
    echo "[!] Failed to download VARA FM installer"
    echo "    You can manually download from: https://rosmodem.wordpress.com/"
    echo "    Place VARA FM setup file in: ${SCRIPT_DIR}"
    VARA_FM_INSTALLER=""
  fi
fi

echo
echo "[*] VARA installer check complete"
echo

# -------------------------------------------------------------
#   Read user configuration from user.json
# -------------------------------------------------------------
echo "[*] Reading user configuration from ${USER_CONFIG}..."

if [[ ! -f "${USER_CONFIG}" ]]; then
  echo "ERROR: User configuration file not found: ${USER_CONFIG}"
  echo "       Please run 'et-user' first to configure your callsign and settings."
  exit 1
fi

# Read JSON values
USER_CALLSIGN=$(jq -r '.callsign // "N0CALL"' "${USER_CONFIG}")
USER_GRID=$(jq -r '.grid // "DM33"' "${USER_CONFIG}")
USER_WINLINK_PASSWD=$(jq -r '.winlinkPasswd // "NOPASS"' "${USER_CONFIG}")

# Check if user has configured their callsign
if [[ "${USER_CALLSIGN}" == "N0CALL" ]]; then
  echo
  echo "============================================================="
  echo "  ERROR: Default callsign detected (N0CALL)"
  echo "============================================================="
  echo "  Please run 'et-user' to configure your callsign, grid square,"
  echo "  and Winlink password before running this installer."
  echo
  exit 1
fi

echo "    Callsign: ${USER_CALLSIGN}"
echo "    Grid Square: ${USER_GRID}"
echo "    Winlink Password: [configured]"

# -------------------------------------------------------------
#   Read or prompt for VARA registration key
# -------------------------------------------------------------
VARA_REG_KEY=""

if [[ -f "${VARA_KEY_FILE}" ]]; then
  echo "[*] Reading VARA registration key from ${VARA_KEY_FILE}..."
  VARA_REG_KEY=$(cat "${VARA_KEY_FILE}" | tr -d '[:space:]')
  echo "    VARA Key: [found]"
else
  echo
  echo "============================================================="
  echo "  VARA Registration Key"
  echo "============================================================="
  echo "  VARA HF and VARA FM require a registration key for full"
  echo "  functionality. You can run in trial mode or enter your key now."
  echo
  echo "  To purchase a key, visit:"
  echo "    https://rosmodem.wordpress.com/"
  echo
  read -r -p "Enter your VARA registration key (or press Enter to skip): " VARA_REG_KEY
  
  if [[ -n "${VARA_REG_KEY}" ]]; then
    # Remove any whitespace
    VARA_REG_KEY=$(echo "${VARA_REG_KEY}" | tr -d '[:space:]')
    echo "${VARA_REG_KEY}" > "${VARA_KEY_FILE}"
    echo "[*] VARA registration key saved to ${VARA_KEY_FILE}"
  else
    echo "[*] Continuing without VARA registration key (trial mode)"
  fi
fi

# -------------------------------------------------------------
#   Helpers to patch shell env files for WINEARCH=win32 + ~/.wine32
# -------------------------------------------------------------
patch_shell_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  echo "  - Patching $f"

  # Backup first
  cp "$f" "${f}.bak_etwine_$(date +%s)" 2>/dev/null || true

  # Normalize WINEARCH win64 -> win32 in common forms
  sed -i -E 's/export[[:space:]]+WINEARCH="win64"/export WINEARCH="win32"/' "$f"
  sed -i -E 's/export[[:space:]]+WINEARCH=win64/export WINEARCH=win32/' "$f"
  sed -i -E 's/WINEARCH="win64"/WINEARCH="win32"/' "$f"
  sed -i -E 's/WINEARCH=win64/WINEARCH=win32/' "$f"

  # If anyone hardcoded .wine, bump it to .wine32
  sed -i -E 's|\$HOME/\.wine"|$HOME/.wine32"|' "$f" || true
  sed -i -E 's|\$HOME/\.wine\b|$HOME/.wine32|' "$f" || true
}

patch_common_checks() {
  local f="/opt/emcomm-tools/bin/common_checks.sh"
  [[ -f "$f" ]] || return 0

  echo "  - Patching $f"
  cp "$f" "${f}.bak_etwine_$(date +%s)" 2>/dev/null || true

  sed -i -E \
    -e 's/export[[:space:]]+WINEARCH="win64"/export WINEARCH="win32"/g' \
    -e 's/export[[:space:]]+WINEARCH=win64/export WINEARCH=win32/g' \
    -e 's/WINEARCH="win64"/WINEARCH="win32"/g' \
    -e 's/WINEARCH=win64/WINEARCH=win32/g' \
    -e 's/\.wine\b/.wine32/g' \
    "$f"
}

# -------------------------------------------------------------
#   Gate on current WINEARCH
# -------------------------------------------------------------
CURRENT_WA="${WINEARCH:-}"

if [[ "${CURRENT_WA}" != "win32" ]]; then
  echo
  echo "-------------------------------------------------------------"
  echo "  WINEARCH IS NOT SET TO win32 IN THIS SESSION"
  echo "-------------------------------------------------------------"
  echo "  Detected WINEARCH: '${CURRENT_WA:-<unset>}'"
  echo
  echo "  To safely use a 32-bit prefix at ~/.wine32, we need to:"
  echo "    - Update your shell init files to use WINEARCH=\"win32\""
  echo "    - Update EmComm Tools common_checks.sh to use .wine32"
  echo

  echo "[*] Patching shell init files for 32-bit Wine + ~/.wine32 ..."
  patch_shell_env_file "${HOME}/.bash_profile"
  patch_shell_env_file "${HOME}/.bashrc"
  patch_shell_env_file "${HOME}/.profile"

  echo "[*] Patching EmComm Tools common_checks.sh if present ..."
  patch_common_checks

  echo
  echo "============================================================="
  echo "  ENVIRONMENT UPDATED FOR 32-BIT WINE (~/.wine32)"
  echo "============================================================="
  echo "Next steps:"
  echo "  1) Log out of your desktop session (or SSH session) completely."
  echo "  2) Log back in, so the new WINEARCH=win32 takes effect."
  echo "  3) Re-run this installer:"
  echo "       ${SCRIPT_DIR}/wine-setup.sh"
  echo
  echo "After your next login, 'echo \$WINEARCH' should output: win32"
  echo "Only then will this script continue with installation."
  echo
  exit 0
fi

# If we get here, WINEARCH is already win32 for this shell
export WINEARCH="win32"
export WINEPREFIX="${PREFIX}"

echo
echo "[*] WINEARCH is '${WINEARCH}', proceeding with installation."
echo "    WINEPREFIX = ${WINEPREFIX}"

# -------------------------------------------------------------
#   CLEAN UP OLD / AUTO-GENERATED SHORTCUTS
# -------------------------------------------------------------
echo
echo "[*] Cleaning stale Wine application shortcuts..."
rm -rf "${HOME}/.local/share/applications/wine" 2>/dev/null || true
rm -f "${HOME}"/.local/share/applications/*Winlink*.desktop 2>/dev/null || true
rm -f "${HOME}"/.local/share/applications/*RMS*Express*.desktop 2>/dev/null || true
rm -f "${HOME}"/.local/share/applications/*VarAC*.desktop 2>/dev/null || true
update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
xdg-desktop-menu forceupdate 2>/dev/null || true
echo "[*] Old Wine shortcuts removed."

# -------------------------------------------------------------
#   Helper functions (installers, wrappers, pdh.dll, etc.)
# -------------------------------------------------------------

find_varac_installer() {
  local dirs=("${SCRIPT_DIR}" "${HOME}/Downloads")
  for dir in "${dirs[@]}"; do
    local files
    # Look specifically for VarAC installer (not VARA)
    files=$(ls -1 "${dir}"/VarAC_Installer*.exe 2>/dev/null | sort -r || true)
    if [[ -n "${files}" ]]; then
      echo "${files}" | head -n 1
      return 0
    fi
  done
  return 1
}

# Helper: create vara.cmd wrapper next to modem EXE
create_vara_wrapper_cmd() {
  local exe_path="$1"   # full Unix path to VARA.exe / VaraFM.exe
  local mode="$2"       # "HF" or "FM"

  [[ -f "${exe_path}" ]] || return 0

  local exe_dir exe_base cmd_path win_cd_path
  exe_dir="$(dirname "${exe_path}")"
  exe_base="$(basename "${exe_path}")"

  cmd_path="${exe_dir}/vara.cmd"

  # Windows path for cd /d line (convert PREFIX/drive_c/... → C:\...)
  local rel="${exe_dir#${PREFIX}/drive_c/}"
  rel="${rel//\//\\}"
  win_cd_path="C:\\${rel}"

  cat > "${cmd_path}" <<EOF
@echo off
cd /d "${win_cd_path}"
start "" "${exe_base}"
EOF

  echo "[*] Created VARA ${mode} wrapper: ${cmd_path}"
}

# Helper: convert absolute Unix path under drive_c to Windows path
to_windows_path() {
  local abs="$1"
  local rel="${abs#${PREFIX}/drive_c/}"
  rel="${rel//\//\\\\}"
  echo "C:\\\\${rel}"
}

# Helper: fix pdh.dll requirement by pulling nt4pdhdll.exe into VARA dir
fix_pdh_dll_for_vara_dir() {
  local vara_dir="$1"

  [[ -d "${vara_dir}" ]] || return 0

  if [[ ! -e "${vara_dir}/nt4pdhdll.exe" ]]; then
    echo "[*] VARA directory '${vara_dir}' missing nt4pdhdll.exe, installing pdh.dll bundle..."
    local CWD
    CWD="$(pwd)"
    cd "${vara_dir}"
    curl -s -f -L -O \
      "http://download.microsoft.com/download/winntsrv40/update/5.0.2195.2668/nt4/en-us/nt4pdhdll.exe" && \
      unzip -o nt4pdhdll.exe >/dev/null 2>&1 || {
        echo "[!] Failed to download or unzip nt4pdhdll.exe in ${vara_dir}"
      }
    cd "${CWD}"
  else
    echo "[*] nt4pdhdll.exe already present in '${vara_dir}', skipping pdh.dll fix."
  fi
}

# Helper: generate VARA HF INI file
generate_vara_hf_ini() {
  local vara_dir="$1"
  local ini_file="${vara_dir}/VARA.ini"
  
  echo "[*] Generating VARA HF configuration: ${ini_file}"
  
  cat > "${ini_file}" <<EOF
[Monitor]
Monitor Mode=0
[Setup]
Enable KISS=1
TCP Command Port=8300
KISS Port=8100
Registration Code=$(if [[ -n "${VARA_REG_KEY}" ]]; then echo "${VARA_REG_KEY}"; else echo ""; fi)
Registration Code 1=
Registration Code 2=
Registration Code 3=
Callsign Licence 0=${USER_CALLSIGN}
Callsign Licence 1=
Callsign Licence 2=
Callsign Licence 3=
WaterFall=1
Retries=5
View=1
CW ID=0
RA-Board PTT=0
Compatibility=0
Updates=1
ATU=0
Encryption=0
Password encryption=
[Soundcard]
Input Device Name=USB Audio CODEC
Output Device Name=USB Audio CODEC
ALC Drive Level=-10
RA-Board Device Path=
Channel=0
[PTT]
Rig=52
PTTPort=COM10
CATPort=COM10
Baud=19200
Pin=1
RTS=0
DTR=0
Via=3
Icom Address=
[Log]
Log Caption=Log*
Enable SysLog=0
SysLog Host=localhost
SysLog UDP Port=514
CommandsLog=0
SysLog Station Name=
[Position]
Top Position=3720
Left Position=9405
EOF
}

# Helper: generate VARA FM INI file
generate_vara_fm_ini() {
  local vara_dir="$1"
  local ini_file="${vara_dir}/VARAFM.ini"
  
  echo "[*] Generating VARA FM configuration: ${ini_file}"
  
  cat > "${ini_file}" <<EOF
[Monitor]
Monitor Mode=0
[Setup]
Enable KISS=1
TCP Command Port=8300
KISS Port=8100
Registration Code=$(if [[ -n "${VARA_REG_KEY}" ]]; then echo "${VARA_REG_KEY}"; else echo ""; fi)
Registration Code 1=
Registration Code 2=
Registration Code 3=
Callsign Licence 0=${USER_CALLSIGN}
Callsign Licence 1=
Callsign Licence 2=
Callsign Licence 3=
WaterFall=1
Retries=5
View=1
CW ID=0
RA-Board PTT=0
Compatibility=0
Updates=1
ATU=0
Encryption=0
Password encryption=
[Soundcard]
Input Device Name=USB Audio CODEC
Output Device Name=USB Audio CODEC
ALC Drive Level=-10
RA-Board Device Path=
Channel=0
[PTT]
Rig=52
PTTPort=COM10
CATPort=COM10
Baud=19200
Pin=1
RTS=0
DTR=0
Via=3
Icom Address=
[Log]
Log Caption=Log*
Enable SysLog=0
SysLog Host=localhost
SysLog UDP Port=514
CommandsLog=0
SysLog Station Name=
[Position]
Top Position=3720
Left Position=9405
EOF
}

# -------------------------------------------------------------
#   Step 1: Create or reuse Wine prefix (~/.wine32)
# -------------------------------------------------------------
NEW_PREFIX=0

if [[ -d "${PREFIX}" ]]; then
  echo "[*] Reusing existing prefix: ${PREFIX}"
  if ! grep -q "#arch=win32" "${PREFIX}/system.reg" 2>/dev/null; then
    echo "ERROR: Existing prefix is NOT 32-bit (missing #arch=win32)."
    echo "       Please remove '${PREFIX}' or migrate data manually, then rerun."
    exit 1
  fi
else
  NEW_PREFIX=1
  echo "[*] Creating NEW 32-bit Wine prefix at ${PREFIX}..."
  WINEARCH=win32 WINEPREFIX="${PREFIX}" wineboot -u
  sleep 2
  WINEARCH=win32 WINEPREFIX="${PREFIX}" wineboot -u
  unset WINEARCH
fi

# -------------------------------------------------------------
#   Step 2: Install dependencies for new prefix
# -------------------------------------------------------------
if [[ "${NEW_PREFIX}" -eq 1 ]]; then
  echo
  echo "[*] Installing Wine dependencies via winetricks..."
  echo "    winxp, sound=alsa, dotnet35sp1, vb6run,"
  echo "    vcrun2015, dotnet40, dotnet46, corefonts,"
  echo "    tahoma, gdiplus, msxml6"
  echo

  DEPS=(winxp sound=alsa dotnet35sp1 vb6run vcrun2015 dotnet40 dotnet46 corefonts tahoma gdiplus msxml6)

  # Pre-fetch VB6 runtime from Microsoft — winetricks mirrors are unreliable
  VB6_CACHE="${HOME}/.cache/winetricks/vb6run"
  VB6_FILE="${VB6_CACHE}/VB6.0-KB290887-X86.exe"
  if [[ ! -f "${VB6_FILE}" ]]; then
    echo "  -> Pre-fetching VB6 runtime (winetricks mirror workaround)..."
    mkdir -p "${VB6_CACHE}"
    curl -L -o "${VB6_FILE}" \
      "https://download.microsoft.com/download/5/a/d/5ad868a0-8ecd-4bb0-a882-fe53eb7ef348/VB6.0-KB290887-X86.exe" \
      2>/dev/null || echo "WARNING: VB6 pre-fetch failed. winetricks will attempt its own download."
  fi

  for dep in "${DEPS[@]}"; do
    echo "  -> winetricks ${dep}"
    set +e
    env -u WINEARCH WINEPREFIX="${PREFIX}" winetricks -q ${dep}
    STATUS=$?
    set -e
    if [[ ${STATUS} -ne 0 ]]; then
      echo "WARNING: winetricks ${dep} returned ${STATUS}. Continuing..."
    fi
  done

  echo
  echo "[*] Disabling Windows spooler service in prefix to avoid print crashes..."
  env -u WINEARCH WINEPREFIX="${PREFIX}" wine reg add \
    "HKLM\\System\\CurrentControlSet\\Services\\Spooler" \
    /v Start /t REG_DWORD /d 4 /f >/dev/null 2>&1 || true
fi

# -------------------------------------------------------------
#   Step 3: Install Winlink Express
# -------------------------------------------------------------
WINLINK_PATH_ON_DISK=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "RMS Express.exe" | head -n 1 || true)

if [[ -n "${WINLINK_PATH_ON_DISK}" ]]; then
  echo
  echo "[*] Winlink Express already installed at:"
  echo "    ${WINLINK_PATH_ON_DISK}"
else
  echo
  echo "============================================================="
  echo "                 Installing Winlink Express"
  echo "============================================================="

  if [[ ! -f "${WINLINK_ZIP_FILE}" ]]; then
    echo "[*] Downloading Winlink Express ZIP..."
    wget -O "${WINLINK_ZIP_FILE}" "${WINLINK_ZIP_URL}"
  else
    echo "[*] Using existing ${WINLINK_ZIP_FILE}"
  fi

  echo "[*] Extracting ${WINLINK_ZIP_FILE}..."
  unzip -o "${WINLINK_ZIP_FILE}"

  WINLINK_INSTALLER=""
  for f in Winlink_Express_install*.exe RMS_Express_install*.exe; do
    if [[ -f "$f" ]]; then
      WINLINK_INSTALLER="$f"
      break
    fi
  done

  if [[ -z "${WINLINK_INSTALLER}" ]]; then
    echo "ERROR: No Winlink Express installer found in current directory."
    echo "       Expected names like Winlink_Express_install_*.exe"
    exit 1
  fi

  echo "[*] Running Winlink Express installer: ${WINLINK_INSTALLER}"
  env -u WINEARCH WINEPREFIX="${PREFIX}" wine "${WINLINK_INSTALLER}"

  WINLINK_PATH_ON_DISK=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "RMS Express.exe" | head -n 1 || true)
  if [[ -z "${WINLINK_PATH_ON_DISK}" ]]; then
    echo "WARNING: Winlink installer ran but RMS Express.exe not found."
  else
    echo "[*] Winlink Express installed at:"
    echo "    ${WINLINK_PATH_ON_DISK}"
  fi
fi

# -------------------------------------------------------------
#   Step 4: Install VarAC
# -------------------------------------------------------------
VARAC_PATH_ON_DISK=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "VarAC.exe" | head -n 1 || true)

if [[ -n "${VARAC_PATH_ON_DISK}" ]]; then
  echo
  echo "[*] VarAC already installed at:"
  echo "    ${VARAC_PATH_ON_DISK}"
else
  echo
  echo "============================================================="
  echo "                 Checking for VarAC installer"
  echo "============================================================="

  VARAC_INSTALLER=""
  if VARAC_INSTALLER=$(find_varac_installer); then
    echo "[*] Found VarAC installer:"
    echo "    ${VARAC_INSTALLER}"
    echo "[*] Running VarAC installer..."
    env -u WINEARCH WINEPREFIX="${PREFIX}" wine "${VARAC_INSTALLER}"
    VARAC_PATH_ON_DISK=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "VarAC.exe" | head -n 1 || true)
    echo "[*] VarAC installation finished."
  else
    echo "[!] VarAC installer NOT found."
    echo "    Download the WINDOWS installer from:"
    echo "      https://www.varac-hamradio.com/download"
    echo "    Save it as VarAC_Installer_*.exe in:"
    echo "      - ${SCRIPT_DIR}"
    echo "      - or ${HOME}/Downloads"
    echo
    read -r -p "Continue WITHOUT installing VarAC? (y/N) " ANS
    ANS=${ANS:-N}
    if [[ ! "${ANS}" =~ ^[Yy]$ ]]; then
      echo "Please download VarAC_Installer_*.exe and rerun this script."
      exit 1
    else
      echo "[*] Skipping VarAC installation."
    fi
  fi
fi

# -------------------------------------------------------------
#   Step 5: Install VARA HF / VARA FM + pdh.dll fix
# -------------------------------------------------------------
echo
echo "============================================================="
echo "                 Installing VARA HF / VARA FM"
echo "============================================================="

VARA_HF_EXE=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "VARA.exe" | head -n 1 || true)
VARA_FM_EXE=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "VaraFM.exe" | head -n 1 || true)

# --- VARA HF ---
if [[ -n "${VARA_HF_EXE}" ]]; then
  echo "[*] VARA HF already installed at:"
  echo "    ${VARA_HF_EXE}"
else
  if [[ -n "${VARA_HF_INSTALLER}" && -f "${VARA_HF_INSTALLER}" ]]; then
    echo "[*] Running VARA HF installer: ${VARA_HF_INSTALLER}"
    env -u WINEARCH WINEPREFIX="${PREFIX}" wine "${VARA_HF_INSTALLER}"
    VARA_HF_EXE=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "VARA.exe" | head -n 1 || true)
    if [[ -n "${VARA_HF_EXE}" ]]; then
      echo "[*] VARA HF installed at:"
      echo "    ${VARA_HF_EXE}"
      
      # Generate VARA HF INI file
      VARA_HF_DIR="$(dirname "${VARA_HF_EXE}")"
      generate_vara_hf_ini "${VARA_HF_DIR}"
    else
      echo "WARNING: VARA HF installer ran but VARA.exe not found."
    fi
  else
    echo "[!] VARA HF installer not available"
    echo "    Download manually from: https://rosmodem.wordpress.com/"
  fi
fi

# --- VARA FM ---
if [[ -n "${VARA_FM_EXE}" ]]; then
  echo "[*] VARA FM already installed at:"
  echo "    ${VARA_FM_EXE}"
else
  if [[ -n "${VARA_FM_INSTALLER}" && -f "${VARA_FM_INSTALLER}" ]]; then
    echo "[*] Running VARA FM installer: ${VARA_FM_INSTALLER}"
    env -u WINEARCH WINEPREFIX="${PREFIX}" wine "${VARA_FM_INSTALLER}"
    VARA_FM_EXE=$(find "${PREFIX}/drive_c" -maxdepth 6 -iname "VaraFM.exe" | head -n 1 || true)
    if [[ -n "${VARA_FM_EXE}" ]]; then
      echo "[*] VARA FM installed at:"
      echo "    ${VARA_FM_EXE}"
      
      # Generate VARA FM INI file
      VARA_FM_DIR="$(dirname "${VARA_FM_EXE}")"
      generate_vara_fm_ini "${VARA_FM_DIR}"
    else
      echo "WARNING: VARA FM installer ran but VaraFM.exe not found."
    fi
  else
    echo "[!] VARA FM installer not available"
    echo "    Download manually from: https://rosmodem.wordpress.com/"
  fi
fi

# Create vara.cmd wrappers if EXEs were found
if [[ -n "${VARA_HF_EXE}" ]]; then
  create_vara_wrapper_cmd "${VARA_HF_EXE}" "HF"
fi
if [[ -n "${VARA_FM_EXE}" ]]; then
  create_vara_wrapper_cmd "${VARA_FM_EXE}" "FM"
fi

# Apply pdh.dll fix (nt4pdhdll.exe) to both VARA dirs if present
if [[ -n "${VARA_HF_EXE}" ]]; then
  fix_pdh_dll_for_vara_dir "$(dirname "${VARA_HF_EXE}")"
fi
if [[ -n "${VARA_FM_EXE}" ]]; then
  fix_pdh_dll_for_vara_dir "$(dirname "${VARA_FM_EXE}")"
fi

# -------------------------------------------------------------
#   Step 6: Wine graphics / font / focus tweaks
# -------------------------------------------------------------
echo
echo "============================================================="
echo "           Applying Wine graphics / font / focus tweaks"
echo "============================================================="

cat > /tmp/vara_fix.reg << 'EOF'
[HKEY_CURRENT_USER\Software\Wine\X11 Driver]
"ClientSideGraphics"="N"
"ClientSideWithRender"="N"
"UseXIM"="N"

[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"renderer"="gdi"
"MaxVersionGL"=dword:00030002

; Try to reduce focus stealing / flashing by matching a conservative Windows desktop config
[HKEY_CURRENT_USER\Control Panel\Desktop]
"ForegroundLockTimeout"=dword:00030d40
"ForegroundFlashCount"=dword:00000001
"MenuShowDelay"="400"
EOF

env -u WINEARCH WINEPREFIX="${PREFIX}" wine regedit /tmp/vara_fix.reg >/dev/null 2>&1 || true
rm -f /tmp/vara_fix.reg

# Disable winemenubuilder to avoid random menu entries / interference
env -u WINEARCH WINEPREFIX="${PREFIX}" wine reg add \
  "HKCU\\Software\\Wine" \
  /v "EnableMenuBuilder" /t REG_SZ /d "N" /f >/dev/null 2>&1 || true

echo "[*] Wine tweaks applied."

# -------------------------------------------------------------
#   Step 7: COM10 → /dev/et-cat
# -------------------------------------------------------------
echo
echo "============================================================="
echo "              Mapping COM10 → /dev/et-cat"
echo "============================================================="

mkdir -p "${PREFIX}/dosdevices"
ln -sf "/dev/et-cat" "${PREFIX}/dosdevices/com10" 2>/dev/null || true

env -u WINEARCH WINEPREFIX="${PREFIX}" wine reg add \
  "HKLM\\Software\\Wine\\Ports" \
  /v COM10 /t REG_SZ /d "/dev/et-cat" /f >/dev/null 2>&1 || true

echo "[*] COM10 mapped to /dev/et-cat (symlink + registry)."

# -------------------------------------------------------------
#   Step 8: GNOME launchers (Winlink + VarAC only)
# -------------------------------------------------------------
echo
echo "============================================================="
echo "               Creating GNOME Ham Radio Launchers"
echo "============================================================="

APP_DIR_TOP="${HOME}/.local/share/applications"
mkdir -p "${APP_DIR_TOP}"

# Helper: grab Icon= from a Wine-generated .desktop if possible
get_wine_icon() {
  local pattern="$1"
  local wine_apps="${HOME}/.local/share/applications/wine"
  local src
  src=$(find "${wine_apps}" -type f -iname "${pattern}" 2>/dev/null | head -n 1 || true)
  if [[ -n "${src}" ]]; then
    local icon_line
    icon_line=$(grep '^Icon=' "${src}" 2>/dev/null || true)
    if [[ -n "${icon_line}" ]]; then
      echo "${icon_line#Icon=}"
      return 0
    fi
  fi
  echo "wine"
}

# ---- Winlink Express ----
WINLINK_EXE="${WINLINK_PATH_ON_DISK:-$(find "${PREFIX}/drive_c" -maxdepth 6 -iname 'RMS Express.exe' | head -n 1 || true)}"
WINLINK_DIR="${PREFIX}/drive_c"
WINLINK_WIN="C:\\\\RMS Express\\\\RMS Express.exe"

if [[ -n "${WINLINK_EXE}" ]]; then
  WINLINK_DIR="$(dirname "${WINLINK_EXE}")"
  WINLINK_WIN="$(to_windows_path "${WINLINK_EXE}")"
fi

WINLINK_ICON=$(get_wine_icon "*Winlink*Express*.desktop")
cat > "${APP_DIR_TOP}/winlink-express-wle.desktop" <<EOF
[Desktop Entry]
Name=Winlink Express (WLE)
Exec=env -u WINEARCH WINEPREFIX="${PREFIX}" wine-stable "${WINLINK_WIN}"
Type=Application
StartupNotify=true
Path=${WINLINK_DIR}
Icon=${WINLINK_ICON}
Categories=Network;HamRadio;Application;
EOF

# ---- VarAC (only if installed) ----
VARAC_EXE="${VARAC_PATH_ON_DISK:-$(find "${PREFIX}/drive_c" -maxdepth 6 -iname 'VarAC.exe' | head -n 1 || true)}"
if [[ -n "${VARAC_EXE}" ]]; then
  VARAC_DIR="$(dirname "${VARAC_EXE}")"
  VARAC_WIN="$(to_windows_path "${VARAC_EXE}")"
  VARAC_ICON=$(get_wine_icon "VarAC*.desktop")
  cat > "${APP_DIR_TOP}/varac.desktop" <<EOF
[Desktop Entry]
Name=VarAC (Chat)
Exec=env -u WINEARCH WINEPREFIX="${PREFIX}" wine-stable "${VARAC_WIN}"
Type=Application
StartupNotify=true
Path=${VARAC_DIR}
Icon=${VARAC_ICON}
Categories=Network;HamRadio;Application;
EOF
fi

# Fallback: if wine-stable isn't present, use wine
if ! command -v wine-stable >/dev/null 2>&1; then
  sed -i 's/wine-stable/wine/' \
    "${APP_DIR_TOP}/winlink-express-wle.desktop" 2>/dev/null || true
  if [[ -f "${APP_DIR_TOP}/varac.desktop" ]]; then
    sed -i 's/wine-stable/wine/' "${APP_DIR_TOP}/varac.desktop" 2>/dev/null || true
  fi
fi

update-desktop-database "${APP_DIR_TOP}" 2>/dev/null || true
xdg-desktop-menu forceupdate 2>/dev/null || true

echo
echo "============================================================="
echo "   Winlink + VarAC + VARA HF/FM  v${VERSION}"
echo "              Installation COMPLETE"
echo "============================================================="
echo "Launchers should appear under:  Applications → Ham Radio"
echo
echo "Wine prefix: ${PREFIX}"
echo
echo "Configuration summary:"
echo "  Callsign: ${USER_CALLSIGN}"
echo "  Grid Square: ${USER_GRID}"
echo "  Winlink Password: [configured]"
if [[ -n "${VARA_REG_KEY}" ]]; then
  echo "  VARA Registration: [configured]"
else
  echo "  VARA Registration: [trial mode]"
fi
echo
echo "VARA HF/FM Executables:"
[[ -n "${VARA_HF_EXE}" ]] && echo "  HF: ${VARA_HF_EXE}"
[[ -n "${VARA_FM_EXE}" ]] && echo "  FM: ${VARA_FM_EXE}"
echo
echo "IMPORTANT - NEXT STEPS:"
echo "  1) DO NOT launch programs directly from the menu yet!"
echo "  2) Run 'nozzle-menu' to properly configure and launch your programs"
echo "  3) nozzle-menu will:"
echo "     - Allocate free ports automatically"
echo "     - Configure Winlink, VarAC, and VARA with correct settings"
echo "     - Launch programs in the correct order"
echo
echo "NOTES:"
echo "  - Initial .ini files created with your callsign and COM10 port"
echo "  - nozzle-menu will update ports and audio settings on each run"
echo "  - All programs share the 32-bit Wine prefix: ~/.wine32"
echo "  - pdh.dll has been installed to avoid missing DLL errors"
echo
