# windows-tuneup — Plan 2: manejadores restantes, salud y medición

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar el motor con los manejadores `appx`, `capability`, `feature`, `powercfg` y `action`, un resultado honesto `partial`, el diagnóstico `-Health` (SFC + DISM con resumen leído de CBS.log y reparación opcional) y la medición `-Measure`/`-Compare`, todo con pruebas que nunca tocan el sistema real.

**Architecture:** Se mantiene el módulo único `engine/Tuneup.psm1` que carga un `.ps1` por responsabilidad. Una tabla en `engine/Dispatch.ps1` registra cada tipo de ajuste (despacho y validación del catálogo salen de ahí). Los manejadores siguen el contrato Get/Test/Set/Restore y ahora pueden devolver un "resultado de manejador" (`New-TuneupOutcome`) para informar `partial`, reinicio pedido por Windows o una nota de reversa. Toda llamada al sistema pasa por un envoltorio del módulo (`Get-TuneupAppxPackage`, `Invoke-TuneupPowercfg`, `Invoke-TuneupSfc`…), que es lo que simulan las pruebas. `-Health` y `-Measure` son módulos nuevos (`engine/Health.ps1`, `engine/Measure.ps1`) con analizadores puros probados contra extractos reales.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.9.1, PSScriptAnalyzer 1.25, GitHub Actions (`windows-latest`).

**Especificación:** `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md` (la Task 1 le agrega la sección 10, "Adenda del Plan 2").

**Plan anterior:** `docs/superpowers/plans/2026-09-30-plan-1-motor-nucleo.md`. Como dice su encabezado, **los archivos del repositorio son la fuente de verdad**; este plan se escribió leyendo el código de `main` después de mergear el Plan 1 (`4199f51`).

---

## Convenciones de este plan

Se heredan las del Plan 1:

- **Código, comentarios, identificadores y errores para desarrolladores en inglés.** Los textos para el usuario van en `i18n/es.json` y `i18n/en.json`, con las mismas claves y los mismos marcadores `{n}` en los dos (lo verifican `tests/I18n.Tests.ps1`).
- **Todo `.ps1`/`.psm1`/`.psd1` en ASCII** (lo verifica `tests/Repo.Tests.ps1`). Para un carácter no ASCII en una prueba se usa `[char]0x00ED`.
- **Las funciones emiten elementos; quien llama envuelve con `@()`.** Nunca `return ,$array`.
- **`ConvertTo-Json` siempre con `-Depth 10`.** **Comparaciones con null: `$null -eq $x`.**
- **Los fallos se lanzan, nunca se tragan.** Un `catch` solo existe para convertir el error en otro más claro, en un resultado `partial`/`failed` explícito o en un motivo (`reason`) que se informa.
- Parámetros de arreglo que pueden venir vacíos: `[AllowEmptyCollection()]` (y `[AllowEmptyString()]` si sus elementos pueden ser cadenas vacías).
- Pruebas con **Pester 5.9.1** en Windows PowerShell 5.1:
  `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 [-Path tests/X.Tests.ps1]`.
  `BeforeEach`/`AfterEach` solo dentro de un `Describe`.
- **Las pruebas nunca modifican el sistema real.** Appx, DISM, winget, powercfg, sfc, el visor de eventos y los contadores se simulan con `Mock -ModuleName Tuneup` sobre los envoltorios del módulo. El registro real solo se toca bajo `HKCU:\Software\windows-tuneup-test`.
- Lint: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`. Nombres de función con verbo aprobado y sustantivo en singular (`PSUseSingularNouns` está activo).
- Commits **sin** `Co-Authored-By`. **Nunca `git add -A` ni `git add .`**: cada paso de commit nombra sus archivos.
- Directorio del repo: `C:\Users\Edgar\Documents\GitHub\windows-tuneup` (comandos relativos a esa raíz, rama `main`).

Nuevas para este plan:

- **Ejecutables nativos con `Invoke-TuneupNative`.** El módulo corre con `$ErrorActionPreference = 'Stop'` y Windows PowerShell 5.1 convierte cualquier línea que un `.exe` escriba en la salida de errores en un error terminante cuando se redirige con `2>&1` (comprobado en este equipo con `cmd /c "echo err 1>&2"`). `Invoke-TuneupNative` baja la preferencia a `Continue` solo dentro de la función y devuelve `ExitCode` y `Output`; quien llama decide si el código es un error.
- **Comportamiento de `Mock` verificado en Pester 5.9.1:** el último `Mock` definido gana (un `Mock` dentro de un `It` reemplaza al del `BeforeEach`), uno con `-ParameterFilter` gana sobre uno sin filtro, y `-ModuleName Tuneup` solo afecta las llamadas hechas **desde dentro** del módulo. Un `Mock` puede leer y escribir variables `$script:` del archivo de prueba.

## Adenda de diseño

Este texto se copia en la Task 1 como sección 10 de la especificación.

1. **Resultado de `Set` y estado `partial`.** `Set-<Tipo>TweakDesired` puede emitir un resultado de manejador creado con `New-TuneupOutcome` (un `[pscustomobject]` con tipo `Tuneup.Outcome` y los campos `partial`, `detail`, `rebootRequired` y `reason`); cualquier otra salida del manejador se ignora. Si informa `partial` (cambió algo pero no pudo terminar; por ejemplo, el servicio quedó deshabilitado pero no se pudo detener), el ajuste queda `partial` con la explicación en `detail`, diga lo que diga `Test`. Si no, `Test` decide `applied` o `not-applied`, como antes. `rebootRequired` del resultado es el del catálogo **o** el que pida Windows (`RestartNeeded` de DISM). El resumen y el JSON cuentan `partial`; un `partial` da código de salida `2`; `-Status` lo trata como ajuste tocado. `Restore-<Tipo>TweakState` usa el mismo objeto: su `reason` (por ejemplo `reinstalled`), `detail` y `rebootRequired` llegan al resultado de `-Undo`, que sigue contando como `restored`.
2. **Registro único de manejadores.** `engine/Dispatch.ps1` tiene una tabla `tipo → manejador` que también dice si leer el estado exige administrador. La usan el despachador y la validación del catálogo; la validación del bloque `set` de cada tipo vive en su manejador (`Test-<Tipo>TweakDefinition`). Agregar un tipo es una línea en la tabla más `engine/handlers/<Tipo>.ps1`. Una prueba exige que cada tipo de la tabla tenga sus cinco funciones. Los tipos se comparan en minúsculas exactas.
3. **appx.** `scope: machine`. `set: { name, storeId, action: "remove" }`: `name` es el nombre del paquete Appx (`Microsoft.BingNews`, sin comodines) y `storeId` el id de producto de la Microsoft Store (`^[0-9A-Z]{12}$`, por ejemplo `9WZDNCRFHVFW`). Estado: `{ installedUsers, provisioned, version }`; instalado para algún usuario según `Get-AppxPackage -AllUsers` (solo cuenta `InstallState = Installed`, no `Staged`) y provisionado según `Get-AppxProvisionedPackage -Online` por `DisplayName`. Una app que no está ni instalada ni provisionada cuenta como **aplicada** (no hay nada que quitar); nunca es `not-present`. Aplicar quita el paquete para todos los usuarios y lo desprovisiona; si una parte falla después de que otra funcionó, el resultado es `partial`; si nada funcionó, `failed`. Deshacer: si estaba instalada, `winget install --id <storeId> --source msstore --exact --accept-package-agreements --accept-source-agreements --silent --disable-interactivity` para el usuario actual, con resultado `restored` y motivo `reinstalled` ("reinstalada para el usuario actual; no se volvió a provisionar"); si el usuario actual ya la tiene, no se llama a winget. Si solo estaba provisionada, la Store no permite volver a provisionarla: `restored` con motivo `not-reprovisioned` y la línea de winget para instalarla a mano. Sin winget, o si winget falla, el deshacer falla con el código de salida y la corrida queda pendiente para reintentar.
4. **capability.** `set: { name: "<Nombre~~~~Versión>", state: "Installed"|"NotPresent" }`. Los estados pendientes cuentan hacia donde van (`InstallPending` = instalada; `UninstallPending`, `Staged`, `Removed` = no presente). La lista de capacidades se pide una vez por proceso y se vuelve a pedir después de cada cambio. Deshacer vuelve a agregarla, lo que necesita Windows Update o un origen de características a petición; si falla, el error lo dice. `RestartNeeded` → `rebootRequired`.
5. **feature.** `set: { name, state: "Enabled"|"Disabled" }`. Se usa `-NoRestart` y nunca `-All` ni `-Remove` (reversa exacta). `DisabledWithPayloadRemoved` y `DisablePending` cuentan como deshabilitada; `EnablePending`, como habilitada. Misma caché que `capability`. `RestartNeeded` → `rebootRequired`.
6. **powercfg.** Dos clases según `set.kind`. `scheme`: `{ kind, scheme: <GUID> }`; el estado es el GUID del plan activo, leído con `powercfg /getactivescheme` tomando solo el GUID con una expresión regular (las palabras dependen del idioma de Windows); un plan que no aparece en `powercfg /list` es `not-present`. `setting`: `{ kind, scheme: "SCHEME_CURRENT"|<GUID>, subgroup: <GUID>, setting: <GUID>, ac, dc }`, con `ac`/`dc` enteros de 0 a 4294967295. Subgrupo y valor van como GUID: el valor actual se lee del registro y los alias de `powercfg` no sirven para eso. Lectura: `HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\<plan>\<subgrupo>\<valor>` (`ACSettingIndex`/`DCSettingIndex`) y, para el que no esté, el predeterminado en `...\Control\Power\PowerSettings\<subgrupo>\<valor>\DefaultPowerSchemeValues\<plan>`; si la definición `PowerSettings\<subgrupo>\<valor>` no existe, `not-present`. Verificado en este equipo: Equilibrado / Suspender tras da AC 0 (valor propio) y DC 1800 = `0x708`, igual que `powercfg /q`. `powercfg /q` no se usa para leer porque omite los valores con atributo oculto (en este equipo `SUB_BUTTONS LIDACTION` sale vacío). `SCHEME_CURRENT` se resuelve al GUID en el momento de leer y el diario guarda ese GUID, así que deshacer vuelve al mismo plan aunque después se active otro. Se escribe con `powercfg /setacvalueindex` y `/setdcvalueindex`, más `/setactive` si es el plan activo; si AC se escribió y lo demás falló, `partial`. La reversa devuelve el mismo valor efectivo (si antes regía el predeterminado, queda escrito como valor propio del plan). Un plan personalizado sin valor propio ni predeterminado da "no se pudo leer".
7. **action.** `set: { script: "<nombre-en-kebab>" }` → `actions/<nombre>.ps1` define `Get-<Pascal>ActionState`, `Test-<Pascal>ActionState`, `Set-<Pascal>ActionDesired` y `Restore-<Pascal>ActionState` (mismo contrato que los manejadores; `fixture-toggle` → `FixtureToggle`). El cargador **no ejecuta** el archivo: lo analiza y solo acepta definiciones de funciones con bloque `param()` cuyo nombre lleve `-<Pascal>Action`, así una acción no puede reemplazar funciones del motor ni correr código al cargarse. Las acciones de `actions/` se cargan al importar el módulo; `-ActionsPath <carpeta>` (solo pruebas y desarrollo, como `-StateRoot`) agrega otra carpeta. El catálogo valida que la acción esté cargada. El Plan 2 solo trae una acción de prueba en `tests/fixtures/actions`; las reales llegan en el Plan 3.
8. **Carpeta de usuario.** Sigue aceptando solo ajustes de registro `HKCU` (`Test-TuneupUserScopedTweak` no cambia). Todos los tipos nuevos exigen `scope: machine`, así que se aplican y deshacen elevados y su diario va a la carpeta de máquina.
9. **Estado que solo se lee elevado.** `appx`, `capability` y `feature` no se pueden leer sin administrador (verificado: `Get-AppxPackage -AllUsers` da "Acceso denegado" y los cmdlets de DISM "La operación solicitada requiere elevación"). Sin elevar, el plan los muestra como cambios por aplicar con la nota `unverified-needs-admin` (se comprueban al aplicar, que de todos modos exige administrador) y `-Status` los informa como `needs-admin`, en vez de "no se pudo leer".
10. **-Health.** Exige administrador. Corre `sfc /scannow` y `DISM /Online /Cleanup-Image /ScanHealth /English`, guardando el código de salida y los bytes crudos de la salida, que se decodifican después (sfc escribe UTF-16 al redirigirse y DISM usa la página OEM); se guardan en memoria, no en un archivo temporal. El resultado se lee de `%windir%\Logs\CBS\CBS.log` y de los `CbsPersist_*.log` modificados desde el inicio (Windows rota CBS.log en medio de una revisión larga), solo con líneas desde la hora de inicio: `[SR] Repairing N components`, `[SR] Cannot repair member file`, `[SR] Repairing corrupted file`, `[Pnp] Corrupt file`/`[Pnp] Repaired file`, el bloque `Summary` que sigue a `Checking System Update Readiness` (`Operation`, `Operation result`, `Total Detected Corruption`, `Total Repaired Corruption`) y las líneas `(p) CSI Payload Corrupt` que no dicen `(Fixed)`, agrupadas por componente. Resumen: SFC `clean|repaired|unrepaired|unknown`, almacén de componentes `healthy|repairable|repaired|unrepairable|unknown`, grupos dañados y recomendación `none|run-repair|manual-repair|check-logs`. El código de salida de SFC no está documentado: se muestra, pero no decide. `-Repair` corre `DISM /RestoreHealth` y SFC otra vez solo si hace falta, e informa antes y después. Código de salida: `0` sin problemas, `2` quedan problemas o no se pudo confirmar, `1` no se pudo empezar (sin administrador). No hay pregunta interactiva para reparar: el menú es del Plan 4.
11. **-Measure / -Compare.** Métricas: RAM en uso (MB), procesos, servicios en ejecución, tareas programadas habilitadas, espacio libre del disco del sistema (GB), duración del último arranque (`BootTime` del evento 100 de `Microsoft-Windows-Diagnostics-Performance/Operational`) y minutos desde el arranque, más fecha y entorno. Si la duración no se puede leer queda `null` con el motivo en `notes` (`needs-admin`, `no-event`, `not-recorded-yet` si el evento es de un arranque anterior, `unreadable`, `unavailable`); no hay respaldo con el tiempo hasta el inicio de sesión. Sin elevar, Windows responde "no hay eventos" en vez de "acceso denegado" (verificado), por eso ese caso se informa como `needs-admin`. `-IdleSeconds <n>` (0 a 3600) espera antes de medir; el README recomienda reiniciar y usar 120. Se guarda en `<carpeta de estado>\measurements\<id>.json` con las mismas reglas de confianza que las corridas (máquina si es administrador, usuario si no, `-StateRoot` para pruebas). `-Compare <id|last>` compara contra una medición guardada (no contra una corrida); se resuelve antes de medir, así `last` nunca es la medición nueva.
12. **CLI.** `-Status`, `-Undo`, `-Health` y `-Measure` se excluyen entre sí y ninguno se combina con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` ni `-Yes`. Opciones que dependen de un comando: `-Tweak` (de `-Undo`), `-Repair` (de `-Health`), `-Compare` e `-IdleSeconds` (de `-Measure`). La regla vive en una función pura (`Get-TuneupArgumentConflict`). El JSON suma los comandos `health` y `measure`, con `schemaVersion` y `warnings` como los demás.

## Desviaciones respecto de la especificación

| Especificación | Plan 2 | Motivo |
|---|---|---|
| `-Health`: "si hay daño, ofrece `/RestoreHealth`" | Recomendación más `-Repair` explícito | Sin menú hasta el Plan 4; la skill y `-Json` necesitan un parámetro |
| `-Measure [-Compare <runId>]` | `-Compare <id\|last>` de una medición | Una corrida no guarda métricas |
| Duración del arranque con respaldo "tiempo hasta el inicio de sesión" | `null` con motivo | El respaldo no se puede medir de forma comparable entre equipos |
| `action` con `Get-Current`/`Restore-Previous` | `Get-<Pascal>ActionState`, `Test-…`, `Set-<Pascal>ActionDesired`, `Restore-…` | El mismo contrato que los manejadores y nombres que no chocan entre acciones |
| `powercfg`: reversa "Exacta" | Mismo valor efectivo | Un valor que venía del predeterminado queda escrito como propio del plan |
| `appx`: "Reinstala desde la Store" | Solo para el usuario actual; una app solo provisionada no se puede reponer | Es lo que permite winget sin el paquete original |
| `Health.psm1`, `Measure.psm1` | `engine/Health.ps1`, `engine/Measure.ps1` | Mismo criterio que el Plan 1: un solo módulo para `Mock -ModuleName Tuneup` |

## Estructura de archivos del Plan 2

```
windows-tuneup/
├── tuneup.ps1                          + -ActionsPath, -Health, -Repair, -Measure, -Compare, -IdleSeconds
├── engine/
│   ├── Tuneup.psm1                     + carga las acciones de actions/ al importar
│   ├── Dispatch.ps1                    tabla de manejadores, New-/Get-TuneupOutcome
│   ├── Catalog.ps1                     valida con la tabla; la validación de cada set pasa a su manejador
│   ├── Executor.ps1                    partial, detail, rebootRequired dinámico
│   ├── Undo.ps1                        notas de la reversa, partial en -Status, needs-admin
│   ├── Planner.ps1                     unverified-needs-admin
│   ├── Output.ps1                      partial, reportes de -Health y -Measure
│   ├── StateSecurity.ps1               Initialize-TuneupStateRoot -Children
│   ├── Native.ps1                      (nuevo) Invoke-TuneupNative
│   ├── Arguments.ps1                   (nuevo) Get-TuneupArgumentConflict
│   ├── Health.ps1                      (nuevo) CBS.log, sfc, DISM, recomendación
│   ├── Measure.ps1                     (nuevo) métricas, comparación, mediciones en disco
│   └── handlers/
│       ├── Registry.ps1, Service.ps1, Task.ps1   + Test-<Tipo>TweakDefinition
│       ├── Appx.ps1, Capability.ps1, Feature.ps1, Powercfg.ps1, Action.ps1   (nuevos)
├── i18n/es.json, i18n/en.json          + claves de partial, salud, medición y motivos nuevos
├── build/lint.ps1                      + carpeta actions/
├── tests/
│   ├── Dispatch, Executor, Output, Undo, Service, Planner, StateFiles, Cli .Tests.ps1   (se amplían)
│   ├── Native, Appx, Capability, Feature, Powercfg, Action, Arguments, Health, Measure .Tests.ps1   (nuevos)
│   └── fixtures/
│       ├── actions/fixture-toggle.ps1  (nuevo)
│       ├── cbs/*.log                   (nuevos, extractos con el formato real de CBS.log)
│       └── catalog/test.json           + test.action
├── docs/superpowers/specs/…-design.md  + sección 10 y parámetros
└── README.md
```

---

### Task 1: Adenda de diseño en la especificación

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`

- [ ] **Step 1: Agregar la sección 10 al final de la especificación**

Agregar al final del archivo (después de la tabla de la sección 9, con una línea en blanco antes):

````markdown
## 10. Adenda del Plan 2 (2026-09-30)

Decisiones tomadas al planificar los manejadores restantes, `-Health` y `-Measure`. Donde contradicen
secciones anteriores, manda esta.

1. **Resultado de `Set` y estado `partial`.** `Set-<Tipo>TweakDesired` puede emitir un resultado de manejador creado con `New-TuneupOutcome` (un `[pscustomobject]` con tipo `Tuneup.Outcome` y los campos `partial`, `detail`, `rebootRequired` y `reason`); cualquier otra salida del manejador se ignora. Si informa `partial` (cambió algo pero no pudo terminar; por ejemplo, el servicio quedó deshabilitado pero no se pudo detener), el ajuste queda `partial` con la explicación en `detail`, diga lo que diga `Test`. Si no, `Test` decide `applied` o `not-applied`, como antes. `rebootRequired` del resultado es el del catálogo **o** el que pida Windows (`RestartNeeded` de DISM). El resumen y el JSON cuentan `partial`; un `partial` da código de salida `2`; `-Status` lo trata como ajuste tocado. `Restore-<Tipo>TweakState` usa el mismo objeto: su `reason` (por ejemplo `reinstalled`), `detail` y `rebootRequired` llegan al resultado de `-Undo`, que sigue contando como `restored`.
2. **Registro único de manejadores.** `engine/Dispatch.ps1` tiene una tabla `tipo → manejador` que también dice si leer el estado exige administrador. La usan el despachador y la validación del catálogo; la validación del bloque `set` de cada tipo vive en su manejador (`Test-<Tipo>TweakDefinition`). Agregar un tipo es una línea en la tabla más `engine/handlers/<Tipo>.ps1`. Una prueba exige que cada tipo de la tabla tenga sus cinco funciones. Los tipos se comparan en minúsculas exactas.
3. **appx.** `scope: machine`. `set: { name, storeId, action: "remove" }`: `name` es el nombre del paquete Appx (`Microsoft.BingNews`, sin comodines) y `storeId` el id de producto de la Microsoft Store (`^[0-9A-Z]{12}$`, por ejemplo `9WZDNCRFHVFW`). Estado: `{ installedUsers, provisioned, version }`; instalado para algún usuario según `Get-AppxPackage -AllUsers` (solo cuenta `InstallState = Installed`, no `Staged`) y provisionado según `Get-AppxProvisionedPackage -Online` por `DisplayName`. Una app que no está ni instalada ni provisionada cuenta como **aplicada** (no hay nada que quitar); nunca es `not-present`. Aplicar quita el paquete para todos los usuarios y lo desprovisiona; si una parte falla después de que otra funcionó, el resultado es `partial`; si nada funcionó, `failed`. Deshacer: si estaba instalada, `winget install --id <storeId> --source msstore --exact --accept-package-agreements --accept-source-agreements --silent --disable-interactivity` para el usuario actual, con resultado `restored` y motivo `reinstalled` ("reinstalada para el usuario actual; no se volvió a provisionar"); si el usuario actual ya la tiene, no se llama a winget. Si solo estaba provisionada, la Store no permite volver a provisionarla: `restored` con motivo `not-reprovisioned` y la línea de winget para instalarla a mano. Sin winget, o si winget falla, el deshacer falla con el código de salida y la corrida queda pendiente para reintentar.
4. **capability.** `set: { name: "<Nombre~~~~Versión>", state: "Installed"|"NotPresent" }`. Los estados pendientes cuentan hacia donde van (`InstallPending` = instalada; `UninstallPending`, `Staged`, `Removed` = no presente). La lista de capacidades se pide una vez por proceso y se vuelve a pedir después de cada cambio. Deshacer vuelve a agregarla, lo que necesita Windows Update o un origen de características a petición; si falla, el error lo dice. `RestartNeeded` → `rebootRequired`.
5. **feature.** `set: { name, state: "Enabled"|"Disabled" }`. Se usa `-NoRestart` y nunca `-All` ni `-Remove` (reversa exacta). `DisabledWithPayloadRemoved` y `DisablePending` cuentan como deshabilitada; `EnablePending`, como habilitada. Misma caché que `capability`. `RestartNeeded` → `rebootRequired`.
6. **powercfg.** Dos clases según `set.kind`. `scheme`: `{ kind, scheme: <GUID> }`; el estado es el GUID del plan activo, leído con `powercfg /getactivescheme` tomando solo el GUID con una expresión regular (las palabras dependen del idioma de Windows); un plan que no aparece en `powercfg /list` es `not-present`. `setting`: `{ kind, scheme: "SCHEME_CURRENT"|<GUID>, subgroup: <GUID>, setting: <GUID>, ac, dc }`, con `ac`/`dc` enteros de 0 a 4294967295. Subgrupo y valor van como GUID: el valor actual se lee del registro y los alias de `powercfg` no sirven para eso. Lectura: `HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\<plan>\<subgrupo>\<valor>` (`ACSettingIndex`/`DCSettingIndex`) y, para el que no esté, el predeterminado en `...\Control\Power\PowerSettings\<subgrupo>\<valor>\DefaultPowerSchemeValues\<plan>`; si la definición `PowerSettings\<subgrupo>\<valor>` no existe, `not-present`. Verificado en este equipo: Equilibrado / Suspender tras da AC 0 (valor propio) y DC 1800 = `0x708`, igual que `powercfg /q`. `powercfg /q` no se usa para leer porque omite los valores con atributo oculto (en este equipo `SUB_BUTTONS LIDACTION` sale vacío). `SCHEME_CURRENT` se resuelve al GUID en el momento de leer y el diario guarda ese GUID, así que deshacer vuelve al mismo plan aunque después se active otro. Se escribe con `powercfg /setacvalueindex` y `/setdcvalueindex`, más `/setactive` si es el plan activo; si AC se escribió y lo demás falló, `partial`. La reversa devuelve el mismo valor efectivo (si antes regía el predeterminado, queda escrito como valor propio del plan). Un plan personalizado sin valor propio ni predeterminado da "no se pudo leer".
7. **action.** `set: { script: "<nombre-en-kebab>" }` → `actions/<nombre>.ps1` define `Get-<Pascal>ActionState`, `Test-<Pascal>ActionState`, `Set-<Pascal>ActionDesired` y `Restore-<Pascal>ActionState` (mismo contrato que los manejadores; `fixture-toggle` → `FixtureToggle`). El cargador **no ejecuta** el archivo: lo analiza y solo acepta definiciones de funciones con bloque `param()` cuyo nombre lleve `-<Pascal>Action`, así una acción no puede reemplazar funciones del motor ni correr código al cargarse. Las acciones de `actions/` se cargan al importar el módulo; `-ActionsPath <carpeta>` (solo pruebas y desarrollo, como `-StateRoot`) agrega otra carpeta. El catálogo valida que la acción esté cargada. El Plan 2 solo trae una acción de prueba en `tests/fixtures/actions`; las reales llegan en el Plan 3.
8. **Carpeta de usuario.** Sigue aceptando solo ajustes de registro `HKCU` (`Test-TuneupUserScopedTweak` no cambia). Todos los tipos nuevos exigen `scope: machine`, así que se aplican y deshacen elevados y su diario va a la carpeta de máquina.
9. **Estado que solo se lee elevado.** `appx`, `capability` y `feature` no se pueden leer sin administrador (verificado: `Get-AppxPackage -AllUsers` da "Acceso denegado" y los cmdlets de DISM "La operación solicitada requiere elevación"). Sin elevar, el plan los muestra como cambios por aplicar con la nota `unverified-needs-admin` (se comprueban al aplicar, que de todos modos exige administrador) y `-Status` los informa como `needs-admin`, en vez de "no se pudo leer".
10. **-Health.** Exige administrador. Corre `sfc /scannow` y `DISM /Online /Cleanup-Image /ScanHealth /English`, guardando el código de salida y los bytes crudos de la salida, que se decodifican después (sfc escribe UTF-16 al redirigirse y DISM usa la página OEM); se guardan en memoria, no en un archivo temporal. El resultado se lee de `%windir%\Logs\CBS\CBS.log` y de los `CbsPersist_*.log` modificados desde el inicio (Windows rota CBS.log en medio de una revisión larga), solo con líneas desde la hora de inicio: `[SR] Repairing N components`, `[SR] Cannot repair member file`, `[SR] Repairing corrupted file`, `[Pnp] Corrupt file`/`[Pnp] Repaired file`, el bloque `Summary` que sigue a `Checking System Update Readiness` (`Operation`, `Operation result`, `Total Detected Corruption`, `Total Repaired Corruption`) y las líneas `(p) CSI Payload Corrupt` que no dicen `(Fixed)`, agrupadas por componente. Resumen: SFC `clean|repaired|unrepaired|unknown`, almacén de componentes `healthy|repairable|repaired|unrepairable|unknown`, grupos dañados y recomendación `none|run-repair|manual-repair|check-logs`. El código de salida de SFC no está documentado: se muestra, pero no decide. `-Repair` corre `DISM /RestoreHealth` y SFC otra vez solo si hace falta, e informa antes y después. Código de salida: `0` sin problemas, `2` quedan problemas o no se pudo confirmar, `1` no se pudo empezar (sin administrador). No hay pregunta interactiva para reparar: el menú es del Plan 4.
11. **-Measure / -Compare.** Métricas: RAM en uso (MB), procesos, servicios en ejecución, tareas programadas habilitadas, espacio libre del disco del sistema (GB), duración del último arranque (`BootTime` del evento 100 de `Microsoft-Windows-Diagnostics-Performance/Operational`) y minutos desde el arranque, más fecha y entorno. Si la duración no se puede leer queda `null` con el motivo en `notes` (`needs-admin`, `no-event`, `not-recorded-yet` si el evento es de un arranque anterior, `unreadable`, `unavailable`); no hay respaldo con el tiempo hasta el inicio de sesión. Sin elevar, Windows responde "no hay eventos" en vez de "acceso denegado" (verificado), por eso ese caso se informa como `needs-admin`. `-IdleSeconds <n>` (0 a 3600) espera antes de medir; el README recomienda reiniciar y usar 120. Se guarda en `<carpeta de estado>\measurements\<id>.json` con las mismas reglas de confianza que las corridas (máquina si es administrador, usuario si no, `-StateRoot` para pruebas). `-Compare <id|last>` compara contra una medición guardada (no contra una corrida); se resuelve antes de medir, así `last` nunca es la medición nueva.
12. **CLI.** `-Status`, `-Undo`, `-Health` y `-Measure` se excluyen entre sí y ninguno se combina con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` ni `-Yes`. Opciones que dependen de un comando: `-Tweak` (de `-Undo`), `-Repair` (de `-Health`), `-Compare` e `-IdleSeconds` (de `-Measure`). La regla vive en una función pura (`Get-TuneupArgumentConflict`). El JSON suma los comandos `health` y `measure`, con `schemaVersion` y `warnings` como los demás.
````

- [ ] **Step 2: Verificar que la suite sigue verde**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`). Solo cambió documentación.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-30-windows-tuneup-design.md
git commit -m "docs: adenda de diseño del Plan 2"
```

---

### Task 2: Registro único de manejadores

**Files:**
- Modify: `engine/Dispatch.ps1`, `engine/Catalog.ps1`
- Modify: `engine/handlers/Registry.ps1`, `engine/handlers/Service.ps1`, `engine/handlers/Task.ps1`
- Test: `tests/Dispatch.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Dispatch.Tests.ps1`:

```powershell
Describe 'Handler registry' {
    It 'has the contract functions for every dispatched type' {
        $missing = foreach ($type in @(Get-TuneupHandlerType)) {
            $name = Get-TuneupHandlerName -Tweak ([pscustomobject]@{ type = $type })
            foreach ($function in "Get-${name}TweakState", "Test-${name}TweakState", "Set-${name}TweakDesired", "Restore-${name}TweakState", "Test-${name}TweakDefinition") {
                if (-not (Get-Command -Name $function -Module Tuneup -ErrorAction SilentlyContinue)) { "${type}: $function" }
            }
        }
        $missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'lets the catalog accept exactly the dispatched types' {
        foreach ($type in @(Get-TuneupHandlerType)) {
            (Test-TuneupTweak -Tweak (New-TestTweak -Type $type)) -join '; ' | Should -Not -Match 'unsupported type' -Because $type
        }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'Registry')) -join '; ' | Should -Match "unsupported type 'Registry'"
        { Get-TuneupHandlerName -Tweak (New-TestTweak -Type 'Registry') } | Should -Throw "*Unsupported tweak type 'Registry'*"
    }

    It 'starts with the types of the first plan' {
        @(Get-TuneupHandlerType)[0..2] -join ',' | Should -Be 'registry,service,task'
    }

    It 'says whether reading a type needs elevation' {
        (Get-TuneupHandler -Type 'registry').ReadNeedsAdmin | Should -BeFalse
        Get-TuneupHandler -Type 'magic' | Should -BeNullOrEmpty
        Get-TuneupHandler -Type $null | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: FAIL, `Get-TuneupHandlerType` no se reconoce como comando.

- [ ] **Step 3: Tabla de manejadores**

En `engine/Dispatch.ps1`, reemplazar la función `Get-TuneupHandlerName` completa por:

```powershell
# Every tweak type, mapped to its handler. Adding a type takes one entry here plus
# engine/handlers/<Name>.ps1 with Get-<Name>TweakState, Test-<Name>TweakState,
# Set-<Name>TweakDesired, Restore-<Name>TweakState and Test-<Name>TweakDefinition (the catalog
# check of its set block). ReadNeedsAdmin: reading the state needs an elevated process.
$script:TuneupHandlers = [ordered]@{
    registry = [pscustomobject]@{ Name = 'Registry'; ReadNeedsAdmin = $false }
    service  = [pscustomobject]@{ Name = 'Service'; ReadNeedsAdmin = $false }
    task     = [pscustomobject]@{ Name = 'Task'; ReadNeedsAdmin = $false }
}

function Get-TuneupHandlerType {
    foreach ($type in $script:TuneupHandlers.Keys) { $type }
}

function Get-TuneupHandler {
    param([AllowNull()]$Type)
    # Exact, lowercase match: the user-folder rule and the journals compare types the same way.
    if ($Type -isnot [string] -or @(Get-TuneupHandlerType) -cnotcontains $Type) { return $null }
    $script:TuneupHandlers[$Type]
}

function Get-TuneupHandlerName {
    param([Parameter(Mandatory)]$Tweak)
    $handler = Get-TuneupHandler -Type $Tweak.type
    if ($null -eq $handler) { throw "Unsupported tweak type '$($Tweak.type)'" }
    $handler.Name
}
```

Las funciones `Get-TuneupState`, `Test-TuneupState`, `Set-TuneupDesired` y `Restore-TuneupState` no cambian.

- [ ] **Step 4: La validación de cada `set` pasa a su manejador**

En `engine/Catalog.ps1`:

1. Borrar estas tres líneas del principio:

```powershell
$script:RegistryKinds = @('DWord', 'QWord', 'String', 'ExpandString')
$script:ServiceStartTypes = @('Automatic', 'AutomaticDelayed', 'Manual', 'Disabled')
$script:TaskStates = @('Enabled', 'Disabled')
```

2. Borrar la función `Test-TuneupRegistryValue` completa (pasa a `Registry.ps1`). `Test-TuneupIntegerInRange` se queda: la usa también `powercfg`.

3. En `Test-TuneupTweak`, reemplazar desde la línea `    $set = $Tweak.set` hasta el final de la función por:

```powershell
    $handler = Get-TuneupHandler -Type $Tweak.type
    if ($null -eq $handler) {
        $errors.Add("$id has an unsupported type '$($Tweak.type)'")
    } else {
        foreach ($problem in @(& "Test-$($handler.Name)TweakDefinition" -Tweak $Tweak)) { $errors.Add("$id $problem") }
    }
    $errors.ToArray()
}
```

Al principio de `engine/handlers/Registry.ps1` agregar:

```powershell
$script:RegistryKinds = @('DWord', 'QWord', 'String', 'ExpandString')

function Test-TuneupRegistryValue {
    param([string]$Kind, $Value)
    if ($Value -is [array]) { return $false }
    switch ($Kind) {
        'DWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -2147483648 -Max 4294967295) }
        'QWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -9223372036854775808 -Max 9223372036854775807) }
        default { return ($Value -is [string]) }
    }
}

function Test-RegistryTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.path -notmatch '^(HKLM|HKCU):\\.+') {
        'has an invalid registry path'
    } elseif (([string]$set.path -match '^HKCU:') -ne ($Tweak.scope -eq 'user')) {
        'scope does not match its registry hive'
    }
    if ([string]::IsNullOrEmpty([string]$set.name)) { 'is missing set.name' }
    if ($null -ne $set.value) {
        if ($script:RegistryKinds -notcontains $set.kind) {
            "has an invalid registry kind '$($set.kind)'"
        } elseif (-not (Test-TuneupRegistryValue -Kind $set.kind -Value $set.value)) {
            "has a value that does not match kind $($set.kind)"
        }
    }
}
```

Al principio de `engine/handlers/Service.ps1` (antes de `$script:ScStartArguments`) agregar:

```powershell
$script:ServiceStartTypes = @('Automatic', 'AutomaticDelayed', 'Manual', 'Disabled')

function Test-ServiceTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]::IsNullOrEmpty([string]$set.name)) { 'is missing set.name' }
    if ($script:ServiceStartTypes -notcontains $set.startType) { "has an invalid startType '$($set.startType)'" }
    if ($set.stop -isnot [bool]) { 'set.stop must be true or false' }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}
```

Al principio de `engine/handlers/Task.ps1` agregar:

```powershell
$script:TaskStates = @('Enabled', 'Disabled')

function Test-TaskTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.path -notmatch '^\\(.*\\)?$') { 'task path must start and end with a backslash' }
    if ([string]::IsNullOrEmpty([string]$set.name)) { 'is missing set.name' }
    if (([string]$set.name + [string]$set.path) -match '[*?\[\]]') { 'task name and path cannot contain wildcard characters' }
    if ($script:TaskStates -notcontains $set.state) { "has an invalid task state '$($set.state)'" }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}
```

Los mensajes son los mismos que antes sin el id delante: `Test-TuneupTweak` lo agrega, así que `tests/Catalog.Tests.ps1` no cambia.

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas todas las pruebas de `tests/Catalog.Tests.ps1`.

- [ ] **Step 6: Commit**

```bash
git add engine/Dispatch.ps1 engine/Catalog.ps1 engine/handlers/Registry.ps1 engine/handlers/Service.ps1 engine/handlers/Task.ps1 tests/Dispatch.Tests.ps1
git commit -m "refactor: registro único de manejadores para despacho y catálogo"
```

---

### Task 3: Resultado `partial` y contrato de salida de los manejadores

**Files:**
- Modify: `engine/Dispatch.ps1`, `engine/Executor.ps1`, `engine/Output.ps1`, `engine/Undo.ps1`
- Modify: `i18n/es.json`, `i18n/en.json`
- Test: `tests/Dispatch.Tests.ps1`, `tests/Executor.Tests.ps1`, `tests/Output.Tests.ps1`, `tests/Undo.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Dispatch.Tests.ps1`:

```powershell
Describe 'Handler outcomes' {
    It 'ignores output that is not an outcome' {
        $outcome = Get-TuneupOutcome -Output @('noise', 5, [pscustomobject]@{ partial = $true; detail = 'plain' })
        $outcome.partial | Should -BeFalse
        $outcome.detail | Should -BeNullOrEmpty
        $outcome.rebootRequired | Should -BeFalse
        $outcome.reason | Should -BeNullOrEmpty
    }

    It 'merges partial, restart, reason and detail' {
        $outcome = Get-TuneupOutcome -Output @(
            (New-TuneupOutcome -Partial -Detail 'one'),
            'noise',
            (New-TuneupOutcome -RebootRequired -Detail 'two' -Reason 'reinstalled'))
        $outcome.partial | Should -BeTrue
        $outcome.rebootRequired | Should -BeTrue
        $outcome.reason | Should -Be 'reinstalled'
        $outcome.detail | Should -Be 'one; two'
    }

    It 'refuses a partial outcome without a detail' {
        { New-TuneupOutcome -Partial } | Should -Throw '*A partial outcome needs a detail*'
        { New-TuneupOutcome -Partial -Detail '' } | Should -Throw '*A partial outcome needs a detail*'
        (New-TuneupOutcome -Partial -Detail 'x').partial | Should -BeTrue
    }

    It 'returns an empty outcome for no output' {
        $outcome = Get-TuneupOutcome -Output @()
        $outcome.partial | Should -BeFalse
        $outcome.rebootRequired | Should -BeFalse
    }
}
```

Agregar dentro del `Describe 'Invoke-TuneupPlan'` de `tests/Executor.Tests.ps1`, después de la última prueba:

```powershell
    It 'reports a partial change with its explanation' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { 'noise'; New-TuneupOutcome -Partial -Detail 'half done' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results.Count | Should -Be 2
        $results[0].status | Should -Be 'partial'
        $results[0].detail | Should -Be 'half done'
        $results[0].error | Should -BeNullOrEmpty
        $results[1].status | Should -Be 'applied'
        $results[1].detail | Should -BeNullOrEmpty
        @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl')).Count | Should -Be 2
    }

    It 'reports partial even when the state reads as applied' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired {
            Write-TuneupRegistryValue -Path $Tweak.set.path -Name $Tweak.set.name -Kind $Tweak.set.kind -Value $Tweak.set.value
            New-TuneupOutcome -Partial -Detail 'x'
        } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        Test-TuneupState -Tweak $One | Should -Be 'applied'
        $results[0].status | Should -Be 'partial'
        $results[0].detail | Should -Be 'x'
    }

    It 'adds a restart asked for by the handler to the catalog flag' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired {
            Write-TuneupRegistryValue -Path $Tweak.set.path -Name $Tweak.set.name -Kind $Tweak.set.kind -Value $Tweak.set.value
            New-TuneupOutcome -RebootRequired
        } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'applied'
        $results[0].rebootRequired | Should -BeTrue
    }
```

En `tests/Output.Tests.ps1`, agregar estos dos casos al final de la lista `-TestCases` de `Describe 'Get-TuneupApplyExitCode'` (antes del paréntesis que la cierra):

```powershell
        @{ Name = 'a partial tweak'; Statuses = @('applied', 'partial'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a journal error after a partial change'; Statuses = @('partial', 'journal-error'); NotSaved = $false; Expected = 2 }
```

agregar dentro de `Describe 'New-TuneupApplyReport'`:

```powershell
    It 'counts partial tweaks and lets them ask for a restart' {
        $partial = New-TestResult -Status 'partial'
        $partial.rebootRequired = $true
        $report = New-TestReport @((New-TestResult -Status 'applied'), $partial)
        $report.summary.partial | Should -Be 1
        $report.summary.applied | Should -Be 1
        $report.rebootRequired | Should -BeTrue
        $report.summary.PSObject.Properties.Name -join ',' | Should -Be 'applied,partial,notApplied,failed,skipped,journalErrors'
    }
```

y dentro de `Describe 'Write-TuneupApplyReport'`:

```powershell
    It 'shows a partial tweak with its explanation' {
        $partial = [pscustomobject]@{ id = 'test.partial'; title = 'Title partial'; status = 'partial'; reason = $null; error = $null; detail = 'Stopping it failed'; rebootRequired = $false }
        $text = (Write-TuneupApplyReport -Report (New-TestReport @($partial)) 6>&1 | Out-String)
        $text | Should -Match '\[partial\] Title partial'
        $text | Should -Match 'Stopping it failed'
        $text | Should -Match 'Applied: 0 \| Partial: 1 \| No effect: 0 \| Failed: 0 \| Skipped: 0'
    }
```

Agregar dentro de `Describe 'Undo and status'` de `tests/Undo.Tests.ps1`:

```powershell
    It 'keeps a partial tweak in the status' {
        $run = Invoke-TestApply $Root
        $results = @(
            [pscustomobject]@{ id = 'test.one'; status = 'partial' },
            [pscustomobject]@{ id = 'test.two'; status = 'failed' }
        )
        Save-TuneupJson -Path (Join-Path $run.Dir 'result.json') -Object ([pscustomobject]@{ results = $results })
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one'
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: FAIL, `Get-TuneupOutcome` no se reconoce como comando.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: FAIL en `returns 2 for a partial tweak` (devuelve 0), `counts partial tweaks…` y `shows a partial tweak…`.

- [ ] **Step 3: Resultado de manejador**

Agregar al final de `engine/Dispatch.ps1`:

```powershell
# What a handler's Set or Restore can report besides doing its work. The type name marks it, so
# anything else a handler or a cmdlet prints is never mistaken for it.
function New-TuneupOutcome {
    param([switch]$Partial, [string]$Detail, [switch]$RebootRequired, [string]$Reason)
    if ($Partial -and -not $Detail) { throw 'A partial outcome needs a detail' }
    [pscustomobject]@{
        PSTypeName     = 'Tuneup.Outcome'
        partial        = [bool]$Partial
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = [bool]$RebootRequired
        reason         = $(if ($Reason) { $Reason } else { $null })
    }
}

function Get-TuneupOutcome {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Output = @())
    $merged = [pscustomobject]@{ partial = $false; detail = $null; rebootRequired = $false; reason = $null }
    foreach ($item in @($Output)) {
        if ($null -eq $item -or $item.PSObject.TypeNames -notcontains 'Tuneup.Outcome') { continue }
        if ($item.partial) { $merged.partial = $true }
        if ($item.rebootRequired) { $merged.rebootRequired = $true }
        if ($item.reason) { $merged.reason = $item.reason }
        if ($item.detail) {
            $merged.detail = $(if ($merged.detail) { "$($merged.detail); $($item.detail)" } else { $item.detail })
        }
    }
    $merged
}
```

- [ ] **Step 4: Ejecutor**

Reemplazar `engine/Executor.ps1` completo por:

```powershell
function New-TuneupResult {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason,
        [string]$ErrorText,
        [string]$Detail,
        [switch]$RebootRequired
    )
    [pscustomobject]@{
        id             = $Item.Id
        title          = Get-TuneupTitle -Tweak $Item.Tweak
        status         = $Status
        reason         = $(if ($Reason) { $Reason } else { $null })
        error          = $(if ($ErrorText) { $ErrorText } else { $null })
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = ([bool]$Item.Tweak.rebootRequired -or [bool]$RebootRequired)
    }
}

function Invoke-TuneupPlan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][string]$RunDir
    )
    $journal = Join-Path $RunDir 'snapshot.jsonl'
    $journalError = $null
    foreach ($item in $Plan) {
        if ($item.Action -ne 'apply') {
            New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason
            continue
        }
        if ($journalError) {
            New-TuneupResult -Item $item -Status 'skipped' -Reason 'journal-error' -ErrorText $journalError
            continue
        }
        $tweak = $item.Tweak
        try {
            $state = Get-TuneupState -Tweak $tweak
        } catch {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $_.Exception.Message
            continue
        }
        try {
            Add-TuneupJournalEntry -Path $journal -Tweak $tweak -State $state
        } catch {
            $journalError = $_.Exception.Message
            New-TuneupResult -Item $item -Status 'skipped' -Reason 'journal-error' -ErrorText $journalError
            continue
        }
        try {
            # Set may report through New-TuneupOutcome that it changed something but could not finish
            # (partial) or that Windows asked for a restart; any other output is ignored.
            $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $tweak)
            if ($outcome.partial) {
                $status = 'partial'
            } elseif ((Test-TuneupState -Tweak $tweak) -eq 'applied') {
                $status = 'applied'
            } else {
                $status = 'not-applied'
            }
            New-TuneupResult -Item $item -Status $status -Detail $outcome.detail -RebootRequired:$outcome.rebootRequired
        } catch {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $_.Exception.Message
        }
    }
}
```

- [ ] **Step 5: Reporte, código de salida y estado**

En `engine/Output.ps1`, reemplazar la función `New-TuneupApplyReport` completa por:

```powershell
function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment
    )
    # A tweak left out because its backup could not be written was not done: it is counted apart.
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status -and $_.reason -ne 'journal-error' }).Count }
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = ConvertTo-TuneupEnvironmentView -Environment $Environment
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            partial       = & $count 'partial'
            notApplied    = & $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
        }
        results        = $Results
    }
}
```

Reemplazar `Get-TuneupApplyExitCode` y el comentario que tiene encima por:

```powershell
# 0: everything done. 2: not everything was completed (a partial, failed or ineffective tweak, a
# backup that could not be written after some change, or an unsaved result; read the summary).
# 1: nothing was changed because the backups could not be written.
function Get-TuneupApplyExitCode {
    param([Parameter(Mandatory)]$Report, [switch]$ResultNotSaved)
    $summary = $Report.summary
    $touched = $summary.applied + $summary.partial + $summary.notApplied + $summary.failed
    if ($summary.journalErrors -and -not $touched) { return 1 }
    if ($summary.partial -or $summary.notApplied -or $summary.failed -or $summary.journalErrors -or $ResultNotSaved) { return 2 }
    0
}
```

Reemplazar `Write-TuneupApplyReport` completa por:

```powershell
function Write-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Report.results) {
        if ($result.reason -eq 'journal-error') {
            Write-Host ((Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key 'status.skipped'), $result.title) + ": $(Get-TuneupText -Key 'reason.journal-error')") -ForegroundColor Red
            if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
            continue
        }
        if ($result.status -eq 'skipped') { continue }
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title) -ForegroundColor $colors[$result.status]
        if ($result.detail) { Write-Host "    $($result.detail)" -ForegroundColor Yellow }
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    $summary = $Report.summary
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.partial, $summary.notApplied, $summary.failed, $summary.skipped)
    Write-Host (Get-TuneupText -Key "restore.$($Report.restorePoint)")
    Write-Host (Get-TuneupText -Key 'run.saved' -Format $Report.runId, $Report.runDir)
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}
```

En `engine/Undo.ps1`, dentro de `Get-TuneupStatus`, reemplazar:

```powershell
            $touchedIds = @($result.results | Where-Object { $_.status -eq 'applied' -or $_.status -eq 'not-applied' } | ForEach-Object { $_.id })
```

por:

```powershell
            $touchedIds = @($result.results | Where-Object { $_.status -eq 'applied' -or $_.status -eq 'partial' -or $_.status -eq 'not-applied' } | ForEach-Object { $_.id })
```

- [ ] **Step 6: Textos**

En `i18n/es.json`, agregar `"status.partial"` justo después de `"status.applied"` y reemplazar la línea de `"summary"`:

```json
  "status.partial": "parcial",
  "summary": "Aplicados: {0} · Parciales: {1} · Sin efecto: {2} · Fallidos: {3} · Omitidos: {4}",
```

En `i18n/en.json`, lo mismo:

```json
  "status.partial": "partial",
  "summary": "Applied: {0} | Partial: {1} | No effect: {2} | Failed: {3} | Skipped: {4}",
```

- [ ] **Step 7: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`). `does not leak handler output into the results` sigue pasando: la cadena `'noise'` no es un resultado de manejador.

- [ ] **Step 8: Commit**

```bash
git add engine/Dispatch.ps1 engine/Executor.ps1 engine/Output.ps1 engine/Undo.ps1 i18n/es.json i18n/en.json tests/Dispatch.Tests.ps1 tests/Executor.Tests.ps1 tests/Output.Tests.ps1 tests/Undo.Tests.ps1
git commit -m "feat: resultado partial con explicación y reinicio pedido por el manejador"
```

---

### Task 4: Servicio que no se pudo detener queda `partial`

**Files:**
- Modify: `engine/handlers/Service.ps1`
- Test: `tests/Service.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

En `tests/Service.Tests.ps1`, reemplazar la prueba `It 'throws a clear error when stopping fails after the start type was changed'` completa por estas dos:

```powershell
    It 'reports a partial change when stopping fails after the start type was changed' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { throw 'cannot stop' }
        $outcome = Get-TuneupOutcome -Output @(Set-ServiceTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -Be 'Start type of RetailDemo set to Disabled, but stopping it failed: cannot stop'
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'fails without a partial result when the start type cannot be changed' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { throw 'sc.exe config RetailDemo start= disabled failed with exit code 5: Access is denied.' }
        Mock -ModuleName Tuneup Stop-Service { }
        { Set-ServiceTweakDesired -Tweak $Tweak } | Should -Throw '*exit code 5*'
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 0 -Exactly
    }
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Service.Tests.ps1`
Expected: FAIL en `reports a partial change…` con la excepción `Start type of RetailDemo set to Disabled, but stopping it failed: cannot stop`.

- [ ] **Step 3: Implementación**

En `engine/handlers/Service.ps1`, dentro de `Set-ServiceTweakDesired`, reemplazar:

```powershell
        catch {
            throw "Start type of $name set to $startType, but stopping it failed: $($_.Exception.Message)"
        }
```

por:

```powershell
        catch {
            # The start type did change, so this is reported as partial instead of failed.
            New-TuneupOutcome -Partial -Detail "Start type of $name set to $startType, but stopping it failed: $($_.Exception.Message)"
        }
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Service.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Service.ps1 tests/Service.Tests.ps1
git commit -m "feat: servicio deshabilitado que no se pudo detener queda parcial"
```

---

### Task 5: Deshacer con las notas del manejador

**Files:**
- Modify: `engine/Undo.ps1`, `engine/Output.ps1`
- Modify: `i18n/es.json`, `i18n/en.json`
- Test: `tests/Undo.Tests.ps1`, `tests/Output.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

Agregar dentro de `Describe 'Undo and status'` de `tests/Undo.Tests.ps1`:

```powershell
    It 'passes the note, detail and restart request of the restore into the result' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { New-TuneupOutcome -Reason 'reinstalled' -Detail 'for the current user only' -RebootRequired } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupUndo -Run $run)
        $results[0].id | Should -Be 'test.two'
        $results[0].status | Should -Be 'restored'
        $results[0].reason | Should -Be 'reinstalled'
        $results[0].detail | Should -Be 'for the current user only'
        $results[0].rebootRequired | Should -BeTrue
        $results[1].reason | Should -BeNullOrEmpty
        $results[1].rebootRequired | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
        Get-TuneupUndoExitCode -Results $results | Should -Be 0
    }
```

Agregar dentro de `Describe 'Write-TuneupUndoReport'` de `tests/Output.Tests.ps1`:

```powershell
    It 'shows the restore note and asks for a restart' {
        $restored = [pscustomobject]@{ id = 'apps.news'; title = 'News'; status = 'restored'; reason = 'reinstalled'; error = $null; detail = 'Reinstalled for the current user'; rebootRequired = $true }
        $text = (Write-TuneupUndoReport -RunId '20250101-000000' -Results @($restored) 6>&1 | Out-String)
        $text | Should -Match 'News: reinstalled from the Microsoft Store'
        $text | Should -Match 'Reinstalled for the current user'
        $text | Should -Match 'Restart the computer'
        (Write-TuneupUndoReport -RunId '20250101-000000' -Results @($restored) -Json | ConvertFrom-Json).rebootRequired | Should -BeTrue
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Undo.Tests.ps1`
Expected: FAIL en `passes the note, detail and restart request…`: `reason` vacío.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: FAIL en `shows the restore note…`: el texto dice `reason.reinstalled` (la clave no existe todavía).

- [ ] **Step 3: Implementación**

En `engine/Undo.ps1`, reemplazar la función `Invoke-TuneupUndo` completa por:

```powershell
function Invoke-TuneupUndo {
    param([Parameter(Mandatory)]$Run, [string]$TweakId)
    Assert-TuneupRunUndoable -Run $Run
    # A run object built before the undo carries no Undone flag, so the marker itself decides.
    if ($Run.Undone -or (Test-TuneupRunMarker -Dir $Run.Dir -Name 'undone.json' -Root $Run.Root)) {
        throw (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $Run.Id)
    }
    $journal = Get-TuneupRunJournal -Run $Run
    $alreadyUndone = @(Get-TuneupUndoneTweakId -Run $Run)
    $entries = @($journal.Entries)
    # Entries of another user are reported as skipped: they stay pending for their owner.
    $foreign = @($journal.SkippedEntries)
    $newResult = {
        param($entry, [string]$status, $reason, $errorText, $outcome)
        [pscustomobject]@{
            id             = $entry.id
            title          = Get-TuneupTitle -Tweak $entry.tweak
            status         = $status
            reason         = $reason
            error          = $errorText
            detail         = $(if ($outcome) { $outcome.detail } else { $null })
            rebootRequired = $(if ($outcome) { [bool]$outcome.rebootRequired } else { $false })
        }
    }
    if ($TweakId) {
        $entries = @($entries | Where-Object { $_.id -eq $TweakId })
        $foreign = @($foreign | Where-Object { $_.id -eq $TweakId })
        if (-not $entries.Count -and -not $foreign.Count) { throw (Get-TuneupText -Key 'err.tweakNotInRun' -Format $TweakId) }
        if ($alreadyUndone -contains $TweakId) {
            # Restoring again would overwrite whatever the tweak holds now with a stale value.
            return (& $newResult (@($entries) + @($foreign))[0] 'skipped' 'already-undone' $null $null)
        }
        if (-not $entries.Count) { return (& $newResult $foreign[0] 'skipped' 'other-user' $null $null) }
    } else {
        $entries = @($entries | Where-Object { $alreadyUndone -notcontains $_.id })
        $foreign = @($foreign | Where-Object { $alreadyUndone -notcontains $_.id })
    }
    [array]::Reverse($entries)
    [array]::Reverse($foreign)
    $results = @(foreach ($entry in $entries) {
        try {
            # A restore can add a note (for example, reinstalled from the Store) and ask for a restart.
            $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $entry.tweak -State $entry.state)
            & $newResult $entry 'restored' $outcome.reason $null $outcome
        } catch {
            & $newResult $entry 'failed' $null $_.Exception.Message $null
        }
    })
    $results += @(foreach ($entry in $foreign) { & $newResult $entry 'skipped' 'other-user' $null $null })
    # The values are already restored; an unrecorded undo would leave the run pending, so it is reported.
    # The whole run is marked only when every one of its tweaks is restored. Anything left (a failed
    # restore, or entries of another user) keeps the run pending, and only the tweaks restored here are
    # noted, so a retry or the other user picks up the rest.
    $restoredIds = @($results | Where-Object { $_.status -eq 'restored' } | ForEach-Object { $_.id })
    $doneIds = @($alreadyUndone) + $restoredIds
    $runIds = @(@($journal.Entries | ForEach-Object { $_.id }) + @($journal.Skipped))
    $pendingIds = @($runIds | Where-Object { $doneIds -notcontains $_ })
    try {
        if ($pendingIds.Count -eq 0) {
            Save-TuneupJson -Path (Join-Path $Run.Dir 'undone.json') -Root $Run.Root `
                -Object ([pscustomobject]@{ undoneAt = (Get-Date).ToString('s'); results = $results })
        } elseif ($restoredIds.Count) {
            Write-TuneupStateFile -Path (Join-Path $Run.Dir 'undone-tweaks.txt') -Root $Run.Root -Append `
                -Text (($restoredIds -join [Environment]::NewLine) + [Environment]::NewLine)
        }
    } catch {
        $results += [pscustomobject]@{ id = $null; title = "run $($Run.Id)"; status = 'failed'; reason = $null; error = "The undo could not be recorded: $($_.Exception.Message)"; detail = $null; rebootRequired = $false }
    }
    $results
}
```

En `engine/Output.ps1`, reemplazar la función `Write-TuneupUndoReport` completa por:

```powershell
function Write-TuneupUndoReport {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    $restored = @($Results | Where-Object { $_.status -eq 'restored' }).Count
    $failed = @($Results | Where-Object { $_.status -eq 'failed' }).Count
    $skipped = @($Results | Where-Object { $_.status -eq 'skipped' }).Count
    $rebootRequired = @($Results | Where-Object { $_.rebootRequired }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion  = 1
            command        = 'undo'
            runId          = $RunId
            rebootRequired = $rebootRequired
            results        = $Results
            summary        = [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'undo.header' -Format $RunId)
    $colors = @{ 'restored' = 'Green'; 'skipped' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Results) {
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
        if ($result.detail) { Write-Host "    $($result.detail)" -ForegroundColor DarkGray }
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    Write-Host (Get-TuneupText -Key 'undo.summary' -Format $restored, $failed, $skipped)
    if ($rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}
```

- [ ] **Step 4: Textos**

En `i18n/es.json`, después de la línea `"reason.other-user": ...`, agregar:

```json
  "reason.reinstalled": "reinstalada desde Microsoft Store para el usuario actual; no se volvió a provisionar para usuarios nuevos",
  "reason.not-reprovisioned": "solo estaba provisionada para usuarios nuevos y no se puede volver a provisionar desde la Store",
```

En `i18n/en.json`, en el mismo lugar:

```json
  "reason.reinstalled": "reinstalled from the Microsoft Store for the current user; not provisioned again for new users",
  "reason.not-reprovisioned": "it was only provisioned for new users and cannot be provisioned again from the Store",
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`).

- [ ] **Step 6: Commit**

```bash
git add engine/Undo.ps1 engine/Output.ps1 i18n/es.json i18n/en.json tests/Undo.Tests.ps1 tests/Output.Tests.ps1
git commit -m "feat: deshacer informa notas y reinicio pedidos por el manejador"
```

---

### Task 6: Ejecutables nativos sin cortes por la salida de errores

**Files:**
- Create: `engine/Native.ps1`
- Modify: `engine/handlers/Service.ps1`
- Test: `tests/Native.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Native.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
}

Describe 'Invoke-TuneupNative' {
    It 'returns the exit code and both output streams without throwing' {
        $result = Invoke-TuneupNative -FilePath $Cmd -Arguments @('/c', 'echo out & echo err 1>&2 & exit 3')
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Match 'out'
        $result.Output | Should -Match 'err'
    }

    It 'returns exit code 0 for a tool that succeeds' {
        (Invoke-TuneupNative -FilePath $Cmd -Arguments @('/c', 'exit 0')).ExitCode | Should -Be 0
    }
}

Describe 'Invoke-TuneupSc' {
    It 'calls sc.exe config with start= and the value as separate arguments' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = '[SC] ChangeServiceConfig SUCCESS' } }
        Invoke-TuneupSc -Name 'RetailDemo' -Start 'disabled'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\System32\sc.exe' -and ($Arguments -join '|') -eq 'config|RetailDemo|start=|disabled'
        }
    }

    It 'throws with the exit code and the output when sc.exe fails' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 1060; Output = 'The specified service does not exist as an installed service.' } }
        { Invoke-TuneupSc -Name 'Nope' -Start 'disabled' } | Should -Throw '*exit code 1060*does not exist*'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Native.Tests.ps1`
Expected: FAIL, `Invoke-TuneupNative` no se reconoce como comando.

- [ ] **Step 3: Implementación**

`engine/Native.ps1`:

```powershell
function Invoke-TuneupNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )
    # Native tools report failure through their exit code. With Stop, Windows PowerShell 5.1 turns
    # any line they write to standard error into a terminating error before that code can be read.
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @Arguments 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    }
}
```

En `engine/handlers/Service.ps1`, reemplazar la función `Invoke-TuneupSc` completa por:

```powershell
function Invoke-TuneupSc {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Start)
    $result = Invoke-TuneupNative -FilePath (Join-Path $env:SystemRoot 'System32\sc.exe') -Arguments @('config', $Name, 'start=', $Start)
    if ($result.ExitCode -ne 0) {
        throw "sc.exe config $Name start= $Start failed with exit code $($result.ExitCode): $($result.Output)"
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Native.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Service.Tests.ps1`
Expected: PASS (sus pruebas simulan `Invoke-TuneupSc`).

- [ ] **Step 5: Commit**

```bash
git add engine/Native.ps1 engine/handlers/Service.ps1 tests/Native.Tests.ps1
git commit -m "fix: ejecutables nativos con código de salida aunque escriban errores"
```

---

### Task 7: Manejador `appx`: estado, verificación y quitar

**Files:**
- Create: `engine/handlers/Appx.ps1`
- Test: `tests/Appx.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Appx.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'apps.bing-news' -Type 'appx' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
    function New-FakePackage([string]$InstallState = 'Installed') {
        [pscustomobject]@{
            Name                   = 'Microsoft.BingNews'
            PackageFullName        = 'Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe'
            Version                = '4.55.62231.0'
            PackageUserInformation = @([pscustomobject]@{ InstallState = $InstallState })
        }
    }
    $script:Provisioned = [pscustomobject]@{
        DisplayName = 'Microsoft.BingNews'
        PackageName = 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        Version     = '4.55.62231.0'
    }
}

Describe 'Appx handler' {
    It 'reads an app installed for a user and provisioned' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeTrue
        $state.provisioned | Should -BeTrue
        $state.version | Should -Be '4.55.62231.0'
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'treats a package only staged for a user as not installed' {
        $staged = New-FakePackage -InstallState 'Staged'
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $staged }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        (Get-AppxTweakState -Tweak $Tweak).installedUsers | Should -BeFalse
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'still needs the removal when the app is only provisioned' {
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'counts an app that is neither installed nor provisioned as applied' {
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeFalse
        $state.provisioned | Should -BeFalse
        $state.version | Should -BeNullOrEmpty
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'removes the app for all users and deprovisions it' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        Should -Invoke Remove-TuneupAppxPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $Package.PackageFullName -eq 'Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe'
        }
        Should -Invoke Remove-TuneupAppxProvisionedPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $Package.PackageName -eq 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        }
    }

    It 'reports a partial change when deprovisioning fails after the removal' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { throw 'Access denied' }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*provisioned package*Access denied*'
    }

    It 'throws when nothing could be removed' {
        $installed = New-FakePackage
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { throw 'in use' }
        { Set-AppxTweakDesired -Tweak $Tweak } | Should -Throw '*for all users failed: in use*'
    }
}

Describe 'Appx definition' {
    It 'accepts a valid appx tweak' {
        (Test-AppxTweakDefinition -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a wildcard in the name'; Field = 'name'; Value = 'Microsoft.Bing*'; Message = 'invalid appx package name' }
        @{ Problem = 'a lowercase Store id'; Field = 'storeId'; Value = '9wzdncrfhvfw'; Message = 'Microsoft Store id' }
        @{ Problem = 'a short Store id'; Field = 'storeId'; Value = '9WZDNCRF'; Message = 'Microsoft Store id' }
        @{ Problem = 'another action'; Field = 'action'; Value = 'install'; Message = "invalid appx action 'install'" }
    ) {
        param($Field, $Value, $Message)
        $set = [pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' }
        $set.$Field = $Value
        $tweak = New-TestTweak -Type 'appx' -Scope 'machine' -Set $set
        (Test-AppxTweakDefinition -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'requires scope machine' {
        $tweak = New-TestTweak -Type 'appx' -Scope 'user' -Set $Tweak.set
        (Test-AppxTweakDefinition -Tweak $tweak) -join '; ' | Should -Match 'must use scope machine'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Appx.Tests.ps1`
Expected: FAIL, `Get-AppxTweakState` no se reconoce como comando.

- [ ] **Step 3: Implementación**

`engine/handlers/Appx.ps1`:

```powershell
# Appx package names look like Microsoft.BingNews; Store ids are the 12-character product ids
# that winget uses with --source msstore.
$script:AppxNamePattern = '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$'
$script:StoreIdPattern = '^[0-9A-Z]{12}$'

function Test-AppxTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:AppxNamePattern) { 'has an invalid appx package name' }
    if ([string]$set.storeId -cnotmatch $script:StoreIdPattern) { 'needs a Microsoft Store id (12 capital letters or digits) in set.storeId' }
    if ($set.action -cne 'remove') { "has an invalid appx action '$($set.action)'" }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}

function Get-TuneupAppxPackage {
    param([Parameter(Mandatory)][string]$Name)
    # -Name takes wildcards, so only the exact name is kept.
    Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop | Where-Object { $_.Name -eq $Name }
}

function Get-TuneupAppxProvisionedPackage {
    param([Parameter(Mandatory)][string]$Name)
    Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $Name }
}

function Remove-TuneupAppxPackage {
    param([Parameter(Mandatory)]$Package)
    Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction Stop
}

function Remove-TuneupAppxProvisionedPackage {
    param([Parameter(Mandatory)]$Package)
    Remove-AppxProvisionedPackage -Online -PackageName $Package.PackageName -AllUsers -ErrorAction Stop | Out-Null
}

function Test-TuneupAppxInstalledForAnyUser {
    param([AllowEmptyCollection()][object[]]$Packages = @())
    # -AllUsers also lists packages that are only staged for a user (provisioned, never installed).
    foreach ($package in $Packages) {
        foreach ($user in @($package.PackageUserInformation)) {
            if ([string]$user.InstallState -eq 'Installed') { return $true }
        }
    }
    $false
}

function Get-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $installed = @(Get-TuneupAppxPackage -Name $name)
    $provisioned = @(Get-TuneupAppxProvisionedPackage -Name $name)
    $versions = @(@($installed | ForEach-Object { [string]$_.Version }) + @($provisioned | ForEach-Object { [string]$_.Version }) | Where-Object { $_ })
    [pscustomobject]@{
        installedUsers = (Test-TuneupAppxInstalledForAnyUser -Packages $installed)
        provisioned    = ($provisioned.Count -gt 0)
        version        = $(if ($versions.Count) { $versions[0] } else { $null })
    }
}

function Test-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-AppxTweakState -Tweak $Tweak
    # An app that is neither installed nor provisioned already matches the goal: there is nothing to remove.
    if ($state.installedUsers -or $state.provisioned) { return 'not-applied' }
    'applied'
}

function Set-AppxTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $changed = 0
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($package in @(Get-TuneupAppxPackage -Name $name)) {
        try {
            Remove-TuneupAppxPackage -Package $package
            $changed++
        } catch {
            $problems.Add("removing $($package.PackageFullName) for all users failed: $($_.Exception.Message)")
        }
    }
    foreach ($package in @(Get-TuneupAppxProvisionedPackage -Name $name)) {
        try {
            Remove-TuneupAppxProvisionedPackage -Package $package
            $changed++
        } catch {
            $problems.Add("removing the provisioned package $($package.PackageName) failed: $($_.Exception.Message)")
        }
    }
    if (-not $problems.Count) { return }
    $message = $problems -join '; '
    # Some removal worked: the app is partly gone, which is not the same as a failure.
    if ($changed) { return (New-TuneupOutcome -Partial -Detail $message) }
    throw $message
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Appx.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Appx.ps1 tests/Appx.Tests.ps1
git commit -m "feat: manejador appx con quitar para todos y desprovisionar"
```

---

### Task 8: Manejador `appx`: reinstalar con winget y registrarlo

**Files:**
- Modify: `engine/handlers/Appx.ps1`, `engine/Dispatch.ps1`
- Test: `tests/Appx.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Appx.Tests.ps1`:

```powershell
Describe 'Appx restore' {
    It 'reinstalls an app that was installed, from the Store, for the current user' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = 0; Output = 'Successfully installed' } }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $true; version = '4.55.62231.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        $outcome.detail | Should -BeLike '*current user only*not provisioned again*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id 9WZDNCRFHVFW --source msstore --exact --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
        }
    }

    It 'accepts the winget code for an app that is already installed' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335135; Output = 'Found an existing package already installed.' } }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $false; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -Be 'reinstalled'
    }

    It 'throws with the winget exit code when the install fails' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No package found matching input criteria.' } }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $false; version = '1.0' }
        { Restore-AppxTweakState -Tweak $Tweak -State $state } | Should -Throw '*exit code -1978335212*No package found*'
    }

    It 'does not call winget when the current user still has the app' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $true }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $true; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -BeNullOrEmpty
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'does nothing for an app that was not there' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { }
        $state = [pscustomobject]@{ installedUsers = $false; provisioned = $false; version = $null }
        @(Restore-AppxTweakState -Tweak $Tweak -State $state).Count | Should -Be 0
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'explains that an app that was only provisioned cannot be provisioned again' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { }
        $state = [pscustomobject]@{ installedUsers = $false; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'not-reprovisioned'
        $outcome.detail | Should -BeLike '*winget install --id 9WZDNCRFHVFW --source msstore*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'winget' {
    It 'throws a clear error when winget is missing' {
        Mock -ModuleName Tuneup Get-TuneupWingetPath { }
        { Invoke-TuneupWinget -Arguments @('--version') } | Should -Throw '*winget is not available*'
    }

    It 'runs winget through the native runner' {
        Mock -ModuleName Tuneup Get-TuneupWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = 'v1.9.25200' } }
        (Invoke-TuneupWinget -Arguments @('--version')).Output | Should -Be 'v1.9.25200'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\fake\winget.exe' -and ($Arguments -join ' ') -eq '--version'
        }
    }
}

Describe 'Appx registration' {
    It 'is a dispatched type that needs elevation to read' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Appx'
        (Get-TuneupHandler -Type 'appx').ReadNeedsAdmin | Should -BeTrue
    }

    It 'passes the catalog validation' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Appx.Tests.ps1`
Expected: FAIL, `Restore-AppxTweakState` y `Invoke-TuneupWinget` no se reconocen; `Unsupported tweak type 'appx'`.

- [ ] **Step 3: Implementación**

Agregar al final de `engine/handlers/Appx.ps1`:

```powershell
# winget: APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED (0x8A150061).
$script:WingetAlreadyInstalled = -1978335135

function Get-TuneupWingetPath {
    $command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { $command.Source }
}

function Invoke-TuneupWinget {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $path = Get-TuneupWingetPath
    if (-not $path) { throw 'winget is not available. Install App Installer from the Microsoft Store and run the undo again.' }
    Invoke-TuneupNative -FilePath $path -Arguments $Arguments
}

function Get-TuneupWingetInstallArgument {
    param([Parameter(Mandatory)][string]$StoreId)
    'install', '--id', $StoreId, '--source', 'msstore', '--exact', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'
}

function Test-TuneupAppxInstalledForCurrentUser {
    param([Parameter(Mandatory)][string]$Name)
    @(Get-AppxPackage -Name $Name -ErrorAction Stop | Where-Object { $_.Name -eq $Name }).Count -gt 0
}

function Restore-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $name = [string]$Tweak.set.name
    $storeId = [string]$Tweak.set.storeId
    if (-not $State.installedUsers) {
        if ($State.provisioned) {
            # Provisioning needs the package file, which the Store does not hand out.
            return (New-TuneupOutcome -Reason 'not-reprovisioned' -Detail "$name was only provisioned for new users and cannot be provisioned again. To install it: winget install --id $storeId --source msstore")
        }
        return
    }
    if (Test-TuneupAppxInstalledForCurrentUser -Name $name) { return }
    $result = Invoke-TuneupWinget -Arguments @(Get-TuneupWingetInstallArgument -StoreId $storeId)
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne $script:WingetAlreadyInstalled) {
        throw "winget could not reinstall $name ($storeId), exit code $($result.ExitCode): $($result.Output)"
    }
    New-TuneupOutcome -Reason 'reinstalled' -Detail "$name was reinstalled from the Microsoft Store for the current user only; it was not provisioned again for new users"
}
```

En `engine/Dispatch.ps1`, agregar la entrada `appx` a la tabla, después de `task`:

```powershell
    appx     = [pscustomobject]@{ Name = 'Appx'; ReadNeedsAdmin = $true }
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Appx.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: PASS (el registro exige las cinco funciones de `Appx`).

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Appx.ps1 engine/Dispatch.ps1 tests/Appx.Tests.ps1
git commit -m "feat: appx reinstala desde la Store con winget al deshacer"
```

---

### Task 9: Estado que solo se lee con administrador

**Files:**
- Modify: `engine/Dispatch.ps1`, `engine/Planner.ps1`, `engine/Undo.ps1`, `engine/Output.ps1`
- Modify: `i18n/es.json`, `i18n/en.json`
- Test: `tests/Planner.Tests.ps1`, `tests/Undo.Tests.ps1`, `tests/Output.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Planner.Tests.ps1`:

```powershell
Describe 'New-TuneupPlan with state that needs elevation to read' {
    BeforeAll {
        $appSet = [pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' }
        $script:AppCatalog = @(
            (New-TestTweak -Id 'apps.news' -Type 'appx' -Scope 'machine' -Set $appSet),
            (New-TestTweak -Id 'apps.risky' -Type 'appx' -Scope 'machine' -Risk 'high' -Set $appSet)
        )
        $script:AppProfiles = @(New-TestProfile -Id 'base' -Include @('apps.news', 'apps.risky'))
        $script:UserEnvironment = New-TestEnvironment
        $script:UserEnvironment.IsAdmin = $false
    }

    It 'plans it as unverified without reading it when not elevated' {
        $plan = @(New-TuneupPlan -Catalog $AppCatalog -Profiles $AppProfiles -Environment $UserEnvironment -TestState { throw 'must not read' })
        $plan[0].Action | Should -Be 'apply'
        $plan[0].Reason | Should -Be 'unverified-needs-admin'
    }

    It 'still leaves out an unverified high-risk tweak that was not requested' {
        $plan = @(New-TuneupPlan -Catalog $AppCatalog -Profiles $AppProfiles -Environment $UserEnvironment -TestState { throw 'must not read' })
        $plan[1].Action | Should -Be 'skip'
        $plan[1].Reason | Should -Be 'high-risk-not-requested'
    }

    It 'reads it when elevated' {
        $plan = @(New-TuneupPlan -Catalog $AppCatalog -Profiles $AppProfiles -Environment (New-TestEnvironment) -TestState { 'applied' })
        $plan[0].Action | Should -Be 'skip'
        $plan[0].Reason | Should -Be 'already-applied'
    }
}
```

Agregar dentro de `Describe 'Undo and status'` de `tests/Undo.Tests.ps1`:

```powershell
    It 'says a tweak needs elevation to check instead of reading it' {
        $appx = New-TestTweak -Id 'apps.news' -Type 'appx' -Scope 'machine' `
            -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
        New-RunFolder -Root $Root -Id '20250101-000000' -Tweaks @($appx) | Out-Null
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        Mock -ModuleName Tuneup Test-TuneupState { throw 'must not read' }
        $status = @(Get-TuneupStatus -StateRoot $Root)
        $status.Count | Should -Be 1
        $status[0].status | Should -Be 'needs-admin'
        Should -Invoke Test-TuneupState -ModuleName Tuneup -Times 0 -Exactly
    }
```

Agregar dentro de `Describe 'Write-TuneupPlanReport'` de `tests/Output.Tests.ps1`:

```powershell
    It 'explains a change that could not be checked without elevation' {
        $item = New-TestPlanItem 'machine' 'apply'
        $item.Reason = 'unverified-needs-admin'
        (Write-TuneupPlanReport -Plan @($item) -Environment (New-TestEnvironment) 6>&1 | Out-String) | Should -Match 'checked when applied'
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: FAIL en `plans it as unverified…`: `Reason` es `state-unreadable`.

- [ ] **Step 3: Implementación**

Agregar al final de `engine/Dispatch.ps1`:

```powershell
function Test-TuneupHandlerReadNeedsAdmin {
    param([Parameter(Mandatory)]$Tweak)
    $handler = Get-TuneupHandler -Type $Tweak.type
    ($null -ne $handler) -and [bool]$handler.ReadNeedsAdmin
}
```

En `engine/Planner.ps1`, dentro de `New-TuneupPlan`, reemplazar el cuerpo del `foreach ($tweakId in $wanted)` completo por:

```powershell
    foreach ($tweakId in $wanted) {
        $tweak = $byId[$tweakId]
        if ($null -eq $tweak) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
        $requested = $Include -contains $tweakId
        $reason = $null
        $note = $null
        if ($Exclude -contains $tweakId) { $reason = 'excluded' }
        elseif (($keep -contains $tweakId) -and -not $requested) { $reason = 'kept-by-profile' }
        elseif (-not (Test-TuneupCompatible -Tweak $tweak -Environment $Environment)) { $reason = 'incompatible' }
        elseif ($Environment.IsManaged -and (Test-TuneupPolicyTweak -Tweak $tweak)) { $reason = 'managed-device' }
        else {
            if ((Test-TuneupHandlerReadNeedsAdmin -Tweak $tweak) -and -not $Environment.IsAdmin) {
                # Applying it needs elevation anyway; the plan says it is checked then instead of
                # calling it unreadable.
                $state = 'unverified'
            } else {
                try { $state = & $TestState $tweak } catch { $state = 'unreadable' }
            }
            if ($state -eq 'applied') { $reason = 'already-applied' }
            elseif ($state -eq 'not-present') { $reason = 'not-present' }
            elseif ($state -eq 'unreadable') { $reason = 'state-unreadable' }
            elseif ($tweak.risk -eq 'high' -and -not $requested) { $reason = 'high-risk-not-requested' }
            elseif ($tweak.ask -and -not $Interactive -and -not $requested) { $reason = 'needs-confirmation' }
            elseif ($state -eq 'unverified') { $note = 'unverified-needs-admin' }
        }
        [pscustomobject]@{
            Id     = $tweakId
            Tweak  = $tweak
            Action = $(if ($reason) { 'skip' } else { 'apply' })
            Reason = $(if ($reason) { $reason } else { $note })
        }
    }
```

En `engine/Undo.ps1`, dentro de `Get-TuneupStatus`, reemplazar:

```powershell
        try {
            $state = Test-TuneupState -Tweak $item.tweak
            $status = switch ($state) { 'applied' { 'ok' } 'not-applied' { 'drift' } default { 'not-present' } }
        } catch {
            $status = 'unknown'
        }
```

por:

```powershell
        try {
            if ((Test-TuneupHandlerReadNeedsAdmin -Tweak $item.tweak) -and -not (Test-TuneupAdmin)) {
                $status = 'needs-admin'
            } else {
                $state = Test-TuneupState -Tweak $item.tweak
                $status = switch ($state) { 'applied' { 'ok' } 'not-applied' { 'drift' } default { 'not-present' } }
            }
        } catch {
            $status = 'unknown'
        }
```

En `engine/Output.ps1`, dentro de `Write-TuneupPlanReport`, reemplazar:

```powershell
        if ($item.action -eq 'apply') {
            Write-Host (Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")) -ForegroundColor Cyan
        } else {
```

por:

```powershell
        if ($item.action -eq 'apply') {
            $line = Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")
            if ($item.reason) { $line += ": $(Get-TuneupText -Key "reason.$($item.reason)")" }
            Write-Host $line -ForegroundColor Cyan
        } else {
```

y dentro de `Write-TuneupStatusReport`, reemplazar:

```powershell
    $colors = @{ 'ok' = 'Green'; 'drift' = 'Yellow'; 'not-present' = 'DarkGray'; 'unknown' = 'Red' }
```

por:

```powershell
    $colors = @{ 'ok' = 'Green'; 'drift' = 'Yellow'; 'not-present' = 'DarkGray'; 'unknown' = 'Red'; 'needs-admin' = 'DarkYellow' }
```

- [ ] **Step 4: Textos**

En `i18n/es.json`, después de `"reason.state-unreadable": ...`, agregar:

```json
  "reason.unverified-needs-admin": "se comprueba al aplicar: leer su estado requiere administrador",
```

y después de `"status.unknown": ...`:

```json
  "status.needs-admin": "requiere administrador para comprobarlo",
```

En `i18n/en.json`, en los mismos lugares:

```json
  "reason.unverified-needs-admin": "checked when applied: reading its state needs administrator",
```

```json
  "status.needs-admin": "needs administrator to check",
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`).

- [ ] **Step 6: Commit**

```bash
git add engine/Dispatch.ps1 engine/Planner.ps1 engine/Undo.ps1 engine/Output.ps1 i18n/es.json i18n/en.json tests/Planner.Tests.ps1 tests/Undo.Tests.ps1 tests/Output.Tests.ps1
git commit -m "feat: plan y estado avisan cuando leer un ajuste requiere administrador"
```

---

### Task 10: Manejador `capability`

**Files:**
- Create: `engine/handlers/Capability.ps1`
- Modify: `engine/Dispatch.ps1`
- Test: `tests/Capability.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Capability.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Name = 'App.StepsRecorder~~~~0.0.1.0'
    $script:Tweak = New-TestTweak -Id 'apps.steps-recorder' -Type 'capability' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = $Name; state = 'NotPresent' })
}

Describe 'Capability handler' {
    BeforeEach {
        $script:Raw = 'Installed'
        Mock -ModuleName Tuneup Get-TuneupWindowsCapability { [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0'; State = $script:Raw } }
    }

    It 'maps <Raw> to <Expected>' -TestCases @(
        @{ Raw = 'Installed'; Expected = 'Installed' }
        @{ Raw = 'InstallPending'; Expected = 'Installed' }
        @{ Raw = 'NotPresent'; Expected = 'NotPresent' }
        @{ Raw = 'UninstallPending'; Expected = 'NotPresent' }
        @{ Raw = 'Staged'; Expected = 'NotPresent' }
        @{ Raw = 'Removed'; Expected = 'NotPresent' }
    ) {
        param($Raw, $Expected)
        ConvertTo-TuneupCapabilityState -State $Raw | Should -Be $Expected
    }

    It 'is not applied while the capability is installed' {
        (Get-CapabilityTweakState -Tweak $Tweak).state | Should -Be 'Installed'
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'is applied once the removal waits for a restart' {
        $script:Raw = 'UninstallPending'
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a capability that this Windows does not list as not-present' {
        Mock -ModuleName Tuneup Get-TuneupWindowsCapability { }
        (Get-CapabilityTweakState -Tweak $Tweak).present | Should -BeFalse
        Test-CapabilityTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'removes the capability and passes on a restart request' {
        Mock -ModuleName Tuneup Remove-TuneupWindowsCapability { [pscustomobject]@{ RestartNeeded = $true } }
        $outcome = Get-TuneupOutcome -Output @(Set-CapabilityTweakDesired -Tweak $Tweak)
        $outcome.rebootRequired | Should -BeTrue
        Should -Invoke Remove-TuneupWindowsCapability -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'App.StepsRecorder~~~~0.0.1.0' }
    }

    It 'adds the capability back on restore' {
        $script:Raw = 'NotPresent'
        Mock -ModuleName Tuneup Add-TuneupWindowsCapability { [pscustomobject]@{ RestartNeeded = $false } }
        $outcome = Get-TuneupOutcome -Output @(Restore-CapabilityTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Installed' }))
        $outcome.rebootRequired | Should -BeFalse
        Should -Invoke Add-TuneupWindowsCapability -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'App.StepsRecorder~~~~0.0.1.0' }
    }

    It 'does nothing on restore when the capability is already as it was' {
        Mock -ModuleName Tuneup Add-TuneupWindowsCapability { }
        Mock -ModuleName Tuneup Remove-TuneupWindowsCapability { }
        Restore-CapabilityTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Installed' })
        Should -Invoke Add-TuneupWindowsCapability -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Remove-TuneupWindowsCapability -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'does nothing on restore when the capability was not present' {
        Mock -ModuleName Tuneup Add-TuneupWindowsCapability { }
        Restore-CapabilityTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $false; state = $null })
        Should -Invoke Add-TuneupWindowsCapability -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Capability system calls' {
    BeforeEach {
        Clear-TuneupCapabilityCache
    }

    It 'lists the capabilities once and again after a change' {
        Mock -ModuleName Tuneup Get-WindowsCapability {
            [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0'; State = 'Installed' }
            [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0x'; State = 'NotPresent' }
        }
        Mock -ModuleName Tuneup Remove-WindowsCapability { }
        (Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0').State | Should -Be 'Installed'
        (Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0').State | Should -Be 'Installed'
        Should -Invoke Get-WindowsCapability -ModuleName Tuneup -Times 1 -Exactly
        Remove-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0'
        Get-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0' | Out-Null
        Should -Invoke Get-WindowsCapability -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'explains that adding a capability needs a source' {
        Mock -ModuleName Tuneup Add-WindowsCapability { throw 'The source files could not be found.' }
        { Add-TuneupWindowsCapability -Name 'App.StepsRecorder~~~~0.0.1.0' } |
            Should -Throw '*Windows Update or a features-on-demand source*source files could not be found*'
    }
}

Describe 'Capability definition and registration' {
    It 'accepts a valid capability tweak' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a name without the version part'; Set = @{ name = 'App.StepsRecorder'; state = 'NotPresent' }; Scope = 'machine'; Message = 'invalid capability name' }
        @{ Problem = 'a wildcard'; Set = @{ name = 'App.Steps*~~~~0.0.1.0'; state = 'NotPresent' }; Scope = 'machine'; Message = 'invalid capability name' }
        @{ Problem = 'an unknown state'; Set = @{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'Removed' }; Scope = 'machine'; Message = "invalid capability state 'Removed'" }
        @{ Problem = 'scope user'; Set = @{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' }; Scope = 'user'; Message = 'must use scope machine' }
    ) {
        param($Set, $Scope, $Message)
        $tweak = New-TestTweak -Type 'capability' -Scope $Scope -Set ([pscustomobject]$Set)
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'is a dispatched type that needs elevation to read' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Capability'
        (Get-TuneupHandler -Type 'capability').ReadNeedsAdmin | Should -BeTrue
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Capability.Tests.ps1`
Expected: FAIL, `ConvertTo-TuneupCapabilityState` no se reconoce como comando.

- [ ] **Step 3: Implementación**

`engine/handlers/Capability.ps1`:

```powershell
$script:CapabilityStates = @('Installed', 'NotPresent')
# Name~~~~Version, as Get-WindowsCapability lists it (for example App.StepsRecorder~~~~0.0.1.0).
$script:CapabilityNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]*~[A-Za-z0-9._~-]*$'
$script:CapabilityCache = $null

function ConvertTo-TuneupCapabilityState {
    param([AllowNull()][AllowEmptyString()][string]$State)
    # A pending change counts as done: Windows finishes it on the next restart.
    if (@('Installed', 'InstallPending', 'PartiallyInstalled') -contains $State) { return 'Installed' }
    'NotPresent'
}

function Clear-TuneupCapabilityCache {
    $script:CapabilityCache = $null
}

function Get-TuneupWindowsCapability {
    param([Parameter(Mandatory)][string]$Name)
    # One listing per process, filtered by exact name; every change clears it.
    if ($null -eq $script:CapabilityCache) { $script:CapabilityCache = @(Get-WindowsCapability -Online -ErrorAction Stop) }
    $script:CapabilityCache | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
}

function Add-TuneupWindowsCapability {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupCapabilityCache
    try {
        Add-WindowsCapability -Online -Name $Name -ErrorAction Stop
    } catch {
        throw "Adding capability $Name failed (it needs Windows Update or a features-on-demand source): $($_.Exception.Message)"
    }
}

function Remove-TuneupWindowsCapability {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupCapabilityCache
    Remove-WindowsCapability -Online -Name $Name -ErrorAction Stop
}

function Test-CapabilityTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:CapabilityNamePattern) { 'has an invalid capability name (expected Name~~~~Version)' }
    if ($script:CapabilityStates -cnotcontains $set.state) { "has an invalid capability state '$($set.state)'" }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}

function Get-CapabilityTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $capability = Get-TuneupWindowsCapability -Name ([string]$Tweak.set.name)
    if ($null -eq $capability) { return [pscustomobject]@{ present = $false; state = $null } }
    [pscustomobject]@{ present = $true; state = (ConvertTo-TuneupCapabilityState -State ([string]$capability.State)) }
}

function Test-CapabilityTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-CapabilityTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.state -eq $Tweak.set.state) { return 'applied' }
    'not-applied'
}

function Set-TuneupCapabilityState {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$State)
    if ($State -eq 'Installed') {
        $result = @(Add-TuneupWindowsCapability -Name $Name)
    } else {
        $result = @(Remove-TuneupWindowsCapability -Name $Name)
    }
    if (@($result | Where-Object { $_.RestartNeeded }).Count) { New-TuneupOutcome -RebootRequired }
}

function Set-CapabilityTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupCapabilityState -Name ([string]$Tweak.set.name) -State ([string]$Tweak.set.state)
}

function Restore-CapabilityTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    $current = Get-CapabilityTweakState -Tweak $Tweak
    if ($current.present -and $current.state -eq $State.state) { return }
    Set-TuneupCapabilityState -Name ([string]$Tweak.set.name) -State ([string]$State.state)
}
```

En `engine/Dispatch.ps1`, agregar a la tabla, después de `appx`:

```powershell
    capability = [pscustomobject]@{ Name = 'Capability'; ReadNeedsAdmin = $true }
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Capability.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Capability.ps1 engine/Dispatch.ps1 tests/Capability.Tests.ps1
git commit -m "feat: manejador de capacidades de Windows"
```

---

### Task 11: Manejador `feature`

**Files:**
- Create: `engine/handlers/Feature.ps1`
- Modify: `engine/Dispatch.ps1`
- Test: `tests/Feature.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Feature.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'apps.work-folders' -Type 'feature' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'WorkFolders-Client'; state = 'Disabled' })
}

Describe 'Feature handler' {
    BeforeEach {
        $script:Raw = 'Enabled'
        Mock -ModuleName Tuneup Get-TuneupWindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'WorkFolders-Client'; State = $script:Raw } }
    }

    It 'maps <Raw> to <Expected>' -TestCases @(
        @{ Raw = 'Enabled'; Expected = 'Enabled' }
        @{ Raw = 'EnablePending'; Expected = 'Enabled' }
        @{ Raw = 'Disabled'; Expected = 'Disabled' }
        @{ Raw = 'DisablePending'; Expected = 'Disabled' }
        @{ Raw = 'DisabledWithPayloadRemoved'; Expected = 'Disabled' }
    ) {
        param($Raw, $Expected)
        ConvertTo-TuneupFeatureState -State $Raw | Should -Be $Expected
    }

    It 'is not applied while the feature is enabled' {
        (Get-FeatureTweakState -Tweak $Tweak).state | Should -Be 'Enabled'
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'counts a feature without its files as disabled' {
        $script:Raw = 'DisabledWithPayloadRemoved'
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a feature that this Windows does not list as not-present' {
        Mock -ModuleName Tuneup Get-TuneupWindowsOptionalFeature { }
        Test-FeatureTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'disables the feature and passes on a restart request' {
        Mock -ModuleName Tuneup Disable-TuneupWindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $true } }
        $outcome = Get-TuneupOutcome -Output @(Set-FeatureTweakDesired -Tweak $Tweak)
        $outcome.rebootRequired | Should -BeTrue
        Should -Invoke Disable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'WorkFolders-Client' }
    }

    It 'enables the feature again on restore' {
        $script:Raw = 'Disabled'
        Mock -ModuleName Tuneup Enable-TuneupWindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $true } }
        $outcome = Get-TuneupOutcome -Output @(Restore-FeatureTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Enabled' }))
        $outcome.rebootRequired | Should -BeTrue
        Should -Invoke Enable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'WorkFolders-Client' }
    }

    It 'does nothing on restore when the feature is already as it was' {
        Mock -ModuleName Tuneup Enable-TuneupWindowsOptionalFeature { }
        Mock -ModuleName Tuneup Disable-TuneupWindowsOptionalFeature { }
        Restore-FeatureTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; state = 'Enabled' })
        Should -Invoke Enable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Disable-TuneupWindowsOptionalFeature -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Feature system calls' {
    BeforeEach {
        Clear-TuneupFeatureCache
    }

    It 'lists the features once and again after a change, without -All or -Remove' {
        Mock -ModuleName Tuneup Get-WindowsOptionalFeature {
            [pscustomobject]@{ FeatureName = 'WorkFolders-Client'; State = 'Enabled' }
            [pscustomobject]@{ FeatureName = 'TFTP'; State = 'Disabled' }
        }
        Mock -ModuleName Tuneup Disable-WindowsOptionalFeature { }
        (Get-TuneupWindowsOptionalFeature -Name 'TFTP').State | Should -Be 'Disabled'
        (Get-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client').State | Should -Be 'Enabled'
        Should -Invoke Get-WindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly
        Disable-TuneupWindowsOptionalFeature -Name 'WorkFolders-Client'
        Should -Invoke Disable-WindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FeatureName -eq 'WorkFolders-Client' -and $NoRestart -and -not $Remove
        }
        Get-TuneupWindowsOptionalFeature -Name 'TFTP' | Out-Null
        Should -Invoke Get-WindowsOptionalFeature -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'explains that enabling a feature may need a source' {
        Mock -ModuleName Tuneup Enable-WindowsOptionalFeature { throw 'The source files could not be found.' }
        { Enable-TuneupWindowsOptionalFeature -Name 'NetFx3' } | Should -Throw '*installation source*source files could not be found*'
        Should -Invoke Enable-WindowsOptionalFeature -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $NoRestart -and -not $All }
    }
}

Describe 'Feature definition and registration' {
    It 'accepts a valid feature tweak' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a wildcard'; Set = @{ name = 'WorkFolders*'; state = 'Disabled' }; Scope = 'machine'; Message = 'invalid feature name' }
        @{ Problem = 'an unknown state'; Set = @{ name = 'WorkFolders-Client'; state = 'Off' }; Scope = 'machine'; Message = "invalid feature state 'Off'" }
        @{ Problem = 'scope user'; Set = @{ name = 'WorkFolders-Client'; state = 'Disabled' }; Scope = 'user'; Message = 'must use scope machine' }
    ) {
        param($Set, $Scope, $Message)
        $tweak = New-TestTweak -Type 'feature' -Scope $Scope -Set ([pscustomobject]$Set)
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'is a dispatched type that needs elevation to read' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Feature'
        (Get-TuneupHandler -Type 'feature').ReadNeedsAdmin | Should -BeTrue
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Feature.Tests.ps1`
Expected: FAIL, `ConvertTo-TuneupFeatureState` no se reconoce como comando.

- [ ] **Step 3: Implementación**

`engine/handlers/Feature.ps1`:

```powershell
$script:FeatureStates = @('Enabled', 'Disabled')
$script:FeatureNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]*$'
$script:FeatureCache = $null

function ConvertTo-TuneupFeatureState {
    param([AllowNull()][AllowEmptyString()][string]$State)
    # A pending change counts as done; a feature whose files were removed is still disabled.
    if (@('Enabled', 'EnablePending', 'PartiallyInstalled') -contains $State) { return 'Enabled' }
    'Disabled'
}

function Clear-TuneupFeatureCache {
    $script:FeatureCache = $null
}

function Get-TuneupWindowsOptionalFeature {
    param([Parameter(Mandatory)][string]$Name)
    # One listing per process, filtered by exact name; every change clears it.
    if ($null -eq $script:FeatureCache) { $script:FeatureCache = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop) }
    $script:FeatureCache | Where-Object { $_.FeatureName -eq $Name } | Select-Object -First 1
}

function Enable-TuneupWindowsOptionalFeature {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupFeatureCache
    try {
        # No -All: parent features are left as they are, so the undo stays exact.
        Enable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
    } catch {
        throw "Enabling feature $Name failed (it may need Windows Update or an installation source): $($_.Exception.Message)"
    }
}

function Disable-TuneupWindowsOptionalFeature {
    param([Parameter(Mandatory)][string]$Name)
    Clear-TuneupFeatureCache
    # No -Remove: the files stay, so enabling it again needs no source.
    Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
}

function Test-FeatureTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:FeatureNamePattern) { 'has an invalid feature name' }
    if ($script:FeatureStates -cnotcontains $set.state) { "has an invalid feature state '$($set.state)'" }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}

function Get-FeatureTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $feature = Get-TuneupWindowsOptionalFeature -Name ([string]$Tweak.set.name)
    if ($null -eq $feature) { return [pscustomobject]@{ present = $false; state = $null } }
    [pscustomobject]@{ present = $true; state = (ConvertTo-TuneupFeatureState -State ([string]$feature.State)) }
}

function Test-FeatureTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-FeatureTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.state -eq $Tweak.set.state) { return 'applied' }
    'not-applied'
}

function Set-TuneupFeatureState {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$State)
    if ($State -eq 'Enabled') {
        $result = @(Enable-TuneupWindowsOptionalFeature -Name $Name)
    } else {
        $result = @(Disable-TuneupWindowsOptionalFeature -Name $Name)
    }
    if (@($result | Where-Object { $_.RestartNeeded }).Count) { New-TuneupOutcome -RebootRequired }
}

function Set-FeatureTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupFeatureState -Name ([string]$Tweak.set.name) -State ([string]$Tweak.set.state)
}

function Restore-FeatureTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    $current = Get-FeatureTweakState -Tweak $Tweak
    if ($current.present -and $current.state -eq $State.state) { return }
    Set-TuneupFeatureState -Name ([string]$Tweak.set.name) -State ([string]$State.state)
}
```

En `engine/Dispatch.ps1`, agregar a la tabla, después de `capability`:

```powershell
    feature    = [pscustomobject]@{ Name = 'Feature'; ReadNeedsAdmin = $true }
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Feature.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Feature.ps1 engine/Dispatch.ps1 tests/Feature.Tests.ps1
git commit -m "feat: manejador de características opcionales de Windows"
```

---

### Task 12: `powercfg`: salida sin idioma y plan de energía activo

**Files:**
- Create: `engine/handlers/Powercfg.ps1`
- Test: `tests/Powercfg.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Powercfg.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $script:High = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $script:SchemeTweak = New-TestTweak -Id 'power.high-performance' -Type 'powercfg' -Scope 'machine' `
        -Set ([pscustomobject]@{ kind = 'scheme'; scheme = '8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C' })
    # The words follow the Windows language (this is the Spanish output); only the GUIDs are read.
    $script:ActiveBalanced = 'GUID de plan de energ' + [char]0x00ED + 'a: 381b4222-f694-41f0-9685-ff5bb260df2e  (Equilibrado)'
    $script:ActiveHigh = 'Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)'
    $script:BothSchemes = "Existing Power Schemes (* Active)`r`n-----------------------------------`r`nPower Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *`r`nPower Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)"
}

Describe 'powercfg output' {
    It 'reads the GUIDs in lowercase whatever the language' {
        @(Get-TuneupGuidList -Text $ActiveBalanced) -join ',' | Should -Be $Balanced
        @(Get-TuneupGuidList -Text $BothSchemes) -join ',' | Should -Be "$Balanced,$High"
        @(Get-TuneupGuidList -Text 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE') -join '' | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        @(Get-TuneupGuidList -Text '').Count | Should -Be 0
    }

    It 'throws with the exit code when powercfg fails' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 1; Output = 'Invalid Parameters -- try "/?" for help' } }
        { Invoke-TuneupPowercfg -Arguments @('/setactive', $High) } | Should -Throw "*powercfg /setactive $High failed with exit code 1*"
    }

    It 'returns the output when powercfg succeeds' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)' } }
        Get-TuneupActivePowerScheme | Should -Be $Balanced
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\System32\powercfg.exe' -and ($Arguments -join ' ') -eq '/getactivescheme'
        }
    }
}

Describe 'Power scheme' {
    BeforeEach {
        $script:ActiveText = $ActiveBalanced
        $script:ListText = $BothSchemes
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ActiveText } -ParameterFilter { $Arguments[0] -eq '/getactivescheme' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ListText } -ParameterFilter { $Arguments[0] -eq '/list' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { '' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
    }

    It 'reads the active scheme and whether the wanted one exists' {
        $state = Get-TuneupPowerSchemeState -Tweak $SchemeTweak
        $state.kind | Should -Be 'scheme'
        $state.active | Should -Be $Balanced
        $state.exists | Should -BeTrue
        Test-TuneupPowerSchemeState -Tweak $SchemeTweak | Should -Be 'not-applied'
    }

    It 'is applied when the wanted scheme is active' {
        $script:ActiveText = $ActiveHigh
        Test-TuneupPowerSchemeState -Tweak $SchemeTweak | Should -Be 'applied'
    }

    It 'is not-present when the wanted scheme does not exist' {
        $script:ListText = 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *'
        Test-TuneupPowerSchemeState -Tweak $SchemeTweak | Should -Be 'not-present'
    }

    It 'activates a scheme by GUID' {
        Set-TuneupActivePowerScheme -Guid $High
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $High" }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Powercfg.Tests.ps1`
Expected: FAIL, `Get-TuneupGuidList` no se reconoce como comando.

- [ ] **Step 3: Implementación**

`engine/handlers/Powercfg.ps1`:

```powershell
$script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$script:GuidSearch = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Invoke-TuneupPowercfg {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-TuneupNative -FilePath (Join-Path $env:SystemRoot 'System32\powercfg.exe') -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw "powercfg $($Arguments -join ' ') failed with exit code $($result.ExitCode): $($result.Output)"
    }
    $result.Output
}

function Get-TuneupGuidList {
    param([AllowEmptyString()][string]$Text)
    # Only the GUIDs are read: the words around them depend on the Windows language.
    foreach ($match in [regex]::Matches([string]$Text, $script:GuidSearch)) { $match.Value.ToLowerInvariant() }
}

function Get-TuneupActivePowerScheme {
    $guids = @(Get-TuneupGuidList -Text (Invoke-TuneupPowercfg -Arguments @('/getactivescheme')))
    if (-not $guids.Count) { throw 'powercfg /getactivescheme did not return a scheme GUID' }
    $guids[0]
}

function Get-TuneupPowerSchemeList {
    Get-TuneupGuidList -Text (Invoke-TuneupPowercfg -Arguments @('/list'))
}

function Set-TuneupActivePowerScheme {
    param([Parameter(Mandatory)][string]$Guid)
    Invoke-TuneupPowercfg -Arguments @('/setactive', $Guid) | Out-Null
}

function Get-TuneupPowerSchemeState {
    param([Parameter(Mandatory)]$Tweak)
    $wanted = ([string]$Tweak.set.scheme).ToLowerInvariant()
    [pscustomobject]@{
        kind   = 'scheme'
        active = Get-TuneupActivePowerScheme
        exists = (@(Get-TuneupPowerSchemeList) -contains $wanted)
    }
}

function Test-TuneupPowerSchemeState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-TuneupPowerSchemeState -Tweak $Tweak
    if (-not $state.exists) { return 'not-present' }
    if ($state.active -eq ([string]$Tweak.set.scheme).ToLowerInvariant()) { return 'applied' }
    'not-applied'
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Powercfg.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Powercfg.ps1 tests/Powercfg.Tests.ps1
git commit -m "feat: powercfg lee el plan activo sin depender del idioma"
```

---

### Task 13: `powercfg`: valores de configuración y registro del manejador

**Files:**
- Modify: `engine/handlers/Powercfg.ps1`, `engine/Dispatch.ps1`
- Test: `tests/Powercfg.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Powercfg.Tests.ps1`:

```powershell
Describe 'Power setting' {
    BeforeAll {
        $script:Sleep = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        $script:StandbyIdle = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
        $script:Definition = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\$Sleep\$StandbyIdle"
        $script:UserValues = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$Balanced\$Sleep\$StandbyIdle"
        $script:Defaults = "$Definition\DefaultPowerSchemeValues\$Balanced"
        $script:SettingTweak = New-TestTweak -Id 'power.sleep-after' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = 0; dc = 900 })
    }

    BeforeEach {
        $script:Keys = @{}
        $script:Keys[$Definition] = [pscustomobject]@{}
        $script:Keys[$Defaults] = [pscustomobject]@{ ACSettingIndex = 1800; DCSettingIndex = 900 }
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 0 }
        $script:FailDc = $false
        $script:ActiveText = $ActiveBalanced
        Mock -ModuleName Tuneup Test-Path { $script:Keys.ContainsKey($LiteralPath) } -ParameterFilter { $LiteralPath -like 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\*' }
        Mock -ModuleName Tuneup Get-ItemProperty { $script:Keys[$LiteralPath] } -ParameterFilter { $LiteralPath -like 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\*' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { $script:ActiveText } -ParameterFilter { $Arguments[0] -eq '/getactivescheme' }
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg {
            if ($script:FailDc -and $Arguments[0] -eq '/setdcvalueindex') { throw 'powercfg /setdcvalueindex failed with exit code 1: Invalid Parameters' }
            ''
        } -ParameterFilter { $Arguments[0] -like '/set*' }
    }

    It 'reads the value of the scheme and falls back to its default for each power source' {
        $state = Get-PowercfgTweakState -Tweak $SettingTweak
        $state.kind | Should -Be 'setting'
        $state.scheme | Should -Be $Balanced
        $state.present | Should -BeTrue
        $state.ac | Should -Be 0
        $state.dc | Should -Be 900
        Test-PowercfgTweakState -Tweak $SettingTweak | Should -Be 'applied'
    }

    It 'is not applied when a value differs' {
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 0; DCSettingIndex = 1800 }
        Test-PowercfgTweakState -Tweak $SettingTweak | Should -Be 'not-applied'
    }

    It 'reads a DWORD above 2147483647 as unsigned' {
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = -1; DCSettingIndex = 0 }
        (Get-PowercfgTweakState -Tweak $SettingTweak).ac | Should -Be 4294967295
    }

    It 'is not-present when Windows does not define the setting' {
        $script:Keys.Remove($Definition)
        Test-PowercfgTweakState -Tweak $SettingTweak | Should -Be 'not-present'
    }

    It 'throws when neither the scheme nor its default has a value' {
        $script:Keys.Remove($Defaults)
        $script:Keys.Remove($UserValues)
        { Get-PowercfgTweakState -Tweak $SettingTweak } | Should -Throw '*Cannot read ACSettingIndex*'
    }

    It 'writes both values and activates the scheme again when it is the active one' {
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $SettingTweak)
        $outcome.partial | Should -BeFalse
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 0" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setdcvalueindex $Balanced $Sleep $StandbyIdle 900" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $Balanced" }
    }

    It 'does not activate a scheme that is not the active one' {
        $script:ActiveText = $ActiveHigh
        $tweak = New-TestTweak -Id 'power.balanced-sleep' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = $Balanced; subgroup = $Sleep; setting = $StandbyIdle; ac = 0; dc = 900 })
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setactive' }
    }

    It 'reports a partial change when the DC value fails after the AC value was written' {
        $script:FailDc = $true
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $SettingTweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*AC power was changed*setdcvalueindex*'
    }

    It 'restores the saved values to the saved scheme even after another one was activated' {
        $script:ActiveText = $ActiveHigh
        $state = [pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 1800; dc = 900 }
        Restore-PowercfgTweakState -Tweak $SettingTweak -State $state
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 1800" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setdcvalueindex $Balanced $Sleep $StandbyIdle 900" }
    }

    It 'throws instead of a partial result when a restore fails half way' {
        $script:FailDc = $true
        $state = [pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 1800; dc = 900 }
        { Restore-PowercfgTweakState -Tweak $SettingTweak -State $state } | Should -Throw '*AC power was changed*'
    }

    It 'restores the scheme that was active' {
        Restore-PowercfgTweakState -Tweak $SchemeTweak -State ([pscustomobject]@{ kind = 'scheme'; active = $Balanced; exists = $true })
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $Balanced" }
    }
}

Describe 'Powercfg definition and registration' {
    It 'accepts a valid <Kind> tweak' -TestCases @(
        @{ Kind = 'scheme'; Set = @{ kind = 'scheme'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' } }
        @{ Kind = 'setting'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = 4294967295 } }
    ) {
        param($Set)
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]$Set))) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'an unknown kind'; Set = @{ kind = 'plan'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }; Message = "invalid powercfg kind 'plan'" }
        @{ Problem = 'an alias as scheme to activate'; Set = @{ kind = 'scheme'; scheme = 'SCHEME_MIN' }; Message = 'GUID of the power scheme' }
        @{ Problem = 'a subgroup alias'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = 'SUB_SLEEP'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = 0 }; Message = 'set.subgroup must be a GUID' }
        @{ Problem = 'a value out of range'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 4294967296; dc = 0 }; Message = 'set.ac must be an integer' }
        @{ Problem = 'a value that is text'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0; dc = '900' }; Message = 'set.dc must be an integer' }
    ) {
        param($Set, $Message)
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]$Set))) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'requires scope machine' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'powercfg' -Scope 'user' -Set $SchemeTweak.set)) -join '; ' | Should -Match 'must use scope machine'
    }

    It 'is a dispatched type that reads without elevation' {
        Get-TuneupHandlerName -Tweak $SchemeTweak | Should -Be 'Powercfg'
        (Get-TuneupHandler -Type 'powercfg').ReadNeedsAdmin | Should -BeFalse
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Powercfg.Tests.ps1`
Expected: FAIL, `Get-PowercfgTweakState` no se reconoce como comando; `Unsupported tweak type 'powercfg'`.

- [ ] **Step 3: Implementación**

Agregar al final de `engine/handlers/Powercfg.ps1`:

```powershell
$script:PowerKeyRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'

function ConvertTo-TuneupUInt32 {
    param([Parameter(Mandatory)]$Value)
    # Get-ItemProperty returns REG_DWORD values above 2147483647 as negative numbers.
    $number = [long]$Value
    if ($number -lt 0) { $number += 4294967296 }
    $number
}

function Resolve-TuneupPowerScheme {
    param([Parameter(Mandatory)][string]$Scheme)
    # The journal keeps the GUID, so an undo goes back to the same scheme even if another is active then.
    if ($Scheme -ceq 'SCHEME_CURRENT') { return (Get-TuneupActivePowerScheme) }
    $Scheme.ToLowerInvariant()
}

function Get-TuneupPowerSettingIndex {
    param(
        [Parameter(Mandatory)][string]$Scheme,
        [Parameter(Mandatory)][string]$Subgroup,
        [Parameter(Mandatory)][string]$Setting
    )
    $definition = "$script:PowerKeyRoot\PowerSettings\$Subgroup\$Setting"
    if (-not (Test-Path -LiteralPath $definition)) { return [pscustomobject]@{ present = $false; ac = $null; dc = $null } }
    # A value changed for this scheme lives under User\PowerSchemes; otherwise Windows uses the
    # scheme default kept with the setting definition. powercfg /q hides settings marked hidden.
    $sources = @("$script:PowerKeyRoot\User\PowerSchemes\$Scheme\$Subgroup\$Setting", "$definition\DefaultPowerSchemeValues\$Scheme")
    $values = @{}
    foreach ($name in 'ACSettingIndex', 'DCSettingIndex') {
        foreach ($source in $sources) {
            $properties = Get-ItemProperty -LiteralPath $source -ErrorAction SilentlyContinue
            if ($null -ne $properties -and $null -ne $properties.$name) {
                $values[$name] = ConvertTo-TuneupUInt32 -Value $properties.$name
                break
            }
        }
        if (-not $values.ContainsKey($name)) { throw "Cannot read $name of power setting $Subgroup\$Setting in scheme $Scheme" }
    }
    [pscustomobject]@{ present = $true; ac = $values['ACSettingIndex']; dc = $values['DCSettingIndex'] }
}

function Get-TuneupPowerSettingState {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    $scheme = Resolve-TuneupPowerScheme -Scheme ([string]$set.scheme)
    $index = Get-TuneupPowerSettingIndex -Scheme $scheme -Subgroup ([string]$set.subgroup).ToLowerInvariant() -Setting ([string]$set.setting).ToLowerInvariant()
    [pscustomobject]@{ kind = 'setting'; scheme = $scheme; present = $index.present; ac = $index.ac; dc = $index.dc }
}

function Set-TuneupPowerSettingIndex {
    param(
        [Parameter(Mandatory)][string]$Scheme,
        [Parameter(Mandatory)][string]$Subgroup,
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)][long]$Ac,
        [Parameter(Mandatory)][long]$Dc,
        [switch]$ReportPartial
    )
    Invoke-TuneupPowercfg -Arguments @('/setacvalueindex', $Scheme, $Subgroup, $Setting, [string]$Ac) | Out-Null
    try {
        Invoke-TuneupPowercfg -Arguments @('/setdcvalueindex', $Scheme, $Subgroup, $Setting, [string]$Dc) | Out-Null
        # A change to the active scheme takes effect once it is activated again.
        if ($Scheme -eq (Get-TuneupActivePowerScheme)) { Invoke-TuneupPowercfg -Arguments @('/setactive', $Scheme) | Out-Null }
    } catch {
        $message = "The value on AC power was changed, but not the rest: $($_.Exception.Message)"
        if ($ReportPartial) { return (New-TuneupOutcome -Partial -Detail $message) }
        throw $message
    }
}

function Test-PowercfgTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
    switch -CaseSensitive ([string]$set.kind) {
        'scheme' {
            if ([string]$set.scheme -notmatch $script:GuidPattern) { 'needs the GUID of the power scheme in set.scheme' }
        }
        'setting' {
            if ([string]$set.scheme -cne 'SCHEME_CURRENT' -and [string]$set.scheme -notmatch $script:GuidPattern) { 'set.scheme must be SCHEME_CURRENT or a scheme GUID' }
            foreach ($field in 'subgroup', 'setting') {
                if ([string]$set.$field -notmatch $script:GuidPattern) { "set.$field must be a GUID" }
            }
            foreach ($field in 'ac', 'dc') {
                if (-not (Test-TuneupIntegerInRange -Value $set.$field -Min 0 -Max 4294967295)) { "set.$field must be an integer from 0 to 4294967295" }
            }
        }
        default { "has an invalid powercfg kind '$($set.kind)'" }
    }
}

function Get-PowercfgTweakState {
    param([Parameter(Mandatory)]$Tweak)
    if ($Tweak.set.kind -eq 'scheme') { return (Get-TuneupPowerSchemeState -Tweak $Tweak) }
    Get-TuneupPowerSettingState -Tweak $Tweak
}

function Test-PowercfgTweakState {
    param([Parameter(Mandatory)]$Tweak)
    if ($Tweak.set.kind -eq 'scheme') { return (Test-TuneupPowerSchemeState -Tweak $Tweak) }
    $state = Get-TuneupPowerSettingState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ([long]$state.ac -eq [long]$Tweak.set.ac -and [long]$state.dc -eq [long]$Tweak.set.dc) { return 'applied' }
    'not-applied'
}

function Set-PowercfgTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ($set.kind -eq 'scheme') {
        Set-TuneupActivePowerScheme -Guid ([string]$set.scheme).ToLowerInvariant()
        return
    }
    $scheme = Resolve-TuneupPowerScheme -Scheme ([string]$set.scheme)
    Set-TuneupPowerSettingIndex -Scheme $scheme -Subgroup ([string]$set.subgroup).ToLowerInvariant() `
        -Setting ([string]$set.setting).ToLowerInvariant() -Ac ([long]$set.ac) -Dc ([long]$set.dc) -ReportPartial
}

function Restore-PowercfgTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if ($Tweak.set.kind -eq 'scheme') {
        if ($State.active) { Set-TuneupActivePowerScheme -Guid ([string]$State.active) }
        return
    }
    if (-not $State.present) { return }
    Set-TuneupPowerSettingIndex -Scheme ([string]$State.scheme) -Subgroup ([string]$Tweak.set.subgroup).ToLowerInvariant() `
        -Setting ([string]$Tweak.set.setting).ToLowerInvariant() -Ac ([long]$State.ac) -Dc ([long]$State.dc)
}
```

En `engine/Dispatch.ps1`, agregar a la tabla, después de `feature`:

```powershell
    powercfg   = [pscustomobject]@{ Name = 'Powercfg'; ReadNeedsAdmin = $false }
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Powercfg.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Powercfg.ps1 engine/Dispatch.ps1 tests/Powercfg.Tests.ps1
git commit -m "feat: manejador powercfg para planes y valores de energía"
```

---

### Task 14: Acciones: biblioteca que no ejecuta código y manejador `action`

**Files:**
- Create: `engine/handlers/Action.ps1`, `tests/fixtures/actions/fixture-toggle.ps1`
- Modify: `engine/Tuneup.psm1`, `engine/Dispatch.ps1`
- Test: `tests/Action.Tests.ps1`, `tests/StateFiles.Tests.ps1`

- [ ] **Step 1: Acción de prueba**

`tests/fixtures/actions/fixture-toggle.ps1` (toca solo `HKCU:\Software\windows-tuneup-test`):

```powershell
function Get-FixtureToggleActionState {
    param([Parameter(Mandatory)]$Tweak)
    $key = 'HKCU:\Software\windows-tuneup-test'
    $value = $null
    if (Test-Path -LiteralPath $key) { $value = (Get-ItemProperty -LiteralPath $key).Action }
    [pscustomobject]@{ value = $value }
}

function Test-FixtureToggleActionState {
    param([Parameter(Mandatory)]$Tweak)
    if ((Get-FixtureToggleActionState -Tweak $Tweak).value -eq 1) { 'applied' } else { 'not-applied' }
}

function Set-FixtureToggleActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    Write-TuneupRegistryValue -Path 'HKCU:\Software\windows-tuneup-test' -Name 'Action' -Kind 'DWord' -Value 1
    New-TuneupOutcome -RebootRequired
}

function Restore-FixtureToggleActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if ($null -eq $State.value) {
        Remove-TuneupRegistryValue -Path 'HKCU:\Software\windows-tuneup-test' -Name 'Action'
        return
    }
    Write-TuneupRegistryValue -Path 'HKCU:\Software\windows-tuneup-test' -Name 'Action' -Kind 'DWord' -Value $State.value
}
```

- [ ] **Step 2: Prueba que falla**

`tests/Action.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    Import-TuneupActionLibrary -Path (Join-Path $PSScriptRoot 'fixtures\actions')
    $script:Tweak = New-TestTweak -Id 'test.action' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'fixture-toggle' })
    function New-ActionFolder([hashtable]$Files) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($name in $Files.Keys) { [System.IO.File]::WriteAllText((Join-Path $dir $name), $Files[$name]) }
        $dir
    }
    $script:Contract = @'
function Get-BadOneActionState { param($Tweak) $null }
function Test-BadOneActionState { param($Tweak) 'applied' }
function Set-BadOneActionDesired { param($Tweak) }
function Restore-BadOneActionState { param($Tweak, $State) }
'@
}

Describe 'Action library' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'turns kebab-case names into Pascal names' {
        ConvertTo-TuneupPascalName -Name 'fixture-toggle' | Should -Be 'FixtureToggle'
        ConvertTo-TuneupPascalName -Name 'win11-start' | Should -Be 'Win11Start'
        Get-TuneupActionFunctionName -Name 'fixture-toggle' -Verb 'Set' | Should -Be 'Set-FixtureToggleActionDesired'
    }

    It 'rejects a name that is not lowercase kebab case' {
        { ConvertTo-TuneupPascalName -Name 'Bad_Name' } | Should -Throw "*Invalid action script name 'Bad_Name'*"
    }

    It 'runs the loaded action through the dispatcher and undoes it' {
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        (Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)).rebootRequired | Should -BeTrue
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $Tweak -State $state
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'never runs code while loading a script' {
        $marker = Join-Path $TestDrive 'ran.txt'
        $dir = New-ActionFolder @{ 'bad-one.ps1' = ($Contract + "`r`n[System.IO.File]::WriteAllText('$marker', 'x')") }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*bad-one.ps1 may only define functions*'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'refuses a function outside the name space of its script' {
        $dir = New-ActionFolder @{ 'bad-one.ps1' = ($Contract + "`r`nfunction Test-TuneupTrustedItem { param(`$Path) `$true }") }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*defines Test-TuneupTrustedItem*'
        (& (Get-Module Tuneup) { Test-TuneupTrustedItem -Path 'C:\no\such\path' }) | Should -BeFalse
    }

    It 'refuses names reserved for the engine' {
        $dir = New-ActionFolder @{ 'tuneup.ps1' = 'function Get-TuneupActionCommand { param($Tweak) }' }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*reserved for the engine*'
    }

    It 'refuses a script without the four contract functions' {
        $dir = New-ActionFolder @{ 'bad-one.ps1' = 'function Get-BadOneActionState { param($Tweak) $null }' }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*does not define Test-BadOneActionState*'
    }

    It 'refuses a file name that is not kebab case' {
        $dir = New-ActionFolder @{ 'Bad_One.ps1' = $Contract }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw "*Invalid action script name 'Bad_One'*"
    }

    It 'refuses parameters declared outside a param block' {
        $inline = @'
function Get-BadOneActionState($Tweak) { $null }
function Test-BadOneActionState { param($Tweak) 'applied' }
function Set-BadOneActionDesired { param($Tweak) }
function Restore-BadOneActionState { param($Tweak, $State) }
'@
        $dir = New-ActionFolder @{ 'bad-one.ps1' = $inline }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*param() block*'
    }

    It 'ignores a folder that does not exist' {
        { Import-TuneupActionLibrary -Path (Join-Path $TestDrive 'none') } | Should -Not -Throw
    }

    It 'says when an action is not loaded' {
        $other = New-TestTweak -Id 'test.other' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'not-loaded' })
        { Get-TuneupState -Tweak $other } | Should -Throw "*Action script 'not-loaded' is not loaded*"
    }

    It 'rejects a test function that answers something else' {
        $odd = @'
function Get-OddTestActionState { param($Tweak) $null }
function Test-OddTestActionState { param($Tweak) 'yes' }
function Set-OddTestActionDesired { param($Tweak) }
function Restore-OddTestActionState { param($Tweak, $State) }
'@
        Import-TuneupActionLibrary -Path (New-ActionFolder @{ 'odd-test.ps1' = $odd })
        $tweak = New-TestTweak -Id 'test.odd' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'odd-test' })
        { Test-TuneupState -Tweak $tweak } | Should -Throw "*returned 'yes'*"
    }
}

Describe 'Action definition and registration' {
    It 'accepts a loaded script' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a script that is not loaded'; Script = 'missing-one'; Scope = 'machine'; Message = "action script 'missing-one', which is not in the actions folder" }
        @{ Problem = 'a path as script name'; Script = '..\evil'; Scope = 'machine'; Message = 'invalid action script name' }
        @{ Problem = 'scope user'; Script = 'fixture-toggle'; Scope = 'user'; Message = 'must use scope machine' }
    ) {
        param($Script, $Scope, $Message)
        $tweak = New-TestTweak -Type 'action' -Scope $Scope -Set ([pscustomobject]@{ script = $Script })
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'is a dispatched type that reads without elevation' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Action'
        (Get-TuneupHandler -Type 'action').ReadNeedsAdmin | Should -BeFalse
    }
}
```

En `tests/StateFiles.Tests.ps1`, agregar estos casos al final de la lista `-TestCases` de `It 'refuses to journal a <Name> in the user folder'` (antes del paréntesis que la cierra):

```powershell
        @{ Name = 'user appx tweak'; Scope = 'user'; Type = 'appx'; Set = @{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' } }
        @{ Name = 'user capability tweak'; Scope = 'user'; Type = 'capability'; Set = @{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' } }
        @{ Name = 'user feature tweak'; Scope = 'user'; Type = 'feature'; Set = @{ name = 'TelnetClient'; state = 'Disabled' } }
        @{ Name = 'user powercfg tweak'; Scope = 'user'; Type = 'powercfg'; Set = @{ kind = 'scheme'; scheme = '381b4222-f694-41f0-9685-ff5bb260df2e' } }
        @{ Name = 'user action tweak with an HKCU path'; Scope = 'user'; Type = 'action'; Set = @{ script = 'fixture-toggle'; path = 'HKCU:\Software\x' } }
```

Estos casos ya pasan (la carpeta de usuario solo acepta registro `HKCU`): documentan la regla 8 de la adenda para los tipos nuevos.

- [ ] **Step 3: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Action.Tests.ps1`
Expected: FAIL, `Import-TuneupActionLibrary` no se reconoce como comando.

- [ ] **Step 4: Implementación**

`engine/handlers/Action.ps1`:

```powershell
$script:ActionNamePattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
# Loaded action scripts: name -> file.
$script:TuneupActionScripts = @{}

function ConvertTo-TuneupPascalName {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -cnotmatch $script:ActionNamePattern) { throw "Invalid action script name '$Name': use lowercase words separated by hyphens" }
    (($Name -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
}

function Get-TuneupActionFunctionName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Get', 'Test', 'Set', 'Restore')][string]$Verb
    )
    $suffix = $(if ($Verb -eq 'Set') { 'Desired' } else { 'State' })
    "$Verb-$(ConvertTo-TuneupPascalName -Name $Name)Action$suffix"
}

function Import-TuneupActionLibrary {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File | Sort-Object Name) {
        $name = $file.BaseName
        $pascal = ConvertTo-TuneupPascalName -Name $name
        if ($pascal -clike 'Tuneup*') { throw "Action script $($file.Name): names starting with tuneup are reserved for the engine" }
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "Action script $($file.Name) has a syntax error: $($parseErrors[0].Message)" }
        # The file is never run: only its function definitions are taken, so loading it cannot
        # execute code, and the name check keeps it from replacing functions of the engine.
        $onlyFunctions = ($null -eq $ast.ParamBlock -and $null -eq $ast.BeginBlock -and $null -eq $ast.ProcessBlock -and
            $null -eq $ast.DynamicParamBlock -and -not @($ast.UsingStatements).Count)
        $definitions = New-Object System.Collections.Generic.List[object]
        if ($null -ne $ast.EndBlock) {
            foreach ($statement in $ast.EndBlock.Statements) {
                if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $onlyFunctions = $false; break }
                $definitions.Add($statement)
            }
        }
        if (-not $onlyFunctions) { throw "Action script $($file.Name) may only define functions" }
        foreach ($definition in $definitions) {
            if ($definition.Name -cnotmatch "^[A-Z][a-z]+-$($pascal)Action[A-Za-z0-9]*$") {
                throw "Action script $($file.Name) defines $($definition.Name); its functions must be named <Verb>-$($pascal)Action..."
            }
            if ($definition.IsFilter -or $definition.IsWorkflow) {
                throw "Action script $($file.Name) must define $($definition.Name) as a plain function"
            }
            if ($null -ne $definition.Parameters) {
                throw "Action script $($file.Name) must declare the parameters of $($definition.Name) in a param() block"
            }
        }
        $defined = @($definitions | ForEach-Object { $_.Name })
        foreach ($verb in 'Get', 'Test', 'Set', 'Restore') {
            $required = Get-TuneupActionFunctionName -Name $name -Verb $verb
            if ($defined -cnotcontains $required) { throw "Action script $($file.Name) does not define $required" }
        }
        foreach ($definition in $definitions) {
            Set-Item -LiteralPath "Function:script:$($definition.Name)" -Value $definition.Body.GetScriptBlock()
        }
        $script:TuneupActionScripts[$name] = $file.FullName
    }
}

function Get-TuneupActionCommand {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][string]$Verb)
    $name = [string]$Tweak.set.script
    if ($name -cnotmatch $script:ActionNamePattern -or -not $script:TuneupActionScripts.ContainsKey($name)) {
        throw "Action script '$name' is not loaded"
    }
    Get-TuneupActionFunctionName -Name $name -Verb $Verb
}

function Test-ActionTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.script
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
    if ($name -cnotmatch $script:ActionNamePattern) { "has an invalid action script name '$name'" }
    elseif (-not $script:TuneupActionScripts.ContainsKey($name)) { "uses action script '$name', which is not in the actions folder" }
}

function Get-ActionTweakState {
    param([Parameter(Mandatory)]$Tweak)
    & (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Get') -Tweak $Tweak
}

function Test-ActionTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $result = @(& (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Test') -Tweak $Tweak)
    if ($result.Count -ne 1 -or @('applied', 'not-applied', 'not-present') -cnotcontains [string]$result[0]) {
        throw "Action script '$($Tweak.set.script)' returned '$($result -join ', ')' from its test; expected applied, not-applied or not-present"
    }
    [string]$result[0]
}

function Set-ActionTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    & (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Set') -Tweak $Tweak
}

function Restore-ActionTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    & (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Restore') -Tweak $Tweak -State $State
}
```

Reemplazar `engine/Tuneup.psm1` completo por:

```powershell
$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
foreach ($folder in @($engineRoot, (Join-Path $engineRoot 'handlers'))) {
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.ps1' | Sort-Object Name) {
        . $file.FullName
    }
}
# Action scripts are parsed, never run: only their functions are defined (handlers/Action.ps1).
Import-TuneupActionLibrary -Path (Join-Path (Split-Path $engineRoot -Parent) 'actions')
Export-ModuleMember -Function *
```

En `engine/Dispatch.ps1`, agregar a la tabla, después de `powercfg`:

```powershell
    action     = [pscustomobject]@{ Name = 'Action'; ReadNeedsAdmin = $false }
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Action.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`). `tests/Repo.Tests.ps1` revisa que `fixture-toggle.ps1` sea ASCII.

- [ ] **Step 6: Commit**

```bash
git add engine/handlers/Action.ps1 engine/Tuneup.psm1 engine/Dispatch.ps1 tests/fixtures/actions/fixture-toggle.ps1 tests/Action.Tests.ps1 tests/StateFiles.Tests.ps1
git commit -m "feat: acciones cargadas sin ejecutar código y manejador action"
```

---

### Task 15: CLI: reglas de argumentos y `-ActionsPath`

**Files:**
- Create: `engine/Arguments.ps1`
- Modify: `tuneup.ps1`, `i18n/es.json`, `i18n/en.json`, `tests/fixtures/catalog/test.json`
- Test: `tests/Arguments.Tests.ps1`, `tests/Cli.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

`tests/Arguments.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
}

Describe 'Get-TuneupArgumentConflict' {
    It 'accepts <Name>' -TestCases @(
        @{ Name = 'a plan'; Present = @('Profile', 'Include', 'Exclude', 'WhatIf') }
        @{ Name = 'applying'; Present = @('Profile', 'Yes') }
        @{ Name = 'nothing'; Present = @() }
        @{ Name = 'status'; Present = @('Status') }
        @{ Name = 'undo of one tweak'; Present = @('Undo', 'Tweak') }
        @{ Name = 'health with repair'; Present = @('Health', 'Repair') }
        @{ Name = 'measure with compare and idle time'; Present = @('Measure', 'Compare', 'IdleSeconds') }
    ) {
        param($Present)
        Get-TuneupArgumentConflict -Present $Present | Should -BeNullOrEmpty
    }

    It 'rejects <Expected>' -TestCases @(
        @{ Present = @('Tweak'); Expected = '-Tweak (-Undo)' }
        @{ Present = @('Repair'); Expected = '-Repair (-Health)' }
        @{ Present = @('Compare'); Expected = '-Compare (-Measure)' }
        @{ Present = @('IdleSeconds', 'Status'); Expected = '-IdleSeconds (-Measure)' }
        @{ Present = @('Status', 'Undo'); Expected = '-Status -Undo' }
        @{ Present = @('Health', 'Measure'); Expected = '-Health -Measure' }
        @{ Present = @('Undo', 'Health'); Expected = '-Undo -Health' }
        @{ Present = @('Status', 'Profile', 'WhatIf'); Expected = '-Status -Profile -WhatIf' }
        @{ Present = @('Measure', 'Yes'); Expected = '-Measure -Yes' }
        @{ Present = @('Health', 'Include'); Expected = '-Health -Include' }
    ) {
        param($Present, $Expected)
        Get-TuneupArgumentConflict -Present $Present | Should -Be $Expected
    }
}
```

En `tests/Cli.Tests.ps1`, dentro del `BeforeAll`, reemplazar la función `Invoke-Tuneup` por:

```powershell
    function Invoke-Tuneup([string[]]$Arguments, [string]$Lang = 'en', [string]$Catalog = (Join-Path $Fixtures 'catalog'), [string]$Actions = (Join-Path $Fixtures 'actions')) {
        $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath $Catalog -ProfilesPath (Join-Path $Fixtures 'profiles') -ActionsPath $Actions `
            -StateRoot $script:Root -Force -Lang $Lang @Arguments
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
```

y agregar dentro de `Describe 'tuneup.ps1'`:

```powershell
    It 'plans an action tweak loaded from -ActionsPath' {
        $result = Invoke-Tuneup @('-Include', 'test.action', '-WhatIf', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        ($json.items | Where-Object { $_.id -eq 'test.action' }).action | Should -Be 'apply'
        $json.requiresAdmin | Should -BeTrue
    }

    It 'refuses an actions folder with a script that runs code' {
        $actions = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $actions | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $actions 'bad-one.ps1'), 'Write-Output hello')
        $result = Invoke-Tuneup @('-WhatIf', '-Json') -Actions $actions
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'may only define functions'
    }

    It 'says when the actions folder does not exist' {
        $result = Invoke-Tuneup @('-WhatIf', '-Json') -Actions (Join-Path $TestDrive 'no-such-actions')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'actions folder'
    }
```

En `tests/fixtures/catalog/test.json`, agregar después del objeto `test.machine` (con una coma después de su `}`):

```json
    {
      "id": "test.action",
      "title": { "es": "Prueba de acción", "en": "Action test" },
      "why": { "es": "Prueba", "en": "Test" },
      "risk": "low", "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "action", "scope": "machine",
      "set": { "script": "fixture-toggle" },
      "rebootRequired": false,
      "sources": ["https://example.com/test"]
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Arguments.Tests.ps1`
Expected: FAIL, `Get-TuneupArgumentConflict` no se reconoce como comando.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: FAIL en casi todas: PowerShell rechaza el parámetro `-ActionsPath`, que todavía no existe.

- [ ] **Step 3: Reglas de argumentos**

`engine/Arguments.ps1`:

```powershell
# Commands exclude each other and the options of applying a plan.
$script:CliCommands = @('Status', 'Undo', 'Health', 'Measure')
$script:CliApplyOptions = @('Profile', 'Include', 'Exclude', 'WhatIf', 'Yes')
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure' }

function Get-TuneupArgumentConflict {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Present)
    foreach ($option in $script:CliDependentOptions.Keys) {
        $parent = $script:CliDependentOptions[$option]
        if ($Present -contains $option -and $Present -notcontains $parent) { return "-$option (-$parent)" }
    }
    $commands = @($script:CliCommands | Where-Object { $Present -contains $_ })
    if ($commands.Count -gt 1) { return (($commands | ForEach-Object { "-$_" }) -join ' ') }
    if ($commands.Count -eq 1) {
        $extra = @($script:CliApplyOptions | Where-Object { $Present -contains $_ })
        if ($extra.Count) { return ((@($commands[0]) + $extra | ForEach-Object { "-$_" }) -join ' ') }
    }
}
```

- [ ] **Step 4: CLI**

Reemplazar `tuneup.ps1` completo por:

```powershell
<#
.SYNOPSIS
    windows-tuneup: goal-based, reversible and measurable Windows optimization.
.EXAMPLE
    .\tuneup.ps1 -Profile base,privacy -WhatIf
.EXAMPLE
    .\tuneup.ps1 -Undo last
#>
param(
    [Alias('Profile')][string[]]$ProfileName = @(),
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$WhatIf,
    [switch]$Yes,
    [switch]$Status,
    [string]$Undo,
    [string]$Tweak,
    [switch]$Json,
    [ValidateSet('es', 'en')][string]$Lang,
    [switch]$Force,
    [string]$StateRoot,
    [string]$CatalogPath,
    [string]$ProfilesPath,
    [string]$ActionsPath
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) { $argumentList += "-$($entry.Key)" }
        } else {
            $argumentList += "-$($entry.Key)"
            $argumentList += (@($entry.Value) -join ',')
        }
    }
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @argumentList
    exit $LASTEXITCODE
}

Import-Module (Join-Path $PSScriptRoot 'engine\Tuneup.psm1') -Force
Initialize-TuneupI18n -Root (Join-Path $PSScriptRoot 'i18n') -Lang $Lang

$script:Warnings = New-Object System.Collections.Generic.List[string]

# powershell.exe writes warnings to standard output, where they would break the JSON document,
# so with -Json they are collected and reported inside it instead.
function Invoke-TuneupStep {
    param([Parameter(Mandatory)][scriptblock]$Step)
    if (-not $Json) { return (& $Step) }
    & $Step 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) {
            if (-not $script:Warnings.Contains($_.Message)) { $script:Warnings.Add($_.Message) }
        } else {
            $_
        }
    }
}

function Stop-Tuneup {
    param([Parameter(Mandatory)][string]$Message, [string[]]$Details = @())
    Write-TuneupErrorReport -Message $Message -Details $Details -Warnings $script:Warnings.ToArray() -Json:$Json
    exit 1
}

$ProfileName = @(Get-TuneupCleanList ($ProfileName -split ','))
$Include = @(Get-TuneupCleanList ($Include -split ','))
$Exclude = @(Get-TuneupCleanList ($Exclude -split ','))

$present = @()
if ($ProfileName.Count) { $present += 'Profile' }
if ($Include.Count) { $present += 'Include' }
if ($Exclude.Count) { $present += 'Exclude' }
if ($WhatIf) { $present += 'WhatIf' }
if ($Yes) { $present += 'Yes' }
if ($Status) { $present += 'Status' }
if ($Undo) { $present += 'Undo' }
if ($Tweak) { $present += 'Tweak' }
$conflict = Get-TuneupArgumentConflict -Present $present
if ($conflict) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.badArgs' -Format $conflict) }

try {
    # Relative paths follow the current PowerShell location, not the process folder that .NET uses.
    $pathApi = $ExecutionContext.SessionState.Path
    if ($StateRoot) { $StateRoot = $pathApi.GetUnresolvedProviderPathFromPSPath($StateRoot) }
    $CatalogPath = $(if ($CatalogPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($CatalogPath) } else { Join-Path $PSScriptRoot 'catalog' })
    $ProfilesPath = $(if ($ProfilesPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($ProfilesPath) } else { Join-Path $PSScriptRoot 'profiles' })
    if ($ActionsPath) {
        # Tests and development only, like -StateRoot: action scripts from another folder.
        $ActionsPath = $pathApi.GetUnresolvedProviderPathFromPSPath($ActionsPath)
        if (-not (Test-Path -LiteralPath $ActionsPath -PathType Container)) {
            Stop-Tuneup -Message (Get-TuneupText -Key 'err.actionsPathMissing' -Format $ActionsPath)
        }
        Invoke-TuneupStep { Import-TuneupActionLibrary -Path $ActionsPath }
    }

    $environment = Invoke-TuneupStep { Get-TuneupEnvironment }

    if ($Status) {
        $items = @(Invoke-TuneupStep { Get-TuneupStatus -StateRoot $StateRoot })
        Write-TuneupStatusReport -Items $items -Warnings $script:Warnings.ToArray() -Json:$Json
        exit 0
    }

    if ($Undo) {
        $run = Invoke-TuneupStep { Resolve-TuneupRun -StateRoot $StateRoot -RunId $Undo }
        if (-not $run) {
            $missing = $(if ($Undo -eq 'last') { Get-TuneupText -Key 'undo.none' } else { Get-TuneupText -Key 'err.runNotFound' -Format $Undo })
            Stop-Tuneup -Message $missing
        }
        # Machine-folder runs always need elevation; a -StateRoot run only for its machine tweaks.
        $needsAdmin = ($run.Root -eq 'machine')
        if (-not $needsAdmin) {
            # Its warnings come again, once, from the undo itself.
            $needsAdmin = @(Invoke-TuneupStep { Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue } | Where-Object { $_.tweak.scope -eq 'machine' }).Count -gt 0
        }
        if ($needsAdmin -and -not $environment.IsAdmin) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.notAdmin') }
        $undoResults = @(Invoke-TuneupStep { Invoke-TuneupUndo -Run $run -TweakId $Tweak })
        Write-TuneupUndoReport -RunId $run.Id -Results $undoResults -Warnings $script:Warnings.ToArray() -Json:$Json
        exit (Get-TuneupUndoExitCode -Results $undoResults)
    }

    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
    if (($environment.Build -lt 19041 -or $environment.Edition -eq 'Unknown') -and -not $Force) {
        Stop-Tuneup -Message (Get-TuneupText -Key 'err.unsupported')
    }
    # Server supports every policy that Enterprise supports.
    if ($environment.IsServer) { $environment.Edition = 'Enterprise' }

    $catalog = @(Invoke-TuneupStep { Import-TuneupCatalog -Path $CatalogPath })
    $profileSet = @(Invoke-TuneupStep { Import-TuneupProfileSet -Path $ProfilesPath })
    $problems = @(Test-TuneupCatalog -Catalog $catalog) + @(Test-TuneupProfileSet -Profiles $profileSet -Catalog $catalog)
    if ($problems.Count) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.catalog') -Details $problems }

    $plan = @(Invoke-TuneupStep {
        New-TuneupPlan -Catalog $catalog -Profiles $profileSet -ProfileIds $ProfileName `
            -Include $Include -Exclude $Exclude -Environment $environment `
            -TestState { param($tweak) Test-TuneupState -Tweak $tweak }
    })
    $toApply = @($plan | Where-Object { $_.Action -eq 'apply' })

    if ($WhatIf -or -not $toApply.Count) {
        Write-TuneupPlanReport -Plan $plan -Environment $environment -Warnings $script:Warnings.ToArray() -Json:$Json
        exit 0
    }
    $machineChanges = @($toApply | Where-Object { $_.Tweak.scope -eq 'machine' }).Count
    if ($machineChanges -and -not $environment.IsAdmin) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.notAdmin') }
    if (-not $Yes) {
        if ($Json) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.jsonNeedsYes') }
        Write-TuneupPlanReport -Plan $plan -Environment $environment
        $answer = Read-Host (Get-TuneupText -Key 'confirm' -Format $toApply.Count)
        if ($answer -notmatch (Get-TuneupText -Key 'confirm.pattern')) {
            Write-Host (Get-TuneupText -Key 'aborted')
            exit 1
        }
    }

    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupStep { New-TuneupRun -StateRoot $StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupStep { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupStep { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    $results = @(Invoke-TuneupStep { Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir })
    $report = New-TuneupApplyReport -Run $run -Results $results -RestorePoint $restorePoint -Environment $environment
    $saved = Invoke-TuneupStep { Save-TuneupApplyReport -Run $run -Report $report }
    Write-TuneupApplyReport -Report $report -Warnings $script:Warnings.ToArray() -Json:$Json
    exit (Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved))
} catch {
    Stop-Tuneup -Message $_.Exception.Message
}
```

- [ ] **Step 5: Textos**

En `i18n/es.json`, después de `"err.badArgs": ...`, agregar:

```json
  "err.actionsPathMissing": "No existe la carpeta de acciones {0}.",
```

En `i18n/en.json`, en el mismo lugar:

```json
  "err.actionsPathMissing": "The actions folder {0} does not exist.",
```

- [ ] **Step 6: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Arguments.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (las pruebas de combinaciones rechazadas siguen dando `Invalid parameter combination`).

- [ ] **Step 7: Commit**

```bash
git add engine/Arguments.ps1 tuneup.ps1 i18n/es.json i18n/en.json tests/fixtures/catalog/test.json tests/Arguments.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat: reglas de argumentos en una función y acciones con -ActionsPath"
```

---

### Task 16: Salud: lectura de CBS.log

**Files:**
- Create: `engine/Health.ps1`
- Create: `tests/fixtures/cbs/sfc-repaired.log`, `tests/fixtures/cbs/sfc-unrepaired.log`, `tests/fixtures/cbs/scanhealth-corrupt.log`, `tests/fixtures/cbs/restorehealth-fixed.log`, `tests/fixtures/cbs/restorehealth-partial.log`
- Test: `tests/Health.Tests.ps1`

Los extractos copian el formato de las líneas reales de `C:\Windows\Logs\CBS\CbsPersist_20260930163350.log` de este equipo (corrida de SFC de las 09:47 y de DISM `/ScanHealth` y `/RestoreHealth` del 30-09), recortados a pocas líneas y sin datos personales. Entre los campos de las líneas `(p)` y de los totales hay **tabulaciones** reales, como en CBS.log; el resto son espacios. Las líneas `[SR] Cannot repair member file` (que este equipo no tiene) siguen el formato que documenta Microsoft para SFC, y `restorehealth-partial.log` combina líneas reales para el caso de una reparación incompleta.

- [ ] **Step 1: Extractos de CBS.log**

`tests/fixtures/cbs/sfc-repaired.log`:

```text
2026-09-30 09:40:00, Info                  CSI    00000001 [SR] Repairing 3 components
2026-09-30 09:47:00, Info                  CSI    00000007 [SR] Verifying 100 components
2026-09-30 09:47:00, Info                  CSI    00000008 [SR] Beginning Verify and Repair transaction
2026-09-30 09:47:00, Info                  CSI    00000009 [SR] Verify complete
2026-09-30 09:48:37, Info                  CSI    0000021f [SR] Verifying 32 components
2026-09-30 09:48:37, Info                  CSI    00000220 [SR] Beginning Verify and Repair transaction
2026-09-30 09:48:37, Info                  CSI    00000221 [SR] Verify complete
2026-09-30 09:48:37, Info                  CSI    00000222 [SR] Repairing 0 components
2026-09-30 09:48:37, Info                  CSI    00000223 [SR] Beginning Verify and Repair transaction
2026-09-30 09:48:37, Info                  CSI    00000224 [SR] Repair complete
2026-09-30 09:48:37, Info                  DEPLOY [Pnp] Corrupt file: C:\WINDOWS\System32\drivers\BthA2dp.sys
2026-09-30 09:48:37, Info                  DEPLOY [Pnp] Repaired file: C:\WINDOWS\System32\drivers\BthA2dp.sys
2026-09-30 09:48:37, Info                  DEPLOY [Pnp] Corrupt file: C:\WINDOWS\System32\drivers\BthHfEnum.sys
2026-09-30 09:48:37, Info                  DEPLOY [Pnp] Repaired file: C:\WINDOWS\System32\drivers\BthHfEnum.sys
```

`tests/fixtures/cbs/sfc-unrepaired.log`:

```text
2026-09-30 11:16:19, Info                  CSI    00000216 [SR] Verifying 100 components
2026-09-30 11:16:19, Info                  CSI    00000217 [SR] Beginning Verify and Repair transaction
2026-09-30 11:16:19, Info                  CSI    00000218 [SR] Cannot repair member file [l:7]"ci.dll" of Microsoft-Windows-CodeIntegrity, version 10.0.26100.1591, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch
2026-09-30 11:16:19, Info                  CSI    00000219 [SR] Verify complete
2026-09-30 11:16:19, Info                  CSI    0000021c [SR] Repairing 1 components
2026-09-30 11:16:19, Info                  CSI    0000021d [SR] Beginning Verify and Repair transaction
2026-09-30 11:16:19, Info                  CSI    0000021e [SR] Cannot repair member file [l:7]"ci.dll" of Microsoft-Windows-CodeIntegrity, version 10.0.26100.1591, arch amd64, nonSxS, pkt {l:8 b:31bf3856ad364e35} in the store, hash mismatch
2026-09-30 11:16:19, Info                  CSI    0000021f [SR] Repair complete
2026-09-30 11:16:19, Info                  DEPLOY [Pnp] Corrupt file: C:\WINDOWS\System32\drivers\bthmodem.sys
```

`tests/fixtures/cbs/scanhealth-corrupt.log`:

```text
2026-09-30 10:01:57, Info                  CBS    Checking System Update Readiness.
2026-09-30 10:01:57, Info                  CBS    
2026-09-30 10:01:57, Info                  CBS    (p)	CSI Payload Corrupt	(n)			amd64_microsoft-windows-codeintegrity_31bf3856ad364e35_10.0.26100.1591_none_3c37ec64b4c6bb8a\r\ci.dll
2026-09-30 10:01:57, Info                  CBS    (p)	CSI Payload Corrupt	(n)			amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\bootmgfw.efi
2026-09-30 10:01:57, Info                  CBS    (p)	CSI Payload Corrupt	(n)			amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\bootmgr.efi
2026-09-30 10:01:57, Info                  CBS    (p)	CSI Payload Corrupt	(n)			amd64_microsoft.ink_31bf3856ad364e35_10.0.26100.1455_none_22be944b505ac37e\r\Microsoft.Ink.dll
2026-09-30 10:01:57, Info                  CBS    (p)	CSI Payload Corrupt	(n)			wow64_microsoft.ink_31bf3856ad364e35_10.0.26100.1455_none_2d133e9d84bb8579\r\Microsoft.Ink.dll
2026-09-30 10:01:57, Info                  CBS    (p)	CSI Payload Corrupt	(n)			amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\SecureBootRecovery.efi
2026-09-30 10:01:57, Info                  CBS    
2026-09-30 10:01:57, Info                  CBS    Summary:
2026-09-30 10:01:57, Info                  CBS    Operation: Detect only 
2026-09-30 10:01:57, Info                  CBS    Operation result: 0x0
2026-09-30 10:01:57, Info                  CBS    Last Successful Step: Stage package detection completes.
2026-09-30 10:01:57, Info                  CBS    Total Detected Corruption:	6
2026-09-30 10:01:57, Info                  CBS    	CBS Manifest Corruption:	0
2026-09-30 10:01:57, Info                  CBS    	CSI Payload Corruption:	6
2026-09-30 10:01:57, Info                  CBS    Total Repaired Corruption:	0
2026-09-30 10:01:57, Info                  CBS    	CSI Payload Repaired:	0
2026-09-30 10:01:57, Info                  CBS    
2026-09-30 10:01:57, Info                  CBS    Total Operation Time: 113 seconds.
```

`tests/fixtures/cbs/restorehealth-fixed.log`:

```text
2026-09-30 10:17:54, Info                  CBS    Checking System Update Readiness.
2026-09-30 10:17:54, Info                  CBS    
2026-09-30 10:17:54, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-codeintegrity_31bf3856ad364e35_10.0.26100.1591_none_3c37ec64b4c6bb8a\r\ci.dll
2026-09-30 10:17:54, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\bootmgfw.efi
2026-09-30 10:17:54, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\bootmgr.efi
2026-09-30 10:17:54, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft.ink_31bf3856ad364e35_10.0.26100.1455_none_22be944b505ac37e\r\Microsoft.Ink.dll
2026-09-30 10:17:54, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	wow64_microsoft.ink_31bf3856ad364e35_10.0.26100.1455_none_2d133e9d84bb8579\r\Microsoft.Ink.dll
2026-09-30 10:17:54, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\SecureBootRecovery.efi
2026-09-30 10:17:54, Info                  CBS    
2026-09-30 10:17:54, Info                  CBS    Summary:
2026-09-30 10:17:54, Info                  CBS    Operation: Detect and Repair 
2026-09-30 10:17:54, Info                  CBS    Operation result: 0x0
2026-09-30 10:17:54, Info                  CBS    Last Successful Step: Remove staged packages completes.
2026-09-30 10:17:54, Info                  CBS    Total Detected Corruption:	6
2026-09-30 10:17:54, Info                  CBS    	CSI Payload Corruption:	6
2026-09-30 10:17:54, Info                  CBS    Total Repaired Corruption:	6
2026-09-30 10:17:54, Info                  CBS    	CSI Payload Repaired:	6
2026-09-30 10:17:54, Info                  CBS    
2026-09-30 10:17:54, Info                  CBS    Total Operation Time: 914 seconds.
2026-09-30 10:17:54, Info                  CBS    All WCP store corruptions were fixed
```

`tests/fixtures/cbs/restorehealth-partial.log`:

```text
2026-09-30 10:40:00, Info                  CBS    Checking System Update Readiness.
2026-09-30 10:40:00, Info                  CBS    
2026-09-30 10:40:00, Info                  CBS    (p)	CSI Payload Corrupt	(n)			amd64_microsoft-windows-codeintegrity_31bf3856ad364e35_10.0.26100.1591_none_3c37ec64b4c6bb8a\r\ci.dll
2026-09-30 10:40:00, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\bootmgfw.efi
2026-09-30 10:40:00, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\bootmgr.efi
2026-09-30 10:40:00, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft.ink_31bf3856ad364e35_10.0.26100.1455_none_22be944b505ac37e\r\Microsoft.Ink.dll
2026-09-30 10:40:00, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	wow64_microsoft.ink_31bf3856ad364e35_10.0.26100.1455_none_2d133e9d84bb8579\r\Microsoft.Ink.dll
2026-09-30 10:40:00, Info                  CBS    (p)	CSI Payload Corrupt	(w)	(Fixed)	amd64_microsoft-windows-b..ore-bootmanager-efi_31bf3856ad364e35_10.0.26100.1455_none_234757a24c629793\r\SecureBootRecovery.efi
2026-09-30 10:40:00, Info                  CBS    
2026-09-30 10:40:00, Info                  CBS    Summary:
2026-09-30 10:40:00, Info                  CBS    Operation: Detect and Repair 
2026-09-30 10:40:00, Info                  CBS    Operation result: 0x800f081f
2026-09-30 10:40:00, Info                  CBS    Last Successful Step: Entire operation completes.
2026-09-30 10:40:00, Info                  CBS    Total Detected Corruption:	6
2026-09-30 10:40:00, Info                  CBS    	CSI Payload Corruption:	6
2026-09-30 10:40:00, Info                  CBS    Total Repaired Corruption:	5
2026-09-30 10:40:00, Info                  CBS    	CSI Payload Repaired:	5
2026-09-30 10:40:00, Info                  CBS    
2026-09-30 10:40:00, Info                  CBS    Total Operation Time: 420 seconds.
```

- [ ] **Step 2: Prueba que falla**

`tests/Health.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Cbs = Join-Path $PSScriptRoot 'fixtures\cbs'
    function Get-CbsFixture([string]$Name) { @(Get-Content -LiteralPath (Join-Path $Cbs $Name) -Encoding UTF8) }
}

Describe 'CBS log window' {
    It 'keeps the lines from the start time on' {
        $lines = Get-CbsFixture 'sfc-repaired.log'
        $window = @(Select-TuneupCbsWindow -Lines $lines -Since ([datetime]'2026-09-30 09:47:00'))
        $window.Count | Should -Be ($lines.Count - 1)
        $window[0] | Should -Match '\[SR\] Verifying 100 components'
    }

    It 'stops at the end time and keeps lines without a time with the entry above' {
        $lines = @('2026-09-30 10:00:00, Info CBS first', 'continuation', '2026-09-30 10:00:05, Info CBS second', 'tail')
        @(Select-TuneupCbsWindow -Lines $lines -Since ([datetime]'2026-09-30 10:00:00') -Until ([datetime]'2026-09-30 10:00:01')) -join '|' |
            Should -Be '2026-09-30 10:00:00, Info CBS first|continuation'
    }
}

Describe 'SFC summary' {
    It 'lists the files SFC repaired' {
        $summary = Get-TuneupSfcSummary -Lines (Get-CbsFixture 'sfc-repaired.log')
        $summary.status | Should -Be 'repaired'
        $summary.repairedFiles -join ',' | Should -Be 'C:\WINDOWS\System32\drivers\BthA2dp.sys,C:\WINDOWS\System32\drivers\BthHfEnum.sys'
        @($summary.unrepairedFiles).Count | Should -Be 0
    }

    It 'is clean when SFC found nothing' {
        $lines = @(Get-CbsFixture 'sfc-repaired.log')[1..9]
        (Get-TuneupSfcSummary -Lines $lines).status | Should -Be 'clean'
    }

    It 'lists the files SFC could not repair once each' {
        $summary = Get-TuneupSfcSummary -Lines (Get-CbsFixture 'sfc-unrepaired.log')
        $summary.status | Should -Be 'unrepaired'
        $summary.unrepairedFiles -join ',' | Should -Be 'ci.dll,C:\WINDOWS\System32\drivers\bthmodem.sys'
    }

    It 'is unknown when SFC left no trace' {
        (Get-TuneupSfcSummary -Lines @('2026-09-30 10:00:00, Info                  CBS    Nothing here')).status | Should -Be 'unknown'
    }
}

Describe 'Component store summary' {
    It 'finds repairable damage after a scan' {
        $summary = Get-TuneupComponentStoreSummary -Lines (Get-CbsFixture 'scanhealth-corrupt.log')
        $summary.state | Should -Be 'repairable'
        $summary.operation | Should -Be 'Detect only'
        $summary.result | Should -Be '0x0'
        $summary.detected | Should -Be 6
        $summary.repaired | Should -Be 0
    }

    It 'reports a repair that fixed everything' {
        $summary = Get-TuneupComponentStoreSummary -Lines (Get-CbsFixture 'restorehealth-fixed.log')
        $summary.state | Should -Be 'repaired'
        $summary.repaired | Should -Be 6
    }

    It 'reports damage that a repair could not fix' {
        $summary = Get-TuneupComponentStoreSummary -Lines (Get-CbsFixture 'restorehealth-partial.log')
        $summary.state | Should -Be 'unrepairable'
        $summary.result | Should -Be '0x800f081f'
        $summary.repaired | Should -Be 5
    }

    It 'is healthy when nothing was detected' {
        $lines = @(
            '2026-09-30 10:00:00, Info                  CBS    Checking System Update Readiness.',
            '2026-09-30 10:00:00, Info                  CBS    Operation: Detect only ',
            "2026-09-30 10:00:00, Info                  CBS    Total Detected Corruption:`t0"
        )
        (Get-TuneupComponentStoreSummary -Lines $lines).state | Should -Be 'healthy'
    }

    It 'is unknown without a DISM summary' {
        (Get-TuneupComponentStoreSummary -Lines @('2026-09-30 10:00:00, Info                  CBS    Nothing here')).state | Should -Be 'unknown'
    }

    It 'uses the last check in the window' {
        $lines = @(Get-CbsFixture 'scanhealth-corrupt.log') + @(Get-CbsFixture 'restorehealth-fixed.log')
        (Get-TuneupComponentStoreSummary -Lines $lines).state | Should -Be 'repaired'
    }

    It 'reads the same values with spaces instead of tabs' {
        $lines = @(Get-CbsFixture 'scanhealth-corrupt.log') -replace "`t", '    '
        (Get-TuneupComponentStoreSummary -Lines $lines).detected | Should -Be 6
        @(Get-TuneupCorruptComponentGroup -Lines $lines).Count | Should -Be 3
    }
}

Describe 'Corrupt component groups' {
    It 'keeps the real tabs of CBS.log in the fixtures' {
        Get-Content -LiteralPath (Join-Path $Cbs 'scanhealth-corrupt.log') -Raw | Should -Match "`t"
    }

    It 'groups the damaged files by component' {
        $groups = @(Get-TuneupCorruptComponentGroup -Lines (Get-CbsFixture 'scanhealth-corrupt.log'))
        ($groups | ForEach-Object { "$($_.name):$($_.files)" }) -join ',' |
            Should -Be 'microsoft-windows-b..ore-bootmanager-efi:3,microsoft.ink:2,microsoft-windows-codeintegrity:1'
    }

    It 'leaves out what a repair fixed' {
        @(Get-TuneupCorruptComponentGroup -Lines (Get-CbsFixture 'restorehealth-fixed.log')).Count | Should -Be 0
    }

    It 'keeps what a repair could not fix' {
        $groups = @(Get-TuneupCorruptComponentGroup -Lines (Get-CbsFixture 'restorehealth-partial.log'))
        ($groups | ForEach-Object { "$($_.name):$($_.files)" }) -join ',' | Should -Be 'microsoft-windows-codeintegrity:1'
    }
}
```

- [ ] **Step 3: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, `Select-TuneupCbsWindow` no se reconoce como comando (la prueba de las tabulaciones ya pasa).

- [ ] **Step 4: Implementación**

`engine/Health.ps1`:

```powershell
$script:CbsTimePattern = '^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),'

function Select-TuneupCbsWindow {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][datetime]$Since,
        [datetime]$Until = [datetime]::MaxValue
    )
    # A line without its own time belongs to the entry above it.
    $inside = $false
    foreach ($line in $Lines) {
        if ($line -match $script:CbsTimePattern) {
            $time = [datetime]::ParseExact($Matches['time'], 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            $inside = ($time -ge $Since -and $time -le $Until)
        }
        if ($inside) { $line }
    }
}

function Get-TuneupSfcSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $ran = $false
    $repairing = 0
    $repaired = New-Object System.Collections.Generic.List[string]
    $unrepaired = New-Object System.Collections.Generic.List[string]
    $corrupt = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        if ($line -match '\[SR\] ') { $ran = $true }
        if ($line -match '\[SR\] Repairing (?<count>\d+) components') {
            $repairing += [int]$Matches['count']
        } elseif ($line -match '\[SR\] Cannot repair member file \[[^\]]*\]"(?<file>[^"]+)"') {
            if (-not $unrepaired.Contains($Matches['file'])) { $unrepaired.Add($Matches['file']) }
        } elseif ($line -match '\[SR\] Repairing corrupted file \[[^\]]*\]"(?<file>[^"]+)"') {
            if (-not $repaired.Contains($Matches['file'])) { $repaired.Add($Matches['file']) }
        } elseif ($line -match '\[Pnp\] Corrupt file: (?<file>.+?)\s*$') {
            if (-not $corrupt.Contains($Matches['file'])) { $corrupt.Add($Matches['file']) }
        } elseif ($line -match '\[Pnp\] Repaired file: (?<file>.+?)\s*$') {
            if (-not $repaired.Contains($Matches['file'])) { $repaired.Add($Matches['file']) }
        }
    }
    # A driver reported corrupt and never repaired is still damaged.
    foreach ($file in $corrupt) {
        if (-not $repaired.Contains($file) -and -not $unrepaired.Contains($file)) { $unrepaired.Add($file) }
    }
    $status = 'clean'
    if (-not $ran) { $status = 'unknown' }
    elseif ($unrepaired.Count) { $status = 'unrepaired' }
    elseif ($repaired.Count -or $repairing) { $status = 'repaired' }
    [pscustomobject]@{
        status          = $status
        repairedFiles   = [string[]]$repaired.ToArray()
        unrepairedFiles = [string[]]$unrepaired.ToArray()
    }
}

function Get-TuneupComponentStoreSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $found = $null
    foreach ($line in $Lines) {
        # Every DISM check starts with this line; only the last one in the window counts.
        if ($line -match 'Checking System Update Readiness') {
            $found = @{ operation = $null; result = $null; detected = $null; repaired = $null }
            continue
        }
        if ($null -eq $found) { continue }
        if ($line -match 'Operation: (?<value>.+?)\s*$') { $found.operation = $Matches['value'] }
        elseif ($line -match 'Operation result: (?<value>0x[0-9a-fA-F]+)') { $found.result = $Matches['value'].ToLowerInvariant() }
        elseif ($line -match 'Total Detected Corruption:\s*(?<value>\d+)') { $found.detected = [int]$Matches['value'] }
        elseif ($line -match 'Total Repaired Corruption:\s*(?<value>\d+)') { $found.repaired = [int]$Matches['value'] }
    }
    if ($null -eq $found -or $null -eq $found.detected) {
        return [pscustomobject]@{ state = 'unknown'; operation = $null; result = $null; detected = $null; repaired = $null }
    }
    $repairMode = ([string]$found.operation -match 'Repair')
    if ($repairMode -and $found.result -and $found.result -ne '0x0') { $state = 'unrepairable' }
    elseif ($found.detected -eq 0) { $state = 'healthy' }
    elseif (-not $repairMode) { $state = 'repairable' }
    elseif ([int]$found.repaired -ge $found.detected) { $state = 'repaired' }
    else { $state = 'unrepairable' }
    [pscustomobject]@{
        state     = $state
        operation = $found.operation
        result    = $found.result
        detected  = $found.detected
        repaired  = $found.repaired
    }
}

function Get-TuneupCorruptComponentGroup {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $block = $null
    foreach ($line in $Lines) {
        if ($line -match 'Checking System Update Readiness') {
            $block = New-Object System.Collections.Generic.List[string]
            continue
        }
        if ($null -ne $block) { $block.Add($line) }
    }
    if ($null -eq $block) { return }
    $counts = @{}
    foreach ($line in $block) {
        # (Fixed) marks what a repair already fixed; the rest is still damaged.
        if ($line -notmatch '\(p\)\s+CSI Payload Corrupt\s+\([a-z]\)\s+(?<fixed>\(Fixed\)\s+)?(?<component>\S+)') { continue }
        if ($Matches['fixed']) { continue }
        $component = $Matches['component']
        if ($component -match '^(?:amd64|wow64|x86|msil|arm64|arm)_(?<name>.+?)_[0-9a-f]{16}_') { $name = $Matches['name'] }
        else { $name = ($component -split '\\')[0] }
        if ($counts.ContainsKey($name)) { $counts[$name]++ } else { $counts[$name] = 1 }
    }
    $counts.GetEnumerator() |
        Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key }; Descending = $false } |
        ForEach-Object { [pscustomobject]@{ name = $_.Key; files = $_.Value } }
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add engine/Health.ps1 tests/Health.Tests.ps1 tests/fixtures/cbs/sfc-repaired.log tests/fixtures/cbs/sfc-unrepaired.log tests/fixtures/cbs/scanhealth-corrupt.log tests/fixtures/cbs/restorehealth-fixed.log tests/fixtures/cbs/restorehealth-partial.log
git commit -m "feat: lectura de SFC y DISM desde CBS.log con extractos reales"
```

---

### Task 17: Salud: archivos de CBS y ejecución de sfc y DISM

**Files:**
- Modify: `engine/Health.ps1`
- Test: `tests/Health.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Health.Tests.ps1`:

```powershell
Describe 'CBS log files' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Folder | Out-Null
        $script:Since = [datetime]'2026-09-30 10:00:00'
        $script:Current = Join-Path $Folder 'CBS.log'
    }

    It 'reads the logs rotated since the start and then CBS.log' {
        $old = Join-Path $Folder 'CbsPersist_20260929000000.log'
        [System.IO.File]::WriteAllText($old, "2026-09-30 10:00:30, Info CBS old`r`n")
        (Get-Item -LiteralPath $old).LastWriteTime = $Since.AddDays(-1)
        $rotated = Join-Path $Folder 'CbsPersist_20260930100500.log'
        [System.IO.File]::WriteAllText($rotated, "2026-09-30 09:59:00, Info CBS before`r`n2026-09-30 10:01:00, Info CBS rotated`r`n")
        (Get-Item -LiteralPath $rotated).LastWriteTime = $Since.AddMinutes(5)
        [System.IO.File]::WriteAllText($Current, "2026-09-30 10:06:00, Info CBS current`r`n")
        @(Read-TuneupCbsLog -Since $Since -Folder $Folder) -join '|' |
            Should -Be '2026-09-30 10:01:00, Info CBS rotated|2026-09-30 10:06:00, Info CBS current'
    }

    It 'reads CBS.log while another process keeps it open for writing' {
        [System.IO.File]::WriteAllText($Current, "2026-09-30 10:06:00, Info CBS current`r`n")
        $writer = [System.IO.FileStream]::new($Current, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
        try {
            @(Read-TuneupCbsLog -Since $Since -Folder $Folder).Count | Should -Be 1
        } finally {
            $writer.Dispose()
        }
    }

    It 'returns nothing when there are no logs' {
        @(Read-TuneupCbsLog -Since $Since -Folder $Folder).Count | Should -Be 0
    }
}

Describe 'Tool output' {
    It 'decodes UTF-16 output' {
        $bytes = [System.Text.Encoding]::Unicode.GetBytes("Beginning system scan.`r`nVerification 100% complete.`r`n")
        ConvertFrom-TuneupToolOutput -Bytes $bytes | Should -Be ("Beginning system scan." + [Environment]::NewLine + "Verification 100% complete.")
    }

    It 'decodes output in the OEM code page' {
        $oem = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        ConvertFrom-TuneupToolOutput -Bytes $oem.GetBytes("Error: 87`r`n`r`nThe parameter is incorrect.`r`n") |
            Should -Be ("Error: 87" + [Environment]::NewLine + "The parameter is incorrect.")
    }

    It 'keeps only the last 15 lines' {
        $text = (1..20 | ForEach-Object { "line $_" }) -join "`r`n"
        $lines = (ConvertFrom-TuneupToolOutput -Bytes ([System.Text.Encoding]::ASCII.GetBytes($text))) -split [Environment]::NewLine
        $lines.Count | Should -Be 15
        $lines[0] | Should -Be 'line 6'
    }

    It 'returns an empty text for no output' {
        ConvertFrom-TuneupToolOutput -Bytes ([byte[]]@()) | Should -Be ''
    }

    It 'runs a tool and returns its exit code and output' {
        $result = Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments @('/c', 'echo', 'hola&', 'exit', '3')
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Be 'hola'
    }

    It 'runs sfc /scannow and DISM with English output' {
        Mock -ModuleName Tuneup Invoke-TuneupHealthTool { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Invoke-TuneupSfc | Out-Null
        Invoke-TuneupDism -Operation 'RestoreHealth' | Out-Null
        Should -Invoke Invoke-TuneupHealthTool -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\System32\sfc.exe' -and ($Arguments -join ' ') -eq '/scannow'
        }
        Should -Invoke Invoke-TuneupHealthTool -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\System32\Dism.exe' -and ($Arguments -join ' ') -eq '/Online /Cleanup-Image /RestoreHealth /English'
        }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, `Read-TuneupCbsLog` y `ConvertFrom-TuneupToolOutput` no se reconocen como comando.

- [ ] **Step 3: Implementación**

Agregar al final de `engine/Health.ps1`:

```powershell
function Get-TuneupCbsLogFile {
    param([Parameter(Mandatory)][datetime]$Since, [string]$Folder = (Join-Path $env:SystemRoot 'Logs\CBS'))
    # Windows moves CBS.log to CbsPersist_<time>.log when it grows, so a long scan can span both.
    Get-ChildItem -LiteralPath $Folder -Filter 'CbsPersist_*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since } | Sort-Object LastWriteTime | ForEach-Object { $_.FullName }
    $current = Join-Path $Folder 'CBS.log'
    if (Test-Path -LiteralPath $current -PathType Leaf) { $current }
}

function Read-TuneupCbsLog {
    param(
        [Parameter(Mandatory)][datetime]$Since,
        [datetime]$Until = [datetime]::MaxValue,
        [string]$Folder = (Join-Path $env:SystemRoot 'Logs\CBS')
    )
    foreach ($path in @(Get-TuneupCbsLogFile -Since $Since -Folder $Folder)) {
        # TrustedInstaller keeps CBS.log open for writing, so it is read sharing read and write.
        $stream = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
        $reader = New-Object System.IO.StreamReader -ArgumentList $stream, ([System.Text.Encoding]::UTF8), $true
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        Select-TuneupCbsWindow -Lines @($text -split "`r?`n" | Where-Object { $_ }) -Since $Since -Until $Until
    }
}

function ConvertFrom-TuneupToolOutput {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    if (-not $Bytes.Length) { return '' }
    # sfc writes UTF-16 when its output is redirected; DISM writes in the OEM code page.
    $zeros = @($Bytes | Where-Object { $_ -eq 0 }).Count
    if ($zeros * 4 -ge $Bytes.Length) {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    } else {
        $text = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($Bytes)
    }
    $lines = @($text.TrimStart([char]0xFEFF) -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    ($lines | Select-Object -Last 15) -join [Environment]::NewLine
}

function Invoke-TuneupHealthTool {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $Arguments -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.CreateNoWindow = $true
    # The raw bytes are kept and decoded afterwards: the tool picks the encoding, not the console.
    $buffer = New-Object System.IO.MemoryStream
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = (ConvertFrom-TuneupToolOutput -Bytes $buffer.ToArray()) }
    } finally {
        $process.Dispose()
        $buffer.Dispose()
    }
}

function Invoke-TuneupSfc {
    Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\sfc.exe') -Arguments @('/scannow')
}

function Invoke-TuneupDism {
    param([Parameter(Mandatory)][ValidateSet('ScanHealth', 'RestoreHealth')][string]$Operation)
    Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\Dism.exe') -Arguments @('/Online', '/Cleanup-Image', "/$Operation", '/English')
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/Health.ps1 tests/Health.Tests.ps1
git commit -m "feat: lectura de CBS.log rotado y ejecución de sfc y DISM con su salida"
```

---

### Task 18: Salud: orquestación, recomendación y código de salida

**Files:**
- Modify: `engine/Health.ps1`
- Test: `tests/Health.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Health.Tests.ps1`:

```powershell
Describe 'Invoke-TuneupHealth' {
    BeforeAll {
        $script:Healthy = @(
            '2026-09-30 10:00:00, Info                  CSI    00000001 [SR] Repairing 0 components',
            '2026-09-30 10:00:01, Info                  CBS    Checking System Update Readiness.',
            '2026-09-30 10:00:01, Info                  CBS    Operation: Detect only ',
            "2026-09-30 10:00:01, Info                  CBS    Total Detected Corruption:`t0"
        )
        $script:Corrupt = @($Healthy[0]) + @(Get-CbsFixture 'scanhealth-corrupt.log')
        $script:Fixed = @(Get-CbsFixture 'restorehealth-fixed.log') + @($Healthy[0])
        $script:NotFixed = @(Get-CbsFixture 'restorehealth-partial.log') + @($Healthy[0])
    }

    BeforeEach {
        $script:Phase = 'scan'
        Mock -ModuleName Tuneup Invoke-TuneupSfc { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock -ModuleName Tuneup Invoke-TuneupDism {
            if ($Operation -eq 'RestoreHealth') { $script:Phase = 'repair' }
            [pscustomobject]@{ ExitCode = 0; Output = '' }
        }
    }

    It 'reports a healthy Windows and does not repair it' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Healthy }
        $report = Invoke-TuneupHealth -Repair
        $report.command | Should -Be 'health'
        $report.schemaVersion | Should -Be 1
        $report.before.sfc.status | Should -Be 'clean'
        $report.before.componentStore.state | Should -Be 'healthy'
        $report.repairRequested | Should -BeTrue
        $report.repairRan | Should -BeFalse
        $report.after | Should -BeNullOrEmpty
        $report.recommendation | Should -Be 'none'
        $report.rebootRecommended | Should -BeFalse
        Get-TuneupHealthExitCode -Report $report | Should -Be 0
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'recommends a repair without running it' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Corrupt }
        $report = Invoke-TuneupHealth
        $report.before.componentStore.state | Should -Be 'repairable'
        @($report.before.corruptComponents).Count | Should -Be 3
        $report.recommendation | Should -Be 'run-repair'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'repairs, checks again and reports before and after' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $script:Fixed } else { $script:Corrupt } }
        $report = Invoke-TuneupHealth -Repair
        $report.before.componentStore.state | Should -Be 'repairable'
        $report.repairRan | Should -BeTrue
        $report.after.componentStore.state | Should -Be 'repaired'
        @($report.after.corruptComponents).Count | Should -Be 0
        $report.recommendation | Should -Be 'none'
        $report.rebootRecommended | Should -BeTrue
        Get-TuneupHealthExitCode -Report $report | Should -Be 0
        Should -Invoke Invoke-TuneupSfc -ModuleName Tuneup -Times 2 -Exactly
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Operation -eq 'RestoreHealth' }
    }

    It 'asks for a manual repair when DISM could not fix everything' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $script:NotFixed } else { $script:Corrupt } }
        $report = Invoke-TuneupHealth -Repair
        $report.after.componentStore.state | Should -Be 'unrepairable'
        $report.recommendation | Should -Be 'manual-repair'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
    }

    It 'asks to check the logs when DISM fails' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Healthy }
        Mock -ModuleName Tuneup Invoke-TuneupDism { [pscustomobject]@{ ExitCode = 87; Output = 'Error: 87' } }
        $report = Invoke-TuneupHealth
        $report.before.componentStore.exitCode | Should -Be 87
        $report.before.componentStore.output | Should -Be 'Error: 87'
        $report.recommendation | Should -Be 'check-logs'
        Get-TuneupHealthExitCode -Report $report | Should -Be 2
    }

    It 'shows the exit code of SFC without letting it decide' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { $script:Healthy }
        Mock -ModuleName Tuneup Invoke-TuneupSfc { [pscustomobject]@{ ExitCode = 1; Output = 'Windows Resource Protection found corrupt files' } }
        $report = Invoke-TuneupHealth
        $report.before.sfc.exitCode | Should -Be 1
        $report.before.sfc.output | Should -Match 'corrupt files'
        $report.recommendation | Should -Be 'none'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL, `Invoke-TuneupHealth` no se reconoce como comando.

- [ ] **Step 3: Implementación**

Agregar al final de `engine/Health.ps1`:

```powershell
function Get-TuneupLogTime {
    # CBS.log has one-second resolution.
    $now = Get-Date
    $now.AddTicks(-($now.Ticks % [TimeSpan]::TicksPerSecond))
}

function New-TuneupHealthScan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)]$SfcRun,
        [Parameter(Mandatory)]$DismRun
    )
    $sfc = Get-TuneupSfcSummary -Lines $Lines
    $store = Get-TuneupComponentStoreSummary -Lines $Lines
    [pscustomobject]@{
        sfc               = [pscustomobject]@{
            exitCode        = $SfcRun.ExitCode
            status          = $sfc.status
            repairedFiles   = $sfc.repairedFiles
            unrepairedFiles = $sfc.unrepairedFiles
            output          = $(if ($SfcRun.ExitCode) { $SfcRun.Output } else { $null })
        }
        componentStore    = [pscustomobject]@{
            exitCode  = $DismRun.ExitCode
            state     = $store.state
            operation = $store.operation
            detected  = $store.detected
            repaired  = $store.repaired
            output    = $(if ($DismRun.ExitCode) { $DismRun.Output } else { $null })
        }
        corruptComponents = @(Get-TuneupCorruptComponentGroup -Lines $Lines)
    }
}

function Test-TuneupHealthNeedsRepair {
    param([Parameter(Mandatory)]$Scan)
    ($Scan.componentStore.state -ne 'healthy') -or ($Scan.sfc.status -eq 'unrepaired')
}

function Get-TuneupHealthRecommendation {
    param([Parameter(Mandatory)]$Scan, [switch]$RepairRan)
    $store = $Scan.componentStore.state
    $sfc = $Scan.sfc.status
    if ($store -eq 'unrepairable') { return 'manual-repair' }
    # SFC exit codes are not documented, so only DISM's decides; SFC's result comes from CBS.log.
    if ($store -eq 'unknown' -or $sfc -eq 'unknown' -or $Scan.componentStore.exitCode) { return 'check-logs' }
    if ($store -eq 'repairable' -or $sfc -eq 'unrepaired') {
        if ($RepairRan) { return 'manual-repair' }
        return 'run-repair'
    }
    'none'
}

function Invoke-TuneupHealth {
    param([switch]$Repair)
    $started = Get-TuneupLogTime
    $sfcRun = Invoke-TuneupSfc
    $dismRun = Invoke-TuneupDism -Operation 'ScanHealth'
    $scanned = Get-TuneupLogTime
    $before = New-TuneupHealthScan -Lines @(Read-TuneupCbsLog -Since $started -Until $scanned) -SfcRun $sfcRun -DismRun $dismRun
    $after = $null
    if ($Repair -and (Test-TuneupHealthNeedsRepair -Scan $before)) {
        $restoreRun = Invoke-TuneupDism -Operation 'RestoreHealth'
        $sfcAgain = Invoke-TuneupSfc
        $after = New-TuneupHealthScan -Lines @(Read-TuneupCbsLog -Since $scanned) -SfcRun $sfcAgain -DismRun $restoreRun
    }
    $final = $(if ($null -ne $after) { $after } else { $before })
    $repaired = @(@($before, $after) | Where-Object { $null -ne $_ -and ($_.sfc.status -eq 'repaired' -or $_.componentStore.state -eq 'repaired') })
    [pscustomobject]@{
        schemaVersion     = 1
        command           = 'health'
        startedAt         = $started.ToString('s')
        finishedAt        = (Get-Date).ToString('s')
        repairRequested   = [bool]$Repair
        repairRan         = ($null -ne $after)
        before            = $before
        after             = $after
        recommendation    = Get-TuneupHealthRecommendation -Scan $final -RepairRan:($null -ne $after)
        rebootRecommended = ($repaired.Count -gt 0)
    }
}

# 0: no problems left. 2: problems remain or the result could not be confirmed.
function Get-TuneupHealthExitCode {
    param([Parameter(Mandatory)]$Report)
    if ($Report.recommendation -eq 'none') { return 0 }
    2
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/Health.ps1 tests/Health.Tests.ps1
git commit -m "feat: revisión de salud con reparación opcional y recomendación"
```

---

### Task 19: Salud: reporte y `-Health`/`-Repair` en la CLI

**Files:**
- Modify: `engine/Output.ps1`, `tuneup.ps1`, `i18n/es.json`, `i18n/en.json`
- Test: `tests/Output.Tests.ps1`, `tests/Cli.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Output.Tests.ps1`:

```powershell
Describe 'Write-TuneupHealthReport' {
    BeforeAll {
        $fixtures = Join-Path $PSScriptRoot 'fixtures\cbs'
        $lines = @(Get-Content -LiteralPath (Join-Path $fixtures 'sfc-repaired.log') -Encoding UTF8) +
            @(Get-Content -LiteralPath (Join-Path $fixtures 'scanhealth-corrupt.log') -Encoding UTF8)
        $ok = [pscustomobject]@{ ExitCode = 0; Output = '' }
        $script:Scan = New-TuneupHealthScan -Lines $lines -SfcRun $ok -DismRun $ok
        $script:HealthReport = [pscustomobject]@{
            schemaVersion = 1; command = 'health'; startedAt = '2026-09-30T10:00:00'; finishedAt = '2026-09-30T10:20:00'
            repairRequested = $false; repairRan = $false; before = $Scan; after = $null
            recommendation = 'run-repair'; rebootRecommended = $true
        }
    }

    It 'explains the scan to people' {
        $text = (Write-TuneupHealthReport -Report $HealthReport 6>&1 | Out-String)
        $text | Should -Match 'SFC: found damaged files and repaired them'
        $text | Should -Match 'repaired: C:\\WINDOWS\\System32\\drivers\\BthA2dp.sys'
        $text | Should -Match 'Component store: 6 corruptions found, repairable with -Health -Repair'
        $text | Should -Match 'microsoft-windows-b\.\.ore-bootmanager-efi: 3 files'
        $text | Should -Match 'run \.\\tuneup\.ps1 -Health -Repair'
        $text | Should -Match 'Restart the computer'
    }

    It 'writes one JSON document with the warnings' {
        $json = Write-TuneupHealthReport -Report $HealthReport -Warnings @('careful') -Json | ConvertFrom-Json
        $json.command | Should -Be 'health'
        $json.before.componentStore.detected | Should -Be 6
        @($json.warnings) -join ',' | Should -Be 'careful'
    }
}
```

En `tests/Cli.Tests.ps1`, agregar estos casos al final de la lista `-TestCases` de `It 'rejects <Arguments>'`:

```powershell
        @{ Arguments = @('-Repair') }
        @{ Arguments = @('-Health', '-Status') }
        @{ Arguments = @('-Health', '-Profile', 'extra') }
        @{ Arguments = @('-Health', '-Undo', 'last') }
```

y agregar dentro de `Describe 'tuneup.ps1'`:

```powershell
    It 'refuses -Health without elevation' -Skip:$Elevated {
        $result = Invoke-Tuneup @('-Health', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be '-Health needs PowerShell as administrator.'
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: FAIL, `Write-TuneupHealthReport` no se reconoce como comando.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: FAIL en los casos nuevos: PowerShell no conoce `-Repair` ni `-Health`.

- [ ] **Step 3: Reporte**

Agregar al final de `engine/Output.ps1`:

```powershell
function Write-TuneupHealthScan {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)]$Scan)
    Write-Host $Title
    $sfcColor = $(if ($Scan.sfc.status -eq 'unrepaired' -or $Scan.sfc.status -eq 'unknown') { 'Yellow' } else { 'Gray' })
    Write-Host (Get-TuneupText -Key "health.sfc.$($Scan.sfc.status)") -ForegroundColor $sfcColor
    foreach ($file in @($Scan.sfc.repairedFiles)) { Write-Host (Get-TuneupText -Key 'health.repairedFile' -Format $file) }
    foreach ($file in @($Scan.sfc.unrepairedFiles)) { Write-Host (Get-TuneupText -Key 'health.unrepairedFile' -Format $file) -ForegroundColor Red }
    if ($Scan.sfc.output) { Write-Host (Get-TuneupText -Key 'health.toolError' -Format 'SFC', $Scan.sfc.exitCode, $Scan.sfc.output) -ForegroundColor DarkGray }
    $store = $Scan.componentStore
    $storeColor = $(if ($store.state -eq 'healthy' -or $store.state -eq 'repaired') { 'Gray' } else { 'Yellow' })
    Write-Host (Get-TuneupText -Key "health.store.$($store.state)" -Format $store.detected, $store.repaired) -ForegroundColor $storeColor
    foreach ($group in @($Scan.corruptComponents)) { Write-Host (Get-TuneupText -Key 'health.group' -Format $group.name, $group.files) }
    if ($store.output) { Write-Host (Get-TuneupText -Key 'health.toolError' -Format 'DISM', $store.exitCode, $store.output) -ForegroundColor Red }
}

function Write-TuneupHealthReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    Write-TuneupHealthScan -Title (Get-TuneupText -Key 'health.before') -Scan $Report.before
    if ($Report.repairRan) {
        Write-TuneupHealthScan -Title (Get-TuneupText -Key 'health.after') -Scan $Report.after
    } elseif ($Report.repairRequested) {
        Write-Host (Get-TuneupText -Key 'health.nothingToRepair')
    }
    Write-Host ''
    $color = $(if ($Report.recommendation -eq 'none') { 'Green' } else { 'Yellow' })
    Write-Host (Get-TuneupText -Key "health.recommendation.$($Report.recommendation)") -ForegroundColor $color
    if ($Report.rebootRecommended) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}
```

- [ ] **Step 4: CLI**

En `tuneup.ps1`:

1. Reemplazar

```powershell
    [string]$ActionsPath
)
```

por

```powershell
    [string]$ActionsPath,
    [switch]$Health,
    [switch]$Repair
)
```

2. Reemplazar

```powershell
if ($Tweak) { $present += 'Tweak' }
```

por

```powershell
if ($Tweak) { $present += 'Tweak' }
if ($Health) { $present += 'Health' }
if ($Repair) { $present += 'Repair' }
```

3. Reemplazar

```powershell
    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
```

por

```powershell
    if ($Health) {
        if (-not $environment.IsAdmin) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.healthNeedsAdmin') }
        if (-not $Json) { Write-Host (Get-TuneupText -Key 'health.running') }
        $healthReport = Invoke-TuneupStep { Invoke-TuneupHealth -Repair:$Repair }
        Write-TuneupHealthReport -Report $healthReport -Warnings $script:Warnings.ToArray() -Json:$Json
        exit (Get-TuneupHealthExitCode -Report $healthReport)
    }

    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
```

- [ ] **Step 5: Textos**

En `i18n/es.json`, antes de la llave de cierre `}` (agregar una coma al final de la línea `"undo.summary": ...`), agregar:

```json
  "err.healthNeedsAdmin": "-Health necesita PowerShell como administrador.",
  "health.running": "Revisando la salud de Windows con SFC y DISM (puede tardar 15 minutos o más)...",
  "health.before": "Revisión:",
  "health.after": "Después de reparar:",
  "health.sfc.clean": "  SFC: no encontró archivos de sistema dañados.",
  "health.sfc.repaired": "  SFC: encontró archivos dañados y los reparó.",
  "health.sfc.unrepaired": "  SFC: hay archivos dañados que no pudo reparar.",
  "health.sfc.unknown": "  SFC: no se pudo leer su resultado en CBS.log.",
  "health.repairedFile": "    reparado: {0}",
  "health.unrepairedFile": "    sin reparar: {0}",
  "health.toolError": "  {0} terminó con código {1}: {2}",
  "health.store.healthy": "  Almacén de componentes: sano.",
  "health.store.repairable": "  Almacén de componentes: {0} daños encontrados, reparables con -Health -Repair.",
  "health.store.repaired": "  Almacén de componentes: {1} de {0} daños reparados.",
  "health.store.unrepairable": "  Almacén de componentes: quedan daños sin reparar ({1} de {0} reparados).",
  "health.store.unknown": "  Almacén de componentes: no se pudo leer el resultado de DISM en CBS.log.",
  "health.group": "    {0}: {1} archivos",
  "health.nothingToRepair": "No había nada que reparar.",
  "health.recommendation.none": "Sin problemas: Windows está sano.",
  "health.recommendation.run-repair": "Hay daños reparables: ejecuta .\\tuneup.ps1 -Health -Repair (usa Windows Update como origen).",
  "health.recommendation.manual-repair": "Quedan daños que DISM no pudo reparar: usa una imagen de Windows como origen (DISM /RestoreHealth /Source) o una reparación con actualización en el mismo lugar.",
  "health.recommendation.check-logs": "No se pudo confirmar el resultado: revisa %windir%\\Logs\\CBS\\CBS.log."
```

En `i18n/en.json`, en el mismo lugar:

```json
  "err.healthNeedsAdmin": "-Health needs PowerShell as administrator.",
  "health.running": "Checking the health of Windows with SFC and DISM (it can take 15 minutes or more)...",
  "health.before": "Check:",
  "health.after": "After the repair:",
  "health.sfc.clean": "  SFC: found no damaged system files.",
  "health.sfc.repaired": "  SFC: found damaged files and repaired them.",
  "health.sfc.unrepaired": "  SFC: some damaged files could not be repaired.",
  "health.sfc.unknown": "  SFC: its result could not be read from CBS.log.",
  "health.repairedFile": "    repaired: {0}",
  "health.unrepairedFile": "    not repaired: {0}",
  "health.toolError": "  {0} ended with exit code {1}: {2}",
  "health.store.healthy": "  Component store: healthy.",
  "health.store.repairable": "  Component store: {0} corruptions found, repairable with -Health -Repair.",
  "health.store.repaired": "  Component store: {1} of {0} corruptions repaired.",
  "health.store.unrepairable": "  Component store: some corruption could not be repaired ({1} of {0} repaired).",
  "health.store.unknown": "  Component store: the DISM result could not be read from CBS.log.",
  "health.group": "    {0}: {1} files",
  "health.nothingToRepair": "There was nothing to repair.",
  "health.recommendation.none": "No problems: Windows is healthy.",
  "health.recommendation.run-repair": "There is damage that can be repaired: run .\\tuneup.ps1 -Health -Repair (it uses Windows Update as the source).",
  "health.recommendation.manual-repair": "DISM could not repair everything: use a Windows image as the source (DISM /RestoreHealth /Source) or an in-place repair upgrade.",
  "health.recommendation.check-logs": "The result could not be confirmed: check %windir%\\Logs\\CBS\\CBS.log."
```

- [ ] **Step 6: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS. Ninguna prueba de la CLI corre SFC ni DISM: en un proceso elevado la prueba de `-Health` sin elevar se omite.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18n.Tests.ps1`
Expected: PASS (mismas claves y marcadores en `es` y `en`).

- [ ] **Step 7: Commit**

```bash
git add engine/Output.ps1 tuneup.ps1 i18n/es.json i18n/en.json tests/Output.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat: comando -Health con -Repair y reporte para personas y JSON"
```

---

### Task 20: Medición: métricas y diferencias

**Files:**
- Create: `engine/Measure.ps1`
- Test: `tests/Measure.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Measure.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # Event 100 of Microsoft-Windows-Diagnostics-Performance/Operational, as Get-WinEvent returns it.
    $script:BootXml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Microsoft-Windows-Diagnostics-Performance'/><EventID>100</EventID></System><EventData><Data Name='BootTsVersion'>2</Data><Data Name='BootStartTime'>2026-09-30T14:07:58.0000000Z</Data><Data Name='BootEndTime'>2026-09-30T14:09:01.0000000Z</Data><Data Name='BootTime'>53789</Data><Data Name='MainPathBootTime'>12345</Data><Data Name='BootKernelInitTime'>21</Data></EventData></Event>"
    function New-NoEventError {
        [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('No events were found that match the specified selection criteria.'),
            'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', 'ObjectNotFound', $null)
    }
}

Describe 'Boot duration' {
    It 'reads BootTime from event 100' {
        $result = ConvertFrom-TuneupBootEvent -Xml $BootXml -Created ([datetime]'2026-09-30 11:12:00') -LastBoot ([datetime]'2026-09-30 11:07:58')
        $result.milliseconds | Should -Be 53789
        $result.reason | Should -BeNullOrEmpty
    }

    It 'ignores an event from a previous boot' {
        $result = ConvertFrom-TuneupBootEvent -Xml $BootXml -Created ([datetime]'2026-09-29 09:00:00') -LastBoot ([datetime]'2026-09-30 11:07:58')
        $result.milliseconds | Should -BeNullOrEmpty
        $result.reason | Should -Be 'not-recorded-yet'
    }

    It 'says why when BootTime is missing' {
        $xml = $BootXml -replace "<Data Name='BootTime'>53789</Data>", ''
        (ConvertFrom-TuneupBootEvent -Xml $xml -Created ([datetime]'2026-09-30 11:12:00') -LastBoot ([datetime]'2026-09-30 11:07:58')).reason | Should -Be 'unreadable'
    }

    It 'reads the latest event' {
        $record = [pscustomobject]@{ TimeCreated = [datetime]'2026-09-30 11:12:00'; Xml = $BootXml }
        $record | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
        Mock -ModuleName Tuneup Get-WinEvent { $record }.GetNewClosure()
        (Get-TuneupBootDuration -LastBoot ([datetime]'2026-09-30 11:07:58')).milliseconds | Should -Be 53789
        Should -Invoke Get-WinEvent -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilterHashtable.LogName -eq 'Microsoft-Windows-Diagnostics-Performance/Operational' -and $FilterHashtable.Id -eq 100 -and $MaxEvents -eq 1
        }
    }

    It 'asks for elevation when Windows hides the events' {
        Mock -ModuleName Tuneup Get-WinEvent { throw (New-NoEventError) }
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        (Get-TuneupBootDuration -LastBoot (Get-Date)).reason | Should -Be 'needs-admin'
    }

    It 'says there is no event when elevated' {
        Mock -ModuleName Tuneup Get-WinEvent { throw (New-NoEventError) }
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        (Get-TuneupBootDuration -LastBoot (Get-Date)).reason | Should -Be 'no-event'
    }
}

Describe 'Measure-TuneupSystem' {
    BeforeEach {
        $script:Boot = (Get-Date).AddMinutes(-90)
        $script:BootDuration = [pscustomobject]@{ milliseconds = 53789; reason = $null }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = [uint64]16777216; FreePhysicalMemory = [uint64]8388608; LastBootUpTime = $script:Boot } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        Mock -ModuleName Tuneup Get-CimInstance { [pscustomobject]@{ FreeSpace = [uint64]107374182400 } } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
        Mock -ModuleName Tuneup Get-Process { 1..150 | ForEach-Object { [pscustomobject]@{ Id = $_ } } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Running' }; [pscustomobject]@{ Status = 'Stopped' }; [pscustomobject]@{ Status = 'Running' } }
        Mock -ModuleName Tuneup Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' }; [pscustomobject]@{ State = 'Disabled' }; [pscustomobject]@{ State = 'Running' } }
        Mock -ModuleName Tuneup Get-TuneupBootDuration { $script:BootDuration }
        Mock -ModuleName Tuneup Start-Sleep { }
    }

    It 'collects the metrics without waiting by default' {
        $measurement = Measure-TuneupSystem -Environment (New-TestEnvironment)
        $measurement.schemaVersion | Should -Be 1
        $measurement.metrics.ramInUseMB | Should -Be 8192
        $measurement.metrics.processCount | Should -Be 150
        $measurement.metrics.runningServices | Should -Be 2
        $measurement.metrics.enabledTasks | Should -Be 2
        $measurement.metrics.systemDriveFreeGB | Should -Be 100
        $measurement.metrics.bootDurationMs | Should -Be 53789
        $measurement.metrics.uptimeMinutes | Should -Be 90
        $measurement.notes.bootDurationMs | Should -BeNullOrEmpty
        $measurement.environment.edition | Should -Be 'Pro'
        $measurement.metrics.PSObject.Properties.Name -join ',' | Should -Be ((Get-TuneupMetricName) -join ',')
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Get-CimInstance -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Filter -eq "DeviceID='$($env:SystemDrive)'" }
    }

    It 'waits the idle time before measuring' {
        Measure-TuneupSystem -Environment (New-TestEnvironment) -IdleSeconds 120 | Out-Null
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Seconds -eq 120 }
    }

    It 'keeps the reason when the boot duration is missing' {
        $script:BootDuration = [pscustomobject]@{ milliseconds = $null; reason = 'needs-admin' }
        $measurement = Measure-TuneupSystem -Environment (New-TestEnvironment)
        $measurement.metrics.bootDurationMs | Should -BeNullOrEmpty
        $measurement.notes.bootDurationMs | Should -Be 'needs-admin'
    }
}

Describe 'Compare-TuneupMeasurement' {
    It 'gives the difference of every metric, and none when a side is missing' {
        $before = [pscustomobject]@{ metrics = [pscustomobject]@{ ramInUseMB = 6000; processCount = 160; runningServices = 120; enabledTasks = 150; systemDriveFreeGB = 100.5; bootDurationMs = $null; uptimeMinutes = 3 } }
        $after = [pscustomobject]@{ metrics = [pscustomobject]@{ ramInUseMB = 5400; processCount = 140; runningServices = 110; enabledTasks = 130; systemDriveFreeGB = 101.25; bootDurationMs = 40000; uptimeMinutes = 2 } }
        $items = @(Compare-TuneupMeasurement -Before $before -After $after)
        ($items | ForEach-Object { $_.metric }) -join ',' | Should -Be 'ramInUseMB,processCount,runningServices,enabledTasks,systemDriveFreeGB,bootDurationMs,uptimeMinutes'
        $items[0].before | Should -Be 6000
        $items[0].after | Should -Be 5400
        $items[0].delta | Should -Be -600
        $items[4].delta | Should -Be 0.75
        $items[5].after | Should -Be 40000
        $items[5].delta | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Measure.Tests.ps1`
Expected: FAIL, `ConvertFrom-TuneupBootEvent` no se reconoce como comando.

- [ ] **Step 3: Implementación**

`engine/Measure.ps1`:

```powershell
$script:MeasureMetrics = @('ramInUseMB', 'processCount', 'runningServices', 'enabledTasks', 'systemDriveFreeGB', 'bootDurationMs', 'uptimeMinutes')

function Get-TuneupMetricName {
    foreach ($metric in $script:MeasureMetrics) { $metric }
}

function ConvertFrom-TuneupBootEvent {
    param(
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][datetime]$Created,
        [Parameter(Mandatory)][datetime]$LastBoot
    )
    # Windows writes event 100 a few minutes after startup; an older one belongs to a previous boot.
    if ($Created -lt $LastBoot) { return [pscustomobject]@{ milliseconds = $null; reason = 'not-recorded-yet' } }
    $document = [xml]$Xml
    $value = @($document.Event.EventData.Data | Where-Object { $_.GetAttribute('Name') -eq 'BootTime' } | ForEach-Object { $_.InnerText })
    $number = 0L
    if (-not $value.Count -or -not [long]::TryParse([string]$value[0], [ref]$number)) {
        return [pscustomobject]@{ milliseconds = $null; reason = 'unreadable' }
    }
    [pscustomobject]@{ milliseconds = $number; reason = $null }
}

function Get-TuneupBootDuration {
    param([Parameter(Mandatory)][datetime]$LastBoot)
    try {
        $record = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
    } catch {
        # Without elevation Windows answers "no events" instead of "access denied".
        $reason = 'unavailable'
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            $reason = $(if (Test-TuneupAdmin) { 'no-event' } else { 'needs-admin' })
        }
        return [pscustomobject]@{ milliseconds = $null; reason = $reason }
    }
    ConvertFrom-TuneupBootEvent -Xml $record.ToXml() -Created $record.TimeCreated -LastBoot $LastBoot
}

function Measure-TuneupSystem {
    param([Parameter(Mandatory)]$Environment, [int]$IdleSeconds = 0)
    if ($IdleSeconds -gt 0) { Start-Sleep -Seconds $IdleSeconds }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $now = Get-Date
    $boot = Get-TuneupBootDuration -LastBoot $os.LastBootUpTime
    [pscustomobject]@{
        schemaVersion = 1
        takenAt       = $now.ToString('s')
        idleSeconds   = $IdleSeconds
        environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
        metrics       = [pscustomobject]@{
            ramInUseMB        = [long][math]::Round(([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1024)
            processCount      = @(Get-Process).Count
            runningServices   = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { [string]$_.Status -eq 'Running' }).Count
            enabledTasks      = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { [string]$_.State -ne 'Disabled' }).Count
            systemDriveFreeGB = [math]::Round([double]$drive.FreeSpace / 1GB, 2)
            bootDurationMs    = $boot.milliseconds
            uptimeMinutes     = [long][math]::Floor(($now - $os.LastBootUpTime).TotalMinutes)
        }
        notes         = [pscustomobject]@{ bootDurationMs = $boot.reason }
    }
}

function Compare-TuneupMeasurement {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    foreach ($metric in $script:MeasureMetrics) {
        $old = $Before.metrics.$metric
        $new = $After.metrics.$metric
        $delta = $null
        if ($null -ne $old -and $null -ne $new) { $delta = [math]::Round([double]$new - [double]$old, 2) }
        [pscustomobject]@{ metric = $metric; before = $old; after = $new; delta = $delta }
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Measure.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add engine/Measure.ps1 tests/Measure.Tests.ps1
git commit -m "feat: métricas del sistema y diferencia entre mediciones"
```

---

### Task 21: Medición: guardar y buscar mediciones

**Files:**
- Modify: `engine/Measure.ps1`, `engine/StateSecurity.ps1`
- Test: `tests/Measure.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Measure.Tests.ps1`:

```powershell
Describe 'Measurement files' {
    BeforeAll {
        function New-TestMeasurement([double]$Ram) {
            [pscustomobject]@{
                schemaVersion = 1; takenAt = '2026-09-30T12:00:00'; idleSeconds = 0; environment = $null
                metrics       = [pscustomobject]@{ ramInUseMB = $Ram; processCount = 100; runningServices = 100; enabledTasks = 100; systemDriveFreeGB = 50; bootDurationMs = $null; uptimeMinutes = 5 }
                notes         = [pscustomobject]@{ bootDurationMs = 'no-event' }
            }
        }
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Stamp = '20260930-120000'
    }

    It 'saves a measurement with its id and finds it again' {
        $saved = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root
        $saved.Root | Should -Be 'custom'
        $saved.Path | Should -Be (Join-Path $Root "measurements\$($saved.Id).json")
        (Get-Content -LiteralPath $saved.Path -Raw | ConvertFrom-Json).id | Should -Be $saved.Id
        (Resolve-TuneupMeasurement -StateRoot $Root -Id 'last').Measurement.metrics.ramInUseMB | Should -Be 5000
        (Resolve-TuneupMeasurement -StateRoot $Root -Id $saved.Id).Path | Should -Be $saved.Path
        Resolve-TuneupMeasurement -StateRoot $Root -Id '19990101-000000' | Should -BeNullOrEmpty
    }

    It 'gives distinct ids within the same second and resolves last to the newest' {
        Mock -ModuleName Tuneup Get-Date { $script:Stamp } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
        $first = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root
        $second = Save-TuneupMeasurement -Measurement (New-TestMeasurement 4000) -StateRoot $Root
        $first.Id | Should -Be '20260930-120000'
        $second.Id | Should -Be '20260930-120000-02'
        $last = Resolve-TuneupMeasurement -StateRoot $Root -Id 'last'
        $last.Id | Should -Be '20260930-120000-02'
        $last.Measurement.metrics.ramInUseMB | Should -Be 4000
    }

    It 'ignores files that are not measurements and warns about unreadable ones' {
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -StateRoot $Root | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $Root 'measurements\notes.json'), '{}')
        [System.IO.File]::WriteAllText((Join-Path $Root 'measurements\20250101-000000.json'), '{ broken')
        $list = @(Get-TuneupMeasurementList -StateRoot $Root -WarningVariable warned -WarningAction SilentlyContinue)
        $list.Count | Should -Be 1
        @($warned | Where-Object { "$_" -like 'Ignoring unreadable state file *' }).Count | Should -Be 1
    }
}

Describe 'Machine measurements' {
    BeforeAll {
        function New-TestMeasurement([double]$Ram) {
            [pscustomobject]@{ schemaVersion = 1; metrics = [pscustomobject]@{ ramInUseMB = $Ram }; notes = [pscustomobject]@{} }
        }
    }

    BeforeEach {
        Use-CurrentUserAsTrusted
        Mock -ModuleName Tuneup Test-TuneupAdmin { $true }
        $script:MachineRoot = New-TestMachineRoot
        $script:UserRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Stamp = '20260930-120000'
        Mock -ModuleName Tuneup Get-Date { $script:Stamp } -ParameterFilter { $Format -eq 'yyyyMMdd-HHmmss' }
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'saves to the protected machine folder when elevated' {
        $saved = Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot
        $saved.Root | Should -Be 'machine'
        foreach ($path in (Join-Path $MachineRoot 'measurements'), $saved.Path) {
            (Get-Acl -LiteralPath $path).AreAccessRulesProtected | Should -BeTrue -Because $path
        }
        $last = Resolve-TuneupMeasurement -MachineRoot $MachineRoot -UserRoot $UserRoot -Id 'last'
        "$($last.Id)/$($last.Root)" | Should -Be '20260930-120000/machine'
    }

    It 'needs an elevated process for the machine folder' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        { Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot } | Should -Throw '*elevated*'
        Test-Path -LiteralPath $MachineRoot | Should -BeFalse
    }

    It 'lists the machine and user folders in id order' {
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot | Out-Null
        $script:Stamp = '20260930-120005'
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 4000) -UserRoot $UserRoot | Out-Null
        $list = @(Get-TuneupMeasurementList -MachineRoot $MachineRoot -UserRoot $UserRoot)
        ($list | ForEach-Object { "$($_.Id)/$($_.Root)" }) -join ',' | Should -Be '20260930-120000/machine,20260930-120005/user'
    }

    It 'ignores a machine measurements folder that others can write' {
        Save-TuneupMeasurement -Measurement (New-TestMeasurement 5000) -Machine -MachineRoot $MachineRoot | Out-Null
        $dir = Join-Path $MachineRoot 'measurements'
        Grant-EveryoneWrite $dir
        @(Get-TuneupMeasurementList -MachineRoot $MachineRoot -UserRoot $UserRoot -WarningVariable warned -WarningAction SilentlyContinue).Count | Should -Be 0
        "$($warned[0])" | Should -Be "Ignoring untrusted state folder $dir"
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Measure.Tests.ps1`
Expected: FAIL, `Save-TuneupMeasurement` no se reconoce como comando.

- [ ] **Step 3: Carpetas hijas de la carpeta de estado**

En `engine/StateSecurity.ps1`, reemplazar la función `Initialize-TuneupStateRoot` completa por:

```powershell
function Initialize-TuneupStateRoot {
    param([Parameter(Mandatory)][string]$Path, [string[]]$Children = @('runs'))
    $base = Split-Path -Parent $Path
    if (-not (Test-TuneupBaseFolder -Path $base)) {
        throw "Folder $base is not trusted to hold the machine state folder"
    }
    foreach ($folder in @($Path) + @($Children | ForEach-Object { Join-Path $Path $_ })) {
        $existed = Test-Path -LiteralPath $folder
        if (-not $existed) {
            try {
                New-TuneupSecureDirectory -Path $folder -Security (New-TuneupStateSecurity)
            }
            catch {
                if (-not (Test-Path -LiteralPath $folder)) { throw }
                $existed = $true
            }
        }
        # Checked after creating it too: someone may have made it first, even as a junction.
        # A folder someone else made is never taken over: its owner could swap it for a junction
        # between the check and Set-Acl, and the ACL would land on the junction target.
        if (-not (Test-TuneupTrustedItem -Path $folder)) {
            throw (Get-TuneupUntrustedMessage -Path $folder)
        }
        if ($existed) { Set-TuneupStateSecurity -Path $folder }
    }
}
```

- [ ] **Step 4: Mediciones en disco**

Agregar al final de `engine/Measure.ps1`:

```powershell
$script:MeasurementIdPattern = '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$'

function Save-TuneupMeasurement {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Measurement, [string]$StateRoot, [switch]$Machine, [string]$MachineRoot, [string]$UserRoot)
    # Same folders and trust rules as the runs.
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $kind = 'custom'
        $root = $StateRoot
    }
    elseif ($Machine) {
        if (-not (Test-TuneupAdmin)) { throw 'The machine state folder can only be written by an elevated process' }
        $kind = 'machine'
        $root = $(if ($MachineRoot) { $MachineRoot } else { Get-TuneupStateRoot -Machine })
        Initialize-TuneupStateRoot -Path $root -Children @('measurements')
    }
    else {
        $kind = 'user'
        $root = $(if ($UserRoot) { $UserRoot } else { Get-TuneupStateRoot })
    }
    $dir = Join-Path $root 'measurements'
    if ($kind -ne 'machine') { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    $baseId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $id = $baseId
    $counter = 1
    while (Test-Path -LiteralPath (Join-Path $dir "$id.json")) {
        $counter++
        $id = '{0}-{1:D2}' -f $baseId, $counter
    }
    $saved = $Measurement | Select-Object -Property *
    $saved | Add-Member -NotePropertyName id -NotePropertyValue $id -Force
    $path = Join-Path $dir "$id.json"
    Save-TuneupJson -Path $path -Object $saved -Root $kind
    [pscustomobject]@{ Id = $id; Path = $path; Root = $kind; Measurement = $saved }
}

function Get-TuneupMeasurementList {
    [CmdletBinding()]
    param([string]$StateRoot, [string]$MachineRoot, [string]$UserRoot)
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $roots = @([pscustomobject]@{ Kind = 'custom'; Path = $StateRoot })
    }
    else {
        if (-not $MachineRoot) { $MachineRoot = Get-TuneupStateRoot -Machine }
        if (-not $UserRoot) { $UserRoot = Get-TuneupStateRoot }
        $roots = @(
            [pscustomobject]@{ Kind = 'machine'; Path = $MachineRoot },
            [pscustomobject]@{ Kind = 'user'; Path = $UserRoot }
        )
    }
    $byKey = @{}
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $roots) {
        $dir = Join-Path $root.Path 'measurements'
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        if ($root.Kind -eq 'machine') {
            $base = Split-Path -Parent $root.Path
            $untrusted = $null
            if (-not (Test-TuneupBaseFolder -Path $base)) { $untrusted = $base }
            else { $untrusted = @($root.Path, $dir) | Where-Object { -not (Test-TuneupTrustedItem -Path $_) } | Select-Object -First 1 }
            if ($untrusted) {
                Write-Warning "Ignoring untrusted state folder $untrusted"
                continue
            }
        }
        foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
            if ($file.BaseName -cnotmatch $script:MeasurementIdPattern) { continue }
            $data = Read-TuneupTrustedJson -Path $file.FullName -Root $root.Kind
            if ($null -eq $data) { continue }
            # A space sorts before '-', so '20250101-000000' stays ahead of '20250101-000000-02'.
            $key = $file.BaseName + ' ' + $root.Kind
            $byKey[$key] = [pscustomobject]@{ Id = $file.BaseName; Path = $file.FullName; Root = $root.Kind; Measurement = $data }
            $keys.Add($key)
        }
    }
    $keys.Sort([System.StringComparer]::Ordinal)
    foreach ($key in $keys) { $byKey[$key] }
}

function Resolve-TuneupMeasurement {
    [CmdletBinding()]
    param([string]$StateRoot, [string]$MachineRoot, [string]$UserRoot, [Parameter(Mandatory)][string]$Id)
    $all = @(Get-TuneupMeasurementList -StateRoot $StateRoot -MachineRoot $MachineRoot -UserRoot $UserRoot)
    if ($Id -eq 'last') {
        if ($all.Count) { return $all[-1] }
        return
    }
    $all | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Measure.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StateSecurity.Tests.ps1`
Expected: PASS (`Initialize-TuneupStateRoot` sin `-Children` sigue creando `runs`).

- [ ] **Step 6: Commit**

```bash
git add engine/Measure.ps1 engine/StateSecurity.ps1 tests/Measure.Tests.ps1
git commit -m "feat: mediciones guardadas con las reglas de confianza de las corridas"
```

---

### Task 22: Medición: reporte y `-Measure`/`-Compare`/`-IdleSeconds` en la CLI

**Files:**
- Modify: `engine/Output.ps1`, `tuneup.ps1`, `i18n/es.json`, `i18n/en.json`
- Test: `tests/Output.Tests.ps1`, `tests/Cli.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Output.Tests.ps1`:

```powershell
Describe 'Write-TuneupMeasureReport' {
    BeforeAll {
        $before = [pscustomobject]@{ metrics = [pscustomobject]@{ ramInUseMB = 6000; processCount = 160; runningServices = 120; enabledTasks = 150; systemDriveFreeGB = 100.5; bootDurationMs = $null; uptimeMinutes = 3 } }
        $measurement = [pscustomobject]@{
            schemaVersion = 1; takenAt = '2026-09-30T12:00:00'; idleSeconds = 120; environment = $null; id = '20260930-120000'
            metrics = [pscustomobject]@{ ramInUseMB = 5400; processCount = 140; runningServices = 110; enabledTasks = 130; systemDriveFreeGB = 101.25; bootDurationMs = $null; uptimeMinutes = 2 }
            notes = [pscustomobject]@{ bootDurationMs = 'needs-admin' }
        }
        $saved = [pscustomobject]@{ Id = '20260930-120000'; Path = 'C:\state\measurements\20260930-120000.json'; Root = 'custom'; Measurement = $measurement }
        $against = [pscustomobject]@{ Id = '20260929-090000'; Measurement = $before }
        $script:MeasureReport = New-TuneupMeasureReport -Saved $saved -Against $against
    }

    It 'builds the report with the comparison' {
        $MeasureReport.command | Should -Be 'measure'
        $MeasureReport.id | Should -Be '20260930-120000'
        $MeasureReport.comparison.againstId | Should -Be '20260929-090000'
        @($MeasureReport.comparison.items).Count | Should -Be 7
    }

    It 'shows the metrics, the reason for a missing one and the differences' {
        $text = (Write-TuneupMeasureReport -Report $MeasureReport 6>&1 | Out-String)
        $text | Should -Match 'RAM in use \(MB\): 5400'
        $text | Should -Match 'Last boot duration \(ms\): needs administrator'
        $text | Should -Match 'Difference from measurement 20260929-090000'
        $text | Should -Match 'RAM in use \(MB\): 6000 -> 5400 \(-600\)'
        $text | Should -Match 'Last boot duration \(ms\): n/a -> n/a \(n/a\)'
    }

    It 'writes one JSON document with the warnings' {
        $json = Write-TuneupMeasureReport -Report $MeasureReport -Warnings @('careful') -Json | ConvertFrom-Json
        $json.command | Should -Be 'measure'
        $json.measurement.metrics.ramInUseMB | Should -Be 5400
        @($json.warnings) -join ',' | Should -Be 'careful'
    }
}
```

En `tests/Cli.Tests.ps1`, agregar estos casos al final de la lista `-TestCases` de `It 'rejects <Arguments>'`:

```powershell
        @{ Arguments = @('-Compare', 'last') }
        @{ Arguments = @('-IdleSeconds', '5') }
        @{ Arguments = @('-Measure', '-Status') }
        @{ Arguments = @('-Measure', '-Yes') }
```

y agregar dentro de `Describe 'tuneup.ps1'`:

```powershell
    It 'measures, saves and compares against the last measurement' {
        $first = Invoke-Tuneup @('-Measure', '-Json')
        $first.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $first.Output
        $json.command | Should -Be 'measure'
        $json.comparison | Should -BeNullOrEmpty
        $json.measurement.metrics.processCount | Should -BeGreaterThan 0
        $json.PSObject.Properties.Name | Should -Contain 'warnings'
        Test-Path -LiteralPath $json.path | Should -BeTrue
        $second = ConvertFrom-PureJson (Invoke-Tuneup @('-Measure', '-Compare', 'last', '-Json')).Output
        $second.comparison.againstId | Should -Be $json.id
        @($second.comparison.items).Count | Should -Be 7
    }

    It 'says when the measurement to compare does not exist' {
        $result = Invoke-Tuneup @('-Measure', '-Compare', '19990101-000000', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'Measurement 19990101-000000 does not exist.'
    }

    It 'prints a measurement for people in the chosen language' {
        $result = Invoke-Tuneup @('-Measure') -Lang 'es'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Procesos: \d+'
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: FAIL, `New-TuneupMeasureReport` no se reconoce como comando.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: FAIL en los casos nuevos: PowerShell no conoce `-Measure`, `-Compare` ni `-IdleSeconds`.

- [ ] **Step 3: Reporte**

Agregar al final de `engine/Output.ps1`:

```powershell
function New-TuneupMeasureReport {
    param([Parameter(Mandatory)]$Saved, [AllowNull()]$Against)
    $comparison = $null
    if ($null -ne $Against) {
        $comparison = [pscustomobject]@{
            againstId = $Against.Id
            items     = @(Compare-TuneupMeasurement -Before $Against.Measurement -After $Saved.Measurement)
        }
    }
    [pscustomobject]@{
        schemaVersion = 1
        command       = 'measure'
        id            = $Saved.Id
        path          = $Saved.Path
        measurement   = $Saved.Measurement
        comparison    = $comparison
    }
}

function Format-TuneupMetric {
    param([AllowNull()]$Value, [switch]$Signed)
    if ($null -eq $Value) { return (Get-TuneupText -Key 'measure.none') }
    if ($Signed) { return ('{0:+0.##;-0.##;0}' -f [double]$Value) }
    '{0:0.##}' -f [double]$Value
}

function Write-TuneupMeasureReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $metrics = $Report.measurement.metrics
    Write-Host (Get-TuneupText -Key 'measure.header' -Format $Report.id)
    foreach ($metric in @(Get-TuneupMetricName)) {
        $value = Format-TuneupMetric -Value $metrics.$metric
        $note = $Report.measurement.notes.$metric
        if ($null -eq $metrics.$metric -and $note) { $value = Get-TuneupText -Key "measure.reason.$note" }
        Write-Host (Get-TuneupText -Key 'measure.line' -Format (Get-TuneupText -Key "metric.$metric"), $value)
    }
    Write-Host (Get-TuneupText -Key 'measure.saved' -Format $Report.path)
    if ($null -eq $Report.comparison) { return }
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'measure.compareHeader' -Format $Report.comparison.againstId)
    foreach ($item in $Report.comparison.items) {
        Write-Host (Get-TuneupText -Key 'measure.delta' -Format (Get-TuneupText -Key "metric.$($item.metric)"),
            (Format-TuneupMetric -Value $item.before), (Format-TuneupMetric -Value $item.after), (Format-TuneupMetric -Value $item.delta -Signed))
    }
}
```

- [ ] **Step 4: CLI**

En `tuneup.ps1`:

1. Reemplazar

```powershell
    [switch]$Health,
    [switch]$Repair
)
```

por

```powershell
    [switch]$Health,
    [switch]$Repair,
    [switch]$Measure,
    [string]$Compare,
    [ValidateRange(0, 3600)][int]$IdleSeconds = 0
)
```

2. Reemplazar

```powershell
if ($Repair) { $present += 'Repair' }
```

por

```powershell
if ($Repair) { $present += 'Repair' }
if ($Measure) { $present += 'Measure' }
if ($Compare) { $present += 'Compare' }
if ($PSBoundParameters.ContainsKey('IdleSeconds')) { $present += 'IdleSeconds' }
```

3. Reemplazar

```powershell
    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
```

por

```powershell
    if ($Measure) {
        # Resolved before measuring, so 'last' is never the new measurement.
        $against = $null
        if ($Compare) {
            $against = Invoke-TuneupStep { Resolve-TuneupMeasurement -StateRoot $StateRoot -Id $Compare }
            if (-not $against) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.measurementNotFound' -Format $Compare) }
        }
        if ($IdleSeconds -gt 0 -and -not $Json) { Write-Host (Get-TuneupText -Key 'measure.waiting' -Format $IdleSeconds) }
        $measurement = Invoke-TuneupStep { Measure-TuneupSystem -Environment $environment -IdleSeconds $IdleSeconds }
        $saved = Invoke-TuneupStep { Save-TuneupMeasurement -Measurement $measurement -StateRoot $StateRoot -Machine:$environment.IsAdmin }
        Write-TuneupMeasureReport -Report (New-TuneupMeasureReport -Saved $saved -Against $against) -Warnings $script:Warnings.ToArray() -Json:$Json
        exit 0
    }

    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
```

- [ ] **Step 5: Textos**

En `i18n/es.json`, agregar una coma al final de la línea `"health.recommendation.check-logs": ...` y después:

```json
  "err.measurementNotFound": "No existe la medición {0}.",
  "measure.waiting": "Esperando {0} segundos en reposo antes de medir...",
  "measure.header": "Medición {0}:",
  "measure.line": "  {0}: {1}",
  "measure.saved": "Guardada en {0}.",
  "measure.compareHeader": "Diferencia con la medición {0}:",
  "measure.delta": "  {0}: {1} -> {2} ({3})",
  "measure.none": "s/d",
  "measure.reason.needs-admin": "requiere administrador",
  "measure.reason.no-event": "Windows no lo registró",
  "measure.reason.not-recorded-yet": "Windows todavía no lo registra para este arranque",
  "measure.reason.unreadable": "no se pudo leer",
  "measure.reason.unavailable": "no disponible",
  "metric.ramInUseMB": "RAM en uso (MB)",
  "metric.processCount": "Procesos",
  "metric.runningServices": "Servicios en ejecución",
  "metric.enabledTasks": "Tareas programadas habilitadas",
  "metric.systemDriveFreeGB": "Espacio libre en el disco del sistema (GB)",
  "metric.bootDurationMs": "Duración del último arranque (ms)",
  "metric.uptimeMinutes": "Minutos desde el arranque"
```

En `i18n/en.json`, en el mismo lugar:

```json
  "err.measurementNotFound": "Measurement {0} does not exist.",
  "measure.waiting": "Waiting {0} seconds idle before measuring...",
  "measure.header": "Measurement {0}:",
  "measure.line": "  {0}: {1}",
  "measure.saved": "Saved in {0}.",
  "measure.compareHeader": "Difference from measurement {0}:",
  "measure.delta": "  {0}: {1} -> {2} ({3})",
  "measure.none": "n/a",
  "measure.reason.needs-admin": "needs administrator",
  "measure.reason.no-event": "Windows did not record it",
  "measure.reason.not-recorded-yet": "Windows has not recorded it for this boot yet",
  "measure.reason.unreadable": "could not be read",
  "measure.reason.unavailable": "not available",
  "metric.ramInUseMB": "RAM in use (MB)",
  "metric.processCount": "Processes",
  "metric.runningServices": "Running services",
  "metric.enabledTasks": "Enabled scheduled tasks",
  "metric.systemDriveFreeGB": "Free space on the system drive (GB)",
  "metric.bootDurationMs": "Last boot duration (ms)",
  "metric.uptimeMinutes": "Minutes since boot"
```

- [ ] **Step 6: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: PASS.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS. `-Measure` solo lee el sistema y guarda en la carpeta `-StateRoot` de la prueba.

- [ ] **Step 7: Commit**

```bash
git add engine/Output.ps1 tuneup.ps1 i18n/es.json i18n/en.json tests/Output.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat: comando -Measure con -Compare e -IdleSeconds"
```

---

### Task 23: README, especificación, lint y suite completa

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`, `build/lint.ps1`

- [ ] **Step 1: Lint también para `actions/`**

En `build/lint.ps1`, reemplazar:

```powershell
$targets = @(
    (Join-Path $root 'tuneup.ps1'),
    (Join-Path $root 'engine'),
    (Join-Path $root 'build')
) | Where-Object { Test-Path -LiteralPath $_ }
```

por:

```powershell
$targets = @(
    (Join-Path $root 'tuneup.ps1'),
    (Join-Path $root 'engine'),
    (Join-Path $root 'actions'),
    (Join-Path $root 'build')
) | Where-Object { Test-Path -LiteralPath $_ }
```

- [ ] **Step 2: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`. Si aparece un hallazgo, corregirlo en el archivo que indica (sin excluir reglas) y volver a correr.

- [ ] **Step 3: README**

Reemplazar `README.md` completo por:

````markdown
# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> Estado: en desarrollo (Planes 1 y 2: motor, manejadores, salud y medición). El catálogo real llega en el Plan 3. No usar todavía en equipos reales.
> Status: work in progress (Plans 1 and 2: engine, handlers, health and measurement). The real catalog comes in Plan 3. Do not use on real machines yet.

## Requisitos / Requirements

- Windows 10 u 11 con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1.
- Windows 10 or 11 with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1.
- Los ajustes de sistema necesitan PowerShell como administrador. Sin elevar, un plan que contenga cualquier cambio de sistema se rechaza completo (no se aplica nada): usar `-Exclude` para dejar fuera esos ajustes o abrir PowerShell como administrador. El perfil `base` incluye un ajuste de servicio, así que aplicarlo exige administrador (o `-Exclude services.retail-demo`). Solo los ajustes de registro de usuario (`HKCU`) se aplican sin elevar.
- System-wide tweaks need PowerShell as administrator. Without elevation, a plan that contains any system-level change is refused entirely (nothing is applied): use `-Exclude` to leave those tweaks out or open PowerShell as administrator. The `base` profile includes a service tweak, so applying it requires administrator (or `-Exclude services.retail-demo`). Only user registry tweaks (`HKCU`) apply without elevation.
- `-Health` necesita administrador. Deshacer la quita de una app de la Store usa `winget` (App Installer).
- `-Health` needs administrator. Undoing the removal of a Store app uses `winget` (App Installer).

## Uso / Usage

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base -WhatIf   # ver el plan / show the plan
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base,privacy   # aplicar / apply
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Status                 # estado / status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Undo last              # deshacer / undo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Health                 # SFC + DISM (administrador / administrator)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Health -Repair         # + DISM /RestoreHealth si hace falta / if needed
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Measure -IdleSeconds 120                 # medir / measure
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Measure -IdleSeconds 120 -Compare last   # comparar / compare
```

`-ExecutionPolicy Bypass` solo afecta a ese proceso y permite ejecutar el script aunque la política de PowerShell sea `Restricted`; no cambia la configuración del equipo.
`-ExecutionPolicy Bypass` only affects that process and lets the script run even if the PowerShell policy is `Restricted`; it does not change the machine configuration.

## Qué hace hoy / What works today

- Tipos de ajuste: registro, servicios, tareas programadas, apps de la Store (`appx`), capacidades y características opcionales de Windows, planes y valores de energía (`powercfg`) y acciones en PowerShell. Los perfiles `base` y `privacy` todavía traen solo 5 ajustes de ejemplo.
  Tweak types: registry, services, scheduled tasks, Store apps (`appx`), Windows capabilities and optional features, power schemes and settings (`powercfg`) and PowerShell actions. The `base` and `privacy` profiles still ship only 5 sample tweaks.
- `-WhatIf` muestra el plan con el motivo de cada omisión (ya aplicado, versión o edición no compatible, equipo administrado...). Sin elevar, lo que solo se puede leer como administrador (apps, capacidades, características) aparece como "se comprueba al aplicar". No cambia nada.
  `-WhatIf` shows the plan with the reason for every skipped tweak (already applied, unsupported version or edition, managed machine...). Without elevation, what can only be read as administrator (apps, capabilities, features) shows as "checked when applied". It changes nothing.
- Antes de tocar un ajuste guarda su valor anterior. Con administrador la corrida queda en `%ProgramData%\windows-tuneup\runs\` (carpeta protegida); sin elevar, en `%LOCALAPPDATA%\windows-tuneup\runs\` (solo ajustes de usuario).
  Before touching a tweak it saves the previous value. Elevated, the run goes to `%ProgramData%\windows-tuneup\runs\` (hardened folder); otherwise to `%LOCALAPPDATA%\windows-tuneup\runs\` (user-level tweaks only).
- Un ajuste que cambió algo pero no pudo terminar (por ejemplo, un servicio deshabilitado que no se pudo detener) se informa como parcial, con la explicación.
  A tweak that changed something but could not finish (for example, a service that was disabled but could not be stopped) is reported as partial, with the explanation.
- `-Undo last` o `-Undo <id> -Tweak <ajuste>` devuelve el valor anterior. Una app de la Store se reinstala con `winget` para el usuario actual (no se vuelve a provisionar para usuarios nuevos, y su versión puede cambiar). Una corrida ya deshecha no se deshace dos veces.
  `-Undo last` or `-Undo <id> -Tweak <tweak>` restores the previous value. A Store app is reinstalled with `winget` for the current user (it is not provisioned again for new users, and its version may change). A run that was already undone is not undone twice.
- `-Status` muestra qué sigue aplicado y qué revirtió Windows. `-Status` y `-Undo` no dependen del catálogo: funcionan con lo guardado en la corrida.
  `-Status` shows what is still applied and what Windows reverted. `-Status` and `-Undo` do not depend on the catalog: they work from what the run saved.
- `-Health` corre `sfc /scannow` y `DISM /ScanHealth` y resume lo que dejaron en `CBS.log`: archivos reparados o sin reparar, estado del almacén de componentes y componentes dañados agrupados. `-Health -Repair` corre además `DISM /RestoreHealth` y SFC otra vez, solo si hace falta, y muestra antes y después.
  `-Health` runs `sfc /scannow` and `DISM /ScanHealth` and summarizes what they left in `CBS.log`: repaired and unrepaired files, component store state and damaged components grouped. `-Health -Repair` also runs `DISM /RestoreHealth` and SFC again, only when needed, and shows before and after.
- `-Measure` guarda RAM en uso, procesos, servicios en ejecución, tareas programadas habilitadas, espacio libre del disco del sistema, duración del último arranque y tiempo desde el arranque; `-Compare <id|last>` muestra la diferencia con una medición anterior.
  `-Measure` saves RAM in use, processes, running services, enabled scheduled tasks, free space on the system drive, last boot duration and time since boot; `-Compare <id|last>` shows the difference from an earlier measurement.
- `-Json` para automatización: un único documento JSON por la salida estándar, con claves en camelCase, `warnings` (los avisos van dentro del documento) y `requiresAdmin` en el plan. Para aplicar sin preguntar usar `-Yes`.
  `-Json` for automation: a single JSON document on standard output, camelCase keys, `warnings` (warnings are carried inside the document) and `requiresAdmin` in the plan. To apply without asking use `-Yes`.
- Códigos de salida: 0 (todo hecho), 2 (no todo se completó: algún ajuste parcial, fallido o sin efecto; leer el resumen), 1 (abortado antes de cambiar nada; al deshacer, nada se restauró). En `-Health`: 0 sin problemas, 2 quedan problemas o no se pudo confirmar, 1 sin administrador.
  Exit codes: 0 (everything done), 2 (not everything was completed: some tweak was partial, failed or had no effect; read the summary), 1 (aborted before changing anything; for undo, nothing was restored). For `-Health`: 0 no problems, 2 problems remain or could not be confirmed, 1 not elevated.
- Idioma con `-Lang es|en`.
  Language with `-Lang es|en`.

## Cómo medir / How to measure

1. Reiniciar, iniciar sesión y correr `-Measure -IdleSeconds 120`: espera dos minutos en reposo antes de medir. Como administrador también se lee la duración del arranque.
   Restart, sign in and run `-Measure -IdleSeconds 120`: it waits two minutes idle before measuring. As administrator it also reads the boot duration.
2. Aplicar los perfiles, reiniciar y correr `-Measure -IdleSeconds 120 -Compare last`.
   Apply the profiles, restart and run `-Measure -IdleSeconds 120 -Compare last`.

Las mediciones quedan en `measurements\` dentro de la misma carpeta de estado que las corridas.
Measurements are kept in `measurements\` inside the same state folder as the runs.

## Desarrollo / Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build\test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File build\lint.ps1
```

Las pruebas usan Pester 5 y el lint PSScriptAnalyzer. Las pruebas no tocan el sistema: Appx, DISM, winget, powercfg, sfc y el visor de eventos se simulan. `-StateRoot` y `-ActionsPath` son solo para pruebas y desarrollo.
Tests use Pester 5 and lint uses PSScriptAnalyzer. Tests do not touch the system: Appx, DISM, winget, powercfg, sfc and the event log are mocked. `-StateRoot` and `-ActionsPath` are for testing and development only.

Licencia / License: MIT
````

- [ ] **Step 4: Especificación: parámetros, medición y códigos de salida**

En `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`:

1. En la tabla de parámetros, reemplazar las filas

```markdown
| `-Health` | SFC + DISM `/ScanHealth` y, si hay daño, ofrece `/RestoreHealth` |
| `-Measure [-Compare <runId>]` | Métricas y comparación |
```

por

```markdown
| `-Health [-Repair]` | SFC + DISM `/ScanHealth` con resumen leído de CBS.log; con `-Repair`, DISM `/RestoreHealth` y SFC otra vez si hace falta. Requiere administrador |
| `-Measure [-Compare <id\|last>] [-IdleSeconds <n>]` | Métricas guardadas en `measurements\` y diferencia con una medición anterior |
```

2. Reemplazar el párrafo que empieza con "Combinaciones que no tienen sentido se rechazan" (cuatro líneas) por:

```markdown
Combinaciones que no tienen sentido se rechazan antes de leer nada (código `1`): `-Status`,
`-Undo`, `-Health` y `-Measure` se excluyen entre sí y ninguno va junto a `-Profile`,
`-Include`, `-Exclude`, `-WhatIf` o `-Yes`; `-Tweak` exige `-Undo`, `-Repair` exige `-Health`, y
`-Compare` e `-IdleSeconds` exigen `-Measure`. Las rutas relativas de `-StateRoot`, `-CatalogPath`,
`-ProfilesPath` y `-ActionsPath` se resuelven contra la ubicación actual de PowerShell.
`-ActionsPath <carpeta>`, como `-StateRoot`, es solo para pruebas y desarrollo: carga acciones de
otra carpeta.
```

3. En la sección "Medición", reemplazar la línea

```markdown
`-Compare` muestra la diferencia contra una medición anterior.
```

por

```markdown
`-IdleSeconds <n>` espera antes de medir. Cada medición se guarda en `measurements\<id>.json`
dentro de la carpeta de estado, con las mismas reglas que las corridas. `-Compare <id|last>`
muestra la diferencia contra una medición anterior. Si la duración del arranque no se puede leer
(sin administrador, sin evento o evento de un arranque anterior), queda vacía con el motivo.
```

4. En la sección 7, después de la línea que termina en "ajustes de otro usuario), `1` nada restaurado.", agregar:

```markdown
  En `-Health`: `0` sin problemas, `2` quedan problemas o no se pudo confirmar el resultado, `1`
  no se pudo empezar (sin administrador). `-Measure`: `0`, o `1` si no pudo medir o guardar. Un
  ajuste `partial` cuenta como no completado (`2`).
```

- [ ] **Step 5: Suite completa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`).

- [ ] **Step 6: Commit**

```bash
git add README.md docs/superpowers/specs/2026-09-30-windows-tuneup-design.md build/lint.ps1
git commit -m "docs: README y especificación del Plan 2"
```

---

## Autorrevisión

**Cobertura de lo pedido (alcance y decisiones 0 a 11):**

| Punto | Dónde |
|---|---|
| 0. Adenda en el plan y en la especificación | Sección "Adenda de diseño" y Task 1 |
| 1. Contrato de `Set` y `partial` (servicio que no se detiene, resumen, JSON, código 2, `-Status`) | Tasks 3 y 4; `README` y especificación en la Task 23 |
| 2. Prueba de registro de manejadores y tabla única | Task 2 (prueba `Handler registry`); cada manejador nuevo agrega su línea |
| 3. `appx` (machine, campos, estado, aplicado si no está, partial, winget, motivos, validación) | Tasks 7 y 8; motivos de deshacer en la Task 5 |
| 4. `capability` (estado, quitar/agregar, reinstalar con error visible, `RestartNeeded`) | Task 10 |
| 5. `feature` (`-NoRestart`, `DisabledWithPayloadRemoved`, `RestartNeeded`) | Task 11 |
| 6. `powercfg` (scheme y setting, registro verificado, `/q` descartado, envoltorio, códigos de salida) | Tasks 12 y 13 |
| 7. `action` (cuatro funciones, PascalName, cargador, validación, acción de prueba, ruta inyectable) | Tasks 14 y 15 |
| 8. Regla de la carpeta de usuario documentada y probada para los tipos nuevos | Adenda punto 8; casos nuevos en `tests/StateFiles.Tests.ps1` (Task 14) |
| 9. `-Health` (administrador, envoltorios, CBS.log, extractos reales, `-Repair`, JSON `health`) | Tasks 16 a 19 |
| 10. `-Measure`/`-Compare` (métricas, evento 100, `-IdleSeconds`, carpetas confiables, diferencia pura, JSON `measure`) | Tasks 20 a 22 |
| 11. CLI, README, especificación, i18n y códigos de salida | Tasks 15, 19, 22 y 23 |

Además: `Invoke-TuneupNative` (Task 6) corrige el corte por la salida de errores que también afectaba a `sc.exe`, y el estado que solo se lee elevado (Task 9) evita que un `-WhatIf` sin elevar muestre todas las apps como "no se pudo leer".

**Búsqueda de marcadores pendientes:** no quedan "TBD", "TODO", "similar a la Task N" ni pasos sin código. Cada paso que modifica un archivo existente da el texto exacto a reemplazar o la función completa.

**Consistencia de nombres y tipos (revisado contra el código de `main`):**

- Contrato: `Get-<Tipo>TweakState`, `Test-<Tipo>TweakState`, `Set-<Tipo>TweakDesired`, `Restore-<Tipo>TweakState`, `Test-<Tipo>TweakDefinition` con `<Tipo>` = `Registry`, `Service`, `Task`, `Appx`, `Capability`, `Feature`, `Powercfg`, `Action`; la tabla de `Dispatch.ps1` usa esos mismos nombres y la prueba de registro lo exige.
- `New-TuneupOutcome` (campos `partial`, `detail`, `rebootRequired`, `reason`) lo emiten `Service`, `Appx`, `Capability`, `Feature`, `Powercfg` y la acción de prueba; `Get-TuneupOutcome` lo leen `Invoke-TuneupPlan` e `Invoke-TuneupUndo`.
- Resultados de aplicar: `id, title, status, reason, error, detail, rebootRequired`; de deshacer: los mismos campos. `summary` de aplicar: `applied, partial, notApplied, failed, skipped, journalErrors`, en ese orden en `New-TuneupApplyReport`, en el texto `summary` (cinco marcadores) y en `Get-TuneupApplyExitCode`.
- Estados de `-Status`: `ok`, `drift`, `not-present`, `unknown`, `needs-admin`, todos con clave `status.*` en los dos idiomas. Motivos nuevos con clave `reason.*`: `unverified-needs-admin`, `reinstalled`, `not-reprovisioned`.
- Envoltorios simulados en las pruebas y definidos en el código: `Get-TuneupAppxPackage`, `Get-TuneupAppxProvisionedPackage`, `Remove-TuneupAppxPackage`, `Remove-TuneupAppxProvisionedPackage`, `Test-TuneupAppxInstalledForCurrentUser`, `Get-TuneupWingetPath`, `Invoke-TuneupWinget`, `Get-TuneupWindowsCapability`, `Add-/Remove-TuneupWindowsCapability`, `Get-TuneupWindowsOptionalFeature`, `Enable-/Disable-TuneupWindowsOptionalFeature`, `Invoke-TuneupPowercfg`, `Invoke-TuneupNative`, `Invoke-TuneupSfc`, `Invoke-TuneupDism`, `Invoke-TuneupHealthTool`, `Read-TuneupCbsLog`, `Get-TuneupBootDuration`.
- Claves i18n nuevas, con los mismos marcadores en `es` y `en`: `status.partial`, `summary` ({0}-{4}), `reason.reinstalled`, `reason.not-reprovisioned`, `reason.unverified-needs-admin`, `status.needs-admin`, `err.actionsPathMissing` ({0}), `err.healthNeedsAdmin`, `health.*`, `err.measurementNotFound` ({0}), `measure.*`, `metric.*`. Las pruebas de `tests/I18n.Tests.ps1` las verifican en cada tarea que las agrega.
- Parámetros de la CLI y la función pura usan los mismos nombres: `Profile`, `Include`, `Exclude`, `WhatIf`, `Yes`, `Status`, `Undo`, `Tweak`, `Health`, `Repair`, `Measure`, `Compare`, `IdleSeconds`.

**Correcciones hechas durante la revisión:** la prueba de parámetros fuera de `param()` arma el archivo completo en vez de usar `-replace` (en un reemplazo de .NET, `$_` y otros `$` tienen significado); un archivo de acción llamado `tuneup.ps1` podía definir `Get-TuneupActionCommand` y reemplazar una función del motor, así que los nombres que empiezan con `tuneup` quedan reservados (y probado); el código de salida de SFC no está documentado, así que se muestra pero no decide la recomendación; `Initialize-TuneupStateRoot` se reemplaza completa porque su línea `param(...)` se repite en `Get-TuneupUntrustedMessage`; las pruebas cambian el comportamiento de un `Mock` con variables `$script:` o definiendo otro `Mock` dentro del `It`, que en Pester 5.9.1 gana sobre el del `BeforeEach` (verificado).
