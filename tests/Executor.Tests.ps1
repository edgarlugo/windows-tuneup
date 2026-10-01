BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:One = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'One'; kind = 'DWord'; value = 1 })
    $script:Two = New-TestTweak -Id 'test.two' -RebootRequired $true -Set ([pscustomobject]@{ path = $Key; name = 'Two'; kind = 'String'; value = 'x' })
    function New-TestPlan {
        New-TuneupPlan -Catalog @($One, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak }
    }
}

Describe 'Invoke-TuneupPlan' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'applies the plan, journals each tweak first and reports the result' {
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'applied,applied'
        $results[0].rebootRequired | Should -BeFalse
        $results[1].rebootRequired | Should -BeTrue
        $journal = @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl'))
        $journal.Count | Should -Be 2
        $journal[0].id | Should -Be 'test.one'
        $journal[0].state.exists | Should -BeFalse
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
    }

    It 'passes skipped items through with their reason' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'One' -PropertyType DWord -Value 1 | Out-Null
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'skipped'
        $results[0].reason | Should -Be 'already-applied'
    }

    It 'marks a tweak that does not stick as not-applied' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'not-applied,not-applied'
    }

    It 'continues after a failing tweak' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { throw 'boom' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'failed'
        $results[0].error | Should -Be 'boom'
        $results[1].status | Should -Be 'applied'
    }

    It 'stops applying once the journal cannot be written' {
        Mock -ModuleName Tuneup Add-TuneupJournalEntry { throw 'disk full' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'skipped,skipped'
        ($results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'journal-error,journal-error'
        $results[0].error | Should -Be 'disk full'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'fails a tweak whose state cannot be read, without journaling or applying it' {
        $plan = @(New-TestPlan)
        Mock -ModuleName Tuneup Get-RegistryTweakState { throw 'cannot read' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $Run.Dir)
        $results[0].status | Should -Be 'failed'
        $results[0].error | Should -Be 'cannot read'
        $results[1].status | Should -Be 'applied'
        $journal = @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl'))
        $journal.Count | Should -Be 1
        $journal[0].id | Should -Be 'test.two'
        Should -Invoke -ModuleName Tuneup Set-RegistryTweakDesired -Times 0 -ParameterFilter { $Tweak.id -eq 'test.one' }
    }

    It 'does not leak handler output into the results' {
        $plan = @(New-TestPlan)
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { 'noise' }
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $Run.Dir)
        $results.Count | Should -Be 2
        @($results | Where-Object { $_ -is [string] }).Count | Should -Be 0
    }

    It 'passes the reason of the Set outcome into the result' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired {
            Write-TuneupRegistryValue -Path $Tweak.set.path -Name $Tweak.set.name -Kind $Tweak.set.kind -Value $Tweak.set.value
            New-TuneupOutcome -Reason 'reinstalled' -Detail 'note'
        } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'applied'
        $results[0].reason | Should -Be 'reinstalled'
        $results[0].detail | Should -Be 'note'
        $results[1].reason | Should -BeNullOrEmpty
    }

    It 'reports a partial change with its explanation' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { 'noise'; New-TuneupOutcome -Partial -Detail 'half done' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results.Count | Should -Be 2
        $results[0].status | Should -Be 'partial'
        $results[0].detail | Should -Be 'half done'
        $results[0].error | Should -BeNullOrEmpty
        $results[1].status | Should -Be 'applied'
        $results[1].detail | Should -BeNullOrEmpty
        @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl')).Count | Should -Be 2
    }

    It 'reports partial even when the state reads as applied' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired {
            Write-TuneupRegistryValue -Path $Tweak.set.path -Name $Tweak.set.name -Kind $Tweak.set.kind -Value $Tweak.set.value
            New-TuneupOutcome -Partial -Detail 'x'
        } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        Test-TuneupState -Tweak $One | Should -Be 'applied'
        $results[0].status | Should -Be 'partial'
        $results[0].detail | Should -Be 'x'
    }

    It 'adds a restart asked for by the handler to the catalog flag' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired {
            Write-TuneupRegistryValue -Path $Tweak.set.path -Name $Tweak.set.name -Kind $Tweak.set.kind -Value $Tweak.set.value
            New-TuneupOutcome -RebootRequired
        } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'applied'
        $results[0].rebootRequired | Should -BeTrue
    }
}

Describe 'Invoke-TuneupPlan with a refusal' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { New-TuneupOutcome -Refused -Reason 'sample-refusal' -Detail 'nothing was changed' } -ParameterFilter { $Tweak.id -eq 'test.one' }
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'reports a refused tweak as skipped with its reason and detail, and goes on' {
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'skipped'
        $results[0].reason | Should -Be 'sample-refusal'
        $results[0].detail | Should -Be 'nothing was changed'
        $results[0].error | Should -BeNullOrEmpty
        $results[1].status | Should -Be 'applied'
    }

    It 'keeps the journal entry and notes the tweak as needing no undo' {
        Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir | Out-Null
        @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl') | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one,test.two'
        @(Get-TuneupUndoneTweakId -Run $Run) -join ',' | Should -Be 'test.one'
    }

    It 'never restores the refused tweak when the run is undone' {
        Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir | Out-Null
        Mock -ModuleName Tuneup Restore-RegistryTweakState { } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupUndo -Run $Run)
        ($results | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.two=restored'
        Should -Invoke Restore-RegistryTweakState -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Tweak.id -eq 'test.one' }
        Test-Path -LiteralPath (Join-Path $Run.Dir 'undone.json') | Should -BeTrue
    }

    It 'warns, without failing the tweak, when the note cannot be written' {
        Mock -ModuleName Tuneup Write-TuneupStateFile { throw 'disk full' } -ParameterFilter { $Path -like '*undone-tweaks.txt' }
        $warnings = @()
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir -WarningVariable warnings -WarningAction SilentlyContinue)
        $results[0].status | Should -Be 'skipped'
        ($warnings -join ' ') | Should -BeLike '*test.one changed nothing*disk full*'
    }
}
