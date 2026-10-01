BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Dispatch' {
    It 'routes <Type> tweaks to the <Handler> handler' -TestCases @(
        @{ Type = 'registry'; Handler = 'Registry' }
        @{ Type = 'service'; Handler = 'Service' }
        @{ Type = 'task'; Handler = 'Task' }
        @{ Type = 'appx'; Handler = 'Appx' }
        @{ Type = 'capability'; Handler = 'Capability' }
        @{ Type = 'feature'; Handler = 'Feature' }
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

Describe 'Handler registry' {
    It 'has the contract functions for every dispatched type' {
        $missing = foreach ($type in @(Get-TuneupHandlerType)) {
            $name = Get-TuneupHandlerName -Tweak ([pscustomobject]@{ type = $type })
            foreach ($function in "Get-${name}TweakState", "Test-${name}TweakState", "Set-${name}TweakDesired", "Restore-${name}TweakState", "Test-${name}TweakDefinition") {
                if (-not (Get-Command -Name $function -Module Tuneup -ErrorAction SilentlyContinue)) { "${type}: $function" }
            }
        }
        $missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'lets the catalog accept exactly the dispatched types' {
        foreach ($type in @(Get-TuneupHandlerType)) {
            (Test-TuneupTweak -Tweak (New-TestTweak -Type $type)) -join '; ' | Should -Not -Match 'unsupported type' -Because $type
        }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'Registry')) -join '; ' | Should -Match "unsupported type 'Registry'"
        { Get-TuneupHandlerName -Tweak (New-TestTweak -Type 'Registry') } | Should -Throw "*Unsupported tweak type 'Registry'*"
    }

    It 'starts with the types of the first plan' {
        @(Get-TuneupHandlerType)[0..2] -join ',' | Should -Be 'registry,service,task'
    }

    It 'says whether reading a type needs elevation' {
        foreach ($type in 'registry', 'service', 'task') {
            (Get-TuneupHandler -Type $type).ReadNeedsAdmin | Should -BeFalse -Because $type
        }
        foreach ($type in 'appx', 'capability', 'feature') {
            (Get-TuneupHandler -Type $type).ReadNeedsAdmin | Should -BeTrue -Because $type
        }
        Get-TuneupHandler -Type 'magic' | Should -BeNullOrEmpty
        Get-TuneupHandler -Type $null | Should -BeNullOrEmpty
        Get-TuneupHandler -Type @('registry') | Should -BeNullOrEmpty
    }
}

Describe 'Handler outcomes' {
    It 'ignores output that is not an outcome' {
        $outcome = Get-TuneupOutcome -Output @('noise', 5, [pscustomobject]@{ partial = $true; detail = 'plain' })
        $outcome.partial | Should -BeFalse
        $outcome.detail | Should -BeNullOrEmpty
        $outcome.rebootRequired | Should -BeFalse
        $outcome.reason | Should -BeNullOrEmpty
    }

    It 'merges partial, restart, reason and detail' {
        $outcome = Get-TuneupOutcome -Output @(
            (New-TuneupOutcome -Partial -Detail 'one'),
            'noise',
            (New-TuneupOutcome -RebootRequired -Detail 'two' -Reason 'reinstalled'))
        $outcome.partial | Should -BeTrue
        $outcome.rebootRequired | Should -BeTrue
        $outcome.reason | Should -Be 'reinstalled'
        $outcome.detail | Should -Be 'one; two'
    }

    It 'builds a refused outcome only with a reason and a detail, and never together with partial' {
        $outcome = Get-TuneupOutcome -Output @(New-TuneupOutcome -Refused -Reason 'sample-refusal' -Detail 'why')
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be 'sample-refusal'
        $outcome.detail | Should -Be 'why'
        $outcome.partial | Should -BeFalse
        { New-TuneupOutcome -Refused -Detail 'why' } | Should -Throw '*refused outcome needs a reason and a detail*'
        { New-TuneupOutcome -Refused -Reason 'sample-refusal' } | Should -Throw '*refused outcome needs a reason and a detail*'
        { New-TuneupOutcome -Refused -Partial -Reason 'sample-refusal' -Detail 'why' } | Should -Throw '*cannot be refused and partial*'
        (Get-TuneupOutcome -Output @(New-TuneupOutcome -Detail 'plain')).refused | Should -BeFalse
    }

    It 'refuses a partial outcome without a detail' {
        { New-TuneupOutcome -Partial } | Should -Throw '*A partial outcome needs a detail*'
        { New-TuneupOutcome -Partial -Detail '' } | Should -Throw '*A partial outcome needs a detail*'
        (New-TuneupOutcome -Partial -Detail 'x').partial | Should -BeTrue
    }

    It 'returns an empty outcome for no output' {
        $outcome = Get-TuneupOutcome -Output @()
        $outcome.partial | Should -BeFalse
        $outcome.rebootRequired | Should -BeFalse
    }
}
