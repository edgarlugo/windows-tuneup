# transcript.log keeps, with each run, the text a person sees: the plan, the warnings before applying,
# each result, the summary and, later, each undo of the run. It is written by the tool from its own
# reports, never with Start-Transcript: that one also records the account, the machine, the command
# line and anything else on the screen, and Users can read the machine state folder. With -Json the
# transcript still gets the text for people.

# The text with the profile folder of the account shown as %USERPROFILE% and the account name shown as
# %USERNAME%, wherever they are. What a run keeps for people to read and share (the transcript,
# result.json, the warnings of a preflight) goes through here, so a bug report does not carry the
# account name inside a path. A name of fewer than 3 characters is left alone: it would also change
# ordinary words. With -JsonEscaped the profile folder is looked for as JSON writes it (doubled
# backslashes).
function Hide-TuneupPersonalData {
    param([AllowNull()][AllowEmptyString()][string]$Text, [switch]$JsonEscaped)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $ignoreCase = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $folders = @(@($env:USERPROFILE, [Environment]::GetFolderPath('UserProfile')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } |
        Select-Object -Unique | Sort-Object -Property Length -Descending)
    foreach ($folder in $folders) {
        $literal = $(if ($JsonEscaped) { $folder.Replace('\', '\\') } else { $folder })
        $Text = [regex]::Replace($Text, [regex]::Escape($literal), '%USERPROFILE%', $ignoreCase)
    }
    $name = [string]$env:USERNAME
    if ($name.Length -ge 3) {
        $Text = [regex]::Replace($Text, '(?<![A-Za-z0-9])' + [regex]::Escape($name) + '(?![A-Za-z0-9])', '%USERNAME%', $ignoreCase)
    }
    $Text
}

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
    $text = Hide-TuneupPersonalData -Text ((@($Lines) -join [Environment]::NewLine) + [Environment]::NewLine)
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
