<#
.SYNOPSIS
    windows-tuneup: goal-based, reversible and measurable Windows optimization.
.EXAMPLE
    .\tuneup.ps1 -Profile base,privacy -WhatIf
.EXAMPLE
    .\tuneup.ps1 -Undo last
.EXAMPLE
    .\tuneup.ps1 -Status -Reapply
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

# Everything but the language and -Json goes to the engine as it was given; -WhatIf is -PlanOnly there.
$cliArguments = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) {
    if ($entry.Key -eq 'Lang' -or $entry.Key -eq 'Json' -or $entry.Key -eq '_Rest' -or $commonParameters -contains $entry.Key) { continue }
    $name = $(if ($entry.Key -eq 'WhatIf') { 'PlanOnly' } else { $entry.Key })
    $cliArguments[$name] = $entry.Value
}
$context = New-TuneupContext -Json:$Json
try {
    if (@($_Rest).Count) {
        Write-TuneupCommandError -Context $context -Message (Get-TuneupText -Key 'err.unknownArgs' -Format (@($_Rest) -join ' '))
    } else {
        Invoke-TuneupGuarded -Context $context -Command { Invoke-TuneupCli -Context $context -ScriptRoot $PSScriptRoot @cliArguments }
    }
} finally {
    exit $context.ExitCode
}
