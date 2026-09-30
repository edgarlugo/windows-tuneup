BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    function Invoke-Tuneup([string[]]$Arguments) {
        $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles') `
            -StateRoot $script:Root -Force -Lang en @Arguments
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
    function Get-Ids($Items) { ($Items | ForEach-Object { $_.id }) -join ',' }
    function Get-RunDir { @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'runs') -Directory | Sort-Object Name)[-1].FullName }
    # The whole standard output has to be one JSON document, with nothing printed around it.
    function ConvertFrom-PureJson([string]$Text) {
        $Text.Trim() | Should -Match '^\{[\s\S]*\}$'
        $Text | ConvertFrom-Json
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
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'shows the plan as JSON without changing anything' {
        $result = Invoke-Tuneup @('-WhatIf', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.schemaVersion | Should -Be 1
        $json.command | Should -Be 'plan'
        Get-Ids $json.items | Should -Be 'test.one,test.two'
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
        $again = (Invoke-Tuneup @('-WhatIf', '-Json')).Output | ConvertFrom-Json
        $again.summary.apply | Should -Be 0
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

    It 'exits with 1 on an unknown profile' {
        $result = Invoke-Tuneup @('-Profile', 'nope', '-WhatIf', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        $json.message | Should -Match 'nope'
    }

    It 'refuses to apply with -Json but without -Yes' {
        (Invoke-Tuneup @('-Json')).ExitCode | Should -Be 1
        Test-Path -LiteralPath $Key | Should -BeFalse
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

    It 'puts -Undo warnings inside the JSON document' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $runDir = Get-RunDir
        $info = Get-Content -LiteralPath (Join-Path $runDir 'run.json') -Raw | ConvertFrom-Json
        $info.userSid = 'S-1-5-21-1-2-3-1001'
        [System.IO.File]::WriteAllText((Join-Path $runDir 'run.json'), ($info | ConvertTo-Json))
        $result = Invoke-Tuneup @('-Undo', (Split-Path $runDir -Leaf), '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.restored | Should -Be 0
        @($json.warnings | Where-Object { $_ -match 'belongs to another user' }).Count | Should -Be 2
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
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
