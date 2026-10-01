$script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z'
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

$script:PowerKeyRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'

function ConvertTo-TuneupUInt32 {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Description)
    # Only a REG_DWORD is a power index; anything else is reported instead of failing in a cast.
    if ($Value -isnot [int] -and $Value -isnot [uint32] -and $Value -isnot [long]) {
        throw "Cannot read $($Description): the registry value is not a DWORD (it is $($Value.GetType().Name))"
    }
    # Get-ItemProperty returns REG_DWORD values above 2147483647 as negative numbers.
    $number = [long]$Value
    if ($number -lt 0) { $number += 4294967296 }
    $number
}

function Resolve-TuneupPowerScheme {
    param([Parameter(Mandatory)][string]$Scheme)
    # The journal keeps the GUID, so an undo goes back to the same scheme even if another is active then.
    if ($Scheme -ceq 'SCHEME_CURRENT') { return (Get-TuneupActivePowerScheme) }
    $Scheme.ToLowerInvariant()
}

function Read-TuneupPowerKey {
    param([Parameter(Mandatory)][string]$Path)
    # A key that is not there has no value to give; one that is there but cannot be read (access
    # denied, a broken hive) is an error, never a reason to go on to the next source as if it were empty.
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
}

function Get-TuneupPowerSettingIndex {
    param(
        [Parameter(Mandatory)][string]$Scheme,
        [Parameter(Mandatory)][string]$Subgroup,
        [Parameter(Mandatory)][string]$Setting
    )
    $definition = "$script:PowerKeyRoot\PowerSettings\$Subgroup\$Setting"
    if (-not (Test-Path -LiteralPath $definition)) { return [pscustomobject]@{ present = $false; ac = $null; dc = $null } }
    # For each power source, the first one that has a value wins: a value changed for this scheme
    # under User\PowerSchemes, then the provisioned default (Prov*SettingIndex, which Windows
    # prefers to the plain one), then the default kept with the setting definition.
    # powercfg /q is not used: it hides the settings marked hidden.
    $user = Read-TuneupPowerKey -Path "$script:PowerKeyRoot\User\PowerSchemes\$Scheme\$Subgroup\$Setting"
    $defaults = Read-TuneupPowerKey -Path "$definition\DefaultPowerSchemeValues\$Scheme"
    $provisioned = @{ ACSettingIndex = 'ProvAcSettingIndex'; DCSettingIndex = 'ProvDcSettingIndex' }
    $values = @{}
    foreach ($name in 'ACSettingIndex', 'DCSettingIndex') {
        $candidates = @(
            @{ Properties = $user; Property = $name },
            @{ Properties = $defaults; Property = $provisioned[$name] },
            @{ Properties = $defaults; Property = $name }
        )
        foreach ($candidate in $candidates) {
            if ($null -ne $candidate.Properties -and $null -ne $candidate.Properties.($candidate.Property)) {
                $values[$name] = ConvertTo-TuneupUInt32 -Value $candidate.Properties.($candidate.Property) `
                    -Description "$($candidate.Property) of power setting $Subgroup\$Setting in scheme $Scheme"
                break
            }
        }
        if (-not $values.ContainsKey($name)) { throw "Cannot read $name of power setting $Subgroup\$Setting in scheme $Scheme" }
    }
    [pscustomobject]@{ present = $true; ac = $values['ACSettingIndex']; dc = $values['DCSettingIndex'] }
}

function Get-TuneupPowerSettingState {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    $scheme = Resolve-TuneupPowerScheme -Scheme ([string]$set.scheme)
    # A scheme that was deleted has no values to read; the active one is always listed.
    if ([string]$set.scheme -cne 'SCHEME_CURRENT' -and @(Get-TuneupPowerSchemeList) -notcontains $scheme) {
        return [pscustomobject]@{ kind = 'setting'; scheme = $scheme; present = $false; ac = $null; dc = $null }
    }
    $index = Get-TuneupPowerSettingIndex -Scheme $scheme -Subgroup ([string]$set.subgroup).ToLowerInvariant() -Setting ([string]$set.setting).ToLowerInvariant()
    [pscustomobject]@{ kind = 'setting'; scheme = $scheme; present = $index.present; ac = $index.ac; dc = $index.dc }
}

# The values a setting tweak asks for: ac and dc are each optional (absent or null leaves that power
# source as it is), but at least one is given (the catalog check makes sure).
function Get-TuneupPowerSettingTarget {
    param([Parameter(Mandatory)]$Set)
    $target = @{ ac = $null; dc = $null }
    foreach ($field in 'ac', 'dc') {
        $property = $Set.PSObject.Properties[$field]
        if ($null -ne $property -and $null -ne $property.Value) { $target[$field] = [long]$property.Value }
    }
    [pscustomobject]$target
}

function Set-TuneupPowerSettingIndex {
    param(
        [Parameter(Mandatory)][string]$Scheme,
        [Parameter(Mandatory)][string]$Subgroup,
        [Parameter(Mandatory)][string]$Setting,
        [AllowNull()]$Ac,
        [AllowNull()]$Dc,
        [switch]$ReportPartial
    )
    # Only the power sources that are given are written; the other one keeps its value.
    $written = @()
    if ($null -ne $Ac) {
        Invoke-TuneupPowercfg -Arguments @('/setacvalueindex', $Scheme, $Subgroup, $Setting, [string][long]$Ac) | Out-Null
        $written += 'AC'
    }
    if ($null -ne $Dc) {
        try {
            Invoke-TuneupPowercfg -Arguments @('/setdcvalueindex', $Scheme, $Subgroup, $Setting, [string][long]$Dc) | Out-Null
        } catch {
            # Nothing was written yet when DC is the only value: a plain failure.
            if (-not $written.Count) { throw }
            $message = "The value on AC power was changed, but not the rest: $($_.Exception.Message)"
            if ($ReportPartial) { return (New-TuneupOutcome -Partial -Detail $message) }
            throw $message
        }
        $written += 'DC'
    }
    # A change to the active scheme takes effect once it is activated again.
    try {
        if ($Scheme -eq (Get-TuneupActivePowerScheme)) { Invoke-TuneupPowercfg -Arguments @('/setactive', $Scheme) | Out-Null }
    } catch {
        $changed = $(if ($written.Count -eq 2) { 'The values on AC and DC power were changed' } else { "The value on $($written[0]) power was changed" })
        $message = "$changed, but activating the scheme again failed: $($_.Exception.Message)"
        if ($ReportPartial) { return (New-TuneupOutcome -Partial -Detail $message) }
        throw $message
    }
}

function Test-PowercfgTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ($Tweak.scope -cne 'machine') { 'must use scope machine' }
    switch -CaseSensitive ([string]$set.kind) {
        'scheme' {
            if ([string]$set.scheme -notmatch $script:GuidPattern) { 'needs the GUID of the power scheme in set.scheme' }
        }
        'setting' {
            if ([string]$set.scheme -cne 'SCHEME_CURRENT' -and [string]$set.scheme -notmatch $script:GuidPattern) { 'set.scheme must be SCHEME_CURRENT or a scheme GUID' }
            foreach ($field in 'subgroup', 'setting') {
                if ([string]$set.$field -notmatch $script:GuidPattern) { "set.$field must be a GUID" }
            }
            # ac and dc are each optional (left as they are when absent or null), but one is needed.
            $given = @('ac', 'dc' | Where-Object { $null -ne $set.PSObject.Properties[$_] -and $null -ne $set.$_ })
            if (-not $given.Count) { 'needs set.ac, set.dc or both' }
            foreach ($field in $given) {
                if (-not (Test-TuneupIntegerInRange -Value $set.$field -Min 0 -Max 4294967295)) { "set.$field must be an integer from 0 to 4294967295" }
            }
        }
        default { "has an invalid powercfg kind '$($set.kind)'" }
    }
}

function Get-PowercfgTweakState {
    param([Parameter(Mandatory)]$Tweak)
    if ($Tweak.set.kind -eq 'scheme') { return (Get-TuneupPowerSchemeState -Tweak $Tweak) }
    Get-TuneupPowerSettingState -Tweak $Tweak
}

function Test-PowercfgTweakState {
    param([Parameter(Mandatory)]$Tweak)
    if ($Tweak.set.kind -eq 'scheme') { return (Test-TuneupPowerSchemeState -Tweak $Tweak) }
    $state = Get-TuneupPowerSettingState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    # A power source the tweak leaves alone does not count.
    $target = Get-TuneupPowerSettingTarget -Set $Tweak.set
    if ($null -ne $target.ac -and [long]$state.ac -ne $target.ac) { return 'not-applied' }
    if ($null -ne $target.dc -and [long]$state.dc -ne $target.dc) { return 'not-applied' }
    'applied'
}

function Set-PowercfgTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ($set.kind -eq 'scheme') {
        Set-TuneupActivePowerScheme -Guid ([string]$set.scheme).ToLowerInvariant()
        return
    }
    $scheme = Resolve-TuneupPowerScheme -Scheme ([string]$set.scheme)
    $target = Get-TuneupPowerSettingTarget -Set $set
    Set-TuneupPowerSettingIndex -Scheme $scheme -Subgroup ([string]$set.subgroup).ToLowerInvariant() `
        -Setting ([string]$set.setting).ToLowerInvariant() -Ac $target.ac -Dc $target.dc -ReportPartial
}

function Restore-PowercfgTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if ($Tweak.set.kind -eq 'scheme') {
        if ($State.active) { Set-TuneupActivePowerScheme -Guid ([string]$State.active) }
        return
    }
    if (-not $State.present) { return }
    # Only the power sources that the tweak changed are given back; the other one may have been
    # changed since by someone else.
    $target = Get-TuneupPowerSettingTarget -Set $Tweak.set
    $ac = $(if ($null -ne $target.ac) { [long]$State.ac } else { $null })
    $dc = $(if ($null -ne $target.dc) { [long]$State.dc } else { $null })
    Set-TuneupPowerSettingIndex -Scheme ([string]$State.scheme) -Subgroup ([string]$Tweak.set.subgroup).ToLowerInvariant() `
        -Setting ([string]$Tweak.set.setting).ToLowerInvariant() -Ac $ac -Dc $dc
}
