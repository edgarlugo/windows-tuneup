Describe 'Repository hygiene' {
    BeforeAll {
        $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    }

    It 'keeps PowerShell files ASCII so Windows PowerShell 5.1 reads them correctly' {
        $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' -and $_.FullName -notmatch '\\\.git\\' }
        $bad = foreach ($file in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            if ([Array]::Exists($bytes, [Predicate[byte]] { param($b) $b -gt 127 })) { $file.FullName }
        }
        ($bad -join ', ') | Should -BeNullOrEmpty
    }

    It 'has JSON files that parse' {
        $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.json' |
            Where-Object { $_.FullName -notmatch '\\\.git\\' }
        foreach ($file in $files) {
            { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Should -Not -Throw -Because $file.FullName
        }
    }
}
