#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install KillerSAPSFix as a persistent Scheduled Task.

.DESCRIPTION
    Copies KillerSAPSFix.ps1 and config.json to C:\ProgramData\KillerSAPSFix\
    and registers a Scheduled Task that runs the script at system startup
    under the SYSTEM account with highest privileges.

.NOTES
    Must be run as Administrator.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ────────────────────────────────────────────────────────────────
$TaskName    = 'KillerSAPSFix'
$InstallDir  = 'C:\ProgramData\KillerSAPSFix'
$ScriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$SourceFiles = @('KillerSAPSFix.ps1', 'config.json')

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
Write-Host '  ║        KillerSAPSFix — Installer v1.0.0       ║' -ForegroundColor Cyan
Write-Host '  ╚════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# ── Step 1 — Copy files ─────────────────────────────────────────────────────
Write-Host '  [1/3] Copying files...' -ForegroundColor White

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "        Created $InstallDir" -ForegroundColor DarkGray
}

foreach ($file in $SourceFiles) {
    $src = Join-Path $ScriptDir $file
    $dst = Join-Path $InstallDir $file

    if (-not (Test-Path $src)) {
        Write-Host "        MISSING: $src" -ForegroundColor Red
        Write-Host '        Aborting install.' -ForegroundColor Red
        exit 1
    }

    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "        Copied $file" -ForegroundColor DarkGray
}

Write-Host '        Done.' -ForegroundColor Green
Write-Host ''

# ── Step 2 — Register Scheduled Task ────────────────────────────────────────
Write-Host '  [2/3] Registering Scheduled Task...' -ForegroundColor White

# Remove existing task if present
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "        Removing existing task '$TaskName'..." -ForegroundColor DarkGray
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Also clean up legacy task name
$legacyTask = Get-ScheduledTask -TaskName 'KillerVPNOverride' -ErrorAction SilentlyContinue
if ($legacyTask) {
    Write-Host "        Removing legacy task 'KillerVPNOverride'..." -ForegroundColor DarkGray
    Stop-ScheduledTask -TaskName 'KillerVPNOverride' -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'KillerVPNOverride' -Confirm:$false
}

$scriptPath = Join-Path $InstallDir 'KillerSAPSFix.ps1'

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtStartup

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable `
    -Hidden

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Fix Intel Killer Performance Suite SAPS VPN Lock and False Band Name Warnings.' `
    -Force | Out-Null

Write-Host "        Task '$TaskName' registered." -ForegroundColor Green
Write-Host ''

# ── Step 3 — Start the task immediately ──────────────────────────────────────
Write-Host '  [3/3] Starting task...' -ForegroundColor White

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2

$taskInfo = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$taskStatus = if ($taskInfo) {
    (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
    $taskInfo.State
} else {
    'Unknown'
}

Write-Host "        Task state: $taskStatus" -ForegroundColor Green
Write-Host ''

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host '  ╔════════════════════════════════════════════════╗' -ForegroundColor Green
Write-Host '  ║         Installation complete!                 ║' -ForegroundColor Green
Write-Host '  ╚════════════════════════════════════════════════╝' -ForegroundColor Green
Write-Host ''
Write-Host "  Install directory : $InstallDir" -ForegroundColor DarkGray
Write-Host "  Scheduled task    : $TaskName" -ForegroundColor DarkGray
Write-Host "  Log file          : $InstallDir\KillerSAPSFix.log" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  The fix is now running and will persist across reboots.' -ForegroundColor White
Write-Host '  To uninstall, run uninstall.ps1 as Administrator.' -ForegroundColor White
Write-Host ''
