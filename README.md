# 📦 Remote App Uninstaller — WPF GUI for Windows Application Management

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-FFDD00?style=for-the-badge)](https://www.buymeacoffee.com/mabdulkadrx)

A modern **WPF-based GUI tool** for browsing, inspecting, exporting, and silently uninstalling applications from local or remote Windows machines. Reads installed apps from the registry, provides real-time filtering and detailed property inspection, and runs uninstalls in a background job with automatic silent-switch detection and leftover cleanup.

---

## 🚀 Features

### Application Inventory
- **Local & remote inventory** — reads installed apps from both 64-bit and 32-bit (WOW6432Node) `HKLM:\...\Uninstall` registry keys
- **WinRM remote access** — remote inventory via `Invoke-Command` with ICMP connectivity pre-check
- **Auto-load on startup** — local machine inventoried automatically after the window appears

### Live Sidebar
- **Target device card** — shows connectivity status (Connected / Offline), device name, IP address, logged-on user, and OS version
- **Target badge** — switches between "This PC" (blue) and "Remote" (orange)
- **Last activity** — displays the most recent operation result

### Stats Dashboard
- **Total apps** — count of all installed applications
- **MSI count** — Windows Installer packages
- **EXE / Other** — non-MSI installers
- **Selected** — currently highlighted apps

### Search & Details
- **Real-time filtering** — case-insensitive regex search across Name, Publisher, and Version
- **Detail pane** — full properties for selected app(s): Publisher, Version, InstallDate, UninstallString, Product Code, Architecture, Scope, Registry Key, and more
- **Multi-select comparison** — compact side-by-side view when multiple apps are selected
- **Clipboard copy** — copy individual fields, entire rows, or use Ctrl+C in the details grid

### Silent Uninstall Engine
- **Auto-detection** — identifies installer type (MSI, Inno Setup, NSIS, Wise, InstallShield, generic EXE)
- **Silent switches** — appends correct flags: `/quiet /norestart` for MSI, `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` for Inno/NSIS, `/S` for generic EXEs
- **Background job** — uninstall runs via `Start-Job` so the UI stays responsive with a live progress bar
- **WinGet fallback** — if the traditional uninstall fails, `winget uninstall --silent` is attempted automatically

### Leftover Cleanup
- **Registry** — removes leftover Uninstall keys matching the app name
- **Program Files** — deletes matching folders under `C:\Program Files` and `C:\Program Files (x86)`
- **Start Menu** — removes matching shortcuts and folders for all users
- **AppData** — purges matching executables, shortcuts, and folders under each user profile

### Export
- **CSV export** — saves the currently filtered app list via a `SaveFileDialog` with auto-generated filename

---

## 📋 Requirements

| Requirement | Details |
|---|---|
| **OS** | Windows 7+ |
| **PowerShell** | Windows PowerShell 5.1+ with WPF (.NET Framework) |
| **Local usage** | Normal user rights for inventory; local admin may be needed for some uninstalls |
| **Remote usage** | WinRM enabled on target (`winrm quickconfig`), firewall rule open, administrative rights. Workgroup targets may require TrustedHosts or CredSSP |
| **Optional** | Winget CLI for fallback uninstall |

---

## ▶️ Usage

```powershell
.\RemoteAppUninstaller.ps1
```

Or bypass execution policy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RemoteAppUninstaller.ps1
```

### Steps

1. **Launch** — a WPF window opens and auto-inventories the local machine
2. **Remote target** — type a computer name or IP in the sidebar and press Enter (or click "Load Applications")
3. **Search** — type in the search box to filter the app list instantly
4. **Select** — click one app to view full details; Ctrl+click for multi-select
5. **Export** — click "Export to CSV" to save the filtered list
6. **Uninstall** — select apps and click "Uninstall Selected". Confirm the dialog, then the job runs in the background. Live output streams to the Message Center; a summary dialog appears on completion

---

## 🏗️ Architecture

```
RemoteAppUninstaller.ps1    (2,700+ lines, self-contained)
├── Assemblies & Globals        — WPF & WinForms references, script-scoped state
├── XAML (Main Window)          — inline WPF layout (2 parts, ~700 lines)
├── XAML Loader                 — safe XamlReader with XML validation
├── Control Binding             — fail-fast FindName for all named controls
├── Target Helpers              — Is-LocalTarget, Test-TargetReachable
├── Session Info                — sidebar device card rendering
├── UI Invoke Helpers           — thread-safe dispatcher wrapper
├── Logger                      — color-coded Message Center output
├── Stats Cards                 — live Total/MSI/EXE/Selected counts
├── Details Panes               — full property grid + multi-select comparison
├── Collection View & Filter    — regex-based real-time search
├── Get-InstalledApps           — registry inventory engine (local + WinRM)
├── Confirmation Dialog         — modal uninstall confirmation
├── Uninstall ScriptBlock       — background job: silent uninstall, verification, cleanup
├── Job Polling                 — DispatcherTimer for live progress & summary
├── Button Handlers             — Load, Refresh, Uninstall, Export event wiring
├── UI Events                   — search, selection, context menu, copy, resize
└── Init & Show Window          — session setup, auto-load timer, message pump
```

---

## 🧠 Message Center Log Levels

Color-coded output displayed in the Message Center:

| Level | Color | Use |
|---|---|---|
| `INFO` | Grey-blue | General operations |
| `DETAIL` | Light blue | Workflow and connectivity details |
| `RESULT` | Blue | Success results |
| `WARN` | Yellow | Non-fatal warnings |
| `ERROR` | Red | Failures |
| `SUMMARY` | Green | Uninstall job summaries |

---

## 📜 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 👤 Author

**Mohammad Abdulkader Omar**  
Website: https://momar.tech  
Version: **1.0**

---

## ⚠ Disclaimer

This script is provided as-is. Test it in a staging environment before applying it to production. The author is not responsible for any unintended outcomes resulting from its use.
