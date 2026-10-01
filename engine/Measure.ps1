$script:MeasureMetrics = @('ramInUseMB', 'processCount', 'runningServices', 'enabledTasks', 'systemDriveFreeGB', 'bootDurationMs', 'uptimeMinutes')

function Get-TuneupMetricName {
    foreach ($metric in $script:MeasureMetrics) { $metric }
}

function ConvertFrom-TuneupBootEvent {
    param(
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][datetime]$Created,
        [Parameter(Mandatory)][datetime]$LastBoot
    )
    # Windows writes event 100 a few minutes after startup; an older one belongs to a previous boot.
    if ($Created -lt $LastBoot) { return [pscustomobject]@{ milliseconds = $null; reason = 'not-recorded-yet' } }
    $document = [xml]$Xml
    $value = @($document.Event.EventData.Data | Where-Object { $_.GetAttribute('Name') -eq 'BootTime' } | ForEach-Object { $_.InnerText })
    $number = 0L
    if (-not $value.Count -or -not [long]::TryParse([string]$value[0], [ref]$number)) {
        return [pscustomobject]@{ milliseconds = $null; reason = 'unreadable' }
    }
    [pscustomobject]@{ milliseconds = $number; reason = $null }
}

function Get-TuneupBootDuration {
    param([Parameter(Mandatory)][datetime]$LastBoot)
    try {
        $record = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
    } catch {
        # Without elevation Windows answers "no events" instead of "access denied".
        $reason = 'unavailable'
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            $reason = $(if (Test-TuneupAdmin) { 'no-event' } else { 'needs-admin' })
        }
        return [pscustomobject]@{ milliseconds = $null; reason = $reason }
    }
    ConvertFrom-TuneupBootEvent -Xml $record.ToXml() -Created $record.TimeCreated -LastBoot $LastBoot
}

function Measure-TuneupSystem {
    param([Parameter(Mandatory)]$Environment, [int]$IdleSeconds = 0)
    if ($IdleSeconds -gt 0) { Start-Sleep -Seconds $IdleSeconds }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $now = Get-Date
    $boot = Get-TuneupBootDuration -LastBoot $os.LastBootUpTime
    [pscustomobject]@{
        schemaVersion = 1
        takenAt       = $now.ToString('s')
        idleSeconds   = $IdleSeconds
        environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
        metrics       = [pscustomobject]@{
            ramInUseMB        = [long][math]::Round(([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1024)
            processCount      = @(Get-Process).Count
            runningServices   = @(Get-Service | Where-Object { [string]$_.Status -eq 'Running' }).Count
            enabledTasks      = @(Get-ScheduledTask | Where-Object { [string]$_.State -ne 'Disabled' }).Count
            systemDriveFreeGB = [math]::Round([double]$drive.FreeSpace / 1GB, 2)
            bootDurationMs    = $boot.milliseconds
            uptimeMinutes     = [long][math]::Floor(($now - $os.LastBootUpTime).TotalMinutes)
        }
        notes         = [pscustomobject]@{ bootDurationMs = $boot.reason }
    }
}

function Compare-TuneupMeasurement {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    foreach ($metric in $script:MeasureMetrics) {
        $old = $Before.metrics.$metric
        $new = $After.metrics.$metric
        $delta = $null
        if ($null -ne $old -and $null -ne $new) { $delta = [math]::Round([double]$new - [double]$old, 2) }
        [pscustomobject]@{ metric = $metric; before = $old; after = $new; delta = $delta }
    }
}

$script:MeasurementIdPattern = '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$'

function Save-TuneupMeasurement {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Measurement, [string]$StateRoot, [switch]$Machine, [string]$MachineRoot, [string]$UserRoot)
    # Same folders and trust rules as the runs.
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $kind = 'custom'
        $root = $StateRoot
    }
    elseif ($Machine) {
        if (-not (Test-TuneupAdmin)) { throw 'The machine state folder can only be written by an elevated process' }
        $kind = 'machine'
        $root = $(if ($MachineRoot) { $MachineRoot } else { Get-TuneupStateRoot -Machine })
        Initialize-TuneupStateRoot -Path $root -Children @('measurements')
    }
    else {
        $kind = 'user'
        $root = $(if ($UserRoot) { $UserRoot } else { Get-TuneupStateRoot })
    }
    $dir = Join-Path $root 'measurements'
    if ($kind -ne 'machine') { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    $baseId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $id = $baseId
    $counter = 1
    while (Test-Path -LiteralPath (Join-Path $dir "$id.json")) {
        $counter++
        $id = '{0}-{1:D2}' -f $baseId, $counter
    }
    $saved = $Measurement | Select-Object -Property *
    $saved | Add-Member -NotePropertyName id -NotePropertyValue $id -Force
    $path = Join-Path $dir "$id.json"
    Save-TuneupJson -Path $path -Object $saved -Root $kind
    [pscustomobject]@{ Id = $id; Path = $path; Root = $kind; Measurement = $saved }
}

# A file that parses can still be anything; comparing needs an object of numbers (or nulls).
function Test-TuneupMeasurementShape {
    param([AllowNull()]$Data)
    if ($null -eq $Data -or $Data -isnot [pscustomobject] -or $Data.metrics -isnot [pscustomobject]) { return $false }
    foreach ($property in $Data.metrics.PSObject.Properties) {
        $value = $property.Value
        if ($null -eq $value) { continue }
        if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) { return $false }
    }
    $true
}

function Get-TuneupMeasurementList {
    [CmdletBinding()]
    param([string]$StateRoot, [string]$MachineRoot, [string]$UserRoot)
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $roots = @([pscustomobject]@{ Kind = 'custom'; Path = $StateRoot })
    }
    else {
        if (-not $MachineRoot) { $MachineRoot = Get-TuneupStateRoot -Machine }
        if (-not $UserRoot) { $UserRoot = Get-TuneupStateRoot }
        $roots = @(
            [pscustomobject]@{ Kind = 'machine'; Path = $MachineRoot },
            [pscustomobject]@{ Kind = 'user'; Path = $UserRoot }
        )
    }
    $byKey = @{}
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $roots) {
        $dir = Join-Path $root.Path 'measurements'
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        if ($root.Kind -eq 'machine') {
            $base = Split-Path -Parent $root.Path
            $untrusted = $null
            if (-not (Test-TuneupBaseFolder -Path $base)) { $untrusted = $base }
            else { $untrusted = @($root.Path, $dir) | Where-Object { -not (Test-TuneupTrustedItem -Path $_) } | Select-Object -First 1 }
            if ($untrusted) {
                Write-Warning "Ignoring untrusted state folder $untrusted"
                continue
            }
        }
        foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
            if ($file.BaseName -cnotmatch $script:MeasurementIdPattern) { continue }
            $data = Read-TuneupTrustedJson -Path $file.FullName -Root $root.Kind
            if ($null -eq $data) { continue }
            if (-not (Test-TuneupMeasurementShape -Data $data)) {
                Write-Warning "Ignoring unreadable state file $($file.FullName)"
                continue
            }
            # A space sorts before '-', so '20250101-000000' stays ahead of '20250101-000000-02'.
            $key = $file.BaseName + ' ' + $root.Kind
            $byKey[$key] = [pscustomobject]@{ Id = $file.BaseName; Path = $file.FullName; Root = $root.Kind; Measurement = $data }
            $keys.Add($key)
        }
    }
    $keys.Sort([System.StringComparer]::Ordinal)
    foreach ($key in $keys) { $byKey[$key] }
}

function Resolve-TuneupMeasurement {
    [CmdletBinding()]
    param([string]$StateRoot, [string]$MachineRoot, [string]$UserRoot, [Parameter(Mandatory)][string]$Id)
    $all = @(Get-TuneupMeasurementList -StateRoot $StateRoot -MachineRoot $MachineRoot -UserRoot $UserRoot)
    if ($Id -eq 'last') {
        if ($all.Count) { return $all[-1] }
        return
    }
    $all | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}