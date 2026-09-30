BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Run state' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'creates distinct run folders within the same second' {
        $first = New-TuneupRun -StateRoot $Root
        $second = New-TuneupRun -StateRoot $Root
        $first.Id | Should -Not -Be $second.Id
        Test-Path -LiteralPath $second.Dir | Should -BeTrue
    }

    It 'keeps journal order and nested state' {
        $run = New-TuneupRun -StateRoot $Root
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak -Id 'test.one') -State ([pscustomobject]@{ exists = $true; value = 5 })
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak -Id 'test.two') -State ([pscustomobject]@{ exists = $false; value = $null })
        $entries = @(Read-TuneupJournal -Path $journal)
        ($entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one,test.two'
        $entries[0].state.value | Should -Be 5
        $entries[0].tweak.set.name | Should -Be 'Sample'
    }

    It 'writes JSON as UTF-8 without BOM' {
        $path = Join-Path $TestDrive 'x.json'
        Save-TuneupJson -Path $path -Object ([pscustomobject]@{ texto = 'configuracion' })
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be ([byte][char]'{')
    }

    It 'resolves last to the newest run that has a journal and was not undone' {
        $old = New-TuneupRun -StateRoot $Root
        Add-TuneupJournalEntry -Path (Join-Path $old.Dir 'snapshot.jsonl') -Tweak (New-TestTweak) -State $null
        $undone = New-TuneupRun -StateRoot $Root
        Add-TuneupJournalEntry -Path (Join-Path $undone.Dir 'snapshot.jsonl') -Tweak (New-TestTweak) -State $null
        Save-TuneupJson -Path (Join-Path $undone.Dir 'undone.json') -Object ([pscustomobject]@{ undoneAt = 'now' })
        New-TuneupRun -StateRoot $Root | Out-Null
        (Resolve-TuneupRun -StateRoot $Root -RunId 'last').Id | Should -Be $old.Id
    }

    It 'round trips an accented Spanish title in the journal' {
        $run = New-TuneupRun -StateRoot $Root
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        $title = 'Configuraci' + [char]0x00F3 + 'n de ' + [char]0x00F1 + 'and' + [char]0x00FA
        $tweak = New-TestTweak -Id 'test.accent'
        $tweak.title.es = $title
        Add-TuneupJournalEntry -Path $journal -Tweak $tweak -State $null
        $entries = @(Read-TuneupJournal -Path $journal)
        $entries[0].tweak.title.es | Should -BeExactly $title
        $bytes = [System.IO.File]::ReadAllBytes($journal)
        $bytes[0] | Should -Be ([byte][char]'{')
    }

    It 'round trips nested state four levels deep' {
        $run = New-TuneupRun -StateRoot $Root
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        $state = [pscustomobject]@{
            a = [pscustomobject]@{ b = [pscustomobject]@{ c = [pscustomobject]@{ d = 42; list = @(1, 2, 3) } } }
        }
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak) -State $state
        $entries = @(Read-TuneupJournal -Path $journal)
        $entries[0].state.a.b.c.d | Should -Be 42
        @($entries[0].state.a.b.c.list).Count | Should -Be 3
    }

    It 'ignores an incomplete last journal line with a warning' {
        $run = New-TuneupRun -StateRoot $Root
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak -Id 'test.one') -State $null
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak -Id 'test.two') -State $null
        [System.IO.File]::AppendAllText($journal, '{"id":"test.three","tweak":{"id":"te', (New-Object System.Text.UTF8Encoding -ArgumentList $false))
        $entries = @(Read-TuneupJournal -Path $journal -WarningVariable warned -WarningAction SilentlyContinue)
        $entries.Count | Should -Be 2
        ($entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one,test.two'
        @($warned).Count | Should -Be 1
        "$($warned[0])" | Should -BeLike 'Ignoring incomplete last journal line in *'
    }

    It 'throws when a middle journal line is corrupt' {
        $run = New-TuneupRun -StateRoot $Root
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak -Id 'test.one') -State $null
        [System.IO.File]::AppendAllText($journal, '{"id":"broken' + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak -Id 'test.three') -State $null
        { Read-TuneupJournal -Path $journal } | Should -Throw '*is corrupt at line 2*'
    }

    It 'ignores folders that are not runs' {
        $run = New-TuneupRun -StateRoot $Root
        $runsDir = Split-Path -Parent $run.Dir
        foreach ($name in 'notes', '20250101-000000-extra', '2025-01-01', 'zzz') {
            New-Item -ItemType Directory -Path (Join-Path $runsDir $name) | Out-Null
            Add-TuneupJournalEntry -Path (Join-Path $runsDir "$name\snapshot.jsonl") -Tweak (New-TestTweak) -State $null
        }
        $ids = @(Get-TuneupRunList -StateRoot $Root | ForEach-Object { $_.Id })
        $ids.Count | Should -Be 1
        $ids[0] | Should -Be $run.Id
        Resolve-TuneupRun -StateRoot $Root -RunId 'notes' | Should -BeNullOrEmpty
    }

    It 'resolves an explicit run id' {
        $first = New-TuneupRun -StateRoot $Root
        $second = New-TuneupRun -StateRoot $Root
        foreach ($run in $first, $second) {
            Add-TuneupJournalEntry -Path (Join-Path $run.Dir 'snapshot.jsonl') -Tweak (New-TestTweak) -State $null
        }
        (Resolve-TuneupRun -StateRoot $Root -RunId $first.Id).Dir | Should -Be $first.Dir
        Resolve-TuneupRun -StateRoot $Root -RunId '19990101-000000' | Should -BeNullOrEmpty
    }

    It 'picks the middle run when the newest of three is undone' {
        $runs = @(1..3 | ForEach-Object { New-TuneupRun -StateRoot $Root })
        foreach ($run in $runs) {
            Add-TuneupJournalEntry -Path (Join-Path $run.Dir 'snapshot.jsonl') -Tweak (New-TestTweak) -State $null
        }
        Save-TuneupJson -Path (Join-Path $runs[2].Dir 'undone.json') -Object ([pscustomobject]@{ undoneAt = 'now' })
        (Resolve-TuneupRun -StateRoot $Root -RunId 'last').Id | Should -Be $runs[1].Id
    }
}
