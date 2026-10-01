# Questions shared by the menu (Menu.ps1) and the commands it drives (Commands.ps1). They read and
# write through $Context.Io (Io.ps1), so they never touch the console directly and the end of the
# input ($null) is handled in one place: it marks the context and every caller goes back.

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

# The word that adds a tweak of high risk: typed in full, with or without the accent in Spanish.
function Test-TuneupHighRiskWord {
    param([AllowNull()][string]$Answer)
    ($null -ne $Answer) -and ($Answer -match (Get-TuneupText -Key 'menu.high.pattern'))
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
        if (Test-TuneupHighRiskWord -Answer $word) { $confirmed.Add([string]$tweak.id) }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.reapply.highSkipped' -Format (Get-TuneupTitle -Tweak $tweak)) }
    }
    , @($confirmed.ToArray())
}

# One question for each tweak of the plan that asks first (ask: true) and was not asked for by name:
# yes, no, yes to this one and all the rest, or no to this one and all the rest. A no turns the item
# into a skip with the reason declined. Gives the ids said no to, or $null when the input ended.
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
