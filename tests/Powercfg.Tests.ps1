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
        @(Get-TuneupGuidList -Text $ActiveBalanced) -join ',' | Should -Be $Balanced
        @(Get-TuneupGuidList -Text $BothSchemes) -join ',' | Should -Be "$Balanced,$High"
        @(Get-TuneupGuidList -Text 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE') -join '' | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
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
