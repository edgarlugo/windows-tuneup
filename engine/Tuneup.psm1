$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
$functionsBefore = @(Get-ChildItem -LiteralPath Function:\ | ForEach-Object { $_.Name })
foreach ($folder in @($engineRoot, (Join-Path $engineRoot 'handlers'))) {
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    # -Filter '*.ps1' also matches names such as x.ps1xml (through their short names).
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File | Where-Object { $_.Extension -eq '.ps1' } | Sort-Object Name) {
        . $file.FullName
    }
}
# Only the engine is exported: the functions of action scripts stay inside the module.
$engineFunctions = @(Get-ChildItem -LiteralPath Function:\ | ForEach-Object { $_.Name } | Where-Object { $functionsBefore -notcontains $_ })
# Action scripts are parsed, never run: only their functions are defined (handlers/Action.ps1).
Import-TuneupActionLibrary -Path (Join-Path (Split-Path $engineRoot -Parent) 'actions')
Export-ModuleMember -Function $engineFunctions
