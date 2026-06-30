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
MERCURY_INI="${HOME}/mercury.ini"

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
for pkg in build-essential pkg-config libasound2-dev libpulse-dev make git; do
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
        sudo apt-get install -y build-essential pkg-config libasound2-dev libpulse-dev make git
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

# Build with internal Hamlib disabled via command-line override.
# The Makefile auto-detects Hamlib via pkg-config, so patching the file
# is not enough — a make variable override takes precedence over all
# Makefile assignments.
echo ""
echo -e "${BLUE}Building Mercury with HAVE_HAMLIB=0 (this may take a few minutes)...${NC}"
echo ""

NPROC=$(nproc 2>/dev/null || echo 2)
make -j"${NPROC}" HAVE_HAMLIB=0
echo ""
echo -e "${GREEN}✓ Build complete${NC}"

# Install
echo ""
echo "Installing..."
sudo make install HAVE_HAMLIB=0
echo -e "${GREEN}✓ Installation complete${NC}"

# Install mercury.ini
echo ""
if [ -f "${MERCURY_INI}" ]; then
    echo -e "${YELLOW}mercury.ini already exists at ${MERCURY_INI}${NC}"
    read -p "Overwrite with default configuration? (y/N): " overwrite_ini
    if [[ "${overwrite_ini}" =~ ^[Yy]$ ]]; then
        cp "${MERCURY_INI}" "${MERCURY_INI}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${GREEN}✓ Existing mercury.ini backed up${NC}"
    else
        echo -e "${YELLOW}⚠ Keeping existing mercury.ini${NC}"
        SKIP_INI=1
    fi
fi

if [ -z "${SKIP_INI:-}" ]; then
    echo "Installing mercury.ini to ${MERCURY_INI}..."
    cat > "${MERCURY_INI}" <<'INIEOF'
;
; Mercury init configuration file
;
; Values defined here are loaded at startup and act as defaults.
; Any setting can be overridden from the command line (CLI takes priority).
;
; Run mercury with -K to list supported HAMLIB radio models.
; Run mercury with -z to list available sound devices.
;

[main]

; Enable UI communication (WebSocket server for mercury-qt)
; true / false (default: false)
ui_enabled = true

; UI WebSocket port (default: 10000)
ui_port = 10000

; WebSocket protocol: ws (plain) or wss (TLS) (default: ws)
ui_protocol = ws

; Enable waterfall / spectrum data sent to the UI (default: true)
waterfall_enabled = true

; HAMLIB radio model ID. Use -1 for none, 0 for HERMES SHM, or a
; positive integer for a HAMLIB model (run mercury -K to see the list).
; (default: -1)
radio_model = -1

; HAMLIB radio device file or ip:port address
; Examples: /dev/ttyUSB0 (Linux), COM3 (Windows), 127.0.0.1:4532 (rigctld)
radio_device = 127.0.0.1:4532

; Serial baud rate for HAMLIB radio (0 = use hamlib default for the model).
; Must match the CAT Rate configured on your radio.
; Common values: 4800, 9600, 19200, 38400, 115200
radio_serial_speed = 115200

; Audio capture (input) device id (e.g. "plughw:0,0")
; Run mercury -z to list available devices.
input_device = plughw:0,0

; Audio playback (output) device id (e.g. "plughw:0,0")
; Run mercury -z to list available devices.
output_device = plughw:0,0

; Capture input channel: left, right, or stereo (default: left)
capture_channel = left

; Sound system / IO API: auto, alsa, pulse, dsound, wasapi, oss, coreaudio, aaudio, shm, null, fifo
; (default: auto — alsa on Linux, dsound on Windows)
; null is a developer/test backend: RX silence, TX discarded.
; fifo is a developer/test backend: raw s32le PCM at 8 kHz via input_device/output_device.
sound_system = auto

; ARQ TCP base port (control = base_port, data = base_port + 1)
; (default: 8300)
arq_tcp_base_port = 8300

; Broadcast TCP port (default: 8100)
broadcast_tcp_port = 8100

; Verbose mode (default: false)
verbose = false

; FreeDV modem verbosity level, 0 to 3 (default: 0)
freedv_verbosity = 0

; Hamlib radio log level, 0 to 6 (default: 0)
; 0=NONE, 1=BUG, 2=ERR, 3=WARN, 4=VERBOSE, 5=TRACE, 6=CACHE
hamlib_log_level = 0

[audio]

; TX audio gain in dB applied to modulator output samples (default: 0.0).
; 0.0 dB = no change.  Use this to set Mercury's TX level independently
; of the host audio mixer, so other modems sharing the radio aren't
; disturbed when you tune Mercury's drive.  Saturation is applied at the
; int32 PCM ceiling so any value clips cleanly.
; Range: -20.0 .. +20.0 (values outside are clamped).
tx_gain_db = 0.0

[arq]

; ARQ link no-progress disconnect budget (seconds, default: 180).
; When data-retry slots exhaust on a frame, Mercury no longer disconnects
; immediately — it resets the retry counter and forces a payload-mode
; downgrade.  The link only drops when wall-clock since the last ACK that
; advanced the sequence number exceeds this budget, OR when the keepalive
; miss limit is reached (5 * 20s = 100s by default).  180s sits just above
; the keepalive timeout as a safety net for the asymmetric case where peer
; keepalives still arrive but our TX direction has gone one-way.  Raise
; this for ultra-marginal NVIS work where forward progress can take longer.
no_progress_timeout_s = 180

; Absolute cap (seconds, default: 30) on how long an application DISCONNECT
; may stay deferred while Mercury drains the last queued TX bytes.  When the
; host (e.g. BPQ32) ends a BBS forwarding session, Mercury finishes sending
; any buffered data, then completes a clean air-side DISCONNECT handshake.
; This cap guarantees the link always tears down within the window even if
; the session is stuck ping-ponging — preventing the rig from being keyed
; indefinitely after the host has already disconnected.  On a healthy link
; the drain finishes in seconds, so this only bites on a stuck session.
disconnect_drain_timeout_s = 30

[tnc]
; IAMALIVE interval on the TNC control port, seconds (5..600).
;keepalive_s = 60
; BUFFER report interval on the TNC control port, milliseconds (100..10000).
;buffer_report_ms = 1000
INIEOF
    echo -e "${GREEN}✓ mercury.ini installed to ${MERCURY_INI}${NC}"
fi

# Patch et-kill-all to stop Mercury
ET_KILL_ALL="/opt/emcomm-tools/bin/et-kill-all"
if [ -f "${ET_KILL_ALL}" ]; then
    if ! grep -q "mercury" "${ET_KILL_ALL}"; then
        echo ""
        echo "Adding Mercury to et-kill-all..."
        echo 'pkill -f "^mercury" 2>/dev/null || true' | sudo tee -a "${ET_KILL_ALL}" >/dev/null
        if grep -q "mercury" "${ET_KILL_ALL}"; then
            echo -e "${GREEN}✓ et-kill-all updated to stop Mercury${NC}"
        else
            echo -e "${YELLOW}⚠ Could not patch et-kill-all — you may need to stop Mercury manually${NC}"
        fi
    else
        echo -e "${GREEN}✓ et-kill-all already handles Mercury${NC}"
    fi
else
    echo -e "${YELLOW}⚠ et-kill-all not found at ${ET_KILL_ALL} — skipping patch${NC}"
fi

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
echo ""
echo "Configuration: ${MERCURY_INI}"
echo "  radio_model = -1 (no internal rig control)"
echo "  radio_device = 127.0.0.1:4532 (connects to rigctld)"
echo "  ui_enabled = true (web GUI on port 10000)"
echo "  arq_tcp_base_port = 8300 (VARA-compatible ARQ port)"
echo ""
echo "To use Mercury, run it from nozzle-menu or launch manually:"
echo "  cd ~ && mercury"
echo ""
echo "Web GUI: http://127.0.0.1:10000"
echo "  Use the web GUI to select and adjust your sound card settings."
echo ""
echo "Build directory: ${BUILD_DIR}"
echo "  (kept for future updates — rerun this script to pull and rebuild)"
echo ""
