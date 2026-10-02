BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:I18nRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
    Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
    function New-TestUninstallEntry([string]$Name, [string]$DisplayName) {
        $path = Join-Path $Key "Uninstall\$Name"
        New-Item -Path $path -Force | Out-Null
        if ($DisplayName) { New-ItemProperty -LiteralPath $path -Name DisplayName -Value $DisplayName -PropertyType String | Out-Null }
    }
}

Describe 'Suggest detectors' {
    BeforeEach { Remove-TestKey }
    AfterAll { Remove-TestKey }

    It 'reads the display names of the uninstall entries, skipping entries without one and missing roots' {
        New-TestUninstallEntry -Name 'A' -DisplayName 'Steam'
        New-TestUninstallEntry -Name 'B'
        New-TestUninstallEntry -Name 'C' -DisplayName 'Git'
        @(Get-TuneupInstalledProgramName -Root @("$Key\Uninstall", "$Key\Missing") | Sort-Object) -join ',' | Should -Be 'Git,Steam'
    }

    It 'reads the names of the Store packages of the current user' {
        Mock -ModuleName Tuneup Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.GamingServices' }, [pscustomobject]@{ Name = 'Microsoft.WindowsCalculator' } }
        @(Get-TuneupUserAppxName) -join ',' | Should -Be 'Microsoft.GamingServices,Microsoft.WindowsCalculator'
    }

    It 'reads whether the computer is in a domain and how much memory it has' {
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; TotalPhysicalMemory = [uint64]4GB } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        $computer = Get-TuneupComputerSystem
        $computer.PartOfDomain | Should -BeTrue
        $computer.TotalPhysicalMemory | Should -Be 4GB
    }

    It 'fails when the computer system cannot be read' {
        Mock -ModuleName Tuneup Get-CimInstance { throw 'Access denied' } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        { Get-TuneupComputerSystem } | Should -Throw '*Access denied*'
    }

    It 'sees an Entra ID join only when JoinInfo has an entry' {
        Test-TuneupEntraJoined -Path "$Key\JoinInfo" | Should -BeFalse
        New-Item -Path "$Key\JoinInfo" -Force | Out-Null
        Test-TuneupEntraJoined -Path "$Key\JoinInfo" | Should -BeFalse
        New-Item -Path "$Key\JoinInfo\0123456789ABCDEF" -Force | Out-Null
        Test-TuneupEntraJoined -Path "$Key\JoinInfo" | Should -BeTrue
    }

    It 'gives <Expected> for media type <MediaType> of the disk that holds the system drive' -TestCases @(
        @{ MediaType = 3; Expected = 'HDD' }
        @{ MediaType = 4; Expected = 'SSD' }
        @{ MediaType = 5; Expected = 'SCM' }
        @{ MediaType = 0; Expected = 'Unspecified' }
    ) {
        param($MediaType, $Expected)
        $script:MediaType = $MediaType
        Mock -ModuleName Tuneup Get-TuneupSystemDrive { 'D:\' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ DiskNumber = 2 } } -ParameterFilter { $ClassName -eq 'MSFT_Partition' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ MediaType = [uint16]$script:MediaType } } -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' }
        Get-TuneupSystemDiskMediaType | Should -Be $Expected
        Should -Invoke -ModuleName Tuneup Get-CimInstance -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'MSFT_Partition' -and $Filter -eq "DriveLetter = 'D'" -and $Namespace -eq 'root/Microsoft/Windows/Storage' }
        Should -Invoke -ModuleName Tuneup Get-CimInstance -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' -and $Filter -eq "DeviceId = '2'" }
    }

    It 'fails when the system drive is not on a physical disk it can find' {
        Mock -ModuleName Tuneup Get-TuneupSystemDrive { 'C:\' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ DiskNumber = 7 } } -ParameterFilter { $ClassName -eq 'MSFT_Partition' }
        Mock -ModuleName Tuneup Get-CimInstance { } -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' }
        { Get-TuneupSystemDiskMediaType } | Should -Throw '*physical disk 7*'
    }
}
