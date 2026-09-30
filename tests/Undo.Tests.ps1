BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
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
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
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
        @(Invoke-TuneupUndo -Run $foreign -WarningAction SilentlyContinue).Count | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone-tweaks.txt') | Should -BeFalse
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
}
