<#
.SYNOPSIS
    Runs the test suite as a standard user.
.DESCRIPTION
    GitHub runners are elevated, so the tests marked -Skip:$Elevated never run there. From an elevated
    process this script starts the suite with runas /trustlevel:0x20000: the same account with a Basic
    User token, where the Administrators group only denies, as for a standard user. runas starts the
    process in its own window and returns at once, so the run writes its output, whether it was
    elevated and its exit code to files under TestResults\standard-user, which this script waits for.
    Without elevation it runs build\test.ps1 directly (that already is a standard user).
.PARAMETER Path
    A test file or folder, as for build\test.ps1.
.PARAMETER Restricted
    Uses runas also when not elevated (to check this script itself).
#>
param([string]$Path, [switch]$Restricted, [int]$TimeoutMinutes = 45)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$test = Join-Path $PSScriptRoot 'test.ps1'
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated -and -not $Restricted) {
    & $test -Path $Path
    exit $LASTEXITCODE
}

$work = Join-Path $root 'TestResults\standard-user'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$log = Join-Path $work 'output.log'
$role = Join-Path $work 'elevated.txt'
$done = Join-Path $work 'exit-code.txt'
foreach ($file in $log, $role, $done) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
$pathArgument = $(if ($Path) { " -Path '$((Resolve-Path -LiteralPath $Path).ProviderPath)'" } else { '' })
$child = Join-Path $work 'run.ps1'
[System.IO.File]::WriteAllText($child, @"
`$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
[System.IO.File]::WriteAllText('$role', [string]`$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
& '$test'$pathArgument *> '$log'
[System.IO.File]::WriteAllText('$done', [string]`$LASTEXITCODE)
"@)

& runas.exe /trustlevel:0x20000 "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$child`""
if ($LASTEXITCODE) { throw "runas could not start the run as a standard user (exit code $LASTEXITCODE)" }

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (-not (Test-Path -LiteralPath $done)) {
    if (-not (Test-Path -LiteralPath $role) -and (Get-Date) -gt $deadline.AddMinutes(-$TimeoutMinutes + 2)) {
        throw 'The run as a standard user did not start within 2 minutes (runas may not work on this machine).'
    }
    if ((Get-Date) -gt $deadline) { throw "The run as a standard user did not finish within $TimeoutMinutes minutes." }
    Start-Sleep -Seconds 5
}
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
if ([System.IO.File]::ReadAllText($role).Trim() -ne 'False') { throw 'The run was still elevated: the Basic User token did not take effect.' }
exit [int][System.IO.File]::ReadAllText($done).Trim()
