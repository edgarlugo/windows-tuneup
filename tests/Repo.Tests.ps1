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

    It 'has no tab or other control character in Markdown, but in verbatim text blocks' {
        # A tab is usually a backslash eaten by an escape (.\tuneup.ps1 written as .<TAB>uneup.ps1). Only
        # a ```text block may hold one: it copies a log as it is (CBS.log separates its fields with tabs).
        $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.md' |
            Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|TestResults)\\' }
        $files.Count | Should -BeGreaterThan 5
        $bad = foreach ($file in $files) {
            $verbatim = $false
            $number = 0
            foreach ($line in ([System.IO.File]::ReadAllText($file.FullName) -split "`r?`n")) {
                $number++
                if ($line -match '^\s*```') { $verbatim = (-not $verbatim) -and ($line -match '^\s*```text\s*$'); continue }
                if (-not $verbatim -and $line -match '[\x00-\x09\x0B\x0C\x0E-\x1F\x7F]') { "$($file.FullName):$number" }
            }
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
