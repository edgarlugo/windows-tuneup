# Virtual machine checklist before each release

Windows Sandbox (`tests/sandbox/Start-E2E.ps1`) tests every profile end to end, but it has no Microsoft Store and no winget, it starts clean every time and has no OneDrive signed in. This checklist covers the rest in a Windows 11 Pro virtual machine. It is done by hand before publishing each release, and its result is attached to the release with `e2e-report.md` and the measurement of [measuring.md](measuring.md).

## Prepare the virtual machine

1. Windows 11 Pro of the latest version, fully updated, with the Microsoft Store and winget working (`winget --version`).
2. A local administrator account signed in at the desktop.
3. OneDrive signed in, with a folder of files that only live in the cloud (Free up space).
4. System Restore **turned off** on `C:` (System Properties > System Protection), to test the warning.
5. A snapshot (checkpoint) of the machine in this state.

## Install the release candidate

Copy the zip, `install.ps1` and `SHA256SUMS` of the draft release to a folder of the virtual machine (or build them in the repository folder with `powershell -NoProfile -ExecutionPolicy Bypass -File .\build\package.ps1 -OutputPath <folder>`). In PowerShell as administrator, in that folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Source <folder> -Version <version> -Sha256 <hash of the zip>
```

- [ ] It installs in `C:\Program Files\windows-tuneup` and says `SHA256 checked`.
- [ ] With a wrong hash it installs nothing.

## Test

- [ ] `tuneup.ps1 -Status`: no tweak is applied.
- [ ] Restart, sign in and run `tuneup.ps1 -Measure -IdleSeconds 120`.
- [ ] `tuneup.ps1` without parameters opens the menu, in the classic Windows PowerShell console and in Windows Terminal; every option works with the keyboard only.
- [ ] Menu > Optimize > `lite`: before confirming, the warning "System Restore is turned off on the system drive..." appears; once the run is confirmed, answer yes to the question about turning it on, check it in System Properties, and the run reports "Restore point created.". Repeat answering no: it goes on without a restore point, with the backup of the tool only.
- [ ] The apps that ask first are answered one by one (yes to all but one); the chosen ones disappear from `Get-AppxPackage -AllUsers` and the other one stays with the reason "you said no".
- [ ] OneDrive with Desktop, Documents or Pictures in OneDrive: `apps.onedrive` is refused (`onedrive-known-folders`); without those folders but with files only in the cloud, refused (`onedrive-online-only-files`); with neither, it is uninstalled.
- [ ] Ctrl+C during a long `lite` run (command line): the tweak in progress finishes, the summary says "Stopped with Ctrl+C" and the exit code is 2; `tuneup.ps1 -Undo last` restores what was applied.
- [ ] Ctrl+C while a native program runs (for example winget when undoing apps) and with `-Json`: the standard output stays empty, the exit code is 2 and the document is the `result.json` of the newest folder under `runs` (`docs/json-contract.md`, section `apply`).
- [ ] `transcript.log` in the run folder tells what was shown and holds neither the account name nor the profile folder.
- [ ] Restart; `tuneup.ps1 -Status` shows everything `ok`; `tuneup.ps1 -Measure -IdleSeconds 120 -Compare last` gives the difference.
- [ ] `tuneup.ps1 -Undo last` (as many times as needed, until "There are no runs to undo"): the apps are reinstalled with winget (reason "reinstalled from the Microsoft Store"), OneDrive is reinstalled and `-Status` is empty.
- [ ] Against the snapshot: the apps are back (their version may differ) and OneDrive syncs again after signing in.
- [ ] Lite versus LTSC: the method of [measuring.md](measuring.md), with its report.

## Attach to the release

- `e2e-report.md` from Windows Sandbox.
- This checklist, ticked, with the Windows build used.
- The output of `-Measure -Compare` and the Lite versus LTSC report.
