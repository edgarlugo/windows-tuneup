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
            signOutRequired = ($null -ne $item.Tweak.PSObject.Properties['signOutRequired'] -and $item.Tweak.signOutRequired -eq $true)
            requires       = @(if ($null -ne $item.Tweak.PSObject.Properties['requires']) { $item.Tweak.requires })
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
    $copy | Add-Member -NotePropertyName toolVersion -NotePropertyValue (Get-TuneupVersion) -Force
    $copy | Add-Member -NotePropertyName warnings -NotePropertyValue ([string[]]@($Warnings)) -Force
    $copy
}

function Write-TuneupPlanReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [ValidateSet('profiles', 'reapply')][string]$Source = 'profiles',
        [switch]$Json,
        # The caller says it with its own line (the menu, when it stops a plan that needs administrator).
        [switch]$NoAdminHint
    )
    $items = @(ConvertTo-TuneupPlanView -Plan $Plan)
    $toApply = @($items | Where-Object { $_.action -eq 'apply' }).Count
    $requiresAdmin = @($Plan | Where-Object { $_.Action -eq 'apply' -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'plan'
            source        = $Source
            environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
            requiresAdmin = $requiresAdmin
            preflight     = @($Preflight)
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
    if ($requiresAdmin -and -not $Environment.IsAdmin -and -not $NoAdminHint) { Write-Host (Get-TuneupText -Key 'plan.needsAdmin') -ForegroundColor Yellow }
    Write-TuneupPreflight -Preflight $Preflight
}

function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [ValidateSet('profiles', 'reapply')][string]$Source = 'profiles'
    )
    # A tweak left out because its backup could not be written was not done: it is counted apart, and
    # so are the tweaks left out because the run was stopped with Ctrl+C. A tweak that refused to
    # change anything is counted apart from the skips of the plan.
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status -and $_.reason -ne 'journal-error' -and $_.reason -ne 'interrupted' -and $_.refused -ne $true }).Count }
    $interrupted = @($Results | Where-Object { $_.reason -eq 'interrupted' }).Count
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        source         = $Source
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = ConvertTo-TuneupEnvironmentView -Environment $Environment
        preflight      = @($Preflight)
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)
        signOutRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.signOutRequired }).Count -gt 0)
        interrupted    = ($interrupted -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            partial       = & $count 'partial'
            notApplied    = & $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            refused       = @($Results | Where-Object { $_.status -eq 'skipped' -and $_.refused -eq $true }).Count
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
            interrupted   = $interrupted
        }
        results        = $Results
    }
}

# A copy of an object with some of its fields changed; the object itself is left as it is.
function Copy-TuneupObject {
    param([Parameter(Mandatory)]$Object, [hashtable]$Change = @{})
    $copy = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        $copy[$property.Name] = $(if ($Change.ContainsKey($property.Name)) { $Change[$property.Name] } else { $property.Value })
    }
    [pscustomobject]$copy
}

# Writes result.json, with the profile folder and the account name hidden (Hide-TuneupPersonalData)
# field by field, only where they can appear: the run folder, the messages of the preflight and the
# error and detail of each result. Ids, statuses, reasons and titles are written as they are: -Status
# reads the ids of this file. The file is meant to be read and shared, and the run folder it names is
# under the profile of the account. Fails when it cannot be written.
function Write-TuneupRunResult {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Report)
    $hide = { param($value) $(if ($value -is [string]) { Hide-TuneupPersonalData -Text $value } else { $value }) }
    $change = @{}
    if ($Report.PSObject.Properties['runDir']) { $change.runDir = & $hide $Report.runDir }
    if ($Report.PSObject.Properties['preflight']) {
        $change.preflight = @(foreach ($item in @($Report.preflight | Where-Object { $null -ne $_ })) {
            $(if ($item.PSObject.Properties['message']) { Copy-TuneupObject -Object $item -Change @{ message = & $hide $item.message } } else { $item })
        })
    }
    if ($Report.PSObject.Properties['results']) {
        $change.results = @(foreach ($result in @($Report.results | Where-Object { $null -ne $_ })) {
            $fields = @{}
            foreach ($name in 'error', 'detail') { if ($result.PSObject.Properties[$name]) { $fields[$name] = & $hide $result.$name } }
            Copy-TuneupObject -Object $result -Change $fields
        })
    }
    $json = ConvertTo-Json -InputObject (Copy-TuneupObject -Object $Report -Change $change) -Depth 10
    Write-TuneupStateFile -Path (Join-Path $Run.Dir 'result.json') -Text $json -Root $Run.Root
}

function Save-TuneupApplyReport {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Report)
    # The changes are already made; losing result.json must not hide the report of what was done.
    try {
        Write-TuneupRunResult -Run $Run -Report $Report
        $true
    } catch {
        Write-Warning "The result of run $($Run.Id) could not be saved: $($_.Exception.Message)"
        $false
    }
}

# 0: everything done. 2: not everything was completed (a partial, failed or ineffective tweak, a
# backup that could not be written after some change, or an unsaved result; read the summary).
# A tweak that refused to change anything (summary.refused) is an omission, like any skip: if
# everything else was done, the code stays 0 and the summary and the line of that tweak say why.
# 1: nothing was changed because the backups could not be written, or because Ctrl+C stopped the
# run before its first tweak. Tweaks left out by Ctrl+C after others were touched count as not done (2).
function Get-TuneupApplyExitCode {
    param([Parameter(Mandatory)]$Report, [switch]$ResultNotSaved)
    $summary = $Report.summary
    $interrupted = $(if ($summary.PSObject.Properties['interrupted']) { [int]$summary.interrupted } else { 0 })
    $touched = $summary.applied + $summary.partial + $summary.notApplied + $summary.failed
    if (($summary.journalErrors -or $interrupted) -and -not $touched) { return 1 }
    if ($summary.partial -or $summary.notApplied -or $summary.failed -or $summary.journalErrors -or $interrupted -or $ResultNotSaved) { return 2 }
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
        [switch]$Json,
        # Shown from the menu: what it says about undoing names the menu, not a parameter.
        [switch]$FromMenu
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $suffix = $(if ($FromMenu) { '.menu' } else { '' })
    $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red'; 'skipped' = 'Yellow' }
    foreach ($result in $Report.results) {
        if ($result.reason -eq 'journal-error') {
            Write-Host ((Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key 'status.skipped'), $result.title) + ": $(Get-TuneupText -Key 'reason.journal-error')") -ForegroundColor Red
            if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
            continue
        }
        # Skips of the plan were already shown, and the tweaks left out by Ctrl+C are counted below; a
        # tweak that refused to change anything when it was applied is shown with its reason.
        if ($result.status -eq 'skipped' -and $result.refused -ne $true) { continue }
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.status -eq 'skipped' -and $result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
        if ($result.detail) { Write-Host "    $($result.detail)" -ForegroundColor Yellow }
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    $summary = $Report.summary
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.partial, $summary.notApplied, $summary.failed, $summary.skipped, $summary.refused)
    if ($summary.PSObject.Properties['interrupted'] -and $summary.interrupted) {
        Write-Host (Get-TuneupText -Key "interrupted.summary$suffix" -Format $summary.interrupted) -ForegroundColor Yellow
    }
    Write-Host (Get-TuneupText -Key "restore.$($Report.restorePoint)")
    Write-Host (Get-TuneupText -Key "run.saved$suffix" -Format $Report.runId, $Report.runDir)
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
    # A restart also signs the user out, so the sign-out line is only needed without one.
    elseif ($Report.signOutRequired) { Write-Host (Get-TuneupText -Key 'signOut') -ForegroundColor Yellow }
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
    $signOutRequired = @($Results | Where-Object { $_.PSObject.Properties['signOutRequired'] -and $_.signOutRequired }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion   = 1
            command         = 'undo'
            runId           = $RunId
            rebootRequired  = $rebootRequired
            signOutRequired = $signOutRequired
            results         = $Results
            summary         = [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
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
        $manual = @($(if ($result.PSObject.Properties['manual']) { $result.manual }) | Where-Object { $_ })
        if ($manual.Count) {
            Write-Host "    $(Get-TuneupText -Key 'undo.manual')"
            foreach ($line in $manual) { Write-Host "      $line" }
        }
    }
    Write-Host (Get-TuneupText -Key 'undo.summary' -Format $restored, $failed, $skipped)
    if ($rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
    elseif ($signOutRequired) { Write-Host (Get-TuneupText -Key 'signOut') -ForegroundColor Yellow }
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

# Numbers follow the language of the output (decimal comma in Spanish, point in English), not the
# regional settings of the machine, so a report reads the same wherever it runs.
function Get-TuneupNumberFormat {
    if ((Get-TuneupLang) -eq 'es') {
        try {
            return [System.Globalization.CultureInfo]::GetCultureInfo('es-ES')
        } catch {
            # No es-ES data on this system (invariant globalization): the same separator by hand.
            $format = [System.Globalization.NumberFormatInfo][System.Globalization.CultureInfo]::InvariantCulture.NumberFormat.Clone()
            $format.NumberDecimalSeparator = ','
            return $format
        }
    }
    [System.Globalization.CultureInfo]::InvariantCulture
}

function Format-TuneupMetric {
    param([AllowNull()]$Value, [switch]$Signed, [string]$Note)
    if ($null -eq $Value) {
        # A value that is missing for a known reason says the reason instead of n/a.
        if ($Note) { return (Get-TuneupText -Key "measure.reason.$Note") }
        return (Get-TuneupText -Key 'measure.none')
    }
    $format = Get-TuneupNumberFormat
    if ($Signed) { return ([double]$Value).ToString('+0.##;-0.##;0', $format) }
    ([double]$Value).ToString('0.##', $format)
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
        $value = Format-TuneupMetric -Value $metrics.$metric -Note $Report.measurement.notes.$metric
        Write-Host (Get-TuneupText -Key 'measure.line' -Format (Get-TuneupText -Key "metric.$metric"), $value)
    }
    Write-Host (Get-TuneupText -Key 'measure.saved' -Format $Report.path)
    if ($null -eq $Report.comparison) { return }
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'measure.compareHeader' -Format $Report.comparison.againstId)
    foreach ($item in $Report.comparison.items) {
        Write-Host (Get-TuneupText -Key 'measure.delta' -Format (Get-TuneupText -Key "metric.$($item.metric)"),
            (Format-TuneupMetric -Value $item.before -Note $item.beforeNote), (Format-TuneupMetric -Value $item.after -Note $item.afterNote),
            (Format-TuneupMetric -Value $item.delta -Signed))
    }
}