# KillerSAPSFix

**Fix Intel Killer Performance Suite SAPS VPN Lock & False Band Name Warnings**

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

---

## The Problem

The **Intel Killer Performance Suite** ships with two frustrating bugs that have no official fix:

### 🔒 Bug 1 — VPN Lock (SAPS Disabled)

The **KAPSService** (Killer Smart AP Selection Service) scans for virtual network adapters — ZeroTier, Tailscale, WireGuard, Hyper-V switches, etc. — and when it finds one, it disables **SAPS** (Smart Access Point Selection) by writing `VPNInhibited=1` to the registry. There is **no UI toggle** to override this.

Even though SAPS has nothing to do with VPN routing, the Killer suite locks it out entirely if *any* virtual adapter is present. This degrades your Wi-Fi experience for no reason.

**Registry key:**
```
HKLM\SOFTWARE\RivetNetworks\KAPS\{ADAPTER_GUID}\VPNInhibited = 1
```

### ⚠️ Bug 2 — False Band Name Warning

The Killer UI constantly shows:

> *"Your 2.4 GHz and 5 GHz WIFI bands have different names"*

…even when **all bands share the same SSID**. This happens because the router's 2.4 GHz radio uses a different MAC/BSSID prefix than the 5/6 GHz radios, and the Killer software uses BSSID grouping (not SSID comparison) to determine band names.

---

## Features

- ✅ **Auto-detects** your Killer adapter GUID — nothing to hardcode
- ✅ **Overrides VPNInhibited** on startup and monitors for re-lock every few seconds
- ✅ **Suppresses false band-name warnings** by normalizing AP2ISPCrossInfo entries
- ✅ **Runs silently** as a Scheduled Task under SYSTEM — no console window
- ✅ **Survives reboots** — the task is registered with an At Startup trigger
- ✅ **Configurable** check interval, toggle each fix independently
- ✅ **Clean uninstall** restores original Killer behavior
- ✅ **Structured logging** for troubleshooting

---

## Requirements

| Requirement | Details |
|---|---|
| **OS** | Windows 10 or Windows 11 |
| **Adapter** | Intel Killer Wi-Fi adapter with Killer Performance Suite installed |
| **PowerShell** | 5.1 or later (built into Windows 10/11) |
| **Privileges** | Administrator (for install/uninstall) |

---

## Quick Install

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

That's it. The fix is now running and will persist across reboots.

---

## Manual Install

If you prefer to understand each step:

1. **Clone or download** this repository
2. **Open PowerShell as Administrator**
3. **Navigate** to the repository folder
4. **Run the installer:**

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

The installer will:
- Copy `KillerSAPSFix.ps1` and `config.json` to `C:\ProgramData\KillerSAPSFix\`
- Register a Scheduled Task named `KillerSAPSFix`
- Start the task immediately

---

## Configuration

Edit `C:\ProgramData\KillerSAPSFix\config.json` after installation (or `config.json` in this repo before installing):

```json
{
  "CheckIntervalSeconds": 5,
  "OverrideVPNLock": true,
  "SuppressBandNameWarning": true,
  "LogEnabled": true,
  "LogPath": "KillerSAPSFix.log"
}
```

| Option | Type | Default | Description |
|---|---|---|---|
| `CheckIntervalSeconds` | int | `5` | How often (in seconds) to check if KAPSService has re-locked SAPS |
| `OverrideVPNLock` | bool | `true` | Enable/disable the VPNInhibited override |
| `SuppressBandNameWarning` | bool | `true` | Enable/disable the band-name warning suppression |
| `LogEnabled` | bool | `true` | Enable/disable logging |
| `LogPath` | string | `KillerSAPSFix.log` | Log file path (relative to install dir, or absolute) |

> **Note:** After editing the config, restart the Scheduled Task for changes to take effect:
> ```powershell
> Stop-ScheduledTask -TaskName KillerSAPSFix
> Start-ScheduledTask -TaskName KillerSAPSFix
> ```

---

## Uninstall

Open **PowerShell as Administrator** and run:

```powershell
.\uninstall.ps1
```

This will:
- Stop and remove the `KillerSAPSFix` Scheduled Task
- Remove the legacy `KillerVPNOverride` task if it exists
- Delete `C:\ProgramData\KillerSAPSFix\`
- Restore `VPNInhibited=1` (original Killer behavior)

---

## How It Works

```
┌──────────────────────────────────────────────────────┐
│                    KillerSAPSFix                     │
│                                                      │
│  1. Auto-detect adapter GUIDs under                  │
│     HKLM\SOFTWARE\RivetNetworks\KAPS\{...}           │
│                                                      │
│  2. Stop KAPSService                                 │
│                                                      │
│  3. Patch registry:                                  │
│     • VPNInhibited = 0                               │
│     • VPNFound = 0 (per-adapter + global)            │
│     • StatusMessage = ""                             │
│     • Normalize AP2ISPCrossInfo SSIDs                │
│                                                      │
│  4. Restart KAPSService                              │
│                                                      │
│  5. Monitor loop (every N seconds):                  │
│     • If VPNInhibited flips back to 1 → re-patch     │
│     • Periodically re-normalize band info            │
│     • Re-scan for new adapter GUIDs every 5 min      │
└──────────────────────────────────────────────────────┘
```

### Registry Keys Modified

| Key | Type | Value Set | Purpose |
|---|---|---|---|
| `KAPS\{GUID}\VPNInhibited` | DWORD | `0` | Unlocks SAPS |
| `KAPS\{GUID}\VPNFound` | DWORD | `0` | Clears VPN detection flag |
| `KAPS\{GUID}\StatusMessage` | REG_SZ | `""` | Clears status message |
| `KAPS\VPNFound` | DWORD | `0` | Clears global VPN flag |
| `KAPS\{GUID}\AP2ISPCrossInfo\*\SSID` | REG_SZ | *(normalized)* | Fixes band name mismatch |

---

## Troubleshooting

### The fix doesn't seem to be running

```powershell
# Check task status
Get-ScheduledTask -TaskName KillerSAPSFix | Format-List State

# Check the log
Get-Content C:\ProgramData\KillerSAPSFix\KillerSAPSFix.log -Tail 20

# Manually start the task
Start-ScheduledTask -TaskName KillerSAPSFix
```

### SAPS still shows as disabled

1. Check the log file for errors
2. Verify the KAPS registry path exists:
   ```powershell
   Get-ChildItem 'HKLM:\SOFTWARE\RivetNetworks\KAPS'
   ```
3. Make sure the Killer Performance Suite is installed and KAPSService exists:
   ```powershell
   Get-Service KAPSService
   ```

### The band name warning persists

This fix normalizes the `AP2ISPCrossInfo` registry entries, but the Killer UI may cache the warning. Try:
1. Close and reopen the Killer Control Center
2. Disconnect and reconnect to Wi-Fi
3. Check the log for "Normalised SSID" entries

### I want to run the script manually for testing

```powershell
# Run in the foreground (requires admin)
powershell -ExecutionPolicy Bypass -File .\KillerSAPSFix.ps1
```

Press `Ctrl+C` to stop.

---

## License

[MIT](LICENSE) — Copyright © 2026 JensenHuangFan
