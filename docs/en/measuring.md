# How to measure: Lite versus Windows 11 LTSC

Versión en español: [../es/measuring.md](../es/measuring.md).

The design promises that the Lite profile (`lite`) ends below a clean Windows 11 LTSC install in idle RAM, processes and running services, without turning off Defender, Windows Update or WinRE. **That claim is not measured yet.** This document describes the manual method that will measure it before each release; the report is attached to the release. Plan 3 automates nothing.

## What is compared

| Machine | What it has |
|---|---|
| A: Windows 11 Pro, clean install | The official ISO of the same version as LTSC (24H2), no Microsoft account (local account), fully updated. |
| B: Windows 11 Enterprise LTSC 2024, clean install | The LTSC 2024 evaluation ISO, local account, fully updated. |

**A with Lite applied** is compared with **B untouched**. A untouched is the reference to see how much Lite gained.

## Prepare the virtual machines

1. Hyper-V (or the tool you use) with the same settings for both: 2 virtual processors, 4 GB of fixed RAM (no dynamic memory, which changes the available RAM between measurements), a 64 GB disk, NAT networking, TPM and Secure Boot on.
2. Install each system with a local account, accept the privacy options as they come (to measure what Windows ships by default) and run Windows Update until no updates are left. Restart as many times as it asks.
3. Wait for the first maintenance to finish: leave the machine on and unused for at least 30 minutes after the last update (indexing, .NET optimization, first-run tasks).
4. Copy `windows-tuneup` to `C:\Program Files\windows-tuneup` (a folder that only administrators can write to) on both machines.
5. Take a checkpoint (snapshot) of each machine in this state, so the measurement can be repeated.

## Measure

On each machine, in this order and with PowerShell **as administrator** (so the boot duration is read too; always compare measurements taken at the same elevation):

1. Restart, sign in and open nothing else.
2. Measure at idle, waiting two minutes:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Measure -IdleSeconds 120
   ```

3. Repeat steps 1 and 2 two more times (three measurements per state). The numbers vary between boots; the report uses the median of the three.

On machine A, also:

4. Apply Lite without questions. The tweaks that ask (`ask`) are skipped with `-Yes`; to measure the whole profile, add them by name with `-Include <id>,<id>` (the list is in [catalog.md](catalog.md#tweaks-that-ask-first)). Without them:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Profile lite -Yes
   ```

   Write down in the report whether it was measured with or without the tweaks that ask, and which ones were included with `-Include`.
5. Restart, sign in and wait 30 minutes (Windows reschedules tasks after big changes).
6. Restart again, sign in and measure, comparing with the last measurement taken before applying:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Measure -IdleSeconds 120 -Compare last
   ```

   `-Compare last` takes the most recent saved measurement, which is the third measurement before applying. Repeat step 6 two more times, comparing with the id of that earlier measurement (`-Compare <id>`).

## What is reported

For each machine and state: the median of RAM in use (MB), processes, running services, enabled scheduled tasks and boot duration. The report table has three columns (clean Pro, Pro + Lite, LTSC 2024) and one row per metric, plus:

- The `windows-tuneup` version (release tag) and the exact build of each machine (`-Measure -Json` keeps it in `environment`).
- How many tweaks Lite applied and which ones were skipped (the run's `result.json`).
- That Defender, Windows Update and WinRE are still on in A after applying: `Get-MpComputerStatus` (`AMServiceEnabled`, `RealTimeProtectionEnabled`), `Get-Service wuauserv` and `reagentc /info`.

The README claim only changes from "pending measurement" to measured when Pro + Lite ends below LTSC in the three main metrics (RAM, processes and services). If it does not, the report is published anyway, with the numbers.

## Back to the starting point

`-Undo last` undoes Lite on A (apps are reinstalled from the Store for the account that undoes). To repeat the measurement from scratch, go back to the checkpoint.
