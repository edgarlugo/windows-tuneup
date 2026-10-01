BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $script:High = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $script:SchemeTweak = New-TestTweak -Id 'power.high-performance' -Type 'powercfg' -Scope 'machine' `
        -Set ([pscustomobject]@{ kind = 'scheme'; scheme = '8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C' })
    # The words follow the Windows language (this is the Spanish output); only the GUIDs are read.
    $script:ActiveBalanced = 'GUID de plan de energ' + [char]0x00ED + 'a: 381b4222-f694-41f0-9685-ff5bb260df2e  (Equilibrado)'
    $script:ActiveHigh = 'Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)'
    $script:BothSchemes = "Existing Power Schemes (* Active)`r`n-----------------------------------`r`nPower Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *`r`nPower Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)"
}

Describe 'powercfg output' {
    It 'reads the GUIDs in lowercase whatever the language' {
        @(Get-TuneupGuidList -Text $ActiveBalanced) -join ',' | Should -BeExactly $Balanced
        @(Get-TuneupGuidList -Text $BothSchemes) -join ',' | Should -BeExactly "$Balanced,$High"
        @(Get-TuneupGuidList -Text 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE') -join '' | Should -BeExactly 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        @(Get-TuneupGuidList -Text '').Count | Should -Be 0
    }

    It 'throws with the exit code when powercfg fails' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 1; Output = 'Invalid Parameters -- try "/?" for help' } }
        { Invoke-TuneupPowercfg -Arguments @('/setactive', $High) } | Should -Throw "*powercfg /setactive $High failed with exit code 1*"
    }

    It 'returns the output when powercfg succeeds' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)' } }
        Get-TuneupActivePowerScheme | Should -Be $Balanced
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\System32\powercfg.exe' -and ($Arguments -join ' ') -eq '/getactivescheme'
        }
    }
}

Describe 'Power scheme' {
    BeforeEach {
        $script:ActiveText = $ActiveBalanced
        $script:ListText = $BothSchemes
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ActiveText } -ParameterFilter { $Arguments[0] -eq '/getactivescheme' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ListText } -ParameterFilter { $Arguments[0] -eq '/list' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { '' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
    }

    It 'reads the active scheme and whether the wanted one exists' {
        $state = Get-TuneupPowerSchemeState -Tweak $SchemeTweak
        $state.kind | Should -Be 'scheme'
        $state.active | Should -Be $Balanced
        $state.exists | Should -BeTrue
        Test-TuneupPowerSchemeState -Tweak $SchemeTweak | Should -Be 'not-applied'
    }

    It 'is applied when the wanted scheme is active' {
        $script:ActiveText = $ActiveHigh
        Test-TuneupPowerSchemeState -Tweak $SchemeTweak | Should -Be 'applied'
    }

    It 'is not-present when the wanted scheme does not exist' {
        $script:ListText = 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *'
        Test-TuneupPowerSchemeState -Tweak $SchemeTweak | Should -Be 'not-present'
    }

    It 'activates a scheme by GUID' {
        Set-TuneupActivePowerScheme -Guid $High
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $High" }
    }
}

Describe 'Power setting' {
    BeforeAll {
        $script:Sleep = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        $script:StandbyIdle = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
        $script:Definition = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\$Sleep\$StandbyIdle"
        $script:UserValues = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$Balanced\$Sleep\$StandbyIdle"
        $script:Defaults = "$Definition\DefaultPowerSchemeValues\$Balanced"
        $script:SettingTweak = New-TestTweak -Id 'power.sleep-after' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = 0; dc = 900 })
    }

    BeforeEach {
        $script:Keys = @{}
        $script:Keys[$Definition] = [pscustomobject]@{}
        $script:Keys[$Defaults] = [pscustomobject]@{ ACSettingIndex = 1800; DCSettingIndex = 900 }
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 0 }
        $script:FailDc = $false
        $script:Denied = @()
        $script:ActiveText = $ActiveBalanced
        $script:ListText = $BothSchemes
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ListText } -ParameterFilter { $Arguments[0] -eq '/list' }
        Mock -ModuleName Tuneup Test-Path { $script:Keys.ContainsKey([string]$LiteralPath) } -ParameterFilter { $LiteralPath -like 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\*' }
        Mock -ModuleName Tuneup Get-ItemProperty {
            if ($script:Denied -contains [string]$LiteralPath) {
                # Like the cmdlet: an error that -ErrorAction can silence.
                $action = $(if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' })
                Write-Error "Access to the path '$LiteralPath' is denied." -ErrorAction $action
                return
            }
            $script:Keys[[string]$LiteralPath]
        } -ParameterFilter { $LiteralPath -like 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\*' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ActiveText } -ParameterFilter { $Arguments[0] -eq '/getactivescheme' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg {
            if ($script:FailDc -and $Arguments[0] -eq '/setdcvalueindex') { throw 'powercfg /setdcvalueindex failed with exit code 1: Invalid Parameters' }
            ''
        } -ParameterFilter { $Arguments[0] -like '/set*' }
    }

    It 'reads the value of the scheme and falls back to its default for each power source' {
        $state = Get-PowercfgTweakState -Tweak $SettingTweak
        $state.kind | Should -Be 'setting'
        $state.scheme | Should -Be $Balanced
        $state.present | Should -BeTrue
        $state.ac | Should -Be 0
        $state.dc | Should -Be 900
        Test-PowercfgTweakState -Tweak $SettingTweak | Should -Be 'applied'
    }

    It 'prefers the provisioned default over the plain one, and the value of the scheme over both' {
        $script:Keys[$Defaults] = [pscustomobject]@{ ACSettingIndex = 1800; DCSettingIndex = 900; ProvAcSettingIndex = 30; ProvDcSettingIndex = 15 }
        $script:Keys.Remove($UserValues)
        $state = Get-PowercfgTweakState -Tweak $SettingTweak
        $state.ac | Should -Be 30
        $state.dc | Should -Be 15
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 0 }
        $state = Get-PowercfgTweakState -Tweak $SettingTweak
        $state.ac | Should -Be 0
        $state.dc | Should -Be 15
    }

    It 'chooses the source of AC and DC independently' {
        $script:Keys[$Defaults] = [pscustomobject]@{ ACSettingIndex = 1800; DCSettingIndex = 900; ProvAcSettingIndex = 30 }
        $script:Keys[$UserValues] = [pscustomobject]@{ DCSettingIndex = 5 }
        $state = Get-PowercfgTweakState -Tweak $SettingTweak
        $state.ac | Should -Be 30
        $state.dc | Should -Be 5
    }

    It 'is not-present, without throwing, when a scheme that is not listed is named' {
        $tweak = New-TestTweak -Id 'power.gone-sleep' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = '11111111-2222-3333-4444-555555555555'; subgroup = $Sleep; setting = $StandbyIdle; ac = 0; dc = 900 })
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'not-present'
        (Get-PowercfgTweakState -Tweak $tweak).present | Should -BeFalse
    }

    It 'says which value is not a DWORD instead of failing in a cast' -TestCases @(
        @{ Keys = @{ ACSettingIndex = 'abc' }; Property = 'ACSettingIndex' }
        @{ Keys = @{ ACSettingIndex = 0; DCSettingIndex = [byte[]]@(1, 2) }; Property = 'DCSettingIndex' }
    ) {
        param($Keys, $Property)
        $script:Keys[$UserValues] = [pscustomobject]$Keys
        { Get-PowercfgTweakState -Tweak $SettingTweak } | Should -Throw "*Cannot read $Property*not a DWORD*"
    }

    It 'says when the provisioned default is not a DWORD' {
        $script:Keys[$Defaults] = [pscustomobject]@{ ProvAcSettingIndex = '30' }
        $script:Keys.Remove($UserValues)
        { Get-PowercfgTweakState -Tweak $SettingTweak } | Should -Throw '*ProvAcSettingIndex*not a DWORD*'
    }

    It 'surfaces the error when a key that exists cannot be read, instead of falling back' -TestCases @(
        @{ Which = 'UserValues' }
        @{ Which = 'Defaults' }
    ) {
        param($Which)
        $script:Denied = @($(if ($Which -eq 'UserValues') { $UserValues } else { $Defaults }))
        { Get-PowercfgTweakState -Tweak $SettingTweak } | Should -Throw '*is denied*'
    }

    It 'still falls back when the key of the scheme does not exist' {
        $script:Keys.Remove($UserValues)
        $script:Denied = @($UserValues)
        (Get-PowercfgTweakState -Tweak $SettingTweak).ac | Should -Be 1800
    }

    It 'is not applied when a value differs' {
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 0; DCSettingIndex = 1800 }
        Test-PowercfgTweakState -Tweak $SettingTweak | Should -Be 'not-applied'
    }

    It 'reads a DWORD above 2147483647 as unsigned' {
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = -1; DCSettingIndex = 0 }
        (Get-PowercfgTweakState -Tweak $SettingTweak).ac | Should -Be 4294967295
    }

    It 'is not-present when Windows does not define the setting' {
        $script:Keys.Remove($Definition)
        Test-PowercfgTweakState -Tweak $SettingTweak | Should -Be 'not-present'
    }

    It 'throws when neither the scheme nor its default has a value' {
        $script:Keys.Remove($Defaults)
        $script:Keys.Remove($UserValues)
        { Get-PowercfgTweakState -Tweak $SettingTweak } | Should -Throw '*Cannot read ACSettingIndex*'
    }

    It 'writes both values and activates the scheme again when it is the active one' {
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $SettingTweak)
        $outcome.partial | Should -BeFalse
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 0" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setdcvalueindex $Balanced $Sleep $StandbyIdle 900" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $Balanced" }
    }

    It 'writes AC, then DC, then activates the scheme again' {
        $script:Calls = @()
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:Calls += $Arguments[0]; '' } -ParameterFilter { $Arguments[0] -like '/set*' }
        Set-PowercfgTweakDesired -Tweak $SettingTweak
        $script:Calls -join ',' | Should -Be '/setacvalueindex,/setdcvalueindex,/setactive'
    }

    It 'lowercases an explicit scheme before it is used' {
        (Resolve-TuneupPowerScheme -Scheme '381B4222-F694-41F0-9685-FF5BB260DF2E') | Should -BeExactly $Balanced
        (Resolve-TuneupPowerScheme -Scheme 'SCHEME_CURRENT') | Should -BeExactly $Balanced
        $tweak = New-TestTweak -Id 'power.balanced-sleep' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = '381B4222-F694-41F0-9685-FF5BB260DF2E'; subgroup = $Sleep.ToUpperInvariant(); setting = $StandbyIdle.ToUpperInvariant(); ac = 0; dc = 900 })
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -ceq "/setacvalueindex $Balanced $Sleep $StandbyIdle 0" }
    }

    It 'activates the wanted scheme with its GUID in lowercase' {
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { '' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
        Set-PowercfgTweakDesired -Tweak $SchemeTweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -ceq "/setactive $High" }
    }

    It 'does not activate a scheme that is not the active one' {
        $script:ActiveText = $ActiveHigh
        $tweak = New-TestTweak -Id 'power.balanced-sleep' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = $Balanced; subgroup = $Sleep; setting = $StandbyIdle; ac = 0; dc = 900 })
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setactive' }
    }

    It 'reports a partial change when the DC value fails after the AC value was written' {
        $script:FailDc = $true
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $SettingTweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*AC power was changed*setdcvalueindex*'
    }

    It 'reports a partial change, not a missing DC value, when only activating the scheme again fails' {
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { throw 'powercfg /setactive failed with exit code 1: Invalid Parameters' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $SettingTweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*AC and DC power were changed*activating the scheme again failed*'
    }

    It 'restores the saved values to the saved scheme even after another one was activated' {
        $script:ActiveText = $ActiveHigh
        $state = [pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 1800; dc = 900 }
        Restore-PowercfgTweakState -Tweak $SettingTweak -State $state
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 1800" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setdcvalueindex $Balanced $Sleep $StandbyIdle 900" }
    }

    It 'throws instead of a partial result when a restore fails half way' {
        $script:FailDc = $true
        $state = [pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 1800; dc = 900 }
        { Restore-PowercfgTweakState -Tweak $SettingTweak -State $state } | Should -Throw '*AC power was changed*'
    }

    It 'throws when a restore cannot activate the scheme again' {
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { throw 'powercfg /setactive failed with exit code 1: Invalid Parameters' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
        $state = [pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 1800; dc = 900 }
        { Restore-PowercfgTweakState -Tweak $SettingTweak -State $state } | Should -Throw '*activating the scheme again failed*'
    }

    It 'writes, compares and restores only the AC value when the tweak gives no DC value' {
        $tweak = New-TestTweak -Id 'power.ac-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = 0 })
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'applied'
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 600 }
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'not-applied'
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 0" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setdcvalueindex' }
        Restore-PowercfgTweakState -Tweak $tweak -State ([pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 600; dc = 300 })
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 600" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setdcvalueindex' }
    }

    It 'treats a null value like an absent one and writes only DC' {
        $tweak = New-TestTweak -Id 'power.dc-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = $null; dc = 600 })
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'not-applied'
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setacvalueindex' }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setdcvalueindex $Balanced $Sleep $StandbyIdle 600" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $Balanced" }
    }

    It 'fails, without a partial result, when the only value cannot be written' {
        $script:FailDc = $true
        $tweak = New-TestTweak -Id 'power.dc-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; dc = 600 })
        { Set-PowercfgTweakDesired -Tweak $tweak } | Should -Throw '*setdcvalueindex failed*'
    }

    It 'names the one value that was changed when activating the scheme again fails' {
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { throw 'powercfg /setactive failed with exit code 1: Invalid Parameters' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
        $tweak = New-TestTweak -Id 'power.ac-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = 5 })
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike 'The value on AC power was changed, but activating the scheme again failed*'
    }

    It 'restores the scheme that was active' {
        Restore-PowercfgTweakState -Tweak $SchemeTweak -State ([pscustomobject]@{ kind = 'scheme'; active = $Balanced; exists = $true })
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $Balanced" }
    }
}

Describe 'Powercfg definition and registration' {
    It 'accepts a valid <Kind> tweak' -TestCases @(
        @{ Kind = 'scheme'; Set = @{ kind = 'scheme'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' } }
        @{ Kind = 'setting'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = 4294967295 } }
        @{ Kind = 'setting with only AC'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0 } }
        @{ Kind = 'setting with only DC'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = $null; dc = 1 } }
    ) {
        param($Set)
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]$Set))) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'an unknown kind'; Set = @{ kind = 'plan'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }; Message = "invalid powercfg kind 'plan'" }
        @{ Problem = 'an alias as scheme to activate'; Set = @{ kind = 'scheme'; scheme = 'SCHEME_MIN' }; Message = 'GUID of the power scheme' }
        @{ Problem = 'a scheme GUID with a trailing newline'; Set = @{ kind = 'scheme'; scheme = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`n" }; Message = 'GUID of the power scheme' }
        @{ Problem = 'a subgroup GUID with a trailing newline'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = "238c9fa8-0aad-41ed-83f4-97be242c8f20`n"; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = 0 }; Message = 'set.subgroup must be a GUID' }
        @{ Problem = 'a subgroup alias'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = 'SUB_SLEEP'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = 0 }; Message = 'set.subgroup must be a GUID' }
        @{ Problem = 'a value out of range'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 4294967296; dc = 0 }; Message = 'set.ac must be an integer' }
        @{ Problem = 'a value that is text'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = '900' }; Message = 'set.dc must be an integer' }
        @{ Problem = 'neither an AC nor a DC value'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' }; Message = 'needs set.ac, set.dc or both' }
        @{ Problem = 'both values null'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = $null; dc = $null }; Message = 'needs set.ac, set.dc or both' }
    ) {
        param($Set, $Message)
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]$Set))) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'requires scope machine' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'powercfg' -Scope 'user' -Set $SchemeTweak.set)) -join '; ' | Should -Match 'must use scope machine'
    }

    It 'is a dispatched type that reads without elevation' {
        Get-TuneupHandlerName -Tweak $SchemeTweak | Should -Be 'Powercfg'
        (Get-TuneupHandler -Type 'powercfg').ReadNeedsAdmin | Should -BeFalse
    }
}
