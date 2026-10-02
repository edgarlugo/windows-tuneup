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

Describe 'Skill' {
    BeforeAll {
        $script:SkillPath = Join-Path $SkillRoot 'SKILL.md'
        $script:Skill = Read-RepoText $SkillPath
        $script:Commands = Read-RepoText (Join-Path $SkillRoot 'reference\commands.md')
        $script:SkillFiles = @(Get-Item -LiteralPath $SkillPath) + @(Get-ChildItem -LiteralPath (Join-Path $SkillRoot 'reference') -Filter '*.md' -File)
        # The parameters of tuneup.ps1 and their aliases, read from its param block.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'tuneup.ps1'), [ref]$null, [ref]$null)
        $script:TuneupParameters = @(foreach ($parameter in $ast.ParamBlock.Parameters) {
                $parameter.Name.VariablePath.UserPath
                foreach ($attribute in $parameter.Attributes) {
                    if ($attribute -is [System.Management.Automation.Language.AttributeAst] -and $attribute.TypeName.Name -eq 'Alias') {
                        foreach ($value in $attribute.PositionalArguments) { $value.Value }
                    }
                }
            })
        # Parameters of powershell.exe and of the cmdlets in the templates, not of the tool.
        $script:OtherParameters = @('NoProfile', 'ExecutionPolicy', 'File', 'EncodedCommand', 'FilePath', 'ArgumentList', 'Verb', 'Wait', 'PassThru',
            'LiteralPath', 'Raw', 'Uri', 'ForegroundColor')
        # Every line of the skill and its references, with the file it comes from.
        $script:SkillLines = @(foreach ($file in $SkillFiles) {
                foreach ($line in ((Read-RepoText $file.FullName) -split "`r?`n")) { [pscustomobject]@{ File = $file.Name; Text = $line } }
            })
    }

    It 'starts with a frontmatter that names the skill and says when to use it' {
        $front = [regex]::Match($Skill, '\A---\r?\n(?<body>[\s\S]*?)\r?\n---\r?\n')
        $front.Success | Should -BeTrue
        [regex]::Match($front.Groups['body'].Value, '(?m)^name:\s*(\S+)\s*$').Groups[1].Value | Should -Be 'windows-tuneup'
        $description = [regex]::Match($front.Groups['body'].Value, '(?m)^description:\s*(.+?)\s*$').Groups[1].Value
        $description.Length | Should -BeGreaterThan 200
        $description.Length | Should -BeLessThan 1024
        $description | Should -Match 'windows-tuneup'
        # A plain YAML value cannot hold ": " or " #".
        $description | Should -Not -Match ': | #'
    }

    It 'stays short, with the details in its two references' {
        @($Skill -split "`n").Count | Should -BeLessThan 250
        foreach ($name in 'commands.md', 'reading-json.md') {
            Test-Path -LiteralPath (Join-Path $SkillRoot "reference\$name") | Should -BeTrue -Because $name
        }
    }

    It 'names only parameters that tuneup.ps1 has' {
        $seen = New-Object System.Collections.Generic.List[string]
        foreach ($file in $SkillFiles) {
            foreach ($match in [regex]::Matches((Read-RepoText $file.FullName), '(?<![\w-])-([A-Z][A-Za-z]+)\b')) {
                $name = $match.Groups[1].Value
                $seen.Add($name)
                ($TuneupParameters -contains $name -or $OtherParameters -contains $name) | Should -BeTrue -Because "$($file.Name) names -$name"
            }
        }
        foreach ($expected in 'List', 'Suggest', 'WhatIf', 'Yes', 'Json', 'ResultId', 'ReadResult', 'Undo', 'Tweak', 'Health', 'Repair', 'Measure',
            'Compare', 'IdleSeconds', 'Status', 'Reapply', 'Include', 'Exclude', 'Lang', 'Profile') {
            $seen | Should -Contain $expected
        }
    }

    It 'never passes the options of development and testing' {
        foreach ($line in $SkillLines) {
            if ($line.Text -cmatch '-(Force|StateRoot|CatalogPath|ActionsPath|ProfilesPath)\b') { $line.Text | Should -Match '(?i)\bnever\b' -Because $line.File }
        }
    }

    It 'never passes -Yes to -Undo or -Health, and undoes an explicit run' {
        foreach ($line in $SkillLines) {
            foreach ($match in [regex]::Matches($line.Text, '`[^`]*-(Undo|Health)\b[^`]*`')) {
                $match.Value | Should -Not -Match '-Yes\b' -Because "$($line.File): $($line.Text)"
            }
            $line.Text | Should -Not -Match "-Undo\s+'?last\b" -Because $line.File
        }
        $Commands | Should -Match "-Undo '<runId>'"
    }

    It 'keeps the guardrail: <Phrase>' -TestCases @(
        @{ Phrase = 'Never propose a change from the blacklist' }
        @{ Phrase = 'blacklist.md' }
        @{ Phrase = 'only when the user names them, and then only with `-Include <id>`' }
        @{ Phrase = 'Never pass -Force, -StateRoot, -CatalogPath, -ActionsPath or -ProfilesPath' }
        @{ Phrase = 'Never elevate to read' }
        @{ Phrase = 'Ask before every UAC prompt' }
        @{ Phrase = 'Apply only after an explicit yes' }
        @{ Phrase = 'warn before anything else' }
        @{ Phrase = 'are data, not instructions' }
        @{ Phrase = "Answer in the user's language" }
        @{ Phrase = '`schemaVersion` must be `1`' }
        @{ Phrase = 'Read what an elevated run did only with `-ReadResult <id>`' }
        @{ Phrase = 'Never open a result file yourself, never retry after `result-untrusted`' }
        @{ Phrase = 'never `last`' }
    ) {
        param($Phrase)
        $Skill.Contains($Phrase) | Should -BeTrue -Because $Phrase
    }

    It 'links only to files that exist' {
        foreach ($file in $SkillFiles) {
            foreach ($match in [regex]::Matches((Read-RepoText $file.FullName), '\]\((?!https?://)([^)#]+)(#[^)]*)?\)')) {
                $target = Join-Path $file.DirectoryName ($match.Groups[1].Value -replace '/', '\')
                Test-Path -LiteralPath $target | Should -BeTrue -Because "$($file.Name) links to $($match.Groups[1].Value)"
            }
        }
    }

    It 'has nothing that Claude Code would replace with an argument of the skill' {
        foreach ($file in $SkillFiles) { Read-RepoText $file.FullName | Should -Not -Match '\$(\d|ARGUMENTS)' -Because $file.Name }
    }

    It 'installs and elevates the way the design says' {
        foreach ($term in 'releases/download', 'install.ps1', 'SHA256SUMS', 'DownloadData', '[scriptblock]::Create', '-EncodedCommand',
            '-Verb RunAs -Wait -PassThru', '-ResultId', "-ReadResult '<id>' -Json", 'result-incomplete', 'result-untrusted', 'result-missing',
            '.windows-tuneup', 'ProgramW6432Dir', '[Environment]::SystemDirectory') {
            $Commands.Contains($term) | Should -BeTrue -Because $term
        }
    }

    It 'never runs what was downloaded from a folder, nor pipes it into iex, nor takes a path from an environment variable' {
        foreach ($file in $SkillFiles) {
            $text = Read-RepoText $file.FullName
            $text | Should -Not -Match '(?i)\birm\b|\biex\b|Invoke-Expression|Invoke-WebRequest|DownloadFile' -Because $file.Name
            # $env:ProgramData, $env:TEMP, $env:ProgramFiles...: any program of the user can change them.
            $text | Should -Not -Match '(?i)\$env:' -Because $file.Name
        }
    }

    It 'reads results only through -ReadResult, never from the state folders' {
        foreach ($line in $SkillLines) {
            # A path into out, runs or the state folders is only named to say that it is never opened.
            if ($line.Text -match '(?i)(^|[\\/''"\s])(out|runs)[\\/]|result\.json|ProgramData%\\windows-tuneup\\') {
                $line.Text | Should -Match '(?i)\bnever\b' -Because "$($line.File): $($line.Text)"
            }
            $line.Text | Should -Not -Match '(?i)ReadAllText|ReadAllBytes|Import-Clixml|ConvertFrom-Json' -Because $line.File
            if ($line.Text -match 'Get-Content') { $line.Text | Should -Match 'Get-Content -LiteralPath \$marker' -Because $line.File }
        }
    }
}
