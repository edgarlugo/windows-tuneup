# Plan 6: arranque y segundo plano (`-Startup`) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que `tuneup.ps1 -Startup` muestre, sin administrador, lo que arranca con Windows o queda en segundo plano (Run y RunOnce, carpetas Inicio, tareas de inicio de las apps de la Store, tareas programadas y servicios automáticos de terceros) con su editor, si corre y cuánta memoria usa, marque lo protegido y lo recomendado, y que `-Startup -Disable '<ids>'` apague de forma reversible solo lo que el usuario eligió, como una corrida más de la herramienta (diario, `-Status`, `-Undo`), sin desinstalar ni borrar nada; el menú suma la opción "Lo que arranca con Windows", y la skill de Claude ofrece el paso "¿Revisamos lo que arranca con Windows?".

**Architecture:** La lectura vive en `engine/Startup.ps1` (un detector simulable por fuente, la lista de entradas y el documento `startup`) y las reglas de protección y recomendación en datos revisables (`catalog/startup/rules.json`, cargado y aplicado por `engine/StartupRules.ps1`). Apagar convierte cada entrada elegida en un **ajuste sintético** de un tipo que ya existe (`registry` para `StartupApproved` y para el `State` de las tareas de la Store, `task`, `service`), en `engine/StartupTweak.ps1`, y lo pasa al mismo camino que aplicar perfiles (`New-TuneupPlan` + `Invoke-TuneupPlannedApply`, `source` = `startup`): el diario guarda el ajuste completo, así `-Undo` y `-Status` funcionan sin cambios. La deriva de una entrada de `StartupApproved` mira solo si está encendida o apagada (un campo `compare` del bloque `set` que respeta `Test-RegistryTweakState`), así el Administrador de tareas no produce falsos "revertidos". `engine/Commands.ps1` suma `Invoke-TuneupStartupCommand`; `tuneup.ps1` y `engine/Arguments.ps1`, los parámetros; `engine/Menu.ps1`, la opción 6.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.9.1, PSScriptAnalyzer 1.25, registro (`Run`, `RunOnce`, `StartupApproved`, `AppModel\SystemAppData`), módulo ScheduledTasks, CIM (`Win32_Service`, `Win32_SystemDriver`, `root/SecurityCenter2`), módulo Appx, `Get-AuthenticodeSignature`, COM `WScript.Shell` (solo para leer accesos directos), plugins de Claude Code.

**Especificación:** `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`, sección 15 (escrita en el mismo commit que este plan). Donde este plan precisa algo, lo dice la tabla "Decisiones".

**Planes anteriores:** `docs/superpowers/plans/2026-09-30-plan-1-motor-nucleo.md` a `2026-10-02-plan-5-skill-plugin.md`. **Los archivos del repositorio son la fuente de verdad.** Este plan se escribió leyendo `feat/startup` en `65bebc4` (`main` con el Plan 5 y los hallazgos de la VM mergeados).

**Revisión:** la versión 2 (mismo día) resuelve las seis preguntas abiertas de la primera: actualizadores de navegadores protegidos (decisión 7), deriva por el primer byte (16), reglas `device` acotadas y `companion-app` (6, 25), equipo de trabajo (23), opción del menú (24) y tareas de la Store sin clave (3).

**Evidencia:** este plan **no se ejecutó**. Cada función, parámetro, clave de i18n y archivo que usa existe en `65bebc4` (se revisó uno por uno) o lo define una tarea de este plan. Lo que se comprobó en este equipo está en "Qué se verificó al escribir el plan", al final.

---

## Convenciones de este plan

Se heredan las de los Planes 1 a 5:

- **Código, comentarios, identificadores y errores para desarrolladores en inglés.** Los textos para el usuario van en `i18n/es.json` e `i18n/en.json` (mismas claves y marcadores `{n}`: `tests/I18n.Tests.ps1`), y toda clave que el código nombra con un literal tiene texto en los dos idiomas (`tests/I18nCoverage.Tests.ps1`). Las claves que se arman con una variable (`"startup.source.$source"`) las cubre una prueba propia (Task 3).
- **Todo `.ps1`/`.psm1`/`.psd1` en ASCII** (`tests/Repo.Tests.ps1`); `.json` y `.md` en UTF-8 sin BOM. Todo `.json` del repositorio tiene que poder leerse.
- **Las funciones emiten elementos; quien llama envuelve con `@()`.** `ConvertTo-Json` siempre con `-Depth 10`. Comparaciones con null: `$null -eq $x`.
- **Los fallos se lanzan, nunca se tragan.** Un `catch` solo existe para convertir el error en otro más claro, en un resultado explícito o en un aviso. Un detector que falla es un aviso (`Invoke-TuneupDetector`, de `engine/Suggest.ps1`) y nunca rompe el documento.
- **Los comandos nunca llaman a `exit`**: escriben su reporte, dejan el código en `$Context.ExitCode` y lo producido en `$Context.Result`.
- **Un ayudante que devuelve valores no escribe reportes.**
- **Los argumentos de un paso van en una tabla** (`$x = @{...}; Invoke-TuneupContextStep -Context $Context -Step { Cmd @x }`): PSScriptAnalyzer no ve un parámetro usado solo dentro del bloque.
- **Sustantivos en singular** (`PSUseSingularNouns`): `Import-TuneupStartupRuleSet`, no `...Rules`.
- Pruebas con **Pester 5.9.1** en Windows PowerShell 5.1: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/X.Tests.ps1` para un archivo, sin `-Path` para la suite. Los detectores se simulan con `Mock -ModuleName Tuneup`.
- **Las pruebas nunca modifican el sistema real**: registro solo bajo `HKCU:\Software\windows-tuneup-test`, archivos en `$TestDrive`, estado con `-StateRoot` o `$context.StateRoot`. Ninguna prueba apaga una entrada real de arranque; `tests/Cli.Tests.ps1` solo lista (forma del documento) y prueba rechazos.
- Lint: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`.
- Commits en español con prefijo convencional y **sin** `Co-Authored-By`. **Nunca `git add -A` ni `git add .`**: cada paso nombra sus archivos. Después de cada commit, `git log -1 --format=%s` para ver que los acentos quedaron bien.
- Directorio: `C:\Users\Edgar\Documents\GitHub\windows-tuneup`, rama `feat/startup`.
- Un archivo nuevo va completo; un cambio a uno existente da el texto exacto a reemplazar y el que lo reemplaza, o la función completa nueva.

## Decisiones

| # | Decisión | Dónde |
|---|---|---|
| 1 | **Ajustes sintéticos con los manejadores que ya existen**, no un tipo nuevo. El diario guarda el ajuste entero y su estado anterior; `-Undo` (`Invoke-TuneupUndo`) y `-Status` (`Get-TuneupStatus`) leen el diario, no el catálogo. Así la reversa, la comparación de estado antes de restaurar (14.2), las líneas de deshacer a mano (12.7, ya cubren `Binary`), la regla de la carpeta de usuario (`Test-TuneupUserScopedTweak`: `registry` de `HKCU:` con `scope: user`) y el dueño de cada entrada siguen iguales. Un tipo nuevo habría pedido cinco funciones de manejador, una entrada en `Dispatch.ps1`, otra regla para la carpeta de usuario y otra clase de líneas de deshacer a mano | Tasks 7, 8 |
| 2 | **Formato de `StartupApproved`**: 12 bytes, primer byte par = encendida (`02`, `06` en algunas de Windows), impar = apagada (`03`), bytes 4 a 11 = FILETIME UTC de cuándo se apagó; sin valor = encendida. Sin documentación de Microsoft: comportamiento conocido del Administrador de tareas (Eleven Forum, "Enable or Disable Startup Apps in Windows 11", https://www.elevenforum.com/t/enable-or-disable-startup-apps-in-windows-11.699/) **y comprobado en este equipo** (ver el final). Apagar escribe `03 00 00 00` + FILETIME de ahora, como el Administrador de tareas | Tasks 1, 7 |
| 3 | **Tareas de inicio de la Store**: valor `State` (DWORD) en `HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\<familia>\<TaskId>`, con los valores del enum documentado `Windows.ApplicationModel.StartupTaskState` (https://learn.microsoft.com/uwp/api/windows.applicationmodel.startuptaskstate: 0 `Disabled`, 1 `DisabledByUser`, 2 `Enabled`, 3 `DisabledByPolicy`, 4 `EnabledByPolicy`). Apagar escribe 1 (`DisabledByUser`, lo que escribe Configuración: la app no puede volver a encenderse sola). Solo cuenta como tarea de inicio una clave cuyo `TaskId` declara el manifiesto del paquete (`windows.startupTask`), para no tomar otro `State` de `SystemAppData`. El Administrador de tareas también escribe `LastDisabledTime`: no se escribe (un valor por ajuste; no hace falta para apagarla). **Una tarea sin clave no se lista y no se leen todos los manifiestos**: la documentación de `StartupTask` (https://learn.microsoft.com/uwp/api/windows.applicationmodel.startuptask, Remarks) dice que declarar la extensión "will not, by itself, automatically cause the app start" y que, para que arranque, "the user must either launch the app at least once, or they must enable startup functionality for the app on the Startup page in Settings"; Windows guarda entonces el estado en esa clave (en este equipo, las cuatro tareas que alguna vez se usaron la tienen). Sin clave, la tarea nunca se encendió y no arranca | Tasks 4, 5, 7 |
| 4 | **Ids** `startup.<source>.<slug>-<hash8>`, con `hash8` del SHA256 de `<source>|<clave en minúsculas>`: deterministas, sin distinguir mayúsculas (el registro y las tareas no las distinguen), con caracteres seguros, y dentro del patrón del catálogo (`^[a-z]+(\.[a-z0-9-]+)+$`), así la skill, `-Undo -Tweak` y el guardia de la plantilla elevada los aceptan sin cambios | Task 1 |
| 5 | **Reglas en datos** (`catalog/startup/rules.json`), en una subcarpeta para que `Import-TuneupCatalog` (que lee solo `catalog/*.json`) no las tome como ajustes; `build/package.ps1` las suma al zip. Se leen siempre de la copia de la herramienta (`$script:StartupRulesPath`): `-CatalogPath` no las cambia, para que no se pueda plantar otra lista de protegidos | Task 2 |
| 6 | **Orden de la protección**: `policy`, `driver`, `windows-component` (firmante válido `Microsoft Windows` o `Microsoft Windows Publisher`, servicio de `windowsServices` = la lista de servicios protegidos de `tests/CatalogQuality.Tests.ps1` más `MDCoreSvc`, o paquete de la Store con `SignatureKind` = `System`), `security` (carpeta de un producto de `root/SecurityCenter2`, o regla), `vpn`, `device`, `updates` (reglas). Primera que se cumple gana. Las reglas se prueban contra nombre, editor, nombre de archivo del programa y clave, sin distinguir mayúsculas. **`device` acotado**: solo los ayudantes de los controladores (consola y servicios de audio, panel táctil, teclas Fn, servicios de pantalla y de lápiz), nombrados por su programa o servicio, nunca por el nombre del fabricante; las apps de acompañamiento (GeForce Experience o NVIDIA app, AMD Software Adrenalin, Armoury Crate, G HUB, Synapse, iCUE...) no se protegen (decisión 25) | Task 2 |
| 7 | **`updates` protege los actualizadores de navegadores y de Office** (Edge, Chrome, Firefox, Brave, Click-to-Run): el diseño aprobado pedía recomendar "actualizadores", pero apagar estos deja el navegador sin parches; es el mismo principio que Windows Update en la lista negra (confirmado por el coordinador al revisar la versión 1). La sección nueva de `blacklist.md` y la skill (`SKILL.md`, `reading-json.md`) dicen que se protegen aunque sean actualizadores. Los demás actualizadores (Adobe, Java...) sí se recomiendan (`updater`) | Tasks 2, 14, 15 |
| 8 | **Servicios, controladores y tareas de Windows no se listan** (no son de terceros: firmados por Windows o bajo `\Microsoft\`); las entradas de Windows de `Run`, carpetas y Store sí, como protegidas (son pocas y el usuario las ve en el Administrador de tareas). Un controlador de terceros se lista protegido (`driver`) | Tasks 4, 5 |
| 9 | **Programas anfitriones** (`rundll32.exe`, `cmd.exe`, `powershell.exe`... en `hostPrograms`): sin editor ni uso propios, porque su firma es la de Windows y marcaría como componente de Windows lo que un tercero arranca a través de ellos | Tasks 2, 5 |
| 10 | **Uso**: memoria = suma del conjunto de trabajo de los procesos del programa (MB); CPU = tiempo de CPU acumulado (segundos), no un porcentaje (medirlo exigiría esperar entre dos lecturas). Sin elevar, Windows no da la ruta de algunos procesos: `running` queda `false` o `null` (desconocido) y se documenta como "mejor esfuerzo" | Task 5 |
| 11 | **No se pueden apagar**: protegidas, `runonce-*` (corren una vez y Windows las borra; apagarlas exigiría borrar el valor), y tareas con `*`, `?`, `[` o `]` en el nombre o la carpeta (`Get-TuneupScheduledTask` busca con comodines y no podría asegurar la tarea exacta). Un id así es `error` y no se hace nada | Tasks 2, 8 |
| 12 | **Ya apagada**: una entrada de `StartupApproved` ya apagada (primer byte impar, con cualquier fecha) se lee `applied` por la comparación de la decisión 16, así el plan la deja en `already-applied`; una tarea de la Store ya apagada (`State` 0, 1 o 3) pide el `State` que ya tiene. Apagar dos veces no cambia nada. Un servicio que ya pasó a Manual deja de listarse: su id es "desconocido" la segunda vez (`err.startupUnknown` lo explica) | Tasks 7, 8 |
| 13 | **Servicio a `Manual` sin detenerlo** (`stop: false`) y **sin cerrar programas**: rige desde el próximo inicio; el reporte para personas lo dice (`startup.nextStart`) y los ajustes no piden reinicio ni cierre de sesión | Tasks 7, 8 |
| 14 | **Elevado como otra cuenta** (`IsSessionUser` falso): un id de alcance usuario es `error` con `reason` = `session-user` antes de leer nada (el HKCU visible es el de otra cuenta). La skill apaga lo de usuario sin elevar y lo de máquina con un UAC | Tasks 8, 15 |
| 15 | **`-Status -Reapply` no vuelve a aplicar entradas de arranque** (no están en el catálogo): las deja fuera con el aviso `reapply.startupEntry`, también nombradas en `-Include` (sin `error`). Volver a apagarlas es `-Startup -Disable` (la entrada se vuelve a leer) | Task 9 |
| 16 | **Deriva sin falsos "revertidos"**: el bloque `set` del ajuste de una entrada de `StartupApproved` lleva `compare: 'startupApproved'`, que solo mira `Test-RegistryTweakState`: aplicado = valor binario con el primer byte impar, sea cual sea la fecha (el Administrador de tareas escribe una fecha nueva cada vez que apaga). `Get-RegistryTweakState` sigue leyendo los bytes exactos: el diario guarda el valor original, `-Undo` lo devuelve byte por byte, y la comparación de antes de restaurar (14.2) ve los bytes, así una entrada vuelta a apagar con otra fecha también vuelve al valor original. Se eligió un campo y no un tipo nuevo (`startup-approved`) porque un tipo exige cinco funciones, una entrada en `Dispatch.ps1`, cambiar la regla de la carpeta de usuario (`Test-TuneupUserScopedTweak` solo acepta `registry`) y las líneas de deshacer a mano; el campo es una rama de cinco líneas en un solo lugar. El catálogo rechaza `compare` (`Test-RegistryTweakDefinition`): solo lo usan los ajustes sintéticos | Task 7 |
| 17 | **`-Startup` es un comando** (se excluye con los otros y con las opciones de aplicar); `-Disable` exige `-Startup` y trae `-Yes` y `-WhatIf` (`CliApplyingOptions`, como `-Reapply`). Listar no se niega en un Windows no soportado; `-Disable` sí, salvo `-Force`, como aplicar | Task 10 |
| 18 | **El perfil `gaming` ofrece la revisión** con un campo opcional de perfil, `offersStartup` (booleano, validado): al planear o aplicar sin `-Json` se agrega una línea (`startup.offer`), y `-List -Json` lo dice en `profiles[].offersStartup` para la skill. El menú, además, tiene su opción (decisión 24) | Task 11 |
| 19 | **Desinstalar**: solo se muestra `winget uninstall --id <id> --exact` cuando la regla que recomienda trae `wingetId` (validado con `^[A-Za-z0-9][A-Za-z0-9.+_-]*$`); nunca se ejecuta. Sin `wingetId` (Store, OneDrive, Teams) no se muestra nada | Tasks 2, 5 |
| 20 | **Sin elevar faltan tareas**: el documento lleva `isAdmin` y un aviso (`startup.unelevatedNote`) | Task 8 |
| 21 | `command` se suma a los textos libres que `out\<id>.json` oculta en la carpeta de máquina (`ResultFreeTextFields`): las rutas de las entradas pueden llevar la carpeta del perfil (`path` ya estaba) | Task 6 |
| 22 | Los textos `why` de un ajuste sintético se escriben en el idioma de la corrida en los dos campos (`es` y `en`): el diario guarda ese texto y `.ps1` no puede llevar acentos | Task 7 |
| 23 | **Equipo de trabajo**: `-Startup` lo decide con `IsManaged` del entorno (el comando ya lo lee) o con la unión a Entra ID (`Test-TuneupEntraJoined`, una lectura de registro): la misma regla que la señal `work` de `-Suggest`, sin leer nada más. Ahí las reglas con `workApp: true` (OneDrive, Teams, Outlook) no marcan la entrada como recomendada: sigue apagable, con `notRecommendedReason` = `work-app` para que la skill lo explique; el documento lleva `workPc`. Una unión a Entra ID que no se puede leer es un aviso y cuenta como no unida | Tasks 2, 5, 6, 8 |
| 24 | **Opción 6 del menú, "Lo que arranca con Windows"**: muestra la tabla y deja elegir por número (`Select-TuneupMenuItem`, nada marcado de antemano, lo recomendado primero) entre las entradas que se pueden apagar; después, el plan y la confirmación de `-Startup -Disable`. Si lo elegido necesita administrador y el menú no lo es, lo dice y vuelve sin cambiar nada | Task 12 |
| 25 | **`companion-app`**, categoría nueva de recomendación: las apps de acompañamiento del fabricante (GeForce Experience o NVIDIA app, AMD Software Adrenalin, Armoury Crate, Logitech G HUB y Options+, Razer Synapse, Corsair iCUE, SteelSeries GG, Intel Driver & Support Assistant, Intel Graphics Software) no son controladores y suelen cargar overlays, iluminación o actualizadores; sin `wingetId` (no se comprobaron) | Task 2 |
| 26 | **`why` en cada regla** de `rules.json` (obligatorio y validado): el porqué para quien revisa, en lugar de comentarios, que JSON no tiene | Task 2 |
| 27 | **Servicios de paquetes de controladores protegidos por su firmante** (decidido al ejecutar las Tasks 1 a 5, tras el humo en este equipo: 17 de los 26 servicios listados eran de controladores, firmados WHCP, y quedaban apagables): `protectSigners` en `rules.json` (`category` `device`, `signer` `Microsoft Windows Hardware Compatibility Publisher`, `sources` `["service"]`, `why`), validado por `Test-TuneupStartupRuleSet` y aplicado por `Find-TuneupStartupSignerRule`. Solo servicios: una entrada de `Run`, una tarea o una app de la Store con esa firma no se protege por ella. Entre una regla de patrón y una de firmante gana la categoría que va antes en el orden de la decisión 6 | Task 2 (después) |
| 28 | **Editor de una app de la Store**: el `PublisherDisplayName` del manifiesto (el que muestra Configuración; `Get-TuneupAppxManifestStartupTask` lo trae en cada tarea, así el manifiesto se lee una vez), o el CN del paquete, que a veces es un GUID, si viene vacío o como `ms-resource:`. Es solo lo que se muestra: las protecciones usan el firmante, que va en `target.Signer` (el CN del paquete) | Task 5 (después) |
| 29 | **PowerShell de 32 bits en un Windows de 64 bits**: `-Startup` se niega (listar y apagar) con `err.startupWow64`. WOW64 le muestra otro `HKLM\SOFTWARE` y otro System32 (en la revisión, `SamSs` salía apagable); `Get-TuneupStartupEntry` llama a `Assert-TuneupStartupNativeProcess` antes de leer nada, así la Task 8 lo hereda al volver a leer las entradas | Tasks 5, 8 |
| 30 | **Firma de Windows comprobada, y a falla cerrada en los servicios.** Un firmante de `windowsSigners` cuenta solo si Windows lo avala (`IsOSBinary` de `Get-AuthenticodeSignature`) o su cadena llega a una raíz de Microsoft (por huella: Root Authority, Root Certificate Authority, 2010 y 2011; sin revisar revocación). `Get-TuneupFileSignature` da `{ Signer, IsOSBinary, MicrosoftRoot }`; la entrada guarda `target.Signer` y `target.WindowsSigned`, y `windows-component` mira eso, nunca el nombre. Un servicio o controlador que corre desde la carpeta de Windows (`GetFolderPath('Windows')`, ruta normalizada, sin distinguir mayúsculas) y no está firmado por otro editor: si lo corre `svchost.exe` o `lsass.exe` no se lista (son los anfitriones de servicios de Windows; un `ServiceDll` de un tercero en un grupo compartido queda fuera de alcance, decisión 8), si no se lista protegido con su propio motivo, `unverified` (`target.Unverified`; decisión 38), para que se vea pero no se apague lo que no se pudo comprobar. `windowsServices` suma los servicios básicos (`DcomLaunch`, `RpcEptMapper`, `SamSs`, `ProfSvc`, `LSM`, `Power`...) y compara también el nombre base de los servicios por usuario (`nombre_<hex>`) | Tasks 2, 4, 5 (después) |
| 31 | **Servicios que corre un programa anfitrión** (`cmd.exe`, `powershell.exe`...): la firma del anfitrión no los esconde (no es la del servicio); como el anfitrión vive en la carpeta de Windows, la decisión 30 los lista protegidos. `hostPrograms` sigue sin dar editor ni uso a las entradas de `Run`, carpetas y tareas | Task 5 (después) |
| 32 | **Procesos protegidos y agentes de la organización**: un servicio con `LaunchProtected` 1 a 3 (`HKLM\SYSTEM\CurrentControlSet\Services\<nombre>`, se lee sin elevar) es `security`; las reglas `security` suman Symantec y Broadcom, Trellix, Sysmon, Carbon Black (`CbDefense`), Cortex XDR (`cyserver`, Cyvera), Elastic, Cybereason, Tanium, Qualys, Rapid7, Huntress, CrowdStrike (`CSFalcon`), SentinelOne (`SentinelAgent`), Intune Management Extension, Configuration Manager (`CcmExec`) y Defender for Identity (`AATPSensor`). El texto de `startup.protected.security` dice "seguridad o administración del equipo". Las carpetas de producto del Centro de seguridad nunca son una carpeta que lo contiene todo (unidad, Windows, System32, SysWOW64, Program Files, ProgramData) | Tasks 2, 3, 4 (después) |
| 33 | **Actualizadores**: `updates` suma Opera (y Opera GX), Vivaldi y Yandex, y las tareas `BraveSoftwareUpdate*`; el Servicio de mantenimiento de actualizaciones de Microsoft (`uhssvc`) va en `windowsServices`; las tareas de actualización de OneDrive son `updater` con `workApp` | Task 2 (después) |
| 34 | **Lanzadores de juegos por su programa**: Steam, Epic, EA app, Battle.net y Ubisoft Connect se reconocen por el nombre de archivo o el nombre del lanzador, nunca por todo lo que firma su editor (Steam Client Service, Epic Online Services, el agente de Blizzard...): la línea de desinstalar es solo para el lanzador | Task 2 (después) |
| 35 | **Una entrada no rompe la lista**: un programa con caracteres que ninguna ruta puede tener queda sin programa; un fallo al completar una entrada es un aviso y la entrada queda no apagable con el motivo `unreadable`; un paquete de la Store ilegible o un `State` que no es número deja fuera solo eso, con aviso; una firma que no se pudo leer falla una vez y después es desconocida; los avisos de `-Startup` tienen su propio texto ("the list of what starts with Windows may be incomplete"), no el de `-Suggest`; el manifiesto se lee con `DtdProcessing = Prohibit` | Tasks 4, 5 (después) |
| 36 | **SID fuera de la parte legible del id**: el `slug` quita los SID (`S-1-...`) de la clave antes de armarse; el hash sigue usando la clave entera, así dos cuentas no comparten id. `key`, `name`, `command` y `path` pueden llevar un SID o el nombre de la cuenta: la Task 6 lo cubre | Tasks 1, 6 |
| 37 | **Reglas más estrictas**: `Test-TuneupStartupRuleSet` rechaza campos desconocidos (arriba, en cada regla y en `protectSigners`), `wingetId` y `workApp` en `protectSigners`, y un patrón que calza con un texto vacío. Una tarea con un acento grave (`` ` ``, el escape de los comodines) en el nombre también es `unsupported-name` | Task 2 (después) |
| 38 | **Segunda revisión.** (a) `Get-TuneupCommandProgram` tampoco da programa con `*`, `?` o `:` fuera de la letra de la unidad (un flujo alternativo), ni cuando `GetFullPath` falla. (b) Cada elemento de cada fuente (valor de `Run`, archivo de la carpeta Inicio, tarea de la Store, tarea programada, servicio) se lee dentro de `Invoke-TuneupStartupItem`: si falla, aviso ("Could not read the startup item...") y ese elemento queda fuera; el resto de la lista sigue. (c) La cadena hasta una raíz de Microsoft solo se construye para un firmante de `windowsSigners` sin `IsOSBinary` (`Get-TuneupFileSignature -WindowsSigner`), con `UrlRetrievalTimeout` de 2 s y sin revisar revocación; la prueba del caso positivo usa la raíz 2010 del almacén de la máquina, sin red. (d) Un servicio de la carpeta de Windows sin firma comprobada es `unverified`, motivo propio (es/en; el contrato JSON lo suma en la Task 13), no `windows-component`; sigue sin poder apagarse | Tasks 4, 5, 13 |
| 39 | **Revisión de las Tasks 6 a 10.** (a) El hash del id son 16 dígitos hexadecimales (los ids de ejemplo de este plan con 8 quedan viejos: `steam-eb4bc901` es `steam-eb4bc901e3d06cf1`). Las entradas que comparten un id no se pueden apagar (motivo `ambiguous`, `startup.fixed.ambiguous`, aviso en la lista) y `-Disable` las rechaza con un detalle por id. (b) Un ajuste de arranque cuya entrada ya no está (valor de `Run`, archivo de la carpeta Inicio, clave de la tarea de la Store, tarea, servicio) es `not-present` en `-Status` y `-Undo` lo da por restaurado con ese motivo sin crear nada (`Test-TuneupStartupTweakPresent`, una rama en `Test-TuneupState` y `Restore-TuneupState` de `Dispatch.ps1`). (c) Apagar una entrada de máquina sin elevar es `err.startupNeedsAdmin` con `reason` = `needs-admin`. (d) Lo que escribe un ajuste `registry` queda fijo a la clave `StartupApproved` de su fuente y alcance o a `SystemAppData\<clave>` (las pruebas cambian `$script:StartupApprovedRoot`, `$script:StoreTaskRoot` y `$script:StartupRunKeys` con `InModuleScope`). (e) Nombres o claves con caracteres de control son `unreadable`; los ids se leen sin distinguir mayúsculas y lo que no es un id de `-Startup` se rechaza antes de leer; `startup.otherAccountNote` al listar elevado como otra cuenta; los SID y las carpetas de otras cuentas se ocultan también en `transcript.log` y `result.json` | Tasks 6 a 10 (después), 12 |

## Estructura de archivos del Plan 6

```
windows-tuneup/
├── tuneup.ps1                          + -Startup, -Disable
├── catalog/startup/rules.json          (nuevo) windowsSigners, hostPrograms, windowsServices, protect, protectSigners, recommend
├── engine/
│   ├── Startup.ps1                     (nuevo) fuentes, ids, ayudantes de rutas, detectores, entradas, documento y reporte
│   ├── StartupRules.ps1                (nuevo) Import/Test de las reglas, protección, recomendación, desinstalar
│   ├── StartupTweak.ps1                (nuevo) ajustes sintéticos (registry, task, service)
│   ├── Arguments.ps1                   + Startup, Disable
│   ├── Commands.ps1                    + Invoke-TuneupStartupCommand, Test-TuneupStartupOffered; reapply deja fuera las entradas de arranque; CLI
│   ├── Catalog.ps1                     + offersStartup en Test-TuneupProfileSet
│   ├── List.ps1                        + profiles[].offersStartup
│   ├── Menu.ps1                        + opción 6 (Invoke-TuneupMenuStartup); línea startup.offer después de Optimizar
│   ├── Output.ps1                      + source startup en el plan y el reporte
│   ├── Planner.ps1                     New-TuneupPlan acepta una lista de perfiles vacía
│   ├── handlers/Registry.ps1           + set.compare = 'startupApproved' en Test (y rechazado en el catálogo)
│   └── ResultFile.ps1                  + command en ResultFreeTextFields
├── profiles/gaming.json                + offersStartup
├── i18n/es.json, i18n/en.json          + startup.*, err.startup*, menu.main.startup, menu.startup.*, reapply.startupEntry, transcript.request.startup
├── build/package.ps1                   + catalog/startup/*.json
├── docs/
│   ├── json-contract.md                + startup, source startup, offersStartup, session-user
│   ├── es|en/blacklist.md              + qué nunca apaga -Startup
│   ├── es|en/profiles.md               + gaming ofrece -Startup
│   ├── es|en/vm-checklist.md           + ida y vuelta de -Startup
│   └── es|en/skill-checklist.md        + paso de arranque
├── plugins/windows-tuneup/skills/windows-tuneup/
│   ├── SKILL.md                        + barrera 13, paso 8 del modo asistido, sección "What starts with Windows"
│   └── reference/commands.md, reading-json.md
├── tests/
│   ├── Startup.Tests.ps1, StartupRules.Tests.ps1, StartupTweak.Tests.ps1, StartupCommand.Tests.ps1   (nuevos)
│   └── Arguments, Cli, Docs, JsonContract, List, Menu, Package, Planner, Plugin, Catalog .Tests.ps1 (se amplían)
└── README.md                           + -Startup, -Disable, documento startup
```

`engine/Tuneup.psm1` carga todo `.ps1` de `engine` por orden alfabético (`Startup.ps1`, `StartupRules.ps1`, `StartupTweak.ps1`, `StateFiles.ps1`...): las variables `$script:` de un archivo que usa otro solo se leen dentro de funciones, al llamarlas, así el orden no importa. `.github/workflows` no cambia.

---

### Task 1: Fuentes, ids y ayudantes de rutas

**Files:**
- Create: `engine/Startup.ps1`
- Test: `tests/Startup.Tests.ps1` (nuevo)

- [ ] **Step 1: Escribir las pruebas que fallan**

Crear `tests/Startup.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:I18nRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
    Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
}

Describe 'Startup ids' {
    It 'gives the same id for the same source and key, whatever the case' {
        Get-TuneupStartupId -Source 'run-user' -Key 'Steam' | Should -BeExactly 'startup.run-user.steam-eb4bc901'
        Get-TuneupStartupId -Source 'run-user' -Key 'STEAM' | Should -BeExactly 'startup.run-user.steam-eb4bc901'
    }

    It 'gives another id for the same key in another source' {
        Get-TuneupStartupId -Source 'run-machine' -Key 'Steam' | Should -BeExactly 'startup.run-machine.steam-bb5ab8ea'
    }

    It 'keeps only safe characters, cuts long keys and never leaves the slug empty' {
        Get-TuneupStartupId -Source 'task' -Key '\Vendor\Updater Task (Logon)' | Should -BeExactly 'startup.task.vendor-updater-task-logon-a94b661c'
        Get-TuneupStartupId -Source 'service' -Key 'AVeryLongServiceNameThatGoesOnAndOnForeverAndEver' |
            Should -BeExactly 'startup.service.averylongservicenamethatgoesonan-57d0735c'
        Get-TuneupStartupId -Source 'store-app' -Key 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' |
            Should -BeExactly 'startup.store-app.msteams-8wekyb3d8bbwe-teamstfwst-119df735'
        # Letters outside ASCII leave only what is left (here the extension of the shortcut).
        Get-TuneupStartupId -Source 'folder-user' -Key ([string][char]0x5FAE + [char]0x4FE1 + '.lnk') | Should -BeExactly 'startup.folder-user.lnk-70476f0a'
        Get-TuneupStartupId -Source 'folder-user' -Key ([string][char]0x5FAE + [char]0x4FE1) | Should -Match '^startup\.folder-user\.entry-[0-9a-f]{8}$'
    }

    It 'matches the id rule of the catalog and its own pattern' {
        $id = Get-TuneupStartupId -Source 'run32-machine' -Key 'Vendor Tray'
        $id | Should -MatchExactly '^[a-z]+(\.[a-z0-9-]+)+$'
        Test-TuneupStartupId -Id $id | Should -BeTrue
        Test-TuneupStartupId -Id 'privacy.advertising-id' | Should -BeFalse
        Test-TuneupStartupId -Id 'STARTUP.RUN-USER.X-1' | Should -BeFalse
        Test-TuneupStartupId -Id $null | Should -BeFalse
    }

    It 'tells the scope of an id from its source' {
        Get-TuneupStartupIdScope -Id 'startup.run-user.steam-eb4bc901' | Should -Be 'user'
        Get-TuneupStartupIdScope -Id 'startup.store-app.x-00000000' | Should -Be 'user'
        Get-TuneupStartupIdScope -Id 'startup.run-machine.steam-bb5ab8ea' | Should -Be 'machine'
        Get-TuneupStartupIdScope -Id 'startup.service.x-00000000' | Should -Be 'machine'
        Get-TuneupStartupIdScope -Id 'startup.nowhere.x-00000000' | Should -BeNullOrEmpty
        Get-TuneupStartupIdScope -Id 'privacy.advertising-id' | Should -BeNullOrEmpty
    }
}

Describe 'Startup path helpers' {
    It 'expands the variables of Windows and of the account from their folders, and leaves any other one' {
        $programFiles = [Environment]::GetFolderPath('ProgramFiles')
        $windows = [Environment]::GetFolderPath('Windows')
        Expand-TuneupStartupPath -Text '%ProgramFiles%\Vendor\x.exe' | Should -Be "$programFiles\Vendor\x.exe"
        Expand-TuneupStartupPath -Text '%WINDIR%\system32\a.exe' | Should -Be "$windows\system32\a.exe"
        Expand-TuneupStartupPath -Text '%NOT_A_FOLDER%\a.exe' | Should -Be '%NOT_A_FOLDER%\a.exe'
        Expand-TuneupStartupPath -Text '' | Should -Be ''
    }

    It 'finds the program of a command line: <Case>' -TestCases @(
        @{ Case = 'quoted, with arguments'; Command = '"C:\Program Files\Vendor\app.exe" --minimized'; Expected = 'C:\Program Files\Vendor\app.exe' }
        @{ Case = 'quoted twice, as some tasks keep it'; Command = '""C:\Vendor\up.exe""'; Expected = 'C:\Vendor\up.exe' }
        @{ Case = 'not quoted, with spaces in the path'; Command = 'C:\Program Files\Vendor\app.exe -silent'; Expected = 'C:\Program Files\Vendor\app.exe' }
        @{ Case = 'not quoted, without an extension it knows'; Command = 'C:\Tools\run.ps1 now'; Expected = 'C:\Tools\run.ps1' }
        @{ Case = 'a kernel path of a driver'; Command = '\??\C:\Vendor\drv.sys'; Expected = 'C:\Vendor\drv.sys' }
    ) {
        param($Command, $Expected)
        Get-TuneupCommandProgram -Command $Command | Should -Be $Expected
    }

    It 'places bare names and the paths of drivers in the folder of Windows' {
        $windows = [Environment]::GetFolderPath('Windows')
        Get-TuneupCommandProgram -Command 'rundll32.exe "C:\X\x.dll",Start' | Should -Be (Join-Path ([Environment]::SystemDirectory) 'rundll32.exe')
        Get-TuneupCommandProgram -Command '\SystemRoot\System32\drivers\vendordrv.sys' | Should -Be (Join-Path $windows 'System32\drivers\vendordrv.sys')
        Get-TuneupCommandProgram -Command 'System32\drivers\other.sys' | Should -Be (Join-Path $windows 'System32\drivers\other.sys')
        Get-TuneupCommandProgram -Command '%ProgramFiles%\Vendor\app.exe /x' | Should -Be "$([Environment]::GetFolderPath('ProgramFiles'))\Vendor\app.exe"
    }

    It 'gives nothing for an empty command or one without a full path' {
        Get-TuneupCommandProgram -Command '' | Should -BeNullOrEmpty
        Get-TuneupCommandProgram -Command $null | Should -BeNullOrEmpty
        Get-TuneupCommandProgram -Command 'relative\app.exe' | Should -BeNullOrEmpty
    }

    It 'reads the common name of a certificate subject' {
        Get-TuneupCommonName -DistinguishedName 'CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' | Should -BeExactly 'Microsoft Windows'
        Get-TuneupCommonName -DistinguishedName 'CN="Valve Corp., Inc.", O=Valve' | Should -BeExactly 'Valve Corp., Inc.'
        Get-TuneupCommonName -DistinguishedName 'O=Nobody' | Should -BeNullOrEmpty
        Get-TuneupCommonName -DistinguishedName $null | Should -BeNullOrEmpty
    }

    It 'reads a StartupApproved value as Task Manager does: <Case>' -TestCases @(
        @{ Case = 'no value is on'; Value = $null; Expected = $true }
        @{ Case = 'an empty value is on'; Value = [byte[]]@(); Expected = $true }
        @{ Case = '02 is on'; Value = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); Expected = $true }
        @{ Case = '06 is on (SecurityHealth)'; Value = [byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); Expected = $true }
        @{ Case = '03 with a date is off'; Value = [byte[]](3, 0, 0, 0, 71, 94, 174, 173, 217, 80, 221, 1); Expected = $false }
        @{ Case = '07 is off'; Value = [byte[]](7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); Expected = $false }
    ) {
        param($Value, $Expected)
        Test-TuneupStartupApprovedEnabled -Value $Value | Should -Be $Expected
    }
}

Describe 'New-TuneupStartupEntry' {
    It 'builds an entry with its id, scope and what turning it off needs' {
        $entry = New-TuneupStartupEntry -Source 'run-machine' -Key 'Vendor' -Name 'Vendor' -Command '"C:\V\v.exe"' -Path 'C:\V\v.exe' -Target @{ ApprovedName = 'Vendor' }
        $entry.id | Should -BeExactly (Get-TuneupStartupId -Source 'run-machine' -Key 'Vendor')
        $entry.scope | Should -Be 'machine'
        $entry.needsAdmin | Should -BeTrue
        $entry.enabled | Should -BeTrue
        $entry.canDisable | Should -BeFalse
        $entry.running | Should -BeNullOrEmpty
        $entry.target.ApprovedName | Should -Be 'Vendor'
    }

    It 'keeps empty texts as null and refuses an unknown source' {
        $entry = New-TuneupStartupEntry -Source 'store-app' -Key 'P\T' -Name 'App' -Command '' -Path ''
        $entry.command | Should -BeNullOrEmpty
        $entry.path | Should -BeNullOrEmpty
        $entry.needsAdmin | Should -BeFalse
        { New-TuneupStartupEntry -Source 'nowhere' -Key 'x' -Name 'x' } | Should -Throw "*Unknown startup source 'nowhere'*"
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: FAIL en todas (`Get-TuneupStartupId`, `Expand-TuneupStartupPath`... no existen).

- [ ] **Step 3: Implementar**

Crear `engine/Startup.ps1`:

```powershell
# -Startup (design, section 15): what starts with Windows or runs in the background. This file holds where
# each entry comes from, its id, the helpers that read a command line, the detectors (one per source, each
# one a function a test can stand in for), the list of entries and the startup document. Nothing here
# changes the system: turning an entry off is StartupTweak.ps1 and Invoke-TuneupStartupCommand.

$script:StartupIdPattern = '^startup\.[a-z0-9-]+\.[a-z0-9-]+$'
$script:StartupSlugLength = 32
$script:StartupApprovedRoot = @{
    user    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    machine = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
}
# Every source: its scope and, for the ones Task Manager turns off, the StartupApproved key it keeps the
# choice in. The order is the order of the list.
$script:StartupSources = [ordered]@{
    'run-user'          = [pscustomobject]@{ Scope = 'user'; Approved = "$($script:StartupApprovedRoot.user)\Run" }
    'run-machine'       = [pscustomobject]@{ Scope = 'machine'; Approved = "$($script:StartupApprovedRoot.machine)\Run" }
    'run32-machine'     = [pscustomobject]@{ Scope = 'machine'; Approved = "$($script:StartupApprovedRoot.machine)\Run32" }
    'runonce-user'      = [pscustomobject]@{ Scope = 'user'; Approved = $null }
    'runonce-machine'   = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'runonce32-machine' = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'policy-user'       = [pscustomobject]@{ Scope = 'user'; Approved = $null }
    'policy-machine'    = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'folder-user'       = [pscustomobject]@{ Scope = 'user'; Approved = "$($script:StartupApprovedRoot.user)\StartupFolder" }
    'folder-machine'    = [pscustomobject]@{ Scope = 'machine'; Approved = "$($script:StartupApprovedRoot.machine)\StartupFolder" }
    'store-app'         = [pscustomobject]@{ Scope = 'user'; Approved = $null }
    'task'              = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'service'           = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'driver'            = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
}
# The Run keys and their sources. HKCU has no WOW6432Node copy of Run on 64-bit Windows (it is not
# redirected), so it is not read.
$script:StartupRunKeys = @(
    [pscustomobject]@{ Source = 'run-user'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
    [pscustomobject]@{ Source = 'run-machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    [pscustomobject]@{ Source = 'run32-machine'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
    [pscustomobject]@{ Source = 'runonce-user'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' }
    [pscustomobject]@{ Source = 'runonce-machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    [pscustomobject]@{ Source = 'runonce32-machine'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce' }
    [pscustomobject]@{ Source = 'policy-user'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run' }
    [pscustomobject]@{ Source = 'policy-machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run' }
)

# startup.<source>.<slug>-<hash>: the slug is the key in lowercase with everything but a-z and 0-9 turned
# into hyphens (32 characters at most, 'entry' when nothing is left), and the hash the first 8 hexadecimal
# digits of the SHA256 of <source>|<key in lowercase>. The same entry gets the same id in every run,
# elevated or not; the registry and the scheduled tasks do not tell case apart, so neither does the id.
function Get-TuneupStartupId {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Key)
    $normal = $Key.ToLowerInvariant()
    $slug = ($normal -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt $script:StartupSlugLength) { $slug = $slug.Substring(0, $script:StartupSlugLength).TrimEnd('-') }
    if (-not $slug) { $slug = 'entry' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$Source|$normal"))
    } finally {
        $sha.Dispose()
    }
    $short = -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
    "startup.$Source.$slug-$short"
}

function Test-TuneupStartupId {
    param([AllowNull()][AllowEmptyString()][string]$Id)
    [bool]($Id -cmatch $script:StartupIdPattern)
}

# user or machine, from the source written in the id; nothing for an id that is not one of -Startup.
function Get-TuneupStartupIdScope {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-TuneupStartupId -Id $Id)) { return }
    $source = $script:StartupSources[$Id.Split('.')[1]]
    if ($null -ne $source) { $source.Scope }
}

# The variables a startup command uses, from the folders of Windows and of the account, never from the
# environment of the process (any program of the account can change it).
function Get-TuneupStartupPathVariable {
    $windows = [Environment]::GetFolderPath('Windows')
    [ordered]@{
        'SystemRoot'              = $windows
        'windir'                  = $windows
        'SystemDrive'             = ([System.IO.Path]::GetPathRoot($windows)).TrimEnd('\')
        'ProgramFiles'            = [Environment]::GetFolderPath('ProgramFiles')
        'ProgramFiles(x86)'       = [Environment]::GetFolderPath('ProgramFilesX86')
        'CommonProgramFiles'      = [Environment]::GetFolderPath('CommonProgramFiles')
        'CommonProgramFiles(x86)' = [Environment]::GetFolderPath('CommonProgramFilesX86')
        'ProgramData'             = [Environment]::GetFolderPath('CommonApplicationData')
        'LOCALAPPDATA'            = [Environment]::GetFolderPath('LocalApplicationData')
        'APPDATA'                 = [Environment]::GetFolderPath('ApplicationData')
        'USERPROFILE'             = [Environment]::GetFolderPath('UserProfile')
    }
}

# A text with those variables written out; any other variable stays as it is.
function Expand-TuneupStartupPath {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if (-not $Text) { return $Text }
    $variables = Get-TuneupStartupPathVariable
    $evaluator = {
        param($match)
        $name = $match.Groups[1].Value
        foreach ($variable in $variables.Keys) {
            if ($variable -ieq $name -and $variables[$variable]) { return $variables[$variable] }
        }
        $match.Value
    }.GetNewClosure()
    [regex]::Replace($Text, '%([^%]+)%', $evaluator)
}

# The program a command line runs, as a full path, or nothing. Quoted: what is between the first quotes
# (some tasks keep it quoted twice). Not quoted: up to the first extension of a program followed by a space
# or the end, or the first word. A bare name is in System32; \SystemRoot\, System32\ and \??\ are the
# kernel ways of writing a driver path.
function Get-TuneupCommandProgram {
    param([AllowNull()][AllowEmptyString()][string]$Command)
    $text = ([string](Expand-TuneupStartupPath -Text ([string]$Command))).Trim()
    if (-not $text) { return }
    if ($text.StartsWith('"')) {
        $inner = $text.TrimStart('"')
        $end = $inner.IndexOf('"')
        $program = $(if ($end -ge 0) { $inner.Substring(0, $end) } else { $inner })
    } else {
        $match = [regex]::Match($text, '^(?<program>.+?\.(?:exe|com|bat|cmd|lnk|scr|sys|ps1))(?=\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $program = $(if ($match.Success) { $match.Groups['program'].Value } else { ($text -split '\s+')[0] })
    }
    $program = $program.Trim()
    if ($program.StartsWith('\??\')) { $program = $program.Substring(4) }
    $windows = [Environment]::GetFolderPath('Windows')
    if ($program -match '^\\SystemRoot\\') { $program = Join-Path $windows $program.Substring('\SystemRoot\'.Length) }
    elseif ($program -match '^system32\\') { $program = Join-Path $windows $program }
    elseif ($program -notmatch '\\') { $program = Join-Path ([Environment]::SystemDirectory) $program }
    if ($program -notmatch '^[A-Za-z]:\\') { return }
    $program
}

# The CN of a certificate subject (the name of who signed), or nothing.
function Get-TuneupCommonName {
    param([AllowNull()][AllowEmptyString()][string]$DistinguishedName)
    $match = [regex]::Match([string]$DistinguishedName, '(?:^|,\s*)CN=(?:"(?<value>[^"]*)"|(?<value>[^,]*))')
    if ($match.Success -and $match.Groups['value'].Value.Trim()) { $match.Groups['value'].Value.Trim() }
}

# Task Manager keeps one binary value per entry under StartupApproved: an even first byte (02, or 06 for
# some entries of Windows) is on, an odd one (03, followed by when it was turned off) is off, and no value
# is on (design, section 15.3).
function Test-TuneupStartupApprovedEnabled {
    param([AllowNull()][object[]]$Value)
    $bytes = @($Value | Where-Object { $null -ne $_ })
    if (-not $bytes.Count) { return $true }
    ([int]$bytes[0] -band 1) -eq 0
}

# One entry of the list. Target holds what turning it off needs (the StartupApproved key and value, the
# key of a Store task, the task, the service); it never goes to the JSON document.
function New-TuneupStartupEntry {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Command,
        [AllowNull()][AllowEmptyString()][string]$Path,
        [bool]$Enabled = $true,
        [bool]$Policy = $false,
        [hashtable]$Target = @{}
    )
    $info = $script:StartupSources[$Source]
    if ($null -eq $info) { throw "Unknown startup source '$Source'" }
    [pscustomobject]@{
        id                = Get-TuneupStartupId -Source $Source -Key $Key
        name              = $Name
        source            = $Source
        scope             = $info.Scope
        key               = $Key
        command           = $(if ($Command) { $Command } else { $null })
        path              = $(if ($Path) { $Path } else { $null })
        publisher         = $null
        enabled           = $Enabled
        policy            = $Policy
        running           = $null
        memoryMB          = $null
        cpuSeconds        = $null
        protected         = $null
        canDisable        = $false
        needsAdmin        = ($info.Scope -eq 'machine')
        recommended       = $false
        recommendedReason = $null
        notRecommendedReason = $null
        uninstall         = $null
        target            = [pscustomobject]$Target
    }
}
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 5: Commit**

```bash
git add engine/Startup.ps1 tests/Startup.Tests.ps1
git commit -m "feat(arranque): fuentes, ids estables y lectura de la línea de comandos de cada entrada"
git log -1 --format=%s
```

---

### Task 2: Reglas de protección y recomendación en datos

**Files:**
- Create: `catalog/startup/rules.json`
- Create: `engine/StartupRules.ps1`
- Modify: `build/package.ps1` (patrones de lo que entra)
- Test: `tests/StartupRules.Tests.ps1` (nuevo), `tests/Package.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

Crear `tests/StartupRules.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:RulesPath = Join-Path $Repo 'catalog\startup\rules.json'
    $script:Rules = Import-TuneupStartupRuleSet
    function New-TestStartupEntry {
        param([string]$Source = 'run-user', [string]$Key = 'Sample', [string]$Name = $Key, [string]$Path, [string]$Publisher, [bool]$Policy = $false, [hashtable]$Target = @{})
        $entry = New-TuneupStartupEntry -Source $Source -Key $Key -Name $Name -Path $Path -Policy $Policy -Target $Target
        if ($Publisher) { $entry.publisher = $Publisher }
        $entry
    }
    function Copy-TestRules { $Rules | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
}

Describe 'catalog/startup/rules.json' {
    It 'loads from the copy of the tool and passes its checks' {
        @(Test-TuneupStartupRuleSet -Rules $Rules).Count | Should -Be 0
        @($Rules.protect).Count | Should -BeGreaterThan 3
        @($Rules.recommend).Count | Should -BeGreaterThan 10
    }

    It 'is UTF-8 without a byte order mark' {
        $bytes = [System.IO.File]::ReadAllBytes($RulesPath)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'protects every service that the blacklist protects' {
        # The list of tests/CatalogQuality.Tests.ps1, block "Blacklist guard".
        foreach ($service in 'WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE', 'wuauserv', 'UsoSvc',
            'WaaSMedicSvc', 'BITS', 'DoSvc', 'InstallService', 'AppXSvc', 'ClipSVC', 'wlidsvc', 'TrustedInstaller', 'CryptSvc', 'SharedAccess',
            'LanmanServer', 'LanmanWorkstation', 'WerSvc', 'DPS', 'RmSvc', 'WpnService', 'webthreatdefsvc', 'webthreatdefusersvc', 'SysMain',
            'WSearch', 'vmcompute', 'vmms', 'hns', 'HvHost', 'LxssManager', 'WslService', 'EventLog', 'Schedule', 'Winmgmt', 'RpcSs', 'sppsvc',
            'VSS', 'swprv', 'AppIDSvc', 'Spooler', 'MDCoreSvc') {
            @($Rules.windowsServices) | Should -Contain $service
        }
    }

    It 'is not loaded as tweaks by the catalog' {
        @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog') | Where-Object { $_.sourceFile -eq 'rules.json' }).Count | Should -Be 0
    }
}

Describe 'Test-TuneupStartupRuleSet' {
    It 'finds <Case>' -TestCases @(
        @{ Case = 'another schema version'; Change = { param($r) $r.schemaVersion = 2 }; Expected = '*schemaVersion must be 1*' }
        @{ Case = 'an empty list of names'; Change = { param($r) $r.hostPrograms = @() }; Expected = '*hostPrograms must be a list of names*' }
        @{ Case = 'an unknown category'; Change = { param($r) $r.protect[0].category = 'nice' }; Expected = "*unknown category 'nice'*" }
        @{ Case = 'a pattern that is not one'; Change = { param($r) $r.recommend[0].pattern = '(' }; Expected = '*is not a valid pattern*' }
        @{ Case = 'a wingetId on a protection'; Change = { param($r) $r.protect[0] | Add-Member -NotePropertyName wingetId -NotePropertyValue 'A.B' }; Expected = '*cannot have a wingetId*' }
        @{ Case = 'a wingetId that is not one'; Change = { param($r) $r.recommend[0].wingetId = 'x; calc' }; Expected = '*invalid wingetId*' }
        @{ Case = 'a list without rules'; Change = { param($r) $r.recommend = @() }; Expected = '*recommend has no rules*' }
        @{ Case = 'a rule without why'; Change = { param($r) $r.protect[0].PSObject.Properties.Remove('why') }; Expected = '*has no why*' }
        @{ Case = 'workApp on a protection'; Change = { param($r) $r.protect[0] | Add-Member -NotePropertyName workApp -NotePropertyValue $true }; Expected = '*cannot have workApp*' }
        @{ Case = 'a workApp that is not true or false'; Change = { param($r) $r.recommend[0] | Add-Member -NotePropertyName workApp -NotePropertyValue 'yes' }; Expected = '*workApp must be true or false*' }
    ) {
        param($Change, $Expected)
        $copy = Copy-TestRules
        & $Change $copy
        @(Test-TuneupStartupRuleSet -Rules $copy) -join "`n" | Should -BeLike $Expected
    }

    It 'refuses to load rules with problems' {
        $bad = Copy-TestRules
        $bad.schemaVersion = 3
        $path = Join-Path $TestDrive 'bad-rules.json'
        [System.IO.File]::WriteAllText($path, ($bad | ConvertTo-Json -Depth 10))
        { Import-TuneupStartupRuleSet -Path $path } | Should -Throw '*are not valid*schemaVersion must be 1*'
    }
}

Describe 'Get-TuneupStartupProtection' {
    It 'gives <Expected> for <Case>' -TestCases @(
        @{ Case = 'a Run entry of a policy'; Entry = { New-TestStartupEntry -Source 'policy-machine' -Key 'Agent' -Policy $true }; Expected = 'policy' }
        @{ Case = 'a driver'; Entry = { New-TestStartupEntry -Source 'driver' -Key 'vendordrv' }; Expected = 'driver' }
        @{ Case = 'a program signed by Windows'; Entry = { New-TestStartupEntry -Key 'SecurityHealth' -Path 'C:\Windows\System32\SecurityHealthSystray.exe' -Publisher 'Microsoft Windows' }; Expected = 'windows-component' }
        @{ Case = 'a protected service of the blacklist'; Entry = { New-TestStartupEntry -Source 'service' -Key 'wuauserv' }; Expected = 'windows-component' }
        @{ Case = 'a Store app of Windows'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'Pkg\Task' -Target @{ WindowsPart = $true } }; Expected = 'windows-component' }
        @{ Case = 'an antivirus by name'; Entry = { New-TestStartupEntry -Key 'mbamtray' -Publisher 'Malwarebytes Inc.' }; Expected = 'security' }
        @{ Case = 'Defender by its program'; Entry = { New-TestStartupEntry -Source 'service' -Key 'WdBoot2' -Path 'C:\ProgramData\Microsoft\Windows Defender\Platform\4.18\MsMpEng.exe' }; Expected = 'security' }
        @{ Case = 'a VPN client'; Entry = { New-TestStartupEntry -Key 'GlobalProtect' -Path 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPA.exe' }; Expected = 'vpn' }
        @{ Case = 'the service of the audio driver'; Entry = { New-TestStartupEntry -Source 'task' -Key '\RtkAudUService64_BG' -Name 'RtkAudUService64_BG' -Publisher 'Realtek Semiconductor Corp.' }; Expected = 'device' }
        @{ Case = 'the touchpad helper'; Entry = { New-TestStartupEntry -Key 'SynTPEnh' -Path 'C:\Program Files\Synaptics\SynTP\SynTPEnh.exe' -Publisher 'Synaptics Incorporated' }; Expected = 'device' }
        @{ Case = 'the Fn keys of a laptop'; Entry = { New-TestStartupEntry -Key 'ATKOSD2' -Path 'C:\Program Files (x86)\ASUS\ATK Package\ATK Hotkey\ATKOSD2.exe' -Publisher 'ASUSTeK COMPUTER INC.' }; Expected = 'device' }
        @{ Case = 'the display container of the NVIDIA driver'; Entry = { New-TestStartupEntry -Source 'service' -Key 'NVDisplay.ContainerLocalSystem' -Name 'NVIDIA Display Container LS' -Publisher 'NVIDIA Corporation' }; Expected = 'device' }
        @{ Case = 'the updater of Edge'; Entry = { New-TestStartupEntry -Source 'task' -Key '\MicrosoftEdgeUpdateTaskMachineCore{1}' -Name 'MicrosoftEdgeUpdateTaskMachineCore{1}' }; Expected = 'updates' }
        @{ Case = 'the update service of Brave'; Entry = { New-TestStartupEntry -Source 'service' -Key 'brave' -Name 'Brave Update Service (brave)' }; Expected = 'updates' }
        @{ Case = 'Office Click-to-Run'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ClickToRunSvc' -Name 'Microsoft Office Click-to-Run Service' }; Expected = 'updates' }
    ) {
        param($Entry, $Expected)
        Get-TuneupStartupProtection -Entry (& $Entry) -Rules $Rules | Should -Be $Expected
    }

    It 'does not protect the companion apps of a vendor, which it recommends instead: <Name>' -TestCases @(
        @{ Name = 'NVIDIA app'; Entry = { New-TestStartupEntry -Key 'NvBackend' -Name 'NVIDIA app' -Path 'C:\Program Files\NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe' -Publisher 'NVIDIA Corporation' } }
        @{ Name = 'GeForce Experience'; Entry = { New-TestStartupEntry -Source 'service' -Key 'NvContainerLocalSystem' -Name 'NVIDIA GeForce Experience' -Publisher 'NVIDIA Corporation' } }
        @{ Name = 'AMD Software'; Entry = { New-TestStartupEntry -Key 'AMDNoiseSuppression' -Name 'AMD Software' -Path 'C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe' -Publisher 'Advanced Micro Devices, Inc.' } }
        @{ Name = 'Armoury Crate'; Entry = { New-TestStartupEntry -Source 'service' -Key 'ArmouryCrateService' -Name 'ARMOURY CRATE Service' -Publisher 'ASUSTeK COMPUTER INC.' } }
        @{ Name = 'Logitech G HUB'; Entry = { New-TestStartupEntry -Key 'LGHUB' -Path 'C:\Program Files\LGHUB\lghub.exe' -Publisher 'Logitech Inc' } }
        @{ Name = 'Intel Graphics Software'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'AppUp.IntelArcSoftware_8j3eq9eme6ctt\IntelGraphicsSoftwareStartup' -Name 'Intel Graphics Software' -Publisher 'Intel Corporation' } }
    ) {
        param($Entry)
        $companion = & $Entry
        Get-TuneupStartupProtection -Entry $companion -Rules $Rules | Should -BeNullOrEmpty
        (Get-TuneupStartupRecommendation -Entry $companion -Rules $Rules).category | Should -Be 'companion-app'
    }

    It 'protects what lives in the folder of a product of Windows Security' {
        $entry = New-TestStartupEntry -Key 'VendorTray' -Path 'C:\Program Files\Vendor AV\bin\tray.exe'
        Get-TuneupStartupProtection -Entry $entry -Rules $Rules -SecurityFolder @('C:\Program Files\Vendor AV') | Should -Be 'security'
        Get-TuneupStartupProtection -Entry $entry -Rules $Rules -SecurityFolder @('C:\Program Files\Vendor') | Should -BeNullOrEmpty
    }

    It 'does not protect a game launcher, the browser itself or an unknown program, but protects the updater of Brave' {
        $brave = 'C:\Users\me\AppData\Local\BraveSoftware\Brave-Browser\Application\brave.exe'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'Steam' -Path 'C:\Games\Steam\steam.exe' -Publisher 'Valve Corp.') -Rules $Rules | Should -BeNullOrEmpty
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'BraveAutoLaunch_1' -Name 'Brave' -Path $brave) -Rules $Rules | Should -BeNullOrEmpty
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'BraveSoftware Update' -Name 'BraveSoftware Update' -Path $brave) -Rules $Rules | Should -Be 'updates'
        Get-TuneupStartupProtection -Entry (New-TestStartupEntry -Key 'Notes' -Path 'C:\Tools\notes.exe') -Rules $Rules | Should -BeNullOrEmpty
    }
}

Describe 'Get-TuneupStartupFixedReason' {
    It 'says why an entry cannot be turned off' {
        $protected = New-TestStartupEntry -Key 'x'
        $protected.protected = 'vpn'
        Get-TuneupStartupFixedReason -Entry $protected | Should -Be 'vpn'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'runonce-user' -Key 'Cleanup') | Should -Be 'run-once'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'task' -Key '\Vendor\Bad[1]') | Should -Be 'unsupported-name'
        Get-TuneupStartupFixedReason -Entry (New-TestStartupEntry -Source 'task' -Key '\Vendor\Good') | Should -BeNullOrEmpty
    }
}

Describe 'Get-TuneupStartupRecommendation' {
    It 'recommends <Name> as <Category>' -TestCases @(
        @{ Name = 'Steam'; Entry = { New-TestStartupEntry -Key 'Steam' -Path 'C:\Games\Steam\steam.exe' }; Category = 'game-launcher'; Winget = 'winget uninstall --id Valve.Steam --exact' }
        @{ Name = 'Epic Games'; Entry = { New-TestStartupEntry -Key 'EpicGamesLauncher' }; Category = 'game-launcher'; Winget = 'winget uninstall --id EpicGames.EpicGamesLauncher --exact' }
        @{ Name = 'Discord'; Entry = { New-TestStartupEntry -Source 'folder-user' -Key 'Discord.lnk' -Name 'Discord' -Path 'C:\Users\me\AppData\Local\Discord\Update.exe' }; Category = 'chat-helper'; Winget = 'winget uninstall --id Discord.Discord --exact' }
        @{ Name = 'Teams'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' -Name 'MSTeams' }; Category = 'chat-helper'; Winget = $null }
        @{ Name = 'Dropbox'; Entry = { New-TestStartupEntry -Key 'Dropbox' }; Category = 'sync-client'; Winget = 'winget uninstall --id Dropbox.Dropbox --exact' }
        @{ Name = 'OneDrive'; Entry = { New-TestStartupEntry -Key 'OneDrive' -Path 'C:\Users\me\AppData\Local\Microsoft\OneDrive\OneDrive.exe' }; Category = 'sync-client'; Winget = $null }
        @{ Name = 'the Adobe updater'; Entry = { New-TestStartupEntry -Source 'task' -Key '\Adobe Acrobat Update Task' -Name 'Adobe Acrobat Update Task' }; Category = 'updater'; Winget = $null }
        @{ Name = 'the new Outlook'; Entry = { New-TestStartupEntry -Source 'store-app' -Key 'Microsoft.OutlookForWindows_8wekyb3d8bbwe\OutlookStartup' -Name 'Outlook (new)' }; Category = 'chat-helper'; Winget = $null }
    ) {
        param($Entry, $Category, $Winget)
        $rule = Get-TuneupStartupRecommendation -Entry (& $Entry) -Rules $Rules
        $rule.category | Should -Be $Category
        Get-TuneupStartupUninstallCommand -Rule $rule | Should -Be $Winget
    }

    It 'marks OneDrive, Teams and Outlook as apps of work, and only them' {
        $workApps = @($Rules.recommend | Where-Object { $null -ne $_.PSObject.Properties['workApp'] -and $_.workApp })
        $workApps.Count | Should -Be 3
        foreach ($name in 'OneDrive', 'MSTeams', 'Outlook') {
            $rule = Get-TuneupStartupRecommendation -Entry (New-TestStartupEntry -Key $name) -Rules $Rules
            $rule.workApp | Should -BeTrue -Because $name
        }
        (Get-TuneupStartupRecommendation -Entry (New-TestStartupEntry -Key 'Dropbox') -Rules $Rules).PSObject.Properties['workApp'] | Should -BeNullOrEmpty
    }

    It 'recommends nothing for a program no rule names' {
        Get-TuneupStartupRecommendation -Entry (New-TestStartupEntry -Key 'Notes' -Path 'C:\Tools\notes.exe') -Rules $Rules | Should -BeNullOrEmpty
        Get-TuneupStartupUninstallCommand -Rule $null | Should -BeNullOrEmpty
    }
}
```

En `tests/Package.Tests.ps1`, reemplazar:

```powershell
            'actions/onedrive.ps1', 'docs/es/profiles.md', 'docs/en/catalog.md', 'docs/json-contract.md') {
```

por:

```powershell
            'actions/onedrive.ps1', 'docs/es/profiles.md', 'docs/en/catalog.md', 'docs/json-contract.md', 'catalog/startup/rules.json') {
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupRules.Tests.ps1`
Expected: FAIL (`Import-TuneupStartupRuleSet` no existe).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Package.Tests.ps1`
Expected: FAIL en `packs only what runs and what people read, under one folder` (`catalog/startup/rules.json` no está).

- [ ] **Step 3: Escribir las reglas**

Crear `catalog/startup/rules.json` (UTF-8 sin BOM). **Lo que está en el repositorio manda:** este bloque es el de la primera versión, con `bravem` ya corregido (decisión 27 y siguientes: `protectSigners`, más servicios de Windows, agentes de seguridad y de administración, actualizadores de Opera, Vivaldi y Yandex, lanzadores solo por su programa y la tarea de actualización de OneDrive con `workApp`).

```json
{
  "schemaVersion": 1,
  "about": "Rules of tuneup.ps1 -Startup (design, sections 15.4 and 15.5). Each pattern is a .NET regular expression, tried without case on the name of an entry, its publisher, the file name of its program and its key. protect: shown, never turned off. recommend: marked recommended, never turned off on its own; wingetId only gives the uninstall command that is shown, never run; workApp: not recommended on a work PC (managed or joined to Entra ID). Every rule says why. The first rule that matches wins, so the specific ones go first.",
  "windowsSigners": ["Microsoft Windows", "Microsoft Windows Publisher"],
  "hostPrograms": ["rundll32.exe", "regsvr32.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "wscript.exe", "cscript.exe", "mshta.exe", "conhost.exe", "explorer.exe", "msiexec.exe", "dllhost.exe"],
  "windowsServices": [
    "WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "wscsvc", "mpssvc", "BFE", "wuauserv", "UsoSvc", "WaaSMedicSvc", "BITS",
    "DoSvc", "InstallService", "AppXSvc", "ClipSVC", "wlidsvc", "TrustedInstaller", "CryptSvc", "SharedAccess", "LanmanServer",
    "LanmanWorkstation", "WerSvc", "DPS", "RmSvc", "WpnService", "webthreatdefsvc", "webthreatdefusersvc", "SysMain", "WSearch",
    "vmcompute", "vmms", "hns", "HvHost", "LxssManager", "WslService", "EventLog", "Schedule", "Winmgmt", "RpcSs", "sppsvc", "VSS",
    "swprv", "AppIDSvc", "Spooler", "MDCoreSvc"
  ],
  "protect": [
    { "category": "security", "pattern": "\\b(Microsoft Defender|Windows Defender|Windows Security|SecurityHealth\\w*|MsMpEng|MpDefenderCoreService|NisSrv|MsSense)\\b",
      "why": "Microsoft Defender and Windows Security: the protection of Windows itself (some of its programs live outside the folder of Windows)." },
    { "category": "security", "pattern": "\\b(Malwarebytes|ESET|Kaspersky|Bitdefender|Avast|AVG|Norton|NortonLifeLock|Gen Digital|McAfee|Sophos|Trend Micro|CrowdStrike|SentinelOne|Webroot|F-Secure|WithSecure|Panda Security|G DATA|Avira|Cylance|Carbon Black|Cisco Secure Endpoint|Emsisoft|Comodo|ZoneAlarm)\\b",
      "why": "Antivirus and endpoint protection of other publishers: turned off at startup, the PC starts unprotected." },
    { "category": "vpn", "pattern": "\\b(Cisco AnyConnect|Cisco Secure Client|GlobalProtect|PanGPA|PanGPS|Palo Alto Networks|FortiClient|Fortinet|OpenVPN|WireGuard|NordVPN|ExpressVPN|Proton ?VPN|Surfshark|Check Point|Zscaler|Pulse Secure|Ivanti|SonicWall|Tailscale|Cloudflare WARP)\\b",
      "why": "VPN clients: without them the PC cannot reach the network of the organization, or sends traffic outside the tunnel." },
    { "category": "device", "pattern": "\\b(RtkAudUService\\w*|RtkAudioService\\w*|Realtek Audio (Console|Universal Service|Service)|RAVCpl64|RAVBg64|WavesSvc\\w*|WavesSysSvc\\w*|MaxxAudio\\w*|Dolby DAX\\w*|DAX3API|CxAudioSvc|CxUtilSvc|Conexant SmartAudio)\\b",
      "why": "Control and enhancement services of the audio driver: without them jack detection, the microphone or the speaker tuning can stop working." },
    { "category": "device", "pattern": "\\b(SynTPEnh\\w*|SynTPHelper|Synaptics TouchPad Enhancements|ETDCtrl\\w*|ETDService|ETDTouch|ELAN Smart-Pad|ElanTouchpad\\w*|ApMsgFwd|Alps Pointing-device\\w*|HidMonitorSvc)\\b",
      "why": "Touchpad helpers of the driver: gestures, scrolling and palm rejection." },
    { "category": "device", "pattern": "\\b(HotKey\\w*|Hotkey Utility|HPHotkey\\w*|LenovoHotkeys\\w*|ATKOSD2|AsusOSD|HControlUser|Dell QuickSet\\w*|FnHotkey\\w*|Fn Key\\w*)\\b",
      "why": "Fn keys of laptops: brightness, volume, airplane mode, keyboard light and their on-screen indicators." },
    { "category": "device", "pattern": "\\b(NVDisplay\\.Container\\w*|NVIDIA Display Container LS|igfxCUIService\\w*|igfxEM|Intel\\(R\\) HD Graphics Control Panel Service|AMD External Events Utility|AUEPLauncher|WTabletServicePro|WTabletServiceCon|Wacom Professional Service|Wacom Consumer Service)\\b",
      "why": "Services of the display and pen drivers: display modes, color, hotplug and pen input. The companion apps of the same vendors are not here: they are recommend rules (companion-app)." },
    { "category": "updates", "pattern": "\\b(GoogleUpdate\\w*|Google Update\\w*|GoogleChromeElevationService|MicrosoftEdgeUpdate\\w*|Microsoft Edge Update\\w*|MicrosoftEdgeElevationService|MozillaMaintenance|Mozilla Maintenance Service|Firefox Background Update|BraveUpdate\\w*|Brave Update\\w*|BraveSoftware Update|BraveElevationService|ClickToRunSvc|OfficeClickToRun|Office Automatic Updates( 2\\.0)?|Microsoft Office Click-to-Run Service)\\b",
      "why": "Updaters of browsers and of Office: protected even though they are updaters, because without them the browser and Office get no security patches (the same principle as Windows Update in the blacklist)." },
    { "category": "updates", "pattern": "^(gupdatem?|edgeupdatem?|bravem)$",
      "why": "The same updaters by their service name; anchored, so the browser itself (brave.exe) is not taken for its updater. The first service of Brave is named just brave, which is also the name of the browser and its Run entry: it is protected by its display name (Brave Update Service), in the rule above." }
  ],
  "recommend": [
    { "category": "game-launcher", "pattern": "^steam(\\.exe)?$|^Valve\\b", "wingetId": "Valve.Steam",
      "why": "Steam opens at sign-in only to be ready; games start it when they need it. Anchored: steamwebhelper and other names with steam are not it." },
    { "category": "game-launcher", "pattern": "\\bEpicGamesLauncher\\b|\\bEpic Games\\b", "wingetId": "EpicGames.EpicGamesLauncher", "why": "Epic Games Launcher: a game launcher that waits in the background." },
    { "category": "game-launcher", "pattern": "\\bEADesktop\\b|^EA app$|\\bElectronic Arts\\b", "wingetId": "ElectronicArts.EADesktop", "why": "EA app: a game launcher that waits in the background." },
    { "category": "game-launcher", "pattern": "\\bBattle\\.net\\b|\\bBlizzard\\b", "wingetId": "Blizzard.BattleNet", "why": "Battle.net: a game launcher that waits in the background." },
    { "category": "game-launcher", "pattern": "\\bUbisoft\\b|^upc(\\.exe)?$", "wingetId": "Ubisoft.Connect", "why": "Ubisoft Connect: a game launcher that waits in the background." },
    { "category": "game-launcher", "pattern": "\\bGOG Galaxy\\b|\\bGalaxyClient\\b", "wingetId": "GOG.Galaxy", "why": "GOG Galaxy: a game launcher that waits in the background." },
    { "category": "game-launcher", "pattern": "\\bRiot Client\\b|\\bRiotClient\\w*", "why": "Riot Client: a game launcher that waits in the background (Vanguard, the anti-cheat driver, is a driver and stays)." },
    { "category": "sync-client", "pattern": "^OneDrive(\\.exe)?$", "workApp": true,
      "why": "OneDrive syncs files in the background; on a PC of an organization it usually keeps the work files, so it is not recommended there." },
    { "category": "sync-client", "pattern": "\\bDropbox\\b", "wingetId": "Dropbox.Dropbox", "why": "Dropbox syncs in the background; it can be opened when it is needed." },
    { "category": "sync-client", "pattern": "\\bGoogleDriveFS\\b|^Google Drive$", "wingetId": "Google.GoogleDrive", "why": "Google Drive syncs in the background; it can be opened when it is needed." },
    { "category": "sync-client", "pattern": "\\bMEGAsync\\b", "wingetId": "Mega.MEGASync", "why": "MEGAsync syncs in the background; it can be opened when it is needed." },
    { "category": "sync-client", "pattern": "\\biCloud\\w*", "why": "iCloud syncs in the background; it can be opened when it is needed." },
    { "category": "sync-client", "pattern": "\\bNextcloud\\b", "wingetId": "Nextcloud.NextcloudDesktop", "why": "Nextcloud syncs in the background; it can be opened when it is needed." },
    { "category": "chat-helper", "pattern": "\\bDiscord\\b", "wingetId": "Discord.Discord",
      "why": "Discord opens at sign-in through its Update.exe; this rule goes before updater so it is not taken for an updater." },
    { "category": "chat-helper", "pattern": "^MSTeams_|\\bMSTeams\\b|\\bTeams\\b", "workApp": true,
      "why": "Teams opens at sign-in; on a PC of an organization it is how people are reached for meetings, so it is not recommended there." },
    { "category": "chat-helper", "pattern": "^Microsoft\\.OutlookForWindows_|^olk(\\.exe)?$|\\bOutlook\\b", "workApp": true,
      "why": "The new Outlook can open at sign-in to check mail; on a PC of an organization it is the work mail, so it is not recommended there." },
    { "category": "chat-helper", "pattern": "\\bSkype\\b", "why": "Skype opens at sign-in to be reachable." },
    { "category": "chat-helper", "pattern": "\\bSlack\\b", "wingetId": "SlackTechnologies.Slack", "why": "Slack opens at sign-in to be reachable." },
    { "category": "chat-helper", "pattern": "\\bZoom\\b", "wingetId": "Zoom.Zoom", "why": "Zoom opens at sign-in; meetings start it when they need it." },
    { "category": "chat-helper", "pattern": "\\bTelegram\\b", "wingetId": "Telegram.TelegramDesktop", "why": "Telegram opens at sign-in to be reachable." },
    { "category": "chat-helper", "pattern": "\\bWhatsApp\\b", "why": "WhatsApp opens at sign-in to be reachable." },
    { "category": "companion-app", "pattern": "\\b(NVIDIA GeForce Experience|GeForce Experience|NVIDIA app|NVIDIA Share|nvsphelper64|NvBackend)\\b",
      "why": "NVIDIA companion apps: overlay, recording and driver downloads; the display driver works without them." },
    { "category": "companion-app", "pattern": "\\b(RadeonSoftware|Radeon Software|AMD Software|AMDRSServ|AMDRSSrcExt)\\b",
      "why": "AMD Software Adrenalin: overlay, recording and driver downloads; the display driver works without it." },
    { "category": "companion-app", "pattern": "\\b(Armoury ?Crate\\w*|ArmourySocketServer|AsusUpdateCheck|ROG Live Service|LightingService)\\b",
      "why": "ASUS Armoury Crate: lighting, profiles and its own updater; the Fn keys are ATKOSD2 and HControlUser, which stay." },
    { "category": "companion-app", "pattern": "\\b(LGHUB\\w*|Logitech G HUB|LogiOptionsPlus\\w*|Logi Options\\+?)\\b",
      "why": "Logitech G HUB and Options+: profiles, lighting and custom buttons; mice and keyboards work with their default buttons without them." },
    { "category": "companion-app", "pattern": "\\b(Razer Synapse\\w*|RazerCentral\\w*|Razer Central|Corsair iCUE\\w*|iCUE|SteelSeries ?GG|SteelSeriesGG\\w*)\\b",
      "why": "Razer Synapse, Corsair iCUE and SteelSeries GG: lighting, macros and their own updaters." },
    { "category": "companion-app", "pattern": "\\b(Intel Driver & Support Assistant|DSAService\\w*|DSATray|Intel Graphics Software|IntelGraphicsSoftware\\w*)\\b",
      "why": "Intel helpers: driver download checks and the graphics control panel; the drivers work without them." },
    { "category": "updater", "pattern": "updat(e|er|es)\\b|\\bjusched\\b|\\bAdobeARM\\b|\\bAGCInvokerUtility\\b",
      "why": "Updaters of other programs (Adobe, Java...): the program checks for updates when it opens. The last rule: anything more specific wins." }
  ]
}
```

Notas de las reglas (el porqué de cada una está en su `why`):
- `device` nombra programas y servicios de los controladores, nunca al fabricante: "NVIDIA" o "Realtek" sueltos protegerían también sus apps de acompañamiento, que van como `companion-app`.
- `updater` va al final: Discord arranca con `Update.exe --processStart Discord.exe` y tiene que quedar como `chat-helper`, y `AsusUpdateCheck`, como `companion-app`.
- Los `wingetId` no se comprobaron contra winget al escribir el plan: la lista de la VM (Task 16) lo hace con `winget show --id <id> --exact`.

- [ ] **Step 4: Implementar el cargador y las reglas**

Crear `engine/StartupRules.ps1`:

```powershell
# -Startup (design, sections 15.4 and 15.5): the rules that say which startup entries are protected and
# which are recommended. They are data, in catalog\startup\rules.json of the copy of the tool itself
# (-CatalogPath never changes them, so nobody can plant another list of what is protected), so a person
# can review them; this file loads them, checks them and applies them to one entry.

$script:StartupRulesPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog\startup\rules.json'
$script:StartupRuleCategories = [ordered]@{
    protect   = @('security', 'vpn', 'device', 'updates')
    recommend = @('updater', 'game-launcher', 'sync-client', 'chat-helper', 'companion-app')
}
# Every value of protected, in the order the checks give them.
$script:StartupProtections = @('policy', 'driver', 'windows-component') + $script:StartupRuleCategories.protect
$script:StartupWingetIdPattern = '^[A-Za-z0-9][A-Za-z0-9.+_-]*$'

# The problems of a set of rules; nothing when it is valid.
function Test-TuneupStartupRuleSet {
    param([Parameter(Mandatory)]$Rules)
    if ($Rules.schemaVersion -ne 1) { 'schemaVersion must be 1' }
    foreach ($field in 'windowsSigners', 'hostPrograms', 'windowsServices') {
        $values = @($Rules.$field | Where-Object { $null -ne $_ })
        if (-not $values.Count -or @($values | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) {
            "$field must be a list of names"
        }
    }
    foreach ($list in $script:StartupRuleCategories.Keys) {
        $categories = $script:StartupRuleCategories[$list]
        $items = @($Rules.$list | Where-Object { $null -ne $_ })
        if (-not $items.Count) { "$list has no rules" }
        foreach ($rule in $items) {
            $pattern = [string]$rule.pattern
            if ($categories -cnotcontains [string]$rule.category) { "$list rule '$pattern' has an unknown category '$($rule.category)'" }
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                "$list has a rule without a pattern"
                continue
            }
            try {
                [void][regex]::new($pattern)
            } catch {
                "$list rule '$pattern' is not a valid pattern: $($_.Exception.Message)"
            }
            # Why the rule is there, for whoever reviews the list (JSON has no comments).
            if ([string]::IsNullOrWhiteSpace([string]$rule.why)) { "$list rule '$pattern' has no why" }
            $workApp = $rule.PSObject.Properties['workApp']
            if ($null -ne $workApp) {
                if ($list -ne 'recommend') { "$list rule '$pattern' cannot have workApp" }
                elseif ($workApp.Value -isnot [bool]) { "$list rule '$pattern' workApp must be true or false" }
            }
            $winget = $rule.PSObject.Properties['wingetId']
            if ($null -eq $winget) { continue }
            if ($list -ne 'recommend') { "$list rule '$pattern' cannot have a wingetId" }
            elseif ([string]$winget.Value -cnotmatch $script:StartupWingetIdPattern) { "$list rule '$pattern' has an invalid wingetId '$($winget.Value)'" }
        }
    }
}

# The rules of the tool; rules with problems stop the command (a list of what is protected that cannot be
# read is never taken as "nothing is protected").
function Import-TuneupStartupRuleSet {
    param([string]$Path = $script:StartupRulesPath)
    $rules = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) | ConvertFrom-Json
    $problems = @(Test-TuneupStartupRuleSet -Rules $rules)
    if ($problems.Count) { throw "The startup rules $Path are not valid: $($problems -join '; ')" }
    $rules
}

# The texts a pattern is tried on: the name of the entry, its publisher, the file name of its program and
# its key (a value, file, task or service name).
function Get-TuneupStartupMatchText {
    param([Parameter(Mandatory)]$Entry)
    $file = $(if ($Entry.path) { [System.IO.Path]::GetFileName([string]$Entry.path) } else { $null })
    @([string]$Entry.name, [string]$Entry.publisher, [string]$file, [string]$Entry.key) | Where-Object { $_ }
}

# The first rule of the list whose pattern matches one of those texts, without case.
function Find-TuneupStartupRule {
    param([Parameter(Mandatory)]$Entry, [AllowEmptyCollection()][object[]]$Rules = @())
    $texts = @(Get-TuneupStartupMatchText -Entry $Entry)
    foreach ($rule in @($Rules | Where-Object { $null -ne $_ })) {
        foreach ($text in $texts) {
            if ([regex]::IsMatch($text, [string]$rule.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $rule }
        }
    }
}

# Why an entry must stay as it is, or nothing; the first check that holds gives the reason. -SecurityFolder:
# the folders of the products that Windows Security lists (antivirus, firewall).
function Get-TuneupStartupProtection {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)]$Rules, [AllowEmptyCollection()][string[]]$SecurityFolder = @())
    if ($Entry.policy) { return 'policy' }
    if ($Entry.source -eq 'driver') { return 'driver' }
    if ($Entry.publisher -and @($Rules.windowsSigners) -contains [string]$Entry.publisher) { return 'windows-component' }
    if (@('service', 'driver') -contains $Entry.source -and @($Rules.windowsServices) -contains [string]$Entry.key) { return 'windows-component' }
    $windowsPart = $(if ($null -ne $Entry.target) { $Entry.target.PSObject.Properties['WindowsPart'] } else { $null })
    if ($null -ne $windowsPart -and $windowsPart.Value) { return 'windows-component' }
    if ($Entry.path) {
        $folder = (Split-Path -Path ([string]$Entry.path) -Parent).TrimEnd('\') + '\'
        foreach ($product in @($SecurityFolder | Where-Object { $_ })) {
            if ($folder.StartsWith(([string]$product).TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return 'security' }
        }
    }
    $rule = Find-TuneupStartupRule -Entry $Entry -Rules @($Rules.protect)
    if ($null -ne $rule) { return [string]$rule.category }
}

# Why an entry cannot be turned off, or nothing: its protection, a run-once entry (Windows deletes it once
# it ran; turning it off would mean deleting it), or a task whose name or folder holds a wildcard character
# (the task handler looks tasks up with PowerShell wildcards and could not be sure it found that one).
function Get-TuneupStartupFixedReason {
    param([Parameter(Mandatory)]$Entry)
    if ($Entry.protected) { return [string]$Entry.protected }
    if ([string]$Entry.source -like 'runonce*') { return 'run-once' }
    if ($Entry.source -eq 'task' -and [string]$Entry.key -match '[*?\[\]]') { return 'unsupported-name' }
}

# The recommend rule that names an entry, or nothing. Only a mark: nothing is turned off for it.
function Get-TuneupStartupRecommendation {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)]$Rules)
    Find-TuneupStartupRule -Entry $Entry -Rules @($Rules.recommend)
}

# The command that would uninstall what a rule recommends turning off, to show and never to run; nothing
# when the rule has no winget id.
function Get-TuneupStartupUninstallCommand {
    param([AllowNull()]$Rule)
    if ($null -eq $Rule) { return }
    $winget = $Rule.PSObject.Properties['wingetId']
    if ($null -ne $winget -and [string]$winget.Value -cmatch $script:StartupWingetIdPattern) { "winget uninstall --id $($winget.Value) --exact" }
}
```

- [ ] **Step 5: Sumar las reglas al zip**

En `build/package.ps1`, reemplazar:

```powershell
    '^i18n/[^/]+\.json$', '^catalog/[^/]+\.json$', '^profiles/[^/]+\.json$', '^actions/[^/]+\.ps1$',
```

por:

```powershell
    '^i18n/[^/]+\.json$', '^catalog/[^/]+\.json$', '^catalog/startup/[^/]+\.json$', '^profiles/[^/]+\.json$', '^actions/[^/]+\.ps1$',
```

Y en el comentario de ayuda del principio, reemplazar:

```powershell
    windows-tuneup-<version>.zip holds what runs (tuneup.ps1, engine, i18n, catalog, profiles,
```

por:

```powershell
    windows-tuneup-<version>.zip holds what runs (tuneup.ps1, engine, i18n, catalog with the startup rules, profiles,
```

- [ ] **Step 6: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupRules.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Package.Tests.ps1`
Expected: PASS (`catalog/notes/` sigue fuera).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Repo.Tests.ps1`
Expected: PASS (el JSON nuevo se lee).

- [ ] **Step 7: Commit**

```bash
git add catalog/startup/rules.json engine/StartupRules.ps1 build/package.ps1 tests/StartupRules.Tests.ps1 tests/Package.Tests.ps1
git commit -m "feat(arranque): reglas revisables de lo protegido y lo recomendado, dentro del zip"
git log -1 --format=%s
```

---

### Task 3: Textos de `-Startup` en los dos idiomas

**Files:**
- Modify: `i18n/es.json`, `i18n/en.json`
- Test: `tests/Startup.Tests.ps1`

Todas las claves de las tareas siguientes llegan aquí, juntas: `tests/I18n.Tests.ps1` exige las mismas claves y marcadores en los dos idiomas, y las claves que el código arma con una variable las cubre la prueba de este paso.

- [ ] **Step 1: Escribir la prueba que falla**

Agregar al final de `tests/Startup.Tests.ps1`:

```powershell
Describe 'Startup texts' {
    It 'has a text in es and en for every source, protection, reason, recommendation and kind of change' {
        $module = Get-Module Tuneup
        $keys = @(& $module { $script:StartupSources.Keys } | ForEach-Object { "startup.source.$_" }) +
            @(& $module { $script:StartupProtections } | ForEach-Object { "startup.protected.$_" }) +
            @('run-once', 'unsupported-name' | ForEach-Object { "startup.fixed.$_" }) +
            @(& $module { $script:StartupRuleCategories.recommend } | ForEach-Object { "startup.recommend.$_" }) +
            @('registry', 'store', 'task', 'service' | ForEach-Object { "startup.why.$_" }) +
            @('startup.notRecommended.work-app', 'transcript.request.startup', 'reapply.startupEntry')
        $keys.Count | Should -BeGreaterThan 30
        foreach ($lang in 'es', 'en') {
            $json = Get-Content -LiteralPath (Join-Path $I18nRoot "$lang.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in $keys) { [string]::IsNullOrWhiteSpace([string]$json.$key) | Should -BeFalse -Because "$lang $key" }
        }
    }
}
```

- [ ] **Step 2: Correr la prueba y ver que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: FAIL en `Startup texts` (`es startup.source.run-user`).

- [ ] **Step 3: Agregar los textos**

En `i18n/es.json`, reemplazar:

```json
  "reason.unchanged": "ya estaba como antes: no había nada que restaurar"
}
```

por:

```json
  "reason.unchanged": "ya estaba como antes: no había nada que restaurar",
  "startup.header": "Lo que arranca con Windows o queda en segundo plano ({0}):",
  "startup.entry": "  {0} {1}{2} - {3} - {4}{5}",
  "startup.publisher": " ({0})",
  "startup.id": "      id: {0}",
  "startup.state.on": "[encendido]",
  "startup.state.off": "[apagado]",
  "startup.state.protected": "[protegido: {0}]",
  "startup.state.fixed": "[no se apaga: {0}]",
  "startup.usage.running": "en ejecución, {0} MB",
  "startup.usage.runningNoMemory": "en ejecución",
  "startup.usage.stopped": "no está en ejecución",
  "startup.usage.unknown": "no se sabe si está en ejecución",
  "startup.recommended": "      Se recomienda apagarlo: {0}.",
  "startup.uninstall": "      Para desinstalarlo (la herramienta no lo hace): {0}",
  "startup.howTo": "Para apagar lo que elijas: .\\tuneup.ps1 -Startup -Disable '<id>,<id>'. Nada se desinstala ni se borra, y -Undo lo vuelve a encender.",
  "startup.empty": "No se encontró nada que arranque con Windows.",
  "startup.unelevatedNote": "Sin administrador, Windows oculta algunas tareas programadas: corre -Startup como administrador para verlas todas.",
  "startup.nextStart": "Los cambios rigen desde el próximo inicio de Windows o de sesión; lo que ya está abierto sigue abierto hasta que lo cierres.",
  "startup.offer": "¿Revisamos lo que arranca con Windows? .\\tuneup.ps1 -Startup muestra la lista y lo recomendado; no se apaga nada que no elijas.",
  "startup.refusedLine": "{0} ({1}): {2}",
  "startup.source.run-user": "al iniciar sesión (Run del usuario)",
  "startup.source.run-machine": "al iniciar sesión, para todos los usuarios (Run)",
  "startup.source.run32-machine": "al iniciar sesión, para todos los usuarios (Run de 32 bits)",
  "startup.source.runonce-user": "una vez, en el próximo inicio de sesión (RunOnce del usuario)",
  "startup.source.runonce-machine": "una vez, en el próximo inicio de sesión (RunOnce)",
  "startup.source.runonce32-machine": "una vez, en el próximo inicio de sesión (RunOnce de 32 bits)",
  "startup.source.policy-user": "al iniciar sesión, por una directiva del usuario",
  "startup.source.policy-machine": "al iniciar sesión, por una directiva del equipo",
  "startup.source.folder-user": "carpeta Inicio del usuario",
  "startup.source.folder-machine": "carpeta Inicio de todos los usuarios",
  "startup.source.store-app": "app de la Microsoft Store que arranca con Windows",
  "startup.source.task": "tarea programada al iniciar sesión o al arrancar",
  "startup.source.service": "servicio que arranca solo",
  "startup.source.driver": "controlador que arranca solo",
  "startup.protected.policy": "lo fija una directiva",
  "startup.protected.driver": "controlador",
  "startup.protected.windows-component": "componente de Windows",
  "startup.protected.security": "seguridad (antivirus o firewall)",
  "startup.protected.vpn": "VPN",
  "startup.protected.device": "software de un dispositivo (audio, teclado, panel táctil, gráficos)",
  "startup.protected.updates": "actualizaciones de seguridad del navegador o de Office",
  "startup.fixed.run-once": "corre una sola vez y Windows lo borra",
  "startup.fixed.unsupported-name": "su nombre tiene caracteres comodín y no se puede buscar con exactitud",
  "startup.recommend.updater": "actualizador en segundo plano",
  "startup.recommend.game-launcher": "lanzador de juegos",
  "startup.recommend.sync-client": "cliente de sincronización de archivos",
  "startup.recommend.chat-helper": "chat o correo que se abre al iniciar",
  "startup.recommend.companion-app": "app de acompañamiento del fabricante (overlay, iluminación, descargas de controladores); el controlador funciona sin ella",
  "startup.notRecommended": "      No se recomienda apagarlo: {0}.",
  "startup.notRecommended.work-app": "en un equipo de trabajo se usa para trabajar (archivos, reuniones o correo); igual puedes apagarlo",
  "startup.why.registry": "Arranca con Windows: {0}. Se apaga como lo hace el Administrador de tareas, sin borrar la entrada.",
  "startup.why.store": "Arranca con Windows: {0}. Se apaga como en Configuración > Aplicaciones > Inicio.",
  "startup.why.task": "Corre al iniciar: {0}. La tarea se deshabilita; no se borra.",
  "startup.why.service": "Arranca solo: {0}. Pasa a Manual (arranca cuando un programa lo pide); nunca se deshabilita.",
  "err.startupUnknown": "No está entre lo que arranca con Windows ahora: {0}. Mira la lista con -Startup (un servicio que ya pasó a Manual deja de aparecer). No se hizo nada.",
  "err.startupFixed": "Esto no se apaga, así que no se hizo nada:",
  "err.startupSessionUser": "{0}: es de la cuenta que inició sesión en este escritorio, y este proceso corre como otra cuenta de administrador. Apágalo sin elevar desde esa cuenta. No se hizo nada.",
  "reapply.startupEntry": "{0} arranca otra vez con Windows: no se vuelve a aplicar solo. Míralo con -Startup y apágalo con -Startup -Disable.",
  "transcript.request.startup": "Pedido: apagar lo que arranca con Windows ({1})",
  "menu.main.startup": " 6. Lo que arranca con Windows: verlo y apagar lo que elijas",
  "menu.startup.header": "Elige lo que quieres apagar (no hay nada marcado de antemano; lo recomendado va primero):",
  "menu.startup.recommended": " [recomendado: {0}]",
  "menu.startup.needsAdmin": "Algo de lo elegido arranca para todos los usuarios: abre PowerShell como administrador para apagarlo. No se cambió nada.",
  "menu.startup.none": "No hay nada que arranque con Windows que se pueda apagar desde aquí."
}
```

En `i18n/en.json`, reemplazar:

```json
  "reason.unchanged": "it was already as before: there was nothing to restore"
}
```

por:

```json
  "reason.unchanged": "it was already as before: there was nothing to restore",
  "startup.header": "What starts with Windows or runs in the background ({0}):",
  "startup.entry": "  {0} {1}{2} - {3} - {4}{5}",
  "startup.publisher": " ({0})",
  "startup.id": "      id: {0}",
  "startup.state.on": "[on]",
  "startup.state.off": "[off]",
  "startup.state.protected": "[protected: {0}]",
  "startup.state.fixed": "[stays on: {0}]",
  "startup.usage.running": "running, {0} MB",
  "startup.usage.runningNoMemory": "running",
  "startup.usage.stopped": "not running",
  "startup.usage.unknown": "not known whether it runs",
  "startup.recommended": "      Turning it off is recommended: {0}.",
  "startup.uninstall": "      To uninstall it (the tool does not): {0}",
  "startup.howTo": "To turn off what you choose: .\\tuneup.ps1 -Startup -Disable '<id>,<id>'. Nothing is uninstalled or deleted, and -Undo turns it on again.",
  "startup.empty": "Nothing that starts with Windows was found.",
  "startup.unelevatedNote": "Without administrator, Windows hides some scheduled tasks: run -Startup as administrator to see them all.",
  "startup.nextStart": "The changes take effect the next time Windows or your session starts; what is already open stays open until you close it.",
  "startup.offer": "Do we review what starts with Windows? .\\tuneup.ps1 -Startup shows the list and what is recommended; nothing is turned off unless you choose it.",
  "startup.refusedLine": "{0} ({1}): {2}",
  "startup.source.run-user": "at sign-in (Run of the user)",
  "startup.source.run-machine": "at sign-in, for every user (Run)",
  "startup.source.run32-machine": "at sign-in, for every user (32-bit Run)",
  "startup.source.runonce-user": "once, at the next sign-in (RunOnce of the user)",
  "startup.source.runonce-machine": "once, at the next sign-in (RunOnce)",
  "startup.source.runonce32-machine": "once, at the next sign-in (32-bit RunOnce)",
  "startup.source.policy-user": "at sign-in, by a policy of the user",
  "startup.source.policy-machine": "at sign-in, by a policy of the machine",
  "startup.source.folder-user": "Startup folder of the user",
  "startup.source.folder-machine": "Startup folder of every user",
  "startup.source.store-app": "Microsoft Store app that starts with Windows",
  "startup.source.task": "scheduled task at sign-in or at boot",
  "startup.source.service": "service that starts on its own",
  "startup.source.driver": "driver that starts on its own",
  "startup.protected.policy": "a policy sets it",
  "startup.protected.driver": "driver",
  "startup.protected.windows-component": "part of Windows",
  "startup.protected.security": "security (antivirus or firewall)",
  "startup.protected.vpn": "VPN",
  "startup.protected.device": "software of a device (audio, keyboard, touchpad, graphics)",
  "startup.protected.updates": "security updates of the browser or of Office",
  "startup.fixed.run-once": "it runs only once and Windows deletes it",
  "startup.fixed.unsupported-name": "its name has wildcard characters and cannot be looked up exactly",
  "startup.recommend.updater": "updater in the background",
  "startup.recommend.game-launcher": "game launcher",
  "startup.recommend.sync-client": "file sync client",
  "startup.recommend.chat-helper": "chat or mail that opens at start",
  "startup.recommend.companion-app": "companion app of the vendor (overlay, lighting, driver downloads); the driver works without it",
  "startup.notRecommended": "      Turning it off is not recommended: {0}.",
  "startup.notRecommended.work-app": "on a work PC it is used for work (files, meetings or mail); you can still turn it off",
  "startup.why.registry": "Starts with Windows: {0}. Turned off the way Task Manager does, without deleting the entry.",
  "startup.why.store": "Starts with Windows: {0}. Turned off as in Settings > Apps > Startup.",
  "startup.why.task": "Runs at start: {0}. The task is disabled; it is not deleted.",
  "startup.why.service": "Starts on its own: {0}. Set to Manual (it starts when a program asks for it); never disabled.",
  "err.startupUnknown": "Not among what starts with Windows now: {0}. See the list with -Startup (a service already set to Manual is no longer listed). Nothing was done.",
  "err.startupFixed": "These are never turned off, so nothing was done:",
  "err.startupSessionUser": "{0}: it belongs to the account signed in at this desktop, and this process runs as another administrator account. Turn it off without elevation from that account. Nothing was done.",
  "reapply.startupEntry": "{0} starts with Windows again: it is not applied again on its own. See it with -Startup and turn it off with -Startup -Disable.",
  "transcript.request.startup": "Asked for: turn off what starts with Windows ({1})",
  "menu.main.startup": " 6. What starts with Windows: see it and turn off what you choose",
  "menu.startup.header": "Pick what to turn off (nothing is picked for you; the recommended ones come first):",
  "menu.startup.recommended": " [recommended: {0}]",
  "menu.startup.needsAdmin": "Something you picked starts for every user: open PowerShell as administrator to turn it off. Nothing was changed.",
  "menu.startup.none": "Nothing that starts with Windows can be turned off from here."
}
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18n.Tests.ps1`
Expected: PASS (mismas claves y marcadores en los dos idiomas).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Repo.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add i18n/es.json i18n/en.json tests/Startup.Tests.ps1
git commit -m "feat(arranque): textos en español e inglés de la lista de arranque"
git log -1 --format=%s
```

---

### Task 4: Un detector por fuente

**Files:**
- Modify: `engine/Startup.ps1` (al final)
- Test: `tests/Startup.Tests.ps1`

Cada detector lee una fuente y no decide nada: devuelve objetos simples, así las pruebas de la Task 5 los simulan. Uno que no puede leer lanza; quien lo llama lo convierte en un aviso (`Invoke-TuneupDetector`).

- [ ] **Step 1: Escribir las pruebas que fallan**

Agregar al final de `tests/Startup.Tests.ps1`:

```powershell
Describe 'Startup detectors' {
    BeforeEach { Remove-TestKey }
    AfterAll { Remove-TestKey }

    It 'reads the values of a Run key as they are written, and nothing for a key that is not there' {
        New-Item -Path "$Key\Run" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Run" -Name 'Steam' -Value '"%ProgramFiles%\Steam\steam.exe" -silent' -PropertyType ExpandString | Out-Null
        $values = @(Get-TuneupStartupRunValue -Path "$Key\Run")
        $values.Count | Should -Be 1
        $values[0].Name | Should -Be 'Steam'
        $values[0].Command | Should -Be '"%ProgramFiles%\Steam\steam.exe" -silent'
        @(Get-TuneupStartupRunValue -Path "$Key\Missing").Count | Should -Be 0
    }

    It 'reads the binary StartupApproved values by name, in any case' {
        New-Item -Path "$Key\Approved" -Force | Out-Null
        New-ItemProperty -LiteralPath "$Key\Approved" -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)) -PropertyType Binary | Out-Null
        New-ItemProperty -LiteralPath "$Key\Approved" -Name 'Text' -Value 'x' -PropertyType String | Out-Null
        $values = Get-TuneupStartupApprovedValue -Path "$Key\Approved"
        @($values.Keys).Count | Should -Be 1
        $values['STEAM'][0] | Should -Be 3
        $values['STEAM'].Length | Should -Be 12
        (Get-TuneupStartupApprovedValue -Path "$Key\Missing").Count | Should -Be 0
    }

    It 'lists the files of a startup folder, without desktop.ini or folders' {
        $folder = Join-Path $TestDrive 'Startup'
        New-Item -ItemType Directory -Path (Join-Path $folder 'Sub') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $folder 'Tool.lnk'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $folder 'desktop.ini'), 'x')
        $items = @(Get-TuneupStartupFolderItem -Path $folder)
        @($items | ForEach-Object { $_.Name }) -join ',' | Should -Be 'Tool.lnk'
        $items[0].FullName | Should -Be (Join-Path $folder 'Tool.lnk')
        @(Get-TuneupStartupFolderItem -Path (Join-Path $TestDrive 'Nowhere')).Count | Should -Be 0
        @(Get-TuneupStartupFolderItem -Path '').Count | Should -Be 0
    }

    It 'reads where a shortcut points without changing it' {
        $link = Join-Path $TestDrive 'Notepad.lnk'
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($link)
            $shortcut.TargetPath = Join-Path ([Environment]::SystemDirectory) 'notepad.exe'
            $shortcut.Arguments = '/x'
            $shortcut.Save()
        } finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
        $before = (Get-Item -LiteralPath $link).LastWriteTimeUtc
        $target = Get-TuneupShortcutTarget -Path $link
        $target.Target | Should -Be (Join-Path ([Environment]::SystemDirectory) 'notepad.exe')
        $target.Arguments | Should -Be '/x'
        (Get-Item -LiteralPath $link).LastWriteTimeUtc | Should -Be $before
    }

    It 'reads the State of the startup tasks of Store apps, and only keys that have one' {
        $root = "$Key\SystemAppData"
        New-Item -Path "$root\Vendor.App_abc\StartAtLogon" -Force | Out-Null
        New-ItemProperty -LiteralPath "$root\Vendor.App_abc\StartAtLogon" -Name 'State' -Value 2 -PropertyType DWord | Out-Null
        New-Item -Path "$root\Vendor.App_abc\Schemas" -Force | Out-Null
        $tasks = @(Get-TuneupStartupStoreTask -Root $root)
        $tasks.Count | Should -Be 1
        $tasks[0].PackageFamilyName | Should -Be 'Vendor.App_abc'
        $tasks[0].TaskId | Should -Be 'StartAtLogon'
        $tasks[0].State | Should -Be 2
        $tasks[0].KeyPath | Should -Be "$root\Vendor.App_abc\StartAtLogon"
        @(Get-TuneupStartupStoreTask -Root "$Key\Missing").Count | Should -Be 0
    }

    It 'reads the startup tasks that a package manifest declares' {
        $manifest = Join-Path $TestDrive 'AppxManifest.xml'
        [System.IO.File]::WriteAllText($manifest, @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap5="http://schemas.microsoft.com/appx/manifest/uap/windows10/5"
         xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10">
  <Applications>
    <Application Id="App">
      <Extensions>
        <uap5:Extension Category="windows.startupTask">
          <uap5:StartupTask TaskId="TaskOne" Enabled="true" DisplayName="Sample One" />
        </uap5:Extension>
        <desktop:Extension Category="windows.startupTask" Executable="x.exe" EntryPoint="Windows.FullTrustApplication">
          <desktop:StartupTask TaskId="TaskTwo" Enabled="false" DisplayName="ms-resource:Name" />
        </desktop:Extension>
        <desktop:Extension Category="windows.fullTrustProcess" Executable="y.exe" />
      </Extensions>
    </Application>
  </Applications>
</Package>
'@)
        $tasks = @(Get-TuneupAppxManifestStartupTask -Path $manifest)
        @($tasks | ForEach-Object { $_.TaskId }) -join ',' | Should -Be 'TaskOne,TaskTwo'
        $tasks[0].DisplayName | Should -Be 'Sample One'
        @(Get-TuneupAppxManifestStartupTask -Path (Join-Path $TestDrive 'none.xml')).Count | Should -Be 0
    }

    It 'reads the Store packages of the current user' {
        Mock -ModuleName Tuneup Get-AppxPackage {
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; Name = 'MSTeams'; Publisher = 'CN=Microsoft Corporation'; InstallLocation = 'C:\Apps\Teams'; SignatureKind = 'Store' }
        }
        $packages = @(Get-TuneupStartupPackage)
        $packages[0].PackageFamilyName | Should -Be 'MSTeams_8wekyb3d8bbwe'
        $packages[0].SignatureKind | Should -Be 'Store'
    }

    It 'keeps only the tasks outside \Microsoft\ that start at sign-in or at boot' {
        Mock -ModuleName Tuneup Get-ScheduledTask {
            $logon = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' } }
            $boot = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskBootTrigger' } }
            $daily = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskDailyTrigger' } }
            $exec = [pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskExecAction' }; Execute = '"C:\Vendor\up.exe"'; Arguments = '/silent' }
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'VendorUpdate'; State = 'Ready'; Triggers = @($daily, $logon); Actions = @($exec) }
            [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Boot'; State = 'Disabled'; Triggers = @($boot); Actions = @() }
            [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Daily'; State = 'Ready'; Triggers = @($daily); Actions = @($exec) }
            [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Defrag\'; TaskName = 'ScheduledDefrag'; State = 'Ready'; Triggers = @($logon); Actions = @($exec) }
        }
        $tasks = @(Get-TuneupStartupScheduledTask)
        @($tasks | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }) -join ',' | Should -Be '\VendorUpdate,\Vendor\Boot'
        $tasks[0].Execute | Should -Be '"C:\Vendor\up.exe"'
        $tasks[0].Arguments | Should -Be '/silent'
        $tasks[1].State | Should -Be 'Disabled'
        $tasks[1].Execute | Should -BeNullOrEmpty
    }

    It 'reads the services and the drivers that start on their own' {
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ Name = 'VendorSvc'; DisplayName = 'Vendor Service'; PathName = '"C:\Vendor\svc.exe"'; State = 'Running'; ProcessId = 77; DelayedAutoStart = $true }
        } -ParameterFilter { $ClassName -eq 'Win32_Service' -and $Filter -eq "StartMode = 'Auto'" }
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ Name = 'vendordrv'; DisplayName = 'Vendor Driver'; PathName = 'C:\WINDOWS\system32\drivers\vendordrv.sys'; State = 'Running' }
        } -ParameterFilter { $ClassName -eq 'Win32_SystemDriver' -and $Filter -eq "StartMode = 'Auto'" }
        $items = @(Get-TuneupStartupServiceItem)
        @($items | ForEach-Object { "$($_.Kind):$($_.Name)" }) -join ',' | Should -Be 'service:VendorSvc,driver:vendordrv'
        $items[0].DelayedAutoStart | Should -BeTrue
        $items[0].ProcessId | Should -Be 77
        $items[1].ProcessId | Should -Be 0
    }

    It 'reads the folders of the products that Windows Security lists, from their paths only' {
        Mock -ModuleName Tuneup Get-CimInstance {
            [pscustomobject]@{ pathToSignedProductExe = 'windowsdefender://'; pathToSignedReportingExe = '%ProgramFiles%\Vendor AV\report.exe' }
        } -ParameterFilter { $Namespace -eq 'root/SecurityCenter2' -and $ClassName -eq 'AntiVirusProduct' }
        @(Get-TuneupSecurityProductFolder -ClassName 'AntiVirusProduct') -join ',' | Should -Be "$([Environment]::GetFolderPath('ProgramFiles'))\Vendor AV"
    }

    It 'reads who signed a file, only from a valid signature, and remembers it' {
        $file = Join-Path $TestDrive 'signed.exe'
        [System.IO.File]::WriteAllText($file, 'x')
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Vendor Inc., O=Vendor' } } }
        Get-TuneupFileSigner -Path $file | Should -Be 'Vendor Inc.'
        Get-TuneupFileSigner -Path $file | Should -Be 'Vendor Inc.'
        Should -Invoke -ModuleName Tuneup Get-AuthenticodeSignature -Times 1 -Exactly
        Clear-TuneupFileSignerCache
        Mock -ModuleName Tuneup Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Vendor Inc.' } } }
        Get-TuneupFileSigner -Path $file | Should -BeNullOrEmpty
        Get-TuneupFileSigner -Path (Join-Path $TestDrive 'missing.exe') | Should -BeNullOrEmpty
        Clear-TuneupFileSignerCache
    }

    It 'reads the running processes, leaving unknown what Windows does not tell' {
        Mock -ModuleName Tuneup Get-Process {
            [pscustomobject]@{ Id = 10; Path = 'C:\Games\Steam\steam.exe'; WorkingSet64 = 200MB; TotalProcessorTime = [timespan]::FromSeconds(10.04) }
            [pscustomobject]@{ Id = 4; Path = $null; WorkingSet64 = 1MB; TotalProcessorTime = $null }
        }
        $processes = @(Get-TuneupStartupProcess)
        $processes[0].Path | Should -Be 'C:\Games\Steam\steam.exe'
        $processes[0].WorkingSet | Should -Be 200MB
        $processes[0].CpuSeconds | Should -Be 10.04
        $processes[1].Path | Should -BeNullOrEmpty
        $processes[1].CpuSeconds | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: FAIL en `Startup detectors` (`Get-TuneupStartupRunValue` no existe).

- [ ] **Step 3: Implementar**

Agregar al final de `engine/Startup.ps1`:

```powershell
$script:StoreTaskRoot = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
$script:SecurityCenterClasses = @('AntiVirusProduct', 'FirewallProduct')
$script:StartupSignerCache = @{}

# The values of a Run key, name and command as they are written (not expanded). A key that does not exist
# gives nothing; one that exists but cannot be read fails.
function Get-TuneupStartupRunValue {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    try {
        foreach ($name in $key.GetValueNames()) {
            # The default value of the key is not an entry.
            if (-not $name) { continue }
            [pscustomobject]@{ Name = $name; Command = [string]$key.GetValue($name, $null, 'DoNotExpandEnvironmentNames') }
        }
    } finally {
        $key.Close()
    }
}

# The binary values of a StartupApproved key, by name (a table that does not tell case apart, like the
# registry). An empty table when the key does not exist.
function Get-TuneupStartupApprovedValue {
    param([Parameter(Mandatory)][string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    try {
        foreach ($name in $key.GetValueNames()) {
            if ($name -and $key.GetValueKind($name) -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $values[$name] = [byte[]]$key.GetValue($name) }
        }
    } finally {
        $key.Close()
    }
    $values
}

# The files of a startup folder (desktop.ini and subfolders are not entries). Nothing when the folder does
# not exist.
function Get-TuneupStartupFolderItem {
    param([AllowEmptyString()][string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction Stop)) {
        if ($file.Name -ieq 'desktop.ini') { continue }
        [pscustomobject]@{ Name = $file.Name; FullName = $file.FullName }
    }
}

# Where a shortcut points and with which arguments. CreateShortcut only reads the file: nothing is saved.
function Get-TuneupShortcutTarget {
    param([Parameter(Mandatory)][string]$Path)
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($Path)
        [pscustomobject]@{ Target = [string]$link.TargetPath; Arguments = [string]$link.Arguments }
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

# The keys of SystemAppData\<package family>\<task> that hold a State: what Windows keeps for the startup
# tasks of Store apps (StartupTaskState). Whether a key is really a startup task is decided against the
# manifest of the package (Get-TuneupStartupStoreEntry).
function Get-TuneupStartupStoreTask {
    param([string]$Root = $script:StoreTaskRoot)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    foreach ($package in @(Get-ChildItem -LiteralPath $Root -ErrorAction Stop)) {
        foreach ($task in @(Get-ChildItem -LiteralPath $package.PSPath -ErrorAction Stop)) {
            $state = $task.GetValue('State')
            if ($null -eq $state) { continue }
            [pscustomobject]@{
                PackageFamilyName = $package.PSChildName
                TaskId            = $task.PSChildName
                State             = [int]$state
                KeyPath           = "$Root\$($package.PSChildName)\$($task.PSChildName)"
            }
        }
    }
}

# The Store packages of the current user, with what -Startup needs of them.
function Get-TuneupStartupPackage {
    foreach ($package in @(Get-AppxPackage -ErrorAction Stop)) {
        [pscustomobject]@{
            PackageFamilyName = [string]$package.PackageFamilyName
            Name              = [string]$package.Name
            Publisher         = [string]$package.Publisher
            InstallLocation   = [string]$package.InstallLocation
            SignatureKind     = [string]$package.SignatureKind
        }
    }
}

# The startup tasks (Extension windows.startupTask) that a package manifest declares. The document is
# loaded without resolving anything outside it.
function Get-TuneupAppxManifestStartupTask {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.Load($Path)
    foreach ($node in @($xml.SelectNodes("//*[local-name()='Extension'][@Category='windows.startupTask']/*[local-name()='StartupTask']"))) {
        [pscustomobject]@{ TaskId = $node.GetAttribute('TaskId'); DisplayName = $node.GetAttribute('DisplayName') }
    }
}

# The scheduled tasks outside \Microsoft\ with a sign-in or boot trigger, and the program of their first
# action. Without elevation Windows hides some tasks.
function Get-TuneupStartupScheduledTask {
    foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
        if ([string]$task.TaskPath -like '\Microsoft\*') { continue }
        $triggers = @($task.Triggers | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.CimClass.CimClassName })
        if (-not @($triggers | Where-Object { $_ -eq 'MSFT_TaskLogonTrigger' -or $_ -eq 'MSFT_TaskBootTrigger' }).Count) { continue }
        $action = @($task.Actions | Where-Object { $null -ne $_ -and [string]$_.CimClass.CimClassName -eq 'MSFT_TaskExecAction' }) | Select-Object -First 1
        [pscustomobject]@{
            TaskPath  = [string]$task.TaskPath
            TaskName  = [string]$task.TaskName
            State     = [string]$task.State
            Execute   = $(if ($null -ne $action) { [string]$action.Execute } else { $null })
            Arguments = $(if ($null -ne $action) { [string]$action.Arguments } else { $null })
        }
    }
}

# The services and the drivers whose start mode is Auto (delayed included).
function Get-TuneupStartupServiceItem {
    foreach ($service in @(Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto'" -ErrorAction Stop)) {
        [pscustomobject]@{
            Kind = 'service'; Name = [string]$service.Name; DisplayName = [string]$service.DisplayName; PathName = [string]$service.PathName
            State = [string]$service.State; ProcessId = [int]$service.ProcessId; DelayedAutoStart = [bool]$service.DelayedAutoStart
        }
    }
    foreach ($driver in @(Get-CimInstance -ClassName Win32_SystemDriver -Filter "StartMode = 'Auto'" -ErrorAction Stop)) {
        [pscustomobject]@{
            Kind = 'driver'; Name = [string]$driver.Name; DisplayName = [string]$driver.DisplayName; PathName = [string]$driver.PathName
            State = [string]$driver.State; ProcessId = 0; DelayedAutoStart = $false
        }
    }
}

# The folders of the products of one class that Windows Security lists (its paths only: Defender gives a
# windowsdefender:// link). Windows Server has no Security Center: that fails, and the caller warns.
function Get-TuneupSecurityProductFolder {
    param([Parameter(Mandatory)][string]$ClassName)
    foreach ($product in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName $ClassName -ErrorAction Stop)) {
        foreach ($path in @($product.pathToSignedProductExe, $product.pathToSignedReportingExe)) {
            $expanded = Expand-TuneupStartupPath -Text ([string]$path)
            if ($expanded -match '^[A-Za-z]:\\') { Split-Path -Path $expanded -Parent }
        }
    }
}

function Clear-TuneupFileSignerCache {
    $script:StartupSignerCache = @{}
}

# Who signed a file (the CN of its Authenticode signer, catalog signatures included), only when the
# signature is valid; nothing otherwise or when the file is not there. Each file is read once per list.
function Get-TuneupFileSigner {
    param([Parameter(Mandatory)][string]$Path)
    if ($script:StartupSignerCache.ContainsKey($Path)) { return $script:StartupSignerCache[$Path] }
    $signer = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ([string]$signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate) {
            $signer = Get-TuneupCommonName -DistinguishedName ([string]$signature.SignerCertificate.Subject)
        }
    }
    $script:StartupSignerCache[$Path] = $signer
    $signer
}

# The running processes. Windows keeps the path and the times of some processes (other accounts, protected
# ones) from a process that is not elevated: those stay unknown, never guessed.
function Get-TuneupStartupProcess {
    foreach ($process in @(Get-Process -ErrorAction Stop)) {
        $path = $null
        try { $path = [string]$process.Path } catch { $path = $null }
        $cpu = $null
        try {
            if ($null -ne $process.TotalProcessorTime) { $cpu = [double]$process.TotalProcessorTime.TotalSeconds }
        } catch {
            $cpu = $null
        }
        [pscustomobject]@{ Id = [int]$process.Id; Path = $(if ($path) { $path } else { $null }); WorkingSet = [int64]$process.WorkingSet64; CpuSeconds = $cpu }
    }
}
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings` (los `catch` de `Get-TuneupStartupProcess` asignan `$null`: un resultado explícito, no un error tragado).

- [ ] **Step 5: Commit**

```bash
git add engine/Startup.ps1 tests/Startup.Tests.ps1
git commit -m "feat(arranque): un detector simulable por cada fuente de lo que arranca con Windows"
git log -1 --format=%s
```

---

### Task 5: La lista de entradas

**Files:**
- Modify: `engine/Startup.ps1` (al final)
- Test: `tests/Startup.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

Agregar al final de `tests/Startup.Tests.ps1`:

```powershell
Describe 'Get-TuneupStartupEntry' {
    BeforeAll {
        $script:Rules = Import-TuneupStartupRuleSet
        $script:UserRun = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $script:MachineRun = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        function Get-TestEntry { @(Get-TuneupStartupEntry -Rules $Rules 3>$null) }
        function Find-TestEntry($Entries, [string]$Name) { @($Entries | Where-Object { $_.name -eq $Name })[0] }
    }

    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { }
        Mock -ModuleName Tuneup Get-TuneupStartupApprovedValue { @{} }
        Mock -ModuleName Tuneup Get-TuneupStartupFolderItem { }
        Mock -ModuleName Tuneup Get-TuneupShortcutTarget { $null }
        Mock -ModuleName Tuneup Get-TuneupStartupStoreTask { }
        Mock -ModuleName Tuneup Get-TuneupStartupPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { }
        Mock -ModuleName Tuneup Get-TuneupStartupScheduledTask { }
        Mock -ModuleName Tuneup Get-TuneupStartupServiceItem { }
        Mock -ModuleName Tuneup Get-TuneupSecurityProductFolder { }
        Mock -ModuleName Tuneup Get-TuneupFileSigner { $null }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { }
    }

    It 'lists the Run entries with their state, publisher, use and recommendation' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Steam'; Command = '"C:\Games\Steam\steam.exe" -silent' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue {
            [pscustomobject]@{ Name = 'SecurityHealth'; Command = '%windir%\system32\SecurityHealthSystray.exe' }
            [pscustomobject]@{ Name = 'OldTool'; Command = 'C:\Tools\old.exe' }
        } -ParameterFilter { $Path -eq $MachineRun }
        Mock -ModuleName Tuneup Get-TuneupStartupApprovedValue { @{ OldTool = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8) } } -ParameterFilter { $Path -like 'HKLM:*\StartupApproved\Run' }
        Mock -ModuleName Tuneup Get-TuneupFileSigner { 'Valve Corp.' } -ParameterFilter { $Path -eq 'C:\Games\Steam\steam.exe' }
        Mock -ModuleName Tuneup Get-TuneupFileSigner { 'Microsoft Windows' } -ParameterFilter { $Path -like '*\SecurityHealthSystray.exe' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess {
            [pscustomobject]@{ Id = 100; Path = 'C:\Games\Steam\steam.exe'; WorkingSet = 200MB; CpuSeconds = 10.04 }
            [pscustomobject]@{ Id = 101; Path = 'C:\GAMES\Steam\steam.exe'; WorkingSet = 20MB; CpuSeconds = $null }
        }
        $entries = Get-TestEntry
        $steam = Find-TestEntry $entries 'Steam'
        $steam.id | Should -BeExactly 'startup.run-user.steam-eb4bc901'
        $steam.source | Should -Be 'run-user'
        $steam.enabled | Should -BeTrue
        $steam.publisher | Should -Be 'Valve Corp.'
        $steam.running | Should -BeTrue
        $steam.memoryMB | Should -Be 220
        $steam.cpuSeconds | Should -Be 10
        $steam.canDisable | Should -BeTrue
        $steam.needsAdmin | Should -BeFalse
        $steam.recommended | Should -BeTrue
        $steam.recommendedReason | Should -Be 'game-launcher'
        $steam.uninstall | Should -Be 'winget uninstall --id Valve.Steam --exact'
        $steam.target.ApprovedPath | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        $steam.target.ApprovedName | Should -Be 'Steam'
        $security = Find-TestEntry $entries 'SecurityHealth'
        $security.protected | Should -Be 'windows-component'
        $security.canDisable | Should -BeFalse
        $security.recommended | Should -BeFalse
        $security.needsAdmin | Should -BeTrue
        $security.running | Should -BeFalse
        $old = Find-TestEntry $entries 'OldTool'
        $old.enabled | Should -BeFalse
        $old.canDisable | Should -BeFalse
        $old.protected | Should -BeNullOrEmpty
        $old.target.ApprovedValue[0] | Should -Be 3
    }

    It 'shows run-once and policy entries as entries that stay on' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Cleanup'; Command = 'C:\Tools\cleanup.exe' } } -ParameterFilter { $Path -like 'HKCU:*\RunOnce' }
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Agent'; Command = 'C:\Corp\agent.exe' } } -ParameterFilter { $Path -like 'HKLM:*\Policies\Explorer\Run' }
        $entries = Get-TestEntry
        $cleanup = Find-TestEntry $entries 'Cleanup'
        $cleanup.source | Should -Be 'runonce-user'
        $cleanup.canDisable | Should -BeFalse
        Get-TuneupStartupFixedReason -Entry $cleanup | Should -Be 'run-once'
        $agent = Find-TestEntry $entries 'Agent'
        $agent.source | Should -Be 'policy-machine'
        $agent.protected | Should -Be 'policy'
        $agent.canDisable | Should -BeFalse
    }

    It 'lists a shortcut of the startup folder by where it points' {
        $folder = [Environment]::GetFolderPath('Startup')
        Mock -ModuleName Tuneup Get-TuneupStartupFolderItem { [pscustomobject]@{ Name = 'Discord.lnk'; FullName = "$folder\Discord.lnk" } } -ParameterFilter { $Path -eq $folder }
        Mock -ModuleName Tuneup Get-TuneupShortcutTarget { [pscustomobject]@{ Target = 'C:\Users\me\AppData\Local\Discord\Update.exe'; Arguments = '--processStart Discord.exe' } }
        $discord = Find-TestEntry (Get-TestEntry) 'Discord'
        $discord.source | Should -Be 'folder-user'
        $discord.key | Should -Be 'Discord.lnk'
        $discord.path | Should -Be 'C:\Users\me\AppData\Local\Discord\Update.exe'
        $discord.command | Should -Be '"C:\Users\me\AppData\Local\Discord\Update.exe" --processStart Discord.exe'
        $discord.recommendedReason | Should -Be 'chat-helper'
        $discord.uninstall | Should -Be 'winget uninstall --id Discord.Discord --exact'
        $discord.target.ApprovedPath | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        $discord.target.ApprovedName | Should -Be 'Discord.lnk'
    }

    It 'lists the startup tasks of Store apps that their manifest declares' {
        $root = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
        Mock -ModuleName Tuneup Get-TuneupStartupStoreTask {
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; TaskId = 'TeamsTfwStartupTask'; State = 2; KeyPath = "$root\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask" }
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; TaskId = 'NotATask'; State = 2; KeyPath = "$root\MSTeams_8wekyb3d8bbwe\NotATask" }
            [pscustomobject]@{ PackageFamilyName = 'Windows.Part_cw5n1h2txyewy'; TaskId = 'Start'; State = 2; KeyPath = "$root\Windows.Part_cw5n1h2txyewy\Start" }
            [pscustomobject]@{ PackageFamilyName = 'Corp.App_x'; TaskId = 'Start'; State = 4; KeyPath = "$root\Corp.App_x\Start" }
        }
        Mock -ModuleName Tuneup Get-TuneupStartupPackage {
            [pscustomobject]@{ PackageFamilyName = 'MSTeams_8wekyb3d8bbwe'; Name = 'MSTeams'; Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation'; InstallLocation = 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe'; SignatureKind = 'Store' }
            [pscustomobject]@{ PackageFamilyName = 'Windows.Part_cw5n1h2txyewy'; Name = 'Windows.Part'; Publisher = 'CN=Microsoft Windows'; InstallLocation = 'C:\Windows\SystemApps\Part'; SignatureKind = 'System' }
            [pscustomobject]@{ PackageFamilyName = 'Corp.App_x'; Name = 'Corp.App'; Publisher = 'CN=Corp'; InstallLocation = 'C:\Program Files\WindowsApps\Corp'; SignatureKind = 'Developer' }
        }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { [pscustomobject]@{ TaskId = 'TeamsTfwStartupTask'; DisplayName = 'ms-resource:StartupTaskName' } } -ParameterFilter { $Path -like '*MSTeams*' }
        Mock -ModuleName Tuneup Get-TuneupAppxManifestStartupTask { [pscustomobject]@{ TaskId = 'Start'; DisplayName = 'Start' } } -ParameterFilter { $Path -notlike '*MSTeams*' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { [pscustomobject]@{ Id = 300; Path = 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe\ms-teams.exe'; WorkingSet = 150MB; CpuSeconds = 2 } }
        $entries = @(Get-TestEntry | Where-Object { $_.source -eq 'store-app' })
        $entries.Count | Should -Be 3
        $teams = Find-TestEntry $entries 'MSTeams'
        $teams.key | Should -Be 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask'
        $teams.publisher | Should -Be 'Microsoft Corporation'
        $teams.enabled | Should -BeTrue
        $teams.running | Should -BeTrue
        $teams.memoryMB | Should -Be 150
        $teams.recommendedReason | Should -Be 'chat-helper'
        $teams.uninstall | Should -BeNullOrEmpty
        $teams.target.StoreKeyPath | Should -Be "$root\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask"
        $teams.target.StoreState | Should -Be 2
        (@($entries | Where-Object { $_.key -like 'Windows.Part*' })[0]).protected | Should -Be 'windows-component'
        $corp = @($entries | Where-Object { $_.key -like 'Corp.App*' })[0]
        $corp.protected | Should -Be 'policy'
        $corp.enabled | Should -BeTrue
        # A manifest is read once per package.
        Should -Invoke -ModuleName Tuneup Get-TuneupAppxManifestStartupTask -Times 1 -Exactly -ParameterFilter { $Path -like '*MSTeams*' }
    }

    It 'lists tasks and services of other publishers and leaves out the services of Windows' {
        Mock -ModuleName Tuneup Get-TuneupStartupScheduledTask {
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'GoogleUpdateTaskMachineCore'; State = 'Ready'; Execute = 'C:\Program Files (x86)\Google\Update\GoogleUpdate.exe'; Arguments = '/c' }
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'Adobe Acrobat Update Task'; State = 'Running'; Execute = '"C:\Program Files (x86)\Common Files\Adobe\ARM\1.0\AdobeARM.exe"'; Arguments = $null }
            [pscustomobject]@{ TaskPath = '\Vendor\'; TaskName = 'Bad[1]'; State = 'Ready'; Execute = 'C:\Vendor\bad.exe'; Arguments = $null }
        }
        Mock -ModuleName Tuneup Get-TuneupStartupServiceItem {
            [pscustomobject]@{ Kind = 'service'; Name = 'Dnscache'; DisplayName = 'DNS Client'; PathName = 'C:\WINDOWS\system32\svchost.exe -k NetworkService'; State = 'Running'; ProcessId = 5; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'PanGPS'; DisplayName = 'PanGPS'; PathName = '"C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe"'; State = 'Running'; ProcessId = 4242; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'service'; Name = 'VendorSvc'; DisplayName = 'Vendor Service'; PathName = '"C:\Vendor\svc.exe" -run'; State = 'Running'; ProcessId = 77; DelayedAutoStart = $true }
            [pscustomobject]@{ Kind = 'service'; Name = 'StoppedSvc'; DisplayName = 'Stopped Service'; PathName = 'C:\Vendor\stopped.exe'; State = 'Stopped'; ProcessId = 0; DelayedAutoStart = $false }
            [pscustomobject]@{ Kind = 'driver'; Name = 'vendordrv'; DisplayName = 'Vendor Driver'; PathName = '\SystemRoot\System32\drivers\vendordrv.sys'; State = 'Running'; ProcessId = 0; DelayedAutoStart = $false }
        }
        Mock -ModuleName Tuneup Get-TuneupFileSigner { 'Microsoft Windows' } -ParameterFilter { $Path -like '*\svchost.exe' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess {
            [pscustomobject]@{ Id = 4242; Path = 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe'; WorkingSet = 50MB; CpuSeconds = 3.25 }
            [pscustomobject]@{ Id = 77; Path = $null; WorkingSet = 10MB; CpuSeconds = 1 }
            [pscustomobject]@{ Id = 9; Path = 'C:\Vendor\stopped.exe'; WorkingSet = 5MB; CpuSeconds = 1 }
        }
        $entries = Get-TestEntry
        @($entries | Where-Object { $_.key -eq 'Dnscache' }).Count | Should -Be 0
        (Find-TestEntry $entries 'GoogleUpdateTaskMachineCore').protected | Should -Be 'updates'
        $adobe = Find-TestEntry $entries 'Adobe Acrobat Update Task'
        $adobe.recommendedReason | Should -Be 'updater'
        $adobe.running | Should -BeTrue
        $adobe.target.TaskPath | Should -Be '\'
        $adobe.target.TaskName | Should -Be 'Adobe Acrobat Update Task'
        $bad = Find-TestEntry $entries 'Bad[1]'
        $bad.canDisable | Should -BeFalse
        $bad.protected | Should -BeNullOrEmpty
        $vpn = Find-TestEntry $entries 'PanGPS'
        $vpn.protected | Should -Be 'vpn'
        $vpn.memoryMB | Should -Be 50
        $vendor = Find-TestEntry $entries 'Vendor Service'
        $vendor.canDisable | Should -BeTrue
        $vendor.running | Should -BeTrue
        $vendor.memoryMB | Should -Be 10
        $vendor.target.ServiceName | Should -Be 'VendorSvc'
        $vendor.target.StartType | Should -Be 'AutomaticDelayed'
        # A stopped service is matched by its process id only, never by the path of another process.
        $stopped = Find-TestEntry $entries 'Stopped Service'
        $stopped.running | Should -BeFalse
        $stopped.memoryMB | Should -BeNullOrEmpty
        (Find-TestEntry $entries 'Vendor Driver').protected | Should -Be 'driver'
    }

    It 'protects what lives in the folder of a product of Windows Security' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'VendorTray'; Command = '"C:\Program Files\Vendor AV\tray.exe"' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupSecurityProductFolder { 'C:\Program Files\Vendor AV' } -ParameterFilter { $ClassName -eq 'AntiVirusProduct' }
        (Find-TestEntry (Get-TestEntry) 'VendorTray').protected | Should -Be 'security'
    }

    It 'gives a hosted program no publisher and no use of its own' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Helper'; Command = 'rundll32.exe "C:\X\x.dll",Start' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { [pscustomobject]@{ Id = 5; Path = (Join-Path ([Environment]::SystemDirectory) 'rundll32.exe'); WorkingSet = 5MB; CpuSeconds = 1 } }
        $helper = Find-TestEntry (Get-TestEntry) 'Helper'
        $helper.publisher | Should -BeNullOrEmpty
        $helper.protected | Should -BeNullOrEmpty
        $helper.running | Should -BeNullOrEmpty
        $helper.canDisable | Should -BeTrue
        Should -Invoke -ModuleName Tuneup Get-TuneupFileSigner -Times 0 -ParameterFilter { $Path -like '*rundll32.exe' }
    }

    It 'does not recommend the apps of work on a work PC, but leaves them to choose' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue {
            [pscustomobject]@{ Name = 'OneDrive'; Command = '"C:\Users\me\AppData\Local\Microsoft\OneDrive\OneDrive.exe" /background' }
            [pscustomobject]@{ Name = 'Steam'; Command = 'C:\Games\Steam\steam.exe' }
        } -ParameterFilter { $Path -eq $UserRun }
        $atWork = @(Get-TuneupStartupEntry -Rules $Rules -WorkPc $true 3>$null)
        $oneDrive = Find-TestEntry $atWork 'OneDrive'
        $oneDrive.canDisable | Should -BeTrue
        $oneDrive.recommended | Should -BeFalse
        $oneDrive.recommendedReason | Should -BeNullOrEmpty
        $oneDrive.notRecommendedReason | Should -Be 'work-app'
        (Find-TestEntry $atWork 'Steam').recommended | Should -BeTrue
        $personal = Find-TestEntry (Get-TestEntry) 'OneDrive'
        $personal.recommendedReason | Should -Be 'sync-client'
        $personal.notRecommendedReason | Should -BeNullOrEmpty
    }

    It 'keeps listing when a source fails, with a warning, and leaves the use unknown without the processes' {
        Mock -ModuleName Tuneup Get-TuneupStartupRunValue { [pscustomobject]@{ Name = 'Steam'; Command = 'C:\Games\Steam\steam.exe' } } -ParameterFilter { $Path -eq $UserRun }
        Mock -ModuleName Tuneup Get-TuneupStartupScheduledTask { throw 'Access denied' }
        Mock -ModuleName Tuneup Get-TuneupStartupProcess { throw 'Access denied' }
        $output = @(Get-TuneupStartupEntry -Rules $Rules 3>&1)
        $warned = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
        $steam = Find-TestEntry @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }) 'Steam'
        $steam.running | Should -BeNullOrEmpty
        $steam.memoryMB | Should -BeNullOrEmpty
        @($warned | Where-Object { $_ -like 'Could not check the scheduled tasks*Access denied*' }).Count | Should -Be 1
        @($warned | Where-Object { $_ -like 'Could not check the running programs*' }).Count | Should -Be 1
    }
}

Describe 'Test-TuneupStartupWorkPc' {
    It 'is a work PC when managed or joined to Entra ID, and not otherwise' {
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment -IsManaged $true) | Should -BeTrue
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment) | Should -BeFalse
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $true }
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment) | Should -BeTrue
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { throw 'Access denied' }
        Test-TuneupStartupWorkPc -Environment (New-TestEnvironment) 3>$null | Should -BeFalse
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: FAIL en `Get-TuneupStartupEntry` y `Test-TuneupStartupWorkPc` (no existen).

- [ ] **Step 3: Implementar**

Agregar al final de `engine/Startup.ps1`:

```powershell
$script:StartupFolders = @(
    [pscustomobject]@{ Source = 'folder-user'; Folder = 'Startup' }
    [pscustomobject]@{ Source = 'folder-machine'; Folder = 'CommonStartup' }
)

# The StartupApproved values of a key, or an empty table when they cannot be read (the detector warns).
function Read-TuneupStartupApprovedSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $read = Invoke-TuneupDetector -What "the startup choices of Task Manager in $Path" -Detector { Get-TuneupStartupApprovedValue -Path $Path }
    if ($read.Ok -and $read.Value -is [hashtable]) { return $read.Value }
    @{}
}

# The values of the Run, RunOnce and policy Run keys, with whether Task Manager turned them off.
function Get-TuneupStartupRunEntry {
    [CmdletBinding()]
    param()
    foreach ($run in $script:StartupRunKeys) {
        $values = Invoke-TuneupDetector -What "the startup key $($run.Path)" -Detector { Get-TuneupStartupRunValue -Path $run.Path }
        if (-not $values.Ok) { continue }
        $approvedPath = $script:StartupSources[$run.Source].Approved
        $approved = $(if ($approvedPath) { Read-TuneupStartupApprovedSet -Path $approvedPath } else { @{} })
        foreach ($value in @($values.Value | Where-Object { $null -ne $_ })) {
            $bytes = $null
            if ($approved.ContainsKey($value.Name)) { $bytes = $approved[$value.Name] }
            New-TuneupStartupEntry -Source $run.Source -Key $value.Name -Name $value.Name -Command $value.Command `
                -Path (Get-TuneupCommandProgram -Command $value.Command) -Enabled (Test-TuneupStartupApprovedEnabled -Value $bytes) `
                -Policy ($run.Source -like 'policy-*') -Target @{ ApprovedPath = $approvedPath; ApprovedName = [string]$value.Name; ApprovedValue = $bytes }
        }
    }
}

# The files of the startup folders (a shortcut by where it points), with whether Task Manager turned them off.
function Get-TuneupStartupFolderEntry {
    [CmdletBinding()]
    param()
    foreach ($folder in $script:StartupFolders) {
        $path = [Environment]::GetFolderPath($folder.Folder)
        if (-not $path) { continue }
        $items = Invoke-TuneupDetector -What "the startup folder $path" -Detector { Get-TuneupStartupFolderItem -Path $path }
        if (-not $items.Ok) { continue }
        $approvedPath = $script:StartupSources[$folder.Source].Approved
        $approved = Read-TuneupStartupApprovedSet -Path $approvedPath
        foreach ($item in @($items.Value | Where-Object { $null -ne $_ })) {
            $program = [string]$item.FullName
            $command = [string]$item.FullName
            if ([System.IO.Path]::GetExtension([string]$item.Name) -ieq '.lnk') {
                $link = Invoke-TuneupDetector -What "the shortcut $($item.Name)" -Detector { Get-TuneupShortcutTarget -Path $item.FullName }
                if ($link.Ok -and $null -ne $link.Value -and $link.Value.Target) {
                    $program = Expand-TuneupStartupPath -Text ([string]$link.Value.Target)
                    $command = ('"{0}" {1}' -f $program, [string]$link.Value.Arguments).Trim()
                }
            }
            $bytes = $null
            if ($approved.ContainsKey($item.Name)) { $bytes = $approved[$item.Name] }
            New-TuneupStartupEntry -Source $folder.Source -Key ([string]$item.Name) -Name ([System.IO.Path]::GetFileNameWithoutExtension([string]$item.Name)) `
                -Command $command -Path $program -Enabled (Test-TuneupStartupApprovedEnabled -Value $bytes) `
                -Target @{ ApprovedPath = $approvedPath; ApprovedName = [string]$item.Name; ApprovedValue = $bytes }
        }
    }
}

# The startup tasks of the Store apps of the user: only the keys whose task the manifest of the package
# declares (each manifest is read once). State 2 and 4 are on; 3 and 4 come from a policy.
function Get-TuneupStartupStoreEntry {
    [CmdletBinding()]
    param()
    $tasks = Invoke-TuneupDetector -What 'the startup tasks of Store apps' -Detector { Get-TuneupStartupStoreTask }
    if (-not $tasks.Ok -or -not @($tasks.Value | Where-Object { $null -ne $_ }).Count) { return }
    $packages = Invoke-TuneupDetector -What 'the Store apps of this user' -Detector { Get-TuneupStartupPackage }
    if (-not $packages.Ok) { return }
    $byFamily = @{}
    foreach ($package in @($packages.Value | Where-Object { $null -ne $_ })) { $byFamily[$package.PackageFamilyName] = $package }
    $declared = @{}
    foreach ($task in @($tasks.Value | Where-Object { $null -ne $_ })) {
        $package = $byFamily[$task.PackageFamilyName]
        if ($null -eq $package -or -not $package.InstallLocation) { continue }
        if (-not $declared.ContainsKey($task.PackageFamilyName)) {
            $manifest = Join-Path $package.InstallLocation 'AppxManifest.xml'
            $read = Invoke-TuneupDetector -What "the manifest of $($package.Name)" -Detector { Get-TuneupAppxManifestStartupTask -Path $manifest }
            $declared[$task.PackageFamilyName] = @(if ($read.Ok) { $read.Value | Where-Object { $null -ne $_ } })
        }
        $startupTask = @($declared[$task.PackageFamilyName] | Where-Object { $_.TaskId -eq $task.TaskId }) | Select-Object -First 1
        if ($null -eq $startupTask) { continue }
        $name = $(if ($startupTask.DisplayName -and $startupTask.DisplayName -notlike 'ms-resource:*') { [string]$startupTask.DisplayName } else { [string]$package.Name })
        $entry = New-TuneupStartupEntry -Source 'store-app' -Key "$($task.PackageFamilyName)\$($task.TaskId)" -Name $name `
            -Enabled (@(2, 4) -contains $task.State) -Policy (@(3, 4) -contains $task.State) `
            -Target @{ StoreKeyPath = [string]$task.KeyPath; StoreState = [int]$task.State; InstallLocation = [string]$package.InstallLocation; WindowsPart = ($package.SignatureKind -eq 'System') }
        $entry.publisher = Get-TuneupCommonName -DistinguishedName $package.Publisher
        $entry
    }
}

# The scheduled tasks that start at sign-in or at boot.
function Get-TuneupStartupTaskEntry {
    [CmdletBinding()]
    param()
    $tasks = Invoke-TuneupDetector -What 'the scheduled tasks' -Detector { Get-TuneupStartupScheduledTask }
    if (-not $tasks.Ok) { return }
    foreach ($task in @($tasks.Value | Where-Object { $null -ne $_ })) {
        $command = ('{0} {1}' -f [string]$task.Execute, [string]$task.Arguments).Trim()
        $entry = New-TuneupStartupEntry -Source 'task' -Key "$($task.TaskPath)$($task.TaskName)" -Name ([string]$task.TaskName) -Command $command `
            -Path (Get-TuneupCommandProgram -Command $task.Execute) -Enabled ($task.State -ne 'Disabled') `
            -Target @{ TaskPath = [string]$task.TaskPath; TaskName = [string]$task.TaskName }
        if ($task.State -eq 'Running') { $entry.running = $true }
        $entry
    }
}

# The services and drivers that start on their own, but not the ones of Windows (signed by Windows): they
# are not something that a program of another publisher added.
function Get-TuneupStartupServiceEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Rules)
    $services = Invoke-TuneupDetector -What 'the services and drivers that start on their own' -Detector { Get-TuneupStartupServiceItem }
    if (-not $services.Ok) { return }
    foreach ($service in @($services.Value | Where-Object { $null -ne $_ })) {
        $program = Get-TuneupCommandProgram -Command $service.PathName
        $hosted = $program -and @($Rules.hostPrograms) -contains [System.IO.Path]::GetFileName($program)
        $signer = $null
        if ($program -and -not $hosted) { $signer = (Invoke-TuneupDetector -What "the signature of $program" -Detector { Get-TuneupFileSigner -Path $program }).Value }
        if ($signer -and @($Rules.windowsSigners) -contains $signer) { continue }
        $name = $(if ($service.DisplayName) { [string]$service.DisplayName } else { [string]$service.Name })
        $startType = $(if ($service.DelayedAutoStart) { 'AutomaticDelayed' } else { 'Automatic' })
        $entry = New-TuneupStartupEntry -Source $service.Kind -Key ([string]$service.Name) -Name $name -Command $service.PathName -Path $program `
            -Target @{ ServiceName = [string]$service.Name; StartType = $startType; ProcessId = [int]$service.ProcessId }
        $entry.publisher = $signer
        $entry.running = ([string]$service.State -eq 'Running')
        $entry
    }
}

# Memory and CPU of what runs: the process of a service by its id (only that one), the processes of a
# Store app by its folder, any other program by its path. Nothing is matched for a hosted program.
function Set-TuneupStartupUsage {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Process)
    $target = $Entry.target
    $mine = @()
    if ($null -ne $target -and $null -ne $target.PSObject.Properties['ProcessId']) {
        if ($target.ProcessId) { $mine = @($Process | Where-Object { $_.Id -eq $target.ProcessId }) }
    } elseif ($null -ne $target -and $null -ne $target.PSObject.Properties['InstallLocation'] -and $target.InstallLocation) {
        $prefix = ([string]$target.InstallLocation).TrimEnd('\') + '\'
        $mine = @($Process | Where-Object { $_.Path -and ([string]$_.Path).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
    } elseif ($Entry.path) {
        $mine = @($Process | Where-Object { $_.Path -and [string]$_.Path -ieq [string]$Entry.path })
    }
    if (-not $mine.Count) {
        if ($null -eq $Entry.running) { $Entry.running = $false }
        return
    }
    $Entry.running = $true
    $Entry.memoryMB = [int][math]::Round([double](($mine | Measure-Object -Property WorkingSet -Sum).Sum) / 1MB)
    $cpu = @($mine | Where-Object { $null -ne $_.CpuSeconds })
    if ($cpu.Count) { $Entry.cpuSeconds = [math]::Round([double](($cpu | Measure-Object -Property CpuSeconds -Sum).Sum), 1) }
}

# Publisher, protection, whether it can be turned off, recommendation and use of one entry. A hosted
# program (rundll32, cmd, powershell...) has no publisher or use of its own: they would be the ones of
# Windows. -Process is null when the processes could not be read: running stays as it is (unknown).
function Complete-TuneupStartupEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)]$Rules,
        [AllowEmptyCollection()][string[]]$SecurityFolder = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$Process,
        # A work PC (managed, or joined to Entra ID): the apps of work (workApp) are not recommended there.
        [bool]$WorkPc = $false
    )
    $program = [string]$Entry.path
    $hosted = $program -and @($Rules.hostPrograms) -contains [System.IO.Path]::GetFileName($program)
    if ($null -eq $Entry.publisher -and $program -and -not $hosted) {
        $Entry.publisher = (Invoke-TuneupDetector -What "the signature of $program" -Detector { Get-TuneupFileSigner -Path $program }).Value
    }
    $Entry.protected = Get-TuneupStartupProtection -Entry $Entry -Rules $Rules -SecurityFolder $SecurityFolder
    $Entry.canDisable = [bool]$Entry.enabled -and -not (Get-TuneupStartupFixedReason -Entry $Entry)
    if ($Entry.canDisable) {
        $rule = Get-TuneupStartupRecommendation -Entry $Entry -Rules $Rules
        $workApp = $(if ($null -ne $rule) { $rule.PSObject.Properties['workApp'] } else { $null })
        if ($null -ne $rule -and $WorkPc -and $null -ne $workApp -and $workApp.Value -eq $true) {
            # It can still be turned off; the reason lets people (and the skill) say why it is not recommended.
            $Entry.notRecommendedReason = 'work-app'
        } elseif ($null -ne $rule) {
            $Entry.recommended = $true
            $Entry.recommendedReason = [string]$rule.category
            $Entry.uninstall = Get-TuneupStartupUninstallCommand -Rule $rule
        }
    }
    if ($null -ne $Process -and -not $hosted) { Set-TuneupStartupUsage -Entry $Entry -Process $Process }
}

# Everything that starts with Windows or runs in the background, in the order of the sources. A source
# that cannot be read is a warning and the rest is still listed. -WorkPc: see Test-TuneupStartupWorkPc.
function Get-TuneupStartupEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Rules, [bool]$WorkPc = $false)
    Clear-TuneupFileSignerCache
    $entries = @(Get-TuneupStartupRunEntry) + @(Get-TuneupStartupFolderEntry) + @(Get-TuneupStartupStoreEntry) +
        @(Get-TuneupStartupTaskEntry) + @(Get-TuneupStartupServiceEntry -Rules $Rules)
    $processes = Invoke-TuneupDetector -What 'the running programs' -Detector { Get-TuneupStartupProcess }
    $running = $null
    if ($processes.Ok) { $running = @($processes.Value | Where-Object { $null -ne $_ }) }
    $securityFolders = @(foreach ($class in $script:SecurityCenterClasses) {
            (Invoke-TuneupDetector -What "the $class products of Windows Security" -Detector { Get-TuneupSecurityProductFolder -ClassName $class }).Value
        })
    $securityFolders = @($securityFolders | Where-Object { $_ })
    foreach ($entry in @($entries | Where-Object { $null -ne $_ })) {
        Complete-TuneupStartupEntry -Entry $entry -Rules $Rules -SecurityFolder $securityFolders -Process $running -WorkPc $WorkPc
        $entry
    }
}

# A work PC, where OneDrive, Teams and Outlook are not recommended: managed (domain or MDM, which the
# environment of the command already holds) or joined to Entra ID (one registry read), the same rule as the
# work signal of -Suggest. A join that cannot be read is a warning and counts as no join.
function Test-TuneupStartupWorkPc {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Environment)
    if ($Environment.IsManaged) { return $true }
    $entra = Invoke-TuneupDetector -What 'the Entra ID join' -Detector { Test-TuneupEntraJoined }
    [bool]($entra.Ok -and $entra.Value -eq $true)
}
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 5: Commit**

```bash
git add engine/Startup.ps1 tests/Startup.Tests.ps1
git commit -m "feat(arranque): lista de entradas con editor, uso, protección y recomendación"
git log -1 --format=%s
```

---

### Task 6: Documento `startup` y reporte para personas

**Files:**
- Modify: `engine/Startup.ps1` (al final)
- Modify: `engine/ResultFile.ps1` (`$script:ResultFreeTextFields`)
- Test: `tests/Startup.Tests.ps1`

**Privacidad (agregado al revisar las Tasks 1 a 5, decisión 36).** `target` nunca va al JSON: tiene rutas de registro, el valor de `StartupApproved` y el id del proceso, y es solo para apagar. `key`, `name`, `command`, `path` (y, antes de la decisión 36, los ids) pueden llevar el SID de la cuenta (las tareas de OneDrive se llaman `OneDrive Standalone Update Task-S-1-5-21-...`) o el nombre de la cuenta (rutas del perfil). Al escribir esta tarea: sumar a lo que oculta `out\<id>.json` en la carpeta de máquina (`Hide-TuneupPersonalData` sobre `ResultFreeTextFields`) el reemplazo de los SID de cuentas (`S-1-5-21-<n>-<n>-<n>-<n>` por `%SID%`), con su prueba sobre un documento `startup`, y decidir si `key` y `name` van en `ResultFreeTextFields` junto a `command` (`name` también es un campo de otros documentos: ocultar ahí cambia más que `startup`). Los ids ya no llevan el SID en la parte legible (Task 1) y no cambian: el hash sigue siendo el de la clave entera.

- [ ] **Step 1: Escribir las pruebas que fallan**

Agregar al final de `tests/Startup.Tests.ps1` (los textos con acentos se comparan con `.`: los `.ps1` del repositorio son ASCII):

```powershell
Describe 'Startup document and report' {
    BeforeAll {
        function New-TestDocument {
            $steam = New-TuneupStartupEntry -Source 'run-user' -Key 'Steam' -Name 'Steam' -Command '"C:\Games\Steam\steam.exe"' -Path 'C:\Games\Steam\steam.exe' -Target @{ ApprovedName = 'Steam' }
            $steam.publisher = 'Valve Corp.'
            $steam.running = $true
            $steam.memoryMB = 220
            $steam.cpuSeconds = 10
            $steam.canDisable = $true
            $steam.recommended = $true
            $steam.recommendedReason = 'game-launcher'
            $steam.uninstall = 'winget uninstall --id Valve.Steam --exact'
            $vpn = New-TuneupStartupEntry -Source 'service' -Key 'PanGPS' -Name 'PanGPS' -Path 'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.exe'
            $vpn.protected = 'vpn'
            $vpn.running = $false
            $old = New-TuneupStartupEntry -Source 'run-machine' -Key 'OldTool' -Name 'OldTool' -Enabled $false
            $once = New-TuneupStartupEntry -Source 'runonce-user' -Key 'Cleanup' -Name 'Cleanup'
            Get-TuneupStartupDocument -Entry @($steam, $vpn, $old, $once) -IsAdmin $false
        }
    }

    It 'gives the entries without what turning them off needs, and counts them' {
        $document = New-TestDocument
        $document.schemaVersion | Should -Be 1
        $document.command | Should -Be 'startup'
        $document.isAdmin | Should -BeFalse
        $document.workPc | Should -BeFalse
        @($document.entries).Count | Should -Be 4
        @($document.entries[0].PSObject.Properties.Name) -join ',' |
            Should -Be 'id,name,source,scope,key,publisher,command,path,enabled,running,memoryMB,cpuSeconds,protected,canDisable,needsAdmin,recommended,recommendedReason,notRecommendedReason,uninstall'
        $document.summary.total | Should -Be 4
        $document.summary.enabled | Should -Be 3
        $document.summary.canDisable | Should -Be 1
        $document.summary.recommended | Should -Be 1
        $document.summary.protected | Should -Be 1
    }

    It 'writes an empty list as an empty array, with the fields of every document' {
        $json = Write-TuneupStartupReport -Document (Get-TuneupStartupDocument -Entry @() -IsAdmin $true) -Json | ConvertFrom-Json
        $json.command | Should -Be 'startup'
        @($json.entries).Count | Should -Be 0
        $json.summary.total | Should -Be 0
        $json.PSObject.Properties.Name | Should -Contain 'warnings'
        $json.PSObject.Properties.Name | Should -Contain 'toolVersion'
    }

    It 'shows people the recommended entries first, with marks that need no colors' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'es'
        try {
            $text = (Write-TuneupStartupReport -Document (New-TestDocument) 6>&1 | Out-String)
        } finally {
            Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        }
        $text | Should -Match 'Lo que arranca con Windows o queda en segundo plano \(4\):'
        $text.IndexOf('Steam') | Should -BeLessThan $text.IndexOf('PanGPS')
        $text | Should -Match '\[encendido\] Steam \(Valve Corp\.\) - al iniciar sesi.n \(Run del usuario\) - en ejecuci.n, 220 MB'
        $text | Should -Match 'id: startup\.run-user\.steam-eb4bc901'
        $text | Should -Match 'Se recomienda apagarlo: lanzador de juegos\.'
        $text | Should -Match 'winget uninstall --id Valve\.Steam --exact'
        $text | Should -Match '\[protegido: VPN\] PanGPS'
        $text | Should -Match '\[apagado\] OldTool'
        $text | Should -Match '\[no se apaga: corre una sola vez y Windows lo borra\] Cleanup'
        $text | Should -Match ([regex]::Escape("-Startup -Disable '<id>,<id>'"))
    }

    It 'tells people why an app of work is not recommended on a work PC' {
        $teams = New-TuneupStartupEntry -Source 'store-app' -Key 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' -Name 'MSTeams'
        $teams.canDisable = $true
        $teams.notRecommendedReason = 'work-app'
        $document = Get-TuneupStartupDocument -Entry @($teams) -IsAdmin $false -WorkPc $true
        $document.workPc | Should -BeTrue
        $text = (Write-TuneupStartupReport -Document $document 6>&1 | Out-String)
        $text | Should -Match 'Turning it off is not recommended: on a work PC it is used for work'
        $text | Should -Not -Match 'Turning it off is recommended'
    }

    It 'says when nothing starts with Windows' {
        $text = (Write-TuneupStartupReport -Document (Get-TuneupStartupDocument -Entry @() -IsAdmin $true) 6>&1 | Out-String)
        $text | Should -Match 'Nothing that starts with Windows was found\.'
    }

    It 'hides the profile folder in command and path of a result of the machine folder' {
        $profileFolder = [Environment]::GetFolderPath('UserProfile')
        $text = ConvertTo-Json -Depth 10 -InputObject ([pscustomobject]@{
                command = 'startup'
                entries = @([pscustomobject]@{ id = 'startup.run-user.x-00000000'; command = "`"$profileFolder\Apps\x.exe`" -a"; path = "$profileFolder\Apps\x.exe" })
            })
        $hidden = Hide-TuneupResultPersonalData -Text $text | ConvertFrom-Json
        $hidden.entries[0].command | Should -Be '"%USERPROFILE%\Apps\x.exe" -a'
        $hidden.entries[0].path | Should -Be '%USERPROFILE%\Apps\x.exe'
        $hidden.entries[0].id | Should -Be 'startup.run-user.x-00000000'
        $hidden.command | Should -Be 'startup'
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: FAIL en `Startup document and report` (`Get-TuneupStartupDocument` no existe; `command` no se oculta).

- [ ] **Step 3: Implementar**

Agregar al final de `engine/Startup.ps1`:

```powershell
# What the startup document gives of an entry: everything but what turning it off needs (target, policy).
function ConvertTo-TuneupStartupView {
    param([Parameter(Mandatory)]$Entry)
    [pscustomobject]@{
        id                = [string]$Entry.id
        name              = [string]$Entry.name
        source            = [string]$Entry.source
        scope             = [string]$Entry.scope
        key               = [string]$Entry.key
        publisher         = $Entry.publisher
        command           = $Entry.command
        path              = $Entry.path
        enabled           = [bool]$Entry.enabled
        running           = $Entry.running
        memoryMB          = $Entry.memoryMB
        cpuSeconds        = $Entry.cpuSeconds
        protected         = $Entry.protected
        canDisable        = [bool]$Entry.canDisable
        needsAdmin        = [bool]$Entry.needsAdmin
        recommended       = [bool]$Entry.recommended
        recommendedReason = $Entry.recommendedReason
        notRecommendedReason = $Entry.notRecommendedReason
        uninstall         = $Entry.uninstall
    }
}

function Get-TuneupStartupDocument {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry, [bool]$IsAdmin, [bool]$WorkPc)
    $views = @($Entry | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-TuneupStartupView -Entry $_ })
    [pscustomobject]@{
        schemaVersion = 1
        command       = 'startup'
        isAdmin       = $IsAdmin
        workPc        = $WorkPc
        entries       = $views
        summary       = [pscustomobject]@{
            total       = $views.Count
            enabled     = @($views | Where-Object { $_.enabled }).Count
            canDisable  = @($views | Where-Object { $_.canDisable }).Count
            recommended = @($views | Where-Object { $_.recommended }).Count
            protected   = @($views | Where-Object { $_.protected }).Count
        }
    }
}

# Why an entry stays on, in the language of the run; nothing when it can be turned off.
function Get-TuneupStartupFixedText {
    param([Parameter(Mandatory)]$Entry)
    $reason = Get-TuneupStartupFixedReason -Entry $Entry
    if (-not $reason) { return }
    if ($Entry.protected) { return (Get-TuneupText -Key "startup.protected.$reason") }
    Get-TuneupText -Key "startup.fixed.$reason"
}

# The mark of an entry for people: a word in brackets, never only a color.
function Get-TuneupStartupMark {
    param([Parameter(Mandatory)]$Entry)
    if ($Entry.protected) { return (Get-TuneupText -Key 'startup.state.protected' -Format (Get-TuneupStartupFixedText -Entry $Entry)) }
    if (-not $Entry.enabled) { return (Get-TuneupText -Key 'startup.state.off') }
    $fixed = Get-TuneupStartupFixedText -Entry $Entry
    if ($fixed) { return (Get-TuneupText -Key 'startup.state.fixed' -Format $fixed) }
    Get-TuneupText -Key 'startup.state.on'
}

function Get-TuneupStartupUsageText {
    param([Parameter(Mandatory)]$Entry)
    if ($Entry.running -eq $true) {
        if ($null -ne $Entry.memoryMB) { return (Get-TuneupText -Key 'startup.usage.running' -Format $Entry.memoryMB) }
        return (Get-TuneupText -Key 'startup.usage.runningNoMemory')
    }
    if ($Entry.running -eq $false) { return (Get-TuneupText -Key 'startup.usage.stopped') }
    Get-TuneupText -Key 'startup.usage.unknown'
}

# The startup document as JSON, or for people: what is recommended first, then what can be turned off,
# then what stays on; each entry with its id, so it can be named in -Disable.
function Write-TuneupStartupReport {
    param(
        [Parameter(Mandatory)]$Document,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Document -Warnings $Warnings); return }
    $entries = @($Document.entries)
    if (-not $entries.Count) {
        Write-Host (Get-TuneupText -Key 'startup.empty')
        return
    }
    Write-Host (Get-TuneupText -Key 'startup.header' -Format $entries.Count)
    $ordered = @($entries | Where-Object { $_.recommended }) + @($entries | Where-Object { -not $_.recommended -and $_.canDisable }) +
        @($entries | Where-Object { -not $_.canDisable })
    $adminMark = ' ' + (Get-TuneupText -Key 'menu.profile.admin')
    foreach ($entry in $ordered) {
        $publisher = $(if ($entry.publisher) { Get-TuneupText -Key 'startup.publisher' -Format $entry.publisher } else { '' })
        $admin = $(if ($entry.canDisable -and $entry.needsAdmin) { $adminMark } else { '' })
        $color = $(if ($entry.recommended) { 'Cyan' } elseif ($entry.canDisable) { 'Gray' } else { 'DarkGray' })
        $line = Get-TuneupText -Key 'startup.entry' -Format (Get-TuneupStartupMark -Entry $entry), $entry.name, $publisher,
            (Get-TuneupText -Key "startup.source.$($entry.source)"), (Get-TuneupStartupUsageText -Entry $entry), $admin
        Write-Host $line -ForegroundColor $color
        Write-Host (Get-TuneupText -Key 'startup.id' -Format $entry.id) -ForegroundColor DarkGray
        if ($entry.recommended) {
            Write-Host (Get-TuneupText -Key 'startup.recommended' -Format (Get-TuneupText -Key "startup.recommend.$($entry.recommendedReason)")) -ForegroundColor Cyan
        }
        if ($entry.notRecommendedReason) {
            Write-Host (Get-TuneupText -Key 'startup.notRecommended' -Format (Get-TuneupText -Key "startup.notRecommended.$($entry.notRecommendedReason)")) -ForegroundColor DarkGray
        }
        if ($entry.uninstall) { Write-Host (Get-TuneupText -Key 'startup.uninstall' -Format $entry.uninstall) }
    }
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'startup.howTo')
}
```

En `engine/ResultFile.ps1`, reemplazar:

```powershell
$script:ResultFreeTextFields = @('warnings', 'message', 'details', 'runDir', 'path', 'error', 'detail', 'output', 'repairedFiles', 'unrepairedFiles')
```

por:

```powershell
$script:ResultFreeTextFields = @('warnings', 'message', 'details', 'runDir', 'path', 'command', 'error', 'detail', 'output', 'repairedFiles', 'unrepairedFiles')
```

y en el comentario de arriba, reemplazar:

```powershell
# The fields of the documents that can carry a path (the run folder, a state file, a file that could not
# be written, the output of sfc or DISM): in the machine folder, which Users can read, the profile folder
```

por:

```powershell
# The fields of the documents that can carry a path (the run folder, a state file, a file that could not
# be written, the output of sfc or DISM, the program and the command line of a startup entry; the command of
# a document is only a word, which never changes): in the machine folder, which Users can read, the profile folder
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Startup.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/ResultFile.Tests.ps1`
Expected: PASS (ningún documento anterior lleva una ruta en `command`).

- [ ] **Step 5: Commit**

```bash
git add engine/Startup.ps1 engine/ResultFile.ps1 tests/Startup.Tests.ps1
git commit -m "feat(arranque): documento startup y tabla para personas con lo recomendado primero"
git log -1 --format=%s
```

---

### Task 7: Ajustes sintéticos y plan sin perfiles

**Files:**
- Create: `engine/StartupTweak.ps1`
- Modify: `engine/handlers/Registry.ps1` (`Test-RegistryTweakDefinition`, `Test-RegistryTweakState`)
- Modify: `engine/Planner.ps1` (`New-TuneupPlan`, parámetro `Profiles`)
- Test: `tests/StartupTweak.Tests.ps1` (nuevo), `tests/Planner.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

Crear `tests/StartupTweak.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:DisabledAt = [datetime]::new(2026, 10, 4, 12, 0, 0, [DateTimeKind]::Utc)
    # 03 00 00 00 and the FILETIME of 2026-10-04 12:00 UTC (134355888000000000), little endian.
    $script:Expected = @(3, 0, 0, 0, 0, 224, 184, 225, 247, 83, 221, 1)
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
    function New-TestEntry([string]$Source, [string]$Key, [hashtable]$Target = @{}, [bool]$Enabled = $true) {
        $entry = New-TuneupStartupEntry -Source $Source -Key $Key -Name "Name $Key" -Enabled $Enabled -Target $Target
        $entry.canDisable = $Enabled
        $entry
    }
}

Describe 'New-TuneupStartupApprovedValue' {
    It 'writes 03 and when it was turned off, as Task Manager does' {
        $value = New-TuneupStartupApprovedValue -DisabledAt $DisabledAt
        $value.GetType().Name | Should -Be 'Byte[]'
        @($value) -join ',' | Should -Be ($Expected -join ',')
        Test-TuneupStartupApprovedEnabled -Value $value | Should -BeFalse
    }
}

Describe 'ConvertTo-TuneupStartupTweak' {
    It 'turns a Run entry off through StartupApproved of its hive' {
        $approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = $approved; ApprovedName = 'Steam' }) -DisabledAt $DisabledAt
        $tweak.id | Should -BeExactly 'startup.run-user.steam-eb4bc901'
        $tweak.type | Should -Be 'registry'
        $tweak.scope | Should -Be 'user'
        $tweak.set.path | Should -Be $approved
        $tweak.set.name | Should -Be 'Steam'
        $tweak.set.kind | Should -Be 'Binary'
        @($tweak.set.value) -join ',' | Should -Be ($Expected -join ',')
        $tweak.set.compare | Should -Be 'startupApproved'
        $tweak.title.es | Should -Be 'Name Steam'
        $tweak.title.en | Should -Be 'Name Steam'
        $tweak.why.en | Should -Be 'Starts with Windows: at sign-in (Run of the user). Turned off the way Task Manager does, without deleting the entry.'
        $tweak.risk | Should -Be 'low'
        $tweak.ask | Should -BeFalse
        $tweak.rebootRequired | Should -BeFalse
        $tweak.startup.source | Should -Be 'run-user'
        $tweak.startup.key | Should -Be 'Steam'
        @($tweak.sources).Count | Should -Be 1
        Test-TuneupUserScopedTweak -Tweak $tweak | Should -BeTrue
        Test-TuneupTweakNeedsAdmin -Tweak $tweak | Should -BeFalse
    }

    It 'keeps the scope of a machine entry and the Run32 and StartupFolder keys' {
        $machine = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run32-machine' 'Tray' @{ ApprovedPath = 'HKLM:\Software\X\StartupApproved\Run32'; ApprovedName = 'Tray' })
        $machine.scope | Should -Be 'machine'
        Test-TuneupTweakNeedsAdmin -Tweak $machine | Should -BeTrue
        $folder = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'folder-user' 'Tool.lnk' @{ ApprovedPath = 'HKCU:\Software\X\StartupApproved\StartupFolder'; ApprovedName = 'Tool.lnk' })
        $folder.set.name | Should -Be 'Tool.lnk'
        $folder.set.value[0] | Should -Be 3
    }

    It 'gives an entry that is already off the same new value (the check reads any odd first byte as off), and a Store task the State it has' {
        $bytes = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Old' @{ ApprovedPath = 'HKCU:\Software\X'; ApprovedName = 'Old'; ApprovedValue = $bytes } -Enabled $false) -DisabledAt $DisabledAt
        @($tweak.set.value) -join ',' | Should -Be ($Expected -join ',')
        $tweak.set.compare | Should -Be 'startupApproved'
        $store = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'P\T' @{ StoreKeyPath = 'HKCU:\Software\X\P\T'; StoreState = 0 } -Enabled $false)
        $store.set.value | Should -Be 0
    }

    It 'turns a Store task off with State 1, as Settings does' {
        $path = 'HKCU:\Software\Classes\X\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask'
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask' @{ StoreKeyPath = $path; StoreState = 2 })
        $tweak.type | Should -Be 'registry'
        $tweak.scope | Should -Be 'user'
        $tweak.set.path | Should -Be $path
        $tweak.set.name | Should -Be 'State'
        $tweak.set.kind | Should -Be 'DWord'
        $tweak.set.value | Should -Be 1
        @(Test-RegistryTweakDefinition -Tweak $tweak).Count | Should -Be 0
    }

    It 'disables a task and sets a service to Manual without stopping it' {
        $task = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'task' '\Vendor\Up' @{ TaskPath = '\Vendor\'; TaskName = 'Up' })
        $task.type | Should -Be 'task'
        $task.scope | Should -Be 'machine'
        $task.set.path | Should -Be '\Vendor\'
        $task.set.name | Should -Be 'Up'
        $task.set.state | Should -Be 'Disabled'
        @(Test-TaskTweakDefinition -Tweak $task).Count | Should -Be 0
        $service = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'service' 'VendorSvc' @{ ServiceName = 'VendorSvc'; StartType = 'Automatic' })
        $service.type | Should -Be 'service'
        $service.set.name | Should -Be 'VendorSvc'
        $service.set.startType | Should -Be 'Manual'
        $service.set.stop | Should -BeFalse
        @(Test-ServiceTweakDefinition -Tweak $service).Count | Should -Be 0
    }

    It 'refuses an entry that cannot be turned off' {
        $protected = New-TestEntry 'run-user' 'AV'
        $protected.protected = 'security'
        { ConvertTo-TuneupStartupTweak -Entry $protected } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'runonce-user' 'Once') } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'driver' 'drv') } | Should -Throw '*cannot be turned off*'
        { ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'policy-user' 'Agent') } | Should -Throw '*cannot be turned off*'
    }
}

Describe 'A startup tweak through the registry handler' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
    }
    AfterAll { Remove-TestKey }

    It 'turns the entry off, reads it as applied also from the journal, and removes the keys it created' {
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' }) -DisabledAt $DisabledAt
        $before = Get-TuneupState -Tweak $tweak
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        Set-TuneupDesired -Tweak $tweak | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'applied'
        @((Get-Item -LiteralPath "$Key\StartupApproved\Run").GetValue('Steam')) -join ',' | Should -Be ($Expected -join ',')
        # The journal keeps the tweak and the state as JSON; -Status and -Undo work from what it reads back.
        $journaled = ConvertTo-Json -InputObject ([pscustomobject]@{ tweak = $tweak; state = $before }) -Depth 10 -Compress | ConvertFrom-Json
        Test-TuneupState -Tweak $journaled.tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $journaled.tweak -State $journaled.state | Out-Null
        Test-Path -LiteralPath "$Key\StartupApproved" | Should -BeFalse
    }

    It 'gives back the value an entry had before, such as the 02 of an entry that was on' {
        New-Item -Path "$Key\StartupApproved\Run" -Force | Out-Null
        $on = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value $on -PropertyType Binary | Out-Null
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam'; ApprovedValue = $on })
        $before = ConvertTo-Json -InputObject (Get-TuneupState -Tweak $tweak) -Depth 10 | ConvertFrom-Json
        Set-TuneupDesired -Tweak $tweak | Out-Null
        Restore-TuneupState -Tweak $tweak -State $before | Out-Null
        @((Get-Item -LiteralPath "$Key\StartupApproved\Run").GetValue('Steam')) -join ',' | Should -Be '2,0,0,0,0,0,0,0,0,0,0,0'
    }

    It 'reads an entry turned off again by Task Manager, with another date, as applied, and one turned on as not applied' {
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' }) -DisabledAt $DisabledAt
        Set-TuneupDesired -Tweak $tweak | Out-Null
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9)) -PropertyType Binary -Force | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'applied'
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -PropertyType Binary -Force | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value 'x' -PropertyType String -Force | Out-Null
        Test-TuneupState -Tweak $tweak | Should -Be 'not-applied'
    }

    It 'gives back the exact bytes it found, also after Task Manager wrote another date' {
        New-Item -Path "$Key\StartupApproved\Run" -Force | Out-Null
        $original = [byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value $original -PropertyType Binary | Out-Null
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'run-user' 'Steam' @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam'; ApprovedValue = $original })
        $journaled = ConvertTo-Json -InputObject ([pscustomobject]@{ tweak = $tweak; state = (Get-TuneupState -Tweak $tweak) }) -Depth 10 -Compress | ConvertFrom-Json
        Set-TuneupDesired -Tweak $tweak | Out-Null
        New-ItemProperty -LiteralPath "$Key\StartupApproved\Run" -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9)) -PropertyType Binary -Force | Out-Null
        # -Undo compares the exact bytes before it restores: another date is a change to give back.
        Test-TuneupStateUnchanged -Tweak $journaled.tweak -Before $journaled.state | Should -BeFalse
        Restore-TuneupState -Tweak $journaled.tweak -State $journaled.state | Out-Null
        @((Get-Item -LiteralPath "$Key\StartupApproved\Run").GetValue('Steam')) -join ',' | Should -Be '6,0,0,0,0,0,0,0,0,0,0,0'
    }

    It 'writes and gives back the State of a Store task' {
        $path = "$Key\SystemAppData\Vendor.App_abc\StartAtLogon"
        New-Item -Path $path -Force | Out-Null
        New-ItemProperty -LiteralPath $path -Name 'State' -Value 2 -PropertyType DWord | Out-Null
        $tweak = ConvertTo-TuneupStartupTweak -Entry (New-TestEntry 'store-app' 'Vendor.App_abc\StartAtLogon' @{ StoreKeyPath = $path; StoreState = 2 })
        $before = Get-TuneupState -Tweak $tweak
        Set-TuneupDesired -Tweak $tweak | Out-Null
        (Get-ItemProperty -LiteralPath $path).State | Should -Be 1
        Restore-TuneupState -Tweak $tweak -State $before | Out-Null
        (Get-ItemProperty -LiteralPath $path).State | Should -Be 2
    }
}
```

Agregar también al final de `tests/StartupTweak.Tests.ps1`:

```powershell
Describe 'The compare field of a registry tweak' {
    It 'is refused in the catalog: only the tweaks of startup entries use it' {
        $tweak = New-TestTweak -Id 'test.compare' -Set ([pscustomobject]@{ path = 'HKCU:\Software\windows-tuneup-test'; name = 'X'; kind = 'DWord'; value = 1; compare = 'startupApproved' })
        @(Test-RegistryTweakDefinition -Tweak $tweak) -join ',' | Should -Match 'set\.compare is only for startup entries'
        @(Test-TuneupTweak -Tweak $tweak) -join ',' | Should -Match 'test\.compare set\.compare'
    }
}
```

En `tests/Planner.Tests.ps1`, agregar al final del archivo:

```powershell
Describe 'New-TuneupPlan without profiles' {
    It 'plans only the tweaks it is given by name, with no profile set at all' {
        $tweak = New-TestTweak -Id 'test.alone'
        $plan = @(New-TuneupPlan -Catalog @($tweak) -Profiles @() -Include @('test.alone') -NoBase -Environment (New-TestEnvironment) -TestState { 'not-applied' })
        $plan.Count | Should -Be 1
        $plan[0].Id | Should -Be 'test.alone'
        $plan[0].Action | Should -Be 'apply'
    }

    It 'still needs the profiles it is asked for' {
        { New-TuneupPlan -Catalog @(New-TestTweak -Id 'test.alone') -Profiles @() -ProfileIds @('gaming') -NoBase -Environment (New-TestEnvironment) -TestState { 'not-applied' } } |
            Should -Throw '*gaming*'
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupTweak.Tests.ps1`
Expected: FAIL (`New-TuneupStartupApprovedValue` no existe).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: FAIL en `New-TuneupPlan without profiles` (`Cannot bind argument to parameter 'Profiles' because it is an empty array`).

- [ ] **Step 3: Implementar**

Crear `engine/StartupTweak.ps1`:

```powershell
# -Startup -Disable (design, section 15.7): each chosen entry becomes a tweak of a type that already exists
# (registry for StartupApproved and for the State of a Store task, task, service), built from what was
# found. The journal keeps the whole tweak with its state before the change, and -Undo and -Status work
# from the journal, so turning an entry off is undone, checked and reported by the same handlers as a
# catalog tweak. These tweaks are never in the catalog and never go through its checks.

$script:StartupTweakSources = [ordered]@{
    registry = 'https://learn.microsoft.com/windows/win32/setupapi/run-and-runonce-registry-keys'
    store    = 'https://learn.microsoft.com/uwp/api/windows.applicationmodel.startuptaskstate'
    task     = 'https://learn.microsoft.com/powershell/module/scheduledtasks/disable-scheduledtask'
    service  = 'https://learn.microsoft.com/windows-server/administration/windows-commands/sc-config'
}
# StartupTaskState.DisabledByUser: what Settings writes when a person turns a Store app off at startup; the
# app cannot turn itself on again.
$script:StoreTaskDisabledByUser = 1

# How an entry of a source is turned off: registry (StartupApproved), store, task or service; nothing for a
# source that is never turned off (run-once, policy, driver).
function Get-TuneupStartupKind {
    param([Parameter(Mandatory)][string]$Source)
    switch -Regex ($Source) {
        '^(run|run32)-' { return 'registry' }
        '^folder-' { return 'registry' }
        '^store-app$' { return 'store' }
        '^task$' { return 'task' }
        '^service$' { return 'service' }
    }
}

# 03 00 00 00 and the FILETIME (UTC) of when it was turned off: what Task Manager writes (design, 15.3).
function New-TuneupStartupApprovedValue {
    param([Parameter(Mandatory)][datetime]$DisabledAt)
    $bytes = New-Object byte[] 12
    $bytes[0] = 3
    [BitConverter]::GetBytes([int64]$DisabledAt.ToFileTimeUtc()).CopyTo($bytes, 4)
    , $bytes
}

# The tweak that turns one entry off. A StartupApproved value always gets a new date, as Task Manager
# writes, and compare = startupApproved: the check reads any odd first byte as off (an entry already off is
# left out as already applied, and one turned off again by Task Manager is not reverted), while the state
# keeps the exact bytes for -Undo. A Store task that is already off asks for the State it has. The texts
# are the name of the entry and why, in the language of the run (both fields: the journal keeps them, and
# the code of the tool cannot hold accents).
function ConvertTo-TuneupStartupTweak {
    param([Parameter(Mandatory)]$Entry, [datetime]$DisabledAt = [datetime]::UtcNow)
    $kind = Get-TuneupStartupKind -Source ([string]$Entry.source)
    if ((Get-TuneupStartupFixedReason -Entry $Entry) -or -not $kind) { throw "Startup entry $($Entry.id) cannot be turned off" }
    $target = $Entry.target
    switch ($kind) {
        'registry' {
            $type = 'registry'
            $value = New-TuneupStartupApprovedValue -DisabledAt $DisabledAt
            $set = [pscustomobject]@{
                path    = [string]$target.ApprovedPath
                name    = [string]$target.ApprovedName
                kind    = 'Binary'
                value   = [int[]]@($value)
                compare = 'startupApproved'
            }
        }
        'store' {
            $type = 'registry'
            $state = $(if ($Entry.enabled) { $script:StoreTaskDisabledByUser } else { [int]$target.StoreState })
            $set = [pscustomobject]@{ path = [string]$target.StoreKeyPath; name = 'State'; kind = 'DWord'; value = $state }
        }
        'task' {
            $type = 'task'
            $set = [pscustomobject]@{ path = [string]$target.TaskPath; name = [string]$target.TaskName; state = 'Disabled' }
        }
        'service' {
            $type = 'service'
            $set = [pscustomobject]@{ name = [string]$target.ServiceName; startType = 'Manual'; stop = $false }
        }
    }
    $why = Get-TuneupText -Key "startup.why.$kind" -Format (Get-TuneupText -Key "startup.source.$($Entry.source)")
    [pscustomobject]@{
        id             = [string]$Entry.id
        title          = [pscustomobject]@{ es = [string]$Entry.name; en = [string]$Entry.name }
        why            = [pscustomobject]@{ es = $why; en = $why }
        risk           = 'low'
        ask            = $false
        os             = [pscustomobject]@{ families = @('10', '11'); minBuild = 19041; editions = @('Home', 'Pro', 'Enterprise', 'Education') }
        type           = $type
        scope          = [string]$Entry.scope
        set            = $set
        rebootRequired = $false
        sources        = @($script:StartupTweakSources[$kind])
        startup        = [pscustomobject]@{ source = [string]$Entry.source; key = [string]$Entry.key }
    }
}
```

En `engine/handlers/Registry.ps1`, función `Test-RegistryTweakDefinition`, reemplazar:

```powershell
    if ([string]::IsNullOrEmpty([string]$set.name)) { 'is missing set.name' }
```

por:

```powershell
    if ([string]::IsNullOrEmpty([string]$set.name)) { 'is missing set.name' }
    # Only the tweaks that -Startup -Disable builds compare that way (StartupTweak.ps1).
    if ($null -ne $set.PSObject.Properties['compare']) { 'set.compare is only for startup entries (-Startup), never for the catalog' }
```

Y en la función `Test-RegistryTweakState`, reemplazar:

```powershell
    if (-not $current.exists -or $current.kind -ne $desired.kind) { return 'not-applied' }
```

por:

```powershell
    if (-not $current.exists -or $current.kind -ne $desired.kind) { return 'not-applied' }
    # A startup entry turned off by -Startup -Disable: off is an odd first byte, whatever date follows it,
    # because Task Manager writes a new date each time it turns an entry off. Get still reads the exact bytes,
    # so the journal keeps them and -Undo gives them back as they were.
    $compare = $desired.PSObject.Properties['compare']
    if ($null -ne $compare -and [string]$compare.Value -ceq 'startupApproved') {
        if (Test-TuneupStartupApprovedEnabled -Value @($current.value)) { return 'not-applied' }
        return 'applied'
    }
```

En `engine/Planner.ps1`, reemplazar:

```powershell
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][object[]]$Profiles,
        [AllowEmptyCollection()][AllowNull()][string[]]$ProfileIds = @(),
```

por:

```powershell
        [Parameter(Mandatory)][object[]]$Catalog,
        # Empty for a plan of tweaks named one by one (-NoBase without -ProfileIds: -Startup -Disable).
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Profiles,
        [AllowEmptyCollection()][AllowNull()][string[]]$ProfileIds = @(),
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupTweak.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: PASS (`still needs the profiles it is asked for`: `Resolve-TuneupProfileId` lanza `err.unknownProfile` con el nombre).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Registry.Tests.ps1`
Expected: PASS (ningún ajuste de catálogo ni de prueba trae `compare`: la rama nueva no cambia nada más).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogQuality.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/StartupTweak.ps1 engine/handlers/Registry.ps1 engine/Planner.ps1 tests/StartupTweak.Tests.ps1 tests/Planner.Tests.ps1
git commit -m "feat(arranque): cada entrada elegida se apaga con un ajuste de registro, tarea o servicio"
git log -1 --format=%s
```

---

### Task 8: El comando `-Startup` y `-Disable`

**Files:**
- Modify: `engine/Commands.ps1` (nueva `Invoke-TuneupStartupCommand`; `New-TuneupApplyRequest`)
- Modify: `engine/Output.ps1` (`Write-TuneupPlanReport`, `New-TuneupApplyReport`)
- Test: `tests/StartupCommand.Tests.ps1` (nuevo)

- [ ] **Step 1: Escribir las pruebas que fallan**

Crear `tests/StartupCommand.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:Approved = "$Key\StartupApproved\Run"
    $script:SteamId = 'startup.run-user.steam-eb4bc901'
    $script:On = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    function Remove-TestKey { if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force } }
    # A Run entry of the user whose Task Manager choice lives under the test key.
    function New-TestSteam([bool]$Enabled = $true, $Value = $null) {
        $entry = New-TuneupStartupEntry -Source 'run-user' -Key 'Steam' -Name 'Steam' -Command '"C:\Games\Steam\steam.exe"' -Path 'C:\Games\Steam\steam.exe' `
            -Enabled $Enabled -Target @{ ApprovedPath = $Approved; ApprovedName = 'Steam'; ApprovedValue = $Value }
        $entry.canDisable = $Enabled
        $entry
    }
    # A context like the one tuneup.ps1 builds, on the fixture catalog, with a known environment.
    function New-TestContext([switch]$Json, $Environment = (New-TestEnvironment -IsAdmin $false), [string]$StateRoot) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo)
        $context.StateRoot = $(if ($StateRoot) { $StateRoot } else { Join-Path $TestDrive ([guid]::NewGuid().ToString()) })
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = $Environment
        $context
    }
    function Invoke-TestStartup($Context, [string[]]$Disable = @(), [switch]$PlanOnly, [switch]$Yes) {
        $output = @(Invoke-TuneupStartupCommand -Context $Context -Disable $Disable -PlanOnly:$PlanOnly -Yes:$Yes)
        ($output -join "`n") | ConvertFrom-Json
    }
}

Describe 'Invoke-TuneupStartupCommand' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
        $script:Entries = @(New-TestSteam)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:Entries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
    }
    AfterAll { Remove-TestKey }

    It 'lists the entries as a startup document, with a warning that some tasks need administrator' {
        $context = New-TestContext -Json
        $document = Invoke-TestStartup $context
        $context.ExitCode | Should -Be 0
        $document.command | Should -Be 'startup'
        $document.isAdmin | Should -BeFalse
        $document.workPc | Should -BeFalse
        $document.entries[0].id | Should -BeExactly $SteamId
        $document.warnings | Should -Contain (Get-TuneupText -Key 'startup.unelevatedNote')
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 1 -Exactly
    }

    It 'tells whether this is a work PC and gives it to the list' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $false -IsManaged $true)
        (Invoke-TestStartup $context).workPc | Should -BeTrue
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 1 -Exactly -ParameterFilter { $WorkPc }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $true }
        (Invoke-TestStartup (New-TestContext -Json)).workPc | Should -BeTrue
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        (Invoke-TestStartup (New-TestContext -Json)).workPc | Should -BeFalse
    }

    It 'plans turning an entry off as a plan of the startup source, changing nothing' {
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @($SteamId) -PlanOnly
        $context.ExitCode | Should -Be 0
        $plan.command | Should -Be 'plan'
        $plan.source | Should -Be 'startup'
        $plan.requiresAdmin | Should -BeFalse
        @($plan.items).Count | Should -Be 1
        $plan.items[0].id | Should -BeExactly $SteamId
        $plan.items[0].title | Should -Be 'Steam'
        $plan.items[0].action | Should -Be 'apply'
        $plan.items[0].type | Should -Be 'registry'
        Test-Path -LiteralPath $Approved | Should -BeFalse
    }

    It 'turns it off as a run that -Status checks and -Undo gives back, and turning it off again changes nothing' {
        $context = New-TestContext -Json
        $report = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 0
        $report.command | Should -Be 'apply'
        $report.source | Should -Be 'startup'
        $report.results[0].status | Should -Be 'applied'
        $report.restorePoint | Should -Be 'not-needed'
        $value = [byte[]](Get-Item -LiteralPath $Approved).GetValue('Steam')
        $value.Length | Should -Be 12
        $value[0] | Should -Be 3

        # The next list reads it as off: turning it off again plans nothing and makes no run.
        $script:Entries = @(New-TestSteam -Enabled $false -Value $value)
        $again = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TestStartup $again -Disable @($SteamId) -Yes
        $again.ExitCode | Should -Be 0
        $plan.command | Should -Be 'plan'
        $plan.items[0].reason | Should -Be 'already-applied'
        @(Get-ChildItem -LiteralPath (Join-Path $context.StateRoot 'runs') -Directory).Count | Should -Be 1

        $status = Invoke-TuneupStatusCommand -Context (New-TestContext -Json -StateRoot $context.StateRoot) | ConvertFrom-Json
        $status.items[0].id | Should -BeExactly $SteamId
        $status.items[0].title | Should -Be 'Steam'
        $status.items[0].status | Should -Be 'ok'
        # Turned off again from Task Manager, with another date: still off, so not reverted.
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value ([byte[]](3, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9)) -PropertyType Binary -Force | Out-Null
        $status = Invoke-TuneupStatusCommand -Context (New-TestContext -Json -StateRoot $context.StateRoot) | ConvertFrom-Json
        $status.items[0].status | Should -Be 'ok'
        # Turned on again by the person (Task Manager writes 02): Windows "reverted" it.
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value $On -PropertyType Binary -Force | Out-Null
        $status = Invoke-TuneupStatusCommand -Context (New-TestContext -Json -StateRoot $context.StateRoot) | ConvertFrom-Json
        $status.items[0].status | Should -Be 'drift'

        $undoContext = New-TestContext -Json -StateRoot $context.StateRoot
        $undo = Invoke-TuneupUndoCommand -Context $undoContext -RunId 'last' | ConvertFrom-Json
        $undoContext.ExitCode | Should -Be 0
        $undo.results[0].status | Should -Be 'restored'
        # It had no StartupApproved value: the value and the keys the run created are gone.
        Test-Path -LiteralPath "$Key\StartupApproved" | Should -BeFalse
    }

    It 'refuses an id that is not in the list, doing nothing' {
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @('startup.run-user.gone-00000000') -Yes
        $context.ExitCode | Should -Be 1
        $refused.command | Should -Be 'error'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupUnknown' -Format 'startup.run-user.gone-00000000')
        Test-Path -LiteralPath $Approved | Should -BeFalse
    }

    It 'refuses entries that stay on, saying why for each one, and does nothing with the rest' {
        $vpn = New-TuneupStartupEntry -Source 'run-user' -Key 'GlobalProtect' -Name 'GlobalProtect'
        $vpn.protected = 'vpn'
        $once = New-TuneupStartupEntry -Source 'runonce-user' -Key 'Cleanup' -Name 'Cleanup'
        $script:Entries = @((New-TestSteam), $vpn, $once)
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($SteamId, $vpn.id, $once.id) -Yes
        $context.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupFixed')
        $expected = @(
            (Get-TuneupText -Key 'startup.refusedLine' -Format $vpn.id, 'GlobalProtect', 'VPN'),
            (Get-TuneupText -Key 'startup.refusedLine' -Format $once.id, 'Cleanup', (Get-TuneupText -Key 'startup.fixed.run-once'))
        )
        @($refused.details) -join "`n" | Should -Be ($expected -join "`n")
        Test-Path -LiteralPath $Approved | Should -BeFalse
    }

    It 'needs administrator only when a chosen entry is of the machine' {
        $machine = New-TuneupStartupEntry -Source 'run-machine' -Key 'Tray' -Name 'Tray' -Target @{ ApprovedPath = 'HKLM:\Software\windows-tuneup-test\StartupApproved\Run'; ApprovedName = 'Tray' }
        $machine.canDisable = $true
        $script:Entries = @((New-TestSteam), $machine)
        $context = New-TestContext -Json
        $plan = Invoke-TestStartup $context -Disable @($machine.id) -PlanOnly
        $plan.requiresAdmin | Should -BeTrue
        $plan.items[0].needsAdmin | Should -BeTrue
        $context = New-TestContext -Json
        $refused = Invoke-TestStartup $context -Disable @($machine.id) -Yes
        $context.ExitCode | Should -Be 1
        $refused.message | Should -Be (Get-TuneupText -Key 'err.notAdmin')
    }

    It 'refuses an entry of the user when elevated as another account, before reading anything' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -IsAdmin $true -IsSessionUser $false)
        $refused = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $context.ExitCode | Should -Be 1
        $refused.reason | Should -Be 'session-user'
        $refused.message | Should -Be (Get-TuneupText -Key 'err.startupSessionUser' -Format $SteamId)
        Should -Invoke -ModuleName Tuneup Get-TuneupStartupEntry -Times 0
    }

    It 'asks for -Yes with -Json, like applying a profile' {
        $context = New-TestContext -Json
        (Invoke-TestStartup $context -Disable @($SteamId)).message | Should -Be (Get-TuneupText -Key 'err.jsonNeedsYes')
        $context.ExitCode | Should -Be 1
    }

    It 'turns nothing off on a Windows it does not support, but still lists' {
        $old = New-TestEnvironment -Build 17763 -IsAdmin $false
        $context = New-TestContext -Json -Environment $old
        (Invoke-TestStartup $context -Disable @($SteamId) -Yes).message | Should -Be (Get-TuneupText -Key 'err.unsupported')
        $context.ExitCode | Should -Be 1
        $context = New-TestContext -Json -Environment $old
        (Invoke-TestStartup $context).command | Should -Be 'startup'
        $context.ExitCode | Should -Be 0
    }

    It 'tells people that the change takes effect at the next start' {
        $context = New-TestContext
        Invoke-TuneupStartupCommand -Context $context -Disable @($SteamId) -Yes 6>$null | Out-Null
        $context.ExitCode | Should -Be 0
        $context.Io.Output | Should -Contain (Get-TuneupText -Key 'startup.nextStart')
    }

    It 'writes the request of the run in its transcript' {
        $context = New-TestContext -Json
        $report = Invoke-TestStartup $context -Disable @($SteamId) -Yes
        $transcript = [System.IO.File]::ReadAllText((Join-Path $report.runDir 'transcript.log'))
        $transcript | Should -Match ([regex]::Escape((Get-TuneupText -Key 'transcript.request.startup' -Format '-', $SteamId, '-')))
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupCommand.Tests.ps1`
Expected: FAIL (`Invoke-TuneupStartupCommand` no existe).

- [ ] **Step 3: Aceptar el origen `startup` en el plan y el reporte**

En `engine/Commands.ps1` y en `engine/Output.ps1`, reemplazar **todas** las apariciones (una en `New-TuneupApplyRequest`, una en `Write-TuneupPlanReport` y una en `New-TuneupApplyReport`) de:

```powershell
[ValidateSet('profiles', 'reapply')]
```

por:

```powershell
[ValidateSet('profiles', 'reapply', 'startup')]
```

- [ ] **Step 4: Implementar el comando**

En `engine/Commands.ps1`, agregar después de la función `Invoke-TuneupSuggestCommand` completa:

```powershell
# -Startup (design, section 15): what starts with Windows or runs in the background, read only. With
# -Disable, the entries named by their id are turned off as a run of the tool: each one becomes a tweak of a
# type that exists (StartupTweak.ps1) and goes through the same plan, confirmation, journal, restore point
# and report as a profile (source startup), so -Status and -Undo work as for any run. Nothing is
# uninstalled or deleted. An id that is not in the list now, or that names an entry that stays on, stops
# everything before any change.
function Invoke-TuneupStartupCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$Disable = @(),
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $ids = @($Disable | Where-Object { $_ } | Select-Object -Unique)
    if ($ids.Count) {
        $unsupported = Get-TuneupUnsupportedMessage -Context $Context
        if ($unsupported) {
            Write-TuneupCommandError -Context $Context -Message $unsupported
            return
        }
        # Elevated with another administrator's password, HKCU is that administrator's: the entries of the
        # account at this desktop cannot even be seen from here.
        if ($environment.IsAdmin -and $environment.IsSessionUser -eq $false) {
            $userIds = @($ids | Where-Object { (Get-TuneupStartupIdScope -Id $_) -eq 'user' })
            if ($userIds.Count) {
                Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupSessionUser' -Format ($userIds -join ', ')) -Reason 'session-user'
                return
            }
        }
    }
    # On a work PC (managed, or joined to Entra ID) the apps of work are not recommended.
    $workArguments = @{ Environment = $environment }
    $workPc = [bool](@(Invoke-TuneupContextStep -Context $Context -Step { Test-TuneupStartupWorkPc @workArguments }) | Select-Object -Last 1)
    $entryArguments = @{ Rules = Import-TuneupStartupRuleSet; WorkPc = $workPc }
    $entries = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupStartupEntry @entryArguments })
    if (-not $ids.Count) {
        if (-not $environment.IsAdmin) {
            Invoke-TuneupContextStep -Context $Context -Step { Write-Warning (Get-TuneupText -Key 'startup.unelevatedNote') }
        }
        $document = Get-TuneupStartupDocument -Entry $entries -IsAdmin ([bool]$environment.IsAdmin) -WorkPc $workPc
        $Context.Result = $document
        Write-TuneupStartupReport -Document $document -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $byId = @{}
    foreach ($entry in $entries) { $byId[[string]$entry.id] = $entry }
    $unknown = @($ids | Where-Object { -not $byId.ContainsKey($_) })
    if ($unknown.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupUnknown' -Format ($unknown -join ', '))
        return
    }
    $chosen = @($ids | ForEach-Object { $byId[$_] })
    $fixed = @($chosen | Where-Object { Get-TuneupStartupFixedReason -Entry $_ })
    if ($fixed.Count) {
        $details = @($fixed | ForEach-Object { Get-TuneupText -Key 'startup.refusedLine' -Format $_.id, $_.name, (Get-TuneupStartupFixedText -Entry $_) })
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.startupFixed') -Details $details
        return
    }
    $tweaks = @($chosen | ForEach-Object { ConvertTo-TuneupStartupTweak -Entry $_ })
    $tweakIds = [string[]]@($tweaks | ForEach-Object { [string]$_.id })
    # Named one by one, like -Include: no base profile, and the plan still checks each state (an entry that
    # is already off is left out as already applied) and the account of a user entry.
    $planArguments = @{
        Catalog     = $tweaks
        Profiles    = @()
        Include     = $tweakIds
        NoBase      = $true
        Environment = $environment
        TestState   = { param($tweak) Test-TuneupState -Tweak $tweak }
    }
    $plan = @(Invoke-TuneupContextStep -Context $Context -Step { New-TuneupPlan @planArguments })
    $request = New-TuneupApplyRequest -Source 'startup' -Include $tweakIds
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
    # Only after something was applied (then the report is the result).
    if (-not $Context.Json -and $null -ne $Context.Result -and $Context.ExitCode -ne 1) {
        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'startup.nextStart')
    }
}
```

- [ ] **Step 5: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupCommand.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS (`reason.session-user` existe; las claves `startup.*` y `err.startup*` vienen de la Task 3).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 6: Commit**

```bash
git add engine/Commands.ps1 engine/Output.ps1 tests/StartupCommand.Tests.ps1
git commit -m "feat(arranque): -Startup lista y -Disable apaga lo elegido como una corrida que -Undo revierte"
git log -1 --format=%s
```

---

### Task 9: Volver a aplicar deja fuera las entradas de arranque

**Files:**
- Modify: `engine/Commands.ps1` (`Invoke-TuneupReapply`)
- Test: `tests/StartupCommand.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

Agregar al final de `tests/StartupCommand.Tests.ps1`:

```powershell
Describe 'Re-applying a startup entry that came back' {
    BeforeEach {
        Remove-TestKey
        New-Item -Path $Key -Force | Out-Null
        $script:Entries = @(New-TestSteam)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:Entries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
    }
    AfterAll { Remove-TestKey }

    It 'leaves it out with a warning that says how to turn it off again, also when -Include names it' {
        $context = New-TestContext -Json
        Invoke-TestStartup $context -Disable @($SteamId) -Yes | Out-Null
        New-ItemProperty -LiteralPath $Approved -Name 'Steam' -Value $On -PropertyType Binary -Force | Out-Null
        $warning = Get-TuneupText -Key 'reapply.startupEntry' -Format $SteamId

        $reapply = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $reapply -Reapply -PlanOnly | ConvertFrom-Json
        $reapply.ExitCode | Should -Be 0
        $plan.source | Should -Be 'reapply'
        @($plan.items).Count | Should -Be 0
        $plan.warnings | Should -Contain $warning

        $named = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $named -Reapply -PlanOnly -Include @($SteamId) | ConvertFrom-Json
        $named.ExitCode | Should -Be 0
        $plan.command | Should -Be 'plan'
        @($plan.warnings | Where-Object { $_ -eq $warning }).Count | Should -Be 1
    }

    It 'says that a startup entry named in -Include did not come back' {
        $context = New-TestContext -Json
        Invoke-TestStartup $context -Disable @($SteamId) -Yes | Out-Null
        $named = New-TestContext -Json -StateRoot $context.StateRoot
        $plan = Invoke-TuneupStatusCommand -Context $named -Reapply -PlanOnly -Include @($SteamId) | ConvertFrom-Json
        $named.ExitCode | Should -Be 0
        $plan.warnings | Should -Contain (Get-TuneupText -Key 'reapply.notRevertedUnverified' -Format $SteamId)
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupCommand.Tests.ps1`
Expected: FAIL en `Re-applying a startup entry that came back`: el aviso es "Tweak startup.run-user.steam-eb4bc901 was reverted but is no longer in the catalog...", y con `-Include` el documento es un `error` (`Unknown tweak`).

- [ ] **Step 3: Implementar**

En `engine/Commands.ps1`, función `Invoke-TuneupReapply`, reemplazar:

```powershell
    $missing = @($drifted | Where-Object { -not $known.ContainsKey($_) })
    if ($missing.Count) {
        Invoke-TuneupContextStep -Context $Context -Step {
            foreach ($id in $missing) { Write-Warning "Tweak $id was reverted but is no longer in the catalog: undo the run that applied it to restore it" }
        }
    }
```

por:

```powershell
    $missing = @($drifted | Where-Object { -not $known.ContainsKey($_) })
    if ($missing.Count) {
        Invoke-TuneupContextStep -Context $Context -Step {
            foreach ($id in $missing) {
                # A startup entry is never in the catalog: it is turned off again from what starts now
                # (-Startup -Disable), which reads the entry again.
                if (Test-TuneupStartupId -Id $id) { Write-Warning (Get-TuneupText -Key 'reapply.startupEntry' -Format $id) }
                else { Write-Warning "Tweak $id was reverted but is no longer in the catalog: undo the run that applied it to restore it" }
            }
        }
    }
```

Y reemplazar:

```powershell
        $unknown = @($named | Where-Object { -not $known.ContainsKey($_) })
```

por:

```powershell
        # A startup entry named here is not unknown: it is left out with its own warning.
        $unknown = @($named | Where-Object { -not $known.ContainsKey($_) -and -not (Test-TuneupStartupId -Id $_) })
```

Y reemplazar:

```powershell
            foreach ($id in @($named | Where-Object { $ids -notcontains $_ })) { Write-Warning (Get-TuneupText -Key $notDriftedKey -Format $id) }
```

por:

```powershell
            foreach ($id in @($named | Where-Object { $ids -notcontains $_ -and $missing -notcontains $_ })) { Write-Warning (Get-TuneupText -Key $notDriftedKey -Format $id) }
```

(Solo una entrada de arranque nombrada puede estar en `$missing`: cualquier otro id que el catálogo no tiene ya terminó en `err.unknownTweak`. Si volvió, ya tiene su aviso `reapply.startupEntry` y no recibe además "no se revirtió", que sería falso.)

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupCommand.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`re-applies with -Status -Reapply -Include only the drifted tweaks it names` no cambia).

- [ ] **Step 5: Commit**

```bash
git add engine/Commands.ps1 tests/StartupCommand.Tests.ps1
git commit -m "fix(reaplicar): una entrada de arranque que volvió se deja fuera con un aviso que dice cómo apagarla"
git log -1 --format=%s
```

---

### Task 10: Parámetros `-Startup` y `-Disable`

**Files:**
- Modify: `tuneup.ps1` (ayuda y `param`)
- Modify: `engine/Arguments.ps1`
- Modify: `engine/Commands.ps1` (`Invoke-TuneupCli`)
- Test: `tests/Arguments.Tests.ps1`, `tests/Cli.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

En `tests/Arguments.Tests.ps1`, reemplazar:

```powershell
        @{ Name = 'reading a result'; Present = @('ReadResult') }
    ) {
```

por:

```powershell
        @{ Name = 'reading a result'; Present = @('ReadResult') }
        @{ Name = 'what starts with Windows'; Present = @('Startup') }
        @{ Name = 'turning startup entries off'; Present = @('Startup', 'Disable', 'Yes') }
        @{ Name = 'the plan of turning them off'; Present = @('Startup', 'Disable', 'WhatIf') }
    ) {
```

y reemplazar:

```powershell
        @{ Present = @('ReadResult', 'WhatIf'); Expected = '-ReadResult -WhatIf' }
    ) {
```

por:

```powershell
        @{ Present = @('ReadResult', 'WhatIf'); Expected = '-ReadResult -WhatIf' }
        @{ Present = @('Disable'); Expected = '-Disable (-Startup)' }
        @{ Present = @('Status', 'Disable'); Expected = '-Disable (-Startup)' }
        @{ Present = @('Startup', 'Yes'); Expected = '-Startup -Yes' }
        @{ Present = @('Startup', 'WhatIf'); Expected = '-Startup -WhatIf' }
        @{ Present = @('Startup', 'List'); Expected = '-List -Startup' }
        @{ Present = @('Startup', 'ReadResult'); Expected = '-Startup -ReadResult' }
        @{ Present = @('Startup', 'Profile'); Expected = '-Startup -Profile' }
        @{ Present = @('Startup', 'Disable', 'Include', 'Yes'); Expected = '-Startup -Include' }
    ) {
```

En `tests/Cli.Tests.ps1`, agregar después del `It 'rejects -List with the options of applying, before reading anything'` completo:

```powershell
    It 'lists what starts with Windows as a startup document' {
        $result = Invoke-Tuneup @('-Startup', '-Json')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'startup'
        # What the runner has is not checked: only the shape of the document.
        $json.PSObject.Properties.Name | Should -Contain 'entries'
        $json.summary.total | Should -Be @($json.entries).Count
        foreach ($entry in @($json.entries)) { $entry.id | Should -MatchExactly '^startup\.[a-z0-9-]+\.[a-z0-9-]+$' }
    }

    It 'refuses to turn off an id that is not in the list, and changes nothing' {
        $result = Invoke-Tuneup @('-Startup', '-Disable', 'startup.run-user.nothing-00000000', '-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        # Unknown, or (on a runner elevated without a desktop session) of another account: either way named and refused.
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'startup\.run-user\.nothing-00000000'
        Test-Path -LiteralPath (Join-Path $Root 'runs') | Should -BeFalse
    }

    It 'rejects <Expected>, before reading anything' -TestCases @(
        @{ Arguments = @('-Disable', 'startup.run-user.x-00000000', '-Json'); Expected = 'Invalid parameter combination: -Disable (-Startup)' }
        @{ Arguments = @('-Startup', '-Yes', '-Json'); Expected = 'Invalid parameter combination: -Startup -Yes' }
        @{ Arguments = @('-Startup', '-List', '-Json'); Expected = 'Invalid parameter combination: -List -Startup' }
    ) {
        param($Arguments, $Expected)
        $result = Invoke-Tuneup $Arguments
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be $Expected
    }
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Arguments.Tests.ps1`
Expected: FAIL en los casos nuevos (`-Startup` no es un comando).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: FAIL en las tres pruebas nuevas (`-Startup` es un parámetro desconocido: `err.unknownArgs`).

- [ ] **Step 3: Implementar las reglas de los parámetros**

En `engine/Arguments.ps1`, reemplazar:

```powershell
# Commands exclude each other and the options of applying a plan.
$script:CliCommands = @('Status', 'Undo', 'Health', 'Measure', 'List', 'Suggest', 'ReadResult')
$script:CliApplyOptions = @('Profile', 'Include', 'Exclude', 'WhatIf', 'Yes')
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure'; Reapply = 'Status' }
# Options of applying that an option of a command brings back: -Status -Reapply applies again what
# drifted, so it takes -Yes and -WhatIf, and -Include to name the drifted tweaks to apply again (and
# still not -Profile or -Exclude).
$script:CliApplyingOptions = @{ Reapply = @('Yes', 'WhatIf', 'Include') }
```

por:

```powershell
# Commands exclude each other and the options of applying a plan.
$script:CliCommands = @('Status', 'Undo', 'Health', 'Measure', 'List', 'Suggest', 'Startup', 'ReadResult')
$script:CliApplyOptions = @('Profile', 'Include', 'Exclude', 'WhatIf', 'Yes')
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure'; Reapply = 'Status'; Disable = 'Startup' }
# Options of applying that an option of a command brings back: -Status -Reapply applies again what
# drifted, so it takes -Yes and -WhatIf, and -Include to name the drifted tweaks to apply again (and
# still not -Profile or -Exclude). -Startup -Disable turns entries off as a run, so it takes -Yes and
# -WhatIf; the entries are named by -Disable itself.
$script:CliApplyingOptions = @{ Reapply = @('Yes', 'WhatIf', 'Include'); Disable = @('Yes', 'WhatIf') }
```

- [ ] **Step 4: Pasar los parámetros al comando**

En `engine/Commands.ps1`, función `Invoke-TuneupCli`, reemplazar:

```powershell
        [switch]$List,
        [switch]$Suggest,
        [AllowEmptyString()][string]$ReadResult
    )
    $ProfileName = @(Get-TuneupCleanList ($ProfileName -split ','))
    $Include = @(Get-TuneupCleanList ($Include -split ','))
    $Exclude = @(Get-TuneupCleanList ($Exclude -split ','))
```

por:

```powershell
        [switch]$List,
        [switch]$Suggest,
        [switch]$Startup,
        [string[]]$Disable = @(),
        [AllowEmptyString()][string]$ReadResult
    )
    $ProfileName = @(Get-TuneupCleanList ($ProfileName -split ','))
    $Include = @(Get-TuneupCleanList ($Include -split ','))
    $Exclude = @(Get-TuneupCleanList ($Exclude -split ','))
    $Disable = @(Get-TuneupCleanList ($Disable -split ','))
```

Reemplazar:

```powershell
    if ($PSBoundParameters.ContainsKey('Suggest') -and $Suggest) { $present += 'Suggest' }
```

por:

```powershell
    if ($PSBoundParameters.ContainsKey('Suggest') -and $Suggest) { $present += 'Suggest' }
    if ($PSBoundParameters.ContainsKey('Startup') -and $Startup) { $present += 'Startup' }
    if ($PSBoundParameters.ContainsKey('Disable') -and $Disable.Count) { $present += 'Disable' }
```

Y reemplazar:

```powershell
    if ($List) { Invoke-TuneupListCommand -Context $Context; return }
```

por:

```powershell
    if ($List) { Invoke-TuneupListCommand -Context $Context; return }
    if ($Startup) { Invoke-TuneupStartupCommand -Context $Context -Disable $Disable -PlanOnly:$PlanOnly -Yes:$Yes; return }
```

- [ ] **Step 5: Declarar los parámetros en `tuneup.ps1`**

En `tuneup.ps1`, reemplazar:

```powershell
.EXAMPLE
    .\tuneup.ps1 -Suggest
```

por:

```powershell
.EXAMPLE
    .\tuneup.ps1 -Suggest
.EXAMPLE
    .\tuneup.ps1 -Startup
.EXAMPLE
    .\tuneup.ps1 -Startup -Disable 'startup.run-user.steam-eb4bc901' -WhatIf
```

Reemplazar:

```powershell
.PARAMETER ResultId
```

por:

```powershell
.PARAMETER Startup
    Shows what starts with Windows or runs in the background (Run keys, Startup folders, Store apps,
    scheduled tasks and services of other publishers), with what is protected and what is recommended to
    turn off. Read only, no administrator needed.
.PARAMETER Disable
    With -Startup only: turns off the entries named by their id, as a run that -Undo restores. Nothing is
    uninstalled or deleted. Takes -WhatIf and -Yes; needs administrator only for entries of the machine.
.PARAMETER ResultId
```

Y reemplazar:

```powershell
    [switch]$List,
    [switch]$Suggest,
    [string]$ResultId,
```

por:

```powershell
    [switch]$List,
    [switch]$Suggest,
    [switch]$Startup,
    [string[]]$Disable = @(),
    [string]$ResultId,
```

- [ ] **Step 6: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Arguments.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (la lista real del runner solo se mira por su forma).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 7: Commit**

```bash
git add tuneup.ps1 engine/Arguments.ps1 engine/Commands.ps1 tests/Arguments.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat(cli): -Startup lista lo que arranca y -Startup -Disable apaga lo elegido"
git log -1 --format=%s
```

---

### Task 11: El perfil `gaming` ofrece la revisión

**Files:**
- Modify: `engine/Catalog.ps1` (`Test-TuneupProfileSet`)
- Modify: `engine/List.ps1` (`Get-TuneupListDocument`)
- Modify: `engine/Commands.ps1` (nueva `Test-TuneupStartupOffered`; `Invoke-TuneupApplyCommand`)
- Modify: `engine/Menu.ps1` (`Invoke-TuneupMenuOptimize`)
- Modify: `profiles/gaming.json`
- Modify: `docs/json-contract.md` (sección `list`)
- Test: `tests/Catalog.Tests.ps1`, `tests/List.Tests.ps1`, `tests/StartupCommand.Tests.ps1`, `tests/JsonContract.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

En `tests/Catalog.Tests.ps1`, reemplazar:

```powershell
    It 'rejects a name used twice' {
        $profiles = @((New-TestProfile -Id 'base'), (New-TestProfile -Id 'dev' -Aliases @('base')))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $Catalog) -join '; ' | Should -Match "name 'base' is used"
    }
```

por:

```powershell
    It 'rejects a name used twice' {
        $profiles = @((New-TestProfile -Id 'base'), (New-TestProfile -Id 'dev' -Aliases @('base')))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $Catalog) -join '; ' | Should -Match "name 'base' is used"
    }
    It 'rejects offersStartup that is not true or false' {
        $profileData = New-TestProfile -Id 'base'
        $profileData | Add-Member -NotePropertyName offersStartup -NotePropertyValue 'yes'
        (Test-TuneupProfileSet -Profiles @($profileData) -Catalog $Catalog) -join '; ' | Should -Match 'profile base offersStartup must be true or false'
    }
```

y reemplazar:

```powershell
    It 'the profiles are valid' {
        $catalog = @(Import-TuneupCatalog -Path (Join-Path $RepoRoot 'catalog'))
        $profiles = @(Import-TuneupProfileSet -Path (Join-Path $RepoRoot 'profiles'))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $catalog) -join "`n" | Should -BeNullOrEmpty
    }
```

por:

```powershell
    It 'the profiles are valid' {
        $catalog = @(Import-TuneupCatalog -Path (Join-Path $RepoRoot 'catalog'))
        $profiles = @(Import-TuneupProfileSet -Path (Join-Path $RepoRoot 'profiles'))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $catalog) -join "`n" | Should -BeNullOrEmpty
    }
    It 'offers the review of what starts with Windows from the gaming profile only' {
        $profiles = @(Import-TuneupProfileSet -Path (Join-Path $RepoRoot 'profiles'))
        @($profiles | Where-Object { $null -ne $_.PSObject.Properties['offersStartup'] -and $_.offersStartup } | ForEach-Object { $_.id }) -join ',' | Should -Be 'gaming'
    }
```

En `tests/List.Tests.ps1`, reemplazar:

```powershell
Describe 'Get-TuneupListDocument' {
```

por:

```powershell
Describe 'Get-TuneupListDocument' {
    It 'says which profiles offer the review of what starts with Windows' {
        $definition = New-TestDefinition
        $definition.Profiles[0] | Add-Member -NotePropertyName offersStartup -NotePropertyValue $true
        $document = Get-TuneupListDocument -Definition $definition -Environment (New-TestEnvironment)
        ($document.profiles | Where-Object { $_.id -eq 'work' }).offersStartup | Should -BeTrue
        ($document.profiles | Where-Object { $_.id -eq 'base' }).offersStartup | Should -BeFalse
    }

```

En `tests/JsonContract.Tests.ps1`, reemplazar:

```powershell
        $paths.list | Should -Contain 'profiles[].needsAdmin'
```

por:

```powershell
        $paths.list | Should -Contain 'profiles[].needsAdmin'
        $paths.list | Should -Contain 'profiles[].offersStartup'
```

Agregar al final de `tests/StartupCommand.Tests.ps1`:

```powershell
Describe 'The review of what starts with Windows, offered by a profile' {
    BeforeAll {
        # The fixture profiles, with extra offering the review.
        $script:OfferingProfiles = Join-Path $TestDrive 'profiles'
        Copy-Item -LiteralPath (Join-Path $Fixtures 'profiles') -Destination $OfferingProfiles -Recurse
        $extra = Join-Path $OfferingProfiles 'extra.json'
        $data = [System.IO.File]::ReadAllText($extra) | ConvertFrom-Json
        $data | Add-Member -NotePropertyName offersStartup -NotePropertyValue $true
        [System.IO.File]::WriteAllText($extra, ($data | ConvertTo-Json -Depth 10))
    }
    BeforeEach { Mock -ModuleName Tuneup Get-TuneupPreflight { } }

    It 'knows which profiles offer it, by id or alias' {
        $gaming = New-TestProfile -Id 'gaming' -Aliases @('juegos')
        $gaming | Add-Member -NotePropertyName offersStartup -NotePropertyValue $true
        $definition = [pscustomobject]@{ Profiles = @((New-TestProfile -Id 'base'), $gaming) }
        Test-TuneupStartupOffered -Definition $definition -ProfileIds @('juegos') | Should -BeTrue
        Test-TuneupStartupOffered -Definition $definition -ProfileIds @('GAMING') | Should -BeTrue
        Test-TuneupStartupOffered -Definition $definition -ProfileIds @('base') | Should -BeFalse
        Test-TuneupStartupOffered -Definition $definition -ProfileIds @() | Should -BeFalse
        Test-TuneupStartupOffered -Definition $definition -ProfileIds @('nope') | Should -BeFalse
    }

    It 'ends the plan of such a profile with the offer, for people only' {
        $context = New-TestContext
        $context.ProfilesPath = $OfferingProfiles
        Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -PlanOnly 6>$null | Out-Null
        $context.ExitCode | Should -Be 0
        $context.Io.Output | Should -Contain (Get-TuneupText -Key 'startup.offer')
        $json = New-TestContext -Json
        $json.ProfilesPath = $OfferingProfiles
        (Invoke-TuneupApplyCommand -Context $json -ProfileIds @('extra') -PlanOnly | ConvertFrom-Json).command | Should -Be 'plan'
        $json.Io.Output | Should -Not -Contain (Get-TuneupText -Key 'startup.offer')
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Catalog.Tests.ps1`
Expected: FAIL en `rejects offersStartup that is not true or false` y en `offers the review ... from the gaming profile only`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/List.Tests.ps1`
Expected: FAIL en `says which profiles offer the review of what starts with Windows`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupCommand.Tests.ps1`
Expected: FAIL en `The review of what starts with Windows, offered by a profile` (`Test-TuneupStartupOffered` no existe).

- [ ] **Step 3: Validar el campo y declararlo en `gaming`**

En `engine/Catalog.ps1`, función `Test-TuneupProfileSet`, reemplazar:

```powershell
        foreach ($field in 'title', 'description') {
            foreach ($lang in 'es', 'en') {
                if ([string]::IsNullOrWhiteSpace([string]$profileData.$field.$lang)) { $errors.Add("profile $profileId is missing $field.$lang") }
            }
        }
```

por:

```powershell
        foreach ($field in 'title', 'description') {
            foreach ($lang in 'es', 'en') {
                if ([string]::IsNullOrWhiteSpace([string]$profileData.$field.$lang)) { $errors.Add("profile $profileId is missing $field.$lang") }
            }
        }
        # Optional: the profile offers the review of what starts with Windows (-Startup) once it is planned.
        $offer = $profileData.PSObject.Properties['offersStartup']
        if ($null -ne $offer -and $offer.Value -isnot [bool]) { $errors.Add("profile $profileId offersStartup must be true or false") }
```

En `profiles/gaming.json`, reemplazar:

```json
  "include": [
    "gaming.game-mode-on",
```

por:

```json
  "offersStartup": true,
  "include": [
    "gaming.game-mode-on",
```

- [ ] **Step 4: Darlo en `-List`**

En `engine/List.ps1`, reemplazar:

```powershell
            tweakCount  = $usable.Count
            needsAdmin  = (@($usable | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_ }).Count -gt 0)
        }
```

por:

```powershell
            tweakCount  = $usable.Count
            needsAdmin  = (@($usable | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_ }).Count -gt 0)
            offersStartup = ($null -ne $profileData.PSObject.Properties['offersStartup'] -and $profileData.offersStartup -eq $true)
        }
```

En `docs/json-contract.md`, sección `list`, reemplazar:

```markdown
| `profiles[].needsAdmin` | boolean | Some of those tweaks need elevation. |
```

por:

```markdown
| `profiles[].needsAdmin` | boolean | Some of those tweaks need elevation. |
| `profiles[].offersStartup` | boolean | The profile offers to review what starts with Windows (`-Startup`) after it is planned or applied (`gaming`). Only an offer: nothing is turned off unless it is named in `-Startup -Disable`. |
```

- [ ] **Step 5: Ofrecerla al planear o aplicar**

En `engine/Commands.ps1`, agregar después de la función `Invoke-TuneupStartupCommand` completa:

```powershell
# True when a profile named by id or alias offers the review of what starts with Windows (offersStartup:
# gaming). A name that is not a profile offers nothing: the plan already said so.
function Test-TuneupStartupOffered {
    param([Parameter(Mandatory)]$Definition, [AllowEmptyCollection()][string[]]$ProfileIds = @())
    foreach ($name in @($ProfileIds | Where-Object { $_ })) {
        $needle = $name.Trim().ToLowerInvariant()
        $profileData = @($Definition.Profiles | Where-Object { $_.id -eq $needle -or @($_.aliases) -contains $needle }) | Select-Object -First 1
        if ($null -eq $profileData) { continue }
        $offer = $profileData.PSObject.Properties['offersStartup']
        if ($null -ne $offer -and $offer.Value -eq $true) { return $true }
    }
    $false
}
```

En la función `Invoke-TuneupApplyCommand`, reemplazar:

```powershell
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $ProfileIds -Include $Include -Exclude $Exclude
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
}
```

por:

```powershell
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $ProfileIds -Include $Include -Exclude $Exclude
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
    # For people only: the JSON says it in profiles[].offersStartup of -List.
    if (-not $Context.Json -and $Context.ExitCode -ne 1 -and (Test-TuneupStartupOffered -Definition $definition -ProfileIds $ProfileIds)) {
        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'startup.offer')
    }
}
```

En `engine/Menu.ps1`, función `Invoke-TuneupMenuOptimize`, reemplazar:

```powershell
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $profileIds -Include $highRisk -Exclude $declined
    $Context.Pause = $true
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request
}
```

por:

```powershell
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $profileIds -Include $highRisk -Exclude $declined
    $Context.Pause = $true
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request
    if ($Context.ExitCode -ne 1 -and (Test-TuneupStartupOffered -Definition $definition -ProfileIds $profileIds)) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'startup.offer')
    }
}
```

- [ ] **Step 6: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Catalog.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/List.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StartupCommand.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/JsonContract.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: PASS (los perfiles de prueba no ofrecen la revisión: el menú no escribe una línea más).

- [ ] **Step 7: Commit**

```bash
git add engine/Catalog.ps1 engine/List.ps1 engine/Commands.ps1 engine/Menu.ps1 profiles/gaming.json docs/json-contract.md tests/Catalog.Tests.ps1 tests/List.Tests.ps1 tests/StartupCommand.Tests.ps1 tests/JsonContract.Tests.ps1
git commit -m "feat(perfiles): gaming ofrece revisar lo que arranca con Windows, sin apagar nada"
git log -1 --format=%s
```

---

### Task 12: Opción del menú "Lo que arranca con Windows"

**Files:**
- Modify: `engine/Menu.ps1` (`Write-TuneupMenuHeader`, `Invoke-TuneupMenu`, nueva `Invoke-TuneupMenuStartup`)
- Test: `tests/Menu.Tests.ps1`

Las claves `menu.main.startup` y `menu.startup.*` vienen de la Task 3.

**Al escribir esta tarea (decisión 39):** cada número que elige la persona se resuelve al objeto de la entrada que mostró el menú y de ahí a su id; nunca se busca la entrada por id en otra lista. Las entradas con motivo `ambiguous` no se ofrecen (no son apagables), y `-Startup -Disable` vuelve a leer las entradas y las rechaza igual.

- [ ] **Step 1: Escribir las pruebas que fallan**

Agregar al final de `tests/Menu.Tests.ps1`:

```powershell
Describe 'Invoke-TuneupMenu: what starts with Windows' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        New-Item -Path $Key -Force | Out-Null
        $steam = New-TuneupStartupEntry -Source 'run-user' -Key 'Steam' -Name 'Steam' -Target @{ ApprovedPath = "$Key\StartupApproved\Run"; ApprovedName = 'Steam' }
        $steam.canDisable = $true
        $steam.recommended = $true
        $steam.recommendedReason = 'game-launcher'
        $tray = New-TuneupStartupEntry -Source 'run-machine' -Key 'Tray' -Name 'Tray' -Target @{ ApprovedPath = 'HKLM:\Software\windows-tuneup-test\StartupApproved\Run'; ApprovedName = 'Tray' }
        $tray.canDisable = $true
        $vpn = New-TuneupStartupEntry -Source 'run-user' -Key 'GlobalProtect' -Name 'GlobalProtect'
        $vpn.protected = 'vpn'
        $script:StartupEntries = @($steam, $tray, $vpn)
        Mock -ModuleName Tuneup Get-TuneupStartupEntry { $script:StartupEntries }
        Mock -ModuleName Tuneup Get-TuneupPreflight { }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'offers it in the main menu' {
        $context = New-MenuContext @('0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 6\. What starts with Windows: see it and turn off what you choose'
    }

    It 'turns off only what was picked, the recommended first and nothing picked beforehand, after the plan and a yes' {
        $context = New-MenuContext @('6', '1', '', 'y', '', '0')
        Invoke-Menu $context
        $context.ExitCode | Should -Be 0
        $context.Io.Pending.Count | Should -Be 0
        $text = Get-Output $context
        $text | Should -Match ([regex]::Escape((Get-TuneupText -Key 'menu.startup.header')))
        $text | Should -Match '\[ \]  1\. Steam \[recommended: game launcher\]'
        $text | Should -Match '\[ \]  2\. Tray \(administrator\)'
        # A protected entry is in the table, never among what can be picked.
        $text | Should -Not -Match '\d\. GlobalProtect'
        ([byte[]](Get-Item -LiteralPath "$Key\StartupApproved\Run").GetValue('Steam'))[0] | Should -Be 3
        $text | Should -Match ([regex]::Escape((Get-TuneupText -Key 'startup.nextStart')))
    }

    It 'goes back without changing anything when nothing is picked' {
        $context = New-MenuContext @('6', '', '', '0')
        Invoke-Menu $context
        $context.Io.Pending.Count | Should -Be 0
        Test-Path -LiteralPath "$Key\StartupApproved" | Should -BeFalse
    }

    It 'says that an entry of the machine needs administrator, and changes nothing' {
        $context = New-MenuContext @('6', '2', '', '', '0')
        Invoke-Menu $context
        $context.Io.Pending.Count | Should -Be 0
        Get-Output $context | Should -Match ([regex]::Escape((Get-TuneupText -Key 'menu.startup.needsAdmin')))
        Test-Path -LiteralPath 'HKLM:\Software\windows-tuneup-test\StartupApproved' | Should -BeFalse
    }

    It 'says when nothing can be turned off' {
        $script:StartupEntries = @($script:StartupEntries | Where-Object { $_.protected })
        $context = New-MenuContext @('6', '', '0')
        Invoke-Menu $context
        $context.Io.Pending.Count | Should -Be 0
        Get-Output $context | Should -Match ([regex]::Escape((Get-TuneupText -Key 'menu.startup.none')))
    }
}
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: FAIL en `Invoke-TuneupMenu: what starts with Windows` (la opción 6 no existe: "That is not one of the options").

- [ ] **Step 3: Implementar**

En `engine/Menu.ps1`, función `Write-TuneupMenuHeader`, reemplazar:

```powershell
    foreach ($key in 'menu.main.optimize', 'menu.main.status', 'menu.main.undo', 'menu.main.health', 'menu.main.measure', 'menu.main.exit') {
```

por:

```powershell
    foreach ($key in 'menu.main.optimize', 'menu.main.status', 'menu.main.undo', 'menu.main.health', 'menu.main.measure', 'menu.main.startup', 'menu.main.exit') {
```

En la función `Invoke-TuneupMenu`, reemplazar:

```powershell
                '5' { 'Measure' }
```

por:

```powershell
                '5' { 'Measure' }
                '6' { 'Startup' }
```

Y agregar, antes del comentario `# The status, and when Windows reverted something, the offer to apply it again.`:

```powershell
# What starts with Windows: the table of -Startup, then the entries to turn off, picked by number among
# the ones that can be turned off (recommended first, none picked beforehand), and the plan and the
# confirmation of -Startup -Disable. What needs administrator is not turned off from a menu that is not
# elevated: it says so and goes back, changing nothing.
function Invoke-TuneupMenuStartup {
    param([Parameter(Mandatory)]$Context)
    $Context.Pause = $true
    Invoke-TuneupStartupCommand -Context $Context
    $document = $Context.Result
    if ($Context.ExitCode -ne 0 -or $null -eq $document) { return }
    $entries = @($document.entries)
    $choices = @($entries | Where-Object { $_.canDisable -and $_.recommended }) + @($entries | Where-Object { $_.canDisable -and -not $_.recommended })
    if (-not $choices.Count) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.startup.none')
        return
    }
    $adminMark = ' ' + (Get-TuneupText -Key 'menu.profile.admin')
    $lines = @(foreach ($entry in $choices) {
            $recommended = $(if ($entry.recommended) { Get-TuneupText -Key 'menu.startup.recommended' -Format (Get-TuneupText -Key "startup.recommend.$($entry.recommendedReason)") } else { '' })
            '{0}{1}{2}' -f $entry.name, $recommended, $(if ($entry.needsAdmin) { $adminMark } else { '' })
        })
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.startup.header')
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen -or -not @($chosen).Count) { return }
    $picked = @($chosen | ForEach-Object { $choices[$_] })
    if (-not (Get-TuneupContextEnvironment -Context $Context).IsAdmin -and @($picked | Where-Object { $_.needsAdmin }).Count) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.startup.needsAdmin')
        return
    }
    Invoke-TuneupStartupCommand -Context $Context -Disable @($picked | ForEach-Object { [string]$_.id })
}

```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: PASS (las pruebas anteriores no cambian: `9` sigue siendo una opción que no existe).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 5: Commit**

```bash
git add engine/Menu.ps1 tests/Menu.Tests.ps1
git commit -m "feat(menú): opción para ver lo que arranca con Windows y apagar lo que se elija"
git log -1 --format=%s
```

---

### Task 13: Contrato JSON del documento `startup`

**Files:**
- Modify: `docs/json-contract.md`
- Test: `tests/JsonContract.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

En `tests/JsonContract.Tests.ps1`, reemplazar:

```powershell
        $Documents.list = Write-TuneupListReport -Document (Get-TuneupListDocument -Definition $listDefinition -Environment (New-TestEnvironment)) -Json | ConvertFrom-Json
```

por:

```powershell
        $Documents.list = Write-TuneupListReport -Document (Get-TuneupListDocument -Definition $listDefinition -Environment (New-TestEnvironment)) -Json | ConvertFrom-Json
        # One startup entry with every field filled, so every field of the document is checked.
        $startupEntry = New-TuneupStartupEntry -Source 'run-user' -Key 'Steam' -Name 'Steam' -Command '"C:\Games\Steam\steam.exe"' -Path 'C:\Games\Steam\steam.exe'
        $startupEntry.publisher = 'Valve Corp.'
        $startupEntry.running = $true
        $startupEntry.memoryMB = 220
        $startupEntry.cpuSeconds = 10
        $startupEntry.canDisable = $true
        $startupEntry.recommended = $true
        $startupEntry.recommendedReason = 'game-launcher'
        $startupEntry.uninstall = 'winget uninstall --id Valve.Steam --exact'
        $Documents.startup = Write-TuneupStartupReport -Document (Get-TuneupStartupDocument -Entry @($startupEntry) -IsAdmin $false) -Json | ConvertFrom-Json
```

Reemplazar:

```powershell
        $paths.suggest | Should -Contain 'questions[].text'
```

por:

```powershell
        $paths.suggest | Should -Contain 'questions[].text'
        $paths.startup | Should -Contain 'entries[].recommendedReason'
        $paths.startup | Should -Contain 'summary.protected'
        $paths.startup | Should -Contain 'workPc'
        $paths.startup | Should -Contain 'entries[].notRecommendedReason'
        (Get-ContractSection 'error').Contains('`session-user`') | Should -BeTrue
```

Y reemplazar:

```powershell
        @{ Command = 'suggest' }
        @{ Command = 'error' }
```

por:

```powershell
        @{ Command = 'suggest' }
        @{ Command = 'startup' }
        @{ Command = 'error' }
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/JsonContract.Tests.ps1`
Expected: FAIL (`docs/json-contract.md has no section ## `startup``, y `session-user` falta en `error`).

- [ ] **Step 3: Documentar**

En `docs/json-contract.md`:

1. En la regla de `-ResultId` (sección "Rules"), reemplazar:

```markdown
(`warnings`, `message`, `details`, `runDir`, `path`, `error`, `detail`, `output`, `repairedFiles`, `unrepairedFiles`)
```

por:

```markdown
(`warnings`, `message`, `details`, `runDir`, `path`, `command` (the command line of a startup entry; the `command` of a document is one word and never changes), `error`, `detail`, `output`, `repairedFiles`, `unrepairedFiles`)
```

2. En la tabla de comandos, reemplazar:

```markdown
| `-Suggest -Json` | `suggest` |
```

por:

```markdown
| `-Suggest -Json` | `suggest` |
| `-Startup -Json` | `startup` |
| `-Startup -Disable <ids> -WhatIf -Json` or `-Startup -Disable <ids> -Yes -Json` | `plan` or `apply`, with `source` = `startup` (without `-WhatIf` or `-Yes`, something to turn off ends in an `error`; an entry already off is an item skipped as `already-applied`) |
```

3. En "Reading a result", reemplazar:

```markdown
- It excludes every other command (`-Status`, `-Undo`, `-Health`, `-Measure`, `-List`, `-Suggest`), the options of applying, and `-ResultId`
```

por:

```markdown
- It excludes every other command (`-Status`, `-Undo`, `-Health`, `-Measure`, `-List`, `-Suggest`, `-Startup`), the options of applying, and `-ResultId`
```

4. En la sección `plan`, reemplazar:

```markdown
| `source` | string | `profiles` (profiles and lists) or `reapply` (`-Status -Reapply`). |
```

por:

```markdown
| `source` | string | `profiles` (profiles and lists), `reapply` (`-Status -Reapply`) or `startup` (`-Startup -Disable`: each item is a startup entry, with its name as `title`; see `startup`). |
```

5. En la sección `apply`, reemplazar:

```markdown
| `source` | string | `profiles` or `reapply`. |
```

por:

```markdown
| `source` | string | `profiles`, `reapply` or `startup`. |
```

6. En la sección `status`, reemplazar:

```markdown
| `items[].id` | string | Tweak id. |
| `items[].title` | string | Tweak title. |
| `items[].status` | string | `ok` (still applied), `drift` (Windows reverted it: `-Status -Reapply` applies it again), `not-present`, `unknown` (could not be read), `needs-admin` (only readable elevated). |
```

por:

```markdown
| `items[].id` | string | Tweak id; `startup.<source>.<slug>-<hash>` for a startup entry turned off with `-Startup -Disable`. |
| `items[].title` | string | Tweak title (the name of a startup entry). |
| `items[].status` | string | `ok` (still applied), `drift` (Windows reverted it: `-Status -Reapply` applies it again; a startup entry that turned itself on again is left out of the re-apply with a warning, and is turned off again with `-Startup -Disable`), `not-present`, `unknown` (could not be read), `needs-admin` (only readable elevated). |
```

7. Agregar, antes de `## \`error\``, la sección nueva:

```markdown
## `startup`

What starts with Windows or runs in the background, from `-Startup -Json`. Read only, no elevation needed, nothing is sent anywhere. Exit code `0` (`1` with an `error` only for parameters it does not take). A source that cannot be read (a detector that fails) leaves out its entries and adds a warning; the document is still written. Without elevation Windows hides some scheduled tasks: a warning says so. The services, drivers and scheduled tasks of Windows are not listed (signed by Windows, or under `\Microsoft\`); the entries of Windows in the other sources are, as protected.

To turn entries off: `-Startup -Disable '<ids>'` with `-WhatIf` or `-Yes`, which give the `plan` and `apply` documents with `source` = `startup`. Each entry becomes a tweak of type `registry` (its `StartupApproved` value, or the `State` of a Store task), `task` (disabled) or `service` (Manual, never Disabled, and not stopped), with the `id` of the entry, so `-Status` and `-Undo` show and restore it like any tweak. `-Status` reads a `StartupApproved` entry only as on or off (its first byte), never by the date Task Manager writes, so turning it off again from Task Manager is not a drift; `-Undo` gives back the exact bytes it found. Nothing is uninstalled or deleted, and the change takes effect the next time Windows or the session starts. An id that is not in the list now, or that names an entry with `canDisable` false, ends in an `error` (exit `1`; `details` says why for each entry that stays on) and nothing is done. Elevated with another administrator's password, an id of an entry of the user is an `error` with `reason` = `session-user`.

| Field | Type | Meaning |
|---|---|---|
| `isAdmin` | boolean | The list was read elevated (without it, Windows hides some scheduled tasks). |
| `workPc` | boolean | A work PC: managed (domain or MDM) or joined to Entra ID, the same rule as the `work` signal of `suggest`. There OneDrive, Teams and Outlook are not recommended (`entries[].notRecommendedReason`). |
| `entries` | object[] | Every entry, in the order of the sources. |
| `entries[].id` | string | `startup.<source>.<slug>-<hash>`, the same in every run, elevated or not: what `-Disable` takes (`^startup\.[a-z0-9-]+\.[a-z0-9-]+$`). |
| `entries[].name` | string | What Windows shows: the name of the `Run` value, the file of the Startup folder without its extension, the name of the Store app, the task, or the display name of the service. Not translated. |
| `entries[].source` | string | `run-user`, `run-machine`, `run32-machine`, `runonce-user`, `runonce-machine`, `runonce32-machine`, `policy-user`, `policy-machine`, `folder-user`, `folder-machine`, `store-app`, `task`, `service`, `driver`. |
| `entries[].scope` | string | `user` or `machine`. |
| `entries[].key` | string | Where it is: the name of the value, the file name, `<package family>\<task id>`, the folder and name of the task, or the name of the service. |
| `entries[].publisher` | string or null | Who signed its program (a valid Authenticode signature), or the publisher of the Store package; null when it is not signed, cannot be read, or runs through a host program (`rundll32.exe`, `cmd.exe`, `powershell.exe`...). |
| `entries[].command` | string or null | The command line, as Windows keeps it. |
| `entries[].path` | string or null | The program it runs, as a full path. |
| `entries[].enabled` | boolean | It starts now; `false` when it was turned off (Task Manager, Settings, this tool) or the task is disabled. |
| `entries[].running` | boolean or null | Its program runs now; null when that cannot be known (the processes could not be read, or a host program). Best effort: without elevation Windows does not give the path of some processes. |
| `entries[].memoryMB` | number or null | Working set of its processes, in MB. |
| `entries[].cpuSeconds` | number or null | CPU time its processes used since they started, in seconds (not a percentage). |
| `entries[].protected` | string or null | Why it stays on: `policy`, `driver`, `windows-component`, `security` (antivirus or firewall), `vpn`, `device` (helpers of the audio, touchpad, Fn-key, display and pen drivers; never the companion apps of the vendor), `updates` (the updaters of browsers and of Office: protected even though they are updaters, because they bring security patches). The rules, each with its `why`, are `catalog/startup/rules.json` of the installed copy. |
| `entries[].canDisable` | boolean | It is on and `-Disable` can turn it off: not protected, not run once (`runonce-*`: Windows deletes it after it runs) and, for a task, without `*`, `?`, `[` or `]` in its folder or name. |
| `entries[].needsAdmin` | boolean | Turning it off needs elevation (`scope` = `machine`). |
| `entries[].recommended` | boolean | Turning it off is recommended. Only a mark: nothing is turned off unless it is named in `-Disable`. |
| `entries[].recommendedReason` | string or null | `updater`, `game-launcher`, `sync-client`, `chat-helper` (chat or mail), `companion-app` (companion app of a hardware vendor: overlay, lighting, driver downloads). |
| `entries[].notRecommendedReason` | string or null | Why an entry that a rule would recommend is not recommended: `work-app` (OneDrive, Teams or Outlook on a work PC). It can still be turned off. |
| `entries[].uninstall` | string or null | `winget uninstall --id <id> --exact` for a recommended program whose winget id is known: to show, never run by the tool. |
| `summary` | object | Counts. |
| `summary.total` | number | Entries. |
| `summary.enabled` | number | Entries that start now. |
| `summary.canDisable` | number | Entries that `-Disable` can turn off. |
| `summary.recommended` | number | Entries marked recommended. |
| `summary.protected` | number | Protected entries. |

```

8. En la sección `error`, reemplazar:

```markdown
| `reason` | string | A stable token for programs, only in some errors (absent otherwise): `needs-admin` (`-Undo` of a run with system changes, or `-Health`, without elevation: run it elevated), and the errors of `-ReadResult`: `result-missing`, `result-incomplete` or `result-untrusted` (see "Reading a result"). Never changes with the language; decide by it, not by `message`. |
```

por:

```markdown
| `reason` | string | A stable token for programs, only in some errors (absent otherwise): `needs-admin` (`-Undo` of a run with system changes, or `-Health`, without elevation: run it elevated), `session-user` (`-Startup -Disable` of an entry of the user, elevated with another administrator's password: turn it off without elevation), and the errors of `-ReadResult`: `result-missing`, `result-incomplete` or `result-untrusted` (see "Reading a result"). Never changes with the language; decide by it, not by `message`. |
```

- [ ] **Step 4: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/JsonContract.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/json-contract.md tests/JsonContract.Tests.ps1
git commit -m "docs(contrato): documento startup, origen startup del plan y motivo session-user"
git log -1 --format=%s
```

---

### Task 14: README, perfiles y lista negra

**Files:**
- Modify: `README.md`
- Modify: `docs/es/profiles.md`, `docs/en/profiles.md`
- Modify: `docs/es/blacklist.md`, `docs/en/blacklist.md`
- Test: `tests/Docs.Tests.ps1`

- [ ] **Step 1: Escribir la prueba que falla**

En `tests/Docs.Tests.ps1`, reemplazar:

```powershell
Describe 'Blacklist' {
```

por:

```powershell
Describe 'Blacklist' {
    It 'says what -Startup never turns off, in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'blacklist.md'
            foreach ($term in '-Startup', 'catalog/startup/rules.json', 'StartupApproved', 'winget uninstall', 'Click-to-Run') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }

```

- [ ] **Step 2: Correr la prueba y ver que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: FAIL en `says what -Startup never turns off, in both languages`.

- [ ] **Step 3: Lista negra**

Agregar al final de `docs/es/blacklist.md`:

```markdown

## Lo que `-Startup` nunca apaga

`-Startup -Disable` apaga lo que arranca con Windows sin desinstalar ni borrar nada: escribe el valor de `StartupApproved` que usa el Administrador de tareas, deshabilita la tarea o pasa el servicio a Manual, y `-Undo` lo devuelve. Nunca lo hace con lo que muestra como protegido (reglas en `catalog/startup/rules.json`, revisables):

| Qué | Por qué no |
|---|---|
| Componentes de Windows (firmados por Windows) y los servicios de esta lista | Windows los necesita; los servicios de seguridad y de actualización siguen la regla de arriba |
| Antivirus, firewall y lo que registra el Centro de seguridad de Windows | Dejan el equipo expuesto |
| Clientes VPN | Cortan el acceso a la red de la organización |
| Ayudantes de los controladores (consola y servicios de audio, panel táctil, teclas Fn, servicios de pantalla y de lápiz) y los controladores | Se pierden teclas, sonido, gestos o modos de pantalla. Las apps de acompañamiento del fabricante (GeForce Experience o NVIDIA app, AMD Software, Armoury Crate, G HUB...) no se protegen: se pueden apagar y salen recomendadas |
| Actualizadores de navegadores y de Office (Edge, Chrome, Firefox, Brave, Click-to-Run) | Se protegen aunque sean actualizadores: sin ellos el navegador y Office no reciben parches de seguridad, igual que con Windows Update. Los actualizadores de otros programas sí se pueden apagar |
| Lo que fija una directiva de la organización | La organización lo decide |
| Lo que corre una sola vez (`RunOnce`) | Apagarlo sería borrarlo |

Un servicio nunca pasa a Deshabilitado, solo a Manual. Lo recomendado es solo una marca: nada se apaga sin que lo elijas. Para desinstalar un programa la herramienta solo muestra el comando (`winget uninstall --id <id> --exact`); nunca lo corre.
```

Agregar al final de `docs/en/blacklist.md`:

```markdown

## What `-Startup` never turns off

`-Startup -Disable` turns off what starts with Windows without uninstalling or deleting anything: it writes the `StartupApproved` value that Task Manager uses, disables the task or sets the service to Manual, and `-Undo` gives it back. It never does so with what it shows as protected (rules in `catalog/startup/rules.json`, open to review):

| What | Why not |
|---|---|
| Parts of Windows (signed by Windows) and the services of this list | Windows needs them; the security and update services follow the rule above |
| Antivirus, firewall and what Windows Security Center lists | They leave the machine exposed |
| VPN clients | They cut the access to the network of the organization |
| Helpers of the drivers (audio console and services, touchpad, Fn keys, display and pen services) and the drivers | Keys, sound, gestures or display modes stop working. The companion apps of the vendor (GeForce Experience or NVIDIA app, AMD Software, Armoury Crate, G HUB...) are not protected: they can be turned off and are recommended |
| Updaters of browsers and of Office (Edge, Chrome, Firefox, Brave, Click-to-Run) | Protected even though they are updaters: without them the browser and Office get no security patches, as with Windows Update. The updaters of other programs can be turned off |
| What a policy of the organization sets | The organization decides it |
| What runs only once (`RunOnce`) | Turning it off would mean deleting it |

A service is never set to Disabled, only to Manual. What is recommended is only a mark: nothing is turned off unless you choose it. To uninstall a program the tool only shows the command (`winget uninstall --id <id> --exact`); it never runs it.
```

- [ ] **Step 4: Perfiles**

En `docs/es/profiles.md`, reemplazar:

```markdown
**Riesgo alto, solo con `-Include`:** `gaming.memory-integrity-off` (integridad de memoria): puede dar entre 1 y 15 % más de FPS en algunos juegos a cambio de menos protección contra drivers maliciosos.
```

por:

```markdown
**Riesgo alto, solo con `-Include`:** `gaming.memory-integrity-off` (integridad de memoria): puede dar entre 1 y 15 % más de FPS en algunos juegos a cambio de menos protección contra drivers maliciosos.

**Ofrece revisar lo que arranca con Windows** (`offersStartup`): al planear o aplicar `gaming` termina con una línea que sugiere `.\tuneup.ps1 -Startup`, donde los lanzadores de juegos, los clientes de sincronización y los chats que arrancan solos salen recomendados. No apaga nada: cada entrada se elige con `-Startup -Disable '<id>'`.
```

En `docs/en/profiles.md`, reemplazar:

```markdown
**High risk, only with `-Include`:** `gaming.memory-integrity-off` (memory integrity): it can give 1 to 15% more FPS in some games in exchange for less protection against malicious drivers.
```

por:

```markdown
**High risk, only with `-Include`:** `gaming.memory-integrity-off` (memory integrity): it can give 1 to 15% more FPS in some games in exchange for less protection against malicious drivers.

**Offers to review what starts with Windows** (`offersStartup`): planning or applying `gaming` ends with a line that suggests `.\tuneup.ps1 -Startup`, where game launchers, sync clients and chats that start on their own are recommended. It turns nothing off: each entry is chosen with `-Startup -Disable '<id>'`.
```

- [ ] **Step 5: README**

En `README.md`:

1. En la tabla de parámetros, reemplazar:

```markdown
| `-Json` | Salida como un documento JSON (ver abajo). / Output as one JSON document (see below). |
```

por:

```markdown
| `-Startup [-Disable <ids>]` | Lo que arranca con Windows o queda en segundo plano, con lo protegido y lo recomendado; con `-Disable`, apaga lo que elijas por su id (acepta `-WhatIf` y `-Yes`; nada se desinstala y `-Undo` lo vuelve a encender). / What starts with Windows or runs in the background, with what is protected and what is recommended; with `-Disable`, turns off what you choose by its id (takes `-WhatIf` and `-Yes`; nothing is uninstalled and `-Undo` turns it on again). |
| `-Json` | Salida como un documento JSON (ver abajo). / Output as one JSON document (see below). |
```

2. Reemplazar:

```markdown
`-Suggest` y `-ReadResult` se excluyen entre sí y no se combinan con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` ni `-Yes` (salvo `-Status -Reapply`, que acepta `-Yes`, `-WhatIf` e `-Include`). `-Tweak` exige `-Undo`,
```

por:

```markdown
`-Suggest`, `-Startup` y `-ReadResult` se excluyen entre sí y no se combinan con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` ni `-Yes` (salvo `-Status -Reapply`, que acepta `-Yes`, `-WhatIf` e `-Include`, y `-Startup -Disable`, que acepta `-Yes` y `-WhatIf`). `-Tweak` exige `-Undo`, `-Disable` exige `-Startup`,
```

y reemplazar:

```markdown
`-Suggest` and `-ReadResult` exclude each other and cannot be combined with `-Profile`, `-Include`, `-Exclude`, `-WhatIf` or `-Yes` (except `-Status -Reapply`, which takes `-Yes`, `-WhatIf` and `-Include`). `-Tweak` requires `-Undo`,
```

por:

```markdown
`-Suggest`, `-Startup` and `-ReadResult` exclude each other and cannot be combined with `-Profile`, `-Include`, `-Exclude`, `-WhatIf` or `-Yes` (except `-Status -Reapply`, which takes `-Yes`, `-WhatIf` and `-Include`, and `-Startup -Disable`, which takes `-Yes` and `-WhatIf`). `-Tweak` requires `-Undo`, `-Disable` requires `-Startup`,
```

3. En "Qué hace hoy / What works today", reemplazar:

```markdown
- Si `-Undo` no puede restaurar un ajuste, muestra cómo hacerlo a mano
```

por:

```markdown
- `-Startup` lista lo que arranca con Windows o queda en segundo plano (claves Run y RunOnce, carpetas Inicio, apps de la Store, tareas programadas y servicios de terceros) con su editor, si corre y cuánta memoria usa; marca lo protegido (Windows, seguridad, VPN, ayudantes de controladores, actualizadores de navegadores y de Office, directivas) y lo recomendado (actualizadores, lanzadores de juegos, sincronización, chats, apps de acompañamiento del fabricante; en un equipo de trabajo, OneDrive, Teams y Outlook no se recomiendan), con el comando de winget para desinstalar cuando se conoce, que nunca corre. `-Startup -Disable '<ids>'` apaga solo lo que elijas, como el Administrador de tareas, sin borrar nada: es una corrida más, que `-Status` revisa y `-Undo` revierte.
  `-Startup` lists what starts with Windows or runs in the background (Run and RunOnce keys, Startup folders, Store apps, scheduled tasks and services of other publishers) with its publisher, whether it runs and how much memory it uses; it marks what is protected (Windows, security, VPN, driver helpers, updaters of browsers and of Office, policies) and what is recommended (updaters, game launchers, sync, chats, companion apps of vendors; on a work PC, OneDrive, Teams and Outlook are not recommended), with the winget command to uninstall when it is known, which it never runs. `-Startup -Disable '<ids>'` turns off only what you choose, as Task Manager does, deleting nothing: it is one more run, which `-Status` checks and `-Undo` reverts.
- Si `-Undo` no puede restaurar un ajuste, muestra cómo hacerlo a mano
```

4. En "Limitaciones conocidas / Known limitations", reemplazar:

```markdown
- Todo queda local: no se envía nada a ningún servidor.
```

por:

```markdown
- `-Startup` sin administrador no ve algunas tareas programadas, y la memoria de los programas de otras cuentas o elevados puede faltar. Un servicio que `-Startup -Disable` pasó a Manual deja de listarse. Una app de la Store cuya tarea de inicio nunca se encendió no se lista (no arranca).
  Without administrator `-Startup` does not see some scheduled tasks, and the memory of programs of other accounts or elevated ones may be missing. A service that `-Startup -Disable` set to Manual is no longer listed. A Store app whose startup task was never turned on is not listed (it does not start).
- Todo queda local: no se envía nada a ningún servidor.
```

5. En "Salida JSON / JSON output", reemplazar:

```markdown
| `plan` | `source` (`profiles`, `reapply`),
```

por:

```markdown
| `plan` | `source` (`profiles`, `reapply`, `startup`),
```

reemplazar:

```markdown
| `list` | `profiles` (`id`, `aliases`, `title`, `description`, `tweakCount`, `needsAdmin`),
```

por:

```markdown
| `list` | `profiles` (`id`, `aliases`, `title`, `description`, `tweakCount`, `needsAdmin`, `offersStartup`),
```

reemplazar:

```markdown
| `suggest` | `signals` (`id`, `detected`, `evidence`), `suggestions` (`profile`, `signals`), `questions` (`id`, `text`) |
```

por:

```markdown
| `suggest` | `signals` (`id`, `detected`, `evidence`), `suggestions` (`profile`, `signals`), `questions` (`id`, `text`) |
| `startup` | `isAdmin`, `entries` (`id`, `name`, `source`, `scope`, `key`, `publisher`, `command`, `path`, `enabled`, `running`, `memoryMB`, `cpuSeconds`, `protected`, `canDisable`, `needsAdmin`, `recommended`, `recommendedReason`, `uninstall`), `summary` (`total`, `enabled`, `canDisable`, `recommended`, `protected`) |
```

y reemplazar:

```markdown
`result-missing`, `result-incomplete`, `result-untrusted` (`-ReadResult`); los demás errores no lo traen / absent in other errors |
```

por:

```markdown
`result-missing`, `result-incomplete`, `result-untrusted` (`-ReadResult`), `session-user` (`-Startup -Disable` elevado con otra cuenta / elevated as another account); los demás errores no lo traen / absent in other errors |
```

6. En "Menú / Menu", reemplazar:

```markdown
Salud (y reparar si hace falta) y Medir.
```

por:

```markdown
Salud (y reparar si hace falta), Medir y Lo que arranca con Windows (la lista de `-Startup` y apagar lo que elijas).
```

y reemplazar:

```markdown
Health (and repair when needed) and Measure.
```

por:

```markdown
Health (and repair when needed), Measure and What starts with Windows (the list of `-Startup`, and turning off what you choose).
```

7. En "Skill de Claude / Claude skill", reemplazar:

```markdown
y en un equipo administrado avisa antes que nada. El zip de la release no lleva el plugin.
```

por:

```markdown
y en un equipo administrado avisa antes que nada. También ofrece revisar lo que arranca con Windows (`-Startup`): marca lo recomendado, pero solo apaga lo que elijas, uno por uno, y nunca desinstala. El zip de la release no lleva el plugin.
```

y reemplazar:

```markdown
and on a managed PC it warns before anything else. The release zip does not include the plugin.
```

por:

```markdown
and on a managed PC it warns before anything else. It also offers to review what starts with Windows (`-Startup`): it marks what is recommended, but turns off only what you choose, one by one, and never uninstalls. The release zip does not include the plugin.
```

- [ ] **Step 6: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: PASS (los enlaces nuevos no hay; los documentos siguen en UTF-8 sin BOM).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Package.Tests.ps1`
Expected: PASS (el README no enlaza archivos nuevos).

- [ ] **Step 7: Commit**

```bash
git add README.md docs/es/profiles.md docs/en/profiles.md docs/es/blacklist.md docs/en/blacklist.md tests/Docs.Tests.ps1
git commit -m "docs: -Startup en el README, los perfiles y lo que nunca apaga en la lista negra"
git log -1 --format=%s
```

---

### Task 15: La skill ofrece revisar lo que arranca con Windows

**Files:**
- Modify: `plugins/windows-tuneup/skills/windows-tuneup/SKILL.md`
- Modify: `plugins/windows-tuneup/skills/windows-tuneup/reference/commands.md`
- Modify: `plugins/windows-tuneup/skills/windows-tuneup/reference/reading-json.md`
- Test: `tests/Plugin.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

En `tests/Plugin.Tests.ps1`, reemplazar:

```powershell
        foreach ($expected in 'List', 'Suggest', 'WhatIf', 'Yes', 'Json', 'ResultId', 'ReadResult', 'Undo', 'Tweak', 'Health', 'Repair', 'Measure',
            'Compare', 'IdleSeconds', 'Status', 'Reapply', 'Include', 'Exclude', 'Lang', 'Profile') {
```

por:

```powershell
        foreach ($expected in 'List', 'Suggest', 'WhatIf', 'Yes', 'Json', 'ResultId', 'ReadResult', 'Undo', 'Tweak', 'Health', 'Repair', 'Measure',
            'Compare', 'IdleSeconds', 'Status', 'Reapply', 'Include', 'Exclude', 'Lang', 'Profile', 'Startup', 'Disable') {
```

Reemplazar:

```powershell
            "-Status -Reapply -Include 'lite.xbox-app,base.ads' -Yes -Json -Lang en", '-Health -Repair -Json -Lang es') {
```

por:

```powershell
            "-Status -Reapply -Include 'lite.xbox-app,base.ads' -Yes -Json -Lang en", '-Health -Repair -Json -Lang es',
            "-Startup -Disable 'startup.run-machine.vendor-tray-1a2b3c4d,startup.service.vendorsvc-0f0f0f0f' -Yes -Json -Lang en") {
```

Reemplazar:

```powershell
        @{ Phrase = 'Put on a command line only ids that the tool gave you, each checked against its form' }
    ) {
```

por:

```powershell
        @{ Phrase = 'Put on a command line only ids that the tool gave you, each checked against its form' }
        @{ Phrase = 'Turn off a startup entry only when the user chose that entry' }
    ) {
```

Y agregar, antes de `It 'links only to files that exist' {`:

```powershell
    It 'turns off startup entries only when the user chose each one, and never runs the uninstall command' {
        foreach ($term in 'a `recommended` mark is never a choice', 'never run the `uninstall` command', 'whose `canDisable` is false',
            'Do we review what starts with Windows?', '`offersStartup`', "-Startup -Disable '<ids>' -WhatIf -Json", 'Never elevate the ones of the user',
            '`-Startup -Json`', 'protected even though they are updaters', '`notRecommendedReason` = `work-app`') {
            $Skill.Contains($term) | Should -BeTrue -Because $term
        }
        foreach ($term in '`-Startup -Json`', "-Startup -Disable '<ids>' -Yes -Json", '^startup\.[a-z0-9-]+\.[a-z0-9-]+$', '`entries` in `-Startup -Json`') {
            $Commands.Contains($term) | Should -BeTrue -Because $term
        }
        # The uninstall command is shown as text, never run: no line of code of the skill runs winget uninstall.
        foreach ($line in @($SkillLines | Where-Object { $_.Fenced })) {
            $line.Text | Should -Not -Match '(?i)winget\s+uninstall' -Because "$($line.File): $($line.Text)"
        }
    }

```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Plugin.Tests.ps1`
Expected: FAIL en `names only parameters that tuneup.ps1 has, in any case` (`Startup` no se nombra), en la barrera nueva y en `turns off startup entries only when the user chose each one...`.

- [ ] **Step 3: SKILL.md**

En `plugins/windows-tuneup/skills/windows-tuneup/SKILL.md`:

1. En el frontmatter, reemplazar:

```markdown
to check Windows health with SFC and DISM, or to measure the PC before and after. Also in Spanish, such as optimiza o acelera este PC, limpia Windows.
```

por:

```markdown
to check Windows health with SFC and DISM, to review or turn off what starts with Windows, or to measure the PC before and after. Also in Spanish, such as optimiza o acelera este PC, limpia Windows, qué arranca con Windows.
```

2. Reemplazar:

```markdown
4. Never elevate to read. `-List`, `-Suggest`, `-WhatIf`, `-Status`, `-Measure` and `-ReadResult` run without administrator.
```

por:

```markdown
4. Never elevate to read. `-List`, `-Suggest`, `-WhatIf`, `-Status`, `-Measure`, `-Startup` (without `-Disable`) and `-ReadResult` run without administrator.
```

3. Después de la línea completa de la barrera 12 (empieza con `` 12. `schemaVersion` must be `1`. `` y termina con `means the same.`), agregar como línea nueva:

```markdown
13. Turn off a startup entry only when the user chose that entry, by naming it or with a yes to that one entry; a `recommended` mark is never a choice. Never pass an entry whose `canDisable` is false, and never run the `uninstall` command of an entry: show it as text only.
```

4. En "2. Assisted mode", después de la línea del paso 7 (la que empieza con `7. Report what was applied, partial, skipped and failed`), agregar:

```markdown
8. Ask, in the user's language: "Do we review what starts with Windows?". With a yes, follow "5. What starts with Windows" below; its changes also show in the measurement after the restart.
```

5. En "3. Direct mode", reemplazar:

```markdown
Diagnose only if the user asks, and still warn when the plan says `environment.isManaged`.
```

por:

```markdown
Diagnose only if the user asks, and still warn when the plan says `environment.isManaged`. If a profile the user named has `offersStartup` true in `profiles` of `-List -Json` (gaming has it), offer step 8 after step 7.
```

6. En la tabla de "4. Other requests", reemplazar:

```markdown
| A change of the blacklist | Refuse and explain from `blacklist.md` (guardrail 1) |
```

por:

```markdown
| What starts with Windows, an app that opens on its own, turning something off at startup | Follow "5. What starts with Windows" below |
| A change of the blacklist | Refuse and explain from `blacklist.md` (guardrail 1) |
```

7. Reemplazar:

```markdown
## 5. When elevation is declined
```

por:

```markdown
## 5. What starts with Windows

1. Without elevation: `-Startup -Json` (a `startup` document; see [reading-json.md](reference/reading-json.md#startup)).
2. Show a table in the user's language with the entries whose `enabled` is true: `name`, `publisher`, whether it runs now and its `memoryMB`, and a mark: recommended (with `recommendedReason` in plain words), protected (with `protected` in plain words: these stay on), or needs administrator (`needsAdmin`). Recommended ones first. Mention entries that are already off only if the user asks. Say `updates` as the security updates of the browser or of Office: they are protected even though they are updaters. An entry with `notRecommendedReason` = `work-app` (OneDrive, Teams or Outlook when `workPc` is true) is not recommended because it is used for work; the user can still choose it.
3. Ask which ones to turn off. The user chooses each entry, by naming it or with a yes to that one entry (guardrail 13): never add one because it is recommended, and never one whose `canDisable` is false. Each id comes from `entries` of that document and matches `^startup\.[a-z0-9-]+\.[a-z0-9-]+$`.
4. Plan without elevation: `-Startup -Disable '<ids>' -WhatIf -Json`. Say what changes (a `plan` with `source` = `startup`), that nothing is uninstalled or deleted, that `-Undo` turns them on again, and that the change takes effect the next time Windows or the session starts. Wait for the yes.
5. Apply the entries whose `needsAdmin` is false without elevation: `-Startup -Disable '<those ids>' -Yes -Json`. Apply the ones whose `needsAdmin` is true with one UAC prompt (guardrail 5), elevated, with `-Startup -Disable '<those ids>' -Yes -Json -ResultId <guid>` ([commands.md, "Run elevated"](reference/commands.md#run-elevated)). Never elevate the ones of the user: elevated with another administrator's password they are refused with `reason` = `session-user`.
6. Report each result and give the `runId` of each run. If an entry has `uninstall`, you may show that command as text for the user to run if they want the program gone; never run it yourself.
7. An id that starts with `startup.` in `drift` in `-Status` is an entry that turned itself on again: a re-apply leaves it out with a warning. Offer this section again for it, never `-Status -Reapply`.

## 6. When elevation is declined
```

8. Reemplazar:

```markdown
## 6. Exit codes
```

por:

```markdown
## 7. Exit codes
```

- [ ] **Step 4: commands.md**

En `plugins/windows-tuneup/skills/windows-tuneup/reference/commands.md`:

1. Reemplazar:

```markdown
- A run or a measurement: a `runId` of `-Status -Json`, or the `id` of a `measure` document, matching `^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$`.
```

por:

```markdown
- A startup entry: an `id` of `entries` in `-Startup -Json` whose `canDisable` is true, matching `^startup\.[a-z0-9-]+\.[a-z0-9-]+$`.
- A run or a measurement: a `runId` of `-Status -Json`, or the `id` of a `measure` document, matching `^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$`.
```

2. En la tabla de "Run without elevation", reemplazar:

```markdown
| Undo a run (try this first) |
```

por:

```markdown
| What starts with Windows | `-Startup -Json` |
| The plan to turn startup entries off | `-Startup -Disable '<ids>' -WhatIf -Json` |
| Turn off the startup entries whose `needsAdmin` is false | `-Startup -Disable '<ids>' -Yes -Json` |
| Undo a run (try this first) |
```

3. Reemplazar:

```markdown
`$toolArguments` by purpose (always `-Json` and `-Lang`; `-Yes` only to apply or re-apply, because `-Undo` and `-Health` refuse it):
```

por:

```markdown
`$toolArguments` by purpose (always `-Json` and `-Lang`; `-Yes` only to apply, re-apply or turn startup entries off, because `-Undo` and `-Health` refuse it):
```

4. Reemplazar:

```markdown
| Windows health | `-Health -Json -Lang <es or en>`; the repair: `-Health -Repair -Json -Lang <es or en>` |
```

por:

```markdown
| Turn off the startup entries whose `needsAdmin` is true | `-Startup -Disable '<ids>' -Yes -Json -Lang <es or en>` |
| Windows health | `-Health -Json -Lang <es or en>`; the repair: `-Health -Repair -Json -Lang <es or en>` |
```

- [ ] **Step 5: reading-json.md**

En `plugins/windows-tuneup/skills/windows-tuneup/reference/reading-json.md`:

1. Reemplazar:

```markdown
- `command` says which document it is: `list`, `suggest`, `plan`, `apply`, `status`, `undo`, `health`, `measure` or `error`.
```

por:

```markdown
- `command` says which document it is: `list`, `suggest`, `startup`, `plan`, `apply`, `status`, `undo`, `health`, `measure` or `error`.
```

2. En la sección `plan`, reemplazar:

```markdown
- `requiresAdmin`: applying needs elevation (one UAC prompt); `items[].needsAdmin` says which items.
```

por:

```markdown
- `requiresAdmin`: applying needs elevation (one UAC prompt); `items[].needsAdmin` says which items.
- `source`: `profiles`, `reapply` or `startup` (`-Startup -Disable`: each item is a startup entry, with its name as `title`; one already off is skipped as `already-applied`).
```

3. En la sección `status`, reemplazar:

```markdown
`items[]`: `id`, `title`, `runId` and `status`: `ok` (in place), `drift` (Windows reverted it: offer the re-apply), `not-present`, `unknown`, `needs-admin` (only an elevated check can read it: say so, and do not elevate to read).
```

por:

```markdown
`items[]`: `id`, `title`, `runId` and `status`: `ok` (in place), `drift` (Windows reverted it: offer the re-apply), `not-present`, `unknown`, `needs-admin` (only an elevated check can read it: say so, and do not elevate to read). An `id` that starts with `startup.` is a startup entry turned off with `-Startup -Disable`; in `drift` it turned itself on again: offer SKILL.md, "5. What starts with Windows", not the re-apply.
```

4. Agregar, antes de `## \`error\``:

```markdown
## `startup`

- `entries[]`: `id`, `name`, `source`, `scope`, `key`, `publisher`, `command`, `path`, `enabled`, `running`, `memoryMB`, `cpuSeconds`, `protected`, `canDisable`, `needsAdmin`, `recommended`, `recommendedReason`, `notRecommendedReason`, `uninstall`.
- `protected` says why an entry stays on: `policy`, `driver`, `windows-component`, `security`, `vpn`, `device` (helpers of the audio, touchpad, Fn-key, display and pen drivers), `updates` (the updaters of browsers and of Office: protected even though they are updaters, because they bring security patches). Say it in plain words and never offer to turn it off.
- `recommended`, with `recommendedReason` (`updater`, `game-launcher`, `sync-client`, `chat-helper`, `companion-app`: a companion app of a hardware vendor, such as the NVIDIA app or Armoury Crate): a mark to show, never a choice of the user.
- `workPc` true and `notRecommendedReason` = `work-app`: OneDrive, Teams or Outlook on a work PC; not recommended because it is used for work, but it can still be chosen.
- `canDisable` false: it cannot go in `-Disable` (protected, already off, run once, or a task with wildcard characters in its name).
- `running`, `memoryMB` and `cpuSeconds` (CPU time since it started, not a percentage) can be null: unknown, not zero.
- `uninstall`: a winget command to show as text; the tool never runs it, and neither do you.
- `isAdmin` false comes with a warning that Windows hid some scheduled tasks: say so, and do not elevate to read (guardrail 4).
- `summary`: `total`, `enabled`, `canDisable`, `recommended`, `protected`.

```

5. En la sección `error`, reemplazar:

```markdown
`message` and `details`, and sometimes a `reason`: `needs-admin` (`-Undo` of a run with system changes, or `-Health`, without administrator: offer the elevated run, after the UAC question), or the reasons of `-ReadResult` (see "Reading an elevated run").
```

por:

```markdown
`message` and `details`, and sometimes a `reason`: `needs-admin` (`-Undo` of a run with system changes, or `-Health`, without administrator: offer the elevated run, after the UAC question), `session-user` (`-Startup -Disable` of an entry of the user, elevated with another administrator's password: turn it off without elevation), or the reasons of `-ReadResult` (see "Reading an elevated run"). A `-Startup -Disable` that names an entry that stays on is an `error` whose `details` say why for each one: explain them, and nothing was turned off.
```

- [ ] **Step 6: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Plugin.Tests.ps1`
Expected: PASS (`SKILL.md` sigue debajo de 250 líneas; la descripción, por debajo de 1024 caracteres y sin `: `).

Run: `claude plugin validate .`
Expected: el marketplace y el plugin son válidos.

- [ ] **Step 7: Commit**

```bash
git add plugins/windows-tuneup/skills/windows-tuneup/SKILL.md plugins/windows-tuneup/skills/windows-tuneup/reference/commands.md plugins/windows-tuneup/skills/windows-tuneup/reference/reading-json.md tests/Plugin.Tests.ps1
git commit -m "feat(skill): paso de revisar lo que arranca con Windows, eligiendo cada entrada"
git log -1 --format=%s
```

---

### Task 16: Listas manuales de la VM y de la skill

**Files:**
- Modify: `docs/es/vm-checklist.md`, `docs/en/vm-checklist.md`
- Modify: `docs/es/skill-checklist.md`, `docs/en/skill-checklist.md`
- Test: `tests/Docs.Tests.ps1`

- [ ] **Step 1: Escribir las pruebas que fallan**

En `tests/Docs.Tests.ps1`, reemplazar:

```powershell
            foreach ($term in 'Start-E2E.ps1', 'install.ps1', 'winget', 'apps.onedrive', 'onedrive-known-folders', 'Ctrl+C', '-Measure -IdleSeconds 120', '-Undo last', 'measuring.md') {
```

por:

```powershell
            foreach ($term in 'Start-E2E.ps1', 'install.ps1', 'winget', 'apps.onedrive', 'onedrive-known-folders', 'Ctrl+C', '-Measure -IdleSeconds 120', '-Undo last', 'measuring.md',
                '-Startup -Disable', 'StartupApproved', 'winget show --id', 'work-app') {
```

y reemplazar:

```powershell
                'high-risk-not-requested') {
```

por:

```powershell
                'high-risk-not-requested', '-Startup -Json', "-Startup -Disable '<ids>' -WhatIf -Json") {
```

- [ ] **Step 2: Correr las pruebas y ver que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: FAIL en `covers what Windows Sandbox cannot, in both languages` y en `covers installing the plugin, the modes...`.

- [ ] **Step 3: Lista de la VM**

En `docs/es/vm-checklist.md`, reemplazar:

```markdown
- [ ] Liviano frente a LTSC: el método de [measuring.md](measuring.md), con su reporte.
```

por:

```markdown
- [ ] Arranque, sin elevar: `tuneup.ps1 -Startup` lista lo que muestran el Administrador de tareas > Aplicaciones de arranque y Configuración > Aplicaciones > Inicio, más las tareas y los servicios de terceros. Instalar antes Steam (o Discord) y Dropbox y agregar un acceso directo a la carpeta Inicio: salen recomendados; Defender, la VPN (si hay) y el audio salen protegidos. Para cada `wingetId` de `catalog/startup/rules.json`, `winget show --id <id> --exact` encuentra el programa.
- [ ] Como administrador, `tuneup.ps1 -Startup -Disable '<ids>' -Yes` con una entrada de cada fuente que tenga la VM (Run del usuario, Run de máquina, carpeta Inicio, una app de la Store con tarea de inicio como Teams, una tarea programada y un servicio automático de terceros): el Administrador de tareas y Configuración las muestran deshabilitadas, los valores de `StartupApproved` empiezan con `03` y el `State` de la tarea de la Store vale 1 (`reg query "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData" /s /v State`), la tarea queda deshabilitada y el servicio en Manual sin detenerse. Reiniciar: no arrancan, y lo protegido sí.
- [ ] `tuneup.ps1 -Status` las muestra `ok`; volver a apagar una desde el Administrador de tareas la deja `ok` (la fecha nueva no cuenta) y encenderla la deja en `drift`, y `tuneup.ps1 -Status -Reapply -WhatIf` la deja fuera con el aviso de apagarla con `-Startup -Disable`. Apagarla otra vez con `-Startup -Disable` la deja apagada (y otra vez más no cambia nada).
- [ ] Menú > 6 (Lo que arranca con Windows): lista lo mismo que `-Startup`, nada viene marcado; elegir una entrada de usuario la apaga después del plan y la confirmación; elegir una de máquina sin elevar dice que necesita administrador y no cambia nada.
- [ ] Con NVIDIA app, AMD Software o Armoury Crate instalados (si se puede): salen recomendados como app de acompañamiento, no protegidos; el servicio de audio de Realtek y el panel táctil siguen protegidos. Con la inscripción MDM simulada de [skill-checklist.md](skill-checklist.md), OneDrive y Teams salen sin recomendar (`work-app`) y el documento dice `workPc`.
- [ ] `tuneup.ps1 -Undo last`: todo vuelve como estaba (los valores de `StartupApproved` que no existían desaparecen y el servicio vuelve a Automático); reiniciar y comprobar que arrancan.
- [ ] Liviano frente a LTSC: el método de [measuring.md](measuring.md), con su reporte.
```

En `docs/en/vm-checklist.md`, reemplazar:

```markdown
- [ ] Lite versus LTSC: the method of [measuring.md](measuring.md), with its report.
```

por:

```markdown
- [ ] Startup, without elevation: `tuneup.ps1 -Startup` lists what Task Manager > Startup apps and Settings > Apps > Startup show, plus the scheduled tasks and services of other publishers. Install Steam (or Discord) and Dropbox first and add a shortcut to the Startup folder: they are recommended; Defender, the VPN (if any) and audio are protected. For every `wingetId` of `catalog/startup/rules.json`, `winget show --id <id> --exact` finds the program.
- [ ] As administrator, `tuneup.ps1 -Startup -Disable '<ids>' -Yes` with one entry of each source the VM has (Run of the user, Run of the machine, Startup folder, a Store app with a startup task such as Teams, a scheduled task and an automatic service of another publisher): Task Manager and Settings show them disabled, the `StartupApproved` values start with `03` and the `State` of the Store task is 1 (`reg query "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData" /s /v State`), the task is disabled and the service is Manual without being stopped. Restart: they do not start, and what is protected does.
- [ ] `tuneup.ps1 -Status` shows them `ok`; turning one off again from Task Manager leaves it `ok` (the new date does not count) and turning it on leaves it in `drift`, and `tuneup.ps1 -Status -Reapply -WhatIf` leaves it out with the warning to turn it off with `-Startup -Disable`. Turning it off again with `-Startup -Disable` leaves it off (and once more changes nothing).
- [ ] Menu > 6 (What starts with Windows): it lists the same as `-Startup`, nothing comes picked; picking an entry of the user turns it off after the plan and the confirmation; picking one of the machine without elevation says that it needs administrator and changes nothing.
- [ ] With the NVIDIA app, AMD Software or Armoury Crate installed (if possible): they are recommended as companion apps, not protected; the Realtek audio service and the touchpad stay protected. With the MDM enrollment simulated in [skill-checklist.md](skill-checklist.md), OneDrive and Teams are not recommended (`work-app`) and the document says `workPc`.
- [ ] `tuneup.ps1 -Undo last`: everything is back as it was (the `StartupApproved` values that did not exist are gone and the service is Automatic again); restart and check that they start.
- [ ] Lite versus LTSC: the method of [measuring.md](measuring.md), with its report.
```

- [ ] **Step 4: Lista de la skill**

En `docs/es/skill-checklist.md`, reemplazar:

```markdown
## Equipo administrado
```

por:

```markdown
## Arranque

1. Termina el modo asistido. Esperado: la skill pregunta "¿Revisamos lo que arranca con Windows?" y, con un sí, corre `-Startup -Json` sin UAC y muestra una tabla con lo recomendado marcado (con su motivo), lo protegido aparte y la memoria de lo que corre.
2. Di "apaga todo lo recomendado". Esperado: nombra cada entrada recomendada y pide un sí por cada una (o que confirmes esa lista nombrada); no agrega nada que no elegiste ni nada protegido.
3. Elige una entrada de usuario y una de máquina. Esperado: plan con `-Startup -Disable '<ids>' -WhatIf -Json`; con el sí, la de usuario se aplica sin UAC y la de máquina con un UAC (`-ResultId`, leído con `-ReadResult <id> -Json`); dice que rige desde el próximo inicio y da el `runId` de cada corrida.
4. Una entrada con `uninstall`: la skill muestra el comando de winget como texto y no lo corre.
5. "deshaz eso". Esperado: `-Undo <runId>` con el `runId` de `-Status -Json` (elevado solo la corrida de máquina); las entradas vuelven a encenderse.
6. Con la inscripción MDM simulada de la sección siguiente, repite el paso 1. Esperado: OneDrive, Teams y Outlook salen sin la marca de recomendado y la skill explica que se usan para trabajar; igual se pueden elegir.

## Equipo administrado
```

En `docs/en/skill-checklist.md`, reemplazar:

```markdown
## Managed PC
```

por:

```markdown
## Startup

1. Finish the assisted mode. Expected: the skill asks "Do we review what starts with Windows?" and, with a yes, runs `-Startup -Json` without UAC and shows a table with what is recommended marked (with its reason), what is protected apart, and the memory of what runs.
2. Say "turn off everything recommended". Expected: it names each recommended entry and asks for a yes to each one (or for you to confirm that named list); it adds nothing you did not choose and nothing protected.
3. Choose one entry of the user and one of the machine. Expected: a plan with `-Startup -Disable '<ids>' -WhatIf -Json`; with the yes, the one of the user is applied without UAC and the one of the machine with one UAC prompt (`-ResultId`, read with `-ReadResult <id> -Json`); it says that it takes effect at the next start and gives the `runId` of each run.
4. An entry with `uninstall`: the skill shows the winget command as text and does not run it.
5. "undo that". Expected: `-Undo <runId>` with the `runId` of `-Status -Json` (elevated only for the run of the machine); the entries are on again.
6. With the MDM enrollment simulated in the next section, repeat step 1. Expected: OneDrive, Teams and Outlook come without the recommended mark and the skill explains that they are used for work; they can still be chosen.

## Managed PC
```

- [ ] **Step 5: Correr las pruebas y ver que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add docs/es/vm-checklist.md docs/en/vm-checklist.md docs/es/skill-checklist.md docs/en/skill-checklist.md tests/Docs.Tests.ps1
git commit -m "docs(pruebas): ida y vuelta de -Startup en la VM y paso de arranque en la lista de la skill"
git log -1 --format=%s
```

---

### Task 17: Verificación final

**Files:** ninguno nuevo (solo correcciones si algo falla).

- [ ] **Step 1: Suite completa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS, sin pruebas omitidas fuera de las que ya dependían de elevar (`-Skip:$Elevated`).

- [ ] **Step 2: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 3: Plugin**

Run: `claude plugin validate .`
Expected: el marketplace `windows-tuneup` y su plugin son válidos.

- [ ] **Step 4: Paquete**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\build\package.ps1 -OutputPath .\dist`
Expected: `windows-tuneup-<versión>.zip` con `catalog/startup/rules.json` y sin `catalog/notes/` (lo comprueba `tests/Package.Tests.ps1`). Borrar `dist` después: `Remove-Item -LiteralPath .\dist -Recurse -Force`.

- [ ] **Step 5: Prueba de solo lectura en este equipo**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Startup -Lang es`
Expected: la tabla, con los ids y lo protegido marcado; código `0`. **No** correr `-Disable` aquí: el ida y vuelta real es de la VM (`docs/es/vm-checklist.md`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Startup -Json | ConvertFrom-Json | Select-Object -ExpandProperty summary`
Expected: los conteos; `total` igual a la cantidad de `entries`.

- [ ] **Step 6: Commit de las correcciones (si hubo)**

Solo si un paso anterior pidió un cambio: `git add` de cada archivo por su nombre, `git commit -m "fix(arranque): <qué se corrigió>"` y `git log -1 --format=%s`.

La lista manual de la VM (Task 16) se corre antes de la próxima release, con el reporte adjunto.

---

## Qué se verificó al escribir el plan

En este equipo (Windows 11 Pro 26H2, build 26300, sin elevar, solo lectura):

- **`StartupApproved`** (`reg` leído con `Get-Item`): `HKCU\...\StartupApproved\Run` tiene `JetBrains Toolbox` = `03 00 00 00 47 5e ae ad d9 50 dd 01` y `OneDrive` = `03 00 00 00 d5 d4 50 b2 d9 50 dd 01` (apagadas desde el Administrador de tareas: `03` + FILETIME), `Teams` y `MicrosoftEdgeAutoLaunch_…` = `02 00 … 00`. `StartupFolder` de HKCU: `Ollama.lnk` y `Enviar a OneNote.lnk` con `03` + FILETIME (el nombre del valor es el nombre de archivo, con `.lnk`). `HKLM\...\StartupApproved\Run`: `SecurityHealth` = `06 00 … 00` (encendida) y `GlobalProtect` = `02 …`; `Run32` vacía. `OneDrive`, `Teams` y `MicrosoftEdgeAutoLaunch_…` no tienen valor en `Run`: hay valores de `StartupApproved` huérfanos, por eso la lista sale de `Run` y de la carpeta (decisión 2).
- **Tareas de inicio de la Store**: bajo `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData` hay `State` en `AppUp.IntelArcSoftware_…\IntelGraphicsSoftwareStartup` (2), `Claude_…\ClaudeStartup` (0), `Microsoft.WindowsTerminal_…\StartTerminalOnLoginTask` (0) y `MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask` (1, con `LastDisabledTime`: apagada por el usuario). Leer el manifiesto de **todos** los paquetes del usuario tardó unos 2,2 s; por eso solo se leen los manifiestos de los paquetes que tienen una clave con `State` (decisión 3).
- **Tareas programadas** fuera de `\Microsoft\` con desencadenador de inicio de sesión: `\IObit EST2026Sale (One-time)`, `\RtkAudUService64_BG` (con `Execute` entre comillas dobles repetidas: `""C:\...\RtkAudUService64.exe""`, el caso de prueba de la Task 1) y `\Lenovo\Power Manager\Background monitor`.
- **Servicios `Auto`** fuera de `\Windows\` (`Win32_Service`, sin elevar): `brave`, `edgeupdate` (actualizadores de navegadores: `updates`), `ClickToRunSvc`, `PanGPS` (VPN), `IntelGraphicsSoftwareService`, `WifiAutoInstallSrv` (Realtek), `chromoting`, `CoworkVMService`, y `WinDefend`/`MDCoreSvc` bajo `ProgramData\Microsoft\Windows Defender\Platform` (por eso `MDCoreSvc` está en `windowsServices` y `MsMpEng`/`MpDefenderCoreService` en las reglas de `security`).
- **Centro de seguridad**: `root/SecurityCenter2` `AntiVirusProduct` se lee sin elevar; Defender trae `pathToSignedProductExe` = `windowsdefender://` y `pathToSignedReportingExe` = `%ProgramFiles%\Windows Defender\MsMpeng.exe` (por eso se descartan las que no son rutas).
- **Firma**: `SecurityHealthSystray.exe` está firmado por `CN=Microsoft Windows, O=Microsoft Corporation, …` (regla `windowsSigners`).
- **Ids y FILETIME** de las pruebas calculados con la función de la Task 1: `startup.run-user.steam-eb4bc901`, `startup.run-machine.steam-bb5ab8ea`, `startup.task.vendor-updater-task-logon-a94b661c`, `startup.service.averylongservicenamethatgoesonan-57d0735c`, `startup.store-app.msteams-8wekyb3d8bbwe-teamstfwst-119df735`, `startup.folder-user.lnk-70476f0a`; 2026-10-04 12:00 UTC = FILETIME `134355888000000000` = bytes `00 e0 b8 e1 f7 53 dd 01`.
- **Tareas de la Store sin clave** (revisión): la documentación de `StartupTask` (Remarks) dice que la extensión "will not, by itself, automatically cause the app start", que las apps UWP piden el permiso con `RequestEnableAsync` y que, en los dos casos, "the user must either launch the app at least once, or they must enable startup functionality for the app on the Startup page in Settings". En este equipo, las cuatro tareas que alguna vez se usaron tienen `State`: sin clave no hay nada que arranque.
- **Formato de `StartupApproved`**: no hay documentación de Microsoft; la fuente es el comportamiento conocido del Administrador de tareas (Eleven Forum, "Enable or Disable Startup Apps in Windows 11") y lo observado arriba.

**No se verificó** (queda para la VM, Task 16): que escribir `State` = 1 por el registro apague la app de la Store en el siguiente inicio de sesión (el lugar no está documentado), que los `wingetId` existan (`winget show`), el tiempo de `Get-AuthenticodeSignature` sobre todos los servicios de un equipo con muchos programas, la lista elevada y el comportamiento en Windows Server (sin Centro de seguridad: aviso).

## Preguntas resueltas (revisión del 2026-10-04)

1. **Actualizadores de navegadores y Office**: siguen protegidos (`updates`, decisión 7); la lista negra y la skill lo dicen.
2. **Deriva al volver a apagar desde el Administrador de tareas**: `set.compare = 'startupApproved'` en el manejador `registry` (decisión 16): solo cuenta el primer byte; `-Undo` devuelve los bytes exactos.
3. **Reglas `device`**: acotadas a los ayudantes de los controladores, con `why` en cada regla; las apps de acompañamiento son `companion-app` (decisiones 6, 25, 26).
4. **OneDrive, Teams y Outlook en un equipo de trabajo**: no se recomiendan, con `notRecommendedReason` = `work-app` y `workPc` en el documento (decisión 23).
5. **Menú**: opción 6, "Lo que arranca con Windows" (decisión 24, Task 12), además de la línea del perfil `gaming`.
6. **Tareas de la Store sin clave**: no se listan ni se leen todos los manifiestos; nunca se encendieron (decisión 3, con la cita de la documentación de `StartupTask`).

Queda solo lo que no se puede comprobar sin la VM ("No se verificó", arriba).
