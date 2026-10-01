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

# The status, and when Windows reverted something, the offer to apply it again.
function Invoke-TuneupMenuStatus {
    param([Parameter(Mandatory)]$Context)
    Invoke-TuneupStatusCommand -Context $Context
    $items = @($Context.Result)
    $drifted = @($items | Where-Object { $_.status -eq 'drift' }).Count
    if (-not $drifted) { return }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.status.reapply' -Format $drifted)
    if ($answer -ine (Get-TuneupText -Key 'menu.status.reapplyKey')) { return }
    Invoke-TuneupReapply -Context $Context -Items $items
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
