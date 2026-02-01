# NozzleMods for EmComm Tools R5

A comprehensive collection of scripts and tools to enhance EmComm Tools R5 with VARA modem support, AIOC DireWolf integration, radio configuration utilities, and system maintenance tools.

## Quick Installation

```bash
curl -fsSL https://raw.githubusercontent.com/CowboyPilot/ETC5_NozzleMods/main/install.sh | bash
```

Or download and run:

```bash
wget https://raw.githubusercontent.com/CowboyPilot/ETC5_NozzleMods/main/install.sh
chmod +x install.sh
./install.sh
```

## What Gets Installed

The installer clones the entire repository to `~/NozzleMods/` with the following structure:

```
NozzleMods/
├── install.sh                          # Installer (for easy updates)
├── wine-tools/
│   ├── bin/
│   │   └── nozzle-menu                # Main menu launcher
│   ├── wine-setup.sh                  # VARA tools installer
│   └── fix-varac-13.sh                # Fix .NET issues with VarAC V13
├── radio-tools/
│   ├── xiegu-g90/
│   │   └── update-g90-config.sh       # Configure G90 DigiRig PTT
│   ├── yaesu-ft710/
│   │   ├── install_ft710.sh           # Install FT-710 support
│   │   ├── yaesu-ft710.json           # Radio configuration
│   │   ├── 78-et-ft710.rules          # udev rules
│   │   └── udev-tester.patch          # System patches
│   └── aioc/                          # ⭐ NEW: AIOC Support
│       ├── install_aioc.sh            # Install AIOC support
│       ├── aioc.json                  # AIOC radio configuration
│       ├── 93-aioc.rules              # AIOC udev rules
│       ├── aioc-direwolf              # AIOC DireWolf launcher script
│       ├── direwolf.aioc-simple.conf  # Simple TNC config
│       ├── direwolf.aioc-packet.conf  # Packet digipeater config
│       └── direwolf.aioc-aprs.conf    # APRS digipeater config
└── linux-tools/
    └── fix-sources.sh                 # Fix APT repository issues
```

The installer also copies `nozzle-menu` to `/opt/emcomm-tools/bin/` for system-wide access.

## Prerequisites

Before using NozzleMods, ensure you have:

1. **EmComm Tools R5** properly installed
2. Run `et-user` to configure your callsign
3. Run `et-audio` to configure audio
4. Run `et-radio` to select your radio
5. **For VARA tools**: Download VarAC Installer to `~/Downloads` (must follow naming: `VarAC_Installer_V*.exe`)
6. **For AIOC**: Have your AIOC hardware connected via USB

## Main Menu: nozzle-menu

After installation, access all features by running:

```bash
nozzle-menu
```

The menu provides organized access to:

### 🎯 VARA Applications (Options 1-9)

Launch Windows applications via Wine with automatic configuration:

* **VarAC + VARA HF/FM** - Digital chat modes
* **Winlink + VARA HF/FM** - Email over radio
* **Winlink Other** - ARDOP/Telnet modes (no VARA)
* **Pat + VARA HF/FM** - Web-based Winlink client
* **VARA Modems Only** - Standalone modem servers

**Features:**
* Automatic port allocation (8300-8350 range)
* Clean process management (kills old instances)
* Automatic INI file configuration
* COM10 mapping to `/dev/et-cat`
* Prevents VARA auto-launch conflicts

---

### 📡 AIOC Options (Option A) ⭐ NEW

Three pre-configured DireWolf modes for AIOC hardware:

1. **Simple TNC** - For APRS, ChatterVox, Packet, BBS applications
2. **Packet Digipeater** - Packet radio digipeater node
3. **APRS Digipeater** - APRS digipeater with full path support

**After launching AIOC mode:**
* Open a new terminal and run `et-mode` to select your application
* Use `alsamixer` to adjust input/output volumes
* The AIOC appears as both an audio device and serial port

**What is AIOC?**
The All-In-One-Cable (AIOC) is a compact USB-C adapter that provides:
* USB audio interface (sound card)
* Virtual serial port (CAT control/programming)
* CM108-compatible PTT control
* Built-in audio level adjustment

Perfect for digital modes, APRS, and packet radio with any K1-style connector radio.

---

### ⚙️ Radio Configuration (Option R)

1. **Xiegu G90 DigiRig PTT** - Configure PTT mode (CAT or RTS)
2. **Yaesu FT-710 Support** - Full installation with udev rules
3. **AIOC Support** - Install AIOC with DireWolf configurations

---

### 🔧 System Tools (Option S)

1. **Fix APT Sources** - Repair broken repository sources (Ubuntu 22.10/kinetic)
2. **Fix VarAC V13** - Resolve .NET runtime issues
3. **Update NozzleMods** - Download and install latest version from GitHub

---

## Detailed Feature Documentation

### VARA Tools Installation

If VARA tools aren't installed, nozzle-menu offers to run the installer, which:

1. Creates 32-bit Wine prefix at `~/.wine32`
2. Installs dependencies (dotnet48, vcrun2015, etc.)
3. Downloads and installs:
   * Winlink Express
   * VARA HF
   * VARA FM
   * VarAC (if installer available in ~/Downloads)
4. Configures COM10 → /dev/et-cat mapping
5. Creates GNOME menu launchers

**Manual installation:**
```bash
cd ~/NozzleMods/wine-tools
./wine-setup.sh
```

**Important**: First run may require logout/login to activate 32-bit Wine environment.

---

### AIOC Installation & Configuration

The AIOC installer sets up complete support for the All-In-One-Cable:

**Installation:**
```bash
cd ~/NozzleMods/radio-tools/aioc
sudo ./install_aioc.sh
```

**What gets installed:**
* Radio configuration file (`aioc.json`)
* udev rules for device detection (`93-aioc.rules`)
* Three DireWolf configuration profiles
* `aioc-direwolf` launcher script to `/opt/emcomm-tools/bin/`

**Three DireWolf Profiles:**

1. **Simple TNC Mode** (`direwolf.aioc-simple.conf`)
   - KISS TNC on port 8001
   - AGW protocol on port 8000
   - Perfect for APRS clients, packet BBS, ChatterVox
   - No digipeating - simple transparent TNC operation

2. **Packet Digipeater** (`direwolf.aioc-packet.conf`)
   - Full packet radio digipeater
   - WIDE1-1 and WIDE2-1 support
   - Flood control and duplicate filtering
   - KISS TNC + AGW simultaneously

3. **APRS Digipeater** (`direwolf.aioc-aprs.conf`)
   - Dedicated APRS digipeater with full path support
   - WIDE1-1, WIDE2-1, WIDE2-2 digipeating
   - Proportional pathing
   - Advanced filter lists

**Usage:**
```bash
# From nozzle-menu (Option A)
1) Simple TNC
2) Packet Digipeater
3) APRS Digipeater

# Or directly from command line:
aioc-direwolf start aioc-simple
aioc-direwolf start aioc-packet
aioc-direwolf start aioc-aprs
aioc-direwolf stop              # Stop any running instance
aioc-direwolf status            # Check status
```

**AIOC Requirements:**
* AIOC hardware connected via USB
* Radio must be set to AIOC in EmComm Tools (`et-radio`)
* Adjust audio levels with `alsamixer` (select AIOC device)
* Set radio to appropriate data mode (usually USB-D or DATA)

**Backup & Restore:**
The installer creates backups automatically. To restore:
```bash
cd ~/NozzleMods/radio-tools/aioc
sudo ./install_aioc.sh
# Choose 'y' when prompted to restore backup
```

---

### Radio-Specific Configuration

#### Xiegu G90 DigiRig

Configure PTT options for DigiRig interface:

```bash
sudo ~/NozzleMods/radio-tools/xiegu-g90/update-g90-config.sh
```

Choose between:
* **CAT PTT** - PTT via CAT commands
* **RTS PTT** - PTT via RTS serial line

**Menu Settings:**
* Set appropriate audio levels
* Enable DATA mode if available
* Adjust MIC gain for clean digital signal

---

#### Yaesu FT-710

Complete support installation with udev rules:

```bash
cd ~/NozzleMods/radio-tools/yaesu-ft710
sudo ./install_ft710.sh
```

**Required FT-710 Menu Settings:**
* **CAT RATE** = 38400bps
* **CAT TOT** = 100ms
* **FUNC → RADIO SETTING → MODE PSK/DATA:**
  + USB OUT LEVEL = 30
  + USB MOD GAIN = 70
* Select operating mode: **DATA-U**

**Features:**
* Automatic device detection via udev
* Creates `/dev/et-cat` and `/dev/et-audio` symlinks
* Patches EmComm Tools for FT-710 support
* Automatic backup creation
* Alsa Configuration

**Backup Location:**
```bash
~/.ft710-backup/udev-tester.sh.backup
```

---

## System Maintenance

### Fix APT Repository Sources

For Ubuntu 22.10 (kinetic) systems with repository errors:

```bash
sudo ~/NozzleMods/linux-tools/fix-sources.sh
```

**This fixes:**
* Points sources to archive.ubuntu.com for EOL releases
* Updates security repository URLs
* Runs `apt update` to verify fixes

---

### Fix VarAC V13 .NET Issues

VarAC V13 requires specific .NET runtime versions:

```bash
~/NozzleMods/wine-tools/fix-varac-13.sh
```

**Fixes:**
* Installs correct .NET Framework versions
* Resolves Wine-specific compatibility issues
* No need to reinstall VarAC

---

## Updating NozzleMods

### Method 1: Via nozzle-menu
```bash
nozzle-menu
# Select: S) System Tools → 3) Update NozzleMods Tools
```

### Method 2: Re-run installer
```bash
curl -fsSL https://raw.githubusercontent.com/CowboyPilot/ETC5_NozzleMods/main/install.sh | bash
```

### Method 3: Use local installer
```bash
~/NozzleMods/install.sh
```

**Update Process:**
* Clones latest repository from GitHub
* Backs up existing installation with timestamp
* Copies all new/updated files
* Updates nozzle-menu in system bin directory
* Preserves your Wine prefix and configurations

---

## Troubleshooting

### VARA Applications Won't Start

**Check installation:**
```bash
ls ~/.wine32
ls ~/.wine32/drive_c/VARA/
```

**If missing:** Run installer from nozzle-menu Option 1 (if VARA not installed)

---

### Port Conflicts

Launcher automatically finds free ports (8300-8350). To check manually:
```bash
ss -tan | grep 8300
```

---

### Radio Not Detected

**Verify radio selection:**
```bash
et-radio
```

**Check device creation:**
```bash
ls -l /dev/et-cat /dev/et-audio
```

**Monitor udev events:**
```bash
sudo udevadm monitor
```

**Check udev rules:**
```bash
ls -l /etc/udev/rules.d/*aioc* /etc/udev/rules.d/*ft710* /etc/udev/rules.d/*g90*
```

---

### AIOC Issues

**Check device detection:**
```bash
lsusb | grep -i aioc
# Should show: "1209:7388"
```

**Check audio device:**
```bash
aplay -l | grep -i aioc
arecord -l | grep -i aioc
```

**Check serial device:**
```bash
ls -l /dev/ttyACM*
```

**Test DireWolf configuration:**
```bash
cd /opt/emcomm-tools/conf/template.d/packet
direwolf -c direwolf.aioc-simple.conf -t 0
# Press Ctrl+C to exit test mode
```

**Adjust audio levels:**
```bash
alsamixer
# Press F6, select AIOC sound card
# Adjust Mic and Speaker levels
```

---

### VarAC V13 Crashes

Run the .NET fix:
```bash
~/NozzleMods/wine-tools/fix-varac-13.sh
```

---

### First-Run Configuration Issues

**Winlink Express:**
* Configure callsign and grid square on first run
* Disable "Auto Launch Vara" and "Auto Launch Vara FM" in Vara TNC settings
* The launcher will handle VARA startup

**VarAC:**
* Configure callsign and grid square
* In VARA HF/FM settings: Disable all "Launch" and "AutoStart" options
* Set COM Port to COM10
* Baud rate should match your radio (usually 38400)

---

## File Locations

| Item | Location |
|------|----------|
| User Scripts | `~/NozzleMods/` |
| nozzle-menu | `/opt/emcomm-tools/bin/nozzle-menu` |
| Wine Prefix | `~/.wine32/` |
| EmComm Tools | `/opt/emcomm-tools/` |
| ET Configuration | `~/.config/emcomm-tools/` |
| AIOC Backups | `~/.aioc-backup/` |
| FT-710 Backups | `~/.ft710-backup/` |
| G90 Backups | `/opt/emcomm-tools/conf/radios.d/*.backup.*` |

---

## Advanced Usage

### Manual AIOC DireWolf Launch

```bash
# Start with specific config
aioc-direwolf start aioc-simple

# Check status
aioc-direwolf status

# Stop running instance
aioc-direwolf stop

# View logs
journalctl -f | grep direwolf
```

---

### Custom DireWolf Configurations

Edit configurations in:
```bash
/opt/emcomm-tools/conf/template.d/packet/direwolf.aioc-*.conf
```

After editing, restart:
```bash
aioc-direwolf stop
aioc-direwolf start aioc-simple  # Or packet/aprs
```

---

### VARA Port Configuration

Ports are automatically assigned (8300-8350). To manually set:

Edit INI files:
```bash
# VARA HF
~/.wine32/drive_c/VARA/VARA.ini

# VARA FM
~/.wine32/drive_c/VARA FM/VARAFM.ini
```

Change line:
```ini
TCP Command Port=8300
```

---

## Supported Hardware

### Radios
* ✅ Xiegu G90 (with DigiRig)
* ✅ Yaesu FT-710
* ✅ Any radio compatible with AIOC (K1-style connector)
* ✅ Any radio supported by EmComm Tools R5

### Interfaces
* ✅ DigiRig Mobile
* ✅ AIOC (All-In-One-Cable)
* ✅ Standard USB-to-serial adapters
* ✅ Built-in USB interfaces

---

## Credits

* **EmComm Tools R5** by [TheTechPrepper](https://github.com/thetechprepper)
* **AIOC Hardware** by [skuep](https://github.com/skuep/AIOC)
* **VARA Modems** by Jose Alberto Reyes Martin, EA5HVK
* **VarAC** by Irad Yakir
* **Winlink Express** by Winlink Development Team
* **DireWolf** by John Langner, WB2OSZ
* **Pat Winlink** by Martin Hebnes Pedersen, LA5NTA

---

## Contributing

Found a bug? Have a suggestion? 

1. Check existing [Issues](https://github.com/CowboyPilot/ETC5_NozzleMods/issues)
2. Open a new issue with details
3. Pull requests welcome!

---

## Version History

### V1.2 (Latest)
* ✨ Added complete AIOC support
* ✨ Added three DireWolf profiles (Simple TNC, Packet Digi, APRS Digi)
* ✨ Added AIOC Options menu to nozzle-menu
* ✨ Added aioc-direwolf launcher script
* 🔧 Improved installer to clone entire repository
* 📝 Updated all documentation

### V1.1
* Added Yaesu FT-710 support
* Improved VARA port handling
* Added system tools menu
* Bug fixes for VarAC V13

### V1.0
* Initial release
* VARA tools installer
* Xiegu G90 support
* nozzle-menu launcher

---

## License

These scripts are provided as-is for use with EmComm Tools R5.

**USE AT YOUR OWN RISK**

Always ensure you have backups before running system modification scripts.

---

## 73!

Happy operating!

*Emergency communications through amateur radio innovation.*

---

## Quick Reference Card

### Most Common Commands
```bash
# Launch main menu
nozzle-menu

# Launch VARA app (from menu)
nozzle-menu → (1-9)

# Launch AIOC mode (from menu)
nozzle-menu → A → (1-3)

# Configure radio
et-radio

# Select audio device
et-audio

# Set user info
et-user

# Check devices
ls -l /dev/et-*

# Update NozzleMods
~/NozzleMods/install.sh
```

### Emergency Radio Setup
1. Connect radio/interface
2. `et-radio` - Select radio
3. `et-audio` - Select audio
4. `et-user` - Set callsign
5. `nozzle-menu` - Launch application

### AIOC Quick Start
1. `nozzle-menu`
2. Select: `R) Radio Configuration → 3) Install AIOC`
3. Reboot or reload udev
4. `et-radio` - Select "AIOC"
5. `nozzle-menu → A` - Launch AIOC mode

---
