BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:PluginRoot = Join-Path $Repo 'plugins\windows-tuneup'
    $script:SkillRoot = Join-Path $PluginRoot 'skills\windows-tuneup'
    $script:Utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    function Read-RepoText([string]$Path) { [System.IO.File]::ReadAllText($Path, $Utf8) }
    function Read-RepoJson([string]$Path) { Read-RepoText $Path | ConvertFrom-Json }
}

Describe 'Plugin marketplace and manifest' {
    BeforeAll {
        $script:Marketplace = Read-RepoJson (Join-Path $Repo '.claude-plugin\marketplace.json')
        $script:Manifest = Read-RepoJson (Join-Path $PluginRoot '.claude-plugin\plugin.json')
    }

    It 'lists one plugin, windows-tuneup, from ./plugins/windows-tuneup' {
        $Marketplace.name | Should -Be 'windows-tuneup'
        $Marketplace.owner.name | Should -Be 'edgarlugo'
        $Marketplace.description | Should -Not -BeNullOrEmpty
        @($Marketplace.plugins).Count | Should -Be 1
        $entry = $Marketplace.plugins[0]
        $entry.name | Should -Be 'windows-tuneup'
        $entry.source | Should -Be './plugins/windows-tuneup'
        $entry.description | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $Repo ($entry.source.Substring(2) -replace '/', '\')) -PathType Container | Should -BeTrue
    }

    It 'names the plugin like its marketplace entry, with the metadata of the repository' {
        $Manifest.name | Should -Be $Marketplace.plugins[0].name
        $Manifest.description | Should -Not -BeNullOrEmpty
        $Manifest.author.name | Should -Be 'edgarlugo'
        $Manifest.license | Should -Be 'MIT'
        $Manifest.homepage | Should -Be 'https://github.com/edgarlugo/windows-tuneup'
        $Manifest.repository | Should -Be 'https://github.com/edgarlugo/windows-tuneup'
        @($Manifest.keywords).Count | Should -BeGreaterThan 0
    }

    It 'carries the version of the tool in the manifest and in the marketplace entry' {
        $Manifest.version | Should -Be (Get-TuneupVersion)
        $Marketplace.plugins[0].version | Should -Be (Get-TuneupVersion)
    }

    It 'has no e-mail address in the marketplace or in any file of the plugin' {
        $files = @(Get-Item -LiteralPath (Join-Path $Repo '.claude-plugin\marketplace.json')) + @(Get-ChildItem -LiteralPath $PluginRoot -Recurse -File -Force)
        foreach ($file in $files) {
            Read-RepoText $file.FullName | Should -Not -Match '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+' -Because $file.FullName
        }
    }

    It 'does not use a name that Claude Code keeps for Anthropic' {
        foreach ($name in $Marketplace.name, $Manifest.name) { $name | Should -Not -Match '(?i)(^|-)(claude|anthropic)(-|$)' }
    }
}
