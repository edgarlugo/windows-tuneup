$script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$script:GuidSearch = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Invoke-TuneupPowercfg {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-TuneupNative -FilePath (Join-Path $env:SystemRoot 'System32\powercfg.exe') -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw "powercfg $($Arguments -join ' ') failed with exit code $($result.ExitCode): $($result.Output)"
    }
    $result.Output
}

function Get-TuneupGuidList {
    param([AllowEmptyString()][string]$Text)
    # Only the GUIDs are read: the words around them depend on the Windows language.
    foreach ($match in [regex]::Matches([string]$Text, $script:GuidSearch)) { $match.Value.ToLowerInvariant() }
}

function Get-TuneupActivePowerScheme {
    $guids = @(Get-TuneupGuidList -Text (Invoke-TuneupPowercfg -Arguments @('/getactivescheme')))
    if (-not $guids.Count) { throw 'powercfg /getactivescheme did not return a scheme GUID' }
    $guids[0]
}

function Get-TuneupPowerSchemeList {
    Get-TuneupGuidList -Text (Invoke-TuneupPowercfg -Arguments @('/list'))
}

function Set-TuneupActivePowerScheme {
    param([Parameter(Mandatory)][string]$Guid)
    Invoke-TuneupPowercfg -Arguments @('/setactive', $Guid) | Out-Null
}

function Get-TuneupPowerSchemeState {
    param([Parameter(Mandatory)]$Tweak)
    $wanted = ([string]$Tweak.set.scheme).ToLowerInvariant()
    [pscustomobject]@{
        kind   = 'scheme'
        active = Get-TuneupActivePowerScheme
        exists = (@(Get-TuneupPowerSchemeList) -contains $wanted)
    }
}

function Test-TuneupPowerSchemeState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-TuneupPowerSchemeState -Tweak $Tweak
    if (-not $state.exists) { return 'not-present' }
    if ($state.active -eq ([string]$Tweak.set.scheme).ToLowerInvariant()) { return 'applied' }
    'not-applied'
}
