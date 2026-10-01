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
        foreach ($id in 'ads.consumer-features', 'ads.start-hide-recommended-policy') {
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
            'edge.diagnostic-data-off',
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
