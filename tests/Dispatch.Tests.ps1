BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Dispatch' {
    It 'routes <Type> tweaks to the <Handler> handler' -TestCases @(
        @{ Type = 'registry'; Handler = 'Registry' }
        @{ Type = 'service'; Handler = 'Service' }
        @{ Type = 'task'; Handler = 'Task' }
    ) {
        Get-TuneupHandlerName -Tweak (New-TestTweak -Type $Type) | Should -Be $Handler
    }

    It 'calls the handler test function' {
        Mock -ModuleName Tuneup Test-RegistryTweakState { 'applied' }
        Test-TuneupState -Tweak (New-TestTweak) | Should -Be 'applied'
    }

    It 'passes the saved state to the handler restore function' {
        Mock -ModuleName Tuneup Restore-RegistryTweakState { }
        $state = [pscustomobject]@{ exists = $false }
        Restore-TuneupState -Tweak (New-TestTweak) -State $state
        Should -Invoke Restore-RegistryTweakState -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $State.exists -eq $false }
    }

    It 'rejects unknown types' {
        { Get-TuneupState -Tweak (New-TestTweak -Type 'magic') } | Should -Throw "*Unsupported tweak type 'magic'*"
    }
}
