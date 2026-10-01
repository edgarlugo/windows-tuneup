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

function ConvertTo-TuneupEnvironmentView {
    param([Parameter(Mandatory)]$Environment)
    [pscustomobject]@{
        build         = $Environment.Build
        ubr           = $Environment.UBR
        family        = $Environment.Family
        edition       = $Environment.Edition
        isServer      = $Environment.IsServer
        isManaged     = $Environment.IsManaged
        isAdmin       = $Environment.IsAdmin
        hasBattery    = $Environment.HasBattery
        pendingReboot = $Environment.PendingReboot
    }
}

function Write-TuneupJson {
    param([Parameter(Mandatory)]$Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    # ASCII only, so the console code page cannot garble accents on the way out.
    $escaped = [regex]::Replace($json, '[^\x00-\x7F]', { param($match) '\u{0:x4}' -f [int][char]$match.Value })
    Write-Output $escaped
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
    $requiresAdmin = @($items | Where-Object { $_.action -eq 'apply' -and $_.scope -eq 'machine' }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'plan'
            environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
            requiresAdmin = $requiresAdmin
            items         = $items
            summary       = [pscustomobject]@{ apply = $toApply; skip = $items.Count - $toApply }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'plan.header' -Format $toApply, ($items.Count - $toApply))
    foreach ($item in $items) {
        if ($item.action -eq 'apply') {
            $line = Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")
            if ($item.reason) { $line += ": $(Get-TuneupText -Key "reason.$($item.reason)")" }
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host (Get-TuneupText -Key 'plan.skip' -Format $item.title, (Get-TuneupText -Key "reason.$($item.reason)")) -ForegroundColor DarkGray
        }
    }
    if (-not $toApply) { Write-Host (Get-TuneupText -Key 'nothing') -ForegroundColor Green }
    if ($requiresAdmin -and -not $Environment.IsAdmin) { Write-Host (Get-TuneupText -Key 'plan.needsAdmin') -ForegroundColor Yellow }
}

function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment
    )
    # A tweak left out because its backup could not be written was not done: it is counted apart.
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status -and $_.reason -ne 'journal-error' }).Count }
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = ConvertTo-TuneupEnvironmentView -Environment $Environment
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            partial       = & $count 'partial'
            notApplied    =& $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
        }
        results        = $Results
    }
}

function Save-TuneupApplyReport {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Report)
    # The changes are already made; losing result.json must not hide the report of what was done.
    try {
        Save-TuneupJson -Path (Join-Path $Run.Dir 'result.json') -Root $Run.Root -Object $Report
        $true
    } catch {
        Write-Warning "The result of run $($Run.Id) could not be saved: $($_.Exception.Message)"
        $false
    }
}

# 0: everything done. 2: not everything was completed (a partial, failed or ineffective tweak, a
# backup that could not be written after some change, or an unsaved result; read the summary).
# 1: nothing was changed because the backups could not be written.
function Get-TuneupApplyExitCode {
    param([Parameter(Mandatory)]$Report, [switch]$ResultNotSaved)
    $summary = $Report.summary
    $touched = $summary.applied + $summary.partial + $summary.notApplied + $summary.failed
    if ($summary.journalErrors -and -not $touched) { return 1 }
    if ($summary.partial -or $summary.notApplied -or $summary.failed -or $summary.journalErrors -or $ResultNotSaved) { return 2 }
    0
}

# 0: everything restored. 2: partly restored. 1: nothing restored.
function Get-TuneupUndoExitCode {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)
    $restored = @($Results | Where-Object { $_.status -eq 'restored' }).Count
    $pending = @($Results | Where-Object { $_.status -eq 'failed' -or ($_.status -eq 'skipped' -and $_.reason -ne 'already-undone') }).Count
    if (-not $pending) { return 0 }
    if ($restored) { return 2 }
    1
}

function Write-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Report.results) {
        if ($result.reason -eq 'journal-error') {
            Write-Host ((Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key 'status.skipped'), $result.title) + ": $(Get-TuneupText -Key 'reason.journal-error')") -ForegroundColor Red
            if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
            continue
        }
        if ($result.status -eq 'skipped') { continue }
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title) -ForegroundColor $colors[$result.status]
        if ($result.detail) { Write-Host "    $($result.detail)" -ForegroundColor Yellow }
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    $summary = $Report.summary
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.partial, $summary.notApplied, $summary.failed, $summary.skipped)
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
    $colors = @{ 'ok' = 'Green'; 'drift' = 'Yellow'; 'not-present' = 'DarkGray'; 'unknown' = 'Red'; 'needs-admin' = 'DarkYellow' }
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
    $rebootRequired = @($Results | Where-Object { $_.rebootRequired }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion  = 1
            command        = 'undo'
            runId          = $RunId
            rebootRequired = $rebootRequired
            results        = $Results
            summary        = [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'undo.header' -Format $RunId)
    $colors = @{ 'restored' = 'Green'; 'skipped' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Results) {
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
        if ($result.detail) { Write-Host "    $($result.detail)" -ForegroundColor DarkGray }
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    Write-Host (Get-TuneupText -Key 'undo.summary' -Format $restored, $failed, $skipped)
    if ($rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
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

# The message that has a singular form is chosen by the count it talks about.
function Get-TuneupCountKey {
    param([Parameter(Mandatory)][string]$Key, $Count)
    $(if ($null -ne $Count -and [int]$Count -eq 1) { "$Key.one" } else { $Key })
}

function Get-TuneupStoreTextKey {
    param([Parameter(Mandatory)]$Store, [bool]$RepairRequested)
    switch ($Store.state) {
        'repairable' { Get-TuneupCountKey -Key $(if ($RepairRequested) { 'health.store.repairableNow' } else { 'health.store.repairable' }) -Count $Store.detected }
        'repaired' { Get-TuneupCountKey -Key 'health.store.repaired' -Count $Store.detected }
        'unrepairable' { if ($Store.operationResult -and $Store.operationResult -ne '0x0') { 'health.store.failed' } else { 'health.store.unrepairable' } }
        default { "health.store.$($Store.state)" }
    }
}

function Format-TuneupToolCode {
    param([Parameter(Mandatory)]$Code, $Hex)
    $(if ($Hex) { "$Code ($Hex)" } else { "$Code" })
}

function Write-TuneupHealthScan {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)]$Scan, [switch]$RepairRequested)
    Write-Host $Title
    $sfcColor = $(if ($Scan.sfc.status -eq 'unrepaired' -or $Scan.sfc.status -eq 'unknown') { 'Yellow' } else { 'Gray' })
    Write-Host (Get-TuneupText -Key "health.sfc.$($Scan.sfc.status)") -ForegroundColor $sfcColor
    foreach ($file in @($Scan.sfc.repairedFiles)) { Write-Host (Get-TuneupText -Key 'health.repairedFile' -Format $file) }
    foreach ($file in @($Scan.sfc.unrepairedFiles)) { Write-Host (Get-TuneupText -Key 'health.unrepairedFile' -Format $file) -ForegroundColor Red }
    if ($Scan.sfc.output) {
        $code = Format-TuneupToolCode -Code $Scan.sfc.exitCode -Hex $Scan.sfc.exitCodeHex
        Write-Host (Get-TuneupText -Key 'health.toolError' -Format 'SFC', $code, $Scan.sfc.output) -ForegroundColor DarkGray
    }
    $store = $Scan.componentStore
    $storeColor = $(if ($store.state -eq 'healthy' -or $store.state -eq 'repaired') { 'Gray' } else { 'Yellow' })
    $storeKey = Get-TuneupStoreTextKey -Store $store -RepairRequested:$RepairRequested
    Write-Host (Get-TuneupText -Key $storeKey -Format $store.detected, $store.repaired, $store.operationResult) -ForegroundColor $storeColor
    foreach ($group in @($Scan.corruptComponents)) {
        Write-Host (Get-TuneupText -Key (Get-TuneupCountKey -Key 'health.group' -Count $group.files) -Format $group.name, $group.files)
    }
    if ($store.output) {
        $code = Format-TuneupToolCode -Code $store.exitCode -Hex $store.exitCodeHex
        Write-Host (Get-TuneupText -Key 'health.toolError' -Format 'DISM', $code, $store.output) -ForegroundColor Red
    }
}

function Write-TuneupHealthReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    Write-TuneupHealthScan -Title (Get-TuneupText -Key 'health.before') -Scan $Report.before -RepairRequested:$Report.repairRequested
    if ($Report.repairRan) {
        Write-TuneupHealthScan -Title (Get-TuneupText -Key 'health.after') -Scan $Report.after
    } elseif ($Report.repairRequested) {
        Write-Host (Get-TuneupText -Key 'health.nothingToRepair')
    }
    Write-Host ''
    $color = $(if ($Report.recommendation -eq 'none') { 'Green' } else { 'Yellow' })
    $final = $(if ($Report.repairRan) { $Report.after } else { $Report.before })
    $key = "health.recommendation.$($Report.recommendation)"
    # A manual repair is about DISM unless the store is fine and only SFC could not repair something.
    if ($Report.recommendation -eq 'manual-repair' -and $final.componentStore.state -ne 'unrepairable') { $key = 'health.recommendation.manual-repair-sfc' }
    Write-Host (Get-TuneupText -Key $key) -ForegroundColor $color
    if ($Report.rebootRecommended) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}
function New-TuneupMeasureReport {
    param([Parameter(Mandatory)]$Saved, [AllowNull()]$Against)
    $comparison = $null
    if ($null -ne $Against) {
        $comparison = [pscustomobject]@{
            againstId = $Against.Id
            items     = @(Compare-TuneupMeasurement -Before $Against.Measurement -After $Saved.Measurement)
        }
    }
    [pscustomobject]@{
        schemaVersion = 1
        command       = 'measure'
        id            = $Saved.Id
        path          = $Saved.Path
        measurement   = $Saved.Measurement
        comparison    = $comparison
    }
}

function Format-TuneupMetric {
    param([AllowNull()]$Value, [switch]$Signed)
    if ($null -eq $Value) { return (Get-TuneupText -Key 'measure.none') }
    if ($Signed) { return ('{0:+0.##;-0.##;0}' -f [double]$Value) }
    '{0:0.##}' -f [double]$Value
}

function Write-TuneupMeasureReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $metrics = $Report.measurement.metrics
    Write-Host (Get-TuneupText -Key 'measure.header' -Format $Report.id)
    foreach ($metric in @(Get-TuneupMetricName)) {
        $value = Format-TuneupMetric -Value $metrics.$metric
        $note = $Report.measurement.notes.$metric
        if ($null -eq $metrics.$metric -and $note) { $value = Get-TuneupText -Key "measure.reason.$note" }
        Write-Host (Get-TuneupText -Key 'measure.line' -Format (Get-TuneupText -Key "metric.$metric"), $value)
    }
    Write-Host (Get-TuneupText -Key 'measure.saved' -Format $Report.path)
    if ($null -eq $Report.comparison) { return }
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'measure.compareHeader' -Format $Report.comparison.againstId)
    foreach ($item in $Report.comparison.items) {
        Write-Host (Get-TuneupText -Key 'measure.delta' -Format (Get-TuneupText -Key "metric.$($item.metric)"),
            (Format-TuneupMetric -Value $item.before), (Format-TuneupMetric -Value $item.after), (Format-TuneupMetric -Value $item.delta -Signed))
    }
}