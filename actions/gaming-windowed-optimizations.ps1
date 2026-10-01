# Optimizations for windowed games (Settings > System > Display > Graphics). Windows keeps the
# choice as one token of a REG_SZ list, DirectXUserGlobalSettings, that also holds other choices
# (for example VRROptimizeEnable=0 or AutoHDREnable=1): a plain registry tweak would overwrite them,
# so this script changes only its own token and keeps the others and their order.
# The value lives in HKCU. Action tweaks run elevated, which on a normal UAC prompt is the same
# account; with an administrator account typed at the prompt it would be that account's setting.

function Get-GamingWindowedOptimizationsActionHelperValue {
    param()
    [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; name = 'DirectXUserGlobalSettings' }
}

function Get-GamingWindowedOptimizationsActionHelperTweak {
    param([Parameter(Mandatory)]$Tweak)
    # The registry handler reads, writes and restores the value exactly (and removes a key it created).
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    [pscustomobject]@{ id = $Tweak.id; set = [pscustomobject]@{ path = $value.path; name = $value.name; kind = 'String'; value = $null } }
}

function Get-GamingWindowedOptimizationsActionHelperToken {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    @(([string]$Text) -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
}

function Get-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak)
    Get-RegistryTweakState -Tweak (Get-GamingWindowedOptimizationsActionHelperTweak -Tweak $Tweak)
}

function Test-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingWindowedOptimizationsActionState -Tweak $Tweak
    if ($state.exists -and $state.kind -ne 'String') {
        throw "DirectXUserGlobalSettings is a $($state.kind) value, not text; it is left as it is"
    }
    if (@(Get-GamingWindowedOptimizationsActionHelperToken -Text $state.value) -ccontains 'SwapEffectUpgradeEnable=1') { return 'applied' }
    'not-applied'
}

function Set-GamingWindowedOptimizationsActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingWindowedOptimizationsActionState -Tweak $Tweak
    if ($state.exists -and $state.kind -ne 'String') {
        throw "DirectXUserGlobalSettings is a $($state.kind) value, not text; it is left as it is"
    }
    $tokens = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($token in @(Get-GamingWindowedOptimizationsActionHelperToken -Text $state.value)) {
        if ($token -like 'SwapEffectUpgradeEnable=*') {
            if (-not $found) { $tokens.Add('SwapEffectUpgradeEnable=1') }
            $found = $true
            continue
        }
        $tokens.Add($token)
    }
    if (-not $found) { $tokens.Add('SwapEffectUpgradeEnable=1') }
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    Write-TuneupRegistryValue -Path $value.path -Name $value.name -Kind 'String' -Value (($tokens -join ';') + ';')
}

function Restore-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    Restore-RegistryTweakState -Tweak (Get-GamingWindowedOptimizationsActionHelperTweak -Tweak $Tweak) -State $State
}
