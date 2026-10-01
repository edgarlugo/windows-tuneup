# Warnings before applying (design, section 7: "warns and asks for confirmation"). None of them stops
# the run: a person sees them next to the plan and answers the confirmation, -Yes already means yes,
# and with -Json they go in the preflight array of the plan and apply documents, so whoever runs it
# (the Claude skill) reads them from -WhatIf -Json before asking.

$script:LowDiskThresholdGB = 2
# Value of HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients that lists the volumes with
# System Restore turned on; only administrators can read it.
$script:SystemRestoreClient = '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}'

function Get-TuneupSystemDrive {
    [System.IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))
}

function Get-TuneupSystemDriveFreeGB {
    $drive = New-Object System.IO.DriveInfo -ArgumentList (Get-TuneupSystemDrive)
    [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
}

# The volume GUID of the system drive (Volume{...}), as Windows lists it in SPP\Clients.
function Get-TuneupSystemVolumeId {
    $letter = (Get-TuneupSystemDrive).TrimEnd('\')
    $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$letter'" -ErrorAction Stop
    $match = [regex]::Match([string]$volume.DeviceID, 'Volume\{[0-9A-Fa-f-]+\}')
    $(if ($match.Success) { $match.Value } else { $null })
}

# The entries of SPP\Clients that list the protected volumes; fails when they cannot be read.
function Get-TuneupSystemRestoreEntry {
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    try { @($key.GetValue($script:SystemRestoreClient, @())) | ForEach-Object { [string]$_ } }
    finally { $key.Close() }
}

function Test-TuneupSystemRestorePolicy {
    $policy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction SilentlyContinue
    ($null -ne $policy) -and ($policy.DisableSR -eq 1 -or $policy.DisableConfig -eq 1)
}

# System Restore on the system drive: enabled, disabled, blocked (off, and a policy keeps it off) or
# unknown (not elevated, or the values could not be read).
function Get-TuneupSystemRestoreState {
    try {
        $entries = @(Get-TuneupSystemRestoreEntry)
        $volume = Get-TuneupSystemVolumeId
    } catch {
        return 'unknown'
    }
    if (-not $volume) { return 'unknown' }
    if (@($entries | Where-Object { $_.IndexOf($volume, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) { return 'enabled' }
    $(if (Test-TuneupSystemRestorePolicy) { 'blocked' } else { 'disabled' })
}

# Turns System Restore on for the system drive, only after the person said yes. It is a change of
# Windows that the run does not journal (the journal is about tweaks); System Properties turns it off.
function Enable-TuneupSystemRestore {
    Enable-ComputerRestore -Drive (Get-TuneupSystemDrive) -ErrorAction Stop
}

# Running elevated from a folder that others can change lets them run code as administrator (README,
# requirements). Checked on the script and the module, like a program that runs elevated.
function Test-TuneupTrustedLocation {
    param([Parameter(Mandatory)][string]$ScriptRoot)
    $root = [System.IO.Path]::GetPathRoot($ScriptRoot)
    (Test-TuneupTrustedExecutable -Path (Join-Path $ScriptRoot 'tuneup.ps1') -StopAt $root) -and
    (Test-TuneupTrustedExecutable -Path (Join-Path $ScriptRoot 'engine\Tuneup.psm1') -StopAt $root)
}

function New-TuneupPreflightItem {
    param([Parameter(Mandatory)][string]$Key, [object[]]$Format = @())
    [pscustomobject]@{ id = $Key.Substring('preflight.'.Length); message = Get-TuneupText -Key $Key -Format $Format }
}

# The warnings for a plan; nothing when the plan changes nothing.
function Get-TuneupPreflight {
    param(
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [string]$ScriptRoot
    )
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    if (-not $toApply.Count) { return }
    if ($Environment.PendingReboot) { New-TuneupPreflightItem -Key 'preflight.pending-reboot' }
    $free = Get-TuneupSystemDriveFreeGB
    if ($free -lt $script:LowDiskThresholdGB) { New-TuneupPreflightItem -Key 'preflight.low-disk' -Format $free, $script:LowDiskThresholdGB }
    # A restore point is only made for system changes, which need elevation; only then is it read.
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and $Environment.IsAdmin) {
        switch (Get-TuneupSystemRestoreState) {
            'disabled' { New-TuneupPreflightItem -Key 'preflight.restore-disabled' }
            'blocked' { New-TuneupPreflightItem -Key 'preflight.restore-blocked' }
        }
    }
    if ($Environment.IsManaged) { New-TuneupPreflightItem -Key 'preflight.managed-device' }
    if ($Environment.IsAdmin -and $ScriptRoot -and -not (Test-TuneupTrustedLocation -ScriptRoot $ScriptRoot)) {
        New-TuneupPreflightItem -Key 'preflight.untrusted-location' -Format $ScriptRoot
    }
}

function Write-TuneupPreflight {
    param([AllowEmptyCollection()][object[]]$Preflight = @())
    if (-not @($Preflight).Count) { return }
    Write-Host (Get-TuneupText -Key 'preflight.header') -ForegroundColor Yellow
    foreach ($item in $Preflight) { Write-Host "  ! $($item.message)" -ForegroundColor Yellow }
}

# Asks to turn System Restore on when it is off. True when it was turned on.
function Request-TuneupSystemRestore {
    param([Parameter(Mandatory)]$Io)
    if (-not (Read-TuneupConfirmation -Io $Io -Prompt (Get-TuneupText -Key 'preflight.enableRestore' -Format (Get-TuneupSystemDrive)))) {
        Write-TuneupIoLine -Io $Io -Text (Get-TuneupText -Key 'preflight.restoreKeptOff')
        return $false
    }
    try {
        Enable-TuneupSystemRestore
    } catch {
        Write-TuneupIoLine -Io $Io -Text (Get-TuneupText -Key 'preflight.restoreEnableFailed' -Format $_.Exception.Message)
        return $false
    }
    Write-TuneupIoLine -Io $Io -Text (Get-TuneupText -Key 'preflight.restoreEnabled')
    $true
}
