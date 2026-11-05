<#
.SYNOPSIS
    windows-tuneup in a window (design, section 17): everything the command line does, with the same engine.
.DESCRIPTION
    Every action runs tuneup.ps1 of this same copy with -Json and shows the document it gives back; the window
    never changes the system itself. What needs administrator asks for it with UAC, one action at a time, or
    the whole window starts again as administrator. Its log is in %LOCALAPPDATA%\windows-tuneup\gui\logs.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\gui.ps1
.PARAMETER Section
    The section to open: Home, Optimize, Status, Undo, Health, Measure, Startup, Clean or Log.
.PARAMETER Lang
    The language of the window, es or en; otherwise the one saved in its settings, or the one of Windows.
#>
[CmdletBinding()]
param(
    [ValidateSet('Home', 'Optimize', 'Status', 'Undo', 'Health', 'Measure', 'Startup', 'Clean', 'Log')][string]$Section = 'Home',
    [ValidateSet('es', 'en')][string]$Lang
)

$ErrorActionPreference = 'Stop'

# WPF needs Windows PowerShell on a single-threaded apartment: from PowerShell 7, or from a console started
# without -STA, the script starts again that way with the same parameters.
if ($PSVersionTable.PSEdition -eq 'Core' -or [System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath, '-Section', $Section)
    if ($Lang) { $relaunch += @('-Lang', $Lang) }
    & ([System.IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\powershell.exe')) @relaunch
    exit $LASTEXITCODE
}

# Modules only from the folders of Windows and of Program Files, as tuneup.ps1 does: a module of the same name in
# a folder of the account would otherwise run with the rights of this window.
$env:PSModulePath = [System.IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\Modules') + ';' +
    [System.IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'WindowsPowerShell\Modules')

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'gui\GuiCore.ps1')
. (Join-Path $PSScriptRoot 'gui\GuiWindow.ps1')

$settings = Read-TuneupGuiSetting
if ($Lang) { $settings.lang = $Lang }
Initialize-TuneupGuiText -Lang $settings.lang
[void](Initialize-TuneupGuiLog)

$engine = Join-Path $PSScriptRoot 'tuneup.ps1'
if (-not [System.IO.File]::Exists($engine)) {
    [void][System.Windows.MessageBox]::Show((Get-TuneupGuiText -Key 'gui.err.noEngine' -Format $engine), 'windows-tuneup', 'OK', 'Error')
    exit 1
}

$exitCode = 0
try {
    Write-TuneupGuiLog -Level INFO -Text (Get-TuneupGuiText -Key 'gui.log.open' -Format $(if (Test-TuneupGuiAdmin) { Get-TuneupGuiText -Key 'gui.header.admin' } else { Get-TuneupGuiText -Key 'gui.header.notAdmin' }))
    $next = [pscustomobject]@{ Lang = $settings.lang; Section = $Section }
    # A change of language closes the window and opens it again in the same section.
    while ($null -ne $next) {
        Initialize-TuneupGuiText -Lang $next.Lang
        $settings.lang = Get-TuneupGuiLang
        $next = Show-TuneupGui -Section $next.Section -Settings $settings
    }
} catch {
    $exitCode = 1
    Write-TuneupGuiLog -Level ERROR -Text ($_.Exception.Message + ' ' + $_.ScriptStackTrace)
    [void][System.Windows.MessageBox]::Show((Get-TuneupGuiText -Key 'gui.err.fatal' -Format $_.Exception.Message, (Get-TuneupGuiLogFolder)), 'windows-tuneup', 'OK', 'Error')
}
exit $exitCode
