# Tiny11 Builder NG

<p align="center">
  <b>Hardened Dual-Platform (Windows & Linux) Debloating & ISO-Mastering Pipeline for Windows 11 (24H2 / 25H2 / 23H2)</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-GPL%203.0%2B-blue.svg" alt="License: GPL-3.0-or-later">
  <img src="https://img.shields.io/badge/Windows%2011-24H2%20%7C%2025H2%20%7C%2023H2-0078D6.svg?logo=windows" alt="Windows 11">
  <img src="https://img.shields.io/badge/Architecture-x64%20(AMD64)%20%7C%20ARM64-orange.svg" alt="Architecture: x64 / ARM64">
  <img src="https://img.shields.io/badge/Boot%20Modes-Legacy%20BIOS%20(MBR)%20%7C%20UEFI%20(GPT)-purple.svg" alt="Boot Modes">
  <img src="https://img.shields.io/badge/Linux%20Toolchain-100%25%20Rootless-success.svg?logo=linux" alt="Linux Rootless">
  <img src="https://img.shields.io/badge/ShellCheck-Passed-brightgreen.svg" alt="ShellCheck Passed">
</p>

---

## 📖 Overview

**Tiny11 Builder NG** is a modern, production-grade toolchain engineered to create trimmed-down, debloated, and optimized Windows 11 installation ISOs.

It features **two independent, fully featured platform engines**:
1. **Windows Native (`tiny11maker.ps1`):** Completely refactored PowerShell engine utilizing native DISM cmdlets, `.NET` garbage collection, retry-backed registry unloading, and embedded `oscdimg`.
2. **Linux Native (`tiny11_linux.sh`):** A **100% rootless**, zero-mount POSIX Bash pipeline utilizing `wimlib-imagex`, `hivexregedit`, and `xorriso` to manipulate WIM images and registry hives offline with zero kernel/FUSE mounts.

Both engines produce **Hybrid Dual-Boot ISOs** compatible with **Legacy BIOS (MBR)** systems (e.g. Panasonic Toughbook CF-19 / CF-31, older ThinkPads) and modern **UEFI (GPT)** systems.

---

## ⚡ Platform Engines Comparison

| Feature | Windows (`tiny11maker.ps1`) | Linux (`tiny11_linux.sh`) |
|---|---|---|
| **Runtime Requirements** | PowerShell 5.1 / PowerShell 7+ (Admin) | POSIX Bash + User-space utilities (Non-root) |
| **Mounting Mechanism** | DISM filesystem mounting (`scratchdir_install`) | **Zero-Mount** (Direct archive manipulation) |
| **Registry Editing** | `reg.exe load` + `Set-Item` / `Set-ItemProperty` | `hivexregedit --merge` (byte-level injection) |
| **ISO Mastering** | Embedded `oscdimg.exe` (ADK fallback) | `xorriso` (Hybrid UEFI/BIOS El Torito) |
| **Execution Privilege** | Elevated Administrator | **100% Unprivileged / Rootless** |
| **Target Architectures** | `amd64` (x64) and `arm64` | `amd64` (x64) and `arm64` |
| **Custom Driver Staging** | Yes (`-Drivers <path>`) | Yes (`-d, --drivers <path>`) |
| **Handling DISM Error 32** | GC Handle Reclamation + Retry Backoff | N/A (Zero-mount design eliminates locks) |

---

## ⚠️ Hardware & CPU Compatibility Guide (POPCNT Check)

Starting in Windows 11 **24H2**, the Windows NT kernel strictly enforces **`SSE4.2`** and **`POPCNT`** instructions. The script automatically senses the build version of your source ISO:

| Target Hardware | CPU Instruction Level | Windows 11 24H2 / 25H2 (Build 26100+) | Windows 11 23H2 (Build 22631) |
|---|---|---|---|
| **Modern UEFI PCs** (Intel 8th Gen+ / Ryzen 2000+) | SSE4.2 + POPCNT + AVX2 | ✅ **Supported natively** | ✅ **Supported** |
| **Older Core i-Series** (e.g. Toughbook CF-19 mk4–mk8 / ThinkPad X220/T430) | SSE4.2 + POPCNT (1st–7th Gen) | ✅ **Supported via LabConfig bypass** | ✅ **Supported** |
| **Legacy Core 2 Duo / Quad** (e.g. Toughbook CF-19 mk1–mk3 / ThinkPad X200/T61) | Lacks POPCNT | ❌ **Kernel Bugcheck (POPCNT Missing)** | ✅ **Fully Supported via LabConfig bypass** |

> [!TIP]
> * **For Core i3/i5/i7 laptops (including Toughbook CF-19 mk4 through mk8):** Use Windows 11 24H2 or 25H2 ISOs.
> * **For Core 2 Duo laptops (including Toughbook CF-19 mk1 through mk3):** Use a Windows 11 23H2 (Build 22631) ISO to bypass the POPCNT CPU requirement.

---

## 🐧 Linux Quick Start (`tiny11_linux.sh`)

The Linux engine requires **zero kernel drivers**, **zero root access**, and **zero loop mounts**. It reads and writes directly into WIM archives and registry hives.

### 1. Install Dependencies

```bash
# Debian / Ubuntu / Devuan / Linux Mint / Kali / Pop!_OS
sudo apt-get update && sudo apt-get install -y wimtools libhivex-bin libwin-hivex-perl xorriso p7zip-full

# Fedora / RHEL / CentOS Stream / Rocky Linux / AlmaLinux
sudo dnf install -y wimlib-utils perl-hivex xorriso p7zip p7zip-plugins

# Arch Linux / Manjaro / EndeavourOS
sudo pacman -Sy --noconfirm wimlib hivex xorriso p7zip

# Void Linux
sudo xbps-install -Sy wimlib hivex xorriso p7zip

# openSUSE / SLES
sudo zypper install -y wimtools perl-Win-Hivex xorriso p7zip

# Alpine Linux
apk add wimlib xorriso 7zip
```
*(Tip: Pass `--auto-install-deps` to let the script automatically detect and install dependencies for your distribution).*

### 2. Usage Examples

```bash
# Verify all toolchain dependencies
./tiny11_linux.sh --check-deps

# Interactive Guided Mode
./tiny11_linux.sh -i /path/to/Win11_24H2_English_x64.iso

# Headless / CI/CD Automation Mode
./tiny11_linux.sh \
  -i /path/to/Win11_24H2_English_x64.iso \
  -o ./tiny11_24H2.iso \
  -x 1 \
  -y

# Staging Custom Hardware Drivers (e.g. Panasonic Touchscreen / Wi-Fi)
./tiny11_linux.sh \
  -i Win11_24H2_x64.iso \
  -d /path/to/cf19_drivers \
  -o tiny11_cf19.iso \
  -x 1 -y
```

### CLI Reference (`tiny11_linux.sh`)

```
Options:
  -i, --iso PATH            Path to source Windows 11 ISO file
  -o, --output PATH         Path for destination ISO (default: ./tiny11_YYYYMMDD.iso)
  -s, --scratch DIR         Custom scratch directory (default: current directory or /tmp)
  -x, --index NUMBER        Windows edition index to extract (e.g. 1, 2, 6)
  -d, --drivers DIR         Directory of custom .inf/.sys drivers to inject
                            (e.g. Panasonic Touchscreen, Wi-Fi, Intel HD Graphics)
  -y, --yes, --non-interactive
                            Run non-interactively without confirmation prompts
      --solid               Use recovery/LZMS solid compression (smaller ISO, slower export)
      --auto-install-deps   Auto-install missing distro packages with sudo
      --check-deps          Inspect dependency status and exit
  -h, --help                Show help menu
```

---

## 🪟 Windows Quick Start (`tiny11maker.ps1`)

### 1. Mount Source Windows 11 ISO
Double-click your official Windows 11 ISO in Windows Explorer and note the drive letter (e.g. `E:`).

### 2. Launch PowerShell as Administrator
```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

### 3. Usage Examples

```powershell
# Interactive Mode
.\tiny11maker.ps1

# Headless / Parametric Mode
.\tiny11maker.ps1 -ISO E -SCRATCH D -Index 1

# Injecting Custom Hardware Drivers
.\tiny11maker.ps1 -ISO E -SCRATCH D -Drivers "C:\Drivers\CF19" -Index 1

# Maximum Solid Compression (LZMS)
.\tiny11maker.ps1 -ISO E -SCRATCH D -Index 1 -Solid
```

---

## 📦 What is Debloated & Hardened

### 1. Pruned Provisioned Packages (Modern 24H2/25H2)
* **Copilot & AI:** `Microsoft.Copilot`, `Microsoft.Windows.Copilot`, `Microsoft.Windows.AI.Copilot.Provider`
* **Bloatware & Preloaders:** `Clipchamp.Clipchamp`, `ByteDance.TikTok`, `SpotifyAB.SpotifyMusic`, `LuminarNeo`
* **MSN Feeds & Widgets:** `Microsoft.BingNews`, `Microsoft.BingSearch`, `Microsoft.BingWeather`, `MicrosoftWindows.Client.WebExperience`
* **Consumer Apps:** `Microsoft.OutlookForWindows`, `Microsoft.Todos`, `Microsoft.YourPhone`, `Microsoft.Windows.CrossDevice`, `Microsoft.WindowsFeedbackHub`, `Microsoft.GetHelp`, `Microsoft.Getstarted`, `MSTeams`, `MicrosoftTeams`, `Microsoft.Windows.Teams`
* **Xbox / Gaming Overlay:** `Microsoft.GamingApp`, `Microsoft.XboxApp`, `Microsoft.XboxGamingOverlay`, `Microsoft.XboxIdentityProvider`, `Microsoft.XboxTCUI`
* **Legacy Stubs:** `Microsoft.549981C3F5F10` (Cortana), `Microsoft.ZuneMusic`, `Microsoft.ZuneVideo`, `Microsoft.3DViewer`
* **Edge Browser:** Full Edge browser binaries, EdgeUpdate, and scheduled telemetry tasks removed (*core `WebView2` runtime preserved*).
* **OneDrive:** Setup preloader removed.

### 2. Retained Critical Components (Protected)
* ✅ **Microsoft Store** (`Microsoft.WindowsStore`, `Microsoft.StorePurchaseApp`, `Microsoft.DesktopAppInstaller`)
* ✅ **WebView2 Runtime** (prevents crashes in Winget, Store, and Settings)
* ✅ **.NET & Visual C++ Frameworks** (`Microsoft.VCLibs`, `Microsoft.UI.Xaml`)
* ✅ **Full International Language Packs & IMEs** (supports any language edition)

### 3. Injected Registry Bypasses & Optimizations
* **`LabConfig` Setup Bypasses:** `BypassTPMCheck=1`, `BypassSecureBootCheck=1`, `BypassRAMCheck=1`, `BypassCPUCheck=1`, `BypassStorageCheck=1`
* **OOBE Offline Account:** `BypassNRO=1` (enables local account setup without internet)
* **BitLocker Auto-Encryption Block:** `PreventDeviceEncryption=1` (prevents surprise drive locking during clean installs)
* **Recall & AI Telemetry:** `TurnOffRecall=1`, `DisableAIDataAnalysis=1`, `TurnOffWindowsCopilot=1`
* **Low-Resource & Battery Footprint:** Reduced hibernation file footprint (`powercfg /h /type reduced`, saving 2–4 GB on small SSDs), balanced power plan, compact Explorer view.
* **Telemetry & Spynet:** `AllowTelemetry=0`, `SpynetReporting=0`, `SubmitSamplesConsent=2`
* **Classic Context Menus:** Native classic Windows 10 style right-click context menus enabled out-of-the-box.

---

## 💾 Creating Installation Media (BIOS MBR vs UEFI GPT)

### 1. For Legacy BIOS / Non-UEFI Laptops (e.g. Toughbook CF-19 / CF-31, ThinkPads)
* **Rufus (Windows):**
  * **Partition scheme:** `MBR`
  * **Target system:** `BIOS (or UEFI-CSM)`
  * **File system:** `NTFS`
* **Ventoy (Windows / Linux):**
  * Install Ventoy to USB using `Partition Style: MBR`. Copy the ISO directly to the USB.

### 2. For Modern UEFI Systems
* **Rufus (Windows):**
  * **Partition scheme:** `GPT`
  * **Target system:** `UEFI (non-CSM)`
* **dd / Etcher (Linux):**
  ```bash
  sudo dd if=tiny11_custom.iso of=/dev/sdX bs=4M status=progress conv=fsync
  ```

---

## 📄 License

GNU General Public License v3.0 or later ([GPL-3.0-or-later](LICENSE)).
