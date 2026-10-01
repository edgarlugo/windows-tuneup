# Optimizations for windowed games (Settings > System > Display > Graphics). Windows keeps the
# choice as one item of a REG_SZ list, DirectXUserGlobalSettings, that also holds other choices
# (for example VRROptimizeEnable=0 or AutoHDREnable=1): a plain registry tweak would overwrite them,
# so this script changes only its own item and keeps the others as they are written and in their order.
# The list is read as Windows does: items split at ';', the name before the first '=' without regard
# to case or spaces, and the last copy of a name wins. Undo only puts back its own item (or takes it
# out) and leaves it alone if the user changed it after the apply.
# The value lives in HKCU. Action tweaks run elevated, which on a normal UAC prompt is the same
# account; with an administrator account typed at the prompt it would be that account's setting, so
# the apply refuses when the process is not the account at this desktop, the state saves whose it is
# and the undo of another account leaves it for its owner.

function Get-GamingWindowedOptimizationsActionHelperValue {
    param()
    [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; name = 'DirectXUserGlobalSettings' }
}

function Get-GamingWindowedOptimizationsActionHelperItem {
    param()
    # The item of the list that this script owns.
    'SwapEffectUpgradeEnable'
}

function Get-GamingWindowedOptimizationsActionHelperTweak {
    param([Parameter(Mandatory)]$Tweak)
    # The registry handler reads the value exactly and removes a key it created.
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    [pscustomobject]@{ id = $Tweak.id; set = [pscustomobject]@{ path = $value.path; name = $value.name; kind = 'String'; value = $null } }
}

function Get-GamingWindowedOptimizationsActionHelperSegment {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    # Each piece between ';' as it is written, with its name and value read without spaces.
    foreach ($raw in @(([string]$Text) -split ';')) {
        $at = $raw.IndexOf('=')
        [pscustomobject]@{
            raw   = $raw
            name  = $(if ($at -ge 0) { $raw.Substring(0, $at).Trim() } else { $raw.Trim() })
            value = $(if ($at -ge 0) { $raw.Substring($at + 1).Trim() } else { $null })
        }
    }
}

function Get-GamingWindowedOptimizationsActionHelperSetting {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    # The value of the item that Windows uses: the last copy of the name, or nothing.
    $item = Get-GamingWindowedOptimizationsActionHelperItem
    $value = $null
    foreach ($segment in @(Get-GamingWindowedOptimizationsActionHelperSegment -Text $Text)) {
        if ($segment.name -ieq $item) { $value = $segment.value }
    }
    $value
}

function Get-GamingWindowedOptimizationsActionHelperOtherItem {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    # The other items, without spaces or empty pieces, to tell whether anything else is in the list.
    $item = Get-GamingWindowedOptimizationsActionHelperItem
    @(Get-GamingWindowedOptimizationsActionHelperSegment -Text $Text |
        Where-Object { $_.name -and $_.name -ine $item } | ForEach-Object { "$($_.name)=$($_.value)" })
}

function Edit-GamingWindowedOptimizationsActionHelperList {
    param([AllowNull()][AllowEmptyString()][string]$Text, [AllowNull()]$Value)
    # One copy of the item with $Value in place of the first copy (at the end if there is none), or
    # no copy at all when $Value is null. The other pieces stay exactly as they are written. $Value
    # has no type: a [string] parameter would turn null into an empty value.
    $item = Get-GamingWindowedOptimizationsActionHelperItem
    $pieces = New-Object System.Collections.Generic.List[string]
    $placed = $false
    foreach ($segment in @(Get-GamingWindowedOptimizationsActionHelperSegment -Text $Text)) {
        if ($segment.name -ieq $item) {
            if (-not $placed -and $null -ne $Value) { $pieces.Add("$item=$Value") }
            $placed = $true
            continue
        }
        $pieces.Add($segment.raw)
    }
    $result = $pieces -join ';'
    if (-not $placed -and $null -ne $Value) {
        $result = $result.TrimEnd()
        if ($result -and -not $result.EndsWith(';')) { $result += ';' }
        $result += "$item=$Value;"
    }
    $result
}

function Get-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-RegistryTweakState -Tweak (Get-GamingWindowedOptimizationsActionHelperTweak -Tweak $Tweak)
    $state | Add-Member -NotePropertyName currentUserSid -NotePropertyValue (Get-TuneupCurrentUserSid) -PassThru
}

function Test-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingWindowedOptimizationsActionState -Tweak $Tweak
    if ($state.exists -and $state.kind -ne 'String') {
        throw "DirectXUserGlobalSettings is a $($state.kind) value, not text; it is left as it is"
    }
    if ((Get-GamingWindowedOptimizationsActionHelperSetting -Text $state.value) -ceq '1') { return 'applied' }
    'not-applied'
}

function Set-GamingWindowedOptimizationsActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingWindowedOptimizationsActionState -Tweak $Tweak
    if ($state.exists -and $state.kind -ne 'String') {
        throw "DirectXUserGlobalSettings is a $($state.kind) value, not text; it is left as it is"
    }
    # HKCU is the account of this process: elevated with another administrator's password it would be
    # that administrator's setting, not the one of the account at this desktop.
    if (-not (Test-TuneupSessionUser)) {
        return (New-TuneupOutcome -Refused -Reason 'session-user' -Detail "$($Tweak.id): this process does not run as the account signed in at this desktop (it was elevated with another administrator's password, or there is no desktop to compare with), so the setting would land in another account. Run windows-tuneup from an elevated prompt of the account that is signed in; nothing was changed")
    }
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    $text = Edit-GamingWindowedOptimizationsActionHelperList -Text ([string]$state.value) -Value '1'
    Write-TuneupRegistryValue -Path $value.path -Name $value.name -Kind 'String' -Value $text
}

function Restore-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    $target = Get-GamingWindowedOptimizationsActionHelperTweak -Tweak $Tweak
    $saved = $(if ($State.exists -and $State.kind -eq 'String') { [string]$State.value } else { '' })
    $savedSetting = Get-GamingWindowedOptimizationsActionHelperSetting -Text $saved
    $current = Get-RegistryTweakState -Tweak $target
    $currentSetting = $(if ($current.exists -and $current.kind -eq 'String') { Get-GamingWindowedOptimizationsActionHelperSetting -Text $current.value } else { $null })
    # Only the item that the apply turned on is given back: if it is no longer on, it is either back
    # as it was or the user changed it after the apply, and it is left alone.
    if ($currentSetting -cne '1' -or $savedSetting -ceq '1') {
        if ($currentSetting -ceq $savedSetting) { return }
        return (New-TuneupOutcome -Detail "$(Get-GamingWindowedOptimizationsActionHelperItem) was changed after the apply; it was left as it is")
    }
    $text = Edit-GamingWindowedOptimizationsActionHelperList -Text ([string]$current.value) -Value $savedSetting
    $others = @(Get-GamingWindowedOptimizationsActionHelperOtherItem -Text $text)
    if (($others -join ';') -ceq (@(Get-GamingWindowedOptimizationsActionHelperOtherItem -Text $saved) -join ';') -and
        $savedSetting -ceq (Get-GamingWindowedOptimizationsActionHelperSetting -Text $text)) {
        # Nothing else changed since the apply: the exact text (and a key it created) comes back.
        Restore-RegistryTweakState -Tweak $target -State $State
        return
    }
    Write-TuneupRegistryValue -Path $value.path -Name $value.name -Kind 'String' -Value $text
}
