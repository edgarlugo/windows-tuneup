$script:CapabilityStates = @('Installed', 'NotPresent')
# Name~~~~Version, as Get-WindowsCapability lists it (for example App.StepsRecorder~~~~0.0.1.0).
$script:CapabilityNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]*~[A-Za-z0-9._~-]*\z'
$script:CapabilityCache = $null

function ConvertTo-TuneupCapabilityState {
    param([AllowNull()][AllowEmptyString()][string]$State)
    # A pending change counts as done: Windows finishes it on the next restart. Any other state
    # (PartiallyInstalled, Superseded, Resolved...) is neither one nor the other: it returns
    # nothing, so the capability is left alone instead of being read as installed or absent.
    if (@('Installed', 'InstallPending') -contains $State) { return 'Installed' }
    if (@('NotPresent', 'UninstallPending', 'Staged', 'Removed') -contains $State) { return 'NotPresent' }
}

function Clear-TuneupCapabilityCache {
    $script:CapabilityCache = $null
}

function Get-TuneupWindowsCapability {
    param([Parameter(Mandatory)][string]$Name)
    # One listing per process, filtered by exact name; every change clears it.
    if ($null -eq $script:CapabilityCache) { $script:CapabilityCache = @(Get-WindowsCapability -Online -ErrorAction Stop) }
    $script:CapabilityCache | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
}

function Add-TuneupWindowsCapability {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupCapabilityCache
    try {
        Add-WindowsCapability -Online -Name $Name -ErrorAction Stop
    } catch {
        throw "Adding capability $Name failed (it needs Windows Update or a features-on-demand source): $($_.Exception.Message)"
    }
}

function Remove-TuneupWindowsCapability {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupCapabilityCache
    Remove-WindowsCapability -Online -Name $Name -ErrorAction Stop
}

function Test-CapabilityTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:CapabilityNamePattern) { 'has an invalid capability name (expected Name~~~~Version)' }
    if ($script:CapabilityStates -cnotcontains $set.state) { "has an invalid capability state '$($set.state)'" }
    if ($Tweak.scope -cne 'machine') { 'must use scope machine' }
}

function Get-CapabilityTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $capability = Get-TuneupWindowsCapability -Name ([string]$Tweak.set.name)
    if ($null -eq $capability) { return [pscustomobject]@{ present = $false; state = $null } }
    $state = ConvertTo-TuneupCapabilityState -State ([string]$capability.State)
    # A state that is not clearly installed or absent counts as not present: it is not touched.
    if ($null -eq $state) { return [pscustomobject]@{ present = $false; state = $null } }
    [pscustomobject]@{ present = $true; state = $state }
}

function Test-CapabilityTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-CapabilityTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.state -eq $Tweak.set.state) { return 'applied' }
    'not-applied'
}

function Set-TuneupCapabilityState {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$State)
    if ($State -eq 'Installed') {
        $result = @(Add-TuneupWindowsCapability -Name $Name)
    } else {
        $result = @(Remove-TuneupWindowsCapability -Name $Name)
    }
    if (@($result | Where-Object { $_.RestartNeeded }).Count) { New-TuneupOutcome -RebootRequired }
}

function Set-CapabilityTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupCapabilityState -Name ([string]$Tweak.set.name) -State ([string]$Tweak.set.state)
}

function Restore-CapabilityTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    $current = Get-CapabilityTweakState -Tweak $Tweak
    if ($current.present -and $current.state -eq $State.state) { return }
    Set-TuneupCapabilityState -Name ([string]$Tweak.set.name) -State ([string]$State.state)
}
