BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:DisabledAt = [datetime]::new(2026, 10, 4, 12, 0, 0, [DateTimeKind]::Utc)
    # 03 00 00 00 and the FILETIME of 2026-10-04 12:00 UTC, little endian.
    $script:Expected = @(@(3, 0, 0, 0) + @([BitConverter]::GetBytes([int64]$DisabledAt.ToFileTimeUtc())))
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
    # Whether an entry is still there is read from the Run key of the test, never from the one of the account.
    InModuleScope Tuneup -Parameters @{ Run = "$Key\Run" } {
        param($Run)
        $script:StartupRunKeys = @([pscustomobject]@{ Source = 'run-user'; Path = $Run })
    }
    # What a tweak may write is pinned to StartupApproved and SystemAppData: the tests use copies under their key.
    $script:WindowsRoots = InModuleScope Tuneup { [pscustomobject]@{ Approved = $script:StartupApprovedRoot.Clone(); Store = $script:StoreTaskRoot } }
    function Use-TestRoot([switch]$Windows) {
        $roots = $(if ($Windows) { $WindowsRoots } else {
                [pscustomobject]@{ Approved = @{ user = "$Key\StartupApproved"; machine = 'HKLM:\SOFTWARE\windows-tuneup-test\StartupApproved' }; Store = "$Key\SystemAppData" } })
        InModuleScope Tuneup -Parameters @{ Roots = $roots } {
            param($Roots)
            $script:StartupApprovedRoot = $Roots.Approved
            $script:StoreTaskRoot = $Roots.Store
        }
    }
    Use-TestRoot
    function New-TestEntry([string]$Source, [string]$Key, [hashtable]$Target = @{}, [bool]$Enabled = $true) {
        $entry = New-TuneupStartupEntry -Source $Source -Key $Key -Name "Name $Key" -Enabled $Enabled -Target $Target
        $entry.canDisable = $Enabled
        $entry
    }
}

Describe 'New-TuneupStartupApprovedValue' {
    It 'writes 03 and when it was turned off, as Task Manager does' {
        $value = New-TuneupStartupApprovedValue -DisabledAt $DisabledAt
        $value.GetType().Name | Should -Be 'Byte[]'
        $value.Length | Should -Be 12
        @($value) -join ',' | Should -Be ($Expected -join ',')
        # 134355888000000000 is 2026-10-04 12:00 UTC as a FILETIME.
        [BitConverter]::ToInt64($value, 4) | Should -Be 134355888000000000
        Test-TuneupStartupApprovedEnabled -Value $value | Should -BeFalse
    }
}

Describe 'ConvertTo-TuneupStartupTweak' {
    It 'turns a Run entry off through StartupApproved of its hive' {
        $approved = "$Key\StartupApproved\Run"
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = $approved; ApprovedName = 'Steam' }) -DisabledAt $DisabledAt
        $tweak.id | Should -BeExactly 'startup.run-user.steam-eb4bc901e3d06cf1'
        $tweak.type | Should -Be 'registry'
        $tweak.scope | Should -Be 'user'
        $tweak.set.path | Should -Be $approved
        $tweak.set.name | Should -Be 'Steam'
        $tweak.set.kind | Should -Be 'Binary'
        @($tweak.set.value) -join ',' | Should -Be ($Expected -join ',')
        $tweak.set.compare | Should -Be 'startupApproved'
        $tweak.title.es | Should -Be 'Name Steam'
        $tweak.title.en | Should -Be 'Name Steam'
        $tweak.why.en | Should -Be 'Starts with Windows: at sign-in (Run of the user). Turned off the way Task Manager does, without deleting the entry.'
        $tweak.why.es | Should -Be $tweak.why.en
        $tweak.risk | Should -Be 'low'
        $tweak.ask | Should -BeFalse
        $tweak.rebootRequired | Should -BeFalse
        $tweak.startup.source | Should -Be 'run-user'
        $tweak.startup.key | Should -Be 'Steam'
        @($tweak.sources).Count | Should -Be 1
        Test-TuneupUserScopedTweak -Tweak $tweak | Should -BeTrue
        Test-TuneupTweakNeedsAdmin -Tweak $tweak | Should -BeFalse
    }

    It 'writes why in the language of the run, in both fields' {
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'es'
        try {
            $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' })
        } finally {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
        }
        $tweak.why.en | Should -Match '^Arranca con Windows: al iniciar sesi.n \(Run del usuario\)\.'
        $tweak.why.es | Should -Be $tweak.why.en
    }

    It 'keeps the scope of a machine entry and the Run32 and StartupFolder keys' {
        $machine = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run32-machine' 'Tray' @{ ApprovedPath = 'HKLM:\SOFTWARE\windows-tuneup-test\StartupApproved\Run32'; ApprovedName = 'Tray' })
        $machine.scope | Should -Be 'machine'
        Test-TuneupTweakNeedsAdmin -Tweak $machine | Should -BeTrue
        $folder = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'folder-user' 'Tool.lnk' @{ ApprovedPath = "$Key\StartupApproved\StartupFolder"; ApprovedName = 'Tool.lnk' })
        $folder.set.name | Should -Be 'Tool.lnk'
        $folder.set.value[0] | Should -Be 3
    }

    It 'gives an entry that is already off the same new value (the check reads any odd first byte as off), and a Store task the State it has' {
        $bytes = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Old' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Old'; ApprovedValue = $bytes } -Enabled $false) -DisabledAt $DisabledAt
        @($tweak.set.value) -join ',' | Should -Be ($Expected -join ',')
        $tweak.set.compare | Should -Be 'startupApproved'
        $store = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'P\T' @{ StoreKeyPath = "$Key\SystemAppData\P\T"; StoreState = 0 } -Enabled $false)
        $store.set.value | Should -Be 0
    }

    It 'turns a Store task off with State 1, as Settings does' {
        $path = "$Key\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' @{ StoreKeyPath = $path; StoreState = 2 })
        $tweak.type | Should -Be 'registry'
        $tweak.scope | Should -Be 'user'
        $tweak.set.path | Should -Be $path
        $tweak.set.name | Should -Be 'State'
        $tweak.set.kind | Should -Be 'DWord'
        $tweak.set.value | Should -Be 1
        $tweak.set.PSObject.Properties.Name | Should -Not -Contain 'compare'
        @(Test-RegistryTweakDefinition -Tweak $tweak).Count | Should -Be 0
    }

    It 'disables a task and sets a service to Manual without stopping it' {
        $task = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'task' '\Vendor\Up' @{ TaskPath = '\Vendor\'; TaskName = 'Up' })
        $task.type | Should -Be 'task'
        $task.scope | Should -Be 'machine'
        $task.set.path | Should -Be '\Vendor\'
        $task.set.name | Should -Be 'Up'
        $task.set.state | Should -Be 'Disabled'
        @(Test-TaskTweakDefinition -Tweak $task).Count | Should -Be 0
        $service = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'service' 'VendorSvc' @{ ServiceName = 'VendorSvc'; StartType = 'Automatic' })
        $service.type | Should -Be 'service'
        $service.set.name | Should -Be 'VendorSvc'
        $service.set.startType | Should -Be 'Manual'
        $service.set.stop | Should -BeFalse
        @(Test-ServiceTweakDefinition -Tweak $service).Count | Should -Be 0
    }

    It 'refuses an entry that cannot be turned off' {
        $protected = New-TestEntry 'run-user' 'AV'
        $protected.protected = 'security'
        { ConvertTo-TuneupStartupTweak -Entry $protected } | Should -Throw '*cannot be turned off*'
        $unverified = New-TestEntry 'service' 'Odd' @{ ServiceName = 'Odd'; Unverified = $true }
        $unverified.protected = 'unverified'
        { ConvertTo-TuneupStartupTweak -Entry $unverified } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Half' @{ ApprovedPath = "$Key\Run"; ApprovedName = 'Half'; Incomplete = $true }) } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'task' '\V\a*b' @{ TaskPath = '\V\'; TaskName = 'a*b' }) } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'runonce-user' 'Once') } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'driver' 'drv') } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'policy-user' 'Agent') } | Should -Throw '*cannot be turned off*'
    }

    It 'refuses an entry whose target does not say where to turn it off' {
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'NoKey') } | Should -Throw '*cannot be turned off*'
        # A user entry kept under HKLM (or a machine one under HKCU) would land in the wrong place.
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Wrong' @{ ApprovedPath = 'HKLM:\Software\X'; ApprovedName = 'Wrong' }) } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'P\T' @{ StoreKeyPath = ''; StoreState = 2 }) } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'task' '\V\Up' @{ TaskPath = 'V'; TaskName = 'Up' }) } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'service' 'Svc') } | Should -Throw '*cannot be turned off*'
    }

    It 'writes only the StartupApproved value of the entry and the State of its Store task: <Name>' -TestCases @(
        @{ Name = 'the key of another source'; Source = 'run-user'; EntryKey = 'Steam'; Target = @{ ApprovedPath = 'HKCU:\Software\windows-tuneup-test\StartupApproved\Run32'; ApprovedName = 'Steam' } }
        @{ Name = 'the Run key itself'; Source = 'run-user'; EntryKey = 'Steam'; Target = @{ ApprovedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; ApprovedName = 'Steam' } }
        @{ Name = 'a key under StartupApproved'; Source = 'run-user'; EntryKey = 'Steam'; Target = @{ ApprovedPath = 'HKCU:\Software\windows-tuneup-test\StartupApproved\Run\Sub'; ApprovedName = 'Steam' } }
        @{ Name = 'the value of another entry'; Source = 'run-user'; EntryKey = 'Steam'; Target = @{ ApprovedPath = 'HKCU:\Software\windows-tuneup-test\StartupApproved\Run'; ApprovedName = 'Other' } }
        @{ Name = 'the folder of the machine for an entry of the user'; Source = 'folder-user'; EntryKey = 'Tool.lnk'; Target = @{ ApprovedPath = 'HKLM:\SOFTWARE\windows-tuneup-test\StartupApproved\StartupFolder'; ApprovedName = 'Tool.lnk' } }
        @{ Name = 'the task of another Store app'; Source = 'store-app'; EntryKey = 'P\T'; Target = @{ StoreKeyPath = 'HKCU:\Software\windows-tuneup-test\SystemAppData\Other\T'; StoreState = 2 } }
        @{ Name = 'a key outside SystemAppData'; Source = 'store-app'; EntryKey = 'P\T'; Target = @{ StoreKeyPath = 'HKCU:\Software\Elsewhere\P\T'; StoreState = 2 } }
    ) {
        param($Source, $EntryKey, $Target)
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry $Source $EntryKey $Target) } | Should -Throw '*cannot be turned off*'
    }

    It 'pins the keys of Windows when no test copy stands in for them' {
        Use-TestRoot -Windows
        try {
            $real = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            (ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = $real; ApprovedName = 'Steam' })).set.path | Should -Be $real
            $store = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\P\T'
            (ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'P\T' @{ StoreKeyPath = $store; StoreState = 2 })).set.path | Should -Be $store
            { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' }) } | Should -Throw '*cannot be turned off*'
        } finally {
            Use-TestRoot
        }
    }
}

Describe 'A startup tweak through the registry handler' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path "$Key\Run" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Run" -Name 'Steam' -Value 'C:\Games\Steam\steam.exe' -PropertyType String | Out-Null
    }
    AfterAll { Remove-TestKey }

    It 'turns the entry off, reads it as applied also from the journal, and removes the keys it created' {
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' }) -DisabledAt $DisabledAt
        $before = Get-TuneupState -Tweak $tweak
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        Set-TuneupDesired -Tweak $tweak | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'applied'
        $item = Get-Item -LiteralPath "$Key\StartupApproved\Run"
        [string]$item.GetValueKind('Steam') | Should -Be 'Binary'
        @($item.GetValue('Steam')) -join ',' | Should -Be ($Expected -join ',')
        $item.Close()
        # The journal keeps the tweak and the state as JSON; -Status and -Undo work from what it reads back.
        $journaled = ConvertTo-Json -InputObject ([pscustomobject]@{ tweak = $tweak; state = $before }) -Depth 10 -Compress | ConvertFrom-Json
        Test-TuneupState -Tweak $journaled.tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $journaled.tweak -State $journaled.state | Out-Null
        Test-Path -LiteralPath "$Key\StartupApproved" | Should -BeFalse
    }

    It 'gives back the value an entry had before, such as the 02 of an entry that was on' {
        New-Item -Path "$Key\StartupApproved\Run" -Force | Out-Null
        $on = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value $on -PropertyType Binary | Out-Null
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam'; ApprovedValue = $on })
        $before = ConvertTo-Json -InputObject (Get-TuneupState -Tweak $tweak) -Depth 10 | ConvertFrom-Json
        Set-TuneupDesired -Tweak $tweak | Out-Null
        Restore-TuneupState -Tweak $tweak -State $before | Out-Null
        @((Get-Item -LiteralPath "$Key\StartupApproved\Run").GetValue('Steam')) -join ',' | Should -Be '2,0,0,0,0,0,0,0,0,0,0,0'
    }

    It 'reads an entry turned off again by Task Manager, with another date, as applied, and one turned on as not applied' {
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' }) -DisabledAt $DisabledAt
        Set-TuneupDesired -Tweak $tweak | Out-Null
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9)) -PropertyType Binary -Force | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'applied'
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -PropertyType Binary -Force | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value 'x' -PropertyType String -Force | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        Remove-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam'
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
    }

    It 'gives back the exact bytes it found, also after Task Manager wrote another date' {
        New-Item -Path "$Key\StartupApproved\Run" -Force | Out-Null
        $original = [byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value $original -PropertyType Binary | Out-Null
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam'; ApprovedValue = $original })
        $journaled = ConvertTo-Json -InputObject ([pscustomobject]@{ tweak = $tweak; state = (Get-TuneupState -Tweak $tweak) }) -Depth 10 -Compress | ConvertFrom-Json
        Set-TuneupDesired -Tweak $tweak | Out-Null
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9)) -PropertyType Binary -Force | Out-Null
        # -Undo compares the exact bytes before it restores: another date is a change to give back.
        Test-TuneupStateUnchanged -Tweak $journaled.tweak -Before $journaled.state | Should -BeFalse
        Restore-TuneupState -Tweak $journaled.tweak -State $journaled.state | Out-Null
        @((Get-Item -LiteralPath "$Key\StartupApproved\Run").GetValue('Steam')) -join ',' | Should -Be '6,0,0,0,0,0,0,0,0,0,0,0'
    }

    It 'writes and gives back the State of a Store task' {
        $path = "$Key\SystemAppData\Vendor.App_abc\StartAtLogon"
        New-Item -Path $path -Force | Out-Null
        New-ItemProperty -LiteralPath $path -Name 'State' -Value 2 -PropertyType DWord | Out-Null
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'Vendor.App_abc\StartAtLogon' @{ StoreKeyPath = $path; StoreState = 2 })
        $before = Get-TuneupState -Tweak $tweak
        Set-TuneupDesired -Tweak $tweak | Out-Null
        (Get-ItemProperty -LiteralPath $path).State | Should -Be 1
        Test-TuneupState -Tweak $tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $tweak -State $before | Out-Null
        (Get-ItemProperty -LiteralPath $path).State | Should -Be 2
    }
}

Describe 'A startup tweak through the task and service handlers' {
    It 'disables the task it names exactly and enables it again' {
        $script:Calls = New-Object System.Collections.Generic.List[string]
        $script:TaskState = 'Ready'
        # Client-only CIM instances: the real cmdlets type -InputObject as CimInstance, and no real task is touched.
        Mock -ModuleName Tuneup Get-ScheduledTask {
            New-CimInstance -ClientOnly -ClassName MSFT_ScheduledTask -Namespace 'Root/Microsoft/Windows/TaskScheduler' `
                -Property @{ TaskName = 'Up'; TaskPath = '\Vendor\'; State = $script:TaskState }
        }
        Mock -ModuleName Tuneup Disable-ScheduledTask { $script:Calls.Add("disable $($InputObject.TaskPath)$($InputObject.TaskName)"); $script:TaskState = 'Disabled' }
        Mock -ModuleName Tuneup Enable-ScheduledTask { $script:Calls.Add("enable $($InputObject.TaskPath)$($InputObject.TaskName)"); $script:TaskState = 'Ready' }
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'task' '\Vendor\Up' @{ TaskPath = '\Vendor\'; TaskName = 'Up' })
        $before = Get-TuneupState -Tweak $tweak
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        Set-TuneupDesired -Tweak $tweak | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $tweak -State $before | Out-Null
        @($script:Calls) -join ';' | Should -Be 'disable \Vendor\Up;enable \Vendor\Up'
    }

    It 'sets the service to Manual with sc.exe and gives back Automatic, delayed included, never stopping it' {
        $script:Sc = New-Object System.Collections.Generic.List[string]
        Mock -ModuleName Tuneup Invoke-TuneupSc { $script:Sc.Add("$Name $Start") }
        Mock -ModuleName Tuneup Stop-Service { throw 'never stopped' }
        Mock -ModuleName Tuneup Start-Service { }
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'AutomaticDelayed'; running = $false } }
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'service' 'VendorSvc' @{ ServiceName = 'VendorSvc'; StartType = 'AutomaticDelayed' })
        $before = Get-TuneupState -Tweak $tweak
        Set-TuneupDesired -Tweak $tweak | Out-Null
        Restore-TuneupState -Tweak $tweak -State $before | Out-Null
        @($script:Sc) -join ';' | Should -Be 'VendorSvc demand;VendorSvc delayed-auto'
        Should -Invoke -ModuleName Tuneup Stop-Service -Times 0
    }
}

Describe 'The compare field of a registry tweak' {
    It 'is refused in the catalog: only the tweaks of startup entries use it' {
        $tweak = New-TestTweak -Id 'test.compare' -Set ([pscustomobject]@{ path = 'HKCU:\Software\windows-tuneup-test'; name = 'X'; kind = 'DWord'; value = 1; compare = 'startupApproved' })
        @(Test-RegistryTweakDefinition -Tweak $tweak) -join ',' | Should -Match 'set\.compare is only for startup entries'
        @(Test-TuneupTweak -Tweak $tweak) -join ',' | Should -Match 'test\.compare set\.compare'
    }

    It 'changes nothing for a registry tweak without it' {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
        try {
            $tweak = New-TestTweak -Id 'test.plain' -Set ([pscustomobject]@{ path = $Key; name = 'X'; kind = 'DWord'; value = 3 })
            New-ItemProperty -LiteralPath $Key -Name 'X' -Value 1 -PropertyType DWord | Out-Null
            Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        } finally {
            Remove-TestKey
        }
    }
}

Describe 'Test-TuneupStartupTweakPresent' {
    It 'follows the shortcut of a startup folder' {
        $folder = Join-Path $TestDrive 'Startup'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'Tool.lnk') -Value 'x'
        Mock -ModuleName Tuneup Get-TuneupStartupFolderPath { $folder }.GetNewClosure()
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'folder-user' 'Tool.lnk' @{ ApprovedPath = "$Key\StartupApproved\StartupFolder"; ApprovedName = 'Tool.lnk' })
        Test-TuneupStartupTweakPresent -Tweak $tweak | Should -BeTrue
        Remove-Item -LiteralPath (Join-Path $folder 'Tool.lnk')
        Test-TuneupStartupTweakPresent -Tweak $tweak | Should -BeFalse
        Test-TuneupState -Tweak $tweak | Should -Be 'not-present'
    }

    It 'leaves a tweak of the catalog alone' {
        Test-TuneupStartupTweak -Tweak (New-TestTweak -Id 'test.plain') | Should -BeFalse
    }
}