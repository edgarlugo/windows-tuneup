<#
.SYNOPSIS
    windows-tuneup: goal-based, reversible and measurable Windows optimization.
.EXAMPLE
    .\tuneup.ps1 -Profile base,privacy -WhatIf
.EXAMPLE
    .\tuneup.ps1 -Undo last
.PARAMETER ActionsPath
    Development and testing only: loads action scripts from another folder. They run as the
    current user, with administrator rights when elevated, so use only a folder you trust.
.PARAMETER StateRoot
    Development and testing only: keeps runs and measurements in another folder. That folder
    is not hardened like the machine state folder.
#>
param(
    [Alias('Profile')][string[]]$ProfileName = @(),
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$WhatIf,
    [switch]$Yes,
    [switch]$Status,
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
    [int]$IdleSeconds = 0
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) { $argumentList += "-$($entry.Key)" }
        } else {
            $argumentList += "-$($entry.Key)"
            $argumentList += (@($entry.Value) -join ',')
        }
    }
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @argumentList
    exit $LASTEXITCODE
}

Import-Module (Join-Path $PSScriptRoot 'engine\Tuneup.psm1') -Force
Initialize-TuneupI18n -Root (Join-Path $PSScriptRoot 'i18n') -Lang $Lang

# Everything but the language and -Json goes to the engine as it was given; -WhatIf is -PlanOnly there.
$cliArguments = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) {
    if ($entry.Key -eq 'Lang' -or $entry.Key -eq 'Json') { continue }
    $name = $(if ($entry.Key -eq 'WhatIf') { 'PlanOnly' } else { $entry.Key })
    $cliArguments[$name] = $entry.Value
}
$context = New-TuneupContext -Json:$Json
try {
    Invoke-TuneupCli -Context $context -ScriptRoot $PSScriptRoot @cliArguments
} catch {
    Write-TuneupCommandError -Context $context -Message $_.Exception.Message
} finally {
    exit $context.ExitCode
}
