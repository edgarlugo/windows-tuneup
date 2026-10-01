BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:CatalogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog'
    function Get-CategoryTweak([string]$Name) {
        @(Import-TuneupCatalog -Path $CatalogDir | Where-Object { $_.sourceFile -eq "$Name.json" })
    }
    function Get-CategoryId([string]$Name) { @(Get-CategoryTweak $Name | ForEach-Object { $_.id }) -join ',' }
}

Describe 'privacy catalog' {
    It 'ships the privacy tweaks in this order' {
        $expected = @(
            'privacy.advertising-id',
            'privacy.tailored-experiences',
            'privacy.diagnostic-data-required',
            'privacy.diagnostic-data-off',
            'privacy.feedback-never',
            'privacy.ceip-off',
            'privacy.app-launch-tracking-off',
            'privacy.online-speech-off',
            'privacy.inking-typing-improve-off',
            'privacy.input-personalization-text-off',
            'privacy.input-personalization-ink-off',
            'privacy.language-list-off',
            'privacy.activity-publish-off',
            'privacy.activity-upload-off',
            'privacy.clipboard-cloud-off',
            'privacy.location-off',
            'privacy.find-my-device-off',
            'privacy.error-reporting-off'
        ) -join ','
        Get-CategoryId 'privacy' | Should -Be $expected
    }

    It 'keeps diagnostic data off as a high-risk alternative for Enterprise and Education only' {
        $off = Get-CategoryTweak 'privacy' | Where-Object { $_.id -eq 'privacy.diagnostic-data-off' }
        $off.risk | Should -Be 'high'
        @($off.os.editions) -join ',' | Should -Be 'Enterprise,Education'
        $required = Get-CategoryTweak 'privacy' | Where-Object { $_.id -eq 'privacy.diagnostic-data-required' }
        $required.set.value | Should -Be 1
        @($required.os.editions) -join ',' | Should -Be 'Pro,Enterprise,Education'
    }
}

Describe 'ads catalog' {
    It 'ships the ads tweaks in this order' {
        $expected = @(
            'ads.start-suggestions',
            'ads.start-system-pane',
            'ads.start-recommendations',
            'ads.start-account-notifications',
            'ads.tips-and-tricks',
            'ads.welcome-experience',
            'ads.settings-suggestions-1',
            'ads.settings-suggestions-2',
            'ads.settings-suggestions-3',
            'ads.finish-setup-prompts',
            'ads.sync-provider-notifications',
            'ads.silent-installed-apps',
            'ads.suggested-notifications',
            'ads.phone-link-suggestions',
            'ads.backup-reminders',
            'ads.start-phone-link',
            'ads.lockscreen-tips',
            'ads.lockscreen-overlay',
            'ads.consumer-features',
            'ads.settings-home-365',
            'ads.start-hide-recommended-policy',
            'ads.start-recent-files-off',
            'ads.start-recent-apps-off',
            'ads.start-most-used-off',
            'ads.bing-search-off',
            'ads.search-box-suggestions-off',
            'ads.search-highlights-off',
            'ads.search-history-off'
        ) -join ','
        Get-CategoryId 'ads' | Should -Be $expected
    }

    It 'declares the policies that only Enterprise and Education honor' {
        foreach ($id in 'ads.consumer-features', 'ads.settings-home-365') {
            @((Get-CategoryTweak 'ads' | Where-Object { $_.id -eq $id }).os.editions) -join ',' | Should -Be 'Enterprise,Education' -Because $id
        }
    }
}

Describe 'ui catalog' {
    It 'ships the ui tweaks in this order' {
        $expected = @(
            'ui.show-file-extensions',
            'ui.show-hidden-files',
            'ui.taskbar-end-task',
            'ui.task-view-button-off',
            'ui.widgets-off',
            'ui.news-interests-win10',
            'ui.meet-now-win10',
            'ui.transparency-off',
            'ui.window-animations-off',
            'ui.listview-shadow-off',
            'ui.listview-alpha-select-off',
            'ui.aero-peek-off'
        ) -join ','
        Get-CategoryId 'ui' | Should -Be $expected
    }
}

Describe 'ai catalog' {
    It 'ships the ai tweaks in this order' {
        $expected = @(
            'ai.copilot-button-off',
            'ai.copilot-policy-off',
            'ai.recall-snapshots-off',
            'ai.recall-unavailable',
            'ai.click-to-do-off',
            'ai.notepad-ai-off',
            'ai.paint-cocreator-off',
            'ai.paint-image-creator-off',
            'ai.paint-generative-fill-off',
            'ai.fabric-service-manual'
        ) -join ','
        Get-CategoryId 'ai' | Should -Be $expected
    }
}

Describe 'edge catalog' {
    It 'ships the edge tweaks in this order' {
        $expected = @(
            'edge.personalization-reporting-off',
            'edge.diagnostic-data-required',
            'edge.feedback-off',
            'edge.new-tab-feed-off',
            'edge.shopping-off',
            'edge.recommendations-off',
            'edge.spotlight-off',
            'edge.default-browser-campaign-off',
            'edge.acrobat-button-off',
            'edge.first-run-off',
            'edge.alternate-error-pages-off',
            'edge.sidebar-off',
            'edge.new-tab-bing-chat-off',
            'edge.history-ai-search-off',
            'edge.local-ai-model-off',
            'edge.startup-boost-off',
            'edge.background-mode-off'
        ) -join ','
        Get-CategoryId 'edge' | Should -Be $expected
    }

    It 'only writes Microsoft Edge policies of the machine' {
        foreach ($tweak in Get-CategoryTweak 'edge') {
            $tweak.scope | Should -Be 'machine' -Because $tweak.id
            [string]$tweak.set.path | Should -BeLike 'HKLM:\SOFTWARE\Policies\Microsoft\Edge*' -Because $tweak.id
        }
    }
}

Describe 'services catalog' {
    It 'ships the services tweaks in this order' {
        $expected = @(
            'services.retail-demo',
            'services.diagtrack',
            'services.wia',
            'services.maps-broker',
            'services.geolocation',
            'services.connected-devices',
            'services.connected-devices-user',
            'services.contact-data',
            'services.user-data-storage',
            'services.user-data-access'
        ) -join ','
        Get-CategoryId 'services' | Should -Be $expected
    }

    It 'asks before the services that apps or features of the user rely on' {
        $asked = @(Get-CategoryTweak 'services' | Where-Object { $_.ask } | ForEach-Object { $_.id }) -join ','
        $asked | Should -Be 'services.diagtrack,services.geolocation,services.connected-devices,services.connected-devices-user,services.contact-data,services.user-data-storage,services.user-data-access'
    }
}

Describe 'tasks catalog' {
    It 'ships the tasks tweaks in this order' {
        $expected = @(
            'tasks.ceip-consolidator',
            'tasks.ceip-usbceip',
            'tasks.autochk-proxy',
            'tasks.disk-diagnostic-data-collector',
            'tasks.appraiser',
            'tasks.appraiser-exp',
            'tasks.program-data-updater',
            'tasks.mare-backup',
            'tasks.startup-app-task',
            'tasks.maps-toast',
            'tasks.maps-update',
            'tasks.xbox-game-save',
            'tasks.power-efficiency-analyze',
            'tasks.disk-footprint-diagnostics',
            'tasks.work-folders-logon',
            'tasks.work-folders-maintenance',
            'tasks.winsat',
            'tasks.recommended-troubleshooting',
            'tasks.family-safety-monitor',
            'tasks.family-safety-refresh',
            'tasks.speech-model-download'
        ) -join ','
        Get-CategoryId 'tasks' | Should -Be $expected
    }
}

Describe 'performance catalog' {
    It 'ships the performance tweaks in this order' {
        $expected = @(
            'performance.delivery-optimization-http-only',
            'performance.explorer-folder-type-general',
            'performance.background-apps-off'
        ) -join ','
        Get-CategoryId 'performance' | Should -Be $expected
    }
}

Describe 'power catalog' {
    It 'ships the power tweaks in this order' {
        $expected = @(
            'power.high-performance-plan',
            'power.usb-selective-suspend-ac-off',
            'power.standby-network-off-battery'
        ) -join ','
        Get-CategoryId 'power' | Should -Be $expected
    }

    It 'ties the power tweaks to the hardware they are meant for' {
        $tweaks = Get-CategoryTweak 'power'
        @(($tweaks | Where-Object { $_.id -eq 'power.high-performance-plan' }).requires) -join ',' | Should -Be 'no-battery'
        @(($tweaks | Where-Object { $_.id -eq 'power.standby-network-off-battery' }).requires) -join ',' | Should -Be 'battery'
        $usb = $tweaks | Where-Object { $_.id -eq 'power.usb-selective-suspend-ac-off' }
        $usb.set.ac | Should -Be 0
        $null -eq $usb.set.PSObject.Properties['dc'] | Should -BeTrue
    }
}

Describe 'gaming catalog' {
    It 'ships the gaming tweaks in this order' {
        $expected = @(
            'gaming.game-mode-on',
            'gaming.game-dvr-off',
            'gaming.app-capture-off',
            'gaming.background-recording-off',
            'gaming.gamebar-controller-off',
            'gaming.mouse-accel-off',
            'gaming.mouse-accel-threshold-1',
            'gaming.mouse-accel-threshold-2',
            'gaming.windowed-optimizations',
            'gaming.hags-on',
            'gaming.memory-integrity-off'
        ) -join ','
        Get-CategoryId 'gaming' | Should -Be $expected
    }

    It 'leaves memory integrity as the only high-risk gaming tweak' {
        @(Get-CategoryTweak 'gaming' | Where-Object { $_.risk -eq 'high' } | ForEach-Object { $_.id }) -join ',' | Should -Be 'gaming.memory-integrity-off'
    }
}

Describe 'dev catalog' {
    It 'ships the dev tweaks in this order' {
        $expected = @(
            'dev.developer-mode',
            'dev.long-paths',
            'dev.sudo-enable'
        ) -join ','
        Get-CategoryId 'dev' | Should -Be $expected
    }
}

Describe 'apps catalog' {
    It 'ships the apps tweaks in this order' {
        $expected = @(
            'apps.clipchamp',
            'apps.bing-news',
            'apps.bing-weather',
            'apps.bing-finance',
            'apps.office-hub',
            'apps.power-automate',
            'apps.dev-home',
            'apps.messaging',
            'apps.mixed-reality-portal',
            'apps.movies-tv',
            'apps.bing-search',
            'apps.copilot',
            'apps.get-help',
            'apps.feedback-hub',
            'apps.todos',
            'apps.alarms-clock',
            'apps.sound-recorder',
            'apps.media-player',
            'apps.quick-assist',
            'apps.phone-link',
            'apps.xbox-gaming-app',
            'apps.xbox-game-bar',
            'apps.widgets-web-experience',
            'apps.widgets-platform-runtime',
            'apps.start-experiences',
            'apps.outlook-new',
            'apps.family-safety',
            'apps.mail-calendar',
            'apps.msteams',
            'apps.onedrive'
        ) -join ','
        Get-CategoryId 'apps' | Should -Be $expected
    }

    It 'asks before removing the apps people often use' {
        $asked = @(Get-CategoryTweak 'apps' | Where-Object { $_.ask } | ForEach-Object { $_.id }) -join ','
        $asked | Should -Be 'apps.copilot,apps.get-help,apps.alarms-clock,apps.media-player,apps.quick-assist,apps.phone-link,apps.xbox-gaming-app,apps.xbox-game-bar,apps.outlook-new,apps.family-safety,apps.mail-calendar,apps.msteams,apps.onedrive'
    }

    It 'gives every Store app the id that winget reinstalls' {
        foreach ($tweak in Get-CategoryTweak 'apps' | Where-Object { $_.type -eq 'appx' }) {
            [string]$tweak.set.storeId | Should -MatchExactly '^(?:[0-9A-Z]{12}|XP[0-9A-Z]{12})$' -Because $tweak.id
        }
        (Get-CategoryTweak 'apps' | Where-Object { $_.id -eq 'apps.msteams' }).set.storeId | Should -Be 'XP8BT8DW290MPQ'
        (Get-CategoryTweak 'apps' | Where-Object { $_.id -eq 'apps.onedrive' }).set.script | Should -Be 'onedrive'
    }
}

Describe 'review decisions of the catalog' {
    BeforeAll {
        $script:All = @(Import-TuneupCatalog -Path $CatalogDir)
        function Get-One([string]$Id) { $found = @($All | Where-Object { $_.id -eq $Id }); $found.Count | Should -Be 1 -Because $Id; $found[0] }
    }

    It 'keeps Recall behind -Include: high risk, and it says undo cannot bring the snapshots back' {
        foreach ($id in 'ai.recall-snapshots-off', 'ai.recall-unavailable') {
            $tweak = Get-One $id
            $tweak.risk | Should -Be 'high' -Because $id
            [string]$tweak.why.es | Should -BeLike '*deshacer no puede devolverlas*' -Because $id
            [string]$tweak.why.en | Should -BeLike '*undo cannot bring them back*' -Because $id
        }
    }

    It 'asks before the compatibility backup task, which also feeds the appraiser' {
        $tweak = Get-One 'tasks.mare-backup'
        $tweak.risk | Should -Be 'medium'
        $tweak.ask | Should -BeTrue
        [string]$tweak.why.en | Should -BeLike '*appraiser*'
    }

    It 'asks before limiting diagnostic data to Required, because Insider devices lose their builds' {
        $tweak = Get-One 'privacy.diagnostic-data-required'
        $tweak.ask | Should -BeTrue
        [string]$tweak.why.en | Should -BeLike '*Insider*'
        [string]$tweak.why.es | Should -BeLike '*Insider*'
    }

    It 'asks before the Xbox game save task, which Game Pass games use' {
        (Get-One 'tasks.xbox-game-save').ask | Should -BeTrue
    }

    It 'does not ship the Xbox services: they are Manual by default and Disabled breaks the Xbox sign-in' {
        $names = @($All | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        foreach ($name in 'XblGameSave', 'XblAuthManager', 'XboxNetApiSvc', 'XboxGipSvc') { $names | Should -Not -Contain $name }
    }

    It 'asks before background apps are stopped, and only for Windows 10' {
        $tweak = Get-One 'performance.background-apps-off'
        $tweak.ask | Should -BeTrue
        @($tweak.os.families) -join ',' | Should -Be '10'
        [string]$tweak.why.en | Should -BeLike '*Spotlight*'
    }

    It 'sets Edge diagnostic data to required data only, as a low-risk tweak' {
        @($All | Where-Object { $_.id -eq 'edge.diagnostic-data-off' }).Count | Should -Be 0
        $tweak = Get-One 'edge.diagnostic-data-required'
        $tweak.set.name | Should -Be 'DiagnosticData'
        $tweak.set.value | Should -Be 1
        $tweak.risk | Should -Be 'low'
    }

    It 'declares the editions the documentation gives' -TestCases @(
        @{ Id = 'ads.settings-home-365'; Editions = 'Enterprise,Education' }
        @{ Id = 'ui.news-interests-win10'; Editions = 'Pro,Enterprise,Education' }
        @{ Id = 'ads.start-hide-recommended-policy'; Editions = 'Pro,Enterprise,Education' }
        @{ Id = 'ai.notepad-ai-off'; Editions = 'Home,Pro,Enterprise,Education' }
        @{ Id = 'privacy.diagnostic-data-required'; Editions = 'Pro,Enterprise,Education' }
    ) {
        param($Id, $Editions)
        @((Get-One $Id).os.editions) -join ',' | Should -Be $Editions
    }

    It 'says that the Edge sidebar policy skips Microsoft-account profiles, and that diagnostic data is not for Insider builds' {
        [string](Get-One 'edge.sidebar-off').why.en | Should -BeLike '*Microsoft account*'
        [string](Get-One 'privacy.diagnostic-data-required').why.en | Should -BeLike '*Insider*'
    }

    It 'cites the Microsoft settings reference for Game Mode and background recording' {
        foreach ($id in 'gaming.game-mode-on', 'gaming.background-recording-off') {
            @((Get-One $id).sources) | Should -Contain 'https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11' -Because $id
        }
    }
}
