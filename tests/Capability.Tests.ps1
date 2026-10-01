BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Name = 'App.StepsRecorder~~~~0.0.1.0'
    $script:Tweak = New-TestTweak -Id 'apps.steps-recorder' -Type 'capability' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = $Name; state = 'NotPresent' })
}

Describe 'Capability handler' {
    BeforeEach {
        $script:Raw = 'Installed'
        Mock -ModuleName Tuneup Get-TuneupWindowsCapability { [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0'; State = $script:Raw } }
    }

    It 'maps <Raw> to <Expected>' -TestCases @(
        @{ Raw = 'Installed'; Expected = 'Installed' }
        @{ Raw = 'InstallPending'; Expected = 'Installed' }
        @{ Raw = 'NotPresent'; Expected = 'NotPresent' }
        @{ Raw = 'UninstallPending'; Expected = 'NotPresent' }
        @{ Raw = 'Staged'; Expected = 'NotPresent' }
        @{ Raw = 'Removed'; Expected = 'NotPresent' }
    ) {
        param($Raw, $Expected)
        ConvertTo-TuneupCapabilityState -State $Raw | Should -Be $Expected
    }

    It 'does not read <Raw> as installed or not present' -TestCases @(
        @{ Raw = 'PartiallyInstalled' }
        @{ Raw = 'Superseded' }
        @{ Raw = 'Resolved' }
        @{ Raw = 'Unheard' }
        @{ Raw = '' }
        @{ Raw = $null }
    ) {
        param($Raw)
        $null -eq (ConvertTo-TuneupCapabilityState -State $Raw) | Should -BeTrue
    }

    It 'leaves a capability in the unusual state <Raw> alone' -TestCases @(
        @{ Raw = 'PartiallyInstalled' }
        @{ Raw = 'Superseded' }
        @{ Raw = 'Resolved' }
        @{ Raw = $null }
    ) {
        param($Raw)
        $script:Raw = $Raw
        (Get-CapabilityTweakState -Tweak $Tweak).present | Should -BeFalse
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'is not applied while the capability is installed' {
        (Get-CapabilityTweakState -Tweak $Tweak).state | Should -Be 'Installed'
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'is applied once the removal waits for a restart' {
        $script:Raw = 'UninstallPending'
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a capability that this Windows does not list as not-present' {
        Mock -ModuleName Tuneup Get-TuneupWindowsCapability { }
        (Get-CapabilityTweakState -Tweak $Tweak).present | Should -BeFalse
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'removes the capability and passes on a restart request' {
        Mock -ModuleName Tuneup Remove-TuneupWindowsCapability { [pscustomobject]@{ RestartNeeded = $true } }
        $outcome = Get-TuneupOutcome -Output @(Set-CapabilityTweakDesired -Tweak $Tweak)
        $outcome.rebootRequired | Should -BeTrue
        Should -Invoke Remove-TuneupWindowsCapability -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'App.StepsRecorder~~~~0.0.1.0' }
    }

    It 'adds the capability back on restore' {
        $script:Raw = 'NotPresent'
        Mock -ModuleName Tuneup Add-TuneupWindowsCapability { [pscustomobject]@{ RestartNeeded = $false } }
        $outcome = Get-TuneupOutcome -Output @(Restore-CapabilityTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Installed' }))
        $outcome.rebootRequired | Should -BeFalse
        Should -Invoke Add-TuneupWindowsCapability -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'App.StepsRecorder~~~~0.0.1.0' }
    }

    It 'does nothing on restore when the capability is already as it was' {
        Mock -ModuleName Tuneup Add-TuneupWindowsCapability { }
        Mock -ModuleName Tuneup Remove-TuneupWindowsCapability { }
        Restore-CapabilityTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Installed' })
        Should -Invoke Add-TuneupWindowsCapability -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Remove-TuneupWindowsCapability -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'does nothing on restore when the capability was not present' {
        Mock -ModuleName Tuneup Add-TuneupWindowsCapability { }
        Restore-CapabilityTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $false; state = $null })
        Should -Invoke Add-TuneupWindowsCapability -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Capability system calls' {
    BeforeEach {
        Clear-TuneupCapabilityCache
    }

    It 'lists the capabilities once and again after a change' {
        # The look-alikes come first: a prefix or first-match lookup would return one of them.
        Mock -ModuleName Tuneup Get-WindowsCapability {
            [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0x'; State = 'NotPresent' }
            [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.'; State = 'NotPresent' }
            [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0'; State = 'Installed' }
        }
        Mock -ModuleName Tuneup Remove-WindowsCapability { }
        (Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0').State | Should -Be 'Installed'
        (Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0').State | Should -Be 'Installed'
        Should -Invoke Get-WindowsCapability -ModuleName Tuneup -Times 1 -Exactly
        Remove-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0'
        Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0' | Out-Null
        Should -Invoke Get-WindowsCapability -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'lists the capabilities again after adding one' {
        Mock -ModuleName Tuneup Get-WindowsCapability { [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0'; State = 'NotPresent' } }
        Mock -ModuleName Tuneup Add-WindowsCapability { }
        Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0' | Out-Null
        Add-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0'
        Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0' | Out-Null
        Should -Invoke Get-WindowsCapability -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'explains that adding a capability needs a source' {
        Mock -ModuleName Tuneup Add-WindowsCapability { throw 'The source files could not be found.' }
        { Add-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0' } |
            Should -Throw '*Windows Update or a features-on-demand source*source files could not be found*'
    }
}

Describe 'Capability definition and registration' {
    It 'accepts a valid capability tweak' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a name without the version part'; Set = @{ name = 'App.StepsRecorder'; state = 'NotPresent' }; Scope = 'machine'; Message = 'invalid capability name' }
        @{ Problem = 'a wildcard'; Set = @{ name = 'App.Steps*~~~~0.0.1.0'; state = 'NotPresent' }; Scope = 'machine'; Message = 'invalid capability name' }
        @{ Problem = 'a name with a trailing newline'; Set = @{ name = "App.StepsRecorder~~~~0.0.1.0`n"; state = 'NotPresent' }; Scope = 'machine'; Message = 'invalid capability name' }
        @{ Problem = 'an unknown state'; Set = @{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'Removed' }; Scope = 'machine'; Message = "invalid capability state 'Removed'" }
        @{ Problem = 'scope user'; Set = @{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' }; Scope = 'user'; Message = 'must use scope machine' }
    ) {
        param($Set, $Scope, $Message)
        $tweak = New-TestTweak -Type 'capability' -Scope $Scope -Set ([pscustomobject]$Set)
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'is a dispatched type that needs elevation to read' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Capability'
        (Get-TuneupHandler -Type 'capability').ReadNeedsAdmin | Should -BeTrue
    }
}
