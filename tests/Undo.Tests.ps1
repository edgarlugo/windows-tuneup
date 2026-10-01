BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:One = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'One'; kind = 'DWord'; value = 1 })
    $script:Two = New-TestTweak -Id 'test.two' -Set ([pscustomobject]@{ path = $Key; name = 'Two'; kind = 'String'; value = 'x' })
    function Invoke-TestApply([string]$Root) {
        $plan = @(New-TuneupPlan -Catalog @($One, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        $run = New-TuneupRun -StateRoot $Root
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir)
        Save-TuneupJson -Path (Join-Path $run.Dir 'result.json') -Object ([pscustomobject]@{ results = $results })
        $run
    }
}

Describe 'Undo and status' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        $env:TUNEUP_TEST_FAIL_RESTORE = $null
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'passes the note, detail and restart request of the restore into the result' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { New-TuneupOutcome -Reason 'reinstalled' -Detail 'for the current user only' -RebootRequired } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupUndo -Run $run)
        $results[0].id | Should -Be 'test.two'
        $results[0].status | Should -Be 'restored'
        $results[0].reason | Should -Be 'reinstalled'
        $results[0].detail | Should -Be 'for the current user only'
        $results[0].rebootRequired | Should -BeTrue
        $results[1].reason | Should -BeNullOrEmpty
        $results[1].rebootRequired | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
        Get-TuneupUndoExitCode -Results $results | Should -Be 0
    }

    It 'does not let stray output of a restore leak into the results' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { 'noise'; 42; New-TuneupOutcome -Reason 'reinstalled'; [pscustomobject]@{ id = 'fake'; status = 'restored' } } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupUndo -Run $run)
        $results.Count | Should -Be 2
        ($results | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.two,test.one'
        $results[0].reason | Should -Be 'reinstalled'
    }

    It 'restores the exact previous state' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'Two' -PropertyType String -Value 'old' | Out-Null
        $run = Invoke-TestApply $Root
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'restored,restored'
        $item = Get-Item -LiteralPath $Key
        $item.GetValueNames() -contains 'One' | Should -BeFalse
        $item.GetValue('Two') | Should -Be 'old'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
    }

    It 'removes keys that did not exist before' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run | Out-Null
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'reports a failure when the undo cannot be recorded' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Save-TuneupJson { throw [System.UnauthorizedAccessException]::new('Access denied') } -ParameterFilter { $Path -like '*undone.json' }
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'restored,restored,failed'
        $results[2].error | Should -BeLike '*Access denied*'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'refuses to undo a machine run without elevation' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        $machineRun = [pscustomobject]@{ Id = $run.Id; Dir = $run.Dir; Root = 'machine'; UserSid = $run.UserSid }
        { Invoke-TuneupUndo -Run $machineRun } | Should -Throw '*needs an elevated process'
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
    }

    It 'does not mark a run of another user as undone' {
        $run = Invoke-TestApply $Root
        $foreign = [pscustomobject]@{ Id = $run.Id; Dir = $run.Dir; Root = $run.Root; UserSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        $results = @(Invoke-TuneupUndo -Run $foreign -WarningAction SilentlyContinue)
        ($results | ForEach-Object { "$($_.id):$($_.status):$($_.reason)" }) -join ',' | Should -Be 'test.two:skipped:other-user,test.one:skipped:other-user'
        $results[0].title | Should -Be 'Title test.two'
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone-tweaks.txt') | Should -BeFalse
    }

    It 'skips a single tweak of another user' {
        $run = Invoke-TestApply $Root
        $foreign = [pscustomobject]@{ Id = $run.Id; Dir = $run.Dir; Root = $run.Root; UserSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        $results = @(Invoke-TuneupUndo -Run $foreign -TweakId 'test.one' -WarningAction SilentlyContinue)
        ($results | ForEach-Object { "$($_.id):$($_.status):$($_.reason)" }) -join ',' | Should -Be 'test.one:skipped:other-user'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }

    It 'undoes a single tweak' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        $item = Get-Item -LiteralPath $Key
        $item.GetValueNames() -contains 'One' | Should -BeFalse
        $item.GetValue('Two') | Should -Be 'x'
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.two'
    }

    It 'throws when the tweak is not in the run' {
        $run = Invoke-TestApply $Root
        { Invoke-TuneupUndo -Run $run -TweakId 'test.nope' } | Should -Throw
    }

    It 'reports ok and drift' {
        Invoke-TestApply $Root | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $status = @(Get-TuneupStatus -StateRoot $Root)
        ($status | Where-Object { $_.id -eq 'test.one' }).status | Should -Be 'drift'
        ($status | Where-Object { $_.id -eq 'test.two' }).status | Should -Be 'ok'
    }

    It 'ignores runs that were undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run | Out-Null
        @(Get-TuneupStatus -StateRoot $Root).Count | Should -Be 0
    }

    It 'plans nothing when applied twice' {
        Invoke-TestApply $Root | Out-Null
        $plan = @(New-TuneupPlan -Catalog @($One, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        @($plan | Where-Object { $_.Action -eq 'apply' }).Count | Should -Be 0
    }

    It 'keeps the run pending when a restore fails and finishes it on retry' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { throw 'restore broke' } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.id + ':' + $_.status }) -join ',' | Should -Be 'test.two:failed,test.one:restored'
        $results[0].error | Should -BeLike '*restore broke*'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone-tweaks.txt') | Should -BeTrue
        (Get-Item -LiteralPath $Key).GetValueNames() -contains 'One' | Should -BeFalse
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        Should -Invoke -ModuleName Tuneup Restore-TuneupState -Times 1 -Exactly -ParameterFilter { $Tweak.id -eq 'test.two' }
    }

    It 'retries the failed tweaks through the last pending run and then marks it undone' {
        $run = Invoke-TestApply $Root
        $env:TUNEUP_TEST_FAIL_RESTORE = '1'
        Mock -ModuleName Tuneup Restore-TuneupState {
            if ($env:TUNEUP_TEST_FAIL_RESTORE) { throw 'restore broke' }
            Restore-RegistryTweakState -Tweak $Tweak -State $State
        } -ParameterFilter { $Tweak.id -eq 'test.two' }
        Invoke-TuneupUndo -Run $run | Out-Null
        $env:TUNEUP_TEST_FAIL_RESTORE = $null
        $last = Resolve-TuneupRun -StateRoot $Root -RunId 'last'
        $last.Id | Should -Be $run.Id
        $results = @(Invoke-TuneupUndo -Run $last)
        ($results | ForEach-Object { $_.id + ':' + $_.status }) -join ',' | Should -Be 'test.two:restored'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
        (Get-Item -LiteralPath $Key).GetValueNames() -contains 'Two' | Should -BeFalse
        $null -eq (Resolve-TuneupRun -StateRoot $Root -RunId 'last') | Should -BeTrue
    }

    It 'skips a tweak that was already undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 7
        $results = @(Invoke-TuneupUndo -Run $run -TweakId 'test.one')
        $results.Count | Should -Be 1
        $results[0].status | Should -Be 'skipped'
        $results[0].reason | Should -Be 'already-undone'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 7
    }

    It 'does not restore again a tweak undone on its own when the whole run is undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 7
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.id + ':' + $_.status }) -join ',' | Should -Be 'test.two:restored'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 7
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
    }

    It 'marks the run undone once every tweak was undone one by one' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Invoke-TuneupUndo -Run $run -TweakId 'test.two' | Out-Null
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
        @(Get-TuneupStatus -StateRoot $Root).Count | Should -Be 0
    }

    It 'leaves out of the status a tweak whose apply failed' {
        $run = Invoke-TestApply $Root
        $results = @(
            [pscustomobject]@{ id = 'test.one'; status = 'failed' },
            [pscustomobject]@{ id = 'test.two'; status = 'applied' }
        )
        Save-TuneupJson -Path (Join-Path $run.Dir 'result.json') -Object ([pscustomobject]@{ results = $results })
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.two'
    }

    It 'counts the journaled tweaks of a run that was cut before its result' {
        $run = Invoke-TestApply $Root
        Remove-Item -LiteralPath (Join-Path $run.Dir 'result.json')
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id } | Sort-Object) -join ',' | Should -Be 'test.one,test.two'
    }

    It 'takes the definition from the latest run for the same tweak' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'OneB' -PropertyType DWord -Value 1 | Out-Null
        $first = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'One'; kind = 'DWord'; value = 1 })
        $second = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'OneB'; kind = 'DWord'; value = 1 })
        New-RunFolder -Root $Root -Id '20250101-000001' -Tweaks @($first) | Out-Null
        New-RunFolder -Root $Root -Id '20250101-000002' -Tweaks @($second) | Out-Null
        $status = @(Get-TuneupStatus -StateRoot $Root)
        $status.Count | Should -Be 1
        $status[0].runId | Should -Be '20250101-000002'
        $status[0].status | Should -Be 'ok'
    }

    It 'reports unknown when the state cannot be read' {
        Invoke-TestApply $Root | Out-Null
        Mock -ModuleName Tuneup Test-TuneupState { throw 'cannot read' }
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.status } | Select-Object -Unique) -join ',' | Should -Be 'unknown'
    }

    It 'reports not-present when the handler says so' {
        Invoke-TestApply $Root | Out-Null
        Mock -ModuleName Tuneup Test-TuneupState { 'not-present' }
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.status } | Select-Object -Unique) -join ',' | Should -Be 'not-present'
    }

    It 'refuses to undo a run that was already undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run | Out-Null
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'One' -PropertyType DWord -Value 9 | Out-Null
        { Invoke-TuneupUndo -Run $run } | Should -Throw '*already undone*'
        $resolved = Resolve-TuneupRun -StateRoot $Root -RunId $run.Id
        $resolved.Undone | Should -BeTrue
        { Invoke-TuneupUndo -Run $resolved } | Should -Throw '*already undone*'
        { Invoke-TuneupUndo -Run $resolved -TweakId 'test.one' } | Should -Throw '*already undone*'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 9
    }

    It 'keeps a partial tweak in the status' {
        $run = Invoke-TestApply $Root
        $results = @(
            [pscustomobject]@{ id = 'test.one'; status = 'partial' },
            [pscustomobject]@{ id = 'test.two'; status = 'failed' }
        )
        Save-TuneupJson -Path (Join-Path $run.Dir 'result.json') -Object ([pscustomobject]@{ results = $results })
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one'
    }

    It 'says a tweak needs elevation to check instead of reading it' {
        $appx = New-TestTweak -Id 'apps.news' -Type 'appx' -Scope 'machine' `
            -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
        New-RunFolder -Root $Root -Id '20250101-000000' -Tweaks @($appx) | Out-Null
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        Mock -ModuleName Tuneup Test-TuneupState { throw 'must not read' }
        $status = @(Get-TuneupStatus -StateRoot $Root)
        $status.Count | Should -Be 1
        $status[0].status | Should -Be 'needs-admin'
        Should -Invoke Test-TuneupState -ModuleName Tuneup -Times 0 -Exactly
    }
}
