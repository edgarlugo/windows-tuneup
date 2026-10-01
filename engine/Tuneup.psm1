$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
foreach ($folder in @($engineRoot, (Join-Path $engineRoot 'handlers'))) {
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.ps1' | Sort-Object Name) {
        . $file.FullName
    }
}
# Action scripts are parsed, never run: only their functions are defined (handlers/Action.ps1).
Import-TuneupActionLibrary -Path (Join-Path (Split-Path $engineRoot -Parent) 'actions')
Export-ModuleMember -Function *
