function ConvertTo-TuneupList {
    param([AllowEmptyCollection()][string[]]$Value = @())
    @($Value | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function ConvertTo-TuneupPlanView {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan)
    foreach ($item in $Plan) {
        [pscustomobject]@{
            id             = $item.Id
            title          = Get-TuneupTitle -Tweak $item.Tweak
            risk           = $item.Tweak.risk
            scope          = $item.Tweak.scope
            action         = $item.Action
            reason         = $item.Reason
            rebootRequired = [bool]$item.Tweak.rebootRequired
        }
    }
}

function Write-TuneupJson {
    param([Parameter(Mandatory)]$Object)
    Write-Output (ConvertTo-Json -InputObject $Object -Depth 10)
}

function Add-TuneupJsonWarning {
    param([Parameter(Mandatory)]$Document, [AllowEmptyCollection()][string[]]$Warnings = @())
    # A copy, so the report saved in the run folder does not change.
    $copy = $Document | Select-Object -Property *
    $copy | Add-Member -NotePropertyName warnings -NotePropertyValue ([string[]]@($Warnings)) -Force
    $copy
}

function Write-TuneupPlanReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    $items = @(ConvertTo-TuneupPlanView -Plan $Plan)
    $toApply = @($items | Where-Object { $_.action -eq 'apply' }).Count
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'plan'
            environment   = $Environment
            items         = $items
            summary       = [pscustomobject]@{ apply = $toApply; skip = $items.Count - $toApply }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'plan.header' -Format $toApply, ($items.Count - $toApply))
    foreach ($item in $items) {
        if ($item.action -eq 'apply') {
            Write-Host (Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")) -ForegroundColor Cyan
        } else {
            Write-Host (Get-TuneupText -Key 'plan.skip' -Format $item.title, (Get-TuneupText -Key "reason.$($item.reason)")) -ForegroundColor DarkGray
        }
    }
    if (-not $toApply) { Write-Host (Get-TuneupText -Key 'nothing') -ForegroundColor Green }
}

function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment
    )
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status }).Count }
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = $Environment
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { $_.status -eq 'applied' -and $_.rebootRequired }).Count -gt 0)
        summary        = [pscustomobject]@{
            applied    = & $count 'applied'
            notApplied = & $count 'not-applied'
            failed     = & $count 'failed'
            skipped    = & $count 'skipped'
        }
        results        = $Results
    }
}

function Write-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $colors = @{ 'applied' = 'Green'; 'not-applied' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Report.results) {
        if ($result.status -eq 'skipped') { continue }
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title) -ForegroundColor $colors[$result.status]
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    $summary = $Report.summary
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.notApplied, $summary.failed, $summary.skipped)
    Write-Host (Get-TuneupText -Key "restore.$($Report.restorePoint)")
    Write-Host (Get-TuneupText -Key 'run.saved' -Format $Report.runId, $Report.runDir)
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}

function Write-TuneupStatusReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{ schemaVersion = 1; command = 'status'; items = $Items }))
        return
    }
    if (-not $Items.Count) { Write-Host (Get-TuneupText -Key 'status.empty'); return }
    Write-Host (Get-TuneupText -Key 'status.header')
    $colors = @{ 'ok' = 'Green'; 'drift' = 'Yellow'; 'not-present' = 'DarkGray'; 'unknown' = 'Red' }
    foreach ($item in $Items) {
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($item.status)"), "$($item.title) ($($item.runId))") -ForegroundColor $colors[$item.status]
    }
}

function Write-TuneupUndoReport {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    $restored = @($Results | Where-Object { $_.status -eq 'restored' }).Count
    $failed = @($Results | Where-Object { $_.status -eq 'failed' }).Count
    $skipped = @($Results | Where-Object { $_.status -eq 'skipped' }).Count
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'undo'
            runId         = $RunId
            results       = $Results
            summary       = [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'undo.header' -Format $RunId)
    $colors = @{ 'restored' = 'Green'; 'skipped' = 'DarkGray'; 'failed' = 'Red' }
    foreach ($result in $Results) {
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    Write-Host (Get-TuneupText -Key 'undo.summary' -Format $restored, $failed)
}

function Write-TuneupErrorReport {
    param(
        [Parameter(Mandatory)][string]$Message,
        [AllowEmptyCollection()][string[]]$Details = @(),
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'error'
            message       = $Message
            details       = [string[]]@($Details)
        }))
        return
    }
    Write-Host $Message -ForegroundColor Red
    foreach ($detail in $Details) { Write-Host "  - $detail" -ForegroundColor Red }
}
