BeforeDiscovery {
    $script:Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:SubKey = 'HKCU:\Software\windows-tuneup-test\Sub'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    function Invoke-Tuneup([string[]]$Arguments, [string]$Lang = 'en', [string]$Catalog = (Join-Path $Fixtures 'catalog'), [string]$Actions = (Join-Path $Fixtures 'actions')) {
        $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath $Catalog -ProfilesPath (Join-Path $Fixtures 'profiles') -ActionsPath $Actions `
            -StateRoot $script:Root -Force -Lang $Lang @Arguments
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
    function Get-Ids($Items) { ($Items | ForEach-Object { $_.id }) -join ',' }
    function Get-RunDir { @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'runs') -Directory | Sort-Object Name)[-1].FullName }
    # The whole standard output has to be one JSON document, with nothing printed around it.
    function ConvertFrom-PureJson([string]$Text) {
        $Text.Trim() | Should -Match '^\{[\s\S]*\}$'
        $Text | ConvertFrom-Json
    }
    # Denies the current user writing values in the Sub key only, so a change there fails. The key is
    # opened for its ACL alone: Set-Acl would ask for write access, which the deny itself blocks.
    function Set-TestSetValueDeny([switch]$Remove) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\windows-tuneup-test\Sub',
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]'ReadPermissions, ChangePermissions')
        try {
            $acl = $key.GetAccessControl()
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList `
                ([Security.Principal.WindowsIdentity]::GetCurrent().User), 'SetValue', 'None', 'None', 'Deny'
            if ($Remove) { [void]$acl.RemoveAccessRule($rule) } else { $acl.AddAccessRule($rule) }
            $key.SetAccessControl($acl)
        } finally {
            $key.Close()
        }
    }
    function Remove-TestKey {
        if (Test-Path -LiteralPath $SubKey) { Set-TestSetValueDeny -Remove }
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }
}

Describe 'tuneup.ps1' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Remove-TestKey
    }

    AfterAll {
        Remove-TestKey
    }

    It 'plans an action tweak loaded from -ActionsPath' {
        $result = Invoke-Tuneup @('-Include', 'test.action', '-WhatIf', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        ($json.items | Where-Object { $_.id -eq 'test.action' }).action | Should -Be 'apply'
        $json.requiresAdmin | Should -BeTrue
    }

    It 'lists the profiles and the tweaks that suit this machine' {
        $result = Invoke-Tuneup @('-List', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'list'
        @($json.profiles | ForEach-Object { $_.id }) -join ',' | Should -Be 'base,extra,nested,system'
        ($json.profiles | Where-Object { $_.id -eq 'system' }).needsAdmin | Should -BeTrue
        @(($json.tweaks | Where-Object { $_.id -eq 'test.three' }).profiles) -join ',' | Should -Be 'extra'
        $json.PSObject.Properties.Name | Should -Contain 'warnings'
    }

    It 'shows the list for people in the chosen language' {
        $result = Invoke-Tuneup @('-List') -Lang 'es'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Perfiles:'
        $result.Output | Should -Match 'test\.one - Prueba uno'
    }

    It 'suggests profiles, always with every signal and base first' {
        $result = Invoke-Tuneup @('-Suggest', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'suggest'
        # What the runner has installed is not checked: only the shape of the document.
        @($json.signals | ForEach-Object { $_.id }) -join ',' | Should -Be 'dev,gaming,laptop,work,legacy,managed'
        $json.suggestions[0].profile | Should -Be 'base'
        @($json.questions | ForEach-Object { $_.id }) -join ',' | Should -Be 'privacy,lite'
    }

    It 'rejects -List with the options of applying, before reading anything' {
        $result = Invoke-Tuneup @('-List', '-Profile', 'extra', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'Invalid parameter combination: -List -Profile'
    }

    It 'also writes the JSON document to out\<id>.json with -ResultId' {
        $id = [guid]::NewGuid().ToString()
        $result = Invoke-Tuneup @('-Status', '-Json', '-ResultId', $id)
        $result.ExitCode | Should -Be 0
        $saved = [System.IO.File]::ReadAllText((Join-Path $Root "out\$id.json"))
        ($saved -replace "`r`n", "`n").Trim() | Should -Be $result.Output.Trim()
        (ConvertFrom-PureJson $saved).command | Should -Be 'status'
    }

    It 'writes the -Suggest document to the result file too, though -Suggest reads no state' {
        $id = [guid]::NewGuid().ToString()
        $result = Invoke-Tuneup @('-Suggest', '-Json', '-ResultId', $id)
        $result.ExitCode | Should -Be 0
        $saved = [System.IO.File]::ReadAllText((Join-Path $Root "out\$id.json"))
        ($saved -replace "`r`n", "`n").Trim() | Should -Be $result.Output.Trim()
        (ConvertFrom-PureJson $saved).command | Should -Be 'suggest'
    }

    It 'puts the result file next to the runs of a relative -StateRoot' {
        $script:Root = [guid]::NewGuid().ToString()
        $id = [guid]::NewGuid().ToString()
        Push-Location -LiteralPath $TestDrive
        try {
            $result = Invoke-Tuneup @('-Yes', '-Json', '-ResultId', $id)
        } finally {
            Pop-Location
        }
        $result.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $result.Output).runDir | Should -BeLike (Join-Path $TestDrive "$Root\runs\*")
        Test-Path -LiteralPath (Join-Path $TestDrive "$Root\out\$id.json") | Should -BeTrue
    }

    It 'writes an error document to the result file too' {
        $id = [guid]::NewGuid().ToString()
        $result = Invoke-Tuneup @('-Profile', 'nope', '-WhatIf', '-Json', '-ResultId', $id)
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson ([System.IO.File]::ReadAllText((Join-Path $Root "out\$id.json")))).command | Should -Be 'error'
    }

    It 'writes the error of an unknown parameter to the result file' {
        $id = [guid]::NewGuid().ToString()
        $result = Invoke-Tuneup @('-Exlude', 'test.three', '-Json', '-ResultId', $id)
        $result.ExitCode | Should -Be 1
        $saved = ConvertFrom-PureJson ([System.IO.File]::ReadAllText((Join-Path $Root "out\$id.json")))
        $saved.message | Should -Match 'Unknown parameter or value without a parameter name: -Exlude test\.three'
    }

    It 'refuses -ResultId <Case> with an error document and writes no file' -TestCases @(
        @{ Case = 'that is too short'; Arguments = @('-Status', '-Json', '-ResultId', 'abc') }
        @{ Case = 'that is a path'; Arguments = @('-Status', '-Json', '-ResultId', '..\..\escape-1') }
        @{ Case = 'that is a relative path, with -List'; Arguments = @('-ResultId', '../x', '-Json', '-List') }
        @{ Case = 'that is invalid, with an unknown parameter too'; Arguments = @('-Bogus', '-Json', '-ResultId', 'abc') }
    ) {
        param($Arguments)
        $result = Invoke-Tuneup $Arguments
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be '-ResultId takes 8 to 64 letters (A-Z), digits or hyphens, starting with a letter or a digit, such as a GUID. Nothing was done.'
        Test-Path -LiteralPath (Join-Path $Root 'out') | Should -BeFalse
    }

    It 'refuses -ResultId without -Json' {
        $result = Invoke-Tuneup @('-Status', '-ResultId', [guid]::NewGuid().ToString())
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '-ResultId needs -Json'
        Test-Path -LiteralPath (Join-Path $Root 'out') | Should -BeFalse
    }

    It 'refuses an id whose file exists and changes nothing' {
        $id = [guid]::NewGuid().ToString()
        New-Item -ItemType Directory -Path (Join-Path $Root 'out') -Force | Out-Null
        $existing = Join-Path $Root "out\$id.json"
        [System.IO.File]::WriteAllText($existing, 'old')
        $result = Invoke-Tuneup @('-Yes', '-Json', '-ResultId', $id)
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be "The result $id already exists: use a new -ResultId. Nothing was done."
        [System.IO.File]::ReadAllText($existing) | Should -Be 'old'
        Test-Path -LiteralPath $Key | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $Root 'runs') | Should -BeFalse
    }

    It 'puts an old result that could not be removed in the warnings of the document' {
        $dir = Join-Path $Root 'out'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $start = [datetime]::UtcNow.AddDays(-1)
        for ($i = 1; $i -le 50; $i++) {
            $path = Join-Path $dir ('old-{0:D8}.json' -f $i)
            [System.IO.File]::WriteAllText($path, '{}')
            [System.IO.File]::SetLastWriteTimeUtc($path, $start.AddMinutes($i))
        }
        $id = [guid]::NewGuid().ToString()
        $lock = [System.IO.File]::Open((Join-Path $dir 'old-00000001.json'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $result = Invoke-Tuneup @('-Status', '-Json', '-ResultId', $id)
        } finally {
            $lock.Dispose()
        }
        $result.ExitCode | Should -Be 0
        @((ConvertFrom-PureJson $result.Output).warnings) -join "`n" | Should -Match 'Could not remove the old result file .*old-00000001\.json'
        @((ConvertFrom-PureJson ([System.IO.File]::ReadAllText((Join-Path $dir "$id.json")))).warnings) -join "`n" | Should -Match 'old-00000001\.json'
    }

    It 'reads a saved result back with -ReadResult, as it was written, with or without -Json' {
        $id = [guid]::NewGuid().ToString()
        (Invoke-Tuneup @('-Status', '-Json', '-ResultId', $id)).ExitCode | Should -Be 0
        $saved = [System.IO.File]::ReadAllText((Join-Path $Root "out\$id.json"))
        foreach ($arguments in @(@('-ReadResult', $id, '-Json'), @('-ReadResult', $id))) {
            $result = Invoke-Tuneup $arguments
            $result.ExitCode | Should -Be 0
            $result.Output.Trim() | Should -Be ($saved -replace "`r`n", "`n").Trim()
        }
    }

    It 'says why a result cannot be read, with its reason' {
        $id = [guid]::NewGuid().ToString()
        $result = Invoke-Tuneup @('-ReadResult', $id, '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        $json.reason | Should -Be 'result-missing'
        New-Item -ItemType Directory -Path (Join-Path $Root 'out') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $Root "out\$id.json"), '')
        $result = Invoke-Tuneup @('-ReadResult', $id, '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).reason | Should -Be 'result-incomplete'
    }

    It 'rejects -ReadResult with <Case>' -TestCases @(
        @{ Case = '-ResultId'; Arguments = @('-ResultId', 'abcd-1234-efgh'); Expected = '-ReadResult -ResultId' }
        @{ Case = 'another command'; Arguments = @('-Status'); Expected = '-Status -ReadResult' }
        @{ Case = 'an option of applying'; Arguments = @('-Yes'); Expected = '-ReadResult -Yes' }
    ) {
        param($Arguments, $Expected)
        $result = Invoke-Tuneup (@('-ReadResult', [guid]::NewGuid().ToString(), '-Json') + $Arguments)
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be "Invalid parameter combination: $Expected"
        Test-Path -LiteralPath (Join-Path $Root 'out') | Should -BeFalse
    }

    It 'exits with 2 instead of 0 when the result file cannot be saved' {
        # In this process, so that saving can fail: tuneup.ps1 then uses the module this file loaded.
        Mock Import-Module { }
        Mock Close-TuneupResultFile { $File.Stream.Dispose(); $false }
        $id = [guid]::NewGuid().ToString()
        $output = & (Join-Path $Repo 'tuneup.ps1') -StateRoot $Root -Lang en -Status -Json -ResultId $id
        $LASTEXITCODE | Should -Be 2
        (ConvertFrom-PureJson ($output -join "`n")).command | Should -Be 'status'
        Should -Invoke Close-TuneupResultFile -Times 1 -Exactly
    }

    It 'reports an actions folder script that runs code as a warning and keeps -Status working' {
        $actions = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $actions | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $actions 'bad-one.ps1'), 'Write-Output hello')
        $result = Invoke-Tuneup @('-WhatIf', '-Json') -Actions $actions
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        # The fixture catalog has an action tweak whose script is not in this folder.
        @($json.warnings) -join ' ' | Should -Match 'bad-one.ps1.*may only define functions'
        $result = Invoke-Tuneup @('-Status', '-Json') -Actions $actions
        $result.ExitCode | Should -Be 0
        @((ConvertFrom-PureJson $result.Output).warnings) -join ' ' | Should -Match 'bad-one.ps1.*may only define functions'
    }

    It 'fails the catalog check only for the tweaks whose action script could not be loaded' {
        $actions = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $actions | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $actions 'fixture-toggle.ps1'), 'Write-Output hello')
        $result = Invoke-Tuneup @('-WhatIf', '-Json') -Actions $actions
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        @($json.details) -join ' ' | Should -Match "test.action action script 'fixture-toggle' could not be loaded: .*may only define functions"
    }

    It 'keeps -Status, -Undo, -Health and -Measure working when a script of the repository actions folder is broken' {
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($item in 'tuneup.ps1', 'engine', 'i18n') { Copy-Item -LiteralPath (Join-Path $Repo $item) -Destination (Join-Path $copy $item) -Recurse }
        New-Item -ItemType Directory -Path (Join-Path $copy 'actions') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path (Join-Path $copy 'actions') 'bad-one.ps1'), 'Write-Output hi')
        $run = {
            param([string[]]$Arguments)
            $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copy 'tuneup.ps1') -StateRoot $script:Root -Lang en -Json @Arguments
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        }
        $status = & $run @('-Status')
        $status.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $status.Output
        $json.command | Should -Be 'status'
        @($json.warnings) -join ' ' | Should -Match 'bad-one.ps1.*may only define functions'
        $undo = & $run @('-Undo', 'last')
        $undo.ExitCode | Should -Be 1
        $undoJson = ConvertFrom-PureJson $undo.Output
        $undoJson.message | Should -Match 'no runs to undo'
        @($undoJson.warnings) -join ' ' | Should -Match 'bad-one.ps1'
        $measure = & $run @('-Measure')
        $measure.ExitCode | Should -Be 0
        $measureJson = ConvertFrom-PureJson $measure.Output
        $measureJson.command | Should -Be 'measure'
        @($measureJson.warnings) -join ' ' | Should -Match 'bad-one.ps1'
    }

    It 'says when the actions folder does not exist' {
        $result = Invoke-Tuneup @('-WhatIf', '-Json') -Actions (Join-Path $TestDrive 'no-such-actions')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'actions folder'
    }

    It 'says when -ActionsPath is a file and not a folder' {
        $file = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.ps1')
        [System.IO.File]::WriteAllText($file, 'function Get-Nothing { }')
        $result = Invoke-Tuneup @('-WhatIf', '-Json') -Actions $file
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'is not a folder'
    }

    It 'resolves a relative -ActionsPath against the current folder' {
        Copy-Item -LiteralPath (Join-Path $Fixtures 'actions') -Destination (Join-Path $TestDrive 'relative-actions') -Recurse
        Push-Location -LiteralPath $TestDrive
        try {
            $result = Invoke-Tuneup @('-Include', 'test.action', '-WhatIf', '-Json') -Actions 'relative-actions'
        } finally {
            Pop-Location
        }
        $result.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $result.Output).items.id | Should -Contain 'test.action'
    }

    It 'does not warn about -ActionsPath when not elevated' -Skip:$Elevated {
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-WhatIf', '-Json')).Output
        @($json.warnings).Count | Should -Be 0
    }

    It 'carries the -ActionsPath warning inside the JSON document when elevated' -Skip:(-not $Elevated) {
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-WhatIf', '-Json')).Output
        @($json.warnings) | Should -Contain '-ActionsPath loads functions that run with administrator rights; use only for development and testing'
    }

    It 'shows the plan as JSON without changing anything' {
        $result = Invoke-Tuneup @('-WhatIf', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.schemaVersion | Should -Be 1
        $json.command | Should -Be 'plan'
        $json.requiresAdmin | Should -BeFalse
        Get-Ids $json.items | Should -Be 'test.one,test.two'
        $json.environment.PSObject.Properties.Name -join ',' | Should -Be 'build,ubr,family,edition,isServer,isManaged,isAdmin,hasBattery,pendingReboot'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'applies, reports and is idempotent' {
        $result = Invoke-Tuneup @('-Yes', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'apply'
        $json.summary.applied | Should -Be 2
        $json.rebootRequired | Should -BeTrue
        $json.restorePoint | Should -Be 'not-needed'
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        $saved = Get-Content -LiteralPath (Join-Path $json.runDir 'result.json') -Raw | ConvertFrom-Json
        $saved.runId | Should -Be $json.runId
        $saved.PSObject.Properties.Name | Should -Not -Contain 'warnings'
        $again = (Invoke-Tuneup @('-WhatIf', '-Json')).Output | ConvertFrom-Json
        $again.summary.apply | Should -Be 0
    }

    It 'exits with 2 when part of the plan fails' {
        New-Item -Path $SubKey -Force | Out-Null
        Set-TestSetValueDeny
        $result = Invoke-Tuneup @('-Profile', 'nested', '-Yes', '-Json')
        $result.ExitCode | Should -Be 2
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.applied | Should -Be 2
        $json.summary.failed | Should -Be 1
        ($json.results | Where-Object { $_.id -eq 'test.four' }).status | Should -Be 'failed'
    }

    It 'exits with 1 when the journal cannot be written before any change' {
        # Windows PowerShell 5.1 does not take paths of 260 characters or more: the run folder and
        # its small files fit, the journal (snapshot.jsonl) does not.
        $script:Root = Join-Path $TestDrive ('j' * (224 - $TestDrive.Length))
        New-Item -ItemType Directory -Path $Root | Out-Null
        $probe = Join-Path $Root ('p' * (260 - $Root.Length))
        try { [System.IO.File]::WriteAllText($probe, 'x') } catch { $probe = $null }
        if ($probe) {
            Remove-Item -LiteralPath $probe -Force
            Set-ItResult -Skipped -Because 'this PowerShell accepts long paths'
            return
        }
        $result = Invoke-Tuneup @('-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.applied | Should -Be 0
        $json.summary.journalErrors | Should -Be 2
        ($json.results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'journal-error,journal-error'
        $json.results[0].error | Should -Not -BeNullOrEmpty
        (Get-ChildItem -LiteralPath (Get-RunDir) -Name) | Should -Contain 'result.json'
        Test-Path -LiteralPath $Key | Should -BeFalse
        $script:Root = Join-Path $TestDrive ('k' * (224 - $TestDrive.Length))
        $human = Invoke-Tuneup @('-Yes')
        $human.ExitCode | Should -Be 1
        $human.Output | Should -Match 'the backup could not be saved'
    }

    It 'reports drift in -Status' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-Status', '-Json')).Output
        ($json.items | Where-Object { $_.id -eq 'test.one' }).status | Should -Be 'drift'
        ($json.items | Where-Object { $_.id -eq 'test.two' }).status | Should -Be 'ok'
    }

    It 're-applies what drifted with -Status -Reapply -Yes' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $result = Invoke-Tuneup @('-Status', '-Reapply', '-Yes', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.source | Should -Be 'reapply'
        Get-Ids $json.results | Should -Be 'test.one'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }

    It 're-applies with -Status -Reapply -Include only the drifted tweaks it names' {
        Invoke-Tuneup @('-Profile', 'extra', '-Yes', '-Json') | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        Set-ItemProperty -LiteralPath $Key -Name 'Three' -Value 5
        $result = Invoke-Tuneup @('-Status', '-Reapply', '-Include', 'test.three', '-Yes', '-Json')
        $result.ExitCode | Should -Be 0
        Get-Ids (ConvertFrom-PureJson $result.Output).results | Should -Be 'test.three'
        (Get-ItemProperty -LiteralPath $Key).Three | Should -Be 1
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 5
    }

    It 'keeps the ids of result.json whatever the account is called, so -Status and -Reapply still work (<Name>)' -ForEach @(
        @{ Name = 'test' }, @{ Name = 'User' }, @{ Name = 'dev' }, @{ Name = 'apps' }
    ) {
        $previous = $env:USERNAME
        $env:USERNAME = $Name
        try {
            $applied = ConvertFrom-PureJson (Invoke-Tuneup @('-Yes', '-Json')).Output
            $text = [System.IO.File]::ReadAllText((Join-Path $applied.runDir 'result.json'))
            Get-Ids ($text | ConvertFrom-Json).results | Should -Be 'test.one,test.two'
            # The profile folder is written %USERPROFILE% (the state folder of the test is usually under it).
            $text | Should -Not -Match ('(?i)' + [regex]::Escape($env:USERPROFILE.TrimEnd('\').Replace('\', '\\')))
            if ($script:Root.StartsWith($env:USERPROFILE.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                ($text | ConvertFrom-Json).runDir | Should -Match '^%USERPROFILE%\\'
            }
            $status = ConvertFrom-PureJson (Invoke-Tuneup @('-Status', '-Json')).Output
            ($status.items | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.one=ok,test.two=ok'
            Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
            $reapply = Invoke-Tuneup @('-Status', '-Reapply', '-Yes', '-Json')
            $reapply.ExitCode | Should -Be 0
            Get-Ids (ConvertFrom-PureJson $reapply.Output).results | Should -Be 'test.one'
            (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        } finally {
            $env:USERNAME = $previous
        }
    }

    It 'opens the menu without a command and reads the answers from standard input' {
        # Optimize, only base, apply, back to the menu, exit.
        $answers = @('1', '', 'y', '', '0')
        $output = $answers | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles') `
            -ActionsPath (Join-Path $Fixtures 'actions') -StateRoot $script:Root -Force -Lang en
        $LASTEXITCODE | Should -Be 0
        $text = $output -join "`n"
        $text | Should -Match '1\. Optimize: choose profiles and apply them'
        $text | Should -Match 'Applied: 2'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }

    It 'does not open the menu with -NonInteractive, also with the input redirected, and says why' {
        $output = @('2') | & $PowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') -StateRoot $script:Root -Lang en 2>&1
        $LASTEXITCODE | Should -Be 1
        $text = $output -join "`n"
        $text | Should -Match 'PowerShell was started with -NonInteractive'
        $text | Should -Not -Match 'Read-Host|NonInteractive mode'
    }

    It 'leaves the menu at the end of standard input' {
        $output = @('2') | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') -StateRoot $script:Root -Lang en
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'windows-tuneup has not applied any tweak'
    }

    It 'undoes the last run' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $result.Output).summary.restored | Should -Be 2
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'exits with 2 when an undo restores only part of the run' {
        (Invoke-Tuneup @('-Profile', 'nested', '-Yes', '-Json')).ExitCode | Should -Be 0
        Set-TestSetValueDeny
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 2
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.restored | Should -Be 2
        $json.summary.failed | Should -Be 1
        (Get-ItemProperty -LiteralPath $SubKey).Four | Should -Be 1
    }

    It 'reports status and undoes a run without reading the catalog' -TestCases @(
        @{ Kind = 'broken' }
        @{ Kind = 'missing' }
    ) {
        param($Kind)
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        if ($Kind -eq 'broken') {
            $catalog = Join-Path $TestDrive 'broken-catalog'
            New-Item -ItemType Directory -Path $catalog | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $catalog 'bad.json'), '{ broken')
        } else {
            $catalog = Join-Path $TestDrive 'no-such-catalog'
        }
        $status = Invoke-Tuneup @('-Status', '-Json') -Catalog $catalog
        $status.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $status.Output
        $json.command | Should -Be 'status'
        Get-Ids $json.items | Should -Be 'test.one,test.two'
        $undo = Invoke-Tuneup @('-Undo', 'last', '-Json') -Catalog $catalog
        $undo.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $undo.Output).summary.restored | Should -Be 2
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'says the run does not exist for an unknown run id' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $result = Invoke-Tuneup @('-Undo', '19990101-000000', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'Run 19990101-000000 does not exist.'
        (Invoke-Tuneup @('-Undo', '19990101-000000') -Lang 'es').Output | Should -Match 'No existe la corrida 19990101-000000\.'
    }

    It 'says there is nothing to undo for last without runs' {
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'There are no runs to undo.'
    }

    It 'skips a tweak that was already undone and refuses to undo a run twice' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $runId = Split-Path (Get-RunDir) -Leaf
        (Invoke-Tuneup @('-Undo', $runId, '-Tweak', 'test.two', '-Json')).ExitCode | Should -Be 0
        $again = Invoke-Tuneup @('-Undo', $runId, '-Tweak', 'test.two', '-Json')
        $again.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $again.Output
        $json.results[0].status | Should -Be 'skipped'
        $json.results[0].reason | Should -Be 'already-undone'
        $json.summary.skipped | Should -Be 1
        (Invoke-Tuneup @('-Undo', $runId, '-Json')).ExitCode | Should -Be 0
        $twice = Invoke-Tuneup @('-Undo', $runId, '-Json')
        $twice.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $twice.Output).message | Should -Match 'already undone'
    }

    It 'accepts comma separated profiles and aliases' {
        $json = (Invoke-Tuneup @('-Profile', 'adicional,base', '-WhatIf', '-Json')).Output | ConvertFrom-Json
        Get-Ids $json.items | Should -Be 'test.one,test.two,test.three'
    }

    It 'resolves a relative -StateRoot against the current folder' {
        $script:Root = [guid]::NewGuid().ToString()
        Push-Location -LiteralPath $TestDrive
        try {
            $result = Invoke-Tuneup @('-Yes', '-Json')
        } finally {
            Pop-Location
        }
        $result.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $result.Output).runDir | Should -BeLike (Join-Path $TestDrive "$Root\runs\*")
    }

    It 'writes JSON as pure ASCII and keeps the accents' {
        $result = Invoke-Tuneup @('-Profile', 'extra', '-WhatIf', '-Json') -Lang 'es'
        [regex]::IsMatch($result.Output, '[^\x00-\x7F]') | Should -BeFalse
        $json = ConvertFrom-PureJson $result.Output
        ($json.items | Where-Object { $_.id -eq 'test.three' }).title | Should -Be ('Prueba tres: configuraci' + [char]0x00F3 + 'n')
        $failure = Invoke-Tuneup @('-Tweak', 'test.one', '-Json') -Lang 'es'
        [regex]::IsMatch($failure.Output, '[^\x00-\x7F]') | Should -BeFalse
        (ConvertFrom-PureJson $failure.Output).message | Should -BeLike ('Combinaci' + [char]0x00F3 + 'n de par' + [char]0x00E1 + 'metros no v' + [char]0x00E1 + 'lida*')
    }

    It 'exits with 1 on an unknown profile' {
        $result = Invoke-Tuneup @('-Profile', 'nope', '-WhatIf', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        $json.message | Should -Match 'nope'
    }

    It 'rejects <Arguments>' -TestCases @(
        @{ Arguments = @('-Tweak', 'test.one') }
        @{ Arguments = @('-Status', '-Undo', 'last') }
        @{ Arguments = @('-Status', '-WhatIf') }
        @{ Arguments = @('-Status', '-Include', 'test.three') }
        @{ Arguments = @('-Undo', 'last', '-Profile', 'extra') }
        @{ Arguments = @('-Undo', 'last', '-Yes') }
        @{ Arguments = @('-Undo', 'last', '-Exclude', 'test.one') }
        @{ Arguments = @('-Repair') }
        @{ Arguments = @('-Health', '-Status') }
        @{ Arguments = @('-Health', '-Profile', 'extra') }
        @{ Arguments = @('-Health', '-Undo', 'last') }
        @{ Arguments = @('-Compare', 'last') }
        @{ Arguments = @('-IdleSeconds', '5') }
        @{ Arguments = @('-Measure', '-Status') }
        @{ Arguments = @('-Measure', '-Yes') }
        @{ Arguments = @('-Reapply') }
        @{ Arguments = @('-Status', '-Yes') }
        @{ Arguments = @('-Status', '-Reapply', '-Profile', 'extra') }
    ) {
        param($Arguments)
        $result = Invoke-Tuneup (@($Arguments) + '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'Invalid parameter combination'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'rejects an unknown parameter <Arguments> with an error document, doing nothing' -TestCases @(
        @{ Arguments = @('-Bogus'); Unknown = '-Bogus' }
        @{ Arguments = @('-Profile', 'extra', '-Exlude', 'test.three', '-Yes'); Unknown = '-Exlude test.three' }
        @{ Arguments = @('base', '-Yes'); Unknown = 'base' }
    ) {
        param($Arguments, $Unknown)
        $result = Invoke-Tuneup (@($Arguments) + '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        $json.message | Should -Match ('Unknown parameter or value without a parameter name: ' + [regex]::Escape($Unknown))
        Test-Path -LiteralPath $Key | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Root 'runs') | Should -BeFalse
    }

    It 'rejects a misspelled parameter without -Json before planning anything' {
        $result = Invoke-Tuneup @('-Profile', 'extra', '-Exlude', 'test.three', '-WhatIf')
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Unknown parameter or value without a parameter name: -Exlude test\.three'
        $result.Output | Should -Not -Match 'Test one'
    }

    It 'refuses -Health without elevation' -Skip:$Elevated {
        $result = Invoke-Tuneup @('-Health', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be '-Health needs PowerShell as administrator.'
    }

    It 'measures, saves and compares against the last measurement' {
        $first = Invoke-Tuneup @('-Measure', '-Json')
        $first.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $first.Output
        $json.command | Should -Be 'measure'
        $json.comparison | Should -BeNullOrEmpty
        $json.measurement.metrics.processCount | Should -BeGreaterThan 0
        $json.PSObject.Properties.Name | Should -Contain 'warnings'
        Test-Path -LiteralPath $json.path | Should -BeTrue
        $second = ConvertFrom-PureJson (Invoke-Tuneup @('-Measure', '-Compare', 'last', '-Json')).Output
        $second.comparison.againstId | Should -Be $json.id
        @($second.comparison.items).Count | Should -Be 7
    }

    It 'says when the measurement to compare does not exist' {
        $result = Invoke-Tuneup @('-Measure', '-Compare', '19990101-000000', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'Measurement 19990101-000000 does not exist.'
    }

    It 'says there is nothing to compare against when no measurement was saved' {
        $result = Invoke-Tuneup @('-Measure', '-Compare', 'last', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'There are no saved measurements to compare against.'
        Test-Path -LiteralPath (Join-Path $Root 'measurements') | Should -BeFalse
    }

    It 'rejects -IdleSeconds <Seconds> as out of range, in the JSON document' -TestCases @(
        @{ Seconds = '-1' }
        @{ Seconds = '3601' }
    ) {
        param($Seconds)
        $result = Invoke-Tuneup @('-Measure', '-IdleSeconds', $Seconds, '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be '-IdleSeconds must be between 0 and 3600.'
        Test-Path -LiteralPath (Join-Path $Root 'measurements') | Should -BeFalse
    }

    It 'prints a measurement for people in the chosen language' {
        $result = Invoke-Tuneup @('-Measure') -Lang 'es'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Procesos: \d+'
    }

    It 'refuses to apply with -Json but without -Yes' {
        (Invoke-Tuneup @('-Json')).ExitCode | Should -Be 1
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'marks a plan with system changes as requiring elevation' {
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-Profile', 'system', '-WhatIf', '-Json')).Output
        $json.requiresAdmin | Should -BeTrue
        ($json.items | Where-Object { $_.id -eq 'test.machine' }).action | Should -Be 'apply'
    }

    It 'hints at elevation in a plan with system changes' -Skip:$Elevated {
        (Invoke-Tuneup @('-Profile', 'system', '-WhatIf')).Output | Should -Match 'To apply the system changes, open PowerShell as administrator'
    }

    It 'treats a policy value under HKCU as needing elevation' {
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-Include', 'test.policy', '-WhatIf', '-Json')).Output
        ($json.items | Where-Object { $_.id -eq 'test.policy' }).scope | Should -Be 'user'
        ($json.items | Where-Object { $_.id -eq 'test.policy' }).action | Should -Be 'apply'
        $json.requiresAdmin | Should -BeTrue
    }

    It 'refuses a policy value under HKCU without elevation, writing nothing' -Skip:$Elevated {
        $result = Invoke-Tuneup @('-Include', 'test.policy', '-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'The plan has system changes: open PowerShell as administrator.'
        Test-Path -LiteralPath "$Key\Policies" | Should -BeFalse
    }

    It 'refuses system changes without elevation' -Skip:$Elevated {
        $result = Invoke-Tuneup @('-Profile', 'system', '-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'The plan has system changes: open PowerShell as administrator.'
        Test-Path -LiteralPath $Key | Should -BeFalse
        Test-Path -LiteralPath 'HKLM:\SOFTWARE\windows-tuneup-test' | Should -BeFalse
    }

    It 'carries every JSON document a warnings array' {
        foreach ($arguments in @(@('-WhatIf', '-Json'), @('-Yes', '-Json'), @('-Status', '-Json'), @('-Undo', 'last', '-Json'), @('-Profile', 'nope', '-Json'),
                @('-List', '-Json'), @('-Suggest', '-Json'), @('-Status', '-Json', '-ResultId', 'short'))) {
            $json = ConvertFrom-PureJson (Invoke-Tuneup $arguments).Output
            $json.PSObject.Properties.Name | Should -Contain 'warnings' -Because ($arguments -join ' ')
        }
    }

    It 'puts -Status warnings inside the JSON document' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        [System.IO.File]::AppendAllText((Join-Path (Get-RunDir) 'snapshot.jsonl'), '{"id":"test.bro')
        $result = Invoke-Tuneup @('-Status', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        @($json.warnings | Where-Object { $_ -match 'incomplete last journal line' }).Count | Should -Be 1
        Get-Ids $json.items | Should -Be 'test.one,test.two'
    }

    It 'skips the tweaks of another user and exits with 1 when nothing was restored' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $runDir = Get-RunDir
        $info = Get-Content -LiteralPath (Join-Path $runDir 'run.json') -Raw | ConvertFrom-Json
        $info.userSid = 'S-1-5-21-1-2-3-1001'
        [System.IO.File]::WriteAllText((Join-Path $runDir 'run.json'), ($info | ConvertTo-Json))
        $result = Invoke-Tuneup @('-Undo', (Split-Path $runDir -Leaf), '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.restored | Should -Be 0
        $json.summary.skipped | Should -Be 2
        ($json.results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'other-user,other-user'
        @($json.warnings | Where-Object { $_ -match 'belongs to another user' }).Count | Should -Be 2
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        $human = Invoke-Tuneup @('-Undo', (Split-Path $runDir -Leaf))
        $human.ExitCode | Should -Be 1
        $human.Output | Should -Match 'Skipped: 2'
        @([regex]::Matches($human.Output, "Ignoring user-scope entry 'test.one'")).Count | Should -Be 1
    }

    It 'puts warnings inside the JSON error document' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path (Get-RunDir) 'run.json'), '{ broken')
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        @($json.warnings | Where-Object { $_ -match 'unreadable state file' }).Count | Should -Be 1
    }

    It 'prints warnings normally without -Json' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        [System.IO.File]::AppendAllText((Join-Path (Get-RunDir) 'snapshot.jsonl'), '{"id":"test.bro')
        $result = Invoke-Tuneup @('-Status')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'incomplete last journal line'
    }

    It 'refuses to undo a run with a policy value under HKCU when not elevated' -Skip:$Elevated {
        $run = New-TuneupRun -StateRoot $script:Root -WarningAction SilentlyContinue
        $policy = New-TestTweak -Id 'test.policy' -Scope 'user' -Set ([pscustomobject]@{ path = 'HKCU:\Software\windows-tuneup-test\Policies\Sub'; name = 'Policy'; kind = 'DWord'; value = 1 })
        Add-TuneupJournalEntry -Path (Join-Path $run.Dir 'snapshot.jsonl') -Tweak $policy -State ([pscustomobject]@{ exists = $false }) -Root 'custom'
        $result = Invoke-Tuneup @('-Undo', $run.Id, '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match "Run $([regex]::Escape($run.Id)) has system changes: undoing it needs PowerShell as administrator"
    }

    It 'refuses to undo a run with a machine-scope entry when not elevated' -Skip:$Elevated {
        $run = New-TuneupRun -StateRoot $script:Root -WarningAction SilentlyContinue
        Add-TuneupJournalEntry -Path (Join-Path $run.Dir 'snapshot.jsonl') -Tweak (New-TestMachineTweak) -State $null -Root 'custom'
        $result = Invoke-Tuneup @('-Undo', $run.Id, '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        $json.message | Should -Match 'undoing it needs PowerShell as administrator'
        $json.reason | Should -Be 'needs-admin'
        Test-Path -LiteralPath 'HKLM:\Software\windows-tuneup-test' | Should -BeFalse
    }
}
