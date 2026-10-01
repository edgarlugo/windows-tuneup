# The interactive menu: tuneup.ps1 without a command. Questions and answers go through $Context.Io
# (Io.ps1, Prompts.ps1) and the work through the same commands as the command line (Commands.ps1).
# Every answer is a line of text (a number, a letter, or Enter alone), so it works the same in the
# Windows PowerShell console, Windows Terminal and a redirected input. The end of the input means
# back, all the way out. Marks are text ([x], (administrator), [high risk]), never a color alone.

# Numbers typed to pick items from a list of Count: "2,4" or "2 4"; each one counts once. $null when
# something else was typed.
function ConvertFrom-TuneupMenuNumberList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][int]$Count)
    $numbers = @()
    foreach ($part in @($Text -split '[,\s]+' | Where-Object { $_ })) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $Count) { return $null }
        if ($numbers -notcontains $number) { $numbers += $number }
    }
    , @($numbers)
}

# One number of a list of Count items; anything else is said to be invalid and asked again. $null for
# Enter alone (back) and for the end of the input.
function Read-TuneupMenuNumber {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][int]$Count)
    while ($true) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '') { return $null }
        $numbers = ConvertFrom-TuneupMenuNumberList -Text $answer -Count $Count
        if ($null -ne $numbers -and @($numbers).Count -eq 1) { return [int]@($numbers)[0] }
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
    }
}

# One of the given letters (any case); anything else is said to be invalid and asked again. $null for
# Enter alone (back) and for the end of the input.
function Read-TuneupMenuKey {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][string[]]$Keys)
    while ($true) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '') { return $null }
        foreach ($key in $Keys) { if ($answer -ieq $key) { return $key } }
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
    }
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
            if ($Locked -contains $index) {
                Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.select.locked' -Format $number)
                continue
            }
            if ($selected.Contains($index)) { [void]$selected.Remove($index) } else { $selected.Add($index) }
        }
    }
}

# Why the menu cannot ask anything, or nothing when it can: PowerShell started with -NonInteractive
# and an input that is not redirected has nobody to answer, and Read-Host would fail with a PowerShell
# error. Gives the text for the person.
function Get-TuneupMenuBlockMessage {
    param(
        [string[]]$CommandLineArgument = [Environment]::GetCommandLineArgs(),
        [bool]$InputRedirected = [Console]::IsInputRedirected
    )
    $nonInteractive = @($CommandLineArgument | Where-Object { $_ -match '^[-/]noni' }).Count -gt 0
    if ($nonInteractive -and -not $InputRedirected) { Get-TuneupText -Key 'menu.nonInteractive' }
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

# The options come back to the menu when they finish; an option that printed something asks for Enter
# first ($Context.Pause), so the screen is not wiped before it is read. The exit code is 0 when the
# menu is left with 0 or at the end of the input: an option that fails shows its error and the menu
# goes on, so the failure is not the code of the session. Ctrl+C at a prompt stops PowerShell itself:
# the code is then the one of the last option (0 at the main prompt).
function Invoke-TuneupMenu {
    param([Parameter(Mandatory)]$Context)
    $Context.InputEnded = $false
    $Context.Menu = $true
    while (-not $Context.InputEnded) {
        $Context.ExitCode = 0
        Write-TuneupMenuHeader -Context $Context
        $action = $null
        $leave = $false
        while ($null -eq $action) {
            $choice = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.choose')
            if ($null -eq $choice -or $choice -eq '0') { $leave = $true; break }
            $action = switch ($choice) {
                '1' { 'Optimize' }
                '2' { 'Status' }
                '3' { 'Undo' }
                '4' { 'Health' }
                '5' { 'Measure' }
                default { $null }
            }
            if ($null -eq $action -and $choice -ne '') { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid') }
        }
        if ($leave) { break }
        $Context.Pause = $false
        # A failure ends that option, not the menu: it is shown and the menu comes back.
        try {
            & "Invoke-TuneupMenu$action" -Context $Context
        } catch {
            Write-TuneupErrorReport -Message $_.Exception.Message
            $Context.Pause = $true
        }
        if ($Context.InputEnded) { break }
        if ($Context.Pause -and $null -eq (Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.back'))) { break }
    }
    $Context.Menu = $false
    $Context.ExitCode = 0
}

# The profiles to apply (base is always on). $null to go back.
function Select-TuneupMenuProfile {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $byId = @{}
    foreach ($tweak in $Definition.Catalog) { $byId[[string]$tweak.id] = $tweak }
    $profiles = @(@($Definition.Profiles | Where-Object { $_.id -eq 'base' }) + @($Definition.Profiles | Where-Object { $_.id -ne 'base' }))
    $lines = @(foreach ($profileData in $profiles) {
        $marks = @()
        if (@($profileData.include | Where-Object { $byId.ContainsKey([string]$_) -and (Test-TuneupTweakNeedsAdmin -Tweak $byId[[string]$_]) }).Count) {
            $marks += Get-TuneupText -Key 'menu.profile.admin'
        }
        if ($profileData.id -eq 'base') { $marks += Get-TuneupText -Key 'menu.profile.always' }
        # The marks go right after the title, where they are read first.
        '{0}{1} ({2}): {3}' -f (Get-TuneupLocalizedText $profileData.title), $(if ($marks.Count) { ' ' + ($marks -join ' ') }),
            $profileData.id, (Get-TuneupLocalizedText $profileData.description)
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
    if (-not (Test-TuneupHighRiskWord -Answer $word)) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.notAdded')
        return , @()
    }
    , @($chosen | ForEach-Object { [string]$candidates[$_].id })
}

# When the plan has system changes and PowerShell is not elevated, shows the plan anyway (so the
# person sees what needs administrator) and says so; $true when it did, and the option ends there.
# -Ignore: tweaks that are still to be asked about, which may yet be declined.
function Test-TuneupMenuBlockedByAdministrator {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan, [AllowEmptyCollection()][string[]]$Ignore = @())
    $environment = Get-TuneupContextEnvironment -Context $Context
    if ($environment.IsAdmin) { return $false }
    $needsAdmin = @($Plan | Where-Object { $_.Action -eq 'apply' -and $Ignore -notcontains $_.Id -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count
    if (-not $needsAdmin) { return $false }
    Write-TuneupPlanReport -Plan $Plan -Environment $environment
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.optimize.needsAdmin')
    $Context.Pause = $true
    $true
}

# Profiles, then the high-risk tweaks (only on request), then one question per tweak that asks first,
# then the plan with its warnings and the confirmation (Invoke-TuneupPlannedApply). A plan that needs
# administrator is stopped before any question is asked, unless a tweak that asks could still be the
# only one that needs it.
function Invoke-TuneupMenuOptimize {
    param([Parameter(Mandatory)]$Context)
    $ready = Get-TuneupPlanningDefinition -Context $Context
    if ($ready.Message) {
        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
        $Context.Pause = $true
        return
    }
    $definition = $ready.Definition
    $profileIds = Select-TuneupMenuProfile -Context $Context -Definition $definition
    if ($null -eq $profileIds) { return }
    $highRisk = Select-TuneupMenuHighRisk -Context $Context -Definition $definition
    if ($null -eq $highRisk) { return }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $profileIds -Include $highRisk -Interactive)
    $toAsk = @($plan | Where-Object { $_.Action -eq 'apply' -and $_.Tweak.ask -and $highRisk -notcontains $_.Id } | ForEach-Object { [string]$_.Id })
    if (Test-TuneupMenuBlockedByAdministrator -Context $Context -Plan $plan -Ignore $toAsk) { return }
    $declined = Request-TuneupMenuAskedTweak -Context $Context -Plan $plan -Requested $highRisk
    if ($null -eq $declined) { return }
    if (Test-TuneupMenuBlockedByAdministrator -Context $Context -Plan $plan) { return }
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $profileIds -Include $highRisk -Exclude $declined
    $Context.Pause = $true
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request
}

# The status, and when Windows reverted something, the offer to apply it again.
function Invoke-TuneupMenuStatus {
    param([Parameter(Mandatory)]$Context)
    Invoke-TuneupStatusCommand -Context $Context
    $Context.Pause = $true
    $items = @($Context.Result)
    $drifted = @($items | Where-Object { $_.status -eq 'drift' }).Count
    if (-not $drifted) { return }
    while ($true) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.status.reapply' -Format $drifted)
        if ($null -eq $answer) { return }
        # Enter was the answer to the question: the menu comes back at once.
        if ($answer -eq '') { $Context.Pause = $false; return }
        if ($answer -ieq (Get-TuneupText -Key 'menu.status.reapplyKey')) {
            Invoke-TuneupReapply -Context $Context -Items $items -Interactive
            return
        }
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
    }
}

# The runs that can be undone, newest first (the 15 newest; older ones by command line); then the
# whole run or one of its tweaks. What is already undone is said, not asked about.
function Invoke-TuneupMenuUndo {
    param([Parameter(Mandatory)]$Context)
    $maxRuns = 15
    $all = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupRunList -StateRoot $Context.StateRoot } |
        Where-Object { Test-TuneupRunHasJournal -Dir $_.Dir })
    [array]::Reverse($all)
    $runs = @($all | Select-Object -First $maxRuns)
    if (-not $runs.Count) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'undo.none')
        $Context.Pause = $true
        return
    }
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
    if ($all.Count -gt $maxRuns) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.more' -Format $maxRuns) }
    $number = Read-TuneupMenuNumber -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickRun') -Count $runs.Count
    if ($null -eq $number) { return }
    $run = $runs[$number - 1]
    if ($run.Undone -or (Test-TuneupRunAllNotedUndone -Run $run)) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $run.Id)
        $Context.Pause = $true
        return
    }
    $wholeKey = Get-TuneupText -Key 'menu.undo.wholeKey'
    $tweakKey = Get-TuneupText -Key 'menu.undo.tweakKey'
    $how = Read-TuneupMenuKey -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.how') -Keys @($wholeKey, $tweakKey)
    if ($null -eq $how) { return }
    if ($how -eq $wholeKey) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmRun' -Format $run.Id)) {
            $Context.Pause = $true
            Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id
        }
        return
    }
    $entries = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run })
    $done = @(Get-TuneupUndoneTweakId -Run $run)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $mark = $(if ($done -contains $entries[$i].id) { ' ' + (Get-TuneupText -Key 'menu.undo.state.undone') } else { '' })
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1} ({2}){3}' -f ($i + 1), (Get-TuneupTitle -Tweak $entries[$i].tweak), $entries[$i].id, $mark)
    }
    $number = Read-TuneupMenuNumber -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickTweak') -Count $entries.Count
    if ($null -eq $number) { return }
    $entry = $entries[$number - 1]
    $title = Get-TuneupTitle -Tweak $entry.tweak
    if ($done -contains $entry.id) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.tweakAlreadyUndone' -Format $title)
        $Context.Pause = $true
        return
    }
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmTweak' -Format $title)) {
        $Context.Pause = $true
        Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id -TweakId ([string]$entry.id)
    }
}

# SFC and DISM, and when they find damage that can be repaired, the offer to repair it now (without
# checking again: the check that was just made is reused).
function Invoke-TuneupMenuHealth {
    param([Parameter(Mandatory)]$Context)
    if (-not (Get-TuneupContextEnvironment -Context $Context).IsAdmin) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.health.needsAdmin')
        $Context.Pause = $true
        return
    }
    if (-not (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.confirm'))) { return }
    $Context.Pause = $true
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
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.measure.range' -Format 0, 3600) }
    }
    $compare = $null
    $earlier = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupMeasurementList -StateRoot $Context.StateRoot })
    if ($earlier.Count) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.compare' -Format $earlier[-1].Id)) { $compare = 'last' }
        if ($Context.InputEnded) { return }
    }
    $Context.Pause = $true
    Invoke-TuneupMeasureCommand -Context $Context -IdleSeconds $seconds -Compare $compare
}
