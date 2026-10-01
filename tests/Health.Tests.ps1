BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Cbs = Join-Path $PSScriptRoot 'fixtures\cbs'
    function Get-CbsFixture([string]$Name) { @(Get-Content -LiteralPath (Join-Path $Cbs $Name) -Encoding UTF8) }
}

Describe 'CBS log window' {
    It 'keeps the lines from the start time on' {
        $lines = Get-CbsFixture 'sfc-repaired.log'
        $window = @(Select-TuneupCbsWindow -Lines $lines -Since ([datetime]'2026-09-30 09:47:00'))
        $window.Count | Should -Be ($lines.Count - 1)
        $window[0] | Should -Match '\[SR\] Verifying 100 components'
    }

    It 'stops at the end time and keeps lines without a time with the entry above' {
        $lines = @('2026-09-30 10:00:00, Info CBS first', 'continuation', '2026-09-30 10:00:05, Info CBS second', 'tail')
        @(Select-TuneupCbsWindow -Lines $lines -Since ([datetime]'2026-09-30 10:00:00') -Until ([datetime]'2026-09-30 10:00:01')) -join '|' |
            Should -Be '2026-09-30 10:00:00, Info CBS first|continuation'
    }
}

Describe 'SFC summary' {
    It 'lists the files SFC repaired' {
        $summary = Get-TuneupSfcSummary -Lines (Get-CbsFixture 'sfc-repaired.log')
        $summary.status | Should -Be 'repaired'
        $summary.repairedFiles -join ',' | Should -Be 'C:\WINDOWS\System32\drivers\BthA2dp.sys,C:\WINDOWS\System32\drivers\BthHfEnum.sys'
        @($summary.unrepairedFiles).Count | Should -Be 0
    }

    It 'is clean when SFC found nothing' {
        $lines = @(Get-CbsFixture 'sfc-repaired.log')[1..9]
        (Get-TuneupSfcSummary -Lines $lines).status | Should -Be 'clean'
    }

    It 'lists the files SFC could not repair once each' {
        $summary = Get-TuneupSfcSummary -Lines (Get-CbsFixture 'sfc-unrepaired.log')
        $summary.status | Should -Be 'unrepaired'
        $summary.unrepairedFiles -join ',' | Should -Be 'ci.dll,C:\WINDOWS\System32\drivers\bthmodem.sys'
    }

    It 'is unknown when SFC left no trace' {
        (Get-TuneupSfcSummary -Lines @('2026-09-30 10:00:00, Info                  CBS    Nothing here')).status | Should -Be 'unknown'
    }
}

Describe 'Component store summary' {
    It 'finds repairable damage after a scan' {
        $summary = Get-TuneupComponentStoreSummary -Lines (Get-CbsFixture 'scanhealth-corrupt.log')
        $summary.state | Should -Be 'repairable'
        $summary.operation | Should -Be 'Detect only'
        $summary.result | Should -Be '0x0'
        $summary.detected | Should -Be 6
        $summary.repaired | Should -Be 0
    }

    It 'reports a repair that fixed everything' {
        $summary = Get-TuneupComponentStoreSummary -Lines (Get-CbsFixture 'restorehealth-fixed.log')
        $summary.state | Should -Be 'repaired'
        $summary.repaired | Should -Be 6
    }

    It 'reports damage that a repair could not fix' {
        $summary = Get-TuneupComponentStoreSummary -Lines (Get-CbsFixture 'restorehealth-partial.log')
        $summary.state | Should -Be 'unrepairable'
        $summary.result | Should -Be '0x800f081f'
        $summary.repaired | Should -Be 5
    }

    It 'is healthy when nothing was detected' {
        $lines = @(
            '2026-09-30 10:00:00, Info                  CBS    Checking System Update Readiness.',
            '2026-09-30 10:00:00, Info                  CBS    Operation: Detect only ',
            "2026-09-30 10:00:00, Info                  CBS    Total Detected Corruption:`t0"
        )
        (Get-TuneupComponentStoreSummary -Lines $lines).state | Should -Be 'healthy'
    }

    It 'is unknown without a DISM summary' {
        (Get-TuneupComponentStoreSummary -Lines @('2026-09-30 10:00:00, Info                  CBS    Nothing here')).state | Should -Be 'unknown'
    }

    It 'uses the last check in the window' {
        $lines = @(Get-CbsFixture 'scanhealth-corrupt.log') + @(Get-CbsFixture 'restorehealth-fixed.log')
        (Get-TuneupComponentStoreSummary -Lines $lines).state | Should -Be 'repaired'
    }

    It 'reads the same values with spaces instead of tabs' {
        $lines = @(Get-CbsFixture 'scanhealth-corrupt.log') -replace "`t", '    '
        (Get-TuneupComponentStoreSummary -Lines $lines).detected | Should -Be 6
        @(Get-TuneupCorruptComponentGroup -Lines $lines).Count | Should -Be 3
    }
}

Describe 'Corrupt component groups' {
    It 'keeps the real tabs of CBS.log in the fixtures' {
        Get-Content -LiteralPath (Join-Path $Cbs 'scanhealth-corrupt.log') -Raw | Should -Match "`t"
    }

    It 'groups the damaged files by component' {
        $groups = @(Get-TuneupCorruptComponentGroup -Lines (Get-CbsFixture 'scanhealth-corrupt.log'))
        ($groups | ForEach-Object { "$($_.name):$($_.files)" }) -join ',' |
            Should -Be 'microsoft-windows-b..ore-bootmanager-efi:3,microsoft.ink:2,microsoft-windows-codeintegrity:1'
    }

    It 'leaves out what a repair fixed' {
        @(Get-TuneupCorruptComponentGroup -Lines (Get-CbsFixture 'restorehealth-fixed.log')).Count | Should -Be 0
    }

    It 'keeps what a repair could not fix' {
        $groups = @(Get-TuneupCorruptComponentGroup -Lines (Get-CbsFixture 'restorehealth-partial.log'))
        ($groups | ForEach-Object { "$($_.name):$($_.files)" }) -join ',' | Should -Be 'microsoft-windows-codeintegrity:1'
    }
}
