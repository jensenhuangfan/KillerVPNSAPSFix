#Requires -RunAsAdministrator
<#
.SYNOPSIS
    KillerSAPSFix - Fix Intel Killer Performance Suite SAPS VPN Lock & False Band Name Warnings.

.DESCRIPTION
    Runs as a background service (via Scheduled Task) to continuously override the
    VPNInhibited registry flag that KAPSService sets when it detects virtual network
    adapters (e.g. ZeroTier, Tailscale, WireGuard).

    adapters (e.g. ZeroTier, Tailscale, WireGuard).

.NOTES
    Author : JensenHuangFan
    License: MIT
    Version: 1.0.0
#>

# ── Resolve paths relative to the script location ────────────────────────────
$ScriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ConfigPath = Join-Path $ScriptDir 'config.json'

# ── Load configuration ───────────────────────────────────────────────────────
function Read-Config {
    $defaults = @{
        CheckIntervalSeconds    = 5
        OverrideVPNLock         = $true
        LogEnabled              = $true
        LogPath                 = 'KillerSAPSFix.log'
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found at '$ConfigPath'. Using defaults."
        return $defaults
    }

    try {
        $json = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        $cfg  = @{}
        foreach ($key in $defaults.Keys) {
            if ($null -ne $json.$key) {
                $cfg[$key] = $json.$key
            } else {
                $cfg[$key] = $defaults[$key]
            }
        }
        return $cfg
    } catch {
        Write-Warning "Failed to parse config: $_  — Using defaults."
        return $defaults
    }
}

$Config = Read-Config

# ── Logging ──────────────────────────────────────────────────────────────────
$LogFile = if ([System.IO.Path]::IsPathRooted($Config.LogPath)) {
    $Config.LogPath
} else {
    Join-Path $ScriptDir $Config.LogPath
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"

    if ($Config.LogEnabled) {
        try {
            Add-Content -Path $LogFile -Value $line -ErrorAction Stop
        } catch {
            # If we can't write to the log, silently continue — we are a background service.
        }
    }
}

# ── Adapter GUID auto-detection ──────────────────────────────────────────────
$KAPSRoot = 'HKLM:\SOFTWARE\RivetNetworks\KAPS'

function Find-AdapterGUIDs {
    <#
    .SYNOPSIS
        Scans HKLM\SOFTWARE\RivetNetworks\KAPS for subkeys that look like
        adapter GUIDs ({xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}).
    #>
    $guids = @()
    $guidPattern = '^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$'

    if (-not (Test-Path $KAPSRoot)) {
        Write-Log "KAPS registry root not found at '$KAPSRoot'." -Level ERROR
        return $guids
    }

    try {
        $subkeys = Get-ChildItem -Path $KAPSRoot -ErrorAction Stop
        foreach ($sk in $subkeys) {
            $name = $sk.PSChildName
            if ($name -match $guidPattern) {
                $guids += $name
                Write-Log "Detected adapter GUID: $name"
            }
        }
    } catch {
        Write-Log "Error scanning KAPS registry: $_" -Level ERROR
    }

    if ($guids.Count -eq 0) {
        Write-Log "No adapter GUIDs found under '$KAPSRoot'." -Level WARN
    }

    return $guids
}

# ── Registry helpers ─────────────────────────────────────────────────────────
function Set-RegistryDWord {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -ErrorAction Stop
        return $true
    } catch {
        Write-Log "Failed to set $Path\$Name = $Value : $_" -Level ERROR
        return $false
    }
}

function Set-RegistryString {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String -ErrorAction Stop
        return $true
    } catch {
        Write-Log "Failed to set $Path\$Name = '$Value' : $_" -Level ERROR
        return $false
    }
}

function Get-RegistryDWord {
    param(
        [string]$Path,
        [string]$Name
    )
    try {
        if (-not (Test-Path $Path)) { return $null }
        $val = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $val.$Name
    } catch {
        return $null
    }
}

# ── Core fix functions ───────────────────────────────────────────────────────
function Invoke-VPNLockOverride {
    <#
    .SYNOPSIS
        Clears VPNInhibited, VPNFound, and StatusMessage for every detected adapter,
        plus the global VPNFound flag.
    #>
    param([string[]]$GUIDs, [switch]$Silent)

    foreach ($guid in $GUIDs) {
        $adapterPath = Join-Path $KAPSRoot $guid

        Set-RegistryDWord  -Path $adapterPath -Name 'VPNInhibited' -Value 0 | Out-Null
        Set-RegistryDWord  -Path $adapterPath -Name 'VPNFound'     -Value 0 | Out-Null
        Set-RegistryString -Path $adapterPath -Name 'StatusMessage' -Value '' | Out-Null

        if (-not $Silent) {
            Write-Log "Cleared VPN lock flags for adapter $guid"
        }
    }

    # Global VPNFound flag
    Set-RegistryDWord -Path $KAPSRoot -Name 'VPNFound' -Value 0 | Out-Null

    if (-not $Silent) {
        Write-Log 'Global VPNFound flag cleared.'
    }
}



# ── Service management ───────────────────────────────────────────────────────
function Stop-KAPSService {
    try {
        $svc = Get-Service -Name 'KAPSService' -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Log 'Stopping KAPSService...'
            Stop-Service -Name 'KAPSService' -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Log 'KAPSService stopped.'
        } else {
            Write-Log 'KAPSService is not running (or not installed).' -Level WARN
        }
    } catch {
        Write-Log "Failed to stop KAPSService: $_" -Level ERROR
    }
}

function Start-KAPSService {
    try {
        $svc = Get-Service -Name 'KAPSService' -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log 'Starting KAPSService...'
            Start-Service -Name 'KAPSService' -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Log 'KAPSService started.'
        } else {
            Write-Log 'KAPSService not found. Skipping start.' -Level WARN
        }
    } catch {
        Write-Log "Failed to start KAPSService: $_" -Level ERROR
    }
}

# ── Main entry point ─────────────────────────────────────────────────────────
function Start-KillerSAPSFix {
    Write-Log '═══════════════════════════════════════════════════════════════'
    Write-Log "KillerSAPSFix v1.0.0 starting (PID $PID)"
    Write-Log "Script directory : $ScriptDir"
    Write-Log "Config file      : $ConfigPath"
    Write-Log "Log file         : $LogFile"
    Write-Log "Check interval   : $($Config.CheckIntervalSeconds)s"
    Write-Log "Override VPN lock : $($Config.OverrideVPNLock)"
    Write-Log '═══════════════════════════════════════════════════════════════'

    # Auto-update logic
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $updateUrl = "https://raw.githubusercontent.com/jensenhuangfan/KillerVPNSAPSFix/master/KillerSAPSFix.ps1"
        $remoteContent = Invoke-RestMethod -Uri $updateUrl -UseBasicParsing -ErrorAction Stop
        $localContent = Get-Content -Path $PSCommandPath -Raw -ErrorAction Stop
        
        if ($remoteContent -and $localContent.Trim() -ne $remoteContent.Trim()) {
            Write-Log 'Update found on GitHub. Applying update...'
            Stop-KAPSService
            Set-Content -Path $PSCommandPath -Value $remoteContent -Force
            Write-Log 'Update applied. Restarting script...'
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
            exit 0
        }
    } catch {
        Write-Log "Failed to check for updates: $_" -Level WARN
    }

    # Detect adapters
    $guids = Find-AdapterGUIDs
    if ($guids.Count -eq 0) {
        Write-Log 'No Killer adapter GUIDs detected. Will retry in monitoring loop.' -Level WARN
    }

    # ── Initial fix (stop service → patch → restart) ─────────────────────
    if ($guids.Count -gt 0) {
        Stop-KAPSService

        if ($Config.OverrideVPNLock) {
            Invoke-VPNLockOverride -GUIDs $guids
        }

        Start-KAPSService
        Write-Log 'Initial patch applied successfully.'
    }

    # ── Monitoring loop ──────────────────────────────────────────────────
    Write-Log 'Entering monitoring loop...'
    $patchCount   = 0
    $loopCount    = 0
    $lastGuidScan = Get-Date

    while ($true) {
        Start-Sleep -Seconds $Config.CheckIntervalSeconds
        $loopCount++

        # Re-scan for adapters every 5 minutes in case new ones appear
        if (((Get-Date) - $lastGuidScan).TotalMinutes -ge 5 -or $guids.Count -eq 0) {
            $newGuids = Find-AdapterGUIDs
            if ($newGuids.Count -gt 0) {
                $guids = $newGuids
            }
            $lastGuidScan = Get-Date
        }

        if ($guids.Count -eq 0) { continue }

        # Check and re-patch VPN lock
        if ($Config.OverrideVPNLock) {
            $needsPatch = $false

            foreach ($guid in $guids) {
                $adapterPath = Join-Path $KAPSRoot $guid
                $vpnInhibited = Get-RegistryDWord -Path $adapterPath -Name 'VPNInhibited'

                if ($vpnInhibited -eq 1) {
                    $needsPatch = $true
                    break
                }
            }

            # Also check global VPNFound
            $globalVPN = Get-RegistryDWord -Path $KAPSRoot -Name 'VPNFound'
            if ($globalVPN -eq 1) { $needsPatch = $true }

            if ($needsPatch) {
                $patchCount++
                Write-Log "VPN lock re-detected (occurrence #$patchCount). Re-patching registry..."
                Invoke-VPNLockOverride -GUIDs $guids -Silent
                Write-Log "VPN lock override re-applied (no service restart)."
            }
        }
    }
}

# Run
Start-KillerSAPSFix
