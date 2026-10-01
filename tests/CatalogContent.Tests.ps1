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
