# Ctrl+C while tweaks are applied: the tweak in progress finishes, the rest is left out and the run
# ends with its normal report and exit code 2. While the trap is on, the console hands Ctrl+C to
# PowerShell as a key (TreatControlCAsInput) instead of stopping it; the apply looks for that key
# between two tweaks.
#
# A native program that runs in between (cmd.exe, sc.exe, DISM, winget) can set the console back to
# normal Ctrl+C handling, so every check turns the trap on again. A Ctrl+C that arrives while such a
# program runs stops the program and PowerShell at once: the apply then saves what it has from its
# finally block, and the journal, written before each change, still lets -Undo restore the tweak that
# was cut. Without a console (input redirected, as when another program runs tuneup.ps1 -Json) there
# is no key to read and Ctrl+C keeps its usual meaning.

function Enable-TuneupInterruptTrap {
    try {
        if ([Console]::IsInputRedirected) { return $null }
        $previous = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
        [pscustomobject]@{ PSTypeName = 'Tuneup.InterruptTrap'; Previous = $previous }
    } catch {
        # No console to configure (a host without one): Ctrl+C keeps its usual meaning.
        $null
    }
}

# True when Ctrl+C was pressed since the last check. Every other key typed meanwhile is dropped.
function Test-TuneupInterruptRequested {
    param([AllowNull()]$Trap)
    if ($null -eq $Trap) { return $false }
    $requested = $false
    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::C -and ($key.Modifiers -band [ConsoleModifiers]::Control)) { $requested = $true }
    }
    # A native program that ran since the last check may have turned the trap off.
    [Console]::TreatControlCAsInput = $true
    $requested
}

function Disable-TuneupInterruptTrap {
    param([AllowNull()]$Trap)
    if ($null -eq $Trap) { return }
    [Console]::TreatControlCAsInput = [bool]$Trap.Previous
}
