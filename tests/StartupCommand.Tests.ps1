BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:Approved = "$Key\StartupApproved\Run"
    $script:SteamId = 'startup.run-user.steam-eb4bc901e3d06cf1'
    $script:On = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    $script:Run = "$Key\Run"
    # Whether an entry is still there is read from the Run key of the test, never from the one of the account.
    InModuleScope Tuneup -Parameters @{ Run = $Run } {
        param($Run)
        $script:StartupRunKeys = @(
            [pscustomobject]@{ Source = 'run-user'; Path = $Run }
            [pscustomobject]@{ Source = 'run-machine'; Path = "$Run-machine" }
        )
    }
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
    function Add-TestRunValue([string]$Name) {
        if (-not (Test-Path -LiteralPath $Run)) { New-Item -Path $Run -Force | Out-Null }
        New-ItemProperty -LiteralPath $Run -Name $Name -Value "`"C:\Games\$Name\$Name.exe`"" -PropertyType String -Force | Out-Null
    }
    function Get-TestApproved([string]$Name = 'Steam') {
        $item = Get-Item -LiteralPath $Approved
        try { , [byte[]]$item.GetValue($Name) } finally { $item.Close() }
    }
    # A Run entry of the user whose Task Manager choice lives under the test key.
    function New-TestSteam([bool]$Enabled = $true, $Value = $null, [string]$Name = 'Steam') {
        $entry = New-TuneupStartupEntry -Source 'run-user' -Key $Name -Name $Name -Command "`"C:\Games\$Name\$Name.exe`"" -Path "C:\Games\$Name\$Name.exe" `
            -Enabled $Enabled -Target @{ ApprovedPath = $Approved; ApprovedName = $Name; ApprovedValue = $Value }
        $entry.canDisable = $Enabled
        $entry
    }
    # A context like the one tuneup.ps1 builds, on the fixture catalog, with a known environment.
    function New-TestContext([switch]$Json, $Environment = (New-TestEnvironment -IsAdmin $false), [string]$StateRoot) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo)
        $context.StateRoot = $(if ($StateRoot) { $StateRoot } else { Join-Path $TestDrive ([guid]::NewGuid().ToString()) })
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = $Environment
        $context
    }
    function Invoke-TestStartup($Context, [string[]]$Disable = @(), [switch]$PlanOnly, [switch]$Yes) {
        $output = @(Invoke-TuneupStartupCommand -Context $Context -Disable $Disable -PlanOnly:$PlanOnly -Yes:$Yes)
        ($output -join "`n") | ConvertFrom-Json
    }
    function Invoke-TestStatus([string]$StateRoot, $Environment = (New-TestEnvironment -IsAdmin $false)) {
        Invoke-TuneupStatusCommand -Context (New-TestContext -Json -StateRoot $StateRoot -Environment $Environment) | ConvertFrom-Json
    }
    function Get-TestRunCount([string]$StateRoot) {
        $runs = Join-Path $StateRoot 'runs'
        if (-not (Test-Path -LiteralPath $runs)) { return 0 }
        @(Get-ChildItem -LiteralPath $runs -Directory).Count
    }
}

Describe 'Invoke-TuneupStartupCommand' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
        Add-TestRunValue 'Steam'
        $script:Entries = @(New-TestSteam)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:Entries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupWow64Process { $false }
    }
    AfterAll { Remove-TestKey }

    It 'lists the entries as a startup document, with a warning that some tasks need administrator' {
        $context = New-TestContext -Json
        $document = Invoke-TestStartup $context
        $context.ExitCode | Should -Be 0
        $document.command | Should -Be 'startup'
        $document.isAdmin | Should -BeFalse
        $document.workPc | Should -BeFalse
        $document.entries[0].id | Should -BeExactly $SteamId
        $document.entries[0].PSObject.Properties.Name | Should -Not -Contain 'target'
        $document.warnings | Should -Contain (Get-TuneupText -Key 'startup.unelevatedNote')
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 1 -Exactly
    }

    It 'gives no warning about hidden tasks when elevated' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true)
        $document = Invoke-TestStartup $context
        $document.isAdmin | Should -BeTrue
        @($document.warnings) | Should -Not -Contain (Get-TuneupText -Key 'startup.unelevatedNote')
    }

    It 'tells whether this is a work PC and gives it to the list' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $false -IsManaged $true)
        (Invoke-TestStartup $context).workPc | Should -BeTrue
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 1 -Exactly -ParameterFilter { $WorkPc }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $true }
        (Invoke-TestStartup (New-TestContext -Json)).workPc | Should -BeTrue
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        (Invoke-TestStartup (New-TestContext -Json)).workPc | Should -BeFalse
    }

    It 'refuses everything in a 32-bit PowerShell on a 64-bit Windows, before reading anything: <Name>' -TestCases @(
        @{ Name = 'the list'; Disable = @(); Environment = @{ IsAdmin = $false } }
        @{ Name = 'turning an entry off'; Disable = @('startup.run-user.steam-eb4bc901e3d06cf1'); Environment = @{ IsAdmin = $false } }
        @{ Name = 'elevated as another account'; Disable = @('startup.run-user.steam-eb4bc901e3d06cf1'); Environment = @{ IsAdmin = $true; IsSessionUser = $false } }
        @{ Name = 'on a Windows it does not support'; Disable = @('startup.run-user.steam-eb4bc901e3d06cf1'); Environment = @{ Build = 17763; IsAdmin = $false } }
    ) {
        param($Disable, $Environment)
        Mock -ModuleName Tuneup Test-TuneupWow64Process { $true }
        $context = New-TestContext -Json -Environment (New-TestEnvironment @Environment)
        $refused = Invoke-TestStartup $context -Disable $Disable -Yes:([bool]$Disable.Count)
        $context.ExitCode | Should -Be 1
        $refused.command | Should -Be 'error'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupWow64')
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 0
        Test-Path -LiteralPath $Approved | Should -BeFalse
        Get-TestRunCount $context.StateRoot | Should -Be 0
    }

    It 'plans turning an entry off as a plan of the startup source, changing nothing' {
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @($SteamId) -PlanOnly
        $context.ExitCode | Should -Be 0
        $plan.command | Should -Be 'plan'
        $plan.source | Should -Be 'startup'
        $plan.requiresAdmin | Should -BeFalse
        @($plan.items).Count | Should -Be 1
        $plan.items[0].id | Should -BeExactly $SteamId
        $plan.items[0].title | Should -Be 'Steam'
        $plan.items[0].action | Should -Be 'apply'
        $plan.items[0].type | Should -Be 'registry'
        $plan.items[0].needsAdmin | Should -BeFalse
        Test-Path -LiteralPath $Approved | Should -BeFalse
        Get-TestRunCount $context.StateRoot | Should -Be 0
    }

    It 'reads the entries again to turn them off, never an earlier list' {
        $listed = Invoke-TestStartup (New-TestContext -Json)
        $listed.entries[0].id | Should -BeExactly $SteamId
        # Gone since the list was shown (uninstalled, say): it is not among what starts now.
        $script:Entries = @()
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupUnknown' -Format $SteamId)
        # Protected since then (an update moved it under a VPN client, say): refused with why.
        $now = New-TestSteam
        $now.protected = 'vpn'
        $now.canDisable = $false
        $script:Entries = @($now)
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupFixed')
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 3 -Exactly
        Test-Path -LiteralPath $Approved | Should -BeFalse
    }

    It 'turns it off as a run that -Status checks and -Undo gives back, and turning it off again changes nothing' {
        $context = New-TestContext -Json
        $report = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 0
        $report.command | Should -Be 'apply'
        $report.source | Should -Be 'startup'
        $report.results[0].id | Should -BeExactly $SteamId
        $report.results[0].status | Should -Be 'applied'
        $report.restorePoint | Should -Be 'not-needed'
        $value = Get-TestApproved
        $value.Length | Should -Be 12
        $value[0] | Should -Be 3
        # The FILETIME of when it was turned off, as Task Manager writes it.
        [datetime]::FromFileTimeUtc([BitConverter]::ToInt64($value, 4)) | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-5))

        # The next list reads it as off: turning it off again plans nothing and makes no run.
        $script:Entries = @(New-TestSteam -Enabled $false -Value $value)
        $again = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TestStartup $again -Disable @($SteamId) -Yes
        $again.ExitCode | Should -Be 0
        $plan.command | Should -Be 'plan'
        $plan.items[0].reason | Should -Be 'already-applied'
        Get-TestRunCount $context.StateRoot | Should -Be 1
        (Get-TestApproved) -join ',' | Should -Be (@($value) -join ',')

        $status = Invoke-TestStatus $context.StateRoot
        $status.items[0].id | Should -BeExactly $SteamId
        $status.items[0].title | Should -Be 'Steam'
        $status.items[0].status | Should -Be 'ok'
        # Turned off again from Task Manager, with another date: still off, so not reverted.
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9)) -PropertyType Binary -Force | Out-Null
        (Invoke-TestStatus $context.StateRoot).items[0].status | Should -Be 'ok'
        # Turned on again by the person (Task Manager writes 02): Windows "reverted" it.
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value $On -PropertyType Binary -Force | Out-Null
        (Invoke-TestStatus $context.StateRoot).items[0].status | Should -Be 'drift'

        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        $undo.results[0].status | Should -Be 'restored'
        # It had no StartupApproved value: the value and the keys the run created are gone.
        Test-Path -LiteralPath "$Key\StartupApproved" | Should -BeFalse
    }

    It 'gives back the exact bytes the entry had, after Task Manager turned it off again with another date' {
        New-Item -Path $Approved -Force | Out-Null
        $original = [byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value $original -PropertyType Binary | Out-Null
        $script:Entries = @(New-TestSteam -Value $original)
        $context = New-TestContext -Json
        (Invoke-TestStartup $context -Disable @($SteamId) -Yes).results[0].status | Should -Be 'applied'
        (Get-TestApproved)[0] | Should -Be 3
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 7, 7, 7, 7, 7, 7, 7, 7)) -PropertyType Binary -Force | Out-Null
        (Invoke-TestStatus $context.StateRoot).items[0].status | Should -Be 'ok'
        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        $undo.results[0].status | Should -Be 'restored'
        $undo.results[0].reason | Should -BeNullOrEmpty
        (Get-TestApproved) -join ',' | Should -Be '6,0,0,0,0,0,0,0,0,0,0,0'
        # Nothing is left to check: the run is undone.
        @((Invoke-TestStatus $context.StateRoot).items).Count | Should -Be 0
    }

    It 'turns off what is on and leaves out, saying so, what is already off' {
        $offBytes = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)
        New-Item -Path $Approved -Force | Out-Null
        New-ItemProperty -LiteralPath $Approved -Name 'Discord' -Value $offBytes -PropertyType Binary | Out-Null
        $discord = New-TestSteam -Enabled $false -Value $offBytes -Name 'Discord'
        Add-TestRunValue 'Discord'
        $script:Entries = @((New-TestSteam), $discord)
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @($SteamId, $discord.id) -PlanOnly
        @($plan.items | ForEach-Object { "$($_.id)=$($_.action):$($_.reason)" }) -join ';' |
            Should -Be "${SteamId}=apply:;$($discord.id)=skip:already-applied"
        $context = New-TestContext -Json
        $report = Invoke-TestStartup $context -Disable @($SteamId, $discord.id) -Yes
        $context.ExitCode | Should -Be 0
        @($report.results | ForEach-Object { "$($_.id)=$($_.status):$($_.reason)" }) -join ';' |
            Should -Be "${SteamId}=applied:;$($discord.id)=skipped:already-applied"
        # Already off: its date is the one it had.
        (Get-TestApproved 'Discord') -join ',' | Should -Be (@($offBytes) -join ',')
    }

    It 'refuses ids that are not in the list, naming each one, and does nothing' {
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId, 'startup.run-user.gone-00000000', 'startup.task.other-11111111') -Yes
        $context.ExitCode | Should -Be 1
        $refused.command | Should -Be 'error'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupUnknown' -Format 'startup.run-user.gone-00000000, startup.task.other-11111111')
        Test-Path -LiteralPath $Approved | Should -BeFalse
        Get-TestRunCount $context.StateRoot | Should -Be 0
    }

    It 'refuses entries that stay on, saying why for each one, and does nothing with the rest' {
        $vpn = New-TuneupStartupEntry -Source 'run-user' -Key 'GlobalProtect' -Name 'GlobalProtect'
        $vpn.protected = 'vpn'
        $once = New-TuneupStartupEntry -Source 'runonce-user' -Key 'Cleanup' -Name 'Cleanup'
        $odd = New-TuneupStartupEntry -Source 'service' -Key 'OddSvc' -Name 'Odd service' -Target @{ ServiceName = 'OddSvc'; Unverified = $true }
        $odd.protected = 'unverified'
        $half = New-TuneupStartupEntry -Source 'run-user' -Key 'Half' -Name 'Half' -Target @{ ApprovedPath = $Approved; ApprovedName = 'Half'; Incomplete = $true }
        $wild = New-TuneupStartupEntry -Source 'task' -Key '\Vendor\Up[1]' -Name 'Up[1]' -Target @{ TaskPath = '\Vendor\'; TaskName = 'Up[1]' }
        $script:Entries = @((New-TestSteam), $vpn, $once, $odd, $half, $wild)
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId, $vpn.id, $once.id, $odd.id, $half.id, $wild.id) -Yes
        $context.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupFixed')
        $expected = @(
            (Get-TuneupText -Key 'startup.refusedLine' -Format $vpn.id, 'GlobalProtect', 'VPN'),
            (Get-TuneupText -Key 'startup.refusedLine' -Format $once.id, 'Cleanup', (Get-TuneupText -Key 'startup.fixed.run-once')),
            (Get-TuneupText -Key 'startup.refusedLine' -Format $odd.id, 'Odd service', (Get-TuneupText -Key 'startup.protected.unverified')),
            (Get-TuneupText -Key 'startup.refusedLine' -Format $half.id, 'Half', (Get-TuneupText -Key 'startup.fixed.unreadable')),
            (Get-TuneupText -Key 'startup.refusedLine' -Format $wild.id, 'Up[1]', (Get-TuneupText -Key 'startup.fixed.unsupported-name'))
        )
        @($refused.details) -join "`n" | Should -Be ($expected -join "`n")
        Test-Path -LiteralPath $Approved | Should -BeFalse
        Get-TestRunCount $context.StateRoot | Should -Be 0
    }

    It 'refuses an id that two entries share, naming both, and turns neither off' {
        $script:Entries = @((New-TestSteam), (New-TestSteam -Name 'STEAM'))
        $script:Entries[1].id | Should -BeExactly $SteamId
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupFixed')
        @($refused.details) -join "`n" | Should -Be (Get-TuneupText -Key 'startup.refusedLine' -Format $SteamId, 'Steam, STEAM', (Get-TuneupText -Key 'startup.fixed.ambiguous'))
        Test-Path -LiteralPath $Approved | Should -BeFalse
        Get-TestRunCount $context.StateRoot | Should -Be 0
    }

    It 'needs administrator only when a chosen entry is of the machine, and then changes nothing at all' {
        $machine = New-TuneupStartupEntry -Source 'run-machine' -Key 'Tray' -Name 'Tray' -Target @{ ApprovedPath = 'HKLM:\Software\windows-tuneup-test\StartupApproved\Run'; ApprovedName = 'Tray' }
        $machine.canDisable = $true
        New-Item -Path "$Run-machine" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Run-machine" -Name 'Tray' -Value 'C:\Tray\tray.exe' -PropertyType String | Out-Null
        $script:Entries = @((New-TestSteam), $machine)
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @($machine.id) -PlanOnly
        $context.ExitCode | Should -Be 0
        $plan.requiresAdmin | Should -BeTrue
        $plan.items[0].needsAdmin | Should -BeTrue
        # Like -Undo of a run with system changes and -Health: the reason is needs-admin.
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId, $machine.id) -Yes
        $context.ExitCode | Should -Be 1
        $refused.reason | Should -Be 'needs-admin'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupNeedsAdmin' -Format $machine.id)
        # The entry of the user was not turned off either: nothing is done halfway.
        Test-Path -LiteralPath $Approved | Should -BeFalse
        Get-TestRunCount $context.StateRoot | Should -Be 0
    }

    It 'refuses an entry of the user when elevated as another account, before reading anything' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true -IsSessionUser $false)
        $refused = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 1
        $refused.reason | Should -Be 'session-user'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupSessionUser' -Format $SteamId)
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 0
    }

    It 'reads ids without case, and the scope of an id written in capitals still decides the account' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true -IsSessionUser $false)
        $refused = Invoke-TestStartup $context -Disable @($SteamId.ToUpperInvariant()) -Yes
        $refused.reason | Should -Be 'session-user'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupSessionUser' -Format $SteamId)
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 0
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @(" $($SteamId.ToUpperInvariant()) ") -PlanOnly
        $plan.items[0].id | Should -BeExactly $SteamId
    }

    It 'refuses what is not an id of -Startup before reading anything' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true -IsSessionUser $false)
        $refused = Invoke-TestStartup $context -Disable @('privacy.advertising-id', 'steam') -Yes
        $context.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupUnknown' -Format 'privacy.advertising-id, steam')
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 0
    }

    It 'says that Windows hides some tasks when an unknown id of the machine is asked for without administrator' {
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @('startup.task.vendor-up-0000000000000000') -Yes
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupUnknown' -Format 'startup.task.vendor-up-0000000000000000')
        @($refused.details) | Should -Contain (Get-TuneupText -Key 'startup.unelevatedNote')
        $context = New-TestContext -Json
        @((Invoke-TestStartup $context -Disable @('startup.run-user.gone-0000000000000000') -Yes).details) | Should -Not -Contain (Get-TuneupText -Key 'startup.unelevatedNote')
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true)
        @((Invoke-TestStartup $context -Disable @('startup.task.vendor-up-0000000000000000') -Yes).details) | Should -Not -Contain (Get-TuneupText -Key 'startup.unelevatedNote')
    }

    It 'warns, when elevated as another account, that the entries of the user are that account''s' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true -IsSessionUser $false)
        $document = Invoke-TestStartup $context
        $context.ExitCode | Should -Be 0
        $document.warnings | Should -Contain (Get-TuneupText -Key 'startup.otherAccountNote')
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true)
        @((Invoke-TestStartup $context).warnings) | Should -Not -Contain (Get-TuneupText -Key 'startup.otherAccountNote')
    }

    It 'asks for -Yes with -Json, like applying a profile' {
        $context = New-TestContext -Json
        (Invoke-TestStartup $context -Disable @($SteamId)).message | Should -Be (Get-TuneupText -Key 'err.jsonNeedsYes')
        $context.ExitCode | Should -Be 1
        Test-Path -LiteralPath $Approved | Should -BeFalse
    }

    It 'turns nothing off on a Windows it does not support, but still lists' {
        $old = New-TestEnvironment -Build 17763 -IsAdmin $false
        $context = New-TestContext -Json -Environment $old
        (Invoke-TestStartup $context -Disable @($SteamId) -Yes).message | Should -Be (Get-TuneupText -Key 'err.unsupported')
        $context.ExitCode | Should -Be 1
        $context = New-TestContext -Json -Environment $old
        (Invoke-TestStartup $context).command | Should -Be 'startup'
        $context.ExitCode | Should -Be 0
    }

    It 'asks people before turning anything off, and tells them that the change takes effect at the next start' {
        $context = New-TestContext
        $context.Io = New-TestIo -Answers @('n')
        Invoke-TuneupStartupCommand -Context $context -Disable @($SteamId) 6>$null | Out-Null
        $context.ExitCode | Should -Be 1
        Test-Path -LiteralPath $Approved | Should -BeFalse
        $context = New-TestContext
        Invoke-TuneupStartupCommand -Context $context -Disable @($SteamId) -Yes 6>$null | Out-Null
        $context.ExitCode | Should -Be 0
        $context.Io.Output | Should -Contain (Get-TuneupText -Key 'startup.nextStart')
    }

    It 'writes the request of the run in its transcript' {
        $context = New-TestContext -Json
        $report = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $transcript = [System.IO.File]::ReadAllText((Join-Path $report.runDir 'transcript.log'))
        $transcript | Should -Match ([regex]::Escape((Get-TuneupText -Key 'transcript.request.startup' -Format '-', $SteamId, '-')))
    }
}

Describe 'Turning off a scheduled task and a service' {
    BeforeEach {
        $script:TaskState = 'Ready'
        $script:ServiceStart = 'AutomaticDelayed'
        $script:Calls = New-Object System.Collections.Generic.List[string]
        $task = New-TuneupStartupEntry -Source 'task' -Key '\Vendor\Up' -Name 'Up' -Target @{ TaskPath = '\Vendor\'; TaskName = 'Up' }
        $task.canDisable = $true
        $service = New-TuneupStartupEntry -Source 'service' -Key 'VendorSvc' -Name 'Vendor service' -Target @{ ServiceName = 'VendorSvc'; StartType = 'AutomaticDelayed' }
        $service.canDisable = $true
        $script:Entries = @($task, $service)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:Entries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupWow64Process { $false }
        Mock -ModuleName Tuneup New-TuneupRestorePoint { 'created' }
        # Client-only CIM instances and a stand-in for sc.exe: no real task or service is touched.
        Mock -ModuleName Tuneup Get-ScheduledTask {
            New-CimInstance -ClientOnly -ClassName MSFT_ScheduledTask -Namespace 'Root/Microsoft/Windows/TaskScheduler' `
                -Property @{ TaskName = 'Up'; TaskPath = '\Vendor\'; State = $script:TaskState }
        }
        Mock -ModuleName Tuneup Disable-ScheduledTask { $script:Calls.Add('task off'); $script:TaskState = 'Disabled' }
        Mock -ModuleName Tuneup Enable-ScheduledTask { $script:Calls.Add('task on'); $script:TaskState = 'Ready' }
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = $script:ServiceStart; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc {
            $script:Calls.Add("sc $Name $Start")
            $script:ServiceStart = @{ demand = 'Manual'; auto = 'Automatic'; 'delayed-auto' = 'AutomaticDelayed' }[$Start]
        }
        Mock -ModuleName Tuneup Stop-Service { throw 'a service is never stopped' }
        Mock -ModuleName Tuneup Start-Service { $script:Calls.Add('service started') }
    }

    It 'disables the task and sets the service to Manual as an elevated run, which -Status checks and -Undo gives back' {
        $elevated = New-TestEnvironment -IsAdmin $true
        $context = New-TestContext -Json -Environment $elevated
        $ids = @($Entries | ForEach-Object { $_.id })
        $plan = Invoke-TestStartup $context -Disable $ids -PlanOnly
        $plan.requiresAdmin | Should -BeTrue
        @($plan.items | ForEach-Object { "$($_.type)=$($_.action)" }) -join ';' | Should -Be 'task=apply;service=apply'
        $context = New-TestContext -Json -Environment $elevated
        $report = Invoke-TestStartup $context -Disable $ids -Yes
        $context.ExitCode | Should -Be 0
        @($report.results | ForEach-Object { $_.status }) -join ';' | Should -Be 'applied;applied'
        $report.restorePoint | Should -Be 'created'
        @($Calls) -join ';' | Should -Be 'task off;sc VendorSvc demand'
        $status = Invoke-TestStatus $context.StateRoot -Environment $elevated
        @($status.items | ForEach-Object { $_.status }) -join ';' | Should -Be 'ok;ok'
        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot -Environment $elevated
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        @($undo.results | ForEach-Object { $_.status }) -join ';' | Should -Be 'restored;restored'
        # Back to delayed Automatic and running, as it was; nothing was stopped.
        @($Calls) -join ';' | Should -Be 'task off;sc VendorSvc demand;sc VendorSvc delayed-auto;service started;task on'
        $script:ServiceStart | Should -Be 'AutomaticDelayed'
        $script:TaskState | Should -Be 'Ready'
        Should -Invoke -ModuleName Tuneup Stop-Service -Times 0
    }

    It 'says not-present for a task and a service uninstalled since, and -Undo gives nothing back for them' {
        $elevated = New-TestEnvironment -IsAdmin $true
        $context = New-TestContext -Json -Environment $elevated
        (Invoke-TestStartup $context -Disable @($Entries | ForEach-Object { $_.id }) -Yes).results.status -join ';' | Should -Be 'applied;applied'
        # Both uninstalled.
        Mock -ModuleName Tuneup Get-ScheduledTask { }
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $false; startType = $null; running = $false } }
        @((Invoke-TestStatus $context.StateRoot -Environment $elevated).items | ForEach-Object { $_.status }) -join ';' | Should -Be 'not-present;not-present'
        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot -Environment $elevated
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        @($undo.results | ForEach-Object { "$($_.status):$($_.reason)" }) -join ';' | Should -Be 'restored:not-present;restored:not-present'
        @($Calls) -join ';' | Should -Be 'task off;sc VendorSvc demand'
    }

    It 'refuses them without administrator, with the reason needs-admin, and touches nothing' {
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($Entries | ForEach-Object { $_.id }) -Yes
        $context.ExitCode | Should -Be 1
        $refused.reason | Should -Be 'needs-admin'
        $Calls.Count | Should -Be 0
        Should -Invoke -ModuleName Tuneup New-TuneupRestorePoint -Times 0
    }
}

Describe 'Re-applying a startup entry that came back' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
        Add-TestRunValue 'Steam'
        $script:Entries = @(New-TestSteam)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:Entries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupWow64Process { $false }
    }
    AfterAll { Remove-TestKey }

    It 'leaves it out with a warning that says how to turn it off again, also when -Include names it' {
        $context = New-TestContext -Json
        Invoke-TestStartup $context -Disable @($SteamId) -Yes | Out-Null
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value $On -PropertyType Binary -Force | Out-Null
        $warning = Get-TuneupText -Key 'reapply.startupEntry' -Format $SteamId

        $reapply = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $reapply -Reapply -PlanOnly | ConvertFrom-Json
        $reapply.ExitCode | Should -Be 0
        $plan.source | Should -Be 'reapply'
        @($plan.items).Count | Should -Be 0
        $plan.warnings | Should -Contain $warning
        @($plan.warnings | Where-Object { $_ -match 'no longer in the catalog' }).Count | Should -Be 0

        $named = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $named -Reapply -PlanOnly -Include @($SteamId) | ConvertFrom-Json
        $named.ExitCode | Should -Be 0
        $plan.command | Should -Be 'plan'
        @($plan.warnings | Where-Object { $_ -eq $warning }).Count | Should -Be 1
        @($plan.warnings | Where-Object { $_ -eq (Get-TuneupText -Key 'reapply.notRevertedUnverified' -Format $SteamId) }).Count | Should -Be 0
        # Nothing was turned off again: it stays as the person left it.
        (Get-TestApproved)[0] | Should -Be 2
    }

    It 'says that a startup entry named in -Include did not come back' {
        $context = New-TestContext -Json
        Invoke-TestStartup $context -Disable @($SteamId) -Yes | Out-Null
        $named = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $named -Reapply -PlanOnly -Include @($SteamId) | ConvertFrom-Json
        $named.ExitCode | Should -Be 0
        $plan.warnings | Should -Contain (Get-TuneupText -Key 'reapply.notRevertedUnverified' -Format $SteamId)
    }

    It 'still refuses an id that is neither in the catalog nor of a startup entry' {
        $context = New-TestContext -Json
        Invoke-TestStartup $context -Disable @($SteamId) -Yes | Out-Null
        $named = New-TestContext -Json -StateRoot $context.StateRoot
        $refused = Invoke-TuneupStatusCommand -Context $named -Reapply -PlanOnly -Include @('test.unknown') | ConvertFrom-Json
        $named.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.unknownTweak' -Format 'test.unknown')
    }
}

Describe 'A startup entry that is no longer there' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
        Add-TestRunValue 'Steam'
        $script:Entries = @(New-TestSteam)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:Entries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupWow64Process { $false }
    }
    AfterAll { Remove-TestKey }

    It 'is not-present once its Run value is gone: -Status does not call it reverted, -Reapply says nothing and -Undo leaves it' {
        $context = New-TestContext -Json
        (Invoke-TestStartup $context -Disable @($SteamId) -Yes).results[0].status | Should -Be 'applied'
        $off = Get-TestApproved
        Remove-ItemProperty -LiteralPath $Run -Name 'Steam'
        (Invoke-TestStatus $context.StateRoot).items[0].status | Should -Be 'not-present'
        $reapply = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $reapply -Reapply -PlanOnly | ConvertFrom-Json
        $reapply.ExitCode | Should -Be 0
        @($plan.items).Count | Should -Be 0
        @($plan.warnings | Where-Object { $_ -eq (Get-TuneupText -Key 'reapply.startupEntry' -Format $SteamId) }).Count | Should -Be 0
        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        "$($undo.results[0].status):$($undo.results[0].reason)" | Should -Be 'restored:not-present'
        # Left as it was: nothing is written for an entry that no longer starts.
        (Get-TestApproved) -join ',' | Should -Be ($off -join ',')
    }

    It 'leaves out of the plan an entry whose Run value went away after the list was read' {
        Remove-ItemProperty -LiteralPath $Run -Name 'Steam'
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 0
        "$($plan.items[0].action):$($plan.items[0].reason)" | Should -Be 'skip:not-present'
        Test-Path -LiteralPath $Approved | Should -BeFalse
    }

    It 'never makes again the key of a Store app that was uninstalled' {
        $package = "$Key\SystemAppData\Vendor.App_abc"
        New-Item -Path "$package\StartAtLogon" -Force | Out-Null
        New-ItemProperty -LiteralPath "$package\StartAtLogon" -Name 'State' -Value 2 -PropertyType DWord | Out-Null
        $store = New-TuneupStartupEntry -Source 'store-app' -Key 'Vendor.App_abc\StartAtLogon' -Name 'Vendor App' -Target @{ StoreKeyPath = "$package\StartAtLogon"; StoreState = 2 }
        $store.canDisable = $true
        $script:Entries = @($store)
        $context = New-TestContext -Json
        (Invoke-TestStartup $context -Disable @($store.id) -Yes).results[0].status | Should -Be 'applied'
        (Get-ItemProperty -LiteralPath "$package\StartAtLogon").State | Should -Be 1
        Remove-Item -LiteralPath $package -Recurse -Force
        (Invoke-TestStatus $context.StateRoot).items[0].status | Should -Be 'not-present'
        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        "$($undo.results[0].status):$($undo.results[0].reason)" | Should -Be 'restored:not-present'
        Test-Path -LiteralPath $package | Should -BeFalse
    }
}