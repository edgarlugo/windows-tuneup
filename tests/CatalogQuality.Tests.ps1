BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:CatalogDir = Join-Path $RepoRoot 'catalog'
    $script:ProfilesDir = Join-Path $RepoRoot 'profiles'
    $script:Catalog = @(Import-TuneupCatalog -Path $CatalogDir)
    $script:Profiles = @(Import-TuneupProfileSet -Path $ProfilesDir)
    $script:ById = @{}
    foreach ($tweak in $Catalog) { $script:ById[[string]$tweak.id] = $tweak }
    function Get-ProfileById([string]$Id) { $Profiles | Where-Object { $_.id -eq $Id } }
}

Describe 'Shipped catalog quality' {
    It 'validates without problems' {
        $Catalog.Count | Should -BeGreaterThan 0
        (Test-TuneupCatalog -Catalog $Catalog) -join "`n" | Should -BeNullOrEmpty
        (Test-TuneupProfileSet -Profiles $Profiles -Catalog $Catalog) -join "`n" | Should -BeNullOrEmpty
    }

    It 'keeps every catalog and profile file in UTF-8 without a byte order mark' {
        $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        foreach ($file in @(Get-ChildItem -LiteralPath $CatalogDir -Filter '*.json' -File) + @(Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' -File)) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse -Because "$($file.Name) has no BOM"
            { $strict.GetString($bytes) } | Should -Not -Throw -Because "$($file.Name) is UTF-8"
        }
    }

    It 'uses only the known category files' {
        $known = @('privacy', 'ads', 'ui', 'ai', 'edge', 'services', 'tasks', 'performance', 'power', 'gaming', 'dev', 'apps')
        foreach ($file in Get-ChildItem -LiteralPath $CatalogDir -Filter '*.json' -File) {
            $known | Should -Contain $file.BaseName
        }
    }

    It 'gives every tweak at least one source and a title and reason in each language' {
        foreach ($tweak in $Catalog) {
            @($tweak.sources | Where-Object { $_ }).Count | Should -BeGreaterThan 0 -Because $tweak.id
            foreach ($lang in 'es', 'en') {
                [string]$tweak.title.$lang | Should -Not -BeNullOrEmpty -Because "$($tweak.id) title.$lang"
                [string]$tweak.why.$lang | Should -Not -BeNullOrEmpty -Because "$($tweak.id) why.$lang"
            }
        }
    }

    It 'has unique ids and a different title for every tweak in each language' {
        @($Catalog | Group-Object -Property id | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) -join ', ' | Should -BeNullOrEmpty
        foreach ($lang in 'es', 'en') {
            @($Catalog | Group-Object -Property { [string]$_.title.$lang } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) -join ', ' |
                Should -BeNullOrEmpty -Because $lang
        }
    }

    It 'writes each registry value from a single tweak, except the documented alternatives' {
        # Two tweaks for the same value would undo each other. The allowed pair are alternatives that
        # the documentation tells apart (one of them is high risk and is only applied by name).
        $allowed = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry')
        $groups = $Catalog | Where-Object { $_.type -eq 'registry' } | Group-Object -Property { "$($_.set.path)|$($_.set.name)" }
        @($groups | Where-Object { $_.Count -gt 1 -and $allowed -notcontains $_.Name } | ForEach-Object { $_.Name }) -join ', ' | Should -BeNullOrEmpty
    }

    It 'uses only known requires tokens' {
        foreach ($tweak in $Catalog | Where-Object { $null -ne $_.PSObject.Properties['requires'] }) {
            foreach ($token in @($tweak.requires)) { @('battery', 'no-battery') | Should -Contain $token -Because $tweak.id }
        }
    }

    It 'finds the script of every action tweak in actions/ and loads it' {
        $loadErrors = @(Get-TuneupActionLoadError)
        foreach ($tweak in $Catalog | Where-Object { $_.type -eq 'action' }) {
            Test-Path -LiteralPath (Join-Path $RepoRoot "actions\$($tweak.set.script).ps1") -PathType Leaf | Should -BeTrue -Because $tweak.id
            @($loadErrors | Where-Object { $_.name -eq $tweak.set.script }).Count | Should -Be 0 -Because $tweak.id
        }
    }
}

Describe 'Blacklist guard' {
    BeforeAll {
        # Every comparison ignores case: Windows paths, service names and package names do.
        $script:ProtectedServices = @('WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE', 'wuauserv', 'UsoSvc',
            'WaaSMedicSvc', 'BITS', 'DoSvc', 'InstallService', 'AppXSvc', 'ClipSVC', 'wlidsvc', 'TrustedInstaller', 'CryptSvc', 'SharedAccess',
            'LanmanServer', 'LanmanWorkstation', 'WerSvc', 'DPS', 'RmSvc', 'WpnService', 'webthreatdefsvc', 'webthreatdefusersvc', 'SysMain',
            'WSearch', 'vmcompute', 'vmms', 'hns', 'HvHost', 'LxssManager', 'WslService', 'EventLog', 'Schedule', 'Winmgmt', 'RpcSs', 'sppsvc',
            'VSS', 'swprv', 'AppIDSvc', 'Spooler')
        $script:BlockedValueNames = @('SvcHostSplitThresholdInKB', 'NetworkThrottlingIndex', 'SystemResponsiveness', 'TcpAckFrequency', 'TCPNoDelay',
            'DisableAntiSpyware', 'DisableRealtimeMonitoring', 'EnableSmartScreen', 'SmartScreenEnabled', 'NoAutoUpdate', 'DisableWindowsUpdateAccess',
            'FeatureSettingsOverride', 'FeatureSettingsOverrideMask', 'PagingFiles', 'EnableFirewall',
            'EnableLUA', 'ConsentPromptBehaviorAdmin', 'ConsentPromptBehaviorUser', 'PromptOnSecureDesktop', 'EnableVirtualization',
            'FilterAdministratorToken', 'LocalAccountTokenFilterPolicy',
            'EnableVirtualizationBasedSecurity', 'RequirePlatformSecurityFeatures', 'HypervisorEnforcedCodeIntegrity', 'LsaCfgFlags')
        $script:BlockedPathFragments = @('\Windows Defender', '\WindowsUpdate', '\WindowsFirewall', '\Session Manager\Memory Management', '\DeviceGuard')
        # The one tweak that is meant to turn memory integrity off (high risk, only with -Include).
        $script:VirtualizationSecurityException = 'gaming.memory-integrity-off'
        $script:ProtectedTaskFolders = @('\Microsoft\Windows\Windows Defender\', '\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\',
            '\Microsoft\Windows\WaaSMedic\', '\Microsoft\Windows\SystemRestore\', '\Microsoft\Windows\RecoveryEnvironment\',
            '\Microsoft\Windows\Chkdsk\', '\Microsoft\Windows\Defrag\', '\Microsoft\Windows\Servicing\', '\Microsoft\Windows\Registry\')
        $script:ProtectedTaskNames = @('Microsoft-Windows-DiskDiagnosticResolver')
        # The apps Windows needs or that people expect to keep, plus the frameworks and sign-in components.
        $script:ProtectedApps = @('Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.WindowsTerminal',
            'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad', 'Microsoft.Paint', 'Microsoft.ScreenSketch',
            'Microsoft.WindowsCamera', 'Microsoft.SecHealthUI', 'Microsoft.MicrosoftEdge*', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.XboxGameCallableUI', 'MicrosoftWindows.Client.CoreAI', 'MicrosoftWindows.Client.CBS',
            'Microsoft.NET.*', 'Microsoft.VCLibs.*', 'Microsoft.UI.Xaml.*', 'Microsoft.WindowsAppRuntime*', 'MicrosoftCorporationII.WinAppRuntime*')

        function Get-BlacklistViolation($Tweak) {
            $type = [string]$Tweak.type
            $set = $Tweak.set
            $id = [string]$Tweak.id
            if ($type -eq 'service') {
                if ($ProtectedServices -contains [string]$set.name) { "$id touches the protected service $($set.name)" }
            }
            if ($type -eq 'registry') {
                $path = [string]$set.path
                if ($BlockedValueNames -contains [string]$set.name -and $id -ne $VirtualizationSecurityException) { "$id writes the protected value $($set.name)" }
                foreach ($fragment in $BlockedPathFragments) {
                    if ($id -eq $VirtualizationSecurityException) { continue }
                    if ($path.IndexOf($fragment, [StringComparison]::OrdinalIgnoreCase) -ge 0) { "$id writes under $fragment" }
                }
                foreach ($service in $ProtectedServices) {
                    if ($path -match ('(?i)\\Services\\' + [regex]::Escape($service) + '(\\|$)')) { "$id writes the configuration of the protected service $service" }
                }
            }
            if ($type -eq 'task') {
                $folder = ([string]$set.path).TrimEnd('\') + '\'
                foreach ($protectedFolder in $ProtectedTaskFolders) {
                    # Also catches a subfolder and a path written without its final backslash.
                    if ($folder.StartsWith($protectedFolder, [StringComparison]::OrdinalIgnoreCase)) { "$id disables a task under $protectedFolder" }
                }
                if ($ProtectedTaskNames -contains [string]$set.name) { "$id disables the task $($set.name)" }
            }
            if ($type -eq 'appx') {
                foreach ($pattern in $ProtectedApps) {
                    # A wildcard in the catalog name must not slip past the list either.
                    if (([string]$set.name -like $pattern) -or ($pattern -like [string]$set.name)) { "$id removes the protected app $pattern" }
                }
            }
            if ($type -eq 'feature' -or $type -eq 'capability') {
                if ([string]$set.name -match '^(Microsoft-Hyper-V|VirtualMachinePlatform|HypervisorPlatform|Containers|Microsoft-Windows-Subsystem-Linux)') {
                    "$id touches a virtualization feature that WSL, Hyper-V or containers need"
                }
            }
        }
    }

    It 'trips no rule of the blacklist' {
        $violations = @($Catalog | ForEach-Object { Get-BlacklistViolation $_ })
        $violations -join "`n" | Should -BeNullOrEmpty
    }

    It 'keeps every protected service, task and app of the lists out of the catalog by name' {
        $services = @($Catalog | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        @($services | Where-Object { $ProtectedServices -contains $_ }) -join ', ' | Should -BeNullOrEmpty
        $apps = @($Catalog | Where-Object { $_.type -eq 'appx' } | ForEach-Object { [string]$_.set.name })
        foreach ($keep in 'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.WindowsTerminal', 'Microsoft.WindowsCalculator',
            'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad', 'Microsoft.Paint', 'Microsoft.ScreenSketch', 'Microsoft.WindowsCamera', 'Microsoft.SecHealthUI') {
            $apps | Should -Not -Contain $keep
        }
    }

    It 'catches <Name>' -TestCases @(
        # The four ways past the first version of these checks.
        @{ Name = 'a registry path written in another case'; Type = 'registry'; Set = @{ path = 'HKLM:\software\policies\microsoft\WINDOWS DEFENDER'; name = 'Foo'; kind = 'DWord'; value = 1 } }
        @{ Name = 'a value inside the key of a protected service'; Type = 'registry'; Set = @{ path = 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend'; name = 'Start'; kind = 'DWord'; value = 4 } }
        @{ Name = 'a task in a subfolder of a protected folder, in another case'; Type = 'task'; Set = @{ path = '\microsoft\windows\windowsupdate\Sub'; name = 'Any'; state = 'Disabled' } }
        @{ Name = 'a keep-list app'; Type = 'appx'; Set = @{ name = 'Microsoft.WindowsCalculator'; storeId = '9WZDNCRFHVN5'; action = 'remove' } }
        # More of the same kind.
        @{ Name = 'the Store written with a wildcard'; Type = 'appx'; Set = @{ name = 'Microsoft.Windows*'; storeId = '9WZDNCRFHVN5'; action = 'remove' } }
        @{ Name = 'a protected service in another case'; Type = 'service'; Set = @{ name = 'wuauserv'.ToUpper(); startType = 'Disabled'; stop = $true } }
        @{ Name = 'a UAC value'; Type = 'registry'; Set = @{ path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'PromptOnSecureDesktop'; kind = 'DWord'; value = 0 } }
        @{ Name = 'a UAC value for standard users'; Type = 'registry'; Set = @{ path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'ConsentPromptBehaviorUser'; kind = 'DWord'; value = 0 } }
        @{ Name = 'a virtualization-based security key'; Type = 'registry'; Set = @{ path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; name = 'EnableVirtualizationBasedSecurity'; kind = 'DWord'; value = 0 } }
        @{ Name = 'a task of the update orchestrator'; Type = 'task'; Set = @{ path = '\Microsoft\Windows\UpdateOrchestrator'; name = 'Schedule Scan'; state = 'Disabled' } }
        @{ Name = 'the disk diagnostic task'; Type = 'task'; Set = @{ path = '\Microsoft\Windows\DiskDiagnostic\'; name = 'Microsoft-Windows-DiskDiagnosticResolver'; state = 'Disabled' } }
        @{ Name = 'a virtualization feature'; Type = 'feature'; Set = @{ name = 'Microsoft-Hyper-V-All'; state = 'Disabled' } }
    ) {
        param($Type, $Set)
        $tweak = [pscustomobject]@{ id = 'test.bad'; type = $Type; set = [pscustomobject]$Set }
        @(Get-BlacklistViolation $tweak).Count | Should -BeGreaterThan 0
    }

    It 'lets a harmless tweak and the explicit memory integrity tweak through' {
        $harmless = [pscustomobject]@{ id = 'test.ok'; type = 'registry'; set = [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; kind = 'DWord'; value = 0 } }
        @(Get-BlacklistViolation $harmless).Count | Should -Be 0
        $memory = $ById['gaming.memory-integrity-off']
        $memory.risk | Should -Be 'high'
        @(Get-BlacklistViolation $memory).Count | Should -Be 0
        $copy = $memory | Select-Object -Property *
        $copy.id = 'test.other'
        @(Get-BlacklistViolation $copy).Count | Should -BeGreaterThan 0
    }
}

Describe 'Shipped profiles' {
    It 'never lists a tweak both in include and in keep of the same profile' {
        foreach ($profileData in $Profiles) {
            @(@($profileData.include) | Where-Object { @($profileData.keep) -contains $_ }) -join ', ' | Should -BeNullOrEmpty -Because $profileData.id
        }
    }

    It 'keeps base to user tweaks that need no administrator and are not policies' {
        foreach ($tweakId in @((Get-ProfileById 'base').include)) {
            $tweak = $ById[$tweakId]
            Test-TuneupUserScopedTweak -Tweak $tweak | Should -BeTrue -Because $tweakId
            Test-TuneupPolicyTweak -Tweak $tweak | Should -BeFalse -Because $tweakId
            Test-TuneupTweakNeedsAdmin -Tweak $tweak | Should -BeFalse -Because $tweakId
        }
    }

    It 'treats the HKCU policies of the catalog as needing an administrator, so base cannot hold them' {
        $policies = @($Catalog | Where-Object { $_.scope -eq 'user' -and (Test-TuneupPolicyTweak -Tweak $_) } | ForEach-Object { $_.id })
        $policies | Should -Contain 'ads.start-hide-recommended-policy'
        $policies | Should -Contain 'ai.copilot-policy-off'
        foreach ($id in $policies) { Test-TuneupTweakNeedsAdmin -Tweak $ById[$id] | Should -BeTrue -Because $id }
        foreach ($id in $policies) { @((Get-ProfileById 'base').include) | Should -Not -Contain $id }
    }

    It 'has no high-risk tweak in any profile' {
        foreach ($profileData in $Profiles) {
            foreach ($tweakId in @($profileData.include)) { $ById[$tweakId].risk | Should -Not -Be 'high' -Because "$($profileData.id) $tweakId" }
        }
    }
}

Describe 'The eight profiles' {
    BeforeAll {
        $script:NotApplied = { param($tweak) 'not-applied' }
        function Get-Plan([string[]]$ProfileIds, $Environment = (New-TestEnvironment), [string[]]$Include = @()) {
            @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -ProfileIds $ProfileIds -Include $Include -Environment $Environment -TestState $NotApplied)
        }
    }

    It 'ships exactly base, dev, gaming, privacy, laptop, legacy, work and lite with their aliases' {
        @($Profiles | ForEach-Object { $_.id } | Sort-Object) -join ',' | Should -Be 'base,dev,gaming,laptop,legacy,lite,privacy,work'
        $expected = @{ dev = 'desarrollo'; gaming = 'juegos'; privacy = 'privacidad'; laptop = 'portatil,port' + [char]0x00E1 + 'til'
            legacy = 'equipo-antiguo,antiguo'; work = 'trabajo'; lite = 'liviano'; base = '' }
        foreach ($profileData in $Profiles) { @($profileData.aliases) -join ',' | Should -Be $expected[$profileData.id] -Because $profileData.id }
    }

    It 'resolves every alias to its profile' {
        foreach ($profileData in $Profiles) {
            foreach ($alias in @($profileData.aliases)) { Resolve-TuneupProfileId -Profiles $Profiles -Name $alias | Should -Be $profileData.id }
        }
    }

    It 'plans every profile on <Name> without errors, listing every tweak it includes' -TestCases @(
        @{ Name = 'Home with a battery'; Edition = 'Home'; Battery = $true; Managed = $false; Family = '11'; Build = 26100 }
        @{ Name = 'Pro without a battery'; Edition = 'Pro'; Battery = $false; Managed = $false; Family = '11'; Build = 26100 }
        @{ Name = 'Enterprise managed by an organization'; Edition = 'Enterprise'; Battery = $true; Managed = $true; Family = '11'; Build = 26100 }
        @{ Name = 'Windows 10 Education'; Edition = 'Education'; Battery = $false; Managed = $false; Family = '10'; Build = 19045 }
    ) {
        param($Edition, $Battery, $Managed, $Family, $Build)
        $environment = New-TestEnvironment -Edition $Edition -HasBattery $Battery -IsManaged $Managed -Family $Family -Build $Build
        $known = @('excluded', 'kept-by-profile', 'incompatible', 'not-applicable-hardware', 'managed-device', 'high-risk-not-requested', 'needs-confirmation')
        foreach ($profileData in $Profiles) {
            $plan = Get-Plan -ProfileIds $profileData.id -Environment $environment
            foreach ($tweakId in @($profileData.include)) { @($plan | ForEach-Object { $_.Id }) | Should -Contain $tweakId -Because "$($profileData.id) on $Edition" }
            foreach ($item in $plan | Where-Object { $_.Action -eq 'skip' }) {
                $known | Should -Contain $item.Reason -Because "$($profileData.id): $($item.Id)"
                Get-TuneupText -Key "reason.$($item.Reason)" | Should -Not -Be "reason.$($item.Reason)"
            }
        }
    }

    It 'asks before every tweak marked ask, unless it is requested by name' {
        $plan = Get-Plan -ProfileIds 'lite', 'privacy', 'gaming', 'dev', 'laptop'
        foreach ($item in $plan | Where-Object { $_.Tweak.ask -and $_.Reason -ne 'incompatible' -and $_.Reason -ne 'not-applicable-hardware' -and $_.Reason -ne 'kept-by-profile' }) {
            $item.Reason | Should -Be 'needs-confirmation' -Because $item.Id
        }
        (Get-Plan -ProfileIds 'lite' -Include 'apps.onedrive' | Where-Object { $_.Id -eq 'apps.onedrive' }).Action | Should -Be 'apply'
    }

    It 'keeps the Xbox apps and task when gaming is combined with lite' {
        $plan = Get-Plan -ProfileIds 'gaming', 'lite'
        foreach ($tweakId in 'apps.xbox-gaming-app', 'apps.xbox-game-bar', 'tasks.xbox-game-save') {
            ($plan | Where-Object { $_.Id -eq $tweakId }).Reason | Should -Be 'kept-by-profile' -Because $tweakId
        }
    }

    It 'keeps Teams, Outlook, OneDrive and Microsoft 365 when work is combined with lite' {
        $plan = Get-Plan -ProfileIds 'work', 'lite'
        foreach ($tweakId in 'apps.msteams', 'apps.outlook-new', 'apps.onedrive', 'apps.office-hub', 'apps.power-automate') {
            ($plan | Where-Object { $_.Id -eq $tweakId }).Reason | Should -Be 'kept-by-profile' -Because $tweakId
        }
    }

    It 'gives work only user settings that are not policies' {
        foreach ($tweakId in @((Get-ProfileById 'work').include)) {
            Test-TuneupUserScopedTweak -Tweak $ById[$tweakId] | Should -BeTrue -Because $tweakId
            Test-TuneupPolicyTweak -Tweak $ById[$tweakId] | Should -BeFalse -Because $tweakId
            Test-TuneupTweakNeedsAdmin -Tweak $ById[$tweakId] | Should -BeFalse -Because $tweakId
        }
    }

    It 'removes in lite what LTSC does not ship' {
        $lite = @((Get-ProfileById 'lite').include)
        foreach ($tweakId in 'apps.copilot', 'apps.msteams', 'apps.xbox-gaming-app', 'apps.phone-link', 'apps.onedrive', 'apps.widgets-web-experience', 'ui.widgets-off', 'ads.bing-search-off') {
            $lite | Should -Contain $tweakId
        }
    }

    It 'leaves the plan of a machine with a battery free of the desktop power plan' {
        $plan = Get-Plan -ProfileIds 'gaming' -Environment (New-TestEnvironment -HasBattery $true)
        ($plan | Where-Object { $_.Id -eq 'power.high-performance-plan' }).Reason | Should -Be 'not-applicable-hardware'
    }
}
