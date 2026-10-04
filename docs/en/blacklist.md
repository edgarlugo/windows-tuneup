# Blacklist

Versión en español: [../es/blacklist.md](../es/blacklist.md).

These changes are **never applied**: they are in no profile, they cannot be asked for with `-Include`, and `-Force` does not enable them. The Claude skill does not offer them even when asked; it explains why not. The catalog tests (`tests/CatalogQuality.Tests.ps1`, block "Blacklist guard") fail if a catalog tweak touches any of the services, registry values, tasks or apps of this list.

What was evaluated and left out for other reasons (apps that cannot be reinstalled, unverified tweaks, engine limits) is at the end of [catalog.md](catalog.md#not-included).

## Security

| Change | Why not |
|---|---|
| Turning off Microsoft Defender, its real-time protection or its cloud protection (`DisableAntiSpyware`, `DisableRealtimeMonitoring`, `Set-MpPreference -SubmitSamplesConsent 2`) | It leaves the machine exposed and the performance gain is minimal. For code folders Microsoft recommends a Dev Drive, not exclusions. |
| Turning off SmartScreen (`EnableSmartScreen`, `SmartScreenEnabled`) | It is the defense against known malicious downloads and sites. |
| Turning off User Account Control (`EnableLUA`, `ConsentPromptBehaviorAdmin`) | Every program would run with administrator rights without asking. |
| Turning off the firewall (`EnableFirewall`, services `mpssvc`, `BFE`) | It opens the ports of every service to the network. |
| Turning off the CPU mitigations for Spectre and Meltdown (`FeatureSettingsOverride`) | A real security risk for little performance. |
| Turning off memory integrity (VBS/HVCI) **by default** | It only exists as the high-risk tweak `gaming.memory-integrity-off`, which no profile includes and which is applied only when asked for by name. Turning off VBS as a whole does not exist. |
| Turning off Windows Security, `webthreatdefsvc` or `webthreatdefusersvc` | They are the Defender interface and the protection against credential theft. |
| Changing the PowerShell execution policies | It is a security setting of the machine. |

## Updates and recovery

| Change | Why not |
|---|---|
| Turning Windows Update off completely (services `wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `BITS`; `NoAutoUpdate`, `DisableWindowsUpdateAccess`; tasks of `WindowsUpdate`, `UpdateOrchestrator` and `WaaSMedic`) | No security patches. At most, automatic restarts are avoided or feature updates are delayed. |
| Blocking Microsoft domains in `hosts` or in the firewall | It breaks Windows Update, the Store and activation. |
| Turning off or deleting WinRE (`C:\Recovery`, tasks of `RecoveryEnvironment`) | No local recovery from a broken boot. |
| Turning off System Restore or its tasks (`SystemRestore`, services `VSS` and `swprv`) | Besides protecting the user, the engine itself creates a restore point before system changes. |
| `DISM /ResetBase` by default | Problem updates can no longer be uninstalled. |
| Deleting the CBS and DISM logs | They are needed to diagnose repairs (`-Health`). |
| Turning off the `Chkdsk`, `Defrag`, `Servicing\StartComponentCleanup` or `Registry\RegIdleBackup` tasks, or the `DiskDiagnosticResolver` task | Disk and system health: TRIM on SSDs, SMART failure warnings, component store cleanup. |
| Removing the Microsoft Store or App Installer (winget) | Undoing any app depends on them. Removing the Store could at most be a separate option with a warning; it does not exist today. |

## Memory, disk and data

| Change | Why not |
|---|---|
| Removing the page file (`PagingFiles`) | Hangs when memory runs out and no crash dumps. |
| Registry cleaners | No measurable benefit; risk of breaking programs. |
| Deleting user folders (for example `%UserProfile%\OneDrive`) | Data loss. Uninstalling OneDrive (`apps.onedrive`) never deletes files and refuses when folders were moved to OneDrive or files only live in the cloud. |
| Turning Storage Sense on | It deletes files from the Recycle Bin and Downloads without asking. |
| Removing apps that keep the user's data inside the app (Sticky Notes, Journal, Whiteboard, OneNote) | Removing the app deletes those notes. |

## "Optimizations" that are placebo

| Change | Why not |
|---|---|
| Grouping svchost processes (`SvcHostSplitThresholdInKB`) | It only lowers the visible number of processes and removes the isolation between services. |
| Network tweaks (`NetworkThrottlingIndex`, `SystemResponsiveness`, TCP autotuning, `TcpAckFrequency`, `TCPNoDelay`, Nagle's algorithm) | No demonstrable effect on modern machines; most real-time games use UDP. |
| Forcing HPET (`bcdedit /set useplatformclock`) | Windows does not use it unless forced, and forcing it usually makes latency worse. It also touches the boot configuration. |
| Timer resolution, `Win32PrioritySeparation`, MMCSS priorities | Values already optimal or ignored; since Windows 10 2004 the resolution is per process. |
| Minimum processor state at 100%, the "Ultimate Performance" plan (`powercfg -duplicatescheme e9a42b02...`) | On modern CPUs it does not raise FPS, it raises temperature and power draw; the new plan cannot be undone cleanly. |
| Turning off fullscreen optimizations | It usually loses latency and the overlay; it only helps specific cases. |
| `NtfsDisable8dot3NameCreation`, `NtfsDisableLastAccessUpdate` | Marginal gain and it can break old installers. |

## Services that are never touched

| Service | Why not |
|---|---|
| `SharedAccess` (Internet Connection Sharing) | It carries the NAT of WSL2, the Hyper-V Default Switch, Docker Desktop and the mobile hotspot. |
| `vmcompute`, `vmms`, `hns`, `HvHost`, `LxssManager`, `WslService` | Virtualization, WSL, Hyper-V and containers (the Development profile keeps them). |
| `LanmanServer`, `LanmanWorkstation` | Microsoft: "do not disable"; file sharing, IPC$ and remote administration. |
| `WerSvc`, `DPS`, `WdiServiceHost`, `WdiSystemHost` | Crash handling, troubleshooters and diagnostics. Turning off report uploads (`privacy.error-reporting-off`) leaves the service alone. |
| `RmSvc` | Radio and airplane mode: without it Wi-Fi and Bluetooth cannot be controlled from Settings. |
| `WpnService` | Notifications and tiles. |
| `SysMain`, `WSearch` | The design keeps SysMain (it helps on hard disks); without WSearch Start and Explorer search stop finding files. |
| `XblGameSave`, `XblAuthManager`, `XboxNetApiSvc` | They are already Manual and Windows starts them when needed; disabling them breaks the Xbox and Game Pass sign-in. |
| `Spooler` | Without it nothing prints; it would only make sense with printer detection. |
| `EventLog`, `Schedule`, `Winmgmt`, `RpcSs`, `CryptSvc`, `sppsvc`, `AppIDSvc`, `TrustedInstaller` | Windows infrastructure: logs, tasks, WMI, RPC, certificates, activation, AppLocker and servicing. |

## Edge

| Change | Why not |
|---|---|
| Removing Microsoft Edge or WebView2 | It breaks Widgets, help and many apps that show web content, and leaves the machine without a supported browser. |

## What `-Startup` never turns off

`-Startup -Disable` turns off what starts with Windows without uninstalling or deleting anything: it writes the `StartupApproved` value that Task Manager uses (or the state of the startup task of a Store app, as Settings does), disables the task or sets the service to Manual, and `-Undo` gives it back. It never does so with what it shows as protected (rules in `catalog/startup/rules.json`, open to review) or with what it cannot turn off safely:

| What | Why not |
|---|---|
| Parts of Windows (with a checked signature of Windows) and the services of this list | Windows needs them; the security and update services follow the rule above |
| Services and drivers that run from the Windows folder without a checked signature (`unverified`) | It is not known whose they are: they are shown, but not turned off |
| Antivirus, firewall, what Windows Security Center lists, protected processes and agents of the organization (EDR, Sysmon, Intune, Configuration Manager) | They leave the machine exposed or out of the management of the organization |
| VPN clients | They cut the access to the network of the organization |
| Helpers of the drivers (audio console and services, touchpad, Fn keys, display and pen services), the services of driver packages and the drivers | Keys, sound, gestures or display modes stop working. The companion apps of the vendor (GeForce Experience or NVIDIA app, AMD Software, Armoury Crate, G HUB...) are not protected: they can be turned off and are recommended |
| Updaters of browsers and of Office (Edge, Chrome, Firefox, Brave, Opera, Vivaldi, Yandex, Click-to-Run) | Protected even though they are updaters: without them the browser and Office get no security patches, as with Windows Update. The updaters of other programs can be turned off |
| What a policy of the organization sets | The organization decides it |
| What runs only once (`RunOnce`) | Turning it off would mean deleting it |
| What could not be read completely, what shares its id with another entry, and tasks with wildcard characters in their name | The id could name something other than what you see |

A service is never set to Disabled, only to Manual, and it is not stopped. What is recommended is only a mark: nothing is turned off unless you choose it. To uninstall a program the tool only shows the command (`winget uninstall --id <id> --exact`); it never runs it.
