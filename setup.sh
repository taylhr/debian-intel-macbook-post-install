#!/bin/bash
# setup.sh
# Post-installation setup for Debian 13 (Trixie) on Intel MacBooks
# Tested on MacBook Air 7,2 (2015) — should work on most Intel MacBooks
# https://github.com/willardcsoriano/debian-intel-macbook-post-install

set -uo pipefail

# ─────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────
# TRACKING
# ─────────────────────────────────────────────
INSTALLED=()
SKIPPED=()
FAILED=()
REBOOT_REQUIRED=false
HAS_DBUS=true
# Optional system-upgrade status, rendered as its own summary block (it's a
# system-currency status, not a package): current | upgraded | declined | failed
UPGRADE_STATE="current"
UPGRADE_COUNT=0

# ─────────────────────────────────────────────
# GROUPS
# ─────────────────────────────────────────────
# Every installable unit belongs to exactly one group, and each group can be
# turned off at runtime (see --help). GROUP_ORDER is also the execution order,
# and that order is load-bearing:
#   • APT sources are configured before this list runs (core, not a group)
#   • the DKMS drivers (wifi-broadcom, webcam) must register before
#     system-upgrade, so a new kernel rebuilds them automatically
#   • system-upgrade runs last, immediately before the summary
# Pre-flight checks, APT sources, the summary, and the reboot prompt are core:
# they always run, because every group depends on them.
GROUP_ORDER=(
    wifi-broadcom
    auto-updates
    desktop
    terminal
    apps-essential
    apps-dev
    apps-media
    apps-office
    print-scan
    bluetooth
    monitoring
    network-manager
    keyboard
    touchpad
    webcam
    microphone
    power
    panel
    desktop-shortcuts
    system-upgrade
)

group_desc() {
    case "$1" in
        wifi-broadcom)     echo "Broadcom WiFi rebuild chain — DKMS, headers, module blacklists" ;;
        auto-updates)      echo "Unattended security patches, microcode, firmware, needrestart" ;;
        desktop)           echo "Xorg, XFCE, fonts, window tiling, App Finder launcher fix" ;;
        terminal)          echo "GNOME Terminal and the bracketed-paste fix" ;;
        apps-essential)    echo "Firefox, gedit, File Roller, gdebi, poppler-utils, speech-dispatcher" ;;
        apps-dev)          echo "Visual Studio Code (adds Microsoft's apt repository)" ;;
        apps-media)        echo "VLC, Flameshot (+ screenshot shortcut), mtPaint" ;;
        apps-office)       echo "LibreOffice — large download, roughly 300MB" ;;
        print-scan)        echo "CUPS printing, SANE, Simple Scan" ;;
        bluetooth)         echo "Blueman Bluetooth manager" ;;
        monitoring)        echo "XFCE Task Manager, htop, fastfetch" ;;
        network-manager)   echo "NetworkManager, replacing manual wpa_supplicant + dhcpcd" ;;
        keyboard)          echo "keyd Mac-style remapping, rofi, backlight permissions" ;;
        touchpad)          echo "bcm5974 trackpad resume fix" ;;
        webcam)            echo "FaceTime HD camera driver — builds from source, several minutes" ;;
        microphone)        echo "ALSA microphone quirk (snd-hda-intel model=mbp101)" ;;
        power)             echo "s2idle suspend, lid suspend-then-hibernate, battery plugin" ;;
        panel)             echo "Clean XFCE panel layout applied on first login" ;;
        desktop-shortcuts) echo "Desktop launchers and the keyboard shortcuts cheat sheet" ;;
        system-upgrade)    echo "Offer a full apt upgrade to the latest point release" ;;
        *)                 echo "" ;;
    esac
}

# Hard prerequisites. A group listed here cannot run without the groups it
# names, so an inconsistent selection is rejected up front rather than
# silently installing something that was deliberately turned off.
group_requires() {
    case "$1" in
        panel)             echo "desktop" ;;
        desktop-shortcuts) echo "desktop" ;;
        *)                 echo "" ;;
    esac
}

# Presets are starting points, not final answers — --add and --skip apply on top.
# Used only for help text and error messages; preset_groups() below is what
# actually defines them, and an unknown name there is what makes one invalid.
PRESET_NAMES="full, minimal, hardware, existing-desktop"

preset_groups() {
    case "$1" in
        hardware)
            echo "wifi-broadcom auto-updates network-manager keyboard touchpad webcam microphone power"
            ;;
        minimal)
            echo "wifi-broadcom auto-updates network-manager keyboard touchpad power \
                  desktop terminal apps-essential panel desktop-shortcuts"
            ;;
        # For a machine that already has a desktop — e.g. Debian installed with
        # the "Debian desktop environment + Xfce" task. Keeps every hardware fix
        # and the XFCE tweaks (window tiling, App Finder launcher fix, which the
        # desktop group carries and whose packages no-op when already present),
        # and leaves alone the parts that would fight an existing setup:
        #   panel             would replace a panel layout you may have customised
        #   desktop-shortcuts would litter a Desktop you have already arranged
        #   terminal          gnome-terminal duplicates the xfce4-terminal you have
        #   apps-*            the desktop task ships its own browser, editor,
        #                     media player and LibreOffice components. apps-office
        #                     in particular installs the libreoffice metapackage,
        #                     which adds Base, Draw and Math on top of the
        #                     writer/calc/impress the task already gave you.
        #   print-scan        the desktop task ships cups and xsane
        # Add any of them back with --add.
        existing-desktop)
            echo "wifi-broadcom auto-updates network-manager keyboard touchpad webcam \
                  microphone power desktop system-upgrade"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Enabled groups are tracked as a space-delimited string rather than an
# associative array so this runs on any bash, including the 3.2 that ships on
# macOS — handy when editing or testing the script away from the target machine.
ENABLED_SET=""

is_enabled() {
    case " $ENABLED_SET " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

# True when the group was named directly on --only or --add, i.e. asked for
# rather than merely left on. Groups that would overwrite existing configuration
# hold off unless explicitly requested this way.
is_requested() {
    case " $REQUESTED_SET " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

enable_group() {
    is_enabled "$1" || ENABLED_SET="$ENABLED_SET $1"
}

disable_group() {
    local g new=""
    for g in $ENABLED_SET; do
        [ "$g" = "$1" ] || new="$new $g"
    done
    ENABLED_SET="$new"
}

enable_all() {
    local g
    ENABLED_SET=""
    for g in "${GROUP_ORDER[@]}"; do
        ENABLED_SET="$ENABLED_SET $g"
    done
}

disable_all() { ENABLED_SET=""; }

is_group() {
    local g
    for g in "${GROUP_ORDER[@]}"; do
        [ "$g" = "$1" ] && return 0
    done
    return 1
}

# ─────────────────────────────────────────────
# COMMAND LINE
# ─────────────────────────────────────────────
usage() {
    cat << USAGE

  setup.sh — post-installation setup for Debian 13 on Intel MacBooks

  Usage: setup.sh [options]

  With no options every group runs, which is the full install.

  Options:
    -p, --preset NAME   Start from a preset instead of the full install
    -o, --only LIST     Run only these groups (comma separated)
    -a, --add LIST      Add these groups on top of a preset (comma separated)
    -s, --skip LIST     Skip these groups (comma separated)
    -l, --list          List every group with what it does, then exit
    -n, --dry-run       Show what would run, install nothing, then exit
    -h, --help          Show this help, then exit

  Presets:
    full              Everything (the default)
    minimal           Hardware fixes, desktop, terminal, essential apps
    hardware          MacBook hardware enablement and updates only — no desktop,
                      no apps
    existing-desktop  For a machine that already has a desktop, e.g. Debian
                      installed with the "Debian desktop environment + Xfce"
                      task. Hardware fixes and XFCE tweaks, without the parts
                      that would fight a desktop you already set up.

  Examples:
    setup.sh --skip apps-office,apps-dev
    setup.sh --preset hardware
    setup.sh --only wifi-broadcom,keyboard,webcam
    setup.sh --preset minimal --skip webcam
    setup.sh --preset existing-desktop --add monitoring

    bash <(curl -s .../setup.sh) --skip apps-office

  --preset and --only are mutually exclusive. --add and --skip apply on top of
  either, in that order. Pre-flight checks, APT sources, and the summary always
  run.

USAGE
}

list_groups() {
    local g req
    echo -e "\n${BOLD}  Available groups${NC}\n"
    for g in "${GROUP_ORDER[@]}"; do
        printf "  ${CYAN}%-18s${NC} %s" "$g" "$(group_desc "$g")"
        req=$(group_requires "$g")
        [ -n "$req" ] && printf " ${YELLOW}(requires: %s)${NC}" "$req"
        echo ""
    done
    echo -e "\n  ${CYAN}All groups run by default. Use --skip, --only, or --preset to choose.${NC}\n"
}

# Validates a comma-separated group list, echoing the names one per line.
# Fails on the first unknown name so a typo can't silently drop a group.
parse_group_list() {
    local raw=$1 flag=$2 g
    local IFS=','
    for g in $raw; do
        g="${g//[[:space:]]/}"
        [ -n "$g" ] || continue
        if ! is_group "$g"; then
            echo -e "${RED}  ✘ Unknown group '$g' in $flag${NC}" >&2
            echo -e "${YELLOW}  Run: setup.sh --list  to see valid group names.${NC}" >&2
            return 1
        fi
        echo "$g"
    done
}

PRESET=""
ONLY_LIST=""
ADD_LIST=""
SKIP_LIST=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        -p|--preset)
            [ $# -ge 2 ] || { echo -e "${RED}  ✘ --preset needs a value${NC}" >&2; exit 1; }
            PRESET="$2"; shift 2 ;;
        --preset=*) PRESET="${1#*=}"; shift ;;
        -o|--only)
            [ $# -ge 2 ] || { echo -e "${RED}  ✘ --only needs a value${NC}" >&2; exit 1; }
            ONLY_LIST="$2"; shift 2 ;;
        --only=*)   ONLY_LIST="${1#*=}"; shift ;;
        -a|--add)
            [ $# -ge 2 ] || { echo -e "${RED}  ✘ --add needs a value${NC}" >&2; exit 1; }
            ADD_LIST="$2"; shift 2 ;;
        --add=*)    ADD_LIST="${1#*=}"; shift ;;
        -s|--skip)
            [ $# -ge 2 ] || { echo -e "${RED}  ✘ --skip needs a value${NC}" >&2; exit 1; }
            SKIP_LIST="$2"; shift 2 ;;
        --skip=*)   SKIP_LIST="${1#*=}"; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -l|--list)  list_groups; exit 0 ;;
        -h|--help)  usage; exit 0 ;;
        *)
            echo -e "${RED}  ✘ Unknown option: $1${NC}" >&2
            echo -e "${YELLOW}  Run: setup.sh --help${NC}" >&2
            exit 1 ;;
    esac
done

if [ -n "$PRESET" ] && [ -n "$ONLY_LIST" ]; then
    echo -e "${RED}  ✘ --preset and --only are mutually exclusive.${NC}" >&2
    echo -e "${YELLOW}  Pick a preset and narrow it with --skip, or list groups with --only.${NC}" >&2
    exit 1
fi

enable_all

if [ -n "$PRESET" ]; then
    # Validity comes from preset_groups() itself — an unknown name returns an
    # empty list — so presets only ever need adding in one place. "full" is the
    # exception: it means every group, which is already the starting state.
    if [ "$PRESET" != "full" ]; then
        _preset_list=$(preset_groups "$PRESET")
        if [ -z "$_preset_list" ]; then
            echo -e "${RED}  ✘ Unknown preset: $PRESET${NC}" >&2
            echo -e "${YELLOW}  Valid presets: $PRESET_NAMES${NC}" >&2
            exit 1
        fi
        disable_all
        for _g in $_preset_list; do enable_group "$_g"; done
    fi
fi

# Groups named directly on --only or --add are stated requests, tracked
# separately from groups that merely happen to be on. Unmet dependencies are
# handled differently for the two (see below), and groups that would overwrite
# existing configuration only do so when asked for this explicitly.
REQUESTED_SET=""

if [ -n "$ONLY_LIST" ]; then
    _only=$(parse_group_list "$ONLY_LIST" "--only") || exit 1
    disable_all
    for _g in $_only; do
        enable_group "$_g"
        REQUESTED_SET="$REQUESTED_SET $_g"
    done
fi

if [ -n "$ADD_LIST" ]; then
    _add=$(parse_group_list "$ADD_LIST" "--add") || exit 1
    for _g in $_add; do
        enable_group "$_g"
        REQUESTED_SET="$REQUESTED_SET $_g"
    done
fi

if [ -n "$SKIP_LIST" ]; then
    _skip=$(parse_group_list "$SKIP_LIST" "--skip") || exit 1
    for _g in $_skip; do disable_group "$_g"; done
fi

# Resolve dependencies before anything is installed — finding out 20 minutes in
# that the panel silently did nothing is worse than being told now.
#
# Skipping a group implicitly skips whatever needs it: "--skip desktop" plainly
# means no GUI, so carrying panel and desktop-shortcuts along with it is what
# was meant. A group named directly on --only is different — that's an explicit
# request, so an unmet dependency is an error rather than a silent no-op, and
# quietly pulling in all of XFCE to satisfy it would defeat the point of --only.
# Loops to a fixed point so a chain of dependencies resolves in one pass.
CASCADED=()
_blocked=()
while :; do
    _changed=false
    for _g in "${GROUP_ORDER[@]}"; do
        is_enabled "$_g" || continue
        for _dep in $(group_requires "$_g"); do
            is_enabled "$_dep" && continue
            case " $REQUESTED_SET " in
                *" $_g "*) _blocked+=("$_g needs $_dep, which is not in this run") ;;
                *)         CASCADED+=("$_g — needs $_dep") ;;
            esac
            disable_group "$_g"
            _changed=true
            break
        done
    done
    $_changed || break
done

if [ ${#_blocked[@]} -gt 0 ]; then
    echo -e "\n${RED}  ✘ That group selection doesn't work:${NC}" >&2
    for _p in "${_blocked[@]}"; do
        echo -e "${RED}    • $_p${NC}" >&2
    done
    echo -e "${YELLOW}  Add the missing group, or drop the one that needs it.${NC}\n" >&2
    exit 1
fi

if [ ${#CASCADED[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}  Also skipping, because what they depend on is skipped:${NC}"
    for _c in "${CASCADED[@]}"; do
        echo -e "${YELLOW}    • $_c${NC}"
    done
fi

ENABLED_COUNT=0
DISABLED_GROUPS=()
for _g in "${GROUP_ORDER[@]}"; do
    if is_enabled "$_g"; then
        ENABLED_COUNT=$((ENABLED_COUNT + 1))
    else
        DISABLED_GROUPS+=("$_g")
    fi
done

# Checked before the dry-run report so an empty selection is caught either way.
if [ "$ENABLED_COUNT" -eq 0 ]; then
    echo -e "\n${RED}  ✘ Every group is disabled — there is nothing to do.${NC}" >&2
    echo -e "${YELLOW}  Run: setup.sh --list  to see what's available.${NC}\n" >&2
    exit 1
fi

if $DRY_RUN; then
    echo -e "\n${BOLD}  Dry run — nothing will be installed${NC}\n"
    for _g in "${GROUP_ORDER[@]}"; do
        if is_enabled "$_g"; then
            echo -e "  ${GREEN}✔ $(printf '%-18s' "$_g")${NC} $(group_desc "$_g")"
        else
            echo -e "  ${YELLOW}⊘ $(printf '%-18s' "$_g")${NC} skipped"
        fi
    done
    echo -e "\n  ${CYAN}$ENABLED_COUNT group(s) would run, ${#DISABLED_GROUPS[@]} skipped.${NC}\n"
    exit 0
fi

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
LOG_FILE="$HOME/setup-$(date +%Y%m%d-%H%M%S).log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/setup-$(date +%Y%m%d-%H%M%S).log"

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
print_header() {
    echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}\n"
}

print_ok()      { echo -e "${GREEN}  ✔ $1${NC}"; }
print_skip()    { echo -e "${YELLOW}  ⊘ $1 — already installed, skipping${NC}"; }
print_fail()    { echo -e "${RED}  ✘ $1 — failed to install${NC}"; }
print_info()    { echo -e "${CYAN}  → $1${NC}"; }
print_warning() { echo -e "${YELLOW}  ⚠ $1${NC}"; }

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

# Returns: 0 = installed now, 1 = already installed, 2 = failed
install_pkg() {
    local pkg=$1
    local label=${2:-$1}
    if dpkg -s "$pkg" &>/dev/null; then
        print_skip "$label"
        SKIPPED+=("$label")
        return 1
    fi
    print_info "Installing $label..."
    log "apt install $pkg"
    if sudo apt install -y "$pkg" >>"$LOG_FILE" 2>&1; then
        print_ok "$label installed"
        INSTALLED+=("$label")
        return 0
    fi
    print_fail "$label"
    FAILED+=("$label")
    return 2
}

# Returns: 0 = installed now, 1 = already installed, 2 = failed
install_pkgs() {
    local label=$1
    shift
    local pkgs=("$@")
    local all_installed=true

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            all_installed=false
            break
        fi
    done

    if $all_installed; then
        print_skip "$label"
        SKIPPED+=("$label")
        return 1
    fi
    print_info "Installing $label..."
    log "apt install ${pkgs[*]}"
    if sudo apt install -y "${pkgs[@]}" >>"$LOG_FILE" 2>&1; then
        print_ok "$label installed"
        INSTALLED+=("$label")
        return 0
    fi
    print_fail "$label"
    FAILED+=("$label")
    return 2
}

xfconf_set() {
    # Safely call xfconf-query; warn if no session
    if ! $HAS_DBUS; then
        log "xfconf skipped (no dbus): $*"
        return 1
    fi
    xfconf-query "$@" 2>>"$LOG_FILE" || true
}

fix_desktop_launchers() {
    local apps_dir="/usr/share/applications"
    local local_dir="$ACTUAL_HOME/.local/share/applications"
    local fixed=0
    mkdir -p "$local_dir"

    for desktop_file in "$apps_dir"/*.desktop; do
        local app_name
        app_name=$(basename "$desktop_file")

        if [ -f "$local_dir/$app_name" ] && ! grep -qE "Exec=.*%[FfUu]" "$local_dir/$app_name"; then
            continue
        fi

        if ! grep -qE "Exec=.*%[FfUu]" "$desktop_file"; then
            continue
        fi

        sed 's/ *%[FfUu]//g' "$desktop_file" > "$local_dir/$app_name"
        ((fixed++))
    done

    if [ "$fixed" -gt 0 ]; then
        update-desktop-database "$local_dir"
        print_ok "Fixed $fixed app launcher(s) for XFCE App Finder"
    else
        print_skip "App launcher fix — all already clean"
    fi
}

create_shortcut() {
    local name=$1
    local exec=$2
    local icon=$3
    local terminal=${4:-false}
    local file="$DESKTOP_DIR/${name}.desktop"

    # Skip launchers for apps that aren't installed. Any app group may be
    # turned off, and a shortcut that does nothing when clicked is worse than
    # no shortcut at all. Terminal wrappers ("gnome-terminal -- htop") need
    # both the terminal and the program it runs, so check both.
    local bins=("${exec%% *}") rest
    if [[ "$exec" == *" -- "* ]]; then
        rest=${exec#* -- }
        bins+=("${rest%% *}")
    fi
    local bin
    for bin in "${bins[@]}"; do
        if ! command -v "$bin" &>/dev/null; then
            log "shortcut skipped ($name): $bin not installed"
            return 0
        fi
    done

    if [ -f "$file" ]; then
        print_skip "$name desktop shortcut"
    else
        cat > "$file" <<SHORTCUT
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Exec=$exec
Icon=$icon
Terminal=$terminal
SHORTCUT
        chmod +x "$file"
        print_ok "$name shortcut created on Desktop"
    fi
}

# ─────────────────────────────────────────────
# WELCOME
# ─────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   debian-intel-macbook-post-install      ║"
echo "  ║   Intel MacBooks · Debian 13 Trixie      ║"
echo "  ║   github.com/willardcsoriano             ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}\n"
if [ ${#DISABLED_GROUPS[@]} -eq 0 ]; then
    echo -e "  This script will set up your MacBook with everything"
    echo -e "  you need for a smooth Linux experience.\n"
    echo -e "  ${CYAN}Estimated time: 10–20 minutes depending on internet speed.${NC}"
else
    echo -e "  Running ${BOLD}$ENABLED_COUNT${NC} of ${#GROUP_ORDER[@]} groups."
    echo -e "  ${YELLOW}Skipping: ${DISABLED_GROUPS[*]}${NC}\n"
fi
echo -e "  ${CYAN}Group options: setup.sh --help${NC}"
echo -e "  ${CYAN}Full log: $LOG_FILE${NC}\n"

log "enabled groups:$ENABLED_SET"

# ─────────────────────────────────────────────
# CHECKS
# ─────────────────────────────────────────────
print_header "Pre-flight Checks"

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}  ✘ Please do not run this script as root.${NC}"
    echo -e "${YELLOW}  Run it as your regular user. See the README for setup instructions.${NC}"
    exit 1
fi
print_ok "Running as regular user (${USER})"

if ! sudo -v &>/dev/null; then
    echo -e "${RED}  ✘ sudo is not configured for your user.${NC}"
    echo -e "${YELLOW}  Fix it by running: su -${NC}"
    echo -e "${YELLOW}  Then: usermod -aG sudo ${USER}${NC}"
    echo -e "${YELLOW}  Then log out and back in, and run this script again.${NC}"
    exit 1
fi
print_ok "sudo access confirmed"

# Keep sudo alive for the full run (webcam build can take several minutes)
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null || true" EXIT INT TERM

# Use whichever HTTP client is on the system; minimal Debian may lack wget
if command -v wget &>/dev/null; then
    NET_CHECK="wget -q --spider --timeout=5 https://deb.debian.org"
elif command -v curl &>/dev/null; then
    NET_CHECK="curl -fsS --max-time 5 -o /dev/null https://deb.debian.org"
else
    NET_CHECK=""
fi
if [ -z "$NET_CHECK" ] || ! eval "$NET_CHECK"; then
    if [ -z "$NET_CHECK" ]; then
        print_warning "Neither wget nor curl found — skipping connectivity check."
    else
        echo -e "${RED}  ✘ No internet connection detected.${NC}"
        echo -e "${YELLOW}  Please connect to WiFi or a hotspot first, then run this script again.${NC}"
        exit 1
    fi
else
    print_ok "Internet connection is working"
fi

if ! grep -q "trixie\|13" /etc/os-release; then
    print_warning "This script was tested on Debian 13 (Trixie). Your system may differ."
    read -p "  Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi
print_ok "Debian 13 (Trixie) confirmed"

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    HAS_DBUS=false
    print_warning "No active dbus session detected."
    print_warning "XFCE settings (shortcuts, power, tiling) will NOT persist."
    print_warning "For best results, run this script from inside an XFCE session."
    read -p "  Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
else
    print_ok "dbus user session detected"
fi

BACKLIGHT_PATH="/sys/class/backlight/intel_backlight"
if [ -f "$BACKLIGHT_PATH/max_brightness" ]; then
    MAX_BRIGHTNESS=$(cat "$BACKLIGHT_PATH/max_brightness")
    print_ok "Screen backlight detected (max brightness: $MAX_BRIGHTNESS)"
else
    MAX_BRIGHTNESS=2777
    print_warning "Could not detect backlight. Using default value of $MAX_BRIGHTNESS."
fi

ACTUAL_HOME=$(getent passwd "$USER" | cut -d: -f6)
DESKTOP_DIR="$ACTUAL_HOME/Desktop"
print_ok "Home directory: $ACTUAL_HOME"

# Detect a desktop that predates this run. This script was written for a bare
# terminal install, but Debian can equally be installed with the "Debian desktop
# environment + Xfce" task, and that machine arrives with XFCE already set up and
# possibly customised. Checked here, before any group installs anything, so the
# answer reflects the machine as it was handed to us. See group_panel.
if dpkg -s xfce4 &>/dev/null; then
    XFCE_PREEXISTING=true
    print_info "XFCE is already installed — treating this as an existing desktop"
    print_info "Package steps that are already satisfied will be skipped automatically"
else
    XFCE_PREEXISTING=false
fi

# ─────────────────────────────────────────────
# APT SOURCES
# ─────────────────────────────────────────────
print_header "Configuring Package Sources"

# Debian 13 may use either the legacy /etc/apt/sources.list OR the new
# deb822 format at /etc/apt/sources.list.d/debian.sources. Handle both.
SOURCES_LEGACY="/etc/apt/sources.list"
SOURCES_DEB822="/etc/apt/sources.list.d/debian.sources"

enable_component() {
    # $1 = file, $2 = component name (contrib, non-free, non-free-firmware)
    local file=$1 comp=$2
    if [[ "$file" == *.sources ]]; then
        # deb822 format: Components: main non-free-firmware
        if ! grep -qE "^Components:.*\b${comp}\b([^-]|$)" "$file"; then
            sudo sed -i -E "/^Components:/ s/\$/ ${comp}/" "$file"
            return 0
        fi
    else
        # Legacy format: deb ... main non-free-firmware
        if ! grep -qE "\b${comp}\b([^-]|$)" "$file"; then
            sudo sed -i -E "s/(^deb[^\n]*main[^\n]*)$/\1 ${comp}/" "$file"
            return 0
        fi
    fi
    return 1
}

if [ -f "$SOURCES_DEB822" ]; then
    SOURCES_FILE="$SOURCES_DEB822"
    FORMAT="deb822"
elif [ -s "$SOURCES_LEGACY" ]; then
    SOURCES_FILE="$SOURCES_LEGACY"
    FORMAT="legacy"
else
    SOURCES_FILE=""
    FORMAT="none"
fi

if [ -n "$SOURCES_FILE" ]; then
    print_info "Detected APT sources format: $FORMAT ($SOURCES_FILE)"
    changed=false
    for comp in contrib non-free non-free-firmware; do
        if enable_component "$SOURCES_FILE" "$comp"; then
            changed=true
        fi
    done
    if $changed; then
        print_ok "Additional repositories enabled (contrib, non-free, non-free-firmware)"
    else
        print_skip "Package repositories already configured"
    fi
else
    print_warning "No APT sources file found — skipping component enable"
fi

print_info "Refreshing package list (this may take a moment)..."
sudo apt update -y >>"$LOG_FILE" 2>&1
print_ok "Package list is up to date"

# ─────────────────────────────────────────────
# GROUP: wifi-broadcom
# ─────────────────────────────────────────────
group_wifi_broadcom() {
    print_header "Broadcom WiFi Hardening"
    echo -e "  ${CYAN}Locking in the Broadcom driver rebuild chain so WiFi survives kernel updates.${NC}\n"

    # DKMS and kernel headers — without these, the Broadcom driver
    # vanishes silently on every kernel update
    install_pkg "dkms" "DKMS (kernel module rebuild framework)"
    install_pkg "linux-headers-amd64" "linux-headers-amd64 (kernel headers meta-package)"
    print_ok "Broadcom driver rebuild chain secured"

    # Blacklist conflicting open-source Broadcom modules — b43, bcma, and ssb
    # fight with the proprietary wl driver and win, causing random WiFi drops
    local blacklist_file="/etc/modprobe.d/broadcom-blacklist.conf"
    if [ ! -f "$blacklist_file" ]; then
        print_info "Blacklisting conflicting Broadcom modules (b43, bcma, ssb)..."
        sudo tee "$blacklist_file" > /dev/null << 'EOF'
blacklist b43
blacklist bcma
blacklist ssb
EOF
        print_ok "Conflicting modules blacklisted"
    else
        print_skip "Broadcom blacklist already configured"
    fi

    # Persist the wl module across reboots — modprobe alone doesn't survive a restart
    if ! grep -q "wl" /etc/modules-load.d/broadcom.conf 2>/dev/null; then
        print_info "Setting wl module to load automatically on boot..."
        echo "wl" | sudo tee /etc/modules-load.d/broadcom.conf > /dev/null
        print_ok "wl module set to load on boot"
    else
        print_skip "wl boot config already set"
    fi

    # Swap check — 8GB RAM with no swap will hard freeze on OOM with no warning
    if ! /usr/sbin/swapon --show 2>/dev/null | grep -q .; then
        print_warning "No swap detected — consider adding a swapfile to prevent out-of-memory freezes"
    fi
}

# ─────────────────────────────────────────────
# GROUP: auto-updates
# ─────────────────────────────────────────────
group_auto_updates() {
    print_header "Automatic Security Updates"
    echo -e "  ${CYAN}Enabling unattended security patches, kernel updates, CPU microcode, and firmware updates.${NC}\n"

    install_pkg "linux-image-amd64" "linux-image-amd64 (kernel meta-package)"
    install_pkg "intel-microcode" "Intel CPU microcode (security mitigations)"
    install_pkg "unattended-upgrades" "unattended-upgrades (auto security patches)"
    install_pkg "needrestart" "needrestart (reboot-needed notifier)"
    install_pkg "fwupd" "fwupd (firmware updater)"

    # Create /etc/apt/apt.conf.d/20auto-upgrades so the apt periodic timers actually fire
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades >>"$LOG_FILE" 2>&1 || true

    # Default 50unattended-upgrades only patches the -security pocket and Debian origins.
    # Extend to the stable -updates pocket and the VS Code repo (third-party origins are
    # excluded by default, so VS Code would otherwise never auto-update).
    local uu_extra="/etc/apt/apt.conf.d/52unattended-upgrades-extra"
    if [ ! -f "$uu_extra" ]; then
        print_info "Extending unattended-upgrades to cover -updates pocket and VS Code..."
        sudo tee "$uu_extra" > /dev/null << 'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-updates";
    "site=packages.microsoft.com";
};
EOF
        print_ok "unattended-upgrades extended"
    else
        print_skip "unattended-upgrades extra origins"
    fi

    # Installing fwupd doesn't auto-refresh metadata; the timer does
    if systemctl list-unit-files fwupd-refresh.timer &>/dev/null; then
        sudo systemctl enable --now fwupd-refresh.timer >>"$LOG_FILE" 2>&1 || true
        print_ok "Firmware metadata refresh timer enabled"
    fi

    # AppArmor ships enabled on Debian 13; only warn if it has been disabled
    if systemctl is-active apparmor &>/dev/null; then
        print_ok "AppArmor is active"
    else
        print_warning "AppArmor is not active — consider: sudo systemctl enable --now apparmor"
    fi
}

# ─────────────────────────────────────────────
# GROUP: desktop
# ─────────────────────────────────────────────
group_desktop() {
    print_header "Desktop Environment"
    echo -e "  ${CYAN}Installing the graphical desktop (XFCE), fonts, and window tiling.${NC}\n"

    install_pkgs "Xorg display server" xorg x11-xserver-utils
    install_pkgs "XFCE desktop environment" xfce4 xfce4-goodies && REBOOT_REQUIRED=true

    install_pkg "fonts-liberation" "Liberation fonts (Arial/Times/Courier replacements)"
    install_pkg "fonts-noto" "Noto fonts (broad Unicode coverage)"

    # Real window tiling — tile_on_move is the setting that snaps windows
    # to screen edges when dragged. wrap_windows is about workspace wrapping.
    xfconf_set -c xfwm4 -p /general/tile_on_move -s true --create -t bool
    xfconf_set -c xfwm4 -p /general/snap_to_border -s true --create -t bool
    xfconf_set -c xfwm4 -p /general/wrap_windows -s false --create -t bool
    print_ok "Window tiling enabled — drag windows to screen edges to snap them"

    # Some .desktop files declare Exec=...%F or %U, telling the launcher to pass
    # a file argument; launched from App Finder with no file selected they fail
    # silently. Write cleaned per-user copies that override the system ones.
    print_info "Cleaning app launchers for XFCE App Finder..."
    fix_desktop_launchers
}

# ─────────────────────────────────────────────
# GROUP: terminal
# ─────────────────────────────────────────────
group_terminal() {
    print_header "Terminal"
    echo -e "  ${CYAN}Installing a modern terminal with proper copy-paste support.${NC}\n"

    install_pkg "gnome-terminal" "GNOME Terminal"

    local bashrc="/etc/bash.bashrc"
    if ! grep -q "enable-bracketed-paste" "$bashrc"; then
        print_info "Fixing paste behavior in terminal (disabling bracketed paste mode)..."
        echo 'bind "set enable-bracketed-paste off"' | sudo tee -a "$bashrc" > /dev/null
        print_ok "Terminal paste fixed"
    else
        print_skip "Terminal paste fix already applied"
    fi
}

# ─────────────────────────────────────────────
# GROUP: apps-essential
# ─────────────────────────────────────────────
group_apps_essential() {
    print_header "Essential Applications"
    echo -e "  ${CYAN}Installing a browser, a text editor, and everyday file tools.${NC}\n"

    install_pkg "firefox-esr" "Firefox web browser"
    install_pkg "gedit" "gedit text editor"
    install_pkg "file-roller" "File Roller (archive manager)"
    install_pkg "gdebi" "gdebi (package installer)"
    install_pkg "poppler-utils" "poppler-utils (PDF command-line tools)"
    install_pkg "speech-dispatcher" "speech-dispatcher (text-to-speech)"
}

# ─────────────────────────────────────────────
# GROUP: apps-dev
# ─────────────────────────────────────────────
group_apps_dev() {
    print_header "Visual Studio Code"
    echo -e "  ${CYAN}Installing VS Code from Microsoft's official apt repository.${NC}\n"

    install_pkgs "VS Code prerequisites" wget gpg apt-transport-https

    local vscode_key="/usr/share/keyrings/packages.microsoft.gpg"
    local vscode_list="/etc/apt/sources.list.d/vscode.list"

    if [ ! -f "$vscode_key" ]; then
        print_info "Adding Microsoft GPG key..."
        if wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor 2>>"$LOG_FILE" \
            | sudo tee "$vscode_key" > /dev/null; then
            print_ok "Microsoft GPG key added"
        else
            print_fail "Microsoft GPG key"
            FAILED+=("Microsoft GPG key")
        fi
    else
        print_skip "Microsoft GPG key"
    fi

    if [ ! -f "$vscode_list" ]; then
        print_info "Adding VS Code apt repository..."
        echo "deb [arch=amd64,arm64,armhf signed-by=$vscode_key] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee "$vscode_list" > /dev/null
        sudo apt update -y >>"$LOG_FILE" 2>&1
        print_ok "VS Code repository added"
    else
        # VS Code's own updater can auto-create vscode.sources pointing to a different keyring,
        # which conflicts with our vscode.list and breaks all apt commands.
        if [ -f "/etc/apt/sources.list.d/vscode.sources" ]; then
            sudo rm /etc/apt/sources.list.d/vscode.sources >>"$LOG_FILE" 2>&1
        fi
        print_skip "VS Code repository"
    fi

    install_pkg "code" "Visual Studio Code"
}

# ─────────────────────────────────────────────
# GROUP: apps-media
# ─────────────────────────────────────────────
group_apps_media() {
    print_header "Media and Graphics"
    echo -e "  ${CYAN}Installing a media player, screenshot tool, and image editor.${NC}\n"

    install_pkg "vlc" "VLC media player"
    install_pkg "flameshot" "Flameshot (screenshot tool)"
    install_pkg "mtpaint" "mtPaint (simple image editor)"

    print_info "Configuring screenshot shortcut..."
    xfconf_set -c xfce4-keyboard-shortcuts -p '/commands/custom/<Primary><Alt>s' -s 'flameshot gui' --create -t string
    print_ok "Screenshot shortcut set to Ctrl+Alt+S (flameshot)"
}

# ─────────────────────────────────────────────
# GROUP: apps-office
# ─────────────────────────────────────────────
group_apps_office() {
    print_header "Office Suite"
    echo -e "  ${CYAN}Installing LibreOffice. This is a large download, roughly 300MB.${NC}\n"

    install_pkg "libreoffice" "LibreOffice (office suite)"
}

# ─────────────────────────────────────────────
# GROUP: print-scan
# ─────────────────────────────────────────────
group_print_scan() {
    print_header "Printing and Scanning"
    echo -e "  ${CYAN}Installing printer and scanner support.${NC}\n"

    install_pkg "cups" "CUPS printing system"
    install_pkg "sane-utils" "SANE (scanner support)"
    install_pkg "simple-scan" "Simple Scan (scanning app)"

    sudo systemctl enable cups >>"$LOG_FILE" 2>&1 || true
    sudo systemctl start cups >>"$LOG_FILE" 2>&1 || true
    print_ok "Printing service enabled"
}

# ─────────────────────────────────────────────
# GROUP: bluetooth
# ─────────────────────────────────────────────
group_bluetooth() {
    print_header "Bluetooth"
    echo -e "  ${CYAN}Installing a Bluetooth manager with a tray applet.${NC}\n"

    install_pkg "blueman" "Blueman (Bluetooth manager)"
}

# ─────────────────────────────────────────────
# GROUP: monitoring
# ─────────────────────────────────────────────
group_monitoring() {
    print_header "System Monitoring"
    echo -e "  ${CYAN}Installing tools to monitor CPU, RAM, and running processes.${NC}\n"

    install_pkg "xfce4-taskmanager" "XFCE Task Manager (like Activity Monitor)"
    install_pkg "htop" "htop (terminal process viewer)"
    install_pkg "fastfetch" "fastfetch (system info)"
}

# ─────────────────────────────────────────────
# GROUP: network-manager
# ─────────────────────────────────────────────
group_network_manager() {
    print_header "WiFi Management"
    echo -e "  ${CYAN}Switching from manual WiFi commands to automatic GUI-based management.${NC}\n"

    install_pkgs "NetworkManager" network-manager network-manager-gnome && REBOOT_REQUIRED=true

    if systemctl is-enabled wpa_supplicant &>/dev/null; then
        print_info "Disabling manual WiFi service (wpa_supplicant)..."
        sudo systemctl disable wpa_supplicant >>"$LOG_FILE" 2>&1 || true
        sudo systemctl stop wpa_supplicant >>"$LOG_FILE" 2>&1 || true
        print_ok "Manual WiFi service disabled"
    else
        print_skip "wpa_supplicant was not active"
    fi

    if systemctl is-enabled dhcpcd &>/dev/null; then
        print_info "Disabling manual IP service (dhcpcd)..."
        sudo systemctl disable dhcpcd >>"$LOG_FILE" 2>&1 || true
        sudo systemctl stop dhcpcd >>"$LOG_FILE" 2>&1 || true
        print_ok "Manual IP service disabled"
    else
        print_skip "dhcpcd was not active"
    fi

    local nm_conf="/etc/NetworkManager/NetworkManager.conf"
    if [ -f "$nm_conf" ] && grep -q "managed=false" "$nm_conf"; then
        print_info "Enabling NetworkManager to manage all interfaces..."
        sudo sed -i 's/managed=false/managed=true/' "$nm_conf"
        print_ok "NetworkManager set to manage all interfaces"
    else
        print_skip "NetworkManager already managing all interfaces"
    fi

    sudo systemctl enable NetworkManager >>"$LOG_FILE" 2>&1 || true
    sudo systemctl start NetworkManager >>"$LOG_FILE" 2>&1 || true
    print_ok "NetworkManager is running — WiFi will connect automatically on boot"
}

# ─────────────────────────────────────────────
# GROUP: keyboard
# ─────────────────────────────────────────────
group_keyboard() {
    print_header "MacBook Keyboard Fixes"
    echo -e "  ${CYAN}Remapping keys so your Mac keyboard works naturally on Linux.${NC}\n"

    install_pkg "keyd" "keyd (key remapper)" && REBOOT_REQUIRED=true
    install_pkg "brightness-udev" "brightness-udev (backlight permissions)" || true
    install_pkg "rofi" "rofi (window switcher for F3)"

    local keyd_conf="/etc/keyd/default.conf"
    if [ -f "$keyd_conf" ]; then
        print_info "Backing up existing keyboard config..."
        sudo cp "$keyd_conf" "$keyd_conf.bak"
        print_ok "Backup saved to $keyd_conf.bak"
    fi

    print_info "Writing keyboard configuration..."
    sudo mkdir -p /etc/keyd
    sudo tee "$keyd_conf" > /dev/null << EOF
[ids]
*

[main]
# Cmd key acts as Ctrl (Mac muscle memory)
meta = leftcontrol

# Cmd+Space / F4 opens XFCE app finder
meta+space = A-f2
dashboard = A-f2

# F3 - Mission Control equivalent (rofi window switcher)
scale = command(sh -c 'DISPLAY=:0 XAUTHORITY=$ACTUAL_HOME/.Xauthority rofi -show window -show-icons')

# Brightness keys (via sysfs)
brightnessdown = command(sh -c 'val=\$(cat /sys/class/backlight/intel_backlight/brightness); echo \$((val > 200 ? val - 200 : 100)) | tee /sys/class/backlight/intel_backlight/brightness')
brightnessup = command(sh -c 'val=\$(cat /sys/class/backlight/intel_backlight/brightness); echo \$((val + 200 > $MAX_BRIGHTNESS ? $MAX_BRIGHTNESS : val + 200)) | tee /sys/class/backlight/intel_backlight/brightness')

# Cmd+arrow text navigation (Mac style)
meta+left = home
meta+right = end
meta+up = C-home
meta+down = C-end
meta+shift+left = S-home
meta+shift+right = S-end
meta+shift+up = C-S-home
meta+shift+down = C-S-end
meta+backspace = S-home delete
EOF

    print_ok "Keyboard config written"

    sudo systemctl enable keyd >>"$LOG_FILE" 2>&1 || true
    sudo systemctl restart keyd >>"$LOG_FILE" 2>&1 || true
    print_ok "Keyboard remapping is active"

    echo -e "\n  ${CYAN}Key mappings applied:${NC}"
    echo -e "  • Cmd key now works as Ctrl"
    echo -e "  • Cmd+Space / F4 opens app finder"
    echo -e "  • F1/F2 controls screen brightness"
    echo -e "  • F3 opens window switcher"
    echo -e "  • F5/F6 controls keyboard backlight (via kernel)"
    echo -e "  • F7/F8/F9 controls media playback (via kernel)"
    echo -e "  • F10/F11/F12 controls volume (via kernel)"
    echo -e "  • Cmd+Left/Right jumps to start/end of line"
    echo -e "  • Cmd+Up/Down jumps to start/end of document\n"
}

# ─────────────────────────────────────────────
# GROUP: touchpad
# ─────────────────────────────────────────────
group_touchpad() {
    print_header "MacBook Touchpad Resume Fix"
    echo -e "  ${CYAN}Keeping the bcm5974 trackpad alive across lid-close and resume.${NC}\n"

    # The bcm5974 trackpad re-enumerates as a USB device on lid-open/resume. When it
    # reconnects, xfsettingsd replays stored xinput properties — and if it has a stale
    # Device_Enabled=0, it disables the trackpad before anything can re-enable it,
    # leaving a dead pad until reboot. Fix is two parts: clear the stored disabled
    # state, and add a sleep hook that force-enables the device after it settles.

    # 1. Stop XFCE from storing/replaying Device_Enabled=0
    xfconf_set -c pointers -p /bcm5974/Properties/Device_Enabled -s 1 --create -t int
    print_ok "Cleared any stale XFCE trackpad-disabled state"

    # 2. systemd sleep hook — re-enable the trackpad after resume
    print_info "Installing resume hook /etc/systemd/system-sleep/touchpad-resume..."
    sudo mkdir -p /etc/systemd/system-sleep
    sudo tee /etc/systemd/system-sleep/touchpad-resume > /dev/null << 'EOF'
#!/bin/sh
# Re-enable bcm5974 touchpad after resume.
# xfsettingsd replays stored xinput properties on device reconnect; if it has
# Device_Enabled=0 stored, it disables the touchpad before xorg.conf.d can
# re-enable it. This hook runs after the device settles and forces it back on.
[ "$1" = "post" ] && [ "$2" = "resume" ] || exit 0
sleep 2
XUSER=$(who | awk '/:0/{print $1; exit}')
[ -z "$XUSER" ] && exit 0
XAUTH="/home/$XUSER/.Xauthority"
su "$XUSER" -c "DISPLAY=:0 XAUTHORITY=$XAUTH xinput enable bcm5974" 2>/dev/null || true
EOF
    sudo chmod +x /etc/systemd/system-sleep/touchpad-resume
    print_ok "Trackpad will re-enable automatically after lid-open/resume"
}

# ─────────────────────────────────────────────
# GROUP: webcam
# ─────────────────────────────────────────────
group_webcam() {
    print_header "Webcam"
    echo -e "  ${CYAN}The MacBook FaceTime HD camera needs a custom driver — installing now.${NC}\n"

    # git clones both repos, curl fetches the firmware, cpio extracts it from
    # Apple's driver package, make/build-essential compile, dkms manages the
    # module. (alsa-utils used to ride along here from when the webcam and
    # microphone were one section — it belongs with the microphone.)
    install_pkgs "Build tools for webcam driver" git curl cpio make build-essential dkms

    local kernel_version
    kernel_version=$(uname -r)
    if ! dpkg -s "linux-headers-$kernel_version" &>/dev/null; then
        print_info "Installing kernel headers for $kernel_version..."
        if sudo apt install -y "linux-headers-$kernel_version" >>"$LOG_FILE" 2>&1; then
            print_ok "Kernel headers installed"
            INSTALLED+=("Kernel headers")
        else
            print_fail "Kernel headers — webcam driver may not work"
            FAILED+=("Kernel headers")
        fi
    else
        print_skip "Kernel headers"
        SKIPPED+=("Kernel headers")
    fi

    # FaceTime HD firmware — idempotent build
    if compgen -G "/lib/firmware/facetimehd/*" >/dev/null; then
        print_skip "FaceTime HD firmware"
        SKIPPED+=("FaceTime HD firmware")
    else
        print_info "Downloading and building FaceTime HD firmware (this may take a few minutes)..."
        if (
            set -e
            cd /tmp
            rm -rf facetimehd-firmware
            git clone https://github.com/patjak/facetimehd-firmware.git
            cd facetimehd-firmware
            make
            sudo make install
            cd /tmp
            rm -rf facetimehd-firmware
        ) >>"$LOG_FILE" 2>&1; then
            print_ok "FaceTime HD firmware installed"
            INSTALLED+=("FaceTime HD firmware")
        else
            print_fail "FaceTime HD firmware (see $LOG_FILE)"
            FAILED+=("FaceTime HD firmware")
        fi
    fi

    # FaceTime HD kernel module — idempotent DKMS build
    if find /lib/modules/$(uname -r) -name "facetimehd.ko*" 2>/dev/null | grep -q .; then
        print_skip "FaceTime HD webcam driver"
        SKIPPED+=("FaceTime HD webcam driver")
    else
        print_info "Building FaceTime HD kernel module..."
        if (
            set -e
            cd /tmp
            rm -rf facetimehd
            git clone https://github.com/patjak/facetimehd.git
            cd facetimehd
            FTHD_VERSION=$(grep "^PACKAGE_VERSION" dkms.conf | cut -d= -f2 | tr -d '"')
            sudo rm -rf "/usr/src/facetimehd-$FTHD_VERSION"
            sudo cp -r /tmp/facetimehd "/usr/src/facetimehd-$FTHD_VERSION"
            sudo dkms add -m facetimehd -v "$FTHD_VERSION" || true
            sudo dkms build -m facetimehd -v "$FTHD_VERSION"
            sudo dkms install -m facetimehd -v "$FTHD_VERSION"
            sudo depmod -a
            cd /tmp
            rm -rf facetimehd
        ) >>"$LOG_FILE" 2>&1; then
            print_ok "FaceTime HD webcam driver installed"
            INSTALLED+=("FaceTime HD webcam driver")
            REBOOT_REQUIRED=true
        else
            print_fail "FaceTime HD webcam driver (see $LOG_FILE)"
            FAILED+=("FaceTime HD webcam driver")
        fi
    fi

    if ! grep -q "facetimehd" /etc/modules-load.d/facetimehd.conf 2>/dev/null; then
        print_info "Configuring webcam to load automatically on boot..."
        echo "facetimehd" | sudo tee /etc/modules-load.d/facetimehd.conf > /dev/null
        print_ok "Webcam will load automatically on every boot"
        REBOOT_REQUIRED=true
    else
        print_skip "Webcam boot config already set"
    fi
}

# ─────────────────────────────────────────────
# GROUP: microphone
# ─────────────────────────────────────────────
# Separate from the webcam: different hardware, and this quirk is model-specific
# (mbp101), so it can be wrong on a MacBook the webcam driver handles fine.
group_microphone() {
    print_header "Microphone"
    echo -e "  ${CYAN}Applying the ALSA model quirk that makes the internal mic work.${NC}\n"

    # alsamixer and friends — the tools you need to unmute and verify the mic
    # once the quirk below is in place, so they belong with it.
    install_pkg "alsa-utils" "ALSA utilities (alsamixer, amixer)"

    if ! grep -q "options snd-hda-intel" /etc/modprobe.d/alsa-base.conf 2>/dev/null; then
        print_info "Configuring microphone for MacBook Air hardware..."
        echo "options snd-hda-intel model=mbp101" | sudo tee /etc/modprobe.d/alsa-base.conf > /dev/null
        print_ok "Microphone configured"
        REBOOT_REQUIRED=true
    else
        print_skip "Microphone already configured"
    fi
}

# ─────────────────────────────────────────────
# GROUP: power
# ─────────────────────────────────────────────
group_power() {
    print_header "Battery and Power Management"
    echo -e "  ${CYAN}Configuring power behavior (suspend + automatic hibernate).${NC}\n"

    # XFCE (user input layer) — only where XFCE will actually exist, so a
    # hardware-only install on a bare system doesn't drag in the whole desktop
    # just to set a lid preference. That means either the desktop group is part
    # of this run, or XFCE was already on the machine before it started: on an
    # existing desktop these packages are typically installed already, so this
    # applies the lid and lock configuration rather than skipping it.
    if is_enabled desktop || $XFCE_PREEXISTING; then
        install_pkg "xfce4-battery-plugin" "Battery indicator plugin"
        install_pkg "xfce4-power-manager" "Power manager"

        print_info "Configuring lid + screen lock, and delegating the lid to logind..."
        xfconf_set -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-ac -s 2 --create -t int
        xfconf_set -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-battery -s 2 --create -t int
        xfconf_set -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -s true --create -t bool
        # Hand the lid switch to systemd-logind: XFCE has no native suspend-then-hibernate
        # lid action, so we let logind own it. With this true, XFCE drops its lid inhibitor
        # and logind's HandleLidSwitch= (set below) takes over. The lid-action-* values
        # above then become inert fallbacks. See https://docs.xfce.org/xfce/xfce4-power-manager/faq
        xfconf_set -c xfce4-power-manager -p /xfce4-power-manager/logind-handle-lid-switch -s true --create -t bool
        print_ok "XFCE configured — lid handling delegated to logind"
    else
        print_info "Desktop group disabled — configuring the kernel and systemd layers only"
    fi

    # kernel (suspend mechanism layer)
    # Intel MacBooks (Broadwell, e.g. MacBookAir7,2) default to deep/S3 suspend,
    # which enters fine but never resumes — the machine is dead on lid-open until a
    # hard power-off. Force s2idle (suspend-to-idle), which resumes reliably on this
    # firmware. See https://github.com/basecamp/omarchy/issues/1840
    if ! grep -q "mem_sleep_default=s2idle" /etc/default/grub; then
        print_info "Forcing s2idle suspend via kernel parameter (deep/S3 won't resume on this hardware)..."
        sudo sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 mem_sleep_default=s2idle"/' /etc/default/grub
        sudo update-grub
        print_ok "Kernel set to s2idle suspend (takes full effect after reboot)"
        REBOOT_REQUIRED=true
    else
        print_skip "s2idle kernel parameter already set"
    fi

    # systemd (power policy layer)
    # MemorySleepMode=s2idle makes systemd write s2idle to /sys/power/mem_sleep on
    # every mem suspend, so the fix holds even before the next reboot / if GRUB is
    # regenerated without the param.
    print_info "Configuring systemd suspend-then-hibernate (s2idle)..."
    sudo mkdir -p /etc/systemd
    sudo tee /etc/systemd/sleep.conf > /dev/null << 'EOF'
[Sleep]
AllowSuspendThenHibernate=yes
HibernateDelaySec=30min
MemorySleepMode=s2idle
EOF
    print_ok "systemd configured — s2idle suspend → hibernate after 30 minutes"

    # logind (lid policy layer)
    # logind now owns the lid (see logind-handle-lid-switch above). suspend-then-
    # hibernate = s2idle first for fast resume, then hibernate to swap after
    # HibernateDelaySec — so a long/overnight close can't drain the battery flat and
    # lose work. logind-initiated lid actions bypass polkit, so the hibernate-blocking
    # rule below does not interfere. Applies on next reboot (no logind restart, which
    # would kill the session).
    print_info "Configuring logind: lid close → suspend-then-hibernate..."
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo tee /etc/systemd/logind.conf.d/10-lid.conf > /dev/null << 'EOF'
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
HandleLidSwitchDocked=ignore
EOF
    print_ok "logind configured — lid → suspend-then-hibernate (effective after reboot)"

    # polkit (authority / safety layer)
    print_info "Restricting user-space hibernate requests (XFCE)..."
    sudo mkdir -p /etc/polkit-1/rules.d
    sudo tee /etc/polkit-1/rules.d/50-disable-hibernate.rules > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate") {
        return polkit.Result.NO;
    }
});
EOF
    print_ok "Hibernate restricted to system-level control only"

    # sleep.conf is re-read by systemd-logind on demand, so no restart needed.
    # (Restarting systemd-logind can terminate the active user session.)
    print_ok "Power management changes will take effect after reboot"
}

# ─────────────────────────────────────────────
# GROUP: panel
# ─────────────────────────────────────────────
group_panel() {
    print_header "Panel Setup"
    echo -e "  ${CYAN}Scheduling a clean panel layout for first login.${NC}\n"

    # The volume plugin is a panel component, so it belongs to this group —
    # installing it with the media apps would leave a gap in the panel for
    # anyone who skips them.
    install_pkg "xfce4-pulseaudio-plugin" "PulseAudio volume plugin"

    # The layout below is built by clearing every existing panel item first,
    # which is right on the bare install this script was written for and wrong
    # on a machine that already had a desktop — that panel may have been
    # arranged deliberately, and replacing it would be silent data loss. So on a
    # pre-existing desktop it is left alone unless the group was asked for by
    # name, matching how --only treats an explicit request everywhere else.
    if $XFCE_PREEXISTING && ! is_requested panel; then
        print_warning "XFCE predates this run — leaving your existing panel layout alone"
        print_info "The clean layout replaces every item currently on your panel"
        print_info "To rebuild it anyway:  setup.sh --only panel"
        SKIPPED+=("Panel layout (existing desktop)")
        return 0
    fi
    if $XFCE_PREEXISTING; then
        print_warning "Rebuilding the panel as requested — your current layout will be replaced"
    fi

    local panel_setup_script="$ACTUAL_HOME/.local/bin/setup-panel-once.sh"
    local panel_marker="$ACTUAL_HOME/.local/share/panel-configured"

    mkdir -p "$ACTUAL_HOME/.local/bin"
    mkdir -p "$ACTUAL_HOME/.config/autostart"
    mkdir -p "$ACTUAL_HOME/.local/share"

    cat > "$panel_setup_script" << 'PANEL_SCRIPT'
#!/bin/bash
# One-shot: builds a clean panel layout on first XFCE login.
MARKER="$HOME/.local/share/panel-configured"
[ -f "$MARKER" ] && exit 0

# Wait up to 15 seconds for xfce4-panel to be running
for i in $(seq 1 15); do
    pgrep -x xfce4-panel > /dev/null && break
    sleep 1
done
pgrep -x xfce4-panel > /dev/null || exit 1

# Use docklike (icon-only window buttons) if installed, otherwise tasklist
if dpkg -s xfce4-docklike-plugin &>/dev/null; then
    WIN="docklike"
else
    WIN="tasklist"
fi

# Clear all existing plugin entries
while IFS= read -r id; do
    xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" -r -R 2>/dev/null || true
done < <(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | grep -oE '^[0-9]+$')

# Build the plugin list. Plugins whose package may not be installed (the setup
# script's groups are selectable) are added only when present — registering a
# missing plugin leaves a dead gap in the panel.
PLUGINS=(
    "applicationsmenu"   # app menu
    "separator:thin"
    "$WIN"               # open window icons
    "separator:expand"   # pushes the rest to the right
    "systray"            # nm-applet WiFi icon lives here
)
dpkg -s xfce4-pulseaudio-plugin &>/dev/null && PLUGINS+=("pulseaudio")
dpkg -s xfce4-battery-plugin   &>/dev/null && PLUGINS+=("battery")
PLUGINS+=("clock")

# Register each plugin with a sequential ID, then set the panel order to match
ID=1
ORDER=()
for spec in "${PLUGINS[@]}"; do
    xfconf-query -c xfce4-panel -p /plugins/plugin-$ID --create -t string -s "${spec%%:*}"
    case "$spec" in
        separator:thin)
            xfconf-query -c xfce4-panel -p /plugins/plugin-$ID/style  --create -t uint -s 0
            xfconf-query -c xfce4-panel -p /plugins/plugin-$ID/expand --create -t bool -s false
            ;;
        separator:expand)
            xfconf-query -c xfce4-panel -p /plugins/plugin-$ID/style  --create -t uint -s 0
            xfconf-query -c xfce4-panel -p /plugins/plugin-$ID/expand --create -t bool -s true
            ;;
        clock)
            xfconf-query -c xfce4-panel -p /plugins/plugin-$ID/digital-format \
                --create -t string -s "%Y-%m-%d  %H:%M"
            ;;
    esac
    ORDER+=(-t int -s "$ID")
    ID=$((ID + 1))
done

xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids --force-array "${ORDER[@]}"

# Ensure nm-applet is running (WiFi tray icon)
if command -v nm-applet > /dev/null 2>&1; then
    pgrep -x nm-applet > /dev/null || nm-applet &
fi

xfce4-panel --restart &
sleep 2

touch "$MARKER"
rm -f "$HOME/.config/autostart/setup-panel-once.desktop"
PANEL_SCRIPT

    chmod +x "$panel_setup_script"

    cat > "$ACTUAL_HOME/.config/autostart/setup-panel-once.desktop" << PANEL_DESKTOP
[Desktop Entry]
Type=Application
Name=Panel Setup (once)
Exec=$panel_setup_script
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
PANEL_DESKTOP

    if [ -f "$panel_marker" ]; then
        print_skip "Panel already configured"
    else
        print_ok "Panel setup scheduled — clean layout will apply on first login"
    fi
}

# ─────────────────────────────────────────────
# GROUP: desktop-shortcuts
# ─────────────────────────────────────────────
group_desktop_shortcuts() {
    print_header "Desktop Shortcuts"
    echo -e "  ${CYAN}Creating shortcuts on your Desktop so you can find everything easily.${NC}\n"

    mkdir -p "$DESKTOP_DIR"

    # create_shortcut skips anything whose program isn't installed, so this list
    # stays correct no matter which app groups were selected.
    create_shortcut "Firefox" "firefox-esr" "firefox-esr"
    create_shortcut "Files" "thunar" "file-manager"
    create_shortcut "Terminal" "gnome-terminal" "utilities-terminal"
    create_shortcut "Text Editor" "gedit" "gedit"
    create_shortcut "Simple Scan" "simple-scan" "scanner"
    create_shortcut "VLC" "vlc" "vlc"
    create_shortcut "Screenshot" "flameshot gui" "flameshot"
    create_shortcut "Bluetooth" "blueman-manager" "bluetooth"
    create_shortcut "Task Manager" "xfce4-taskmanager" "utilities-system-monitor"
    create_shortcut "System Settings" "xfce4-settings-manager" "preferences-system"
    create_shortcut "htop" "gnome-terminal -- htop" "utilities-system-monitor" "true"
    create_shortcut "System Info" "gnome-terminal -- fastfetch" "computer" "true"
    create_shortcut "LibreOffice Writer" "libreoffice --writer" "libreoffice-writer"
    create_shortcut "LibreOffice Calc" "libreoffice --calc" "libreoffice-calc"
    create_shortcut "LibreOffice Impress" "libreoffice --impress" "libreoffice-impress"
    create_shortcut "Image Editor" "mtpaint" "applications-graphics"
    create_shortcut "VS Code" "code" "code"

    cat > "$DESKTOP_DIR/KEYBOARD SHORTCUTS.txt" << 'SHORTCUTS'
═══════════════════════════════════════════════════════
  KEYBOARD SHORTCUTS — debian-intel-macbook-post-install
  Intel MacBooks · Debian 13 Trixie · XFCE
═══════════════════════════════════════════════════════

NOTE: On this setup, the Cmd key works as Ctrl.
      So Cmd+C = Ctrl+C, Cmd+V = Ctrl+V, etc.

      Shortcuts below assume the full install. If you ran
      setup.sh with a preset or --skip, the ones belonging
      to a skipped group will not be active.

───────────────────────────────────────────────────────
  GENERAL (works in most apps)
───────────────────────────────────────────────────────
  Cmd+C              Copy
  Cmd+V              Paste
  Cmd+X              Cut
  Cmd+Z              Undo
  Cmd+A              Select All
  Cmd+S              Save
  Cmd+F              Find
  Cmd+W              Close window
  Cmd+Q              Quit app
  Cmd+Tab            Switch between open apps

───────────────────────────────────────────────────────
  TEXT NAVIGATION
───────────────────────────────────────────────────────
  Cmd+Left           Jump to start of line
  Cmd+Right          Jump to end of line
  Cmd+Up             Jump to start of document
  Cmd+Down           Jump to end of document
  Cmd+Shift+Left     Select to start of line
  Cmd+Shift+Right    Select to end of line
  Cmd+Shift+Up       Select to start of document
  Cmd+Shift+Down     Select to end of document
  Cmd+Backspace      Delete entire line to left of cursor

───────────────────────────────────────────────────────
  DESKTOP AND WINDOWS
───────────────────────────────────────────────────────
  Cmd+Space          Open app finder (like Spotlight)
  Ctrl+Alt+D         Show desktop (hide all windows)
  Ctrl+Alt+L         Lock screen
  Ctrl+Alt+T         Open terminal
  Ctrl+Alt+F         Open file manager
  Alt+Tab            Switch between open windows
  Alt+Shift+Tab      Switch windows in reverse
  Alt+F4             Close window
  Alt+F10            Maximize window
  Alt+F9             Minimize window
  Alt+F11            Fullscreen

───────────────────────────────────────────────────────
  MAC-STYLE FUNCTION KEYS
───────────────────────────────────────────────────────
  F1                 Brightness down
  F2                 Brightness up
  F3                 Window switcher (like Mission Control)
  F4                 Open app finder (like Launchpad)
  F5                 Keyboard backlight down
  F6                 Keyboard backlight up
  F7                 Previous track
  F8                 Play / Pause
  F9                 Next track
  F10                Mute / Unmute
  F11                Volume down
  F12                Volume up
  Fn+F1-F12          Use as standard F1-F12 keys

───────────────────────────────────────────────────────
  SCREENSHOTS
───────────────────────────────────────────────────────
  Ctrl+Alt+S         Screenshot with annotation (flameshot)
  Print              Full screen screenshot (screenshooter)
  Shift+Print        Region screenshot (screenshooter)
  Alt+Print          Active window screenshot

───────────────────────────────────────────────────────
  SYSTEM
───────────────────────────────────────────────────────
  Ctrl+Shift+Esc     Open task manager
  Ctrl+Alt+Esc       Click a window to force quit it
  Ctrl+Alt+Delete    Log out / shutdown menu

───────────────────────────────────────────────────────
  WINDOW TILING (drag to edge OR use keys)
───────────────────────────────────────────────────────
  Drag to edge       Snap window to that half of screen
  Cmd+KP_Left        Tile window to left half
  Cmd+KP_Right       Tile window to right half
  Cmd+KP_Up          Tile window to top half
  Cmd+KP_Down        Tile window to bottom half

───────────────────────────────────────────────────────
  WORKSPACES (virtual desktops)
───────────────────────────────────────────────────────
  Ctrl+Alt+Left      Switch to left workspace
  Ctrl+Alt+Right     Switch to right workspace
  Ctrl+F1            Go to workspace 1
  Ctrl+F2            Go to workspace 2
  Ctrl+F3            Go to workspace 3
  Ctrl+F4            Go to workspace 4

───────────────────────────────────────────────────────
  DESKTOP ICONS (first time only)
───────────────────────────────────────────────────────
  When clicking a desktop icon for the first time,
  XFCE will ask "Untrusted application launcher" —
  click Launch to confirm. It won't ask again.

═══════════════════════════════════════════════════════
SHORTCUTS
    print_ok "Keyboard shortcuts cheat sheet saved to Desktop"
}

# ─────────────────────────────────────────────
# GROUP: system-upgrade
# ─────────────────────────────────────────────
# Runs last, after every DKMS driver (Broadcom wl, facetimehd) is already
# registered — so if this pulls a new kernel, its post-install triggers a DKMS
# rebuild of those drivers for the new kernel automatically. Upgrading earlier
# would leave the webcam driver built only for the old running kernel.
group_system_upgrade() {
    print_header "System Upgrade (optional)"

    # Simulate the upgrade to see if anything is actually pending. The package list
    # was refreshed earlier, so this reflects the current state. Count the package
    # actions (Inst = install/upgrade, Remv = remove) apt would perform.
    UPGRADE_COUNT=$(apt-get -s full-upgrade 2>/dev/null | grep -cE '^(Inst|Remv) ')

    if [ "$UPGRADE_COUNT" -eq 0 ]; then
        UPGRADE_STATE="current"
        echo -e "  ${CYAN}Every installed package is already at the latest Debian 13 point release.${NC}\n"
        print_ok "Nothing to upgrade"
        return 0
    fi

    echo -e "  ${CYAN}$UPGRADE_COUNT package(s) can be upgraded to the latest Debian 13 point release.${NC}\n"

    # Whether skipping this is actually safe depends on unattended-upgrades being
    # in place — which it is not if the auto-updates group was skipped. Check the
    # machine rather than assume, so the advice can't contradict reality.
    if dpkg -s unattended-upgrades &>/dev/null; then
        echo -e "  ${YELLOW}Safe to skip: security updates already install automatically via"
        echo -e "  unattended-upgrades.${NC}"
    else
        echo -e "  ${YELLOW}Note: unattended-upgrades is not installed, so security updates are NOT"
        echo -e "  applied automatically on this machine. Skipping this leaves the system"
        echo -e "  unpatched until you upgrade by hand.${NC}"
    fi
    echo -e "  ${YELLOW}A full upgrade can download a lot and may install a new kernel — the"
    echo -e "  Broadcom/webcam DKMS drivers rebuild for it automatically, but you must"
    echo -e "  reboot to use it.${NC}\n"

    read -p "$(echo -e ${BOLD}"  Run a full system upgrade now? [y/N] "${NC})" do_upgrade
    if [[ "$do_upgrade" =~ ^[Yy]$ ]]; then
        local running_kernel newest_kernel
        running_kernel=$(uname -r)
        print_info "Upgrading all packages (this can take a while)..."
        log "apt full-upgrade"
        if sudo apt full-upgrade -y >>"$LOG_FILE" 2>&1; then
            UPGRADE_STATE="upgraded"
            print_ok "System upgraded to the latest available packages"
            sudo apt autoremove -y >>"$LOG_FILE" 2>&1 || true
        else
            UPGRADE_STATE="failed"
            echo -e "${RED}  ✘ System upgrade failed — see $LOG_FILE${NC}"
        fi
        # A newer kernel only becomes active after a reboot; flag it so the reboot
        # prompt fires and the DKMS drivers run on the kernel you actually boot into.
        newest_kernel=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
        if [ -n "$newest_kernel" ] && [ "$newest_kernel" != "$running_kernel" ]; then
            REBOOT_REQUIRED=true
            print_warning "New kernel installed ($newest_kernel) — reboot to activate it,"
            print_warning "then verify WiFi and the webcam still work."
        fi
    else
        # Declined with updates pending: this machine is knowingly behind, so warn
        # (not a neutral skip) and hand over the one command to catch up later.
        UPGRADE_STATE="declined"
        print_warning "$UPGRADE_COUNT update(s) available but not applied"
        print_warning "Apply later with: sudo apt full-upgrade"
    fi
}

# ─────────────────────────────────────────────
# RUN THE SELECTED GROUPS
# ─────────────────────────────────────────────
for _group in "${GROUP_ORDER[@]}"; do
    if ! is_enabled "$_group"; then
        log "group skipped: $_group"
        continue
    fi
    log "group start: $_group"
    "group_${_group//-/_}"
    log "group done: $_group"
done

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
print_header "Installation Summary"

echo -e "${GREEN}${BOLD}  Installed (${#INSTALLED[@]})${NC}"
for item in "${INSTALLED[@]}"; do
    echo -e "  ${GREEN}✔ $item${NC}"
done

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}${BOLD}  Already installed, skipped (${#SKIPPED[@]})${NC}"
    for item in "${SKIPPED[@]}"; do
        echo -e "  ${YELLOW}⊘ $item${NC}"
    done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "\n${RED}${BOLD}  Failed (${#FAILED[@]})${NC}"
    for item in "${FAILED[@]}"; do
        echo -e "  ${RED}✘ $item${NC}"
    done
    echo -e "\n${RED}  Some items failed. Full details in: $LOG_FILE${NC}"
fi

# Groups turned off for this run — listed separately from the package tallies
# because "you chose not to install this" is different from "it was already there".
if [ ${#DISABLED_GROUPS[@]} -gt 0 ]; then
    echo -e "\n${CYAN}${BOLD}  Groups not selected (${#DISABLED_GROUPS[@]})${NC}"
    for item in "${DISABLED_GROUPS[@]}"; do
        echo -e "  ${CYAN}— $item${NC}"
    done
    echo -e "  ${CYAN}Add any of these later by re-running with: --only ${DISABLED_GROUPS[0]}${NC}"
fi

# System-currency status — rendered on its own, not lumped in with the package
# tallies, because "is this system up to date?" is a different question from
# "is this package installed?".
if is_enabled system-upgrade; then
    echo -e "\n${BOLD}  System status${NC}"
    case "$UPGRADE_STATE" in
        upgraded)
            echo -e "  ${GREEN}✔ System upgraded — $UPGRADE_COUNT package(s) updated this run${NC}"
            ;;
        declined)
            echo -e "  ${YELLOW}⚠ $UPGRADE_COUNT update(s) available — not applied${NC}"
            echo -e "  ${YELLOW}  Apply later with:  sudo apt full-upgrade${NC}"
            ;;
        failed)
            echo -e "  ${RED}✘ System upgrade failed — see the log below${NC}"
            echo -e "  ${RED}  Retry later with:  sudo apt full-upgrade${NC}"
            ;;
        *)
            echo -e "  ${GREEN}✔ Fully up to date${NC}"
            ;;
    esac
fi

echo -e "\n${CYAN}  Full log saved to: $LOG_FILE${NC}"

# ─────────────────────────────────────────────
# NEXT STEPS
# ─────────────────────────────────────────────
echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════${NC}"
if [ "$REBOOT_REQUIRED" = true ]; then
    echo -e "${BLUE}${BOLD}  All done! Just reboot when ready.${NC}"
else
    echo -e "${BLUE}${BOLD}  All done! Your MacBook is ready to use.${NC}"
fi
echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}\n"
if is_enabled panel; then
    echo -e "  ${CYAN}A clean panel (app menu, window icons, WiFi, volume, battery, clock) will appear on first login.${NC}"
fi
if is_enabled network-manager; then
    echo -e "  ${CYAN}Your saved WiFi password will be picked up automatically.${NC}"
fi
if is_enabled desktop-shortcuts; then
    echo -e "  ${CYAN}All your desktop shortcuts are ready on the Desktop.${NC}"
fi
echo ""

# ─────────────────────────────────────────────
# REBOOT
# ─────────────────────────────────────────────
echo -e "${BOLD}══════════════════════════════════════════${NC}"
if [ "$REBOOT_REQUIRED" = true ]; then
    echo -e "\n${YELLOW}  A reboot is required to apply all changes.${NC}\n"
    read -p "$(echo -e ${BOLD}"  Reboot now? [Y/n] "${NC})" reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Nn]$ ]]; then
        echo -e "\n${YELLOW}  Please reboot before using the desktop.${NC}\n"
    else
        echo -e "\n${GREEN}  Rebooting now — see you on the other side!${NC}\n"
        sudo reboot
    fi
else
    echo -e "\n${GREEN}  All done! No reboot needed — changes are already active.${NC}\n"
fi
