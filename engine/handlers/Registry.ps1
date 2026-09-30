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
    if (Test-TuneupRegistryValueEqual -Kind $desired.kind -Current $current.value -Desired $desired.value) { return 'applied' }
    'not-applied'
}

function Set-RegistryTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $desired = $Tweak.set
    if ($null -eq $desired.value) {
        if (Test-Path -LiteralPath $desired.path) {
            Remove-ItemProperty -LiteralPath $desired.path -Name $desired.name -ErrorAction SilentlyContinue
        }
        return
    }
    Write-TuneupRegistryValue -Path $desired.path -Name $desired.name -Kind $desired.kind -Value $desired.value
}

function Restore-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $path = [string]$Tweak.set.path
    $name = [string]$Tweak.set.name
    if ($State.exists) {
        Write-TuneupRegistryValue -Path $path -Name $name -Kind $State.kind -Value $State.value
        return
    }
    if (Test-Path -LiteralPath $path) {
        Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
    }
    $current = $path
    while ($current -and $current -ne $State.existingAncestor -and (Test-Path -LiteralPath $current)) {
        $key = Get-Item -LiteralPath $current
        $isEmpty = ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0)
        $key.Close()
        if (-not $isEmpty) { break }
        Remove-Item -LiteralPath $current -Force -ErrorAction Stop
        $current = Split-Path -Path $current -Parent
    }
}
