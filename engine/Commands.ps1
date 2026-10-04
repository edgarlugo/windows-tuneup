# The commands of the tool, shared by the command line (tuneup.ps1) and the menu. Each one writes its
# report (a JSON document on the output with -Json, text for people otherwise), leaves its exit code in
# $Context.ExitCode and what it produced in $Context.Result. A command never calls exit: an error that
# ends it is written as an error report with exit code 1.

# The reason of an error that only an elevated process can get past (-Undo of a run with system
# changes, -Health): a program that drives the tool decides by it, never by the text of the message.
$script:NeedsAdminError = 'needs-admin'

# What one invocation shares between its steps: JSON or text, the folders for testing, the warnings
# collected so far, the questions and answers (Io), the exit code and the last result. The exit code
# starts at 1 and every command sets 0 when it succeeds, so one that dies before reporting is a failure.
# Menu is on while the menu runs, so what a command says about undoing names the menu and not a
# parameter; Pause is set by a menu option that printed something to be read before the menu returns.
function New-TuneupContext {
    param([switch]$Json, $Io)
    [pscustomobject]@{
        PSTypeName   = 'Tuneup.Context'
        Json         = [bool]$Json
        StateRoot    = $null
        CatalogPath  = $null
        ProfilesPath = $null
        Force        = $false
        Warnings     = New-Object System.Collections.Generic.List[string]
        Environment  = $null
        ScriptRoot   = $null
        Io           = $(if ($null -ne $Io) { $Io } else { New-TuneupConsoleIo })
        InputEnded   = $false
        Menu         = $false
        Pause        = $false
        ExitCode     = 1
        Result       = $null
    }
}

# With -Json the warnings go inside the document; otherwise each one is shown once.
function Invoke-TuneupContextStep {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][scriptblock]$Step)
    Invoke-TuneupStepCollectingWarning -Step $Step -Warnings $Context.Warnings -Json:$Context.Json
}

function Write-TuneupCommandError {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Message, [AllowEmptyCollection()][string[]]$Details = @(), [string]$Reason)
    Write-TuneupErrorReport -Message $Message -Details $Details -Reason $Reason -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 1
}

# Runs a command line; whatever it throws becomes an error report and exit code 1. The code is set
# before the report is written, so if the report cannot be written either, the failure still counts.
function Invoke-TuneupGuarded {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][scriptblock]$Command)
    try {
        & $Command
    } catch {
        $Context.ExitCode = 1
        Write-TuneupCommandError -Context $Context -Message $_.Exception.Message
    }
}

function Get-TuneupContextEnvironment {
    param([Parameter(Mandatory)]$Context)
    if ($null -eq $Context.Environment) {
        $Context.Environment = Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupEnvironment }
    }
    $Context.Environment
}

# -Reapply applies again, as a new run, the tweaks that Windows reverted (drift), with the same
# confirmation, -Yes and -WhatIf as applying profiles. People see the status first; with -Json the
# output is the plan or apply document of the re-apply (source reapply).
function Invoke-TuneupStatusCommand {
    param([Parameter(Mandatory)]$Context, [switch]$Reapply, [switch]$PlanOnly, [switch]$Yes, [string[]]$Include = @())
    $items = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupStatus -StateRoot $Context.StateRoot })
    $Context.Result = $items
    if (-not $Reapply) {
        Write-TuneupStatusReport -Items $items -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    if (-not $Context.Json) { Write-TuneupStatusReport -Items $items }
    Invoke-TuneupReapply -Context $Context -Items $items -PlanOnly:$PlanOnly -Yes:$Yes -Include $Include
}

# Plans again, from the catalog of now, the tweaks whose status is drift: only them (no base profile)
# and by name, so a tweak that asks first or is kept by a profile is applied again too; the
# compatibility checks still apply. A drifted tweak that the catalog no longer has is left out with a
# warning: undoing the run that applied it restores it. -Interactive (the menu) asks about the tweaks
# that are left out otherwise: one question for each that asks first, and each one of high risk comes
# back only after typing the confirmation word in full. -Include (the command line) names the drifted
# tweaks to apply again: only those, by name, so one that asks first or has high risk comes back too; a
# named tweak that did not drift is left out with a warning, and an unknown one stops everything.
function Invoke-TuneupReapply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [switch]$PlanOnly,
        [switch]$Yes,
        [switch]$Interactive,
        [string[]]$Include = @()
    )
    # In the order of the runs that applied them, not alphabetical.
    $drifted = @($Items | Where-Object { $_.status -eq 'drift' } | ForEach-Object { [string]$_.id } | Select-Object -Unique)
    $named = @($Include | Where-Object { $_ } | Select-Object -Unique)
    if (-not $drifted.Count -and -not $Context.Json -and -not $named.Count) {
        # Without administrator some tweaks cannot be checked: that is not the same as nothing to do.
        $unverified = @($Items | Where-Object { $_.status -eq 'needs-admin' }).Count
        $line = $(if ($unverified) { Get-TuneupText -Key 'reapply.noneUnverified' -Format $unverified } else { Get-TuneupText -Key 'reapply.none' })
        Write-TuneupIoLine -Io $Context.Io -Text $line
        $Context.ExitCode = 0
        return
    }
    $ready = Get-TuneupPlanningDefinition -Context $Context
    if ($ready.Message) {
        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
        return
    }
    $definition = $ready.Definition
    $known = @{}
    foreach ($tweak in $definition.Catalog) { $known[[string]$tweak.id] = $true }
    $missing = @($drifted | Where-Object { -not $known.ContainsKey($_) })
    if ($missing.Count) {
        Invoke-TuneupContextStep -Context $Context -Step {
            foreach ($id in $missing) {
                # A startup entry is never in the catalog: it is turned off again from what starts now
                # (-Startup -Disable), which reads the entry again.
                if (Test-TuneupStartupId -Id $id) { Write-Warning (Get-TuneupText -Key 'reapply.startupEntry' -Format $id) }
                else { Write-Warning "Tweak $id was reverted but is no longer in the catalog: undo the run that applied it to restore it" }
            }
        }
    }
    $ids = @($drifted | Where-Object { $known.ContainsKey($_) })
    $confirmed = @()
    if ($named.Count) {
        # A startup entry named here is not unknown: it is left out with its own warning.
        $unknown = @($named | Where-Object { -not $known.ContainsKey($_) -and -not (Test-TuneupStartupId -Id $_) })
        if ($unknown.Count) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.unknownTweak' -Format ($unknown -join ', '))
            return
        }
        # Without administrator, -Status cannot check some tweaks (apps, capabilities, features): one of
        # those may have been reverted, and the warning says so.
        $notDriftedKey = $(if ((Get-TuneupContextEnvironment -Context $Context).IsAdmin) { 'reapply.notReverted' } else { 'reapply.notRevertedUnverified' })
        Invoke-TuneupContextStep -Context $Context -Step {
            # A startup entry that came back already has its own warning (reapply.startupEntry).
            foreach ($id in @($named | Where-Object { $ids -notcontains $_ -and $missing -notcontains $_ })) { Write-Warning (Get-TuneupText -Key $notDriftedKey -Format $id) }
        }
        $ids = @($ids | Where-Object { $named -contains $_ })
        $confirmed = $ids
    }
    # Named like a profile names them, not asked for: a tweak that asks first or has high risk is left
    # out (needs-confirmation, high-risk-not-requested) and the plan says so; the menu asks about those,
    # and -Include names them.
    if ($Interactive) {
        # Like Optimize: a plan that needs administrator is stopped before any question, unless only
        # tweaks still to be asked about (that ask first, or of high risk) need it.
        $preview = @(New-TuneupContextPlan -Context $Context -Definition $definition -Candidates $ids -NoBase -Interactive)
        $toAsk = @($preview | Where-Object { $_.Action -eq 'apply' -and $_.Tweak.ask } | ForEach-Object { [string]$_.Id })
        if (Test-TuneupMenuBlockedByAdministrator -Context $Context -Plan $preview -Ignore $toAsk) { return }
        $confirmed = Confirm-TuneupMenuReappliedHighRisk -Context $Context -Catalog $definition.Catalog -Ids $ids
        if ($null -eq $confirmed) { return }
    }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -Candidates $ids -Include $confirmed -NoBase -Interactive:$Interactive)
    $declined = @()
    if ($Interactive) {
        # Back in the order of the runs that applied them: a confirmed tweak is planned first.
        $plan = @(foreach ($id in $ids) { $plan | Where-Object { $_.Id -eq $id } })
        $declined = Request-TuneupMenuAskedTweak -Context $Context -Plan $plan -Requested $confirmed
        if ($null -eq $declined) { return }
        if (Test-TuneupMenuBlockedByAdministrator -Context $Context -Plan $plan) { return }
    }
    $request = New-TuneupApplyRequest -Source 'reapply' -Include $ids -Exclude $declined
    if ($Yes -and -not $PlanOnly -and -not $Context.Json) {
        # With -Yes the plan is not shown, so what is left out is listed here.
        foreach ($item in @($plan | Where-Object { $_.Action -eq 'skip' -and @('needs-confirmation', 'high-risk-not-requested') -contains $_.Reason })) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'reapply.leftOut' -Format (Get-TuneupTitle -Tweak $item.Tweak), (Get-TuneupText -Key "reason.$($item.Reason)"))
        }
    }
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
}

function Invoke-TuneupUndoCommand {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$RunId, [string]$TweakId)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $run = Invoke-TuneupContextStep -Context $Context -Step { Resolve-TuneupRun -StateRoot $Context.StateRoot -RunId $RunId }
    if (-not $run) {
        $missing = $(if ($RunId -eq 'last') { Get-TuneupText -Key 'undo.none' } else { Get-TuneupText -Key 'err.runNotFound' -Format $RunId })
        Write-TuneupCommandError -Context $Context -Message $missing
        return
    }
    # Machine-folder runs always need elevation; a -StateRoot run only for its machine tweaks.
    $needsAdmin = ($run.Root -eq 'machine')
    if (-not $needsAdmin) {
        # Its warnings come again, once, from the undo itself.
        $needsAdmin = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue } |
            Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.tweak }).Count -gt 0
    }
    if ($needsAdmin -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.undoNeedsAdmin' -Format $run.Id) -Reason $script:NeedsAdminError
        return
    }
    # Arguments of a step go in a table: PSScriptAnalyzer does not see a parameter used only inside it.
    $undoArguments = @{ Run = $run; TweakId = $TweakId }
    $results = @(Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupUndo @undoArguments })
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupUndoTranscript -Context $Context -Run $run -Results $results }
    $Context.Result = $results
    Write-TuneupUndoReport -RunId $run.Id -Results $results -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupUndoExitCode -Results $results
}

# -Previous: a health report whose check is reused, so -Repair only repairs (the menu offers it).
function Invoke-TuneupHealthCommand {
    param([Parameter(Mandatory)]$Context, [switch]$Repair, $Previous)
    $environment = Get-TuneupContextEnvironment -Context $Context
    if (-not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.healthNeedsAdmin') -Reason $script:NeedsAdminError
        return
    }
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'health.running') }
    # One line per phase for people; with -Json nothing but the document goes to the output.
    $healthArguments = @{ Repair = $Repair; Previous = $Previous }
    if (-not $Context.Json) {
        $io = $Context.Io
        $healthArguments.OnPhase = { param($Name) Write-TuneupIoLine -Io $io -Text (Get-TuneupText -Key "health.phase.$Name") }.GetNewClosure()
    }
    $report = Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupHealth @healthArguments }
    $Context.Result = $report
    Write-TuneupHealthReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupHealthExitCode -Report $report
}

function Invoke-TuneupMeasureCommand {
    param([Parameter(Mandatory)]$Context, [string]$Compare, [int]$IdleSeconds = 0)
    $environment = Get-TuneupContextEnvironment -Context $Context
    # Resolved before measuring, so 'last' is never the new measurement.
    $against = $null
    if ($Compare) {
        $against = Invoke-TuneupContextStep -Context $Context -Step { Resolve-TuneupMeasurement -StateRoot $Context.StateRoot -Id $Compare }
        if (-not $against) {
            $missing = $(if ($Compare -eq 'last') { Get-TuneupText -Key 'err.noMeasurements' } else { Get-TuneupText -Key 'err.measurementNotFound' -Format $Compare })
            Write-TuneupCommandError -Context $Context -Message $missing
            return
        }
    }
    if ($IdleSeconds -gt 0 -and -not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'measure.waiting' -Format $IdleSeconds) }
    $measurement = Invoke-TuneupContextStep -Context $Context -Step { Measure-TuneupSystem -Environment $environment -IdleSeconds $IdleSeconds }
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupMeasurement -Measurement $measurement -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    $report = New-TuneupMeasureReport -Saved $saved -Against $against
    $Context.Result = $report
    Write-TuneupMeasureReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 0
}

# -List: the profiles and the tweaks that suit this machine. It reads the catalog, so it refuses an
# unsupported Windows and a catalog with errors like any command that plans.
function Invoke-TuneupListCommand {
    param([Parameter(Mandatory)]$Context)
    $ready = Get-TuneupPlanningDefinition -Context $Context
    if ($ready.Message) {
        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
        return
    }
    $document = Get-TuneupListDocument -Definition $ready.Definition -Environment (Get-TuneupContextEnvironment -Context $Context)
    $Context.Result = $document
    Write-TuneupListReport -Document $document -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 0
}

# -Suggest: the signals of this machine and the profiles that fit them. It reads no catalog and changes
# nothing; a detector that fails is a warning inside the document.
function Invoke-TuneupSuggestCommand {
    param([Parameter(Mandatory)]$Context)
    $document = Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupSuggestion }
    $Context.Result = $document
    Write-TuneupSuggestReport -Document $document -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 0
}

# -Startup (design, section 15): what starts with Windows or runs in the background, read only. With
# -Disable, the entries named by their id are turned off as a run of the tool: each one becomes a tweak of a
# type that exists (StartupTweak.ps1) and goes through the same plan, confirmation, journal, restore point
# and report as a profile (source startup), so -Status and -Undo work as for any run. Nothing is
# uninstalled or deleted. The entries are read again here, never taken from an earlier list. An id that is
# not in the list now, or that names an entry that stays on, stops everything before any change; an entry
# that is already off is left out of the plan as already applied.
function Invoke-TuneupStartupCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$Disable = @(),
        [switch]$PlanOnly,
        [switch]$Yes
    )
    # A 32-bit PowerShell on a 64-bit Windows sees another HKLM\SOFTWARE and another System32: the list
    # and what it would turn off would be wrong, so nothing is read.
    if (Test-TuneupWow64Process) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupWow64')
        return
    }
    $environment = Get-TuneupContextEnvironment -Context $Context
    # Ids are lowercase; one written in capitals is the same id (and its scope is read from it below).
    $ids = @($Disable | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if ($ids.Count) {
        $unsupported = Get-TuneupUnsupportedMessage -Context $Context
        if ($unsupported) {
            Write-TuneupCommandError -Context $Context -Message $unsupported
            return
        }
        # What is not an id of -Startup can never be in the list: refused before anything is read.
        $malformed = @($ids | Where-Object { -not (Test-TuneupStartupId -Id $_) })
        if ($malformed.Count) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupUnknown' -Format ($malformed -join ', '))
            return
        }
        # Elevated with another administrator's password, HKCU is that administrator's: the entries of the
        # account at this desktop cannot even be seen from here.
        if ($environment.IsAdmin -and $environment.IsSessionUser -eq $false) {
            $userIds = @($ids | Where-Object { (Get-TuneupStartupIdScope -Id $_) -eq 'user' })
            if ($userIds.Count) {
                Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupSessionUser' -Format ($userIds -join ', ')) -Reason 'session-user'
                return
            }
        }
    }
    # On a work PC (managed, or joined to Entra ID) the apps of work are not recommended.
    $workArguments = @{ Environment = $environment }
    $workPc = [bool](@(Invoke-TuneupContextStep -Context $Context -Step { Test-TuneupStartupWorkPc @workArguments }) | Select-Object -Last 1)
    $entryArguments = @{ Rules = Import-TuneupStartupRuleSet; WorkPc = $workPc }
    $entries = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupStartupEntry @entryArguments } | Where-Object { $null -ne $_ })
    if (-not $ids.Count) {
        if (-not $environment.IsAdmin) {
            Invoke-TuneupContextStep -Context $Context -Step { Write-Warning (Get-TuneupText -Key 'startup.unelevatedNote') }
        }
        # Elevated with another administrator's password: what is of the user (Run of the user, its startup
        # folder, Store apps) is that administrator's, not the one of the account at this desktop.
        if ($environment.IsAdmin -and $environment.IsSessionUser -eq $false) {
            Invoke-TuneupContextStep -Context $Context -Step { Write-Warning (Get-TuneupText -Key 'startup.otherAccountNote') }
        }
        $document = Get-TuneupStartupDocument -Entry $entries -IsAdmin ([bool]$environment.IsAdmin) -WorkPc $workPc
        $Context.Result = $document
        Write-TuneupStartupReport -Document $document -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    # An id that more than one entry has could name the wrong one: none of them is turned off.
    Invoke-TuneupContextStep -Context $Context -Step { Set-TuneupStartupAmbiguity -Entry $entries }
    $byId = @{}
    $names = @{}
    foreach ($entry in $entries) {
        $id = [string]$entry.id
        if (-not $byId.ContainsKey($id)) {
            $byId[$id] = $entry
            $names[$id] = New-Object System.Collections.Generic.List[string]
        }
        $names[$id].Add([string]$entry.name)
    }
    $unknown = @($ids | Where-Object { -not $byId.ContainsKey($_) })
    if ($unknown.Count) {
        # Without administrator Windows hides some scheduled tasks: an id of the machine may be one of them.
        $hint = @(if (-not $environment.IsAdmin -and @($unknown | Where-Object { (Get-TuneupStartupIdScope -Id $_) -eq 'machine' }).Count) { Get-TuneupText -Key 'startup.unelevatedNote' })
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupUnknown' -Format ($unknown -join ', ')) -Details $hint
        return
    }
    $chosen = @($ids | ForEach-Object { $byId[$_] })
    # Protected, run once, not read completely, or a name the task handler cannot look up exactly: one line
    # for each, with why.
    $fixed = @($chosen | Where-Object { Get-TuneupStartupFixedReason -Entry $_ })
    if ($fixed.Count) {
        $details = @($fixed | ForEach-Object { Get-TuneupText -Key 'startup.refusedLine' -Format $_.id, ($names[[string]$_.id] -join ', '), (Get-TuneupStartupFixedText -Entry $_) })
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupFixed') -Details $details
        return
    }
    $tweaks = @($chosen | ForEach-Object { ConvertTo-TuneupStartupTweak -Entry $_ })
    $tweakIds = [string[]]@($tweaks | ForEach-Object { [string]$_.id })
    # Named one by one, like -Include: no base profile, and the plan still checks each state (an entry that
    # is already off is left out as already applied) and the account of a user entry.
    $planArguments = @{
        Catalog     = $tweaks
        Profiles    = @()
        Include     = $tweakIds
        NoBase      = $true
        Environment = $environment
        TestState   = { param($tweak) Test-TuneupState -Tweak $tweak }
    }
    $plan = @(Invoke-TuneupContextStep -Context $Context -Step { New-TuneupPlan @planArguments })
    # An entry of the machine needs an elevated process; the plan alone (-WhatIf) does not.
    $machineIds = @($plan | Where-Object { $_.Action -eq 'apply' -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) } | ForEach-Object { [string]$_.Id })
    if ($machineIds.Count -and -not $PlanOnly -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupNeedsAdmin' -Format ($machineIds -join ', ')) -Reason $script:NeedsAdminError
        return
    }
    $request = New-TuneupApplyRequest -Source 'startup' -Include $tweakIds
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
    # Only after something was applied (then the report is the result).
    if (-not $Context.Json -and $null -ne $Context.Result -and $Context.ExitCode -ne 1) {
        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'startup.nextStart')
    }
}

# -ReadResult: the document that a run with -ResultId saved, exactly as it was written, for a caller that
# started the tool elevated (the Claude skill) and reads the result unelevated through the tool instead
# of opening the file itself: the tool checks that only an administrator could have written it. An
# elevated caller reads only the machine folder; an unelevated one also its own folder. A result that
# cannot be read is an error with a stable reason. It reads no catalog, state or environment.
function Invoke-TuneupReadResultCommand {
    param([Parameter(Mandatory)]$Context, [AllowEmptyString()][string]$Id, [string]$StateRoot)
    if ($Id -cnotmatch $script:ResultIdPattern) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.readResultInvalid')
        return
    }
    $readArguments = @{ Id = $Id; IncludeUser = -not (Test-TuneupAdmin) }
    if ($StateRoot) { $readArguments.StateRoot = $StateRoot }
    $read = Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupResultFile @readArguments }
    if ($read.Code) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key $read.Key -Format $Id, $read.Folder) -Reason $read.Code
        return
    }
    $Context.Result = $read.Text
    Write-Output $read.Text
    $Context.ExitCode = 0
}

# Windows Server and builds older than 19041 are refused unless -Force; Server then plans like
# Enterprise, which supports every policy that Server supports. Gives the message of the refusal, or
# nothing. Helpers like this one return values and never write a report: with -Json the report is
# output, and it would be mixed into what the helper returns.
function Get-TuneupUnsupportedMessage {
    param([Parameter(Mandatory)]$Context)
    $environment = Get-TuneupContextEnvironment -Context $Context
    if ($environment.IsServer -and -not $Context.Force) { return (Get-TuneupText -Key 'err.server') }
    if (($environment.Build -lt 19041 -or $environment.Edition -eq 'Unknown') -and -not $Context.Force) {
        return (Get-TuneupText -Key 'err.unsupported')
    }
    if ($environment.IsServer) { $environment.Edition = 'Enterprise' }
}

# The start of every command that plans: the refusal of an unsupported Windows and the catalog with
# its profiles. Gives { Definition, Message, Details }; Message is set when the command cannot go on
# and its caller writes the error (with -Json the report is output, and written here it would be
# mixed into what this returns).
function Get-TuneupPlanningDefinition {
    param([Parameter(Mandatory)]$Context)
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) { return [pscustomobject]@{ Definition = $null; Message = $unsupported; Details = [string[]]@() } }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        return [pscustomobject]@{ Definition = $null; Message = (Get-TuneupText -Key 'err.catalog'); Details = $definition.Problems }
    }
    [pscustomobject]@{ Definition = $definition; Message = $null; Details = [string[]]@() }
}

# The catalog and the profiles, with the problems that the checks found (none when they are valid).
function Import-TuneupContextDefinition {
    param([Parameter(Mandatory)]$Context)
    $catalog = @(Invoke-TuneupContextStep -Context $Context -Step { Import-TuneupCatalog -Path $Context.CatalogPath })
    $profileSet = @(Invoke-TuneupContextStep -Context $Context -Step { Import-TuneupProfileSet -Path $Context.ProfilesPath })
    $problems = @(Test-TuneupCatalog -Catalog $catalog) + @(Test-TuneupProfileSet -Profiles $profileSet -Catalog $catalog)
    [pscustomobject]@{ Catalog = $catalog; Profiles = $profileSet; Problems = [string[]]$problems }
}

function New-TuneupContextPlan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Definition,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [AllowEmptyCollection()][string[]]$Candidates = @(),
        [switch]$Interactive,
        [switch]$NoBase
    )
    $planArguments = @{
        Catalog     = $Definition.Catalog
        Profiles    = $Definition.Profiles
        ProfileIds  = $ProfileIds
        Include     = $Include
        Exclude     = $Exclude
        Candidates  = $Candidates
        Environment = Get-TuneupContextEnvironment -Context $Context
        Interactive = $Interactive
        NoBase      = $NoBase
        TestState   = { param($tweak) Test-TuneupState -Tweak $tweak }
    }
    @(Invoke-TuneupContextStep -Context $Context -Step { New-TuneupPlan @planArguments })
}

function Invoke-TuneupApplyCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $ready = Get-TuneupPlanningDefinition -Context $Context
    if ($ready.Message) {
        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
        return
    }
    $definition = $ready.Definition
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $ProfileIds -Include $Include -Exclude $Exclude)
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $ProfileIds -Include $Include -Exclude $Exclude
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
}

# What was asked for, for the transcript and the JSON report: profiles and the -Include and -Exclude
# lists, or a re-apply of what drifted.
function New-TuneupApplyRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('profiles', 'reapply', 'startup')][string]$Source,
        [AllowEmptyCollection()][string[]]$Profiles = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @()
    )
    [pscustomobject]@{ Source = $Source; Profiles = [string[]]@($Profiles); Include = [string[]]@($Include); Exclude = [string[]]@($Exclude) }
}

# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    # Warnings before applying (Preflight.ps1): none of them stops the run.
    $preflightArguments = @{ Environment = $environment; Plan = $Plan; ScriptRoot = $Context.ScriptRoot }
    $preflight = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupPreflight @preflightArguments })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight -Source $Request.Source -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
        # The only warning with something to do about it here: System Restore can be turned on. It is
        # asked after the apply is confirmed, so declining the apply never leaves it on, and once it is
        # on the warning is no longer true and leaves the report of the run.
        if (@($preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count -and (Request-TuneupSystemRestore -Io $Context.Io)) {
            $preflight = @($preflight | Where-Object { $_.id -ne 'restore-disabled' })
        }
    } elseif (-not $Context.Json) {
        Write-TuneupPreflight -Preflight $preflight
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    # Ctrl+C stops the run between two tweaks (Interrupt.ps1). If it stops PowerShell itself, the
    # finally block saves what was done; the results and the tweak in progress are kept outside the
    # pipeline for that.
    $results = New-Object System.Collections.Generic.List[object]
    $progress = @{ Current = $null }
    $trap = Enable-TuneupInterruptTrap
    if ($null -ne $trap -and -not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'interrupted.hint') }
    $applyArguments = @{
        Plan          = $Plan
        RunDir        = $run.Dir
        Results       = $results
        Progress      = $progress
        StopRequested = { Test-TuneupInterruptRequested -Trap $trap }
    }
    $finished = $false
    $failure = $null
    try {
        Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan @applyArguments } | Out-Null
        $finished = $true
    } catch {
        # Ctrl+C that stops PowerShell is not an error of the apply; any other error is saved as one.
        if ($_.Exception -isnot [System.Management.Automation.PipelineStoppedException]) { $failure = $_.Exception.Message }
        throw
    } finally {
        Disable-TuneupInterruptTrap -Trap $trap
        if (-not $finished) {
            Save-TuneupStoppedApply -Context $Context -Run $run -Plan $Plan -Request $Request -Results $results -Progress $progress -RestorePoint $restorePoint -Preflight $preflight -Failure $failure
        }
    }
    $report = New-TuneupApplyReport -Run $run -Results $results.ToArray() -RestorePoint $restorePoint -Environment $environment -Preflight $preflight -Source $Request.Source
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyTranscript -Context $Context -Run $run -Request $Request -Plan $Plan -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json -FromMenu:$Context.Menu
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}

# The transcript is a convenience: when it cannot be written the run goes on, with a warning.
function Save-TuneupApplyTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Report
    )
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $Report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        Write-Warning "The transcript of run $($Run.Id) could not be saved: $($_.Exception.Message)"
    }
}

function Save-TuneupUndoTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Run, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupUndoTranscript -Run $Run -Results $Results -Warnings $Context.Warnings.ToArray())
    } catch {
        Write-Warning "The transcript of run $($Run.Id) could not be updated: $($_.Exception.Message)"
    }
}

# Ctrl+C reached PowerShell itself while a native program ran (Interrupt.ps1), or the apply failed
# outside any one tweak (-Failure holds the error). What was done is saved as the result of the run:
# the tweak in progress is reported as failed when its journal entry was written (-Undo can restore
# it) and the rest as interrupted by Ctrl+C or as aborted by the error. A tweak cut before its journal
# entry changed nothing, so it is only left out. The output is closed by then (a stopped pipeline),
# so only the host and the files can be written.
function Save-TuneupStoppedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][hashtable]$Progress,
        [Parameter(Mandatory)][string]$RestorePoint,
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [string]$Failure
    )
    $done = @($Results.ToArray())
    $doneIds = @($done | ForEach-Object { $_.id })
    $rest = @(foreach ($item in $Plan) {
        if ($doneIds -contains $item.Id) { continue }
        if ($item.Action -ne 'apply') { New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason }
        elseif ($item.Id -eq $Progress.Current -and $Progress.Journaled) {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $(if ($Failure) { "$Failure; -Undo can restore it" } else { 'stopped while it was being applied; -Undo can restore it' })
        }
        else { New-TuneupResult -Item $item -Status 'skipped' -Reason $(if ($Failure) { 'aborted' } else { 'interrupted' }) }
    })
    $report = New-TuneupApplyReport -Run $Run -Results (@($done) + @($rest)) -RestorePoint $RestorePoint -Environment $Context.Environment -Preflight $Preflight -Source $Request.Source
    $saved = $true
    try {
        Write-TuneupRunResult -Run $Run -Report $report
    } catch {
        $saved = $false
    }
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        # A missing transcript loses nothing that result.json and the journal do not keep.
        $null = $_
    }
    $Context.Result = $report
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
    if (-not $Context.Json) {
        $savedKey = $(if ($Failure) { 'aborted.saved' } else { 'interrupted.saved' })
        if ($Context.Menu) { $savedKey += '.menu' }
        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key $savedKey -Format $Run.Id)
    }
}

# The command line: checks the parameters, resolves the folders, loads the actions of -ActionsPath and
# runs the command they name. Same parameters as tuneup.ps1 except -Lang, -Json and -ResultId (the
# caller sets the language, the context carries -Json, and tuneup.ps1 writes the result file), and
# -WhatIf is called -PlanOnly (a parameter named WhatIf belongs to ShouldProcess in a function).
function Invoke-TuneupCli {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ScriptRoot,
        [string[]]$ProfileName = @(),
        [string[]]$Include = @(),
        [string[]]$Exclude = @(),
        [switch]$PlanOnly,
        [switch]$Yes,
        [switch]$Status,
        [switch]$Reapply,
        [string]$Undo,
        [string]$Tweak,
        [switch]$Force,
        [string]$StateRoot,
        [string]$CatalogPath,
        [string]$ProfilesPath,
        [string]$ActionsPath,
        [switch]$Health,
        [switch]$Repair,
        [switch]$Measure,
        [string]$Compare,
        [int]$IdleSeconds = 0,
        [switch]$List,
        [switch]$Suggest,
        [switch]$Startup,
        [string[]]$Disable = @(),
        [AllowEmptyString()][string]$ReadResult
    )
    $ProfileName = @(Get-TuneupCleanList ($ProfileName -split ','))
    $Include = @(Get-TuneupCleanList ($Include -split ','))
    $Exclude = @(Get-TuneupCleanList ($Exclude -split ','))
    $Disable = @(Get-TuneupCleanList ($Disable -split ','))

    # A parameter counts as given when it was bound and carries a value (a switch only when it is on).
    $present = @()
    if ($PSBoundParameters.ContainsKey('ProfileName') -and $ProfileName.Count) { $present += 'Profile' }
    if ($PSBoundParameters.ContainsKey('Include') -and $Include.Count) { $present += 'Include' }
    if ($PSBoundParameters.ContainsKey('Exclude') -and $Exclude.Count) { $present += 'Exclude' }
    if ($PSBoundParameters.ContainsKey('PlanOnly') -and $PlanOnly) { $present += 'WhatIf' }
    if ($PSBoundParameters.ContainsKey('Yes') -and $Yes) { $present += 'Yes' }
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $present += 'Status' }
    if ($PSBoundParameters.ContainsKey('Reapply') -and $Reapply) { $present += 'Reapply' }
    if ($PSBoundParameters.ContainsKey('Undo') -and $Undo) { $present += 'Undo' }
    if ($PSBoundParameters.ContainsKey('Tweak') -and $Tweak) { $present += 'Tweak' }
    if ($PSBoundParameters.ContainsKey('Health') -and $Health) { $present += 'Health' }
    if ($PSBoundParameters.ContainsKey('Repair') -and $Repair) { $present += 'Repair' }
    if ($PSBoundParameters.ContainsKey('Measure') -and $Measure) { $present += 'Measure' }
    if ($PSBoundParameters.ContainsKey('Compare') -and $Compare) { $present += 'Compare' }
    if ($PSBoundParameters.ContainsKey('IdleSeconds')) { $present += 'IdleSeconds' }
    if ($PSBoundParameters.ContainsKey('List') -and $List) { $present += 'List' }
    if ($PSBoundParameters.ContainsKey('Suggest') -and $Suggest) { $present += 'Suggest' }
    if ($PSBoundParameters.ContainsKey('Startup') -and $Startup) { $present += 'Startup' }
    if ($PSBoundParameters.ContainsKey('Disable') -and $Disable.Count) { $present += 'Disable' }
    if ($PSBoundParameters.ContainsKey('ReadResult')) { $present += 'ReadResult' }
    $conflict = Get-TuneupArgumentConflict -Present $present
    if ($conflict) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.badArgs' -Format $conflict)
        return
    }
    # Checked here and not with ValidateRange, so that -Json gets its error as a JSON document.
    $maxIdleSeconds = 3600
    if ($PSBoundParameters.ContainsKey('IdleSeconds') -and ($IdleSeconds -lt 0 -or $IdleSeconds -gt $maxIdleSeconds)) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.idleSecondsRange' -Format 0, $maxIdleSeconds)
        return
    }

    if ($PSBoundParameters.ContainsKey('ReadResult')) {
        $resolvedRoot = $(if ($StateRoot) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StateRoot) } else { $null })
        Invoke-TuneupReadResultCommand -Context $Context -Id $ReadResult -StateRoot $resolvedRoot
        return
    }
    # -Suggest reads no catalog, state or environment of the tool (what it needs it reads itself and
    # tolerates failing), so a broken system query cannot turn it into an error.
    if ($Suggest) {
        Invoke-TuneupSuggestCommand -Context $Context
        return
    }

    # Relative paths follow the current PowerShell location, not the process folder that .NET uses.
    $pathApi = $ExecutionContext.SessionState.Path
    $Context.Force = [bool]$Force
    $Context.ScriptRoot = $ScriptRoot
    $Context.StateRoot = $(if ($StateRoot) { $pathApi.GetUnresolvedProviderPathFromPSPath($StateRoot) } else { $null })
    $Context.CatalogPath = $(if ($CatalogPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($CatalogPath) } else { Join-Path $ScriptRoot 'catalog' })
    $Context.ProfilesPath = $(if ($ProfilesPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($ProfilesPath) } else { Join-Path $ScriptRoot 'profiles' })
    if ($ActionsPath) {
        # Tests and development only, like -StateRoot: action scripts from another folder.
        $ActionsPath = $pathApi.GetUnresolvedProviderPathFromPSPath($ActionsPath)
        if (-not (Test-Path -LiteralPath $ActionsPath -PathType Container)) {
            $key = $(if (Test-Path -LiteralPath $ActionsPath -PathType Leaf) { 'err.actionsPathNotFolder' } else { 'err.actionsPathMissing' })
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key $key -Format $ActionsPath)
            return
        }
        Invoke-TuneupContextStep -Context $Context -Step { Write-TuneupActionsPathWarning }
        Invoke-TuneupContextStep -Context $Context -Step { Import-TuneupActionLibrary -Path $ActionsPath }
    }
    # Scripts of the repository folder or of -ActionsPath that could not be loaded: a warning here,
    # and an error in the catalog check only for the tweaks that use them.
    Invoke-TuneupContextStep -Context $Context -Step { Write-TuneupActionLoadWarning }
    Get-TuneupContextEnvironment -Context $Context | Out-Null

    # No command and no option of applying: the menu (with -Json there is nobody to ask).
    if (-not $present.Count -and -not $Context.Json) {
        $blocked = Get-TuneupMenuBlockMessage
        if ($blocked) { Write-TuneupCommandError -Context $Context -Message $blocked; return }
        Invoke-TuneupMenu -Context $Context
        return
    }
    if ($List) { Invoke-TuneupListCommand -Context $Context; return }
    if ($Startup) { Invoke-TuneupStartupCommand -Context $Context -Disable $Disable -PlanOnly:$PlanOnly -Yes:$Yes; return }
    if ($Status) { Invoke-TuneupStatusCommand -Context $Context -Reapply:$Reapply -PlanOnly:$PlanOnly -Yes:$Yes -Include $Include; return }
    if ($Undo) { Invoke-TuneupUndoCommand -Context $Context -RunId $Undo -TweakId $Tweak; return }
    if ($Health) { Invoke-TuneupHealthCommand -Context $Context -Repair:$Repair; return }
    if ($Measure) { Invoke-TuneupMeasureCommand -Context $Context -Compare $Compare -IdleSeconds $IdleSeconds; return }
    Invoke-TuneupApplyCommand -Context $Context -ProfileIds $ProfileName -Include $Include -Exclude $Exclude -PlanOnly:$PlanOnly -Yes:$Yes
}
