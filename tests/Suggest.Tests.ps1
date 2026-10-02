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

Describe 'Get-TuneupSuggestion' {
    BeforeEach {
        # Nothing found by default; each test changes what one source gives, or makes it fail.
        $script:Fake = @{
            Programs = @(); Packages = @(); Battery = $false; Entra = $false; Mdm = $false; Disk = 'SSD'; Fail = @(); Memory = $null
            Os = [pscustomobject]@{ Build = 26100; Edition = 'Pro'; IsServer = $false }
            Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]16GB }
        }
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { if ($script:Fake.Fail -contains 'programs') { throw 'access denied' }; $script:Fake.Programs }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { if ($script:Fake.Fail -contains 'packages') { throw 'no Appx module' }; $script:Fake.Packages }
        Mock -ModuleName Tuneup Test-TuneupSuggestBattery { if ($script:Fake.Fail -contains 'battery') { throw 'battery query failed' }; $script:Fake.Battery }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { if ($script:Fake.Fail -contains 'computer') { throw 'WMI is broken' }; $script:Fake.Computer }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $script:Fake.Entra }
        Mock -ModuleName Tuneup Test-TuneupSuggestMdm { if ($script:Fake.Fail -contains 'mdm') { throw 'enrollments denied' }; $script:Fake.Mdm }
        Mock -ModuleName Tuneup Get-TuneupInstalledMemoryByte { if ($script:Fake.Fail -contains 'memory') { throw 'no memory modules' }; $script:Fake.Memory }
        Mock -ModuleName Tuneup Get-TuneupOsSupport { if ($script:Fake.Fail -contains 'os') { throw 'registry denied' }; $script:Fake.Os }
        Mock -ModuleName Tuneup Get-TuneupSystemDiskMediaType { if ($script:Fake.Fail -contains 'disk') { throw 'Cannot find physical disk 3' }; $script:Fake.Disk }
        function Get-Signal($Document, [string]$Id) { $Document.signals | Where-Object { $_.id -eq $Id } }
    }

    It 'suggests only base on a PC without signals, and asks about privacy and lite' {
        $document = Get-TuneupSuggestion
        $document.schemaVersion | Should -Be 1
        $document.command | Should -Be 'suggest'
        @($document.signals | ForEach-Object { $_.id }) -join ',' | Should -Be 'dev,gaming,laptop,work,legacy,managed'
        @($document.signals | Where-Object { $_.detected }).Count | Should -Be 0
        @($document.signals | ForEach-Object { @($_.evidence).Count } | Where-Object { $_ }).Count | Should -Be 0
        @($document.suggestions | ForEach-Object { $_.profile }) -join ',' | Should -Be 'base'
        @($document.suggestions[0].signals).Count | Should -Be 0
        @($document.questions | ForEach-Object { $_.id }) -join ',' | Should -Be 'privacy,lite'
        foreach ($question in $document.questions) { $question.text | Should -Not -BeLike 'suggest.*' }
    }

    It 'finds <Signal> from <Case>' -TestCases @(
        @{ Signal = 'dev'; Case = 'Visual Studio Code'; Field = 'Programs'; Value = @('Microsoft Visual Studio Code (User)'); Evidence = 'Visual Studio Code' }
        @{ Signal = 'dev'; Case = 'Visual Studio'; Field = 'Programs'; Value = @('Visual Studio Community 2022'); Evidence = 'Visual Studio' }
        @{ Signal = 'dev'; Case = 'a JetBrains IDE'; Field = 'Programs'; Value = @('PyCharm Community Edition 2024.1'); Evidence = 'JetBrains' }
        @{ Signal = 'dev'; Case = 'RustRover without the JetBrains prefix'; Field = 'Programs'; Value = @('RustRover 2024.2'); Evidence = 'JetBrains' }
        @{ Signal = 'dev'; Case = 'Rider without the JetBrains prefix'; Field = 'Programs'; Value = @('Rider 2024.2'); Evidence = 'JetBrains' }
        @{ Signal = 'dev'; Case = 'Fleet'; Field = 'Programs'; Value = @('Fleet'); Evidence = 'JetBrains' }
        @{ Signal = 'dev'; Case = 'the Python install manager from the Store'; Field = 'Packages'; Value = @('PythonSoftwareFoundation.PythonManager'); Evidence = 'Python' }
        @{ Signal = 'dev'; Case = 'Git'; Field = 'Programs'; Value = @('Git'); Evidence = 'Git' }
        @{ Signal = 'dev'; Case = 'Node.js'; Field = 'Programs'; Value = @('Node.js'); Evidence = 'Node.js' }
        @{ Signal = 'dev'; Case = 'Python'; Field = 'Programs'; Value = @('Python 3.12.4 (64-bit)'); Evidence = 'Python' }
        @{ Signal = 'dev'; Case = 'Python from the Store'; Field = 'Packages'; Value = @('PythonSoftwareFoundation.Python.3.12'); Evidence = 'Python' }
        @{ Signal = 'dev'; Case = 'a JDK'; Field = 'Programs'; Value = @('Eclipse Temurin JDK with Hotspot 21.0.4+7 (x64)'); Evidence = 'JDK' }
        @{ Signal = 'dev'; Case = 'WSL'; Field = 'Packages'; Value = @('MicrosoftCorporationII.WindowsSubsystemForLinux'); Evidence = 'WSL' }
        @{ Signal = 'gaming'; Case = 'Steam'; Field = 'Programs'; Value = @('Steam'); Evidence = 'Steam' }
        @{ Signal = 'gaming'; Case = 'Epic Games'; Field = 'Programs'; Value = @('Epic Games Launcher'); Evidence = 'Epic Games Launcher' }
        @{ Signal = 'gaming'; Case = 'EA app'; Field = 'Programs'; Value = @('EA app'); Evidence = 'EA app' }
        @{ Signal = 'gaming'; Case = 'Game Pass'; Field = 'Packages'; Value = @('Microsoft.GamingServices'); Evidence = 'Xbox Gaming Services' }
        @{ Signal = 'laptop'; Case = 'a battery'; Field = 'Battery'; Value = $true; Evidence = 'battery' }
        @{ Signal = 'work'; Case = 'a domain'; Field = 'Computer'; Value = [pscustomobject]@{ PartOfDomain = $true; TotalPhysicalMemory = [double]16GB }; Evidence = 'domain' }
        @{ Signal = 'work'; Case = 'Entra ID'; Field = 'Entra'; Value = $true; Evidence = 'Entra ID' }
        @{ Signal = 'work'; Case = 'MDM'; Field = 'Mdm'; Value = $true; Evidence = 'MDM' }
        @{ Signal = 'legacy'; Case = '4 GB of RAM'; Field = 'Computer'; Value = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]3.8GB }; Evidence = 'RAM 4 GB' }
        @{ Signal = 'legacy'; Case = 'a hard disk'; Field = 'Disk'; Value = 'HDD'; Evidence = 'HDD' }
    ) {
        param($Signal, $Field, $Value, $Evidence)
        $script:Fake[$Field] = $Value
        $document = Get-TuneupSuggestion
        $found = Get-Signal $document $Signal
        $found.detected | Should -BeTrue
        @($found.evidence) | Should -Contain $Evidence
        $suggestion = $document.suggestions | Where-Object { $_.profile -eq $Signal }
        @($suggestion.signals) -join ',' | Should -Be $Signal
        $document.suggestions[0].profile | Should -Be 'base'
    }

    It 'does not take other programs whose name starts like a JetBrains tool or Python' {
        $script:Fake.Programs = @('Riders of the Storm', 'Fleetwood Player', 'Pythonista Notes')
        $script:Fake.Packages = @('PythonSoftwareFoundation.Other')
        (Get-Signal (Get-TuneupSuggestion) 'dev').detected | Should -BeFalse
    }

    It 'does not take the Xbox app or the Game Bar that come with Windows for games' {
        $script:Fake.Packages = @('Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider')
        (Get-Signal (Get-TuneupSuggestion) 'gaming').detected | Should -BeFalse
    }

    It 'does not take 8 GB, which Windows reports as a little less, for an old PC' {
        $script:Fake.Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]7.8GB }
        (Get-Signal (Get-TuneupSuggestion) 'legacy').detected | Should -BeFalse
    }

    It 'calls a PC in a domain or in MDM managed, without suggesting a profile for it' {
        $script:Fake.Computer = [pscustomobject]@{ PartOfDomain = $true; TotalPhysicalMemory = [double]16GB }
        $script:Fake.Mdm = $true
        $document = Get-TuneupSuggestion
        $managed = Get-Signal $document 'managed'
        $managed.detected | Should -BeTrue
        @($managed.evidence) -join ',' | Should -Be 'domain,MDM'
        @($document.suggestions | ForEach-Object { $_.profile }) -join ',' | Should -Be 'base,work'
    }

    It 'does not call a PC joined to Entra ID alone managed' {
        $script:Fake.Entra = $true
        $document = Get-TuneupSuggestion
        (Get-Signal $document 'work').detected | Should -BeTrue
        (Get-Signal $document 'managed').detected | Should -BeFalse
    }

    It 'lists the suggested profiles in the order of the signals, each product once' {
        $script:Fake.Programs = @('Steam', 'Git', 'Git')
        $script:Fake.Battery = $true
        $document = Get-TuneupSuggestion
        @($document.suggestions | ForEach-Object { $_.profile }) -join ',' | Should -Be 'base,dev,gaming,laptop'
        @((Get-Signal $document 'dev').evidence) -join ',' | Should -Be 'Git'
    }

    It 'keeps going when a detector fails: that part is left out and a warning says so' {
        $script:Fake.Fail = @('programs')
        $script:Fake.Packages = @('Microsoft.GamingServices')
        $output = @(Get-TuneupSuggestion 3>&1)
        $warned = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $document = $output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
        (Get-Signal $document 'dev').detected | Should -BeFalse
        (Get-Signal $document 'gaming').detected | Should -BeTrue
        @($warned).Count | Should -Be 1
        "$($warned[0])" | Should -Match 'installed programs.*access denied'
    }

    It 'still finds work from MDM when the computer cannot be read' {
        $script:Fake.Fail = @('computer', 'disk')
        $script:Fake.Mdm = $true
        $output = @(Get-TuneupSuggestion 3>&1)
        $warned = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $document = $output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
        @((Get-Signal $document 'work').evidence) -join ',' | Should -Be 'MDM'
        (Get-Signal $document 'legacy').detected | Should -BeFalse
        @($warned).Count | Should -Be 2
    }
}

Describe 'Get-TuneupSuggestion memory, strict detectors and Windows support' {
    BeforeEach {
        $script:Fake = @{
            Fail = @(); Memory = $null; Battery = $false; Mdm = $false
            Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]16GB }
            Os = [pscustomobject]@{ Build = 26100; Edition = 'Pro'; IsServer = $false }
        }
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { @() }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { @() }
        Mock -ModuleName Tuneup Test-TuneupSuggestBattery { if ($script:Fake.Fail -contains 'battery') { throw 'battery query failed' }; $script:Fake.Battery }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { $script:Fake.Computer }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupSuggestMdm { if ($script:Fake.Fail -contains 'mdm') { throw 'enrollments denied' }; $script:Fake.Mdm }
        Mock -ModuleName Tuneup Get-TuneupSystemDiskMediaType { 'SSD' }
        Mock -ModuleName Tuneup Get-TuneupInstalledMemoryByte { if ($script:Fake.Fail -contains 'memory') { throw 'no memory modules' }; $script:Fake.Memory }
        Mock -ModuleName Tuneup Get-TuneupOsSupport { if ($script:Fake.Fail -contains 'os') { throw 'registry denied' }; $script:Fake.Os }
        function Split-Output($Output) {
            [pscustomobject]@{
                Warnings = @($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
                Document = ($Output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
            }
        }
    }

    It 'trusts the installed memory over what Windows reports, which leaves out what hardware reserves' {
        $script:Fake.Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]6.5GB }
        $script:Fake.Memory = [double]8GB
        $legacy = (Get-TuneupSuggestion).signals | Where-Object { $_.id -eq 'legacy' }
        $legacy.detected | Should -BeFalse
        $script:Fake.Memory = [double]4GB
        $legacy = (Get-TuneupSuggestion).signals | Where-Object { $_.id -eq 'legacy' }
        @($legacy.evidence) -join ',' | Should -Be 'RAM 4 GB'
    }

    It 'falls back to the memory Windows reports, rounded half away from zero, when the modules are not known' {
        $script:Fake.Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]6.5GB }
        $legacy = (Get-TuneupSuggestion).signals | Where-Object { $_.id -eq 'legacy' }
        @($legacy.evidence) -join ',' | Should -Be 'RAM 7 GB'
    }

    It 'falls back quietly when the modules cannot be read' {
        $script:Fake.Fail = @('memory')
        $script:Fake.Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]3.8GB }
        $result = Split-Output @(Get-TuneupSuggestion 3>&1)
        @(($result.Document.signals | Where-Object { $_.id -eq 'legacy' }).evidence) -join ',' | Should -Be 'RAM 4 GB'
        $result.Warnings.Count | Should -Be 0
    }

    It 'still reads the memory when the computer system cannot be read' {
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { throw 'WMI is broken' }
        $script:Fake.Memory = [double]4GB
        $result = Split-Output @(Get-TuneupSuggestion 3>&1)
        @(($result.Document.signals | Where-Object { $_.id -eq 'legacy' }).evidence) -join ',' | Should -Be 'RAM 4 GB'
        $result.Warnings.Count | Should -Be 1
    }

    It 'warns when the battery cannot be read, instead of calling it no battery' {
        $script:Fake.Fail = @('battery')
        $result = Split-Output @(Get-TuneupSuggestion 3>&1)
        $result.Warnings.Count | Should -Be 1
        "$($result.Warnings[0])" | Should -Match 'battery.*battery query failed'
        ($result.Document.signals | Where-Object { $_.id -eq 'laptop' }).detected | Should -BeFalse
    }

    It 'warns when the MDM enrollments cannot be read, instead of calling it not enrolled' {
        $script:Fake.Fail = @('mdm')
        $result = Split-Output @(Get-TuneupSuggestion 3>&1)
        $result.Warnings.Count | Should -Be 1
        "$($result.Warnings[0])" | Should -Match 'MDM.*enrollments denied'
    }

    It 'says nothing about Windows when it is supported' {
        (Split-Output @(Get-TuneupSuggestion 3>&1)).Warnings.Count | Should -Be 0
    }

    It 'warns that the profiles need -Force on <Case>' -TestCases @(
        @{ Case = 'Windows Server'; Os = [pscustomobject]@{ Build = 26100; Edition = 'Server'; IsServer = $true } }
        @{ Case = 'a build older than 19041'; Os = [pscustomobject]@{ Build = 17763; Edition = 'Pro'; IsServer = $false } }
        @{ Case = 'an unknown edition'; Os = [pscustomobject]@{ Build = 26100; Edition = 'Unknown'; IsServer = $false } }
    ) {
        param($Os)
        $script:Fake.Os = $Os
        $result = Split-Output @(Get-TuneupSuggestion 3>&1)
        $result.Document.command | Should -Be 'suggest'
        $result.Warnings.Count | Should -Be 1
        "$($result.Warnings[0])" | Should -Match 'not supported.*-Force'
    }

    It 'gives no warning about Windows when it cannot tell which one this is' {
        $script:Fake.Fail = @('os')
        $result = Split-Output @(Get-TuneupSuggestion 3>&1)
        $result.Document.command | Should -Be 'suggest'
        $result.Warnings.Count | Should -Be 0
    }
}

Describe 'Strict detectors of -Suggest' {
    BeforeEach { Remove-TestKey }
    AfterAll { Remove-TestKey }

    It 'reads that a battery is there, in a portable chassis or in an unknown one' {
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ Name = 'Battery' } } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ ChassisTypes = [uint16[]]@(10) } } -ParameterFilter { $ClassName -eq 'Win32_SystemEnclosure' }
        Test-TuneupSuggestBattery | Should -BeTrue
        Mock -ModuleName Tuneup Get-CimInstance { } -ParameterFilter { $ClassName -eq 'Win32_SystemEnclosure' }
        Test-TuneupSuggestBattery | Should -BeTrue
    }

    It 'says no battery for a desktop chassis with an uninterruptible supply, and when there is none' {
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ Name = 'UPS' } } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ ChassisTypes = [uint16[]]@(3) } } -ParameterFilter { $ClassName -eq 'Win32_SystemEnclosure' }
        Test-TuneupSuggestBattery | Should -BeFalse
        Mock -ModuleName Tuneup Get-CimInstance { } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        Test-TuneupSuggestBattery | Should -BeFalse
    }

    It 'fails when the battery cannot be queried' {
        Mock -ModuleName Tuneup Get-CimInstance { throw 'Access denied' } -ParameterFilter { $ClassName -eq 'Win32_Battery' }
        { Test-TuneupSuggestBattery } | Should -Throw '*Access denied*'
    }

    It 'sees an MDM enrollment only by its provider' {
        Test-TuneupSuggestMdm -Root "$Key\Enrollments" | Should -BeFalse
        New-Item -Path "$Key\Enrollments\A" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Enrollments\A" -Name ProviderID -Value 'Other' -PropertyType String | Out-Null
        Test-TuneupSuggestMdm -Root "$Key\Enrollments" | Should -BeFalse
        New-Item -Path "$Key\Enrollments\B" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Enrollments\B" -Name ProviderID -Value 'MS DM Server' -PropertyType String | Out-Null
        Test-TuneupSuggestMdm -Root "$Key\Enrollments" | Should -BeTrue
    }

    It 'fails when the MDM enrollments exist but cannot be listed' {
        New-Item -Path "$Key\Enrollments" -Force | Out-Null
        Mock -ModuleName Tuneup Get-ChildItem { throw 'Access denied' } -ParameterFilter { $LiteralPath -like '*Enrollments' }
        { Test-TuneupSuggestMdm -Root "$Key\Enrollments" } | Should -Throw '*Access denied*'
    }

    It 'adds up the installed memory modules, and gives nothing when there are none' {
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ Capacity = [uint64]4GB }, [pscustomobject]@{ Capacity = [uint64]4GB } } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' }
        Get-TuneupInstalledMemoryByte | Should -Be 8GB
        Mock -ModuleName Tuneup Get-CimInstance { } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' }
        Get-TuneupInstalledMemoryByte | Should -BeNullOrEmpty
    }

    It 'fails when the memory modules cannot be queried' {
        Mock -ModuleName Tuneup Get-CimInstance { throw 'Access denied' } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' }
        { Get-TuneupInstalledMemoryByte } | Should -Throw '*Access denied*'
    }

    It 'reads which Windows this is: <Case>' -TestCases @(
        @{ Case = 'a client'; EditionId = 'Professional'; InstallationType = 'Client'; Edition = 'Pro'; IsServer = $false }
        @{ Case = 'a server'; EditionId = 'ServerStandard'; InstallationType = 'Server'; Edition = 'Server'; IsServer = $true }
    ) {
        param($EditionId, $InstallationType, $Edition, $IsServer)
        New-Item -Path "$Key\Windows" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Windows" -Name CurrentBuild -Value '26100' -PropertyType String | Out-Null
        New-ItemProperty -LiteralPath "$Key\Windows" -Name EditionID -Value $EditionId -PropertyType String | Out-Null
        New-ItemProperty -LiteralPath "$Key\Windows" -Name InstallationType -Value $InstallationType -PropertyType String | Out-Null
        $os = Get-TuneupOsSupport -Path "$Key\Windows"
        $os.Build | Should -Be 26100
        $os.Edition | Should -Be $Edition
        $os.IsServer | Should -Be $IsServer
    }
}

Describe 'Invoke-TuneupSuggestCommand' {
    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { throw 'access denied' }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { 'Microsoft.GamingServices' }
        Mock -ModuleName Tuneup Test-TuneupSuggestBattery { $false }
        Mock -ModuleName Tuneup Get-TuneupInstalledMemoryByte { $null }
        Mock -ModuleName Tuneup Get-TuneupOsSupport { [pscustomobject]@{ Build = 26100; Edition = 'Pro'; IsServer = $false } }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { [pscustomobject]@{ PartOfDomain = $true; TotalPhysicalMemory = [double]16GB } }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupSuggestMdm { $false }
        Mock -ModuleName Tuneup Get-TuneupSystemDiskMediaType { 'SSD' }
    }

    It 'writes one suggest document, with the warning of the failed detector inside, and exits with 0' {
        $context = New-TuneupContext -Json -Io (New-TestIo)
        $documents = @(Invoke-TuneupSuggestCommand -Context $context | ForEach-Object { $_ | ConvertFrom-Json })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'suggest'
        $documents[0].toolVersion | Should -Be (Get-TuneupVersion)
        @($documents[0].warnings | Where-Object { $_ -match 'installed programs' }).Count | Should -Be 1
        @($documents[0].suggestions | ForEach-Object { $_.profile }) -join ',' | Should -Be 'base,gaming,work'
        $context.ExitCode | Should -Be 0
    }

    It 'shows the signals, the suggested profiles and the questions for people' {
        $context = New-TuneupContext -Io (New-TestIo)
        $text = (Invoke-TuneupSuggestCommand -Context $context 6>&1 3>$null | Out-String)
        $text | Should -Match '\[x\] Games: Xbox Gaming Services'
        $text | Should -Match '\[ \] Development tools'
        $text | Should -Match 'Suggested profiles: base, gaming, work'
        $text | Should -Match 'tuneup\.ps1 -Profile gaming,work -WhatIf'
        $text | Should -Match 'managed by an organization'
        $context.ExitCode | Should -Be 0
    }

    It 'writes the generic evidence in the language of the run for people, and keeps the tokens in the JSON' {
        Mock -ModuleName Tuneup Test-TuneupSuggestBattery { $true }
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'es'
        try {
            $text = (Invoke-TuneupSuggestCommand -Context (New-TuneupContext -Io (New-TestIo)) 6>&1 3>$null | Out-String)
            $text | Should -Match 'bater.a'
            $text | Should -Match 'dominio'
            $text | Should -Not -Match 'battery'
            $text | Should -Not -Match '\bdomain\b'
            $document = Invoke-TuneupSuggestCommand -Context (New-TuneupContext -Json -Io (New-TestIo)) 3>$null | ConvertFrom-Json
            @(($document.signals | Where-Object { $_.id -eq 'laptop' }).evidence) -join ',' | Should -Be 'battery'
            @(($document.signals | Where-Object { $_.id -eq 'work' }).evidence) -join ',' | Should -Be 'domain'
        } finally {
            Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        }
    }

    It 'has a text for every signal and question in both languages' {
        try {
            foreach ($lang in 'es', 'en') {
                Initialize-TuneupI18n -Root $I18nRoot -Lang $lang
                foreach ($key in @('dev', 'gaming', 'laptop', 'work', 'legacy', 'managed' | ForEach-Object { "suggest.signal.$_" }) + @('suggest.question.privacy', 'suggest.question.lite')) {
                    Get-TuneupText -Key $key | Should -Not -Be $key -Because "$lang $key"
                }
            }
        } finally {
            Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        }
    }
}
