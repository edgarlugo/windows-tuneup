BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # Ctrl+C needs a console of its own: the harness runs in a new, hidden console window. It presses
    # Ctrl+C by writing the key into that console's input (what the keyboard does), or sends the signal
    # that a native program would let through, and writes what it saw to a file.
    $script:Harness = @'
param([string]$Repo, [string]$Out, [string]$Mode, [string]$StateRoot)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TuneupTestConsole {
    [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
    public struct KeyEvent {
        [FieldOffset(0)] public int KeyDown;
        [FieldOffset(4)] public ushort RepeatCount;
        [FieldOffset(6)] public ushort VirtualKeyCode;
        [FieldOffset(8)] public ushort VirtualScanCode;
        [FieldOffset(10)] public char UnicodeChar;
        [FieldOffset(12)] public uint ControlKeyState;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct InputRecord {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KeyEvent Key;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GetStdHandle(int handle);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool WriteConsoleInput(IntPtr input, InputRecord[] records, uint length, out uint written);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint group);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
    public static bool PressCtrlC() {
        var records = new InputRecord[2];
        for (int i = 0; i < 2; i++) {
            records[i].EventType = 1;
            records[i].Key.KeyDown = i == 0 ? 1 : 0;
            records[i].Key.RepeatCount = 1;
            records[i].Key.VirtualKeyCode = 0x43;
            records[i].Key.VirtualScanCode = 0x2E;
            records[i].Key.UnicodeChar = (char)3;
            records[i].Key.ControlKeyState = 0x0008;
        }
        uint written;
        return WriteConsoleInput(GetStdHandle(-10), records, 2, out written) && written == 2;
    }
    public static void SendCtrlC() {
        SetConsoleCtrlHandler(IntPtr.Zero, false);
        GenerateConsoleCtrlEvent(0, 0);
    }
}
"@
function Save-Line([string]$Text) { Add-Content -LiteralPath $Out -Value $Text -Encoding UTF8 }
Import-Module (Join-Path $Repo 'engine\Tuneup.psm1') -Force
Initialize-TuneupI18n -Root (Join-Path $Repo 'i18n') -Lang en
Save-Line "redirected=$([Console]::IsInputRedirected)"
if ($Mode -eq 'trap') {
    $trap = Enable-TuneupInterruptTrap
    Save-Line "enabled=$($null -ne $trap)"
    Save-Line "pressedKey=$([TuneupTestConsole]::PressCtrlC())"
    Save-Line "requested=$(Test-TuneupInterruptRequested -Trap $trap)"
    Save-Line "again=$(Test-TuneupInterruptRequested -Trap $trap)"
    cmd.exe /c 'exit 0'
    Save-Line "afterNative=$([Console]::TreatControlCAsInput)"
    Test-TuneupInterruptRequested -Trap $trap | Out-Null
    Save-Line "rearmed=$([Console]::TreatControlCAsInput)"
    Disable-TuneupInterruptTrap -Trap $trap
    Save-Line "restored=$([Console]::TreatControlCAsInput)"
    exit 0
}
# key or signal: right after test.one is set, Ctrl+C comes as a key or as the signal.
& (Get-Module Tuneup) {
    param($Mode)
    $script:HarnessMode = $Mode
    $script:HarnessSet = ${function:Set-RegistryTweakDesired}
    function script:Set-RegistryTweakDesired {
        param($Tweak)
        & $script:HarnessSet -Tweak $Tweak
        if ($Tweak.id -ne 'test.one') { return }
        if ($script:HarnessMode -eq 'key') { [TuneupTestConsole]::PressCtrlC() | Out-Null; return }
        [TuneupTestConsole]::SendCtrlC()
        Start-Sleep -Seconds 10
    }
} $Mode
$context = New-TuneupContext -Json
try {
    Invoke-TuneupCli -Context $context -ScriptRoot $Repo -Yes -Force -StateRoot $StateRoot `
        -CatalogPath (Join-Path $Repo 'tests\fixtures\catalog') -ProfilesPath (Join-Path $Repo 'tests\fixtures\profiles') `
        -ActionsPath (Join-Path $Repo 'tests\fixtures\actions') | Out-Null
    Save-Line "trapAfter=$([Console]::TreatControlCAsInput)"
    Save-Line 'completed=True'
} finally {
    Save-Line "exit=$($context.ExitCode)"
    exit $context.ExitCode
}
'@

    function Invoke-Harness([string]$Mode) {
        $script:Out = Join-Path $TestDrive "$Mode-$([guid]::NewGuid()).txt"
        $script:StateRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script_ = Join-Path $TestDrive 'harness.ps1'
        [System.IO.File]::WriteAllText($script_, $Harness)
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script_`"", '-Repo', "`"$Repo`"", '-Out', "`"$Out`"", '-Mode', $Mode, '-StateRoot', "`"$StateRoot`"")
        $process = Start-Process -FilePath $PowerShell -ArgumentList $arguments -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(120000)) { $process.Kill(); throw "The $Mode harness did not finish" }
        $lines = @(if (Test-Path -LiteralPath $Out) { Get-Content -LiteralPath $Out -Encoding UTF8 })
        $seen = @{}
        foreach ($line in $lines) { $name, $value = $line -split '=', 2; $seen[$name] = $value }
        [pscustomobject]@{ ExitCode = $process.ExitCode; Seen = $seen; Text = ($lines -join "`n") }
    }
    function Get-RunResult {
        $dir = @(Get-ChildItem -LiteralPath (Join-Path $StateRoot 'runs') -Directory)[-1].FullName
        Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
    }
}

Describe 'Ctrl+C while applying' {
    BeforeEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'reads Ctrl+C as a key while the trap is on, and turns it on again after a native program' {
        $run = Invoke-Harness 'trap'
        if ($run.Seen['redirected'] -eq 'True') { Set-ItResult -Skipped -Because 'the harness got no console of its own'; return }
        $run.Text | Should -Not -BeNullOrEmpty
        $run.Seen['enabled'] | Should -Be 'True'
        $run.Seen['pressedKey'] | Should -Be 'True'
        $run.Seen['requested'] | Should -Be 'True'
        $run.Seen['again'] | Should -Be 'False'
        $run.Seen['afterNative'] | Should -Be 'False'
        $run.Seen['rearmed'] | Should -Be 'True'
        $run.Seen['restored'] | Should -Be 'False'
    }

    It 'finishes the tweak in progress, leaves the rest out and exits with 2' {
        $run = Invoke-Harness 'key'
        if ($run.Seen['redirected'] -eq 'True') { Set-ItResult -Skipped -Because 'the harness got no console of its own'; return }
        $run.ExitCode | Should -Be 2 -Because $run.Text
        $run.Seen['completed'] | Should -Be 'True'
        # The trap is off again once the command is done, so the console keeps its usual Ctrl+C.
        $run.Seen['trapAfter'] | Should -Be 'False'
        $result = Get-RunResult
        ($result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/interrupted'
        $result.summary.interrupted | Should -Be 1
        (Get-Item -LiteralPath $Key).GetValueNames() -join ',' | Should -Be 'One'
    }

    It 'saves what was done and exits with 2 when Ctrl+C stops PowerShell itself, and the undo restores it' {
        $run = Invoke-Harness 'signal'
        if ($run.Seen['redirected'] -eq 'True') { Set-ItResult -Skipped -Because 'the harness got no console of its own'; return }
        $run.ExitCode | Should -Be 2 -Because $run.Text
        $run.Seen.ContainsKey('completed') | Should -BeFalse
        $result = Get-RunResult
        ($result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=failed/,test.two=skipped/interrupted'
        $result.results[0].error | Should -Match '-Undo can restore it'
        $undo = @(Invoke-TuneupUndo -Run (Resolve-TuneupRun -StateRoot $StateRoot -RunId 'last' -WarningAction SilentlyContinue) -WarningAction SilentlyContinue)
        ($undo | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.one=restored'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }
}
