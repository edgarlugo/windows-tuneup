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
    # menu.askadmin asks first and needs administrator (it is declined or never applied: no test runs elevated).
    $extra = @(
        (New-TestTweak -Id 'menu.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.ask2' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask2'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.ask3' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask3'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.askadmin' -Ask $true -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\Software\windows-tuneup-test'; name = 'AskAdmin'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.high' -Risk 'high' -Set ([pscustomobject]@{ path = $Key; name = 'High'; kind = 'DWord'; value = 1 }))
    )
    [System.IO.File]::WriteAllText((Join-Path $catalogDir 'menu.json'), (ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = $extra }) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'asking.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'asking' -Include @('menu.ask')) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'zadmin.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'zadmin' -Include @('menu.askadmin')) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'zmany.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'zmany' -Include @('menu.ask', 'menu.ask2', 'menu.ask3')) -Depth 10))

    # The profiles in the order of the menu: base first, then by file name.
    # 1 base, 2 asking, 3 extra, 4 nested, 5 system, 6 zadmin, 7 zmany.
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
    function Get-Count($Context, [string]$Pattern) { [regex]::Matches((Get-Output $Context), $Pattern).Count }
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
        Get-Output $context | Should -Match ' 4\. Windows health \(SFC and DISM\)'
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
        $text | Should -Match '\[x\]  1\. Base \(always\) \(base\): Test'
        $text | Should -Match '\[x\]  2\. asking \(asking\)'
        $text | Should -Match '\[ \]  5\. System \(administrator\) \(system\): Test'
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
        Get-Output $context | Should -Match 'Nothing was added\.'
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
        $text | Should -Not -Match 'To apply the system changes'
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

    It 'stops applying again what needs administrator before asking anything, like Optimize' {
        # Two reverted tweaks in a run: one of the system and one that asks first.
        New-RunFolder -Root $Root -Id '20250101-000000' -Tweaks @((New-TestMachineTweak),
            (New-TestTweak -Id 'menu.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 }))) | Out-Null
        $context = New-MenuContext @('2', 'r', '', '0')
        $hostText = (Invoke-TuneupMenu -Context $context 3>$null 6>&1 | Out-String)
        $text = Get-Output $context
        $text | Should -Match 'This plan has system changes: open PowerShell as administrator'
        $text | Should -Not -Match 'Title menu\.ask \[low risk\]'
        # The plan is shown once, with one line about administrator (the menu's, not the plan's).
        $hostText | Should -Match 'System test'
        $hostText | Should -Not -Match 'To apply the system changes'
        Test-Path -LiteralPath 'HKLM:\SOFTWARE\windows-tuneup-test' | Should -BeFalse
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'shows the status and applies again what Windows reverted' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $context = New-MenuContext @('2', 'r', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Tweaks reverted by Windows: 1\.'
        Get-Value 'One' | Should -Be 1
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory).Count | Should -Be 2
    }

    It 'undoes a whole run picked from the list' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 'w', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 1\. \d{8}-\d{6}  tweaks: 2  \[pending\]  \(test folder\)'
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
        Get-Output $context | Should -Match 'The health check needs PowerShell as administrator'
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
        $text | Should -Match 'Type a number between 0 and 3600\.'
        $text | Should -Not -Match '-IdleSeconds'
        $text | Should -Match 'Compare with the last measurement \(\d{8}-\d{6}\)'
        $context.Result.comparison | Should -Not -BeNullOrEmpty
    }

    It 'asks again, without showing the menu again, when the option does not exist or nothing was typed' {
        $context = New-MenuContext @('9', '', '0')
        Invoke-Menu $context
        Get-Count $context 'windows-tuneup 0\.' | Should -Be 1
        Get-Count $context 'That is not one of the options' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'asks for Enter before the menu comes back only when the option printed something' {
        $context = New-MenuContext @('1', '0', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Not -Match 'Press Enter to go back'
        $context.Io.Pending.Count | Should -Be 0
        $context = New-MenuContext @('2', '', '0')
        Invoke-Menu $context
        Get-Count $context 'Press Enter to go back' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says an answer that is not r is invalid when Windows reverted something, and Enter goes back at once' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $context = New-MenuContext @('2', 'x', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 1
        Get-Output $context | Should -Not -Match 'Press Enter to go back'
        Get-Value 'One' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'keeps base chosen and says so when its number is typed' {
        $context = New-MenuContext @('1', '1', '', 'n', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'Option 1 always stays selected'
        ([regex]::Matches($text, '\[x\]  1\. Base')).Count | Should -Be 2
        Get-Value 'One' | Should -Be 1
    }

    It 'says a number out of the list is not valid and changes nothing of the selection' {
        $context = New-MenuContext @('1', '2,9', '', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 1
        Get-Output $context | Should -Not -Match '1/1 Title menu\.ask'
        Get-Value 'Ask' | Should -BeNullOrEmpty
        Get-Value 'One' | Should -Be 1
    }

    It 'counts a number typed twice once' {
        $context = New-MenuContext @('1', '2,2', '', 'n', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '1/1 Title menu\.ask'
        Get-Value 'Ask' | Should -Be 1
    }

    It 'answers yes to the tweak asked and to all the rest with the first answer a' {
        $context = New-MenuContext @('1', '7', '', 'n', 'a', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context '\d/3 Title menu\.ask\d? ' | Should -Be 1
        foreach ($name in 'Ask', 'Ask2', 'Ask3') { Get-Value $name | Should -Be 1 }
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'answers no to the rest, but not to what was already said yes to, with x' {
        $context = New-MenuContext @('1', '7', '', 'n', 'y', 'x', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'Ask2' | Should -BeNullOrEmpty
        Get-Value 'Ask3' | Should -BeNullOrEmpty
        $result = Get-Content -LiteralPath (Join-Path @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName 'result.json') -Raw | ConvertFrom-Json
        @($result.results | Where-Object { $_.reason -eq 'declined' } | ForEach-Object { $_.id }) -join ',' | Should -Be 'menu.ask2,menu.ask3'
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'keeps asking after a no, and a later a applies the rest' {
        $context = New-MenuContext @('1', '7', '', 'n', 'n', 'a', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -BeNullOrEmpty
        Get-Value 'Ask2' | Should -Be 1
        Get-Value 'Ask3' | Should -Be 1
    }

    It 'says x on the first question and applies none of the tweaks that ask' {
        $context = New-MenuContext @('1', '7', '', 'n', 'x', 'y', '', '0')
        Invoke-Menu $context
        foreach ($name in 'Ask', 'Ask2', 'Ask3') { Get-Value $name | Should -BeNullOrEmpty }
        Get-Value 'One' | Should -Be 1
    }

    It 'asks again when the answer to a question is not one of the letters' {
        $context = New-MenuContext @('1', '2', '', 'n', 'q', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 1
        Get-Value 'Ask' | Should -Be 1
    }

    It 'stops a plan that needs administrator before asking anything' {
        $context = New-MenuContext @('1', '2,5', '', 'n', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'This plan has system changes'
        $text | Should -Not -Match 'Apply it\?'
        Get-Value 'Ask' | Should -BeNullOrEmpty
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'asks about a tweak that needs administrator, and goes on when the answer is no' {
        $context = New-MenuContext @('1', '6', '', 'n', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '1/1 Title menu\.askadmin'
        Get-Output $context | Should -Not -Match 'This plan has system changes'
        Get-Value 'One' | Should -Be 1
    }

    It 'says it needs administrator when the answer to a tweak that needs it is yes' {
        $context = New-MenuContext @('1', '6', '', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'This plan has system changes'
        Get-Value 'One' | Should -BeNullOrEmpty
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'talks about the menu, not about a parameter, when it says how to undo what it applied' {
        $context = New-MenuContext @('1', '', 'n', 'y', '', '0')
        $text = (Invoke-TuneupMenu -Context $context 3>$null 6>&1 | Out-String)
        $text | Should -Match 'To undo it, choose option 3 in the menu'
        $text | Should -Not -Match '-Undo'
    }

    It 'lists the 15 newest runs, newest first, and says that there are older ones' {
        foreach ($n in 1..17) { New-RunFolder -Root $Root -Id ('20260101-{0:D6}' -f $n) | Out-Null }
        $context = New-MenuContext @('3', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match ' 1\. 20260101-000017 '
        $text | Should -Match '15\. 20260101-000003 '
        $text | Should -Not -Match '20260101-000002'
        $text | Should -Match 'Only the 15 newest runs are listed'
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'does not mention older runs when all of them are listed' {
        New-RunFolder -Root $Root -Id '20260101-000001' | Out-Null
        $context = New-MenuContext @('3', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Not -Match 'newest runs are listed'
    }

    It 'asks again when the run, the way or the tweak is not valid' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '9', '1', 'z', 't', '0', '2', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 3
        Get-Value 'Two' | Should -BeNullOrEmpty
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'changes nothing when the undo is not confirmed, and asks for no Enter' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 'w', 'n', '0')
        Invoke-Menu $context
        Get-Value 'One' | Should -Be 1
        Get-Value 'Two' | Should -Be 'x'
        Get-Output $context | Should -Not -Match 'Press Enter to go back'
        $context.Io.Pending.Count | Should -Be 0
        $context = New-MenuContext @('3', '1', 't', '1', 'n', '0')
        Invoke-Menu $context
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says that a run or a tweak is already undone instead of asking to undo it' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 't', '1', 'y', '', '3', '1', 't', '1', '', '3', '1', 'w', 'y', '', '3', '1', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'The tweak "Test one" was already undone'
        $text | Should -Match 'Run \d{8}-\d{6} was already undone'
        Get-Value 'One' | Should -BeNullOrEmpty
        Get-Value 'Two' | Should -BeNullOrEmpty
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'goes back when the input ends in the middle of any picker' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        foreach ($answers in @(@('3', $null), @('3', '1', $null), @('3', '1', 't', $null), @('3', '1', 'w', $null), @('1', $null), @('1', '', $null), @('2', $null), @('5', $null))) {
            $context = New-MenuContext $answers
            { Invoke-Menu $context } | Should -Not -Throw -Because ($answers -join ',')
            $context.Io.Pending.Count | Should -Be 0 -Because ($answers -join ',')
        }
        Get-Value 'One' | Should -Be 1
    }

    It 'shows the error of an option that fails, goes back to the menu and leaves the exit code at 0' {
        $context = New-MenuContext @('1', '', '0')
        $context.CatalogPath = Join-Path $TestDrive 'no-such-catalog'
        Invoke-Menu $context
        $context.ExitCode | Should -Be 0
        $context.Io.Pending.Count | Should -Be 0
    }
}

Describe 'Invoke-TuneupMenu in Spanish' {
    BeforeAll {
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'es'
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }

    It 'goes through optimize with a question and a high-risk tweak, with plurals that fit any count' {
        # Optimize, asking, go on, see the high-risk ones, the first, go on, the word with a capital and an accent, yes to its question, apply.
        $siWord = "S$([char]0x00CD)"
        $context = New-MenuContext @('1', '2', '', 's', '1', '', $siWord, 's', 's', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[x\]  1\. Base \(siempre\) \(base\): Prueba'
        $text | Should -Match '\[ \]  5\. Sistema \(administrador\) \(system\): Prueba'
        $text | Should -Match 'Ajustes de riesgo alto que ning.n perfil aplica: 1\. .Quieres verlos\? \(s/n\)'
        $text | Should -Match 'Ajustes que preguntan antes de aplicarse: 1'
        $text | Should -Match 'Cambios por aplicar: 4\. .Aplicar\? \(s/n\)'
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'High' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'accepts the word of a high-risk tweak with or without the accent, and not part of it' {
        foreach ($case in @(@("s$([char]0x00ED)", $true), @('si', $true), @('s', $false))) {
            if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
            $context = New-MenuContext @('1', '', 's', '1', '', $case[0], 's', '', '0')
            Invoke-Menu $context
            ((Get-Value 'High') -eq 1) | Should -Be $case[1] -Because $case[0]
        }
    }

    It 'applies again a high-risk tweak that Windows reverted when the word is typed with the accent' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        $context = New-MenuContext @('2', 'r', "s$([char]0x00ED)", 'n', 's', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Ajustes revertidos por Windows: 3\.'
        Get-Value 'High' | Should -Be 1
        Get-Value 'Ask' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'lists the runs with a count that reads well for one tweak and for several' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 1\. \d{8}-\d{6}  ajustes: 2  \[pendiente\]'
    }
}

Describe 'Get-TuneupMenuBlockMessage' {
    BeforeAll {
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }

    It 'says the menu cannot ask when PowerShell was started with -NonInteractive, also with the input redirected' {
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-NoProfile', '-NonInteractive', '-File', 'tuneup.ps1') |
            Should -Match '-NonInteractive'
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-noni', '-File', 'tuneup.ps1') | Should -Not -BeNullOrEmpty
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '/NonI', '-ExecutionPolicy', 'Bypass', '-File', 'tuneup.ps1') | Should -Not -BeNullOrEmpty
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-NonInteractive', '-File', 'tuneup.ps1') | Should -Not -Match 'redirect the input'
    }

    It 'lets the menu run in an interactive PowerShell, whatever comes after the script' {
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-NoProfile', '-File', 'tuneup.ps1') | Should -BeNullOrEmpty
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-File', 'tuneup.ps1', '-NonInteractive') | Should -BeNullOrEmpty
    }
}
