# Profiles

Versión en español: [../es/profiles.md](../es/profiles.md).

A profile is a list of catalog tweaks grouped by goal. `base` is always applied; the others combine: `-Profile privacy,gaming`. A profile can also be named by its alias (`privacidad`, `juegos`...). The full list of tweaks, with their risk and sources, is in [catalog.md](catalog.md); what is never applied, in [blacklist.md](blacklist.md).

Rules that apply to all of them:

- **Look at the plan first:** `.\tuneup.ps1 -Profile <profile> -WhatIf` shows what changes and why each tweak is skipped. It changes nothing.
- **`keep` wins:** if one profile keeps something (Gaming keeps Xbox) and another would remove it (Lite), it is kept. Asking for it by name with `-Include` wins over `keep`.
- **Questions:** tweaks that change something someone might be using have `ask: true`. Until the interactive menu exists they are skipped with the reason "needs confirmation"; to apply them, ask for them by name: `-Include apps.onedrive`.
- **High risk:** no profile includes high-risk tweaks; they are only applied with `-Include`.
- **Edition and hardware:** a policy that your edition ignores (for example, Home) or a tweak meant for other hardware (with or without a battery) is skipped and the plan says why.
- **Machines of an organization:** on a domain-joined or Intune-enrolled machine policies (`\Policies\`) are left alone: the plan shows them as "managed device".
- **Administrator:** `base` and `work` only hold settings of your user that are not policies and apply without elevation. The others bring system changes or policies of your user (Windows only lets an administrator read and write them): open PowerShell as administrator, or leave those tweaks out with `-Exclude`. Without elevation the plan marks them as needing an administrator and applying refuses.
- **Undo:** `.\tuneup.ps1 -Undo last` gives back everything of the last run. Apps are reinstalled from the Store for your account (see the README).

## Base (`base`)

**What it does:** removes ads and suggestions from Start, Settings, the lock screen, File Explorer and search (search highlights), turns off the advertising ID, tailored experiences and feedback surveys, and shows file extensions.

**Why:** it is what any machine gains without losing anything: less noise, and an `invoice.pdf.exe` file shows what it is.

**What it keeps:** everything else. It touches no services, tasks, apps or policies, so it is also safe on a work machine.

**Administrator:** no. It is always applied together with any other profile.

## Development (`dev`, alias `desarrollo`)

**What it does:** turns on Developer Mode (symbolic links without administrator, test apps), paths longer than 260 characters (`node_modules`, git), shows hidden files, adds "End task" to the taskbar menu and stops suspending USB devices while plugged in (debugging devices).

**Asks before:** `dev.sudo-enable` (sudo for Windows).

**What it keeps:** WSL, Hyper-V, Virtual Machine Platform, containers and Windows Terminal. No catalog tweak touches their services (`vmcompute`, `vmms`, `hns`, `HvHost`, `LxssManager`, `WslService`) or `SharedAccess`, which carries the network of WSL2 and Hyper-V; a test checks it.

**What it does not do:** Defender exclusions for your code folders (they remove protection; Microsoft recommends a Dev Drive) or creating a Dev Drive (it needs a volume to be formatted). For git, `git config --global core.longpaths true` complements long paths.

**Administrator:** yes. Long paths ask for a restart.

## Gaming (`gaming`, alias `juegos`)

**What it does:** turns on Game Mode, turns off Game DVR, capture and background recording, removes mouse acceleration (1:1, noticed after signing in again), turns on optimizations for windowed games, hardware-accelerated GPU scheduling **only when the driver supports it** (otherwise the plan says "does not exist on this machine") and stops suspending USB devices while plugged in.

**Asks before:** `gaming.gamebar-controller-off` (the controller's Xbox button no longer opens Game Bar) and `power.high-performance-plan` (High performance plan; only on machines without a battery).

**What it keeps:** the Xbox apps and Game Bar and their game save task, which Game Pass and many games need. The Xbox services are not in the catalog: they are already Manual and disabling them breaks the Xbox sign-in. Combined with Lite, they are kept too.

**High risk, only with `-Include`:** `gaming.memory-integrity-off` (memory integrity): it can give 1 to 15% more FPS in some games in exchange for less protection against malicious drivers.

**Administrator:** yes. GPU scheduling asks for a restart.

## Privacy (`privacy`, alias `privacidad`)

**What it does:** keeps diagnostic data at "Required" (Pro, Enterprise and Education; Home ignores that policy), turns off the Customer Experience Improvement Program, activity history and its upload, cloud clipboard, app launch tracking, online speech (Win+H dictation stops working), typing personalization, Bing and history in search, recent files in Start, Copilot and Click to Do, the cloud AI features of Notepad and Paint, the telemetry tasks and what Edge sends to Microsoft. It removes the Bing integration in Start.

**Asks before:** `privacy.location-off`, `privacy.find-my-device-off`, `privacy.error-reporting-off`, `services.diagtrack` (the telemetry service; do not use it with Defender for Endpoint), `tasks.mare-backup` (it also runs the compatibility appraiser), `tasks.appraiser`, `tasks.appraiser-exp` and `tasks.program-data-updater` (they can stop Windows from offering feature updates) and `apps.copilot`.

**High risk, only with `-Include`:** `privacy.diagnostic-data-off` (diagnostic data fully off, Enterprise and Education only). Use it together with `-Exclude privacy.diagnostic-data-required`, which writes the same value. `ai.recall-snapshots-off` and `ai.recall-unavailable` are high risk too (Recall: they delete the snapshots already saved and undo cannot bring them back); no profile includes them.

**What it keeps:** security updates. The Edge policies make Edge say "Managed by your organization": it is only a notice.

**Administrator:** yes.

## Laptop (`laptop`, aliases `portatil`, `portátil`)

**What it does:** stops Store apps from running in the background (you can allow apps one by one in Settings), removes Edge's preloaded processes, stops sharing Windows downloads with other PCs, and sets the scanner and maps services to manual.

**Asks before:** `performance.background-apps-off` (Windows 10 only: Store apps do not notify while closed and Windows Spotlight backgrounds may stop refreshing) and `power.standby-network-off-battery` (no network during modern standby on battery; only on machines with a battery and Pro or later).

**What it keeps:** SysMain, modern standby, hibernation and the manufacturer's power plan.

**Administrator:** yes.

## Older PC (`legacy`, aliases `equipo-antiguo`, `antiguo`)

**What it does:** turns off transparency, window animations, shadows and translucent selection and Aero Peek (some show after signing in again), Widgets and News and interests, File Explorer's folder type detection, Store apps in the background and Edge in the background; stops sharing Windows downloads with other PCs, sets the scanner and maps services to manual; turns off background tasks that weigh on hard disks (WinSAT, diagnostics, maps, Work Folders) and removes preinstalled apps that almost nobody uses (Clipchamp, News, Weather, Finance, Messaging, Mixed Reality Portal, Movies & TV).

**Asks before:** `performance.background-apps-off` (Windows 10 only; see Laptop).

**What it keeps:** everything in Base, Defender, Windows Update and search (smaller indexing is not in the catalog yet).

**Administrator:** yes.

## Work (`work`, alias `trabajo`)

**What it does:** only settings of your user that are not policies: typing and speech privacy, language list, app launch tracking, Bing, search history, recent files and the Copilot button.

**Why:** on a machine of an organization the policies belong to IT. This profile touches none and needs no administrator.

**What it keeps:** Teams, Outlook (new), OneDrive, Microsoft 365 and Power Automate, even when combined with Lite.

**Administrator:** no.

## Lite (`lite`, alias `liviano`)

**What it does:** removes what Windows 11 LTSC does not ship (preinstalled apps, Widgets, Copilot, Teams, Xbox, Phone Link, the new Outlook, Mail and Calendar; OneDrive asks first) and trims services and tasks that LTSC keeps: telemetry, maps, scanner, the Xbox game save task, connected devices, Work Folders, WinSAT. Search stays local (no Bing). Edge without promotional content or background processes.

**Asks before:** `services.diagtrack`, `services.geolocation`, `services.connected-devices`, `services.connected-devices-user`, `services.contact-data`, `services.user-data-storage`, `services.user-data-access`, `tasks.appraiser`, `tasks.appraiser-exp`, `tasks.program-data-updater`, `tasks.mare-backup`, `tasks.family-safety-monitor`, `tasks.family-safety-refresh`, `apps.copilot`, `apps.get-help`, `apps.alarms-clock`, `apps.media-player`, `apps.quick-assist`, `apps.phone-link`, `apps.xbox-gaming-app`, `apps.xbox-game-bar`, `apps.outlook-new`, `apps.family-safety`, `apps.mail-calendar`, `apps.msteams` and `apps.onedrive`. Uninstalling OneDrive never deletes files: it refuses when Desktop, Documents or Pictures are in OneDrive, when files only live in the cloud, when not every file could be checked, when another account of the machine has data at risk or when the process does not run as the account signed in to the desktop.

**What it keeps:** Defender, security updates, WinRE, the Store and winget (undo depends on them). Removing the Store is not in the catalog.

**Lighter than LTSC?** That is the goal, but it is not measured yet. The method is in [measuring.md](measuring.md).

**Administrator:** yes.
