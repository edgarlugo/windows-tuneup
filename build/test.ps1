param([string]$Path)

$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.6.0

$root = Split-Path $PSScriptRoot -Parent
$resultsDir = Join-Path $root 'TestResults'
if (-not (Test-Path -LiteralPath $resultsDir)) { New-Item -ItemType Directory -Path $resultsDir | Out-Null }

$config = New-PesterConfiguration
$config.Run.Path = $(if ($Path) { $Path } else { Join-Path $root 'tests' })
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $resultsDir 'pester.xml'
Invoke-Pester -Configuration $config
