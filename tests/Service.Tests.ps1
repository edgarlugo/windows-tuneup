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

    It 'treats a service key without a Start value as not-present' {
        Mock -ModuleName Tuneup Test-Path { $true }
        Mock -ModuleName Tuneup Get-ItemProperty { [pscustomobject]@{ ImagePath = 'x.exe' } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        $state = Get-ServiceTweakState -Tweak $Tweak
        $state.present | Should -BeFalse
        Test-ServiceTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'sets the start type with sc.exe and stops a running service without -Force' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        Set-ServiceTweakDesired -Tweak $Tweak
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'RetailDemo' -and $Start -eq 'disabled' }
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { -not $Force -and $ErrorAction -eq 'Stop' }
    }

    It 'does not stop a service that is not running' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $false } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        Set-ServiceTweakDesired -Tweak $Tweak
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'reports a partial change when stopping fails after the start type was changed' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { throw 'cannot stop' }
        $outcome = Get-TuneupOutcome -Output @(Set-ServiceTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -Be 'Start type of RetailDemo set to Disabled, but stopping it failed: cannot stop'
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'fails without a partial result when the start type cannot be changed' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { throw 'sc.exe config RetailDemo start= disabled failed with exit code 5: Access is denied.' }
        Mock -ModuleName Tuneup Stop-Service { }
        { Set-ServiceTweakDesired -Tweak $Tweak } | Should -Throw '*exit code 5*'
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 0 -Exactly
    }
    It 'refuses to change a <Current> driver before calling sc.exe' -TestCases @(
        @{ Current = 'Boot' }
        @{ Current = 'System' }
    ) {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = $Current; running = $false } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        { Set-ServiceTweakDesired -Tweak $Tweak } | Should -Throw 'Refusing to change boot or system driver RetailDemo'
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'restores the previous start type and starts the service if it was running' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Start-Service { }
        $state = [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true }
        Restore-ServiceTweakState -Tweak $Tweak -State $state
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Start -eq 'demand' }
        Should -Invoke Start-Service -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'surfaces a failed service start from restore' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Start-Service { throw 'cannot start' }
        $state = [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true }
        { Restore-ServiceTweakState -Tweak $Tweak -State $state } | Should -Throw '*cannot start*'
    }

    It 'does not touch boot or system drivers on restore' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        $state = [pscustomobject]@{ present = $true; startType = 'Boot'; running = $false }
        Restore-ServiceTweakState -Tweak $Tweak -State $state
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 0 -Exactly
    }
}
