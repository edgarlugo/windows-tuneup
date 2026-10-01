BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Cbs = Join-Path $PSScriptRoot 'fixtures\cbs'
    function Get-CbsFixture([string]$Name) { @(Get-Content -LiteralPath (Join-Path $Cbs $Name) -Encoding UTF8) }
    function Get-SrLine([string]$Text) { "2026-09-30 11:00:00, Info                  CSI    00000001 [SR] $Text" }
    $script:Ok = [pscustomobject]@{ ExitCode = 0; Output = '' }
    $script:HealthyStore = @(
        '2026-09-30 11:19:12, Info                  CBS    Checking System Update Readiness.',
        '2026-09-30 11:19:12, Info                  CBS    Operation: Detect only ',
        '2026-09-30 11:19:12, Info                  CBS    Operation result: 0x0',
        "2026-09-30 11:19:12, Info                  CBS    Total Detected Corruption:`t0"
    )
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
        $summary.unrepairedFiles -join ',' | Should -Be 'ci.dll (Microsoft-Windows-CodeIntegrity, amd64),C:\WINDOWS\System32\drivers\bthmodem.sys'
    }

    It 'reads the files that CSI writes between single quotes or without quotes' {
        $summary = Get-TuneupSfcSummary -Lines (Get-CbsFixture 'sfc-modern-unrepaired.log')
        $summary.status | Should -Be 'unrepaired'
        $summary.unrepairedFiles -join ',' | Should -Be 'pbrpwbt.exe (Microsoft-Windows-PbrpWBT, amd64)'
        $summary.repairedFiles -join ',' | Should -Be 'C:\WINDOWS\System32\opencl.dll'
    }

    It 'reads a repaired file written between double quotes' {
        $lines = @((Get-SrLine 'Verifying 1 components'), (Get-SrLine 'Repairing corrupted file [l:7]"ci.dll" from store'), (Get-SrLine 'Repair complete'))
        (Get-TuneupSfcSummary -Lines $lines).repairedFiles -join ',' | Should -Be 'ci.dll'
    }

    It 'does not take a file that cannot be repaired for an all clear' {
        $lines = @(Get-CbsFixture 'sfc-modern-unrepaired.log') + $HealthyStore
        $scan = New-TuneupHealthScan -Lines $lines -SfcRun $Ok -DismRun $Ok
        $scan.componentStore.state | Should -Be 'healthy'
        $scan.sfc.status | Should -Be 'unrepaired'
        Test-TuneupHealthNeedsRepair -Scan $scan | Should -BeTrue
        Get-TuneupHealthRecommendation -Scan $scan | Should -Be 'run-repair'
    }

    It 'prefers the full path that SFC gives for a file it could not repair' {
        $lines = @((Get-SrLine 'Verifying 1 components'),
            (Get-SrLine "Cannot repair member file [l:7]'ci.dll' of Microsoft-Windows-CodeIntegrity, version 10.0.1, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch"),
            (Get-SrLine 'Could not reproject corrupted file \??\C:\WINDOWS\System32\ci.dll; source file in store is also corrupted'),
            (Get-SrLine 'Repair complete'))
        (Get-TuneupSfcSummary -Lines $lines).unrepairedFiles -join ',' | Should -Be 'C:\WINDOWS\System32\ci.dll'
    }

    It 'keeps the copies of a file for each architecture apart' {
        $lines = @((Get-SrLine 'Verifying 2 components'),
            (Get-SrLine "Cannot repair member file [l:7]'ci.dll' of Microsoft-Windows-CodeIntegrity, version 10.0.1, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch"),
            (Get-SrLine "Cannot repair member file [l:7]'ci.dll' of Microsoft-Windows-CodeIntegrity, version 10.0.1, arch wow64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch"),
            (Get-SrLine 'Repair complete'))
        @((Get-TuneupSfcSummary -Lines $lines).unrepairedFiles).Count | Should -Be 2
    }

    It 'counts only the latest SFC run' {
        $second = @((Get-SrLine 'Verifying 100 components'), (Get-SrLine 'Repairing 0 components'), (Get-SrLine 'Repair complete'))
        $summary = Get-TuneupSfcSummary -Lines (@(Get-CbsFixture 'sfc-modern-unrepaired.log') + $second)
        $summary.status | Should -Be 'clean'
        @($summary.unrepairedFiles).Count | Should -Be 0
    }

    It 'is unknown when only an interrupted run is left' {
        $lines = @((Get-SrLine 'Verifying 100 components'),
            (Get-SrLine "Cannot repair member file [l:11]'pbrpwbt.exe' of Microsoft-Windows-PbrpWBT, version 10.0.1, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch"))
        (Get-TuneupSfcSummary -Lines $lines).status | Should -Be 'unknown'
    }

    It 'keeps the completed run when background noise follows it' {
        $lines = @(Get-CbsFixture 'sfc-modern-unrepaired.log') + @((Get-SrLine 'Verifying 1 components'), (Get-SrLine 'Verify complete'))
        $summary = Get-TuneupSfcSummary -Lines $lines
        $summary.status | Should -Be 'unrepaired'
        $summary.unrepairedFiles -join ',' | Should -Be 'pbrpwbt.exe (Microsoft-Windows-PbrpWBT, amd64)'
    }

    It 'keeps the completed run when an interrupted one follows it' {
        $lines = @(Get-CbsFixture 'sfc-modern-unrepaired.log') + @((Get-SrLine 'Verifying 100 components'),
            (Get-SrLine "Cannot repair member file [l:7]'other.dll' of Microsoft-Windows-Other, version 10.0.1, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch"))
        (Get-TuneupSfcSummary -Lines $lines).unrepairedFiles -join ',' | Should -Be 'pbrpwbt.exe (Microsoft-Windows-PbrpWBT, amd64)'
    }

    It 'does not read the driver lines that follow an interrupted run' {
        $lines = @(Get-CbsFixture 'sfc-modern-unrepaired.log') + @((Get-SrLine 'Verifying 100 components'), '2026-09-30 11:00:00, Info DEPLOY [Pnp] Corrupt file: C:\x.sys')
        (Get-TuneupSfcSummary -Lines $lines).unrepairedFiles -join ',' | Should -Be 'pbrpwbt.exe (Microsoft-Windows-PbrpWBT, amd64)'
    }

    It 'keeps the damage that SFC found in an early batch of its run' {
        $batches = 1..30 | ForEach-Object { (Get-SrLine 'Verifying 100 components'), (Get-SrLine 'Verify complete') }
        $damage = Get-SrLine "Cannot repair member file [l:11]'pbrpwbt.exe' of Microsoft-Windows-PbrpWBT, version 10.0.1, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch"
        $lines = @((Get-SrLine 'Verifying 100 components'), $damage) + @($batches) + @((Get-SrLine 'Verifying 32 components'), (Get-SrLine 'Repairing 0 components'), (Get-SrLine 'Repair complete'))
        (Get-TuneupSfcSummary -Lines $lines).status | Should -Be 'unrepaired'
    }

    It 'reads the files of the driver lines that follow the end of the run' {
        $lines = @((Get-SrLine 'Verifying 32 components'), (Get-SrLine 'Repairing 0 components'), (Get-SrLine 'Repair complete'), '2026-09-30 11:00:00, Info DEPLOY [Pnp] Corrupt file: C:\WINDOWS\System32\drivers\x.sys')
        (Get-TuneupSfcSummary -Lines $lines).unrepairedFiles -join ',' | Should -Be 'C:\WINDOWS\System32\drivers\x.sys'
    }

    It 'ignores [SR] lines that are not part of an SFC run' {
        (Get-TuneupSfcSummary -Lines @((Get-SrLine 'Repairing 3 components'))).status | Should -Be 'unknown'
        $lines = @((Get-SrLine 'Repairing 3 components'), (Get-SrLine 'Verifying 100 components'), (Get-SrLine 'Repairing 0 components'), (Get-SrLine 'Repair complete'))
        (Get-TuneupSfcSummary -Lines $lines).status | Should -Be 'clean'
    }

    It 'is repaired when SFC repaired components without naming files' {
        (Get-TuneupSfcSummary -Lines @((Get-SrLine 'Verifying 100 components'), (Get-SrLine 'Repairing 2 components'), (Get-SrLine 'Repair complete'))).status | Should -Be 'repaired'
        (Get-TuneupSfcSummary -Lines @((Get-SrLine 'Verifying 100 components'), (Get-SrLine 'Repairing 0 components'), (Get-SrLine 'Repair complete'))).status | Should -Be 'clean'
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

    It 'is unknown when a scan failed and counted nothing' {
        $lines = $HealthyStore -replace 'result: 0x0', 'result: 0x800f0906'
        $summary = Get-TuneupComponentStoreSummary -Lines $lines
        $summary.state | Should -Be 'unknown'
        $summary.result | Should -Be '0x800f0906'
    }

    It 'is unrepairable when a repair failed even if it counted everything as repaired' {
        $lines = @(
            '2026-09-30 10:40:00, Info                  CBS    Checking System Update Readiness.',
            '2026-09-30 10:40:00, Info                  CBS    Operation: Detect and Repair ',
            '2026-09-30 10:40:00, Info                  CBS    Operation result: 0x800f081f',
            "2026-09-30 10:40:00, Info                  CBS    Total Detected Corruption:`t3",
            "2026-09-30 10:40:00, Info                  CBS    Total Repaired Corruption:`t3"
        )
        (Get-TuneupComponentStoreSummary -Lines $lines).state | Should -Be 'unrepairable'
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

Describe 'CBS log files' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Folder | Out-Null
        $script:Since = [datetime]'2026-09-30 10:00:00'
        $script:Current = Join-Path $Folder 'CBS.log'
    }

    It 'reads the logs rotated since the start and then CBS.log' {
        $old = Join-Path $Folder 'CbsPersist_20260929000000.log'
        [System.IO.File]::WriteAllText($old, "2026-09-30 10:00:30, Info CBS old`r`n")
        (Get-Item -LiteralPath $old).LastWriteTime = $Since.AddDays(-1)
        $rotated = Join-Path $Folder 'CbsPersist_20260930100500.log'
        [System.IO.File]::WriteAllText($rotated, "2026-09-30 09:59:00, Info CBS before`r`n2026-09-30 10:01:00, Info CBS rotated`r`n")
        (Get-Item -LiteralPath $rotated).LastWriteTime = $Since.AddMinutes(5)
        [System.IO.File]::WriteAllText($Current, "2026-09-30 10:06:00, Info CBS current`r`n")
        @(Read-TuneupCbsLog -Since $Since -Folder $Folder) -join '|' |
            Should -Be '2026-09-30 10:01:00, Info CBS rotated|2026-09-30 10:06:00, Info CBS current'
    }

    It 'reads CBS.log while another process keeps it open for writing' {
        [System.IO.File]::WriteAllText($Current, "2026-09-30 10:06:00, Info CBS current`r`n")
        $writer = [System.IO.FileStream]::new($Current, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
        try {
            @(Read-TuneupCbsLog -Since $Since -Folder $Folder).Count | Should -Be 1
        } finally {
            $writer.Dispose()
        }
    }

    It 'returns nothing when there are no logs' {
        @(Read-TuneupCbsLog -Since $Since -Folder $Folder).Count | Should -Be 0
    }

    It 'returns nothing when the folder does not exist' {
        @(Read-TuneupCbsLog -Since $Since -Folder (Join-Path $Folder 'missing')).Count | Should -Be 0
    }

    It 'lists the logs again when one rotates away before it is opened' {
        [System.IO.File]::WriteAllText($Current, "2026-09-30 10:06:00, Info CBS current`r`n")
        $script:Listings = 0
        Mock -ModuleName Tuneup Get-TuneupCbsLogFile {
            $script:Listings++
            if ($script:Listings -eq 1) { Join-Path $script:Folder 'CbsPersist_gone.log' } else { $script:Current }
        }
        @(Read-TuneupCbsLog -Since $Since -Folder $Folder) -join '|' | Should -Be '2026-09-30 10:06:00, Info CBS current'
        $script:Listings | Should -Be 2
    }

    It 'fails when the log is still missing the second time' {
        Mock -ModuleName Tuneup Get-TuneupCbsLogFile { Join-Path $script:Folder 'CbsPersist_gone.log' }
        { Read-TuneupCbsLog -Since $Since -Folder $Folder } | Should -Throw
    }
}

Describe 'Tool output' {
    It 'decodes UTF-16 output' {
        $bytes = [System.Text.Encoding]::Unicode.GetBytes("Beginning system scan.`r`nVerification 100% complete.`r`n")
        ConvertFrom-TuneupToolOutput -Bytes $bytes | Should -Be ("Beginning system scan." + [Environment]::NewLine + "Verification 100% complete.")
    }

    It 'decodes output in the OEM code page' {
        $oem = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        ConvertFrom-TuneupToolOutput -Bytes $oem.GetBytes("Error: 87`r`n`r`nThe parameter is incorrect.`r`n") |
            Should -Be ("Error: 87" + [Environment]::NewLine + "The parameter is incorrect.")
    }

    It 'keeps only the last 15 lines' {
        $text = (1..20 | ForEach-Object { "line $_" }) -join "`r`n"
        $lines = (ConvertFrom-TuneupToolOutput -Bytes ([System.Text.Encoding]::ASCII.GetBytes($text))) -split [Environment]::NewLine
        $lines.Count | Should -Be 15
        $lines[0] | Should -Be 'line 6'
    }

    It 'decodes UTF-16 output when told so, even without many zero bytes' {
        $text = ([string][char]0x65E5) * 12
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($text)
        ConvertFrom-TuneupToolOutput -Bytes $bytes -Encoding Unicode | Should -Be $text
    }

    It 'decodes the output of a tool that writes UTF-16' {
        $result = Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments @('/u', '/c', 'echo', 'hola') -Encoding Unicode
        $result.Output | Should -Be 'hola'
    }

    It 'uses the 32-bit-proof folder of the system tools' {
        Get-TuneupSystemToolPath -Name 'sfc.exe' -Is64BitOperatingSystem $true -Is64BitProcess $false | Should -BeLike '*\Sysnative\sfc.exe'
        Get-TuneupSystemToolPath -Name 'sfc.exe' -Is64BitOperatingSystem $true -Is64BitProcess $true | Should -BeLike '*\System32\sfc.exe'
        Get-TuneupSystemToolPath -Name 'sfc.exe' -Is64BitOperatingSystem $false -Is64BitProcess $false | Should -BeLike '*\System32\sfc.exe'
    }

    It 'returns an empty text for no output' {
        ConvertFrom-TuneupToolOutput -Bytes ([byte[]]@()) | Should -Be ''
    }

    It 'runs a tool and returns its exit code and output' {
        $result = Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments @('/c', 'echo', 'hola&', 'exit', '3')
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Be 'hola'
    }

    It 'runs sfc /scannow and DISM with English output' {
        Mock -ModuleName Tuneup Invoke-TuneupHealthTool { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Invoke-TuneupSfc | Out-Null
        Invoke-TuneupDism -Operation 'RestoreHealth' | Out-Null
        Should -Invoke Invoke-TuneupHealthTool -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\sfc.exe' -and ($Arguments -join ' ') -eq '/scannow' -and $Encoding -eq 'Unicode'
        }
        Should -Invoke Invoke-TuneupHealthTool -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\Dism.exe' -and ($Arguments -join ' ') -eq '/Online /Cleanup-Image /RestoreHealth /English' -and $Encoding -eq 'Oem'
        }
    }
}

Describe 'Invoke-TuneupHealth' {
    BeforeAll {
        $script:Healthy = @(
            '2026-09-30 10:00:00, Info                  CSI    00000001 [SR] Verifying 100 components',
            '2026-09-30 10:00:00, Info                  CSI    00000002 [SR] Repairing 0 components',
            '2026-09-30 10:00:00, Info                  CSI    00000003 [SR] Repair complete',
            '2026-09-30 10:00:01, Info                  CBS    Checking System Update Readiness.',
            '2026-09-30 10:00:01, Info                  CBS    Operation: Detect only ',
            "2026-09-30 10:00:01, Info                  CBS    Total Detected Corruption:`t0"
        )
        $script:Corrupt = @($Healthy[0..2]) + @(Get-CbsFixture 'scanhealth-corrupt.log')
        $script:Fixed = @(Get-CbsFixture 'restorehealth-fixed.log') + @($Healthy[0..2])
        $script:NotFixed = @(Get-CbsFixture 'restorehealth-partial.log') + @($Healthy[0..2])
    }

    BeforeEach {
        $script:Phase = 'scan'
        Mock -ModuleName Tuneup Invoke-TuneupSfc { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock -ModuleName Tuneup Invoke-TuneupDism {
            if ($Operation -eq 'RestoreHealth') { $script:Phase = 'repair' }
            [pscustomobject]@{ ExitCode = 0; Output = '' }
        }
    }

    It 'reports a healthy Windows and does not repair it' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Healthy }
        $report = Invoke-TuneupHealth -Repair
        $report.command | Should -Be 'health'
        $report.schemaVersion | Should -Be 1
        $report.before.sfc.status | Should -Be 'clean'
        $report.before.componentStore.state | Should -Be 'healthy'
        $report.repairRequested | Should -BeTrue
        $report.repairRan | Should -BeFalse
        $report.after | Should -BeNullOrEmpty
        $report.recommendation | Should -Be 'none'
        $report.rebootRecommended | Should -BeFalse
        Get-TuneupHealthExitCode -Report $report | Should -Be 0
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'recommends a repair without running it' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Corrupt }
        $report = Invoke-TuneupHealth
        $report.before.componentStore.state | Should -Be 'repairable'
        @($report.before.corruptComponents).Count | Should -Be 3
        $report.recommendation | Should -Be 'run-repair'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'repairs, checks again and reports before and after' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $script:Fixed } else { $script:Corrupt } }
        $report = Invoke-TuneupHealth -Repair
        $report.before.componentStore.state | Should -Be 'repairable'
        $report.repairRan | Should -BeTrue
        $report.after.componentStore.state | Should -Be 'repaired'
        @($report.after.corruptComponents).Count | Should -Be 0
        $report.recommendation | Should -Be 'none'
        $report.rebootRecommended | Should -BeTrue
        Get-TuneupHealthExitCode -Report $report | Should -Be 0
        Should -Invoke Invoke-TuneupSfc -ModuleName Tuneup -Times 2 -Exactly
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'asks for a manual repair when DISM could not fix everything' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $script:NotFixed } else { $script:Corrupt } }
        $report = Invoke-TuneupHealth -Repair
        $report.after.componentStore.state | Should -Be 'unrepairable'
        $report.recommendation | Should -Be 'manual-repair'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
    }

    It 'asks to check the logs when DISM fails' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Healthy }
        Mock -ModuleName Tuneup Invoke-TuneupDism { [pscustomobject]@{ ExitCode = 87; Output = 'Error: 87' } }
        $report = Invoke-TuneupHealth
        $report.before.componentStore.exitCode | Should -Be 87
        $report.before.componentStore.output | Should -Be 'Error: 87'
        $report.recommendation | Should -Be 'check-logs'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
    }

    It 'shows the exit code of SFC without letting it decide' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Healthy }
        Mock -ModuleName Tuneup Invoke-TuneupSfc { [pscustomobject]@{ ExitCode = 1; Output = 'Windows Resource Protection found corrupt files' } }
        $report = Invoke-TuneupHealth
        $report.before.sfc.exitCode | Should -Be 1
        $report.before.sfc.output | Should -Match 'corrupt files'
        $report.recommendation | Should -Be 'none'
    }

    It 'reads the log of the scan up to its end and the log of the repair from there on' {
        $script:Reads = @()
        $script:Times = [System.Collections.Generic.Queue[datetime]]::new()
        $script:Times.Enqueue([datetime]'2026-09-30 10:00:00')
        $script:Times.Enqueue([datetime]'2026-09-30 10:05:00')
        Mock -ModuleName Tuneup Get-TuneupLogTime { $script:Times.Dequeue() }
        Mock -ModuleName Tuneup Read-TuneupCbsLog {
            $script:Reads += [pscustomobject]@{ Since = $Since; HasUntil = ($null -ne $Until); Until = $Until }
            if ($script:Phase -eq 'repair') { $script:Fixed } else { $script:Corrupt }
        }
        Invoke-TuneupHealth -Repair | Out-Null
        $script:Reads.Count | Should -Be 2
        $script:Reads[0].HasUntil | Should -BeTrue
        $script:Reads[0].Until | Should -BeGreaterOrEqual $script:Reads[0].Since
        $script:Reads[1].HasUntil | Should -BeFalse
        $script:Reads[1].Since | Should -Be $script:Reads[0].Until
        $script:Reads[1].Since | Should -Not -Be $script:Reads[0].Since
    }

    It 'asks for a manual repair when SFC still cannot repair after DISM fixed the store' {
        $stillBroken = @(Get-CbsFixture 'restorehealth-fixed.log') + @(Get-CbsFixture 'sfc-modern-unrepaired.log')
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $stillBroken } else { $script:Corrupt } }
        $report = Invoke-TuneupHealth -Repair
        $report.after.componentStore.state | Should -Be 'repaired'
        $report.after.sfc.status | Should -Be 'unrepaired'
        $report.recommendation | Should -Be 'manual-repair'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
    }

    It 'does not repair when the result could not be read' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { @($script:Healthy[0]) }
        $report = Invoke-TuneupHealth -Repair
        $report.before.componentStore.state | Should -Be 'unknown'
        $report.repairRan | Should -BeFalse
        $report.recommendation | Should -Be 'check-logs'
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'recommends the repair for a repairable store although SFC left no trace' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { Get-CbsFixture 'scanhealth-corrupt.log' }
        $report = Invoke-TuneupHealth
        $report.before.sfc.status | Should -Be 'unknown'
        $report.recommendation | Should -Be 'run-repair'
    }

    It 'reports each phase as it starts' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $script:Fixed } else { $script:Corrupt } }
        $script:Phases = @()
        Invoke-TuneupHealth -Repair -OnPhase { param($Name) $script:Phases += $Name } | Out-Null
        $script:Phases -join ',' | Should -Be 'sfc,dismScan,dismRestore,sfcAgain'
        $script:Phases = @()
        Invoke-TuneupHealth -OnPhase { param($Name) $script:Phases += $Name } | Out-Null
        $script:Phases -join ',' | Should -Be 'sfc,dismScan'
    }

    It 'keeps the DISM operation result and the exit codes in hex' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:NotFixed }
        Mock -ModuleName Tuneup Invoke-TuneupDism { [pscustomobject]@{ ExitCode = -2146498529; Output = 'Error: 0x800f081f' } }
        $report = Invoke-TuneupHealth
        $report.before.componentStore.operationResult | Should -Be '0x800f081f'
        $report.before.componentStore.exitCodeHex | Should -Be '0x800f081f'
        $report.before.sfc.exitCodeHex | Should -Be '0x0'
    }
}