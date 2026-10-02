BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:I18nRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
}

Describe 'i18n' {
    It 'defines the same keys in es and en' {
        $es = (Get-Content -LiteralPath (Join-Path $I18nRoot 'es.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object
        $en = (Get-Content -LiteralPath (Join-Path $I18nRoot 'en.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object
        (Compare-Object -ReferenceObject $es -DifferenceObject $en | ForEach-Object { $_.InputObject }) -join ', ' | Should -BeNullOrEmpty
    }

    It 'uses the same {n} placeholders in es and en for every key' {
        $es = Get-Content -LiteralPath (Join-Path $I18nRoot 'es.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $en = Get-Content -LiteralPath (Join-Path $I18nRoot 'en.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $placeholders = { param($text) (([regex]::Matches([string]$text, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ',') }
        $mismatches = foreach ($key in $es.PSObject.Properties.Name) {
            $spanish = & $placeholders $es.$key
            $english = & $placeholders $en.$key
            if ($spanish -ne $english) { "${key}: es=[$spanish] en=[$english]" }
        }
        $mismatches -join '; ' | Should -BeNullOrEmpty
    }

    It 'keeps the English texts in plain ASCII separators' {
        $en = Get-Content -LiteralPath (Join-Path $I18nRoot 'en.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $offenders = foreach ($property in $en.PSObject.Properties) {
            if ([string]$property.Value -match [regex]::Escape([string][char]0x00B7)) { $property.Name }
        }
        $offenders -join ', ' | Should -BeNullOrEmpty
    }

    It 'has no control characters in any text, such as the tab of an unescaped path separator' {
        foreach ($lang in 'es', 'en') {
            $texts = Get-Content -LiteralPath (Join-Path $I18nRoot "$lang.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            $offenders = foreach ($property in $texts.PSObject.Properties) {
                if ([string]$property.Value -match '\p{Cc}') { $property.Name }
            }
            $offenders -join ', ' | Should -BeNullOrEmpty -Because $lang
        }
    }

    It 'says what the rule of a managed PC is and why a result can be missing, in both languages' {
        $es = Get-Content -LiteralPath (Join-Path $I18nRoot 'es.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $en = Get-Content -LiteralPath (Join-Path $I18nRoot 'en.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        # managed = joined to a domain or enrolled in MDM (the rule of environment.isManaged).
        $es.'suggest.signal.managed' | Should -Match 'dominio o MDM'
        $en.'suggest.signal.managed' | Should -Match 'domain or MDM'
        # No result: refused before it started, or stopped (Ctrl+C, exit 2) before it wrote.
        $es.'err.readResultMissing' | Should -Match 'Ctrl\+C'
        $en.'err.readResultMissing' | Should -Match 'Ctrl\+C'
        $en.'err.readResultMissing' | Should -Match 'exit code 2'
    }

    It 'formats texts with arguments' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        Get-TuneupText -Key 'plan.header' -Format 3, 1 | Should -Be 'Plan: 3 to apply, 1 skipped'
    }

    It 'returns the key when the text does not exist' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        Get-TuneupText -Key 'no.such.key' | Should -Be 'no.such.key'
    }

    It 'picks the tweak title in the active language' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'es'
        Get-TuneupTitle -Tweak (New-TestTweak -Id 'test.a') | Should -Be 'Titulo test.a'
    }

    It 'falls back to English for an unknown language' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'fr'
        Get-TuneupLang | Should -Be 'en'
    }
}
