BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'

    # The fixture catalog and profiles, plus a tweak that asks first, a high-risk one and a profile
    # with the one that asks.
    $script:Definitions = Join-Path $TestDrive 'definitions'
    $catalogDir = Join-Path $Definitions 'catalog'
    $profilesDir = Join-Path $Definitions 'profiles'
    New-Item -ItemType Directory -Path $catalogDir, $profilesDir -Force | Out-Null
    Copy-Item -Path (Join-Path $Fixtures 'catalog\*.json') -Destination $catalogDir
    Copy-Item -Path (Join-Path $Fixtures 'profiles\*.json') -Destination $profilesDir
    $extra = @(
        (New-TestTweak -Id 'menu.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.high' -Risk 'high' -Set ([pscustomobject]@{ path = $Key; name = 'High'; kind = 'DWord'; value = 1 }))
    )
    [System.IO.File]::WriteAllText((Join-Path $catalogDir 'menu.json'), (ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = $extra }) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'asking.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'asking' -Include @('menu.ask')) -Depth 10))

    # The profiles in the order of the menu: base first, then by file name.
    # 1 base, 2 asking, 3 extra, 4 nested, 5 system.
    function New-MenuContext([object[]]$Answers, [switch]$Admin) {
        $context = New-TuneupContext -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = $catalogDir
        $context.ProfilesPath = $profilesDir
        $context.Environment = New-TestEnvironment -IsAdmin ([bool]$Admin)
        $context
    }
    function Invoke-Menu($Context) { Invoke-TuneupMenu -Context $Context 3>$null 6>$null }
    function Get-Output($Context) { $Context.Io.Output -join "`n" }
    function Get-Value([string]$Name) {
        if (-not (Test-Path -LiteralPath $Key)) { return $null }
        (Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue).$Name
    }
}

Describe 'Invoke-TuneupMenu' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'shows the options and exits with 0, or at the end of the input' {
        $context = New-MenuContext @('0')
        Invoke-Menu $context
        $context.ExitCode | Should -Be 0
        Get-Output $context | Should -Match ' 1\. Optimize: choose profiles and apply them'
        Get-Output $context | Should -Match 'Not running as administrator'
        $context = New-MenuContext @($null)
        Invoke-Menu $context
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says when an option does not exist and asks again' {
        $context = New-MenuContext @('9', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'That is not one of the options'
    }

    It 'applies the chosen profiles after one question per tweak that asks first' {
        # Optimize, select "asking", go on, no to the high-risk list, yes to its tweak, apply, back to the menu, exit.
        $context = New-MenuContext @('1', '2', '', 'n', 'y', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[x\]  1\. Base \(base\): Test \(always\)'
        $text | Should -Match '\[x\]  2\. asking \(asking\)'
        $text | Should -Match '\[ \]  5\. System \(system\): Test \(administrator\)'
        $text | Should -Match '1/1 Title menu\.ask \[low risk\]: Reason'
        Get-Value 'One' | Should -Be 1
        Get-Value 'Ask' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'leaves out a tweak that asks first when the answer is no, with the reason declined' {
        $context = New-MenuContext @('1', '2', '', 'n', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -BeNullOrEmpty
        $result = Get-Content -LiteralPath (Join-Path @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName 'result.json') -Raw | ConvertFrom-Json
        ($result.results | Where-Object { $_.id -eq 'menu.ask' }).reason | Should -Be 'declined'
    }

    It 'adds a high-risk tweak only when it is asked for and the word is typed in full' {
        $context = New-MenuContext @('1', '', 'y', '1', '', 'no', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'They were not added.'
        Get-Value 'High' | Should -BeNullOrEmpty
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        $context = New-MenuContext @('1', '', 'y', '1', '', 'YES', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '\[high risk\] Title menu\.high \(menu\.high\): Reason'
        Get-Value 'High' | Should -Be 1
    }

    It 'shows the plan and changes nothing when it needs administrator' {
        $context = New-MenuContext @('1', '5', '', 'n', '', '0')
        $text = (Invoke-TuneupMenu -Context $context 3>$null 6>&1 | Out-String)
        $text | Should -Match 'System test'
        Get-Output $context | Should -Match 'This plan has system changes: open PowerShell as administrator'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'goes back without applying when the input ends in the middle' {
        $context = New-MenuContext @('1', '2', '', 'y', $null)
        { Invoke-Menu $context } | Should -Not -Throw
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'asks about a drifted tweak that asks first and one of high risk before applying them again' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        # Status, apply again, the word for the high-risk one, no to the one that asks, confirm, back, exit.
        $context = New-MenuContext @('2', 'r', 'YES', 'n', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[high risk\] Title menu\.high \(menu\.high\): Reason'
        $text | Should -Match '1/1 Title menu\.ask \[low risk\]: Reason'
        Get-Value 'One' | Should -Be 1
        Get-Value 'High' | Should -Be 1
        Get-Value 'Ask' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'leaves a drifted high-risk tweak alone unless its word is typed in full' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        $context = New-MenuContext @('2', 'r', 'y', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Not applied again: Title menu\.high\.'
        Get-Value 'High' | Should -Be 5
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'shows the status and applies again what Windows reverted' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $context = New-MenuContext @('2', 'r', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Windows reverted 1 tweaks'
        Get-Value 'One' | Should -Be 1
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory).Count | Should -Be 2
    }

    It 'undoes a whole run picked from the list' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 'w', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 1\. \d{8}-\d{6}  2 tweaks  \[pending\]  \(test folder\)'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'undoes one tweak of a run' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 't', '2', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 2\. Test two \(test\.two\)'
        Get-Value 'One' | Should -Be 1
        Get-Value 'Two' | Should -BeNullOrEmpty
    }

    It 'refuses the health check without administrator' {
        $context = New-MenuContext @('4', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '-Health needs PowerShell as administrator.'
    }

    It 'offers to repair right after a check that found damage, reusing that check' {
        $found = [pscustomobject]@{ schemaVersion = 1; command = 'health'; startedAt = '2026-10-01T10:00:00'; finishedAt = '2026-10-01T10:20:00'
            repairRequested = $false; repairRan = $false; before = $null; after = $null; recommendation = 'run-repair'; rebootRecommended = $false }
        Mock -ModuleName Tuneup Invoke-TuneupHealth { $found }
        Mock -ModuleName Tuneup Write-TuneupHealthReport { }
        $context = New-MenuContext @('4', 'y', 'y', '', '0') -Admin
        Invoke-Menu $context
        Should -Invoke Invoke-TuneupHealth -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { -not $Repair -and $null -eq $Previous }
        Should -Invoke Invoke-TuneupHealth -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Repair -and $Previous.startedAt -eq '2026-10-01T10:00:00' }
    }

    It 'measures and then compares with the last measurement' {
        $context = New-MenuContext @('5', '', '', '5', 'x', '0', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '-IdleSeconds must be between 0 and 3600.'
        $text | Should -Match 'Compare with the last measurement \(\d{8}-\d{6}\)'
        $context.Result.comparison | Should -Not -BeNullOrEmpty
    }
}
