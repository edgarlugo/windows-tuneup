BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:AdminSid = 'S-1-5-32-544'
    function New-OwnedSecurity([string]$Sid) {
        $security = New-Object System.Security.AccessControl.DirectorySecurity
        $security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid))
        $security
    }
    function New-RunFolder([string]$Root, [string]$Id, [object[]]$Tweaks = @((New-TestTweak))) {
        $dir = Join-Path $Root "runs\$Id"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($tweak in $Tweaks) {
            Add-TuneupJournalEntry -Path (Join-Path $dir 'snapshot.jsonl') -Tweak $tweak -State $null -Root 'custom'
        }
        $dir
    }
    $script:MachineTweak = New-TestTweak -Id 'test.machine' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = 'HKLM:\Software\windows-tuneup-test'; name = 'Sample'; kind = 'DWord'; value = 1 })
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
}

Describe 'State roots' {
    It 'uses the user folder unless the machine folder is asked for' {
        Get-TuneupStateRoot | Should -Be (Join-Path $env:LOCALAPPDATA 'windows-tuneup')
        Get-TuneupStateRoot -Machine | Should -Be (Join-Path $env:ProgramData 'windows-tuneup')
        Get-TuneupStateRoot -StateRoot 'D:\dev-state' -Machine | Should -Be 'D:\dev-state'
    }

    It 'classifies paths by the root they live in' {
        Get-TuneupRootKind -Path (Join-Path (Get-TuneupStateRoot -Machine) 'runs\20250101-000000\snapshot.jsonl') | Should -Be 'machine'
        Get-TuneupRootKind -Path (Join-Path (Get-TuneupStateRoot) 'runs\20250101-000000\snapshot.jsonl') | Should -Be 'user'
        Get-TuneupRootKind -Path ((Get-TuneupStateRoot -Machine) + '-other\runs') | Should -Be 'custom'
        Get-TuneupRootKind -Path (Join-Path $TestDrive 'runs') | Should -Be 'custom'
    }
}

Describe 'Machine state folder security' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'builds a protected ACL owned by Administrators from well-known SIDs' {
        $security = New-TuneupStateSecurity
        $security | Should -BeOfType [System.Security.AccessControl.DirectorySecurity]
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $AdminSid
        $security.AreAccessRulesProtected | Should -BeTrue
        $rules = @($security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $rules.Count | Should -Be 3
        $expected = @{
            'S-1-5-18'     = [System.Security.AccessControl.FileSystemRights]::FullControl
            'S-1-5-32-544' = [System.Security.AccessControl.FileSystemRights]::FullControl
            'S-1-5-32-545' = [System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize'
        }
        foreach ($rule in $rules) {
            $sid = $rule.IdentityReference.Value
            $expected.ContainsKey($sid) | Should -BeTrue -Because $sid
            $rule.FileSystemRights | Should -Be $expected[$sid] -Because $sid
            $rule.AccessControlType | Should -Be 'Allow'
            $rule.InheritanceFlags | Should -Be ([System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit')
            $rule.PropagationFlags | Should -Be ([System.Security.AccessControl.PropagationFlags]::None)
            $rule.IsInherited | Should -BeFalse
        }
    }

    It 'applies that ACL with Set-Acl' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Set-Acl { }
        Set-TuneupStateSecurity -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $Folder -and $AclObject.AreAccessRulesProtected -and
            $AclObject.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544' -and
            @($AclObject.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])).Count -eq 3
        }
    }

    It 'keeps the SACL out of Set-Acl when the folder is already protected' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Get-Acl {
            $current = New-Object System.Security.AccessControl.DirectorySecurity
            $current.SetAccessRuleProtection($true, $false)
            $current
        }
        Mock -ModuleName Tuneup Set-Acl { }
        Set-TuneupStateSecurity -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $AclObject.AreAuditRulesProtected }
    }

    It 'reports the folder as not trusted when Set-Acl fails' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Set-Acl { throw 'Access denied' }
        { Set-TuneupStateSecurity -Path $Folder } |
            Should -Throw -ExpectedMessage "State folder $Folder is not trusted. Delete it as administrator and run again."
    }

    It 'creates and hardens a missing machine folder and its runs folder' {
        Mock -ModuleName Tuneup Set-Acl { }
        Initialize-TuneupStateRoot -Path $Folder
        Test-Path -LiteralPath (Join-Path $Folder 'runs') -PathType Container | Should -BeTrue
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $Folder }
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq (Join-Path $Folder 'runs') }
    }

    It 're-applies the ACL to an existing folder owned by Administrators' {
        New-Item -ItemType Directory -Path (Join-Path $Folder 'runs') -Force | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Set-Acl { }
        Initialize-TuneupStateRoot -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'refuses an existing folder that someone else owns without touching it' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        Mock -ModuleName Tuneup Set-Acl { }
        { Initialize-TuneupStateRoot -Path $Folder } | Should -Throw -ExpectedMessage "State folder $Folder is not trusted.*"
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'refuses a machine folder that is a junction' {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $Folder -Value $target | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Set-Acl { }
        { Initialize-TuneupStateRoot -Path $Folder } | Should -Throw -ExpectedMessage '*is not trusted*'
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Machine runs' {
    BeforeEach {
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'needs an elevated process' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        Mock -ModuleName Tuneup Set-Acl { }
        { New-TuneupRun -Machine -MachineRoot $MachineRoot } | Should -Throw -ExpectedMessage '*elevated*'
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
    }

    It 'creates a hardened run with an empty journal owned by Administrators' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        Mock -ModuleName Tuneup Set-Acl { }
        $run = New-TuneupRun -Machine -MachineRoot $MachineRoot
        $run.Root | Should -Be 'machine'
        $run.Dir | Should -Be (Join-Path $MachineRoot "runs\$($run.Id)")
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        (Get-Item -LiteralPath $journal).Length | Should -Be 0
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $run.Dir -and $AclObject.AreAccessRulesProtected
        }
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $journal -and $AclObject.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544'
        }
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 4 -Exactly
    }

    It 'writes new runs to the user folder when not elevated' {
        $userRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Mock -ModuleName Tuneup Set-Acl { }
        $run = New-TuneupRun -UserRoot $userRoot -MachineRoot $MachineRoot
        $run.Root | Should -Be 'user'
        $run.Dir | Should -Be (Join-Path $userRoot "runs\$($run.Id)")
        Test-Path -LiteralPath (Join-Path $run.Dir 'snapshot.jsonl') | Should -BeFalse
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Trusted runs' {
    BeforeEach {
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Item = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Item | Out-Null
    }

    It 'trusts items owned by <Name>' -TestCases @(
        @{ Name = 'Administrators'; Sid = 'S-1-5-32-544' }
        @{ Name = 'SYSTEM'; Sid = 'S-1-5-18' }
    ) {
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity $Sid }
        Test-TuneupTrustedItem -Path $Item | Should -BeTrue
    }

    It 'does not trust items owned by a user' {
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        Test-TuneupTrustedItem -Path $Item | Should -BeFalse
    }

    It 'does not trust items it cannot inspect' {
        Mock -ModuleName Tuneup Get-Acl { throw 'Access denied' }
        Test-TuneupTrustedItem -Path $Item | Should -BeFalse
        Test-TuneupTrustedItem -Path (Join-Path $Item 'missing') | Should -BeFalse
    }

    It 'skips a planted machine run and resolves the last trusted one' {
        $good = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        $planted = New-RunFolder -Root $MachineRoot -Id '20250101-000001' -Tweaks @($MachineTweak)
        $plantedJournal = Join-Path $planted 'snapshot.jsonl'
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter {
            $LiteralPath -eq $plantedJournal
        }
        $runs = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue)
        ($runs | ForEach-Object { $_.Id }) -join ',' | Should -Be '20250101-000000'
        "$($warned[0])" | Should -BeLike "Ignoring untrusted run $planted*"
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last' -WarningAction SilentlyContinue).Dir | Should -Be $good
    }

    It 'skips a machine run folder owned by a user' {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        $planted = New-RunFolder -Root $MachineRoot -Id '20250101-000001'
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter {
            $LiteralPath -eq $planted
        }
        $ids = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningAction SilentlyContinue | ForEach-Object { $_.Id })
        $ids -join ',' | Should -Be '20250101-000000'
    }

    It 'ignores the whole machine folder when its runs folder is not trusted' {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        $runsDir = Join-Path $MachineRoot 'runs'
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter {
            $LiteralPath -eq $runsDir
        }
        @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0
        "$($warned[0])" | Should -BeLike "Ignoring untrusted state folder $runsDir*"
    }

    It 'refuses to read a machine journal that is not trusted' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        { Read-TuneupJournal -Path (Join-Path $dir 'snapshot.jsonl') -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }

    It 'reads machine-scope entries from a trusted machine journal' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak, (New-TestTweak))
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        @(Read-TuneupJournal -Path (Join-Path $dir 'snapshot.jsonl') -Root 'machine').Count | Should -Be 2
    }
}

Describe 'User runs' {
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

Describe 'Merged run list' {
    BeforeEach {
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
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

    It 'resolves last and explicit ids across both roots' {
        New-RunFolder -Root $UserRoot -Id '20250101-000000' | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000001' | Out-Null
        $last = Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last'
        "$($last.Id)/$($last.Root)" | Should -Be '20250101-000001/machine'
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId '20250101-000000').Root | Should -Be 'user'
    }

    It 'lists the user root alone when the machine root does not exist' {
        New-RunFolder -Root $UserRoot -Id '20250101-000000' | Out-Null
        (@(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot) | ForEach-Object { $_.Root }) -join ',' | Should -Be 'user'
    }
}
