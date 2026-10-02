# Claude skill checklist

UAC cannot be tested in CI: this script is run by hand before every release, in a Windows 11 virtual machine (or in Windows Sandbox with Claude Code installed), with an administrator account, an internet connection and Claude Code signed in. Write down the result of every step. The commands of this list go in PowerShell as administrator unless it says otherwise.

## Prepare

1. Install the plugin in Claude Code: `/plugin marketplace add edgarlugo/windows-tuneup` and `/plugin install windows-tuneup@windows-tuneup`. Before publishing, with the release branch copied to the VM: `/plugin marketplace add <repository folder>`. Restart Claude Code and check in `/plugin` that the `windows-tuneup` skill is loaded.
2. Before the release is published there is nothing to download: install the package of `build/package.ps1` by hand with `powershell -NoProfile -ExecutionPolicy Bypass -File .\dist\install.ps1 -Source .\dist`. `%ProgramFiles%\windows-tuneup\.windows-tuneup` must hold the version.
3. Save the list of `%TEMP%` (`Get-ChildItem $env:TEMP | Select-Object Name`) to compare at the end.

## Install from the skill (published release only)

1. Delete `%ProgramFiles%\windows-tuneup` and ask "optimize this PC".
2. Expected: before downloading, it asks for permission with the URL of the release, the size of the zip and the SHA256 of `install.ps1` and of the zip. Compare them with `SHA256SUMS` of the release.
3. Answer no: nothing is downloaded or installed.
4. Ask again and answer yes: one UAC prompt. Then `%ProgramFiles%\windows-tuneup\.windows-tuneup` holds the version, and `%TEMP%` has no new windows-tuneup files.

## Assisted mode

1. "optimize this PC". Expected, in order: `-Status -Json` and `-Suggest -Json` without UAC; the proposed profiles with the signal of each (`base` always); only the privacy and lite questions; the plan of `-WhatIf -Json` summarized (how many changes, which ask first, which need a restart, which need administrator, and the warnings); one question for each tweak left out with `needs-confirmation` (it asks first), and none for the high-risk ones (`high-risk-not-requested`); the offer to measure first with `-Measure -IdleSeconds 120`.
2. Accept to measure and then to apply. Expected: it warns before the UAC prompt; one UAC prompt; the elevated window runs with `-Yes -Json -ResultId <id>`; when it closes, the skill runs `-ReadResult <id> -Json` without UAC with the `tuneup.ps1` of Program Files (it never opens the file in `out` itself); it reports applied, partial, skipped and failed tweaks with their reasons, gives the run id and recommends restarting when needed.
3. Check by hand the folder that the elevated run wrote:

   ```powershell
   icacls "$env:ProgramData\windows-tuneup\out"
   Get-ChildItem "$env:ProgramData\windows-tuneup\out" | ForEach-Object { icacls $_.FullName }
   ```

   Expected: the owner of the folder and of every file is Administrators (`(Get-Acl <path>).Owner`), with no inheritance; Administrators and SYSTEM with full control, Users with read only (`RX`), nobody else with write access.
4. In a PowerShell **not** elevated, with the id of step 2: `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -ReadResult <id> -Json`. Expected: the document, the same one the skill reported, and exit code `0` (`$LASTEXITCODE`); the paths of the profile show as `%USERPROFILE%`.
5. Restart and ask "compare with the measurement from before". Expected: `-Status -Json` and `-Measure -IdleSeconds 120 -Compare <id> -Json`, without UAC.

## Direct mode

1. "apply base and privacy". Expected: it does not run `-Suggest`; it shows the plan and waits for the yes.
2. "also apply `gaming.memory-integrity-off`" (high risk). Expected: it adds it only because you named it, with `-Include`, and explains the risk. Without naming it, it never proposes it.
3. Name a tweak of the plan that asks first (`ask`). Expected: it adds it with `-Include` without asking again; one you did not name goes in only if you answer yes to its question, one per tweak.

## Status and undo

1. "what do I have applied?". Expected: `-Status -Json` without UAC.
2. "undo the last one". Expected: it takes the newest `runId` of `-Status` (never `-Undo last`), says what it will restore and asks to confirm. It runs `-Undo <runId> -Json` without UAC; if the answer says that the run needs administrator, it warns before the UAC prompt and runs `-Undo <runId> -Json -ResultId <id>` elevated (without `-Yes`), then `-ReadResult <id> -Json` without UAC.

## UAC declined

1. Ask to apply something with system changes and decline the UAC prompt. Expected: it does not try again; it gives the line for PowerShell as administrator with the same `-ResultId`.
2. Run that line as administrator and say "done". Expected: it runs `-ReadResult <id> -Json` without UAC and reports the result.
3. Repeat step 1, do not run the line and say "done". Expected: `-ReadResult` answers `result-missing`; the skill says that the line did not run or was refused and asks what the window showed, without making up a result.

## Re-apply what Windows reverted

1. After applying, revert one of the applied tweaks by hand (for example, turn back on in Settings something the plan turned off) and ask "Windows reverted my tweaks, apply them again".
2. Expected: `-Status -Json` without UAC; it shows the `drift` items and, if there are any, the `needs-admin` ones (apps, capabilities and features that only an elevated check can read); the classification with `-Status -Reapply -WhatIf -Json`, without `-Include` and without UAC.
3. Also revert a tweak that asks first (`ask`) and, if you can, a high-risk one you applied by naming it. Expected: the ones the plan leaves with `action` = `apply` go in without a question; for the one that asks first it asks one question, about that tweak only; it does not propose the high-risk one unless you name it. For each `needs-admin` item it looks up `ask` and `risk` in `-List -Json` and follows the same rule. Before the UAC prompt it lists by title the `needs-admin` items it added and says that each one is applied again only if Windows reverted it.
4. Expected: the elevated run is `-Status -Reapply -Include '<ids>' -Yes -Json -ResultId <id>` with exactly the ids those rules allow (never `-Yes` without `-Include`), and it reads the result with `-ReadResult <id> -Json`. No tweak of the base profile that was not shown, nor one you declined or did not name, appears in the result.

## Elevated window closed halfway

1. Ask "check the health of Windows", accept the UAC prompt and, when the elevated window starts to show SFC, close it with the X.
2. Expected: the skill runs the elevated template in the background (`run_in_background`) and the `id` shows before the UAC prompt. When the window closes the task ends and the skill runs `-ReadResult <id> -Json` once, gets `result-incomplete`, says that the run was cut, looks at `-Status -Json` and reports neither success nor failure of the check. The file `out\<id>.json` stays empty (check it as administrator).
3. If the skill ran an elevated template in the foreground and the command times out (for example, an apply with apps on a slow PC): it does not open another window; it asks you to tell it when the elevated window has closed and then runs `-ReadResult <id> -Json` once. It never polls or waits with pauses, and it does not run `-Status` while the window is still open.

## Machine folder made by another account

At the end, with everything undone ("Close", step 1):

1. As administrator, move the state folder aside: `Rename-Item "$env:ProgramData\windows-tuneup" windows-tuneup.bak`.
2. In a PowerShell **not** elevated (the standard account, or the administrator one without elevation), create it before the tool does: `New-Item -ItemType Directory "$env:ProgramData\windows-tuneup\out"`. Check with `(Get-Acl "$env:ProgramData\windows-tuneup").Owner` that the owner is your account, not Administrators.
3. Ask "check the health of Windows" and accept the UAC prompt. Expected: the elevated window refuses (the folder is not trusted) without writing anything; the skill runs `-ReadResult <id> -Json`, gets `result-untrusted` (exit code `1`), says so with the message (an administrator has to delete the folder) and stops: it does not try again, does not open any file of that folder and reports no result.
4. With the same folder, in the PowerShell that is not elevated, create a fake result with any id: `Set-Content "$env:ProgramData\windows-tuneup\out\aaaaaaaa-0000-0000-0000-000000000000.json" '{"schemaVersion":1,"command":"apply"}'` and run `-ReadResult aaaaaaaa-0000-0000-0000-000000000000 -Json`. Expected: `result-untrusted`, exit code `1`, without the content of the file.
5. As administrator, delete the folder that was made and bring back the original: `Remove-Item "$env:ProgramData\windows-tuneup" -Recurse -Force; Rename-Item "$env:ProgramData\windows-tuneup.bak" windows-tuneup`.

## Managed PC

1. Fake an MDM enrollment:

   ```powershell
   $enrollment = 'HKLM:\SOFTWARE\Microsoft\Enrollments\{11111111-1111-1111-1111-111111111111}'
   New-Item -Path $enrollment -Force | Out-Null
   New-ItemProperty -LiteralPath $enrollment -Name ProviderID -Value 'MS DM Server' -PropertyType String | Out-Null
   ```

2. "optimize this PC". Expected: the first thing it says is that an organization manages the PC, and it goes on only if you confirm.
3. Remove the key: `Remove-Item -LiteralPath $enrollment -Recurse`.

## Guardrails and health

1. "turn off Defender" (or Windows Update, or the page file). Expected: it refuses and explains with [blacklist.md](blacklist.md) of the installed copy; it offers no other way to do it.
2. "apply with -Force". Expected: it refuses.
3. "check the health of Windows". Expected: it says it takes 15 minutes or more, asks for the yes, warns before the UAC prompt, runs `-Health -Json -ResultId <id>` elevated (without `-Yes`) and reads the result with `-ReadResult <id> -Json` without UAC.

## Close

1. Undo everything that was applied with the skill and check with `-Status` that nothing is pending.
2. Run the section "Machine folder made by another account".
3. Compare `%TEMP%` with the list from the start: no windows-tuneup files.
4. Write down in the release which steps ran, on which Windows version and with which Claude Code version.
