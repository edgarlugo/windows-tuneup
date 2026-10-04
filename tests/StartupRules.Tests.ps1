BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:RulesPath = Join-Path $Repo 'catalog\startup\rules.json'
    $script:Rules = Import-TuneupStartupRuleSet
    function New-TestStartupEntry {
        param([string]$Source = 'run-user', [string]$Key = 'Sample', [string]$Name = $Key, [string]$Path, [string]$Publisher, [bool]$Policy = $false,
            [string]$Signer, [bool]$WindowsSigned = $false, [hashtable]$Target = @{})
        $fields = $Target.Clone()
        # What the list keeps of a verified signature: the signer, and whether Windows vouches for it.
        if ($Signer) { $fields.Signer = $Signer }
        if ($WindowsSigned) { $fields.WindowsSigned = $true }
        $entry = New-TuneupStartupEntry -Source $Source -Key $Key -Name $Name -Path $Path -Policy $Policy -Target $fields
        if ($Publisher) { $entry.publisher = $Publisher }
        $entry
    }
    function Copy-TestRules { $Rules | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
}

Describe 'catalog/startup/rules.json' {
    It 'loads from the copy of the tool and passes its checks' {
        @(Test-TuneupStartupRuleSet -Rules $Rules).Count | Should -Be 0
        @($Rules.protect).Count | Should -BeGreaterThan 3
        @($Rules.recommend).Count | Should -BeGreaterThan 10
        @($Rules.protectSigners | Where-Object { $_.signer -eq 'Microsoft Windows Hardware Compatibility Publisher' }).Count | Should -Be 1
    }

    It 'is UTF-8 without a byte order mark' {
        $bytes = [System.IO.File]::ReadAllBytes($RulesPath)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'protects every service that the blacklist protects' {
        # The list of tests/CatalogQuality.Tests.ps1, block "Blacklist guard".
        foreach ($service in 'WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE', 'wuauserv', 'UsoSvc',
            'WaaSMedicSvc', 'BITS', 'DoSvc', 'InstallService', 'AppXSvc', 'ClipSVC', 'wlidsvc', 'TrustedInstaller', 'CryptSvc', 'SharedAccess',
            'LanmanServer', 'LanmanWorkstation', 'WerSvc', 'DPS', 'RmSvc', 'WpnService', 'webthreatdefsvc', 'webthreatdefusersvc', 'SysMain',
            'WSearch', 'vmcompute', 'vmms', 'hns', 'HvHost', 'LxssManager', 'WslService', 'EventLog', 'Schedule', 'Winmgmt', 'RpcSs', 'sppsvc',
            'VSS', 'swprv', 'AppIDSvc', 'Spooler', 'MDCoreSvc') {
            @($Rules.windowsServices) | Should -Contain $service
        }
    }

    It 'is not loaded as tweaks by the catalog' {
        @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog') | Where-Object { $_.sourceFile -eq 'rules.json' }).Count | Should -Be 0
    }
}

Describe 'Test-TuneupStartupRuleSet' {
    It 'finds <Case>' -TestCases @(
        @{ Case = 'another schema version'; Change = { param($r) $r.schemaVersion = 2 }; Expected = '*schemaVersion must be 1*' }
        @{ Case = 'an empty list of names'; Change = { param($r) $r.hostPrograms = @() }; Expected = '*hostPrograms must be a list of names*' }
        @{ Case = 'an unknown category'; Change = { param($r) $r.protect[0].category = 'nice' }; Expected = "*unknown category 'nice'*" }
        @{ Case = 'a pattern that is not one'; Change = { param($r) $r.recommend[0].pattern = '(' }; Expected = '*is not a valid pattern*' }
        @{ Case = 'a wingetId on a protection'; Change = { param($r) $r.protect[0] | Add-Member -NotePropertyName wingetId -NotePropertyValue 'A.B' }; Expected = '*cannot have a wingetId*' }
        @{ Case = 'a wingetId that is not one'; Change = { param($r) $r.recommend[0].wingetId = 'x; calc' }; Expected = '*invalid wingetId*' }
        @{ Case = 'a list without rules'; Change = { param($r) $r.recommend = @() }; Expected = '*recommend has no rules*' }
        @{ Case = 'a rule without why'; Change = { param($r) $r.protect[0].PSObject.Properties.Remove('why') }; Expected = '*has no why*' }
        @{ Case = 'workApp on a protection'; Change = { param($r) $r.protect[0] | Add-Member -NotePropertyName workApp -NotePropertyValue $true }; Expected = '*cannot have workApp*' }
        @{ Case = 'a workApp that is not true or false'; Change = { param($r) $r.recommend[0] | Add-Member -NotePropertyName workApp -NotePropertyValue 'yes' }; Expected = '*workApp must be true or false*' }
        @{ Case = 'a signer rule without a signer'; Change = { param($r) $r.protectSigners[0].signer = ' ' }; Expected = '*protectSigners has a rule without a signer*' }
        @{ Case = 'a signer rule that is not a protection'; Change = { param($r) $r.protectSigners[0].category = 'updater' }; Expected = "*unknown category 'updater'*" }
        @{ Case = 'a signer rule without sources'; Change = { param($r) $r.protectSigners[0].sources = @() }; Expected = '*must name the sources it applies to*' }
        @{ Case = 'a signer rule with an unknown source'; Change = { param($r) $r.protectSigners[0].sources = @('service', 'nowhere') }; Expected = "*unknown source 'nowhere'*" }
        @{ Case = 'a signer rule without why'; Change = { param($r) $r.protectSigners[0].PSObject.Properties.Remove('why') }; Expected = '*protectSigners rule*has no why*' }
        @{ Case = 'a wingetId on a signer rule'; Change = { param($r) $r.protectSigners[0] | Add-Member -NotePropertyName wingetId -NotePropertyValue 'A.B' }; Expected = '*protectSigners rule*cannot have a wingetId*' }
        @{ Case = 'workApp on a signer rule'; Change = { param($r) $r.protectSigners[0] | Add-Member -NotePropertyName workApp -NotePropertyValue $true }; Expected = '*protectSigners rule*cannot have workApp*' }
        @{ Case = 'an unknown field at the top'; Change = { param($r) $r | Add-Member -NotePropertyName extra -NotePropertyValue 1 }; Expected = "*unknown field 'extra'*" }
        @{ Case = 'an unknown field in a rule'; Change = { param($r) $r.recommend[0] | Add-Member -NotePropertyName colour -NotePropertyValue 'red' }; Expected = "*unknown field 'colour'*" }
        @{ Case = 'a pattern that matches an empty text'; Change = { param($r) $r.protect[0].pattern = 'x|' }; Expected = '*matches an empty text*' }
    ) {
        param($Change, $Expected)
        $copy = Copy-TestRules
        & $Change $copy
        @(Test-TuneupStartupRuleSet -Rules $copy) -join "`n" | Should -BeLike $Expected
    }

    It 'refuses to load rules with problems' {
        $bad = Copy-TestRules
        $bad.schemaVersion = 3
        $path = Join-Path $TestDrive 'bad-rules.json'
        [System.IO.File]::WriteAllText($path, ($bad | ConvertTo-Json -Depth 10))
        { Import-TuneupStartupRuleSet -Path $path } | Should -Throw '*are not valid*schemaVersion must be 1*'
    }
}

Describe 'Get-TuneupStartupProtection' {
    It 'gives <Expected> for <Case>' -TestCases @(
        @{ Case = 'a Run entry of a policy'; Entry = { New-TestStartupEntry -Source 'policy-machine' -Key 'Agent' -Policy $true }; Expected = 'policy' }
        @{ Case = 'a driver'; Entry = { New-TestStartupEntry -Source 'driver' -Key 'vendordrv' }; Expected = 'driver' }
        @{ Case = 'a program signed by Windows'; Entry = { New-TestStartupEntry -Key 'SecurityHealth' -Path 'C:\Windows\System32\SecurityHealthSystray.exe' -Publisher 'Microsoft Windows' -Signer 'Microsoft Windows' -WindowsSigned $true }; Expected = 'windows-component' }
        @{ Case = 'a protected service of the blacklist'; Entry = { New-TestStartupEntry -Source 'service' -Key 'wuauserv' }; Expected = 'windows-component' }
        @{ Case = 'a Store app of Windows'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'Pkg\Task' -Target @{ WindowsPart = $true } }; Expected = 'windows-component' }
        @{ Case = 'an antivirus by name'; Entry = { New-TestStartupEntry -Key 'mbamtray' -Publisher 'Malwarebytes Inc.' }; Expected = 'security' }
        @{ Case = 'Defender by its program'; Entry = { New-TestStartupEntry -Source 'service' -Key 'WdBoot2' -Path 'C:\ProgramData\Microsoft\Windows Defender\Platform\4.18\MsMpEng.exe' }; Expected = 'security' }
        @{ Case = 'a VPN client'; Entry = { New-TestStartupEntry -Key 'GlobalProtect' -Path 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPA.exe' }; Expected = 'vpn' }
        @{ Case = 'the service of the audio driver'; Entry = { New-TestStartupEntry -Source 'task' -Key '\RtkAudUService64_BG' -Name 'RtkAudUService64_BG' -Publisher 'Realtek Semiconductor Corp.' }; Expected = 'device' }
        @{ Case = 'the touchpad helper'; Entry = { New-TestStartupEntry -Key 'SynTPEnh' -Path 'C:\Program Files\Synaptics\SynTP\SynTPEnh.exe' -Publisher 'Synaptics Incorporated' }; Expected = 'device' }
        @{ Case = 'the Fn keys of a laptop'; Entry = { New-TestStartupEntry -Key 'ATKOSD2' -Path 'C:\Program Files (x86)\ASUS\ATK Package\ATK Hotkey\ATKOSD2.exe' -Publisher 'ASUSTeK COMPUTER INC.' }; Expected = 'device' }
        @{ Case = 'the display container of the NVIDIA driver'; Entry = { New-TestStartupEntry -Source 'service' -Key 'NVDisplay.ContainerLocalSystem' -Name 'NVIDIA Display Container LS' -Publisher 'NVIDIA Corporation' }; Expected = 'device' }
        @{ Case = 'the updater of Edge'; Entry = { New-TestStartupEntry -Source 'task' -Key '\MicrosoftEdgeUpdateTaskMachineCore{1}' -Name 'MicrosoftEdgeUpdateTaskMachineCore{1}' }; Expected = 'updates' }
        @{ Case = 'the update service of Brave'; Entry = { New-TestStartupEntry -Source 'service' -Key 'brave' -Name 'Brave Update Service (brave)' }; Expected = 'updates' }
        @{ Case = 'Office Click-to-Run'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ClickToRunSvc' -Name 'Microsoft Office Click-to-Run Service' }; Expected = 'updates' }
        @{ Case = 'the update tasks of Brave'; Entry = { New-TestStartupEntry -Source 'task' -Key '\BraveSoftwareUpdateTaskMachineCore{A1}' -Name 'BraveSoftwareUpdateTaskMachineCore{A1}' }; Expected = 'updates' }
        @{ Case = 'the updater of Opera'; Entry = { New-TestStartupEntry -Source 'task' -Key '\Opera scheduled Autoupdate 1700000000' -Name 'Opera scheduled Autoupdate 1700000000' }; Expected = 'updates' }
        @{ Case = 'the updater of Vivaldi'; Entry = { New-TestStartupEntry -Source 'task' -Key '\VivaldiUpdateCheck' -Name 'VivaldiUpdateCheck' }; Expected = 'updates' }
        @{ Case = 'the Update Health Service of Windows'; Entry = { New-TestStartupEntry -Source 'service' -Key 'uhssvc' -Name 'Microsoft Update Health Service' }; Expected = 'windows-component' }
        @{ Case = 'Symantec'; Entry = { New-TestStartupEntry -Source 'service' -Key 'SepMasterService' -Name 'Symantec Endpoint Protection' }; Expected = 'security' }
        @{ Case = 'a product of Broadcom'; Entry = { New-TestStartupEntry -Source 'service' -Key 'SepWscSvc' -Name 'Endpoint Security Center' -Publisher 'Broadcom Inc.' }; Expected = 'security' }
        @{ Case = 'Trellix'; Entry = { New-TestStartupEntry -Source 'service' -Key 'masvc' -Name 'Trellix Agent Service' }; Expected = 'security' }
        @{ Case = 'McAfee'; Entry = { New-TestStartupEntry -Source 'service' -Key 'mfemms' -Name 'McAfee Service Controller' }; Expected = 'security' }
        @{ Case = 'Sysmon'; Entry = { New-TestStartupEntry -Source 'service' -Key 'Sysmon64' -Name 'Sysmon64' }; Expected = 'security' }
        @{ Case = 'Carbon Black'; Entry = { New-TestStartupEntry -Source 'service' -Key 'CbDefense' -Name 'CbDefense' }; Expected = 'security' }
        @{ Case = 'Cortex XDR'; Entry = { New-TestStartupEntry -Source 'service' -Key 'cyserver' -Name 'Cortex XDR' }; Expected = 'security' }
        @{ Case = 'Cyvera'; Entry = { New-TestStartupEntry -Source 'service' -Key 'CyveraService' -Name 'CyveraService' }; Expected = 'security' }
        @{ Case = 'the Elastic Agent'; Entry = { New-TestStartupEntry -Source 'service' -Key 'Elastic Agent' -Name 'Elastic Agent' }; Expected = 'security' }
        @{ Case = 'Elastic Endpoint'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ElasticEndpoint' -Name 'Elastic Endpoint' }; Expected = 'security' }
        @{ Case = 'Cybereason'; Entry = { New-TestStartupEntry -Source 'service' -Key 'CybereasonActiveProbe' -Name 'Cybereason Active Probe' }; Expected = 'security' }
        @{ Case = 'Tanium'; Entry = { New-TestStartupEntry -Source 'service' -Key 'Tanium Client' -Name 'Tanium Client' }; Expected = 'security' }
        @{ Case = 'Qualys'; Entry = { New-TestStartupEntry -Source 'service' -Key 'QualysAgent' -Name 'Qualys Cloud Agent' }; Expected = 'security' }
        @{ Case = 'Rapid7'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ir_agent' -Name 'Rapid7 Insight Agent' }; Expected = 'security' }
        @{ Case = 'Huntress'; Entry = { New-TestStartupEntry -Source 'service' -Key 'HuntressAgent' -Name 'Huntress Agent' }; Expected = 'security' }
        @{ Case = 'CrowdStrike'; Entry = { New-TestStartupEntry -Source 'service' -Key 'CSFalconService' -Name 'CSFalconService' }; Expected = 'security' }
        @{ Case = 'SentinelOne'; Entry = { New-TestStartupEntry -Source 'service' -Key 'SentinelAgent' -Name 'Sentinel Agent' }; Expected = 'security' }
        @{ Case = 'the Intune Management Extension'; Entry = { New-TestStartupEntry -Source 'service' -Key 'IntuneManagementExtension' -Name 'Microsoft Intune Management Extension' }; Expected = 'security' }
        @{ Case = 'the Configuration Manager client'; Entry = { New-TestStartupEntry -Source 'service' -Key 'CcmExec' -Name 'SMS Agent Host' }; Expected = 'security' }
        @{ Case = 'Defender for Identity'; Entry = { New-TestStartupEntry -Source 'service' -Key 'AATPSensor' -Name 'Azure Advanced Threat Protection Sensor' }; Expected = 'security' }
    ) {
        param($Entry, $Expected)
        Get-TuneupStartupProtection -Entry (& $Entry) -Rules $Rules | Should -Be $Expected
    }

    It 'does not protect the companion apps of a vendor, which it recommends instead: <Name>' -TestCases @(
        @{ Name = 'NVIDIA app'; Entry = { New-TestStartupEntry -Key 'NvBackend' -Name 'NVIDIA app' -Path 'C:\Program Files\NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe' -Publisher 'NVIDIA Corporation' } }
        @{ Name = 'GeForce Experience'; Entry = { New-TestStartupEntry -Source 'service' -Key 'NvContainerLocalSystem' -Name 'NVIDIA GeForce Experience' -Publisher 'NVIDIA Corporation' } }
        @{ Name = 'AMD Software'; Entry = { New-TestStartupEntry -Key 'AMDNoiseSuppression' -Name 'AMD Software' -Path 'C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe' -Publisher 'Advanced Micro Devices, Inc.' } }
        @{ Name = 'Armoury Crate'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ArmouryCrateService' -Name 'ARMOURY CRATE Service' -Publisher 'ASUSTeK COMPUTER INC.' } }
        @{ Name = 'Logitech G HUB'; Entry = { New-TestStartupEntry -Key 'LGHUB' -Path 'C:\Program Files\LGHUB\lghub.exe' -Publisher 'Logitech Inc' } }
        @{ Name = 'Intel Graphics Software'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'AppUp.IntelArcSoftware_8j3eq9eme6ctt\IntelGraphicsSoftwareStartup' -Name 'Intel Graphics Software' -Publisher 'Intel Corporation' } }
    ) {
        param($Entry)
        $companion = & $Entry
        Get-TuneupStartupProtection -Entry $companion -Rules $Rules | Should -BeNullOrEmpty
        (Get-TuneupStartupRecommendation -Entry $companion -Rules $Rules).category | Should -Be 'companion-app'
    }

    It 'protects the services of driver packages by their signer, and only services' {
        $whcp = 'Microsoft Windows Hardware Compatibility Publisher'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source 'service' -Key 'esifsvc' -Name 'Intel(R) Dynamic Tuning service' -Signer $whcp) -Rules $Rules | Should -Be 'device'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source 'service' -Key 'FMAPOService' -Name 'Fortemedia APO Control Service' -Signer $whcp.ToUpperInvariant()) -Rules $Rules | Should -Be 'device'
        foreach ($source in 'run-user', 'run-machine', 'folder-user', 'task', 'store-app') {
            Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source $source -Key 'VendorTray' -Signer $whcp) -Rules $Rules | Should -BeNullOrEmpty -Because $source
        }
        # A rule of a category that comes first in the order of protection still wins.
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source 'service' -Key 'PanGPS' -Signer $whcp) -Rules $Rules | Should -Be 'vpn'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source 'service' -Key 'VendorSvc' -Signer 'Vendor Inc.') -Rules $Rules | Should -BeNullOrEmpty
        # The publisher shown is only a name: the signer decides.
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source 'service' -Key 'VendorSvc' -Publisher $whcp -Signer 'Vendor Inc.') -Rules $Rules | Should -BeNullOrEmpty
    }

    It 'never takes the name of a signer for proof that it is part of Windows' {
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'Fake' -Path 'C:\Tools\fake.exe' -Publisher 'Microsoft Windows' -Signer 'Microsoft Windows') -Rules $Rules | Should -BeNullOrEmpty
        # A Store app is part of Windows only by the kind of its signature (System), never by its publisher.
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Source 'store-app' -Key 'Fake_x\Start' -Publisher 'Microsoft Windows' -Signer 'Microsoft Windows') -Rules $Rules | Should -BeNullOrEmpty
    }

    It 'protects the services that Windows starts as protected processes, and the services of Windows by name: <Case>' -TestCases @(
        @{ Case = 'LaunchProtected 1'; Entry = { New-TestStartupEntry -Source 'service' -Key 'VendorShield' -Target @{ LaunchProtected = 1 } }; Expected = 'security' }
        @{ Case = 'LaunchProtected 3'; Entry = { New-TestStartupEntry -Source 'service' -Key 'VendorShield' -Target @{ LaunchProtected = 3 } }; Expected = 'security' }
        @{ Case = 'LaunchProtected 0'; Entry = { New-TestStartupEntry -Source 'service' -Key 'VendorShield' -Target @{ LaunchProtected = 0 } }; Expected = $null }
        @{ Case = 'a per-user service of Windows'; Entry = { New-TestStartupEntry -Source 'service' -Key 'webthreatdefusersvc_4a5b6' -Signer 'Vendor Inc.' }; Expected = 'windows-component' }
        @{ Case = 'DcomLaunch'; Entry = { New-TestStartupEntry -Source 'service' -Key 'DcomLaunch' -Signer 'Vendor Inc.' }; Expected = 'windows-component' }
        @{ Case = 'RpcEptMapper'; Entry = { New-TestStartupEntry -Source 'service' -Key 'RpcEptMapper' -Signer 'Vendor Inc.' }; Expected = 'windows-component' }
        @{ Case = 'SamSs'; Entry = { New-TestStartupEntry -Source 'service' -Key 'SamSs' -Signer 'Vendor Inc.' }; Expected = 'windows-component' }
        @{ Case = 'ProfSvc'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ProfSvc' -Signer 'Vendor Inc.' }; Expected = 'windows-component' }
        @{ Case = 'a service of Windows that could not be verified'; Entry = { New-TestStartupEntry -Source 'service' -Key 'OddSvc' -Target @{ WindowsPart = $true } }; Expected = 'windows-component' }
    ) {
        param($Entry, $Expected)
        Get-TuneupStartupProtection -Entry (& $Entry) -Rules $Rules | Should -Be $Expected
    }

    It 'protects what lives in the folder of a product of Windows Security' {
        $entry = New-TestStartupEntry -Key 'VendorTray' -Path 'C:\Program Files\Vendor AV\bin\tray.exe'
        Get-TuneupStartupProtection -Entry $entry -Rules $Rules -SecurityFolder @('C:\Program Files\Vendor AV') | Should -Be 'security'
        Get-TuneupStartupProtection -Entry $entry -Rules $Rules -SecurityFolder @('C:\Program Files\Vendor') | Should -BeNullOrEmpty
    }

    It 'does not protect a game launcher, the browser itself or an unknown program, but protects the updater of Brave' {
        $brave = 'C:\Users\me\AppData\Local\BraveSoftware\Brave-Browser\Application\brave.exe'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'Steam' -Path 'C:\Games\Steam\steam.exe' -Publisher 'Valve Corp.') -Rules $Rules | Should -BeNullOrEmpty
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'BraveAutoLaunch_1' -Name 'Brave' -Path $brave) -Rules $Rules | Should -BeNullOrEmpty
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'BraveSoftware Update' -Name 'BraveSoftware Update' -Path $brave) -Rules $Rules | Should -Be 'updates'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'Notes' -Path 'C:\Tools\notes.exe') -Rules $Rules | Should -BeNullOrEmpty
    }
}

Describe 'Get-TuneupStartupFixedReason' {
    It 'says why an entry cannot be turned off' {
        $protected = New-TestStartupEntry -Key 'x'
        $protected.protected = 'vpn'
        Get-TuneupStartupFixedReason -Entry $protected | Should -Be 'vpn'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'runonce-user' -Key 'Cleanup') | Should -Be 'run-once'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'task' -Key '\Vendor\Bad[1]') | Should -Be 'unsupported-name'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'task' -Key '\Vendor\Good') | Should -BeNullOrEmpty
        # A backtick is the escape character of PowerShell wildcards.
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'task' -Key '\Vendor\Odd`Name') | Should -Be 'unsupported-name'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Key 'Half' -Target @{ Incomplete = $true }) | Should -Be 'unreadable'
    }
}

Describe 'Get-TuneupStartupRecommendation' {
    It 'recommends <Name> as <Category>' -TestCases @(
        @{ Name = 'Steam'; Entry = { New-TestStartupEntry -Key 'Steam' -Path 'C:\Games\Steam\steam.exe' }; Category = 'game-launcher'; Winget = 'winget uninstall --id Valve.Steam --exact' }
        @{ Name = 'Epic Games'; Entry = { New-TestStartupEntry -Key 'EpicGamesLauncher' }; Category = 'game-launcher'; Winget = 'winget uninstall --id EpicGames.EpicGamesLauncher --exact' }
        @{ Name = 'Discord'; Entry = { New-TestStartupEntry -Source 'folder-user' -Key 'Discord.lnk' -Name 'Discord' -Path 'C:\Users\me\AppData\Local\Discord\Update.exe' }; Category = 'chat-helper'; Winget = 'winget uninstall --id Discord.Discord --exact' }
        @{ Name = 'Teams'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' -Name 'MSTeams' }; Category = 'chat-helper'; Winget = $null }
        @{ Name = 'Dropbox'; Entry = { New-TestStartupEntry -Key 'Dropbox' }; Category = 'sync-client'; Winget = 'winget uninstall --id Dropbox.Dropbox --exact' }
        @{ Name = 'OneDrive'; Entry = { New-TestStartupEntry -Key 'OneDrive' -Path 'C:\Users\me\AppData\Local\Microsoft\OneDrive\OneDrive.exe' }; Category = 'sync-client'; Winget = $null }
        @{ Name = 'the Adobe updater'; Entry = { New-TestStartupEntry -Source 'task' -Key '\Adobe Acrobat Update Task' -Name 'Adobe Acrobat Update Task' }; Category = 'updater'; Winget = $null }
        @{ Name = 'the new Outlook'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'Microsoft.OutlookForWindows_8wekyb3d8bbwe\OutlookStartup' -Name 'Outlook (new)' }; Category = 'chat-helper'; Winget = $null }
        @{ Name = 'the EA app'; Entry = { New-TestStartupEntry -Key 'EADM' -Path 'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe' -Publisher 'Electronic Arts, Inc.' }; Category = 'game-launcher'; Winget = 'winget uninstall --id ElectronicArts.EADesktop --exact' }
        @{ Name = 'Battle.net'; Entry = { New-TestStartupEntry -Key 'Battle.net' -Path 'C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe' -Publisher 'Blizzard Entertainment, Inc.' }; Category = 'game-launcher'; Winget = 'winget uninstall --id Blizzard.BattleNet --exact' }
        @{ Name = 'the update task of OneDrive'; Entry = { New-TestStartupEntry -Source 'task' -Key '\OneDrive Standalone Update Task-S-1-5-21-1-2-3-1001' -Name 'OneDrive Standalone Update Task-S-1-5-21-1-2-3-1001' }; Category = 'updater'; Winget = $null }
    ) {
        param($Entry, $Category, $Winget)
        $rule = Get-TuneupStartupRecommendation -Entry (& $Entry) -Rules $Rules
        $rule.category | Should -Be $Category
        Get-TuneupStartupUninstallCommand -Rule $rule | Should -Be $Winget
    }

    It 'marks OneDrive, Teams and Outlook as apps of work, and only them' {
        $workApps = @($Rules.recommend | Where-Object { $null -ne $_.PSObject.Properties['workApp'] -and $_.workApp })
        $workApps.Count | Should -Be 4
        foreach ($name in 'OneDrive', 'MSTeams', 'Outlook', 'OneDrive Standalone Update Task-S-1-5-21-1-2-3-1001', 'Microsoft Teams Update') {
            $rule = Get-TuneupStartupRecommendation -Entry (New-TestStartupEntry -Key $name) -Rules $Rules
            $rule.workApp | Should -BeTrue -Because $name
        }
        (Get-TuneupStartupRecommendation -Entry (New-TestStartupEntry -Key 'Dropbox') -Rules $Rules).PSObject.Properties['workApp'] | Should -BeNullOrEmpty
    }

    It 'names the launcher of a game store by its program, never everything its publisher signs: <Name>' -TestCases @(
        @{ Name = 'the service of Steam'; Entry = { New-TestStartupEntry -Source 'service' -Key 'Steam Client Service' -Path 'C:\Program Files (x86)\Common Files\Steam\steamservice.exe' -Publisher 'Valve Corp.' } }
        @{ Name = 'SteamVR'; Entry = { New-TestStartupEntry -Key 'SteamVR' -Path 'C:\Games\Steam\steamapps\common\SteamVR\bin\win64\vrstartup.exe' -Publisher 'Valve Corp.' } }
        @{ Name = 'Epic Online Services'; Entry = { New-TestStartupEntry -Source 'service' -Key 'EpicOnlineServices' -Name 'Epic Online Services' -Publisher 'Epic Games Inc.' } }
        @{ Name = 'the service of the EA app'; Entry = { New-TestStartupEntry -Source 'service' -Key 'EABackgroundService' -Name 'EABackgroundService' -Publisher 'Electronic Arts, Inc.' } }
        @{ Name = 'the agent of Blizzard'; Entry = { New-TestStartupEntry -Key 'BlizzardAgent' -Path 'C:\ProgramData\Battle.net\Agent\Agent.exe' -Publisher 'Blizzard Entertainment, Inc.' } }
    ) {
        param($Entry)
        Get-TuneupStartupRecommendation -Entry (& $Entry) -Rules $Rules | Should -BeNullOrEmpty
    }

    It 'never matches an empty text with a pattern of the tool' {
        foreach ($rule in @($Rules.protect) + @($Rules.recommend)) {
            [regex]::IsMatch('', [string]$rule.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | Should -BeFalse -Because $rule.pattern
        }
    }

    It 'recommends nothing for a program no rule names' {
        Get-TuneupStartupRecommendation -Entry (New-TestStartupEntry -Key 'Notes' -Path 'C:\Tools\notes.exe') -Rules $Rules | Should -BeNullOrEmpty
        Get-TuneupStartupUninstallCommand -Rule $null | Should -BeNullOrEmpty
    }
}
