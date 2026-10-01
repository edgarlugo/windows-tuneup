BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:OtherSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001'
    $script:MeSid = Get-TestCurrentSid
    $script:MachineTweak = New-TestMachineTweak
}

Describe 'Run folders' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'creates distinct run folders within the same second' {
        $first = New-TuneupRun -StateRoot $Root
        $second = New-TuneupRun -StateRoot $Root
        $first.Id | Should -Not -Be $second.Id
        Test-Path -LiteralPath $second.Dir | Should -BeTrue
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

    It 'does not resolve a run whose journal is still empty' {
        $old = New-TuneupRun -StateRoot $Root
        Add-TuneupJournalEntry -Path (Join-Path $old.Dir 'snapshot.jsonl') -Tweak (New-TestTweak) -State $null
        $empty = New-TuneupRun -StateRoot $Root
        [System.IO.File]::WriteAllText((Join-Path $empty.Dir 'snapshot.jsonl'), '')
        (Resolve-TuneupRun -StateRoot $Root -RunId 'last').Id | Should -Be $old.Id
        Resolve-TuneupRun -StateRoot $Root -RunId $empty.Id | Should -BeNullOrEmpty
    }

    It 'tags runs from an explicit state root as custom' {
        $run = New-TuneupRun -StateRoot $Root
        $run.Root | Should -Be 'custom'
        (@(Get-TuneupRunList -StateRoot $Root))[0].Root | Should -Be 'custom'
    }

    It 'records who made the run in run.json' {
        $run = New-TuneupRun -StateRoot $Root
        $run.UserSid | Should -Be $MeSid
        $info = Get-Content -LiteralPath (Join-Path $run.Dir 'run.json') -Raw | ConvertFrom-Json
        $info.schemaVersion | Should -Be 1
        $info.userSid | Should -Be $MeSid
        $info.machine | Should -BeFalse
        $info.createdAt | Should -Not -BeNullOrEmpty
        (@(Get-TuneupRunList -StateRoot $Root))[0].UserSid | Should -Be $MeSid
    }

    It 'warns that -StateRoot disables hardening when elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        New-TuneupRun -StateRoot $Root -WarningVariable created -WarningAction SilentlyContinue | Out-Null
        Get-TuneupRunList -StateRoot $Root -WarningVariable listed -WarningAction SilentlyContinue | Out-Null
        foreach ($warned in @($created), @($listed)) {
            $warned.Count | Should -Be 1
            "$($warned[0])" | Should -Be '-StateRoot disables state-folder hardening; use only for testing'
        }
    }

    It 'does not warn about -StateRoot when not elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        New-TuneupRun -StateRoot $Root -WarningVariable created -WarningAction SilentlyContinue | Out-Null
        @($created).Count | Should -Be 0
    }
}

Describe 'Machine runs' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $script:MachineRoot = New-TestMachineRoot
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'needs an elevated process' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        { New-TuneupRun -Machine -MachineRoot $MachineRoot } | Should -Throw -ExpectedMessage '*elevated*'
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
    }

    It 'creates the run folder, journal and run.json with the protected ACL' {
        $run = New-TuneupRun -Machine -MachineRoot $MachineRoot
        $run.Root | Should -Be 'machine'
        $run.UserSid | Should -Be $MeSid
        $run.Dir | Should -Be (Join-Path $MachineRoot "runs\$($run.Id)")
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        (Get-Item -LiteralPath $journal).Length | Should -Be 0
        foreach ($path in $run.Dir, $journal, (Join-Path $run.Dir 'run.json')) {
            $acl = Get-Acl -LiteralPath $path
            $acl.AreAccessRulesProtected | Should -BeTrue -Because $path
            $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $MeSid -Because $path
            @(Get-TestAccessRule $acl | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-4' }).Count | Should -Be 1 -Because $path
        }
        $info = Read-TuneupTrustedJson -Path (Join-Path $run.Dir 'run.json') -Root 'machine'
        $info.userSid | Should -Be $MeSid
        $info.machine | Should -BeTrue
        $info.schemaVersion | Should -Be 1
        $listed = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot (Join-Path $TestDrive 'none'))
        "$($listed[0].Id)/$($listed[0].Root)/$($listed[0].UserSid)" | Should -Be "$($run.Id)/machine/$MeSid"
    }

    It 'writes new runs to the user folder when not elevated' {
        $userRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $run = New-TuneupRun -UserRoot $userRoot -MachineRoot $MachineRoot
        $run.Root | Should -Be 'user'
        $run.Dir | Should -Be (Join-Path $userRoot "runs\$($run.Id)")
        Test-Path -LiteralPath (Join-Path $run.Dir 'snapshot.jsonl') | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $run.Dir 'run.json') -Raw | ConvertFrom-Json).machine | Should -BeFalse
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
    }
}

Describe 'Trusted runs' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        $script:MachineRoot = New-TestMachineRoot
        Initialize-TuneupStateRoot -Path $MachineRoot
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'skips a planted machine run and resolves the last trusted one' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $good = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        $planted = New-RunFolder -Root $MachineRoot -Id '20250101-000001' -Tweaks @($MachineTweak)
        Grant-EveryoneWrite (Join-Path $planted 'snapshot.jsonl')
        $runs = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue)
        ($runs | ForEach-Object { $_.Id }) -join ',' | Should -Be '20250101-000000'
        "$($warned[0])" | Should -BeLike "Ignoring untrusted run $planted*"
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last' -WarningAction SilentlyContinue).Dir | Should -Be $good
    }

    It 'skips a machine run folder owned by a user' {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        $planted = New-RunFolder -Root $MachineRoot -Id '20250101-000001'
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter {
            $LiteralPath -eq $planted
        }
        $ids = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningAction SilentlyContinue | ForEach-Object { $_.Id })
        $ids -join ',' | Should -Be '20250101-000000'
    }

    It 'ignores the whole machine folder when <Name> is not trusted' -TestCases @(
        @{ Name = 'its runs folder'; Leaf = 'runs' }
        @{ Name = 'the folder that holds it'; Leaf = '..' }
    ) {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        $target = [System.IO.Path]::GetFullPath((Join-Path $MachineRoot $Leaf))
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter {
            $LiteralPath -eq $target
        }
        @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0
        "$($warned[0])" | Should -Be "Ignoring untrusted state folder $target"
    }

    It 'ignores run markers and run info that are not trusted' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        Save-TuneupJson -Path (Join-Path $dir 'undone.json') -Root 'custom' -Object ([pscustomobject]@{ undoneAt = 'now' })
        [System.IO.File]::WriteAllText((Join-Path $dir 'undone-tweaks.txt'), "test.sample`r`n")
        foreach ($name in 'undone.json', 'undone-tweaks.txt', 'run.json') { Grant-EveryoneWrite (Join-Path $dir $name) }
        $run = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue)[0]
        $run.Undone | Should -BeFalse
        $run.UserSid | Should -BeNullOrEmpty
        @($warned | Where-Object { "$_" -like 'Ignoring untrusted state file *' }).Count | Should -Be 2
        @(Get-TuneupUndoneTweakId -Run $run -WarningAction SilentlyContinue).Count | Should -Be 0
    }

    It 'reads trusted run markers and run info' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        Save-TuneupJson -Path (Join-Path $dir 'undone.json') -Root 'custom' -Object ([pscustomobject]@{ undoneAt = 'now' })
        [System.IO.File]::WriteAllText((Join-Path $dir 'undone-tweaks.txt'), "test.one`r`ntest.two`r`n")
        $run = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot)[0]
        $run.Undone | Should -BeTrue
        $run.UserSid | Should -Be $MeSid
        @(Get-TuneupUndoneTweakId -Run $run) -join ',' | Should -Be 'test.one,test.two'
    }

    It 'lists a run whose run.json is locked and says it is in use' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        $lock = [System.IO.FileStream]::new((Join-Path $dir 'run.json'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $runs = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue)
        }
        finally {
            $lock.Dispose()
        }
        $runs.Count | Should -Be 1
        $runs[0].UserSid | Should -BeNullOrEmpty
        @($warned).Count | Should -Be 1
        "$($warned[0])" | Should -BeLike '*is in use*'
    }
}

Describe 'Runs of other users' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        $script:MachineRoot = New-TestMachineRoot
        Initialize-TuneupStateRoot -Path $MachineRoot
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'skips user-scope entries of a run made by another user' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak, (New-TestTweak)) -UserSid $OtherSid
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'machine'; UserSid = $OtherSid }
        $journal = Get-TuneupRunJournal -Run $run -WarningVariable warned -WarningAction SilentlyContinue
        ($journal.Entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine'
        @($journal.Skipped) -join ',' | Should -Be 'test.sample'
        (@($journal.SkippedEntries) | ForEach-Object { $_.tweak.id }) -join ',' | Should -Be 'test.sample'
        "$($warned[0])" | Should -BeLike "Ignoring user-scope entry 'test.sample' of run 20250101-000000*"
        (@(Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine'
    }

    It 'skips the Store app entry whose copy belongs to another user' {
        $appx = New-TestTweak -Id 'test.appx' -Type 'appx' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak)
        $states = @(
            @{ id = 'mine'; state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; currentUserSid = $MeSid; otherUsers = 0; provisioned = $false } }
            @{ id = 'other'; state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; currentUserSid = $OtherSid; otherUsers = 0; provisioned = $false } }
            @{ id = 'nobody'; state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $false; currentUserSid = $null; otherUsers = 2; provisioned = $true } }
            @{ id = 'old'; state = [pscustomobject]@{ installedUsers = $true; provisioned = $false } }
        )
        foreach ($item in $states) {
            $tweak = New-TestTweak -Id "test.appx-$($item.id)" -Type 'appx' -Scope 'machine' -Set $appx.set
            Add-TuneupJournalEntry -Path (Join-Path $dir 'snapshot.jsonl') -Tweak $tweak -State $item.state -Root 'custom'
        }
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'machine'; UserSid = $MeSid }
        $journal = Get-TuneupRunJournal -Run $run -WarningVariable warned -WarningAction SilentlyContinue
        ($journal.Entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine,test.appx-mine,test.appx-nobody,test.appx-old'
        @($journal.Skipped) -join ',' | Should -Be 'test.appx-other'
        (@($journal.SkippedEntries) | ForEach-Object { $_.tweak.id }) -join ',' | Should -Be 'test.appx-other'
        "$($warned[0])" | Should -BeLike "Ignoring appx entry 'test.appx-other' of run 20250101-000000*belongs to another user*"
    }

    It 'skips any entry whose state says it belongs to another user, an action too' {
        $action = New-TestTweak -Id 'test.action' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'fixture-toggle' })
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak)
        $states = @(
            @{ id = 'mine'; state = [pscustomobject]@{ value = 1; currentUserSid = $MeSid } }
            @{ id = 'other'; state = [pscustomobject]@{ value = 1; currentUserSid = $OtherSid } }
            @{ id = 'nobody'; state = [pscustomobject]@{ value = 1; currentUserSid = $null } }
            @{ id = 'old'; state = [pscustomobject]@{ value = 1 } }
        )
        foreach ($item in $states) {
            $tweak = New-TestTweak -Id "test.action-$($item.id)" -Type 'action' -Scope 'machine' -Set $action.set
            Add-TuneupJournalEntry -Path (Join-Path $dir 'snapshot.jsonl') -Tweak $tweak -State $item.state -Root 'custom'
        }
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'machine'; UserSid = $MeSid }
        $journal = Get-TuneupRunJournal -Run $run -WarningVariable warned -WarningAction SilentlyContinue
        ($journal.Entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine,test.action-mine,test.action-nobody,test.action-old'
        @($journal.Skipped) -join ',' | Should -Be 'test.action-other'
        "$($warned[0])" | Should -BeLike "Ignoring action entry 'test.action-other' of run 20250101-000000*belongs to another user*"
        (& (Get-Module Tuneup) { param($e, $s) Test-TuneupEntryOfOtherUser -Entry $e -CurrentSid $s } $journal.SkippedEntries[0] $MeSid) | Should -BeTrue
    }

    It 'does not resolve last, when elevated, to a run whose action entry belongs to another user' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $action = New-TestTweak -Id 'test.action' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'fixture-toggle' })
        $mine = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak)
        $theirs = New-RunFolder -Root $MachineRoot -Id '20250101-000001' -Tweaks @() -UserSid $OtherSid
        Add-TuneupJournalEntry -Path (Join-Path $theirs 'snapshot.jsonl') -Tweak $action -State ([pscustomobject]@{ value = 1; currentUserSid = $OtherSid }) -Root 'custom'
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last' -WarningAction SilentlyContinue).Dir | Should -Be $mine
    }

    It 'keeps every entry of a run made by the current user' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak, (New-TestTweak))
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'machine'; UserSid = $MeSid }
        $journal = Get-TuneupRunJournal -Run $run
        @($journal.Entries).Count | Should -Be 2
        @($journal.Skipped).Count | Should -Be 0
    }

    It 'skips user-scope entries when a custom run does not say who made it' {
        $dir = New-RunFolder -Root $UserRoot -Id '20250101-000000'
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'custom'; UserSid = $null }
        @(Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue).Count | Should -Be 0
    }

    It 'treats a user-folder run without run.json as the current user''s' {
        $dir = New-RunFolder -Root $UserRoot -Id '20250101-000000'
        Remove-Item -LiteralPath (Join-Path $dir 'run.json')
        (@(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot))[0].UserSid | Should -Be $MeSid
    }

    It 'never resolves last to a machine run when not elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last' | Should -BeNullOrEmpty
        New-RunFolder -Root $UserRoot -Id '20240101-000000' | Out-Null
        New-RunFolder -Root $UserRoot -Id '20240102-000000' -UserSid $OtherSid | Out-Null
        $last = Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last' -WarningAction SilentlyContinue
        "$($last.Id)/$($last.Root)" | Should -Be '20240101-000000/user'
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId '20250101-000000').Root | Should -Be 'machine'
    }

    It 'resolves last, when elevated, to runs that do not hold another user''s HKCU values' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000001' -UserSid $OtherSid | Out-Null
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last').Id | Should -Be '20250101-000000'
        New-RunFolder -Root $MachineRoot -Id '20250101-000002' -Tweaks @($MachineTweak) -UserSid $OtherSid | Out-Null
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last').Id | Should -Be '20250101-000002'
        New-RunFolder -Root $UserRoot -Id '20250101-000003' | Out-Null
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last').Root | Should -Be 'user'
    }

    It 'needs elevation to undo a machine run, even one of the same user' {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        $run = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot)[0]
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        { Assert-TuneupRunUndoable -Run $run } | Should -Throw -ExpectedMessage '*needs an elevated process'
        Mock -ModuleName Tuneup New-TuneupSecureFile { throw [System.UnauthorizedAccessException]::new('Access denied') }
        { Save-TuneupJson -Path (Join-Path $run.Dir 'undone.json') -Root 'machine' -Object ([pscustomobject]@{ undoneAt = 'now' }) } |
            Should -Throw -ExpectedMessage 'Access denied'
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        { Assert-TuneupRunUndoable -Run $run } | Should -Not -Throw
        { Assert-TuneupRunUndoable -Run ([pscustomobject]@{ Id = 'x'; Root = 'user' }) } | Should -Not -Throw
    }
}

Describe 'Merged run list' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        $script:MachineRoot = New-TestMachineRoot
        Initialize-TuneupStateRoot -Path $MachineRoot
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'merges both roots sorted by id and tags each run' {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        New-RunFolder -Root $UserRoot -Id '20250101-000000-02' | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000001' | Out-Null
        New-RunFolder -Root $UserRoot -Id '20250102-000000' | Out-Null
        $runs = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot)
        ($runs | ForEach-Object { "$($_.Id)/$($_.Root)" }) -join ',' |
            Should -Be '20250101-000000/machine,20250101-000000-02/user,20250101-000001/machine,20250102-000000/user'
        $runs[1].Dir | Should -Be (Join-Path $UserRoot 'runs\20250101-000000-02')
    }

    It 'resolves last and explicit ids across both roots when elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        New-RunFolder -Root $UserRoot -Id '20250101-000000' | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000001' | Out-Null
        $last = Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last'
        "$($last.Id)/$($last.Root)" | Should -Be '20250101-000001/machine'
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId '20250101-000000').Root | Should -Be 'user'
    }

    It 'lists the user root alone when the machine root does not exist' {
        $missing = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-RunFolder -Root $UserRoot -Id '20250101-000000' | Out-Null
        (@(Get-TuneupRunList -MachineRoot $missing -UserRoot $UserRoot) | ForEach-Object { $_.Root }) -join ',' | Should -Be 'user'
    }
}
