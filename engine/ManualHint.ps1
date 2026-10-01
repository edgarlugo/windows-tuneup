# What a person can run to put a tweak back by hand when -Undo could not: one command line per step,
# built from the tweak and the state saved in the journal. Commands are the same in every language;
# an action script, which can change anything, gets a sentence instead.

$script:RegistryKindNames = @{
    String       = 'REG_SZ'
    ExpandString = 'REG_EXPAND_SZ'
    MultiString  = 'REG_MULTI_SZ'
    DWord        = 'REG_DWORD'
    QWord        = 'REG_QWORD'
    Binary       = 'REG_BINARY'
}

function ConvertTo-TuneupRegExePath {
    param([Parameter(Mandatory)][string]$Path)
    $Path -replace '^(HKCU|HKLM):\\', '$1\'
}

# Quotes a value for reg.exe: a double quote inside is written as \".
function ConvertTo-TuneupRegExeQuoted {
    param([AllowEmptyString()][string]$Text)
    '"' + ($Text -replace '"', '\"') + '"'
}

function Get-TuneupRegistryRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    $key = ConvertTo-TuneupRegExeQuoted (ConvertTo-TuneupRegExePath -Path ([string]$Set.path))
    $name = ConvertTo-TuneupRegExeQuoted ([string]$Set.name)
    if (-not $State.exists) { return "reg.exe delete $key /v $name /f" }
    $kind = [string]$State.kind
    if (-not $script:RegistryKindNames.ContainsKey($kind)) { return $null }
    $data = switch ($kind) {
        'MultiString' { ConvertTo-TuneupRegExeQuoted (@($State.value) -join '\0') }
        'Binary' { (@($State.value) | ForEach-Object { '{0:x2}' -f [int]$_ }) -join '' }
        # The registry gives a DWORD as a signed number; reg.exe takes it unsigned.
        'DWord' { $number = [int64]$State.value; if ($number -lt 0) { $number += 4294967296 }; [string]$number }
        'QWord' { [string][int64]$State.value }
        default { ConvertTo-TuneupRegExeQuoted ([string]$State.value) }
    }
    "reg.exe add $key /v $name /t $($script:RegistryKindNames[$kind]) /d $data /f"
}

function Get-TuneupManualRestoreHint {
    param([Parameter(Mandatory)]$Tweak, [AllowNull()]$State)
    $set = $Tweak.set
    if ([string]$Tweak.type -ceq 'appx') { return "winget install --id $($set.storeId) --source msstore" }
    if ([string]$Tweak.type -ceq 'action') { return (Get-TuneupText -Key 'undo.manual.action' -Format $set.script) }
    # The other types need the saved state; without it there is nothing exact to suggest.
    if ($null -eq $State -or $State -is [string] -or $State -is [ValueType]) { return }
    switch -CaseSensitive ([string]$Tweak.type) {
        'registry' { Get-TuneupRegistryRestoreHint -Set $set -State $State }
        'service' {
            if ($State.present -and $script:ScStartArguments.ContainsKey([string]$State.startType)) {
                "sc.exe config `"$($set.name)`" start= $($script:ScStartArguments[[string]$State.startType])"
                if ($State.running) { "sc.exe start `"$($set.name)`"" }
            }
        }
        'task' {
            if ($State.present) {
                $switch = $(if ($State.enabled) { '/ENABLE' } else { '/DISABLE' })
                "schtasks.exe /Change /TN `"$($set.path)$($set.name)`" $switch"
            }
        }
        'capability' {
            if ($State.present) {
                $verb = $(if ($State.state -eq 'Installed') { 'Add-Capability' } else { 'Remove-Capability' })
                "DISM.exe /Online /$verb /CapabilityName:$($set.name)"
            }
        }
        'feature' {
            if ($State.present) {
                $verb = $(if ($State.state -eq 'Enabled') { 'Enable-Feature' } else { 'Disable-Feature' })
                "DISM.exe /Online /$verb /FeatureName:$($set.name) /NoRestart"
            }
        }
        'powercfg' {
            if ($set.kind -eq 'scheme') {
                if ($State.active) { "powercfg.exe /setactive $($State.active)" }
            } elseif ($State.present) {
                $target = Get-TuneupPowerSettingTarget -Set $set
                $ids = "$($State.scheme) $(([string]$set.subgroup).ToLowerInvariant()) $(([string]$set.setting).ToLowerInvariant())"
                if ($null -ne $target.ac) { "powercfg.exe /setacvalueindex $ids $($State.ac)" }
                if ($null -ne $target.dc) { "powercfg.exe /setdcvalueindex $ids $($State.dc)" }
                # Reloads the active scheme, so a change to it takes effect; another scheme is not activated.
                "powercfg.exe /setactive SCHEME_CURRENT"
            }
        }
    }
}
