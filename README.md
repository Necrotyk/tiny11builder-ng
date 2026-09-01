# Tiny11 Builder NG (Dual-Platform Windows & Linux 24H2/25H2 Pipeline)

A hardened, automated, and dual-platform toolchain to build streamlined, debloated, and optimized Windows 11 installation ISOs.

Supports **Windows 11 24H2 and 25H2** releases across both **x64 (`amd64`)** and **ARM64 (`arm64`)** architectures.

---

## ⚡ Platform Engines

| Platform | Script | Toolchain / Mechanism | Root / Admin Privileges |
|---|---|---|---|
| **Windows** | `tiny11maker.ps1` | Native PowerShell + DISM cmdlets + Embedded `oscdimg` | Elevated Administrator |
| **Linux / POSIX** | `tiny11_linux.sh` | Zero-Mount `wimlib-imagex` + `hivexregedit` + `xorriso` | **100% Rootless** (user-space) |

---

## ⚠️ Windows 11 24H2+ Hardware Notice

> **Important CPU Instruction Requirement:**
> Starting in Windows 11 24H2, the Windows NT kernel (`ntoskrnl.exe`) strictly enforces **`SSE4.2`** and **`POPCNT`** instructions.
>
> While `LabConfig` registry bypasses (`BypassTPMCheck`, `BypassCPUCheck`, `BypassRAMCheck`, `BypassSecureBootCheck`, `BypassStorageCheck`, `BypassNRO`) allow installation on unsupported generation CPUs (e.g. Intel 7th Gen, AMD 1st Gen Zen), CPUs lacking hardware `POPCNT` instructions (such as Core 2 Duo / Quad) will bugcheck (`BlockedExecutionDueToPOPCNTMissing`) and cannot boot Windows 11 24H2+.

---

## 🚀 Linux Quick Start (`tiny11_linux.sh`)

The Linux toolchain performs **direct byte-level offline WIM and registry manipulation** without requiring root access, loop mounts, or FUSE filesystems.

### 1. Install Dependencies
```bash
# Debian / Ubuntu / Devuan
sudo apt-get update && sudo apt-get install -y wimtools libhivex-bin libwin-hivex-perl xorriso p7zip-full

# Fedora / RHEL / Rocky Linux
sudo dnf install -y wimlib-utils perl-hivex xorriso p7zip p7zip-plugins

# Arch Linux / Manjaro
sudo pacman -Sy --noconfirm wimlib hivex xorriso p7zip

# Void Linux
sudo xbps-install -Sy wimlib hivex xorriso p7zip

# openSUSE / SLES
sudo zypper install -y wimtools perl-Win-Hivex xorriso p7zip

# Alpine Linux
apk add wimlib xorriso 7zip
```
*(Or let `tiny11_linux.sh --auto-install-deps` automatically detect and install dependencies for you).*

### 2. Run the Builder
```bash
# Verify dependencies
./tiny11_linux.sh --check-deps

# Interactive Mode
./tiny11_linux.sh -i /path/to/Win11_24H2_English_x64.iso

# Automated / Headless Mode
./tiny11_linux.sh \
  -i /path/to/Win11_24H2_English_x64.iso \
  -o ./tiny11_24H2.iso \
  -x 1 \
  -y
```

### Linux CLI Flags:
```
Options:
  -i, --iso PATH            Path to source Windows 11 ISO file
  -o, --output PATH         Path for output ISO (default: ./tiny11_custom.iso)
  -s, --scratch DIR         Custom scratch directory (default: system tmp / cwd)
  -x, --index NUMBER        Image edition index to extract (e.g. 1, 2, 6)
  -y, --yes, --non-interactive
                            Run non-interactively, accepting defaults
      --solid               Use recovery/LZMS solid compression (smaller, slower)
      --auto-install-deps   Automatically install missing dependencies with sudo
      --check-deps          Verify toolchain dependencies and exit
  -h, --help                Show help menu
```

---

## 🪟 Windows Quick Start (`tiny11maker.ps1`)

### 1. Mount Windows 11 ISO
Mount your official Windows 11 ISO in Windows Explorer (note the assigned drive letter, e.g. `E:`).

### 2. Run PowerShell as Administrator
```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

### 3. Build Image
```powershell
# Interactive Mode
.\tiny11maker.ps1

# Headless / Parametric Mode
.\tiny11maker.ps1 -ISO E -SCRATCH D -Index 1

# Maximum Solid Compression (LZMS)
.\tiny11maker.ps1 -ISO E -SCRATCH D -Index 1 -Solid
```

### Windows Key Improvements in NG:
- **DISM Parameter Binding Fix:** Resolves `NamedParameterNotFound` by using `-Path` instead of `-Image` across all feature cmdlets.
- **Nameless Registry Key Fix:** Properly sets default registry values (`Set-Item -Path $tweak.Path -Value $tweak.Value -Force`) preventing `EmptyStringNotAllowed` crashes.
- **Garbage Collection & Retry Hive Unloading:** Automatic `.NET` GC collection and retry loop for `reg.exe unload` preventing `DISM Error 32` file locking.
- **Isolated Mount Directories:** Uses distinct `$ScratchDisk\scratchdir_install` and `$ScratchDisk\scratchdir_boot` mount points.
- **Intelligent Scratch Auto-Discovery:** Automatically scans fixed drives for $\ge 25\text{ GB}$ capacity and prompts user when default disk lacks space.

---

## 📦 What is Debloated & Hardened

### 1. Removed Provisioned Apps
* **Copilot & AI:** `Microsoft.Copilot`, `Microsoft.Windows.Copilot`, `Microsoft.Windows.AI.Copilot.Provider`
* **Bloatware & Preloads:** `Clipchamp.Clipchamp`, `ByteDance.TikTok`, `SpotifyAB.SpotifyMusic`, `LuminarNeo`
* **MSN Feeds & Widgets:** `Microsoft.BingNews`, `Microsoft.BingSearch`, `Microsoft.BingWeather`, `MicrosoftWindows.Client.WebExperience`
* **Consumer Apps:** `Microsoft.OutlookForWindows`, `Microsoft.Todos`, `Microsoft.YourPhone`, `Microsoft.Windows.CrossDevice`, `Microsoft.WindowsFeedbackHub`, `Microsoft.GetHelp`, `Microsoft.Getstarted`, `MSTeams`, `MicrosoftTeams`, `Microsoft.Windows.Teams`
* **Xbox / Gaming Overlay:** `Microsoft.GamingApp`, `Microsoft.XboxApp`, `Microsoft.XboxGamingOverlay`, `Microsoft.XboxIdentityProvider`, `Microsoft.XboxTCUI`
* **Legacy Stubs:** `Microsoft.549981C3F5F10` (Cortana), `Microsoft.ZuneMusic`, `Microsoft.ZuneVideo`, `Microsoft.3DViewer`
* **Edge Browser:** Full Edge browser binaries, EdgeUpdate, and scheduled telemetry tasks removed (*core `WebView2` runtime preserved to ensure Microsoft Store, Winget, and modern dialogs function without crashes*).
* **OneDrive:** Setup preloader removed.

### 2. Retained Critical Components (Protected)
* ✅ **Microsoft Store** (`Microsoft.WindowsStore`, `Microsoft.StorePurchaseApp`, `Microsoft.DesktopAppInstaller`)
* ✅ **WebView2 Runtime**
* ✅ **.NET & Visual C++ Runtimes** (`Microsoft.VCLibs`, `Microsoft.UI.Xaml`)
* ✅ **Full International Language Packs & IMEs**

### 3. Injected Registry Bypasses & Optimizations
* **`LabConfig` Setup Bypasses:** `BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck`, `BypassStorageCheck`
* **OOBE Offline Account:** `BypassNRO=1` (enables local account setup without Microsoft Account)
* **BitLocker Auto-Encryption Block:** `PreventDeviceEncryption=1` (prevents surprise drive locking during clean installs)
* **Recall & AI Telemetry:** `TurnOffRecall=1`, `DisableAIDataAnalysis=1`, `TurnOffWindowsCopilot=1`
* **Telemetry & Spynet:** `AllowTelemetry=0`, `SpynetReporting=0`, `SubmitSamplesConsent=2`
* **Classic Context Menus:** Native classic Windows 10 style right-click context menus enabled by default.

---

## 📄 License

GNU General Public License v3.0 or later (GPL-3.0-or-later).
