#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Manage KillerSAPSFix installation, uninstallation, and configuration.

.DESCRIPTION
    A single setup script to install the fix as a scheduled task, uninstall it,
    or configure the behavior (polling interval, enabling/disabling fixes).

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
$LegacyTask  = 'KillerVPNOverride'
$KAPSRoot    = 'HKLM:\SOFTWARE\RivetNetworks\KAPS'

# ── Admin check ──────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host '  Elevating to Administrator...' -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

# ── Functions ────────────────────────────────────────────────────────────────

function Install-Fix {
    Write-Host "`n  [1/5] Checking for updates from GitHub..." -ForegroundColor White
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $repoUrl = "https://raw.githubusercontent.com/jensenhuangfan/KillerVPNSAPSFix/master"
        
        $remoteFix = Invoke-RestMethod -Uri "$repoUrl/KillerSAPSFix.ps1" -UseBasicParsing -ErrorAction Stop
        $remoteFixClean = $remoteFix -replace "`r`n", "`n"
        $localFixPath = Join-Path $ScriptDir 'KillerSAPSFix.ps1'
        $localFixContent = if (Test-Path $localFixPath) { (Get-Content $localFixPath -Raw) -replace "`r`n", "`n" } else { "" }
        if ($localFixContent.Trim() -ne $remoteFixClean.Trim()) {
            Set-Content -Path $localFixPath -Value $remoteFix -Force
            Write-Host "        Updated KillerSAPSFix.ps1" -ForegroundColor DarkGray
        }

        $remoteSetup = Invoke-RestMethod -Uri "$repoUrl/setup.ps1" -UseBasicParsing -ErrorAction Stop
        $remoteSetupClean = $remoteSetup -replace "`r`n", "`n"
        $localSetupPath = Join-Path $ScriptDir 'setup.ps1'
        $localSetupContent = if (Test-Path $localSetupPath) { (Get-Content $localSetupPath -Raw) -replace "`r`n", "`n" } else { "" }
        if ($localSetupContent.Trim() -ne $remoteSetupClean.Trim()) {
            Set-Content -Path $localSetupPath -Value $remoteSetup -Force
            Write-Host "        Updated setup.ps1" -ForegroundColor DarkGray
        }
        
        Write-Host "        Done." -ForegroundColor Green
    } catch {
        Write-Host "        WARNING: Could not check for updates. Proceeding with local files. $_" -ForegroundColor Yellow
    }

    Write-Host "`n  [2/5] Stopping Killer Services..." -ForegroundColor White
    Stop-Service -Name KAPSService -Force -ErrorAction SilentlyContinue
    Stop-Process -Name KAPS -Force -ErrorAction SilentlyContinue

    Write-Host "`n  [3/5] Copying files..." -ForegroundColor White
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
            return
        }
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "        Copied $file" -ForegroundColor DarkGray
    }
    Write-Host '        Done.' -ForegroundColor Green

    Write-Host "`n  [4/5] Registering Scheduled Task..." -ForegroundColor White
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "        Removing existing task '$TaskName'..." -ForegroundColor DarkGray
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $legacy = Get-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue
    if ($legacy) {
        Write-Host "        Removing legacy task '$LegacyTask'..." -ForegroundColor DarkGray
        Stop-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $LegacyTask -Confirm:$false
    }

    $scriptPath = Join-Path $InstallDir 'KillerSAPSFix.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -Hidden

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Fix Intel Killer Performance Suite SAPS VPN Lock.' -Force | Out-Null
    Write-Host "        Task '$TaskName' registered." -ForegroundColor Green

    Write-Host "`n  [5/5] Starting task..." -ForegroundColor White
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2

    $taskInfo = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $taskStatus = if ($taskInfo) { (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult; $taskInfo.State } else { 'Unknown' }
    Write-Host "        Task state: $taskStatus" -ForegroundColor Green

    Write-Host "`n  Installation complete!" -ForegroundColor Green
    Write-Host "  Install directory : $InstallDir" -ForegroundColor DarkGray
    Write-Host "  Scheduled task    : $TaskName" -ForegroundColor DarkGray
    Write-Host "  The fix is now running and will persist across reboots.`n" -ForegroundColor White
}

function Uninstall-Fix {
    Write-Host "`n  [1/4] Stopping Killer Services..." -ForegroundColor White
    Stop-Service -Name KAPSService -Force -ErrorAction SilentlyContinue
    Stop-Process -Name KAPS -Force -ErrorAction SilentlyContinue

    Write-Host "`n  [2/4] Removing Scheduled Tasks..." -ForegroundColor White
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
        }
    }
    Write-Host '        Done.' -ForegroundColor Green

    Write-Host "`n  [3/4] Removing installed files..." -ForegroundColor White
    if (Test-Path $InstallDir) {
        try {
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
            Write-Host "        Removed $InstallDir" -ForegroundColor DarkGray
        } catch {
            Write-Host "        WARNING: Could not fully remove $InstallDir : $_" -ForegroundColor Yellow
        }
    }
    Write-Host '        Done.' -ForegroundColor Green

    Write-Host "`n  [4/4] Restoring original registry values..." -ForegroundColor White
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
    }
    
    Write-Host "        Starting KAPSService..." -ForegroundColor DarkGray
    Start-Service -Name KAPSService -ErrorAction SilentlyContinue
    Write-Host '        Done.' -ForegroundColor Green

    Write-Host "`n  Uninstall complete! The Killer suite has been restored to default behavior.`n" -ForegroundColor Green
}

function Configure-Fix {
    Write-Host "`n  Configuration" -ForegroundColor Cyan
    $configPath = Join-Path $ScriptDir 'config.json'
    if (Test-Path $InstallDir) {
        $installedConfig = Join-Path $InstallDir 'config.json'
        if (Test-Path $installedConfig) {
            $configPath = $installedConfig
        }
    }
    
    if (-not (Test-Path $configPath)) {
        Write-Host "  Could not find config.json at $configPath." -ForegroundColor Red
        return
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    Write-Host "  Current settings:"
    Write-Host "  1. Check Interval (seconds) : $($config.CheckIntervalSeconds)"
    Write-Host "  2. Override VPN Lock        : $($config.OverrideVPNLock)"
    Write-Host "  3. Enable Logging           : $($config.LogEnabled)"
    Write-Host "  4. Log Path                 : $($config.LogPath)"
    Write-Host "  5. Go back"
    
    $choice = Read-Host "`n  Select an option to change (1-5)"
    
    switch ($choice) {
        '1' { $config.CheckIntervalSeconds = [int](Read-Host "  Enter new check interval (e.g., 5)") }
        '2' { $config.OverrideVPNLock = -not $config.OverrideVPNLock; Write-Host "  Toggled OverrideVPNLock to $($config.OverrideVPNLock)" }
        '3' { $config.LogEnabled = -not $config.LogEnabled; Write-Host "  Toggled LogEnabled to $($config.LogEnabled)" }
        '4' { $config.LogPath = Read-Host "  Enter new log path (absolute or relative to script)" }
        '5' { return }
        default { Write-Host "  Invalid choice." -ForegroundColor Red; return }
    }

    $config | ConvertTo-Json | Set-Content $configPath
    Write-Host "  Saved changes to $configPath." -ForegroundColor Green
    
    if ($configPath -match 'ProgramData' -and (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        Write-Host "  Restarting service to apply changes..." -ForegroundColor DarkGray
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
}

# ── Main Menu ────────────────────────────────────────────────────────────────

while ($true) {
    Write-Host ''
    Write-Host '  KillerSAPSFix Setup' -ForegroundColor Cyan
    Write-Host '  ─────────────────────────────' -ForegroundColor Cyan
    Write-Host '  1. Install / Update'
    Write-Host '  2. Uninstall'
    Write-Host '  3. Configure'
    Write-Host '  4. Exit'
    Write-Host ''

    $choice = Read-Host '  Select an option (1-4)'
    
    switch ($choice) {
        '1' { Install-Fix }
        '2' { Uninstall-Fix }
        '3' { Configure-Fix }
        '4' { exit 0 }
        default { Write-Host '  Invalid choice, please select 1-4.' -ForegroundColor Red }
    }
}
