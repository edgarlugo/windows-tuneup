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

Describe 'Test-TuneupHasBattery' {
    BeforeEach {
        $script:Batteries = @()
        $script:Chassis = @()
        Mock -ModuleName Tuneup Get-CimInstance { $script:Batteries } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        Mock -ModuleName Tuneup Get-CimInstance { $script:Chassis } -ParameterFilter { $ClassName -eq 'Win32_SystemEnclosure' }
    }

    It 'is false without a battery, whatever the chassis' {
        $script:Chassis = @([pscustomobject]@{ ChassisTypes = @([uint16]10) })
        Test-TuneupHasBattery | Should -BeFalse
    }

    It 'is true for a battery in a portable chassis (<Type>)' -TestCases @(
        @{ Type = 8 }, @{ Type = 9 }, @{ Type = 10 }, @{ Type = 14 }, @{ Type = 30 }, @{ Type = 31 }, @{ Type = 32 }
    ) {
        param($Type)
        $script:Batteries = @([pscustomobject]@{ Name = 'Battery' })
        $script:Chassis = @([pscustomobject]@{ ChassisTypes = @([uint16]$Type) })
        Test-TuneupHasBattery | Should -BeTrue
    }

    It 'is false for a battery in a desktop chassis (a UPS that reports as a battery)' {
        $script:Batteries = @([pscustomobject]@{ Name = 'UPS' })
        $script:Chassis = @([pscustomobject]@{ ChassisTypes = @([uint16]3) })
        Test-TuneupHasBattery | Should -BeFalse
    }

    It 'trusts the battery when there is no chassis information' {
        $script:Batteries = @([pscustomobject]@{ Name = 'Battery' })
        Test-TuneupHasBattery | Should -BeTrue
        $script:Chassis = @([pscustomobject]@{ ChassisTypes = $null })
        Test-TuneupHasBattery | Should -BeTrue
    }
}

Describe 'Test-TuneupSessionUser' {
    BeforeAll {
        $script:Me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }

    It 'is true only when the account at this desktop is the one of this process: <Name>' -TestCases @(
        @{ Name = 'the same account'; Owners = @('ME'); Expected = $true }
        @{ Name = 'another administrator'; Owners = @('S-1-5-21-1000000000-2000000000-3000000000-1001'); Expected = $false }
        @{ Name = 'two accounts'; Owners = @('ME', 'S-1-5-21-1000000000-2000000000-3000000000-1001'); Expected = $false }
        @{ Name = 'no desktop'; Owners = @(); Expected = $false }
        @{ Name = 'the desktop cannot be read'; Owners = @('throw'); Expected = $false }
    ) {
        param($Owners, $Expected)
        $script:Owners = @($Owners | ForEach-Object { $_ -replace '^ME$', $Me })
        Mock -ModuleName Tuneup Get-TuneupSessionUserSid { if ($script:Owners -contains 'throw') { throw 'denied' }; $script:Owners }
        Test-TuneupSessionUser | Should -Be $Expected
    }

    It 'reads the owners of explorer.exe in this session without changing anything' {
        foreach ($sid in @(Get-TuneupSessionUserSid)) { $sid | Should -Match '^S-1-' }
    }
}

Describe 'Get-TuneupEnvironment account at the desktop' {
    It 'asks whether the process is the account at the desktop only when elevated' -TestCases @(
        @{ Admin = $true; Same = $false; Expected = $false }
        @{ Admin = $true; Same = $true; Expected = $true }
        @{ Admin = $false; Same = $false; Expected = $true }
    ) {
        param($Admin, $Same, $Expected)
        $script:Admin = $Admin
        $script:Same = $Same
        Mock -ModuleName Tuneup Test-TuneupAdmin { $script:Admin }
        Mock -ModuleName Tuneup Test-TuneupSessionUser { $script:Same }
        (Get-TuneupEnvironment).IsSessionUser | Should -Be $Expected
    }
}
