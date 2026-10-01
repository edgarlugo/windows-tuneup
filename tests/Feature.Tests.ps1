BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'apps.work-folders' -Type 'feature' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'WorkFolders-Client'; state = 'Disabled' })
}

Describe 'Feature handler' {
    BeforeEach {
        $script:Raw = 'Enabled'
        Mock -ModuleName Tuneup Get-TuneupWindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'WorkFolders-Client'; State = $script:Raw } }
    }

    It 'maps <Raw> to <Expected>' -TestCases @(
        @{ Raw = 'Enabled'; Expected = 'Enabled' }
        @{ Raw = 'EnablePending'; Expected = 'Enabled' }
        @{ Raw = 'Disabled'; Expected = 'Disabled' }
        @{ Raw = 'DisablePending'; Expected = 'Disabled' }
        @{ Raw = 'DisabledWithPayloadRemoved'; Expected = 'Disabled' }
    ) {
        param($Raw, $Expected)
        ConvertTo-TuneupFeatureState -State $Raw | Should -Be $Expected
    }

    It 'does not read <Raw> as enabled or disabled' -TestCases @(
        @{ Raw = 'PartiallyInstalled' }
        @{ Raw = 'Superseded' }
        @{ Raw = 'Unheard' }
        @{ Raw = '' }
        @{ Raw = $null }
    ) {
        param($Raw)
        $null -eq (ConvertTo-TuneupFeatureState -State $Raw) | Should -BeTrue
    }

    It 'leaves a feature in the unusual state <Raw> alone' -TestCases @(
        @{ Raw = 'PartiallyInstalled' }
        @{ Raw = 'Superseded' }
        @{ Raw = $null }
    ) {
        param($Raw)
        $script:Raw = $Raw
        (Get-FeatureTweakState -Tweak $Tweak).present | Should -BeFalse
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'is not applied while the feature is enabled' {
        (Get-FeatureTweakState -Tweak $Tweak).state | Should -Be 'Enabled'
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'counts a feature without its files as disabled' {
        $script:Raw = 'DisabledWithPayloadRemoved'
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a feature that this Windows does not list as not-present' {
        Mock -ModuleName Tuneup Get-TuneupWindowsOptionalFeature { }
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'disables the feature and passes on a restart request' {
        Mock -ModuleName Tuneup Disable-TuneupWindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $true } }
        $outcome = Get-TuneupOutcome -Output @(Set-FeatureTweakDesired -Tweak $Tweak)
        $outcome.rebootRequired | Should -BeTrue
        Should -Invoke Disable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'WorkFolders-Client' }
    }

    It 'enables the feature again on restore' {
        $script:Raw = 'Disabled'
        Mock -ModuleName Tuneup Enable-TuneupWindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $true } }
        $outcome = Get-TuneupOutcome -Output @(Restore-FeatureTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Enabled' }))
        $outcome.rebootRequired | Should -BeTrue
        Should -Invoke Enable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'WorkFolders-Client' }
    }

    It 'does nothing on restore when the feature is already as it was' {
        Mock -ModuleName Tuneup Enable-TuneupWindowsOptionalFeature { }
        Mock -ModuleName Tuneup Disable-TuneupWindowsOptionalFeature { }
        Restore-FeatureTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Enabled' })
        Should -Invoke Enable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Disable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Feature system calls' {
    BeforeEach {
        Clear-TuneupFeatureCache
    }

    It 'lists the features once and again after a change, without -All or -Remove' {
        # The look-alikes come first: a prefix or first-match lookup would return one of them.
        Mock -ModuleName Tuneup Get-WindowsOptionalFeature {
            [pscustomobject]@{ FeatureName = 'WorkFolders-Client-Extra'; State = 'Disabled' }
            [pscustomobject]@{ FeatureName = 'WorkFolders'; State = 'Disabled' }
            [pscustomobject]@{ FeatureName = 'TFTP-Legacy'; State = 'Enabled' }
            [pscustomobject]@{ FeatureName = 'WorkFolders-Client'; State = 'Enabled' }
            [pscustomobject]@{ FeatureName = 'TFTP'; State = 'Disabled' }
        }
        Mock -ModuleName Tuneup Disable-WindowsOptionalFeature { }
        (Get-TuneupWindowsOptionalFeature -Name 'TFTP').State | Should -Be 'Disabled'
        (Get-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client').State | Should -Be 'Enabled'
        Should -Invoke Get-WindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly
        Disable-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client'
        Should -Invoke Disable-WindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FeatureName -eq 'WorkFolders-Client' -and $NoRestart -and -not $Remove
        }
        Get-TuneupWindowsOptionalFeature -Name 'TFTP' | Out-Null
        Should -Invoke Get-WindowsOptionalFeature -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'lists the features again after enabling one' {
        Mock -ModuleName Tuneup Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'WorkFolders-Client'; State = 'Disabled' } }
        Mock -ModuleName Tuneup Enable-WindowsOptionalFeature { }
        Get-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client' | Out-Null
        Enable-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client'
        Get-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client' | Out-Null
        Should -Invoke Get-WindowsOptionalFeature -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'explains that enabling a feature may need a source' {
        Mock -ModuleName Tuneup Enable-WindowsOptionalFeature { throw 'The source files could not be found.' }
        { Enable-TuneupWindowsOptionalFeature -Name 'NetFx3' } | Should -Throw '*installation source*source files could not be found*'
        Should -Invoke Enable-WindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $NoRestart -and -not $All }
    }
}

Describe 'Feature definition and registration' {
    It 'accepts a valid feature tweak' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a wildcard'; Set = @{ name = 'WorkFolders*'; state = 'Disabled' }; Scope = 'machine'; Message = 'invalid feature name' }
        @{ Problem = 'a name with a trailing newline'; Set = @{ name = "WorkFolders-Client`n"; state = 'Disabled' }; Scope = 'machine'; Message = 'invalid feature name' }
        @{ Problem = 'an unknown state'; Set = @{ name = 'WorkFolders-Client'; state = 'Off' }; Scope = 'machine'; Message = "invalid feature state 'Off'" }
        @{ Problem = 'scope user'; Set = @{ name = 'WorkFolders-Client'; state = 'Disabled' }; Scope = 'user'; Message = 'must use scope machine' }
    ) {
        param($Set, $Scope, $Message)
        $tweak = New-TestTweak -Type 'feature' -Scope $Scope -Set ([pscustomobject]$Set)
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'is a dispatched type that needs elevation to read' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Feature'
        (Get-TuneupHandler -Type 'feature').ReadNeedsAdmin | Should -BeTrue
    }
}
