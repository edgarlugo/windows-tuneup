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

    It 'reads a startup folder from the folders of the account' {
        Get-TuneupStartupFolderPath -Name 'Startup' | Should -Be ([Environment]::GetFolderPath('Startup'))
        Get-TuneupStartupFolderPath -Name 'CommonStartup' | Should -Be ([Environment]::GetFolderPath('CommonStartup'))
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
  <Properties>
    <DisplayName>Sample</DisplayName>
    <PublisherDisplayName>Sample Publisher</PublisherDisplayName>
  </Properties>
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
        # The name of the publisher that Settings shows, on every task of the package (the manifest is read once).
        @($tasks | ForEach-Object { $_.PublisherDisplayName }) -join ',' | Should -Be 'Sample Publisher,Sample Publisher'
        $bare = Join-Path $TestDrive 'Bare.xml'
        [System.IO.File]::WriteAllText($bare, ([System.IO.File]::ReadAllText($manifest) -replace '(?s)<Properties>.*</Properties>', ''))
        @(Get-TuneupAppxManifestStartupTask -Path $bare)[0].PublisherDisplayName | Should -BeNullOrEmpty
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

    It 'never takes a folder of Windows, a Program Files folder or a drive for the folder of a product' {
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ pathToSignedProductExe = '%ProgramFiles%\report.exe'; pathToSignedReportingExe = '%windir%\system32\SecurityHealthService.exe' }
            [pscustomobject]@{ pathToSignedProductExe = '%ProgramFiles(x86)%\a.exe'; pathToSignedReportingExe = '%ProgramData%\b.exe' }
            [pscustomobject]@{ pathToSignedProductExe = '%windir%\c.exe'; pathToSignedReportingExe = '%SystemDrive%\d.exe' }
            [pscustomobject]@{ pathToSignedProductExe = '%windir%\SysWOW64\e.exe'; pathToSignedReportingExe = '%ProgramFiles%\Vendor AV\f.exe' }
        } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' -and $ClassName -eq 'FirewallProduct' }
        @(Get-TuneupSecurityProductFolder -ClassName 'FirewallProduct') -join ',' | Should -Be "$([Environment]::GetFolderPath('ProgramFiles'))\Vendor AV"
    }

    It 'reads who signed a file and whether Windows or a Microsoft root vouches for it, only from a valid signature' {
        $file = Join-Path $TestDrive 'signed.exe'
        [System.IO.File]::WriteAllText($file, 'x')
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Test-TuneupMicrosoftRootChain { $false }
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; IsOSBinary = $false; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Vendor Inc., O=Vendor' } } }
        $signature = Get-TuneupFileSignature -Path $file
        $signature.Signer | Should -Be 'Vendor Inc.'
        $signature.IsOSBinary | Should -BeFalse
        $signature.MicrosoftRoot | Should -BeFalse
        (Get-TuneupFileSignature -Path $file).Signer | Should -Be 'Vendor Inc.'
        Should -Invoke -ModuleName Tuneup Get-AuthenticodeSignature -Times 1 -Exactly
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; IsOSBinary = $true; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Windows, O=Microsoft Corporation' } } }
        (Get-TuneupFileSignature -Path $file).IsOSBinary | Should -BeTrue
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Vendor Inc.' } } }
        Get-TuneupFileSignature -Path $file | Should -BeNullOrEmpty
        Get-TuneupFileSignature -Path (Join-Path $TestDrive 'missing.exe') | Should -BeNullOrEmpty
        Clear-TuneupFileSignerCache
    }

    It 'reads a signature that cannot be read only once: the next time it is unknown, without failing again' {
        $file = Join-Path $TestDrive 'locked.exe'
        [System.IO.File]::WriteAllText($file, 'x')
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { throw 'The file is in use' }
        { Get-TuneupFileSignature -Path $file } | Should -Throw '*in use*'
        Get-TuneupFileSignature -Path $file | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Tuneup Get-AuthenticodeSignature -Times 1 -Exactly
        Clear-TuneupFileSignerCache
    }

    It 'tells a certificate of a Microsoft root from any other' {
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        try {
            $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Microsoft Windows, O=Not Microsoft', $rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $selfSigned = $request.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-1), [DateTimeOffset]::Now.AddDays(1))
        } finally {
            $rsa.Dispose()
        }
        Test-TuneupMicrosoftRootChain -Certificate $selfSigned | Should -BeFalse
        # A file of Windows itself, which every Windows has.
        $windows = Get-AuthenticodeSignature -LiteralPath (Join-Path ([Environment]::SystemDirectory) 'ntdll.dll')
        Test-TuneupMicrosoftRootChain -Certificate $windows.SignerCertificate | Should -BeTrue
    }

    It 'reads whether a service starts as a protected process' {
        New-Item -Path "$Key\Services\VendorAv" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Services\VendorAv" -Name 'LaunchProtected' -Value 3 -PropertyType DWord | Out-Null
        New-Item -Path "$Key\Services\Plain" -Force | Out-Null
        Get-TuneupServiceLaunchProtected -Name 'VendorAv' -Root "$Key\Services" | Should -Be 3
        Get-TuneupServiceLaunchProtected -Name 'Plain' -Root "$Key\Services" | Should -BeNullOrEmpty
        Get-TuneupServiceLaunchProtected -Name 'Missing' -Root "$Key\Services" | Should -BeNullOrEmpty
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

Describe 'Get-TuneupStartupEntry' {
    BeforeAll {
        $script:Rules = Import-TuneupStartupRuleSet
        $script:UserRun = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $script:MachineRun = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        # The startup folders are never read from the account that runs the tests (a service account may have none).
        $script:UserStartupFolder = 'C:\Users\me\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        $script:CommonStartupFolder = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp'
        function Get-TestEntry { @(Get-TuneupStartupEntry -Rules $Rules 3>$null) }
        function Find-TestEntry($Entries, [string]$Name) { @($Entries | Where-Object { $_.name -eq $Name })[0] }
    }

    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { }
        Mock -ModuleName Tuneup Get-TuneupStartupApprovedValue { @{} }
        Mock -ModuleName Tuneup Get-TuneupStartupFolderPath { $UserStartupFolder } -ParameterFilter { $Name -eq 'Startup' }
        Mock -ModuleName Tuneup Get-TuneupStartupFolderPath { $CommonStartupFolder } -ParameterFilter { $Name -eq 'CommonStartup' }
        Mock -ModuleName Tuneup Get-TuneupStartupFolderItem { }
        Mock -ModuleName Tuneup Get-TuneupShortcutTarget { $null }
        Mock -ModuleName Tuneup Get-TuneupStartupStoreTask { }
        Mock -ModuleName Tuneup Get-TuneupStartupPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { }
        Mock -ModuleName Tuneup Get-TuneupStartupScheduledTask { }
        Mock -ModuleName Tuneup Get-TuneupStartupServiceItem { }
        Mock -ModuleName Tuneup Get-TuneupSecurityProductFolder { }
        Mock -ModuleName Tuneup Get-TuneupFileSignature { $null }
        Mock -ModuleName Tuneup Get-TuneupServiceLaunchProtected { $null }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { }
    }

    It 'lists the Run entries with their state, publisher, use and recommendation' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Steam'; Command = '"C:\Games\Steam\steam.exe" -silent' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue {
            [pscustomobject]@{ Name = 'SecurityHealth'; Command = '%windir%\system32\SecurityHealthSystray.exe' }
            [pscustomobject]@{ Name = 'OldTool'; Command = 'C:\Tools\old.exe' }
        } -ParameterFilter { $Path -eq $MachineRun }
        Mock -ModuleName Tuneup Get-TuneupStartupApprovedValue { @{ OldTool = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8) } } -ParameterFilter { $Path -like 'HKLM:*\StartupApproved\Run' }
        Mock -ModuleName Tuneup Get-TuneupFileSignature { [pscustomobject]@{ Signer = 'Valve Corp.'; IsOSBinary = $false; MicrosoftRoot = $false } } -ParameterFilter { $Path -eq 'C:\Games\Steam\steam.exe' }
        Mock -ModuleName Tuneup Get-TuneupFileSignature { [pscustomobject]@{ Signer = 'Microsoft Windows'; IsOSBinary = $true; MicrosoftRoot = $true } } -ParameterFilter { $Path -like '*\SecurityHealthSystray.exe' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess {
            [pscustomobject]@{ Id = 100; Path = 'C:\Games\Steam\steam.exe'; WorkingSet = 200MB; CpuSeconds = 10.04 }
            [pscustomobject]@{ Id = 101; Path = 'C:\GAMES\Steam\steam.exe'; WorkingSet = 20MB; CpuSeconds = $null }
        }
        $entries = Get-TestEntry
        $steam = Find-TestEntry $entries 'Steam'
        $steam.id | Should -BeExactly 'startup.run-user.steam-eb4bc901'
        $steam.source | Should -Be 'run-user'
        $steam.enabled | Should -BeTrue
        $steam.publisher | Should -Be 'Valve Corp.'
        $steam.running | Should -BeTrue
        $steam.memoryMB | Should -Be 220
        $steam.cpuSeconds | Should -Be 10
        $steam.canDisable | Should -BeTrue
        $steam.needsAdmin | Should -BeFalse
        $steam.recommended | Should -BeTrue
        $steam.recommendedReason | Should -Be 'game-launcher'
        $steam.uninstall | Should -Be 'winget uninstall --id Valve.Steam --exact'
        $steam.target.ApprovedPath | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        $steam.target.ApprovedName | Should -Be 'Steam'
        $security = Find-TestEntry $entries 'SecurityHealth'
        $security.protected | Should -Be 'windows-component'
        $security.canDisable | Should -BeFalse
        $security.recommended | Should -BeFalse
        $security.needsAdmin | Should -BeTrue
        $security.running | Should -BeFalse
        $old = Find-TestEntry $entries 'OldTool'
        $old.enabled | Should -BeFalse
        $old.canDisable | Should -BeFalse
        $old.protected | Should -BeNullOrEmpty
        $old.target.ApprovedValue[0] | Should -Be 3
    }

    It 'shows run-once and policy entries as entries that stay on' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Cleanup'; Command = 'C:\Tools\cleanup.exe' } } -ParameterFilter { $Path -like 'HKCU:*\RunOnce' }
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Agent'; Command = 'C:\Corp\agent.exe' } } -ParameterFilter { $Path -like 'HKLM:*\Policies\Explorer\Run' }
        $entries = Get-TestEntry
        $cleanup = Find-TestEntry $entries 'Cleanup'
        $cleanup.source | Should -Be 'runonce-user'
        $cleanup.canDisable | Should -BeFalse
        Get-TuneupStartupFixedReason -Entry $cleanup | Should -Be 'run-once'
        $agent = Find-TestEntry $entries 'Agent'
        $agent.source | Should -Be 'policy-machine'
        $agent.protected | Should -Be 'policy'
        $agent.canDisable | Should -BeFalse
    }

    It 'lists a shortcut of the startup folder by where it points' {
        $folder = $UserStartupFolder
        Mock -ModuleName Tuneup Get-TuneupStartupFolderItem { [pscustomobject]@{ Name = 'Discord.lnk'; FullName = "$folder\Discord.lnk" } } -ParameterFilter { $Path -eq $folder }
        Mock -ModuleName Tuneup Get-TuneupShortcutTarget { [pscustomobject]@{ Target = 'C:\Users\me\AppData\Local\Discord\Update.exe'; Arguments = '--processStart Discord.exe' } }
        $discord = Find-TestEntry (Get-TestEntry) 'Discord'
        $discord.source | Should -Be 'folder-user'
        $discord.key | Should -Be 'Discord.lnk'
        $discord.path | Should -Be 'C:\Users\me\AppData\Local\Discord\Update.exe'
        $discord.command | Should -Be '"C:\Users\me\AppData\Local\Discord\Update.exe" --processStart Discord.exe'
        $discord.recommendedReason | Should -Be 'chat-helper'
        $discord.uninstall | Should -Be 'winget uninstall --id Discord.Discord --exact'
        $discord.target.ApprovedPath | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        $discord.target.ApprovedName | Should -Be 'Discord.lnk'
    }

    It 'lists the startup tasks of Store apps that their manifest declares' {
        $root = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
        Mock -ModuleName Tuneup Get-TuneupStartupStoreTask {
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; TaskId = 'TeamsTfwStartupTask'; State = 2; KeyPath = "$root\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask" }
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; TaskId = 'NotATask'; State = 2; KeyPath = "$root\MSTeams_8wekyb3d8bbwe\NotATask" }
            [pscustomobject]@{ PackageFamilyName = 'Windows.Part_cw5n1h2txyewy'; TaskId = 'Start'; State = 2; KeyPath = "$root\Windows.Part_cw5n1h2txyewy\Start" }
            [pscustomobject]@{ PackageFamilyName = 'Corp.App_x'; TaskId = 'Start'; State = 4; KeyPath = "$root\Corp.App_x\Start" }
        }
        Mock -ModuleName Tuneup Get-TuneupStartupPackage {
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; Name = 'MSTeams'; Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation'; InstallLocation = 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe'; SignatureKind = 'Store' }
            [pscustomobject]@{ PackageFamilyName = 'Windows.Part_cw5n1h2txyewy'; Name = 'Windows.Part'; Publisher = 'CN=Microsoft Windows'; InstallLocation = 'C:\Windows\SystemApps\Part'; SignatureKind = 'System' }
            [pscustomobject]@{ PackageFamilyName = 'Corp.App_x'; Name = 'Corp.App'; Publisher = 'CN=EB51A5DA-0E72-4863-82E4-EA21C1F8DFE3'; InstallLocation = 'C:\Program Files\WindowsApps\Corp'; SignatureKind = 'Developer' }
        }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { [pscustomobject]@{ TaskId = 'TeamsTfwStartupTask'; DisplayName = 'ms-resource:StartupTaskName'; PublisherDisplayName = 'ms-resource:PublisherDisplayName' } } -ParameterFilter { $Path -like '*MSTeams*' }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { [pscustomobject]@{ TaskId = 'Start'; DisplayName = 'Start'; PublisherDisplayName = '' } } -ParameterFilter { $Path -like '*\SystemApps\*' }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { [pscustomobject]@{ TaskId = 'Start'; DisplayName = 'Start'; PublisherDisplayName = 'Corp Inc.' } } -ParameterFilter { $Path -like '*\WindowsApps\Corp\*' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { [pscustomobject]@{ Id = 300; Path = 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe\ms-teams.exe'; WorkingSet = 150MB; CpuSeconds = 2 } }
        $entries = @(Get-TestEntry | Where-Object { $_.source -eq 'store-app' })
        $entries.Count | Should -Be 3
        $teams = Find-TestEntry $entries 'MSTeams'
        $teams.key | Should -Be 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask'
        # The publisher that Settings shows (PublisherDisplayName of the manifest), or the CN of the package when
        # the manifest gives none or only a resource reference.
        $teams.publisher | Should -Be 'Microsoft Corporation'
        $teams.enabled | Should -BeTrue
        $teams.running | Should -BeTrue
        $teams.memoryMB | Should -Be 150
        $teams.recommendedReason | Should -Be 'chat-helper'
        $teams.uninstall | Should -BeNullOrEmpty
        $teams.target.StoreKeyPath | Should -Be "$root\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"
        $teams.target.StoreState | Should -Be 2
        $part = @($entries | Where-Object { $_.key -like 'Windows.Part*' })[0]
        $part.protected | Should -Be 'windows-component'
        $part.publisher | Should -Be 'Microsoft Windows'
        $corp = @($entries | Where-Object { $_.key -like 'Corp.App*' })[0]
        $corp.protected | Should -Be 'policy'
        $corp.enabled | Should -BeTrue
        $corp.publisher | Should -Be 'Corp Inc.'
        # What decides a protection is the signer of the package, never the name it shows.
        $corp.target.Signer | Should -Be 'EB51A5DA-0E72-4863-82E4-EA21C1F8DFE3'
        $part.target.Signer | Should -Be 'Microsoft Windows'
        # A manifest is read once per package.
        Should -Invoke -ModuleName Tuneup Get-TuneupAppxManifestStartupTask -Times 1 -Exactly -ParameterFilter { $Path -like '*MSTeams*' }
    }

    It 'lists tasks and services of other publishers and leaves out the services of Windows' {
        Mock -ModuleName Tuneup Get-TuneupStartupScheduledTask {
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'GoogleUpdateTaskMachineCore'; State = 'Ready'; Execute = 'C:\Program Files (x86)\Google\Update\GoogleUpdate.exe'; Arguments = '/c' }
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'Adobe Acrobat Update Task'; State = 'Running'; Execute = '"C:\Program Files (x86)\Common Files\Adobe\ARM\1.0\AdobeARM.exe"'; Arguments = $null }
            [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Bad[1]'; State = 'Ready'; Execute = 'C:\Vendor\bad.exe'; Arguments = $null }
        }
        Mock -ModuleName Tuneup Get-TuneupStartupServiceItem {
            [pscustomobject]@{ Kind = 'service'; Name = 'Dnscache'; DisplayName = 'DNS Client'; PathName = 'C:\WINDOWS\system32\svchost.exe -k NetworkService'; State = 'Running'; ProcessId = 5; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'PanGPS'; DisplayName = 'PanGPS'; PathName = '"C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe"'; State = 'Running'; ProcessId = 4242; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'VendorSvc'; DisplayName = 'Vendor Service'; PathName = '"C:\Vendor\svc.exe" -run'; State = 'Running'; ProcessId = 77; DelayedAutoStart = $true }
            [pscustomobject]@{ Kind = 'service'; Name = 'StoppedSvc'; DisplayName = 'Stopped Service'; PathName = 'C:\Vendor\stopped.exe'; State = 'Stopped'; ProcessId = 0; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'driver'; Name = 'vendordrv'; DisplayName = 'Vendor Driver'; PathName = '\SystemRoot\System32\drivers\vendordrv.sys'; State = 'Running'; ProcessId = 0; DelayedAutoStart = $false }
        }
        Mock -ModuleName Tuneup Get-TuneupFileSignature { [pscustomobject]@{ Signer = 'Microsoft Windows'; IsOSBinary = $true; MicrosoftRoot = $true } } -ParameterFilter { $Path -like '*\svchost.exe' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess {
            [pscustomobject]@{ Id = 4242; Path = 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe'; WorkingSet = 50MB; CpuSeconds = 3.25 }
            [pscustomobject]@{ Id = 77; Path = $null; WorkingSet = 10MB; CpuSeconds = 1 }
            [pscustomobject]@{ Id = 9; Path = 'C:\Vendor\stopped.exe'; WorkingSet = 5MB; CpuSeconds = 1 }
        }
        $entries = Get-TestEntry
        @($entries | Where-Object { $_.key -eq 'Dnscache' }).Count | Should -Be 0
        (Find-TestEntry $entries 'GoogleUpdateTaskMachineCore').protected | Should -Be 'updates'
        $adobe = Find-TestEntry $entries 'Adobe Acrobat Update Task'
        $adobe.recommendedReason | Should -Be 'updater'
        $adobe.running | Should -BeTrue
        $adobe.target.TaskPath | Should -Be '\'
        $adobe.target.TaskName | Should -Be 'Adobe Acrobat Update Task'
        $bad = Find-TestEntry $entries 'Bad[1]'
        $bad.canDisable | Should -BeFalse
        $bad.protected | Should -BeNullOrEmpty
        $vpn = Find-TestEntry $entries 'PanGPS'
        $vpn.protected | Should -Be 'vpn'
        $vpn.memoryMB | Should -Be 50
        $vendor = Find-TestEntry $entries 'Vendor Service'
        $vendor.canDisable | Should -BeTrue
        $vendor.running | Should -BeTrue
        $vendor.memoryMB | Should -Be 10
        $vendor.target.ServiceName | Should -Be 'VendorSvc'
        $vendor.target.StartType | Should -Be 'AutomaticDelayed'
        # A stopped service is matched by its process id only, never by the path of another process.
        $stopped = Find-TestEntry $entries 'Stopped Service'
        $stopped.running | Should -BeFalse
        $stopped.memoryMB | Should -BeNullOrEmpty
        (Find-TestEntry $entries 'Vendor Driver').protected | Should -Be 'driver'
    }

    It 'fails closed on the services that run from the folder of Windows' {
        $windows = [Environment]::GetFolderPath('Windows')
        Mock -ModuleName Tuneup Get-TuneupStartupServiceItem {
            [pscustomobject]@{ Kind = 'service'; Name = 'DcomLaunch'; DisplayName = 'DCOM Server Process Launcher'; PathName = "$windows\system32\svchost.exe -k DcomLaunch -p"; State = 'Running'; ProcessId = 900; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'RpcEptMapper'; DisplayName = 'RPC Endpoint Mapper'; PathName = "$windows\system32\svchost.exe -k RPCSS -p"; State = 'Running'; ProcessId = 901; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'ProfSvc'; DisplayName = 'User Profile Service'; PathName = "$windows\system32\svchost.exe -k netsvcs -p"; State = 'Running'; ProcessId = 902; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'SamSs'; DisplayName = 'Security Accounts Manager'; PathName = "$windows\system32\lsass.exe"; State = 'Running'; ProcessId = 903; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'OddSvc'; DisplayName = 'Odd Service'; PathName = "$($windows.ToUpperInvariant())\System32\..\System32\oddsvc.exe"; State = 'Running'; ProcessId = 904; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'ClaimSvc'; DisplayName = 'Claims Windows'; PathName = "$windows\claim.exe"; State = 'Running'; ProcessId = 905; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'VendorInWin'; DisplayName = 'Vendor In Windows'; PathName = "$windows\System32\vendorsvc.exe"; State = 'Running'; ProcessId = 906; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'ScriptSvc'; DisplayName = 'Script Service'; PathName = 'cmd.exe /c C:\Vendor\run.bat'; State = 'Running'; ProcessId = 907; DelayedAutoStart = $false }
        }
        # Nothing can be verified, but the vendor service is signed by its vendor and the claim only names Windows.
        Mock -ModuleName Tuneup Get-TuneupFileSignature { [pscustomobject]@{ Signer = 'Vendor Inc.'; IsOSBinary = $false; MicrosoftRoot = $false } } -ParameterFilter { $Path -like '*\vendorsvc.exe' }
        Mock -ModuleName Tuneup Get-TuneupFileSignature { [pscustomobject]@{ Signer = 'Microsoft Windows'; IsOSBinary = $false; MicrosoftRoot = $false } } -ParameterFilter { $Path -like '*\claim.exe' }
        $entries = Get-TestEntry
        foreach ($name in 'DcomLaunch', 'RpcEptMapper', 'ProfSvc', 'SamSs') {
            @($entries | Where-Object { $_.key -eq $name -and $_.canDisable }).Count | Should -Be 0 -Because $name
        }
        # The service hosts of Windows are not listed at all.
        @($entries | Where-Object { $_.path -like '*\svchost.exe' -or $_.path -like '*\lsass.exe' }).Count | Should -Be 0
        foreach ($name in 'Odd Service', 'Claims Windows', 'Script Service') {
            $entry = Find-TestEntry $entries $name
            $entry.protected | Should -Be 'windows-component' -Because $name
            $entry.canDisable | Should -BeFalse -Because $name
        }
        (Find-TestEntry $entries 'Script Service').publisher | Should -BeNullOrEmpty
        $vendor = Find-TestEntry $entries 'Vendor In Windows'
        $vendor.publisher | Should -Be 'Vendor Inc.'
        $vendor.protected | Should -BeNullOrEmpty
        $vendor.canDisable | Should -BeTrue
    }

    It 'protects a service that Windows starts as a protected process' {
        Mock -ModuleName Tuneup Get-TuneupStartupServiceItem {
            [pscustomobject]@{ Kind = 'service'; Name = 'VendorShield'; DisplayName = 'Vendor Shield'; PathName = '"C:\Program Files\Vendor Shield\shield.exe"'; State = 'Running'; ProcessId = 50; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'VendorPlain'; DisplayName = 'Vendor Plain'; PathName = '"C:\Program Files\Vendor\plain.exe"'; State = 'Running'; ProcessId = 51; DelayedAutoStart = $false }
        }
        Mock -ModuleName Tuneup Get-TuneupFileSignature { [pscustomobject]@{ Signer = 'Vendor Inc.'; IsOSBinary = $false; MicrosoftRoot = $false } }
        Mock -ModuleName Tuneup Get-TuneupServiceLaunchProtected { 3 } -ParameterFilter { $Name -eq 'VendorShield' }
        Mock -ModuleName Tuneup Get-TuneupServiceLaunchProtected { 0 } -ParameterFilter { $Name -eq 'VendorPlain' }
        $entries = Get-TestEntry
        (Find-TestEntry $entries 'Vendor Shield').protected | Should -Be 'security'
        (Find-TestEntry $entries 'Vendor Plain').protected | Should -BeNullOrEmpty
    }

    It 'protects what lives in the folder of a product of Windows Security' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'VendorTray'; Command = '"C:\Program Files\Vendor AV\tray.exe"' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupSecurityProductFolder { 'C:\Program Files\Vendor AV' } -ParameterFilter { $ClassName -eq 'AntiVirusProduct' }
        (Find-TestEntry (Get-TestEntry) 'VendorTray').protected | Should -Be 'security'
    }

    It 'gives a hosted program no publisher and no use of its own' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Helper'; Command = 'rundll32.exe "C:\X\x.dll",Start' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { [pscustomobject]@{ Id = 5; Path = (Join-Path ([Environment]::SystemDirectory) 'rundll32.exe'); WorkingSet = 5MB; CpuSeconds = 1 } }
        $helper = Find-TestEntry (Get-TestEntry) 'Helper'
        $helper.publisher | Should -BeNullOrEmpty
        $helper.protected | Should -BeNullOrEmpty
        $helper.running | Should -BeNullOrEmpty
        $helper.canDisable | Should -BeTrue
        Should -Invoke -ModuleName Tuneup Get-TuneupFileSignature -Times 0 -ParameterFilter { $Path -like '*rundll32.exe' }
    }

    It 'does not recommend the apps of work on a work PC, but leaves them to choose' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue {
            [pscustomobject]@{ Name = 'OneDrive'; Command = '"C:\Users\me\AppData\Local\Microsoft\OneDrive\OneDrive.exe" /background' }
            [pscustomobject]@{ Name = 'Steam'; Command = 'C:\Games\Steam\steam.exe' }
        } -ParameterFilter { $Path -eq $UserRun }
        $atWork = @(Get-TuneupStartupEntry -Rules $Rules -WorkPc $true 3>$null)
        $oneDrive = Find-TestEntry $atWork 'OneDrive'
        $oneDrive.canDisable | Should -BeTrue
        $oneDrive.recommended | Should -BeFalse
        $oneDrive.recommendedReason | Should -BeNullOrEmpty
        $oneDrive.notRecommendedReason | Should -Be 'work-app'
        (Find-TestEntry $atWork 'Steam').recommended | Should -BeTrue
        $personal = Find-TestEntry (Get-TestEntry) 'OneDrive'
        $personal.recommendedReason | Should -Be 'sync-client'
        $personal.notRecommendedReason | Should -BeNullOrEmpty
    }

    It 'keeps listing when a source fails, with a warning, and leaves the use unknown without the processes' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Steam'; Command = 'C:\Games\Steam\steam.exe' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupStartupScheduledTask { throw 'Access denied' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { throw 'Access denied' }
        $output = @(Get-TuneupStartupEntry -Rules $Rules 3>&1)
        $warned = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
        $steam = Find-TestEntry @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }) 'Steam'
        $steam.running | Should -BeNullOrEmpty
        $steam.memoryMB | Should -BeNullOrEmpty
        @($warned | Where-Object { $_ -like 'Could not check the scheduled tasks*Access denied*' }).Count | Should -Be 1
        @($warned | Where-Object { $_ -like 'Could not check the running programs*' }).Count | Should -Be 1
    }
}

Describe 'Test-TuneupStartupWorkPc' {
    It 'is a work PC when managed or joined to Entra ID, and not otherwise' {
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment -IsManaged $true) | Should -BeTrue
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment) | Should -BeFalse
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $true }
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment) | Should -BeTrue
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { throw 'Access denied' }
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment) 3>$null | Should -BeFalse
    }
}
