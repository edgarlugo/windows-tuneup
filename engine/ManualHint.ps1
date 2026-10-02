# What a person can run to put a tweak back by hand when -Undo could not: one PowerShell command per
# line, built from the tweak and the state saved in the journal. Every name and value that comes from
# the catalog or the journal goes in a single-quoted literal with its quotes doubled, so nothing in it
# is expanded or run when the line is pasted. Commands are the same in every language; an action
# script, which can change anything, gets a sentence instead.

$script:RegistryHiveNames = @{ HKCU = 'HKEY_CURRENT_USER'; HKLM = 'HKEY_LOCAL_MACHINE' }
$script:ServiceStartTypeNames = @{ Automatic = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
# A service name that sc.exe takes as one word; anything else gets no sc.exe line.
$script:ScServiceNamePattern = '^[A-Za-z0-9_.@-]+\z'

# A PowerShell single-quoted literal. PowerShell reads four characters as a single quote (the ASCII
# one and the typographic ones), so all of them are doubled; a line break is written as [char] so the
# command stays on one line.
function ConvertTo-TuneupPsLiteral {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $quotes = "'" + [char]0x2018 + [char]0x2019 + [char]0x201A + [char]0x201B
    $escaped = [regex]::Replace([string]$Text, "[$quotes]", '$0$0')
    if ($escaped -notmatch '[\r\n]') { return "'$escaped'" }
    $escaped = $escaped.Replace("`r", "' + [char]13 + '").Replace("`n", "' + [char]10 + '")
    "('$escaped')"
}

function ConvertTo-TuneupBytesLiteral {
    param([AllowNull()]$Value)
    $bytes = @($Value | Where-Object { $null -ne $_ } | ForEach-Object { '0x{0:x2}' -f [int]$_ })
    if (-not $bytes.Count) { return '([byte[]]@())' }
    "([byte[]]($($bytes -join ',')))"
}

function Get-TuneupRegistryRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    $path = [string]$Set.path
    $pathText = ConvertTo-TuneupPsLiteral -Text $path
    $nameText = ConvertTo-TuneupPsLiteral -Text ([string]$Set.name)
    if (-not $State.exists) {
        "Remove-ItemProperty -LiteralPath $pathText -Name $nameText"
        # The keys that this tweak created and that are empty again go too (deepest first); a key
        # that holds anything else stays, and the line says so.
        $ancestor = [string]$State.existingAncestor
        if ($ancestor) {
            $current = $path
            while ($current -and $current -ne $ancestor -and $current -match '^(HKCU|HKLM):\\.+') {
                $keyText = ConvertTo-TuneupPsLiteral -Text $current
                "`$k = Get-Item -LiteralPath $keyText -ErrorAction SilentlyContinue; if (`$k -and `$k.ValueCount -eq 0 -and `$k.SubKeyCount -eq 0) { Remove-Item -LiteralPath $keyText } else { 'Not removed: it holds other values or keys, or it is already gone.' }"
                $current = Split-Path -Path $current -Parent
            }
        }
        return
    }
    $kind = [string]$State.kind
    $common = "-LiteralPath $pathText -Name $nameText"
    switch -CaseSensitive ($kind) {
        'DWord' { return "New-ItemProperty $common -PropertyType DWord -Value $([string](ConvertTo-TuneupDWord -Value $State.value)) -Force | Out-Null" }
        'QWord' { return "New-ItemProperty $common -PropertyType QWord -Value $([string][int64]$State.value) -Force | Out-Null" }
        'String' { return "New-ItemProperty $common -PropertyType String -Value $(ConvertTo-TuneupPsLiteral -Text ([string]$State.value)) -Force | Out-Null" }
        'ExpandString' { return "New-ItemProperty $common -PropertyType ExpandString -Value $(ConvertTo-TuneupPsLiteral -Text ([string]$State.value)) -Force | Out-Null" }
        'MultiString' {
            $items = @($State.value | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-TuneupPsLiteral -Text ([string]$_) })
            $list = $(if ($items.Count) { "@($($items -join ','))" } else { '([string[]]@())' })
            return "New-ItemProperty $common -PropertyType MultiString -Value $list -Force | Out-Null"
        }
        'Binary' { return "New-ItemProperty $common -PropertyType Binary -Value $(ConvertTo-TuneupBytesLiteral -Value $State.value) -Force | Out-Null" }
        { $_ -ceq 'None' -or $_ -ceq 'Unknown' } {
            # PowerShell has no -PropertyType for these; the .NET call is the one that writes them.
            if ($path -notmatch '^(?<hive>HKCU|HKLM):\\(?<sub>.+)$') { return }
            $fullKey = ConvertTo-TuneupPsLiteral -Text "$($script:RegistryHiveNames[$Matches['hive']])\$($Matches['sub'])"
            return "[Microsoft.Win32.Registry]::SetValue($fullKey, $nameText, $(ConvertTo-TuneupBytesLiteral -Value $State.value), [Microsoft.Win32.RegistryValueKind]::None)"
        }
    }
}

function Get-TuneupServiceRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    $name = [string]$Set.name
    $nameText = ConvertTo-TuneupPsLiteral -Text $name
    $startType = [string]$State.startType
    if ($script:ServiceStartTypeNames.ContainsKey($startType)) {
        "Set-Service -Name $nameText -StartupType $($script:ServiceStartTypeNames[$startType])"
    } elseif ($startType -ceq 'AutomaticDelayed' -and $name -cmatch $script:ScServiceNamePattern) {
        # Set-Service in Windows PowerShell 5.1 has no delayed start.
        "sc.exe config $nameText start= delayed-auto"
    }
    if ($State.running) { "Start-Service -Name $nameText" }
}

function Get-TuneupPowercfgRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    if ([string]$Set.kind -ceq 'scheme') {
        if ([string]$State.active -match $script:GuidPattern) { "powercfg.exe /setactive $($State.active)" }
        return
    }
    if (-not $State.present) { return }
    $ids = @([string]$State.scheme, [string]$Set.subgroup, [string]$Set.setting)
    if (@($ids | Where-Object { $_ -notmatch $script:GuidPattern }).Count) { return }
    $target = Get-TuneupPowerSettingTarget -Set $Set
    $indexes = "$($ids[0]) $(([string]$ids[1]).ToLowerInvariant()) $(([string]$ids[2]).ToLowerInvariant())"
    foreach ($source in @(@('ac', 'setacvalueindex'), @('dc', 'setdcvalueindex'))) {
        if ($null -eq $target.($source[0])) { continue }
        $number = [uint32]$State.($source[0])
        "powercfg.exe /$($source[1]) $indexes $number"
    }
    # Reloads the active scheme, so a change to it takes effect; another scheme is not activated.
    'powercfg.exe /setactive SCHEME_CURRENT'
}

# The lines for a result of -Undo. A hint that cannot be built (an odd value in a saved state) gives
# no lines and does not hide the failure that it was meant to help with.
function Get-TuneupManualRestoreLine {
    param([Parameter(Mandatory)]$Tweak, [AllowNull()]$State)
    try {
        [string[]]@(Get-TuneupManualRestoreHint -Tweak $Tweak -State $State)
    } catch {
        [string[]]@()
    }
}

function Get-TuneupManualRestoreHint {
    param([Parameter(Mandatory)]$Tweak, [AllowNull()]$State)
    $set = $Tweak.set
    if ([string]$Tweak.type -ceq 'appx') {
        if ([string]$set.storeId -cmatch $script:StoreIdPattern) { Get-TuneupWingetManualCommand -StoreId ([string]$set.storeId) }
        return
    }
    if ([string]$Tweak.type -ceq 'action') { return (Get-TuneupText -Key 'undo.manual.action' -Format $set.script) }
    # The other types need the saved state; without it there is nothing exact to suggest.
    if ($null -eq $State -or $State -is [string] -or $State -is [ValueType]) { return }
    switch -CaseSensitive ([string]$Tweak.type) {
        'registry' { Get-TuneupRegistryRestoreHint -Set $set -State $State }
        'service' { Get-TuneupServiceRestoreHint -Set $set -State $State }
        'task' {
            if ($State.present) {
                $verb = $(if ($State.enabled) { 'Enable-ScheduledTask' } else { 'Disable-ScheduledTask' })
                "$verb -TaskPath $(ConvertTo-TuneupPsLiteral -Text ([string]$set.path)) -TaskName $(ConvertTo-TuneupPsLiteral -Text ([string]$set.name))"
            }
        }
        'capability' {
            if ($State.present) {
                $verb = $(if ($State.state -eq 'Installed') { 'Add-WindowsCapability' } else { 'Remove-WindowsCapability' })
                "$verb -Online -Name $(ConvertTo-TuneupPsLiteral -Text ([string]$set.name))"
            }
        }
        'feature' {
            if ($State.present) {
                $verb = $(if ($State.state -eq 'Enabled') { 'Enable-WindowsOptionalFeature' } else { 'Disable-WindowsOptionalFeature' })
                "$verb -Online -FeatureName $(ConvertTo-TuneupPsLiteral -Text ([string]$set.name)) -NoRestart"
            }
        }
        'powercfg' { Get-TuneupPowercfgRestoreHint -Set $set -State $State }
    }
}
