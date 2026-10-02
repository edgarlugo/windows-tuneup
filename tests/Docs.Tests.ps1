BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    $script:Profiles = @(Import-TuneupProfileSet -Path (Join-Path $Repo 'profiles'))
    function Get-DocText([string]$Lang, [string]$Name) {
        [System.IO.File]::ReadAllText((Join-Path $Repo "docs\$Lang\$Name"), (New-Object System.Text.UTF8Encoding -ArgumentList $false))
    }
}

Describe 'Blacklist' {
    It 'explains the cases of the design and of the research in both languages' {
        $terms = @('Defender', 'SmartScreen', 'Windows Update', 'WinRE', '/ResetBase', 'Spectre', 'PagingFiles', 'hosts',
            'SvcHostSplitThresholdInKB', 'NetworkThrottlingIndex', 'HPET', 'SharedAccess', 'OneDrive', 'CBS', 'WerSvc', 'Spooler')
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'blacklist.md'
            foreach ($term in $terms) { $text.Contains($term) | Should -BeTrue -Because "$lang $term" }
        }
    }
}

Describe 'Measuring guide' {
    It 'gives the commands of the method and the LTSC edition in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'measuring.md'
            foreach ($term in '-Measure -IdleSeconds 120', '-Compare last', '-Profile lite -Yes', 'LTSC 2024', 'reagentc /info', '-Undo last') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }
}

Describe 'Virtual machine checklist' {
    It 'covers what Windows Sandbox cannot, in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'vm-checklist.md'
            foreach ($term in 'Start-E2E.ps1', 'install.ps1', 'winget', 'apps.onedrive', 'onedrive-known-folders', 'Ctrl+C', '-Measure -IdleSeconds 120', '-Undo last', 'measuring.md') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }
}

Describe 'Skill checklist' {
    It 'covers installing the plugin, the modes, undo, a declined UAC prompt, reading results and a managed PC, in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'skill-checklist.md'
            foreach ($term in '/plugin marketplace add edgarlugo/windows-tuneup', 'windows-tuneup@windows-tuneup', 'install.ps1', 'SHA256SUMS', '-Suggest -Json',
                '-ResultId', '-Undo <runId>', 'UAC', 'MS DM Server', 'blacklist.md', 'gaming.memory-integrity-off', '-Health -Json', '-ReadResult <id> -Json',
                'result-incomplete', 'result-untrusted', 'result-missing', 'icacls', 'Get-Acl') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }
}

Describe 'Documentation in both languages' {
    It 'has <Name> in Spanish and English, in UTF-8 without a byte order mark' -TestCases @(
        @{ Name = 'blacklist.md' }
        @{ Name = 'profiles.md' }
        @{ Name = 'measuring.md' }
        @{ Name = 'catalog.md' }
        @{ Name = 'vm-checklist.md' }
        @{ Name = 'skill-checklist.md' }
    ) {
        param($Name)
        foreach ($lang in 'es', 'en') {
            $path = Join-Path $Repo "docs\$lang\$Name"
            Test-Path -LiteralPath $path | Should -BeTrue -Because "docs/$lang/$Name"
            $bytes = [System.IO.File]::ReadAllBytes($path)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because "docs/$lang/$Name"
        }
    }

    It 'only links to files that exist' {
        foreach ($lang in 'es', 'en') {
            foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Repo "docs\$lang") -Filter '*.md' -File) {
                $text = Get-DocText $lang $file.Name
                foreach ($match in [regex]::Matches($text, '\]\((?!https?://)([^)#]+)(#[^)]*)?\)')) {
                    $target = Join-Path $file.DirectoryName ($match.Groups[1].Value -replace '/', '\')
                    Test-Path -LiteralPath $target | Should -BeTrue -Because "$lang/$($file.Name) links to $($match.Groups[1].Value)"
                }
            }
        }
    }
}

Describe 'Profile guide' {
    It 'describes every profile with its id' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'profiles.md'
            foreach ($profileData in $Profiles) { $text.Contains("(``$($profileData.id)``") | Should -BeTrue -Because "$lang $($profileData.id)" }
        }
    }

    It 'names every tweak that asks first in the profiles that include it' {
        $ask = @($Catalog | Where-Object { $_.ask } | ForEach-Object { $_.id })
        $included = @($Profiles | ForEach-Object { @($_.include) } | Where-Object { $ask -contains $_ } | Sort-Object -Unique)
        $included.Count | Should -BeGreaterThan 0
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'profiles.md'
            foreach ($tweakId in $included) { $text.Contains("``$tweakId``") | Should -BeTrue -Because "$lang $tweakId" }
        }
    }

    It 'names every high-risk tweak and how to ask for it' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'profiles.md'
            foreach ($tweak in $Catalog | Where-Object { $_.risk -eq 'high' }) { $text.Contains("``$($tweak.id)``") | Should -BeTrue -Because "$lang $($tweak.id)" }
        }
    }
}
