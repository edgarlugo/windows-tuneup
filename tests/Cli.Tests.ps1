BeforeDiscovery {
    $script:Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:SubKey = 'HKCU:\Software\windows-tuneup-test\Sub'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    function Invoke-Tuneup([string[]]$Arguments, [string]$Lang = 'en') {
        $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles') `
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

Describe 'ConvertTo-TuneupList' {
    It 'splits comma separated values from a single argument' {
        (ConvertTo-TuneupList -Value @('base, extra', 'dev')) -join '|' | Should -Be 'base|extra|dev'
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
    ) {
        param($Arguments)
        $result = Invoke-Tuneup (@($Arguments) + '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'Invalid parameter combination'
        Test-Path -LiteralPath $Key | Should -BeFalse
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

    It 'refuses system changes without elevation' -Skip:$Elevated {
        $result = Invoke-Tuneup @('-Profile', 'system', '-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'The plan has system changes: open PowerShell as administrator.'
        Test-Path -LiteralPath $Key | Should -BeFalse
        Test-Path -LiteralPath 'HKLM:\SOFTWARE\windows-tuneup-test' | Should -BeFalse
    }

    It 'carries every JSON document a warnings array' {
        foreach ($arguments in @(@('-WhatIf', '-Json'), @('-Yes', '-Json'), @('-Status', '-Json'), @('-Undo', 'last', '-Json'), @('-Profile', 'nope', '-Json'))) {
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
}
