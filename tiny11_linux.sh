#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# tiny11_linux.sh — Native POSIX/Linux Windows 11 (24H2/25H2) Debloating & ISO Mastering Engine
#
# Direct offline WIM manipulation and registry injection with zero filesystem mounting.
# Dependencies: wimlib-imagex, hivexregedit, xorriso, 7z (or bsdtar)

set -euo pipefail
IFS=$'\n\t'

#=============================================================================
# Global Configuration & Defaults
#=============================================================================

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034
readonly SCRIPT_DIR
readonly REQUIRED_FREE_GB=25

SRC_ISO=""
OUTPUT_ISO=""
CUSTOM_SCRATCH=""
EDITION_INDEX=""
DRIVERS_DIR=""
NON_INTERACTIVE=false
SOLID_COMPRESSION=false
AUTO_INSTALL_DEPS=false
CHECK_DEPS_ONLY=false

TMP_WORK_DIR=""
CLEAN_EXIT=false
DETECTED_BUILD=0
DETECTED_ARCH="amd64"

#=============================================================================
# UI & Output Helpers
#=============================================================================

log_info() {
    printf "[\033[1;34mINFO\033[0m] %s\n" "$*"
}

log_ok() {
    printf "[\033[1;32m OK \033[0m] %s\n" "$*"
}

log_warn() {
    printf "[\033[1;33mWARN\033[0m] %s\n" "$*" >&2
}

log_error() {
    printf "[\033[1;31mFAIL\033[0m] %s\n" "$*" >&2
}

print_banner() {
    cat << 'EOF'
=================================================================
  Tiny11 Builder NG (Linux Native Toolchain) — 24H2/25H2 Ready   
=================================================================
  Offline WIM/Registry Manipulation | Zero FUSE/Kernel Mounts    
  Legacy BIOS (MBR) & Modern UEFI (GPT) Dual-Boot Support       
=================================================================
EOF
    echo ""
}

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  -i, --iso PATH            Path to source Windows 11 ISO file
  -o, --output PATH         Path for output ISO (default: ./tiny11_custom.iso)
  -s, --scratch DIR         Custom scratch directory (default: system tmp / cwd)
  -x, --index NUMBER        Image edition index to extract (e.g. 1, 2, 6)
  -d, --drivers DIR         Directory of custom .inf/.sys drivers to inject
                            (e.g. Panasonic Touchscreen, Wi-Fi, Intel HD Graphics)
  -y, --yes, --non-interactive
                            Run non-interactively, accepting defaults
      --solid               Use recovery/LZMS solid compression (smaller, slower)
      --auto-install-deps   Automatically install missing dependencies with sudo
      --check-deps          Verify toolchain dependencies and exit
  -h, --help                Show this help message and exit

Examples:
  $SCRIPT_NAME -i Win11_24H2_English_x64.iso -o tiny11_24H2.iso
  $SCRIPT_NAME -i Win11_24H2_x64.iso -d ./cf19_drivers -o tiny11_cf19.iso -x 1 -y
  $SCRIPT_NAME --check-deps

EOF
}

#=============================================================================
# Signal Trapping & Cleanup
#=============================================================================

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM ERR
    if [ -n "$TMP_WORK_DIR" ] && [ -d "$TMP_WORK_DIR" ]; then
        log_info "Cleaning up temporary scratch directory: $TMP_WORK_DIR"
        rm -rf "$TMP_WORK_DIR" || true
    fi
    if [ "$exit_code" -ne 0 ] && [ "$CLEAN_EXIT" = false ]; then
        log_error "Execution terminated prematurely (exit code: $exit_code)."
    fi
    exit "$exit_code"
}

trap cleanup EXIT INT TERM ERR

#=============================================================================
# Distro Sensing & Dependency Management
#=============================================================================

detect_distro_pm() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi

    case "$DISTRO_ID" in
        debian|ubuntu|devuan|linuxmint|pop|kali)
            PKG_MANAGER="apt"
            PKG_INSTALL_CMD="apt-get update && apt-get install -y wimtools libhivex-bin libwin-hivex-perl xorriso p7zip-full"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MANAGER="dnf"
            PKG_INSTALL_CMD="dnf install -y wimlib-utils perl-hivex xorriso p7zip p7zip-plugins"
            ;;
        arch|manjaro|endeavouros|artix)
            PKG_MANAGER="pacman"
            PKG_INSTALL_CMD="pacman -Sy --noconfirm wimlib hivex xorriso p7zip"
            ;;
        void)
            PKG_MANAGER="xbps"
            PKG_INSTALL_CMD="xbps-install -Sy wimlib hivex xorriso p7zip"
            ;;
        opensuse*|suse|sles)
            PKG_MANAGER="zypper"
            PKG_INSTALL_CMD="zypper install -y wimtools perl-Win-Hivex xorriso p7zip"
            ;;
        alpine)
            PKG_MANAGER="apk"
            PKG_INSTALL_CMD="apk add wimlib xorriso 7zip"
            ;;
        *)
            if echo "$DISTRO_LIKE" | grep -qi "debian"; then
                PKG_MANAGER="apt"
                PKG_INSTALL_CMD="apt-get update && apt-get install -y wimtools libhivex-bin libwin-hivex-perl xorriso p7zip-full"
            elif echo "$DISTRO_LIKE" | grep -qi "fedora\|rhel"; then
                PKG_MANAGER="dnf"
                PKG_INSTALL_CMD="dnf install -y wimlib-utils perl-hivex xorriso p7zip p7zip-plugins"
            elif echo "$DISTRO_LIKE" | grep -qi "arch"; then
                PKG_MANAGER="pacman"
                PKG_INSTALL_CMD="pacman -Sy --noconfirm wimlib hivex xorriso p7zip"
            else
                PKG_MANAGER="unknown"
                PKG_INSTALL_CMD="wimtools / wimlib, hivex / libwin-hivex-perl, xorriso, 7z (p7zip)"
            fi
            ;;
    esac
}

check_dependencies() {
    log_info "Verifying host toolchain dependencies..."
    local missing=()

    command -v wimlib-imagex >/dev/null 2>&1 || missing+=("wimlib-imagex (package: wimtools / wimlib-utils)")
    command -v hivexregedit >/dev/null 2>&1 || missing+=("hivexregedit (package: libwin-hivex-perl / perl-hivex / hivex)")
    command -v xorriso >/dev/null 2>&1 || missing+=("xorriso (package: xorriso)")
    
    if ! command -v 7z >/dev/null 2>&1 && ! command -v 7za >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
        missing+=("7z / 7za / bsdtar (package: p7zip-full / 7zip / libarchive-tools)")
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        log_ok "All required utilities are present (wimlib-imagex, hivexregedit, xorriso, 7z)."
        return 0
    fi

    log_warn "Missing required toolchain dependencies:"
    for item in "${missing[@]}"; do
        printf "  - %s\n" "$item"
    done

    detect_distro_pm

    if [ "$CHECK_DEPS_ONLY" = true ]; then
        printf "\nTo install dependencies on %s, run:\n  sudo %s\n" "$DISTRO_ID" "$PKG_INSTALL_CMD"
        CLEAN_EXIT=true
        exit 1
    fi

    if [ "$AUTO_INSTALL_DEPS" = true ] || [ "$NON_INTERACTIVE" = false ]; then
        local do_install=false
        if [ "$AUTO_INSTALL_DEPS" = true ]; then
            do_install=true
        else
            echo ""
            read -r -p "Would you like to auto-install missing packages now using sudo? [Y/n] " response
            case "$response" in
                [yY][eE][sS]|[yY]|"") do_install=true ;;
                *) do_install=false ;;
            esac
        fi

        if [ "$do_install" = true ]; then
            log_info "Attempting to install dependencies via $PKG_MANAGER..."
            if command -v sudo >/dev/null 2>&1; then
                eval "sudo $PKG_INSTALL_CMD"
            elif [ "$(id -u)" -eq 0 ]; then
                eval "$PKG_INSTALL_CMD"
            else
                log_error "Root privileges or sudo required to install packages."
                exit 1
            fi
            # Re-verify
            check_dependencies
            return 0
        fi
    fi

    log_error "Dependencies unsatisfied. Please install required packages manually:\n  sudo $PKG_INSTALL_CMD"
    exit 1
}

#=============================================================================
# Pre-Flight Disk Space & Scratch Setup
#=============================================================================

setup_scratch_space() {
    local target_base=""

    if [ -n "$CUSTOM_SCRATCH" ]; then
        target_base="$CUSTOM_SCRATCH"
    else
        target_base="$PWD"
    fi

    mkdir -p "$target_base"
    local free_gb
    free_gb="$(df -BG "$target_base" | awk 'NR==2 {gsub("G","",$4); print $4}')"

    if [ "$free_gb" -lt "$REQUIRED_FREE_GB" ]; then
        log_warn "Selected scratch path '$target_base' has only ${free_gb} GB free ($REQUIRED_FREE_GB GB required)."
        
        log_info "Scanning available filesystems with >= $REQUIRED_FREE_GB GB free..."
        local candidates=()
        while read -r line; do
            local mnt
            mnt="$(echo "$line" | awk '{print $6}')"
            local avail
            avail="$(echo "$line" | awk '{gsub("G","",$4); print $4}')"
            if [ -d "$mnt" ] && [ -w "$mnt" ] && [ "$avail" -ge "$REQUIRED_FREE_GB" ]; then
                candidates+=("$mnt (${avail} GB free)")
            fi
        done < <(df -BG -x tmpfs -x devtmpfs -x squashfs | awk 'NR>1')

        if [ ${#candidates[@]} -gt 0 ] && [ "$NON_INTERACTIVE" = false ]; then
            echo ""
            echo "Available directories with sufficient space:"
            for i in "${!candidates[@]}"; do
                printf "  [%d] %s\n" "$((i+1))" "${candidates[$i]}"
            done
            read -r -p "Select alternative mount point number [1-${#candidates[@]}]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#candidates[@]}" ]; then
                target_base="$(echo "${candidates[$((choice-1))]}" | awk '{print $1}')"
            fi
        else
            log_error "INSUFFICIENT DISK SPACE: No local volume has >= $REQUIRED_FREE_GB GB free space."
            exit 1
        fi
    fi

    TMP_WORK_DIR="$(mktemp -d -p "$target_base" tiny11_scratch_XXXXXX)"
    log_ok "Scratch directory initialized: $TMP_WORK_DIR (Available: ${free_gb} GB)"
}

#=============================================================================
# ISO Extraction & Inspection
#=============================================================================

extract_source_iso() {
    log_info "Extracting source ISO: $SRC_ISO"
    local iso_dir="$TMP_WORK_DIR/iso_files"
    mkdir -p "$iso_dir"

    if command -v 7z >/dev/null 2>&1; then
        7z x -bso0 -bsp0 -y -o"$iso_dir" "$SRC_ISO"
    elif command -v 7za >/dev/null 2>&1; then
        7za x -y -o"$iso_dir" "$SRC_ISO" >/dev/null
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$SRC_ISO" -C "$iso_dir"
    elif command -v xorriso >/dev/null 2>&1; then
        xorriso -osirx on -indev "$SRC_ISO" -extract / "$iso_dir" 2>/dev/null
    else
        log_error "No supported ISO extraction tool found."
        exit 1
    fi

    if [ ! -f "$iso_dir/sources/boot.wim" ]; then
        log_error "Invalid Windows installation media: sources/boot.wim missing."
        exit 1
    fi

    log_ok "Source ISO extracted successfully."
}

#=============================================================================
# WIM Edition Selection, Export & Build Sensing
#=============================================================================

process_wim_image() {
    local iso_dir="$TMP_WORK_DIR/iso_files"
    local src_image=""

    if [ -f "$iso_dir/sources/install.wim" ]; then
        src_image="$iso_dir/sources/install.wim"
    elif [ -f "$iso_dir/sources/install.esd" ]; then
        src_image="$iso_dir/sources/install.esd"
    else
        log_error "Neither install.wim nor install.esd found in source ISO."
        exit 1
    fi

    log_info "Inspecting editions in $src_image..."
    wimlib-imagex info "$src_image" | grep -E '^(Index|Name|Description):' || true

    local total_images
    total_images="$(wimlib-imagex info "$src_image" | grep -c '^Index:' || echo 1)"

    if [ -z "$EDITION_INDEX" ]; then
        if [ "$total_images" -eq 1 ] || [ "$NON_INTERACTIVE" = true ]; then
            EDITION_INDEX=1
            log_info "Defaulting to Image Index 1."
        else
            echo ""
            read -r -p "Enter edition index to customize [1-$total_images]: " chosen_idx
            EDITION_INDEX="${chosen_idx:-1}"
        fi
    fi

    log_info "Selected Edition Index: $EDITION_INDEX"

    # Export target image to clean install.wim
    local dest_wim="$TMP_WORK_DIR/install_clean.wim"
    local compress_flag="--compress=maximum"
    if [ "$SOLID_COMPRESSION" = true ]; then
        compress_flag="--compress=lzms:100"
    fi

    log_info "Exporting index $EDITION_INDEX to standalone install.wim ($compress_flag)..."
    wimlib-imagex export "$src_image" "$EDITION_INDEX" "$dest_wim" "$compress_flag" --check

    # Overwrite source in iso_dir
    rm -f "$iso_dir/sources/install.esd" "$iso_dir/sources/install.wim"
    mv "$dest_wim" "$iso_dir/sources/install.wim"

    # Determine Architecture & Build Version
    local wim_xml
    wim_xml="$(wimlib-imagex info "$iso_dir/sources/install.wim" 1 --xml || true)"
    
    local arch_raw
    arch_raw="$(echo "$wim_xml" | grep -i '<ARCH>' | head -n1 | sed -e 's/[<>/]//g' -e 's/ARCH//g' | tr -d '[:space:]' || echo "PROCESSOR_ARCHITECTURE_AMD64")"
    if echo "$arch_raw" | grep -qi "ARM64"; then
        DETECTED_ARCH="arm64"
    else
        DETECTED_ARCH="amd64"
    fi

    local build_raw
    build_raw="$(echo "$wim_xml" | grep -i '<BUILD>' | head -n1 | sed -e 's/[^0-9]//g' || echo 0)"
    if [ -n "$build_raw" ] && [ "$build_raw" -gt 0 ]; then
        DETECTED_BUILD="$build_raw"
    fi

    log_ok "Detected Architecture: $DETECTED_ARCH | Windows Build: $DETECTED_BUILD"

    # Hardware Compatibility Advisory
    echo ""
    if [ "$DETECTED_BUILD" -ge 26100 ]; then
        log_warn "================================================================="
        log_warn "  Windows 11 24H2/25H2 Detected (Build $DETECTED_BUILD)           "
        log_warn "  HARDWARE NOTICE: Kernel strictly requires SSE4.2 + POPCNT.     "
        log_warn "  - Supported: Intel Core i3/i5/i7 (1st Gen+) / CF-19 mk4 to mk8 "
        log_warn "  - Unsupported: Core 2 Duo / Quad / CF-19 mk1 to mk3            "
        log_warn "================================================================="
    else
        log_ok "================================================================="
        log_ok "  Windows 11 23H2 / 22H2 Detected (Build $DETECTED_BUILD)        "
        log_ok "  HARDWARE NOTICE: Fully compatible with Legacy BIOS, non-UEFI,  "
        log_ok "  and older Core 2 Duo / Core Duo hardware (CF-19 mk1 to mk8).  "
        log_ok "================================================================="
    fi
    echo ""
}

#=============================================================================
# Offline AppX & Bloatware Pruning (Zero-Mount wimlib update)
#=============================================================================

debloat_install_wim() {
    local install_wim="$TMP_WORK_DIR/iso_files/sources/install.wim"
    log_info "Pruning provisioned AppX bloatware and telemetry components..."

    local update_cmds="$TMP_WORK_DIR/wim_update_cmds.txt"
    cat << 'EOF' > "$update_cmds"
delete --force --recursive '/Program Files (x86)/Microsoft/Edge'
delete --force --recursive '/Program Files (x86)/Microsoft/EdgeUpdate'
delete --force --recursive '/Program Files (x86)/Microsoft/EdgeCore'
delete --force --recursive '/Windows/System32/OneDriveSetup.exe'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/Application Experience'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/Customer Experience Improvement Program'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/Autochk'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/Feedback'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/Flighting'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/Windows Error Reporting'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/Windows/UpdateOrchestrator/UpdateModelTask'
delete --force --recursive '/Windows/System32/Tasks/Microsoft/XblGameSave'
EOF

    local appx_prefixes=(
        "Clipchamp.Clipchamp"
        "Microsoft.BingNews"
        "Microsoft.BingSearch"
        "Microsoft.BingWeather"
        "Microsoft.Copilot"
        "Microsoft.Windows.Copilot"
        "Microsoft.Windows.AI.Copilot.Provider"
        "Microsoft.Windows.CrossDevice"
        "Microsoft.GamingApp"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MicrosoftStickyNotes"
        "Microsoft.MixedReality.Portal"
        "Microsoft.MSPaint"
        "Microsoft.Office.OneNote"
        "Microsoft.OfficePushNotificationUtility"
        "Microsoft.OutlookForWindows"
        "Microsoft.Paint"
        "Microsoft.People"
        "Microsoft.PowerAutomateDesktop"
        "Microsoft.SkypeApp"
        "Microsoft.StartExperiencesApp"
        "Microsoft.Todos"
        "Microsoft.Wallet"
        "Microsoft.Windows.DevHome"
        "Microsoft.Windows.Teams"
        "Microsoft.WindowsAlarms"
        "Microsoft.WindowsCamera"
        "microsoft.windowscommunicationsapps"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxApp"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.YourPhone"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "MicrosoftCorporationII.MicrosoftFamily"
        "MicrosoftCorporationII.QuickAssist"
        "MSTeams"
        "MicrosoftTeams"
        "Microsoft.549981C3F5F10"
        "MicrosoftWindows.Client.WebExperience"
        "LuminarNeo"
        "SpotifyAB.SpotifyMusic"
        "ByteDance.TikTok"
    )

    local wim_apps_list="$TMP_WORK_DIR/wim_apps.txt"
    wimlib-imagex dir "$install_wim" 1 --path="/Program Files/WindowsApps" 2>/dev/null > "$wim_apps_list" || true

    if [ -s "$wim_apps_list" ]; then
        for prefix in "${appx_prefixes[@]}"; do
            while read -r match; do
                if [ -n "$match" ]; then
                    echo "delete --force --recursive '/Program Files/WindowsApps/$match'" >> "$update_cmds"
                fi
            done < <(grep -i "^$prefix" "$wim_apps_list" || true)
        done
    fi

    wimlib-imagex update "$install_wim" 1 < "$update_cmds" >/dev/null 2>&1 || true
    log_ok "WIM directory pruning completed."
}

#=============================================================================
# Offline Binary Registry Tweaks (hivexregedit)
#=============================================================================

apply_registry_tweaks() {
    local install_wim="$TMP_WORK_DIR/iso_files/sources/install.wim"
    local hives_dir="$TMP_WORK_DIR/hives"
    mkdir -p "$hives_dir"

    log_info "Extracting registry hives from install.wim..."
    wimlib-imagex extract "$install_wim" 1 "/Windows/System32/config/SYSTEM" --dest-dir="$hives_dir" --no-acls
    wimlib-imagex extract "$install_wim" 1 "/Windows/System32/config/SOFTWARE" --dest-dir="$hives_dir" --no-acls
    wimlib-imagex extract "$install_wim" 1 "/Windows/System32/config/default" --dest-dir="$hives_dir" --no-acls
    wimlib-imagex extract "$install_wim" 1 "/Users/Default/ntuser.dat" --dest-dir="$hives_dir" --no-acls

    local sys_hive="$hives_dir/SYSTEM"
    local soft_hive="$hives_dir/SOFTWARE"
    local def_hive="$hives_dir/default"
    local ntu_hive="$hives_dir/ntuser.dat"

    log_info "Injecting Windows 11 registry bypasses, BitLocker blocks & optimizations..."

    # SYSTEM Hive Tweaks
    local sys_reg="$TMP_WORK_DIR/system_tweaks.reg"
    cat << 'EOF' > "$sys_reg"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\Setup\LabConfig]
"BypassCPUCheck"=dword:00000001
"BypassRAMCheck"=dword:00000001
"BypassSecureBootCheck"=dword:00000001
"BypassStorageCheck"=dword:00000001
"BypassTPMCheck"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\Setup\MoSetup]
"AllowUpgradesWithUnsupportedTPMOrCPU"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\BitLocker]
"PreventDeviceEncryption"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Lsa]
"RunAsPPL"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\DeviceGuard]
"EnableVirtualizationBasedSecurity"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\dmwappushservice]
"Start"=dword:00000004

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener]
"Start"=dword:00000000
EOF

    hivexregedit --merge --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' "$sys_hive" "$sys_reg"

    # SOFTWARE Hive Tweaks
    local soft_reg="$TMP_WORK_DIR/software_tweaks.reg"
    cat << 'EOF' > "$soft_reg"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE]
"BypassNRO"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsAI]
"TurnOffRecall"=dword:00000001
"DisableAIDataAnalysis"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot]
"TurnOffWindowsCopilot"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection]
"AllowTelemetry"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet]
"SpynetReporting"=dword:00000000
"SubmitSamplesConsent"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent]
"DisableWindowsConsumerFeatures"=dword:00000001
"DisableConsumerAccountStateContent"=dword:00000001
"DisableCloudOptimizedContent"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search]
"AllowCortana"=dword:00000000
"DisableWebSearch"=dword:00000001
"ConnectedSearchUseWeb"=dword:00000000
"PreventIndexingLowDiskSpaceMB"=dword:00000400
EOF

    hivexregedit --merge --prefix 'HKEY_LOCAL_MACHINE\SOFTWARE' "$soft_hive" "$soft_reg"

    # DEFAULT Hive Tweaks
    local def_reg="$TMP_WORK_DIR/default_tweaks.reg"
    cat << 'EOF' > "$def_reg"
Windows Registry Editor Version 5.00

[HKEY_USERS\.DEFAULT\Control Panel\UnsupportedHardwareNotificationCache]
"SV1"=dword:00000000
"SV2"=dword:00000000
EOF

    hivexregedit --merge --prefix 'HKEY_USERS\.DEFAULT' "$def_hive" "$def_reg"

    # NTUSER Hive Tweaks (Classic Context Menu, Compact Explorer, Left Taskbar)
    local ntu_reg="$TMP_WORK_DIR/ntuser_tweaks.reg"
    cat << 'EOF' > "$ntu_reg"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32]
@=""

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced]
"HideFileExt"=dword:00000000
"Hidden"=dword:00000001
"UseCompactMode"=dword:00000001
"TaskbarMn"=dword:00000000
"ShowSecondsInSystemClock"=dword:00000000

[HKEY_CURRENT_USER\Control Panel\UnsupportedHardwareNotificationCache]
"SV1"=dword:00000000
"SV2"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager]
"OemPreInstalledAppsEnabled"=dword:00000000
"PreInstalledAppsEnabled"=dword:00000000
"SilentInstalledAppsEnabled"=dword:00000000
"SubscribedContent-310093Enabled"=dword:00000000
"SystemPaneSuggestionsEnabled"=dword:00000000
EOF

    hivexregedit --merge --prefix 'HKEY_CURRENT_USER' "$ntu_hive" "$ntu_reg"

    log_info "Writing modified registry hives back into install.wim..."
    local readd_cmds="$TMP_WORK_DIR/readd_hives.txt"
    cat << EOF > "$readd_cmds"
add --force '$sys_hive' '/Windows/System32/config/SYSTEM'
add --force '$soft_hive' '/Windows/System32/config/SOFTWARE'
add --force '$def_hive' '/Windows/System32/config/default'
add --force '$ntu_hive' '/Users/Default/ntuser.dat'
EOF

    wimlib-imagex update "$install_wim" 1 < "$readd_cmds" >/dev/null
    log_ok "Registry tweaks applied successfully."
}

#=============================================================================
# SetupComplete.cmd, Drivers & Unattended Injections
#=============================================================================

inject_setup_scripts_and_unattend() {
    local install_wim="$TMP_WORK_DIR/iso_files/sources/install.wim"
    local iso_dir="$TMP_WORK_DIR/iso_files"

    log_info "Injecting first-boot optimization script (SetupComplete.cmd)..."
    local scripts_dir="$TMP_WORK_DIR/scripts"
    mkdir -p "$scripts_dir"
    local setup_complete="$scripts_dir/SetupComplete.cmd"

    cat << 'EOF' > "$setup_complete"
@echo off
:: Tiny11 First-Boot Automation Script
echo [Tiny11] Performing first-boot cleanup and driver configuration...

:: 1. Cleanly unregister removed AppX manifests for all users
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-AppxPackage -AllUsers | Where-Object { $_.Name -match '^(Microsoft\.Copilot|Microsoft\.Windows\.DevHome|Microsoft\.OutlookForWindows|Microsoft\.BingNews|Microsoft\.BingSearch|Microsoft\.BingWeather|Microsoft\.549981C3F5F10|Microsoft\.Todos|Microsoft\.YourPhone|Microsoft\.ZuneVideo|Microsoft\.ZuneMusic|Microsoft\.WindowsFeedbackHub|Microsoft\.GetHelp|Microsoft\.Getstarted|Microsoft\.Windows\.CrossDevice|MicrosoftWindows\.Client\.WebExperience|MSTeams|MicrosoftTeams|Microsoft\.GamingApp|Microsoft\.Xbox.*|Microsoft\.PowerAutomateDesktop|Clipchamp\.Clipchamp|ByteDance\.TikTok|SpotifyAB\.SpotifyMusic)' } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue" >nul 2>&1

:: 2. Low-Resource & Battery Optimizations (Reduce Hibernation file size by 50%)
powercfg.exe /hibernate /type reduced >nul 2>&1
powercfg.exe /setactive SCHEME_BALANCED >nul 2>&1

:: 3. Offline Staged Driver Installation (e.g. Panasonic Touchscreen, Wi-Fi, Intel HD)
if exist "C:\Windows\Setup\Drivers" (
    echo [Tiny11] Installing staged hardware drivers...
    pnputil.exe /add-driver "C:\Windows\Setup\Drivers\*.inf" /subdirs /install >nul 2>&1
)
EOF

    # Dynamic autounattend.xml generation
    local autounattend_file="$TMP_WORK_DIR/autounattend.xml"
    cat << EOF > "$autounattend_file"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="Microsoft-Windows-Setup" processorArchitecture="$DETECTED_ARCH" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DynamicUpdate>
                <WillShowUI>OnError</WillShowUI>
            </DynamicUpdate>
            <ImageInstall>
                <OSImage>
                    <Compact>true</Compact>
                    <WillShowUI>OnError</WillShowUI>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>1</Value>
                        </MetaData>
                    </InstallFrom>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey>
                    <Key/>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="Microsoft-Windows-Shell-Setup" processorArchitecture="$DETECTED_ARCH" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <ConfigureChatAutoInstall>false</ConfigureChatAutoInstall>
        </component>
    </settings>
</unattend>
EOF

    # Stage custom hardware drivers if provided
    local inject_cmds="$TMP_WORK_DIR/inject_cmds.txt"
    cat << EOF > "$inject_cmds"
add --force '$setup_complete' '/Windows/Setup/Scripts/SetupComplete.cmd'
add --force '$autounattend_file' '/Windows/System32/Sysprep/autounattend.xml'
EOF

    if [ -n "$DRIVERS_DIR" ] && [ -d "$DRIVERS_DIR" ]; then
        log_info "Staging custom hardware drivers from: $DRIVERS_DIR"
        echo "add --force '$DRIVERS_DIR' '/Windows/Setup/Drivers'" >> "$inject_cmds"
    fi

    wimlib-imagex update "$install_wim" 1 < "$inject_cmds" >/dev/null

    # Copy to ISO root
    cp "$autounattend_file" "$iso_dir/autounattend.xml"
    log_ok "Setup scripts, unattended answer file, and driver stages injected."
}

#=============================================================================
# boot.wim Setup WinPE LabConfig Injections
#=============================================================================

customize_boot_wim() {
    local boot_wim="$TMP_WORK_DIR/iso_files/sources/boot.wim"
    if [ ! -f "$boot_wim" ]; then return 0; fi

    log_info "Injecting hardware requirement bypasses into boot.wim..."
    local boot_hives="$TMP_WORK_DIR/boot_hives"
    mkdir -p "$boot_hives"

    local total_boot_images
    total_boot_images="$(wimlib-imagex info "$boot_wim" | grep -c '^Index:' || echo 1)"
    local setup_idx=2
    if [ "$total_boot_images" -eq 1 ]; then setup_idx=1; fi

    wimlib-imagex extract "$boot_wim" "$setup_idx" "/Windows/System32/config/SYSTEM" --dest-dir="$boot_hives" --no-acls

    local boot_sys="$boot_hives/SYSTEM"
    local boot_reg="$TMP_WORK_DIR/boot_tweaks.reg"
    cat << 'EOF' > "$boot_reg"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\Setup\LabConfig]
"BypassCPUCheck"=dword:00000001
"BypassRAMCheck"=dword:00000001
"BypassSecureBootCheck"=dword:00000001
"BypassStorageCheck"=dword:00000001
"BypassTPMCheck"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\Setup\MoSetup]
"AllowUpgradesWithUnsupportedTPMOrCPU"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\BitLocker]
"PreventDeviceEncryption"=dword:00000001
EOF

    hivexregedit --merge --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' "$boot_sys" "$boot_reg"

    wimlib-imagex update "$boot_wim" "$setup_idx" --command "add --force '$boot_sys' '/Windows/System32/config/SYSTEM'" >/dev/null
    log_ok "boot.wim customized with LabConfig bypasses."
}

#=============================================================================
# ISO Mastering (xorriso)
#=============================================================================

master_final_iso() {
    local iso_dir="$TMP_WORK_DIR/iso_files"
    local out_iso="${OUTPUT_ISO:-$PWD/tiny11_$(date +%Y%m%d).iso}"

    log_info "Mastering dual-mode UEFI/BIOS bootable ISO with xorriso..."

    local bios_boot="$iso_dir/boot/etfsboot.com"
    local efi_boot="$iso_dir/efi/microsoft/boot/efisys.bin"

    if [ ! -f "$bios_boot" ] || [ ! -f "$efi_boot" ]; then
        log_error "Required bootloader binaries missing from staging directory."
        exit 1
    fi

    # Build hybrid ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -udf \
        -volid "TINY11" \
        -b "boot/etfsboot.com" \
        -no-emul-boot \
        -boot-load-size 8 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e "efi/microsoft/boot/efisys.bin" \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -o "$out_iso" \
        "$iso_dir" 2>&1 | grep -v 'NOTE : ' || true

    if [ -f "$out_iso" ]; then
        local size_gb
        size_gb="$(du -h "$out_iso" | awk '{print $1}')"
        local sha_hash
        sha_hash="$(sha256sum "$out_iso" | awk '{print $1}')"
        echo ""
        log_ok "================================================================="
        log_ok "  Tiny11 ISO Created Successfully: $out_iso ($size_gb)"
        log_ok "  SHA256: $sha_hash"
        log_ok "================================================================="
        echo ""
        printf "\033[1;36m%s\033[0m\n" "── USB Burning Guide ───────────────────────────────────────────────"
        printf "  \033[1m• Legacy BIOS / Non-UEFI Target (e.g. Toughbook CF-19, CF-31, ThinkPad):\033[0m\n"
        printf "    - Rufus: Partition Scheme: \033[1;32mMBR\033[0m | Target: \033[1;32mBIOS (or UEFI-CSM)\033[0m | FS: NTFS\n"
        printf "    - Ventoy: Standard MBR installation\n"
        printf "  \033[1m• Modern UEFI Target:\033[0m\n"
        printf "    - Rufus: Partition Scheme: \033[1;32mGPT\033[0m | Target: \033[1;32mUEFI (non-CSM)\033[0m\n"
        printf "    - dd: sudo dd if=\"%s\" of=/dev/sdX bs=4M status=progress conv=fsync\n" "$out_iso"
        printf "\033[1;36m%s\033[0m\n\n" "────────────────────────────────────────────────────────────────────"
    else
        log_error "ISO generation failed."
        exit 1
    fi
}

#=============================================================================
# Main Entrypoint & CLI Parsing
#=============================================================================

main() {
    print_banner

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--iso)
                SRC_ISO="${2:-}"
                shift 2
                ;;
            -o|--output)
                OUTPUT_ISO="${2:-}"
                shift 2
                ;;
            -s|--scratch)
                CUSTOM_SCRATCH="${2:-}"
                shift 2
                ;;
            -x|--index)
                EDITION_INDEX="${2:-}"
                shift 2
                ;;
            -d|--drivers)
                DRIVERS_DIR="${2:-}"
                shift 2
                ;;
            -y|--yes|--non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --solid)
                SOLID_COMPRESSION=true
                shift
                ;;
            --auto-install-deps)
                AUTO_INSTALL_DEPS=true
                shift
                ;;
            --check-deps)
                CHECK_DEPS_ONLY=true
                shift
                ;;
            -h|--help)
                print_usage
                CLEAN_EXIT=true
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    check_dependencies
    if [ "$CHECK_DEPS_ONLY" = true ]; then
        CLEAN_EXIT=true
        exit 0
    fi

    # Interactive ISO selection if not provided
    if [ -z "$SRC_ISO" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            log_error "Source ISO must be specified in non-interactive mode via -i/--iso."
            exit 1
        fi
        read -r -e -p "Enter path to Windows 11 source ISO: " input_iso
        SRC_ISO="$(eval echo "$input_iso")"
    fi

    if [ ! -f "$SRC_ISO" ]; then
        log_error "Source ISO file does not exist: $SRC_ISO"
        exit 1
    fi

    setup_scratch_space
    extract_source_iso
    process_wim_image
    debloat_install_wim
    apply_registry_tweaks
    inject_setup_scripts_and_unattend
    customize_boot_wim
    master_final_iso

    CLEAN_EXIT=true
    log_ok "All tasks completed successfully."
}

main "$@"
