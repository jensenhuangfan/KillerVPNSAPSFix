#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstall KillerSAPSFix and restore original Killer behavior.

.DESCRIPTION
    Stops and removes the KillerSAPSFix Scheduled Task, deletes installed
    files from C:\ProgramData\KillerSAPSFix, and restores VPNInhibited=1
    so the Killer suite returns to its default behavior.

.NOTES
    Must be run as Administrator.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ────────────────────────────────────────────────────────────────
$TaskName    = 'KillerSAPSFix'
$LegacyTask  = 'KillerVPNOverride'
$InstallDir  = 'C:\ProgramData\KillerSAPSFix'
$KAPSRoot    = 'HKLM:\SOFTWARE\RivetNetworks\KAPS'

# ── Admin check ──────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host ''
    Write-Host '  ERROR: This script must be run as Administrator.' -ForegroundColor Red
    Write-Host '  Right-click PowerShell and choose "Run as administrator".' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

# ── Banner ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  ╔════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '  ║       KillerSAPSFix — Uninstaller v1.0.0      ║' -ForegroundColor Cyan
Write-Host '  ╚════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# ── Step 1 — Stop and remove Scheduled Tasks ────────────────────────────────
Write-Host '  [1/3] Removing Scheduled Tasks...' -ForegroundColor White

foreach ($name in @($TaskName, $LegacyTask)) {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            Write-Host "        Removed task '$name'." -ForegroundColor DarkGray
        } catch {
            Write-Host "        WARNING: Could not remove task '$name': $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "        Task '$name' not found (skipped)." -ForegroundColor DarkGray
    }
}

Write-Host '        Done.' -ForegroundColor Green
Write-Host ''

# ── Step 2 — Remove installed files ─────────────────────────────────────────
Write-Host '  [2/3] Removing installed files...' -ForegroundColor White

if (Test-Path $InstallDir) {
    try {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
        Write-Host "        Removed $InstallDir" -ForegroundColor DarkGray
    } catch {
        Write-Host "        WARNING: Could not fully remove $InstallDir : $_" -ForegroundColor Yellow
        Write-Host '        The directory may be cleaned up after reboot.' -ForegroundColor Yellow
    }
} else {
    Write-Host "        $InstallDir not found (skipped)." -ForegroundColor DarkGray
}

Write-Host '        Done.' -ForegroundColor Green
Write-Host ''

# ── Step 3 — Restore original registry state ────────────────────────────────
Write-Host '  [3/3] Restoring original registry values...' -ForegroundColor White

$guidPattern = '^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$'

if (Test-Path $KAPSRoot) {
    try {
        $subkeys = Get-ChildItem -Path $KAPSRoot -ErrorAction SilentlyContinue
        foreach ($sk in $subkeys) {
            if ($sk.PSChildName -match $guidPattern) {
                $adapterPath = $sk.PSPath
                Set-ItemProperty -Path $adapterPath -Name 'VPNInhibited' -Value 1 -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $adapterPath -Name 'VPNFound'     -Value 1 -Type DWord -ErrorAction SilentlyContinue
                Write-Host "        Restored VPNInhibited=1 for $($sk.PSChildName)" -ForegroundColor DarkGray
            }
        }

        Set-ItemProperty -Path $KAPSRoot -Name 'VPNFound' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Write-Host '        Restored global VPNFound=1.' -ForegroundColor DarkGray
    } catch {
        Write-Host "        WARNING: Could not fully restore registry: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "        KAPS registry root not found (skipped)." -ForegroundColor DarkGray
}

Write-Host '        Done.' -ForegroundColor Green
Write-Host ''

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host '  ╔════════════════════════════════════════════════╗' -ForegroundColor Green
Write-Host '  ║          Uninstall complete!                   ║' -ForegroundColor Green
Write-Host '  ╚════════════════════════════════════════════════╝' -ForegroundColor Green
Write-Host ''
Write-Host '  The Killer suite has been restored to default behavior.' -ForegroundColor White
Write-Host '  You may need to restart your computer for all changes' -ForegroundColor White
Write-Host '  to take full effect.' -ForegroundColor White
Write-Host ''
