BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Event 100 of Microsoft-Windows-Diagnostics-Performance/Operational, as Get-WinEvent returns it.
    $script:BootXml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Microsoft-Windows-Diagnostics-Performance'/><EventID>100</EventID></System><EventData><Data Name='BootTsVersion'>2</Data><Data Name='BootStartTime'>2026-09-30T14:07:58.0000000Z</Data><Data Name='BootEndTime'>2026-09-30T14:09:01.0000000Z</Data><Data Name='BootTime'>53789</Data><Data Name='MainPathBootTime'>12345</Data><Data Name='BootKernelInitTime'>21</Data></EventData></Event>"
    function New-NoEventError {
        [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No events were found that match the specified selection criteria.'),
            'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
    }
}

Describe 'Boot duration' {
    It 'reads BootTime from event 100' {
        $result = ConvertFrom-TuneupBootEvent -Xml $BootXml -Created ([datetime]'2026-09-30 11:12:00') -LastBoot ([datetime]'2026-09-30 11:07:58')
        $result.milliseconds | Should -Be 53789
        $result.reason | Should -BeNullOrEmpty
    }

    It 'ignores an event from a previous boot' {
        $result = ConvertFrom-TuneupBootEvent -Xml $BootXml -Created ([datetime]'2026-09-29 09:00:00') -LastBoot ([datetime]'2026-09-30 11:07:58')
        $result.milliseconds | Should -BeNullOrEmpty
        $result.reason | Should -Be 'not-recorded-yet'
    }

    It 'says why when BootTime is missing' {
        $xml = $BootXml -replace "<Data Name='BootTime'>53789</Data>", ''
        (ConvertFrom-TuneupBootEvent -Xml $xml -Created ([datetime]'2026-09-30 11:12:00') -LastBoot ([datetime]'2026-09-30 11:07:58')).reason | Should -Be 'unreadable'
    }

    It 'reads the latest event' {
        $record = [pscustomobject]@{ TimeCreated = [datetime]'2026-09-30 11:12:00'; Xml = $BootXml }
        $record | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
        Mock -ModuleName Tuneup Get-WinEvent { $record }.GetNewClosure()
        (Get-TuneupBootDuration -LastBoot ([datetime]'2026-09-30 11:07:58')).milliseconds | Should -Be 53789
        Should -Invoke Get-WinEvent -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilterHashtable.LogName -eq 'Microsoft-Windows-Diagnostics-Performance/Operational' -and $FilterHashtable.Id -eq 100 -and $MaxEvents -eq 1
        }
    }

    It 'asks for elevation when Windows hides the events' {
        Mock -ModuleName Tuneup Get-WinEvent { throw (New-NoEventError) }
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        (Get-TuneupBootDuration -LastBoot (Get-Date)).reason | Should -Be 'needs-admin'
    }

    It 'says there is no event when elevated' {
        Mock -ModuleName Tuneup Get-WinEvent { throw (New-NoEventError) }
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        (Get-TuneupBootDuration -LastBoot (Get-Date)).reason | Should -Be 'no-event'
    }
}

Describe 'Measure-TuneupSystem' {
    BeforeEach {
        $script:Boot = (Get-Date).AddMinutes(-90)
        $script:BootDuration = [pscustomobject]@{ milliseconds = 53789; reason = $null }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = [uint64]16777216; FreePhysicalMemory = [uint64]8388608; LastBootUpTime = $script:Boot } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ FreeSpace = [uint64]107374182400 } } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
        Mock -ModuleName Tuneup Get-Process { 1..150 | ForEach-Object { [pscustomobject]@{ Id = $_ } } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Running' }; [pscustomobject]@{ Status = 'Stopped' }; [pscustomobject]@{ Status = 'Running' } }
        Mock -ModuleName Tuneup Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' }; [pscustomobject]@{ State = 'Disabled' }; [pscustomobject]@{ State = 'Running' } }
        Mock -ModuleName Tuneup Get-TuneupBootDuration { $script:BootDuration }
        Mock -ModuleName Tuneup Start-Sleep { }
    }

    It 'collects the metrics without waiting by default' {
        $measurement = Measure-TuneupSystem -Environment (New-TestEnvironment)
        $measurement.schemaVersion | Should -Be 1
        $measurement.metrics.ramInUseMB | Should -Be 8192
        $measurement.metrics.processCount | Should -Be 150
        $measurement.metrics.runningServices | Should -Be 2
        $measurement.metrics.enabledTasks | Should -Be 2
        $measurement.metrics.systemDriveFreeGB | Should -Be 100
        $measurement.metrics.bootDurationMs | Should -Be 53789
        $measurement.metrics.uptimeMinutes | Should -Be 90
        $measurement.notes.bootDurationMs | Should -BeNullOrEmpty
        $measurement.environment.edition | Should -Be 'Pro'
        $measurement.metrics.PSObject.Properties.Name -join ',' | Should -Be ((Get-TuneupMetricName) -join ',')
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Get-CimInstance -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Filter -eq "DeviceID='$($env:SystemDrive)'" }
    }

    It 'waits the idle time before measuring' {
        Measure-TuneupSystem -Environment (New-TestEnvironment) -IdleSeconds 120 | Out-Null
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Seconds -eq 120 }
    }

    It 'keeps the reason when the boot duration is missing' {
        $script:BootDuration = [pscustomobject]@{ milliseconds = $null; reason = 'needs-admin' }
        $measurement = Measure-TuneupSystem -Environment (New-TestEnvironment)
        $measurement.metrics.bootDurationMs | Should -BeNullOrEmpty
        $measurement.notes.bootDurationMs | Should -Be 'needs-admin'
    }
}

Describe 'Compare-TuneupMeasurement' {
    It 'gives the difference of every metric, and none when a side is missing' {
        $before = [pscustomobject]@{ metrics = [pscustomobject]@{ ramInUseMB = 6000; processCount = 160; runningServices = 120; enabledTasks = 150; systemDriveFreeGB = 100.5; bootDurationMs = $null; uptimeMinutes = 3 } }
        $after = [pscustomobject]@{ metrics = [pscustomobject]@{ ramInUseMB = 5400; processCount = 140; runningServices = 110; enabledTasks = 130; systemDriveFreeGB = 101.25; bootDurationMs = 40000; uptimeMinutes = 2 } }
        $items = @(Compare-TuneupMeasurement -Before $before -After $after)
        ($items | ForEach-Object { $_.metric }) -join ',' | Should -Be 'ramInUseMB,processCount,runningServices,enabledTasks,systemDriveFreeGB,bootDurationMs,uptimeMinutes'
        $items[0].before | Should -Be 6000
        $items[0].after | Should -Be 5400
        $items[0].delta | Should -Be -600
        $items[4].delta | Should -Be 0.75
        $items[5].after | Should -Be 40000
        $items[5].delta | Should -BeNullOrEmpty
    }
}
