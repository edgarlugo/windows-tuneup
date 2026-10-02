BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Id = '3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12'
    $script:InvalidText = '-ResultId takes 8 to 64 letters (A-Z), digits or hyphens, starting with a letter or a digit, such as a GUID. Nothing was done.'
    # Old results in out, oldest first, one minute apart.
    function New-OldResult([string]$Dir, [int]$Count) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $start = [datetime]::UtcNow.AddDays(-1)
        for ($i = 1; $i -le $Count; $i++) {
            $path = Join-Path $Dir ('old-{0:D8}.json' -f $i)
            [System.IO.File]::WriteAllText($path, '{}')
            [System.IO.File]::SetLastWriteTimeUtc($path, $start.AddMinutes($i))
        }
    }
    function Split-WarningOutput([object[]]$Output) {
        [pscustomobject]@{
            Warnings = @($Output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            Value    = $Output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
        }
    }
    # A file outside out that a link inside out points to.
    function New-OutsideFile([string]$Text) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $path = Join-Path $dir 'outside.json'
        [System.IO.File]::WriteAllText($path, $Text)
        $path
    }
}

Describe 'Get-TuneupResultIdProblem' {
    It 'accepts <Name>' -TestCases @(
        @{ Name = 'a GUID'; Id = '3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12' }
        @{ Name = 'eight characters'; Id = 'abcd1234' }
        @{ Name = 'sixty-four characters'; Id = ('a' * 64) }
        @{ Name = 'a digit first and hyphens after it'; Id = '7-------' }
        @{ Name = 'letters of both cases and hyphens'; Id = 'Run-2026-A' }
    ) {
        param($Id)
        Get-TuneupResultIdProblem -Id $Id -Json | Should -BeNullOrEmpty
    }

    It 'rejects <Name>' -TestCases @(
        @{ Name = 'seven characters'; Id = 'abc1234' }
        @{ Name = 'sixty-five characters'; Id = ('a' * 65) }
        @{ Name = 'a path'; Id = '..\..\escape-1' }
        @{ Name = 'a file name'; Id = 'abcdefgh.json' }
        @{ Name = 'a space'; Id = 'abcd 1234' }
        @{ Name = 'a line break at the end'; Id = "abcd1234`n" }
        @{ Name = 'a letter outside A-Z'; Id = "abcd1234$([char]0x00E9)" }
        @{ Name = 'a hyphen first (PowerShell would take it as a parameter name)'; Id = '-abcd1234' }
        @{ Name = 'nothing'; Id = '' }
    ) {
        param($Id)
        Get-TuneupResultIdProblem -Id $Id -Json | Should -Be $InvalidText
    }

    It 'asks for -Json before anything else' {
        Get-TuneupResultIdProblem -Id $Id | Should -Be '-ResultId needs -Json: the result file holds the JSON document. Nothing was done.'
    }
}

Describe 'Result files' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'creates out\<id>.json in the user state folder and writes the document when it closes' {
        $file = Open-TuneupResultFile -Id $Id -UserRoot $Root
        $file.Root | Should -Be 'user'
        $file.Path | Should -Be (Join-Path $Root "out\$Id.json")
        Test-Path -LiteralPath $file.Path | Should -BeTrue
        Close-TuneupResultFile -File $file -Text '{"command":"status"}' | Should -BeTrue
        [System.IO.File]::ReadAllText($file.Path) | Should -Be '{"command":"status"}'
    }

    It 'uses the -StateRoot folder of tests and development' {
        $file = Open-TuneupResultFile -Id $Id -StateRoot $Root -WarningAction SilentlyContinue
        $file.Root | Should -Be 'custom'
        Close-TuneupResultFile -File $file -Text '{}' | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Root "out\$Id.json") | Should -BeTrue
    }

    It 'refuses an id whose file exists, leaving that file as it was' {
        New-Item -ItemType Directory -Path (Join-Path $Root 'out') | Out-Null
        $existing = Join-Path $Root "out\$Id.json"
        [System.IO.File]::WriteAllText($existing, 'old')
        { Open-TuneupResultFile -Id $Id -UserRoot $Root } | Should -Throw "The result $Id already exists: use a new -ResultId. Nothing was done."
        [System.IO.File]::ReadAllText($existing) | Should -Be 'old'
    }

    It 'refuses an id whose name is a link planted in out, leaving the file it points to as it was' {
        $outside = New-OutsideFile -Text 'secret'
        New-Item -ItemType Directory -Path (Join-Path $Root 'out') | Out-Null
        New-Item -ItemType HardLink -Path (Join-Path $Root "out\$Id.json") -Target $outside | Out-Null
        { Open-TuneupResultFile -Id $Id -UserRoot $Root } | Should -Throw "The result $Id already exists: use a new -ResultId. Nothing was done."
        [System.IO.File]::ReadAllText($outside) | Should -Be 'secret'
    }

    It 'refuses an id that is not a plain name, creating nothing' {
        { Open-TuneupResultFile -Id '..\outside-1' -UserRoot $Root } | Should -Throw '*Invalid result id*'
        { Open-TuneupResultFile -Id "abcd1234`n" -UserRoot $Root } | Should -Throw '*Invalid result id*'
        Test-Path -LiteralPath $Root | Should -BeFalse
    }

    It 'removes the file when there is no document to write' {
        $file = Open-TuneupResultFile -Id $Id -UserRoot $Root
        Close-TuneupResultFile -File $file -Text '' | Should -BeFalse
        Test-Path -LiteralPath $file.Path | Should -BeFalse
    }

    It 'removes the file when the document cannot be written' {
        $file = Open-TuneupResultFile -Id $Id -UserRoot $Root
        $file.Stream.Dispose()
        Close-TuneupResultFile -File $file -Text '{}' | Should -BeFalse
        Test-Path -LiteralPath $file.Path | Should -BeFalse
    }

    It 'keeps the 50 newest results and leaves other files alone' {
        $dir = Join-Path $Root 'out'
        New-OldResult -Dir $dir -Count 55
        foreach ($name in 'notes.txt', 'x.json') { [System.IO.File]::WriteAllText((Join-Path $dir $name), 'keep') }
        $file = Open-TuneupResultFile -Id $Id -UserRoot $Root
        Close-TuneupResultFile -File $file -Text '{}' | Out-Null
        @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Where-Object { $_.BaseName -match '^[A-Za-z0-9-]{8,64}$' }).Count | Should -Be 50
        foreach ($i in 1..6) { Test-Path -LiteralPath (Join-Path $dir ('old-{0:D8}.json' -f $i)) | Should -BeFalse }
        foreach ($name in 'old-00000007.json', 'old-00000055.json', "$Id.json", 'notes.txt', 'x.json') {
            Test-Path -LiteralPath (Join-Path $dir $name) | Should -BeTrue -Because $name
        }
    }

    It 'never removes anything outside out when it prunes' {
        $dir = Join-Path $Root 'out'
        New-OldResult -Dir $dir -Count 50
        # The oldest result is a hard link to a file outside out: pruning removes the name, not the file.
        $outside = New-OutsideFile -Text 'secret'
        $link = Join-Path $dir 'link-00000000.json'
        New-Item -ItemType HardLink -Path $link -Target $outside | Out-Null
        [System.IO.File]::SetLastWriteTimeUtc($link, [datetime]::UtcNow.AddDays(-2))
        # A junction named like a result: a folder, never listed.
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $target 'old-00000099.json'), 'keep')
        New-Item -ItemType Junction -Path (Join-Path $dir 'junction-0001.json') -Target $target | Out-Null
        try {
            $file = Open-TuneupResultFile -Id $Id -UserRoot $Root
            Close-TuneupResultFile -File $file -Text '{}' | Out-Null
            Test-Path -LiteralPath $link | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $dir 'old-00000001.json') | Should -BeFalse
            [System.IO.File]::ReadAllText($outside) | Should -Be 'secret'
            [System.IO.File]::ReadAllText((Join-Path $target 'old-00000099.json')) | Should -Be 'keep'
            Test-Path -LiteralPath (Join-Path $dir 'junction-0001.json') | Should -BeTrue
        } finally {
            [System.IO.Directory]::Delete((Join-Path $dir 'junction-0001.json'))
        }
    }

    It 'never counts nor removes the file just created, however old the others look' {
        $dir = Join-Path $Root 'out'
        New-OldResult -Dir $dir -Count 50
        # The old results look newer than the one being created, which is held open until it is closed.
        foreach ($old in Get-ChildItem -LiteralPath $dir -File) { [System.IO.File]::SetLastWriteTimeUtc($old.FullName, $old.LastWriteTimeUtc.AddDays(2)) }
        $opened = Split-WarningOutput @(Open-TuneupResultFile -Id $Id -UserRoot $Root 3>&1)
        try {
            $opened.Warnings.Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $dir 'old-00000001.json') | Should -BeFalse
            @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File).Count | Should -Be 50
        } finally {
            Close-TuneupResultFile -File $opened.Value -Text '{}' | Out-Null
        }
        Test-Path -LiteralPath (Join-Path $dir "$Id.json") | Should -BeTrue
    }

    It 'writes the document as it was outside the machine folder, personal paths included' {
        $text = '{"message":"' + ($env:USERPROFILE -replace '\\', '\\') + '"}'
        $file = Open-TuneupResultFile -Id $Id -UserRoot $Root
        Close-TuneupResultFile -File $file -Text $text | Should -BeTrue
        [System.IO.File]::ReadAllText($file.Path) | Should -Be $text
    }

    It 'warns instead of failing when an old result cannot be removed' {
        $dir = Join-Path $Root 'out'
        New-OldResult -Dir $dir -Count 50
        $oldest = Join-Path $dir 'old-00000001.json'
        $lock = [System.IO.File]::Open($oldest, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $file = $null
        try {
            $opened = Split-WarningOutput @(Open-TuneupResultFile -Id $Id -UserRoot $Root 3>&1)
            $file = $opened.Value
            $opened.Warnings.Count | Should -Be 1
            $opened.Warnings[0] | Should -Match 'Could not remove the old result file .*old-00000001\.json'
            Test-Path -LiteralPath $oldest | Should -BeTrue
        } finally {
            $lock.Dispose()
            if ($null -ne $file) { Close-TuneupResultFile -File $file -Text '{}' | Out-Null }
        }
    }
}

Describe 'Machine result files' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $script:MachineRoot = New-TestMachineRoot
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'creates the file in the protected machine folder, readable by users, when elevated' {
        $file = Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot
        $file.Root | Should -Be 'machine'
        Close-TuneupResultFile -File $file -Text '{"command":"apply"}' | Should -BeTrue
        foreach ($path in (Join-Path $MachineRoot 'out'), $file.Path) {
            (Get-Acl -LiteralPath $path).AreAccessRulesProtected | Should -BeTrue -Because $path
        }
        $rules = @((Get-Acl -LiteralPath $file.Path).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $users = @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' -and $_.AccessControlType -eq 'Allow' })
        $users.Count | Should -Be 1
        $writeRights = InModuleScope Tuneup { $script:WriteRights }
        ([int]$users[0].FileSystemRights -band $writeRights) | Should -Be 0
        [System.IO.File]::ReadAllText($file.Path) | Should -Be '{"command":"apply"}'
    }

    It 'hides the profile folder and the account name in the machine folder, field by field, leaving ids alone' -Skip:(([string]$env:USERNAME).Length -lt 3) {
        $profileFolder = $env:USERPROFILE
        $name = $env:USERNAME
        # A path under the profile, the account name as a folder of another path, and ids that hold the
        # name without a path around it.
        $document = [pscustomobject]@{
            schemaVersion = 1; command = 'undo'; toolVersion = '0.0.0'; runId = "$name-run"
            warnings = [string[]]@("Ignoring untrusted state file $profileFolder\AppData\Local\windows-tuneup\runs\x\run.json")
            results = @([pscustomobject]@{
                id = "$name.tweak"; title = "Title $name"; status = 'failed'; reason = $null
                error = "Cannot write D:\Data\$name\file.txt"; detail = $null
                manual = [string[]]@("Set-ItemProperty -LiteralPath 'HKCU:\Software\X' -Name P -Value '$profileFolder\x'")
            })
        }
        $text = ConvertTo-Json -InputObject $document -Depth 10
        $file = Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot
        Close-TuneupResultFile -File $file -Text $text | Should -BeTrue
        $saved = [System.IO.File]::ReadAllText($file.Path)
        $json = $saved | ConvertFrom-Json
        $json.warnings[0] | Should -Be 'Ignoring untrusted state file %USERPROFILE%\AppData\Local\windows-tuneup\runs\x\run.json'
        $json.results[0].error | Should -Be 'Cannot write D:\Data\%USERNAME%\file.txt'
        @($json.results[0].manual).Count | Should -Be 1
        # A command to run keeps its paths: hidden, it would restore a wrong value or key.
        $json.results[0].manual[0] | Should -Be "Set-ItemProperty -LiteralPath 'HKCU:\Software\X' -Name P -Value '$profileFolder\x'"
        $json.results[0].id | Should -Be "$name.tweak"
        $json.results[0].title | Should -Be "Title $name"
        $json.runId | Should -Be "$name-run"
        $json.results[0].status | Should -Be 'failed'
    }

    It 'needs an elevated process for the machine folder' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        { Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot } | Should -Throw '*elevated*'
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
    }

    It 'refuses an out folder that other accounts can change' {
        Initialize-TuneupStateRoot -Path $MachineRoot -Children @('out')
        Grant-EveryoneWrite (Join-Path $MachineRoot 'out')
        { Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot } | Should -Throw '*is not trusted*'
        Test-Path -LiteralPath (Join-Path $MachineRoot "out\$Id.json") | Should -BeFalse
    }

    It 'refuses an out folder that is a junction, writing nothing where it points' {
        Initialize-TuneupStateRoot -Path $MachineRoot -Children @('runs')
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target | Out-Null
        $out = Join-Path $MachineRoot 'out'
        New-Item -ItemType Junction -Path $out -Target $target | Out-Null
        try {
            { Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot } | Should -Throw '*is not trusted*'
            @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
        } finally {
            [System.IO.Directory]::Delete($out)
        }
    }

    It 'refuses an id in use in the machine folder, leaving that file as it was' {
        $first = Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot
        Close-TuneupResultFile -File $first -Text 'old' | Should -BeTrue
        { Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot } | Should -Throw "The result $Id already exists: use a new -ResultId. Nothing was done."
        [System.IO.File]::ReadAllText($first.Path) | Should -Be 'old'
    }
}

Describe 'Reading result files' {
    BeforeEach {
        Use-CurrentUserAsTrusted
        # Writing to the machine folder needs an elevated process; reading it does not ask.
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $script:MachineRoot = New-TestMachineRoot
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Document = '{"schemaVersion":1,"command":"status","toolVersion":"0.1.0","warnings":[],"items":[]}'
        # Both folders that an unelevated caller looks in.
        $script:Roots = @{ MachineRoot = $MachineRoot; UserRoot = $UserRoot }
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'reads a result of the user folder when the machine folder has none' {
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -UserRoot $UserRoot) -Text $Document | Should -BeTrue
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -BeNullOrEmpty
        $read.Text | Should -Be $Document
        $read.Path | Should -Be (Join-Path $UserRoot "out\$Id.json")
    }

    It 'never looks in the user folder for an elevated caller' {
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -UserRoot $UserRoot) -Text $Document | Should -BeTrue
        $read = Read-TuneupResultFile -Id $Id @Roots
        $read.Code | Should -Be 'result-missing'
        $read.Text | Should -BeNullOrEmpty
    }

    It 'reads a result of the machine folder, before the user folder' {
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot) -Text $Document | Should -BeTrue
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -UserRoot $UserRoot) -Text '{"command":"user"}' | Should -BeTrue
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -BeNullOrEmpty
        $read.Text | Should -Be $Document
        $read.Path | Should -Be (Join-Path $MachineRoot "out\$Id.json")
    }

    It 'says result-missing when no folder has it' {
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -Be 'result-missing'
        $read.Key | Should -Be 'err.readResultMissing'
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
        Test-Path -LiteralPath $UserRoot | Should -BeFalse
    }

    It 'refuses a result in an out folder that other accounts can change, reading nothing' {
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot) -Text $Document | Should -BeTrue
        Grant-EveryoneWrite (Join-Path $MachineRoot 'out')
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -Be 'result-untrusted'
        $read.Key | Should -Be 'err.readResultUntrusted'
        $read.Folder | Should -Be $MachineRoot
        $read.Text | Should -BeNullOrEmpty
    }

    It 'refuses a result file that other accounts can change' {
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot) -Text $Document | Should -BeTrue
        Grant-EveryoneWrite (Join-Path $MachineRoot "out\$Id.json")
        (Read-TuneupResultFile -Id $Id @Roots -IncludeUser).Code | Should -Be 'result-untrusted'
    }

    It 'refuses a machine folder that another account made, also when the result is not there' {
        # A standard user can make the folder before the first elevated run, which then refuses to write.
        Initialize-TuneupStateRoot -Path $MachineRoot -Children @('out')
        Grant-EveryoneWrite $MachineRoot
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -Be 'result-untrusted'
        $read.Folder | Should -Be $MachineRoot
    }

    It 'refuses a machine folder that another account made before it looks in the user folder' {
        # Its run may have been refused there; a result of the same id in the user folder is not it.
        Initialize-TuneupStateRoot -Path $MachineRoot -Children @('out')
        Grant-EveryoneWrite $MachineRoot
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -UserRoot $UserRoot) -Text $Document | Should -BeTrue
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -Be 'result-untrusted'
        $read.Text | Should -BeNullOrEmpty
    }

    It 'refuses an out folder that is a junction, reading nothing where it points' {
        Initialize-TuneupStateRoot -Path $MachineRoot -Children @('runs')
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $target "$Id.json"), $Document)
        $out = Join-Path $MachineRoot 'out'
        New-Item -ItemType Junction -Path $out -Target $target | Out-Null
        try {
            $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
            $read.Code | Should -Be 'result-untrusted'
            $read.Text | Should -BeNullOrEmpty
        } finally {
            [System.IO.Directory]::Delete($out)
        }
    }

    It 'refuses a result that is a hard link to a file elsewhere' {
        Initialize-TuneupStateRoot -Path $MachineRoot -Children @('out')
        $outside = New-OutsideFile -Text $Document
        New-Item -ItemType HardLink -Path (Join-Path $MachineRoot "out\$Id.json") -Target $outside | Out-Null
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -Be 'result-untrusted'
        $read.Text | Should -BeNullOrEmpty
    }

    It 'says result-incomplete for an empty result, a run that was stopped before it wrote' {
        $file = Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot
        $file.Stream.Dispose()
        $read = Read-TuneupResultFile -Id $Id @Roots -IncludeUser
        $read.Code | Should -Be 'result-incomplete'
        $read.Key | Should -Be 'err.readResultIncomplete'
    }

    It 'says result-incomplete while the result is still being written' {
        $file = Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot
        try {
            (Read-TuneupResultFile -Id $Id @Roots -IncludeUser).Code | Should -Be 'result-incomplete'
        } finally {
            Close-TuneupResultFile -File $file -Text $Document | Should -BeTrue
        }
        (Read-TuneupResultFile -Id $Id @Roots -IncludeUser).Text | Should -Be $Document
    }

    It 'says result-incomplete for <Name>' -TestCases @(
        @{ Name = 'text that is not JSON'; Text = 'not json' }
        @{ Name = 'two documents'; Text = '{"command":"status"}{"command":"error"}' }
        @{ Name = 'an array'; Text = '[1,2]' }
        @{ Name = 'only spaces'; Text = '   ' }
    ) {
        param($Text)
        New-Item -ItemType Directory -Path (Join-Path $UserRoot 'out') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $UserRoot "out\$Id.json"), $Text)
        (Read-TuneupResultFile -Id $Id @Roots -IncludeUser).Code | Should -Be 'result-incomplete'
    }

    It 'reads only the -StateRoot folder of tests and development' {
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -Machine -MachineRoot $MachineRoot) -Text '{"command":"machine"}' | Should -BeTrue
        $custom = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Close-TuneupResultFile -File (Open-TuneupResultFile -Id $Id -StateRoot $custom -WarningAction SilentlyContinue) -Text $Document | Should -BeTrue
        $read = Read-TuneupResultFile -Id $Id -StateRoot $custom @Roots -IncludeUser -WarningAction SilentlyContinue
        $read.Text | Should -Be $Document
        $read.Path | Should -Be (Join-Path $custom "out\$Id.json")
    }

    It 'refuses an id that is not a plain name, reading nothing' {
        { Read-TuneupResultFile -Id '..\outside-1' @Roots -IncludeUser } | Should -Throw '*Invalid result id*'
        { Read-TuneupResultFile -Id "abcd1234`n" @Roots -IncludeUser } | Should -Throw '*Invalid result id*'
    }
}
