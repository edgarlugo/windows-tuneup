BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
}

Describe 'ConvertTo-TuneupEdition' {
    It 'maps <EditionId> to <Expected>' -TestCases @(
        @{ EditionId = 'Core'; Expected = 'Home' }
        @{ EditionId = 'CoreSingleLanguage'; Expected = 'Home' }
        @{ EditionId = 'Professional'; Expected = 'Pro' }
        @{ EditionId = 'ProfessionalWorkstation'; Expected = 'Pro' }
        @{ EditionId = 'ProfessionalEducation'; Expected = 'Pro' }
        @{ EditionId = 'Enterprise'; Expected = 'Enterprise' }
        @{ EditionId = 'EnterpriseS'; Expected = 'Enterprise' }
        @{ EditionId = 'IoTEnterpriseS'; Expected = 'Enterprise' }
        @{ EditionId = 'Education'; Expected = 'Education' }
        @{ EditionId = 'ServerDatacenter'; Expected = 'Server' }
        @{ EditionId = 'Mystery'; Expected = 'Unknown' }
    ) {
        ConvertTo-TuneupEdition -EditionId $EditionId | Should -Be $Expected
    }
}

Describe 'Resolve-TuneupEdition' {
    It 'maps <EditionId> on <InstallationType> to <Expected>' -TestCases @(
        @{ EditionId = 'ServerDatacenter'; InstallationType = 'Server'; Expected = 'Server' }
        @{ EditionId = 'ServerStandard'; InstallationType = 'Server Core'; Expected = 'Server' }
        @{ EditionId = 'ServerRdsh'; InstallationType = 'Client'; Expected = 'Enterprise' }
        @{ EditionId = 'Professional'; InstallationType = 'Client'; Expected = 'Pro' }
        @{ EditionId = 'Core'; InstallationType = ''; Expected = 'Home' }
        @{ EditionId = 'Enterprise'; InstallationType = 'Server'; Expected = 'Server' }
        @{ EditionId = 'Mystery'; InstallationType = 'Client'; Expected = 'Unknown' }
    ) {
        Resolve-TuneupEdition -EditionId $EditionId -InstallationType $InstallationType | Should -Be $Expected
    }
}

Describe 'Get-TuneupFamily' {
    It 'returns <Expected> for build <Build>' -TestCases @(
        @{ Build = 19045; Expected = '10' }
        @{ Build = 22000; Expected = '11' }
        @{ Build = 26300; Expected = '11' }
    ) {
        Get-TuneupFamily -Build $Build | Should -Be $Expected
    }
}

Describe 'Get-TuneupEnvironment' {
    It 'describes the current machine' {
        $environment = Get-TuneupEnvironment
        $environment.Build | Should -BeGreaterThan 0
        $environment.Family | Should -BeIn @('10', '11')
        $environment.Edition | Should -Not -BeNullOrEmpty
        $environment.IsAdmin | Should -BeOfType [bool]
        $environment.IsManaged | Should -BeOfType [bool]
        $environment.PendingReboot | Should -BeOfType [bool]
    }
}
