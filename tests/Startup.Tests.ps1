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
Describe 'Startup texts' {
    It 'has a text in es and en for every source, protection, reason, recommendation and kind of change' {
        $module = Get-Module Tuneup
        $keys = @(& $module { $script:StartupSources.Keys } | ForEach-Object { "startup.source.$_" }) +
            @(& $module { $script:StartupProtections } | ForEach-Object { "startup.protected.$_" }) +
            @('run-once', 'unsupported-name' | ForEach-Object { "startup.fixed.$_" }) +
            @(& $module { $script:StartupRuleCategories.recommend } | ForEach-Object { "startup.recommend.$_" }) +
            @('registry', 'store', 'task', 'service' | ForEach-Object { "startup.why.$_" }) +
            @('startup.notRecommended.work-app', 'transcript.request.startup', 'reapply.startupEntry')
        $keys.Count | Should -BeGreaterThan 30
        foreach ($lang in 'es', 'en') {
            $json = Get-Content -LiteralPath (Join-Path $I18nRoot "$lang.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in $keys) { [string]::IsNullOrWhiteSpace([string]$json.$key) | Should -BeFalse -Because "$lang $key" }
        }
    }
}

Describe 'Startup detectors' {
    BeforeEach { Remove-TestKey }
    AfterAll { Remove-TestKey }

    It 'reads the values of a Run key as they are written, and nothing for a key that is not there' {
        New-Item -Path "$Key\Run" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Run" -Name 'Steam' -Value '"%ProgramFiles%\Steam\steam.exe" -silent' -PropertyType ExpandString | Out-Null
        $values = @(Get-TuneupStartupRunValue -Path "$Key\Run")
        $values.Count | Should -Be 1
        $values[0].Name | Should -Be 'Steam'
        $values[0].Command | Should -Be '"%ProgramFiles%\Steam\steam.exe" -silent'
        @(Get-TuneupStartupRunValue -Path "$Key\Missing").Count | Should -Be 0
    }

    It 'reads the binary StartupApproved values by name, in any case' {
        New-Item -Path "$Key\Approved" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Approved" -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)) -PropertyType Binary | Out-Null
        New-ItemProperty -LiteralPath "$Key\Approved" -Name 'Text' -Value 'x' -PropertyType String | Out-Null
        $values = Get-TuneupStartupApprovedValue -Path "$Key\Approved"
        @($values.Keys).Count | Should -Be 1
        $values['STEAM'][0] | Should -Be 3
        $values['STEAM'].Length | Should -Be 12
        (Get-TuneupStartupApprovedValue -Path "$Key\Missing").Count | Should -Be 0
    }

    It 'lists the files of a startup folder, without desktop.ini or folders' {
        $folder = Join-Path $TestDrive 'Startup'
        New-Item -ItemType Directory -Path (Join-Path $folder 'Sub') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $folder 'Tool.lnk'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $folder 'desktop.ini'), 'x')
        $items = @(Get-TuneupStartupFolderItem -Path $folder)
        @($items | ForEach-Object { $_.Name }) -join ',' | Should -Be 'Tool.lnk'
        $items[0].FullName | Should -Be (Join-Path $folder 'Tool.lnk')
        @(Get-TuneupStartupFolderItem -Path (Join-Path $TestDrive 'Nowhere')).Count | Should -Be 0
        @(Get-TuneupStartupFolderItem -Path '').Count | Should -Be 0
    }

    It 'reads where a shortcut points without changing it' {
        $link = Join-Path $TestDrive 'Notepad.lnk'
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($link)
            $shortcut.TargetPath = Join-Path ([Environment]::SystemDirectory) 'notepad.exe'
            $shortcut.Arguments = '/x'
            $shortcut.Save()
        } finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
        $before = (Get-Item -LiteralPath $link).LastWriteTimeUtc
        $target = Get-TuneupShortcutTarget -Path $link
        $target.Target | Should -Be (Join-Path ([Environment]::SystemDirectory) 'notepad.exe')
        $target.Arguments | Should -Be '/x'
        (Get-Item -LiteralPath $link).LastWriteTimeUtc | Should -Be $before
    }

    It 'reads the State of the startup tasks of Store apps, and only keys that have one' {
        $root = "$Key\SystemAppData"
        New-Item -Path "$root\Vendor.App_abc\StartAtLogon" -Force | Out-Null
        New-ItemProperty -LiteralPath "$root\Vendor.App_abc\StartAtLogon" -Name 'State' -Value 2 -PropertyType DWord | Out-Null
        New-Item -Path "$root\Vendor.App_abc\Schemas" -Force | Out-Null
        $tasks = @(Get-TuneupStartupStoreTask -Root $root)
        $tasks.Count | Should -Be 1
        $tasks[0].PackageFamilyName | Should -Be 'Vendor.App_abc'
        $tasks[0].TaskId | Should -Be 'StartAtLogon'
        $tasks[0].State | Should -Be 2
        $tasks[0].KeyPath | Should -Be "$root\Vendor.App_abc\StartAtLogon"
        @(Get-TuneupStartupStoreTask -Root "$Key\Missing").Count | Should -Be 0
    }

    It 'reads the startup tasks that a package manifest declares' {
        $manifest = Join-Path $TestDrive 'AppxManifest.xml'
        [System.IO.File]::WriteAllText($manifest, @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap5="http://schemas.microsoft.com/appx/manifest/uap/windows10/5"
         xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10">
  <Applications>
    <Application Id="App">
      <Extensions>
        <uap5:Extension Category="windows.startupTask">
          <uap5:StartupTask TaskId="TaskOne" Enabled="true" DisplayName="Sample One" />
        </uap5:Extension>
        <desktop:Extension Category="windows.startupTask" Executable="x.exe" EntryPoint="Windows.FullTrustApplication">
          <desktop:StartupTask TaskId="TaskTwo" Enabled="false" DisplayName="ms-resource:Name" />
        </desktop:Extension>
        <desktop:Extension Category="windows.fullTrustProcess" Executable="y.exe" />
      </Extensions>
    </Application>
  </Applications>
</Package>
'@)
        $tasks = @(Get-TuneupAppxManifestStartupTask -Path $manifest)
        @($tasks | ForEach-Object { $_.TaskId }) -join ',' | Should -Be 'TaskOne,TaskTwo'
        $tasks[0].DisplayName | Should -Be 'Sample One'
        @(Get-TuneupAppxManifestStartupTask -Path (Join-Path $TestDrive 'none.xml')).Count | Should -Be 0
    }

    It 'reads the Store packages of the current user' {
        Mock -ModuleName Tuneup Get-AppxPackage {
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; Name = 'MSTeams'; Publisher = 'CN=Microsoft Corporation'; InstallLocation = 'C:\Apps\Teams'; SignatureKind = 'Store' }
        }
        $packages = @(Get-TuneupStartupPackage)
        $packages[0].PackageFamilyName | Should -Be 'MSTeams_8wekyb3d8bbwe'
        $packages[0].SignatureKind | Should -Be 'Store'
    }

    It 'keeps only the tasks outside \Microsoft\ that start at sign-in or at boot' {
        Mock -ModuleName Tuneup Get-ScheduledTask {
            $logon = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' } }
            $boot = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskBootTrigger' } }
            $daily = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskDailyTrigger' } }
            $exec = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskExecAction' }; Execute = '"C:\Vendor\up.exe"'; Arguments = '/silent' }
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'VendorUpdate'; State = 'Ready'; Triggers = @($daily, $logon); Actions = @($exec) }
            [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Boot'; State = 'Disabled'; Triggers = @($boot); Actions = @() }
            [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Daily'; State = 'Ready'; Triggers = @($daily); Actions = @($exec) }
            [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Defrag\'; TaskName = 'ScheduledDefrag'; State = 'Ready'; Triggers = @($logon); Actions = @($exec) }
        }
        $tasks = @(Get-TuneupStartupScheduledTask)
        @($tasks | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }) -join ',' | Should -Be '\VendorUpdate,\Vendor\Boot'
        $tasks[0].Execute | Should -Be '"C:\Vendor\up.exe"'
        $tasks[0].Arguments | Should -Be '/silent'
        $tasks[1].State | Should -Be 'Disabled'
        $tasks[1].Execute | Should -BeNullOrEmpty
    }

    It 'reads the services and the drivers that start on their own' {
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ Name = 'VendorSvc'; DisplayName = 'Vendor Service'; PathName = '"C:\Vendor\svc.exe"'; State = 'Running'; ProcessId = 77; DelayedAutoStart = $true }
        } -ParameterFilter { $ClassName -eq 'Win32_Service' -and $Filter -eq "StartMode = 'Auto'" }
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ Name = 'vendordrv'; DisplayName = 'Vendor Driver'; PathName = 'C:\WINDOWS\system32\drivers\vendordrv.sys'; State = 'Running' }
        } -ParameterFilter { $ClassName -eq 'Win32_SystemDriver' -and $Filter -eq "StartMode = 'Auto'" }
        $items = @(Get-TuneupStartupServiceItem)
        @($items | ForEach-Object { "$($_.Kind):$($_.Name)" }) -join ',' | Should -Be 'service:VendorSvc,driver:vendordrv'
        $items[0].DelayedAutoStart | Should -BeTrue
        $items[0].ProcessId | Should -Be 77
        $items[1].ProcessId | Should -Be 0
    }

    It 'reads the folders of the products that Windows Security lists, from their paths only' {
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ pathToSignedProductExe = 'windowsdefender://'; pathToSignedReportingExe = '%ProgramFiles%\Vendor AV\report.exe' }
        } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' -and $ClassName -eq 'AntiVirusProduct' }
        @(Get-TuneupSecurityProductFolder -ClassName 'AntiVirusProduct') -join ',' | Should -Be "$([Environment]::GetFolderPath('ProgramFiles'))\Vendor AV"
    }

    It 'reads who signed a file, only from a valid signature, and remembers it' {
        $file = Join-Path $TestDrive 'signed.exe'
        [System.IO.File]::WriteAllText($file, 'x')
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Vendor Inc., O=Vendor' } } }
        Get-TuneupFileSigner -Path $file | Should -Be 'Vendor Inc.'
        Get-TuneupFileSigner -Path $file | Should -Be 'Vendor Inc.'
        Should -Invoke -ModuleName Tuneup Get-AuthenticodeSignature -Times 1 -Exactly
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Vendor Inc.' } } }
        Get-TuneupFileSigner -Path $file | Should -BeNullOrEmpty
        Get-TuneupFileSigner -Path (Join-Path $TestDrive 'missing.exe') | Should -BeNullOrEmpty
        Clear-TuneupFileSignerCache
    }

    It 'reads the running processes, leaving unknown what Windows does not tell' {
        Mock -ModuleName Tuneup Get-Process {
            [pscustomobject]@{ Id = 10; Path = 'C:\Games\Steam\steam.exe'; WorkingSet64 = 200MB; TotalProcessorTime = [timespan]::FromSeconds(10.04) }
            [pscustomobject]@{ Id = 4; Path = $null; WorkingSet64 = 1MB; TotalProcessorTime = $null }
        }
        $processes = @(Get-TuneupStartupProcess)
        $processes[0].Path | Should -Be 'C:\Games\Steam\steam.exe'
        $processes[0].WorkingSet | Should -Be 200MB
        $processes[0].CpuSeconds | Should -Be 10.04
        $processes[1].Path | Should -BeNullOrEmpty
        $processes[1].CpuSeconds | Should -BeNullOrEmpty
    }
}
