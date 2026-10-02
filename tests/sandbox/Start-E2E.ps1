<#
.SYNOPSIS
    Opens Windows Sandbox and runs the end-to-end test of every profile in it.
.DESCRIPTION
    Needs Windows 10/11 Pro, Enterprise or Education with Windows Sandbox turned on (Windows features:
    "Windows Sandbox", or Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
    as administrator, then restart). It writes the .wsb file to -Output, opens it and waits for
    e2e-report.json there; the sandbox closes itself when the run ends (unless -KeepOpen). Nothing of
    the host changes: the repository is mapped read-only and everything runs inside the sandbox.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1 -Profiles base,lite -KeepOpen
#>
param(
    [string]$Output,
    [string[]]$Profiles = @(),
    [switch]$KeepOpen,
    [int]$TimeoutMinutes = 240
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).ProviderPath
$sandbox = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandbox)) {
    throw 'Windows Sandbox is not turned on: turn on the Windows feature "Windows Sandbox" (Containers-DisposableClientVM) and restart.'
}
if (-not $Output) { $Output = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-tuneup-e2e-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$Output = (Resolve-Path -LiteralPath $Output).ProviderPath
foreach ($name in 'e2e-report.json', 'e2e-report.md', 'e2e.log') {
    if (Test-Path -LiteralPath (Join-Path $Output $name)) { Remove-Item -LiteralPath (Join-Path $Output $name) -Force }
}

Import-Module (Join-Path $PSScriptRoot 'E2E.psm1') -Force
$arguments = @()
if ($Profiles.Count) { $arguments += "-Profiles $((@($Profiles -split ',' | Where-Object { $_ })) -join ',')" }
if ($KeepOpen) { $arguments += '-KeepOpen' }
$template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'e2e.wsb'))
$configuration = Join-Path $Output 'e2e.wsb'
[System.IO.File]::WriteAllText($configuration, (New-E2EConfiguration -Template $template -Repo $repo -Output $Output -Arguments ($arguments -join ' ')))

Write-Host "Opening Windows Sandbox; the report goes to $Output"
Start-Process -FilePath $sandbox -ArgumentList "`"$configuration`""
$report = Join-Path $Output 'e2e-report.json'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (-not (Test-Path -LiteralPath $report)) {
    if ((Get-Date) -gt $deadline) { throw "No report after $TimeoutMinutes minutes: see $(Join-Path $Output 'e2e.log')" }
    Start-Sleep -Seconds 15
}
Start-Sleep -Seconds 2
Get-Content -LiteralPath (Join-Path $Output 'e2e-report.md') -Encoding UTF8
$result = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $result.passed) { exit 1 }
