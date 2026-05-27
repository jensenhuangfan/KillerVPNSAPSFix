# KillerSAPSFix

**A fix for the Intel Killer Performance Suite SAPS VPN Lock & Band Name Warnings**

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-Custom-green)

---

## What is this?

The Intel Killer Performance Suite has a couple of annoying bugs that I decided to fix since there's no official patch for them. 

### 1. The VPN Lock Bug (SAPS Disabled)
The Killer Smart AP Selection Service (KAPSService) constantly scans your network adapters. If it spots a virtual network adapter like ZeroTier, Tailscale, WireGuard, or even a Hyper-V switch, it panics and disables SAPS (Smart Access Point Selection) entirely. It does this by writing `VPNInhibited=1` to your registry. There is no setting in the UI to turn this off. 

This means your Wi-Fi experience is degraded just because you have a virtual adapter installed, even if you aren't using a VPN to route your traffic.

### 2. The False Band Name Warning
The Killer app loves to spam this warning:
> "Your 2.4 GHz and 5 GHz WIFI bands have different names"

The funny part is, it does this even when your bands have the exact same name. The software groups bands by BSSID (MAC address prefixes) instead of looking at the actual SSID string. If your router uses a different MAC prefix for its 2.4 GHz radio than its 5/6 GHz radios, the Killer app gets confused and assumes they are different networks.

---

## What the fix does

- Auto-detects your Killer adapter GUID so you don't have to configure anything manually.
- Overrides the VPN lock on startup and monitors the registry to force it open if KAPSService tries to lock it again.
- Suppresses the false band-name warnings by fixing the AP2ISPCrossInfo entries in the registry.
- Runs silently in the background as a Scheduled Task.
- Has a unified setup menu so you can easily install, uninstall, or configure it.

---

## Requirements

- Windows 10 or Windows 11
- An Intel Killer Wi-Fi adapter with the Killer Performance Suite installed
- PowerShell 5.1 or newer
- Administrator rights to run the setup

---

## How to use it

Everything is handled through a single script now. 

1. Clone or download this repository to your computer.
2. Open **PowerShell as Administrator**.
3. Navigate to the folder where you downloaded the files.
4. Run the setup script:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

A menu will pop up allowing you to:
- **Install**: Copies the files to `C:\ProgramData\KillerSAPSFix` and sets up the background task.
- **Uninstall**: Completely removes the scheduled tasks, deletes the files, and restores your registry to the default Killer behavior.
- **Configure**: Lets you tweak things like the polling interval, or turn specific fixes on and off.

---

## How It Works behind the scenes

1. It finds your adapter GUIDs under `HKLM\SOFTWARE\RivetNetworks\KAPS`.
2. It temporarily stops the KAPSService.
3. It patches the registry (sets `VPNInhibited = 0`, `VPNFound = 0`, clears `StatusMessage`, and normalizes your SSIDs).
4. It restarts KAPSService.
5. It runs a lightweight background loop that watches the registry. If KAPSService flips the switch back to 1, the script immediately flips it back to 0. It also re-scans for new adapters every 5 minutes just in case.

---

## Troubleshooting

- **The script isn't running:** Open PowerShell as admin and run `Get-ScheduledTask -TaskName KillerSAPSFix` to see if the task is registered and running.
- **Still seeing the band name warning:** Sometimes the Killer Control Center caches the warning. Try closing the app entirely from the system tray and reopening it, or disconnect and reconnect to your Wi-Fi.
- **Logs:** You can check the logs at `C:\ProgramData\KillerSAPSFix\KillerSAPSFix.log` to see what the script is doing in real-time.

---

## License

[Custom License](LICENSE) — Copyright © 2026 JensenHuangFan
