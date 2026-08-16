# 📦 Remote App Uninstaller — WPF GUI for Windows Application Management

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![Version](https://img.shields.io/badge/version-1.1-green.svg)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-FFDD00?style=for-the-badge)](https://www.buymeacoffee.com/mabdulkadrx)

A modern **WPF-based GUI tool** for browsing, inspecting, exporting, and silently uninstalling applications from local or remote Windows machines. It reads the installed-app inventory from the registry (64-bit and 32-bit views), provides real-time filtering, a full property inspector, and runs uninstalls in background jobs with automatic silent-switch detection, WinGet fallback, and leftover cleanup.

---

## ⚡ Quick Start

```powershell
.\RemoteAppUninstaller.ps1
```

Or bypass the execution policy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\RemoteAppUninstaller.ps1
```

The window opens empty. Click **Load This PC Apps** (local) or **Load Applications** (local or remote) to inventory a machine.

---

## 🚀 Feature Highlights

### Application Inventory
- **Local & remote inventory** — reads installed apps from both registry views:
  - `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
  - `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`
- **WinRM remote access** — remote inventory via `Invoke-Command` with an ICMP connectivity pre-check (`Test-Connection`)
- **Load on demand, never freezes** — inventory runs in a `Start-Job` background job; the UI shows an indeterminate progress overlay until it finishes
- **Auto refresh** — the app list reloads automatically after uninstall jobs finish

### Live Sidebar (Target Device Card)
- **Connectivity status** — Connected (green) / Offline (red) indicator dot
- **Target badge** — switches between **This PC** (blue) and **Remote** (orange)
- **System info** — device name, IP address, logged-on user, and OS version (queried locally or via WinRM)
- **Last activity** — the most recent operation result is shown at the bottom of the sidebar

### Stats Dashboard
Live counters updated on every selection change:

| Card | Meaning |
|---|---|
| **TOTAL** | All installed applications |
| **MSI** | Windows Installer packages |
| **EXE / OTHER** | Non-MSI installers |
| **SELECTED** | Currently highlighted apps |

### Search & Filtering
- **Real-time filtering** — case-insensitive regex search across **Name**, **Publisher**, and **Version**
- Search box is cleared with the **Clear** button

### Details Inspector
- **Full property grid** — select an app to see Publisher, Version, InstallDate, Language, UninstallString, Product Code, Architecture, Scope, Registry Key, Upgrade Code, and ~30 more fields (empty fields are hidden)
- **Multi-select comparison** — compact side-by-side key fields when more than one app is selected
- **Clipboard copy** — copy a single field/value via context menu, or copy a full row via double-click / `Ctrl+C`

### Silent Uninstall Engine
- **Auto-detection** — identifies the installer type (MSI, Inno Setup, NSIS, Wise, InstallShield, generic EXE)
- **Silent switches** — appends the correct flags for each type (see [Silent Switch Mapping](#silent-switch-mapping))
- **Safe execution** — uninstall commands are split into executable + arguments and run without a shell to avoid shell injection
- **Concurrent background jobs** — each batch uninstalls via `Start-Job`; multiple jobs can run simultaneously, each with its own live progress row
- **Per-job progress & Stop** — every job row shows its own progress bar/count and a **Stop** button
- **Verification** — after uninstall, the registry is re-checked to confirm removal
- **WinGet fallback** — if the traditional uninstall fails, `winget uninstall --silent` is attempted automatically

### Leftover Cleanup (best-effort, always attempted)
| Location | What is removed |
|---|---|
| Registry | Leftover `HKLM\...\Uninstall` keys whose `DisplayName` matches |
| Program Files | Matching folders under `C:\Program Files` and `C:\Program Files (x86)` |
| Start Menu | Matching shortcuts/folders (All Users + every user profile) |
| AppData | Matching `.exe`/`.lnk` files and folders under each user profile |

### Export
- **CSV export** — saves the currently **filtered** app list via a `SaveFileDialog`, with an auto-generated filename (`<device>-<timestamp>-apps.csv`)

---

## 🖥️ UI Walkthrough

```
┌───────────────────────────┬──────────────────────────────────────────────┐
│  LEFT SIDEBAR             │  MAIN CONTENT                                │
│                           │  Application Manager          (Header)      │
│  ▪ Brand / title          │  ┌──────┬──────┬───────┬──────┐              │
│  ▪ NAVIGATION             │  │Total │  MSI │EXE/OTR│Selected│  Stats     │
│    • Applications         │  └──────┴──────┴───────┴──────┘              │
│  ▪ TARGET DEVICE          │                                              │
│    • Target badge         │  ┌──────────────────┬─────────────────────┐  │
│    • PC name text box     │  │ Installed Apps   │ Application Details │  │
│    • Load Applications    │  │ [search] [Clear] │ Field | Value       │  │
│    • Load This PC Apps    │  │ ─────────────────│ (full property grid │  │
│  ▪ SYSTEM INFO            │  │ # Name Ver. Pub. │  or compact         │  │
│    • Device / IP / User   │  │ ...              │  comparison)        │  │
│    • OS + status badge    │  │ ...              │                     │  │
│  ▪ LAST ACTIVITY          │  ├──────────────────┴─────────────────────┤  │
│  ▪ Footer (author)        │  │ [Reload] [Export to CSV] [Uninstall]   │  │
│                           │  │ [▓▓ progress ] 0/5 + per-job rows      │  │
│                           ├──────────────────────────────────────────┤  │
│                           │  MESSAGE CENTER  (dark console) [Copy][Clear]│
└───────────────────────────┴──────────────────────────────────────────────┘
```

### Control Reference

| Control | Behavior |
|---|---|
| **PCNameBox** | Type a computer name/IP, or leave empty for the local machine. `Enter` triggers a load. |
| **Load Applications** | Inventory the target from the box (local if empty). |
| **Load This PC Apps** | Inventory the local machine only. |
| **Reload Apps** | Re-inventory the current target (shows "Reloading..."). |
| **Export to CSV** | Save the currently filtered list to CSV. |
| **Uninstall Selected** | Opens the confirmation dialog, then launches a background uninstall job. |
| **SearchBox / Clear** | Live regex filter + reset. |
| **Copy / Clear (Message Center)** | Copy all output to clipboard / wipe the log view. |
| **Stop (per job)** | Cancels a running uninstall job. |

---

## 🏗️ Architecture

The entire tool is a **self-contained single script** (`RemoteAppUninstaller.ps1`, ~3,300 lines) that renders its UI from inline XAML. The script runs entirely in-process: no external modules, no config files, no installer.

### Execution Model

```
PowerShell (STA) ──► WPF Window (Dispatcher)
   │
   ├── LoadJob (Start-Job)      ──► writes to %TEMP%\...\load-<ts>.log
   │                                  └─ LoadTimer (300 ms) polls file → streams to Message Center
   │
   └── UninstallJob xN (Start-Job) ─► writes to %TEMP%\...\uninstall-<id>-<ts>.log
                                          └─ DispatcherTimer polls jobs → per-job progress rows, Stop buttons
```

Background jobs cannot return partial output while running on PowerShell 5.1, so every job **appends its log lines to a live log file** that the UI polls with a timer — this is what makes output stream in real time.

### Code Regions (in file order)

| # | Region | Purpose |
|---|---|---|
| 01 | **ASSEMBLIES & GLOBALS** | WPF/WinForms references, script-scoped state, temp log dir |
| 02 | **XAML — MAIN WINDOW** | Window, sidebar, stats cards, button styles |
| 03 | **XAML — MAIN WINDOW (Part 2)** | Apps list, details pane, Message Center, job panels |
| 04 | **XAML LOADER (SAFE)** | `Load-XamlWindowSafe` — validates & loads XAML with descriptive errors |
| 05 | **CONTROL BINDING (SAFE)** | `Get-ControlOrFail` — fail-fast `FindName` for named controls |
| 06 | **TARGET HELPERS** | `Is-LocalTarget` — local vs remote detection |
| 07 | **FOOTER LINK (OPTIONAL)** | LinkedIn hyperlink handler |
| 08 | **SESSION INFO (SIDEBAR)** | Target badge, device card, OS/IP/user rendering |
| 09 | **UI INVOKE HELPERS** | `Invoke-Ui` — thread-safe dispatcher wrapper |
| 10 | **LOGGER** | `Update-Output` — color-coded Message Center output |
| 11 | **LAST ACTION (OPTIONAL)** | `Set-LastAction` — sidebar activity line |
| 12 | **STATS (CARDS)** | `Update-Stats` — live Total/MSI/EXE/Selected counts |
| 13 | **DETAILS PANES** | Full property grid + multi-select comparison + copy helpers |
| 14 | **COLLECTION VIEW + FILTER** | `Set-AppList` / `Update-Filter` — CollectionView regex filtering |
| 15 | **GET-INSTALLEDAPPS** | Shared registry inventory scriptblock (local + WinRM) |
| 16 | **BACKGROUND INVENTORY LOAD** | `Start-LoadApps` + `LoadTimer` — background load streamed to Message Center |
| 17 | **CONFIRMATION DIALOG** | Modal "Confirm Uninstall" window |
| 18 | **UNINSTALL SCRIPTBLOCK** | Background job: silent uninstall, verification, cleanup |
| 19 | **JOB POLLING** | `New-JobRow` / `Start-UninstallJob` + DispatcherTimer |
| 20 | **BUTTON HANDLERS** | Load / Load This PC / Refresh / Uninstall / Export |
| 21 | **UI EVENTS** | Search, selection, context menu, copy, resize, Enter-to-load |
| 22 | **INIT + SHOW WINDOW** | Session setup, initial state, WPF message pump |

### Core Functions Reference

| Function | Location | Purpose |
|---|---|---|
| `Load-XamlWindowSafe` | #04 | Parses XAML text into a WPF object graph |
| `Get-ControlOrFail` | #05 | Finds a named control or throws |
| `Is-LocalTarget` | #06 | Returns `$true` for `.`, `localhost`, or this computer |
| `Update-Sidebar` / `Set-SessionInfo` | #08 | Renders the device card + status badge |
| `Invoke-Ui` | #09 | Marshals work onto the WPF dispatcher thread |
| `Update-Output` | #10 | Appends a color-coded line to the Message Center |
| `Update-Stats` | #12 | Recomputes dashboard counters |
| `Update-Details` | #13 | Renders the details grid / comparison view |
| `Copy-ListProperty` / `Copy-ListRow` | #13 | Clipboard helpers |
| `Set-AppList` | #14 | Binds the ListView, resets filter & details |
| `Update-Filter` | #14 | Applies/clears the regex filter |
| `$GetRegistryAppsSb` | #15 | Registry → app objects (shared local/remote) |
| `Start-LoadApps` | #16 | Launches the background inventory job |
| `Show-UninstallConfirmation` | #17 | Modal confirmation dialog (returns bool) |
| `$UninstallScriptBlock` | #18 | Full uninstall orchestration job |
| `New-JobRow` / `Start-UninstallJob` | #19 | Per-job UI row + job registration |

---

## 📊 Data Model (Registry → App Object)

For every registry subkey with a `DisplayName`, the inventory produces an object with these properties:

| Property | Source registry value |
|---|---|
| `Name` | `DisplayName` |
| `Publisher` | `Publisher` |
| `Version` | `DisplayVersion` |
| `InstallDate` | `InstallDate` |
| `UninstallString` | `UninstallString` (normalized: `/i {guid}` → `/x {guid}`) |
| `QuietUninstallString` | `QuietUninstallString` |
| `ModifyPath` / `RepairPath` | `ModifyPath` / `RepairPath` |
| `InstallLocation` / `InstallSource` | `InstallLocation` / `InstallSource` |
| `InstallSize` / `EstimatedSize` | `InstallSize` / `EstimatedSize` |
| `DisplayIcon` | `DisplayIcon` |
| `RegistryKey` | Registry `PSPath` |
| `ProductCode` | `ProductCode` (falls back to the key name if it is a `{GUID}`) |
| `UpgradeCode` | `UpgradeCode` |
| `URLInfoAbout` / `HelpLink` | `URLInfoAbout` / `HelpLink` |
| `ReleaseType` | `ReleaseType` |
| `ParentDisplayName` / `ParentKeyName` | `ParentDisplayName` / `ParentKeyName` |
| `SystemComponent` / `WindowsInstaller` | `SystemComponent` / `WindowsInstaller` |
| `Comments` / `Contact` / `Readme` | `Comments` / `Contact` / `Readme` |
| `LanguageCode` | `Language` (mapped to a friendly name in the UI) |
| `InstallerType` | Derived: `MSI` if `UninstallString` contains `msiexec`, else `EXE/Other` |
| `Architecture` | Derived: `x86` (WOW6432Node) or `x64` |
| `Scope` | Always `Machine` |
| `Index` | 1-based list numbering |

---

## 🔧 Uninstall Engine

### Silent Switch Mapping

| Installer | Detection | Switches appended |
|---|---|---|
| **MSI** | `msiexec` in the uninstall string | `/x <product-code> /quiet /norestart` (or convert `/i {guid}` → `/x {guid}`, then add `/quiet /norestart` if missing) |
| **Inno / NSIS / Wise / InstallShield** | `unins*.exe` in the path | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| **Generic EXE** | `.exe` and no silent flag already present | `/S` |

The command is then split (`Split-UninstallCommand`) into its executable and argument parts and launched with `Start-Process` — never through a shell.

### Per-App Removal Pipeline (`Remove-Application`)

1. **Reachability** — for remote targets, a quick ping check (skip unreachable hosts).
2. **Stop processes & services** — matching process name/description and service name/display name are force-stopped (remote runs capped at 45 s).
3. **Run uninstall** — silent switches applied, command split, run hidden with `-Wait`.
   - **Remote:** the uninstaller runs via `Invoke-Command -AsJob` while the job polls `Test-AppStillInstalled` every 15 s for up to **4 minutes** (an Inno uninstaller often lingers after removal, so "gone from remote registry" counts as success). Elevation and exit codes are surfaced in the log.
4. **Verify** — the registry is re-checked for a matching `DisplayName` on the target.
5. **WinGet fallback** — if still installed, runs:
   `winget uninstall --name "<name>" --exact --silent --accept-source-agreements --accept-package-agreements`
6. **Leftover cleanup** — registry keys, Program Files folders, Start Menu entries, and AppData remnants are removed (best-effort).

### Job Result Object

Each app produces `{ App, Status, Note, Details[] }` where `Status` is `Success` or `Failed`. A batch summary is logged, and the UI shows a summary line with the success/failure breakdown.

---

## 🧵 Job System & Concurrency

- **Inventory load** — a single `$Global:LoadJob` at a time; the UI disables load/refresh/uninstall buttons and shows the spinner while it runs.
- **Uninstall jobs** — fully concurrent. `$Global:UninstallJobs` maps job id → state; `$Global:NextJobId` increments per job. Each job row (`New-JobRow`) contains:
  - `Job #<id> - <target>` label
  - Per-job `ProgressBar` (max = app count)
  - Count text (`done/total`)
  - Red **Stop** button (calls `Stop-Job`)
- **Progress protocol** — the uninstall job emits explicit `[PROGRESS] done/total` lines that drive the progress bars.
- **Completion** — when all jobs finish, the app list refreshes automatically and a summary is written to the Message Center.

---

## 🧾 Logging & Message Center

The dark console at the bottom of the window streams everything. Log levels are color-coded:

| Level | Color | Use |
|---|---|---|
| `INFO` | Grey-blue | General operations |
| `DETAIL` | Light blue | Workflow and connectivity details |
| `RESULT` | Blue | Success results |
| `WARN` | Yellow | Non-fatal warnings |
| `ERROR` | Red | Failures |
| `SUMMARY` | Green | Uninstall job summaries |

**Raw log files** are also written to:

```
%TEMP%\RemoteAppUninstaller-Logs\
├── load-<yyyyMMddHHmmss>.log        (inventory)
└── uninstall-<id>-<yyyyMMddHHmmss>.log   (each uninstall job)
```

The Message Center has **Copy** and **Clear** buttons; the stream is font `Cascadia Code / Consolas` on a dark background.

---

## 🎨 Design System (UI)

| Token | Value |
|---|---|
| Font | Segoe UI |
| Window | 1360 × 860 (min 1000 × 600), centered |
| **Button radius** | 5 px (uniform across all button styles) |
| Card radius | 8 px |
| Input / small element radius | 6 px |
| Primary button | `#4338CA` on white |
| Secondary button | `#F1F5F9` / `#CBD5E1` border |
| Danger button | `#DC2626` |
| Nav / ghost | `#EEF2FF` → `#E0E7FF` on hover |
| Hover overlay | `#16000000` (hover), `#2B000000` (pressed) — fills the **entire** button |
| Cursor | Hand on all interactive elements |

Button styles: `BtnBase`, `BtnPrimary`, `BtnSecondary`, `BtnDanger`, `BtnNav`, `BtnGhost`, `BtnDarkGhost`, `DlgBtn*`. Buttons use lightweight custom `ControlTemplate`s — no default WPF chrome.

---

## ⌨️ Keyboard & Mouse

- `Enter` in the PC-name box → **Load Applications**
- `Ctrl+C` on a details row → copies `Field: Value`
- Double-click on a details row → copies `Field: Value`
- Right-click a details row → **Copy Field** / **Copy Value**
- `Ctrl+click` in the app list → multi-select (comparison view)

---

## 📋 Requirements

| Requirement | Details |
|---|---|
| **OS** | Windows 7+ |
| **PowerShell** | Windows PowerShell 5.1+ with WPF (.NET Framework) — run from a PowerShell console or the compiled EXE |
| **Local usage** | Normal user rights for inventory; admin may be required for some uninstalls |
| **Remote usage** | WinRM enabled on target (`winrm quickconfig`), remote management firewall rule open, admin rights on target |
| **Workgroup targets** | May require `TrustedHosts` or CredSSP configuration |
| **Optional** | WinGet CLI for the fallback uninstall |

### Remote Setup Checklist

```powershell
# On the target computer (as admin):
winrm quickconfig

# On the source computer (workgroup / non-domain, one-time):
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "target1,target2" -Force
```

---

## 🔍 Troubleshooting

| Symptom | Fix |
|---|---|
| Script blocked by execution policy | `powershell.exe -ExecutionPolicy Bypass -File .\RemoteAppUninstaller.ps1` |
| Remote load reports unreachable | Check ICMP (firewall), then `Test-WSMan <host>` |
| WinRM access denied / not enabled | `winrm quickconfig` on the target + open the firewall rule |
| Uninstall of Program Files apps fails remotely | Ensure the remote WinRM session is elevated |
| No output while loading | Wait — output streams via the live log file; check `%TEMP%\RemoteAppUninstaller-Logs\` |
| GUI "freezes" on remote uninstall | It shouldn't; everything runs in jobs. If it seems slow, watch the per-job progress rows |
| `UninstallString` empty | The app may not expose one; the tool logs a warning and still attempts cleanup |

---

## 📁 File Reference

| File | Size | Description |
|---|---|---|
| **`RemoteAppUninstaller.ps1`** | ~148 KB | The complete application source: WPF XAML, UI logic, inventory engine, uninstall engine, job system (self-contained, ~3,300 lines) |
| **`RemoteAppUninstaller.exe`** | ~182 KB | Compiled launcher (no console window) — convenient double-click entry point |
| **`delete.png`** | ~12 KB | Icon resource referenced by the packaged executable |
| **`README.md`** | — | This documentation |

---

## 🕑 Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-08-05 | Initial release |
| 1.1 | 2026-08-16 | Full overhaul — see [changelog](#11-2026-08-16) below |

### 1.1 — 2026-08-16

**Reliability / bug fixes**

- Fixed GUI crash **"Error formatting a string: Format specifier was invalid"** — `[math]::Floor()` returns doubles, which break the `{0:d2}` time format (`working 0:08`, `Still working on X (elapsed 1:35)...`). Values are now cast to `[int]` before formatting.
- Fixed apps being reported **Failed even though they were actually removed** — `Test-AppStillInstalled` used `return` inside `ForEach-Object`, which emits `$true` but does **not** exit the script block, so a match returned a truthy array instead of a clean boolean. Rewritten with `foreach` + `break`.
- Remote uninstalls **no longer hang or time out too early** — the uninstaller runs via `Invoke-Command -AsJob` while the app is polled with `Test-AppStillInstalled` every 15 s until removal is confirmed in the remote registry (up to 4 minutes). Long-running Inno/NSIS uninstallers now report success as soon as the app is actually gone. Elevation requests (`ELEVATED:`), missing executables (`EXE_NOT_FOUND:`) and exit codes (`EXITCODE:`) are surfaced in the log.
- Process-stop phase **no longer hangs** — remote process stop is wrapped in a job with a 45 s `Wait-Job` timeout; on timeout it logs a warning and continues. Matching **Windows services** are also force-stopped during this phase.

**UX / UI**

- Live **"working m:ss"** elapsed indicator per job plus an indeterminate progress bar while the batch is active, with 20 s heartbeat messages.
- Batch **SUMMARY now lists app names**: `SUMMARY: Completed on it-op-031 | Uninstalled: 1 (AnyDesk) | Failed: 0`.
- **Message Center readability**: thin rule separators between sections, bold violet app headers, indented `DETAIL` lines, bold `SUMMARY`, and SemiBold `ERROR` lines.
- **Button overhaul**: hover/pressed overlays fill the entire button on every style (primary, secondary, danger, nav, ghost, dark-ghost, dialog buttons); uniform 5 px button corner radius with the overlay radius matched; light secondary buttons gained a visible `#CBD5E1` border; explicit `VerticalScrollBarVisibility="Auto"` on the app list and details list.

---

## 🏗️ Roadmap Ideas

- Export details view alongside the CSV
- CredSSP / custom-credential support for domain remote uninstalls
- Per-app install date sorting and grouping
- Refresh-before-uninstall sanity check (warn if list is stale)

---

## 📜 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 👤 Author

**Mohammad Abdulkader Omar**  
Org: Qassim University — IT Operations  
Website: https://momar.tech  
LinkedIn: https://www.linkedin.com/in/mabdulkadr/  
Version: **1.1**

---

## ⚠ Disclaimer

This script is provided as-is. Test it in a staging environment before applying it to production. The author is not responsible for any unintended outcomes resulting from its use.
