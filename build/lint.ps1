$ErrorActionPreference = 'Stop'
Import-Module PSScriptAnalyzer

$root = Split-Path $PSScriptRoot -Parent
$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
$targets = @(
    (Join-Path $root 'tuneup.ps1'),
    (Join-Path $root 'install.ps1'),
    (Join-Path $root 'engine'),
    (Join-Path $root 'actions'),
    (Join-Path $root 'build'),
    (Join-Path $root 'tests\sandbox')
) | Where-Object { Test-Path -LiteralPath $_ }

$findings = @(foreach ($target in $targets) {
    Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settings
})
if ($findings.Count) {
    $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 220 | Write-Output
    exit 1
}
Write-Output 'PSScriptAnalyzer: no findings'
