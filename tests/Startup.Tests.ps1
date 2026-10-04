BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:I18nRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
    Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
}

Describe 'Startup ids' {
    It 'gives the same id for the same source and key, whatever the case' {
        Get-TuneupStartupId -Source 'run-user' -Key 'Steam' | Should -BeExactly 'startup.run-user.steam-eb4bc901'
        Get-TuneupStartupId -Source 'run-user' -Key 'STEAM' | Should -BeExactly 'startup.run-user.steam-eb4bc901'
    }

    It 'gives another id for the same key in another source' {
        Get-TuneupStartupId -Source 'run-machine' -Key 'Steam' | Should -BeExactly 'startup.run-machine.steam-bb5ab8ea'
    }

    It 'keeps only safe characters, cuts long keys and never leaves the slug empty' {
        Get-TuneupStartupId -Source 'task' -Key '\Vendor\Updater Task (Logon)' | Should -BeExactly 'startup.task.vendor-updater-task-logon-a94b661c'
        Get-TuneupStartupId -Source 'service' -Key 'AVeryLongServiceNameThatGoesOnAndOnForeverAndEver' |
            Should -BeExactly 'startup.service.averylongservicenamethatgoesonan-57d0735c'
        Get-TuneupStartupId -Source 'store-app' -Key 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' |
            Should -BeExactly 'startup.store-app.msteams-8wekyb3d8bbwe-teamstfwst-119df735'
        # Letters outside ASCII leave only what is left (here the extension of the shortcut).
        Get-TuneupStartupId -Source 'folder-user' -Key ([string][char]0x5FAE + [char]0x4FE1 + '.lnk') | Should -BeExactly 'startup.folder-user.lnk-70476f0a'
        Get-TuneupStartupId -Source 'folder-user' -Key ([string][char]0x5FAE + [char]0x4FE1) | Should -Match '^startup\.folder-user\.entry-[0-9a-f]{8}$'
    }

    It 'matches the id rule of the catalog and its own pattern' {
        $id = Get-TuneupStartupId -Source 'run32-machine' -Key 'Vendor Tray'
        $id | Should -MatchExactly '^[a-z]+(\.[a-z0-9-]+)+$'
        Test-TuneupStartupId -Id $id | Should -BeTrue
        Test-TuneupStartupId -Id 'privacy.advertising-id' | Should -BeFalse
        Test-TuneupStartupId -Id 'STARTUP.RUN-USER.X-1' | Should -BeFalse
        Test-TuneupStartupId -Id $null | Should -BeFalse
    }

    It 'tells the scope of an id from its source' {
        Get-TuneupStartupIdScope -Id 'startup.run-user.steam-eb4bc901' | Should -Be 'user'
        Get-TuneupStartupIdScope -Id 'startup.store-app.x-00000000' | Should -Be 'user'
        Get-TuneupStartupIdScope -Id 'startup.run-machine.steam-bb5ab8ea' | Should -Be 'machine'
        Get-TuneupStartupIdScope -Id 'startup.service.x-00000000' | Should -Be 'machine'
        Get-TuneupStartupIdScope -Id 'startup.nowhere.x-00000000' | Should -BeNullOrEmpty
        Get-TuneupStartupIdScope -Id 'privacy.advertising-id' | Should -BeNullOrEmpty
    }
}

Describe 'Startup path helpers' {
    It 'expands the variables of Windows and of the account from their folders, and leaves any other one' {
        $programFiles = [Environment]::GetFolderPath('ProgramFiles')
        $windows = [Environment]::GetFolderPath('Windows')
        Expand-TuneupStartupPath -Text '%ProgramFiles%\Vendor\x.exe' | Should -Be "$programFiles\Vendor\x.exe"
        Expand-TuneupStartupPath -Text '%WINDIR%\system32\a.exe' | Should -Be "$windows\system32\a.exe"
        Expand-TuneupStartupPath -Text '%NOT_A_FOLDER%\a.exe' | Should -Be '%NOT_A_FOLDER%\a.exe'
        Expand-TuneupStartupPath -Text '' | Should -Be ''
    }

    It 'finds the program of a command line: <Case>' -TestCases @(
        @{ Case = 'quoted, with arguments'; Command = '"C:\Program Files\Vendor\app.exe" --minimized'; Expected = 'C:\Program Files\Vendor\app.exe' }
        @{ Case = 'quoted twice, as some tasks keep it'; Command = '""C:\Vendor\up.exe""'; Expected = 'C:\Vendor\up.exe' }
        @{ Case = 'not quoted, with spaces in the path'; Command = 'C:\Program Files\Vendor\app.exe -silent'; Expected = 'C:\Program Files\Vendor\app.exe' }
        @{ Case = 'not quoted, without an extension it knows'; Command = 'C:\Tools\run.ps1 now'; Expected = 'C:\Tools\run.ps1' }
        @{ Case = 'a kernel path of a driver'; Command = '\??\C:\Vendor\drv.sys'; Expected = 'C:\Vendor\drv.sys' }
    ) {
        param($Command, $Expected)
        Get-TuneupCommandProgram -Command $Command | Should -Be $Expected
    }

    It 'places bare names and the paths of drivers in the folder of Windows' {
        $windows = [Environment]::GetFolderPath('Windows')
        Get-TuneupCommandProgram -Command 'rundll32.exe "C:\X\x.dll",Start' | Should -Be (Join-Path ([Environment]::SystemDirectory) 'rundll32.exe')
        Get-TuneupCommandProgram -Command '\SystemRoot\System32\drivers\vendordrv.sys' | Should -Be (Join-Path $windows 'System32\drivers\vendordrv.sys')
        Get-TuneupCommandProgram -Command 'System32\drivers\other.sys' | Should -Be (Join-Path $windows 'System32\drivers\other.sys')
        Get-TuneupCommandProgram -Command '%ProgramFiles%\Vendor\app.exe /x' | Should -Be "$([Environment]::GetFolderPath('ProgramFiles'))\Vendor\app.exe"
    }

    It 'gives nothing for an empty command or one without a full path' {
        Get-TuneupCommandProgram -Command '' | Should -BeNullOrEmpty
        Get-TuneupCommandProgram -Command $null | Should -BeNullOrEmpty
        Get-TuneupCommandProgram -Command 'relative\app.exe' | Should -BeNullOrEmpty
    }

    It 'reads the common name of a certificate subject' {
        Get-TuneupCommonName -DistinguishedName 'CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' | Should -BeExactly 'Microsoft Windows'
        Get-TuneupCommonName -DistinguishedName 'CN="Valve Corp., Inc.", O=Valve' | Should -BeExactly 'Valve Corp., Inc.'
        Get-TuneupCommonName -DistinguishedName 'O=Nobody' | Should -BeNullOrEmpty
        Get-TuneupCommonName -DistinguishedName $null | Should -BeNullOrEmpty
    }

    It 'reads a StartupApproved value as Task Manager does: <Case>' -TestCases @(
        @{ Case = 'no value is on'; Value = $null; Expected = $true }
        @{ Case = 'an empty value is on'; Value = [byte[]]@(); Expected = $true }
        @{ Case = '02 is on'; Value = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); Expected = $true }
        @{ Case = '06 is on (SecurityHealth)'; Value = [byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); Expected = $true }
        @{ Case = '03 with a date is off'; Value = [byte[]](3, 0, 0, 0, 71, 94, 174, 173, 217, 80, 221, 1); Expected = $false }
        @{ Case = '07 is off'; Value = [byte[]](7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); Expected = $false }
    ) {
        param($Value, $Expected)
        Test-TuneupStartupApprovedEnabled -Value $Value | Should -Be $Expected
    }
}

Describe 'New-TuneupStartupEntry' {
    It 'builds an entry with its id, scope and what turning it off needs' {
        $entry = New-TuneupStartupEntry -Source 'run-machine' -Key 'Vendor' -Name 'Vendor' -Command '"C:\V\v.exe"' -Path 'C:\V\v.exe' -Target @{ ApprovedName = 'Vendor' }
        $entry.id | Should -BeExactly (Get-TuneupStartupId -Source 'run-machine' -Key 'Vendor')
        $entry.scope | Should -Be 'machine'
        $entry.needsAdmin | Should -BeTrue
        $entry.enabled | Should -BeTrue
        $entry.canDisable | Should -BeFalse
        $entry.running | Should -BeNullOrEmpty
        $entry.target.ApprovedName | Should -Be 'Vendor'
    }

    It 'keeps empty texts as null and refuses an unknown source' {
        $entry = New-TuneupStartupEntry -Source 'store-app' -Key 'P\T' -Name 'App' -Command '' -Path ''
        $entry.command | Should -BeNullOrEmpty
        $entry.path | Should -BeNullOrEmpty
        $entry.needsAdmin | Should -BeFalse
        { New-TuneupStartupEntry -Source 'nowhere' -Key 'x' -Name 'x' } | Should -Throw "*Unknown startup source 'nowhere'*"
    }
}
