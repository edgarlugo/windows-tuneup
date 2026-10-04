BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
}

Describe 'Get-TuneupArgumentConflict' {
    It 'accepts <Name>' -TestCases @(
        @{ Name = 'a plan'; Present = @('Profile', 'Include', 'Exclude', 'WhatIf') }
        @{ Name = 'applying'; Present = @('Profile', 'Yes') }
        @{ Name = 'nothing'; Present = @() }
        @{ Name = 'status'; Present = @('Status') }
        @{ Name = 'undo of one tweak'; Present = @('Undo', 'Tweak') }
        @{ Name = 'health with repair'; Present = @('Health', 'Repair') }
        @{ Name = 'measure with compare and idle time'; Present = @('Measure', 'Compare', 'IdleSeconds') }
        @{ Name = 'a re-apply'; Present = @('Status', 'Reapply') }
        @{ Name = 'a re-apply without asking'; Present = @('Status', 'Reapply', 'Yes') }
        @{ Name = 'the plan of a re-apply'; Present = @('Status', 'Reapply', 'WhatIf') }
        @{ Name = 'a re-apply of the tweaks it names'; Present = @('Status', 'Reapply', 'Include', 'Yes') }
        @{ Name = 'the list'; Present = @('List') }
        @{ Name = 'the suggestions'; Present = @('Suggest') }
        @{ Name = 'reading a result'; Present = @('ReadResult') }
        @{ Name = 'what starts with Windows'; Present = @('Startup') }
        @{ Name = 'turning startup entries off'; Present = @('Startup', 'Disable', 'Yes') }
        @{ Name = 'the plan of turning them off'; Present = @('Startup', 'Disable', 'WhatIf') }
    ) {
        param($Present)
        Get-TuneupArgumentConflict -Present $Present | Should -BeNullOrEmpty
    }

    It 'rejects <Expected>' -TestCases @(
        @{ Present = @('Tweak'); Expected = '-Tweak (-Undo)' }
        @{ Present = @('Repair'); Expected = '-Repair (-Health)' }
        @{ Present = @('Compare'); Expected = '-Compare (-Measure)' }
        @{ Present = @('IdleSeconds', 'Status'); Expected = '-IdleSeconds (-Measure)' }
        @{ Present = @('Status', 'Undo'); Expected = '-Status -Undo' }
        @{ Present = @('Health', 'Measure'); Expected = '-Health -Measure' }
        @{ Present = @('Undo', 'Health'); Expected = '-Undo -Health' }
        @{ Present = @('Status', 'Profile', 'WhatIf'); Expected = '-Status -Profile -WhatIf' }
        @{ Present = @('Measure', 'Yes'); Expected = '-Measure -Yes' }
        @{ Present = @('Health', 'Include'); Expected = '-Health -Include' }
        @{ Present = @('Reapply'); Expected = '-Reapply (-Status)' }
        @{ Present = @('Status', 'Yes'); Expected = '-Status -Yes' }
        @{ Present = @('Status', 'Reapply', 'Profile'); Expected = '-Status -Profile' }
        @{ Present = @('Status', 'Reapply', 'Exclude', 'Yes'); Expected = '-Status -Exclude' }
        @{ Present = @('Status', 'Include'); Expected = '-Status -Include' }
        @{ Present = @('Undo', 'Include'); Expected = '-Undo -Include' }
        @{ Present = @('List', 'Suggest'); Expected = '-List -Suggest' }
        @{ Present = @('Status', 'List'); Expected = '-Status -List' }
        @{ Present = @('Suggest', 'Measure'); Expected = '-Measure -Suggest' }
        @{ Present = @('List', 'Profile'); Expected = '-List -Profile' }
        @{ Present = @('Suggest', 'WhatIf'); Expected = '-Suggest -WhatIf' }
        @{ Present = @('List', 'Yes'); Expected = '-List -Yes' }
        @{ Present = @('ReadResult', 'Status'); Expected = '-Status -ReadResult' }
        @{ Present = @('ReadResult', 'Suggest'); Expected = '-Suggest -ReadResult' }
        @{ Present = @('ReadResult', 'Profile'); Expected = '-ReadResult -Profile' }
        @{ Present = @('ReadResult', 'Yes'); Expected = '-ReadResult -Yes' }
        @{ Present = @('ReadResult', 'WhatIf'); Expected = '-ReadResult -WhatIf' }
        @{ Present = @('Disable'); Expected = '-Disable (-Startup)' }
        @{ Present = @('Status', 'Disable'); Expected = '-Disable (-Startup)' }
        @{ Present = @('Startup', 'Yes'); Expected = '-Startup -Yes' }
        @{ Present = @('Startup', 'WhatIf'); Expected = '-Startup -WhatIf' }
        @{ Present = @('Startup', 'List'); Expected = '-List -Startup' }
        @{ Present = @('Startup', 'Suggest'); Expected = '-Suggest -Startup' }
        @{ Present = @('Startup', 'ReadResult'); Expected = '-Startup -ReadResult' }
        @{ Present = @('Startup', 'Profile'); Expected = '-Startup -Profile' }
        @{ Present = @('Startup', 'Disable', 'Include', 'Yes'); Expected = '-Startup -Include' }
        @{ Present = @('Startup', 'Disable', 'Exclude'); Expected = '-Startup -Exclude' }
        @{ Present = @('Startup', 'Reapply'); Expected = '-Reapply (-Status)' }
    ) {
        param($Present, $Expected)
        Get-TuneupArgumentConflict -Present $Present | Should -Be $Expected
    }
}

Describe 'Write-TuneupActionsPathWarning' {
    It 'warns when elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        Write-TuneupActionsPathWarning -WarningVariable warned -WarningAction SilentlyContinue
        @($warned).Count | Should -Be 1
        "$($warned[0])" | Should -Be '-ActionsPath loads functions that run with administrator rights; use only for development and testing'
    }

    It 'stays quiet when not elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        Write-TuneupActionsPathWarning -WarningVariable warned -WarningAction SilentlyContinue
        @($warned).Count | Should -Be 0
    }
}

Describe 'Invoke-TuneupStepCollectingWarning' {
    BeforeEach {
        $script:Collected = New-Object 'System.Collections.Generic.List[string]'
    }

    It 'shows each distinct warning once, however many steps raise it' {
        $first = Invoke-TuneupStepCollectingWarning -Warnings $Collected -Step { Write-Warning 'same'; 'one' } 3>&1
        $second = Invoke-TuneupStepCollectingWarning -Warnings $Collected -Step { Write-Warning 'same'; Write-Warning 'other'; 'two' } 3>&1
        @($first | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        @($second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message }) -join ',' | Should -Be 'other'
        $Collected -join ',' | Should -Be 'same,other'
        @($first | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }) | Should -Be 'one'
    }

    It 'keeps the warnings out of the output with -Json and collects them once' {
        $output = Invoke-TuneupStepCollectingWarning -Warnings $Collected -Json -Step { Write-Warning 'same'; Write-Warning 'same'; 'one' } 3>&1
        @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
        $Collected -join ',' | Should -Be 'same'
        @($output) | Should -Be 'one'
    }

    It 'returns what the step returns, and lets an error go through' {
        @(Invoke-TuneupStepCollectingWarning -Warnings $Collected -Step { 1, 2, 3 }) -join ',' | Should -Be '1,2,3'
        { Invoke-TuneupStepCollectingWarning -Warnings $Collected -Step { throw 'boom' } } | Should -Throw 'boom'
    }
}
