BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:AdminSid = 'S-1-5-32-544'
    $script:OtherSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001'
    $script:MeSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    function New-OwnedSecurity([string]$Sid) {
        $security = New-Object System.Security.AccessControl.DirectorySecurity
        $security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid))
        $security
    }
    function Set-TestTrust([string]$Owner, [string[]]$Trusted) {
        InModuleScope Tuneup -Parameters @{ Owner = $Owner; Trusted = $Trusted } {
            param($Owner, $Trusted)
            $script:StateOwnerSid = $Owner
            $script:TrustedSids = $Trusted
        }
    }
    # The state folders are hardened for Administrators; tests can only own files as the current user.
    function Use-CurrentUserAsTrusted { Set-TestTrust -Owner $MeSid -Trusted @('S-1-5-18', 'S-1-5-32-544', $MeSid) }
    function Reset-TestTrust { Set-TestTrust -Owner 'S-1-5-32-544' -Trusted @('S-1-5-18', 'S-1-5-32-544') }
    function Grant-EveryoneWrite([string]$Path) {
        $acl = Get-Acl -LiteralPath $Path
        $inheritance = [System.Security.AccessControl.InheritanceFlags]::None
        if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) {
            $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        }
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-1-0'),
            [System.Security.AccessControl.FileSystemRights]::Write, $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
        $acl.SetAuditRuleProtection($acl.AreAccessRulesProtected, $true)
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
    function New-RunFolder([string]$Root, [string]$Id, [object[]]$Tweaks = @((New-TestTweak)), [string]$UserSid = $MeSid) {
        $dir = Join-Path $Root "runs\$Id"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($tweak in $Tweaks) {
            Add-TuneupJournalEntry -Path (Join-Path $dir 'snapshot.jsonl') -Tweak $tweak -State $null -Root 'custom'
        }
        Save-TuneupJson -Path (Join-Path $dir 'run.json') -Root 'custom' `
            -Object ([pscustomobject]@{ schemaVersion = 1; userSid = $UserSid; machine = $true; createdAt = 'now' })
        $dir
    }
    function Get-Rules($Security) {
        @($Security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
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

Describe 'Machine state folder security' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'builds a protected ACL owned by Administrators from well-known SIDs' {
        $security = New-TuneupStateSecurity
        $security | Should -BeOfType [System.Security.AccessControl.DirectorySecurity]
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $AdminSid
        $security.AreAccessRulesProtected | Should -BeTrue
        $rules = Get-Rules $security
        $rules.Count | Should -Be 4
        $expected = @{
            'S-1-5-18'     = [System.Security.AccessControl.FileSystemRights]::FullControl
            'S-1-5-32-544' = [System.Security.AccessControl.FileSystemRights]::FullControl
            'S-1-5-32-545' = [System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize'
            'S-1-3-4'      = [System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize'
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

    It 'builds the same ACL for files without inheritance flags' {
        $security = New-TuneupStateSecurity -File
        $security | Should -BeOfType [System.Security.AccessControl.FileSecurity]
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $AdminSid
        $security.AreAccessRulesProtected | Should -BeTrue
        $rules = Get-Rules $security
        ($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',' | Should -Be 'S-1-3-4,S-1-5-18,S-1-5-32-544,S-1-5-32-545'
        @($rules | Where-Object { $_.InheritanceFlags -ne 'None' }).Count | Should -Be 0
    }

    It 'builds the ACL for injected SIDs' {
        $security = New-TuneupStateSecurity -OwnerSid $OtherSid -TrustedSids @($OtherSid)
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $OtherSid
        ((Get-Rules $security) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',' |
            Should -Be "S-1-3-4,$OtherSid,S-1-5-32-545"
    }

    It 'applies that ACL with Set-Acl' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Set-Acl { }
        Set-TuneupStateSecurity -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $Folder -and $AclObject.AreAccessRulesProtected -and
            $AclObject.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544' -and
            @($AclObject.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])).Count -eq 4
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

    It 'hardens a real folder with injected SIDs' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Set-TuneupStateSecurity -Path $Folder -OwnerSid $MeSid -TrustedSids @($MeSid)
        $acl = Get-Acl -LiteralPath $Folder
        $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $MeSid
        $acl.AreAccessRulesProtected | Should -BeTrue
        $rules = Get-Rules $acl
        ($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',' | Should -Be "S-1-3-4,$MeSid,S-1-5-32-545"
        ($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-4' }).FileSystemRights |
            Should -Be ([System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize')
        @($rules | Where-Object { $_.IsInherited }).Count | Should -Be 0
        Test-TuneupTrustedItem -Path $Folder -TrustedSids @($MeSid) | Should -BeTrue
    }

    It 'creates a missing machine folder and its runs folder with the ACL already in place' {
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Set-Acl { }
        Initialize-TuneupStateRoot -Path $Folder
        foreach ($path in $Folder, (Join-Path $Folder 'runs')) {
            $acl = Get-Acl -LiteralPath $path
            $acl.AreAccessRulesProtected | Should -BeTrue -Because $path
            $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $MeSid
            @(Get-Rules $acl | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-4' }).Count | Should -Be 1
        }
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
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

    It 'refuses a folder that someone else created first while it was being created' {
        Mock -ModuleName Tuneup New-TuneupSecureDirectory {
            New-Item -ItemType Directory -Path $Path | Out-Null
            throw 'Cannot create a file when that file already exists'
        }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        Mock -ModuleName Tuneup Set-Acl { }
        { Initialize-TuneupStateRoot -Path $Folder } | Should -Throw -ExpectedMessage "State folder $Folder is not trusted.*"
        Test-Path -LiteralPath $Folder | Should -BeTrue
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

Describe 'Trust checks' {
    BeforeEach {
        $script:Item = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Item | Out-Null
    }

    AfterEach {
        Reset-TestTrust
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

    It 'does not trust a DACL that grants <Name> to another SID' -TestCases @(
        @{ Name = 'WriteData'; Rights = 0x2 }
        @{ Name = 'AppendData'; Rights = 0x4 }
        @{ Name = 'WriteExtendedAttributes'; Rights = 0x10 }
        @{ Name = 'DeleteSubdirectoriesAndFiles'; Rights = 0x40 }
        @{ Name = 'WriteAttributes'; Rights = 0x100 }
        @{ Name = 'Delete'; Rights = 0x10000 }
        @{ Name = 'ChangePermissions'; Rights = 0x40000 }
        @{ Name = 'TakeOwnership'; Rights = 0x80000 }
        @{ Name = 'GenericAll'; Rights = 0x10000000 }
        @{ Name = 'GenericWrite'; Rights = 0x40000000 }
    ) {
        Mock -ModuleName Tuneup Get-Acl {
            $security = New-OwnedSecurity 'S-1-5-32-544'
            $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
                (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-545'),
                [System.Security.AccessControl.FileSystemRights]$Rights,
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow)))
            $security
        }
        Test-TuneupTrustedItem -Path $Item | Should -BeFalse
    }

    It 'ignores deny entries and read-only grants' {
        Mock -ModuleName Tuneup Get-Acl {
            $security = New-OwnedSecurity 'S-1-5-32-544'
            foreach ($rule in @(
                    @('S-1-1-0', 'FullControl', 'Deny'),
                    @('S-1-5-32-545', 'ReadAndExecute', 'Allow'),
                    @('S-1-5-32-544', 'FullControl', 'Allow'))) {
                $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
                    (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $rule[0]),
                    [System.Security.AccessControl.FileSystemRights]$rule[1],
                    [System.Security.AccessControl.InheritanceFlags]::None,
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]$rule[2])))
            }
            $security
        }
        Test-TuneupTrustedItem -Path $Item | Should -BeTrue
    }

    It 'does not trust a real folder once Everyone can write to it' {
        Set-TuneupStateSecurity -Path $Item -OwnerSid $MeSid -TrustedSids @($MeSid)
        Test-TuneupTrustedItem -Path $Item -TrustedSids @($MeSid) | Should -BeTrue
        Grant-EveryoneWrite $Item
        Test-TuneupTrustedItem -Path $Item -TrustedSids @($MeSid) | Should -BeFalse
    }

    It 'does not trust a real file with a second hard link' {
        Use-CurrentUserAsTrusted
        Set-TuneupStateSecurity -Path $Item
        $file = Join-Path $Item 'snapshot.jsonl'
        [System.IO.File]::WriteAllText($file, '')
        Test-TuneupTrustedItem -Path $file | Should -BeTrue
        New-Item -ItemType HardLink -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -Value $file | Out-Null
        Test-TuneupTrustedItem -Path $file | Should -BeFalse
    }
}

Describe 'Machine runs' {
    BeforeEach {
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
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
            @(Get-Rules $acl | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-4' }).Count | Should -Be 1 -Because $path
        }
        $info = Read-TuneupTrustedJson -Path (Join-Path $run.Dir 'run.json') -Root 'machine'
        $info.userSid | Should -Be $MeSid
        $info.machine | Should -BeTrue
        $info.schemaVersion | Should -Be 1
        $listed = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot (Join-Path $TestDrive 'none'))
        "$($listed[0].Id)/$($listed[0].Root)/$($listed[0].UserSid)" | Should -Be "$($run.Id)/machine/$MeSid"
    }

    It 'appends to the machine journal through a checked handle' {
        $run = New-TuneupRun -Machine -MachineRoot $MachineRoot
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        Add-TuneupJournalEntry -Path $journal -Tweak $MachineTweak -State $null -Root 'machine'
        Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak) -State $null -Root 'machine'
        (@(Read-TuneupJournal -Path $journal -Root 'machine') | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine,test.sample'
    }

    It 'refuses to append to a machine journal with a second hard link' {
        $run = New-TuneupRun -Machine -MachineRoot $MachineRoot
        $journal = Join-Path $run.Dir 'snapshot.jsonl'
        New-Item -ItemType HardLink -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -Value $journal | Out-Null
        { Add-TuneupJournalEntry -Path $journal -Tweak (New-TestTweak) -State $null -Root 'machine' } |
            Should -Throw -ExpectedMessage "State file $journal is not trusted"
        { Read-TuneupJournal -Path $journal -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }

    It 'writes machine state files with the protected ACL and can replace them' {
        $run = New-TuneupRun -Machine -MachineRoot $MachineRoot
        $path = Join-Path $run.Dir 'undone.json'
        Save-TuneupJson -Path $path -Object ([pscustomobject]@{ undoneAt = 'first' }) -Root 'machine'
        Save-TuneupJson -Path $path -Object ([pscustomobject]@{ undoneAt = 'second' }) -Root 'machine'
        (Read-TuneupTrustedJson -Path $path -Root 'machine').undoneAt | Should -Be 'second'
        (Get-Acl -LiteralPath $path).AreAccessRulesProtected | Should -BeTrue
        Test-TuneupRunMarker -Dir $run.Dir -Name 'undone.json' -Root 'machine' | Should -BeTrue
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
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Use-CurrentUserAsTrusted
        Initialize-TuneupStateRoot -Path $MachineRoot
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'skips a planted machine run and resolves the last trusted one' {
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

    It 'ignores the whole machine folder when its runs folder is not trusted' {
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        $runsDir = Join-Path $MachineRoot 'runs'
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter {
            $LiteralPath -eq $runsDir
        }
        @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0
        "$($warned[0])" | Should -BeLike "Ignoring untrusted state folder $runsDir*"
    }

    It 'refuses to read a machine journal that is not trusted' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        Grant-EveryoneWrite (Join-Path $dir 'snapshot.jsonl')
        { Read-TuneupJournal -Path (Join-Path $dir 'snapshot.jsonl') -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }

    It 'reads machine-scope entries from a trusted machine journal' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak, (New-TestTweak))
        @(Read-TuneupJournal -Path (Join-Path $dir 'snapshot.jsonl') -Root 'machine').Count | Should -Be 2
    }

    It 'ignores run markers and run info that are not trusted' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        foreach ($name in 'undone.json', 'result.json') {
            Save-TuneupJson -Path (Join-Path $dir $name) -Root 'custom' -Object ([pscustomobject]@{ results = @() })
        }
        foreach ($name in 'undone.json', 'result.json', 'run.json') { Grant-EveryoneWrite (Join-Path $dir $name) }
        $run = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue)[0]
        $run.Undone | Should -BeFalse
        $run.UserSid | Should -BeNullOrEmpty
        @($warned | Where-Object { "$_" -like 'Ignoring untrusted state file *' }).Count | Should -Be 2
        Read-TuneupTrustedJson -Path (Join-Path $dir 'result.json') -Root 'machine' -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        Read-TuneupStateFile -Path (Join-Path $dir 'result.json') -Root 'machine' -IgnoreUntrusted -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        { Read-TuneupStateFile -Path (Join-Path $dir 'result.json') -Root 'machine' } | Should -Throw -ExpectedMessage '*is not trusted*'
    }

    It 'reads trusted run markers and run info' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000'
        Save-TuneupJson -Path (Join-Path $dir 'result.json') -Root 'custom' -Object ([pscustomobject]@{ results = @('x') })
        Save-TuneupJson -Path (Join-Path $dir 'undone.json') -Root 'custom' -Object ([pscustomobject]@{ undoneAt = 'now' })
        $run = @(Get-TuneupRunList -MachineRoot $MachineRoot -UserRoot $UserRoot)[0]
        $run.Undone | Should -BeTrue
        $run.UserSid | Should -Be $MeSid
        @((Read-TuneupTrustedJson -Path (Join-Path $dir 'result.json') -Root 'machine').results) -join ',' | Should -Be 'x'
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

Describe 'Runs of other users' {
    BeforeEach {
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Use-CurrentUserAsTrusted
        Initialize-TuneupStateRoot -Path $MachineRoot
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'skips user-scope entries of a run made by another user' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak, (New-TestTweak)) -UserSid $OtherSid
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'machine'; UserSid = $OtherSid }
        $entries = @(Read-TuneupRunJournal -Run $run -WarningVariable warned -WarningAction SilentlyContinue)
        ($entries | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.machine'
        "$($warned[0])" | Should -BeLike "Ignoring user-scope entry 'test.sample' of run 20250101-000000*"
    }

    It 'keeps every entry of a run made by the current user' {
        $dir = New-RunFolder -Root $MachineRoot -Id '20250101-000000' -Tweaks @($MachineTweak, (New-TestTweak))
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'machine'; UserSid = $MeSid }
        @(Read-TuneupRunJournal -Run $run).Count | Should -Be 2
    }

    It 'skips user-scope entries when the run does not say who made it' {
        $dir = New-RunFolder -Root $UserRoot -Id '20250101-000000'
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'custom'; UserSid = $null }
        @(Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue).Count | Should -Be 0
    }

    It 'resolves last to a run that a non-elevated user can complete' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000001' -UserSid $OtherSid | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000002' -Tweaks @($MachineTweak, (New-TestTweak)) | Out-Null
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last').Id | Should -Be '20250101-000000'
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId '20250101-000002').Id | Should -Be '20250101-000002'
        New-RunFolder -Root $UserRoot -Id '20240101-000000' -UserSid $OtherSid | Out-Null
        New-RunFolder -Root $UserRoot -Id '20250101-000003' | Out-Null
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last').Root | Should -Be 'user'
    }

    It 'resolves last to the newest run when elevated' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        New-RunFolder -Root $MachineRoot -Id '20250101-000000' | Out-Null
        New-RunFolder -Root $MachineRoot -Id '20250101-000001' -Tweaks @($MachineTweak) -UserSid $OtherSid | Out-Null
        (Resolve-TuneupRun -MachineRoot $MachineRoot -UserRoot $UserRoot -RunId 'last').Id | Should -Be '20250101-000001'
    }
}

Describe 'Merged run list' {
    BeforeEach {
        $script:MachineRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Use-CurrentUserAsTrusted
        Initialize-TuneupStateRoot -Path $MachineRoot
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
