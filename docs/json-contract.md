# windows-tuneup JSON contract

What `tuneup.ps1 ... -Json` writes, for programs that drive it (the Claude skill of Plan 5 among them). This page is for developers and is kept in English; `tests/JsonContract.Tests.ps1` fails when a document has a field that this page does not name.

## Rules

- Standard output is **one** JSON document, ASCII only (every non-ASCII character is `\uXXXX`), with camelCase keys. Nothing else is printed around it; warnings go inside it.
- Every document has `schemaVersion` (`1`), `command`, `toolVersion` and `warnings`. A field is never removed or renamed within a `schemaVersion`; new fields can appear, so readers ignore what they do not know.
- The exit code completes the document: `0` everything done, `2` not everything was done (read the document), `1` nothing was done or it could not start (the document is usually an `error`).
- An unknown or misspelled parameter, or a value without its parameter name (parameters are never positional), ends in an `error` document (exit `1`) and nothing is done. A value PowerShell cannot take (a `-Lang` other than `es`/`en`, an `-IdleSeconds` that is not a number) is rejected by PowerShell itself: no JSON document, exit code `1`.
- `-Json` never asks anything. Applying needs `-Yes` (or `-WhatIf` to only see the plan); without either, a plan with changes ends in an `error` (exit `1`), `-Json` alone included. Without a command and without `-Json` the tool opens the menu, which has no JSON output.
- Texts meant for people (`title`, `why`, `description`, `message`, `detail`, `error`, `text`, `warnings`) follow `-Lang`; ids, statuses, reasons and `evidence` never change with the language.
- `-ResultId <id>` (with `-Json` only, any command) also writes the document to `out\<id>.json` under the state folder: `%ProgramData%\windows-tuneup` when elevated (only administrators can write there; users can read; the folder and `out` are checked like the rest of the machine state, and one that other accounts can change, or that is a junction, is refused, so no one else can put a file or a link there), `%LOCALAPPDATA%\windows-tuneup` otherwise (`-StateRoot` in tests and development, as for the runs). It is for a program that starts the tool elevated with UAC and cannot read its standard output; that program reads the result back with `-ReadResult` (below), never by opening the file itself. The id is 8 to 64 characters among `A-Z`, `a-z`, `0-9` and `-`, and starts with a letter or a digit (a GUID fits; one that starts with `-` would be taken by PowerShell as a parameter name); the caller never gives a path. An invalid id or an id whose file already exists (an existing file or hard link is never replaced) ends in an `error` document on the standard output; `-ResultId` without `-Json` ends in the same refusal as plain text, with no document. Either way: exit `1`, nothing done, no file written. The file is created, empty, before the command runs and gets, when it ends, the same document as the standard output, `error` documents included (an unknown parameter too, when the id is valid). In the machine folder, which users can read, the profile folder and the account name in a path are hidden in the free texts that can carry one (`warnings`, `message`, `details`, `runDir`, `path`, `error`, `detail`, `output`, `repairedFiles`, `unrepairedFiles`) as `%USERPROFILE%` and `%USERNAME%`, like `result.json` does; ids, statuses, reasons and titles are as on the standard output, which is never hidden. `manual` keeps its paths: it is a command to run, and the run folder already holds those values. `out` keeps the 50 newest results (only files named like a result id count: folders and links are left alone, and a result that cannot be removed is a warning in the document). An empty file, or one that is not a single JSON document, means the command is still running or was stopped before it could write (window closed, process killed): read it as no document and check with `-Status` (`-ReadResult` says `result-incomplete`). No file after the process ended means the document could not be written (the exit code is then `2` if it would have been `0`) or Ctrl+C stopped PowerShell itself (see `apply`).
- `-ReadResult <id>` prints the document that a run with `-ResultId <id>` saved, after checking who could have written it (see "Reading a result").

| Command line | `command` of the document |
|---|---|
| `-WhatIf -Json`, or nothing to apply | `plan` |
| `-Yes -Json` | `apply` (or `plan` when there was nothing to apply) |
| `-Status -Json` | `status` |
| `-Status -Reapply -WhatIf -Json` or `-Status -Reapply -Yes -Json` | `plan` or `apply`, with `source` = `reapply` (a `plan` with no items when nothing drifted; without `-WhatIf` or `-Yes`, something to apply ends in an `error`) |
| `-Undo <id\|last> [-Tweak <id>] -Json` | `undo` |
| `-Health [-Repair] -Json` | `health` |
| `-Measure [-Compare <id\|last>] [-IdleSeconds <n>] -Json` | `measure` |
| `-List -Json` | `list` |
| `-Suggest -Json` | `suggest` |
| `-ReadResult <id> [-Json]` | the document saved by `-ResultId`, unchanged (any `command`), or `error` |
| any refusal or failure before the work | `error` |

## Reading a result

`-ReadResult <id>` is how a program that started the tool elevated gets the document: it runs the installed `tuneup.ps1` again, **without** elevation, with `-ReadResult <id> -Json`, and never opens `out\<id>.json` itself. The reason: a standard user can create `%ProgramData%\windows-tuneup` (or its `out` folder) before the first elevated run; that run then refuses to write there (its `error` goes only to the elevated window, which the caller does not see) and the file found by its path would be whatever that user put there.

- It excludes every other command (`-Status`, `-Undo`, `-Health`, `-Measure`, `-List`, `-Suggest`), the options of applying, and `-ResultId`: `error` (`Invalid parameter combination`), exit `1`. Elevated or not, it needs no administrator. It reads no catalog, profiles, state or environment.
- The id follows the rule of `-ResultId`; another id is an `error` (exit `1`, no `reason`).
- Where: first `out\<id>.json` of the machine folder (`CommonApplicationData`, that is `%ProgramData%\windows-tuneup`), only if the folder that holds it, the state folder, `out` and the file pass the checks of the machine state (owned by Administrators, SYSTEM or TrustedInstaller; no write right for anyone else; not a junction or a link; the file has one name only, no hard link). Then, only when the caller is not elevated, `out\<id>.json` of `%LOCALAPPDATA%\windows-tuneup`, where unelevated runs write. With `-StateRoot` (tests and development) only that folder, without checks.
- Success: the stored document exactly as it was written (ASCII JSON; in the machine folder the profile folder and the account name are hidden as described for `-ResultId`), with or without `-Json`, and exit `0` whatever the document says. The exit code of the run itself is the one of the process that ran it (`Start-Process -PassThru`); its `command` says what it is, an `error` included. The warnings of the read itself are not added.
- Otherwise an `error` document (with `-Json`; plain text without it) whose `reason` is one of these, exit `1`, and nothing of the file is printed:

| `reason` | Meaning | What to do |
|---|---|---|
| `result-missing` | No result with that id in any folder it reads. | If the elevated process ended with exit `1`, it refused before it could write (an invalid or used id, an untrusted state folder, a tool that did not start): run the same command in a PowerShell opened as administrator to see the message. |
| `result-incomplete` | The file is empty, held open by the run that writes it, or not a single JSON object. | The command is still running, or it was stopped before it wrote (window closed, process killed): check with `-Status`. |
| `result-untrusted` | The file, `out`, the state folder or the folder that holds it fails the checks; also when the result is not there and the state folder fails them (the reason an elevated run could not write). | Do not read the file by other means and do not retry: the folder named in the message has to be deleted by an administrator. |

## `shared`

Fields that several documents carry.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | number | `1`. |
| `command` | string | Which document this is (see the table above). |
| `toolVersion` | string | Version of windows-tuneup that wrote it (`major.minor.patch`). |
| `warnings` | string[] | Warnings raised while running (untrusted state files ignored, action scripts that did not load, `-StateRoot` or `-ActionsPath` used while elevated...). |
| `environment.build` | number | Windows build (`CurrentBuild`). |
| `environment.ubr` | number | Update build revision. |
| `environment.family` | string | `10` or `11`. |
| `environment.edition` | string | `Home`, `Pro`, `Enterprise`, `Education`, `Server` or `Unknown`. `Server` and `Unknown` are refused with an `error` unless `-Force`; a Server then plans as `Enterprise` and the document says `Enterprise`. |
| `environment.isServer` | boolean | Windows Server. |
| `environment.isManaged` | boolean | Joined to a domain or enrolled in MDM (Intune): policies are skipped. |
| `environment.isAdmin` | boolean | The process is elevated. |
| `environment.hasBattery` | boolean | A battery on a portable chassis. |
| `environment.pendingReboot` | boolean | Windows has a restart pending. |
| `preflight[].id` | string | A warning before applying (none stops the run): `pending-reboot`, `low-disk` (less than 2 GB free on the system drive), `restore-disabled` (System Restore off on the system drive), `restore-blocked` (off by policy), `managed-device`, `untrusted-location` (elevated, with the program or its `engine`, `catalog`, `profiles`, `actions` or `i18n` folders in a place that non-elevated processes can change; the message shows the folder with the profile folder written `%USERPROFILE%`). Only when the plan changes something; `restore-*` only for system changes made elevated, and a System Restore turned on from the offer (asked after the apply is confirmed) takes `restore-disabled` out of the apply document. |
| `preflight[].message` | string | The warning for people. |

## `plan`

| Field | Type | Meaning |
|---|---|---|
| `source` | string | `profiles` (profiles and lists) or `reapply` (`-Status -Reapply`). |
| `environment` | object | See `shared`. |
| `requiresAdmin` | boolean | The plan has system changes, or policies under `HKCU`: applying needs elevation. |
| `preflight` | object[] | Warnings before applying (see `shared`); empty when nothing would change. |
| `items` | object[] | One per tweak considered, in order. |
| `items[].id` | string | Tweak id. |
| `items[].title` | string | Tweak title in the language of the run. |
| `items[].why` | string | What the tweak does and why, in the language of the run. |
| `items[].risk` | string | `low`, `medium` or `high`. |
| `items[].ask` | boolean | The tweak asks before it is applied: a profile alone leaves it out (`needs-confirmation`); `-Include <id>` asks for it by name. |
| `items[].scope` | string | `user` or `machine`. |
| `items[].type` | string | Kind of change: `registry`, `service`, `task`, `appx`, `capability`, `feature`, `powercfg` or `action`. |
| `items[].needsAdmin` | boolean | Applying it needs elevation: a machine change, or a policy under `HKCU`. |
| `items[].action` | string | `apply` or `skip`. |
| `items[].reason` | string or null | Why it is skipped: `excluded`, `kept-by-profile`, `incompatible`, `not-applicable-hardware`, `managed-device`, `session-user`, `already-applied`, `not-present`, `state-unreadable`, `high-risk-not-requested`, `needs-confirmation`, `declined` (menu only). An item to apply can carry `unverified-needs-admin` (its state is checked when applied). |
| `items[].rebootRequired` | boolean | The tweak needs a restart once applied. |
| `items[].signOutRequired` | boolean | The tweak shows after signing in again. |
| `items[].requires` | string[] | Hardware it is meant for: `battery`, `no-battery`; empty for any. |
| `summary` | object | Counts. |
| `summary.apply` | number | Items to apply. |
| `summary.skip` | number | Items skipped. |

## `apply`

Also saved, without `warnings` and `toolVersion`, as `result.json` in the run folder. In the saved copy the profile folder is written `%USERPROFILE%` and the account name `%USERNAME%` (`runDir` included, so the file can be shared); the standard output keeps the real `runDir`.

| Field | Type | Meaning |
|---|---|---|
| `source` | string | `profiles` or `reapply`. |
| `runId` | string | Id of the run (`yyyyMMdd-HHmmss`, maybe with `-NN`): what `-Undo` takes. |
| `runDir` | string | Folder of the run. |
| `finishedAt` | string | Local time, ISO 8601 without zone. |
| `environment` | object | See `shared`. |
| `preflight` | object[] | Warnings shown before applying (see `shared`). |
| `restorePoint` | string | `created`, `skipped-recent` (Windows makes one every 24 hours), `failed`, `unavailable`, `not-needed` (only user changes). |
| `rebootRequired` | boolean | Some applied or partial tweak needs a restart. |
| `signOutRequired` | boolean | Some applied or partial tweak shows after signing in again. |
| `interrupted` | boolean | Ctrl+C stopped the run: the tweaks after it were not applied. |
| `summary` | object | Counts. |
| `summary.applied` | number | Applied and checked. |
| `summary.partial` | number | Changed something but could not finish (`detail` says what). |
| `summary.notApplied` | number | Applied, but the check says it is not in place (Windows or a policy reverted it). |
| `summary.failed` | number | Failed (`error` says why). |
| `summary.skipped` | number | Skipped by the plan. |
| `summary.refused` | number | Left alone by the tweak itself, changing nothing (`reason` says why). |
| `summary.journalErrors` | number | Not applied because their backup could not be written. |
| `summary.interrupted` | number | Not applied because Ctrl+C stopped the run. |
| `results` | object[] | One per item of the plan, in order. |
| `results[].id` | string | Tweak id. |
| `results[].title` | string | Tweak title. |
| `results[].status` | string | `applied`, `partial`, `not-applied`, `failed`, `skipped`. |
| `results[].reason` | string or null | For `skipped`: the reason of the plan, `journal-error`, `interrupted`, `aborted` (the run stopped because of an error that was not Ctrl+C), or the reason of a refusal (`onedrive-known-folders`, `onedrive-online-only-files`, `onedrive-scan-incomplete`, `onedrive-other-accounts`, `onedrive-session-user`, `session-user`). |
| `results[].error` | string or null | What failed. |
| `results[].detail` | string or null | Explanation of a partial result or a refusal. |
| `results[].rebootRequired` | boolean | This tweak needs a restart. |
| `results[].signOutRequired` | boolean | This tweak shows after signing in again. |
| `results[].refused` | boolean | The tweak refused to change anything. |

Exit code: `0` everything applied (refusals and skips included); `2` something partial, not applied, failed, interrupted after a change, or a backup or `result.json` not saved; `1` nothing changed (no backup could be written, or Ctrl+C before the first tweak).

Ctrl+C with `-Json`: when it reaches the console as a key (between two tweaks, with a console of its own) the usual `apply` document comes out, with `interrupted` true and the exit code above. When it stops PowerShell itself (a native program such as DISM or winget was running) nothing is written to the standard output: the exit code is `2` and the document is the `result.json` of the newest folder under `runs` of the state folder (the tweak that was cut is `failed`, with its journal entry, so `-Undo last` restores it; the ones not reached are `interrupted`). A caller must read an empty output with exit code `2` as "look at `result.json`". A failure that is not Ctrl+C (an unexpected error in the middle of the run) leaves the same `result.json`, with the tweaks not reached as `aborted`, and the standard output has an `error` document with exit code `1`.

## `status`

| Field | Type | Meaning |
|---|---|---|
| `items` | object[] | One per tweak that a pending run applied, from the latest run that touched it. |
| `items[].id` | string | Tweak id. |
| `items[].title` | string | Tweak title. |
| `items[].status` | string | `ok` (still applied), `drift` (Windows reverted it: `-Status -Reapply` applies it again), `not-present`, `unknown` (could not be read), `needs-admin` (only readable elevated). |
| `items[].runId` | string | Run that applied it. |

## `undo`

| Field | Type | Meaning |
|---|---|---|
| `runId` | string | The run undone. |
| `rebootRequired` | boolean | Some restore asked for a restart. |
| `signOutRequired` | boolean | Some restored tweak shows after signing in again. |
| `results` | object[] | One per tweak, last applied first. |
| `results[].id` | string | Tweak id. |
| `results[].title` | string | Tweak title. |
| `results[].status` | string | `restored`, `failed`, `skipped`. |
| `results[].reason` | string or null | `already-undone`, `other-user` (it belongs to another account, which can undo it), or a note of the restore: `reinstalled`, `installed-for-other-users`, `not-reprovisioned`, `reinstalled-onedrive`. |
| `results[].error` | string or null | Why the restore failed. |
| `results[].detail` | string or null | What the restore could not give back. |
| `results[].rebootRequired` | boolean | This restore needs a restart. |
| `results[].signOutRequired` | boolean | This restored tweak shows after signing in again. |
| `results[].manual` | string[] | For `failed`: PowerShell command lines that restore it by hand (`New-ItemProperty`, `Remove-ItemProperty`, `Set-Service`, `Enable-ScheduledTask`, `Add-WindowsCapability`, `Enable-WindowsOptionalFeature`, `powercfg.exe`, `winget`), or a sentence for an action; empty otherwise, and also empty when the lines cannot be built. |
| `summary` | object | Counts. |
| `summary.restored` | number | Restored. |
| `summary.failed` | number | Failed: the run stays pending and `-Undo last` retries them. |
| `summary.skipped` | number | Skipped. |

Exit code: `0` everything restored, `2` some left, `1` nothing restored.

## `measure`

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Id of the new measurement (what `-Compare` takes). |
| `path` | string | Where it was saved. |
| `measurement` | object | What was measured. |
| `measurement.schemaVersion` | number | `1`. |
| `measurement.id` | string | Same as `id`. |
| `measurement.takenAt` | string | Local time, ISO 8601 without zone. |
| `measurement.idleSeconds` | number | Seconds waited idle before measuring. |
| `measurement.environment` | object | See `shared`. |
| `measurement.metrics` | object | The values; `null` when one could not be read. |
| `measurement.metrics.ramInUseMB` | number | RAM in use (MB). |
| `measurement.metrics.processCount` | number | Processes. |
| `measurement.metrics.runningServices` | number | Running services. |
| `measurement.metrics.enabledTasks` | number | Enabled scheduled tasks. |
| `measurement.metrics.systemDriveFreeGB` | number | Free space on the system drive (GB). |
| `measurement.metrics.bootDurationMs` | number or null | Last boot duration (ms), event 100 of Diagnostics-Performance. |
| `measurement.metrics.uptimeMinutes` | number | Minutes since boot. |
| `measurement.notes` | object | Why a metric is `null`, by metric name. |
| `measurement.notes.bootDurationMs` | string | `needs-admin`, `no-event`, `not-recorded-yet`, `unreadable`, `unavailable`. |
| `comparison` | object or null | With `-Compare`; `null` otherwise. |
| `comparison.againstId` | string | The earlier measurement. |
| `comparison.items` | object[] | One per metric. |
| `comparison.items[].metric` | string | Metric name. |
| `comparison.items[].before` | number or null | Earlier value. |
| `comparison.items[].after` | number or null | New value. |
| `comparison.items[].delta` | number or null | `after - before`. |
| `comparison.items[].beforeNote` | string or null | Why `before` is missing. |
| `comparison.items[].afterNote` | string or null | Why `after` is missing. |

## `health`

| Field | Type | Meaning |
|---|---|---|
| `startedAt` | string | Local time of the start. |
| `finishedAt` | string | Local time of the end. |
| `repairRequested` | boolean | `-Repair` was given (or the menu repaired after a check). |
| `repairRan` | boolean | A repair ran (only when the check found damage it can repair). |
| `before` | object | The check. |
| `before.sfc` | object | System File Checker. |
| `before.sfc.status` | string | `clean`, `repaired`, `unrepaired`, `unknown`. |
| `before.sfc.repairedFiles` | string[] | Files it repaired. |
| `before.sfc.unrepairedFiles` | string[] | Files it could not repair. |
| `before.sfc.exitCode` | number | Exit code of sfc (shown, not decisive). |
| `before.sfc.exitCodeHex` | string | The same in hexadecimal. |
| `before.sfc.output` | string or null | Output of sfc when it ended with an error. |
| `before.componentStore` | object | DISM. |
| `before.componentStore.state` | string | `healthy`, `repairable`, `repaired`, `unrepairable`, `unknown`. |
| `before.componentStore.operation` | string or null | Operation named in CBS.log. |
| `before.componentStore.operationResult` | string or null | Its result (`0x0` is success). |
| `before.componentStore.detected` | number or null | Corruptions detected. |
| `before.componentStore.repaired` | number or null | Corruptions repaired. |
| `before.componentStore.exitCode` | number | Exit code of DISM. |
| `before.componentStore.exitCodeHex` | string | The same in hexadecimal. |
| `before.componentStore.output` | string or null | Output of DISM when it ended with an error. |
| `before.corruptComponents` | object[] | Damaged components, grouped. |
| `before.corruptComponents[].name` | string | Component. |
| `before.corruptComponents[].files` | number | Damaged files in it. |
| `after` | object or null | The same fields as `before`, after the repair; `null` without a repair. |
| `recommendation` | string | `none`, `run-repair`, `manual-repair`, `check-logs`. |
| `rebootRecommended` | boolean | Something was repaired. |

Exit code: `0` no problems (`recommendation` = `none`), `2` problems remain or the result could not be confirmed, `1` not elevated.

## `list`

What the catalog and the profiles offer on this machine. Read only, no elevation needed. Exit code `0`, or `1` with an `error` (an unsupported Windows without `-Force`, or a catalog or profiles with errors). The blacklist is not data of the tool: it is `docs/es/blacklist.md` and `docs/en/blacklist.md` of the installed copy.

| Field | Type | Meaning |
|---|---|---|
| `profiles` | object[] | Every profile, `base` first. |
| `profiles[].id` | string | Profile id: what `-Profile` takes. |
| `profiles[].aliases` | string[] | Other names `-Profile` takes (`privacidad`, `juegos`...). |
| `profiles[].title` | string | Title in the language of the run. |
| `profiles[].description` | string | What the profile does, in the language of the run. |
| `profiles[].tweakCount` | number | Tweaks of the profile that suit this machine (the ones not in `incompatible`). |
| `profiles[].needsAdmin` | boolean | Some of those tweaks need elevation. |
| `tweaks` | object[] | Every tweak of the catalog that suits this machine, in catalog order. |
| `tweaks[].id` | string | Tweak id: what `-Include` and `-Exclude` take. |
| `tweaks[].title` | string | Title in the language of the run. |
| `tweaks[].why` | string | What it does and why, in the language of the run. |
| `tweaks[].risk` | string | `low`, `medium` or `high` (`high` is never in a profile: only `-Include` applies it). |
| `tweaks[].ask` | boolean | It asks before it is applied: a profile alone leaves it out; `-Include <id>` asks for it. |
| `tweaks[].type` | string | `registry`, `service`, `task`, `appx`, `capability`, `feature`, `powercfg` or `action`. |
| `tweaks[].scope` | string | `user` or `machine`. |
| `tweaks[].needsAdmin` | boolean | Applying it needs elevation. |
| `tweaks[].rebootRequired` | boolean | It needs a restart once applied. |
| `tweaks[].requires` | string[] | Hardware it is meant for: `battery`, `no-battery`; empty for any. |
| `tweaks[].profiles` | string[] | Ids of the profiles that include it; empty for one that is only applied by name. |
| `incompatible` | object[] | Tweaks that do not suit this machine, with the reason the plan would give. |
| `incompatible[].id` | string | Tweak id. |
| `incompatible[].reason` | string | `incompatible` (Windows version or edition), `not-applicable-hardware` (its `requires` does not match this machine) or `managed-device` (a policy, on a device joined to a domain or enrolled in MDM, where the plan leaves policies alone). |

## `suggest`

What this machine has and the profiles that fit it. Read only, no elevation needed, nothing is sent anywhere. Exit code `0` (`1` with an `error` only for parameters it does not take). It reads no catalog, profiles, actions, state or environment of the tool, so `-CatalogPath`, `-ProfilesPath`, `-ActionsPath` and `-StateRoot` do not change it (`-StateRoot` only places the `-ResultId` file), and a broken system query cannot turn it into an `error`. A source that cannot be read (a detector that fails) leaves out what it would have found and adds a warning; the document is still written. On a Windows the tool does not support (Server, a build older than 19041 or an edition it does not know) a warning says that the profiles would need `-Force`: it is advice only, the document is the same and the exit code is still `0`; a Windows whose version cannot be read gives no warning.

| Field | Type | Meaning |
|---|---|---|
| `signals` | object[] | Always six, in this order: `dev`, `gaming`, `laptop`, `work`, `legacy`, `managed`. |
| `signals[].id` | string | `dev`: Visual Studio, Visual Studio Code, a JetBrains IDE, Android Studio, Git, Node.js, Python, a JDK or WSL installed. `gaming`: Steam, Epic Games Launcher, EA app, or Xbox Gaming Services (the Xbox app installs it to play Game Pass; the Xbox app and the Game Bar that come with Windows do not count). `laptop`: a battery on a portable chassis. `work`: joined to a domain or to Entra ID, or enrolled in MDM. `legacy`: less than 8 GB of RAM (the installed modules; when they cannot be read, what Windows reports rounded to the nearest GB, because it reports a little less than what is installed) or a system disk that is a hard disk. `managed`: joined to a domain or enrolled in MDM, the same rule as `environment.isManaged`; it suggests no profile, it is there to warn before changing anything. |
| `signals[].detected` | boolean | Something was found. |
| `signals[].evidence` | string[] | What was found. `battery`, `domain`, `Entra ID`, `MDM`, `HDD` and `RAM <n> GB` (`<n>` a whole number) are stable tokens: they never change with the language (the text for people translates them). Anything else is a product name: `Visual Studio`, `Visual Studio Code`, `JetBrains`, `Android Studio`, `Git`, `Node.js`, `Python`, `JDK`, `WSL`, `Steam`, `Epic Games Launcher`, `EA app` or `Xbox Gaming Services`. Never a path, the display name of an installer or the account. |
| `suggestions` | object[] | Profiles to propose: `base` first (always, with no signals), then one per detected signal except `managed`, in the order of `signals`. |
| `suggestions[].profile` | string | Profile id. |
| `suggestions[].signals` | string[] | Ids of the signals behind it. |
| `questions` | object[] | What only the user can decide: `privacy` and `lite` are never suggested. |
| `questions[].id` | string | The profile it asks about: `privacy` or `lite`. |
| `questions[].text` | string | The question, in the language of the run. |

## `error`

| Field | Type | Meaning |
|---|---|---|
| `message` | string | What went wrong, for people. |
| `details` | string[] | More lines (for example, each problem of the catalog). |
| `reason` | string | Only in the errors of `-ReadResult`: `result-missing`, `result-incomplete` or `result-untrusted` (see "Reading a result"). Never changes with the language. |

Exit code: `1`.

## Run folder

Not a document of the standard output, but what a caller reads after a run: `runs\<runId>` under the state folder (`%ProgramData%\windows-tuneup` when elevated, `%LOCALAPPDATA%\windows-tuneup` otherwise). Every `.json` file is UTF-8.

| File | What it holds |
|---|---|
| `run.json` | `schemaVersion`, `toolVersion`, `userSid`, `machine` (the run is in the protected machine folder), `createdAt`. |
| `plan.json` | The plan that was confirmed: an array with the fields of `items[]` of `plan`. |
| `snapshot.jsonl` | The journal: one JSON line per tweak with its `id`, the tweak itself and the state before the change, written before each change. `-Undo` restores from it. |
| `result.json` | The `apply` document (see `apply`). |
| `transcript.log` | What was shown to people, without the account name; each `-Undo` adds its own section. |
| `undone.json`, `undone-tweaks.txt` | The run was undone (`undoneAt` and the `results` of the undo), or the tweaks of it already restored one by one. |
