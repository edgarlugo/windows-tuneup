$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
foreach ($folder in @($engineRoot, (Join-Path $engineRoot 'handlers'))) {
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    # -Filter '*.ps1' also matches names such as x.ps1xml (through their short names).
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File | Where-Object { $_.Extension -eq '.ps1' } | Sort-Object Name) {
        . $file.FullName
    }
}
# Only the engine is exported: the functions of action scripts stay inside the module. They are
# taken before the actions load, from what this module itself defined, so a function of the same
# name in the session (a global one or another copy of the module) does not drop out of the list.
$engineFunctions = @(Get-ChildItem -LiteralPath Function:\ |
    Where-Object { $_.Module -eq $ExecutionContext.SessionState.Module } | ForEach-Object { $_.Name })
# Action scripts are parsed, never run: only their functions are defined (handlers/Action.ps1).
Import-TuneupActionLibrary -Path (Join-Path (Split-Path $engineRoot -Parent) 'actions')
Export-ModuleMember -Function $engineFunctions
