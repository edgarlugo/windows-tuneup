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
    ) {
        param($Present, $Expected)
        Get-TuneupArgumentConflict -Present $Present | Should -Be $Expected
    }
}
