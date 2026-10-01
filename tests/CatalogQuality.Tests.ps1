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
    It 'never touches a service that the blacklist or a profile protects' {
        $protected = @('WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE', 'wuauserv', 'UsoSvc',
            'WaaSMedicSvc', 'BITS', 'TrustedInstaller', 'CryptSvc', 'SharedAccess', 'LanmanServer', 'LanmanWorkstation', 'WerSvc', 'DPS',
            'RmSvc', 'WpnService', 'webthreatdefsvc', 'webthreatdefusersvc', 'SysMain', 'WSearch', 'vmcompute', 'vmms', 'hns', 'HvHost',
            'LxssManager', 'WslService', 'EventLog', 'Schedule', 'Winmgmt', 'RpcSs', 'sppsvc', 'VSS', 'swprv', 'AppIDSvc', 'Spooler')
        $touched = @($Catalog | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        @($touched | Where-Object { $protected -contains $_ }) -join ', ' | Should -BeNullOrEmpty
    }

    It 'never writes a registry value of the blacklist' {
        $names = @('SvcHostSplitThresholdInKB', 'NetworkThrottlingIndex', 'SystemResponsiveness', 'TcpAckFrequency', 'TCPNoDelay',
            'DisableAntiSpyware', 'DisableRealtimeMonitoring', 'EnableLUA', 'ConsentPromptBehaviorAdmin', 'EnableSmartScreen',
            'SmartScreenEnabled', 'NoAutoUpdate', 'DisableWindowsUpdateAccess', 'FeatureSettingsOverride', 'FeatureSettingsOverrideMask',
            'PagingFiles', 'EnableFirewall')
        $paths = @('\Windows Defender', '\WindowsUpdate', '\WindowsFirewall', '\Services\SharedAccess', '\Session Manager\Memory Management')
        foreach ($tweak in $Catalog | Where-Object { $_.type -eq 'registry' }) {
            $names | Should -Not -Contain ([string]$tweak.set.name) -Because $tweak.id
            foreach ($fragment in $paths) { ([string]$tweak.set.path).Contains($fragment) | Should -BeFalse -Because "$($tweak.id) writes under $fragment" }
        }
    }

    It 'never disables a scheduled task of Defender, updates, recovery or disk health' {
        $folders = @('\Microsoft\Windows\Windows Defender\', '\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\',
            '\Microsoft\Windows\WaaSMedic\', '\Microsoft\Windows\SystemRestore\', '\Microsoft\Windows\RecoveryEnvironment\',
            '\Microsoft\Windows\Chkdsk\', '\Microsoft\Windows\Defrag\', '\Microsoft\Windows\Servicing\', '\Microsoft\Windows\Registry\')
        foreach ($tweak in $Catalog | Where-Object { $_.type -eq 'task' }) {
            $folders | Should -Not -Contain ([string]$tweak.set.path) -Because $tweak.id
            [string]$tweak.set.name | Should -Not -Be 'Microsoft-Windows-DiskDiagnosticResolver' -Because $tweak.id
        }
    }

    It 'never removes the Store, winget, Windows Security, Edge, frameworks or the Xbox sign-in components' {
        $patterns = @('Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI',
            'Microsoft.MicrosoftEdge*', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
            'Microsoft.XboxGameCallableUI', 'MicrosoftWindows.Client.CoreAI', 'MicrosoftWindows.Client.CBS', 'Microsoft.NET.*',
            'Microsoft.VCLibs.*', 'Microsoft.UI.Xaml.*', 'Microsoft.WindowsAppRuntime*', 'MicrosoftCorporationII.WinAppRuntime*')
        foreach ($tweak in $Catalog | Where-Object { $_.type -eq 'appx' }) {
            foreach ($pattern in $patterns) { [string]$tweak.set.name | Should -Not -BeLike $pattern -Because $tweak.id }
        }
    }

    It 'never touches the virtualization features that WSL, Hyper-V and containers need' {
        foreach ($tweak in $Catalog | Where-Object { $_.type -eq 'feature' -or $_.type -eq 'capability' }) {
            [string]$tweak.set.name | Should -Not -Match '^(Microsoft-Hyper-V|VirtualMachinePlatform|HypervisorPlatform|Containers|Microsoft-Windows-Subsystem-Linux)' -Because $tweak.id
        }
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
        }
    }

    It 'has no high-risk tweak in any profile' {
        foreach ($profileData in $Profiles) {
            foreach ($tweakId in @($profileData.include)) { $ById[$tweakId].risk | Should -Not -Be 'high' -Because "$($profileData.id) $tweakId" }
        }
    }
}
