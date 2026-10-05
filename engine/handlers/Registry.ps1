$script:RegistryKinds = @('DWord', 'QWord', 'String', 'ExpandString')

function Test-TuneupRegistryValue {
    param([string]$Kind, $Value)
    if ($Value -is [array]) { return $false }
    switch ($Kind) {
        'DWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -2147483648 -Max 4294967295) }
        'QWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -9223372036854775808 -Max 9223372036854775807) }
        default { return ($Value -is [string]) }
    }
}

function Test-RegistryTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.path -cnotmatch '^(HKLM|HKCU):\\.+') {
        'has an invalid registry path'
    } elseif (([string]$set.path -cmatch '^HKCU:') -ne ($Tweak.scope -ceq 'user')) {
        'scope does not match its registry hive'
    }
    if ([string]::IsNullOrEmpty([string]$set.name)) { 'is missing set.name' }
    # Only the tweaks that -Startup -Disable builds compare that way (StartupTweak.ps1).
    if ($null -ne $set.PSObject.Properties['compare']) { 'set.compare is only for startup entries (-Startup), never for the catalog' }
    if ($null -ne $set.value) {
        if ($script:RegistryKinds -cnotcontains $set.kind) {
            "has an invalid registry kind '$($set.kind)'"
        } elseif (-not (Test-TuneupRegistryValue -Kind $set.kind -Value $set.value)) {
            "has a value that does not match kind $($set.kind)"
        }
    }
}

function ConvertTo-TuneupDWord {
    param([Parameter(Mandatory)]$Value)
    $number = [int64]$Value
    if ($number -lt 0) { $number += 4294967296 }
    [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$number), 0)
}

function ConvertTo-TuneupByteArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return , ([byte[]]@()) }
    , ([byte[]]@($Value))
}

function Test-TuneupRegistryValueEqual {
    param([Parameter(Mandatory)][string]$Kind, $Current, $Desired)
    switch ($Kind) {
        'DWord' { return (ConvertTo-TuneupDWord -Value $Current) -eq (ConvertTo-TuneupDWord -Value $Desired) }
        'QWord' { return [int64]$Current -eq [int64]$Desired }
        'MultiString' {
            $left = [string[]]@($Current)
            $right = [string[]]@($Desired)
            if ($left.Count -ne $right.Count) { return $false }
            for ($i = 0; $i -lt $left.Count; $i++) {
                if ($left[$i] -cne $right[$i]) { return $false }
            }
            return $true
        }
        { $_ -in 'Binary', 'None', 'Unknown' } {
            $left = ConvertTo-TuneupByteArray -Value $Current
            $right = ConvertTo-TuneupByteArray -Value $Desired
            if ($left.Length -ne $right.Length) { return $false }
            for ($i = 0; $i -lt $left.Length; $i++) {
                if ($left[$i] -ne $right[$i]) { return $false }
            }
            return $true
        }
        default { return [string]$Current -ceq [string]$Desired }
    }
}

function Write-TuneupRawRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()]$Value
    )
    if ($Path -match '^HKCU:\\?(?<sub>.*)$') { $root = [Microsoft.Win32.Registry]::CurrentUser }
    elseif ($Path -match '^HKLM:\\?(?<sub>.*)$') { $root = [Microsoft.Win32.Registry]::LocalMachine }
    else { throw "Unsupported registry path for kind ${Kind}: $Path" }
    $key = $root.OpenSubKey($Matches['sub'], $true)
    if ($null -eq $key) { throw "Cannot open registry key for writing: $Path" }
    try {
        $key.SetValue($Name, (ConvertTo-TuneupByteArray -Value $Value), [Microsoft.Win32.RegistryValueKind]$Kind)
    }
    finally {
        $key.Close()
    }
}

function Write-TuneupRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()]$Value
    )
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    if ($Kind -in 'None', 'Unknown') {
        Write-TuneupRawRegistryValue -Path $Path -Name $Name -Kind $Kind -Value $Value
        return
    }
    if ($Kind -eq 'DWord') { $data = ConvertTo-TuneupDWord -Value $Value }
    elseif ($Kind -eq 'QWord') { $data = [int64]$Value }
    elseif ($Kind -eq 'Binary') { $data = ConvertTo-TuneupByteArray -Value $Value }
    elseif ($Kind -eq 'MultiString') { $data = [string[]]@($Value) }
    else { $data = [string]$Value }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Kind -Value $data -Force -ErrorAction Stop | Out-Null
}

function Remove-TuneupRegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    # An absent value is already gone; any other failure (access denied) must surface.
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $key = Get-Item -LiteralPath $Path
    $present = $key.GetValueNames() -contains $Name
    $key.Close()
    if ($present) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop }
}

function Get-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $path = [string]$Tweak.set.path
    $name = [string]$Tweak.set.name
    $ancestor = $path
    while ($ancestor -and -not (Test-Path -LiteralPath $ancestor)) {
        $ancestor = Split-Path -Path $ancestor -Parent
    }
    $state = [pscustomobject]@{
        keyExisted       = ($ancestor -eq $path)
        existingAncestor = $ancestor
        exists           = $false
        kind             = $null
        value            = $null
    }
    if ($state.keyExisted) {
        $key = Get-Item -LiteralPath $path
        if ($key.GetValueNames() -contains $name) {
            $state.exists = $true
            $state.kind = $key.GetValueKind($name).ToString()
            $state.value = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        }
        $key.Close()
    }
    $state
}

function Test-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $desired = $Tweak.set
    $current = Get-RegistryTweakState -Tweak $Tweak
    if ($null -eq $desired.value) {
        if ($current.exists) { return 'not-applied' }
        return 'applied'
    }
    if (-not $current.exists -or $current.kind -ne $desired.kind) { return 'not-applied' }
    # A startup entry turned off by -Startup -Disable: off is an odd first byte, whatever date follows it,
    # because Task Manager writes a new date each time it turns an entry off. Get still reads the exact bytes,
    # so the journal keeps them and -Undo gives them back as they were.
    $compare = $desired.PSObject.Properties['compare']
    if ($null -ne $compare -and [string]$compare.Value -ceq 'startupApproved') {
        if (Test-TuneupStartupApprovedEnabled -Value @($current.value)) { return 'not-applied' }
        return 'applied'
    }
    if (Test-TuneupRegistryValueEqual -Kind $desired.kind -Current $current.value -Desired $desired.value) { return 'applied' }
    'not-applied'
}

# True when an error is access denied: what Windows answers for a value it keeps from programs (on
# build 26300, AllowNewsAndInterests under the policies of Dsh, even for an administrator, while other
# values of that key can be written) or for a key or value whose access list denies the change.
function Test-TuneupAccessDenied {
    param([Parameter(Mandatory)]$ErrorRecord)
    if ([string]$ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied') { return $true }
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.UnauthorizedAccessException] -or $exception -is [System.Security.SecurityException]) { return $true }
        $exception = $exception.InnerException
    }
    $false
}

# Removes the keys from -Path up to -StopAt (not included), the deepest existing one first, that hold
# nothing, and stops at the first one that holds something. A level that is missing (the creation
# stopped above it) is passed over: every key between -Path and -StopAt was created after the state was
# saved. Without a -StopAt above -Path nothing is removed. Gives the key that could not be removed and
# why, or nothing.
function Remove-TuneupEmptyRegistryKey {
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$StopAt)
    if (-not $StopAt -or -not $Path.StartsWith($StopAt.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return }
    $current = $Path
    while ($current -and $current -ne $StopAt) {
        if (-not (Test-Path -LiteralPath $current)) {
            $current = Split-Path -Path $current -Parent
            continue
        }
        $key = Get-Item -LiteralPath $current
        $isEmpty = ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0)
        $key.Close()
        if (-not $isEmpty) { return }
        try {
            Remove-Item -LiteralPath $current -Force -ErrorAction Stop
        } catch {
            return [pscustomobject]@{ Path = $current; Message = $_.Exception.Message }
        }
        $current = Split-Path -Path $current -Parent
    }
}

# A value that Windows does not let programs change is refused, with what was created for it removed, so
# the state stays as it was journaled (the executor checks it). Without elevation a tweak that needs an
# administrator (a machine value, or a policy of the account) is denied for that reason alone: that stays
# a failure.
function Set-RegistryTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $desired = $Tweak.set
    $before = Get-RegistryTweakState -Tweak $Tweak
    try {
        if ($null -eq $desired.value) {
            Remove-TuneupRegistryValue -Path $desired.path -Name $desired.name
        } else {
            Write-TuneupRegistryValue -Path $desired.path -Name $desired.name -Kind $desired.kind -Value $desired.value
        }
    } catch {
        if (-not (Test-TuneupAccessDenied -ErrorRecord $_) -or ((Test-TuneupTweakNeedsAdmin -Tweak $Tweak) -and -not (Test-TuneupAdmin))) { throw }
        if (-not $before.keyExisted) { [void](Remove-TuneupEmptyRegistryKey -Path $desired.path -StopAt $before.existingAncestor) }
        $target = "$($desired.path)\$($desired.name)"
        $manual = $Tweak.PSObject.Properties['manualSetting']
        $detail = $(if ($null -ne $manual -and $manual.Value) {
                Get-TuneupText -Key 'run.protectedByWindowsManual' -Format $target, (Get-TuneupLocalizedText -Text $manual.Value)
            } else {
                Get-TuneupText -Key 'run.protectedByWindows' -Format $target
            })
        return (New-TuneupOutcome -Refused -Reason 'protected-by-windows' -Detail $detail)
    }
}

# The value goes back as it was; the keys the tweak created go too when they are empty again. An empty
# key that cannot be removed holds nothing and changes nothing: the restore says so instead of failing.
function Restore-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $path = [string]$Tweak.set.path
    $name = [string]$Tweak.set.name
    if ($State.exists) {
        Write-TuneupRegistryValue -Path $path -Name $name -Kind $State.kind -Value $State.value
        return
    }
    Remove-TuneupRegistryValue -Path $path -Name $name
    $left = Remove-TuneupEmptyRegistryKey -Path $path -StopAt ([string]$State.existingAncestor)
    if ($left) { New-TuneupOutcome -Detail (Get-TuneupText -Key 'undo.emptyKeyLeft' -Format $left.Path, $left.Message) }
}
