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
