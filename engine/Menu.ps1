# The interactive menu: tuneup.ps1 without a command. Questions and answers go through $Context.Io
# (Io.ps1) and the work through the same commands as the command line (Commands.ps1). Every answer is
# a line of text (a number, a letter, or Enter alone), so it works the same in the Windows PowerShell
# console, Windows Terminal and a redirected input. The end of the input means back, all the way out.
# Marks are text ([x], (administrator), [high risk]), never a color alone.

# The text of a { es, en } object in the language of the session.
function Get-TuneupLocalizedText {
    param([AllowNull()]$Text)
    if ($null -eq $Text) { return '' }
    $value = $Text.((Get-TuneupLang))
    if (-not $value) { $value = $Text.en }
    [string]$value
}

# An answer of the menu; $null, and the context marked, when the input ended.
function Read-TuneupMenuAnswer {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupIoAnswer -Io $Context.Io -Prompt $Prompt
    if ($null -eq $answer) { $Context.InputEnded = $true }
    $answer
}

function Read-TuneupMenuConfirmation {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
    ($null -ne $answer) -and ($answer -match (Get-TuneupText -Key 'confirm.pattern'))
}

function Write-TuneupMenuLine {
    param([Parameter(Mandatory)]$Context, [AllowEmptyString()][string]$Text = '')
    Write-TuneupIoLine -Io $Context.Io -Text $Text
}

# Numbers typed to pick items from a list of Count: "2,4" or "2 4". $null when something else was typed.
function ConvertFrom-TuneupMenuNumberList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][int]$Count)
    $numbers = @()
    foreach ($part in @($Text -split '[,\s]+' | Where-Object { $_ })) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $Count) { return $null }
        $numbers += $number
    }
    , @($numbers)
}

# Lets the person turn items on and off by number until Enter alone. Gives the chosen indexes, or
# $null to go back (0, or the end of the input). Locked indexes stay chosen.
function Select-TuneupMenuItem {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$Prompt,
        [int[]]$Chosen = @(),
        [int[]]$Locked = @()
    )
    $selected = New-Object System.Collections.Generic.List[int]
    foreach ($index in @($Chosen) + @($Locked)) { if (-not $selected.Contains($index)) { $selected.Add($index) } }
    while ($true) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $mark = $(if ($selected.Contains($i)) { '[x]' } else { '[ ]' })
            Write-TuneupMenuLine -Context $Context -Text ('  {0} {1,2}. {2}' -f $mark, ($i + 1), $Lines[$i])
        }
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '0') { return $null }
        if ($answer -eq '') { return , @($selected | Sort-Object) }
        $numbers = ConvertFrom-TuneupMenuNumberList -Text $answer -Count $Lines.Count
        if ($null -eq $numbers) {
            Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
            continue
        }
        foreach ($number in $numbers) {
            $index = $number - 1
            if ($Locked -contains $index) { continue }
            if ($selected.Contains($index)) { [void]$selected.Remove($index) } else { $selected.Add($index) }
        }
    }
}

function Write-TuneupMenuHeader {
    param([Parameter(Mandatory)]$Context)
    $environment = Get-TuneupContextEnvironment -Context $Context
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.title' -Format (Get-TuneupVersion), $environment.Family, $environment.Edition, $environment.Build)
    $adminKey = $(if ($environment.IsAdmin) { 'menu.admin.yes' } else { 'menu.admin.no' })
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key $adminKey)
    if ($environment.IsManaged) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.managed') }
    Write-TuneupMenuLine -Context $Context
    foreach ($key in 'menu.main.optimize', 'menu.main.status', 'menu.main.undo', 'menu.main.health', 'menu.main.measure', 'menu.main.exit') {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key $key)
    }
}

function Invoke-TuneupMenu {
    param([Parameter(Mandatory)]$Context)
    $Context.InputEnded = $false
    while (-not $Context.InputEnded) {
        Write-TuneupMenuHeader -Context $Context
        $choice = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.choose')
        $action = switch ($choice) {
            '1' { 'Optimize' }
            '2' { 'Status' }
            '3' { 'Undo' }
            '4' { 'Health' }
            '5' { 'Measure' }
            default { $null }
        }
        if ($null -eq $choice -or $choice -eq '0') { break }
        if ($null -eq $action) {
            Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
            continue
        }
        # A failure ends that option, not the menu: it is shown and the menu comes back.
        try {
            & "Invoke-TuneupMenu$action" -Context $Context
        } catch {
            Write-TuneupErrorReport -Message $_.Exception.Message
        }
        if ($Context.InputEnded) { break }
        if ($null -eq (Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.back'))) { break }
    }
    $Context.ExitCode = 0
}

# Profiles, then the high-risk tweaks (only on request), then one question per tweak that asks first,
# then the plan with its warnings and the confirmation (Invoke-TuneupPlannedApply).
function Invoke-TuneupMenuOptimize {
    param([Parameter(Mandatory)]$Context)
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) { Write-TuneupCommandError -Context $Context -Message $unsupported; return }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
        return
    }
    $profileIds = Select-TuneupMenuProfile -Context $Context -Definition $definition
    if ($null -eq $profileIds) { return }
    $highRisk = Select-TuneupMenuHighRisk -Context $Context -Definition $definition
    if ($null -eq $highRisk) { return }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $profileIds -Include $highRisk -Interactive)
    $declined = Request-TuneupMenuAskedTweak -Context $Context -Plan $plan -Requested $highRisk
    if ($null -eq $declined) { return }
    $environment = Get-TuneupContextEnvironment -Context $Context
    $needsAdmin = @($plan | Where-Object { $_.Action -eq 'apply' -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count
    if ($needsAdmin -and -not $environment.IsAdmin) {
        # The plan is shown anyway, so the person sees what needs administrator before going back.
        Write-TuneupPlanReport -Plan $plan -Environment $environment
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.optimize.needsAdmin')
        return
    }
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $profileIds -Include $highRisk -Exclude $declined
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request
}

# The profiles to apply (base is always on). $null to go back.
function Select-TuneupMenuProfile {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $byId = @{}
    foreach ($tweak in $Definition.Catalog) { $byId[[string]$tweak.id] = $tweak }
    $profiles = @(@($Definition.Profiles | Where-Object { $_.id -eq 'base' }) + @($Definition.Profiles | Where-Object { $_.id -ne 'base' }))
    $lines = @(foreach ($profileData in $profiles) {
        $admin = @($profileData.include | Where-Object { $byId.ContainsKey([string]$_) -and (Test-TuneupTweakNeedsAdmin -Tweak $byId[[string]$_]) }).Count
        $line = '{0} ({1}): {2}' -f (Get-TuneupLocalizedText $profileData.title), $profileData.id, (Get-TuneupLocalizedText $profileData.description)
        if ($admin) { $line += ' ' + (Get-TuneupText -Key 'menu.profile.admin') }
        if ($profileData.id -eq 'base') { $line += ' ' + (Get-TuneupText -Key 'menu.profile.always') }
        $line
    })
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.profiles.header')
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Locked @(0) -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen) { return $null }
    , @($chosen | Where-Object { $_ -ne 0 } | ForEach-Object { [string]$profiles[$_].id })
}

# High-risk tweaks are never in a profile: they are offered only when asked for, and added only after
# typing the confirmation word in full. Gives their ids (none is an empty list), or $null to go back.
function Select-TuneupMenuHighRisk {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $candidates = @($Definition.Catalog | Where-Object { $_.risk -eq 'high' -and (Test-TuneupCompatible -Tweak $_ -Environment $environment) })
    if (-not $candidates.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    $wanted = Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.high.offer' -Format $candidates.Count)
    if ($Context.InputEnded) { return $null }
    if (-not $wanted) { return , @() }
    $lines = @(foreach ($tweak in $candidates) {
        '{0} {1} ({2}): {3}' -f (Get-TuneupText -Key 'menu.high.mark'), (Get-TuneupTitle -Tweak $tweak), $tweak.id, (Get-TuneupLocalizedText $tweak.why)
    })
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen) { return $null }
    if (-not @($chosen).Count) { return , @() }
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.warning')
    $word = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.high.confirm' -Format (Get-TuneupText -Key 'menu.high.word'))
    if ($null -eq $word) { return $null }
    if ($word -ine (Get-TuneupText -Key 'menu.high.word')) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.notAdded')
        return , @()
    }
    , @($chosen | ForEach-Object { [string]$candidates[$_].id })
}

# A tweak of high risk that Windows reverted does not come back on its own either: each one is shown
# and applied again only after typing the confirmation word in full. Gives the ids confirmed (none is
# an empty list), or $null when the input ended.
function Confirm-TuneupMenuReappliedHighRisk {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][object[]]$Catalog, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Ids)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $high = @($Ids | ForEach-Object { $id = $_; $Catalog | Where-Object { $_.id -eq $id } } |
        Where-Object { $_.risk -eq 'high' -and (Test-TuneupCompatible -Tweak $_ -Environment $environment) })
    $confirmed = New-Object System.Collections.Generic.List[string]
    if (-not $high.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.warning')
    foreach ($tweak in $high) {
        Write-TuneupMenuLine -Context $Context -Text ('{0} {1} ({2}): {3}' -f (Get-TuneupText -Key 'menu.high.mark'), (Get-TuneupTitle -Tweak $tweak), $tweak.id, (Get-TuneupLocalizedText $tweak.why))
        $word = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.reapply.highConfirm' -Format (Get-TuneupText -Key 'menu.high.word'))
        if ($null -eq $word) { return $null }
        if ($word -ieq (Get-TuneupText -Key 'menu.high.word')) { $confirmed.Add([string]$tweak.id) }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.reapply.highSkipped' -Format (Get-TuneupTitle -Tweak $tweak)) }
    }
    , @($confirmed.ToArray())
}

# One question for each tweak of the plan that asks first (ask: true) and was not asked for by name:
# yes, no, yes to all the rest or no to all the rest. A no turns the item into a skip with the reason
# declined. Gives the ids said no to, or $null to go back.
function Request-TuneupMenuAskedTweak {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan, [AllowEmptyCollection()][string[]]$Requested = @())
    $asked = @($Plan | Where-Object { $_.Action -eq 'apply' -and $_.Tweak.ask -and $Requested -notcontains $_.Id })
    $declined = New-Object System.Collections.Generic.List[string]
    if (-not $asked.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.ask.header' -Format $asked.Count)
    $rest = $null
    for ($i = 0; $i -lt $asked.Count; $i++) {
        $item = $asked[$i]
        $answer = $rest
        if ($null -eq $answer) {
            Write-TuneupMenuLine -Context $Context -Text ('{0}/{1} {2} [{3}]: {4}' -f ($i + 1), $asked.Count, (Get-TuneupTitle -Tweak $item.Tweak),
                (Get-TuneupText -Key "risk.$($item.Tweak.risk)"), (Get-TuneupLocalizedText $item.Tweak.why))
            while ($null -eq $answer) {
                $typed = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.ask.prompt')
                if ($null -eq $typed) { return $null }
                $answer = switch ($typed.ToLowerInvariant()) {
                    (Get-TuneupText -Key 'menu.ask.yes') { 'yes' }
                    (Get-TuneupText -Key 'menu.ask.no') { 'no' }
                    (Get-TuneupText -Key 'menu.ask.all') { 'all' }
                    (Get-TuneupText -Key 'menu.ask.none') { 'none' }
                    default { $null }
                }
                if ($null -eq $answer) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid') }
            }
            if ($answer -eq 'all') { $rest = 'yes'; $answer = 'yes' }
            if ($answer -eq 'none') { $rest = 'no'; $answer = 'no' }
        }
        if ($answer -eq 'no') {
            $item.Action = 'skip'
            $item.Reason = 'declined'
            $declined.Add($item.Id)
        }
    }
    , @($declined.ToArray())
}

# The status, and when Windows reverted something, the offer to apply it again.
function Invoke-TuneupMenuStatus {
    param([Parameter(Mandatory)]$Context)
    Invoke-TuneupStatusCommand -Context $Context
    $items = @($Context.Result)
    $drifted = @($items | Where-Object { $_.status -eq 'drift' }).Count
    if (-not $drifted) { return }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.status.reapply' -Format $drifted)
    if ($answer -ine (Get-TuneupText -Key 'menu.status.reapplyKey')) { return }
    Invoke-TuneupReapply -Context $Context -Items $items -Interactive
}

# The runs that can be undone, newest first; then the whole run or one of its tweaks.
function Invoke-TuneupMenuUndo {
    param([Parameter(Mandatory)]$Context)
    $runs = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupRunList -StateRoot $Context.StateRoot } |
        Where-Object { Test-TuneupRunHasJournal -Dir $_.Dir })
    [array]::Reverse($runs)
    $runs = @($runs | Select-Object -First 15)
    if (-not $runs.Count) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'undo.none'); return }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.header')
    for ($i = 0; $i -lt $runs.Count; $i++) {
        $run = $runs[$i]
        $count = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupJournal -Path (Join-Path $run.Dir 'snapshot.jsonl') -Root $run.Root }).Count
        $state = $(if ($run.Undone -or (Test-TuneupRunAllNotedUndone -Run $run)) { 'menu.undo.state.undone' }
            elseif (@(Get-TuneupUndoneTweakId -Run $run).Count) { 'menu.undo.state.partly' } else { 'menu.undo.state.pending' })
        $where = switch ($run.Root) { 'machine' { 'menu.undo.root.machine' } 'user' { 'menu.undo.root.user' } default { 'menu.undo.root.custom' } }
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1}  {2}  {3}  {4}' -f ($i + 1), $run.Id, (Get-TuneupText -Key 'menu.undo.tweaks' -Format $count),
            (Get-TuneupText -Key $state), (Get-TuneupText -Key $where))
    }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickRun')
    $numbers = $(if ($answer) { ConvertFrom-TuneupMenuNumberList -Text $answer -Count $runs.Count } else { $null })
    if ($null -eq $numbers -or @($numbers).Count -ne 1) { return }
    $run = $runs[$numbers[0] - 1]
    $how = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.how')
    if ($how -ieq (Get-TuneupText -Key 'menu.undo.wholeKey')) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmRun' -Format $run.Id)) {
            Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id
        }
        return
    }
    if ($how -ine (Get-TuneupText -Key 'menu.undo.tweakKey')) { return }
    $entries = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run })
    $done = @(Get-TuneupUndoneTweakId -Run $run)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $mark = $(if ($done -contains $entries[$i].id) { ' ' + (Get-TuneupText -Key 'menu.undo.state.undone') } else { '' })
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1} ({2}){3}' -f ($i + 1), (Get-TuneupTitle -Tweak $entries[$i].tweak), $entries[$i].id, $mark)
    }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickTweak')
    $numbers = $(if ($answer) { ConvertFrom-TuneupMenuNumberList -Text $answer -Count $entries.Count } else { $null })
    if ($null -eq $numbers -or @($numbers).Count -ne 1) { return }
    $entry = $entries[$numbers[0] - 1]
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmTweak' -Format (Get-TuneupTitle -Tweak $entry.tweak))) {
        Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id -TweakId ([string]$entry.id)
    }
}

# SFC and DISM, and when they find damage that can be repaired, the offer to repair it now (without
# checking again: the check that was just made is reused).
function Invoke-TuneupMenuHealth {
    param([Parameter(Mandatory)]$Context)
    if (-not (Get-TuneupContextEnvironment -Context $Context).IsAdmin) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'err.healthNeedsAdmin')
        return
    }
    if (-not (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.confirm'))) { return }
    Invoke-TuneupHealthCommand -Context $Context
    $report = $Context.Result
    if ($null -eq $report -or $report.recommendation -ne 'run-repair') { return }
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.repair')) {
        Invoke-TuneupHealthCommand -Context $Context -Repair -Previous $report
    }
}

# A measurement after some seconds idle, compared with the last one if there is one and the person wants.
function Invoke-TuneupMenuMeasure {
    param([Parameter(Mandatory)]$Context)
    $seconds = $null
    while ($null -eq $seconds) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.idle')
        if ($null -eq $answer) { return }
        if ($answer -eq '') { $seconds = 0; break }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 0 -and $number -le 3600) { $seconds = $number }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'err.idleSecondsRange' -Format 0, 3600) }
    }
    $compare = $null
    $earlier = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupMeasurementList -StateRoot $Context.StateRoot })
    if ($earlier.Count) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.compare' -Format $earlier[-1].Id)) { $compare = 'last' }
        if ($Context.InputEnded) { return }
    }
    Invoke-TuneupMeasureCommand -Context $Context -IdleSeconds $seconds -Compare $compare
}
