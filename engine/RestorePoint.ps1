function New-TuneupRestorePoint {
    param([Parameter(Mandatory)][string]$Description)
    try {
        $before = @(Get-ComputerRestorePoint -ErrorAction Stop).Count
    } catch {
        return 'unavailable'
    }
    try {
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        return 'failed'
    }
    $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    if ($after -gt $before) { 'created' } else { 'skipped-recent' }
}
