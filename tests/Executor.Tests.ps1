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

    It 'applies nothing once the journal cannot be written' {
        Mock -ModuleName Tuneup Add-TuneupJournalEntry { throw 'disk full' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'journal-error,journal-error'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }
}
