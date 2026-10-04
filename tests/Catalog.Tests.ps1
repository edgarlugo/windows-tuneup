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
    It 'rejects a service tweak that does not use scope machine' {
        $set = [pscustomobject]@{ name = 'RetailDemo'; startType = 'Disabled'; stop = $false }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'service' -Scope 'user' -Set $set)) -join '; ' | Should -Match 'must use scope machine'
    }
    It 'rejects a task tweak that does not use scope machine' {
        $set = [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'X'; state = 'Disabled' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'task' -Scope 'user' -Set $set)) -join '; ' | Should -Match 'must use scope machine'
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

Describe 'Test-TuneupTweak case rules' {
    It 'rejects a registry <Field> that differs only in case (<Value>)' -TestCases @(
        @{ Field = 'kind'; Value = 'dword'; Set = @{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'dword'; value = 1 }; Message = 'invalid registry kind' }
        @{ Field = 'kind'; Value = 'string'; Set = @{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'string'; value = 'x' }; Message = 'invalid registry kind' }
        @{ Field = 'path'; Value = 'hkcu:'; Set = @{ path = 'hkcu:\Software\Example'; name = 'A'; kind = 'DWord'; value = 1 }; Message = 'invalid registry path' }
    ) {
        param($Set, $Message)
        $tweak = New-TestTweak -Set ([pscustomobject]$Set)
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match $Message
    }

    It 'rejects a service start type that differs only in case' {
        $set = [pscustomobject]@{ name = 'RetailDemo'; startType = 'disabled'; stop = $false }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'service' -Scope 'machine' -Set $set)) -join '; ' | Should -Match "invalid startType 'disabled'"
    }

    It 'rejects a task state that differs only in case' {
        $set = [pscustomobject]@{ path = '\Microsoft\Windows'; name = 'X'; state = 'disabled' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'task' -Scope 'machine' -Set $set)) -join '; ' | Should -Match "invalid task state 'disabled'"
    }

    It 'rejects a scope that differs only in case for every machine type (<Type>)' -TestCases @(
        @{ Type = 'service'; Set = @{ name = 'RetailDemo'; startType = 'Disabled'; stop = $false } }
        @{ Type = 'task'; Set = @{ path = '\Microsoft\Windows'; name = 'X'; state = 'Disabled' } }
        @{ Type = 'appx'; Set = @{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' } }
        @{ Type = 'capability'; Set = @{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' } }
        @{ Type = 'feature'; Set = @{ name = 'Printing-XPSServices-Features'; state = 'Disabled' } }
    ) {
        param($Type, $Set)
        $tweak = New-TestTweak -Type $Type -Scope 'Machine' -Set ([pscustomobject]$Set)
        $problems = (Test-TuneupTweak -Tweak $tweak) -join '; '
        $problems | Should -Match "invalid scope 'Machine'"
        $problems | Should -Match 'must use scope machine'
    }

    It 'rejects the user scope written in another case' {
        $tweak = New-TestTweak -Scope 'User'
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match "invalid scope 'User'"
    }

    It 'keeps the exact spelling that the shipped catalog and the fixtures use valid' {
        foreach ($folder in (Join-Path $RepoRoot 'catalog'), (Join-Path $PSScriptRoot 'fixtures\catalog')) {
            $catalog = @(Import-TuneupCatalog -Path $folder)
            @(Test-TuneupCatalog -Catalog $catalog | Where-Object { $_ -notlike "*action script*" -and $_ -notlike "*actions folder*" }) -join '; ' | Should -BeNullOrEmpty
        }
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
    It 'rejects offersStartup that is not true or false' {
        $profileData = New-TestProfile -Id 'base'
        $profileData | Add-Member -NotePropertyName offersStartup -NotePropertyValue 'yes'
        (Test-TuneupProfileSet -Profiles @($profileData) -Catalog $Catalog) -join '; ' | Should -Match 'profile base offersStartup must be true or false'
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
    It 'offers the review of what starts with Windows from the gaming profile only' {
        $profiles = @(Import-TuneupProfileSet -Path (Join-Path $RepoRoot 'profiles'))
        @($profiles | Where-Object { $null -ne $_.PSObject.Properties['offersStartup'] -and $_.offersStartup } | ForEach-Object { $_.id }) -join ',' | Should -Be 'gaming'
    }
}

Describe 'Test-TuneupTweak requires' {
    It 'accepts a tweak without requires and one with known tokens' {
        (Test-TuneupTweak -Tweak (New-TestTweak)) -join '; ' | Should -BeNullOrEmpty
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires @('battery'))) -join '; ' | Should -BeNullOrEmpty
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires @('no-battery'))) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'an unknown token'; Requires = @('desktop') }
        @{ Problem = 'a token in another case'; Requires = @('Battery') }
        @{ Problem = 'an empty list'; Requires = @() }
    ) {
        param($Requires)
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires $Requires)) -join '; ' | Should -Match 'invalid requires'
    }

    It 'rejects a requires that is not a list of text' {
        $tweak = New-TestTweak
        $tweak | Add-Member -NotePropertyName requires -NotePropertyValue $null
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'invalid requires'
    }

    It 'rejects a requires that is a bare string instead of a list' {
        $tweak = New-TestTweak
        $tweak | Add-Member -NotePropertyName requires -NotePropertyValue 'battery'
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'invalid requires'
    }

    It 'rejects a bare string in requires read from a catalog file' {
        $dir = Join-Path $TestDrive 'requires-bare-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $json = ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = @((New-TestTweak -Id 'power.sample')) }) -Depth 10
        $json = $json -replace '"rebootRequired":\s+false', '"rebootRequired": false, "requires": "battery"'
        Set-Content -LiteralPath (Join-Path $dir 'power.json') -Value $json -Encoding UTF8
        (Test-TuneupCatalog -Catalog @(Import-TuneupCatalog -Path $dir)) -join '; ' | Should -Match 'invalid requires'
    }

    It 'rejects battery and no-battery together' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires @('battery', 'no-battery'))) -join '; ' | Should -Match 'requires both battery and no-battery'
    }

    It 'reads requires from a catalog file' {
        $dir = Join-Path $TestDrive 'requires-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $tweak = New-TestTweak -Id 'power.sample' -Requires @('battery')
        ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = @($tweak) }) -Depth 10 |
            Set-Content -LiteralPath (Join-Path $dir 'power.json') -Encoding UTF8
        $catalog = @(Import-TuneupCatalog -Path $dir)
        @($catalog[0].requires) -join ',' | Should -Be 'battery'
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -BeNullOrEmpty
    }
}

Describe 'Test-TuneupTweak manualSetting' {
    It 'accepts a tweak without manualSetting and one with both languages' {
        $tweak = New-TestTweak
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -BeNullOrEmpty
        $tweak | Add-Member -NotePropertyName manualSetting -NotePropertyValue ([pscustomobject]@{ es = 'Configuracion > Widgets'; en = 'Settings > Widgets' })
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects a manualSetting without <Case>' -TestCases @(
        @{ Case = 'Spanish'; Value = [pscustomobject]@{ en = 'Settings' }; Missing = 'manualSetting.es' }
        @{ Case = 'English'; Value = [pscustomobject]@{ es = 'Configuracion'; en = ' ' }; Missing = 'manualSetting.en' }
        @{ Case = 'languages'; Value = 'Settings'; Missing = 'manualSetting.es' }
    ) {
        $tweak = New-TestTweak
        $tweak | Add-Member -NotePropertyName manualSetting -NotePropertyValue $Value
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape("is missing $Missing"))
    }
}

Describe 'Test-TuneupTweak signOutRequired' {
    It 'accepts a tweak without signOutRequired and one with a boolean' {
        $tweak = New-TestTweak
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -BeNullOrEmpty
        $tweak | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $true
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects a signOutRequired that is not a boolean (<Value>)' -TestCases @(
        @{ Value = 'yes' }
        @{ Value = 1 }
        @{ Value = $null }
    ) {
        param($Value)
        $tweak = New-TestTweak
        $tweak | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $Value
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'signOutRequired must be true or false'
    }
}
