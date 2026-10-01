BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    function New-TestResult([string]$Status, [string]$Reason, [string]$ErrorText) {
        [pscustomobject]@{ id = "test.$Status"; title = "Title $Status"; status = $Status; reason = $Reason; error = $ErrorText; rebootRequired = $false }
    }
    function New-TestReport([object[]]$Results) {
        New-TuneupApplyReport -Run ([pscustomobject]@{ Id = '20250101-000000'; Dir = 'C:\runs\20250101-000000' }) -Results $Results `
            -RestorePoint 'not-needed' -Environment (New-TestEnvironment)
    }
    function New-TestPlanItem([string]$Scope, [string]$Action) {
        $path = $(if ($Scope -eq 'machine') { 'HKLM:\SOFTWARE\windows-tuneup-test' } else { 'HKCU:\Software\windows-tuneup-test' })
        $tweak = New-TestTweak -Id "test.$Scope" -Scope $Scope -Set ([pscustomobject]@{ path = $path; name = 'X'; kind = 'DWord'; value = 1 })
        [pscustomobject]@{ Id = $tweak.id; Tweak = $tweak; Action = $Action; Reason = $(if ($Action -eq 'skip') { 'already-applied' } else { $null }) }
    }
    $script:JournalError = New-TestResult -Status 'skipped' -Reason 'journal-error' -ErrorText 'Disk full'
    $script:PlanSkip = New-TestResult -Status 'skipped' -Reason 'already-applied'
}

Describe 'Module' {
    It 'stops on errors inside the engine' {
        & (Get-Module Tuneup) { Get-Variable -Name ErrorActionPreference -Scope Script -ValueOnly -ErrorAction SilentlyContinue } | Should -Be 'Stop'
    }
}

Describe 'Write-TuneupJson' {
    It 'escapes every non-ASCII character' {
        $text = 'acci' + [char]0x00F3 + 'n ' + [char]::ConvertFromUtf32(0x1F600)
        $json = Write-TuneupJson ([pscustomobject]@{ text = $text })
        [regex]::IsMatch($json, '[^\x00-\x7F]') | Should -BeFalse
        $json | Should -Match '\\u00f3'
        ($json | ConvertFrom-Json).text | Should -Be $text
    }
}

Describe 'ConvertTo-TuneupEnvironmentView' {
    It 'uses camelCase keys' {
        $view = ConvertTo-TuneupEnvironmentView -Environment (New-TestEnvironment -Edition 'Home')
        $view.PSObject.Properties.Name -join ',' | Should -Be 'build,ubr,family,edition,isServer,isManaged,isAdmin,hasBattery,pendingReboot'
        $view.edition | Should -Be 'Home'
        $view.isAdmin | Should -BeTrue
    }
}

Describe 'New-TuneupApplyReport' {
    It 'counts journal errors apart from the skipped tweaks' {
        $report = New-TestReport @((New-TestResult -Status 'applied'), $JournalError, $PlanSkip)
        $report.summary.applied | Should -Be 1
        $report.summary.journalErrors | Should -Be 1
        $report.summary.skipped | Should -Be 1
        $report.environment.PSObject.Properties.Name | Should -Contain 'isAdmin'
    }
}

Describe 'Get-TuneupApplyExitCode' {
    It 'returns <Expected> for <Name>' -TestCases @(
        @{ Name = 'everything applied'; Statuses = @('applied', 'plan-skip'); NotSaved = $false; Expected = 0 }
        @{ Name = 'a tweak without effect'; Statuses = @('applied', 'not-applied'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a failed tweak'; Statuses = @('applied', 'failed'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a journal error before any change'; Statuses = @('journal-error', 'plan-skip'); NotSaved = $false; Expected = 1 }
        @{ Name = 'a journal error after a change'; Statuses = @('applied', 'journal-error'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a journal error after a failure'; Statuses = @('failed', 'journal-error'); NotSaved = $false; Expected = 2 }
        @{ Name = 'an unsaved result'; Statuses = @('applied'); NotSaved = $true; Expected = 2 }
        @{ Name = 'an unsaved result with nothing applied'; Statuses = @('journal-error'); NotSaved = $true; Expected = 1 }
    ) {
        param($Statuses, $NotSaved, $Expected)
        $results = @(foreach ($status in $Statuses) {
            switch ($status) {
                'plan-skip' { $PlanSkip }
                'journal-error' { $JournalError }
                default { New-TestResult -Status $status }
            }
        })
        Get-TuneupApplyExitCode -Report (New-TestReport $results) -ResultNotSaved:$NotSaved | Should -Be $Expected
    }
}

Describe 'Get-TuneupUndoExitCode' {
    It 'returns <Expected> for <Name>' -TestCases @(
        @{ Name = 'everything restored'; Results = @('restored', 'restored'); Expected = 0 }
        @{ Name = 'restored and already undone'; Results = @('restored', 'already-undone'); Expected = 0 }
        @{ Name = 'only already undone'; Results = @('already-undone'); Expected = 0 }
        @{ Name = 'restored and failed'; Results = @('restored', 'failed'); Expected = 2 }
        @{ Name = 'restored and of another user'; Results = @('restored', 'other-user'); Expected = 2 }
        @{ Name = 'only failed'; Results = @('failed'); Expected = 1 }
        @{ Name = 'only of another user'; Results = @('other-user', 'other-user'); Expected = 1 }
    ) {
        param($Results, $Expected)
        $items = @(foreach ($kind in $Results) {
            if ($kind -in 'already-undone', 'other-user') { New-TestResult -Status 'skipped' -Reason $kind } else { New-TestResult -Status $kind }
        })
        Get-TuneupUndoExitCode -Results $items | Should -Be $Expected
    }
}

Describe 'Save-TuneupApplyReport' {
    It 'saves result.json without warnings' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'custom' }
        Save-TuneupApplyReport -Run $run -Report (New-TestReport @(New-TestResult -Status 'applied')) | Should -BeTrue
        $saved = Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
        $saved.runId | Should -Be '20250101-000000'
        $saved.PSObject.Properties.Name | Should -Not -Contain 'warnings'
    }

    It 'warns instead of failing when result.json cannot be saved' {
        Mock -ModuleName Tuneup Save-TuneupJson { throw [System.UnauthorizedAccessException]::new('Access denied') }
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $TestDrive; Root = 'custom' }
        $saved = Save-TuneupApplyReport -Run $run -Report (New-TestReport @(New-TestResult -Status 'applied')) -WarningVariable warned -WarningAction SilentlyContinue
        $saved | Should -BeFalse
        "$($warned[0])" | Should -BeLike '*20250101-000000*Access denied*'
    }
}

Describe 'Write-TuneupApplyReport' {
    It 'lists journal errors with their error and hides plain skips' {
        $report = New-TestReport @((New-TestResult -Status 'applied'), $JournalError, $PlanSkip)
        $text = (Write-TuneupApplyReport -Report $report 6>&1 | Out-String)
        $text | Should -Match 'Title skipped'
        $text | Should -Match 'the backup could not be saved'
        $text | Should -Match 'Disk full'
        @([regex]::Matches($text, 'Title skipped')).Count | Should -Be 1
    }

    It 'adds the warnings only to the JSON document' {
        $report = New-TestReport @(New-TestResult -Status 'applied')
        $json = Write-TuneupApplyReport -Report $report -Warnings @('careful') -Json | ConvertFrom-Json
        @($json.warnings) -join ',' | Should -Be 'careful'
        $report.PSObject.Properties.Name | Should -Not -Contain 'warnings'
    }
}

Describe 'Write-TuneupPlanReport' {
    It 'marks a plan with system changes as requiring elevation' {
        $json = Write-TuneupPlanReport -Plan @((New-TestPlanItem 'user' 'apply'), (New-TestPlanItem 'machine' 'apply')) -Environment (New-TestEnvironment) -Json | ConvertFrom-Json
        $json.requiresAdmin | Should -BeTrue
        $json.environment.PSObject.Properties.Name | Should -Contain 'isAdmin'
        $json.environment.PSObject.Properties.Name -ccontains 'IsAdmin' | Should -BeFalse
    }

    It 'does not require elevation for skipped system tweaks' {
        $json = Write-TuneupPlanReport -Plan @((New-TestPlanItem 'user' 'apply'), (New-TestPlanItem 'machine' 'skip')) -Environment (New-TestEnvironment) -Json | ConvertFrom-Json
        $json.requiresAdmin | Should -BeFalse
    }

    It 'hints at elevation only when it is missing' {
        $plan = @(New-TestPlanItem 'machine' 'apply')
        $user = New-TestEnvironment
        $user.IsAdmin = $false
        (Write-TuneupPlanReport -Plan $plan -Environment $user 6>&1 | Out-String) | Should -Match 'To apply the system changes'
        (Write-TuneupPlanReport -Plan $plan -Environment (New-TestEnvironment) 6>&1 | Out-String) | Should -Not -Match 'To apply the system changes'
    }
}

Describe 'Write-TuneupUndoReport' {
    It 'shows skipped tweaks with their reason and counts them' {
        $results = @((New-TestResult -Status 'restored'), (New-TestResult -Status 'skipped' -Reason 'other-user'))
        $text = (Write-TuneupUndoReport -RunId '20250101-000000' -Results $results 6>&1 | Out-String)
        $text | Should -Match 'Title skipped: belongs to another user'
        $text | Should -Match 'Restored: 1 . Failed: 0 . Skipped: 1'
    }
}
