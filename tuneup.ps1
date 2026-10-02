<#
.SYNOPSIS
    windows-tuneup: goal-based, reversible and measurable Windows optimization.
.EXAMPLE
    .\tuneup.ps1 -Profile base,privacy -WhatIf
.EXAMPLE
    .\tuneup.ps1 -Undo last
.EXAMPLE
    .\tuneup.ps1 -Status -Reapply
.EXAMPLE
    .\tuneup.ps1 -Suggest
.EXAMPLE
    .\tuneup.ps1 -List -Json -ResultId 3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12
.PARAMETER List
    Shows the profiles and the tweaks that suit this machine. Read only.
.PARAMETER Suggest
    Shows what this machine has (development tools, games, a battery, an organization, modest
    hardware) and the profiles that fit it. Read only.
.PARAMETER ResultId
    With -Json only: also writes the JSON document to out\<id>.json in the state folder (the machine
    one when elevated, which only administrators can change), so a program that started the tool
    elevated can read it. 8 to 64 letters, digits or hyphens; a file with that id must not exist.
.PARAMETER ActionsPath
    Development and testing only: loads action scripts from another folder. They run as the
    current user, with administrator rights when elevated, so use only a folder you trust.
.PARAMETER StateRoot
    Development and testing only: keeps runs and measurements in another folder. That folder
    is not hardened like the machine state folder.
#>
# PositionalBinding off and the last parameter collect what PowerShell could not bind (a misspelled or
# unknown parameter, a value without its name), so it is rejected with an error report (a JSON document
# with -Json) instead of being ignored or taken as a profile. Its name starts with _ so that no
# abbreviation of a real parameter (-Un for -Undo) becomes ambiguous.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Alias('Profile')][string[]]$ProfileName = @(),
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$WhatIf,
    [switch]$Yes,
    [switch]$Status,
    [switch]$Reapply,
    [string]$Undo,
    [string]$Tweak,
    [switch]$Json,
    [ValidateSet('es', 'en')][string]$Lang,
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
    [string]$ResultId,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$_Rest = @()
)

$ErrorActionPreference = 'Stop'
# The common parameters that [CmdletBinding()] adds (-Verbose, -ErrorAction...) are not options of the
# tool: they are left out of what is passed on. -WhatIf is ours (it is not ShouldProcess here).
$commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters)

if ($PSVersionTable.PSEdition -eq 'Core') {
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Key -eq '_Rest' -or $commonParameters -contains $entry.Key) { continue }
        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) { $argumentList += "-$($entry.Key)" }
        } else {
            $argumentList += "-$($entry.Key)"
            $argumentList += (@($entry.Value) -join ',')
        }
    }
    # What could not be bound goes as it came, so Windows PowerShell rejects it with its report.
    $argumentList += @($_Rest)
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @argumentList
    exit $LASTEXITCODE
}

Import-Module (Join-Path $PSScriptRoot 'engine\Tuneup.psm1') -Force
Initialize-TuneupI18n -Root (Join-Path $PSScriptRoot 'i18n') -Lang $Lang

# Everything but the language, -Json and -ResultId goes to the engine as it was given; -WhatIf is
# -PlanOnly there.
$cliArguments = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) {
    if (@('Lang', 'Json', 'ResultId', '_Rest') -contains $entry.Key -or $commonParameters -contains $entry.Key) { continue }
    $name = $(if ($entry.Key -eq 'WhatIf') { 'PlanOnly' } else { $entry.Key })
    $cliArguments[$name] = $entry.Value
}
$context = New-TuneupContext -Json:$Json
$run = {
    if (@($_Rest).Count) {
        Write-TuneupCommandError -Context $context -Message (Get-TuneupText -Key 'err.unknownArgs' -Format (@($_Rest) -join ' '))
    } else {
        Invoke-TuneupGuarded -Context $context -Command { Invoke-TuneupCli -Context $context -ScriptRoot $PSScriptRoot @cliArguments }
    }
}
# -ResultId: the document also goes to out\<id>.json of the state folder, for a program that cannot read
# this output (the Claude skill starts the tool elevated with UAC). The file is created before anything
# runs, so an id in use stops here, and gets what the command wrote, errors included. The folder is the
# one the runs of this process use: the hardened machine folder when elevated, the user folder
# otherwise, -StateRoot resolved as Invoke-TuneupCli resolves it.
$resultFile = $null
$document = New-Object System.Collections.Generic.List[string]
try {
    if ($PSBoundParameters.ContainsKey('ResultId')) {
        $problem = Get-TuneupResultIdProblem -Id $ResultId -Json:$Json
        if (-not $problem) {
            $opened = Open-TuneupContextResultFile -Context $context -Id $ResultId -StateRoot $StateRoot
            $problem = $opened.Message
            $resultFile = $opened.File
        }
        if ($problem) {
            Write-TuneupCommandError -Context $context -Message $problem
            return
        }
    }
    if ($null -eq $resultFile) {
        & $run
    } else {
        & $run | ForEach-Object { $document.Add([string]$_); $_ }
    }
} finally {
    # A document that could not be saved is not everything done: 0 becomes 2.
    if ($null -ne $resultFile -and -not (Close-TuneupResultFile -File $resultFile -Text ($document -join [Environment]::NewLine)) -and $context.ExitCode -eq 0) {
        $context.ExitCode = 2
    }
    exit $context.ExitCode
}
