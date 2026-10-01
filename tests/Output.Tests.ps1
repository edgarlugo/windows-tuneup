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

    It 'counts partial tweaks and lets them ask for a restart' {
        $partial = New-TestResult -Status 'partial'
        $partial.rebootRequired = $true
        $report = New-TestReport @((New-TestResult -Status 'applied'), $partial)
        $report.summary.partial | Should -Be 1
        $report.summary.applied | Should -Be 1
        $report.rebootRequired | Should -BeTrue
        $report.summary.PSObject.Properties.Name -join ',' | Should -Be 'applied,partial,notApplied,failed,skipped,journalErrors'
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
        @{ Name = 'a partial tweak'; Statuses = @('applied', 'partial'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a journal error after a partial change'; Statuses = @('partial', 'journal-error'); NotSaved = $false; Expected = 2 }
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

    It 'shows a partial tweak with its explanation' {
        $partial = [pscustomobject]@{ id = 'test.partial'; title = 'Title partial'; status = 'partial'; reason = $null; error = $null; detail = 'Stopping it failed'; rebootRequired = $false }
        $text = (Write-TuneupApplyReport -Report (New-TestReport @($partial)) 6>&1 | Out-String)
        $text | Should -Match '\[partial\] Title partial'
        $text | Should -Match 'Stopping it failed'
        $text | Should -Match 'Applied: 0 \| Partial: 1 \| No effect: 0 \| Failed: 0 \| Skipped: 0'
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

    It 'explains a change that could not be checked without elevation' {
        $item = New-TestPlanItem 'machine' 'apply'
        $item.Reason = 'unverified-needs-admin'
        (Write-TuneupPlanReport -Plan @($item) -Environment (New-TestEnvironment) 6>&1 | Out-String) | Should -Match 'checked when applied'
    }
}

Describe 'Write-TuneupUndoReport' {
    It 'shows the restore note and asks for a restart' {
        $restored = [pscustomobject]@{ id = 'apps.news'; title = 'News'; status = 'restored'; reason = 'reinstalled'; error = $null; detail = 'Reinstalled for the current user'; rebootRequired = $true }
        $text = (Write-TuneupUndoReport -RunId '20250101-000000' -Results @($restored) 6>&1 | Out-String)
        $text | Should -Match 'News: reinstalled from the Microsoft Store'
        $text | Should -Match 'Reinstalled for the current user'
        $text | Should -Match 'Restart the computer'
        (Write-TuneupUndoReport -RunId '20250101-000000' -Results @($restored) -Json | ConvertFrom-Json).rebootRequired | Should -BeTrue
    }

    It 'shows skipped tweaks with their reason and counts them' {
        $results = @((New-TestResult -Status 'restored'), (New-TestResult -Status 'skipped' -Reason 'other-user'))
        $text = (Write-TuneupUndoReport -RunId '20250101-000000' -Results $results 6>&1 | Out-String)
        $text | Should -Match 'Title skipped: belongs to another user'
        $text | Should -Match 'Restored: 1 . Failed: 0 . Skipped: 1'
    }
}

Describe 'Write-TuneupHealthReport' {
    BeforeAll {
        $fixtures = Join-Path $PSScriptRoot 'fixtures\cbs'
        $lines = @(Get-Content -LiteralPath (Join-Path $fixtures 'sfc-repaired.log') -Encoding UTF8) +
            @(Get-Content -LiteralPath (Join-Path $fixtures 'scanhealth-corrupt.log') -Encoding UTF8)
        $ok = [pscustomobject]@{ ExitCode = 0; Output = '' }
        $script:Scan = New-TuneupHealthScan -Lines $lines -SfcRun $ok -DismRun $ok
        $script:HealthReport = [pscustomobject]@{
            schemaVersion = 1; command = 'health'; startedAt = '2026-09-30T10:00:00'; finishedAt = '2026-09-30T10:20:00'
            repairRequested = $false; repairRan = $false; before = $Scan; after = $null
            recommendation = 'run-repair'; rebootRecommended = $true
        }
    }

    It 'explains the scan to people' {
        $text = (Write-TuneupHealthReport -Report $HealthReport 6>&1 | Out-String)
        $text | Should -Match 'SFC: found damaged files and repaired them'
        $text | Should -Match 'repaired: C:\\WINDOWS\\System32\\drivers\\BthA2dp.sys'
        $text | Should -Match 'Component store: 6 corruptions found, repairable with -Health -Repair'
        $text | Should -Match 'microsoft-windows-b\.\.ore-bootmanager-efi: 3 files'
        $text | Should -Match 'run \.\\tuneup\.ps1 -Health -Repair'
        $text | Should -Match 'Restart the computer'
    }

    It 'does not promise a later repair when the repair is part of this run' {
        $report = $HealthReport | Select-Object -Property *
        $report.repairRequested = $true
        $text = (Write-TuneupHealthReport -Report $report 6>&1 | Out-String)
        $text | Should -Match 'Component store: 6 corruptions found; a repair will be attempted'
        $text | Should -Not -Match 'repairable with -Health -Repair'
    }

    It 'shows what the repair left and asks for a manual repair of the component store' {
        $ok = [pscustomobject]@{ ExitCode = -2146498529; Output = 'Error: 0x800f081f' }
        $partial = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\cbs\restorehealth-partial.log') -Encoding UTF8)
        $after = New-TuneupHealthScan -Lines $partial -SfcRun $ok -DismRun $ok
        $report = [pscustomobject]@{
            schemaVersion = 1; command = 'health'; startedAt = 'a'; finishedAt = 'b'; repairRequested = $true; repairRan = $true
            before = $Scan; after = $after; recommendation = 'manual-repair'; rebootRecommended = $false
        }
        $text = (Write-TuneupHealthReport -Report $report 6>&1 | Out-String)
        $text | Should -Match 'After the repair:'
        $text | Should -Match 'DISM could not complete the repair \(result 0x800f081f\)'
        $text | Should -Not -Match 'repaired 5 of 6'
        $text | Should -Match 'microsoft-windows-codeintegrity: 1 file\b'
        $text | Should -Match 'DISM ended with exit code -2146498529 \(0x800f081f\)'
        $text | Should -Match 'DISM could not repair everything'
    }

    It 'asks to review SFC when the component store is fine and SFC could not repair a file' {
        $lines = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\cbs\sfc-modern-unrepaired.log') -Encoding UTF8)
        $ok = [pscustomobject]@{ ExitCode = 0; Output = '' }
        $after = New-TuneupHealthScan -Lines $lines -SfcRun $ok -DismRun $ok
        $report = [pscustomobject]@{
            schemaVersion = 1; command = 'health'; startedAt = 'a'; finishedAt = 'b'; repairRequested = $true; repairRan = $true
            before = $Scan; after = $after; recommendation = 'manual-repair'; rebootRecommended = $false
        }
        $text = (Write-TuneupHealthReport -Report $report 6>&1 | Out-String)
        $text | Should -Match 'not repaired: pbrpwbt.exe'
        $text | Should -Match 'SFC still cannot repair some files'
        $text | Should -Not -Match 'DISM could not repair everything'
    }

    It 'keeps the DISM result and the hexadecimal exit codes in the JSON' {
        $json = Write-TuneupHealthReport -Report $HealthReport -Json | ConvertFrom-Json
        $json.before.componentStore.operationResult | Should -Be '0x0'
        $json.before.componentStore.exitCodeHex | Should -Be '0x0'
    }
    It 'writes one JSON document with the warnings' {
        $json = Write-TuneupHealthReport -Report $HealthReport -Warnings @('careful') -Json | ConvertFrom-Json
        $json.command | Should -Be 'health'
        $json.before.componentStore.detected | Should -Be 6
        @($json.warnings) -join ',' | Should -Be 'careful'
    }
}

Describe 'Format-TuneupMetric' {
    BeforeAll {
        # The separators follow the culture of the process; the tests pin one.
        $script:SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
    }

    AfterAll {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:SavedCulture
    }

    It 'shows a plus sign on a positive difference only' -TestCases @(
        @{ Value = 0.75; Expected = '+0.75' }
        @{ Value = 9; Expected = '+9' }
        @{ Value = -600; Expected = '-600' }
        @{ Value = 0; Expected = '0' }
        @{ Value = $null; Expected = 'n/a' }
    ) {
        param($Value, $Expected)
        Format-TuneupMetric -Value $Value -Signed | Should -Be $Expected
    }

    It 'shows a plain value without a sign' {
        Format-TuneupMetric -Value 101.25 | Should -Be '101.25'
    }
}

Describe 'Write-TuneupMeasureReport' {
    BeforeAll {
        $before = [pscustomobject]@{ metrics = [pscustomobject]@{ ramInUseMB = 6000; processCount = 160; runningServices = 120; enabledTasks = 150; systemDriveFreeGB = 100.5; bootDurationMs = $null; uptimeMinutes = 3 } }
        $measurement = [pscustomobject]@{
            schemaVersion = 1; takenAt = '2026-09-30T12:00:00'; idleSeconds = 120; environment = $null; id = '20260930-120000'
            metrics = [pscustomobject]@{ ramInUseMB = 5400; processCount = 140; runningServices = 110; enabledTasks = 130; systemDriveFreeGB = 101.25; bootDurationMs = $null; uptimeMinutes = 2 }
            notes = [pscustomobject]@{ bootDurationMs = 'needs-admin' }
        }
        $saved = [pscustomobject]@{ Id = '20260930-120000'; Path = 'C:\state\measurements\20260930-120000.json'; Root = 'custom'; Measurement = $measurement }
        $against = [pscustomobject]@{ Id = '20260929-090000'; Measurement = $before }
        $script:MeasureReport = New-TuneupMeasureReport -Saved $saved -Against $against
    }

    It 'builds the report with the comparison' {
        $MeasureReport.command | Should -Be 'measure'
        $MeasureReport.id | Should -Be '20260930-120000'
        $MeasureReport.comparison.againstId | Should -Be '20260929-090000'
        @($MeasureReport.comparison.items).Count | Should -Be 7
    }

    It 'shows the metrics, the reason for a missing one and the differences' {
        $text = (Write-TuneupMeasureReport -Report $MeasureReport 6>&1 | Out-String)
        $text | Should -Match 'RAM in use \(MB\): 5400'
        $text | Should -Match 'Last boot duration \(ms\): needs administrator'
        $text | Should -Match 'Difference from measurement 20260929-090000'
        $text | Should -Match 'RAM in use \(MB\): 6000 -> 5400 \(-600\)'
        $text | Should -Match 'Last boot duration \(ms\): n/a -> n/a \(n/a\)'
    }

    It 'writes one JSON document with the warnings' {
        $json = Write-TuneupMeasureReport -Report $MeasureReport -Warnings @('careful') -Json | ConvertFrom-Json
        $json.command | Should -Be 'measure'
        $json.measurement.metrics.ramInUseMB | Should -Be 5400
        @($json.warnings) -join ',' | Should -Be 'careful'
    }
}