# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> **En desarrollo.** El motor y el catálogo (166 ajustes en 8 perfiles) están completos; falta el menú interactivo (Plan 4) y la prueba de extremo a extremo de cada perfil en una máquina virtual antes de la primera release. Revisa siempre el plan con `-WhatIf` antes de aplicar.
> **Work in progress.** The engine and the catalog (166 tweaks in 8 profiles) are complete; the interactive menu (Plan 4) and the end-to-end test of every profile in a virtual machine before the first release are still missing. Always review the plan with `-WhatIf` before applying.

## Perfiles / Profiles

| Perfil / Profile | Alias | Qué hace / What it does | Administrador / Administrator |
|---|---|---|---|
| `base` | | Sin anuncios ni sugerencias, ID de publicidad apagado, extensiones visibles. Siempre se aplica. / No ads or suggestions, advertising ID off, extensions shown. Always applied. | No |
| `dev` | `desarrollo` | Modo desarrollador, rutas largas, archivos ocultos, "Finalizar tarea"; respeta WSL y Hyper-V. / Developer Mode, long paths, hidden files, "End task"; keeps WSL and Hyper-V. | Sí / Yes |
| `gaming` | `juegos` | Modo Juego, sin grabación en segundo plano ni aceleración del mouse, GPU con menos latencia; conserva Xbox. / Game Mode, no background recording or mouse acceleration, lower GPU latency; keeps Xbox. | Sí / Yes |
| `privacy` | `privacidad` | Telemetría al mínimo, historial de actividad, Bing, Copilot, Edge (Recall solo con `-Include`). / Minimum telemetry, activity history, Bing, Copilot, Edge (Recall only with `-Include`). | Sí / Yes |
| `laptop` | `portatil`, `portátil` | Más batería: apps y Edge sin procesos de fondo, sin red en suspensión con batería. / More battery: apps and Edge without background processes, no network in standby on battery. | Sí / Yes |
| `legacy` | `equipo-antiguo`, `antiguo` | Sin transparencia ni animaciones, menos tareas de fondo y apps preinstaladas. / No transparency or animations, fewer background tasks and preinstalled apps. | Sí / Yes |
| `work` | `trabajo` | Solo ajustes de tu usuario, sin directivas; conserva Teams, Outlook y OneDrive. / Only settings of your user, no policies; keeps Teams, Outlook and OneDrive. | No |
| `lite` | `liviano` | Quita lo que LTSC no trae y recorta servicios y tareas; sin tocar Defender, Update ni WinRE. / Removes what LTSC does not ship and trims services and tasks; Defender, Update and WinRE untouched. | Sí / Yes |

Guía de cada perfil / Guide to each profile: [docs/es/profiles.md](docs/es/profiles.md) · [docs/en/profiles.md](docs/en/profiles.md). Catálogo completo / Full catalog: [docs/es/catalog.md](docs/es/catalog.md) · [docs/en/catalog.md](docs/en/catalog.md). Lo que nunca se aplica / What is never applied: [docs/es/blacklist.md](docs/es/blacklist.md) · [docs/en/blacklist.md](docs/en/blacklist.md).

**Liviano frente a LTSC / Lite versus LTSC:** el objetivo es que Liviano quede por debajo de una instalación limpia de Windows 11 LTSC 2024 en RAM, procesos y servicios en reposo. **Todavía no está medido**; el método está en [docs/es/measuring.md](docs/es/measuring.md). / The goal is for Lite to end below a clean Windows 11 LTSC 2024 install in idle RAM, processes and services. **It is not measured yet**; the method is in [docs/en/measuring.md](docs/en/measuring.md).

## Requisitos / Requirements

- Windows 10 u 11 (build 19041 o posterior) con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1. Windows Server y builds anteriores se rechazan salvo con `-Force`.
- Windows 10 or 11 (build 19041 or later) with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1. Windows Server and older builds are refused unless `-Force` is given.
- Los ajustes de sistema y las directivas de tu usuario (las claves `Policies` de `HKCU`, que Windows solo deja leer y escribir a un administrador) necesitan PowerShell como administrador. Sin elevar, un plan que contenga cualquiera de ellos se rechaza completo (no se aplica nada): usar `-Exclude` para dejar fuera esos ajustes o abrir PowerShell como administrador. Los perfiles `base` (siempre aplicado) y `work` solo tienen ajustes de registro de usuario (`HKCU`) que no son directivas y se aplican sin elevar; los demás traen cambios de sistema o directivas.
- System-wide tweaks and policies of your user (the `Policies` keys of `HKCU`, which Windows only lets an administrator read and write) need PowerShell as administrator. Without elevation, a plan that contains any of them is refused entirely (nothing is applied): use `-Exclude` to leave those tweaks out or open PowerShell as administrator. The `base` (always applied) and `work` profiles only hold user registry tweaks (`HKCU`) that are not policies and apply without elevation; the others bring system changes or policies.
- `-Health` necesita administrador. `-Measure` no, pero sin administrador no puede leer la duración del arranque. Deshacer la quita de una app de la Store usa `winget` (App Installer); elevado, solo el `winget.exe` que Windows instaló en `Program Files\WindowsApps`, nunca el alias de la carpeta del usuario.
- `-Health` needs administrator. `-Measure` does not, but without administrator it cannot read the boot duration. Undoing the removal of a Store app uses `winget` (App Installer); elevated, only the `winget.exe` that Windows installed under `Program Files\WindowsApps`, never the alias in the user's folder.
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
| `powercfg` | El plan de energía activo, o un valor de un plan (CA, CC o los dos; el que falta no se toca). / The active power scheme, or one value of a scheme (AC, DC or both; the missing one is left alone). | El mismo valor efectivo (si regía el predeterminado, queda escrito como valor propio del plan). / The same effective value (if the default applied, it is written back as the scheme's own value). |
| `action` | Un script de `actions/` con las funciones `Get`, `Test`, `Set` y `Restore`: `onedrive`, `gaming-hags`, `gaming-windowed-optimizations`. / A script in `actions/` with `Get`, `Test`, `Set` and `Restore` functions: `onedrive`, `gaming-hags`, `gaming-windowed-optimizations`. | Lo que implemente su función `Restore`. / Whatever its `Restore` function implements. |

- **Mayúsculas en el catálogo:** la validación distingue mayúsculas y minúsculas en todos los tipos: `scope`, `type`, el tipo de valor de registro (`DWord`, no `dword`), el tipo de arranque de un servicio (`Disabled`), el estado de una tarea, capacidad o característica y los prefijos de ruta (`HKCU:`). Un valor con otra capitalización no pasa la validación.
  **Case in the catalog:** validation is case-sensitive for every type: `scope`, `type`, the registry value kind (`DWord`, not `dword`), a service start type (`Disabled`), the state of a task, capability or feature, and path prefixes (`HKCU:`). A value with other casing does not pass validation.
- **Ajustes que dependen del equipo:** un ajuste puede declarar `requires` (`battery` o `no-battery`); en un equipo que no corresponde se omite con el motivo `not-applicable-hardware`. Algunos ajustes se notan al volver a iniciar sesión (`signOutRequired`): el resumen lo dice y el JSON de `apply` trae `signOutRequired`.
  **Tweaks that depend on the machine:** a tweak can declare `requires` (`battery` or `no-battery`); on a machine that does not match it is skipped with the reason `not-applicable-hardware`. Some tweaks show after signing in again (`signOutRequired`): the summary says so and the `apply` JSON carries `signOutRequired`.
- **Apps de la Store (`appx`):** quitar una app la quita para todos los usuarios y la desaprovisiona. Deshacer la reinstala desde la Store con `winget` **solo para la cuenta que ejecuta el deshacer**: si la app la perdió otra cuenta, su entrada se omite (`skipped`, motivo `other-user`) y queda pendiente para esa cuenta, en vez de instalarla en la tuya; no puede provisionarla de nuevo para usuarios nuevos ni reponerla a otros usuarios, y su versión puede cambiar. Sin `winget` el deshacer falla y la corrida queda pendiente para reintentar. El catálogo no debe incluir paquetes `NonRemovable` ni de framework (`Microsoft.NET.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`): Windows los protege y otras apps dependen de ellos.
  **Store apps (`appx`):** removing an app removes it for all users and deprovisions it. Undo reinstalls it from the Store with `winget` **only for the account that runs the undo** (if the app was lost by another account, its entry is skipped (`skipped`, reason `other-user`) and stays pending for that account instead of being installed in yours); it cannot provision it again for new users or restore it for other users, and its version may change. Without `winget` the undo fails and the run stays pending to retry. The catalog must not include `NonRemovable` or framework packages (`Microsoft.NET.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`): Windows protects them and other apps depend on them.
- **Capacidades y características (`capability`, `feature`):** solo se tocan las que Windows informa claramente como instaladas o ausentes (habilitadas o deshabilitadas); en cualquier otro estado (por ejemplo `PartiallyInstalled`) se informa `not-present` y no se tocan. Deshabilitar una característica sin `-All` también deshabilita las que dependen de ella y deshacer solo vuelve a habilitar esa: el catálogo no debe incluir características padre, solo hojas.
  **Capabilities and features (`capability`, `feature`):** only those that Windows clearly reports as installed or absent (enabled or disabled) are touched; in any other state (for example `PartiallyInstalled`) they are reported as `not-present` and left alone. Disabling a feature without `-All` also disables the features that depend on it and undo only enables that one again: the catalog must not include parent features, only leaf ones.
- **Energía (`powercfg`):** el estado se lee del registro (valor del plan, luego el predeterminado aprovisionado `Prov*SettingIndex`, luego el simple), igual que `powercfg /q`. Una clave que existe pero no se puede leer es un error, no se pasa a la siguiente fuente. Limitación conocida: los valores impuestos por directiva de grupo (`HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings`) no se detectan.
  **Power (`powercfg`):** the state is read from the registry (the scheme's own value, then the provisioned default `Prov*SettingIndex`, then the plain one), the same as `powercfg /q`. A key that exists but cannot be read is an error; the next source is not used instead. Known limitation: values enforced by group policy (`HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings`) are not detected.
- **Acciones (`action`):** el cargador analiza los scripts de `actions/` sin ejecutarlos y solo acepta definiciones de funciones con nombres del contrato. `onedrive` desinstala OneDrive sin borrar archivos y se niega (sin cambiar nada) si Escritorio, Documentos o Imágenes están en OneDrive, si hay archivos solo en la nube, si no pudo revisar cada archivo, si otra cuenta del equipo tiene datos en riesgo o si el proceso no corre con la cuenta que inició sesión en el escritorio: el ajuste queda `skipped` con el motivo; deshacer lo reinstala con `winget`. Elevado, solo usa instaladores de rutas confiables. `gaming-hags` solo activa la GPU acelerada si el driver la admite. `gaming-windowed-optimizations` cambia solo su opción dentro de la lista de preferencias de DirectX y también se niega si el proceso no corre con la cuenta del escritorio. Un script que no se pueda cargar no rompe el resto: se informa como advertencia y solo falla la validación de los ajustes que lo usan (`-Status`, `-Undo`, `-Health` y `-Measure` siguen funcionando).
  **Actions (`action`):** the loader parses the scripts in `actions/` without running them and only accepts function definitions with contract names. `onedrive` uninstalls OneDrive without deleting files and refuses (changing nothing) when Desktop, Documents or Pictures are in OneDrive, when files only live in the cloud, when it could not check every file, when another account of the machine has data at risk or when the process does not run as the account signed in to the desktop: the tweak ends `skipped` with the reason; undo reinstalls it with `winget`. Elevated, it only uses installers from trusted paths. `gaming-hags` only turns on GPU scheduling when the driver supports it. `gaming-windowed-optimizations` changes only its own choice inside the DirectX preference list and also refuses when the process does not run as the account at the desktop. A script that cannot be loaded does not break the rest: it is reported as a warning and only the validation of the tweaks that use it fails (`-Status`, `-Undo`, `-Health` and `-Measure` keep working).
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
- `-Measure` guarda RAM en uso, procesos, servicios en ejecución, tareas programadas habilitadas, espacio libre del disco del sistema, duración del último arranque y minutos desde el arranque; `-Compare <id|last>` muestra la diferencia con una medición anterior (se resuelve antes de medir, así `last` nunca es la medición nueva). Los números siguen el idioma de `-Lang` (coma decimal en `es`, punto en `en`) y, si un valor falta, la comparación dice el motivo (por ejemplo, requiere administrador).
  `-Measure` saves RAM in use, processes, running services, enabled scheduled tasks, free space on the system drive, last boot duration and minutes since boot; `-Compare <id|last>` shows the difference from an earlier measurement (it is resolved before measuring, so `last` is never the new measurement). Numbers follow the `-Lang` language (decimal comma in `es`, point in `en`) and, when a value is missing, the comparison says why (for example, needs administrator).
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
| `apply` | `runId`, `runDir`, `finishedAt`, `environment`, `restorePoint`, `rebootRequired`, `signOutRequired`, `summary` (`applied`, `partial`, `notApplied`, `failed`, `skipped`, `refused`, `journalErrors`), `results` (`id`, `title`, `status`, `reason`, `error`, `detail`, `rebootRequired`, `signOutRequired`, `refused`) |
| `status` | `items` (`id`, `title`, `status`, `runId`) |
| `undo` | `runId`, `rebootRequired`, `results` (mismos campos que `apply` / same fields as `apply`), `summary` (`restored`, `failed`, `skipped`) |
| `health` | `startedAt`, `finishedAt`, `repairRequested`, `repairRan`, `before`, `after` (`sfc`, `componentStore`, `corruptComponents`), `recommendation`, `rebootRecommended` |
| `measure` | `id`, `path`, `measurement` (`takenAt`, `idleSeconds`, `environment`, `metrics`, `notes`), `comparison` (`againstId`, `items` con `metric`, `before`, `after`, `delta`; nulo sin `-Compare` / null without `-Compare`) |
| `error` | `message`, `details` |

## Limitaciones conocidas / Known limitations

- Varias directivas no rigen en Windows Home (Widgets, telemetría mínima, historial de actividad...): en Home el plan las omite como "no aplica". La lista está en [docs/es/catalog.md](docs/es/catalog.md).
  Several policies do not apply on Windows Home (Widgets, minimum telemetry, activity history...): on Home the plan skips them as "does not apply". The list is in [docs/en/catalog.md](docs/en/catalog.md).
- Las apps que winget no puede reinstalar (Solitaire, Tips, Mapas, People y otras) no están en el catálogo: quitarlas no se podría deshacer.
  Apps that winget cannot reinstall (Solitaire, Tips, Maps, People and others) are not in the catalog: removing them could not be undone.
- Un ajuste que se niega a cambiar algo (por ejemplo OneDrive con carpetas en la nube) queda omitido (`skipped`), el resumen lo cuenta aparte como negado (`refused`) y no cuenta como fallo: el código de salida sigue siendo `0` si todo lo demás se aplicó.
  A tweak that refuses to change something (for example OneDrive with folders in the cloud) is skipped (`skipped`), the summary counts it apart as refused (`refused`) and it does not count as a failure: the exit code stays `0` if everything else was applied.
- No hay menú interactivo, y `-Status` solo informa la deriva: no ofrece reaplicar (Plan 4).
  There is no interactive menu, and `-Status` only reports drift: it does not offer to reapply (Plan 4).
- Deshacer una app de la Store es una reinstalación para una cuenta, no una restauración exacta (ver arriba).
  Undoing a Store app is a reinstall for one account, not an exact restore (see above).
- `powercfg` no detecta valores impuestos por directiva de grupo.
  `powercfg` does not detect values enforced by group policy.
- Deshacer ajustes sueltos fuera de orden puede dejar una clave de registro vacía que creó la corrida; solo deshacer en orden inverso la elimina.
  Undoing single tweaks out of order may leave an empty registry key that the run created; only undoing in reverse order removes it.
- Todo queda local: no se envía nada a ningún servidor. La skill de Claude llega en un plan posterior.
  Everything stays local: nothing is sent to any server. The Claude skill comes in a later plan.

## Desarrollo / Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build\test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File build\lint.ps1
```

Las pruebas usan Pester 5 y el lint PSScriptAnalyzer (sobre `tuneup.ps1`, `engine/`, `actions/` y `build/`). Las pruebas no instalan, quitan ni cambian nada real del sistema: Appx, DISM, winget, powercfg, sfc, el visor de eventos y el desinstalador de OneDrive se simulan. Solo escriben archivos temporales y la clave de prueba `HKCU:\Software\windows-tuneup-test` (se borra al terminar), hacen consultas de solo lectura (CIM, eventos y la consulta de capacidades de la GPU) y ejecutan `cmd.exe` con comandos inofensivos.
Tests use Pester 5 and lint uses PSScriptAnalyzer (over `tuneup.ps1`, `engine/`, `actions/` and `build/`). Tests never install, remove or change anything real on the system: Appx, DISM, winget, powercfg, sfc, the event log and the OneDrive uninstaller are mocked. They only write temporary files and the test key `HKCU:\Software\windows-tuneup-test` (removed when they finish), run read-only queries (CIM, events and the GPU capability query) and run `cmd.exe` with harmless commands.

`docs/{es,en}/catalog.md` se genera con `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1` a partir del catálogo, los perfiles y `catalog/notes/excluded.json`; una prueba falla si no se regeneró después de cambiar el catálogo.
`docs/{es,en}/catalog.md` is generated with `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1` from the catalog, the profiles and `catalog/notes/excluded.json`; a test fails if it was not regenerated after changing the catalog.

`-StateRoot`, `-ActionsPath`, `-CatalogPath` y `-ProfilesPath` son solo para pruebas y desarrollo. `-StateRoot <carpeta>` guarda corridas y mediciones en otra carpeta, sin la protección de la carpeta de máquina (no usarlo en un equipo real). `-ActionsPath <carpeta>` carga scripts de acción de otra carpeta, que corren con tus permisos (con administrador si estás elevado): usar solo una carpeta de confianza.
`-StateRoot`, `-ActionsPath`, `-CatalogPath` and `-ProfilesPath` are for testing and development only. `-StateRoot <folder>` keeps runs and measurements in another folder, without the protection of the machine folder (do not use it on a real machine). `-ActionsPath <folder>` loads action scripts from another folder, which run with your rights (administrator when elevated): use only a folder you trust.

Licencia / License: MIT
