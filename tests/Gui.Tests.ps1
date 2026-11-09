BeforeAll {
    $script:Repo = Split-Path $PSScriptRoot -Parent
    . (Join-Path $Repo 'gui\GuiCore.ps1')
    Initialize-TuneupGuiText -Lang 'en'
    $script:Xaml = [System.IO.File]::ReadAllText((Join-Path $Repo 'gui\MainWindow.xaml'))
    $script:WindowCode = [System.IO.File]::ReadAllText((Join-Path $Repo 'gui\GuiWindow.ps1'))
    $script:Strings = @{}
    foreach ($lang in 'es', 'en') {
        $json = [System.IO.File]::ReadAllText((Join-Path $Repo "i18n\$lang.json")) | ConvertFrom-Json
        $script:Strings[$lang] = @($json.PSObject.Properties.Name)
    }
    function Get-ThemeKey([string]$Name) {
        @(([xml][System.IO.File]::ReadAllText((Join-Path $Repo "gui\Themes\$Name.xaml"))).ResourceDictionary.SolidColorBrush | ForEach-Object { $_.Key } | Sort-Object)
    }
}

Describe 'New-TuneupGuiArgument' {
    It 'gives the arguments of <Action>' -TestCases @(
        @{ Action = 'list'; Options = @{}; Expected = '-List -Json -Lang en' }
        @{ Action = 'status'; Options = @{}; Expected = '-Status -Json -Lang en' }
        @{ Action = 'reapply'; Options = @{ PlanOnly = $true }; Expected = '-Status -Reapply -WhatIf -Json -Lang en' }
        @{ Action = 'apply'; Options = @{ Profile = @('base', 'gaming'); Include = @('gaming.memory-integrity-off'); PlanOnly = $true }; Expected = '-Profile base,gaming -Include gaming.memory-integrity-off -WhatIf -Json -Lang en' }
        @{ Action = 'apply'; Options = @{ Profile = @('privacy'); Exclude = @('privacy.bing') }; Expected = '-Profile privacy -Exclude privacy.bing -Yes -Json -Lang en' }
        @{ Action = 'undo'; Options = @{ Run = 'last' }; Expected = '-Undo last -Json -Lang en' }
        @{ Action = 'undo'; Options = @{ Run = '20261021-200314'; Tweak = @('base.ads') }; Expected = '-Undo 20261021-200314 -Tweak base.ads -Json -Lang en' }
        @{ Action = 'health'; Options = @{ Repair = $true }; Expected = '-Health -Repair -Json -Lang en' }
        @{ Action = 'measure'; Options = @{ IdleSeconds = 120; Compare = @('last') }; Expected = '-Measure -IdleSeconds 120 -Compare last -Json -Lang en' }
        @{ Action = 'startup-disable'; Options = @{ Disable = @('startup.run-user.steam-eb4bc901e3d06cf1') }; Expected = '-Startup -Disable startup.run-user.steam-eb4bc901e3d06cf1 -Yes -Json -Lang en' }
        @{ Action = 'clean'; Options = @{ Large = $true }; Expected = '-Clean -Large -Json -Lang en' }
        @{ Action = 'clean-remove'; Options = @{ Remove = @('clean.temp-user', 'clean.pip-cache'); PlanOnly = $true }; Expected = '-Clean -Remove clean.temp-user,clean.pip-cache -WhatIf -Json -Lang en' }
        @{ Action = 'clean-remove'; Options = @{ Remove = @('clean.temp-user'); ResultId = '3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12' }; Expected = '-Clean -Remove clean.temp-user -Yes -ResultId 3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12 -Json -Lang en' }
        @{ Action = 'read-result'; Options = @{ ResultId = '3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12' }; Expected = '-ReadResult 3f2a9c1e-0b7d-4e55-9a10-2c4b6d8e0f12 -Json -Lang en' }
    ) {
        param($Action, $Options, $Expected)
        (New-TuneupGuiArgument -Action $Action -Options $Options) -join ' ' | Should -BeExactly $Expected
    }

    It 'refuses <Name>, so nothing else reaches the command line' -TestCases @(
        @{ Name = 'an id with a separator'; Action = 'clean-remove'; Options = @{ Remove = @('clean.temp-user; calc') } }
        @{ Name = 'an id with a space'; Action = 'startup-disable'; Options = @{ Disable = @('a b') } }
        @{ Name = 'an id with a quote'; Action = 'apply'; Options = @{ Profile = @('base"') } }
        @{ Name = 'an id that starts like a parameter'; Action = 'undo'; Options = @{ Run = '-Force' } }
        @{ Name = 'applying without a profile'; Action = 'apply'; Options = @{} }
        @{ Name = 'an unknown action'; Action = 'format-disk'; Options = @{} }
    ) {
        param($Action, $Options)
        { New-TuneupGuiArgument -Action $Action -Options $Options } | Should -Throw
    }
}

Describe 'ConvertTo-TuneupGuiCommandLine' {
    It 'quotes only what has a space or a quote' {
        ConvertTo-TuneupGuiCommandLine -Argument @('-File', 'C:\Program Files\windows-tuneup\tuneup.ps1', '-List', 'a"b') |
            Should -BeExactly '-File "C:\Program Files\windows-tuneup\tuneup.ps1" -List "a\"b"'
    }
}

Describe 'ConvertFrom-TuneupGuiDocument' {
    It 'reads a document of the engine' {
        (ConvertFrom-TuneupGuiDocument -Text '{"schemaVersion":1,"command":"status","items":[]}').command | Should -Be 'status'
    }

    It 'says why there is no document: <Name>' -TestCases @(
        @{ Name = 'no output'; Text = ''; Expected = 'The action gave nothing back.' }
        @{ Name = 'not JSON'; Text = 'WARNING: something'; Expected = 'The action did not give a valid document back.' }
        @{ Name = 'JSON that is not a document'; Text = '{"a":1}'; Expected = 'The action did not give a valid document back.' }
    ) {
        param($Text, $Expected)
        { ConvertFrom-TuneupGuiDocument -Text $Text } | Should -Throw $Expected
    }
}

Describe 'Get-TuneupGuiErrorView' {
    It 'offers <Action> for <Reason>' -TestCases @(
        @{ Reason = 'needs-admin'; Action = 'elevate' }
        @{ Reason = 'session-user'; Action = 'unelevated' }
        @{ Reason = 'result-missing'; Action = 'log' }
        @{ Reason = 'result-incomplete'; Action = 'log' }
        @{ Reason = 'result-untrusted'; Action = 'log' }
        @{ Reason = ''; Action = 'copy' }
    ) {
        param($Reason, $Action)
        $document = [pscustomobject]@{ command = 'error'; message = 'Nothing was deleted.'; details = @('one', 'two'); reason = $Reason }
        $view = Get-TuneupGuiErrorView -Document $document
        $view.Action | Should -Be $Action
        $view.Message | Should -Be 'Nothing was deleted.'
        $view.Details | Should -Be @('one', 'two')
        $view.Title | Should -Not -BeLike 'gui.*'
    }

    It 'reads an error without a reason' {
        (Get-TuneupGuiErrorView -Document ([pscustomobject]@{ command = 'error'; message = 'x'; details = @() })).Action | Should -Be 'copy'
    }
}

Describe 'The log of the window' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](Initialize-TuneupGuiLog -Folder $Folder)
    }
    AfterEach { Set-TuneupGuiLogListener -Listener $null }

    It 'writes one line per event, with a byte order mark, and keeps the lines of the session' {
        Write-TuneupGuiLog -Level INFO -Text 'started'
        Write-TuneupGuiLog -Level ERROR -Text 'failed'
        $file = @(Get-ChildItem -LiteralPath $Folder -Filter 'gui-*.log')[0]
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        $lines = @([System.IO.File]::ReadAllLines($file.FullName))
        $lines.Count | Should -Be 2
        $lines[1] | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} ERROR failed$'
        @(Get-TuneupGuiLogLine).Count | Should -Be 2
    }

    It 'hides the profile folder and control characters' {
        Write-TuneupGuiLog -Level WARN -Text ("in " + [Environment]::GetFolderPath('UserProfile') + "\AppData`r`nnext")
        $line = @(Get-TuneupGuiLogLine)[-1]
        $line.Text | Should -BeExactly 'in %USERPROFILE%\AppData  next'
    }

    It 'gives each new line to the window' {
        $seen = New-Object System.Collections.Generic.List[string]
        Set-TuneupGuiLogListener -Listener { param($entry) $seen.Add($entry.Text) }.GetNewClosure()
        Write-TuneupGuiLog -Level INFO -Text 'one'
        $seen | Should -Be @('one')
    }

    It 'keeps the 30 newest files and nothing that is not its own' {
        foreach ($day in 1..35) { New-Item -ItemType File -Path (Join-Path $Folder ('gui-202610{0:00}.log' -f $day)) -Force | Out-Null }
        New-Item -ItemType File -Path (Join-Path $Folder 'other.log') | Out-Null
        [void](Initialize-TuneupGuiLog -Folder $Folder)
        @(Get-ChildItem -LiteralPath $Folder -Filter 'gui-*.log').Count | Should -Be 30
        Test-Path -LiteralPath (Join-Path $Folder 'gui-20261001.log') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $Folder 'other.log') | Should -BeTrue
    }
}

Describe 'Formats of the window' {
    AfterEach { Initialize-TuneupGuiText -Lang 'en' }

    It 'gives <Expected> for <Bytes> bytes in <Lang>' -TestCases @(
        @{ Bytes = 1536; Lang = 'en'; Expected = '2 KB' }
        @{ Bytes = 350MB; Lang = 'en'; Expected = '350 MB' }
        @{ Bytes = 1.44GB; Lang = 'en'; Expected = '1.4 GB' }
        @{ Bytes = 1.44GB; Lang = 'es'; Expected = '1,4 GB' }
    ) {
        param($Bytes, $Lang, $Expected)
        Initialize-TuneupGuiText -Lang $Lang
        Format-TuneupGuiSize -Bytes ([long]$Bytes) | Should -Be $Expected
    }

    It 'shows a run id as a date, and anything else as it is' {
        Format-TuneupGuiRunId -Id '20261021-200314' | Should -Be '21 Oct 2026, 20:03:14'
        Format-TuneupGuiRunId -Id 'not-a-run' | Should -Be 'not-a-run'
    }

    It 'uses the text for one when there is one' {
        Get-TuneupGuiCountText -Key 'gui.common.tweaks' -Count 1 | Should -Be '1 tweak'
        Get-TuneupGuiCountText -Key 'gui.common.tweaks' -Count 3 | Should -Be '3 tweaks'
    }
}

Describe 'Settings of the window' {
    It 'keeps the language and the theme, and ignores values it does not know' {
        $path = Join-Path $TestDrive 'settings.json'
        Save-TuneupGuiSetting -Settings ([pscustomobject]@{ lang = 'es'; theme = 'dark' }) -Path $path
        $read = Read-TuneupGuiSetting -Path $path
        $read.lang | Should -Be 'es'
        $read.theme | Should -Be 'dark'
        [System.IO.File]::WriteAllText($path, '{"lang":"fr","theme":"neon"}')
        $read = Read-TuneupGuiSetting -Path $path
        $read.lang | Should -BeNullOrEmpty
        $read.theme | Should -Be 'system'
        (Read-TuneupGuiSetting -Path (Join-Path $TestDrive 'missing.json')).theme | Should -Be 'system'
    }

    It 'takes the theme that is asked for, and light or dark otherwise' {
        Get-TuneupGuiTheme -Choice 'dark' | Should -Be 'dark'
        Get-TuneupGuiTheme -Choice 'light' | Should -Be 'light'
        @('light', 'dark') | Should -Contain (Get-TuneupGuiTheme -Choice 'system')
    }

    It 'takes the high-contrast theme whenever Windows has high contrast on, whatever the choice' {
        foreach ($choice in 'system', 'light', 'dark') {
            Get-TuneupGuiTheme -Choice $choice -HighContrast $true | Should -Be 'highcontrast'
        }
        Get-TuneupGuiTheme -Choice 'dark' -HighContrast $false | Should -Be 'dark'
    }
}

Describe 'gui/MainWindow.xaml' {
    It 'is XML with no code inside and no handlers by name' {
        { [xml]$Xaml } | Should -Not -Throw
        $Xaml | Should -Not -Match 'x:Code'
        $Xaml | Should -Not -Match '\s(Click|Checked|Unchecked|Loaded|SelectionChanged|KeyDown|PreviewKeyDown|TextChanged)="'
        $Xaml | Should -Not -Match 'x:Class'
    }

    It 'has every element the window code uses' {
        $names = @([regex]::Matches($Xaml, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $match = [regex]::Match($WindowCode, '(?s)\$script:GuiElementNames = @\((.*?)\n\)')
        $wanted = @([regex]::Matches($match.Groups[1].Value, "'([A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value })
        $wanted.Count | Should -BeGreaterThan 80
        foreach ($name in $wanted) { $names | Should -Contain $name -Because $name }
    }

    It 'has a text in es and en for every x:Uid' {
        foreach ($key in @([regex]::Matches($Xaml, 'x:Uid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })) {
            foreach ($lang in 'es', 'en') { $Strings[$lang] | Should -Contain $key -Because "$lang $key" }
        }
    }

    It 'has the same tokens in the light, the dark and the high-contrast theme' {
        $light = Get-ThemeKey 'Light'
        $light.Count | Should -BeGreaterThan 20
        Get-ThemeKey 'Dark' | Should -Be $light
        Get-ThemeKey 'HighContrast' | Should -Be $light
        foreach ($key in @([regex]::Matches($Xaml + $WindowCode, "(?:DynamicResource |Get-GuiBrush '|SetResourceReference\([^,]+, ')([A-Za-z]+)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)) {
            $light | Should -Contain $key -Because $key
        }
    }

    It 'takes every color of the high-contrast theme from Windows' {
        $brushes = @(([xml][System.IO.File]::ReadAllText((Join-Path $Repo 'gui\Themes\HighContrast.xaml'))).ResourceDictionary.SolidColorBrush)
        foreach ($brush in $brushes | Where-Object { $_.Key -ne 'Scrim' }) {
            $brush.Color | Should -Match '^\{DynamicResource \{x:Static SystemColors\.[A-Za-z]+ColorKey\}\}$' -Because $brush.Key
        }
    }

    It 'has no color of its own outside the themes, so high contrast reaches every control' {
        $Xaml | Should -Not -Match '="#[0-9A-Fa-f]{3,8}"'
        $WindowCode | Should -Not -Match "'#[0-9A-Fa-f]{3,8}'"
    }

    It 'loads in a WPF window with each theme, and every element is there' {
        $script = Join-Path $TestDrive 'load.ps1'
        $code = @'
param($Repo)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $Repo 'gui\GuiCore.ps1')
. (Join-Path $Repo 'gui\GuiWindow.ps1')
foreach ($theme in 'light', 'dark', 'highcontrast') {
    $window = Import-GuiWindow -Theme $theme
    foreach ($name in $script:GuiElementNames) { if ($null -eq $window.FindName($name)) { throw "missing $name" } }
    [void]$window.FindResource('Accent')
}
# High contrast: the tokens are the colors of Windows.
foreach ($pair in @(@('Text', 'WindowTextColor'), @('Bg', 'WindowColor'), @('Accent', 'HighlightColor'), @('OnAccent', 'HighlightTextColor'), @('DisabledText', 'GrayTextColor'))) {
    $color = $window.FindResource($pair[0]).Color
    $system = [System.Windows.SystemColors]::($pair[1])
    if ($color -ne $system) { throw "$($pair[0]) is $color, not $system" }
}
'loaded'
'@
        [System.IO.File]::WriteAllText($script, $code)
        $output = & ([System.IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\powershell.exe')) -NoProfile -ExecutionPolicy Bypass -STA -File $script -Repo $Repo 2>&1
        ($output -join "`n") | Should -Match 'loaded$'
    }
}

Describe 'Texts of the window' {
    It 'has a text in es and en for every key the window code names' {
        $code = [System.IO.File]::ReadAllText((Join-Path $Repo 'gui\GuiCore.ps1')) + $WindowCode + [System.IO.File]::ReadAllText((Join-Path $Repo 'gui.ps1'))
        $keys = @([regex]::Matches($code, "Key '([a-z][A-Za-z0-9._-]*)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        # The keys the code builds from a value.
        $keys += @('home', 'optimize', 'status', 'undo', 'health', 'measure', 'startup', 'clean', 'log') | ForEach-Object { "gui.nav.$_" }
        $keys += @('apply', 'already-applied', 'needs-confirmation', 'other') | ForEach-Object { "gui.plan.tab.$_" }
        $keys += @('all', 'ok', 'drift', 'needs-admin', 'not-present', 'unknown') | ForEach-Object { "gui.statusTab.$_" }
        $keys += @('recommended', 'canDisable', 'protected', 'all') | ForEach-Object { "gui.startup.tab.$_" }
        $keys += @('all', 'INFO', 'WARN', 'ERROR') | ForEach-Object { "gui.log.tab.$_" }
        $keys += @('INFO', 'WARN', 'ERROR') | ForEach-Object { "gui.log.level.$_" }
        $keys += @('sfc', 'scan', 'repair', 'sfcAgain') | ForEach-Object { "gui.health.phase.$_" }
        $keys += @('generic', 'needs-admin', 'session-user', 'result-missing', 'result-incomplete', 'result-untrusted') | ForEach-Object { "gui.error.$_" }
        $keys.Count | Should -BeGreaterThan 150
        foreach ($key in $keys) {
            foreach ($lang in 'es', 'en') { $Strings[$lang] | Should -Contain $key -Because "$lang $key" }
        }
    }
}

Describe 'A job of the window' {
    It 'runs tuneup.ps1 with -Json and reads its document' {
        [void](Initialize-TuneupGuiLog -Folder (Join-Path $TestDrive 'joblog'))
        $job = Start-TuneupGuiJob -Action 'list' -Label 'list'
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-TuneupGuiJobDone -Job $job) -and $clock.Elapsed.TotalSeconds -lt 120) { Start-Sleep -Milliseconds 200 }
        $result = Complete-TuneupGuiJob -Job $job
        $result.Problem | Should -BeNullOrEmpty
        # The window never passes -Force, so on Windows Server (the CI runner) the engine refuses with an
        # error document: the job still has to read it and its exit code.
        $installation = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType -ErrorAction SilentlyContinue).InstallationType
        if ($installation -like 'Server*') {
            $result.Document.command | Should -Be 'error'
            $result.Document.message | Should -Match 'Windows Server'
            $code = 1
        } else {
            $result.Document.command | Should -Be 'list' -Because ([string]$result.Document.message)
            $code = 0
        }
        $result.ExitCode | Should -Be $code
        @(Get-TuneupGuiLogLine | Where-Object { $_.Text -like "Ends: list, code $code*" }).Count | Should -Be 1
    }
}
