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
# The run is a script of its own, in ASCII: each path goes in as the base64 of its UTF-8 bytes, so no quote,
# space or letter outside ASCII can break it (and the repository test that wants every .ps1 in ASCII, which
# also sees this file, passes). Whatever happens in it, it writes its exit code, and an error of its own goes
# to the log, so this script never waits for a file that will not come.
function ConvertTo-PathExpression([string]$Text) {
    "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('" + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) + "'))"
}
$testPath = $(if ($Path) { (Resolve-Path -LiteralPath $Path).ProviderPath } else { '' })
$child = Join-Path $work 'run.ps1'
[System.IO.File]::WriteAllText($child, @"
`$code = 1
`$role = $(ConvertTo-PathExpression $role)
`$test = $(ConvertTo-PathExpression $test)
`$testPath = $(ConvertTo-PathExpression $testPath)
`$log = $(ConvertTo-PathExpression $log)
`$done = $(ConvertTo-PathExpression $done)
try {
    `$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    [System.IO.File]::WriteAllText(`$role, [string]`$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    & `$test -Path `$testPath *> `$log
    if (`$null -ne `$LASTEXITCODE) { `$code = `$LASTEXITCODE }
} catch {
    [System.IO.File]::AppendAllText(`$log, "``r``nThe run as a standard user failed: `$(`$_ | Out-String)")
    `$code = 1
} finally {
    [System.IO.File]::WriteAllText(`$done, [string]`$code)
}
"@, [System.Text.Encoding]::ASCII)

# runas takes the whole command as one argument: the quotes around the path go escaped (\") inside it.
& runas.exe /trustlevel:0x20000 ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"' + $child + '\"')
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
if (-not (Test-Path -LiteralPath $role)) { throw 'The run as a standard user ended before saying whether it was elevated (see the log above).' }
if ([System.IO.File]::ReadAllText($role).Trim() -ne 'False') { throw 'The run was still elevated: the Basic User token did not take effect.' }
exit [int][System.IO.File]::ReadAllText($done).Trim()
