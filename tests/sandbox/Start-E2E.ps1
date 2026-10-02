<#
.SYNOPSIS
    Opens Windows Sandbox and runs the end-to-end test of every profile in it.
.DESCRIPTION
    Needs Windows 10/11 Pro, Enterprise or Education with Windows Sandbox turned on (Windows features:
    "Windows Sandbox", or Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
    as administrator, then restart). It writes the .wsb file to -Output, opens it and waits for
    e2e-report.json there; the sandbox closes itself when the run ends (unless -KeepOpen). Nothing of
    the host changes: the repository is mapped read-only and everything runs inside the sandbox.

    Windows Sandbox is opened with WindowsSandbox.exe when Windows has it; newer versions (Windows 11
    24H2 and later, where Windows Sandbox is updated as an app) may not, and then the .wsb file is opened
    through its file association, or with the wsb.exe command line. -MemoryInMB is the memory of the
    sandbox (4096 by default; give more if the host has it to spare).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1 -Profiles base,lite -KeepOpen -MemoryInMB 8192
#>
param(
    [string]$Output,
    [string[]]$Profiles = @(),
    [switch]$KeepOpen,
    [int]$TimeoutMinutes = 240,
    [ValidateRange(2048, 65536)][int]$MemoryInMB = 4096
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).ProviderPath
# How Windows Sandbox is opened: its program, the .wsb file association, or the wsb.exe command line.
$sandbox = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
$wsbCommand = Get-Command -Name 'wsb.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$launcher = $(if (Test-Path -LiteralPath $sandbox) { 'program' }
    elseif (Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\.wsb') { 'association' }
    elseif ($wsbCommand) { 'wsb' }
    else { $null })
if (-not $launcher) {
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
$text = New-E2EConfiguration -Template $template -Repo $repo -Output $Output -Arguments ($arguments -join ' ') -MemoryInMB $MemoryInMB
[System.IO.File]::WriteAllText($configuration, $text)

Write-Host "Opening Windows Sandbox ($MemoryInMB MB); the report goes to $Output"
switch ($launcher) {
    'program' { Start-Process -FilePath $sandbox -ArgumentList "`"$configuration`"" }
    'association' { Start-Process -FilePath $configuration }
    # wsb.exe takes the configuration as text, not as a file; the template has no double quotes.
    'wsb' { & $wsbCommand.Source start --config ($text -replace '\s*\r?\n\s*', '') }
}
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
