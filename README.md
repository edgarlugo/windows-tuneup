# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> **En desarrollo: el catálogo todavía es de ejemplo.** El motor está completo (manejadores, deshacer, salud y medición), pero los perfiles `base` y `privacy` traen solo 5 ajustes de muestra. El catálogo real llega en el Plan 3 y el menú interactivo en el Plan 4. No usar todavía en equipos reales.
> **Work in progress: the catalog is still a sample.** The engine is complete (handlers, undo, health and measurement), but the `base` and `privacy` profiles ship only 5 sample tweaks. The real catalog comes in Plan 3 and the interactive menu in Plan 4. Do not use on real machines yet.

## Requisitos / Requirements

- Windows 10 u 11 (build 19041 o posterior) con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1. Windows Server y builds anteriores se rechazan salvo con `-Force`.
- Windows 10 or 11 (build 19041 or later) with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1. Windows Server and older builds are refused unless `-Force` is given.
- Los ajustes de sistema necesitan PowerShell como administrador. Sin elevar, un plan que contenga cualquier cambio de sistema se rechaza completo (no se aplica nada): usar `-Exclude` para dejar fuera esos ajustes o abrir PowerShell como administrador. El perfil `base` se aplica siempre y incluye un ajuste de servicio, así que aplicar cualquier perfil exige administrador (o `-Exclude services.retail-demo`). Solo los ajustes de registro de usuario (`HKCU`) se aplican sin elevar.
- System-wide tweaks need PowerShell as administrator. Without elevation, a plan that contains any system-level change is refused entirely (nothing is applied): use `-Exclude` to leave those tweaks out or open PowerShell as administrator. The `base` profile is always applied and includes a service tweak, so applying any profile requires administrator (or `-Exclude services.retail-demo`). Only user registry tweaks (`HKCU`) apply without elevation.
- `-Health` necesita administrador. `-Measure` no, pero sin administrador no puede leer la duración del arranque. Deshacer la quita de una app de la Store usa `winget` (App Installer).
- `-Health` needs administrator. `-Measure` does not, but without administrator it cannot read the boot duration. Undoing the removal of a Store app uses `winget` (App Installer).
- Ejecutar `windows-tuneup` desde una carpeta donde solo escriban administradores (por ejemplo bajo `Program Files`): quien pueda modificar `actions/` o `engine/` ejecuta código con los permisos de quien aplica los ajustes. La revisión de las acciones (solo se leen definiciones de funciones, sin ejecutar nada al cargar) es defensa en profundidad, no sustituye ese permiso de carpeta.
- Run `windows-tuneup` from a folder that only administrators can write to (for example under `Program Files`): anyone who can change `actions/` or `engine/` runs code with the rights of whoever applies the tweaks. The check of action scripts (only function definitions are read, nothing runs while loading) is defense in depth, not a substitute for that folder permission.

## Uso / Usage

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base -WhatIf   # ver el plan / show the plan
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base,privacy   # aplicar (pregunta antes) / apply (asks first)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Status                 # estado / status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Undo last              # deshacer / undo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Health                 # SFC + DISM (administrador / administrator)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Health -Repair         # + DISM /RestoreHealth si hace falta / if needed
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Measure -IdleSeconds 120                 # medir / measure
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Measure -IdleSeconds 120 -Compare last   # comparar / compare
```

`-ExecutionPolicy Bypass` solo afecta a ese proceso y permite ejecutar el script aunque la política de PowerShell sea `Restricted`; no cambia la configuración del equipo.
`-ExecutionPolicy Bypass` only affects that process and lets the script run even if the PowerShell policy is `Restricted`; it does not change the machine configuration.

### Parámetros / Parameters

| Parámetro / Parameter | Qué hace / What it does |
|---|---|
| `-Profile <lista>` | Perfiles a aplicar, separados por comas. `base` se aplica siempre. Un perfil también se llama por su alias (`privacidad`). / Profiles to apply, comma separated. `base` is always applied. A profile can also be named by its alias (`privacidad`). |
| `-Include <ids>` / `-Exclude <ids>` | Ajustes extra o excluidos. Solo con `-Include` se aplican los de riesgo alto o que piden confirmación. / Extra or excluded tweaks. Only `-Include` applies tweaks of high risk or that ask for confirmation. |
| `-WhatIf` | Muestra el plan y no cambia nada. / Shows the plan and changes nothing. |
| `-Yes` | Aplica sin preguntar. / Applies without asking. |
| `-Status` | Qué sigue aplicado y qué revirtió Windows. / What is still applied and what Windows reverted. |
| `-Undo <id\|last> [-Tweak <id>]` | Deshace una corrida o solo un ajuste de ella. / Undoes a run, or just one tweak of it. |
| `-Health [-Repair]` | SFC + DISM `/ScanHealth`; con `-Repair`, DISM `/RestoreHealth` y SFC otra vez si hace falta. Administrador. / SFC + DISM `/ScanHealth`; with `-Repair`, DISM `/RestoreHealth` and SFC again if needed. Administrator. |
| `-Measure [-Compare <id\|last>] [-IdleSeconds <n>]` | Guarda una medición; `-Compare` la compara con una anterior; `-IdleSeconds` (0 a 3600) espera antes de medir. / Saves a measurement; `-Compare` compares it with an earlier one; `-IdleSeconds` (0 to 3600) waits before measuring. |
| `-Json` | Salida como un documento JSON (ver abajo). / Output as one JSON document (see below). |
| `-Lang es\|en` | Idioma de los mensajes. / Language of the messages. |
| `-Force` | Permite Windows Server o builds no soportados. / Allows Windows Server or unsupported builds. |
| `-StateRoot`, `-ActionsPath`, `-CatalogPath`, `-ProfilesPath` | Solo para pruebas y desarrollo (ver más abajo). / For testing and development only (see below). |

`-Status`, `-Undo`, `-Health` y `-Measure` se excluyen entre sí y no se combinan con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` ni `-Yes`. `-Tweak` exige `-Undo`, `-Repair` exige `-Health`, y `-Compare` e `-IdleSeconds` exigen `-Measure`. Una combinación inválida termina con código 1 antes de leer nada.
`-Status`, `-Undo`, `-Health` and `-Measure` exclude each other and cannot be combined with `-Profile`, `-Include`, `-Exclude`, `-WhatIf` or `-Yes`. `-Tweak` requires `-Undo`, `-Repair` requires `-Health`, and `-Compare` and `-IdleSeconds` require `-Measure`. An invalid combination ends with code 1 before anything is read.

## Tipos de ajuste y cómo se deshacen / Tweak types and how they are undone

| Tipo / Type | Qué toca / What it touches | Deshacer / Undo |
|---|---|---|
| `registry` | Un valor de registro. / A registry value. | Exacto: restaura el valor o borra la entrada si no existía. / Exact: restores the value, or deletes the entry if it did not exist. |
| `service` | Tipo de arranque y estado de un servicio. / Start type and state of a service. | Exacto. Si el servicio quedó deshabilitado pero no se pudo detener, el ajuste es parcial. / Exact. If the service was disabled but could not be stopped, the tweak is partial. |
| `task` | Una tarea programada. / A scheduled task. | Exacto: habilitada o deshabilitada como estaba. / Exact: enabled or disabled as it was. |
| `appx` | Una app de la Store, para todos los usuarios y el aprovisionamiento. / A Store app, for all users plus provisioning. | **Reinstala**, no restaura: ver abajo. / **Reinstalls**, it does not restore: see below. |
| `capability` | Una capacidad de Windows. / A Windows capability. | La vuelve a agregar; necesita Windows Update o un origen de características a petición. / Adds it again; needs Windows Update or a features-on-demand source. |
| `feature` | Una característica opcional de Windows (DISM). / An optional Windows feature (DISM). | Exacto para características hoja; puede pedir reinicio. / Exact for leaf features; may ask for a restart. |
| `powercfg` | El plan de energía activo, o un valor de un plan (CA y CC). / The active power scheme, or one value of a scheme (AC and DC). | El mismo valor efectivo (si regía el predeterminado, queda escrito como valor propio del plan). / The same effective value (if the default applied, it is written back as the scheme's own value). |
| `action` | Un script de `actions/` con las funciones `Get`, `Test`, `Set` y `Restore`. / A script in `actions/` with `Get`, `Test`, `Set` and `Restore` functions. | Lo que implemente su función `Restore`. / Whatever its `Restore` function implements. |

- **Mayúsculas en el catálogo:** la validación distingue mayúsculas y minúsculas en todos los tipos: `scope`, `type`, el tipo de valor de registro (`DWord`, no `dword`), el tipo de arranque de un servicio (`Disabled`), el estado de una tarea, capacidad o característica y los prefijos de ruta (`HKCU:`). Un valor con otra capitalización no pasa la validación.
  **Case in the catalog:** validation is case-sensitive for every type: `scope`, `type`, the registry value kind (`DWord`, not `dword`), a service start type (`Disabled`), the state of a task, capability or feature, and path prefixes (`HKCU:`). A value with other casing does not pass validation.
- **Apps de la Store (`appx`):** quitar una app la quita para todos los usuarios y la desaprovisiona. Deshacer la reinstala desde la Store con `winget` **solo para la cuenta que ejecuta el deshacer** (si elevas con otra cuenta, la app queda en esa cuenta, no en la tuya); no puede provisionarla de nuevo para usuarios nuevos ni reponerla a otros usuarios, y su versión puede cambiar. Sin `winget` el deshacer falla y la corrida queda pendiente para reintentar. El catálogo no debe incluir paquetes `NonRemovable` ni de framework (`Microsoft.NET.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`): Windows los protege y otras apps dependen de ellos.
  **Store apps (`appx`):** removing an app removes it for all users and deprovisions it. Undo reinstalls it from the Store with `winget` **only for the account that runs the undo** (if you elevate with a different account, the app lands in that account, not yours); it cannot provision it again for new users or restore it for other users, and its version may change. Without `winget` the undo fails and the run stays pending to retry. The catalog must not include `NonRemovable` or framework packages (`Microsoft.NET.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`): Windows protects them and other apps depend on them.
- **Capacidades y características (`capability`, `feature`):** solo se tocan las que Windows informa claramente como instaladas o ausentes (habilitadas o deshabilitadas); en cualquier otro estado (por ejemplo `PartiallyInstalled`) se informa `not-present` y no se tocan. Deshabilitar una característica sin `-All` también deshabilita las que dependen de ella y deshacer solo vuelve a habilitar esa: el catálogo no debe incluir características padre, solo hojas.
  **Capabilities and features (`capability`, `feature`):** only those that Windows clearly reports as installed or absent (enabled or disabled) are touched; in any other state (for example `PartiallyInstalled`) they are reported as `not-present` and left alone. Disabling a feature without `-All` also disables the features that depend on it and undo only enables that one again: the catalog must not include parent features, only leaf ones.
- **Energía (`powercfg`):** el estado se lee del registro (valor del plan, luego el predeterminado aprovisionado `Prov*SettingIndex`, luego el simple), igual que `powercfg /q`. Limitación conocida: los valores impuestos por directiva de grupo (`HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings`) no se detectan.
  **Power (`powercfg`):** the state is read from the registry (the scheme's own value, then the provisioned default `Prov*SettingIndex`, then the plain one), the same as `powercfg /q`. Known limitation: values enforced by group policy (`HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings`) are not detected.
- **Acciones (`action`):** el cargador analiza los scripts de `actions/` sin ejecutarlos y solo acepta definiciones de funciones con nombres del contrato. El repositorio todavía no trae acciones reales (llegan con el catálogo, Plan 3). Un script que no se pueda cargar no rompe el resto: se informa como advertencia y solo falla la validación de los ajustes que lo usan (`-Status`, `-Undo`, `-Health` y `-Measure` siguen funcionando).
  **Actions (`action`):** the loader parses the scripts in `actions/` without running them and only accepts function definitions with contract names. The repository ships no real actions yet (they arrive with the catalog, Plan 3). A script that cannot be loaded does not break the rest: it is reported as a warning and only the validation of the tweaks that use it fails (`-Status`, `-Undo`, `-Health` and `-Measure` keep working).
- `appx`, `capability` y `feature` no se pueden leer sin administrador: sin elevar, el plan los muestra como cambios por aplicar con `reason` `unverified-needs-admin` (en `-Json` el `reason` de un elemento que se aplica puede por eso no ser nulo) y `-Status` los informa como `needs-admin`. Todos los tipos nuevos (`appx`, `capability`, `feature`, `powercfg`, `action`) son de sistema: exigen administrador y su corrida va a la carpeta protegida.
  `appx`, `capability` and `feature` cannot be read without administrator rights: when not elevated, the plan shows them as changes to apply with `reason` `unverified-needs-admin` (so in `-Json` the `reason` of an item that will be applied may be non-null) and `-Status` reports them as `needs-admin`. All the newer types (`appx`, `capability`, `feature`, `powercfg`, `action`) are system-level: they require administrator and their run goes to the protected folder.

## Qué hace hoy / What works today

- `-WhatIf` muestra el plan con el motivo de cada omisión (ya aplicado, versión o edición no compatible, equipo administrado...). Sin elevar, lo que solo se puede leer como administrador aparece como "se comprueba al aplicar". No cambia nada.
  `-WhatIf` shows the plan with the reason for every skipped tweak (already applied, unsupported version or edition, managed machine...). Without elevation, what can only be read as administrator shows as "checked when applied". It changes nothing.
- Antes de tocar un ajuste guarda su valor anterior. Con administrador la corrida queda en `%ProgramData%\windows-tuneup\runs\` (carpeta protegida); sin elevar, en `%LOCALAPPDATA%\windows-tuneup\runs\` (solo ajustes de usuario). Si el plan tiene cambios de sistema también intenta crear un punto de restauración.
  Before touching a tweak it saves the previous value. Elevated, the run goes to `%ProgramData%\windows-tuneup\runs\` (hardened folder); otherwise to `%LOCALAPPDATA%\windows-tuneup\runs\` (user-level tweaks only). If the plan has system changes it also tries to create a restore point.
- Un ajuste que cambió algo pero no pudo terminar se informa como parcial, con la explicación. Si Windows o una directiva revierten un ajuste justo después de aplicarlo, queda como "sin efecto".
  A tweak that changed something but could not finish is reported as partial, with the explanation. If Windows or a policy reverts a tweak right after it was applied, it is reported as "no effect".
- `-Undo last` o `-Undo <id> -Tweak <ajuste>` devuelve el valor anterior (ver la tabla de tipos). Una corrida ya deshecha no se deshace dos veces. Cada usuario deshace solo lo suyo. Deshacer una corrida de la carpeta protegida exige administrador.
  `-Undo last` or `-Undo <id> -Tweak <tweak>` restores the previous value (see the type table). A run that was already undone is not undone twice. Each user undoes only their own changes. Undoing a run from the protected folder requires administrator.
- `-Status` muestra qué sigue aplicado (`ok`), qué revirtió Windows (`drift`), qué ya no existe (`not-present`), qué no se pudo leer (`unknown`) y qué necesita administrador para comprobarse (`needs-admin`). `-Status` y `-Undo` no dependen del catálogo: funcionan con lo guardado en la corrida.
  `-Status` shows what is still applied (`ok`), what Windows reverted (`drift`), what no longer exists (`not-present`), what could not be read (`unknown`) and what needs administrator to check (`needs-admin`). `-Status` and `-Undo` do not depend on the catalog: they work from what the run saved.
- `-Health` corre `sfc /scannow` y `DISM /ScanHealth` y resume lo que dejaron en `CBS.log`: archivos reparados o sin reparar, estado del almacén de componentes y componentes dañados agrupados, con una recomendación (`none`, `run-repair`, `manual-repair`, `check-logs`). `-Health -Repair` corre además `DISM /RestoreHealth` y SFC otra vez, solo si hace falta, y muestra antes y después. No hay pregunta interactiva para reparar: se pide con `-Repair`.
  `-Health` runs `sfc /scannow` and `DISM /ScanHealth` and summarizes what they left in `CBS.log`: repaired and unrepaired files, component store state and damaged components grouped, with a recommendation (`none`, `run-repair`, `manual-repair`, `check-logs`). `-Health -Repair` also runs `DISM /RestoreHealth` and SFC again, only when needed, and shows before and after. There is no interactive question to repair: ask for it with `-Repair`.
- `-Measure` guarda RAM en uso, procesos, servicios en ejecución, tareas programadas habilitadas, espacio libre del disco del sistema, duración del último arranque y minutos desde el arranque; `-Compare <id|last>` muestra la diferencia con una medición anterior (se resuelve antes de medir, así `last` nunca es la medición nueva).
  `-Measure` saves RAM in use, processes, running services, enabled scheduled tasks, free space on the system drive, last boot duration and minutes since boot; `-Compare <id|last>` shows the difference from an earlier measurement (it is resolved before measuring, so `last` is never the new measurement).
- Idioma con `-Lang es|en`.
  Language with `-Lang es|en`.

## Cómo medir / How to measure

1. Reiniciar, iniciar sesión y correr `-Measure -IdleSeconds 120`: espera dos minutos en reposo antes de medir. Como administrador también se lee la duración del arranque.
   Restart, sign in and run `-Measure -IdleSeconds 120`: it waits two minutes idle before measuring. As administrator it also reads the boot duration.
2. Aplicar los perfiles, reiniciar y correr `-Measure -IdleSeconds 120 -Compare last`.
   Apply the profiles, restart and run `-Measure -IdleSeconds 120 -Compare last`.

Las mediciones quedan en `measurements\` dentro de la misma carpeta de estado que las corridas (con las mismas reglas de confianza). Compara solo mediciones tomadas con el mismo nivel de elevación: algunos datos (la duración del arranque, y a veces servicios y tareas) cambian si PowerShell está o no como administrador. Si la duración del arranque no se puede leer, queda vacía con el motivo (`needs-admin`, `no-event`, `not-recorded-yet`, `unreadable` o `unavailable`).
Measurements are kept in `measurements\` inside the same state folder as the runs (with the same trust rules). Compare only measurements taken at the same elevation: some values (the boot duration, and sometimes services and tasks) differ when PowerShell is or is not running as administrator. If the boot duration cannot be read, it is left empty with the reason (`needs-admin`, `no-event`, `not-recorded-yet`, `unreadable` or `unavailable`).

## Códigos de salida / Exit codes

| Comando / Command | 0 | 2 | 1 |
|---|---|---|---|
| Aplicar / Apply | Todo hecho (o nada que aplicar). / Everything done (or nothing to apply). | No todo se completó: algún ajuste parcial, fallido o sin efecto, o no se pudo guardar un respaldo o `result.json`; leer el resumen. / Not everything completed: some tweak was partial, failed or had no effect, or a backup or `result.json` could not be saved; read the summary. | Abortado antes de cambiar nada (respuesta negativa, sin administrador, argumentos o catálogo inválidos, ningún respaldo se pudo escribir). / Aborted before changing anything (answered no, not administrator, invalid arguments or catalog, no backup could be written). |
| `-Undo` | Todo restaurado (lo ya deshecho no cuenta). / Everything restored (what was already undone does not count). | Restauración parcial: quedan fallos o ajustes de otro usuario. / Partly restored: failures or another user's tweaks remain. | Nada se restauró, o no se pudo empezar. / Nothing was restored, or it could not start. |
| `-Status` | Siempre. / Always. | | Error al leer. / Read error. |
| `-Health` | Sin problemas (`recommendation` = `none`). / No problems (`recommendation` = `none`). | Quedan problemas o no se pudo confirmar el resultado. / Problems remain or the result could not be confirmed. | Sin administrador. / Not administrator. |
| `-Measure` | Medición guardada. / Measurement saved. | | No pudo medir o guardar, o `-Compare` no encontró la medición. / It could not measure or save, or `-Compare` did not find the measurement. |

Un parámetro desconocido o un `-Lang` fuera de `es`/`en` lo informa PowerShell por la salida de errores, sin documento JSON, con código 1.
An unknown parameter or a `-Lang` other than `es`/`en` is reported by PowerShell on the error stream, without a JSON document, with code 1.

## Salida JSON / JSON output

Con `-Json` la salida estándar es un único documento JSON en ASCII (todo carácter no ASCII va como `\uXXXX`, así la página de códigos de la consola no lo altera), con claves en camelCase. Los avisos no se escriben sueltos: van dentro del documento, en el arreglo `warnings`. Para aplicar sin preguntar usar `-Yes`; con `-Json` y sin `-Yes` un plan con cambios termina con un error en JSON (código 1).
With `-Json` standard output is a single ASCII JSON document (every non-ASCII character is written as `\uXXXX`, so the console code page cannot alter it), with camelCase keys. Warnings are not printed loose: they go inside the document, in the `warnings` array. To apply without asking use `-Yes`; with `-Json` and without `-Yes` a plan with changes ends with a JSON error (code 1).

Todos los documentos llevan `schemaVersion` (hoy `1`), `command` y `warnings`:
Every document carries `schemaVersion` (currently `1`), `command` and `warnings`:

| `command` | Campos principales / Main fields |
|---|---|
| `plan` | `environment`, `requiresAdmin` (hay cambios de sistema / there are system changes), `items` (`id`, `title`, `risk`, `scope`, `action`, `reason`, `rebootRequired`), `summary` (`apply`, `skip`) |
| `apply` | `runId`, `runDir`, `finishedAt`, `environment`, `restorePoint`, `rebootRequired`, `summary` (`applied`, `partial`, `notApplied`, `failed`, `skipped`, `journalErrors`), `results` (`id`, `title`, `status`, `reason`, `error`, `detail`, `rebootRequired`) |
| `status` | `items` (`id`, `title`, `status`, `runId`) |
| `undo` | `runId`, `rebootRequired`, `results` (mismos campos que `apply` / same fields as `apply`), `summary` (`restored`, `failed`, `skipped`) |
| `health` | `startedAt`, `finishedAt`, `repairRequested`, `repairRan`, `before`, `after` (`sfc`, `componentStore`, `corruptComponents`), `recommendation`, `rebootRecommended` |
| `measure` | `id`, `path`, `measurement` (`takenAt`, `idleSeconds`, `environment`, `metrics`, `notes`), `comparison` (`againstId`, `items` con `metric`, `before`, `after`, `delta`; nulo sin `-Compare` / null without `-Compare`) |
| `error` | `message`, `details` |

## Limitaciones conocidas / Known limitations

- El catálogo es de ejemplo (5 ajustes de registro, servicio y tarea); no hay ajustes reales de `appx`, `capability`, `feature`, `powercfg` ni `action` hasta el Plan 3.
  The catalog is a sample (5 registry, service and task tweaks); there are no real `appx`, `capability`, `feature`, `powercfg` or `action` tweaks until Plan 3.
- No hay menú interactivo, y `-Status` solo informa la deriva: no ofrece reaplicar (Plan 4).
  There is no interactive menu, and `-Status` only reports drift: it does not offer to reapply (Plan 4).
- Deshacer una app de la Store es una reinstalación para una cuenta, no una restauración exacta (ver arriba).
  Undoing a Store app is a reinstall for one account, not an exact restore (see above).
- `powercfg` no detecta valores impuestos por directiva de grupo.
  `powercfg` does not detect values enforced by group policy.
- Deshacer ajustes sueltos fuera de orden puede dejar una clave de registro vacía que creó la corrida; solo deshacer en orden inverso la elimina.
  Undoing single tweaks out of order may leave an empty registry key that the run created; only undoing in reverse order removes it.
- Todo queda local: no se envía nada a ningún servidor. Los documentos de ayuda `docs/{es,en}/` y la skill de Claude llegan en planes posteriores.
  Everything stays local: nothing is sent to any server. The `docs/{es,en}/` guides and the Claude skill come in later plans.

## Desarrollo / Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build\test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File build\lint.ps1
```

Las pruebas usan Pester 5 y el lint PSScriptAnalyzer (sobre `tuneup.ps1`, `engine/`, `actions/` y `build/`). Las pruebas no tocan el sistema: Appx, DISM, winget, powercfg, sfc y el visor de eventos se simulan.
Tests use Pester 5 and lint uses PSScriptAnalyzer (over `tuneup.ps1`, `engine/`, `actions/` and `build/`). Tests do not touch the system: Appx, DISM, winget, powercfg, sfc and the event log are mocked.

`-StateRoot`, `-ActionsPath`, `-CatalogPath` y `-ProfilesPath` son solo para pruebas y desarrollo. `-StateRoot <carpeta>` guarda corridas y mediciones en otra carpeta, sin la protección de la carpeta de máquina (no usarlo en un equipo real). `-ActionsPath <carpeta>` carga scripts de acción de otra carpeta, que corren con tus permisos (con administrador si estás elevado): usar solo una carpeta de confianza.
`-StateRoot`, `-ActionsPath`, `-CatalogPath` and `-ProfilesPath` are for testing and development only. `-StateRoot <folder>` keeps runs and measurements in another folder, without the protection of the machine folder (do not use it on a real machine). `-ActionsPath <folder>` loads action scripts from another folder, which run with your rights (administrator when elevated): use only a folder you trust.

Licencia / License: MIT
