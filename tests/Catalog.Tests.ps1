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
    It 'rejects wildcard characters in a task name or path' {
        foreach ($set in @(
                [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Sample*'; state = 'Disabled' },
                [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Sam?le'; state = 'Disabled' },
                [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Sample[1]'; state = 'Disabled' },
                [pscustomobject]@{ path = '\Microsoft\*\'; name = 'Sample'; state = 'Disabled' })) {
            (Test-TuneupTweak -Tweak (New-TestTweak -Type 'task' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'cannot contain wildcard characters'
        }
    }
    It 'rejects an unsupported type' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'magic')) -join '; ' | Should -Match "unsupported type 'magic'"
    }
    It 'accepts DWord values in the unsigned and signed Int32 range' {
        foreach ($value in 0, 1, 4294967295, -1, -2147483648) {
            $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'DWord'; value = $value }
            (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -BeNullOrEmpty
        }
    }
    It 'rejects a DWord value out of range' {
        foreach ($value in 4294967296, -2147483649) {
            $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'DWord'; value = $value }
            (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'value that does not match kind DWord'
        }
    }
    It 'rejects a DWord value that is a string, a boolean, a fraction or an array' {
        foreach ($value in '1', $true, 1.5, @(1, 2)) {
            $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'DWord'; value = $value }
            (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'value that does not match kind DWord'
        }
    }
    It 'validates QWord and String values against their kind' {
        $ok = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'QWord'; value = 4294967296 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $ok)) -join '; ' | Should -BeNullOrEmpty
        $bad = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'QWord'; value = 'x' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $bad)) -join '; ' | Should -Match 'value that does not match kind QWord'
        $ok = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'String'; value = 'text' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $ok)) -join '; ' | Should -BeNullOrEmpty
        $bad = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'String'; value = 5 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $bad)) -join '; ' | Should -Match 'value that does not match kind String'
        $bad = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'ExpandString'; value = @('a', 'b') }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $bad)) -join '; ' | Should -Match 'value that does not match kind ExpandString'
    }
    It 'rejects ask and rebootRequired that are not booleans' {
        $tweak = New-TestTweak
        $tweak.ask = 'no'
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'ask must be true or false'
        $tweak = New-TestTweak
        $tweak.PSObject.Properties.Remove('rebootRequired')
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'rebootRequired must be true or false'
    }
    It 'rejects a service tweak whose stop is not a boolean' {
        $set = [pscustomobject]@{ name = 'RetailDemo'; startType = 'Disabled' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'service' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'set.stop must be true or false'
    }
    It 'reports a load error before anything else' {
        $placeholder = [pscustomobject]@{ id = $null; sourceFile = 'x.json'; loadError = 'file x.json has no tweaks array' }
        (Test-TuneupTweak -Tweak $placeholder) -join '; ' | Should -Be 'file x.json has no tweaks array'
    }
}

Describe 'Test-TuneupCatalog' {
    It 'does not report duplicate ids for load errors' {
        $first = [pscustomobject]@{ id = $null; sourceFile = 'a.json'; loadError = 'file a.json has no tweaks array' }
        $second = [pscustomobject]@{ id = $null; sourceFile = 'b.json'; loadError = 'file b.json has no tweaks array' }
        $errors = @(Test-TuneupCatalog -Catalog @($first, $second))
        $errors.Count | Should -Be 2
        $errors -join '; ' | Should -Not -Match 'duplicate'
    }
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
    It 'reports a file without a tweaks array' {
        $dir = Join-Path $TestDrive 'bad-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.json') -Value '{ "other": [] }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'b.json') -Value '{ "tweaks": { "id": "b.one" } }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'c.json') -Value '[ { "id": "c.one" } ]' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'd.json') -Value '{ "tweaks": null }' -Encoding UTF8
        $errors = Test-TuneupCatalog -Catalog @(Import-TuneupCatalog -Path $dir)
        foreach ($name in 'a.json', 'b.json', 'c.json', 'd.json') {
            $errors -join '; ' | Should -Match "file $([regex]::Escape($name)) has no tweaks array"
        }
    }
    It 'reports an empty file as a load error without throwing' {
        $dir = Join-Path $TestDrive 'blank-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ui.json') -Value '' -Encoding UTF8
        $ErrorActionPreference = 'Stop'
        $catalog = @(Import-TuneupCatalog -Path $dir)
        $catalog.Count | Should -Be 1
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -Be 'file ui.json has no tweaks array'
    }
    It 'accepts a file with an empty tweaks array' {
        $dir = Join-Path $TestDrive 'empty-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ui.json') -Value '{ "tweaks": [] }' -Encoding UTF8
        @(Import-TuneupCatalog -Path $dir).Count | Should -Be 0
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
    It 'rejects unknown tweak ids in keep' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'base' -Keep @('ui.gone')) -Catalog $Catalog) -join '; ' | Should -Match 'unknown tweak ui.gone'
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
