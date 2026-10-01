$script:FeatureStates = @('Enabled', 'Disabled')
$script:FeatureNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]*\z'
$script:FeatureCache = $null

function ConvertTo-TuneupFeatureState {
    param([AllowNull()][AllowEmptyString()][string]$State)
    # A pending change counts as done; a feature whose files were removed is still disabled. Any
    # other state (PartiallyInstalled, Superseded...) is neither one nor the other: it returns
    # nothing, so the feature is left alone instead of being read as enabled or disabled.
    if (@('Enabled', 'EnablePending') -contains $State) { return 'Enabled' }
    if (@('Disabled', 'DisablePending', 'DisabledWithPayloadRemoved') -contains $State) { return 'Disabled' }
}

function Clear-TuneupFeatureCache {
    $script:FeatureCache = $null
}

function Get-TuneupWindowsOptionalFeature {
    param([Parameter(Mandatory)][string]$Name)
    # One listing per process, filtered by exact name; every change clears it.
    if ($null -eq $script:FeatureCache) { $script:FeatureCache = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop) }
    $script:FeatureCache | Where-Object { $_.FeatureName -eq $Name } | Select-Object -First 1
}

function Enable-TuneupWindowsOptionalFeature {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupFeatureCache
    try {
        # No -All: parent features are left as they are, so the undo stays exact.
        Enable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
    } catch {
        throw "Enabling feature $Name failed (it may need Windows Update or an installation source): $($_.Exception.Message)"
    }
}

function Disable-TuneupWindowsOptionalFeature {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupFeatureCache
    # No -Remove: the files stay, so enabling it again needs no source.
    Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
}

function Test-FeatureTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:FeatureNamePattern) { 'has an invalid feature name' }
    if ($script:FeatureStates -cnotcontains $set.state) { "has an invalid feature state '$($set.state)'" }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}

function Get-FeatureTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $feature = Get-TuneupWindowsOptionalFeature -Name ([string]$Tweak.set.name)
    if ($null -eq $feature) { return [pscustomobject]@{ present = $false; state = $null } }
    $state = ConvertTo-TuneupFeatureState -State ([string]$feature.State)
    # A state that is not clearly enabled or disabled counts as not present: it is not touched.
    if ($null -eq $state) { return [pscustomobject]@{ present = $false; state = $null } }
    [pscustomobject]@{ present = $true; state = $state }
}

function Test-FeatureTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-FeatureTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.state -eq $Tweak.set.state) { return 'applied' }
    'not-applied'
}

function Set-TuneupFeatureState {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$State)
    if ($State -eq 'Enabled') {
        $result = @(Enable-TuneupWindowsOptionalFeature -Name $Name)
    } else {
        $result = @(Disable-TuneupWindowsOptionalFeature -Name $Name)
    }
    if (@($result | Where-Object { $_.RestartNeeded }).Count) { New-TuneupOutcome -RebootRequired }
}

function Set-FeatureTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupFeatureState -Name ([string]$Tweak.set.name) -State ([string]$Tweak.set.state)
}

function Restore-FeatureTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    $current = Get-FeatureTweakState -Tweak $Tweak
    if ($current.present -and $current.state -eq $State.state) { return }
    Set-TuneupFeatureState -Name ([string]$Tweak.set.name) -State ([string]$State.state)
}
