# transcript.log keeps, with each run, the text a person sees: the plan, the warnings before applying,
# each result, the summary and, later, each undo of the run. It is written by the tool from its own
# reports, never with Start-Transcript: that one also records the account, the machine, the command
# line and anything else on the screen, and Users can read the machine state folder. With -Json the
# transcript still gets the text for people.

# The lines that a step writes to the host, captured instead of shown.
function Get-TuneupHostText {
    param([Parameter(Mandatory)][scriptblock]$Step)
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($record in @(& $Step 6>&1)) {
        if ($record -isnot [System.Management.Automation.InformationRecord]) { continue }
        $data = $record.MessageData
        if ($data -is [System.Management.Automation.HostInformationMessage]) {
            $current += [string]$data.Message
            if ($data.NoNewLine) { continue }
        } else {
            $current += [string]$data
        }
        $lines.Add($current)
        $current = ''
    }
    if ($current) { $lines.Add($current) }
    $lines.ToArray()
}

function Add-TuneupTranscript {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $text = (@($Lines) -join [Environment]::NewLine) + [Environment]::NewLine
    Write-TuneupStateFile -Path (Join-Path $Run.Dir 'transcript.log') -Root $Run.Root -Append -Text $text
}

# The transcript of an apply: who asked for what (profiles and lists, never the command line), the
# plan, the warnings and the report.
function Get-TuneupApplyTranscript {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @()
    )
    $list = { param($values) $(if (@($values).Count) { @($values) -join ', ' } else { '-' }) }
    Get-TuneupText -Key 'transcript.header' -Format (Get-TuneupVersion), $Run.Id, (Get-Date).ToString('s')
    Get-TuneupText -Key "transcript.request.$($Request.Source)" -Format (& $list $Request.Profiles), (& $list $Request.Include), (& $list $Request.Exclude)
    ''
    $planArguments = @{ Plan = $Plan; Environment = $Environment; Preflight = @($Report.preflight) }
    Get-TuneupHostText -Step { Write-TuneupPlanReport @planArguments }
    ''
    $reportArguments = @{ Report = $Report }
    Get-TuneupHostText -Step { Write-TuneupApplyReport @reportArguments }
    if (@($Warnings).Count) {
        ''
        Get-TuneupText -Key 'transcript.warnings'
        foreach ($warning in $Warnings) { "  - $warning" }
    }
}

function Get-TuneupUndoTranscript {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [AllowEmptyCollection()][string[]]$Warnings = @()
    )
    ''
    Get-TuneupText -Key 'transcript.undo' -Format (Get-TuneupVersion), (Get-Date).ToString('s')
    $reportArguments = @{ RunId = $Run.Id; Results = $Results }
    Get-TuneupHostText -Step { Write-TuneupUndoReport @reportArguments }
    if (@($Warnings).Count) {
        Get-TuneupText -Key 'transcript.warnings'
        foreach ($warning in $Warnings) { "  - $warning" }
    }
}
