BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
}

Describe 'Test-TuneupTweak' {
    It 'accepts a valid registry tweak' {
        (Test-TuneupTweak -Tweak (New-TestTweak)) -join '; ' | Should -BeNullOrEmpty
    }
    It 'rejects an invalid id' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Id 'Bad Id')) -join '; ' | Should -Match 'invalid id'
    }
    It 'rejects a missing translation' {
        $tweak = New-TestTweak
        $tweak.title.en = ''
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'missing title.en'
    }
    It 'rejects an unknown risk' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Risk 'extreme')) -join '; ' | Should -Match 'invalid risk'
    }
    It 'rejects sources that are not https' {
        $tweak = New-TestTweak
        $tweak.sources = @('http://example.com')
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'https sources'
    }
    It 'rejects a user tweak that writes HKLM' {
        $set = [pscustomobject]@{ path = 'HKLM:\SOFTWARE\Example'; name = 'A'; kind = 'DWord'; value = 1 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'scope does not match'
    }
    It 'rejects an unknown registry kind' {
        $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'Text'; value = 1 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'invalid registry kind'
    }
    It 'accepts a registry tweak that removes a value' {
        $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = $null; value = $null }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -BeNullOrEmpty
    }
    It 'rejects a service tweak with an unknown start type' {
        $set = [pscustomobject]@{ name = 'RetailDemo'; startType = 'Sometimes'; stop = $false }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'service' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'invalid startType'
    }
    It 'rejects a task path without trailing backslash' {
        $set = [pscustomobject]@{ path = '\Microsoft\Windows'; name = 'X'; state = 'Disabled' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'task' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'backslash'
    }
    It 'rejects an unsupported type' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'magic')) -join '; ' | Should -Match "unsupported type 'magic'"
    }
}

Describe 'Test-TuneupCatalog' {
    It 'reports duplicated ids' {
        $catalog = @((New-TestTweak -Id 'test.a'), (New-TestTweak -Id 'test.a'))
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -Match 'duplicate id test.a'
    }
}

Describe 'Import-TuneupCatalog' {
    It 'rejects a tweak whose id does not match its file' {
        $dir = Join-Path $TestDrive 'catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $tweak = New-TestTweak -Id 'privacy.example'
        ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = @($tweak) }) -Depth 10 |
            Set-Content -LiteralPath (Join-Path $dir 'ui.json') -Encoding UTF8
        $catalog = @(Import-TuneupCatalog -Path $dir)
        $catalog.Count | Should -Be 1
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -Match 'does not match file ui.json'
    }
}

Describe 'Test-TuneupProfileSet' {
    BeforeAll {
        $script:Catalog = @((New-TestTweak -Id 'ui.a'), (New-TestTweak -Id 'ui.danger' -Risk 'high'))
    }
    It 'requires a base profile' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'gaming') -Catalog $Catalog) -join '; ' | Should -Match 'base profile is missing'
    }
    It 'rejects unknown tweak ids' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'base' -Include @('ui.nope')) -Catalog $Catalog) -join '; ' | Should -Match 'unknown tweak ui.nope'
    }
    It 'rejects high-risk tweaks inside a profile' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'base' -Include @('ui.danger')) -Catalog $Catalog) -join '; ' | Should -Match 'high-risk tweak ui.danger'
    }
    It 'rejects a name used twice' {
        $profiles = @((New-TestProfile -Id 'base'), (New-TestProfile -Id 'dev' -Aliases @('base')))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $Catalog) -join '; ' | Should -Match "name 'base' is used"
    }
}

Describe 'Shipped catalog and profiles' {
    It 'the catalog is valid and not empty' {
        $catalog = @(Import-TuneupCatalog -Path (Join-Path $RepoRoot 'catalog'))
        $catalog.Count | Should -BeGreaterThan 0
        (Test-TuneupCatalog -Catalog $catalog) -join "`n" | Should -BeNullOrEmpty
    }
    It 'the profiles are valid' {
        $catalog = @(Import-TuneupCatalog -Path (Join-Path $RepoRoot 'catalog'))
        $profiles = @(Import-TuneupProfileSet -Path (Join-Path $RepoRoot 'profiles'))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $catalog) -join "`n" | Should -BeNullOrEmpty
    }
}
