BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Excluded = Get-Content -LiteralPath (Join-Path $Repo 'catalog\notes\excluded.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    function Get-DocText([string]$Path) {
        [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding -ArgumentList $false)) -replace "`r`n", "`n"
    }
}

Describe 'Generated catalog documentation' {
    It 'is up to date with the catalog, the profiles and the notes (<Lang>)' -TestCases @(
        @{ Lang = 'es' }
        @{ Lang = 'en' }
    ) {
        param($Lang)
        $out = Join-Path $TestDrive 'docs'
        & (Join-Path $Repo 'build\catalog-doc.ps1') -OutDir $out | Out-Null
        $committed = Join-Path $Repo "docs\$Lang\catalog.md"
        Test-Path -LiteralPath $committed | Should -BeTrue
        (Get-DocText (Join-Path $out "$Lang\catalog.md")) -ceq (Get-DocText $committed) |
            Should -BeTrue -Because 'docs/*/catalog.md must be regenerated with build/catalog-doc.ps1 after changing the catalog'
    }

    It 'lists every tweak of the catalog' {
        $text = Get-DocText (Join-Path $Repo 'docs\en\catalog.md')
        foreach ($tweak in $Catalog) { $text.Contains("### ``$($tweak.id)``") | Should -BeTrue -Because $tweak.id }
    }

    It 'writes the pages in UTF-8 without a byte order mark' {
        foreach ($lang in 'es', 'en') {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Repo "docs\$lang\catalog.md"))
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because $lang
        }
    }
}

Describe 'Notes on what is not included' {
    It 'explains every group and item in both languages' {
        foreach ($group in $Excluded.groups) {
            foreach ($lang in 'es', 'en') {
                [string]$group.title.$lang | Should -Not -BeNullOrEmpty -Because "$($group.id) title.$lang"
                [string]$group.intro.$lang | Should -Not -BeNullOrEmpty -Because "$($group.id) intro.$lang"
                foreach ($item in $group.items) {
                    $name = $(if ($item.name -is [string]) { $item.name } else { $item.name.$lang })
                    [string]$name | Should -Not -BeNullOrEmpty -Because "$($group.id) name.$lang"
                    [string]$item.why.$lang | Should -Not -BeNullOrEmpty -Because "$name why.$lang"
                }
            }
        }
    }

    It 'explains the Xbox services, the Home policies, the dropped actions and the apps without undo that were left out' {
        $ids = @($Excluded.groups | ForEach-Object { $_.id })
        foreach ($groupId in 'apps-no-undo', 'services-xbox', 'home-policies', 'actions-dropped') { $ids | Should -Contain $groupId }
        $services = @($Excluded.groups | Where-Object { $_.id -eq 'services-xbox' } | ForEach-Object { $_.items } | ForEach-Object { $_.name })
        ($services | Sort-Object) -join ',' | Should -Be 'XblAuthManager,XblGameSave,XboxNetApiSvc'
        $catalogServices = @($Catalog | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        foreach ($name in $services) { $catalogServices | Should -Not -Contain $name }
        $dropped = @($Excluded.groups | Where-Object { $_.id -eq 'actions-dropped' } | ForEach-Object { $_.items } | ForEach-Object { $_.name.en })
        ($dropped -join '|').Contains('power-mode-overlay') | Should -BeTrue
        ($dropped -join '|').Contains('dev-defender-performance-mode') | Should -BeTrue
    }

    It 'never lists an app that the catalog removes' {
        $removed = @($Catalog | Where-Object { $_.type -eq 'appx' } | ForEach-Object { [string]$_.set.name })
        foreach ($item in $Excluded.groups.items | Where-Object { $_.appx }) {
            $removed | Should -Not -Contain $item.appx -Because $item.name
        }
    }
}
