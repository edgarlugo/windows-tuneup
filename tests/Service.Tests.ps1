BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'services.retail-demo' -Type 'service' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'RetailDemo'; startType = 'Disabled'; stop = $true })
}

Describe 'Service handler' {
    It 'maps Start=<Start> Delayed=<Delayed> to <Expected>' -TestCases @(
        @{ Start = 2; Delayed = 1; Expected = 'AutomaticDelayed' }
        @{ Start = 2; Delayed = $null; Expected = 'Automatic' }
        @{ Start = 3; Delayed = $null; Expected = 'Manual' }
        @{ Start = 4; Delayed = $null; Expected = 'Disabled' }
        @{ Start = 0; Delayed = $null; Expected = 'Boot' }
    ) {
        Mock -ModuleName Tuneup Test-Path { $true }
        Mock -ModuleName Tuneup Get-ItemProperty { [pscustomobject]@{ Start = $Start; DelayedAutostart = $Delayed } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        (Get-ServiceTweakState -Tweak $Tweak).startType | Should -Be $Expected
    }

    It 'reports a missing service as not-present' {
        Mock -ModuleName Tuneup Test-Path { $false }
        Test-ServiceTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'is applied when the start type matches' {
        Mock -ModuleName Tuneup Test-Path { $true }
        Mock -ModuleName Tuneup Get-ItemProperty { [pscustomobject]@{ Start = 4; DelayedAutostart = $null } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        Test-ServiceTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'sets the start type with sc.exe and stops the service when asked' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        Set-ServiceTweakDesired -Tweak $Tweak
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'RetailDemo' -and $Start -eq 'disabled' }
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'restores the previous start type and starts the service if it was running' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Start-Service { }
        $state = [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true }
        Restore-ServiceTweakState -Tweak $Tweak -State $state
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Start -eq 'demand' }
        Should -Invoke Start-Service -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'does not touch boot or system drivers on restore' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        $state = [pscustomobject]@{ present = $true; startType = 'Boot'; running = $false }
        Restore-ServiceTweakState -Tweak $Tweak -State $state
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 0 -Exactly
    }
}
