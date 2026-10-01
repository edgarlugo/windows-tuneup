function Get-TuneupNewestRestorePoint {
    param([switch]$Quiet)
    $action = $(if ($Quiet) { 'SilentlyContinue' } else { 'Stop' })
    $points = @(Get-ComputerRestorePoint -ErrorAction $action)
    if (-not $points.Count) { return 0 }
    [long]($points | Measure-Object -Property SequenceNumber -Maximum).Maximum
}

function New-TuneupRestorePoint {
    param([Parameter(Mandatory)][string]$Description)
    try {
        $before = Get-TuneupNewestRestorePoint
    } catch {
        return 'unavailable'
    }
    try {
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        return 'failed'
    }
    # Windows prunes old points, so the count can stay the same; a newer sequence number means a new one.
    $after = Get-TuneupNewestRestorePoint -Quiet
    if ($after -gt $before) { 'created' } else { 'skipped-recent' }
}
