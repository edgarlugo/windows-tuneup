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
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = [uint64]16777216; FreePhysicalMemory = [uint64]4194304; LastBootUpTime = $script:Boot } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
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
        $measurement.metrics.ramInUseMB | Should -Be 12288
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

    It 'keeps the reason of a side that has no value' {
        $before = [pscustomobject]@{ metrics = [pscustomobject]@{ bootDurationMs = $null; ramInUseMB = 1 }; notes = [pscustomobject]@{ bootDurationMs = 'no-event' } }
        $after = [pscustomobject]@{ metrics = [pscustomobject]@{ bootDurationMs = 40000; ramInUseMB = $null }; notes = [pscustomobject]@{ bootDurationMs = $null } }
        $items = @(Compare-TuneupMeasurement -Before $before -After $after)
        $boot = $items | Where-Object { $_.metric -eq 'bootDurationMs' }
        $boot.beforeNote | Should -Be 'no-event'
        $boot.afterNote | Should -BeNullOrEmpty
        ($items | Where-Object { $_.metric -eq 'ramInUseMB' }).afterNote | Should -BeNullOrEmpty
    }

    It 'rounds the difference to two decimals' {
        $before = [pscustomobject]@{ metrics = [pscustomobject]@{ systemDriveFreeGB = 184.90 } }
        $after = [pscustomobject]@{ metrics = [pscustomobject]@{ systemDriveFreeGB = 184.98 } }
        $item = @(Compare-TuneupMeasurement -Before $before -After $after) | Where-Object { $_.metric -eq 'systemDriveFreeGB' }
        $item.delta | Should -Be 0.08
    }
}

Describe 'Measurement files' {
    BeforeAll {
        function New-TestMeasurement([double]$Ram) {
            [pscustomobject]@{
                schemaVersion = 1; takenAt = '2026-09-30T12:00:00'; idleSeconds = 0; environment = $null
                metrics       = [pscustomobject]@{ ramInUseMB = $Ram; processCount = 100; runningServices = 100; enabledTasks = 100; systemDriveFreeGB = 50; bootDurationMs = $null; uptimeMinutes = 5 }
                notes         = [pscustomobject]@{ bootDurationMs = 'no-event' }
            }
        }
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Stamp = '20260930-120000'
    }

    It 'saves a measurement with its id and finds it again' {
        $saved = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root
        $saved.Root | Should -Be 'custom'
        $saved.Path | Should -Be (Join-Path $Root "measurements\$($saved.Id).json")
        (Get-Content -LiteralPath $saved.Path -Raw | ConvertFrom-Json).id | Should -Be $saved.Id
        (Resolve-TuneupMeasurement -StateRoot $Root -Id 'last').Measurement.metrics.ramInUseMB | Should -Be 5000
        (Resolve-TuneupMeasurement -StateRoot $Root -Id $saved.Id).Path | Should -Be $saved.Path
        Resolve-TuneupMeasurement -StateRoot $Root -Id '19990101-000000' | Should -BeNullOrEmpty
    }

    It 'gives distinct ids within the same second and resolves last to the newest' {
        Mock -ModuleName Tuneup Get-Date { $script:Stamp } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
        $first = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root
        $second = Save-TuneupMeasurement -Measurement (New-TestMeasurement 4000) -StateRoot $Root
        $first.Id | Should -Be '20260930-120000'
        $second.Id | Should -Be '20260930-120000-02'
        $last = Resolve-TuneupMeasurement -StateRoot $Root -Id 'last'
        $last.Id | Should -Be '20260930-120000-02'
        $last.Measurement.metrics.ramInUseMB | Should -Be 4000
    }

    It 'never overwrites a file that already has the id' {
        Mock -ModuleName Tuneup Get-Date { $script:Stamp } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
        New-Item -ItemType Directory -Path (Join-Path $Root 'measurements') -Force | Out-Null
        $existing = Join-Path $Root 'measurements\20260930-120000.json'
        [System.IO.File]::WriteAllText($existing, 'keep me')
        $saved = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root
        $saved.Id | Should -Be '20260930-120000-02'
        [System.IO.File]::ReadAllText($existing) | Should -Be 'keep me'
    }

    It 'gives up after the last suffix instead of overwriting' {
        Mock -ModuleName Tuneup Get-Date { $script:Stamp } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
        New-Item -ItemType Directory -Path (Join-Path $Root 'measurements') -Force | Out-Null
        foreach ($name in @('20260930-120000') + @(2..99 | ForEach-Object { '20260930-120000-{0:D2}' -f $_ })) {
            [System.IO.File]::WriteAllText((Join-Path $Root "measurements\$name.json"), 'keep me')
        }
        { Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root } | Should -Throw '*Cannot find a free measurement id*'
    }

    It 'ignores files that are not measurements and warns about unreadable ones' {
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $Root 'measurements\notes.json'), '{}')
        [System.IO.File]::WriteAllText((Join-Path $Root 'measurements\20250101-000000.json'), '{ broken')
        $list = @(Get-TuneupMeasurementList -StateRoot $Root -WarningVariable warned -WarningAction SilentlyContinue)
        $list.Count | Should -Be 1
        @($warned | Where-Object { "$_" -like 'Ignoring unreadable state file *' }).Count | Should -Be 1
    }

    It 'warns about a measurement file with the wrong shape instead of comparing against it' -TestCases @(
        @{ Name = 'no metrics'; Json = '{}' }
        @{ Name = 'a text metric'; Json = '{"metrics":{"ramInUseMB":"lots"}}' }
        @{ Name = 'metrics that are not an object'; Json = '{"metrics":5}' }
        @{ Name = 'empty metrics'; Json = '{"metrics":{}}' }
        @{ Name = 'only unknown metrics'; Json = '{"metrics":{"other":1}}' }
        @{ Name = 'only empty metrics'; Json = '{"metrics":{"ramInUseMB":null}}' }
    ) {
        param($Name, $Json)
        New-Item -ItemType Directory -Path (Join-Path $Root 'measurements') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $Root 'measurements\20250101-000000.json'), $Json)
        @(Get-TuneupMeasurementList -StateRoot $Root -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0 -Because $Name
        @($warned | Where-Object { "$_" -like 'Ignoring unreadable state file *' }).Count | Should -Be 1 -Because $Name
    }
}

Describe 'Machine measurements' {
    BeforeAll {
        function New-TestMeasurement([double]$Ram) {
            [pscustomobject]@{ schemaVersion = 1; metrics = [pscustomobject]@{ ramInUseMB = $Ram }; notes = [pscustomobject]@{} }
        }
    }

    BeforeEach {
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $script:MachineRoot = New-TestMachineRoot
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Stamp = '20260930-120000'
        Mock -ModuleName Tuneup Get-Date { $script:Stamp } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'saves to the protected machine folder when elevated' {
        $saved = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot
        $saved.Root | Should -Be 'machine'
        foreach ($path in (Join-Path $MachineRoot 'measurements'), $saved.Path) {
            (Get-Acl -LiteralPath $path).AreAccessRulesProtected | Should -BeTrue -Because $path
        }
        $last = Resolve-TuneupMeasurement -MachineRoot $MachineRoot -UserRoot $UserRoot -Id 'last'
        "$($last.Id)/$($last.Root)" | Should -Be '20260930-120000/machine'
    }

    It 'needs an elevated process for the machine folder' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        { Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot } | Should -Throw '*elevated*'
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
    }

    It 'lists the machine and user folders in id order' {
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot | Out-Null
        $script:Stamp = '20260930-120005'
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 4000) -UserRoot $UserRoot | Out-Null
        $list = @(Get-TuneupMeasurementList -MachineRoot $MachineRoot -UserRoot $UserRoot)
        ($list | ForEach-Object { "$($_.Id)/$($_.Root)" }) -join ',' | Should -Be '20260930-120000/machine,20260930-120005/user'
    }

    It 'gives distinct ids in the machine folder and keeps the first file' {
        $first = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot
        $second = Save-TuneupMeasurement -Measurement (New-TestMeasurement 4000) -Machine -MachineRoot $MachineRoot
        $second.Id | Should -Be '20260930-120000-02'
        (Get-Content -LiteralPath $first.Path -Raw | ConvertFrom-Json).metrics.ramInUseMB | Should -Be 5000
    }

    It 'ignores a machine measurements folder that others can write' {
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot | Out-Null
        $dir = Join-Path $MachineRoot 'measurements'
        Grant-EveryoneWrite $dir
        @(Get-TuneupMeasurementList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0
        "$($warned[0])" | Should -Be "Ignoring untrusted state folder $dir"
    }

    It 'ignores a machine measurement file that others can write' {
        $saved = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot
        Grant-EveryoneWrite $saved.Path
        @(Get-TuneupMeasurementList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0
        @($warned | Where-Object { "$_" -like 'Ignoring untrusted state file *' }).Count | Should -Be 1
    }

    It 'keeps the runs folder when the measurements folder is added to an existing machine folder' {
        New-TuneupRun -Machine -MachineRoot $MachineRoot | Out-Null
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot | Out-Null
        foreach ($child in 'runs', 'measurements') { Test-Path -LiteralPath (Join-Path $MachineRoot $child) -PathType Container | Should -BeTrue -Because $child }
    }
}