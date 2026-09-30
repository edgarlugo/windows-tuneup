BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:MachineTweak = New-TestMachineTweak
}

Describe 'Journal' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
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
}

Describe 'State roots' {
    It 'uses the user folder unless the machine folder is asked for' {
        Get-TuneupStateRoot | Should -Be (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'windows-tuneup')
        Get-TuneupStateRoot -Machine | Should -Be (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'windows-tuneup')
        Get-TuneupStateRoot -StateRoot 'D:\dev-state' -Machine | Should -Be 'D:\dev-state'
    }

    It 'classifies paths by the root they live in' {
        Get-TuneupRootKind -Path (Join-Path (Get-TuneupStateRoot -Machine) 'runs\20250101-000000\snapshot.jsonl') | Should -Be 'machine'
        Get-TuneupRootKind -Path (Join-Path (Get-TuneupStateRoot) 'runs\20250101-000000\snapshot.jsonl') | Should -Be 'user'
        Get-TuneupRootKind -Path ((Get-TuneupStateRoot -Machine) + '-other\runs') | Should -Be 'custom'
        Get-TuneupRootKind -Path (Join-Path $TestDrive 'runs') | Should -Be 'custom'
    }
}

Describe 'User journals' {
    BeforeEach {
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Journal = Join-Path $UserRoot 'runs\20250101-000000\snapshot.jsonl'
        New-Item -ItemType Directory -Path (Split-Path -Parent $Journal) -Force | Out-Null
    }

    It 'refuses to journal a <Name> in the user folder' -TestCases @(
        @{ Name = 'machine-scope tweak'; Scope = 'machine'; Type = 'registry'; Set = @{ path = 'HKLM:\Software\x'; name = 'A'; kind = 'DWord'; value = 1 } }
        @{ Name = 'user tweak on an HKLM path'; Scope = 'user'; Type = 'registry'; Set = @{ path = 'HKLM:\Software\x'; name = 'A'; kind = 'DWord'; value = 1 } }
        @{ Name = 'user service tweak'; Scope = 'user'; Type = 'service'; Set = @{ name = 'Spooler'; startType = 'Disabled'; stop = $true } }
    ) {
        $Tweak = New-TestTweak -Id 'test.refused' -Scope $Scope -Type $Type -Set ([pscustomobject]$Set)
        { Add-TuneupJournalEntry -Path $Journal -Tweak $Tweak -State $null -Root 'user' } |
            Should -Throw -ExpectedMessage "Cannot journal machine-scope tweak '$($Tweak.id)' in the user state folder"
        Test-Path -LiteralPath $Journal | Should -BeFalse
    }

    It 'journals a user-scope tweak in the user folder' {
        Add-TuneupJournalEntry -Path $Journal -Tweak (New-TestTweak) -State $null -Root 'user'
        @(Read-TuneupJournal -Path $Journal -Root 'user').Count | Should -Be 1
    }

    It 'skips machine-scope entries read from the user folder' {
        $liar = New-TestTweak -Id 'test.liar' -Set ([pscustomobject]@{ path = 'HKLM:\Software\x'; name = 'A'; kind = 'DWord'; value = 1 })
        $pathList = New-TestTweak -Id 'test.list' -Set ([pscustomobject]@{ path = @('HKCU:\Software\x', 'HKLM:\Software\x'); name = 'A'; kind = 'DWord'; value = 1 })
        foreach ($tweak in @($MachineTweak, $liar, $pathList, (New-TestTweak -Id 'test.good'))) {
            Add-TuneupJournalEntry -Path $Journal -Tweak $tweak -State $null -Root 'custom'
        }
        $entries = @(Read-TuneupJournal -Path $Journal -Root 'user' -WarningVariable warned -WarningAction SilentlyContinue)
        ($entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.good'
        @($warned).Count | Should -Be 3
        "$($warned[0])" | Should -BeLike "Ignoring machine-scope entry 'test.machine' in user journal *"
        @(Read-TuneupJournal -Path $Journal -Root 'custom').Count | Should -Be 4
    }
}

Describe 'Machine state files' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $script:MachineRoot = New-TestMachineRoot
        $script:Run = New-TuneupRun -Machine -MachineRoot $MachineRoot
        $script:Journal = Join-Path $Run.Dir 'snapshot.jsonl'
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'appends to the machine journal through a checked handle' {
        Add-TuneupJournalEntry -Path $Journal -Tweak $MachineTweak -State $null -Root 'machine'
        Add-TuneupJournalEntry -Path $Journal -Tweak (New-TestTweak) -State $null -Root 'machine'
        (@(Read-TuneupJournal -Path $Journal -Root 'machine') | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine,test.sample'
    }

    It 'refuses to append to or read a machine journal with a second hard link' {
        New-Item -ItemType HardLink -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -Value $Journal | Out-Null
        { Add-TuneupJournalEntry -Path $Journal -Tweak (New-TestTweak) -State $null -Root 'machine' } |
            Should -Throw -ExpectedMessage "State file $Journal is not trusted"
        { Read-TuneupJournal -Path $Journal -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }

    It 'refuses to read a machine journal that Everyone can write' {
        Grant-EveryoneWrite $Journal
        { Read-TuneupJournal -Path $Journal -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }

    It 'writes machine state files with the protected ACL and can replace them' {
        $path = Join-Path $Run.Dir 'undone.json'
        Save-TuneupJson -Path $path -Object ([pscustomobject]@{ undoneAt = 'first' }) -Root 'machine'
        Save-TuneupJson -Path $path -Object ([pscustomobject]@{ undoneAt = 'second' }) -Root 'machine'
        (Read-TuneupTrustedJson -Path $path -Root 'machine').undoneAt | Should -Be 'second'
        (Get-Acl -LiteralPath $path).AreAccessRulesProtected | Should -BeTrue
    }

    It 'cannot create machine state files without the right to create them' {
        Mock -ModuleName Tuneup New-TuneupSecureFile { throw [System.UnauthorizedAccessException]::new('Access denied') }
        { Save-TuneupJson -Path (Join-Path $Run.Dir 'undone.json') -Object ([pscustomobject]@{ undoneAt = 'now' }) -Root 'machine' } |
            Should -Throw -ExpectedMessage 'Access denied'
    }

    It 'reads a machine file while a writer holds it open' {
        Add-TuneupJournalEntry -Path $Journal -Tweak (New-TestTweak) -State $null -Root 'machine'
        $writer = [System.IO.FileStream]::new($Journal, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            @(Read-TuneupJournal -Path $Journal -Root 'machine').Count | Should -Be 1
        }
        finally {
            $writer.Dispose()
        }
    }

    It 'reports a locked machine file as in use, not as untrusted' {
        $path = Join-Path $Run.Dir 'run.json'
        $lock = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            Read-TuneupTrustedJson -Path $path -Root 'machine' -WarningVariable warned -WarningAction SilentlyContinue | Should -BeNullOrEmpty
            @($warned).Count | Should -Be 1
            "$($warned[0])" | Should -BeLike "State file $path is in use*"
            $failure = $null
            try { Read-TuneupStateFile -Path $path -Root 'machine' } catch { $failure = $_ }
            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception.GetBaseException() | Should -BeOfType [System.IO.IOException]
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'ignores untrusted machine files when asked to' {
        $path = Join-Path $Run.Dir 'result.json'
        Save-TuneupJson -Path $path -Root 'machine' -Object ([pscustomobject]@{ results = @('x') })
        @((Read-TuneupTrustedJson -Path $path -Root 'machine').results) -join ',' | Should -Be 'x'
        Grant-EveryoneWrite $path
        Read-TuneupTrustedJson -Path $path -Root 'machine' -WarningVariable warned -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$($warned[0])" | Should -BeLike "Ignoring untrusted state file $path"
        Read-TuneupStateFile -Path $path -Root 'machine' -IgnoreUntrusted -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        { Read-TuneupStateFile -Path $path -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }
}
