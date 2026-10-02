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
            Programs = @(); Packages = @(); Battery = $false; Entra = $false; Mdm = $false; Disk = 'SSD'; Fail = @()
            Computer = [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]16GB }
        }
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { if ($script:Fake.Fail -contains 'programs') { throw 'access denied' }; $script:Fake.Programs }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { if ($script:Fake.Fail -contains 'packages') { throw 'no Appx module' }; $script:Fake.Packages }
        Mock -ModuleName Tuneup Test-TuneupHasBattery { $script:Fake.Battery }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { if ($script:Fake.Fail -contains 'computer') { throw 'WMI is broken' }; $script:Fake.Computer }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $script:Fake.Entra }
        Mock -ModuleName Tuneup Test-TuneupMdmEnrollment { $script:Fake.Mdm }
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

Describe 'Invoke-TuneupSuggestCommand' {
    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { throw 'access denied' }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { 'Microsoft.GamingServices' }
        Mock -ModuleName Tuneup Test-TuneupHasBattery { $false }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { [pscustomobject]@{ PartOfDomain = $true; TotalPhysicalMemory = [double]16GB } }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupMdmEnrollment { $false }
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
