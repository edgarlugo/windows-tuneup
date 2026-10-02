# windows-tuneup — Plan 4: menú interactivo, avisos antes de aplicar, distribución y prueba de extremo a extremo

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que `windows-tuneup` se pueda usar sin conocer sus parámetros (menú en consola, en español e inglés, solo con teclado) y que se pueda publicar: avisos antes de aplicar (reinicio pendiente, poco disco, Restaurar sistema desactivado, equipo administrado), Ctrl+C limpio, `transcript.log` por corrida, `-Status -Reapply`, instrucciones para deshacer a mano, `toolVersion` en el JSON, un instalador que verifica el SHA256, un workflow de release, una pata de CI sin elevar y la prueba de extremo a extremo de cada perfil en Windows Sandbox.

**Architecture:** La orquestación sale de `tuneup.ps1` a `engine/Commands.ps1`: cada comando (`Invoke-TuneupApplyCommand`, `-Status`, `-Undo`, `-Health`, `-Measure`) recibe un contexto (`New-TuneupContext`), escribe su reporte y deja el código de salida en el contexto; la línea de comandos (`Invoke-TuneupCli`) y el menú (`engine/Menu.ps1`) los comparten. Las preguntas pasan por un objeto `Io` (`engine/Io.ps1`: `Read-Host` en la consola, respuestas guionadas en las pruebas). Lo nuevo vive en archivos propios del motor: `Version.ps1`, `ManualHint.ps1`, `Interrupt.ps1`, `Transcript.ps1`, `Preflight.ps1`. La distribución es `install.ps1` en la raíz, `build/package.ps1` y `.github/workflows/release.yml`; la prueba de extremo a extremo vive en `tests/sandbox/`.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.9.1, PSScriptAnalyzer 1.25, GitHub Actions (`windows-latest`) y GitHub CLI (`gh`) en el workflow de release, Windows Sandbox (manual).

**Especificación:** `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md` (la Task 1 le agrega la sección 12, "Menú, avisos y distribución").

**Planes anteriores:** `docs/superpowers/plans/2026-09-30-plan-1-motor-nucleo.md`, `docs/superpowers/plans/2026-09-30-plan-2-manejadores-salud-medicion.md` y `docs/superpowers/plans/2026-10-01-plan-3-catalogo-perfiles.md`. Como dicen sus encabezados, **los archivos del repositorio son la fuente de verdad**. Este plan se escribió leyendo `feat/plan-3` (`db1bcf0`, PR #2) y se ejecuta sobre `main` después de mergear ese PR.

**Evidencia:** todo el código de este plan se ejecutó en una copia del repositorio (`feat/plan-3`, `db1bcf0`) en un Windows 11 Pro 26H2 (build 26300) **sin elevar**, aplicando las tareas en orden; el texto de cada archivo de este plan se generó desde esa copia y se comprobó que aplicar las tareas sobre `db1bcf0` da exactamente esos archivos. Resultado sobre esa copia rearmada desde el plan: suite completa en verde (`Tests Passed: 1178, Failed: 0, Skipped: 1`) y PSScriptAnalyzer sin hallazgos. Lo que se probó de verdad y lo que queda sin verificar está en la sección final "Qué se probó y qué no".

---

## Convenciones de este plan

Se heredan las de los Planes 1 a 3:

- **Código, comentarios, identificadores y errores para desarrolladores en inglés.** Los textos para el usuario van en `i18n/es.json` e `i18n/en.json` (mismas claves y marcadores `{n}`; lo verifica `tests/I18n.Tests.ps1`), y toda clave, motivo o estado que nombra el código debe tener texto en los dos idiomas (`tests/I18nCoverage.Tests.ps1`).
- **Todo `.ps1`/`.psm1`/`.psd1` en ASCII** (`tests/Repo.Tests.ps1`). Los `.json`, `.md`, `.yml` y `.wsb` van en UTF-8 sin BOM. Fin de línea CRLF (`.gitattributes`; `git add` normaliza lo que el editor escriba).
- **Las funciones emiten elementos; quien llama envuelve con `@()`.** `ConvertTo-Json` siempre con `-Depth 10`. Comparaciones con null: `$null -eq $x`.
- **Los fallos se lanzan, nunca se tragan.** Un `catch` solo existe para convertir el error en otro más claro, en un resultado explícito o en un aviso.
- Pruebas con **Pester 5.9.1** en Windows PowerShell 5.1: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 [-Path tests/X.Tests.ps1]`. `BeforeEach`/`AfterEach` solo dentro de un `Describe`.
- **Las pruebas nunca modifican el sistema real.** El registro solo se escribe bajo `HKCU:\Software\windows-tuneup-test` (también con `New-ItemProperty` y `Remove-ItemProperty` ejecutados en un PowerShell hijo en `tests/ManualHint.Tests.ps1`), el estado va a `$TestDrive` con `-StateRoot`, y lo que tocaría el sistema (Restaurar sistema, SFC, DISM, la lectura de Restaurar sistema) se simula con `Mock -ModuleName Tuneup`. Nuevo: `tests/Interrupt.Tests.ps1` abre PowerShell en consolas ocultas para probar Ctrl+C, y `tests/Package.Tests.ps1` arma zips e instala en `$TestDrive` (nunca en `Program Files`: la prueba que instala sin `-Destination` se salta elevada).
- Lint: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`. Verbo aprobado, sustantivo en singular, `PSReviewUnusedParameter` activo.
- Commits **sin** `Co-Authored-By`. **Nunca `git add -A` ni `git add .`**: cada paso de commit nombra sus archivos.
- Directorio del repo: `C:\Users\Edgar\Documents\GitHub\windows-tuneup` (comandos relativos a esa raíz, rama `main` o una rama nueva desde `main`).

Nuevas para este plan:

- **Los comandos nunca llaman a `exit`.** Escriben su reporte (con `-Json`, el documento sale por la salida estándar), dejan el código en `$Context.ExitCode` y lo que produjeron en `$Context.Result`. Solo `tuneup.ps1` hace `exit`, en un `finally`.
- **Un ayudante que devuelve valores no escribe reportes**: con `-Json` el reporte es salida y se mezclaría con lo que devuelve (pasó en la primera versión de `Import-TuneupContextDefinition`). Devuelve el problema y el comando escribe el error.
- **Los argumentos de un paso van en una tabla**: `$args = @{ ... }; Invoke-TuneupContextStep -Context $Context -Step { Invoke-X @args }`. PSScriptAnalyzer no ve un parámetro usado solo dentro del bloque y lo marca como sin usar.
- En las funciones del motor **`-WhatIf` se llama `-PlanOnly`**: un parámetro `WhatIf` en una función hace que PSScriptAnalyzer pida `SupportsShouldProcess`. `tuneup.ps1` conserva `-WhatIf` y lo pasa como `-PlanOnly`.
- **Preguntas por `$Context.Io`**: el menú y las confirmaciones escriben con `Io.Write` y leen con `Io.Read`. Las pruebas usan `New-TestIo -Answers @(...)` (`tests/TestHelpers.ps1`): cada lectura toma la siguiente respuesta, `$null` es el fin de la entrada, y pedir una respuesta de más falla la prueba en vez de quedarse esperando.
- Un archivo nuevo de este plan va completo; un cambio a un archivo existente da el bloque exacto a reemplazar, la función completa que lo reemplaza o el punto exacto donde agregar.

## Decisiones

| # | Decisión | Dónde |
|---|---|---|
| 1 | La orquestación pasa a funciones del motor que comparten la línea de comandos y el menú; `tuneup.ps1` queda en parámetros, relanzamiento, carga y `exit` | Task 3 |
| 2 | Menú sin parámetros (con `-Json` y nada más sigue siendo el plan de `base`), línea por línea con `Read-Host`, marcas de texto, los ajustes `high` solo pidiéndolos y escribiendo la palabra completa, una pregunta por ajuste `ask` (sí, no, sí a todos, no a todos) con el motivo `declined` | Tasks 9 y 10 |
| 3 | Avisos antes de aplicar (`pending-reboot`, `low-disk`, `restore-disabled`, `restore-blocked`, `managed-device`, `untrusted-location`): **ninguno detiene**; con confirmación se muestran junto al plan, con `-Yes` se muestran y se sigue, con `-Json` van en `preflight`. Solo en modo interactivo, y después de confirmar, se ofrece activar Restaurar sistema; las ubicaciones se escriben sin la cuenta | Tasks 7 y 8b |
| 4 | Ctrl+C: `TreatControlCAsInput` durante la aplicación, la tecla se busca antes de cada ajuste; si llega mientras corre un programa nativo, el `finally` guarda lo hecho. Motivo `interrupted`, `summary.interrupted`, código `2` (o `1` antes del primer ajuste); una línea avisa cómo funciona Ctrl+C y un error que no es Ctrl+C no se presenta como tal (`aborted`) | Tasks 5 y 8b |
| 5 | `transcript.log` escrito por la herramienta (no `Start-Transcript`), con las mismas reglas de confianza y sin el nombre de la cuenta; cada `-Undo` lo completa | Tasks 6 y 8b |
| 6 | `-Status -Reapply` (acepta `-Yes` y `-WhatIf`): solo lo que está en `drift`, por nombre y con el catálogo actual, como corrida nueva (`source` = `reapply`); un `ask` o de riesgo alto no vuelve solo | Tasks 8 y 8b |
| 7 | `manual` (líneas para restaurar a mano) y `signOutRequired` en cada resultado de `-Undo` | Task 4 |
| 8 | `engine/Version.ps1` y `toolVersion` en todo documento JSON y en `run.json` | Task 2 |
| 9 | `install.ps1` con la versión y el SHA256 del zip escritos por `build/package.ps1`; instala elevado en `%ProgramFiles%\windows-tuneup`; `irm | iex` fijado a una versión | Task 11 |
| 10 | Release: etiqueta `v*` igual a `Get-TuneupVersion` → lint, pruebas, paquete y **borrador** de release; se publica a mano | Task 12 |
| 11 | CI sin elevar con `runas /trustlevel:0x20000` | Task 13 |
| 12 | Extremo a extremo en Windows Sandbox sin apps de la Store ni OneDrive; lista para la VM | Tasks 14 y 15 |
| 13 | `docs/json-contract.md` (en inglés) con una prueba que exige que nombre cada campo | Task 15 |

## Desviaciones respecto de la especificación

| Especificación | Plan 4 | Motivo |
|---|---|---|
| Sección 7: reinicio pendiente, menos de 2 GB y Restaurar sistema desactivado "avisan y piden confirmación" | Se muestran antes de la confirmación de siempre; con `-Yes` se muestran y se sigue; con `-Json` van en `preflight`. Ninguno detiene | `-Yes` ya es la confirmación, y la skill del Plan 5 los lee de `-WhatIf -Json` antes de preguntar |
| Sección 7: "ofrece activarla o seguir solo con el diario" | Solo con confirmación interactiva, elevado y con cambios de sistema; nunca con `-Yes` ni `-Json` | Activarla es un cambio de Windows que el diario no deshace: exige un sí explícito |
| Sección 5: `transcript.log` "salida completa" | El texto para personas de la corrida, escrito por la herramienta | `Start-Transcript` guarda cuenta, equipo y línea de comandos, y Usuarios puede leer la carpeta de máquina |
| Sección 5: `Ui.psm1` | `engine/Menu.ps1` e `engine/Io.ps1` dentro del módulo único | El motor es un solo módulo desde el Plan 1 |
| Sección 5, distribución: "una línea `irm … | iex` fijada a una versión" | `install.ps1` de la release con la versión y el SHA256 del zip adentro; la release queda en borrador | El zip se verifica aunque se use `iex`; publicar exige adjuntar los reportes |
| Sección 6, capa 5: cada perfil en Windows Sandbox | Sin apps de la Store ni OneDrive (excluidos), más una prueba de reaplicar | El sandbox no trae Store ni winget: deshacerlas fallaría; las cubre la lista de la VM |
| Plan 2: `-Health` "ofrece `/RestoreHealth`" sin menú | El menú ofrece reparar después de una revisión con daño reparable, sin volver a revisar (`Invoke-TuneupHealth -Previous`) | Ahora hay menú |

## Estructura de archivos del Plan 4

```
windows-tuneup/
├── tuneup.ps1                         Delgado: parámetros, relanzamiento desde pwsh, módulo, textos, exit (+ -Reapply)
├── install.ps1                        (nuevo) Instalador: descarga, verifica el SHA256, extrae, instala
├── engine/
│   ├── Commands.ps1                   (nuevo) Contexto, comandos e Invoke-TuneupCli
│   ├── Io.ps1                         (nuevo) Preguntas y respuestas (consola o pruebas)
│   ├── Menu.ps1                       (nuevo) Menú interactivo
│   ├── Version.ps1                    (nuevo) Get-TuneupVersion
│   ├── ManualHint.ps1                 (nuevo) Cómo restaurar a mano
│   ├── Interrupt.ps1                  (nuevo) Ctrl+C entre ajustes
│   ├── Transcript.ps1                 (nuevo) transcript.log
│   ├── Preflight.ps1                  (nuevo) Avisos antes de aplicar y Restaurar sistema
│   ├── Executor.ps1                   + -StopRequested, -Results, -Progress; Invoke-TuneupPlanItem
│   ├── Output.ps1                     + toolVersion, preflight, source, interrupted, manual, signOutRequired
│   ├── Undo.ps1, Runs.ps1             + manual y signOutRequired; toolVersion en run.json
│   ├── Planner.ps1, Arguments.ps1     + -NoBase; -Reapply
│   └── Health.ps1                     + Invoke-TuneupHealth -Previous
├── i18n/es.json, i18n/en.json         + undo.manual*, reason.interrupted, interrupted.*, transcript.*, preflight.*, reapply.none, reason.declined, menu.*
├── build/
│   ├── package.ps1                    (nuevo) Zip, install.ps1 con versión y hash, SHA256SUMS, notas
│   ├── release-notes.md               (nuevo) Plantilla de las notas de la release
│   ├── test-standard-user.ps1         (nuevo) La suite con un token de usuario estándar
│   └── lint.ps1                       + install.ps1 y tests/sandbox
├── .github/workflows/
│   ├── ci.yml                         + trabajo test-standard-user
│   └── release.yml                    (nuevo) Etiqueta v* → borrador de release
├── docs/
│   ├── json-contract.md               (nuevo) Contrato JSON (inglés)
│   ├── es/vm-checklist.md, en/vm-checklist.md   (nuevos) Lista de la máquina virtual
│   └── superpowers/specs/…-design.md  + sección 12
├── tests/
│   ├── Commands, ManualHint, Interrupt, Transcript, Preflight, Menu, Package, E2E, JsonContract .Tests.ps1   (nuevos)
│   ├── Arguments, Cli, Docs, Executor, I18nCoverage, Output, Planner, Runs, Undo .Tests.ps1   (se amplían)
│   ├── TestHelpers.ps1                + New-TestIo
│   └── sandbox/                       (nuevo) e2e.wsb, E2E.psm1, Invoke-E2E.ps1, Start-E2E.ps1
└── README.md
```

---

### Task 1: Sección 12 de la especificación

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`

Documentación: sin pruebas propias (`tests/Docs.Tests.ps1` no la lee).

- [ ] **Step 1: Corregir las dos notas "Plan 4" que quedan resueltas**

En `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`, reemplazar:

```markdown
| `transcript.log` | Salida completa (Plan 4: todavía no se escribe) |
```

por:

```markdown
| `transcript.log` | Lo que se vio en pantalla: lo pedido, el plan, los avisos, los resultados y cada deshacer (sección 12) |
```

En `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`, reemplazar:

```markdown
- `-Status` detecta deriva (una actualización grande devolvió valores) y ofrece reaplicar
  (Plan 4: hoy solo informa la deriva).
- `-Undo` sigue ante errores y lista lo que no pudo restaurar (Plan 4: la instrucción manual
  para cada uno todavía no se da).
```

por:

```markdown
- `-Status` detecta deriva (una actualización grande devolvió valores) y `-Status -Reapply` (o el
  menú) la vuelve a aplicar (sección 12).
- `-Undo` sigue ante errores y lista lo que no pudo restaurar, con la instrucción para hacerlo a
  mano (sección 12).
```

- [ ] **Step 2: Agregar la sección 12 al final**

Agregar al final de `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md` (después de la sección 11, con una línea en blanco):

```markdown
## 12. Menú, avisos y distribución (Plan 4, 2026-10-01)

Decisiones tomadas al planificar el menú, los avisos antes de aplicar, Ctrl+C, `transcript.log`, la reaplicación, la distribución y la prueba de extremo a extremo. Donde contradicen secciones anteriores, manda esta.

1. **Comandos compartidos.** La orquestación sale de `tuneup.ps1` a `engine/Commands.ps1`: `Invoke-TuneupCli` (revisa los parámetros, resuelve las carpetas y despacha), `Invoke-TuneupApplyCommand`, `Invoke-TuneupStatusCommand`, `Invoke-TuneupUndoCommand`, `Invoke-TuneupHealthCommand`, `Invoke-TuneupMeasureCommand` y la parte común de aplicar, `Invoke-TuneupPlannedApply`. Reciben un contexto (`New-TuneupContext`: `-Json`, carpetas, avisos, `Io`, código de salida y último resultado), escriben su reporte (el JSON sale por la salida estándar) y dejan el código en `$Context.ExitCode`; nunca llaman a `exit`. Un ayudante que devuelve valores no escribe reportes (con `-Json` el reporte se mezclaría con lo que devuelve). `tuneup.ps1` queda en los parámetros, el relanzamiento desde `pwsh`, la carga del módulo y los textos, y `exit $context.ExitCode` en un `finally`. El código de salida del contexto **arranca en `1`** y cada comando pone `0` al terminar bien, así un comando que muere antes de informar nunca parece exitoso; `Invoke-TuneupGuarded` convierte lo que lance un comando en un informe de error con código `1` (lo pone antes de escribir el informe, por si el informe también falla). Las líneas de texto de los comandos (cancelado, esperas y fases de salud) salen por `Io.Write`, igual que las preguntas. En las funciones del motor `-WhatIf` se llama `-PlanOnly` (un parámetro `WhatIf` es de ShouldProcess).
2. **Menú.** `tuneup.ps1` sin comando ni opciones de aplicar, y sin `-Json`, abre el menú (`engine/Menu.ps1`); con `-Json` y nada más sigue siendo el plan de `base`. Toda respuesta es una línea (número, letra o Enter solo), leída con `Read-Host` a través de `$Context.Io`, así funciona en la consola de Windows PowerShell, en Windows Terminal y con la entrada redirigida (el fin de la entrada es volver, hasta salir). Las pruebas pasan un `Io` con respuestas guionadas que falla si se le pide una más. Opciones: Optimizar (perfiles con `[x]`, `(administrador)` y `(siempre)` para `base`; ajustes de riesgo alto solo si se pide verlos y escribiendo la palabra de confirmación completa; una pregunta por ajuste `ask` del plan con sí, no, sí a todos los que quedan y no a todos los que quedan, que quedan omitidos con el motivo `declined`; el plan; si necesita administrador y no lo es, se muestra y se vuelve), Estado (y `r` para volver a aplicar lo revertido), Deshacer (las 15 corridas más nuevas con su estado; toda la corrida o un ajuste), Salud (pide confirmar; si la revisión recomienda reparar, ofrece hacerlo sin revisar otra vez: `Invoke-TuneupHealth -Previous`) y Medir (segundos de espera y comparar con la última). Las marcas son texto, nunca solo color. El código de salida del menú es `0`.
3. **Avisos antes de aplicar** (`engine/Preflight.ps1`): `pending-reboot`, `low-disk` (menos de 2 GB libres en el disco del sistema), `restore-disabled` / `restore-blocked` (solo para cambios de sistema y elevado: se lee `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients`, que solo pueden leer los administradores, y la directiva `DisableSR`/`DisableConfig`), `managed-device` y `untrusted-location` (elevado y con el programa o `engine`, `catalog`, `profiles`, `actions` o `i18n` en una carpeta que procesos sin elevar, incluidos los del propio usuario, pueden cambiar: `Test-TuneupTrustedExecutable` sobre `tuneup.ps1` y `Tuneup.psm1`, y la propiedad y los permisos de cada archivo y carpeta de esas cinco carpetas; el aviso escribe la carpeta con el perfil como `%USERPROFILE%`). **Ninguno detiene la corrida**: con confirmación se muestran junto al plan; con `-Yes` se muestran y se sigue; con `-Json` van en el arreglo `preflight` (`id`, `message`) del plan y del resultado de aplicar (y de `result.json`). Solo `restore-disabled` tiene algo que hacer: en modo interactivo se pregunta si activar Restaurar sistema en el disco del sistema (`Enable-ComputerRestore`) después de confirmar "¿Aplicar N cambios?" (así rechazar no deja nada activado) y, si se activa, el aviso `restore-disabled` sale del reporte; nunca con `-Yes` ni `-Json`. Activarlo no se anota en el diario (no es un ajuste).
4. **Ctrl+C** (`engine/Interrupt.ps1`). Mientras se aplica, `[Console]::TreatControlCAsInput` convierte Ctrl+C en una tecla, que se busca antes de cada ajuste (`Invoke-TuneupPlan -StopRequested`): el ajuste en curso termina y los que faltan quedan `skipped` con el motivo `interrupted`, sin entrada en el diario. El resumen los cuenta aparte (`summary.interrupted`, `interrupted`), y el código es `2` (o `1` si se detuvo antes del primer ajuste). Un programa nativo (cmd, sc.exe, DISM, winget) vuelve a activar el Ctrl+C normal de la consola, así que cada revisión vuelve a poner la trampa; si Ctrl+C llega mientras corre uno de ellos, PowerShell se detiene en el acto: el `finally` de aplicar guarda `result.json` con lo hecho, el ajuste cortado como `failed` (su entrada del diario permite deshacerlo) y el resto como `interrupted`, y `tuneup.ps1` sale con ese código desde su `finally`. Sin consola propia (entrada redirigida) no hay trampa. Al empezar a aplicar, una línea dice cómo funcionan Ctrl+C (se detiene después del ajuste en curso) y Ctrl+Pausa (interrumpe de inmediato). El ajuste cortado se informa como `failed` solo si su entrada del diario ya estaba escrita; si la detención llegó antes, queda `interrupted`. Un error de otro tipo que corta la aplicación no se presenta como Ctrl+C: `result.json` se guarda con el error, el ajuste en curso con diario como `failed` y los que faltan como `aborted`, y el error se informa como siempre. Con `-Json`, si Ctrl+C detiene PowerShell la salida estándar queda vacía, el código es `2` y el documento está en `result.json`. Probado con una consola oculta que recibe la tecla (WriteConsoleInput) o la señal (GenerateConsoleCtrlEvent).
5. **`transcript.log`** (`engine/Transcript.ps1`). Lo escribe la herramienta, no `Start-Transcript` (que guarda cuenta, equipo y línea de comandos, y Usuarios puede leer la carpeta de máquina): encabezado con versión, corrida y hora, lo pedido (perfiles y listas, o reaplicar), el plan con sus avisos, el reporte y los avisos; cada `-Undo` de esa corrida agrega su reporte. Siempre en texto para personas, también con `-Json`. Se escribe con `Write-TuneupStateFile` (las mismas reglas de confianza); si falla, es un aviso y la corrida sigue. Ni el transcript ni `result.json` llevan el nombre de la cuenta ni la carpeta del perfil: se escriben `%USERNAME%` y `%USERPROFILE%` (`Hide-TuneupPersonalData`); la salida JSON conserva el `runDir` real, que es para quien ejecutó la corrida.
6. **`-Status -Reapply`.** `-Reapply` exige `-Status`, y con él `-Status` acepta `-Yes` y `-WhatIf` (no `-Profile`, `-Include` ni `-Exclude`). Planifica con el catálogo actual solo los ajustes en `drift`, por nombre y en el orden de las corridas que los aplicaron (`New-TuneupPlan -NoBase -Candidates`, como los pone un perfil, sin pedirlos): uno conservado por un perfil se vuelve a aplicar, pero uno que pregunta antes (`ask`) o de riesgo alto no vuelve solo: queda omitido con `needs-confirmation` o `high-risk-not-requested` y se informa (el menú pregunta por cada uno); la compatibilidad sigue rigiendo. Sin nada revertido dice que no hay nada que volver a aplicar, o que hay ajustes que sin administrador no se pueden comprobar. Un ajuste revertido que ya no está en el catálogo se deja fuera con un aviso. Es una corrida nueva; los documentos `plan` y `apply` llevan `source` (`profiles` o `reapply`).
7. **Deshacer a mano.** Cada resultado de `-Undo` lleva `manual` y `signOutRequired`; el documento `undo` suma `signOutRequired`. `manual` son líneas de **PowerShell** (para pegar en PowerShell como administrador) que restauran a mano un ajuste que falló, armadas con la definición y el estado guardado; cada nombre y valor va en un literal entre comillas simples con las comillas dobladas (también las tipográficas) y un salto de línea como `[char]`, así nada se expande ni se ejecuta al pegar. Por tipo: registro, `New-ItemProperty -LiteralPath … -Name … -PropertyType <tipo> -Value … -Force` (DWORD con signo; binarios `([byte[]](0x01,0x02))` y `([byte[]]@())`; MultiString `@('a','b')`; `[Microsoft.Win32.Registry]::SetValue` para los tipos None y Unknown), o `Remove-ItemProperty` si el valor no existía, más un `Remove-Item` por cada clave que el ajuste creó, que solo borra la clave si quedó vacía y si no lo avisa; servicio, `Set-Service -StartupType Automatic|Manual|Disabled` (`sc.exe config … start= delayed-auto` solo para un nombre de una palabra, porque Windows PowerShell 5.1 no tiene inicio retrasado) y `Start-Service` si corría; tarea, `Enable-ScheduledTask` o `Disable-ScheduledTask`; capacidad, `Add-WindowsCapability` o `Remove-WindowsCapability`; característica, `Enable-WindowsOptionalFeature` o `Disable-WindowsOptionalFeature` con `-NoRestart`; energía, `powercfg.exe /setactive`, `/setacvalueindex` y `/setdcvalueindex` (solo con GUID y números validados) y `/setactive SCHEME_CURRENT`; Appx, `winget install --id <id> --source msstore` (una sola fuente, `Get-TuneupWingetManualCommand`, que también usa la nota de la restauración); para una acción, una frase. Si las líneas no se pueden armar (un valor raro en el estado guardado), `manual` queda vacío y el fallo de la restauración se informa igual. `signOutRequired` es verdadero solo en un ajuste restaurado cuya definición lo pide, nunca en uno que falló o se omitió.
8. **Versión.** `engine/Version.ps1` (`Get-TuneupVersion`, hoy `0.1.0`). Todo documento JSON lleva `toolVersion` y `run.json` también.
9. **Distribución.** `build/package.ps1` arma `windows-tuneup-<versión>.zip` (carpeta `windows-tuneup-<versión>/` con `tuneup.ps1`, `engine`, `i18n`, `catalog/*.json`, `profiles`, `actions`, `docs/es`, `docs/en`, `README.md` y `LICENSE`; en un checkout de git, solo archivos seguidos), con entradas ordenadas y fechadas con el último commit (el mismo commit da el mismo zip en la misma máquina), `install.ps1` con la versión y el SHA256 del zip escritos, `SHA256SUMS` (formato de `sha256sum`) y `release-notes.md`. `install.ps1` comprueba el SHA256 antes de extraer, rechaza entradas fuera de su carpeta, instala elevado en `%ProgramFiles%\windows-tuneup` (reemplaza solo una copia anterior de windows-tuneup) y sin elevar en la carpeta actual con una advertencia; corre en su propio ámbito y lanza errores, nunca `exit`, así `irm | iex` no deja nada en la sesión ni la cierra. Sus mensajes están en inglés. `.github/workflows/release.yml`: una etiqueta `v*` igual a `Get-TuneupVersion` corre lint y pruebas, empaqueta y deja un **borrador** de release; se publica a mano tras adjuntar los reportes.
10. **CI sin elevar.** Un segundo trabajo corre la suite con `build/test-standard-user.ps1`: desde un proceso elevado la lanza con `runas /trustlevel:0x20000` (la misma cuenta con un token de usuario básico) y espera sus archivos de resultado; falla si el proceso sigue elevado o no arranca.
11. **Extremo a extremo** (`tests/sandbox`). `Start-E2E.ps1` llena `e2e.wsb` (repositorio en solo lectura, carpeta de salida con escritura, 8 GB) y abre Windows Sandbox; `Invoke-E2E.ps1` corre dentro, elevado y con las carpetas de estado reales: por perfil, foto inicial, aplicar con `-Yes` (los `ask` pedidos por nombre), `-Status`, aplicar otra vez (nada que hacer), `-Undo last` y comparar (`E2E.psm1`: estado de cada ajuste con los manejadores, tipo de arranque de cada servicio, tareas habilitadas y apps); una diferencia que solo es si un servicio corre se informa como volátil. Más una prueba de reaplicar sobre `base`. Las apps de la Store y OneDrive quedan fuera (el sandbox no tiene Store ni winget) y las cubre `docs/{es,en}/vm-checklist.md`. Escribe `e2e-report.json` y `e2e-report.md`.
12. **Contrato JSON.** `docs/json-contract.md` (en inglés, para desarrolladores y la skill del Plan 5) describe cada campo de cada documento; `tests/JsonContract.Tests.ps1` falla si un documento tiene un campo que la página no nombra.
13. **Quedan fuera:** PSScriptAnalyzer sobre las pruebas (solo se agrega `tests/sandbox`), detectar Insider o Defender for Endpoint (sección 11, 4f), traducir los mensajes de `install.ps1` y publicar la release (lo hace el usuario).
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-30-windows-tuneup-design.md
git commit -m "docs: sección 12 de la especificación (menú, avisos y distribución)"
```

---

### Task 2: Versión de la herramienta en el JSON y en `run.json`

**Files:**
- Create: `engine/Version.ps1`
- Modify: `engine/Output.ps1` (`Add-TuneupJsonWarning`), `engine/Runs.ps1` (`New-TuneupRun`)
- Test: `tests/Output.Tests.ps1`, `tests/Runs.Tests.ps1`

La release (Task 12) exige que la etiqueta coincida con esta versión, y la skill del Plan 5 declara la versión mínima que entiende: todo documento JSON pasa por `Add-TuneupJsonWarning`, que agrega `toolVersion` a la copia (el `result.json` guardado no la lleva; `run.json` sí).

- [ ] **Step 1: Pruebas que fallan**

En `tests/Output.Tests.ps1`, agregar antes de `Describe 'ConvertTo-TuneupEnvironmentView' {`:

```powershell
Describe 'Add-TuneupJsonWarning' {
    It 'adds the version of the tool and the warnings to a copy of the document' {
        $document = [pscustomobject]@{ schemaVersion = 1; command = 'status' }
        $copy = Add-TuneupJsonWarning -Document $document -Warnings @('careful')
        $copy.toolVersion | Should -Be (Get-TuneupVersion)
        @($copy.warnings) | Should -Be @('careful')
        $document.PSObject.Properties.Name | Should -Not -Contain 'toolVersion'
        Get-TuneupVersion | Should -Match '^\d+\.\d+\.\d+$'
    }
}
```

En `tests/Runs.Tests.ps1`, reemplazar:

```powershell
        $info.schemaVersion | Should -Be 1
        $info.userSid | Should -Be $MeSid
```

por:

```powershell
        $info.schemaVersion | Should -Be 1
        $info.toolVersion | Should -Be (Get-TuneupVersion)
        $info.userSid | Should -Be $MeSid
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: FAIL en `adds the version of the tool...`: `Get-TuneupVersion` no se reconoce.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Runs.Tests.ps1`
Expected: FAIL en `records who made the run in run.json` (`toolVersion` es `$null`).

- [ ] **Step 3: La versión**

Crear `engine/Version.ps1`:

```powershell
# The version of the tool. A release tag (v<version>) must match it: the release workflow checks.
$script:TuneupVersion = '0.1.0'

function Get-TuneupVersion {
    $script:TuneupVersion
}
```

En `engine/Output.ps1`, reemplazar la función `Add-TuneupJsonWarning` completa (con su comentario) por:

```powershell
function Add-TuneupJsonWarning {
    param([Parameter(Mandatory)]$Document, [AllowEmptyCollection()][string[]]$Warnings = @())
    # A copy, so the report saved in the run folder does not change.
    $copy = $Document | Select-Object -Property *
    $copy | Add-Member -NotePropertyName toolVersion -NotePropertyValue (Get-TuneupVersion) -Force
    $copy | Add-Member -NotePropertyName warnings -NotePropertyValue ([string[]]@($Warnings)) -Force
    $copy
}
```

En `engine/Runs.ps1`, reemplazar:

```powershell
        schemaVersion = $script:RunSchemaVersion
        userSid       = $userSid
```

por:

```powershell
        schemaVersion = $script:RunSchemaVersion
        toolVersion   = Get-TuneupVersion
        userSid       = $userSid
```

- [ ] **Step 4: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: PASS (`Tests Passed: 61, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Runs.Tests.ps1`
Expected: PASS (`Tests Passed: 33, Failed: 0`).

- [ ] **Step 5: Commit**

```bash
git add engine/Version.ps1 engine/Output.ps1 engine/Runs.ps1 tests/Output.Tests.ps1 tests/Runs.Tests.ps1
git commit -m "feat: versión de la herramienta en el JSON y en run.json"
```

---

### Task 3: Comandos compartidos y `tuneup.ps1` delgado

**Files:**
- Create: `engine/Io.ps1`, `engine/Commands.ps1`, `tests/Commands.Tests.ps1`
- Modify: `tuneup.ps1` (reemplazo completo), `tests/TestHelpers.ps1`
- Test: `tests/Commands.Tests.ps1`, `tests/Cli.Tests.ps1` (sin cambios: tiene que seguir en verde)

Diseño: `New-TuneupContext` guarda lo que comparte una invocación (`Json`, carpetas, `Force`, avisos, `Io`, `ExitCode`, `Result`). Cada comando escribe su reporte y deja el código en el contexto; con `-Json` el documento sale por la salida estándar de la función y llega a la de `tuneup.ps1`. Los errores que terminan un comando se escriben con `Write-TuneupCommandError` (código `1`). El código de salida del contexto arranca en `1` y cada comando pone `0` al terminar bien: un comando que lanza una excepción antes de informar (por ejemplo, un disco lleno al escribir el JSON) no sale con `0`. `Invoke-TuneupGuarded` ejecuta la línea de comandos de `tuneup.ps1`, pone el `1` antes de escribir el informe de error y deja que lance un informe que tampoco se puede escribir. Las líneas de texto de los comandos (cancelado, espera de la medición, salud) salen por `Io.Write`, no por `Write-Host`. `Invoke-TuneupCli` tiene los mismos parámetros que `tuneup.ps1` salvo `-Lang` y `-Json`, y `-WhatIf` se llama `-PlanOnly`. El comportamiento no cambia: `tests/Cli.Tests.ps1` (59 pruebas y 1 salto sin elevar) es la red de seguridad, y sus pruebas corren `tuneup.ps1` en otro proceso.

Dos trampas que la copia de prueba encontró: (1) `Import-TuneupContextDefinition` primero escribía el error del catálogo y devolvía `$null`, pero con `-Json` el documento de error salía junto con el valor devuelto y el comando seguía con un "catálogo" que era un texto JSON (por eso ahora devuelve `Problems` y el comando escribe el error); (2) PSScriptAnalyzer marcaba como sin usar los parámetros que solo aparecen dentro del bloque de un paso (por eso las tablas `$undoArguments`, `$healthArguments`, `$planArguments`).

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/TestHelpers.ps1`:

```powershell
# Questions and answers for the menu and the confirmations: each read takes the next scripted answer
# ($null stands for the end of the input) and fails when there are none left, so a test that asks
# more than it planned fails instead of waiting. What is written is kept in Output.
function New-TestIo {
    param([object[]]$Answers = @())
    $queue = New-Object System.Collections.Queue
    foreach ($answer in $Answers) { $queue.Enqueue($answer) }
    $output = New-Object System.Collections.Generic.List[string]
    $read = { if ($queue.Count -eq 0) { throw 'The test has no more answers' }; $queue.Dequeue() }.GetNewClosure()
    $write = { param([AllowEmptyString()][string]$Text, [switch]$NoNewline) $output.Add($Text) }.GetNewClosure()
    [pscustomobject]@{ PSTypeName = 'Tuneup.Io'; Read = $read; Write = $write; Output = $output; Pending = $queue }
}
```

Crear `tests/Commands.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    # The fixture catalog has an action tweak, whose script comes from the fixture actions folder.
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    # A context like the one tuneup.ps1 builds, on the fixture catalog, with a known environment.
    function New-TestContext([switch]$Json, [object[]]$Answers = @()) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context
    }
    # Runs a command and gives the JSON documents it wrote, parsed.
    function Get-JsonOutput([scriptblock]$Command) {
        @(& $Command 6>$null | ForEach-Object { $_ | ConvertFrom-Json })
    }
}

Describe 'Commands' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'shows the plan as one JSON document and changes nothing' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'plan'
        $documents[0].summary.apply | Should -Be 2
        $context.ExitCode | Should -Be 0
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'applies with -Yes, keeps the report as the result and sets the exit code' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'apply'
        $context.Result.summary.applied | Should -Be 2
        $context.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }

    It 'asks through the context and changes nothing when the answer is no' {
        $context = New-TestContext -Answers @('n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        $context.ExitCode | Should -Be 1
        $context.Io.Output -join "`n" | Should -Match 'Apply 2 changes\? \(y/n\)'
        $context.Io.Output -join "`n" | Should -Match 'Cancelled'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'applies when the answer is yes' {
        $context = New-TestContext -Answers @('y')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        $context.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
    }

    It 'writes one error document, and nothing else, when the catalog has problems' {
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $TestDrive 'broken-catalog'
        New-Item -ItemType Directory -Path $context.CatalogPath -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $context.CatalogPath 'bad.json'), '{ "tweaks": "no" }')
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'error'
        @($documents[0].details) -join ' ' | Should -Match 'no tweaks array'
        $context.ExitCode | Should -Be 1
    }

    It 'refuses Windows Server without -Force and plans it like Enterprise with it' {
        $context = New-TestContext -Json
        $context.Environment.IsServer = $true
        $context.Environment.Edition = 'Server'
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents[0].message | Should -Match 'Windows Server'
        $context.ExitCode | Should -Be 1
        $context.Force = $true
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents[0].command | Should -Be 'plan'
        $context.Environment.Edition | Should -Be 'Enterprise'
    }

    It 'reports status, undoes the last run and says when there is nothing left' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes } | Out-Null
        $status = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })
        $status[0].command | Should -Be 'status'
        @($context.Result).Count | Should -Be 2
        $undo = @(Get-JsonOutput { Invoke-TuneupUndoCommand -Context $context -RunId 'last' })
        $undo[0].summary.restored | Should -Be 2
        $context.ExitCode | Should -Be 0
        $again = @(Get-JsonOutput { Invoke-TuneupUndoCommand -Context $context -RunId 'last' })
        $again[0].message | Should -Be 'There are no runs to undo.'
        $context.ExitCode | Should -Be 1
    }

    It 'refuses -Health without elevation' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupHealthCommand -Context $context })
        $documents[0].message | Should -Be '-Health needs PowerShell as administrator.'
        $context.ExitCode | Should -Be 1
    }

    It 'measures and compares against the measurement before it' {
        $context = New-TestContext -Json
        $first = @(Get-JsonOutput { Invoke-TuneupMeasureCommand -Context $context })
        $first[0].command | Should -Be 'measure'
        $second = @(Get-JsonOutput { Invoke-TuneupMeasureCommand -Context $context -Compare 'last' })
        $second[0].comparison.againstId | Should -Be $first[0].id
        $context.ExitCode | Should -Be 0
    }

    It 'starts with exit code 1, so a command that fails to report never looks successful' {
        (New-TuneupContext).ExitCode | Should -Be 1
        $context = New-TestContext -Json
        Mock -ModuleName Tuneup Write-TuneupJson { throw 'disk full' }
        { Invoke-TuneupStatusCommand -Context $context } | Should -Throw 'disk full'
        $context.ExitCode | Should -Be 1
    }

    It 'turns what a command throws into an error document and exit code 1' {
        $context = New-TestContext -Json
        $context.ExitCode = 0
        $documents = @(Get-JsonOutput { Invoke-TuneupGuarded -Context $context -Command { throw 'boom' } })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'error'
        $documents[0].message | Should -Be 'boom'
        $context.ExitCode | Should -Be 1
    }

    It 'leaves exit code 1 when the error report cannot be written either' {
        $context = New-TestContext -Json
        $context.ExitCode = 0
        Mock -ModuleName Tuneup Write-TuneupJson { throw 'disk full' }
        { Invoke-TuneupGuarded -Context $context -Command { throw 'boom' } } | Should -Throw 'disk full'
        $context.ExitCode | Should -Be 1
    }

    It 'leaves what a command wrote and its code alone when nothing is thrown' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupGuarded -Context $context -Command { Invoke-TuneupStatusCommand -Context $context } })
        $documents[0].command | Should -Be 'status'
        $context.ExitCode | Should -Be 0
    }

    It 'shows the waiting line of a measurement through Io' {
        $context = New-TestContext
        Mock -ModuleName Tuneup Measure-TuneupSystem { [pscustomobject]@{ schemaVersion = 1 } }
        Mock -ModuleName Tuneup Save-TuneupMeasurement { [pscustomobject]@{ Id = 'm1' } }
        Mock -ModuleName Tuneup New-TuneupMeasureReport { [pscustomobject]@{ schemaVersion = 1; command = 'measure' } }
        Mock -ModuleName Tuneup Write-TuneupMeasureReport { }
        Invoke-TuneupMeasureCommand -Context $context -IdleSeconds 5
        $context.Io.Output -join "`n" | Should -Match 'Waiting 5 seconds idle'
        $context.ExitCode | Should -Be 0
    }

    It 'shows the health lines through Io' {
        $context = New-TestContext
        $context.Environment = New-TestEnvironment -IsAdmin $true
        Mock -ModuleName Tuneup Invoke-TuneupHealth { & $OnPhase 'sfc'; [pscustomobject]@{ recommendation = 'none' } }
        Mock -ModuleName Tuneup Write-TuneupHealthReport { }
        Invoke-TuneupHealthCommand -Context $context
        $text = $context.Io.Output -join "`n"
        $text | Should -Match 'Checking the health of Windows'
        $text | Should -Match 'Running SFC: it checks'
        $context.ExitCode | Should -Be 0
    }

    It 'carries the version of the tool in every JSON document' {
        $context = New-TestContext -Json
        @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })[0].toolVersion | Should -Be (Get-TuneupVersion)
    }
}

Describe 'Invoke-TuneupCli' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'rejects an invalid combination before reading anything' {
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -Status -Yes -StateRoot $Root })
        $documents[0].message | Should -Match 'Invalid parameter combination: -Status -Yes'
        $context.ExitCode | Should -Be 1
        Test-Path -LiteralPath $Root | Should -BeFalse
    }

    It 'resolves the folders into the context and runs the command they name' {
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput {
            Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -Status -StateRoot $Root `
                -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles')
        })
        $documents[0].command | Should -Be 'status'
        $context.StateRoot | Should -Be $Root
        $context.CatalogPath | Should -Be (Join-Path $Fixtures 'catalog')
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: FAIL: `New-TuneupContext` no se reconoce (18 pruebas).

- [ ] **Step 3: Preguntas y respuestas**

Crear `engine/Io.ps1`:

```powershell
# Where questions are written and answers are read. The console one writes to the host and reads a
# line with Read-Host, which also reads lines from a redirected standard input and gives $null at its
# end. Tests pass their own object with the same two script blocks and scripted answers.
function New-TuneupConsoleIo {
    [pscustomobject]@{
        PSTypeName = 'Tuneup.Io'
        Read       = { Read-Host }
        Write      = {
            param([AllowEmptyString()][string]$Text, [switch]$NoNewline)
            Write-Host $Text -NoNewline:$NoNewline
        }
    }
}

function Write-TuneupIoLine {
    param([Parameter(Mandatory)]$Io, [AllowEmptyString()][string]$Text = '', [switch]$NoNewline)
    & $Io.Write $Text -NoNewline:$NoNewline
}

# The answer, trimmed; $null when there is nothing more to read (the end of a redirected input).
function Read-TuneupIoAnswer {
    param([Parameter(Mandatory)]$Io, [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    if ($Prompt) { Write-TuneupIoLine -Io $Io -Text "$Prompt " -NoNewline }
    $answer = & $Io.Read
    if ($null -eq $answer) { return $null }
    ([string]$answer).Trim()
}

# Yes only when the answer matches the yes pattern of the language; anything else, or no answer, is no.
function Read-TuneupConfirmation {
    param([Parameter(Mandatory)]$Io, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupIoAnswer -Io $Io -Prompt $Prompt
    ($null -ne $answer) -and ($answer -match (Get-TuneupText -Key 'confirm.pattern'))
}
```

- [ ] **Step 4: Los comandos**

Crear `engine/Commands.ps1`:

```powershell
# The commands of the tool, shared by the command line (tuneup.ps1) and the menu. Each one writes its
# report (a JSON document on the output with -Json, text for people otherwise), leaves its exit code in
# $Context.ExitCode and what it produced in $Context.Result. A command never calls exit: an error that
# ends it is written as an error report with exit code 1.

# What one invocation shares between its steps: JSON or text, the folders for testing, the warnings
# collected so far, the questions and answers (Io), the exit code and the last result. The exit code
# starts at 1 and every command sets 0 when it succeeds, so one that dies before reporting is a failure.
function New-TuneupContext {
    param([switch]$Json, $Io)
    [pscustomobject]@{
        PSTypeName   = 'Tuneup.Context'
        Json         = [bool]$Json
        StateRoot    = $null
        CatalogPath  = $null
        ProfilesPath = $null
        Force        = $false
        Warnings     = New-Object System.Collections.Generic.List[string]
        Environment  = $null
        Io           = $(if ($null -ne $Io) { $Io } else { New-TuneupConsoleIo })
        ExitCode     = 1
        Result       = $null
    }
}

# With -Json the warnings go inside the document; otherwise each one is shown once.
function Invoke-TuneupContextStep {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][scriptblock]$Step)
    Invoke-TuneupStepCollectingWarning -Step $Step -Warnings $Context.Warnings -Json:$Context.Json
}

function Write-TuneupCommandError {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Message, [AllowEmptyCollection()][string[]]$Details = @())
    Write-TuneupErrorReport -Message $Message -Details $Details -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 1
}

# Runs a command line; whatever it throws becomes an error report and exit code 1. The code is set
# before the report is written, so if the report cannot be written either, the failure still counts.
function Invoke-TuneupGuarded {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][scriptblock]$Command)
    try {
        & $Command
    } catch {
        $Context.ExitCode = 1
        Write-TuneupCommandError -Context $Context -Message $_.Exception.Message
    }
}

function Get-TuneupContextEnvironment {
    param([Parameter(Mandatory)]$Context)
    if ($null -eq $Context.Environment) {
        $Context.Environment = Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupEnvironment }
    }
    $Context.Environment
}

function Invoke-TuneupStatusCommand {
    param([Parameter(Mandatory)]$Context)
    $items = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupStatus -StateRoot $Context.StateRoot })
    $Context.Result = $items
    Write-TuneupStatusReport -Items $items -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 0
}

function Invoke-TuneupUndoCommand {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$RunId, [string]$TweakId)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $run = Invoke-TuneupContextStep -Context $Context -Step { Resolve-TuneupRun -StateRoot $Context.StateRoot -RunId $RunId }
    if (-not $run) {
        $missing = $(if ($RunId -eq 'last') { Get-TuneupText -Key 'undo.none' } else { Get-TuneupText -Key 'err.runNotFound' -Format $RunId })
        Write-TuneupCommandError -Context $Context -Message $missing
        return
    }
    # Machine-folder runs always need elevation; a -StateRoot run only for its machine tweaks.
    $needsAdmin = ($run.Root -eq 'machine')
    if (-not $needsAdmin) {
        # Its warnings come again, once, from the undo itself.
        $needsAdmin = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue } |
            Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.tweak }).Count -gt 0
    }
    if ($needsAdmin -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    # Arguments of a step go in a table: PSScriptAnalyzer does not see a parameter used only inside it.
    $undoArguments = @{ Run = $run; TweakId = $TweakId }
    $results = @(Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupUndo @undoArguments })
    $Context.Result = $results
    Write-TuneupUndoReport -RunId $run.Id -Results $results -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupUndoExitCode -Results $results
}

function Invoke-TuneupHealthCommand {
    param([Parameter(Mandatory)]$Context, [switch]$Repair)
    $environment = Get-TuneupContextEnvironment -Context $Context
    if (-not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.healthNeedsAdmin')
        return
    }
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'health.running') }
    # One line per phase for people; with -Json nothing but the document goes to the output.
    $healthArguments = @{ Repair = $Repair }
    if (-not $Context.Json) {
        $io = $Context.Io
        $healthArguments.OnPhase = { param($Name) Write-TuneupIoLine -Io $io -Text (Get-TuneupText -Key "health.phase.$Name") }.GetNewClosure()
    }
    $report = Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupHealth @healthArguments }
    $Context.Result = $report
    Write-TuneupHealthReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupHealthExitCode -Report $report
}

function Invoke-TuneupMeasureCommand {
    param([Parameter(Mandatory)]$Context, [string]$Compare, [int]$IdleSeconds = 0)
    $environment = Get-TuneupContextEnvironment -Context $Context
    # Resolved before measuring, so 'last' is never the new measurement.
    $against = $null
    if ($Compare) {
        $against = Invoke-TuneupContextStep -Context $Context -Step { Resolve-TuneupMeasurement -StateRoot $Context.StateRoot -Id $Compare }
        if (-not $against) {
            $missing = $(if ($Compare -eq 'last') { Get-TuneupText -Key 'err.noMeasurements' } else { Get-TuneupText -Key 'err.measurementNotFound' -Format $Compare })
            Write-TuneupCommandError -Context $Context -Message $missing
            return
        }
    }
    if ($IdleSeconds -gt 0 -and -not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'measure.waiting' -Format $IdleSeconds) }
    $measurement = Invoke-TuneupContextStep -Context $Context -Step { Measure-TuneupSystem -Environment $environment -IdleSeconds $IdleSeconds }
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupMeasurement -Measurement $measurement -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    $report = New-TuneupMeasureReport -Saved $saved -Against $against
    $Context.Result = $report
    Write-TuneupMeasureReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = 0
}

# Windows Server and builds older than 19041 are refused unless -Force; Server then plans like
# Enterprise, which supports every policy that Server supports. Gives the message of the refusal, or
# nothing. Helpers like this one return values and never write a report: with -Json the report is
# output, and it would be mixed into what the helper returns.
function Get-TuneupUnsupportedMessage {
    param([Parameter(Mandatory)]$Context)
    $environment = Get-TuneupContextEnvironment -Context $Context
    if ($environment.IsServer -and -not $Context.Force) { return (Get-TuneupText -Key 'err.server') }
    if (($environment.Build -lt 19041 -or $environment.Edition -eq 'Unknown') -and -not $Context.Force) {
        return (Get-TuneupText -Key 'err.unsupported')
    }
    if ($environment.IsServer) { $environment.Edition = 'Enterprise' }
}

# The catalog and the profiles, with the problems that the checks found (none when they are valid).
function Import-TuneupContextDefinition {
    param([Parameter(Mandatory)]$Context)
    $catalog = @(Invoke-TuneupContextStep -Context $Context -Step { Import-TuneupCatalog -Path $Context.CatalogPath })
    $profileSet = @(Invoke-TuneupContextStep -Context $Context -Step { Import-TuneupProfileSet -Path $Context.ProfilesPath })
    $problems = @(Test-TuneupCatalog -Catalog $catalog) + @(Test-TuneupProfileSet -Profiles $profileSet -Catalog $catalog)
    [pscustomobject]@{ Catalog = $catalog; Profiles = $profileSet; Problems = [string[]]$problems }
}

function New-TuneupContextPlan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Definition,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [switch]$Interactive
    )
    $planArguments = @{
        Catalog     = $Definition.Catalog
        Profiles    = $Definition.Profiles
        ProfileIds  = $ProfileIds
        Include     = $Include
        Exclude     = $Exclude
        Environment = Get-TuneupContextEnvironment -Context $Context
        Interactive = $Interactive
        TestState   = { param($tweak) Test-TuneupState -Tweak $tweak }
    }
    @(Invoke-TuneupContextStep -Context $Context -Step { New-TuneupPlan @planArguments })
}

function Invoke-TuneupApplyCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) {
        Write-TuneupCommandError -Context $Context -Message $unsupported
        return
    }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
        return
    }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $ProfileIds -Include $Include -Exclude $Exclude)
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -PlanOnly:$PlanOnly -Yes:$Yes
}

# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    $results = @(Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan -Plan $Plan -RunDir $run.Dir })
    $report = New-TuneupApplyReport -Run $run -Results $results -RestorePoint $restorePoint -Environment $environment
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}

# The command line: checks the parameters, resolves the folders, loads the actions of -ActionsPath and
# runs the command they name. Same parameters as tuneup.ps1 except -Lang and -Json (the caller sets
# the language, and the context carries -Json), and -WhatIf is called -PlanOnly (a parameter named
# WhatIf belongs to ShouldProcess in a function).
function Invoke-TuneupCli {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ScriptRoot,
        [string[]]$ProfileName = @(),
        [string[]]$Include = @(),
        [string[]]$Exclude = @(),
        [switch]$PlanOnly,
        [switch]$Yes,
        [switch]$Status,
        [string]$Undo,
        [string]$Tweak,
        [switch]$Force,
        [string]$StateRoot,
        [string]$CatalogPath,
        [string]$ProfilesPath,
        [string]$ActionsPath,
        [switch]$Health,
        [switch]$Repair,
        [switch]$Measure,
        [string]$Compare,
        [int]$IdleSeconds = 0
    )
    $ProfileName = @(Get-TuneupCleanList ($ProfileName -split ','))
    $Include = @(Get-TuneupCleanList ($Include -split ','))
    $Exclude = @(Get-TuneupCleanList ($Exclude -split ','))

    # A parameter counts as given when it was bound and carries a value (a switch only when it is on).
    $present = @()
    if ($PSBoundParameters.ContainsKey('ProfileName') -and $ProfileName.Count) { $present += 'Profile' }
    if ($PSBoundParameters.ContainsKey('Include') -and $Include.Count) { $present += 'Include' }
    if ($PSBoundParameters.ContainsKey('Exclude') -and $Exclude.Count) { $present += 'Exclude' }
    if ($PSBoundParameters.ContainsKey('PlanOnly') -and $PlanOnly) { $present += 'WhatIf' }
    if ($PSBoundParameters.ContainsKey('Yes') -and $Yes) { $present += 'Yes' }
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $present += 'Status' }
    if ($PSBoundParameters.ContainsKey('Undo') -and $Undo) { $present += 'Undo' }
    if ($PSBoundParameters.ContainsKey('Tweak') -and $Tweak) { $present += 'Tweak' }
    if ($PSBoundParameters.ContainsKey('Health') -and $Health) { $present += 'Health' }
    if ($PSBoundParameters.ContainsKey('Repair') -and $Repair) { $present += 'Repair' }
    if ($PSBoundParameters.ContainsKey('Measure') -and $Measure) { $present += 'Measure' }
    if ($PSBoundParameters.ContainsKey('Compare') -and $Compare) { $present += 'Compare' }
    if ($PSBoundParameters.ContainsKey('IdleSeconds')) { $present += 'IdleSeconds' }
    $conflict = Get-TuneupArgumentConflict -Present $present
    if ($conflict) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.badArgs' -Format $conflict)
        return
    }
    # Checked here and not with ValidateRange, so that -Json gets its error as a JSON document.
    $maxIdleSeconds = 3600
    if ($PSBoundParameters.ContainsKey('IdleSeconds') -and ($IdleSeconds -lt 0 -or $IdleSeconds -gt $maxIdleSeconds)) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.idleSecondsRange' -Format 0, $maxIdleSeconds)
        return
    }

    # Relative paths follow the current PowerShell location, not the process folder that .NET uses.
    $pathApi = $ExecutionContext.SessionState.Path
    $Context.Force = [bool]$Force
    $Context.StateRoot = $(if ($StateRoot) { $pathApi.GetUnresolvedProviderPathFromPSPath($StateRoot) } else { $null })
    $Context.CatalogPath = $(if ($CatalogPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($CatalogPath) } else { Join-Path $ScriptRoot 'catalog' })
    $Context.ProfilesPath = $(if ($ProfilesPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($ProfilesPath) } else { Join-Path $ScriptRoot 'profiles' })
    if ($ActionsPath) {
        # Tests and development only, like -StateRoot: action scripts from another folder.
        $ActionsPath = $pathApi.GetUnresolvedProviderPathFromPSPath($ActionsPath)
        if (-not (Test-Path -LiteralPath $ActionsPath -PathType Container)) {
            $key = $(if (Test-Path -LiteralPath $ActionsPath -PathType Leaf) { 'err.actionsPathNotFolder' } else { 'err.actionsPathMissing' })
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key $key -Format $ActionsPath)
            return
        }
        Invoke-TuneupContextStep -Context $Context -Step { Write-TuneupActionsPathWarning }
        Invoke-TuneupContextStep -Context $Context -Step { Import-TuneupActionLibrary -Path $ActionsPath }
    }
    # Scripts of the repository folder or of -ActionsPath that could not be loaded: a warning here,
    # and an error in the catalog check only for the tweaks that use them.
    Invoke-TuneupContextStep -Context $Context -Step { Write-TuneupActionLoadWarning }
    Get-TuneupContextEnvironment -Context $Context | Out-Null

    if ($Status) { Invoke-TuneupStatusCommand -Context $Context; return }
    if ($Undo) { Invoke-TuneupUndoCommand -Context $Context -RunId $Undo -TweakId $Tweak; return }
    if ($Health) { Invoke-TuneupHealthCommand -Context $Context -Repair:$Repair; return }
    if ($Measure) { Invoke-TuneupMeasureCommand -Context $Context -Compare $Compare -IdleSeconds $IdleSeconds; return }
    Invoke-TuneupApplyCommand -Context $Context -ProfileIds $ProfileName -Include $Include -Exclude $Exclude -PlanOnly:$PlanOnly -Yes:$Yes
}
```

- [ ] **Step 5: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: PASS (`Tests Passed: 18, Failed: 0`).

- [ ] **Step 6: `tuneup.ps1` delgado**

Reemplazar `tuneup.ps1` completo por:

```powershell
<#
.SYNOPSIS
    windows-tuneup: goal-based, reversible and measurable Windows optimization.
.EXAMPLE
    .\tuneup.ps1 -Profile base,privacy -WhatIf
.EXAMPLE
    .\tuneup.ps1 -Undo last
.PARAMETER ActionsPath
    Development and testing only: loads action scripts from another folder. They run as the
    current user, with administrator rights when elevated, so use only a folder you trust.
.PARAMETER StateRoot
    Development and testing only: keeps runs and measurements in another folder. That folder
    is not hardened like the machine state folder.
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
    [string]$ActionsPath,
    [switch]$Health,
    [switch]$Repair,
    [switch]$Measure,
    [string]$Compare,
    [int]$IdleSeconds = 0
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

# Everything but the language and -Json goes to the engine as it was given; -WhatIf is -PlanOnly there.
$cliArguments = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) {
    if ($entry.Key -eq 'Lang' -or $entry.Key -eq 'Json') { continue }
    $name = $(if ($entry.Key -eq 'WhatIf') { 'PlanOnly' } else { $entry.Key })
    $cliArguments[$name] = $entry.Value
}
$context = New-TuneupContext -Json:$Json
try {
    Invoke-TuneupGuarded -Context $context -Command { Invoke-TuneupCli -Context $context -ScriptRoot $PSScriptRoot @cliArguments }
} finally {
    exit $context.ExitCode
}
```

- [ ] **Step 7: La línea de comandos sigue igual**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`Tests Passed: 59, Failed: 0, Skipped: 1` sin elevar; elevado se saltan otras pruebas). Es la prueba de que el comportamiento no cambió.

- [ ] **Step 8: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 9: Commit**

```bash
git add engine/Io.ps1 engine/Commands.ps1 tuneup.ps1 tests/TestHelpers.ps1 tests/Commands.Tests.ps1
git commit -m "refactor: comandos compartidos en el motor y tuneup.ps1 delgado"
```

---

### Task 4: Deshacer a mano y `signOutRequired` al deshacer

**Files:**
- Create: `engine/ManualHint.ps1`, `tests/ManualHint.Tests.ps1`
- Modify: `engine/Undo.ps1` (`Invoke-TuneupUndo`), `engine/Output.ps1` (`Write-TuneupUndoReport`), `engine/handlers/Appx.ps1` (`Get-TuneupWingetManualCommand`), `i18n/es.json`, `i18n/en.json`
- Test: `tests/ManualHint.Tests.ps1`, `tests/Undo.Tests.ps1`, `tests/Output.Tests.ps1`

Cada resultado de `-Undo` suma `signOutRequired` (el ajuste restaurado se nota al volver a iniciar sesión; arrastre de la sección 11, 4e; solo es verdadero en un ajuste restaurado: falso si falló o se omitió) y `manual`: para un ajuste que no se pudo restaurar, las líneas de **PowerShell** que lo hacen a mano, armadas con la definición y el estado guardado (sección 12, punto 7: `New-ItemProperty`/`Remove-ItemProperty`, `Set-Service`, `Enable-ScheduledTask`, `Add-WindowsCapability`, `Enable-WindowsOptionalFeature`, `powercfg.exe` y `winget install`; una acción recibe una frase). Todo nombre y valor va en un literal entre comillas simples con las comillas dobladas, así nada se expande al pegarlo; los GUID y números de `powercfg.exe` se validan y un nombre de servicio solo llega a `sc.exe` si es de una palabra. Si armar las líneas falla, `manual` queda vacío (`Get-TuneupManualRestoreLine`) y el fallo de la restauración se informa igual. Las pruebas corren de verdad las líneas, cada una en su propio PowerShell (`-EncodedCommand`) sobre la clave de prueba, con valores con espacios, barra final, comillas, `& | % $` y la comilla invertida, y leen el valor con `GetValue` para comprobar que vuelve exacto.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/ManualHint.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    # The lines of a hint, joined with | so that one line stays a string.
    function Get-Hint($Tweak, $State) { @(Get-TuneupManualRestoreHint -Tweak $Tweak -State $State) -join '|' }
    # Runs one line of a hint in its own PowerShell, like a person pasting it. The line goes encoded, so
    # nothing but the line itself decides what runs. Gives the exit code and what it wrote.
    function Invoke-HintLine([string]$Line) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('$ErrorActionPreference = ''Stop''; ' + $Line))
        $output = & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
    }
    function Get-StoredValue([string]$Name) { (Get-Item -LiteralPath $Key).GetValue($Name, $null, 'DoNotExpandEnvironmentNames') }
}

Describe 'Get-TuneupManualRestoreHint' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'gives PowerShell lines that put a registry value back, or delete it, and they work' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = 'Hint'; kind = 'DWord'; value = 1 })
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'Hint' -PropertyType DWord -Value ([int]-2) | Out-Null
        $hint = Get-Hint $tweak (Get-RegistryTweakState -Tweak $tweak)
        $hint | Should -Be "New-ItemProperty -LiteralPath 'HKCU:\Software\windows-tuneup-test' -Name 'Hint' -PropertyType DWord -Value -2 -Force | Out-Null"
        Set-ItemProperty -LiteralPath $Key -Name 'Hint' -Value 7
        (Invoke-HintLine $hint).Code | Should -Be 0
        Get-StoredValue 'Hint' | Should -Be -2
        $absent = [pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $false; kind = $null; value = $null }
        $delete = Get-Hint $tweak $absent
        $delete | Should -Be "Remove-ItemProperty -LiteralPath 'HKCU:\Software\windows-tuneup-test' -Name 'Hint'"
        (Invoke-HintLine $delete).Code | Should -Be 0
        (Get-Item -LiteralPath $Key).GetValueNames() | Should -Not -Contain 'Hint'
    }

    It 'gives back exactly the value that was saved, whatever characters it has' -TestCases @(
        @{ Kind = 'DWord'; Value = -2; Expected = -2 }
        @{ Kind = 'DWord'; Value = 1; Expected = 1 }
        @{ Kind = 'QWord'; Value = 5000000000; Expected = 5000000000 }
        @{ Kind = 'String'; Value = 'a b'; Expected = 'a b' }
        @{ Kind = 'String'; Value = 'C:\Program Files\x\'; Expected = 'C:\Program Files\x\' }
        @{ Kind = 'String'; Value = ''; Expected = '' }
        @{ Kind = 'String'; Value = 'it''s "quoted"'; Expected = 'it''s "quoted"' }
        @{ Kind = 'String'; Value = 'a & b | c % d $env:USERNAME $(1+1) ; `n'; Expected = 'a & b | c % d $env:USERNAME $(1+1) ; `n' }
        @{ Kind = 'String'; Value = ('x' + [char]0x2019 + 'y' + [char]0x2018 + 'z'); Expected = ('x' + [char]0x2019 + 'y' + [char]0x2018 + 'z') }
        @{ Kind = 'String'; Value = "line1`r`nline2"; Expected = "line1`r`nline2" }
        @{ Kind = 'ExpandString'; Value = '%TEMP%\x $env:TEMP'; Expected = '%TEMP%\x $env:TEMP' }
        @{ Kind = 'MultiString'; Value = @('one', 'two'); Expected = 'one|two' }
        @{ Kind = 'MultiString'; Value = @('it''s', '$x', 'a & b'); Expected = 'it''s|$x|a & b' }
        @{ Kind = 'MultiString'; Value = @(); Expected = '' }
        @{ Kind = 'Binary'; Value = @(1, 171, 255); Expected = '1|171|255' }
        @{ Kind = 'Binary'; Value = @(7); Expected = '7' }
        @{ Kind = 'Binary'; Value = @(); Expected = '' }
        @{ Kind = 'None'; Value = @(1, 2); Expected = '1|2' }
    ) {
        param($Kind, $Value, $Expected)
        $name = 'Say ''hi'' & "bye" $x'
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = $name; kind = 'String'; value = 'x' })
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name $name -PropertyType String -Value 'something else' | Out-Null
        $hint = Get-Hint $tweak ([pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $true; kind = $Kind; value = $Value })
        $result = Invoke-HintLine $hint
        $result.Code | Should -Be 0 -Because $result.Output
        $item = Get-Item -LiteralPath $Key
        $item.GetValueKind($name).ToString() | Should -Be $Kind
        $stored = $item.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        $item.Close()
        if ($Kind -in 'MultiString', 'Binary', 'None') { ($stored -join '|') | Should -Be $Expected }
        else { $stored | Should -Be $Expected }
    }

    It 'removes the keys that the tweak created, only while they are empty' {
        $deep = "$Key\a\b"
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $deep; name = 'Hint'; kind = 'DWord'; value = 1 })
        $state = [pscustomobject]@{ keyExisted = $false; existingAncestor = $Key; exists = $false; kind = $null; value = $null }
        $lines = @(Get-TuneupManualRestoreHint -Tweak $tweak -State $state)
        $lines.Count | Should -Be 3
        $lines[1] | Should -BeLike "*'HKCU:\Software\windows-tuneup-test\a\b'*"
        $lines[2] | Should -BeLike "*'HKCU:\Software\windows-tuneup-test\a'*"
        New-Item -Path $deep -Force | Out-Null
        New-ItemProperty -LiteralPath $deep -Name 'Hint' -PropertyType DWord -Value 1 | Out-Null
        foreach ($line in $lines) { (Invoke-HintLine $line).Code | Should -Be 0 }
        Test-Path -LiteralPath "$Key\a" | Should -BeFalse
        Test-Path -LiteralPath $Key | Should -BeTrue
        # A key that holds something else stays, and the line says so.
        New-Item -Path $deep -Force | Out-Null
        New-ItemProperty -LiteralPath $deep -Name 'Hint' -PropertyType DWord -Value 1 | Out-Null
        New-ItemProperty -LiteralPath "$Key\a" -Name 'Other' -PropertyType DWord -Value 1 | Out-Null
        $outputs = @(foreach ($line in $lines) { (Invoke-HintLine $line).Output })
        Test-Path -LiteralPath $deep | Should -BeFalse
        Test-Path -LiteralPath "$Key\a" | Should -BeTrue
        $outputs -join '' | Should -Match 'Not removed'
    }

    It 'only removes the value when it does not know which keys the tweak created' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = "$Key\a"; name = 'Hint'; kind = 'DWord'; value = 1 })
        $old = [pscustomobject]@{ exists = $false }
        @(Get-TuneupManualRestoreHint -Tweak $tweak -State $old).Count | Should -Be 1
    }

    It 'doubles every quote of a literal and writes a line break as a character' {
        ConvertTo-TuneupPsLiteral -Text 'a''b' | Should -Be '''a''''b'''
        ConvertTo-TuneupPsLiteral -Text ('a' + [char]0x2019 + 'b') | Should -Be ('''a' + [char]0x2019 + [char]0x2019 + 'b''')
        ConvertTo-TuneupPsLiteral -Text "a`r`nb" | Should -Be "('a' + [char]13 + '' + [char]10 + 'b')"
        ConvertTo-TuneupPsLiteral -Text '' | Should -Be ''''''
    }

    It 'writes a value of an unknown kind with the .NET call, and nothing for a kind it cannot write' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\X'; name = 'V'; kind = 'Binary'; value = @(1) })
        Get-Hint $tweak ([pscustomobject]@{ exists = $true; kind = 'Unknown'; value = @(1, 2) }) |
            Should -Be "[Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\X', 'V', ([byte[]](0x01,0x02)), [Microsoft.Win32.RegistryValueKind]::None)"
        Get-Hint $tweak ([pscustomobject]@{ exists = $true; kind = 'Mystery'; value = 1 }) | Should -BeNullOrEmpty
    }

    It 'gives the start type of a service, and starts it if it was running' {
        $tweak = New-TestTweak -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ name = 'DiagTrack'; startType = 'Disabled' })
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'AutomaticDelayed'; running = $true }) | Should -Be "sc.exe config 'DiagTrack' start= delayed-auto|Start-Service -Name 'DiagTrack'"
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'Manual'; running = $false }) | Should -Be "Set-Service -Name 'DiagTrack' -StartupType Manual"
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'Automatic'; running = $false }) | Should -Be "Set-Service -Name 'DiagTrack' -StartupType Automatic"
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'Disabled'; running = $false }) | Should -Be "Set-Service -Name 'DiagTrack' -StartupType Disabled"
        Get-Hint $tweak ([pscustomobject]@{ present = $false; startType = $null; running = $false }) | Should -BeNullOrEmpty
    }

    It 'gives sc.exe only for a service name it can take as one word' {
        $odd = New-TestTweak -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Odd$(1) name'; startType = 'Disabled' })
        Get-Hint $odd ([pscustomobject]@{ present = $true; startType = 'AutomaticDelayed'; running = $false }) | Should -BeNullOrEmpty
        Get-Hint $odd ([pscustomobject]@{ present = $true; startType = 'Manual'; running = $false }) | Should -Be "Set-Service -Name 'Odd`$(1) name' -StartupType Manual"
    }

    It 'gives the task, capability and feature lines, in both directions' {
        $task = New-TestTweak -Type 'task' -Scope 'machine' -Set ([pscustomobject]@{ path = '\Microsoft\Windows\X\'; name = 'Y'; state = 'Disabled' })
        Get-Hint $task ([pscustomobject]@{ present = $true; enabled = $true }) | Should -Be "Enable-ScheduledTask -TaskPath '\Microsoft\Windows\X\' -TaskName 'Y'"
        Get-Hint $task ([pscustomobject]@{ present = $true; enabled = $false }) | Should -Be "Disable-ScheduledTask -TaskPath '\Microsoft\Windows\X\' -TaskName 'Y'"
        Get-Hint $task ([pscustomobject]@{ present = $false; enabled = $null }) | Should -BeNullOrEmpty
        $capability = New-TestTweak -Type 'capability' -Scope 'machine' -Set ([pscustomobject]@{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' })
        Get-Hint $capability ([pscustomobject]@{ present = $true; state = 'Installed' }) | Should -Be "Add-WindowsCapability -Online -Name 'App.StepsRecorder~~~~0.0.1.0'"
        Get-Hint $capability ([pscustomobject]@{ present = $true; state = 'NotPresent' }) | Should -Be "Remove-WindowsCapability -Online -Name 'App.StepsRecorder~~~~0.0.1.0'"
        $feature = New-TestTweak -Type 'feature' -Scope 'machine' -Set ([pscustomobject]@{ name = 'WorkFolders-Client'; state = 'Disabled' })
        Get-Hint $feature ([pscustomobject]@{ present = $true; state = 'Enabled' }) | Should -Be "Enable-WindowsOptionalFeature -Online -FeatureName 'WorkFolders-Client' -NoRestart"
        Get-Hint $feature ([pscustomobject]@{ present = $true; state = 'Disabled' }) | Should -Be "Disable-WindowsOptionalFeature -Online -FeatureName 'WorkFolders-Client' -NoRestart"
    }

    It 'gives the powercfg lines only for GUIDs and numbers, and one winget line from the same source as the undo notes' {
        $scheme = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'scheme'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' })
        Get-Hint $scheme ([pscustomobject]@{ kind = 'scheme'; active = '381b4222-f694-41f0-9685-ff5bb260df2e'; exists = $true }) | Should -Be 'powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e'
        Get-Hint $scheme ([pscustomobject]@{ kind = 'scheme'; active = '1; calc'; exists = $true }) | Should -BeNullOrEmpty
        $subgroup = '4f971e89-eebd-4455-a8de-9e59040e7347'
        $setting = '5ca83367-6e45-459f-a27b-476b1d01c936'
        $both = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $subgroup.ToUpper(); setting = $setting; ac = 0; dc = 1 })
        Get-Hint $both ([pscustomobject]@{ kind = 'setting'; scheme = '381b4222-f694-41f0-9685-ff5bb260df2e'; present = $true; ac = 1200; dc = 600 }) |
            Should -Be "powercfg.exe /setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e $subgroup $setting 1200|powercfg.exe /setdcvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e $subgroup $setting 600|powercfg.exe /setactive SCHEME_CURRENT"
        $acOnly = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $subgroup; setting = $setting; ac = 0 })
        Get-Hint $acOnly ([pscustomobject]@{ kind = 'setting'; scheme = '381b4222-f694-41f0-9685-ff5bb260df2e'; present = $true; ac = 1200; dc = 600 }) |
            Should -Be "powercfg.exe /setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e $subgroup $setting 1200|powercfg.exe /setactive SCHEME_CURRENT"
        Get-Hint $acOnly ([pscustomobject]@{ kind = 'setting'; scheme = 'x; y'; present = $true; ac = 1; dc = 1 }) | Should -BeNullOrEmpty
        $appx = New-TestTweak -Type 'appx' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
        Get-Hint $appx $null | Should -Be 'winget install --id 9WZDNCRFHVFW --source msstore'
        Get-Hint $appx $null | Should -Be (Get-TuneupWingetManualCommand -StoreId '9WZDNCRFHVFW')
        $badId = New-TestTweak -Type 'appx' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZ; calc'; action = 'remove' })
        Get-Hint $badId $null | Should -BeNullOrEmpty
    }

    It 'points an action to the README and gives nothing without a saved state' {
        $action = New-TestTweak -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
        Get-Hint $action $null | Should -Be "Restore it by hand: README (Tweak types) explains what the 'onedrive' action changes."
        Get-Hint (New-TestTweak) $null | Should -BeNullOrEmpty
    }
}
```

En `tests/Undo.Tests.ps1`, agregar antes de `It 'keeps the run pending when a restore fails and finishes it on retry' {`:

```powershell
    It 'tells how to restore by hand a tweak whose restore failed, and nothing for a restored one' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { throw 'access denied' } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupUndo -Run $run)
        $results[0].status | Should -Be 'failed'
        @($results[0].manual) | Should -Be @("Remove-ItemProperty -LiteralPath 'HKCU:\Software\windows-tuneup-test' -Name 'Two'")
        @($results[1].manual).Count | Should -Be 0
    }

    It 'still reports a failed restore when the manual instructions cannot be built' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { throw 'access denied' } -ParameterFilter { $Tweak.id -eq 'test.two' }
        Mock -ModuleName Tuneup Get-TuneupManualRestoreHint { throw 'hint broke' }
        $results = @(Invoke-TuneupUndo -Run $run)
        $results[0].status | Should -Be 'failed'
        $results[0].error | Should -Be 'access denied'
        @($results[0].manual).Count | Should -Be 0
        $results[1].status | Should -Be 'restored'
    }

    It 'says when a restored tweak shows only after signing in again' {
        $signOut = New-TestTweak -Id 'test.signout' -Set ([pscustomobject]@{ path = $Key; name = 'SignOut'; kind = 'DWord'; value = 1 })
        $signOut | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $true
        $run = New-TuneupRun -StateRoot $Root
        $plan = @(New-TuneupPlan -Catalog @($signOut) -Profiles @(New-TestProfile -Id 'base' -Include @('test.signout')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir | Out-Null
        $results = @(Invoke-TuneupUndo -Run $run)
        $results[0].signOutRequired | Should -BeTrue
    }

    It 'does not ask to sign in again for a restore that failed or was skipped' {
        $signOut = New-TestTweak -Id 'test.signout' -Set ([pscustomobject]@{ path = $Key; name = 'SignOut'; kind = 'DWord'; value = 1 })
        $signOut | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $true
        $other = New-TestTweak -Id 'test.other' -Set ([pscustomobject]@{ path = $Key; name = 'Other'; kind = 'DWord'; value = 1 })
        $run = New-TuneupRun -StateRoot $Root
        $plan = @(New-TuneupPlan -Catalog @($signOut, $other) -Profiles @(New-TestProfile -Id 'base' -Include @('test.signout', 'test.other')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir | Out-Null
        Mock -ModuleName Tuneup Restore-TuneupState { throw 'access denied' } -ParameterFilter { $Tweak.id -eq 'test.signout' }
        $failed = @(Invoke-TuneupUndo -Run $run -TweakId 'test.signout')
        $failed[0].status | Should -Be 'failed'
        $failed[0].signOutRequired | Should -BeFalse
        Mock -ModuleName Tuneup Restore-TuneupState { } -ParameterFilter { $Tweak.id -eq 'test.signout' }
        @(Invoke-TuneupUndo -Run $run -TweakId 'test.signout')[0].signOutRequired | Should -BeTrue
        $skipped = @(Invoke-TuneupUndo -Run $run -TweakId 'test.signout')
        $skipped[0].status | Should -Be 'skipped'
        $skipped[0].reason | Should -Be 'already-undone'
        $skipped[0].signOutRequired | Should -BeFalse
    }
```

En `tests/Output.Tests.ps1`, agregar antes de `It 'shows skipped tweaks with their reason and counts them' {`:

```powershell
    It 'shows how to restore a failed tweak by hand and asks to sign out again' {
        $failed = [pscustomobject]@{ id = 'test.one'; title = 'One'; status = 'failed'; reason = $null; error = 'denied'; detail = $null; rebootRequired = $false; signOutRequired = $false; manual = @("Remove-ItemProperty -LiteralPath 'HKCU:\X' -Name 'One'") }
        $restored = [pscustomobject]@{ id = 'test.two'; title = 'Two'; status = 'restored'; reason = $null; error = $null; detail = $null; rebootRequired = $false; signOutRequired = $true; manual = @() }
        $text = (Write-TuneupUndoReport -RunId '20250101-000000' -Results @($failed, $restored) 6>&1 | Out-String)
        $text | Should -Match 'To restore it by hand, run'
        $text | Should -Match ([regex]::Escape("Remove-ItemProperty -LiteralPath 'HKCU:\X' -Name 'One'"))
        $text | Should -Match 'Sign out and sign in again'
        $json = Write-TuneupUndoReport -RunId '20250101-000000' -Results @($failed, $restored) -Json | ConvertFrom-Json
        $json.signOutRequired | Should -BeTrue
        @($json.results[0].manual).Count | Should -Be 1
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/ManualHint.Tests.ps1`
Expected: FAIL: `Get-TuneupManualRestoreHint` no se reconoce.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Undo.Tests.ps1`
Expected: FAIL en las pruebas nuevas (`manual`, `signOutRequired` y la guarda no existen).

- [ ] **Step 3: Las líneas para restaurar a mano**

Crear `engine/ManualHint.ps1`:

```powershell
# What a person can run to put a tweak back by hand when -Undo could not: one PowerShell command per
# line, built from the tweak and the state saved in the journal. Every name and value that comes from
# the catalog or the journal goes in a single-quoted literal with its quotes doubled, so nothing in it
# is expanded or run when the line is pasted. Commands are the same in every language; an action
# script, which can change anything, gets a sentence instead.

$script:RegistryHiveNames = @{ HKCU = 'HKEY_CURRENT_USER'; HKLM = 'HKEY_LOCAL_MACHINE' }
$script:ServiceStartTypeNames = @{ Automatic = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
# A service name that sc.exe takes as one word; anything else gets no sc.exe line.
$script:ScServiceNamePattern = '^[A-Za-z0-9_.@-]+\z'

# A PowerShell single-quoted literal. PowerShell reads four characters as a single quote (the ASCII
# one and the typographic ones), so all of them are doubled; a line break is written as [char] so the
# command stays on one line.
function ConvertTo-TuneupPsLiteral {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $quotes = "'" + [char]0x2018 + [char]0x2019 + [char]0x201A + [char]0x201B
    $escaped = [regex]::Replace([string]$Text, "[$quotes]", '$0$0')
    if ($escaped -notmatch '[\r\n]') { return "'$escaped'" }
    $escaped = $escaped.Replace("`r", "' + [char]13 + '").Replace("`n", "' + [char]10 + '")
    "('$escaped')"
}

function ConvertTo-TuneupBytesLiteral {
    param([AllowNull()]$Value)
    $bytes = @($Value | Where-Object { $null -ne $_ } | ForEach-Object { '0x{0:x2}' -f [int]$_ })
    if (-not $bytes.Count) { return '([byte[]]@())' }
    "([byte[]]($($bytes -join ',')))"
}

function Get-TuneupRegistryRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    $path = [string]$Set.path
    $pathText = ConvertTo-TuneupPsLiteral -Text $path
    $nameText = ConvertTo-TuneupPsLiteral -Text ([string]$Set.name)
    if (-not $State.exists) {
        "Remove-ItemProperty -LiteralPath $pathText -Name $nameText"
        # The keys that this tweak created and that are empty again go too (deepest first); a key
        # that holds anything else stays, and the line says so.
        $ancestor = [string]$State.existingAncestor
        if ($ancestor) {
            $current = $path
            while ($current -and $current -ne $ancestor -and $current -match '^(HKCU|HKLM):\\.+') {
                $keyText = ConvertTo-TuneupPsLiteral -Text $current
                "`$k = Get-Item -LiteralPath $keyText -ErrorAction SilentlyContinue; if (`$k -and `$k.ValueCount -eq 0 -and `$k.SubKeyCount -eq 0) { Remove-Item -LiteralPath $keyText } else { 'Not removed: it holds other values or keys, or it is already gone.' }"
                $current = Split-Path -Path $current -Parent
            }
        }
        return
    }
    $kind = [string]$State.kind
    $common = "-LiteralPath $pathText -Name $nameText"
    switch -CaseSensitive ($kind) {
        'DWord' { return "New-ItemProperty $common -PropertyType DWord -Value $([string](ConvertTo-TuneupDWord -Value $State.value)) -Force | Out-Null" }
        'QWord' { return "New-ItemProperty $common -PropertyType QWord -Value $([string][int64]$State.value) -Force | Out-Null" }
        'String' { return "New-ItemProperty $common -PropertyType String -Value $(ConvertTo-TuneupPsLiteral -Text ([string]$State.value)) -Force | Out-Null" }
        'ExpandString' { return "New-ItemProperty $common -PropertyType ExpandString -Value $(ConvertTo-TuneupPsLiteral -Text ([string]$State.value)) -Force | Out-Null" }
        'MultiString' {
            $items = @($State.value | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-TuneupPsLiteral -Text ([string]$_) })
            $list = $(if ($items.Count) { "@($($items -join ','))" } else { '([string[]]@())' })
            return "New-ItemProperty $common -PropertyType MultiString -Value $list -Force | Out-Null"
        }
        'Binary' { return "New-ItemProperty $common -PropertyType Binary -Value $(ConvertTo-TuneupBytesLiteral -Value $State.value) -Force | Out-Null" }
        { $_ -ceq 'None' -or $_ -ceq 'Unknown' } {
            # PowerShell has no -PropertyType for these; the .NET call is the one that writes them.
            if ($path -notmatch '^(?<hive>HKCU|HKLM):\\(?<sub>.+)$') { return }
            $fullKey = ConvertTo-TuneupPsLiteral -Text "$($script:RegistryHiveNames[$Matches['hive']])\$($Matches['sub'])"
            return "[Microsoft.Win32.Registry]::SetValue($fullKey, $nameText, $(ConvertTo-TuneupBytesLiteral -Value $State.value), [Microsoft.Win32.RegistryValueKind]::None)"
        }
    }
}

function Get-TuneupServiceRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    $name = [string]$Set.name
    $nameText = ConvertTo-TuneupPsLiteral -Text $name
    $startType = [string]$State.startType
    if ($script:ServiceStartTypeNames.ContainsKey($startType)) {
        "Set-Service -Name $nameText -StartupType $($script:ServiceStartTypeNames[$startType])"
    } elseif ($startType -ceq 'AutomaticDelayed' -and $name -cmatch $script:ScServiceNamePattern) {
        # Set-Service in Windows PowerShell 5.1 has no delayed start.
        "sc.exe config $nameText start= delayed-auto"
    }
    if ($State.running) { "Start-Service -Name $nameText" }
}

function Get-TuneupPowercfgRestoreHint {
    param([Parameter(Mandatory)]$Set, [Parameter(Mandatory)]$State)
    if ([string]$Set.kind -ceq 'scheme') {
        if ([string]$State.active -match $script:GuidPattern) { "powercfg.exe /setactive $($State.active)" }
        return
    }
    if (-not $State.present) { return }
    $ids = @([string]$State.scheme, [string]$Set.subgroup, [string]$Set.setting)
    if (@($ids | Where-Object { $_ -notmatch $script:GuidPattern }).Count) { return }
    $target = Get-TuneupPowerSettingTarget -Set $Set
    $indexes = "$($ids[0]) $(([string]$ids[1]).ToLowerInvariant()) $(([string]$ids[2]).ToLowerInvariant())"
    foreach ($source in @(@('ac', 'setacvalueindex'), @('dc', 'setdcvalueindex'))) {
        if ($null -eq $target.($source[0])) { continue }
        $number = [uint32]$State.($source[0])
        "powercfg.exe /$($source[1]) $indexes $number"
    }
    # Reloads the active scheme, so a change to it takes effect; another scheme is not activated.
    'powercfg.exe /setactive SCHEME_CURRENT'
}

# The lines for a result of -Undo. A hint that cannot be built (an odd value in a saved state) gives
# no lines and does not hide the failure that it was meant to help with.
function Get-TuneupManualRestoreLine {
    param([Parameter(Mandatory)]$Tweak, [AllowNull()]$State)
    try {
        [string[]]@(Get-TuneupManualRestoreHint -Tweak $Tweak -State $State)
    } catch {
        [string[]]@()
    }
}

function Get-TuneupManualRestoreHint {
    param([Parameter(Mandatory)]$Tweak, [AllowNull()]$State)
    $set = $Tweak.set
    if ([string]$Tweak.type -ceq 'appx') {
        if ([string]$set.storeId -cmatch $script:StoreIdPattern) { Get-TuneupWingetManualCommand -StoreId ([string]$set.storeId) }
        return
    }
    if ([string]$Tweak.type -ceq 'action') { return (Get-TuneupText -Key 'undo.manual.action' -Format $set.script) }
    # The other types need the saved state; without it there is nothing exact to suggest.
    if ($null -eq $State -or $State -is [string] -or $State -is [ValueType]) { return }
    switch -CaseSensitive ([string]$Tweak.type) {
        'registry' { Get-TuneupRegistryRestoreHint -Set $set -State $State }
        'service' { Get-TuneupServiceRestoreHint -Set $set -State $State }
        'task' {
            if ($State.present) {
                $verb = $(if ($State.enabled) { 'Enable-ScheduledTask' } else { 'Disable-ScheduledTask' })
                "$verb -TaskPath $(ConvertTo-TuneupPsLiteral -Text ([string]$set.path)) -TaskName $(ConvertTo-TuneupPsLiteral -Text ([string]$set.name))"
            }
        }
        'capability' {
            if ($State.present) {
                $verb = $(if ($State.state -eq 'Installed') { 'Add-WindowsCapability' } else { 'Remove-WindowsCapability' })
                "$verb -Online -Name $(ConvertTo-TuneupPsLiteral -Text ([string]$set.name))"
            }
        }
        'feature' {
            if ($State.present) {
                $verb = $(if ($State.state -eq 'Enabled') { 'Enable-WindowsOptionalFeature' } else { 'Disable-WindowsOptionalFeature' })
                "$verb -Online -FeatureName $(ConvertTo-TuneupPsLiteral -Text ([string]$set.name)) -NoRestart"
            }
        }
        'powercfg' { Get-TuneupPowercfgRestoreHint -Set $set -State $State }
    }
}
```

- [ ] **Step 4: Los resultados de deshacer y su reporte**

En `engine/handlers/Appx.ps1`, agregar antes de `function Test-TuneupAppxInstalledForCurrentUser {`:

```powershell
# The line a person can run to install an app by hand: the one source for the undo notes and the
# instructions that -Undo gives when it fails. The id is checked before it reaches here.
function Get-TuneupWingetManualCommand {
    param([Parameter(Mandatory)][string]$StoreId)
    "winget install --id $StoreId --source msstore"
}
```

y en `Restore-AppxTweakState` reemplazar:

```powershell
    $manual = "winget install --id $($Tweak.set.storeId) --source msstore"
```

por:

```powershell
    $manual = Get-TuneupWingetManualCommand -StoreId ([string]$Tweak.set.storeId)
```

En `engine/Undo.ps1`, reemplazar la función `Invoke-TuneupUndo` completa (con su comentario) por:

```powershell
function Invoke-TuneupUndo {
    param([Parameter(Mandatory)]$Run, [string]$TweakId)
    Assert-TuneupRunUndoable -Run $Run
    # A run object built before the undo carries no Undone flag, so the marker itself decides.
    if ($Run.Undone -or (Test-TuneupRunMarker -Dir $Run.Dir -Name 'undone.json' -Root $Run.Root)) {
        throw (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $Run.Id)
    }
    # With -TweakId the run is read as usual: a tweak noted as undone answers already-undone.
    if (-not $TweakId -and (Test-TuneupRunAllNotedUndone -Run $Run)) {
        throw (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $Run.Id)
    }
    $journal = Get-TuneupRunJournal -Run $Run
    $alreadyUndone = @(Get-TuneupUndoneTweakId -Run $Run)
    $entries = @($journal.Entries)
    # Entries of another user are reported as skipped: they stay pending for their owner.
    $foreign = @($journal.SkippedEntries)
    $newResult = {
        param($entry, [string]$status, $reason, $errorText, $outcome)
        # A restored tweak that shows only after signing in again says so, like when it was applied. A
        # failed one carries what a person can run to restore it by hand.
        $signOut = $entry.tweak.PSObject.Properties['signOutRequired']
        [pscustomobject]@{
            id              = $entry.id
            title           = Get-TuneupTitle -Tweak $entry.tweak
            status          = $status
            reason          = $reason
            error           = $errorText
            detail          = $(if ($outcome) { $outcome.detail } else { $null })
            rebootRequired  = $(if ($outcome) { [bool]$outcome.rebootRequired } else { $false })
            signOutRequired = ($status -eq 'restored' -and $null -ne $signOut -and $signOut.Value -eq $true)
            manual          = [string[]]@(if ($status -eq 'failed') { Get-TuneupManualRestoreLine -Tweak $entry.tweak -State $entry.state })
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
        $results += [pscustomobject]@{ id = $null; title = "run $($Run.Id)"; status = 'failed'; reason = $null; error = "The undo could not be recorded: $($_.Exception.Message)"; detail = $null; rebootRequired = $false; signOutRequired = $false; manual = [string[]]@() }
    }
    $results
}
```

En `engine/Output.ps1`, reemplazar la función `Write-TuneupUndoReport` completa (con su comentario) por:

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
    $signOutRequired = @($Results | Where-Object { $_.PSObject.Properties['signOutRequired'] -and $_.signOutRequired }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion   = 1
            command         = 'undo'
            runId           = $RunId
            rebootRequired  = $rebootRequired
            signOutRequired = $signOutRequired
            results         = $Results
            summary         = [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
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
        $manual = @($(if ($result.PSObject.Properties['manual']) { $result.manual }) | Where-Object { $_ })
        if ($manual.Count) {
            Write-Host "    $(Get-TuneupText -Key 'undo.manual')"
            foreach ($line in $manual) { Write-Host "      $line" }
        }
    }
    Write-Host (Get-TuneupText -Key 'undo.summary' -Format $restored, $failed, $skipped)
    if ($rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
    elseif ($signOutRequired) { Write-Host (Get-TuneupText -Key 'signOut') -ForegroundColor Yellow }
}
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "undo.manual": "Para restaurarlo a mano, ejecuta esto en PowerShell como administrador (un ajuste del usuario no lo necesita):",
  "undo.manual.action": "Restáuralo a mano: el README (Tipos de ajuste) explica qué cambia la acción '{0}'."
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "undo.manual": "To restore it by hand, run this in PowerShell as administrator (a user tweak does not need it):",
  "undo.manual.action": "Restore it by hand: README (Tweak types) explains what the '{0}' action changes."
```

- [ ] **Step 5: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/ManualHint.Tests.ps1`
Expected: PASS (`Tests Passed: 28, Failed: 0`), unos 20 segundos: cada línea de las pruebas de valores se corre en su propio PowerShell.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Undo.Tests.ps1`
Expected: PASS (`Tests Passed: 33, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: PASS (`Tests Passed: 62, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS (`Tests Passed: 4, Failed: 0`).

- [ ] **Step 6: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 7: Commit**

```bash
git add engine/ManualHint.ps1 engine/Undo.ps1 engine/Output.ps1 i18n/es.json i18n/en.json tests/ManualHint.Tests.ps1 tests/Undo.Tests.ps1 tests/Output.Tests.ps1
git commit -m "feat: deshacer dice cómo restaurar a mano y avisa del cierre de sesión"
```

---

### Task 5: Ctrl+C entre dos ajustes

**Files:**
- Create: `engine/Interrupt.ps1`, `tests/Interrupt.Tests.ps1`
- Modify: `engine/Executor.ps1` (`Invoke-TuneupPlan`, nuevo `Invoke-TuneupPlanItem`), `engine/Output.ps1` (`New-TuneupApplyReport`, `Get-TuneupApplyExitCode`, `Write-TuneupApplyReport`), `engine/Commands.ps1` (`Invoke-TuneupPlannedApply`, nuevo `Save-TuneupStoppedApply`), `i18n/es.json`, `i18n/en.json`
- Test: `tests/Executor.Tests.ps1`, `tests/Output.Tests.ps1`, `tests/Interrupt.Tests.ps1`

Diseño, probado en la copia antes de escribir el plan (consolas ocultas nuevas, con la tecla escrita en su entrada con `WriteConsoleInput` y la señal enviada con `GenerateConsoleCtrlEvent`):

- Con `[Console]::TreatControlCAsInput = $true`, Ctrl+C llega como una tecla (`ConsoleKey.C` con `Control`) que `[Console]::ReadKey($true)` lee; PowerShell no se detiene. `Invoke-TuneupPlan -StopRequested` la busca antes de cada ajuste por aplicar: el que está en curso termina y los siguientes quedan `skipped` con el motivo `interrupted`, sin entrada en el diario.
- **Un programa nativo vuelve a poner la consola en modo normal**: después de `cmd.exe /c exit 0`, `TreatControlCAsInput` vale `False`. Por eso cada revisión la vuelve a activar. Si Ctrl+C llega mientras corre un programa así (sc.exe, DISM, winget), detiene el programa y la tubería de PowerShell: un `catch` no lo ve, pero el `finally` corre y puede escribir archivos y al host; escribir en la salida (`Write-Output`) vuelve a lanzar la detención y corta el `finally`. Por eso `Invoke-TuneupPlan` también agrega cada resultado a una lista (`-Results`) y anota el ajuste en curso (`-Progress`), y el `finally` de aplicar (`Save-TuneupStoppedApply`) guarda `result.json` sin escribir en la salida: el ajuste cortado como `failed` (su entrada del diario permite deshacerlo) y el resto como `interrupted`. `exit` dentro de un `finally` después de la detención sí fija el código del proceso (`tuneup.ps1` ya sale con `exit $context.ExitCode` en su `finally`).
- Con la entrada redirigida (otro programa corre `tuneup.ps1 -Json`) no hay consola que configurar: no hay trampa y Ctrl+C conserva su efecto de siempre.
- El reporte suma `interrupted` y `summary.interrupted`; los interrumpidos no cuentan como omitidos. Código: `2` si se tocó algo, `1` si se detuvo antes del primer ajuste.

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Executor.Tests.ps1`:

```powershell
Describe 'Invoke-TuneupPlan stopped with Ctrl+C' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'finishes the tweak in progress and leaves the rest out, without journaling them' {
        $asked = New-Object System.Collections.Generic.List[int]
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir -StopRequested { $asked.Add(1); $asked.Count -gt 1 })
        ($results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/interrupted'
        $asked.Count | Should -Be 2
        @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl') | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one'
        (Get-Item -LiteralPath $Key).GetValueNames() | Should -Not -Contain 'Two'
    }

    It 'changes nothing when it is asked to stop before the first tweak' {
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir -StopRequested { $true })
        ($results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'interrupted,interrupted'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'adds every result to -Results and clears -Progress after each tweak' {
        $list = New-Object System.Collections.Generic.List[object]
        $progress = @{ Current = 'stale' }
        # The failure tells which tweak -Progress named while it was being applied.
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { throw "current=$($progress.Current)" } -ParameterFilter { $Tweak.id -eq 'test.one' }
        Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir -Results $list -Progress $progress | Out-Null
        ($list | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one,test.two'
        $list[0].error | Should -Be 'current=test.one'
        $progress.Current | Should -BeNullOrEmpty
    }
}
```

En `tests/Output.Tests.ps1`, reemplazar:

```powershell
        $report.summary.PSObject.Properties.Name -join ',' | Should -Be 'applied,partial,notApplied,failed,skipped,refused,journalErrors'
```

por:

```powershell
        $report.summary.PSObject.Properties.Name -join ',' | Should -Be 'applied,partial,notApplied,failed,skipped,refused,journalErrors,interrupted'
```

En `tests/Output.Tests.ps1`, agregar antes de `Describe 'Get-TuneupUndoExitCode' {`:

```powershell
Describe 'Reports of a run stopped with Ctrl+C' {
    It 'counts the tweaks left out apart and exits with 2 when something was applied' {
        $report = New-TestReport @((New-TestResult -Status 'applied'), (New-TestResult -Status 'skipped' -Reason 'interrupted'), $PlanSkip)
        $report.interrupted | Should -BeTrue
        $report.summary.interrupted | Should -Be 1
        $report.summary.skipped | Should -Be 1
        Get-TuneupApplyExitCode -Report $report | Should -Be 2
        $text = (Write-TuneupApplyReport -Report $report 6>&1 | Out-String)
        $text | Should -Match 'Stopped with Ctrl\+C: 1 tweaks were not applied'
    }

    It 'exits with 1 when it stopped before the first tweak' {
        $report = New-TestReport @((New-TestResult -Status 'skipped' -Reason 'interrupted'), $PlanSkip)
        Get-TuneupApplyExitCode -Report $report | Should -Be 1
        (New-TestReport @((New-TestResult -Status 'applied'))).interrupted | Should -BeFalse
    }
}
```

Crear `tests/Interrupt.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # Ctrl+C needs a console of its own: the harness runs in a new, hidden console window. It presses
    # Ctrl+C by writing the key into that console's input (what the keyboard does), or sends the signal
    # that a native program would let through, and writes what it saw to a file.
    $script:Harness = @'
param([string]$Repo, [string]$Out, [string]$Mode, [string]$StateRoot)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TuneupTestConsole {
    [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
    public struct KeyEvent {
        [FieldOffset(0)] public int KeyDown;
        [FieldOffset(4)] public ushort RepeatCount;
        [FieldOffset(6)] public ushort VirtualKeyCode;
        [FieldOffset(8)] public ushort VirtualScanCode;
        [FieldOffset(10)] public char UnicodeChar;
        [FieldOffset(12)] public uint ControlKeyState;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct InputRecord {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KeyEvent Key;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GetStdHandle(int handle);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool WriteConsoleInput(IntPtr input, InputRecord[] records, uint length, out uint written);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint group);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
    public static bool PressCtrlC() {
        var records = new InputRecord[2];
        for (int i = 0; i < 2; i++) {
            records[i].EventType = 1;
            records[i].Key.KeyDown = i == 0 ? 1 : 0;
            records[i].Key.RepeatCount = 1;
            records[i].Key.VirtualKeyCode = 0x43;
            records[i].Key.VirtualScanCode = 0x2E;
            records[i].Key.UnicodeChar = (char)3;
            records[i].Key.ControlKeyState = 0x0008;
        }
        uint written;
        return WriteConsoleInput(GetStdHandle(-10), records, 2, out written) && written == 2;
    }
    public static void SendCtrlC() {
        SetConsoleCtrlHandler(IntPtr.Zero, false);
        GenerateConsoleCtrlEvent(0, 0);
    }
}
"@
function Save-Line([string]$Text) { Add-Content -LiteralPath $Out -Value $Text -Encoding UTF8 }
Import-Module (Join-Path $Repo 'engine\Tuneup.psm1') -Force
Initialize-TuneupI18n -Root (Join-Path $Repo 'i18n') -Lang en
Save-Line "redirected=$([Console]::IsInputRedirected)"
if ($Mode -eq 'trap') {
    $trap = Enable-TuneupInterruptTrap
    Save-Line "enabled=$($null -ne $trap)"
    Save-Line "pressedKey=$([TuneupTestConsole]::PressCtrlC())"
    Save-Line "requested=$(Test-TuneupInterruptRequested -Trap $trap)"
    Save-Line "again=$(Test-TuneupInterruptRequested -Trap $trap)"
    cmd.exe /c 'exit 0'
    Save-Line "afterNative=$([Console]::TreatControlCAsInput)"
    Test-TuneupInterruptRequested -Trap $trap | Out-Null
    Save-Line "rearmed=$([Console]::TreatControlCAsInput)"
    Disable-TuneupInterruptTrap -Trap $trap
    Save-Line "restored=$([Console]::TreatControlCAsInput)"
    exit 0
}
# key or signal: right after test.one is set, Ctrl+C comes as a key or as the signal.
& (Get-Module Tuneup) {
    param($Mode)
    $script:HarnessMode = $Mode
    $script:HarnessSet = ${function:Set-RegistryTweakDesired}
    function script:Set-RegistryTweakDesired {
        param($Tweak)
        & $script:HarnessSet -Tweak $Tweak
        if ($Tweak.id -ne 'test.one') { return }
        if ($script:HarnessMode -eq 'key') { [TuneupTestConsole]::PressCtrlC() | Out-Null; return }
        [TuneupTestConsole]::SendCtrlC()
        Start-Sleep -Seconds 10
    }
} $Mode
$context = New-TuneupContext -Json
try {
    Invoke-TuneupCli -Context $context -ScriptRoot $Repo -Yes -Force -StateRoot $StateRoot `
        -CatalogPath (Join-Path $Repo 'tests\fixtures\catalog') -ProfilesPath (Join-Path $Repo 'tests\fixtures\profiles') `
        -ActionsPath (Join-Path $Repo 'tests\fixtures\actions') | Out-Null
    Save-Line 'completed=True'
} finally {
    Save-Line "exit=$($context.ExitCode)"
    exit $context.ExitCode
}
'@

    function Invoke-Harness([string]$Mode) {
        $script:Out = Join-Path $TestDrive "$Mode-$([guid]::NewGuid()).txt"
        $script:StateRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script_ = Join-Path $TestDrive 'harness.ps1'
        [System.IO.File]::WriteAllText($script_, $Harness)
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script_`"", '-Repo', "`"$Repo`"", '-Out', "`"$Out`"", '-Mode', $Mode, '-StateRoot', "`"$StateRoot`"")
        $process = Start-Process -FilePath $PowerShell -ArgumentList $arguments -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(120000)) { $process.Kill(); throw "The $Mode harness did not finish" }
        $lines = @(if (Test-Path -LiteralPath $Out) { Get-Content -LiteralPath $Out -Encoding UTF8 })
        $seen = @{}
        foreach ($line in $lines) { $name, $value = $line -split '=', 2; $seen[$name] = $value }
        [pscustomobject]@{ ExitCode = $process.ExitCode; Seen = $seen; Text = ($lines -join "`n") }
    }
    function Get-RunResult {
        $dir = @(Get-ChildItem -LiteralPath (Join-Path $StateRoot 'runs') -Directory)[-1].FullName
        Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
    }
}

Describe 'Ctrl+C while applying' {
    BeforeEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'reads Ctrl+C as a key while the trap is on, and turns it on again after a native program' {
        $run = Invoke-Harness 'trap'
        if ($run.Seen['redirected'] -eq 'True') { Set-ItResult -Skipped -Because 'the harness got no console of its own'; return }
        $run.Text | Should -Not -BeNullOrEmpty
        $run.Seen['enabled'] | Should -Be 'True'
        $run.Seen['pressedKey'] | Should -Be 'True'
        $run.Seen['requested'] | Should -Be 'True'
        $run.Seen['again'] | Should -Be 'False'
        $run.Seen['afterNative'] | Should -Be 'False'
        $run.Seen['rearmed'] | Should -Be 'True'
        $run.Seen['restored'] | Should -Be 'False'
    }

    It 'finishes the tweak in progress, leaves the rest out and exits with 2' {
        $run = Invoke-Harness 'key'
        if ($run.Seen['redirected'] -eq 'True') { Set-ItResult -Skipped -Because 'the harness got no console of its own'; return }
        $run.ExitCode | Should -Be 2 -Because $run.Text
        $run.Seen['completed'] | Should -Be 'True'
        $result = Get-RunResult
        ($result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/interrupted'
        $result.summary.interrupted | Should -Be 1
        (Get-Item -LiteralPath $Key).GetValueNames() -join ',' | Should -Be 'One'
    }

    It 'saves what was done and exits with 2 when Ctrl+C stops PowerShell itself, and the undo restores it' {
        $run = Invoke-Harness 'signal'
        if ($run.Seen['redirected'] -eq 'True') { Set-ItResult -Skipped -Because 'the harness got no console of its own'; return }
        $run.ExitCode | Should -Be 2 -Because $run.Text
        $run.Seen.ContainsKey('completed') | Should -BeFalse
        $result = Get-RunResult
        ($result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=failed/,test.two=skipped/interrupted'
        $result.results[0].error | Should -Match '-Undo can restore it'
        $undo = @(Invoke-TuneupUndo -Run (Resolve-TuneupRun -StateRoot $StateRoot -RunId 'last' -WarningAction SilentlyContinue) -WarningAction SilentlyContinue)
        ($undo | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.one=restored'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: FAIL en las tres pruebas de `Invoke-TuneupPlan stopped with Ctrl+C` (no existe `-StopRequested`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Interrupt.Tests.ps1`
Expected: FAIL: la consola oculta no encuentra `Enable-TuneupInterruptTrap` (el arnés escribe lo que vio en un archivo; la prueba falla en `enabled`).

- [ ] **Step 3: La trampa de Ctrl+C**

Crear `engine/Interrupt.ps1`:

```powershell
# Ctrl+C while tweaks are applied: the tweak in progress finishes, the rest is left out and the run
# ends with its normal report and exit code 2. While the trap is on, the console hands Ctrl+C to
# PowerShell as a key (TreatControlCAsInput) instead of stopping it; the apply looks for that key
# between two tweaks.
#
# A native program that runs in between (cmd.exe, sc.exe, DISM, winget) can set the console back to
# normal Ctrl+C handling, so every check turns the trap on again. A Ctrl+C that arrives while such a
# program runs stops the program and PowerShell at once: the apply then saves what it has from its
# finally block, and the journal, written before each change, still lets -Undo restore the tweak that
# was cut. Without a console (input redirected, as when another program runs tuneup.ps1 -Json) there
# is no key to read and Ctrl+C keeps its usual meaning.

function Enable-TuneupInterruptTrap {
    try {
        if ([Console]::IsInputRedirected) { return $null }
        $previous = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
        [pscustomobject]@{ PSTypeName = 'Tuneup.InterruptTrap'; Previous = $previous }
    } catch {
        # No console to configure (a host without one): Ctrl+C keeps its usual meaning.
        $null
    }
}

# True when Ctrl+C was pressed since the last check. Every other key typed meanwhile is dropped.
function Test-TuneupInterruptRequested {
    param([AllowNull()]$Trap)
    if ($null -eq $Trap) { return $false }
    $requested = $false
    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::C -and ($key.Modifiers -band [ConsoleModifiers]::Control)) { $requested = $true }
    }
    # A native program that ran since the last check may have turned the trap off.
    [Console]::TreatControlCAsInput = $true
    $requested
}

function Disable-TuneupInterruptTrap {
    param([AllowNull()]$Trap)
    if ($null -eq $Trap) { return }
    [Console]::TreatControlCAsInput = [bool]$Trap.Previous
}
```

- [ ] **Step 4: El ejecutor se detiene entre dos ajustes**

En `engine/Executor.ps1`, reemplazar la función `Invoke-TuneupPlan` completa (con su comentario) por:

```powershell
# Applies the plan in order. -StopRequested is asked before each tweak to apply: once it says yes
# (Ctrl+C, see Interrupt.ps1), that tweak and the rest are left out with the reason interrupted. Each
# result is also added to -Results when given, and -Progress.Current names the tweak being applied
# (from its journal entry to its result), so a caller whose pipeline was stopped can still tell what
# was done and which tweak was cut.
function Invoke-TuneupPlan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][string]$RunDir,
        [scriptblock]$StopRequested,
        [System.Collections.Generic.List[object]]$Results,
        [hashtable]$Progress
    )
    if ($null -eq $Results) { $Results = New-Object System.Collections.Generic.List[object] }
    if ($null -eq $Progress) { $Progress = @{} }
    $journal = Join-Path $RunDir 'snapshot.jsonl'
    $journalError = $null
    $interrupted = $false
    foreach ($item in $Plan) {
        $Progress.Current = $null
        if ($item.Action -ne 'apply') {
            $result = New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason
        } elseif ($interrupted -or ($StopRequested -and (& $StopRequested))) {
            $interrupted = $true
            $result = New-TuneupResult -Item $item -Status 'skipped' -Reason 'interrupted'
        } elseif ($journalError) {
            $result = New-TuneupResult -Item $item -Status 'skipped' -Reason 'journal-error' -ErrorText $journalError
        } else {
            $Progress.Current = $item.Id
            $result = Invoke-TuneupPlanItem -Item $item -Journal $journal -RunDir $RunDir
            if ($result.reason -eq 'journal-error') { $journalError = $result.error }
        }
        $Progress.Current = $null
        $Results.Add($result)
        $result
    }
}
```

En `engine/Executor.ps1`, agregar después de la función `Invoke-TuneupPlan`:

```powershell
# One tweak: read its state, journal it, apply it and check it.
function Invoke-TuneupPlanItem {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][string]$Journal, [Parameter(Mandatory)][string]$RunDir)
    $tweak = $Item.Tweak
    try {
        $state = Get-TuneupState -Tweak $tweak
    } catch {
        return (New-TuneupResult -Item $Item -Status 'failed' -ErrorText $_.Exception.Message)
    }
    try {
        Add-TuneupJournalEntry -Path $Journal -Tweak $tweak -State $state
    } catch {
        return (New-TuneupResult -Item $Item -Status 'skipped' -Reason 'journal-error' -ErrorText $_.Exception.Message)
    }
    try {
        # Set may report through New-TuneupOutcome that it changed something but could not finish
        # (partial) or that Windows asked for a restart; any other output is ignored.
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $tweak)
        if ($outcome.refused) {
            # A refusal is only believed when nothing changed: the state is read again and compared
            # with the one that was journaled. If it differs, the tweak is not noted as needing no
            # undo (-Undo can still restore it) and the run reports a failure.
            if (Test-TuneupStateUnchanged -Tweak $tweak -Before $state) {
                # Its journal entry stays (it was written first), and the tweak is noted as needing
                # no undo, so -Undo never calls its restore.
                Add-TuneupRefusedMark -RunDir $RunDir -Tweak $tweak
                return (New-TuneupResult -Item $Item -Status 'skipped' -Reason $outcome.reason -Detail $outcome.detail -Refused)
            }
            return (New-TuneupResult -Item $Item -Status 'failed' -ErrorText 'refused after changing; undo can restore it' -Detail $outcome.detail)
        }
        if ($outcome.partial) {
            $status = 'partial'
        } elseif ((Test-TuneupState -Tweak $tweak) -eq 'applied') {
            $status = 'applied'
        } else {
            $status = 'not-applied'
        }
        New-TuneupResult -Item $Item -Status $status -Reason $outcome.reason -Detail $outcome.detail -RebootRequired:$outcome.rebootRequired
    } catch {
        New-TuneupResult -Item $Item -Status 'failed' -ErrorText $_.Exception.Message
    }
}
```

- [ ] **Step 5: El reporte cuenta los interrumpidos**

En `engine/Output.ps1`, reemplazar la función `New-TuneupApplyReport` completa (con su comentario) por:

```powershell
function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment
    )
    # A tweak left out because its backup could not be written was not done: it is counted apart, and
    # so are the tweaks left out because the run was stopped with Ctrl+C. A tweak that refused to
    # change anything is counted apart from the skips of the plan.
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status -and $_.reason -ne 'journal-error' -and $_.reason -ne 'interrupted' -and $_.refused -ne $true }).Count }
    $interrupted = @($Results | Where-Object { $_.reason -eq 'interrupted' }).Count
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = ConvertTo-TuneupEnvironmentView -Environment $Environment
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)
        signOutRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.signOutRequired }).Count -gt 0)
        interrupted    = ($interrupted -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            partial       = & $count 'partial'
            notApplied    = & $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            refused       = @($Results | Where-Object { $_.status -eq 'skipped' -and $_.refused -eq $true }).Count
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
            interrupted   = $interrupted
        }
        results        = $Results
    }
}
```

En `engine/Output.ps1`, reemplazar la función `Get-TuneupApplyExitCode` completa (con su comentario) por:

```powershell
# 0: everything done. 2: not everything was completed (a partial, failed or ineffective tweak, a
# backup that could not be written after some change, or an unsaved result; read the summary).
# A tweak that refused to change anything (summary.refused) is an omission, like any skip: if
# everything else was done, the code stays 0 and the summary and the line of that tweak say why.
# 1: nothing was changed because the backups could not be written, or because Ctrl+C stopped the
# run before its first tweak. Tweaks left out by Ctrl+C after others were touched count as not done (2).
function Get-TuneupApplyExitCode {
    param([Parameter(Mandatory)]$Report, [switch]$ResultNotSaved)
    $summary = $Report.summary
    $interrupted = $(if ($summary.PSObject.Properties['interrupted']) { [int]$summary.interrupted } else { 0 })
    $touched = $summary.applied + $summary.partial + $summary.notApplied + $summary.failed
    if (($summary.journalErrors -or $interrupted) -and -not $touched) { return 1 }
    if ($summary.partial -or $summary.notApplied -or $summary.failed -or $summary.journalErrors -or $interrupted -or $ResultNotSaved) { return 2 }
    0
}
```

En `engine/Output.ps1`, reemplazar la función `Write-TuneupApplyReport` completa (con su comentario) por:

```powershell
function Write-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red'; 'skipped' = 'Yellow' }
    foreach ($result in $Report.results) {
        if ($result.reason -eq 'journal-error') {
            Write-Host ((Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key 'status.skipped'), $result.title) + ": $(Get-TuneupText -Key 'reason.journal-error')") -ForegroundColor Red
            if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
            continue
        }
        # Skips of the plan were already shown, and the tweaks left out by Ctrl+C are counted below; a
        # tweak that refused to change anything when it was applied is shown with its reason.
        if ($result.status -eq 'skipped' -and $result.refused -ne $true) { continue }
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.status -eq 'skipped' -and $result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
        if ($result.detail) { Write-Host "    $($result.detail)" -ForegroundColor Yellow }
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    $summary = $Report.summary
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.partial, $summary.notApplied, $summary.failed, $summary.skipped, $summary.refused)
    if ($summary.PSObject.Properties['interrupted'] -and $summary.interrupted) {
        Write-Host (Get-TuneupText -Key 'interrupted.summary' -Format $summary.interrupted) -ForegroundColor Yellow
    }
    Write-Host (Get-TuneupText -Key "restore.$($Report.restorePoint)")
    Write-Host (Get-TuneupText -Key 'run.saved' -Format $Report.runId, $Report.runDir)
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
    # A restart also signs the user out, so the sign-out line is only needed without one.
    elseif ($Report.signOutRequired) { Write-Host (Get-TuneupText -Key 'signOut') -ForegroundColor Yellow }
}
```

- [ ] **Step 6: Aplicar con la trampa, y lo que se guarda si PowerShell se detiene**

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupPlannedApply` completa (con su comentario) por:

```powershell
# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    # Ctrl+C stops the run between two tweaks (Interrupt.ps1). If it stops PowerShell itself, the
    # finally block saves what was done; the results and the tweak in progress are kept outside the
    # pipeline for that.
    $results = New-Object System.Collections.Generic.List[object]
    $progress = @{ Current = $null }
    $trap = Enable-TuneupInterruptTrap
    $applyArguments = @{
        Plan          = $Plan
        RunDir        = $run.Dir
        Results       = $results
        Progress      = $progress
        StopRequested = { Test-TuneupInterruptRequested -Trap $trap }
    }
    $finished = $false
    try {
        Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan @applyArguments } | Out-Null
        $finished = $true
    } finally {
        Disable-TuneupInterruptTrap -Trap $trap
        if (-not $finished) {
            Save-TuneupStoppedApply -Context $Context -Run $run -Plan $Plan -Results $results -Progress $progress -RestorePoint $restorePoint
        }
    }
    $report = New-TuneupApplyReport -Run $run -Results $results.ToArray() -RestorePoint $restorePoint -Environment $environment
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}
```

En `engine/Commands.ps1`, agregar después de la función `Invoke-TuneupPlannedApply`:

```powershell
# Ctrl+C reached PowerShell itself while a native program ran (Interrupt.ps1), or the apply failed
# outside any one tweak. What was done is saved as the result of the run: the tweak in progress is
# reported as failed (its journal entry lets -Undo restore it) and the rest as interrupted. The output
# is closed by then (a stopped pipeline), so only the host and the files can be written.
function Save-TuneupStoppedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][hashtable]$Progress,
        [Parameter(Mandatory)][string]$RestorePoint
    )
    $done = @($Results.ToArray())
    $doneIds = @($done | ForEach-Object { $_.id })
    $rest = @(foreach ($item in $Plan) {
        if ($doneIds -contains $item.Id) { continue }
        if ($item.Action -ne 'apply') { New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason }
        elseif ($item.Id -eq $Progress.Current) { New-TuneupResult -Item $item -Status 'failed' -ErrorText 'stopped while it was being applied; -Undo can restore it' }
        else { New-TuneupResult -Item $item -Status 'skipped' -Reason 'interrupted' }
    })
    $report = New-TuneupApplyReport -Run $Run -Results (@($done) + @($rest)) -RestorePoint $RestorePoint -Environment $Context.Environment
    $saved = $true
    try {
        Save-TuneupJson -Path (Join-Path $Run.Dir 'result.json') -Root $Run.Root -Object $report
    } catch {
        $saved = $false
    }
    $Context.Result = $report
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'interrupted.saved' -Format $Run.Id) }
}
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "reason.interrupted": "no se aplicó: la corrida se detuvo con Ctrl+C",
  "interrupted.summary": "Detenido con Ctrl+C: {0} ajustes no se aplicaron. Lo aplicado se puede deshacer con -Undo.",
  "interrupted.saved": "Detenido con Ctrl+C. El resultado de la corrida {0} quedó guardado; para deshacerla: .\\tuneup.ps1 -Undo {0}"
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "reason.interrupted": "not applied: the run was stopped with Ctrl+C",
  "interrupted.summary": "Stopped with Ctrl+C: {0} tweaks were not applied. What was applied can be undone with -Undo.",
  "interrupted.saved": "Stopped with Ctrl+C. The result of run {0} was saved; to undo it: .\\tuneup.ps1 -Undo {0}"
```

- [ ] **Step 7: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: PASS (`Tests Passed: 25, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: PASS (`Tests Passed: 64, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Interrupt.Tests.ps1`
Expected: PASS (`Tests Passed: 3, Failed: 0`), unos 15 segundos: se abren tres consolas ocultas. Si una prueba sale saltada con "the harness got no console of its own", el equipo no dio consola a la ventana oculta; en esta máquina y en `windows-latest` no debería pasar.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`Tests Passed: 59, Failed: 0, Skipped: 1`).

- [ ] **Step 8: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 9: Commit**

```bash
git add engine/Interrupt.ps1 engine/Executor.ps1 engine/Output.ps1 engine/Commands.ps1 i18n/es.json i18n/en.json tests/Executor.Tests.ps1 tests/Output.Tests.ps1 tests/Interrupt.Tests.ps1
git commit -m "feat: Ctrl+C termina el ajuste en curso y se detiene limpio"
```

---

### Task 6: `transcript.log` en cada corrida

**Files:**
- Create: `engine/Transcript.ps1`, `tests/Transcript.Tests.ps1`
- Modify: `engine/Commands.ps1` (`Invoke-TuneupUndoCommand`, `Invoke-TuneupApplyCommand`, `Invoke-TuneupPlannedApply`, `Save-TuneupStoppedApply`; nuevos `New-TuneupApplyRequest`, `Save-TuneupApplyTranscript`, `Save-TuneupUndoTranscript`), `i18n/es.json`, `i18n/en.json`, `tests/I18nCoverage.Tests.ps1`
- Test: `tests/Transcript.Tests.ps1`, `tests/I18nCoverage.Tests.ps1`

Diseño: no se usa `Start-Transcript` (guarda la cuenta, el equipo, la línea de comandos y todo lo de la pantalla, y la carpeta de máquina la puede leer Usuarios). `transcript.log` lo arma la herramienta con sus propios reportes: `Get-TuneupHostText` corre la función del reporte para personas y captura lo que escribe al host (`6>&1`), sin mostrarlo, así el texto es el mismo de la pantalla y existe también con `-Json`. Encabezado (versión, corrida, hora), lo pedido (`New-TuneupApplyRequest`: perfiles y listas; la Task 8 agrega `reapply`), el plan, el reporte y los avisos; cada `-Undo` de la corrida agrega su reporte. Se escribe con `Write-TuneupStateFile -Append` (mismas reglas de confianza). Si no se puede escribir es un aviso: la corrida sigue y el código no cambia.

`'transcript.log'` empieza como una clave de texto (`transcript.` pasa a ser un espacio de nombres de `i18n`), así que la prueba de cobertura deja de leer los nombres de archivo `.log`, como ya hacía con `.json`.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/Transcript.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-TestContext([switch]$Json) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context
    }
    function Get-Transcript($Context) {
        [System.IO.File]::ReadAllText((Join-Path $Context.Result.runDir 'transcript.log'))
    }
}

Describe 'transcript.log' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'keeps with the run what was asked for, the plan and the report, in the language of the run' {
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Exclude @('test.two') -Yes 6>$null
        $text = Get-Transcript $context
        $text | Should -Match ("windows-tuneup $([regex]::Escape((Get-TuneupVersion))) - run $($context.Result.runId) - ")
        $text | Should -Match 'Asked for: profiles extra; included -; excluded test.two'
        $text | Should -Match 'Plan: 2 to apply, 1 skipped'
        $text | Should -Match '\[applied\] Test three: settings'
        $text | Should -Match 'Applied: 2 \| Partial: 0'
    }

    It 'writes the text for people also with -Json, and adds each undo of the run' {
        $context = New-TestContext -Json
        Invoke-TuneupApplyCommand -Context $context -Yes | Out-Null
        $runDir = $context.Result.runDir
        $text = Get-Transcript $context
        $text | Should -Not -Match '"schemaVersion"'
        $text | Should -Match 'Applied: 2'
        Invoke-TuneupUndoCommand -Context $context -RunId 'last' | Out-Null
        $after = [System.IO.File]::ReadAllText((Join-Path $runDir 'transcript.log'))
        $after.StartsWith($text) | Should -BeTrue
        $after | Should -Match 'Undo with windows-tuneup'
        $after | Should -Match 'Restored: 2 \| Failed: 0 \| Skipped: 0'
    }

    It 'never writes the names of the machine or the account, nor the environment' {
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -Yes 6>$null
        $text = Get-Transcript $context
        $text | Should -Not -Match ([regex]::Escape($env:COMPUTERNAME))
        $text | Should -Not -Match ([regex]::Escape((Get-TestCurrentSid)))
        $text | Should -Not -Match '(?m)^(Username|RunAs User|Machine|Host Application|Process ID):'
    }

    It 'goes on with a warning when the transcript cannot be written' {
        $context = New-TestContext -Json
        Mock -ModuleName Tuneup Add-TuneupTranscript { throw 'disk full' }
        $json = Invoke-TuneupApplyCommand -Context $context -Yes | ConvertFrom-Json
        $context.ExitCode | Should -Be 0
        @($json.warnings) -join ' ' | Should -Match 'transcript of run .* could not be saved: disk full'
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Transcript.Tests.ps1`
Expected: FAIL: no existe `transcript.log` en la carpeta de la corrida (4 pruebas).

- [ ] **Step 3: El texto de la corrida**

Crear `engine/Transcript.ps1`:

```powershell
# transcript.log keeps, with each run, the text a person sees: the plan, the warnings before applying,
# each result, the summary and, later, each undo of the run. It is written by the tool from its own
# reports, never with Start-Transcript: that one also records the account, the machine, the command
# line and anything else on the screen, and Users can read the machine state folder. With -Json the
# transcript still gets the text for people.

# The lines that a step writes to the host, captured instead of shown.
function Get-TuneupHostText {
    param([Parameter(Mandatory)][scriptblock]$Step)
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($record in @(& $Step 6>&1)) {
        if ($record -isnot [System.Management.Automation.InformationRecord]) { continue }
        $data = $record.MessageData
        if ($data -is [System.Management.Automation.HostInformationMessage]) {
            $current += [string]$data.Message
            if ($data.NoNewLine) { continue }
        } else {
            $current += [string]$data
        }
        $lines.Add($current)
        $current = ''
    }
    if ($current) { $lines.Add($current) }
    $lines.ToArray()
}

function Add-TuneupTranscript {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $text = (@($Lines) -join [Environment]::NewLine) + [Environment]::NewLine
    Write-TuneupStateFile -Path (Join-Path $Run.Dir 'transcript.log') -Root $Run.Root -Append -Text $text
}

# The transcript of an apply: who asked for what (profiles and lists, never the command line), the
# plan, the warnings and the report.
function Get-TuneupApplyTranscript {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @()
    )
    $list = { param($values) $(if (@($values).Count) { @($values) -join ', ' } else { '-' }) }
    Get-TuneupText -Key 'transcript.header' -Format (Get-TuneupVersion), $Run.Id, (Get-Date).ToString('s')
    Get-TuneupText -Key "transcript.request.$($Request.Source)" -Format (& $list $Request.Profiles), (& $list $Request.Include), (& $list $Request.Exclude)
    ''
    $planArguments = @{ Plan = $Plan; Environment = $Environment }
    Get-TuneupHostText -Step { Write-TuneupPlanReport @planArguments }
    ''
    $reportArguments = @{ Report = $Report }
    Get-TuneupHostText -Step { Write-TuneupApplyReport @reportArguments }
    if (@($Warnings).Count) {
        ''
        Get-TuneupText -Key 'transcript.warnings'
        foreach ($warning in $Warnings) { "  - $warning" }
    }
}

function Get-TuneupUndoTranscript {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [AllowEmptyCollection()][string[]]$Warnings = @()
    )
    ''
    Get-TuneupText -Key 'transcript.undo' -Format (Get-TuneupVersion), (Get-Date).ToString('s')
    $reportArguments = @{ RunId = $Run.Id; Results = $Results }
    Get-TuneupHostText -Step { Write-TuneupUndoReport @reportArguments }
    if (@($Warnings).Count) {
        Get-TuneupText -Key 'transcript.warnings'
        foreach ($warning in $Warnings) { "  - $warning" }
    }
}
```

- [ ] **Step 4: Aplicar y deshacer lo escriben**

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupUndoCommand` completa (con su comentario) por:

```powershell
function Invoke-TuneupUndoCommand {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$RunId, [string]$TweakId)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $run = Invoke-TuneupContextStep -Context $Context -Step { Resolve-TuneupRun -StateRoot $Context.StateRoot -RunId $RunId }
    if (-not $run) {
        $missing = $(if ($RunId -eq 'last') { Get-TuneupText -Key 'undo.none' } else { Get-TuneupText -Key 'err.runNotFound' -Format $RunId })
        Write-TuneupCommandError -Context $Context -Message $missing
        return
    }
    # Machine-folder runs always need elevation; a -StateRoot run only for its machine tweaks.
    $needsAdmin = ($run.Root -eq 'machine')
    if (-not $needsAdmin) {
        # Its warnings come again, once, from the undo itself.
        $needsAdmin = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue } |
            Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.tweak }).Count -gt 0
    }
    if ($needsAdmin -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    # Arguments of a step go in a table: PSScriptAnalyzer does not see a parameter used only inside it.
    $undoArguments = @{ Run = $run; TweakId = $TweakId }
    $results = @(Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupUndo @undoArguments })
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupUndoTranscript -Context $Context -Run $run -Results $results }
    $Context.Result = $results
    Write-TuneupUndoReport -RunId $run.Id -Results $results -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupUndoExitCode -Results $results
}
```

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupApplyCommand` completa (con su comentario) por:

```powershell
function Invoke-TuneupApplyCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) {
        Write-TuneupCommandError -Context $Context -Message $unsupported
        return
    }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
        return
    }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $ProfileIds -Include $Include -Exclude $Exclude)
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $ProfileIds -Include $Include -Exclude $Exclude
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
}
```

En `engine/Commands.ps1`, agregar después de la función `Invoke-TuneupApplyCommand`:

```powershell
# What was asked for, for the transcript and the JSON report: profiles and the -Include and -Exclude
# lists, or a re-apply of what drifted.
function New-TuneupApplyRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('profiles', 'reapply')][string]$Source,
        [AllowEmptyCollection()][string[]]$Profiles = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @()
    )
    [pscustomobject]@{ Source = $Source; Profiles = [string[]]@($Profiles); Include = [string[]]@($Include); Exclude = [string[]]@($Exclude) }
}
```

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupPlannedApply` completa (con su comentario) por:

```powershell
# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    # Ctrl+C stops the run between two tweaks (Interrupt.ps1). If it stops PowerShell itself, the
    # finally block saves what was done; the results and the tweak in progress are kept outside the
    # pipeline for that.
    $results = New-Object System.Collections.Generic.List[object]
    $progress = @{ Current = $null }
    $trap = Enable-TuneupInterruptTrap
    $applyArguments = @{
        Plan          = $Plan
        RunDir        = $run.Dir
        Results       = $results
        Progress      = $progress
        StopRequested = { Test-TuneupInterruptRequested -Trap $trap }
    }
    $finished = $false
    try {
        Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan @applyArguments } | Out-Null
        $finished = $true
    } finally {
        Disable-TuneupInterruptTrap -Trap $trap
        if (-not $finished) {
            Save-TuneupStoppedApply -Context $Context -Run $run -Plan $Plan -Request $Request -Results $results -Progress $progress -RestorePoint $restorePoint
        }
    }
    $report = New-TuneupApplyReport -Run $run -Results $results.ToArray() -RestorePoint $restorePoint -Environment $environment
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyTranscript -Context $Context -Run $run -Request $Request -Plan $Plan -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}
```

En `engine/Commands.ps1`, agregar después de la función `Invoke-TuneupPlannedApply`:

```powershell
# The transcript is a convenience: when it cannot be written the run goes on, with a warning.
function Save-TuneupApplyTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Report
    )
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $Report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        Write-Warning "The transcript of run $($Run.Id) could not be saved: $($_.Exception.Message)"
    }
}

function Save-TuneupUndoTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Run, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupUndoTranscript -Run $Run -Results $Results -Warnings $Context.Warnings.ToArray())
    } catch {
        Write-Warning "The transcript of run $($Run.Id) could not be updated: $($_.Exception.Message)"
    }
}
```

En `engine/Commands.ps1`, reemplazar la función `Save-TuneupStoppedApply` completa (con su comentario) por:

```powershell
# Ctrl+C reached PowerShell itself while a native program ran (Interrupt.ps1), or the apply failed
# outside any one tweak. What was done is saved as the result of the run: the tweak in progress is
# reported as failed (its journal entry lets -Undo restore it) and the rest as interrupted. The output
# is closed by then (a stopped pipeline), so only the host and the files can be written.
function Save-TuneupStoppedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][hashtable]$Progress,
        [Parameter(Mandatory)][string]$RestorePoint
    )
    $done = @($Results.ToArray())
    $doneIds = @($done | ForEach-Object { $_.id })
    $rest = @(foreach ($item in $Plan) {
        if ($doneIds -contains $item.Id) { continue }
        if ($item.Action -ne 'apply') { New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason }
        elseif ($item.Id -eq $Progress.Current) { New-TuneupResult -Item $item -Status 'failed' -ErrorText 'stopped while it was being applied; -Undo can restore it' }
        else { New-TuneupResult -Item $item -Status 'skipped' -Reason 'interrupted' }
    })
    $report = New-TuneupApplyReport -Run $Run -Results (@($done) + @($rest)) -RestorePoint $RestorePoint -Environment $Context.Environment
    $saved = $true
    try {
        Save-TuneupJson -Path (Join-Path $Run.Dir 'result.json') -Root $Run.Root -Object $report
    } catch {
        $saved = $false
    }
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        # A missing transcript loses nothing that result.json and the journal do not keep.
        $null = $_
    }
    $Context.Result = $report
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'interrupted.saved' -Format $Run.Id) }
}
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "transcript.header": "windows-tuneup {0} - corrida {1} - {2}",
  "transcript.request.profiles": "Pedido: perfiles {0}; incluidos {1}; excluidos {2}",
  "transcript.request.reapply": "Pedido: volver a aplicar lo que Windows revirtió ({1})",
  "transcript.warnings": "Avisos:",
  "transcript.undo": "Deshacer con windows-tuneup {0} - {1}"
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "transcript.header": "windows-tuneup {0} - run {1} - {2}",
  "transcript.request.profiles": "Asked for: profiles {0}; included {1}; excluded {2}",
  "transcript.request.reapply": "Asked for: apply again what Windows reverted ({1})",
  "transcript.warnings": "Warnings:",
  "transcript.undo": "Undo with windows-tuneup {0} - {1}"
```

En `tests/I18nCoverage.Tests.ps1`, reemplazar:

```powershell
                # A file name such as run.json starts like a key but is not one.
                if ($match.Groups[1].Value -match '\.jsonl?$') { continue }
```

por:

```powershell
                # A file name such as run.json or transcript.log starts like a key but is not one.
                if ($match.Groups[1].Value -match '\.(jsonl?|log)$') { continue }
```

- [ ] **Step 5: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Transcript.Tests.ps1`
Expected: PASS (`Tests Passed: 4, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS (`Tests Passed: 4, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: PASS (`Tests Passed: 18, Failed: 0`).

- [ ] **Step 6: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 7: Commit**

```bash
git add engine/Transcript.ps1 engine/Commands.ps1 i18n/es.json i18n/en.json tests/Transcript.Tests.ps1 tests/I18nCoverage.Tests.ps1
git commit -m "feat: transcript.log con lo que se vio en cada corrida"
```

---

### Task 7: Avisos antes de aplicar y Restaurar sistema

**Files:**
- Create: `engine/Preflight.ps1`, `tests/Preflight.Tests.ps1`
- Modify: `engine/Output.ps1` (`Write-TuneupPlanReport`, `New-TuneupApplyReport`), `engine/Transcript.ps1` (`Get-TuneupApplyTranscript`), `engine/Commands.ps1` (`New-TuneupContext`, `Invoke-TuneupPlannedApply`, `Save-TuneupStoppedApply`, `Invoke-TuneupCli`), `i18n/es.json`, `i18n/en.json`
- Test: `tests/Preflight.Tests.ps1`

Reglas (sección 12, punto 3): solo se calculan cuando el plan cambia algo. **Ninguno detiene la corrida.** Con confirmación se muestran debajo del plan, con `!` delante (texto, no solo color); con `-Yes` se muestran y se sigue; con `-Json` van en `preflight` del documento `plan` y del `apply` (y en `result.json`). Restaurar sistema solo se lee elevado y con cambios de sistema: los volúmenes protegidos están en `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients`, que un usuario estándar no puede leer (comprobado: `SecurityException`), por eso sin elevar el estado es `unknown` y no hay aviso. Solo `restore-disabled` tiene algo que hacer: con confirmación interactiva se pregunta si activarlo (`Enable-ComputerRestore` en el disco del sistema) antes de "¿Aplicar N cambios?"; nunca con `-Yes` ni `-Json`. `untrusted-location` reutiliza `Test-TuneupTrustedExecutable` sobre `tuneup.ps1` y `engine\Tuneup.psm1` hasta la raíz del disco.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/Preflight.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-PlanItem([string]$Scope = 'user', [string]$Action = 'apply') {
        $tweak = $(if ($Scope -eq 'machine') { New-TestMachineTweak } else { New-TestTweak })
        [pscustomobject]@{ Id = $tweak.id; Tweak = $tweak; Action = $Action; Reason = $null }
    }
    function Get-PreflightId($Environment, $Plan, $ScriptRoot) {
        @(Get-TuneupPreflight -Environment $Environment -Plan $Plan -ScriptRoot $ScriptRoot | ForEach-Object { $_.id }) -join ','
    }
    function New-TestContext([switch]$Json, [object[]]$Answers = @()) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context.Environment.PendingReboot = $true
        $context
    }
}

Describe 'Get-TuneupPreflight' {
    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreState { 'enabled' }
        Mock -ModuleName Tuneup Test-TuneupTrustedLocation { $true }
    }

    It 'says nothing for a plan that changes nothing' {
        $environment = New-TestEnvironment -IsManaged $true
        $environment.PendingReboot = $true
        Get-PreflightId $environment @(New-PlanItem -Action 'skip') $null | Should -BeNullOrEmpty
    }

    It 'warns about a pending restart, a full disk and a managed machine' {
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 1.5 }
        $environment = New-TestEnvironment -IsManaged $true -IsAdmin $false
        $environment.PendingReboot = $true
        Get-PreflightId $environment @(New-PlanItem) $null | Should -Be 'pending-reboot,low-disk,managed-device'
        (Get-TuneupPreflight -Environment $environment -Plan @(New-PlanItem) | Where-Object { $_.id -eq 'low-disk' }).message | Should -Match '^1.5 GB are free on the system drive \(less than 2 GB\)'
    }

    It 'reads System Restore only for system changes made elevated' -TestCases @(
        @{ State = 'disabled'; Expected = 'restore-disabled' }
        @{ State = 'blocked'; Expected = 'restore-blocked' }
        @{ State = 'unknown'; Expected = '' }
        @{ State = 'enabled'; Expected = '' }
    ) {
        param($State, $Expected)
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreState { $State }
        Get-PreflightId (New-TestEnvironment -IsAdmin $true) @(New-PlanItem -Scope 'machine') $null | Should -Be $Expected
        Get-PreflightId (New-TestEnvironment -IsAdmin $true) @(New-PlanItem) $null | Should -BeNullOrEmpty
        Get-PreflightId (New-TestEnvironment -IsAdmin $false) @(New-PlanItem -Scope 'machine') $null | Should -BeNullOrEmpty
    }

    It 'warns when it runs elevated from a folder that others can change' {
        Mock -ModuleName Tuneup Test-TuneupTrustedLocation { $false }
        Get-PreflightId (New-TestEnvironment -IsAdmin $true) @(New-PlanItem) 'C:\Users\x\Downloads\windows-tuneup' | Should -Be 'untrusted-location'
        Get-PreflightId (New-TestEnvironment -IsAdmin $false) @(New-PlanItem) 'C:\Users\x\Downloads\windows-tuneup' | Should -BeNullOrEmpty
    }
}

Describe 'Get-TuneupSystemRestoreState' {
    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupSystemVolumeId { 'Volume{4474738e-ed83-4609-8f9a-d6862426c25e}' }
        Mock -ModuleName Tuneup Test-TuneupSystemRestorePolicy { $false }
    }

    It 'finds the system volume among the protected ones, whatever the case' {
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreEntry { '\\?\VOLUME{4474738E-ED83-4609-8F9A-D6862426C25E}\:(C%3A)' }
        Get-TuneupSystemRestoreState | Should -Be 'enabled'
    }

    It 'says disabled, or blocked by a policy, when the volume is not listed' {
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreEntry { '\\?\Volume{00000000-0000-0000-0000-000000000000}\:(D%3A)' }
        Get-TuneupSystemRestoreState | Should -Be 'disabled'
        Mock -ModuleName Tuneup Test-TuneupSystemRestorePolicy { $true }
        Get-TuneupSystemRestoreState | Should -Be 'blocked'
    }

    It 'says unknown when the list cannot be read' {
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreEntry { throw 'Access denied' }
        Get-TuneupSystemRestoreState | Should -Be 'unknown'
    }
}

Describe 'Preflight when applying' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Enable-TuneupSystemRestore { }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'puts the warnings in the JSON plan, in the apply report and in result.json, without stopping' {
        $context = New-TestContext -Json
        $plan = Invoke-TuneupApplyCommand -Context $context -PlanOnly | ConvertFrom-Json
        @($plan.preflight | ForEach-Object { $_.id }) | Should -Be @('pending-reboot')
        $apply = Invoke-TuneupApplyCommand -Context $context -Yes | ConvertFrom-Json
        $context.ExitCode | Should -Be 0
        @($apply.preflight | ForEach-Object { $_.id }) | Should -Be @('pending-reboot')
        $saved = Get-Content -LiteralPath (Join-Path $apply.runDir 'result.json') -Raw | ConvertFrom-Json
        $saved.preflight[0].id | Should -Be 'pending-reboot'
        [System.IO.File]::ReadAllText((Join-Path $apply.runDir 'transcript.log')) | Should -Match 'Windows has a restart pending'
    }

    It 'shows the warnings next to the plan before asking' {
        $context = New-TestContext -Answers @('n')
        $text = (Invoke-TuneupApplyCommand -Context $context 6>&1 | Out-String)
        $text | Should -Match 'Before applying:'
        $text | Should -Match '! Windows has a restart pending'
        $context.ExitCode | Should -Be 1
    }

    It 'offers to turn System Restore on before asking, and only turns it on with a yes' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('y', 'n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 1 -Exactly
        $context.Io.Output -join "`n" | Should -Match 'Turn on System Restore on .* before applying\? \(y/n\)'
        $context = New-TestContext -Answers @('n', 'n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'never asks nor turns System Restore on with -Yes' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext
        $text = (Invoke-TuneupApplyCommand -Context $context -Yes 6>&1 | Out-String)
        $text | Should -Match '! System Restore is turned off'
        $context.ExitCode | Should -Be 0
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Test-TuneupTrustedLocation' {
    It 'does not trust a copy in a folder that the user owns' {
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $copy 'engine') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $copy 'tuneup.ps1'), '')
        [System.IO.File]::WriteAllText((Join-Path $copy 'engine\Tuneup.psm1'), '')
        Test-TuneupTrustedLocation -ScriptRoot $copy | Should -BeFalse
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Preflight.Tests.ps1`
Expected: FAIL: `Get-TuneupPreflight` no se reconoce.

- [ ] **Step 3: Los avisos**

Crear `engine/Preflight.ps1`:

```powershell
# Warnings before applying (design, section 7: "warns and asks for confirmation"). None of them stops
# the run: a person sees them next to the plan and answers the confirmation, -Yes already means yes,
# and with -Json they go in the preflight array of the plan and apply documents, so whoever runs it
# (the Claude skill) reads them from -WhatIf -Json before asking.

$script:LowDiskThresholdGB = 2
# Value of HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients that lists the volumes with
# System Restore turned on; only administrators can read it.
$script:SystemRestoreClient = '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}'

function Get-TuneupSystemDrive {
    [System.IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))
}

function Get-TuneupSystemDriveFreeGB {
    $drive = New-Object System.IO.DriveInfo -ArgumentList (Get-TuneupSystemDrive)
    [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
}

# The volume GUID of the system drive (Volume{...}), as Windows lists it in SPP\Clients.
function Get-TuneupSystemVolumeId {
    $letter = (Get-TuneupSystemDrive).TrimEnd('\')
    $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$letter'" -ErrorAction Stop
    $match = [regex]::Match([string]$volume.DeviceID, 'Volume\{[0-9A-Fa-f-]+\}')
    $(if ($match.Success) { $match.Value } else { $null })
}

# The entries of SPP\Clients that list the protected volumes; fails when they cannot be read.
function Get-TuneupSystemRestoreEntry {
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    try { @($key.GetValue($script:SystemRestoreClient, @())) | ForEach-Object { [string]$_ } }
    finally { $key.Close() }
}

function Test-TuneupSystemRestorePolicy {
    $policy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction SilentlyContinue
    ($null -ne $policy) -and ($policy.DisableSR -eq 1 -or $policy.DisableConfig -eq 1)
}

# System Restore on the system drive: enabled, disabled, blocked (off, and a policy keeps it off) or
# unknown (not elevated, or the values could not be read).
function Get-TuneupSystemRestoreState {
    try {
        $entries = @(Get-TuneupSystemRestoreEntry)
        $volume = Get-TuneupSystemVolumeId
    } catch {
        return 'unknown'
    }
    if (-not $volume) { return 'unknown' }
    if (@($entries | Where-Object { $_.IndexOf($volume, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) { return 'enabled' }
    $(if (Test-TuneupSystemRestorePolicy) { 'blocked' } else { 'disabled' })
}

# Turns System Restore on for the system drive, only after the person said yes. It is a change of
# Windows that the run does not journal (the journal is about tweaks); System Properties turns it off.
function Enable-TuneupSystemRestore {
    Enable-ComputerRestore -Drive (Get-TuneupSystemDrive) -ErrorAction Stop
}

# Running elevated from a folder that others can change lets them run code as administrator (README,
# requirements). Checked on the script and the module, like a program that runs elevated.
function Test-TuneupTrustedLocation {
    param([Parameter(Mandatory)][string]$ScriptRoot)
    $root = [System.IO.Path]::GetPathRoot($ScriptRoot)
    (Test-TuneupTrustedExecutable -Path (Join-Path $ScriptRoot 'tuneup.ps1') -StopAt $root) -and
    (Test-TuneupTrustedExecutable -Path (Join-Path $ScriptRoot 'engine\Tuneup.psm1') -StopAt $root)
}

function New-TuneupPreflightItem {
    param([Parameter(Mandatory)][string]$Key, [object[]]$Format = @())
    [pscustomobject]@{ id = $Key.Substring('preflight.'.Length); message = Get-TuneupText -Key $Key -Format $Format }
}

# The warnings for a plan; nothing when the plan changes nothing.
function Get-TuneupPreflight {
    param(
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [string]$ScriptRoot
    )
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    if (-not $toApply.Count) { return }
    if ($Environment.PendingReboot) { New-TuneupPreflightItem -Key 'preflight.pending-reboot' }
    $free = Get-TuneupSystemDriveFreeGB
    if ($free -lt $script:LowDiskThresholdGB) { New-TuneupPreflightItem -Key 'preflight.low-disk' -Format $free, $script:LowDiskThresholdGB }
    # A restore point is only made for system changes, which need elevation; only then is it read.
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and $Environment.IsAdmin) {
        switch (Get-TuneupSystemRestoreState) {
            'disabled' { New-TuneupPreflightItem -Key 'preflight.restore-disabled' }
            'blocked' { New-TuneupPreflightItem -Key 'preflight.restore-blocked' }
        }
    }
    if ($Environment.IsManaged) { New-TuneupPreflightItem -Key 'preflight.managed-device' }
    if ($Environment.IsAdmin -and $ScriptRoot -and -not (Test-TuneupTrustedLocation -ScriptRoot $ScriptRoot)) {
        New-TuneupPreflightItem -Key 'preflight.untrusted-location' -Format $ScriptRoot
    }
}

function Write-TuneupPreflight {
    param([AllowEmptyCollection()][object[]]$Preflight = @())
    if (-not @($Preflight).Count) { return }
    Write-Host (Get-TuneupText -Key 'preflight.header') -ForegroundColor Yellow
    foreach ($item in $Preflight) { Write-Host "  ! $($item.message)" -ForegroundColor Yellow }
}

# Asks to turn System Restore on when it is off. True when it was turned on.
function Request-TuneupSystemRestore {
    param([Parameter(Mandatory)]$Io)
    if (-not (Read-TuneupConfirmation -Io $Io -Prompt (Get-TuneupText -Key 'preflight.enableRestore' -Format (Get-TuneupSystemDrive)))) {
        Write-TuneupIoLine -Io $Io -Text (Get-TuneupText -Key 'preflight.restoreKeptOff')
        return $false
    }
    try {
        Enable-TuneupSystemRestore
    } catch {
        Write-TuneupIoLine -Io $Io -Text (Get-TuneupText -Key 'preflight.restoreEnableFailed' -Format $_.Exception.Message)
        return $false
    }
    Write-TuneupIoLine -Io $Io -Text (Get-TuneupText -Key 'preflight.restoreEnabled')
    $true
}
```

- [ ] **Step 4: En el plan, el resultado y el texto de la corrida**

En `engine/Output.ps1`, reemplazar la función `Write-TuneupPlanReport` completa (con su comentario) por:

```powershell
function Write-TuneupPlanReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [switch]$Json
    )
    $items = @(ConvertTo-TuneupPlanView -Plan $Plan)
    $toApply = @($items | Where-Object { $_.action -eq 'apply' }).Count
    $requiresAdmin = @($Plan | Where-Object { $_.Action -eq 'apply' -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'plan'
            environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
            requiresAdmin = $requiresAdmin
            preflight     = @($Preflight)
            items         = $items
            summary       = [pscustomobject]@{ apply = $toApply; skip = $items.Count - $toApply }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'plan.header' -Format $toApply, ($items.Count - $toApply))
    foreach ($item in $items) {
        if ($item.action -eq 'apply') {
            $line = Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")
            if ($item.reason) { $line += ": $(Get-TuneupText -Key "reason.$($item.reason)")" }
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host (Get-TuneupText -Key 'plan.skip' -Format $item.title, (Get-TuneupText -Key "reason.$($item.reason)")) -ForegroundColor DarkGray
        }
    }
    if (-not $toApply) { Write-Host (Get-TuneupText -Key 'nothing') -ForegroundColor Green }
    if ($requiresAdmin -and -not $Environment.IsAdmin) { Write-Host (Get-TuneupText -Key 'plan.needsAdmin') -ForegroundColor Yellow }
    Write-TuneupPreflight -Preflight $Preflight
}
```

En `engine/Output.ps1`, reemplazar la función `New-TuneupApplyReport` completa (con su comentario) por:

```powershell
function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][object[]]$Preflight = @()
    )
    # A tweak left out because its backup could not be written was not done: it is counted apart, and
    # so are the tweaks left out because the run was stopped with Ctrl+C. A tweak that refused to
    # change anything is counted apart from the skips of the plan.
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status -and $_.reason -ne 'journal-error' -and $_.reason -ne 'interrupted' -and $_.refused -ne $true }).Count }
    $interrupted = @($Results | Where-Object { $_.reason -eq 'interrupted' }).Count
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = ConvertTo-TuneupEnvironmentView -Environment $Environment
        preflight      = @($Preflight)
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)
        signOutRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.signOutRequired }).Count -gt 0)
        interrupted    = ($interrupted -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            partial       = & $count 'partial'
            notApplied    = & $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            refused       = @($Results | Where-Object { $_.status -eq 'skipped' -and $_.refused -eq $true }).Count
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
            interrupted   = $interrupted
        }
        results        = $Results
    }
}
```

En `engine/Transcript.ps1`, reemplazar la función `Get-TuneupApplyTranscript` completa (con su comentario) por:

```powershell
# The transcript of an apply: who asked for what (profiles and lists, never the command line), the
# plan, the warnings and the report.
function Get-TuneupApplyTranscript {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @()
    )
    $list = { param($values) $(if (@($values).Count) { @($values) -join ', ' } else { '-' }) }
    Get-TuneupText -Key 'transcript.header' -Format (Get-TuneupVersion), $Run.Id, (Get-Date).ToString('s')
    Get-TuneupText -Key "transcript.request.$($Request.Source)" -Format (& $list $Request.Profiles), (& $list $Request.Include), (& $list $Request.Exclude)
    ''
    $planArguments = @{ Plan = $Plan; Environment = $Environment; Preflight = @($Report.preflight) }
    Get-TuneupHostText -Step { Write-TuneupPlanReport @planArguments }
    ''
    $reportArguments = @{ Report = $Report }
    Get-TuneupHostText -Step { Write-TuneupApplyReport @reportArguments }
    if (@($Warnings).Count) {
        ''
        Get-TuneupText -Key 'transcript.warnings'
        foreach ($warning in $Warnings) { "  - $warning" }
    }
}
```

- [ ] **Step 5: Aplicar los muestra y ofrece activar Restaurar sistema**

En `engine/Commands.ps1`, reemplazar la función `New-TuneupContext` completa (con su comentario) por:

```powershell
# What one invocation shares between its steps: JSON or text, the folders for testing, the warnings
# collected so far, the questions and answers (Io), the exit code and the last result. The exit code
# starts at 1 and every command sets 0 when it succeeds, so one that dies before reporting is a failure.
function New-TuneupContext {
    param([switch]$Json, $Io)
    [pscustomobject]@{
        PSTypeName   = 'Tuneup.Context'
        Json         = [bool]$Json
        StateRoot    = $null
        CatalogPath  = $null
        ProfilesPath = $null
        Force        = $false
        Warnings     = New-Object System.Collections.Generic.List[string]
        Environment  = $null
        ScriptRoot   = $null
        Io           = $(if ($null -ne $Io) { $Io } else { New-TuneupConsoleIo })
        ExitCode     = 1
        Result       = $null
    }
}
```

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupPlannedApply` completa (con su comentario) por:

```powershell
# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    # Warnings before applying (Preflight.ps1): none of them stops the run.
    $preflightArguments = @{ Environment = $environment; Plan = $Plan; ScriptRoot = $Context.ScriptRoot }
    $preflight = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupPreflight @preflightArguments })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight
        # The only warning with something to do about it here: System Restore can be turned on first.
        if (@($preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count) { Request-TuneupSystemRestore -Io $Context.Io | Out-Null }
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
    } elseif (-not $Context.Json) {
        Write-TuneupPreflight -Preflight $preflight
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    # Ctrl+C stops the run between two tweaks (Interrupt.ps1). If it stops PowerShell itself, the
    # finally block saves what was done; the results and the tweak in progress are kept outside the
    # pipeline for that.
    $results = New-Object System.Collections.Generic.List[object]
    $progress = @{ Current = $null }
    $trap = Enable-TuneupInterruptTrap
    $applyArguments = @{
        Plan          = $Plan
        RunDir        = $run.Dir
        Results       = $results
        Progress      = $progress
        StopRequested = { Test-TuneupInterruptRequested -Trap $trap }
    }
    $finished = $false
    try {
        Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan @applyArguments } | Out-Null
        $finished = $true
    } finally {
        Disable-TuneupInterruptTrap -Trap $trap
        if (-not $finished) {
            Save-TuneupStoppedApply -Context $Context -Run $run -Plan $Plan -Request $Request -Results $results -Progress $progress -RestorePoint $restorePoint -Preflight $preflight
        }
    }
    $report = New-TuneupApplyReport -Run $run -Results $results.ToArray() -RestorePoint $restorePoint -Environment $environment -Preflight $preflight
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyTranscript -Context $Context -Run $run -Request $Request -Plan $Plan -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}
```

En `engine/Commands.ps1`, reemplazar la función `Save-TuneupStoppedApply` completa (con su comentario) por:

```powershell
# Ctrl+C reached PowerShell itself while a native program ran (Interrupt.ps1), or the apply failed
# outside any one tweak. What was done is saved as the result of the run: the tweak in progress is
# reported as failed (its journal entry lets -Undo restore it) and the rest as interrupted. The output
# is closed by then (a stopped pipeline), so only the host and the files can be written.
function Save-TuneupStoppedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][hashtable]$Progress,
        [Parameter(Mandatory)][string]$RestorePoint,
        [AllowEmptyCollection()][object[]]$Preflight = @()
    )
    $done = @($Results.ToArray())
    $doneIds = @($done | ForEach-Object { $_.id })
    $rest = @(foreach ($item in $Plan) {
        if ($doneIds -contains $item.Id) { continue }
        if ($item.Action -ne 'apply') { New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason }
        elseif ($item.Id -eq $Progress.Current) { New-TuneupResult -Item $item -Status 'failed' -ErrorText 'stopped while it was being applied; -Undo can restore it' }
        else { New-TuneupResult -Item $item -Status 'skipped' -Reason 'interrupted' }
    })
    $report = New-TuneupApplyReport -Run $Run -Results (@($done) + @($rest)) -RestorePoint $RestorePoint -Environment $Context.Environment -Preflight $Preflight
    $saved = $true
    try {
        Save-TuneupJson -Path (Join-Path $Run.Dir 'result.json') -Root $Run.Root -Object $report
    } catch {
        $saved = $false
    }
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        # A missing transcript loses nothing that result.json and the journal do not keep.
        $null = $_
    }
    $Context.Result = $report
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'interrupted.saved' -Format $Run.Id) }
}
```

En `engine/Commands.ps1`, reemplazar:

```powershell
    $Context.Force = [bool]$Force
```

por:

```powershell
    $Context.Force = [bool]$Force
    $Context.ScriptRoot = $ScriptRoot
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "preflight.header": "Antes de aplicar:",
  "preflight.pending-reboot": "Windows tiene un reinicio pendiente. Conviene reiniciar antes: algunos cambios (servicios, características) pueden fallar o quedar a medias.",
  "preflight.low-disk": "Quedan {0} GB libres en el disco del sistema (menos de {1} GB): el punto de restauración y reinstalar apps al deshacer pueden fallar.",
  "preflight.restore-disabled": "Restaurar sistema está desactivado en el disco del sistema: no habrá punto de restauración, solo el respaldo propio de windows-tuneup (-Undo).",
  "preflight.restore-blocked": "Restaurar sistema está desactivado por una directiva: no habrá punto de restauración, solo el respaldo propio de windows-tuneup (-Undo).",
  "preflight.managed-device": "Este equipo lo administra una organización (dominio o Intune): las directivas se omiten y otros cambios pueden ir contra sus reglas. Consulta con quien lo administra.",
  "preflight.untrusted-location": "windows-tuneup corre como administrador desde {0}, una carpeta que otras cuentas pueden cambiar: instálalo en Program Files (README, Instalación).",
  "preflight.enableRestore": "¿Activar Restaurar sistema en {0} antes de aplicar? (s/n)",
  "preflight.restoreEnabled": "Restaurar sistema activado: se creará un punto de restauración.",
  "preflight.restoreKeptOff": "Se sigue sin punto de restauración, solo con el respaldo de windows-tuneup.",
  "preflight.restoreEnableFailed": "No se pudo activar Restaurar sistema: {0}"
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "preflight.header": "Before applying:",
  "preflight.pending-reboot": "Windows has a restart pending. It is better to restart first: some changes (services, features) may fail or be left half done.",
  "preflight.low-disk": "{0} GB are free on the system drive (less than {1} GB): the restore point, and reinstalling apps when undoing, may fail.",
  "preflight.restore-disabled": "System Restore is turned off on the system drive: there will be no restore point, only the backup of windows-tuneup itself (-Undo).",
  "preflight.restore-blocked": "System Restore is turned off by a policy: there will be no restore point, only the backup of windows-tuneup itself (-Undo).",
  "preflight.managed-device": "This PC is managed by an organization (domain or Intune): policies are skipped and other changes may go against its rules. Check with whoever manages it.",
  "preflight.untrusted-location": "windows-tuneup runs as administrator from {0}, a folder that other accounts can change: install it under Program Files (README, Installation).",
  "preflight.enableRestore": "Turn on System Restore on {0} before applying? (y/n)",
  "preflight.restoreEnabled": "System Restore turned on: a restore point will be created.",
  "preflight.restoreKeptOff": "Going on without a restore point, with the backup of windows-tuneup only.",
  "preflight.restoreEnableFailed": "System Restore could not be turned on: {0}"
```

- [ ] **Step 6: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Preflight.Tests.ps1`
Expected: PASS (`Tests Passed: 15, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Transcript.Tests.ps1`
Expected: PASS (`Tests Passed: 4, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`Tests Passed: 59, Failed: 0, Skipped: 1`). El arreglo `warnings` de los JSON no cambia: los avisos van en `preflight`.

- [ ] **Step 7: Lectura real, sin cambiar nada**

En una ventana de Windows PowerShell 5.1 abierta en la raíz del repo, primero sin elevar y después como administrador:

```powershell
Import-Module .\engine\Tuneup.psm1 -Force
& (Get-Module Tuneup) { "volume=$(Get-TuneupSystemVolumeId) restore=$(Get-TuneupSystemRestoreState) free=$(Get-TuneupSystemDriveFreeGB) trusted=$(Test-TuneupTrustedLocation -ScriptRoot (Get-Location).Path)" }
```

Expected sin elevar: `restore=unknown` (así salió en la copia de prueba, con `trusted=False` por estar en `Documents`). Elevado: `restore` tiene que coincidir con Propiedades del sistema > Protección del sistema para `C:` (`enabled` si dice "Activada", `disabled` si dice "Desactivada"). **No se pudo comprobar elevado al escribir el plan.** Si quien ejecuta el plan no puede elevar, pedirle al usuario que corra el bloque en un PowerShell como administrador y diga qué sale. Si no coincide con Propiedades del sistema, el formato de `SPP\Clients` es otro: no commitear la Task 7 hasta corregir `Get-TuneupSystemRestoreEntry` y `Get-TuneupSystemRestoreState` (y su prueba) con lo que muestre, elevado, `(Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients').GetValue('{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}')`.

- [ ] **Step 8: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 9: Commit**

```bash
git add engine/Preflight.ps1 engine/Output.ps1 engine/Transcript.ps1 engine/Commands.ps1 i18n/es.json i18n/en.json tests/Preflight.Tests.ps1
git commit -m "feat: avisos antes de aplicar y Restaurar sistema con permiso"
```

---

### Task 8: `-Status -Reapply`

**Files:**
- Modify: `engine/Arguments.ps1`, `engine/Planner.ps1` (`New-TuneupPlan -NoBase`), `engine/Output.ps1` (`Write-TuneupPlanReport`, `New-TuneupApplyReport`: `source`), `engine/Commands.ps1` (`Invoke-TuneupStatusCommand`, nuevo `Invoke-TuneupReapply`, `New-TuneupContextPlan`, `Invoke-TuneupPlannedApply`, `Save-TuneupStoppedApply`, `Invoke-TuneupCli`), `tuneup.ps1`, `i18n/es.json`, `i18n/en.json`
- Test: `tests/Arguments.Tests.ps1`, `tests/Planner.Tests.ps1`, `tests/Commands.Tests.ps1`, `tests/Cli.Tests.ps1`

Reglas (sección 12, punto 6): `-Reapply` exige `-Status`; con él, `-Status` acepta `-Yes` y `-WhatIf` (no `-Profile`, `-Include` ni `-Exclude`). Se planifica con el catálogo actual solo lo que está en `drift`, por nombre y sin `base` (`-NoBase`), así un ajuste que pregunta o que un perfil conserva también vuelve; la compatibilidad sigue rigiendo. Es una corrida nueva con `source` = `reapply` en los documentos `plan` y `apply`. Sin `-Json`, primero se ve el estado; sin nada revertido, "Nada que volver a aplicar".

- [ ] **Step 1: Pruebas que fallan**

En `tests/Arguments.Tests.ps1`, reemplazar:

```powershell
        @{ Name = 'measure with compare and idle time'; Present = @('Measure', 'Compare', 'IdleSeconds') }
    ) {
```

por:

```powershell
        @{ Name = 'measure with compare and idle time'; Present = @('Measure', 'Compare', 'IdleSeconds') }
        @{ Name = 'a re-apply'; Present = @('Status', 'Reapply') }
        @{ Name = 'a re-apply without asking'; Present = @('Status', 'Reapply', 'Yes') }
        @{ Name = 'the plan of a re-apply'; Present = @('Status', 'Reapply', 'WhatIf') }
    ) {
```

En `tests/Arguments.Tests.ps1`, reemplazar:

```powershell
        @{ Present = @('Health', 'Include'); Expected = '-Health -Include' }
    ) {
```

por:

```powershell
        @{ Present = @('Health', 'Include'); Expected = '-Health -Include' }
        @{ Present = @('Reapply'); Expected = '-Reapply (-Status)' }
        @{ Present = @('Status', 'Yes'); Expected = '-Status -Yes' }
        @{ Present = @('Status', 'Reapply', 'Profile'); Expected = '-Status -Profile' }
        @{ Present = @('Status', 'Reapply', 'Exclude', 'Yes'); Expected = '-Status -Exclude' }
    ) {
```

En `tests/Planner.Tests.ps1`, agregar antes de `It 'resolves profile aliases case-insensitively' {`:

```powershell
    It 'plans only what it names, without the base profile, with -NoBase' {
        $plan = @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -Include @('ui.b', 'apps.onedrive') -Environment (New-TestEnvironment) -TestState $NotApplied -NoBase)
        ($plan | ForEach-Object { "$($_.Id)=$($_.Action)" }) -join ',' | Should -Be 'ui.b=apply,apps.onedrive=apply'
        @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -Environment (New-TestEnvironment) -TestState $NotApplied -NoBase).Count | Should -Be 0
    }
```

En `tests/Commands.Tests.ps1`, agregar antes de `Describe 'Invoke-TuneupCli' {`:

```powershell
Describe 'Re-applying what drifted' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'applies again, as a new run, only the tweaks that Windows reverted' {
        $context = New-TestContext -Json
        $first = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Yes })[0]
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $documents = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Yes })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'apply'
        $documents[0].source | Should -Be 'reapply'
        $documents[0].runId | Should -Not -Be $first.runId
        ($documents[0].results | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.one=applied'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        $status = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })[0]
        @($status.items | Where-Object { $_.status -ne 'ok' }).Count | Should -Be 0
    }

    It 'shows the plan of a re-apply with -PlanOnly and says when nothing drifted' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes } | Out-Null
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -PlanOnly })[0]
        $plan.command | Should -Be 'plan'
        $plan.source | Should -Be 'reapply'
        @($plan.items).Count | Should -Be 0
        $human = New-TestContext
        $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 6>&1 | Out-String)
        $text | Should -Match 'Tweaks applied by windows-tuneup:'
        $human.Io.Output -join "`n" | Should -Match 'Nothing to apply again: Windows reverted no tweak.'
        $human.ExitCode | Should -Be 0
    }

    It 'asks before re-applying and leaves out, with a warning, a tweak the catalog no longer has' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Include @('test.three') -Yes } | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        Set-ItemProperty -LiteralPath $Key -Name 'Three' -Value 5
        $catalog = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $catalog | Out-Null
        $source = Get-Content -LiteralPath (Join-Path $Fixtures 'catalog\test.json') -Raw | ConvertFrom-Json
        $source.tweaks = @($source.tweaks | Where-Object { $_.id -ne 'test.three' })
        [System.IO.File]::WriteAllText((Join-Path $catalog 'test.json'), ($source | ConvertTo-Json -Depth 10))
        # The profile that names test.three goes too, or the catalog check would fail first.
        $profiles = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $profiles | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $Fixtures 'profiles') -Filter '*.json' | Where-Object { $_.Name -ne 'extra.json' } |
            Copy-Item -Destination $profiles
        $human = New-TestContext -Answers @('y')
        $human.CatalogPath = $catalog
        $human.ProfilesPath = $profiles
        $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 3>&1 6>&1 | Out-String)
        $text | Should -Match 'Tweak test.three was reverted but is no longer in the catalog'
        $text | Should -Match 'Plan: 1 to apply'
        $human.Io.Output -join "`n" | Should -Match 'Apply 1 changes\? \(y/n\)'
        $human.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        (Get-ItemProperty -LiteralPath $Key).Three | Should -Be 5
    }
}
```

En `tests/Cli.Tests.ps1`, agregar antes de `It 'undoes the last run' {`:

```powershell
    It 're-applies what drifted with -Status -Reapply -Yes' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $result = Invoke-Tuneup @('-Status', '-Reapply', '-Yes', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.source | Should -Be 'reapply'
        Get-Ids $json.results | Should -Be 'test.one'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }
```

En `tests/Cli.Tests.ps1`, reemplazar:

```powershell
        @{ Arguments = @('-Measure', '-Yes') }
    ) {
```

por:

```powershell
        @{ Arguments = @('-Measure', '-Yes') }
        @{ Arguments = @('-Reapply') }
        @{ Arguments = @('-Status', '-Yes') }
        @{ Arguments = @('-Status', '-Reapply', '-Profile', 'extra') }
    ) {
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Arguments.Tests.ps1`
Expected: FAIL en `accepts a re-apply...` y `rejects -Reapply (-Status)`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: FAIL en las tres pruebas de `Re-applying what drifted` (`-Reapply` no existe).

- [ ] **Step 3: Parámetros y planificador**

En `engine/Arguments.ps1`, reemplazar:

```powershell
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure' }
```

por:

```powershell
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure'; Reapply = 'Status' }
# Options of applying that an option of a command brings back: -Status -Reapply applies again what
# drifted, so it takes -Yes and -WhatIf (and still not -Profile, -Include or -Exclude).
$script:CliApplyingOptions = @{ Reapply = @('Yes', 'WhatIf') }
```

En `engine/Arguments.ps1`, reemplazar:

```powershell
    if ($commands.Count -eq 1) {
        $extra = @($script:CliApplyOptions | Where-Object { $Present -contains $_ })
```

por:

```powershell
    if ($commands.Count -eq 1) {
        $allowed = @($script:CliApplyingOptions.Keys | Where-Object { $Present -contains $_ } | ForEach-Object { $script:CliApplyingOptions[$_] })
        $extra = @($script:CliApplyOptions | Where-Object { $Present -contains $_ -and $allowed -notcontains $_ })
```

En `engine/Planner.ps1`, reemplazar:

```powershell
        [Parameter(Mandatory)][scriptblock]$TestState,
        [switch]$Interactive
    )
```

por:

```powershell
        [Parameter(Mandatory)][scriptblock]$TestState,
        [switch]$Interactive,
        # Only what -ProfileIds and -Include name, without the base profile: re-applying what drifted.
        [switch]$NoBase
    )
```

En `engine/Planner.ps1`, reemplazar:

```powershell
    foreach ($name in @('base') + @($ProfileIds)) {
```

por:

```powershell
    foreach ($name in @($(if (-not $NoBase) { 'base' })) + @($ProfileIds)) {
```

- [ ] **Step 4: `source` en los documentos**

En `engine/Output.ps1`, reemplazar la función `Write-TuneupPlanReport` completa (con su comentario) por:

```powershell
function Write-TuneupPlanReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [ValidateSet('profiles', 'reapply')][string]$Source = 'profiles',
        [switch]$Json
    )
    $items = @(ConvertTo-TuneupPlanView -Plan $Plan)
    $toApply = @($items | Where-Object { $_.action -eq 'apply' }).Count
    $requiresAdmin = @($Plan | Where-Object { $_.Action -eq 'apply' -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'plan'
            source        = $Source
            environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
            requiresAdmin = $requiresAdmin
            preflight     = @($Preflight)
            items         = $items
            summary       = [pscustomobject]@{ apply = $toApply; skip = $items.Count - $toApply }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'plan.header' -Format $toApply, ($items.Count - $toApply))
    foreach ($item in $items) {
        if ($item.action -eq 'apply') {
            $line = Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")
            if ($item.reason) { $line += ": $(Get-TuneupText -Key "reason.$($item.reason)")" }
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host (Get-TuneupText -Key 'plan.skip' -Format $item.title, (Get-TuneupText -Key "reason.$($item.reason)")) -ForegroundColor DarkGray
        }
    }
    if (-not $toApply) { Write-Host (Get-TuneupText -Key 'nothing') -ForegroundColor Green }
    if ($requiresAdmin -and -not $Environment.IsAdmin) { Write-Host (Get-TuneupText -Key 'plan.needsAdmin') -ForegroundColor Yellow }
    Write-TuneupPreflight -Preflight $Preflight
}
```

En `engine/Output.ps1`, reemplazar la función `New-TuneupApplyReport` completa (con su comentario) por:

```powershell
function New-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$RestorePoint,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [ValidateSet('profiles', 'reapply')][string]$Source = 'profiles'
    )
    # A tweak left out because its backup could not be written was not done: it is counted apart, and
    # so are the tweaks left out because the run was stopped with Ctrl+C. A tweak that refused to
    # change anything is counted apart from the skips of the plan.
    $count = { param($status) @($Results | Where-Object { $_.status -eq $status -and $_.reason -ne 'journal-error' -and $_.reason -ne 'interrupted' -and $_.refused -ne $true }).Count }
    $interrupted = @($Results | Where-Object { $_.reason -eq 'interrupted' }).Count
    [pscustomobject]@{
        schemaVersion  = 1
        command        = 'apply'
        source         = $Source
        runId          = $Run.Id
        runDir         = $Run.Dir
        finishedAt     = (Get-Date).ToString('s')
        environment    = ConvertTo-TuneupEnvironmentView -Environment $Environment
        preflight      = @($Preflight)
        restorePoint   = $RestorePoint
        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)
        signOutRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.signOutRequired }).Count -gt 0)
        interrupted    = ($interrupted -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            partial       = & $count 'partial'
            notApplied    = & $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            refused       = @($Results | Where-Object { $_.status -eq 'skipped' -and $_.refused -eq $true }).Count
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
            interrupted   = $interrupted
        }
        results        = $Results
    }
}
```

- [ ] **Step 5: El comando**

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupStatusCommand` completa (con su comentario) por:

```powershell
# -Reapply applies again, as a new run, the tweaks that Windows reverted (drift), with the same
# confirmation, -Yes and -WhatIf as applying profiles. People see the status first; with -Json the
# output is the plan or apply document of the re-apply (source reapply).
function Invoke-TuneupStatusCommand {
    param([Parameter(Mandatory)]$Context, [switch]$Reapply, [switch]$PlanOnly, [switch]$Yes)
    $items = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupStatus -StateRoot $Context.StateRoot })
    $Context.Result = $items
    if (-not $Reapply) {
        Write-TuneupStatusReport -Items $items -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    if (-not $Context.Json) { Write-TuneupStatusReport -Items $items }
    Invoke-TuneupReapply -Context $Context -Items $items -PlanOnly:$PlanOnly -Yes:$Yes
}
```

En `engine/Commands.ps1`, agregar después de la función `Invoke-TuneupStatusCommand`:

```powershell
# Plans again, from the catalog of now, the tweaks whose status is drift: only them (no base profile)
# and by name, so a tweak that asks first or is kept by a profile is applied again too; the
# compatibility checks still apply. A drifted tweak that the catalog no longer has is left out with a
# warning: undoing the run that applied it restores it.
function Invoke-TuneupReapply {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items, [switch]$PlanOnly, [switch]$Yes)
    $drifted = @($Items | Where-Object { $_.status -eq 'drift' } | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    if (-not $drifted.Count -and -not $Context.Json) {
        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'reapply.none')
        $Context.ExitCode = 0
        return
    }
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) {
        Write-TuneupCommandError -Context $Context -Message $unsupported
        return
    }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
        return
    }
    $known = @{}
    foreach ($tweak in $definition.Catalog) { $known[[string]$tweak.id] = $true }
    $missing = @($drifted | Where-Object { -not $known.ContainsKey($_) })
    if ($missing.Count) {
        Invoke-TuneupContextStep -Context $Context -Step {
            foreach ($id in $missing) { Write-Warning "Tweak $id was reverted but is no longer in the catalog: undo the run that applied it to restore it" }
        }
    }
    $ids = @($drifted | Where-Object { $known.ContainsKey($_) })
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -Include $ids -NoBase)
    $request = New-TuneupApplyRequest -Source 'reapply' -Include $ids
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
}
```

En `engine/Commands.ps1`, reemplazar la función `New-TuneupContextPlan` completa (con su comentario) por:

```powershell
function New-TuneupContextPlan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Definition,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [switch]$Interactive,
        [switch]$NoBase
    )
    $planArguments = @{
        Catalog     = $Definition.Catalog
        Profiles    = $Definition.Profiles
        ProfileIds  = $ProfileIds
        Include     = $Include
        Exclude     = $Exclude
        Environment = Get-TuneupContextEnvironment -Context $Context
        Interactive = $Interactive
        NoBase      = $NoBase
        TestState   = { param($tweak) Test-TuneupState -Tweak $tweak }
    }
    @(Invoke-TuneupContextStep -Context $Context -Step { New-TuneupPlan @planArguments })
}
```

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupPlannedApply` completa (con su comentario) por:

```powershell
# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    # Warnings before applying (Preflight.ps1): none of them stops the run.
    $preflightArguments = @{ Environment = $environment; Plan = $Plan; ScriptRoot = $Context.ScriptRoot }
    $preflight = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupPreflight @preflightArguments })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight -Source $Request.Source -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight
        # The only warning with something to do about it here: System Restore can be turned on first.
        if (@($preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count) { Request-TuneupSystemRestore -Io $Context.Io | Out-Null }
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
    } elseif (-not $Context.Json) {
        Write-TuneupPreflight -Preflight $preflight
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    # Ctrl+C stops the run between two tweaks (Interrupt.ps1). If it stops PowerShell itself, the
    # finally block saves what was done; the results and the tweak in progress are kept outside the
    # pipeline for that.
    $results = New-Object System.Collections.Generic.List[object]
    $progress = @{ Current = $null }
    $trap = Enable-TuneupInterruptTrap
    $applyArguments = @{
        Plan          = $Plan
        RunDir        = $run.Dir
        Results       = $results
        Progress      = $progress
        StopRequested = { Test-TuneupInterruptRequested -Trap $trap }
    }
    $finished = $false
    try {
        Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan @applyArguments } | Out-Null
        $finished = $true
    } finally {
        Disable-TuneupInterruptTrap -Trap $trap
        if (-not $finished) {
            Save-TuneupStoppedApply -Context $Context -Run $run -Plan $Plan -Request $Request -Results $results -Progress $progress -RestorePoint $restorePoint -Preflight $preflight
        }
    }
    $report = New-TuneupApplyReport -Run $run -Results $results.ToArray() -RestorePoint $restorePoint -Environment $environment -Preflight $preflight -Source $Request.Source
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyTranscript -Context $Context -Run $run -Request $Request -Plan $Plan -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}
```

En `engine/Commands.ps1`, reemplazar la función `Save-TuneupStoppedApply` completa (con su comentario) por:

```powershell
# Ctrl+C reached PowerShell itself while a native program ran (Interrupt.ps1), or the apply failed
# outside any one tweak. What was done is saved as the result of the run: the tweak in progress is
# reported as failed (its journal entry lets -Undo restore it) and the rest as interrupted. The output
# is closed by then (a stopped pipeline), so only the host and the files can be written.
function Save-TuneupStoppedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][hashtable]$Progress,
        [Parameter(Mandatory)][string]$RestorePoint,
        [AllowEmptyCollection()][object[]]$Preflight = @()
    )
    $done = @($Results.ToArray())
    $doneIds = @($done | ForEach-Object { $_.id })
    $rest = @(foreach ($item in $Plan) {
        if ($doneIds -contains $item.Id) { continue }
        if ($item.Action -ne 'apply') { New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason }
        elseif ($item.Id -eq $Progress.Current) { New-TuneupResult -Item $item -Status 'failed' -ErrorText 'stopped while it was being applied; -Undo can restore it' }
        else { New-TuneupResult -Item $item -Status 'skipped' -Reason 'interrupted' }
    })
    $report = New-TuneupApplyReport -Run $Run -Results (@($done) + @($rest)) -RestorePoint $RestorePoint -Environment $Context.Environment -Preflight $Preflight -Source $Request.Source
    $saved = $true
    try {
        Save-TuneupJson -Path (Join-Path $Run.Dir 'result.json') -Root $Run.Root -Object $report
    } catch {
        $saved = $false
    }
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        # A missing transcript loses nothing that result.json and the journal do not keep.
        $null = $_
    }
    $Context.Result = $report
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'interrupted.saved' -Format $Run.Id) }
}
```

En `engine/Commands.ps1`, reemplazar:

```powershell
        [switch]$Status,
        [string]$Undo,
```

por:

```powershell
        [switch]$Status,
        [switch]$Reapply,
        [string]$Undo,
```

En `engine/Commands.ps1`, reemplazar:

```powershell
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $present += 'Status' }
```

por:

```powershell
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $present += 'Status' }
    if ($PSBoundParameters.ContainsKey('Reapply') -and $Reapply) { $present += 'Reapply' }
```

En `engine/Commands.ps1`, reemplazar:

```powershell
    if ($Status) { Invoke-TuneupStatusCommand -Context $Context; return }
```

por:

```powershell
    if ($Status) { Invoke-TuneupStatusCommand -Context $Context -Reapply:$Reapply -PlanOnly:$PlanOnly -Yes:$Yes; return }
```

En `tuneup.ps1`, reemplazar:

```powershell
    [switch]$Status,
    [string]$Undo,
```

por:

```powershell
    [switch]$Status,
    [switch]$Reapply,
    [string]$Undo,
```

En `tuneup.ps1`, reemplazar:

```powershell
.EXAMPLE
    .\tuneup.ps1 -Undo last
```

por:

```powershell
.EXAMPLE
    .\tuneup.ps1 -Undo last
.EXAMPLE
    .\tuneup.ps1 -Status -Reapply
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "reapply.none": "Nada que volver a aplicar: Windows no revirtió ningún ajuste."
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "reapply.none": "Nothing to apply again: Windows reverted no tweak."
```

- [ ] **Step 6: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Arguments.Tests.ps1`
Expected: PASS (`Tests Passed: 29, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: PASS (`Tests Passed: 45, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: PASS (`Tests Passed: 21, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`Tests Passed: 63, Failed: 0, Skipped: 1`).

- [ ] **Step 7: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 8: Commit**

```bash
git add engine/Arguments.ps1 engine/Planner.ps1 engine/Output.ps1 engine/Commands.ps1 tuneup.ps1 i18n/es.json i18n/en.json tests/Arguments.Tests.ps1 tests/Planner.Tests.ps1 tests/Commands.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat: -Status -Reapply vuelve a aplicar lo que Windows revirtió"
```

---

### Task 8b: Correcciones de la revisión de las Tasks 5 a 8

**Files:**
- Modify: `engine/Executor.ps1` (`Invoke-TuneupPlan`, `Invoke-TuneupPlanItem`), `engine/Output.ps1` (nuevo `Write-TuneupRunResult`, `Save-TuneupApplyReport`), `engine/Transcript.ps1` (nuevo `Hide-TuneupPersonalData`, `Add-TuneupTranscript`), `engine/Preflight.ps1` (`Test-TuneupTrustedLocation`, nuevo `Test-TuneupTrustedEntry`, aviso `untrusted-location`), `engine/Planner.ps1` (`New-TuneupPlan -Candidates`), `engine/Commands.ps1` (`Invoke-TuneupReapply`, `New-TuneupContextPlan`, `Invoke-TuneupPlannedApply`, `Save-TuneupStoppedApply`), `i18n/es.json`, `i18n/en.json`
- Test: `tests/Interrupt.Tests.ps1`, `tests/Executor.Tests.ps1`, `tests/Planner.Tests.ps1`, `tests/Output.Tests.ps1`, `tests/Preflight.Tests.ps1`, `tests/Commands.Tests.ps1`

La revisión de las Tasks 5 a 8 pidió estos ocho cambios; se hicieron en un commit aparte, con pruebas primero:

1. **Ctrl+C avisa.** Al empezar a aplicar, si hay trampa (consola propia) y no es `-Json`, una línea por `Io` dice que Ctrl+C se detiene después del ajuste en curso y que Ctrl+Pausa (Ctrl+Break) interrumpe de inmediato (`interrupted.hint`). La consola oculta de `Interrupt.Tests.ps1` comprueba que `TreatControlCAsInput` vale `False` otra vez al terminar `Invoke-TuneupCli`.
2. **Un ajuste cortado antes de su entrada del diario no se informa como "fallido, -Undo puede restaurarlo".** `-Progress` suma `Journaled` (verdadero desde que la entrada del diario está escrita hasta el resultado); `Save-TuneupStoppedApply` informa `failed` solo si estaba en curso y con diario, y en otro caso lo deja `interrupted`. Además el resultado se agrega a `-Results` antes de borrar `Current`, así una detención entre las dos líneas no pierde un ajuste ya hecho.
3. **Un error que no es Ctrl+C no pasa por el mensaje "Detenido con Ctrl+C".** `Invoke-TuneupPlannedApply` distingue la detención de PowerShell (`PipelineStoppedException`, que no es un error de la aplicación) de cualquier otra excepción, que guarda en `$failure`. `Save-TuneupStoppedApply -Failure` guarda igual `result.json`, pero con el error: el ajuste en curso con diario queda `failed` con "<error>; -Undo can restore it", el resto `skipped` con el motivo nuevo `aborted`, y el mensaje es `aborted.saved`. La excepción sigue su camino y `Invoke-TuneupGuarded` la informa como siempre.
4. **Ni `transcript.log` ni `result.json` ni el JSON llevan la cuenta o el perfil.** `Hide-TuneupPersonalData` escribe la carpeta del perfil como `%USERPROFILE%` y el nombre de la cuenta (3 letras o más, como palabra entera) como `%USERNAME%`. Pasa por ahí el aviso `untrusted-location` (que lleva la carpeta desde donde corre), cada línea de `Add-TuneupTranscript` y el JSON de `result.json` (`Write-TuneupRunResult -JsonEscaped`, que también cubre `runDir`). La salida estándar con `-Json` conserva el `runDir` real: es para quien lo ejecutó. El aviso pasa a decir "una carpeta (o archivos suyos) que procesos sin elevar, incluidos los tuyos, pueden cambiar".
5. **`untrusted-location` revisa también `engine`, `catalog`, `profiles`, `actions` e `i18n`**: cada archivo y carpeta debe ser de SYSTEM, TrustedInstaller o Administradores y no dar derechos de cambio a nadie más ni ser un vínculo (`Test-TuneupTrustedEntry`); uno solo basta para el aviso.
6. **Restaurar sistema se ofrece después de confirmar.** Se pregunta después de "¿Aplicar N cambios?", así rechazar la aplicación no deja nada activado; si se activa, el aviso `restore-disabled` sale del `preflight` del reporte, de `result.json` y del transcript.
7. **`-Status -Reapply` no vuelve a aplicar solo un ajuste `ask` ni uno de riesgo alto.** `New-TuneupPlan -Candidates` los planifica como un perfil (sin pedirlos por nombre): quedan `skip` con `needs-confirmation` o `high-risk-not-requested`, y con `-Yes` sin `-Json` se listan por `Io` (`reapply.leftOut`); el plan y el resultado JSON los traen. El orden es el de las corridas que los aplicaron, no el alfabético. Sin nada revertido, el texto distingue "nada que volver a aplicar" de "hay ajustes que sin administrador no se pueden comprobar" (`reapply.noneUnverified`). El menú (Tasks 9 y 10) es quien pregunta de a uno por los `ask` y los de riesgo alto al reaplicar.
8. **Contrato JSON** (Task 15): con `-Json`, si Ctrl+C detiene PowerShell mientras corre un programa nativo, la salida estándar queda vacía, el código es `2` y el documento está en `result.json`; si llega como tecla entre dos ajustes, sale el documento `apply` normal con `interrupted: true`.

Se probó que lanzar un `PipelineStoppedException` de verdad dentro de una prueba detiene a Pester entero: la ruta de Ctrl+C se prueba llamando a `Save-TuneupStoppedApply` (lo que llama el `finally`), y la consola oculta de `Interrupt.Tests.ps1` cubre la señal real.

- [ ] **Step 1: Pruebas que fallan**

En `tests/Interrupt.Tests.ps1`, reemplazar:

```powershell
    Save-Line 'completed=True'
```
por:
```powershell
    Save-Line "trapAfter=$([Console]::TreatControlCAsInput)"
    Save-Line 'completed=True'
```
En `tests/Interrupt.Tests.ps1`, reemplazar:
```powershell
        $run.Seen['completed'] | Should -Be 'True'
        $result = Get-RunResult
```
por:
```powershell
        $run.Seen['completed'] | Should -Be 'True'
        # The trap is off again once the command is done, so the console keeps its usual Ctrl+C.
        $run.Seen['trapAfter'] | Should -Be 'False'
        $result = Get-RunResult
```
Agregar al final de `tests/Executor.Tests.ps1`:
```powershell
Describe 'Invoke-TuneupPlan -Progress and the journal' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'says the tweak was not journaled while its state is read, and journaled once it is saved' {
        $progress = @{}
        Mock -ModuleName Tuneup Get-TuneupState { throw "journaled=$($progress.Journaled)" } -ParameterFilter { $Tweak.id -eq 'test.one' }
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { throw "journaled=$($progress.Journaled)" } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir -Progress $progress)
        $results[0].error | Should -Be 'journaled=False'
        $results[1].error | Should -Be 'journaled=True'
        $progress.Journaled | Should -BeFalse
    }
}
```
En `tests/Planner.Tests.ps1`, agregar antes de `It 'resolves profile aliases case-insensitively' {`:
```powershell
    It 'plans -Candidates in their order, like a profile does: not asked for by name, so asks and high risk stay out' {
        $plan = @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -Candidates @('ui.b', 'gaming.vbs-off', 'apps.onedrive', 'ui.a') -Environment (New-TestEnvironment) -TestState $NotApplied -NoBase)
        ($plan | ForEach-Object { "$($_.Id)=$($_.Action)/$($_.Reason)" }) -join ',' |
            Should -Be 'ui.b=apply/,gaming.vbs-off=skip/high-risk-not-requested,apps.onedrive=skip/needs-confirmation,ui.a=apply/'
        { New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -Candidates @('ui.nope') -Environment (New-TestEnvironment) -TestState $NotApplied } | Should -Throw '*ui.nope*'
    }
```
En `tests/Output.Tests.ps1`, reemplazar:
```powershell
        Mock -ModuleName Tuneup Save-TuneupJson { throw [System.UnauthorizedAccessException]::new('Access denied') }
```
por:
```powershell
        Mock -ModuleName Tuneup Write-TuneupRunResult { throw [System.UnauthorizedAccessException]::new('Access denied') }
```
En `tests/Preflight.Tests.ps1`, reemplazar la prueba `It 'offers to turn System Restore on before asking, and only turns it on with a yes'` completa por estas tres:
```powershell
    It 'offers to turn System Restore on only after the apply is confirmed, and drops the warning once it is on' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('y', 'y')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 1 -Exactly
        $output = $context.Io.Output -join "`n"
        $output | Should -Match 'Apply 2 changes\? \(y/n\)[\s\S]*Turn on System Restore on .* before applying\? \(y/n\)'
        @($context.Result.preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count | Should -Be 0
        $saved = Get-Content -LiteralPath (Join-Path $context.Result.runDir 'result.json') -Raw | ConvertFrom-Json
        @($saved.preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count | Should -Be 0
    }

    It 'keeps the warning when System Restore is not turned on' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('y', 'n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 0 -Exactly
        @($context.Result.preflight | ForEach-Object { $_.id }) | Should -Be @('restore-disabled')
    }

    It 'never asks about System Restore when the apply is declined' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 0 -Exactly
        $context.Io.Output -join "`n" | Should -Not -Match 'Turn on System Restore'
        $context.ExitCode | Should -Be 1
    }
```
Agregar al final de `tests/Preflight.Tests.ps1`:
```powershell
Describe 'Locations in what the run keeps' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Test-TuneupTrustedLocation { $false }
        $script:Profile = $env:USERPROFILE.TrimEnd('\')
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'writes the untrusted folder with the profile folder as %USERPROFILE% and rewords the warning' {
        $items = @(Get-TuneupPreflight -Environment (New-TestEnvironment -IsAdmin $true) -Plan @(New-PlanItem) -ScriptRoot (Join-Path $Profile 'Downloads\windows-tuneup'))
        $items.Count | Should -Be 1
        $items[0].message | Should -Match '%USERPROFILE%\\Downloads\\windows-tuneup'
        $items[0].message | Should -Not -Match ([regex]::Escape($Profile))
        $items[0].message | Should -Match 'that non-elevated processes \(including your own\) can change'
    }

    It 'never writes the account name nor the profile folder in transcript.log or result.json, from a profile folder' {
        $context = New-TestContext -Json
        $context.Environment = New-TestEnvironment -IsAdmin $true
        $context.ScriptRoot = Join-Path $Profile "Downloads\$env:USERNAME\windows-tuneup"
        Invoke-TuneupApplyCommand -Context $context -Yes | Out-Null
        $context.ExitCode | Should -Be 0
        $runDir = $context.Result.runDir
        # The run folder of this test is under the profile too, so the paths in the files are real ones.
        $runDir | Should -Match ([regex]::Escape($Profile))
        foreach ($name in 'transcript.log', 'result.json') {
            $text = [System.IO.File]::ReadAllText((Join-Path $runDir $name))
            $text | Should -Match '%USERPROFILE%' -Because $name
            $text | Should -Not -Match ('(?i)' + [regex]::Escape($Profile)) -Because $name
            $text | Should -Not -Match ('(?i)' + [regex]::Escape($Profile.Replace('\', '\\'))) -Because $name
            $text | Should -Not -Match ('(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:USERNAME) + '(?![A-Za-z0-9])') -Because $name
        }
        [System.IO.File]::ReadAllText((Join-Path $runDir 'transcript.log')) | Should -Match 'non-elevated processes'
    }
}

Describe 'Hide-TuneupPersonalData' {
    It 'replaces the profile folder and the account name, whatever the case' {
        $text = "Folder $($env:USERPROFILE.ToLowerInvariant())\AppData of $($env:USERNAME.ToUpperInvariant())"
        Hide-TuneupPersonalData -Text $text | Should -Be 'Folder %USERPROFILE%\AppData of %USERNAME%'
    }

    It 'replaces the profile folder as it is written in JSON' {
        $json = ConvertTo-Json -InputObject ([pscustomobject]@{ dir = (Join-Path $env:USERPROFILE 'x') })
        $hidden = Hide-TuneupPersonalData -Text $json -JsonEscaped
        ($hidden | ConvertFrom-Json).dir | Should -Be '%USERPROFILE%\x'
    }

    It 'leaves a word that only contains the name alone' {
        Hide-TuneupPersonalData -Text "$($env:USERNAME)s and x$($env:USERNAME)" | Should -Be "$($env:USERNAME)s and x$($env:USERNAME)"
    }

    It 'gives back text without either of them untouched' {
        Hide-TuneupPersonalData -Text 'Applied: 2 | Partial: 0' | Should -Be 'Applied: 2 | Partial: 0'
        Hide-TuneupPersonalData -Text '' | Should -Be ''
    }
}

Describe 'Test-TuneupTrustedLocation and the folders the tool reads' {
    BeforeEach {
        $script:Copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Copy -Force | Out-Null
        # The program files themselves are taken as trusted, so only the other folders decide.
        Mock -ModuleName Tuneup Test-TuneupTrustedExecutable { $true }
    }

    It 'trusts a location with nothing else to read' {
        Test-TuneupTrustedLocation -ScriptRoot $Copy | Should -BeTrue
    }

    It 'does not trust a location when <Folder> is a folder that the user owns' -TestCases @(
        @{ Folder = 'catalog' }
        @{ Folder = 'profiles' }
        @{ Folder = 'actions' }
        @{ Folder = 'i18n' }
        @{ Folder = 'engine' }
    ) {
        param($Folder)
        $path = Join-Path $Copy $Folder
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $path 'x.json'), '{}')
        Test-TuneupTrustedLocation -ScriptRoot $Copy | Should -BeFalse
    }
}
```
En `tests/Commands.Tests.ps1`, agregar dentro de `Describe 'Re-applying what drifted'`, después de su última prueba:
```powershell
    BeforeAll {
        # The fixture catalog and profiles plus four tweaks of the re-apply: two plain ones (applied in the
        # order b, a, which is not the alphabetical one), one that asks first and one of high risk.
        function New-ReapplyDefinition {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $dir 'catalog'), (Join-Path $dir 'profiles') -Force | Out-Null
            Copy-Item -Path (Join-Path $Fixtures 'catalog\*.json') -Destination (Join-Path $dir 'catalog')
            Copy-Item -Path (Join-Path $Fixtures 'profiles\*.json') -Destination (Join-Path $dir 'profiles')
            $extra = @(
                (New-TestTweak -Id 'rea.b' -Set ([pscustomobject]@{ path = $Key; name = 'B'; kind = 'DWord'; value = 1 })),
                (New-TestTweak -Id 'rea.a' -Set ([pscustomobject]@{ path = $Key; name = 'A'; kind = 'DWord'; value = 1 })),
                (New-TestTweak -Id 'rea.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 })),
                (New-TestTweak -Id 'rea.high' -Risk 'high' -Set ([pscustomobject]@{ path = $Key; name = 'High'; kind = 'DWord'; value = 1 }))
            )
            [System.IO.File]::WriteAllText((Join-Path $dir 'catalog\rea.json'), (ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = $extra }) -Depth 10))
            $dir
        }

        # The four tweaks applied by name and then reverted by Windows.
        function Initialize-Reverted([string]$Dir) {
            $context = New-TestContext -Json
            $context.CatalogPath = Join-Path $Dir 'catalog'
            $context.ProfilesPath = Join-Path $Dir 'profiles'
            Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Include @('rea.b', 'rea.a', 'rea.ask', 'rea.high') -Yes } | Out-Null
            foreach ($name in 'B', 'A', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        }
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'applies again, as a new run, only the tweaks that Windows reverted' {
        $context = New-TestContext -Json
        $first = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Yes })[0]
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $documents = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Yes })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'apply'
        $documents[0].source | Should -Be 'reapply'
        $documents[0].runId | Should -Not -Be $first.runId
        ($documents[0].results | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.one=applied'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        $status = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })[0]
        @($status.items | Where-Object { $_.status -ne 'ok' }).Count | Should -Be 0
    }

    It 'shows the plan of a re-apply with -PlanOnly and says when nothing drifted' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes } | Out-Null
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -PlanOnly })[0]
        $plan.command | Should -Be 'plan'
        $plan.source | Should -Be 'reapply'
        @($plan.items).Count | Should -Be 0
        $human = New-TestContext
        $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 6>&1 | Out-String)
        $text | Should -Match 'Tweaks applied by windows-tuneup:'
        $human.Io.Output -join "`n" | Should -Match 'Nothing to apply again: Windows reverted no tweak.'
        $human.ExitCode | Should -Be 0
    }

    It 'asks before re-applying and leaves out, with a warning, a tweak the catalog no longer has' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Include @('test.three') -Yes } | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        Set-ItemProperty -LiteralPath $Key -Name 'Three' -Value 5
        $catalog = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $catalog | Out-Null
        $source = Get-Content -LiteralPath (Join-Path $Fixtures 'catalog\test.json') -Raw | ConvertFrom-Json
        $source.tweaks = @($source.tweaks | Where-Object { $_.id -ne 'test.three' })
        [System.IO.File]::WriteAllText((Join-Path $catalog 'test.json'), ($source | ConvertTo-Json -Depth 10))
        # The profile that names test.three goes too, or the catalog check would fail first.
        $profiles = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $profiles | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $Fixtures 'profiles') -Filter '*.json' | Where-Object { $_.Name -ne 'extra.json' } |
            Copy-Item -Destination $profiles
        $human = New-TestContext -Answers @('y')
        $human.CatalogPath = $catalog
        $human.ProfilesPath = $profiles
        $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 3>&1 6>&1 | Out-String)
        $text | Should -Match 'Tweak test.three was reverted but is no longer in the catalog'
        $text | Should -Match 'Plan: 1 to apply'
        $human.Io.Output -join "`n" | Should -Match 'Apply 1 changes\? \(y/n\)'
        $human.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        (Get-ItemProperty -LiteralPath $Key).Three | Should -Be 5
    }

    It 'leaves out a tweak that asks first or has high risk, in the order of the run, and says why' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        $document = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Yes })[0]
        ($document.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' |
            Should -Be 'rea.b=applied/,rea.a=applied/,rea.ask=skipped/needs-confirmation,rea.high=skipped/high-risk-not-requested'
        $values = Get-ItemProperty -LiteralPath $Key
        "$($values.B),$($values.A),$($values.Ask),$($values.High)" | Should -Be '1,1,5,5'
    }

    It 'gives the same plan, in the same order, with -PlanOnly' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -PlanOnly })[0]
        ($plan.items | ForEach-Object { "$($_.id)=$($_.action)/$($_.reason)" }) -join ',' |
            Should -Be 'rea.b=apply/,rea.a=apply/,rea.ask=skip/needs-confirmation,rea.high=skip/high-risk-not-requested'
    }

    It 'lists what it left out when it runs with -Yes and no JSON' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $human = New-TestContext
        $human.CatalogPath = Join-Path $dir 'catalog'
        $human.ProfilesPath = Join-Path $dir 'profiles'
        Invoke-TuneupStatusCommand -Context $human -Reapply -Yes 6>$null
        $text = $human.Io.Output -join "`n"
        $text | Should -Match 'Title rea\.ask: needs confirmation'
        $text | Should -Match 'Title rea\.high: high risk'
        $text | Should -Not -Match 'Title rea\.b'
        $human.ExitCode | Should -Be 0
    }

    It 'does not say there is nothing to apply again when some tweaks need administrator to be checked' {
        Mock -ModuleName Tuneup Get-TuneupStatus {
            @([pscustomobject]@{ id = 'x.one'; title = 'One'; status = 'ok'; runId = 'r' }, [pscustomobject]@{ id = 'x.two'; title = 'Two'; status = 'needs-admin'; runId = 'r' })
        }
        $human = New-TestContext
        Invoke-TuneupStatusCommand -Context $human -Reapply 6>$null
        $text = $human.Io.Output -join "`n"
        $text | Should -Match 'Nothing to apply again among what could be checked, but 1 tweaks need administrator'
        $text | Should -Not -Match 'Windows reverted no tweak'
        $human.ExitCode | Should -Be 0
    }
```
Agregar al final de `tests/Commands.Tests.ps1`:
```powershell
Describe 'An apply that stops before it ends' {
    BeforeAll {
        # What the run saves when the apply fails: test.one was applied, test.two was in progress.
        function Get-FailedResult([bool]$Journaled) {
            $script:stop.Journaled = $Journaled
            $context = New-TestContext
            { Invoke-TuneupApplyCommand -Context $context -Yes 6>$null } | Should -Throw
            $dir = @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName
            [pscustomobject]@{
                Context = $context
                Result  = (Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json)
                Text    = ($context.Io.Output -join "`n")
            }
        }

        # What the run saves when Ctrl+C stops PowerShell itself. Stopping the pipeline of a test would
        # stop the test run, so the function that the apply calls from its finally block is called here.
        function Get-CtrlCResult([bool]$Journaled) {
            $context = New-TestContext
            $plan = @(New-TuneupContextPlan -Context $context -Definition (Import-TuneupContextDefinition -Context $context))
            $run = New-TuneupRun -StateRoot $Root
            $results = New-Object System.Collections.Generic.List[object]
            $results.Add((New-TuneupResult -Item $plan[0] -Status 'applied'))
            $progress = @{ Current = $plan[1].Id; Journaled = $Journaled }
            Save-TuneupStoppedApply -Context $context -Run $run -Plan $plan -Request (New-TuneupApplyRequest -Source 'profiles') `
                -Results $results -Progress $progress -RestorePoint 'not-needed'
            [pscustomobject]@{
                Context = $context
                Result  = (Get-Content -LiteralPath (Join-Path $run.Dir 'result.json') -Raw | ConvertFrom-Json)
                Text    = ($context.Io.Output -join "`n")
            }
        }
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        $script:stop = @{ Journaled = $true }
        $stop = $script:stop
        Mock -ModuleName Tuneup Invoke-TuneupPlan {
            $Results.Add((New-TuneupResult -Item $Plan[0] -Status 'applied'))
            $Progress.Current = $Plan[1].Id
            $Progress.Journaled = $stop.Journaled
            throw 'boom'
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'with Ctrl+C reports the tweak it cut as failed when it was journaled' {
        $stopped = Get-CtrlCResult $true
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=failed/'
        $stopped.Result.results[1].error | Should -Match '-Undo can restore it'
        $stopped.Text | Should -Match 'Stopped with Ctrl\+C'
        $stopped.Context.ExitCode | Should -Be 2
    }

    It 'with Ctrl+C before the journal entry leaves the tweak out, as interrupted, with nothing to undo' {
        $stopped = Get-CtrlCResult $false
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/interrupted'
        $stopped.Result.summary.interrupted | Should -Be 1
        $stopped.Result.interrupted | Should -BeTrue
    }

    It 'with any other error does not say it was Ctrl+C, and saves the error' {
        $stopped = Get-FailedResult $true
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=failed/'
        $stopped.Result.results[1].error | Should -Be 'boom; -Undo can restore it'
        $stopped.Result.interrupted | Should -BeFalse
        $stopped.Text | Should -Not -Match 'Ctrl\+C'
        $stopped.Text | Should -Match 'The run stopped because of an error'
    }

    It 'with another error before the journal entry leaves the tweak out as aborted' {
        $stopped = Get-FailedResult $false
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/aborted'
        $stopped.Result.summary.interrupted | Should -Be 0
    }
}

Describe 'The Ctrl+C hint' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Test-TuneupInterruptRequested { $false }
        Mock -ModuleName Tuneup Disable-TuneupInterruptTrap { }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'says once, through Io, how Ctrl+C and Ctrl+Break work while the trap is on' {
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { [pscustomobject]@{ Previous = $false } }
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -Yes 6>$null
        @($context.Io.Output | Where-Object { $_ -match 'Ctrl\+C stops after the tweak in progress; Ctrl\+Break interrupts at once' }).Count | Should -Be 1
    }

    It 'says nothing without a console to trap, or with -Json' {
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { $null }
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -Yes 6>$null
        $context.Io.Output -join "`n" | Should -Not -Match 'Ctrl'
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { [pscustomobject]@{ Previous = $false } }
        $json = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $json -Yes } | Out-Null
        $json.Io.Output -join "`n" | Should -Not -Match 'Ctrl'
    }
}
```
- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: FAIL en las pruebas nuevas (no existen `-Candidates`, `Hide-TuneupPersonalData`, `-Failure`...).

- [ ] **Step 3: Ejecutor, resultado y transcript**

En `engine/Executor.ps1`, reemplazar la función `Invoke-TuneupPlan` completa (con su comentario) por:

```powershell
# Applies the plan in order. -StopRequested is asked before each tweak to apply: once it says yes
# (Ctrl+C, see Interrupt.ps1), that tweak and the rest are left out with the reason interrupted. Each
# result is also added to -Results when given, and -Progress names the tweak being applied
# (Current, from before its state is read to its result) and whether its journal entry was already
# written (Journaled), so a caller whose pipeline was stopped can still tell what was done, which
# tweak was cut and whether -Undo can restore it. A result is added to -Results before Current is
# cleared, so a stop in between never loses a tweak that was done.
function Invoke-TuneupPlan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][string]$RunDir,
        [scriptblock]$StopRequested,
        [System.Collections.Generic.List[object]]$Results,
        [hashtable]$Progress
    )
    if ($null -eq $Results) { $Results = New-Object System.Collections.Generic.List[object] }
    if ($null -eq $Progress) { $Progress = @{} }
    $journal = Join-Path $RunDir 'snapshot.jsonl'
    $journalError = $null
    $interrupted = $false
    foreach ($item in $Plan) {
        $Progress.Current = $null
        $Progress.Journaled = $false
        if ($item.Action -ne 'apply') {
            $result = New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason
        } elseif ($interrupted -or ($StopRequested -and (& $StopRequested))) {
            $interrupted = $true
            $result = New-TuneupResult -Item $item -Status 'skipped' -Reason 'interrupted'
        } elseif ($journalError) {
            $result = New-TuneupResult -Item $item -Status 'skipped' -Reason 'journal-error' -ErrorText $journalError
        } else {
            $Progress.Current = $item.Id
            $result = Invoke-TuneupPlanItem -Item $item -Journal $journal -RunDir $RunDir -Progress $Progress
            if ($result.reason -eq 'journal-error') { $journalError = $result.error }
        }
        $Results.Add($result)
        $Progress.Current = $null
        $Progress.Journaled = $false
        $result
    }
}
```
En `engine/Executor.ps1`, reemplazar la línea de parámetros de `Invoke-TuneupPlanItem`:
```powershell
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][string]$Journal, [Parameter(Mandatory)][string]$RunDir)
```
por:
```powershell
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][string]$Journal, [Parameter(Mandatory)][string]$RunDir, [hashtable]$Progress)
```
En `engine/Executor.ps1`, dentro de `Invoke-TuneupPlanItem`, reemplazar:
```powershell
        return (New-TuneupResult -Item $Item -Status 'skipped' -Reason 'journal-error' -ErrorText $_.Exception.Message)
    }
    try {
```
por:
```powershell
        return (New-TuneupResult -Item $Item -Status 'skipped' -Reason 'journal-error' -ErrorText $_.Exception.Message)
    }
    if ($null -ne $Progress) { $Progress.Journaled = $true }
    try {
```
En `engine/Output.ps1`, agregar antes de `Save-TuneupApplyReport` y reemplazar esa función completa por:
```powershell
# Writes result.json, with the profile folder and the account name hidden (Hide-TuneupPersonalData):
# the file is meant to be read and shared, and the run folder it names is under the profile of the
# account. Fails when it cannot be written.
function Write-TuneupRunResult {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Report)
    $json = Hide-TuneupPersonalData -Text (ConvertTo-Json -InputObject $Report -Depth 10) -JsonEscaped
    Write-TuneupStateFile -Path (Join-Path $Run.Dir 'result.json') -Text $json -Root $Run.Root
}

function Save-TuneupApplyReport {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Report)
    # The changes are already made; losing result.json must not hide the report of what was done.
    try {
        Write-TuneupRunResult -Run $Run -Report $Report
        $true
    } catch {
        Write-Warning "The result of run $($Run.Id) could not be saved: $($_.Exception.Message)"
        $false
    }
}
```
En `engine/Transcript.ps1`, agregar antes de `Get-TuneupHostText` (con su comentario):
```powershell
# The text with the profile folder of the account shown as %USERPROFILE% and the account name shown as
# %USERNAME%, wherever they are. What a run keeps for people to read and share (the transcript,
# result.json, the warnings of a preflight) goes through here, so a bug report does not carry the
# account name inside a path. A name of fewer than 3 characters is left alone: it would also change
# ordinary words. With -JsonEscaped the profile folder is looked for as JSON writes it (doubled
# backslashes).
function Hide-TuneupPersonalData {
    param([AllowNull()][AllowEmptyString()][string]$Text, [switch]$JsonEscaped)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $ignoreCase = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $folders = @(@($env:USERPROFILE, [Environment]::GetFolderPath('UserProfile')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } |
        Select-Object -Unique | Sort-Object -Property Length -Descending)
    foreach ($folder in $folders) {
        $literal = $(if ($JsonEscaped) { $folder.Replace('\', '\\') } else { $folder })
        $Text = [regex]::Replace($Text, [regex]::Escape($literal), '%USERPROFILE%', $ignoreCase)
    }
    $name = [string]$env:USERNAME
    if ($name.Length -ge 3) {
        $Text = [regex]::Replace($Text, '(?<![A-Za-z0-9])' + [regex]::Escape($name) + '(?![A-Za-z0-9])', '%USERNAME%', $ignoreCase)
    }
    $Text
}
```
En `engine/Transcript.ps1`, reemplazar la función `Add-TuneupTranscript` completa por:
```powershell
function Add-TuneupTranscript {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $text = Hide-TuneupPersonalData -Text ((@($Lines) -join [Environment]::NewLine) + [Environment]::NewLine)
    Write-TuneupStateFile -Path (Join-Path $Run.Dir 'transcript.log') -Root $Run.Root -Append -Text $text
}
```
- [ ] **Step 4: Avisos y planificador**

En `engine/Preflight.ps1`, reemplazar la función `Test-TuneupTrustedLocation` completa (con su comentario) por estas dos funciones:
```powershell
# A file or folder of the tool: not a link, and owned and changeable only by SYSTEM, TrustedInstaller
# and Administrators.
function Test-TuneupTrustedEntry {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
        $security = Get-Acl -LiteralPath $Path -ErrorAction Stop
    } catch {
        return $false
    }
    Test-TuneupTrustedSecurity -Security $security -TrustedSids $script:BaseTrustedSids -SkipInheritOnly
}

# Running elevated from a folder that others can change lets them run code as administrator (README,
# requirements). The script and the module are checked with their parent folders up to the root, like
# a program that runs elevated, and so is everything else the tool loads or reads: the files of
# engine, catalog, profiles, actions and i18n, and those folders themselves. Any one that a
# non-elevated process can change makes the location untrusted.
function Test-TuneupTrustedLocation {
    param([Parameter(Mandatory)][string]$ScriptRoot)
    $root = [System.IO.Path]::GetPathRoot($ScriptRoot)
    if (-not (Test-TuneupTrustedExecutable -Path (Join-Path $ScriptRoot 'tuneup.ps1') -StopAt $root)) { return $false }
    if (-not (Test-TuneupTrustedExecutable -Path (Join-Path $ScriptRoot 'engine\Tuneup.psm1') -StopAt $root)) { return $false }
    foreach ($name in 'engine', 'catalog', 'profiles', 'actions', 'i18n') {
        $folder = Join-Path $ScriptRoot $name
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($entry in @(Get-Item -LiteralPath $folder -Force) + @(Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue)) {
            if (-not (Test-TuneupTrustedEntry -Path $entry.FullName)) { return $false }
        }
    }
    $true
}
```
En `engine/Preflight.ps1`, dentro de `Get-TuneupPreflight`, reemplazar:
```powershell
        New-TuneupPreflightItem -Key 'preflight.untrusted-location' -Format $ScriptRoot
```
por:
```powershell
        # The location is written without the profile folder or the account name: the warning ends up in
        # the transcript, result.json and the JSON, which people share.
        New-TuneupPreflightItem -Key 'preflight.untrusted-location' -Format (Hide-TuneupPersonalData -Text $ScriptRoot)
```
En `engine/Planner.ps1`, dentro de `New-TuneupPlan`, reemplazar:
```powershell
        [AllowEmptyCollection()][AllowNull()][string[]]$Exclude = @(),
        [Parameter(Mandatory)]$Environment,
```
por:
```powershell
        [AllowEmptyCollection()][AllowNull()][string[]]$Exclude = @(),
        # Tweaks named like a profile names them, in this order and without being asked for: one that
        # asks first or has high risk is left out as in a profile.
        [AllowEmptyCollection()][AllowNull()][string[]]$Candidates = @(),
        [Parameter(Mandatory)]$Environment,
```
En `engine/Planner.ps1`, reemplazar:
```powershell
    $Exclude = @(Get-TuneupCleanList $Exclude)

    # Hashtable
```
por:
```powershell
    $Exclude = @(Get-TuneupCleanList $Exclude)
    $Candidates = @(Get-TuneupCleanList $Candidates)

    # Hashtable
```
En `engine/Planner.ps1`, reemplazar:
```powershell
    foreach ($tweakId in @($Include) + @($Exclude)) {
```
por:
```powershell
    foreach ($tweakId in @($Include) + @($Exclude) + @($Candidates)) {
```
En `engine/Planner.ps1`, reemplazar:
```powershell
    $Exclude = @($Exclude | ForEach-Object { & $canonical $_ })
```
por:
```powershell
    $Exclude = @($Exclude | ForEach-Object { & $canonical $_ })
    $Candidates = @($Candidates | ForEach-Object { & $canonical $_ })
```
En `engine/Planner.ps1`, reemplazar:
```powershell
    foreach ($tweakId in $Include) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }
```
por:
```powershell
    foreach ($tweakId in $Include) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }
    foreach ($tweakId in $Candidates) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }
```
(El parámetro no se llama `Wanted` porque PowerShell no distingue mayúsculas y chocaría con la lista local `$wanted`.)

- [ ] **Step 5: Comandos**

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupReapply` completa (con su comentario) por:
```powershell
# Plans again, from the catalog of now, the tweaks whose status is drift: only them (no base profile)
# and by name, so a tweak that asks first or is kept by a profile is applied again too; the
# compatibility checks still apply. A drifted tweak that the catalog no longer has is left out with a
# warning: undoing the run that applied it restores it.
function Invoke-TuneupReapply {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items, [switch]$PlanOnly, [switch]$Yes)
    # In the order of the runs that applied them, not alphabetical.
    $drifted = @($Items | Where-Object { $_.status -eq 'drift' } | ForEach-Object { [string]$_.id } | Select-Object -Unique)
    if (-not $drifted.Count -and -not $Context.Json) {
        # Without administrator some tweaks cannot be checked: that is not the same as nothing to do.
        $unverified = @($Items | Where-Object { $_.status -eq 'needs-admin' }).Count
        $line = $(if ($unverified) { Get-TuneupText -Key 'reapply.noneUnverified' -Format $unverified } else { Get-TuneupText -Key 'reapply.none' })
        Write-TuneupIoLine -Io $Context.Io -Text $line
        $Context.ExitCode = 0
        return
    }
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) {
        Write-TuneupCommandError -Context $Context -Message $unsupported
        return
    }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
        return
    }
    $known = @{}
    foreach ($tweak in $definition.Catalog) { $known[[string]$tweak.id] = $true }
    $missing = @($drifted | Where-Object { -not $known.ContainsKey($_) })
    if ($missing.Count) {
        Invoke-TuneupContextStep -Context $Context -Step {
            foreach ($id in $missing) { Write-Warning "Tweak $id was reverted but is no longer in the catalog: undo the run that applied it to restore it" }
        }
    }
    $ids = @($drifted | Where-Object { $known.ContainsKey($_) })
    # Named like a profile names them, not asked for: a tweak that asks first or has high risk is left
    # out (needs-confirmation, high-risk-not-requested) and the plan says so; the menu asks about those.
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -Candidates $ids -NoBase)
    $request = New-TuneupApplyRequest -Source 'reapply' -Include $ids
    if ($Yes -and -not $PlanOnly -and -not $Context.Json) {
        # With -Yes the plan is not shown, so what is left out is listed here.
        foreach ($item in @($plan | Where-Object { $_.Action -eq 'skip' -and @('needs-confirmation', 'high-risk-not-requested') -contains $_.Reason })) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'reapply.leftOut' -Format (Get-TuneupTitle -Tweak $item.Tweak), (Get-TuneupText -Key "reason.$($item.Reason)"))
        }
    }
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
}
```
En `engine/Commands.ps1`, reemplazar la función `New-TuneupContextPlan` completa por:
```powershell
function New-TuneupContextPlan {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Definition,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [AllowEmptyCollection()][string[]]$Candidates = @(),
        [switch]$Interactive,
        [switch]$NoBase
    )
    $planArguments = @{
        Catalog     = $Definition.Catalog
        Profiles    = $Definition.Profiles
        ProfileIds  = $ProfileIds
        Include     = $Include
        Exclude     = $Exclude
        Candidates  = $Candidates
        Environment = Get-TuneupContextEnvironment -Context $Context
        Interactive = $Interactive
        NoBase      = $NoBase
        TestState   = { param($tweak) Test-TuneupState -Tweak $tweak }
    }
    @(Invoke-TuneupContextStep -Context $Context -Step { New-TuneupPlan @planArguments })
}
```
En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupPlannedApply` completa (con su comentario) por:
```powershell
# Shows the plan, or asks and applies it: the part that applying profiles, re-applying what drifted
# and the menu have in common.
function Invoke-TuneupPlannedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [switch]$PlanOnly,
        [switch]$Yes
    )
    $environment = Get-TuneupContextEnvironment -Context $Context
    $toApply = @($Plan | Where-Object { $_.Action -eq 'apply' })
    # Warnings before applying (Preflight.ps1): none of them stops the run.
    $preflightArguments = @{ Environment = $environment; Plan = $Plan; ScriptRoot = $Context.ScriptRoot }
    $preflight = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupPreflight @preflightArguments })
    if ($PlanOnly -or -not $toApply.Count) {
        $Context.Result = $null
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight -Source $Request.Source -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
        $Context.ExitCode = 0
        return
    }
    $machineChanges = @($toApply | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak }).Count
    if ($machineChanges -and -not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.notAdmin')
        return
    }
    if (-not $Yes) {
        if ($Context.Json) {
            Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.jsonNeedsYes')
            return
        }
        Write-TuneupPlanReport -Plan $Plan -Environment $environment -Preflight $preflight
        if (-not (Read-TuneupConfirmation -Io $Context.Io -Prompt (Get-TuneupText -Key 'confirm' -Format $toApply.Count))) {
            Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'aborted')
            $Context.ExitCode = 1
            return
        }
        # The only warning with something to do about it here: System Restore can be turned on. It is
        # asked after the apply is confirmed, so declining the apply never leaves it on, and once it is
        # on the warning is no longer true and leaves the report of the run.
        if (@($preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count -and (Request-TuneupSystemRestore -Io $Context.Io)) {
            $preflight = @($preflight | Where-Object { $_.id -ne 'restore-disabled' })
        }
    } elseif (-not $Context.Json) {
        Write-TuneupPreflight -Preflight $preflight
    }
    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRun -StateRoot $Context.StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $Plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupContextStep -Context $Context -Step { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    # Ctrl+C stops the run between two tweaks (Interrupt.ps1). If it stops PowerShell itself, the
    # finally block saves what was done; the results and the tweak in progress are kept outside the
    # pipeline for that.
    $results = New-Object System.Collections.Generic.List[object]
    $progress = @{ Current = $null }
    $trap = Enable-TuneupInterruptTrap
    if ($null -ne $trap -and -not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'interrupted.hint') }
    $applyArguments = @{
        Plan          = $Plan
        RunDir        = $run.Dir
        Results       = $results
        Progress      = $progress
        StopRequested = { Test-TuneupInterruptRequested -Trap $trap }
    }
    $finished = $false
    $failure = $null
    try {
        Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupPlan @applyArguments } | Out-Null
        $finished = $true
    } catch {
        # Ctrl+C that stops PowerShell is not an error of the apply; any other error is saved as one.
        if ($_.Exception -isnot [System.Management.Automation.PipelineStoppedException]) { $failure = $_.Exception.Message }
        throw
    } finally {
        Disable-TuneupInterruptTrap -Trap $trap
        if (-not $finished) {
            Save-TuneupStoppedApply -Context $Context -Run $run -Plan $Plan -Request $Request -Results $results -Progress $progress -RestorePoint $restorePoint -Preflight $preflight -Failure $failure
        }
    }
    $report = New-TuneupApplyReport -Run $run -Results $results.ToArray() -RestorePoint $restorePoint -Environment $environment -Preflight $preflight -Source $Request.Source
    $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
    Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyTranscript -Context $Context -Run $run -Request $Request -Plan $Plan -Report $report }
    $Context.Result = $report
    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
}
```
En `engine/Commands.ps1`, reemplazar la función `Save-TuneupStoppedApply` completa (con su comentario) por:
```powershell
# Ctrl+C reached PowerShell itself while a native program ran (Interrupt.ps1), or the apply failed
# outside any one tweak (-Failure holds the error). What was done is saved as the result of the run:
# the tweak in progress is reported as failed when its journal entry was written (-Undo can restore
# it) and the rest as interrupted by Ctrl+C or as aborted by the error. A tweak cut before its journal
# entry changed nothing, so it is only left out. The output is closed by then (a stopped pipeline),
# so only the host and the files can be written.
function Save-TuneupStoppedApply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][hashtable]$Progress,
        [Parameter(Mandatory)][string]$RestorePoint,
        [AllowEmptyCollection()][object[]]$Preflight = @(),
        [string]$Failure
    )
    $done = @($Results.ToArray())
    $doneIds = @($done | ForEach-Object { $_.id })
    $rest = @(foreach ($item in $Plan) {
        if ($doneIds -contains $item.Id) { continue }
        if ($item.Action -ne 'apply') { New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason }
        elseif ($item.Id -eq $Progress.Current -and $Progress.Journaled) {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $(if ($Failure) { "$Failure; -Undo can restore it" } else { 'stopped while it was being applied; -Undo can restore it' })
        }
        else { New-TuneupResult -Item $item -Status 'skipped' -Reason $(if ($Failure) { 'aborted' } else { 'interrupted' }) }
    })
    $report = New-TuneupApplyReport -Run $Run -Results (@($done) + @($rest)) -RestorePoint $RestorePoint -Environment $Context.Environment -Preflight $Preflight -Source $Request.Source
    $saved = $true
    try {
        Write-TuneupRunResult -Run $Run -Report $report
    } catch {
        $saved = $false
    }
    try {
        Add-TuneupTranscript -Run $Run -Lines @(Get-TuneupApplyTranscript -Run $Run -Request $Request -Plan $Plan -Report $report `
                -Environment $Context.Environment -Warnings $Context.Warnings.ToArray())
    } catch {
        # A missing transcript loses nothing that result.json and the journal do not keep.
        $null = $_
    }
    $Context.Result = $report
    $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
    if (-not $Context.Json) {
        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key $(if ($Failure) { 'aborted.saved' } else { 'interrupted.saved' }) -Format $Run.Id)
    }
}
```
En `i18n/es.json`, reemplazar el texto de `preflight.untrusted-location` por:
```json
  "preflight.untrusted-location": "windows-tuneup corre como administrador desde {0}, una carpeta (o archivos suyos) que procesos sin elevar, incluidos los tuyos, pueden cambiar: instálalo en Program Files (README, Instalación).",
```
En `i18n/en.json`, reemplazar el texto de `preflight.untrusted-location` por:
```json
  "preflight.untrusted-location": "windows-tuneup runs as administrator from {0}, a folder (or files in it) that non-elevated processes (including your own) can change: install it under Program Files (README, Installation).",
```
En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):
```json
  "interrupted.hint": "Ctrl+C se detiene después del ajuste en curso; Ctrl+Pausa interrumpe de inmediato",
  "aborted.saved": "La corrida se detuvo por un error. El resultado de la corrida {0} quedó guardado; para deshacerla: .\tuneup.ps1 -Undo {0}",
  "reason.aborted": "no se aplicó: la corrida se detuvo por un error",
  "reapply.noneUnverified": "Nada que volver a aplicar entre lo que se pudo comprobar, pero {0} ajustes necesitan administrador para comprobarse: ejecútalo de nuevo como administrador.",
  "reapply.leftOut": "No se vuelve a aplicar {0}: {1}"
```
En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):
```json
  "interrupted.hint": "Ctrl+C stops after the tweak in progress; Ctrl+Break interrupts at once",
  "aborted.saved": "The run stopped because of an error. The result of run {0} was saved; to undo it: .\tuneup.ps1 -Undo {0}",
  "reason.aborted": "not applied: the run stopped because of an error",
  "reapply.noneUnverified": "Nothing to apply again among what could be checked, but {0} tweaks need administrator to be checked: run it again as administrator.",
  "reapply.leftOut": "Not applied again, {0}: {1}"
```
- [ ] **Step 6: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: PASS (`Tests Passed: 26, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: PASS (`Tests Passed: 46, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Preflight.Tests.ps1`
Expected: PASS (`Tests Passed: 29, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Commands.Tests.ps1`
Expected: PASS (`Tests Passed: 31, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Interrupt.Tests.ps1`
Expected: PASS (`Tests Passed: 3, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: toda la suite en verde (`Tests Passed: 1164, Failed: 0, Skipped: 1`).

- [ ] **Step 7: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 8: Commit**

```bash
git add engine/Executor.ps1 engine/Output.ps1 engine/Transcript.ps1 engine/Preflight.ps1 engine/Planner.ps1 engine/Commands.ps1 i18n/es.json i18n/en.json tests/Interrupt.Tests.ps1 tests/Executor.Tests.ps1 tests/Planner.Tests.ps1 tests/Output.Tests.ps1 tests/Preflight.Tests.ps1 tests/Commands.Tests.ps1
git commit -m "fix: Ctrl+C avisa, transcript sin nombre de cuenta y reaplicar con confirmación"
```

---

### Task 9: Menú: estructura, estado, deshacer, salud y medir

**Files:**
- Create: `engine/Menu.ps1`, `tests/Menu.Tests.ps1`
- Modify: `engine/Health.ps1` (`Invoke-TuneupHealth -Previous`), `engine/Commands.ps1` (`New-TuneupContext`, `Invoke-TuneupHealthCommand`, `Invoke-TuneupCli`), `i18n/es.json`, `i18n/en.json`
- Test: `tests/Menu.Tests.ps1`, `tests/Health.Tests.ps1`, `tests/Cli.Tests.ps1`

Diseño (sección 12, punto 2): sin comando ni opciones de aplicar, y sin `-Json`, `Invoke-TuneupCli` abre el menú. Cada pregunta se escribe con `Io.Write` y se lee con `Io.Read` (`Read-Host` en la consola): un número, una letra o Enter solo. Se probó en la copia que `Read-Host` lee también de una entrada redirigida y devuelve `$null` al terminar: así una prueba de `tests/Cli.Tests.ps1` maneja el menú por la entrada estándar de `powershell -File`. El fin de la entrada marca `$Context.InputEnded` y el menú sale. Un error dentro de una opción se muestra y el menú vuelve. Esta tarea trae todo menos Optimizar (Task 10): la opción `1` ya aparece, y hasta la Task 10 responde con un error ("Invoke-TuneupMenuOptimize no se reconoce") y vuelve al menú.

- Estado: el reporte de `-Status` y, si algo está en `drift`, "Escribe r y Enter para volver a aplicarlos" (`Invoke-TuneupReapply`, con su confirmación).
- Deshacer: las 15 corridas más nuevas con diario, con cantidad de ajustes, estado (`[pendiente]`, `[deshecha en parte]`, `[deshecha]`) y carpeta; luego toda la corrida o un ajuste, con confirmación.
- Salud: pide confirmar (tarda); si la revisión recomienda reparar, ofrece hacerlo **sin revisar otra vez** (`Invoke-TuneupHealth -Previous` toma el `before` del reporte anterior).
- Medir: segundos de espera (0 a 3600) y, si hay mediciones guardadas, comparar con la última.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/Menu.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'

    # The fixture catalog and profiles, plus a tweak that asks first, a high-risk one and a profile
    # with the one that asks.
    $script:Definitions = Join-Path $TestDrive 'definitions'
    $catalogDir = Join-Path $Definitions 'catalog'
    $profilesDir = Join-Path $Definitions 'profiles'
    New-Item -ItemType Directory -Path $catalogDir, $profilesDir -Force | Out-Null
    Copy-Item -Path (Join-Path $Fixtures 'catalog\*.json') -Destination $catalogDir
    Copy-Item -Path (Join-Path $Fixtures 'profiles\*.json') -Destination $profilesDir
    $extra = @(
        (New-TestTweak -Id 'menu.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.high' -Risk 'high' -Set ([pscustomobject]@{ path = $Key; name = 'High'; kind = 'DWord'; value = 1 }))
    )
    [System.IO.File]::WriteAllText((Join-Path $catalogDir 'menu.json'), (ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = $extra }) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'asking.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'asking' -Include @('menu.ask')) -Depth 10))

    # The profiles in the order of the menu: base first, then by file name.
    # 1 base, 2 asking, 3 extra, 4 nested, 5 system.
    function New-MenuContext([object[]]$Answers, [switch]$Admin) {
        $context = New-TuneupContext -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = $catalogDir
        $context.ProfilesPath = $profilesDir
        $context.Environment = New-TestEnvironment -IsAdmin ([bool]$Admin)
        $context
    }
    function Invoke-Menu($Context) { Invoke-TuneupMenu -Context $Context 3>$null 6>$null }
    function Get-Output($Context) { $Context.Io.Output -join "`n" }
    function Get-Value([string]$Name) {
        if (-not (Test-Path -LiteralPath $Key)) { return $null }
        (Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue).$Name
    }
}

Describe 'Invoke-TuneupMenu' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'shows the options and exits with 0, or at the end of the input' {
        $context = New-MenuContext @('0')
        Invoke-Menu $context
        $context.ExitCode | Should -Be 0
        Get-Output $context | Should -Match ' 1\. Optimize: choose profiles and apply them'
        Get-Output $context | Should -Match 'Not running as administrator'
        $context = New-MenuContext @($null)
        Invoke-Menu $context
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says when an option does not exist and asks again' {
        $context = New-MenuContext @('9', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'That is not one of the options'
    }

    It 'shows the status and applies again what Windows reverted' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $context = New-MenuContext @('2', 'r', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Windows reverted 1 tweaks'
        Get-Value 'One' | Should -Be 1
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory).Count | Should -Be 2
    }

    It 'undoes a whole run picked from the list' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 'w', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 1\. \d{8}-\d{6}  2 tweaks  \[pending\]  \(test folder\)'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'undoes one tweak of a run' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 't', '2', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 2\. Test two \(test\.two\)'
        Get-Value 'One' | Should -Be 1
        Get-Value 'Two' | Should -BeNullOrEmpty
    }

    It 'refuses the health check without administrator' {
        $context = New-MenuContext @('4', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '-Health needs PowerShell as administrator.'
    }

    It 'offers to repair right after a check that found damage, reusing that check' {
        $found = [pscustomobject]@{ schemaVersion = 1; command = 'health'; startedAt = '2026-10-01T10:00:00'; finishedAt = '2026-10-01T10:20:00'
            repairRequested = $false; repairRan = $false; before = $null; after = $null; recommendation = 'run-repair'; rebootRecommended = $false }
        Mock -ModuleName Tuneup Invoke-TuneupHealth { $found }
        Mock -ModuleName Tuneup Write-TuneupHealthReport { }
        $context = New-MenuContext @('4', 'y', 'y', '', '0') -Admin
        Invoke-Menu $context
        Should -Invoke Invoke-TuneupHealth -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { -not $Repair -and $null -eq $Previous }
        Should -Invoke Invoke-TuneupHealth -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Repair -and $Previous.startedAt -eq '2026-10-01T10:00:00' }
    }

    It 'measures and then compares with the last measurement' {
        $context = New-MenuContext @('5', '', '', '5', 'x', '0', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '-IdleSeconds must be between 0 and 3600.'
        $text | Should -Match 'Compare with the last measurement \(\d{8}-\d{6}\)'
        $context.Result.comparison | Should -Not -BeNullOrEmpty
    }
}
```

En `tests/Cli.Tests.ps1`, agregar antes de `It 'undoes the last run' {`:

```powershell
    It 'leaves the menu at the end of standard input' {
        $output = @('2') | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') -StateRoot $script:Root -Lang en
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'windows-tuneup has not applied any tweak'
    }
```

En `tests/Health.Tests.ps1`, agregar antes de `It 'reports each phase as it starts' {`:

```powershell
    It 'repairs from the check of an earlier report without checking again' {
        Mock -ModuleName Tuneup Read-TuneupCbsLog { if ($script:Phase -eq 'repair') { $script:Fixed } else { $script:Corrupt } }
        $first = Invoke-TuneupHealth
        $script:Phases = @()
        $report = Invoke-TuneupHealth -Repair -Previous $first -OnPhase { param($Name) $script:Phases += $Name }
        $script:Phases -join ',' | Should -Be 'dismRestore,sfcAgain'
        $report.startedAt | Should -Be $first.startedAt
        $report.before.componentStore.state | Should -Be 'repairable'
        $report.after.componentStore.state | Should -Be 'repaired'
        Should -Invoke Invoke-TuneupDism -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Operation -eq 'ScanHealth' }
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: FAIL: `Invoke-TuneupMenu` no se reconoce (8 pruebas).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: FAIL en `repairs from the check of an earlier report...` (no existe `-Previous`).

- [ ] **Step 3: El menú**

Crear `engine/Menu.ps1`:

```powershell
# The interactive menu: tuneup.ps1 without a command. Questions and answers go through $Context.Io
# (Io.ps1) and the work through the same commands as the command line (Commands.ps1). Every answer is
# a line of text (a number, a letter, or Enter alone), so it works the same in the Windows PowerShell
# console, Windows Terminal and a redirected input. The end of the input means back, all the way out.
# Marks are text ([x], (administrator), [high risk]), never a color alone.

# The text of a { es, en } object in the language of the session.
function Get-TuneupLocalizedText {
    param([AllowNull()]$Text)
    if ($null -eq $Text) { return '' }
    $value = $Text.((Get-TuneupLang))
    if (-not $value) { $value = $Text.en }
    [string]$value
}

# An answer of the menu; $null, and the context marked, when the input ended.
function Read-TuneupMenuAnswer {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupIoAnswer -Io $Context.Io -Prompt $Prompt
    if ($null -eq $answer) { $Context.InputEnded = $true }
    $answer
}

function Read-TuneupMenuConfirmation {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
    ($null -ne $answer) -and ($answer -match (Get-TuneupText -Key 'confirm.pattern'))
}

function Write-TuneupMenuLine {
    param([Parameter(Mandatory)]$Context, [AllowEmptyString()][string]$Text = '')
    Write-TuneupIoLine -Io $Context.Io -Text $Text
}

# Numbers typed to pick items from a list of Count: "2,4" or "2 4". $null when something else was typed.
function ConvertFrom-TuneupMenuNumberList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][int]$Count)
    $numbers = @()
    foreach ($part in @($Text -split '[,\s]+' | Where-Object { $_ })) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $Count) { return $null }
        $numbers += $number
    }
    , @($numbers)
}

function Write-TuneupMenuHeader {
    param([Parameter(Mandatory)]$Context)
    $environment = Get-TuneupContextEnvironment -Context $Context
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.title' -Format (Get-TuneupVersion), $environment.Family, $environment.Edition, $environment.Build)
    $adminKey = $(if ($environment.IsAdmin) { 'menu.admin.yes' } else { 'menu.admin.no' })
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key $adminKey)
    if ($environment.IsManaged) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.managed') }
    Write-TuneupMenuLine -Context $Context
    foreach ($key in 'menu.main.optimize', 'menu.main.status', 'menu.main.undo', 'menu.main.health', 'menu.main.measure', 'menu.main.exit') {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key $key)
    }
}

function Invoke-TuneupMenu {
    param([Parameter(Mandatory)]$Context)
    $Context.InputEnded = $false
    while (-not $Context.InputEnded) {
        Write-TuneupMenuHeader -Context $Context
        $choice = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.choose')
        $action = switch ($choice) {
            '1' { 'Optimize' }
            '2' { 'Status' }
            '3' { 'Undo' }
            '4' { 'Health' }
            '5' { 'Measure' }
            default { $null }
        }
        if ($null -eq $choice -or $choice -eq '0') { break }
        if ($null -eq $action) {
            Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
            continue
        }
        # A failure ends that option, not the menu: it is shown and the menu comes back.
        try {
            & "Invoke-TuneupMenu$action" -Context $Context
        } catch {
            Write-TuneupErrorReport -Message $_.Exception.Message
        }
        if ($Context.InputEnded) { break }
        if ($null -eq (Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.back'))) { break }
    }
    $Context.ExitCode = 0
}

# The status, and when Windows reverted something, the offer to apply it again.
function Invoke-TuneupMenuStatus {
    param([Parameter(Mandatory)]$Context)
    Invoke-TuneupStatusCommand -Context $Context
    $items = @($Context.Result)
    $drifted = @($items | Where-Object { $_.status -eq 'drift' }).Count
    if (-not $drifted) { return }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.status.reapply' -Format $drifted)
    if ($answer -ine (Get-TuneupText -Key 'menu.status.reapplyKey')) { return }
    Invoke-TuneupReapply -Context $Context -Items $items
}

# The runs that can be undone, newest first; then the whole run or one of its tweaks.
function Invoke-TuneupMenuUndo {
    param([Parameter(Mandatory)]$Context)
    $runs = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupRunList -StateRoot $Context.StateRoot } |
        Where-Object { Test-TuneupRunHasJournal -Dir $_.Dir })
    [array]::Reverse($runs)
    $runs = @($runs | Select-Object -First 15)
    if (-not $runs.Count) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'undo.none'); return }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.header')
    for ($i = 0; $i -lt $runs.Count; $i++) {
        $run = $runs[$i]
        $count = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupJournal -Path (Join-Path $run.Dir 'snapshot.jsonl') -Root $run.Root }).Count
        $state = $(if ($run.Undone -or (Test-TuneupRunAllNotedUndone -Run $run)) { 'menu.undo.state.undone' }
            elseif (@(Get-TuneupUndoneTweakId -Run $run).Count) { 'menu.undo.state.partly' } else { 'menu.undo.state.pending' })
        $where = switch ($run.Root) { 'machine' { 'menu.undo.root.machine' } 'user' { 'menu.undo.root.user' } default { 'menu.undo.root.custom' } }
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1}  {2}  {3}  {4}' -f ($i + 1), $run.Id, (Get-TuneupText -Key 'menu.undo.tweaks' -Format $count),
            (Get-TuneupText -Key $state), (Get-TuneupText -Key $where))
    }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickRun')
    $numbers = $(if ($answer) { ConvertFrom-TuneupMenuNumberList -Text $answer -Count $runs.Count } else { $null })
    if ($null -eq $numbers -or @($numbers).Count -ne 1) { return }
    $run = $runs[$numbers[0] - 1]
    $how = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.how')
    if ($how -ieq (Get-TuneupText -Key 'menu.undo.wholeKey')) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmRun' -Format $run.Id)) {
            Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id
        }
        return
    }
    if ($how -ine (Get-TuneupText -Key 'menu.undo.tweakKey')) { return }
    $entries = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run })
    $done = @(Get-TuneupUndoneTweakId -Run $run)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $mark = $(if ($done -contains $entries[$i].id) { ' ' + (Get-TuneupText -Key 'menu.undo.state.undone') } else { '' })
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1} ({2}){3}' -f ($i + 1), (Get-TuneupTitle -Tweak $entries[$i].tweak), $entries[$i].id, $mark)
    }
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickTweak')
    $numbers = $(if ($answer) { ConvertFrom-TuneupMenuNumberList -Text $answer -Count $entries.Count } else { $null })
    if ($null -eq $numbers -or @($numbers).Count -ne 1) { return }
    $entry = $entries[$numbers[0] - 1]
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmTweak' -Format (Get-TuneupTitle -Tweak $entry.tweak))) {
        Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id -TweakId ([string]$entry.id)
    }
}

# SFC and DISM, and when they find damage that can be repaired, the offer to repair it now (without
# checking again: the check that was just made is reused).
function Invoke-TuneupMenuHealth {
    param([Parameter(Mandatory)]$Context)
    if (-not (Get-TuneupContextEnvironment -Context $Context).IsAdmin) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'err.healthNeedsAdmin')
        return
    }
    if (-not (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.confirm'))) { return }
    Invoke-TuneupHealthCommand -Context $Context
    $report = $Context.Result
    if ($null -eq $report -or $report.recommendation -ne 'run-repair') { return }
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.repair')) {
        Invoke-TuneupHealthCommand -Context $Context -Repair -Previous $report
    }
}

# A measurement after some seconds idle, compared with the last one if there is one and the person wants.
function Invoke-TuneupMenuMeasure {
    param([Parameter(Mandatory)]$Context)
    $seconds = $null
    while ($null -eq $seconds) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.idle')
        if ($null -eq $answer) { return }
        if ($answer -eq '') { $seconds = 0; break }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 0 -and $number -le 3600) { $seconds = $number }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'err.idleSecondsRange' -Format 0, 3600) }
    }
    $compare = $null
    $earlier = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupMeasurementList -StateRoot $Context.StateRoot })
    if ($earlier.Count) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.compare' -Format $earlier[-1].Id)) { $compare = 'last' }
        if ($Context.InputEnded) { return }
    }
    Invoke-TuneupMeasureCommand -Context $Context -IdleSeconds $seconds -Compare $compare
}
```

- [ ] **Step 4: Reparar sin revisar otra vez**

En `engine/Health.ps1`, reemplazar la función `Invoke-TuneupHealth` completa (con su comentario) por:

```powershell
# -Previous: a report of an earlier check, whose result is used as the starting point instead of
# checking again (the menu offers to repair right after a check that found damage).
function Invoke-TuneupHealth {
    param([switch]$Repair, [scriptblock]$OnPhase, $Previous)
    if ($null -ne $Previous) {
        $started = [datetime]$Previous.startedAt
        $before = $Previous.before
        $scanned = Get-TuneupLogTime
    } else {
        $started = Get-TuneupLogTime
        if ($OnPhase) { & $OnPhase 'sfc' }
        $sfcRun = Invoke-TuneupSfc
        if ($OnPhase) { & $OnPhase 'dismScan' }
        $dismRun = Invoke-TuneupDism -Operation 'ScanHealth'
        $scanned = Get-TuneupLogTime
        $before = New-TuneupHealthScan -Lines @(Read-TuneupCbsLog -Since $started -Until $scanned) -SfcRun $sfcRun -DismRun $dismRun
    }
    $after = $null
    if ($Repair -and (Test-TuneupHealthNeedsRepair -Scan $before)) {
        if ($OnPhase) { & $OnPhase 'dismRestore' }
        $restoreRun = Invoke-TuneupDism -Operation 'RestoreHealth'
        if ($OnPhase) { & $OnPhase 'sfcAgain' }
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
```

- [ ] **Step 5: El contexto y la línea de comandos**

En `engine/Commands.ps1`, reemplazar la función `New-TuneupContext` completa (con su comentario) por:

```powershell
# What one invocation shares between its steps: JSON or text, the folders for testing, the warnings
# collected so far, the questions and answers (Io), the exit code and the last result. The exit code
# starts at 1 and every command sets 0 when it succeeds, so one that dies before reporting is a failure.
function New-TuneupContext {
    param([switch]$Json, $Io)
    [pscustomobject]@{
        PSTypeName   = 'Tuneup.Context'
        Json         = [bool]$Json
        StateRoot    = $null
        CatalogPath  = $null
        ProfilesPath = $null
        Force        = $false
        Warnings     = New-Object System.Collections.Generic.List[string]
        Environment  = $null
        ScriptRoot   = $null
        Io           = $(if ($null -ne $Io) { $Io } else { New-TuneupConsoleIo })
        InputEnded   = $false
        ExitCode     = 1
        Result       = $null
    }
}
```

En `engine/Commands.ps1`, reemplazar la función `Invoke-TuneupHealthCommand` completa (con su comentario) por:

```powershell
# -Previous: a health report whose check is reused, so -Repair only repairs (the menu offers it).
function Invoke-TuneupHealthCommand {
    param([Parameter(Mandatory)]$Context, [switch]$Repair, $Previous)
    $environment = Get-TuneupContextEnvironment -Context $Context
    if (-not $environment.IsAdmin) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.healthNeedsAdmin')
        return
    }
    if (-not $Context.Json) { Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key 'health.running') }
    # One line per phase for people; with -Json nothing but the document goes to the output.
    $healthArguments = @{ Repair = $Repair; Previous = $Previous }
    if (-not $Context.Json) {
        $io = $Context.Io
        $healthArguments.OnPhase = { param($Name) Write-TuneupIoLine -Io $io -Text (Get-TuneupText -Key "health.phase.$Name") }.GetNewClosure()
    }
    $report = Invoke-TuneupContextStep -Context $Context -Step { Invoke-TuneupHealth @healthArguments }
    $Context.Result = $report
    Write-TuneupHealthReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
    $Context.ExitCode = Get-TuneupHealthExitCode -Report $report
}
```

En `engine/Commands.ps1`, reemplazar:

```powershell
    Get-TuneupContextEnvironment -Context $Context | Out-Null

    if ($Status)
```

por:

```powershell
    Get-TuneupContextEnvironment -Context $Context | Out-Null

    # No command and no option of applying: the menu (with -Json there is nobody to ask).
    if (-not $present.Count -and -not $Context.Json) { Invoke-TuneupMenu -Context $Context; return }
    if ($Status)
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "menu.title": "windows-tuneup {0} - Windows {1} {2} (compilación {3})",
  "menu.admin.yes": "Corre como administrador.",
  "menu.admin.no": "No corre como administrador: los cambios de sistema, la salud de Windows y deshacer corridas de sistema necesitan PowerShell como administrador.",
  "menu.managed": "Este equipo lo administra una organización: las directivas no se tocan.",
  "menu.main.optimize": " 1. Optimizar: elegir perfiles y aplicarlos",
  "menu.main.status": " 2. Estado: qué está aplicado, y volver a aplicar lo que Windows revirtió",
  "menu.main.undo": " 3. Deshacer una corrida o un ajuste",
  "menu.main.health": " 4. Salud de Windows (SFC y DISM)",
  "menu.main.measure": " 5. Medir, y comparar con una medición anterior",
  "menu.main.exit": " 0. Salir",
  "menu.choose": "Elige una opción:",
  "menu.invalid": "Esa no es una de las opciones. Prueba otra vez.",
  "menu.back": "Presiona Enter para volver al menú.",
  "menu.status.reapply": "Windows revirtió {0} ajustes. Escribe r y Enter para volver a aplicarlos, o solo Enter para volver:",
  "menu.status.reapplyKey": "r",
  "menu.undo.header": "Corridas, de la más nueva a la más vieja:",
  "menu.undo.tweaks": "{0} ajustes",
  "menu.undo.state.undone": "[deshecha]",
  "menu.undo.state.partly": "[deshecha en parte]",
  "menu.undo.state.pending": "[pendiente]",
  "menu.undo.root.machine": "(sistema: necesita administrador)",
  "menu.undo.root.user": "(tu usuario)",
  "menu.undo.root.custom": "(carpeta de pruebas)",
  "menu.undo.pickRun": "Escribe el número de una corrida, o Enter para volver:",
  "menu.undo.how": "c = deshacer toda la corrida, a = deshacer un ajuste, Enter = volver:",
  "menu.undo.wholeKey": "c",
  "menu.undo.tweakKey": "a",
  "menu.undo.pickTweak": "Escribe el número del ajuste, o Enter para volver:",
  "menu.undo.confirmRun": "¿Deshacer todos los ajustes de la corrida {0}? (s/n)",
  "menu.undo.confirmTweak": "¿Deshacer \"{0}\"? (s/n)",
  "menu.health.confirm": "SFC y DISM tardan 15 minutos o más. ¿Empezar ahora? (s/n)",
  "menu.health.repair": "¿Reparar ahora con DISM /RestoreHealth (usa Windows Update) y SFC? (s/n)",
  "menu.measure.idle": "Segundos de espera en reposo antes de medir (0 a 3600; después de reiniciar, 120; Enter = 0):",
  "menu.measure.compare": "¿Comparar con la última medición ({0})? (s/n)"
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "menu.title": "windows-tuneup {0} - Windows {1} {2} (build {3})",
  "menu.admin.yes": "Running as administrator.",
  "menu.admin.no": "Not running as administrator: system changes, the health check and undoing system runs need PowerShell as administrator.",
  "menu.managed": "This PC is managed by an organization: policies are left alone.",
  "menu.main.optimize": " 1. Optimize: choose profiles and apply them",
  "menu.main.status": " 2. Status: what is applied, and apply again what Windows reverted",
  "menu.main.undo": " 3. Undo a run or one tweak",
  "menu.main.health": " 4. Health of Windows (SFC and DISM)",
  "menu.main.measure": " 5. Measure, and compare with an earlier measurement",
  "menu.main.exit": " 0. Exit",
  "menu.choose": "Choose an option:",
  "menu.invalid": "That is not one of the options. Try again.",
  "menu.back": "Press Enter to go back to the menu.",
  "menu.status.reapply": "Windows reverted {0} tweaks. Type r and Enter to apply them again, or Enter alone to go back:",
  "menu.status.reapplyKey": "r",
  "menu.undo.header": "Runs, newest first:",
  "menu.undo.tweaks": "{0} tweaks",
  "menu.undo.state.undone": "[undone]",
  "menu.undo.state.partly": "[partly undone]",
  "menu.undo.state.pending": "[pending]",
  "menu.undo.root.machine": "(system: needs administrator)",
  "menu.undo.root.user": "(your user)",
  "menu.undo.root.custom": "(test folder)",
  "menu.undo.pickRun": "Type the number of a run, or Enter to go back:",
  "menu.undo.how": "w = undo the whole run, t = undo one tweak, Enter = go back:",
  "menu.undo.wholeKey": "w",
  "menu.undo.tweakKey": "t",
  "menu.undo.pickTweak": "Type the number of the tweak, or Enter to go back:",
  "menu.undo.confirmRun": "Undo every tweak of run {0}? (y/n)",
  "menu.undo.confirmTweak": "Undo \"{0}\"? (y/n)",
  "menu.health.confirm": "SFC and DISM take 15 minutes or more. Start now? (y/n)",
  "menu.health.repair": "Repair now with DISM /RestoreHealth (it uses Windows Update) and SFC? (y/n)",
  "menu.measure.idle": "Seconds to wait idle before measuring (0 to 3600; after a restart, 120; Enter = 0):",
  "menu.measure.compare": "Compare with the last measurement ({0})? (y/n)"
```

- [ ] **Step 6: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: PASS (`Tests Passed: 8, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Health.Tests.ps1`
Expected: PASS (`Tests Passed: 61, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`Tests Passed: 64, Failed: 0, Skipped: 1`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS (`Tests Passed: 4, Failed: 0`).

- [ ] **Step 7: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 8: Commit**

```bash
git add engine/Menu.ps1 engine/Health.ps1 engine/Commands.ps1 i18n/es.json i18n/en.json tests/Menu.Tests.ps1 tests/Health.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat: menú interactivo con estado, deshacer, salud y medición"
```

---

### Task 10: Menú: optimizar

**Files:**
- Modify: `engine/Menu.ps1` (nuevos `Select-TuneupMenuItem`, `Invoke-TuneupMenuOptimize`, `Select-TuneupMenuProfile`, `Select-TuneupMenuHighRisk`, `Confirm-TuneupMenuReappliedHighRisk`, `Request-TuneupMenuAskedTweak`; `Invoke-TuneupMenuStatus` reaplica con `-Interactive`), `engine/Commands.ps1` (`Invoke-TuneupReapply -Interactive`), `i18n/es.json`, `i18n/en.json`
- Test: `tests/Menu.Tests.ps1`, `tests/Cli.Tests.ps1`

Diseño: perfiles con `[x]`/`[ ]` (se marcan y desmarcan por número; `base` va primero, marcado y fijo, con `(siempre)`; `(administrador)` si algún ajuste lo necesita). Después, si hay ajustes `high` compatibles: "¿Quieres verlos?"; se eligen por número y se agregan solo escribiendo la palabra completa (`si`/`yes`); van como `-Include`. El plan se arma con `-Interactive` y se pregunta cada ajuste `ask` que va a aplicarse y no se pidió por nombre: `s`/`y` sí, `n` no, `t`/`a` sí a todos los que quedan, `x` no a todos los que quedan; el "no" lo deja `skip` con el motivo `declined`. Si el plan necesita administrador y no lo es, se muestra y se vuelve al menú. Si no, `Invoke-TuneupPlannedApply` (plan, avisos, Restaurar sistema, confirmación, aplicar).

Reaplicar desde el menú (corrección de la revisión de la Task 8b): `Invoke-TuneupReapply -Interactive` pregunta por los ajustes revertidos que `-Yes` y `-Json` dejan fuera. Cada uno de riesgo alto se muestra y vuelve solo si se escribe la palabra completa (`Confirm-TuneupMenuReappliedHighRisk`; el que no la recibe queda `skip` con `high-risk-not-requested`), y cada `ask` se pregunta de a uno con `Request-TuneupMenuAskedTweak` (un "no" queda `declined`). El plan conserva el orden de las corridas que los aplicaron.

- [ ] **Step 1: Pruebas que fallan**

En `tests/Menu.Tests.ps1`, agregar antes de `It 'shows the status and applies again what Windows reverted' {`:

```powershell
    It 'applies the chosen profiles after one question per tweak that asks first' {
        # Optimize, select "asking", go on, no to the high-risk list, yes to its tweak, apply, back to the menu, exit.
        $context = New-MenuContext @('1', '2', '', 'n', 'y', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[x\]  1\. Base \(base\): Test \(always\)'
        $text | Should -Match '\[x\]  2\. asking \(asking\)'
        $text | Should -Match '\[ \]  5\. System \(system\): Test \(administrator\)'
        $text | Should -Match '1/1 Title menu\.ask \[low risk\]: Reason'
        Get-Value 'One' | Should -Be 1
        Get-Value 'Ask' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'leaves out a tweak that asks first when the answer is no, with the reason declined' {
        $context = New-MenuContext @('1', '2', '', 'n', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -BeNullOrEmpty
        $result = Get-Content -LiteralPath (Join-Path @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName 'result.json') -Raw | ConvertFrom-Json
        ($result.results | Where-Object { $_.id -eq 'menu.ask' }).reason | Should -Be 'declined'
    }

    It 'adds a high-risk tweak only when it is asked for and the word is typed in full' {
        $context = New-MenuContext @('1', '', 'y', '1', '', 'no', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'They were not added.'
        Get-Value 'High' | Should -BeNullOrEmpty
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        $context = New-MenuContext @('1', '', 'y', '1', '', 'YES', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '\[high risk\] Title menu\.high \(menu\.high\): Reason'
        Get-Value 'High' | Should -Be 1
    }

    It 'shows the plan and changes nothing when it needs administrator' {
        $context = New-MenuContext @('1', '5', '', 'n', '', '0')
        $text = (Invoke-TuneupMenu -Context $context 3>$null 6>&1 | Out-String)
        $text | Should -Match 'System test'
        Get-Output $context | Should -Match 'This plan has system changes: open PowerShell as administrator'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'goes back without applying when the input ends in the middle' {
        $context = New-MenuContext @('1', '2', '', 'y', $null)
        { Invoke-Menu $context } | Should -Not -Throw
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'asks about a drifted tweak that asks first and one of high risk before applying them again' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        # Status, apply again, the word for the high-risk one, no to the one that asks, confirm, back, exit.
        $context = New-MenuContext @('2', 'r', 'YES', 'n', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[high risk\] Title menu\.high \(menu\.high\): Reason'
        $text | Should -Match '1/1 Title menu\.ask \[low risk\]: Reason'
        Get-Value 'One' | Should -Be 1
        Get-Value 'High' | Should -Be 1
        Get-Value 'Ask' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'leaves a drifted high-risk tweak alone unless its word is typed in full' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        $context = New-MenuContext @('2', 'r', 'y', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Not applied again: Title menu\.high\.'
        Get-Value 'High' | Should -Be 5
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }
```

En `tests/Cli.Tests.ps1`, agregar antes de `It 'leaves the menu at the end of standard input' {`:

```powershell
    It 'opens the menu without a command and reads the answers from standard input' {
        # Optimize, only base, apply, back to the menu, exit.
        $answers = @('1', '', 'y', '', '0')
        $output = $answers | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles') `
            -ActionsPath (Join-Path $Fixtures 'actions') -StateRoot $script:Root -Force -Lang en
        $LASTEXITCODE | Should -Be 0
        $text = $output -join "`n"
        $text | Should -Match '1\. Optimize: choose profiles and apply them'
        $text | Should -Match 'Applied: 2'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: FAIL en seis de las siete pruebas nuevas, la de fin de la entrada ya pasa (la opción 1 responde que `Invoke-TuneupMenuOptimize` no se reconoce, y las respuestas guionadas sobran).

- [ ] **Step 3: Elegir de una lista**

En `engine/Menu.ps1`, agregar después de la función `ConvertFrom-TuneupMenuNumberList`:

```powershell
# Lets the person turn items on and off by number until Enter alone. Gives the chosen indexes, or
# $null to go back (0, or the end of the input). Locked indexes stay chosen.
function Select-TuneupMenuItem {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$Prompt,
        [int[]]$Chosen = @(),
        [int[]]$Locked = @()
    )
    $selected = New-Object System.Collections.Generic.List[int]
    foreach ($index in @($Chosen) + @($Locked)) { if (-not $selected.Contains($index)) { $selected.Add($index) } }
    while ($true) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $mark = $(if ($selected.Contains($i)) { '[x]' } else { '[ ]' })
            Write-TuneupMenuLine -Context $Context -Text ('  {0} {1,2}. {2}' -f $mark, ($i + 1), $Lines[$i])
        }
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '0') { return $null }
        if ($answer -eq '') { return , @($selected | Sort-Object) }
        $numbers = ConvertFrom-TuneupMenuNumberList -Text $answer -Count $Lines.Count
        if ($null -eq $numbers) {
            Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
            continue
        }
        foreach ($number in $numbers) {
            $index = $number - 1
            if ($Locked -contains $index) { continue }
            if ($selected.Contains($index)) { [void]$selected.Remove($index) } else { $selected.Add($index) }
        }
    }
}
```

- [ ] **Step 4: Optimizar**

En `engine/Menu.ps1`, agregar después de la función `Invoke-TuneupMenu`:

```powershell
# Profiles, then the high-risk tweaks (only on request), then one question per tweak that asks first,
# then the plan with its warnings and the confirmation (Invoke-TuneupPlannedApply).
function Invoke-TuneupMenuOptimize {
    param([Parameter(Mandatory)]$Context)
    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
    if ($unsupported) { Write-TuneupCommandError -Context $Context -Message $unsupported; return }
    $definition = Import-TuneupContextDefinition -Context $Context
    if ($definition.Problems.Count) {
        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
        return
    }
    $profileIds = Select-TuneupMenuProfile -Context $Context -Definition $definition
    if ($null -eq $profileIds) { return }
    $highRisk = Select-TuneupMenuHighRisk -Context $Context -Definition $definition
    if ($null -eq $highRisk) { return }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $profileIds -Include $highRisk -Interactive)
    $declined = Request-TuneupMenuAskedTweak -Context $Context -Plan $plan -Requested $highRisk
    if ($null -eq $declined) { return }
    $environment = Get-TuneupContextEnvironment -Context $Context
    $needsAdmin = @($plan | Where-Object { $_.Action -eq 'apply' -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count
    if ($needsAdmin -and -not $environment.IsAdmin) {
        # The plan is shown anyway, so the person sees what needs administrator before going back.
        Write-TuneupPlanReport -Plan $plan -Environment $environment
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.optimize.needsAdmin')
        return
    }
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $profileIds -Include $highRisk -Exclude $declined
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request
}

# The profiles to apply (base is always on). $null to go back.
function Select-TuneupMenuProfile {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $byId = @{}
    foreach ($tweak in $Definition.Catalog) { $byId[[string]$tweak.id] = $tweak }
    $profiles = @(@($Definition.Profiles | Where-Object { $_.id -eq 'base' }) + @($Definition.Profiles | Where-Object { $_.id -ne 'base' }))
    $lines = @(foreach ($profileData in $profiles) {
        $admin = @($profileData.include | Where-Object { $byId.ContainsKey([string]$_) -and (Test-TuneupTweakNeedsAdmin -Tweak $byId[[string]$_]) }).Count
        $line = '{0} ({1}): {2}' -f (Get-TuneupLocalizedText $profileData.title), $profileData.id, (Get-TuneupLocalizedText $profileData.description)
        if ($admin) { $line += ' ' + (Get-TuneupText -Key 'menu.profile.admin') }
        if ($profileData.id -eq 'base') { $line += ' ' + (Get-TuneupText -Key 'menu.profile.always') }
        $line
    })
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.profiles.header')
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Locked @(0) -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen) { return $null }
    , @($chosen | Where-Object { $_ -ne 0 } | ForEach-Object { [string]$profiles[$_].id })
}

# High-risk tweaks are never in a profile: they are offered only when asked for, and added only after
# typing the confirmation word in full. Gives their ids (none is an empty list), or $null to go back.
function Select-TuneupMenuHighRisk {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $candidates = @($Definition.Catalog | Where-Object { $_.risk -eq 'high' -and (Test-TuneupCompatible -Tweak $_ -Environment $environment) })
    if (-not $candidates.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    $wanted = Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.high.offer' -Format $candidates.Count)
    if ($Context.InputEnded) { return $null }
    if (-not $wanted) { return , @() }
    $lines = @(foreach ($tweak in $candidates) {
        '{0} {1} ({2}): {3}' -f (Get-TuneupText -Key 'menu.high.mark'), (Get-TuneupTitle -Tweak $tweak), $tweak.id, (Get-TuneupLocalizedText $tweak.why)
    })
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen) { return $null }
    if (-not @($chosen).Count) { return , @() }
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.warning')
    $word = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.high.confirm' -Format (Get-TuneupText -Key 'menu.high.word'))
    if ($null -eq $word) { return $null }
    if ($word -ine (Get-TuneupText -Key 'menu.high.word')) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.notAdded')
        return , @()
    }
    , @($chosen | ForEach-Object { [string]$candidates[$_].id })
}

# A tweak of high risk that Windows reverted does not come back on its own either: each one is shown
# and applied again only after typing the confirmation word in full. Gives the ids confirmed (none is
# an empty list), or $null when the input ended.
function Confirm-TuneupMenuReappliedHighRisk {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][object[]]$Catalog, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Ids)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $high = @($Ids | ForEach-Object { $id = $_; $Catalog | Where-Object { $_.id -eq $id } } |
        Where-Object { $_.risk -eq 'high' -and (Test-TuneupCompatible -Tweak $_ -Environment $environment) })
    $confirmed = New-Object System.Collections.Generic.List[string]
    if (-not $high.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.warning')
    foreach ($tweak in $high) {
        Write-TuneupMenuLine -Context $Context -Text ('{0} {1} ({2}): {3}' -f (Get-TuneupText -Key 'menu.high.mark'), (Get-TuneupTitle -Tweak $tweak), $tweak.id, (Get-TuneupLocalizedText $tweak.why))
        $word = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.reapply.highConfirm' -Format (Get-TuneupText -Key 'menu.high.word'))
        if ($null -eq $word) { return $null }
        if ($word -ieq (Get-TuneupText -Key 'menu.high.word')) { $confirmed.Add([string]$tweak.id) }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.reapply.highSkipped' -Format (Get-TuneupTitle -Tweak $tweak)) }
    }
    , @($confirmed.ToArray())
}

# One question for each tweak of the plan that asks first (ask: true) and was not asked for by name:
# yes, no, yes to all the rest or no to all the rest. A no turns the item into a skip with the reason
# declined. Gives the ids said no to, or $null to go back.
function Request-TuneupMenuAskedTweak {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan, [AllowEmptyCollection()][string[]]$Requested = @())
    $asked = @($Plan | Where-Object { $_.Action -eq 'apply' -and $_.Tweak.ask -and $Requested -notcontains $_.Id })
    $declined = New-Object System.Collections.Generic.List[string]
    if (-not $asked.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.ask.header' -Format $asked.Count)
    $rest = $null
    for ($i = 0; $i -lt $asked.Count; $i++) {
        $item = $asked[$i]
        $answer = $rest
        if ($null -eq $answer) {
            Write-TuneupMenuLine -Context $Context -Text ('{0}/{1} {2} [{3}]: {4}' -f ($i + 1), $asked.Count, (Get-TuneupTitle -Tweak $item.Tweak),
                (Get-TuneupText -Key "risk.$($item.Tweak.risk)"), (Get-TuneupLocalizedText $item.Tweak.why))
            while ($null -eq $answer) {
                $typed = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.ask.prompt')
                if ($null -eq $typed) { return $null }
                $answer = switch ($typed.ToLowerInvariant()) {
                    (Get-TuneupText -Key 'menu.ask.yes') { 'yes' }
                    (Get-TuneupText -Key 'menu.ask.no') { 'no' }
                    (Get-TuneupText -Key 'menu.ask.all') { 'all' }
                    (Get-TuneupText -Key 'menu.ask.none') { 'none' }
                    default { $null }
                }
                if ($null -eq $answer) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid') }
            }
            if ($answer -eq 'all') { $rest = 'yes'; $answer = 'yes' }
            if ($answer -eq 'none') { $rest = 'no'; $answer = 'no' }
        }
        if ($answer -eq 'no') {
            $item.Action = 'skip'
            $item.Reason = 'declined'
            $declined.Add($item.Id)
        }
    }
    , @($declined.ToArray())
}
```

En `engine/Menu.ps1`, en `Invoke-TuneupMenuStatus`, reemplazar `Invoke-TuneupReapply -Context $Context -Items $items` por `Invoke-TuneupReapply -Context $Context -Items $items -Interactive`.

En `engine/Commands.ps1`, reemplazar, desde la línea `# compatibility checks still apply.` del comentario hasta el cierre `)` de `param`, por:

```powershell
# compatibility checks still apply. A drifted tweak that the catalog no longer has is left out with a
# warning: undoing the run that applied it restores it. -Interactive (the menu) asks about the tweaks
# that are left out otherwise: one question for each that asks first, and each one of high risk comes
# back only after typing the confirmation word in full.
function Invoke-TuneupReapply {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [switch]$PlanOnly,
        [switch]$Yes,
        [switch]$Interactive
    )
```

En `Invoke-TuneupReapply`, reemplazar las dos líneas `$plan = ... -Candidates $ids -NoBase)` y `$request = New-TuneupApplyRequest -Source 'reapply' -Include $ids` por:

```powershell
    $confirmed = @()
    if ($Interactive) {
        $confirmed = Confirm-TuneupMenuReappliedHighRisk -Context $Context -Catalog $definition.Catalog -Ids $ids
        if ($null -eq $confirmed) { return }
    }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -Candidates $ids -Include $confirmed -NoBase -Interactive:$Interactive)
    $declined = @()
    if ($Interactive) {
        # Back in the order of the runs that applied them: a confirmed tweak is planned first.
        $plan = @(foreach ($id in $ids) { $plan | Where-Object { $_.Id -eq $id } })
        $declined = Request-TuneupMenuAskedTweak -Context $Context -Plan $plan -Requested $confirmed
        if ($null -eq $declined) { return }
    }
    $request = New-TuneupApplyRequest -Source 'reapply' -Include $ids -Exclude $declined
```

En `i18n/es.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "reason.declined": "dijiste que no",
  "menu.profiles.header": "Perfiles (base se aplica siempre; (administrador) = necesita PowerShell como administrador):",
  "menu.profile.admin": "(administrador)",
  "menu.profile.always": "(siempre)",
  "menu.select.prompt": "Escribe números para marcar o desmarcar (por ejemplo 2,4), Enter para seguir, 0 para volver:",
  "menu.high.offer": "Hay {0} ajustes de riesgo alto que ningún perfil aplica. ¿Quieres verlos? (s/n)",
  "menu.high.mark": "[riesgo alto]",
  "menu.high.warning": "Los ajustes de riesgo alto bajan la protección de Windows o borran datos que deshacer no puede devolver (docs/es/profiles.md explica cada uno).",
  "menu.high.word": "si",
  "menu.high.confirm": "Para agregarlos, escribe {0} completo:",
  "menu.high.notAdded": "No se agregaron.",
  "menu.ask.header": "{0} ajustes preguntan antes de aplicarse:",
  "menu.ask.prompt": "¿Aplicarlo? s = sí, n = no, t = sí a todos los que quedan, x = no a todos los que quedan:",
  "menu.ask.yes": "s",
  "menu.ask.no": "n",
  "menu.ask.all": "t",
  "menu.ask.none": "x",
  "menu.optimize.needsAdmin": "Este plan tiene cambios de sistema: abre PowerShell como administrador y vuelve a correr tuneup.ps1, o elige solo perfiles sin (administrador).",
  "menu.reapply.highConfirm": "Windows lo revirtió. Para volver a aplicarlo, escribe {0} completo:",
  "menu.reapply.highSkipped": "No se vuelve a aplicar {0}."
```

En `i18n/en.json`, agregar estas claves al final (una coma después de la última clave que ya estaba):

```json
  "reason.declined": "you said no",
  "menu.profiles.header": "Profiles (base is always applied; (administrator) = needs PowerShell as administrator):",
  "menu.profile.admin": "(administrator)",
  "menu.profile.always": "(always)",
  "menu.select.prompt": "Type numbers to select or clear them (for example 2,4), Enter to go on, 0 to go back:",
  "menu.high.offer": "There are {0} high-risk tweaks that no profile applies. Look at them? (y/n)",
  "menu.high.mark": "[high risk]",
  "menu.high.warning": "High-risk tweaks lower the protection of Windows or remove data that undo cannot bring back (docs/en/profiles.md explains each one).",
  "menu.high.word": "yes",
  "menu.high.confirm": "To add them, type {0} in full:",
  "menu.high.notAdded": "They were not added.",
  "menu.ask.header": "{0} tweaks ask before being applied:",
  "menu.ask.prompt": "Apply it? y = yes, n = no, a = yes to all the rest, x = no to all the rest:",
  "menu.ask.yes": "y",
  "menu.ask.no": "n",
  "menu.ask.all": "a",
  "menu.ask.none": "x",
  "menu.optimize.needsAdmin": "This plan has system changes: open PowerShell as administrator and run tuneup.ps1 again, or choose only profiles without (administrator).",
  "menu.reapply.highConfirm": "Windows reverted it. To apply it again, type {0} in full:",
  "menu.reapply.highSkipped": "Not applied again: {0}."
```

- [ ] **Step 5: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: PASS (`Tests Passed: 15, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Cli.Tests.ps1`
Expected: PASS (`Tests Passed: 65, Failed: 0, Skipped: 1`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS (`Tests Passed: 4, Failed: 0`).

- [ ] **Step 6: Mirarlo**

Con las respuestas por la entrada estándar (no cambia nada del sistema real: catálogo de prueba, clave de prueba y estado en una carpeta temporal):

```bash
R=$(mktemp -d); printf '1\r\n3\r\n\r\ns\r\n\r\n0\r\n' | powershell -NoProfile -ExecutionPolicy Bypass -File tuneup.ps1 -CatalogPath tests/fixtures/catalog -ProfilesPath tests/fixtures/profiles -ActionsPath tests/fixtures/actions -StateRoot "$(cygpath -w $R)" -Force -Lang es
powershell -NoProfile -ExecutionPolicy Bypass -File tuneup.ps1 -StateRoot "$(cygpath -w $R)" -Lang es -Undo last
```

Expected (como salió en la copia de prueba): el encabezado `windows-tuneup 0.1.0 - Windows 11 Pro (compilación …)`, la línea de administrador, las seis opciones, los perfiles `[x]  1. Base (base): Prueba (siempre)` … `[ ]  4. Sistema (system): Prueba (administrador)`, el plan de 3 ajustes con "Antes de aplicar:" si hay un reinicio pendiente, `¿Aplicar 3 cambios? (s/n) s`, los tres `[aplicado]`, el resumen, "Presiona Enter para volver al menú." y de nuevo el menú. El segundo comando deshace la corrida.

- [ ] **Step 7: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 8: Commit**

```bash
git add engine/Menu.ps1 engine/Commands.ps1 i18n/es.json i18n/en.json tests/Menu.Tests.ps1 tests/Cli.Tests.ps1
git commit -m "feat: optimizar desde el menú, con preguntas y riesgo alto a pedido"
```

---

### Task 10b: Correcciones de la revisión de las Tasks 9 y 10

La revisión de las Tasks 9 y 10 pidió los cambios de esta tarea; el código de abajo **reemplaza** el de esos pasos donde se contradigan (`engine/Menu.ps1` y `tests/Menu.Tests.ps1` se vuelven a escribir completos, `engine/Prompts.ps1` es nuevo). Se hizo con TDD: las pruebas nuevas se escribieron primero y fallaron contra el código de la Task 10.

**Files:**
- Create: `engine/Prompts.ps1`
- Modify: `engine/Menu.ps1` (completo), `engine/Commands.ps1`, `engine/Output.ps1`, `i18n/es.json`, `i18n/en.json`
- Test: `tests/Menu.Tests.ps1` (completo), `tests/Commands.Tests.ps1`, `tests/Output.Tests.ps1`, `tests/Preflight.Tests.ps1`, `tests/I18n.Tests.ps1`

Qué cambia:

1. **Deshacer desde el menú.** El número de la corrida, la letra (`w`/`t`, `c`/`a`) y el número del ajuste se piden de nuevo con "Esa no es una de las opciones" cuando no valen (Enter solo vuelve). Una corrida o un ajuste ya deshechos se dicen directamente, sin pedir confirmación. La lista trae las 15 corridas más nuevas y avisa, si hay más, que las anteriores se deshacen con `-Undo <corrida>`.
2. **Plurales neutros.** Ningún texto lleva "{0} <sustantivo en plural>": `Ajustes revertidos por Windows: {0}.`, `Cambios por aplicar: {0}. ¿Aplicar? (s/n)`, `ajustes: {0}`, etc. (`confirm`, `interrupted.summary`, `reapply.noneUnverified`, `measure.waiting`, `menu.status.reapply`, `menu.undo.tweaks`, `menu.high.offer`, `menu.ask.header`). `aborted.saved` tenía un `\t` sin escapar (un tabulador entre `.` y `uneup.ps1`): se corrige, y `tests/I18n.Tests.ps1` exige que ningún texto lleve caracteres de control.
3. **La palabra de riesgo alto** se acepta como `sí`, `si` o `SÍ` en español (`menu.high.pattern`) y como `yes` en inglés, al optimizar y al reaplicar.
4. **Marcas** `(administrador)`/`(siempre)` justo después del título del perfil.
5. **El menú.** "Presiona Enter para volver" solo si la opción imprimió algo (`$Context.Pause`); una opción inválida o un Enter solo pide de nuevo sin repetir el encabezado; en Estado, una respuesta que no es `r` ni Enter es inválida y se pide de nuevo; textos propios del menú para salud sin administrador, rango de segundos y para deshacer lo recién aplicado (`run.saved.menu`, `interrupted.*.menu`, `aborted.saved.menu`, por `$Context.Menu`); `$Context.ExitCode = 0` en cada vuelta y los códigos de salida documentados en el comentario de `Invoke-TuneupMenu` (Ctrl+C en una pregunta detiene PowerShell mismo: el código es el de la última opción; no se puede capturar para despedirse); aviso claro si PowerShell se abrió con `-NonInteractive` sin entrada redirigida (`Get-TuneupMenuBlockMessage`, código 1).
6. **Optimizar.** El administrador se comprueba **antes** de las preguntas (solo los ajustes que no preguntan cuentan antes; después de las respuestas se comprueba de nuevo); teclear el número de `base` avisa que queda fijo; cada número cuenta una vez (`2,2`); a/t y x dicen "este y todos los que quedan".
7. **Orden del código.** `Confirm-TuneupMenuReappliedHighRisk`, `Request-TuneupMenuAskedTweak` y las preguntas genéricas pasan a `engine/Prompts.ps1` (las usa `Commands.ps1`); `Get-TuneupPlanningDefinition` junta lo que repetían `Invoke-TuneupApplyCommand`, `Invoke-TuneupReapply` y la opción Optimizar (rechazo de Windows no soportado y revisión del catálogo; devuelve el mensaje y el que llama escribe el error).
8. **Pruebas que matan mutantes:** a/x, base fijo, números fuera de lista y repetidos, orden y tope de las corridas, no confirmar, ya deshecho, fin de la entrada en cada selector, sesión en español (con `SÍ`), administrador antes de las preguntas.

- [ ] **Step 1: Pruebas (primero fallan)**

Reemplazar `tests/Menu.Tests.ps1` completo por:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'

    # The fixture catalog and profiles, plus a tweak that asks first, a high-risk one and a profile
    # with the one that asks.
    $script:Definitions = Join-Path $TestDrive 'definitions'
    $catalogDir = Join-Path $Definitions 'catalog'
    $profilesDir = Join-Path $Definitions 'profiles'
    New-Item -ItemType Directory -Path $catalogDir, $profilesDir -Force | Out-Null
    Copy-Item -Path (Join-Path $Fixtures 'catalog\*.json') -Destination $catalogDir
    Copy-Item -Path (Join-Path $Fixtures 'profiles\*.json') -Destination $profilesDir
    # menu.askadmin asks first and needs administrator (it is declined or never applied: no test runs elevated).
    $extra = @(
        (New-TestTweak -Id 'menu.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.ask2' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask2'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.ask3' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask3'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.askadmin' -Ask $true -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\Software\windows-tuneup-test'; name = 'AskAdmin'; kind = 'DWord'; value = 1 })),
        (New-TestTweak -Id 'menu.high' -Risk 'high' -Set ([pscustomobject]@{ path = $Key; name = 'High'; kind = 'DWord'; value = 1 }))
    )
    [System.IO.File]::WriteAllText((Join-Path $catalogDir 'menu.json'), (ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = $extra }) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'asking.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'asking' -Include @('menu.ask')) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'zadmin.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'zadmin' -Include @('menu.askadmin')) -Depth 10))
    [System.IO.File]::WriteAllText((Join-Path $profilesDir 'zmany.json'),
        (ConvertTo-Json -InputObject (New-TestProfile -Id 'zmany' -Include @('menu.ask', 'menu.ask2', 'menu.ask3')) -Depth 10))

    # The profiles in the order of the menu: base first, then by file name.
    # 1 base, 2 asking, 3 extra, 4 nested, 5 system, 6 zadmin, 7 zmany.
    function New-MenuContext([object[]]$Answers, [switch]$Admin) {
        $context = New-TuneupContext -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = $catalogDir
        $context.ProfilesPath = $profilesDir
        $context.Environment = New-TestEnvironment -IsAdmin ([bool]$Admin)
        $context
    }
    function Invoke-Menu($Context) { Invoke-TuneupMenu -Context $Context 3>$null 6>$null }
    function Get-Output($Context) { $Context.Io.Output -join "`n" }
    function Get-Count($Context, [string]$Pattern) { [regex]::Matches((Get-Output $Context), $Pattern).Count }
    function Get-Value([string]$Name) {
        if (-not (Test-Path -LiteralPath $Key)) { return $null }
        (Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue).$Name
    }
}

Describe 'Invoke-TuneupMenu' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'shows the options and exits with 0, or at the end of the input' {
        $context = New-MenuContext @('0')
        Invoke-Menu $context
        $context.ExitCode | Should -Be 0
        Get-Output $context | Should -Match ' 1\. Optimize: choose profiles and apply them'
        Get-Output $context | Should -Match 'Not running as administrator'
        $context = New-MenuContext @($null)
        Invoke-Menu $context
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says when an option does not exist and asks again' {
        $context = New-MenuContext @('9', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'That is not one of the options'
    }

    It 'applies the chosen profiles after one question per tweak that asks first' {
        # Optimize, select "asking", go on, no to the high-risk list, yes to its tweak, apply, back to the menu, exit.
        $context = New-MenuContext @('1', '2', '', 'n', 'y', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[x\]  1\. Base \(always\) \(base\): Test'
        $text | Should -Match '\[x\]  2\. asking \(asking\)'
        $text | Should -Match '\[ \]  5\. System \(administrator\) \(system\): Test'
        $text | Should -Match '1/1 Title menu\.ask \[low risk\]: Reason'
        Get-Value 'One' | Should -Be 1
        Get-Value 'Ask' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'leaves out a tweak that asks first when the answer is no, with the reason declined' {
        $context = New-MenuContext @('1', '2', '', 'n', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -BeNullOrEmpty
        $result = Get-Content -LiteralPath (Join-Path @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName 'result.json') -Raw | ConvertFrom-Json
        ($result.results | Where-Object { $_.id -eq 'menu.ask' }).reason | Should -Be 'declined'
    }

    It 'adds a high-risk tweak only when it is asked for and the word is typed in full' {
        $context = New-MenuContext @('1', '', 'y', '1', '', 'no', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Nothing was added\.'
        Get-Value 'High' | Should -BeNullOrEmpty
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        $context = New-MenuContext @('1', '', 'y', '1', '', 'YES', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '\[high risk\] Title menu\.high \(menu\.high\): Reason'
        Get-Value 'High' | Should -Be 1
    }

    It 'shows the plan and changes nothing when it needs administrator' {
        $context = New-MenuContext @('1', '5', '', 'n', '', '0')
        $text = (Invoke-TuneupMenu -Context $context 3>$null 6>&1 | Out-String)
        $text | Should -Match 'System test'
        Get-Output $context | Should -Match 'This plan has system changes: open PowerShell as administrator'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'goes back without applying when the input ends in the middle' {
        $context = New-MenuContext @('1', '2', '', 'y', $null)
        { Invoke-Menu $context } | Should -Not -Throw
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'asks about a drifted tweak that asks first and one of high risk before applying them again' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        # Status, apply again, the word for the high-risk one, no to the one that asks, confirm, back, exit.
        $context = New-MenuContext @('2', 'r', 'YES', 'n', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[high risk\] Title menu\.high \(menu\.high\): Reason'
        $text | Should -Match '1/1 Title menu\.ask \[low risk\]: Reason'
        Get-Value 'One' | Should -Be 1
        Get-Value 'High' | Should -Be 1
        Get-Value 'Ask' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'leaves a drifted high-risk tweak alone unless its word is typed in full' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        $context = New-MenuContext @('2', 'r', 'y', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Not applied again: Title menu\.high\.'
        Get-Value 'High' | Should -Be 5
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'shows the status and applies again what Windows reverted' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $context = New-MenuContext @('2', 'r', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Tweaks reverted by Windows: 1\.'
        Get-Value 'One' | Should -Be 1
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory).Count | Should -Be 2
    }

    It 'undoes a whole run picked from the list' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 'w', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 1\. \d{8}-\d{6}  tweaks: 2  \[pending\]  \(test folder\)'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'undoes one tweak of a run' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 't', '2', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 2\. Test two \(test\.two\)'
        Get-Value 'One' | Should -Be 1
        Get-Value 'Two' | Should -BeNullOrEmpty
    }

    It 'refuses the health check without administrator' {
        $context = New-MenuContext @('4', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'The health check needs PowerShell as administrator'
    }

    It 'offers to repair right after a check that found damage, reusing that check' {
        $found = [pscustomobject]@{ schemaVersion = 1; command = 'health'; startedAt = '2026-10-01T10:00:00'; finishedAt = '2026-10-01T10:20:00'
            repairRequested = $false; repairRan = $false; before = $null; after = $null; recommendation = 'run-repair'; rebootRecommended = $false }
        Mock -ModuleName Tuneup Invoke-TuneupHealth { $found }
        Mock -ModuleName Tuneup Write-TuneupHealthReport { }
        $context = New-MenuContext @('4', 'y', 'y', '', '0') -Admin
        Invoke-Menu $context
        Should -Invoke Invoke-TuneupHealth -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { -not $Repair -and $null -eq $Previous }
        Should -Invoke Invoke-TuneupHealth -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Repair -and $Previous.startedAt -eq '2026-10-01T10:00:00' }
    }

    It 'measures and then compares with the last measurement' {
        $context = New-MenuContext @('5', '', '', '5', 'x', '0', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'Type a number between 0 and 3600\.'
        $text | Should -Not -Match '-IdleSeconds'
        $text | Should -Match 'Compare with the last measurement \(\d{8}-\d{6}\)'
        $context.Result.comparison | Should -Not -BeNullOrEmpty
    }

    It 'asks again, without showing the menu again, when the option does not exist or nothing was typed' {
        $context = New-MenuContext @('9', '', '0')
        Invoke-Menu $context
        Get-Count $context 'windows-tuneup 0\.' | Should -Be 1
        Get-Count $context 'That is not one of the options' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'asks for Enter before the menu comes back only when the option printed something' {
        $context = New-MenuContext @('1', '0', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Not -Match 'Press Enter to go back'
        $context.Io.Pending.Count | Should -Be 0
        $context = New-MenuContext @('2', '', '0')
        Invoke-Menu $context
        Get-Count $context 'Press Enter to go back' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says an answer that is not r is invalid when Windows reverted something, and Enter goes back at once' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $context = New-MenuContext @('2', 'x', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 1
        Get-Output $context | Should -Not -Match 'Press Enter to go back'
        Get-Value 'One' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'keeps base chosen and says so when its number is typed' {
        $context = New-MenuContext @('1', '1', '', 'n', 'y', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'Option 1 always stays selected'
        ([regex]::Matches($text, '\[x\]  1\. Base')).Count | Should -Be 2
        Get-Value 'One' | Should -Be 1
    }

    It 'says a number out of the list is not valid and changes nothing of the selection' {
        $context = New-MenuContext @('1', '2,9', '', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 1
        Get-Output $context | Should -Not -Match '1/1 Title menu\.ask'
        Get-Value 'Ask' | Should -BeNullOrEmpty
        Get-Value 'One' | Should -Be 1
    }

    It 'counts a number typed twice once' {
        $context = New-MenuContext @('1', '2,2', '', 'n', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '1/1 Title menu\.ask'
        Get-Value 'Ask' | Should -Be 1
    }

    It 'answers yes to the tweak asked and to all the rest with the first answer a' {
        $context = New-MenuContext @('1', '7', '', 'n', 'a', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context '\d/3 Title menu\.ask\d? ' | Should -Be 1
        foreach ($name in 'Ask', 'Ask2', 'Ask3') { Get-Value $name | Should -Be 1 }
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'answers no to the rest, but not to what was already said yes to, with x' {
        $context = New-MenuContext @('1', '7', '', 'n', 'y', 'x', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'Ask2' | Should -BeNullOrEmpty
        Get-Value 'Ask3' | Should -BeNullOrEmpty
        $result = Get-Content -LiteralPath (Join-Path @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName 'result.json') -Raw | ConvertFrom-Json
        @($result.results | Where-Object { $_.reason -eq 'declined' } | ForEach-Object { $_.id }) -join ',' | Should -Be 'menu.ask2,menu.ask3'
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'keeps asking after a no, and a later a applies the rest' {
        $context = New-MenuContext @('1', '7', '', 'n', 'n', 'a', 'y', '', '0')
        Invoke-Menu $context
        Get-Value 'Ask' | Should -BeNullOrEmpty
        Get-Value 'Ask2' | Should -Be 1
        Get-Value 'Ask3' | Should -Be 1
    }

    It 'says x on the first question and applies none of the tweaks that ask' {
        $context = New-MenuContext @('1', '7', '', 'n', 'x', 'y', '', '0')
        Invoke-Menu $context
        foreach ($name in 'Ask', 'Ask2', 'Ask3') { Get-Value $name | Should -BeNullOrEmpty }
        Get-Value 'One' | Should -Be 1
    }

    It 'asks again when the answer to a question is not one of the letters' {
        $context = New-MenuContext @('1', '2', '', 'n', 'q', 'y', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 1
        Get-Value 'Ask' | Should -Be 1
    }

    It 'stops a plan that needs administrator before asking anything' {
        $context = New-MenuContext @('1', '2,5', '', 'n', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'This plan has system changes'
        $text | Should -Not -Match 'Apply it\?'
        Get-Value 'Ask' | Should -BeNullOrEmpty
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'asks about a tweak that needs administrator, and goes on when the answer is no' {
        $context = New-MenuContext @('1', '6', '', 'n', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match '1/1 Title menu\.askadmin'
        Get-Output $context | Should -Not -Match 'This plan has system changes'
        Get-Value 'One' | Should -Be 1
    }

    It 'says it needs administrator when the answer to a tweak that needs it is yes' {
        $context = New-MenuContext @('1', '6', '', 'n', 'y', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'This plan has system changes'
        Get-Value 'One' | Should -BeNullOrEmpty
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'talks about the menu, not about a parameter, when it says how to undo what it applied' {
        $context = New-MenuContext @('1', '', 'n', 'y', '', '0')
        $text = (Invoke-TuneupMenu -Context $context 3>$null 6>&1 | Out-String)
        $text | Should -Match 'To undo it, choose option 3 in the menu'
        $text | Should -Not -Match '-Undo'
    }

    It 'lists the 15 newest runs, newest first, and says that there are older ones' {
        foreach ($n in 1..17) { New-RunFolder -Root $Root -Id ('20260101-{0:D6}' -f $n) | Out-Null }
        $context = New-MenuContext @('3', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match ' 1\. 20260101-000017 '
        $text | Should -Match '15\. 20260101-000003 '
        $text | Should -Not -Match '20260101-000002'
        $text | Should -Match 'Only the 15 newest runs are listed'
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'does not mention older runs when all of them are listed' {
        New-RunFolder -Root $Root -Id '20260101-000001' | Out-Null
        $context = New-MenuContext @('3', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Not -Match 'newest runs are listed'
    }

    It 'asks again when the run, the way or the tweak is not valid' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '9', '1', 'z', 't', '0', '2', 'y', '', '0')
        Invoke-Menu $context
        Get-Count $context 'That is not one of the options' | Should -Be 3
        Get-Value 'Two' | Should -BeNullOrEmpty
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'changes nothing when the undo is not confirmed, and asks for no Enter' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 'w', 'n', '0')
        Invoke-Menu $context
        Get-Value 'One' | Should -Be 1
        Get-Value 'Two' | Should -Be 'x'
        Get-Output $context | Should -Not -Match 'Press Enter to go back'
        $context.Io.Pending.Count | Should -Be 0
        $context = New-MenuContext @('3', '1', 't', '1', 'n', '0')
        Invoke-Menu $context
        Get-Value 'One' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'says that a run or a tweak is already undone instead of asking to undo it' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '1', 't', '1', 'y', '', '3', '1', 't', '1', '', '3', '1', 'w', 'y', '', '3', '1', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match 'The tweak "Test one" was already undone'
        $text | Should -Match 'Run \d{8}-\d{6} was already undone'
        Get-Value 'One' | Should -BeNullOrEmpty
        Get-Value 'Two' | Should -BeNullOrEmpty
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'goes back when the input ends in the middle of any picker' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        foreach ($answers in @(@('3', $null), @('3', '1', $null), @('3', '1', 't', $null), @('3', '1', 'w', $null), @('1', $null), @('1', '', $null), @('2', $null), @('5', $null))) {
            $context = New-MenuContext $answers
            { Invoke-Menu $context } | Should -Not -Throw -Because ($answers -join ',')
            $context.Io.Pending.Count | Should -Be 0 -Because ($answers -join ',')
        }
        Get-Value 'One' | Should -Be 1
    }

    It 'shows the error of an option that fails, goes back to the menu and leaves the exit code at 0' {
        $context = New-MenuContext @('1', '', '0')
        $context.CatalogPath = Join-Path $TestDrive 'no-such-catalog'
        Invoke-Menu $context
        $context.ExitCode | Should -Be 0
        $context.Io.Pending.Count | Should -Be 0
    }
}

Describe 'Invoke-TuneupMenu in Spanish' {
    BeforeAll {
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'es'
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }

    It 'goes through optimize with a question and a high-risk tweak, with plurals that fit any count' {
        # Optimize, asking, go on, see the high-risk ones, the first, go on, the word with a capital and an accent, yes to its question, apply.
        $siWord = "S$([char]0x00CD)"
        $context = New-MenuContext @('1', '2', '', 's', '1', '', $siWord, 's', 's', '', '0')
        Invoke-Menu $context
        $text = Get-Output $context
        $text | Should -Match '\[x\]  1\. Base \(siempre\) \(base\): Prueba'
        $text | Should -Match '\[ \]  5\. Sistema \(administrador\) \(system\): Prueba'
        $text | Should -Match 'Ajustes de riesgo alto que ning.n perfil aplica: 1\. .Quieres verlos\? \(s/n\)'
        $text | Should -Match 'Ajustes que preguntan antes de aplicarse: 1'
        $text | Should -Match 'Cambios por aplicar: 4\. .Aplicar\? \(s/n\)'
        Get-Value 'Ask' | Should -Be 1
        Get-Value 'High' | Should -Be 1
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'accepts the word of a high-risk tweak with or without the accent, and not part of it' {
        foreach ($case in @(@("s$([char]0x00ED)", $true), @('si', $true), @('s', $false))) {
            if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
            $context = New-MenuContext @('1', '', 's', '1', '', $case[0], 's', '', '0')
            Invoke-Menu $context
            ((Get-Value 'High') -eq 1) | Should -Be $case[1] -Because $case[0]
        }
    }

    It 'applies again a high-risk tweak that Windows reverted when the word is typed with the accent' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Include 'menu.ask', 'menu.high' -Yes 6>$null
        foreach ($name in 'One', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        $context = New-MenuContext @('2', 'r', "s$([char]0x00ED)", 'n', 's', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match 'Ajustes revertidos por Windows: 3\.'
        Get-Value 'High' | Should -Be 1
        Get-Value 'Ask' | Should -Be 5
        $context.Io.Pending.Count | Should -Be 0
    }

    It 'lists the runs with a count that reads well for one tweak and for several' {
        Invoke-TuneupApplyCommand -Context (New-MenuContext @()) -Yes 6>$null
        $context = New-MenuContext @('3', '', '0')
        Invoke-Menu $context
        Get-Output $context | Should -Match ' 1\. \d{8}-\d{6}  ajustes: 2  \[pendiente\]'
    }
}

Describe 'Get-TuneupMenuBlockMessage' {
    BeforeAll {
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }

    It 'says the menu cannot ask when PowerShell is not interactive and the input is not redirected' {
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-NoProfile', '-NonInteractive', '-File', 'tuneup.ps1') -InputRedirected $false |
            Should -Match '-NonInteractive'
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-noni', '-File', 'tuneup.ps1') -InputRedirected $false | Should -Not -BeNullOrEmpty
    }

    It 'lets the menu run with a redirected input, or in an interactive PowerShell' {
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-NonInteractive', '-File', 'tuneup.ps1') -InputRedirected $true | Should -BeNullOrEmpty
        Get-TuneupMenuBlockMessage -CommandLineArgument @('powershell.exe', '-NoProfile', '-File', 'tuneup.ps1') -InputRedirected $false | Should -BeNullOrEmpty
    }
}
```

Los cambios de texto en las pruebas de otros archivos:

```diff
diff --git a/tests/Commands.Tests.ps1 b/tests/Commands.Tests.ps1
index ef3ab4f..6cd2e6c 100644
--- a/tests/Commands.Tests.ps1
+++ b/tests/Commands.Tests.ps1
@@ -55,7 +55,7 @@ Describe 'Commands' {
         $context = New-TestContext -Answers @('n')
         Invoke-TuneupApplyCommand -Context $context 6>$null
         $context.ExitCode | Should -Be 1
-        $context.Io.Output -join "`n" | Should -Match 'Apply 2 changes\? \(y/n\)'
+        $context.Io.Output -join "`n" | Should -Match 'Changes to apply: 2\. Apply\? \(y/n\)'
         $context.Io.Output -join "`n" | Should -Match 'Cancelled'
         Test-Path -LiteralPath $Key | Should -BeFalse
     }
@@ -162,7 +162,7 @@ Describe 'Commands' {
         Mock -ModuleName Tuneup New-TuneupMeasureReport { [pscustomobject]@{ schemaVersion = 1; command = 'measure' } }
         Mock -ModuleName Tuneup Write-TuneupMeasureReport { }
         Invoke-TuneupMeasureCommand -Context $context -IdleSeconds 5
-        $context.Io.Output -join "`n" | Should -Match 'Waiting 5 seconds idle'
+        $context.Io.Output -join "`n" | Should -Match 'Waiting idle before measuring \(5 s\)'
         $context.ExitCode | Should -Be 0
     }
 
@@ -272,7 +272,7 @@ Describe 'Re-applying what drifted' {
         $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 3>&1 6>&1 | Out-String)
         $text | Should -Match 'Tweak test.three was reverted but is no longer in the catalog'
         $text | Should -Match 'Plan: 1 to apply'
-        $human.Io.Output -join "`n" | Should -Match 'Apply 1 changes\? \(y/n\)'
+        $human.Io.Output -join "`n" | Should -Match 'Changes to apply: 1\. Apply\? \(y/n\)'
         $human.ExitCode | Should -Be 0
         (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
         (Get-ItemProperty -LiteralPath $Key).Three | Should -Be 5
@@ -323,7 +323,7 @@ Describe 'Re-applying what drifted' {
         $human = New-TestContext
         Invoke-TuneupStatusCommand -Context $human -Reapply 6>$null
         $text = $human.Io.Output -join "`n"
-        $text | Should -Match 'Nothing to apply again among what could be checked, but 1 tweaks need administrator'
+        $text | Should -Match 'Nothing to apply again among what could be checked\. Tweaks that need administrator to be checked: 1'
         $text | Should -Not -Match 'Windows reverted no tweak'
         $human.ExitCode | Should -Be 0
     }
@@ -342,6 +342,19 @@ Describe 'Invoke-TuneupCli' {
         Test-Path -LiteralPath $Root | Should -BeFalse
     }
 
+    It 'opens the menu when no command is given and says why when it cannot ask' {
+        Mock -ModuleName Tuneup Invoke-TuneupMenu { }
+        Mock -ModuleName Tuneup Get-TuneupMenuBlockMessage { $null }
+        $context = New-TuneupContext
+        Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -StateRoot $Root 6>$null
+        Should -Invoke Invoke-TuneupMenu -ModuleName Tuneup -Times 1 -Exactly
+        Mock -ModuleName Tuneup Get-TuneupMenuBlockMessage { 'The menu cannot ask here' }
+        $context = New-TuneupContext
+        Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -StateRoot $Root 6>$null
+        Should -Invoke Invoke-TuneupMenu -ModuleName Tuneup -Times 1 -Exactly
+        $context.ExitCode | Should -Be 1
+    }
+
     It 'resolves the folders into the context and runs the command they name' {
         $context = New-TuneupContext -Json
         $documents = @(Get-JsonOutput {
diff --git a/tests/I18n.Tests.ps1 b/tests/I18n.Tests.ps1
index 7432a9c..5c9bd08 100644
--- a/tests/I18n.Tests.ps1
+++ b/tests/I18n.Tests.ps1
@@ -31,6 +31,16 @@ Describe 'i18n' {
         $offenders -join ', ' | Should -BeNullOrEmpty
     }
 
+    It 'has no control characters in any text, such as the tab of an unescaped path separator' {
+        foreach ($lang in 'es', 'en') {
+            $texts = Get-Content -LiteralPath (Join-Path $I18nRoot "$lang.json") -Raw -Encoding UTF8 | ConvertFrom-Json
+            $offenders = foreach ($property in $texts.PSObject.Properties) {
+                if ([string]$property.Value -match '\p{Cc}') { $property.Name }
+            }
+            $offenders -join ', ' | Should -BeNullOrEmpty -Because $lang
+        }
+    }
+
     It 'formats texts with arguments' {
         Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
         Get-TuneupText -Key 'plan.header' -Format 3, 1 | Should -Be 'Plan: 3 to apply, 1 skipped'
diff --git a/tests/Output.Tests.ps1 b/tests/Output.Tests.ps1
index 69c5647..08433fe 100644
--- a/tests/Output.Tests.ps1
+++ b/tests/Output.Tests.ps1
@@ -122,7 +122,7 @@ Describe 'Reports of a run stopped with Ctrl+C' {
         $report.summary.skipped | Should -Be 1
         Get-TuneupApplyExitCode -Report $report | Should -Be 2
         $text = (Write-TuneupApplyReport -Report $report 6>&1 | Out-String)
-        $text | Should -Match 'Stopped with Ctrl\+C: 1 tweaks were not applied'
+        $text | Should -Match 'Stopped with Ctrl\+C\. Tweaks not applied: 1'
     }
 
     It 'exits with 1 when it stopped before the first tweak' {
diff --git a/tests/Preflight.Tests.ps1 b/tests/Preflight.Tests.ps1
index e573d38..a2905c6 100644
--- a/tests/Preflight.Tests.ps1
+++ b/tests/Preflight.Tests.ps1
@@ -126,7 +126,7 @@ Describe 'Preflight when applying' {
         Invoke-TuneupApplyCommand -Context $context 6>$null
         Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 1 -Exactly
         $output = $context.Io.Output -join "`n"
-        $output | Should -Match 'Apply 2 changes\? \(y/n\)[\s\S]*Turn on System Restore on .* before applying\? \(y/n\)'
+        $output | Should -Match 'Changes to apply: 2\. Apply\? \(y/n\)[\s\S]*Turn on System Restore on .* before applying\? \(y/n\)'
         @($context.Result.preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count | Should -Be 0
         $saved = Get-Content -LiteralPath (Join-Path $context.Result.runDir 'result.json') -Raw | ConvertFrom-Json
         @($saved.preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count | Should -Be 0
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: FAIL en 24 pruebas (textos, avisos y comportamiento nuevos).

- [ ] **Step 2: `engine/Prompts.ps1` (nuevo)**

```powershell
# Questions shared by the menu (Menu.ps1) and the commands it drives (Commands.ps1). They read and
# write through $Context.Io (Io.ps1), so they never touch the console directly and the end of the
# input ($null) is handled in one place: it marks the context and every caller goes back.

# The text of a { es, en } object in the language of the session.
function Get-TuneupLocalizedText {
    param([AllowNull()]$Text)
    if ($null -eq $Text) { return '' }
    $value = $Text.((Get-TuneupLang))
    if (-not $value) { $value = $Text.en }
    [string]$value
}

# An answer of the menu; $null, and the context marked, when the input ended.
function Read-TuneupMenuAnswer {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupIoAnswer -Io $Context.Io -Prompt $Prompt
    if ($null -eq $answer) { $Context.InputEnded = $true }
    $answer
}

function Read-TuneupMenuConfirmation {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
    ($null -ne $answer) -and ($answer -match (Get-TuneupText -Key 'confirm.pattern'))
}

function Write-TuneupMenuLine {
    param([Parameter(Mandatory)]$Context, [AllowEmptyString()][string]$Text = '')
    Write-TuneupIoLine -Io $Context.Io -Text $Text
}

# The word that adds a tweak of high risk: typed in full, with or without the accent in Spanish.
function Test-TuneupHighRiskWord {
    param([AllowNull()][string]$Answer)
    ($null -ne $Answer) -and ($Answer -match (Get-TuneupText -Key 'menu.high.pattern'))
}

# A tweak of high risk that Windows reverted does not come back on its own either: each one is shown
# and applied again only after typing the confirmation word in full. Gives the ids confirmed (none is
# an empty list), or $null when the input ended.
function Confirm-TuneupMenuReappliedHighRisk {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][object[]]$Catalog, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Ids)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $high = @($Ids | ForEach-Object { $id = $_; $Catalog | Where-Object { $_.id -eq $id } } |
        Where-Object { $_.risk -eq 'high' -and (Test-TuneupCompatible -Tweak $_ -Environment $environment) })
    $confirmed = New-Object System.Collections.Generic.List[string]
    if (-not $high.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.warning')
    foreach ($tweak in $high) {
        Write-TuneupMenuLine -Context $Context -Text ('{0} {1} ({2}): {3}' -f (Get-TuneupText -Key 'menu.high.mark'), (Get-TuneupTitle -Tweak $tweak), $tweak.id, (Get-TuneupLocalizedText $tweak.why))
        $word = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.reapply.highConfirm' -Format (Get-TuneupText -Key 'menu.high.word'))
        if ($null -eq $word) { return $null }
        if (Test-TuneupHighRiskWord -Answer $word) { $confirmed.Add([string]$tweak.id) }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.reapply.highSkipped' -Format (Get-TuneupTitle -Tweak $tweak)) }
    }
    , @($confirmed.ToArray())
}

# One question for each tweak of the plan that asks first (ask: true) and was not asked for by name:
# yes, no, yes to this one and all the rest, or no to this one and all the rest. A no turns the item
# into a skip with the reason declined. Gives the ids said no to, or $null when the input ended.
function Request-TuneupMenuAskedTweak {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan, [AllowEmptyCollection()][string[]]$Requested = @())
    $asked = @($Plan | Where-Object { $_.Action -eq 'apply' -and $_.Tweak.ask -and $Requested -notcontains $_.Id })
    $declined = New-Object System.Collections.Generic.List[string]
    if (-not $asked.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.ask.header' -Format $asked.Count)
    $rest = $null
    for ($i = 0; $i -lt $asked.Count; $i++) {
        $item = $asked[$i]
        $answer = $rest
        if ($null -eq $answer) {
            Write-TuneupMenuLine -Context $Context -Text ('{0}/{1} {2} [{3}]: {4}' -f ($i + 1), $asked.Count, (Get-TuneupTitle -Tweak $item.Tweak),
                (Get-TuneupText -Key "risk.$($item.Tweak.risk)"), (Get-TuneupLocalizedText $item.Tweak.why))
            while ($null -eq $answer) {
                $typed = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.ask.prompt')
                if ($null -eq $typed) { return $null }
                $answer = switch ($typed.ToLowerInvariant()) {
                    (Get-TuneupText -Key 'menu.ask.yes') { 'yes' }
                    (Get-TuneupText -Key 'menu.ask.no') { 'no' }
                    (Get-TuneupText -Key 'menu.ask.all') { 'all' }
                    (Get-TuneupText -Key 'menu.ask.none') { 'none' }
                    default { $null }
                }
                if ($null -eq $answer) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid') }
            }
            if ($answer -eq 'all') { $rest = 'yes'; $answer = 'yes' }
            if ($answer -eq 'none') { $rest = 'no'; $answer = 'no' }
        }
        if ($answer -eq 'no') {
            $item.Action = 'skip'
            $item.Reason = 'declined'
            $declined.Add($item.Id)
        }
    }
    , @($declined.ToArray())
}
```

- [ ] **Step 3: `engine/Menu.ps1` (completo)**

```powershell
# The interactive menu: tuneup.ps1 without a command. Questions and answers go through $Context.Io
# (Io.ps1, Prompts.ps1) and the work through the same commands as the command line (Commands.ps1).
# Every answer is a line of text (a number, a letter, or Enter alone), so it works the same in the
# Windows PowerShell console, Windows Terminal and a redirected input. The end of the input means
# back, all the way out. Marks are text ([x], (administrator), [high risk]), never a color alone.

# Numbers typed to pick items from a list of Count: "2,4" or "2 4"; each one counts once. $null when
# something else was typed.
function ConvertFrom-TuneupMenuNumberList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][int]$Count)
    $numbers = @()
    foreach ($part in @($Text -split '[,\s]+' | Where-Object { $_ })) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $Count) { return $null }
        if ($numbers -notcontains $number) { $numbers += $number }
    }
    , @($numbers)
}

# One number of a list of Count items; anything else is said to be invalid and asked again. $null for
# Enter alone (back) and for the end of the input.
function Read-TuneupMenuNumber {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][int]$Count)
    while ($true) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '') { return $null }
        $numbers = ConvertFrom-TuneupMenuNumberList -Text $answer -Count $Count
        if ($null -ne $numbers -and @($numbers).Count -eq 1) { return [int]@($numbers)[0] }
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
    }
}

# One of the given letters (any case); anything else is said to be invalid and asked again. $null for
# Enter alone (back) and for the end of the input.
function Read-TuneupMenuKey {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][string[]]$Keys)
    while ($true) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '') { return $null }
        foreach ($key in $Keys) { if ($answer -ieq $key) { return $key } }
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
    }
}

# Lets the person turn items on and off by number until Enter alone. Gives the chosen indexes, or
# $null to go back (0, or the end of the input). Locked indexes stay chosen.
function Select-TuneupMenuItem {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$Prompt,
        [int[]]$Chosen = @(),
        [int[]]$Locked = @()
    )
    $selected = New-Object System.Collections.Generic.List[int]
    foreach ($index in @($Chosen) + @($Locked)) { if (-not $selected.Contains($index)) { $selected.Add($index) } }
    while ($true) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $mark = $(if ($selected.Contains($i)) { '[x]' } else { '[ ]' })
            Write-TuneupMenuLine -Context $Context -Text ('  {0} {1,2}. {2}' -f $mark, ($i + 1), $Lines[$i])
        }
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt $Prompt
        if ($null -eq $answer -or $answer -eq '0') { return $null }
        if ($answer -eq '') { return , @($selected | Sort-Object) }
        $numbers = ConvertFrom-TuneupMenuNumberList -Text $answer -Count $Lines.Count
        if ($null -eq $numbers) {
            Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
            continue
        }
        foreach ($number in $numbers) {
            $index = $number - 1
            if ($Locked -contains $index) {
                Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.select.locked' -Format $number)
                continue
            }
            if ($selected.Contains($index)) { [void]$selected.Remove($index) } else { $selected.Add($index) }
        }
    }
}

# Why the menu cannot ask anything, or nothing when it can: PowerShell started with -NonInteractive
# and an input that is not redirected has nobody to answer, and Read-Host would fail with a PowerShell
# error. Gives the text for the person.
function Get-TuneupMenuBlockMessage {
    param(
        [string[]]$CommandLineArgument = [Environment]::GetCommandLineArgs(),
        [bool]$InputRedirected = [Console]::IsInputRedirected
    )
    $nonInteractive = @($CommandLineArgument | Where-Object { $_ -match '^[-/]noni' }).Count -gt 0
    if ($nonInteractive -and -not $InputRedirected) { Get-TuneupText -Key 'menu.nonInteractive' }
}

function Write-TuneupMenuHeader {
    param([Parameter(Mandatory)]$Context)
    $environment = Get-TuneupContextEnvironment -Context $Context
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.title' -Format (Get-TuneupVersion), $environment.Family, $environment.Edition, $environment.Build)
    $adminKey = $(if ($environment.IsAdmin) { 'menu.admin.yes' } else { 'menu.admin.no' })
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key $adminKey)
    if ($environment.IsManaged) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.managed') }
    Write-TuneupMenuLine -Context $Context
    foreach ($key in 'menu.main.optimize', 'menu.main.status', 'menu.main.undo', 'menu.main.health', 'menu.main.measure', 'menu.main.exit') {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key $key)
    }
}

# The options come back to the menu when they finish; an option that printed something asks for Enter
# first ($Context.Pause), so the screen is not wiped before it is read. The exit code is 0 when the
# menu is left with 0 or at the end of the input: an option that fails shows its error and the menu
# goes on, so the failure is not the code of the session. Ctrl+C at a prompt stops PowerShell itself:
# the code is then the one of the last option (0 at the main prompt).
function Invoke-TuneupMenu {
    param([Parameter(Mandatory)]$Context)
    $Context.InputEnded = $false
    $Context.Menu = $true
    while (-not $Context.InputEnded) {
        $Context.ExitCode = 0
        Write-TuneupMenuHeader -Context $Context
        $action = $null
        $leave = $false
        while ($null -eq $action) {
            $choice = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.choose')
            if ($null -eq $choice -or $choice -eq '0') { $leave = $true; break }
            $action = switch ($choice) {
                '1' { 'Optimize' }
                '2' { 'Status' }
                '3' { 'Undo' }
                '4' { 'Health' }
                '5' { 'Measure' }
                default { $null }
            }
            if ($null -eq $action -and $choice -ne '') { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid') }
        }
        if ($leave) { break }
        $Context.Pause = $false
        # A failure ends that option, not the menu: it is shown and the menu comes back.
        try {
            & "Invoke-TuneupMenu$action" -Context $Context
        } catch {
            Write-TuneupErrorReport -Message $_.Exception.Message
            $Context.Pause = $true
        }
        if ($Context.InputEnded) { break }
        if ($Context.Pause -and $null -eq (Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.back'))) { break }
    }
    $Context.Menu = $false
    $Context.ExitCode = 0
}

# The profiles to apply (base is always on). $null to go back.
function Select-TuneupMenuProfile {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $byId = @{}
    foreach ($tweak in $Definition.Catalog) { $byId[[string]$tweak.id] = $tweak }
    $profiles = @(@($Definition.Profiles | Where-Object { $_.id -eq 'base' }) + @($Definition.Profiles | Where-Object { $_.id -ne 'base' }))
    $lines = @(foreach ($profileData in $profiles) {
        $marks = @()
        if (@($profileData.include | Where-Object { $byId.ContainsKey([string]$_) -and (Test-TuneupTweakNeedsAdmin -Tweak $byId[[string]$_]) }).Count) {
            $marks += Get-TuneupText -Key 'menu.profile.admin'
        }
        if ($profileData.id -eq 'base') { $marks += Get-TuneupText -Key 'menu.profile.always' }
        # The marks go right after the title, where they are read first.
        '{0}{1} ({2}): {3}' -f (Get-TuneupLocalizedText $profileData.title), $(if ($marks.Count) { ' ' + ($marks -join ' ') }),
            $profileData.id, (Get-TuneupLocalizedText $profileData.description)
    })
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.profiles.header')
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Locked @(0) -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen) { return $null }
    , @($chosen | Where-Object { $_ -ne 0 } | ForEach-Object { [string]$profiles[$_].id })
}

# High-risk tweaks are never in a profile: they are offered only when asked for, and added only after
# typing the confirmation word in full. Gives their ids (none is an empty list), or $null to go back.
function Select-TuneupMenuHighRisk {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Definition)
    $environment = Get-TuneupContextEnvironment -Context $Context
    $candidates = @($Definition.Catalog | Where-Object { $_.risk -eq 'high' -and (Test-TuneupCompatible -Tweak $_ -Environment $environment) })
    if (-not $candidates.Count) { return , @() }
    Write-TuneupMenuLine -Context $Context
    $wanted = Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.high.offer' -Format $candidates.Count)
    if ($Context.InputEnded) { return $null }
    if (-not $wanted) { return , @() }
    $lines = @(foreach ($tweak in $candidates) {
        '{0} {1} ({2}): {3}' -f (Get-TuneupText -Key 'menu.high.mark'), (Get-TuneupTitle -Tweak $tweak), $tweak.id, (Get-TuneupLocalizedText $tweak.why)
    })
    $chosen = Select-TuneupMenuItem -Context $Context -Lines $lines -Prompt (Get-TuneupText -Key 'menu.select.prompt')
    if ($null -eq $chosen) { return $null }
    if (-not @($chosen).Count) { return , @() }
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.warning')
    $word = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.high.confirm' -Format (Get-TuneupText -Key 'menu.high.word'))
    if ($null -eq $word) { return $null }
    if (-not (Test-TuneupHighRiskWord -Answer $word)) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.high.notAdded')
        return , @()
    }
    , @($chosen | ForEach-Object { [string]$candidates[$_].id })
}

# When the plan has system changes and PowerShell is not elevated, shows the plan anyway (so the
# person sees what needs administrator) and says so; $true when it did, and the option ends there.
# -Ignore: tweaks that are still to be asked about, which may yet be declined.
function Test-TuneupMenuBlockedByAdministrator {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan, [AllowEmptyCollection()][string[]]$Ignore = @())
    $environment = Get-TuneupContextEnvironment -Context $Context
    if ($environment.IsAdmin) { return $false }
    $needsAdmin = @($Plan | Where-Object { $_.Action -eq 'apply' -and $Ignore -notcontains $_.Id -and (Test-TuneupTweakNeedsAdmin -Tweak $_.Tweak) }).Count
    if (-not $needsAdmin) { return $false }
    Write-TuneupPlanReport -Plan $Plan -Environment $environment
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.optimize.needsAdmin')
    $Context.Pause = $true
    $true
}

# Profiles, then the high-risk tweaks (only on request), then one question per tweak that asks first,
# then the plan with its warnings and the confirmation (Invoke-TuneupPlannedApply). A plan that needs
# administrator is stopped before any question is asked, unless a tweak that asks could still be the
# only one that needs it.
function Invoke-TuneupMenuOptimize {
    param([Parameter(Mandatory)]$Context)
    $ready = Get-TuneupPlanningDefinition -Context $Context
    if ($ready.Message) {
        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
        $Context.Pause = $true
        return
    }
    $definition = $ready.Definition
    $profileIds = Select-TuneupMenuProfile -Context $Context -Definition $definition
    if ($null -eq $profileIds) { return }
    $highRisk = Select-TuneupMenuHighRisk -Context $Context -Definition $definition
    if ($null -eq $highRisk) { return }
    $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $profileIds -Include $highRisk -Interactive)
    $toAsk = @($plan | Where-Object { $_.Action -eq 'apply' -and $_.Tweak.ask -and $highRisk -notcontains $_.Id } | ForEach-Object { [string]$_.Id })
    if (Test-TuneupMenuBlockedByAdministrator -Context $Context -Plan $plan -Ignore $toAsk) { return }
    $declined = Request-TuneupMenuAskedTweak -Context $Context -Plan $plan -Requested $highRisk
    if ($null -eq $declined) { return }
    if (Test-TuneupMenuBlockedByAdministrator -Context $Context -Plan $plan) { return }
    $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $profileIds -Include $highRisk -Exclude $declined
    $Context.Pause = $true
    Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request
}

# The status, and when Windows reverted something, the offer to apply it again.
function Invoke-TuneupMenuStatus {
    param([Parameter(Mandatory)]$Context)
    Invoke-TuneupStatusCommand -Context $Context
    $Context.Pause = $true
    $items = @($Context.Result)
    $drifted = @($items | Where-Object { $_.status -eq 'drift' }).Count
    if (-not $drifted) { return }
    while ($true) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.status.reapply' -Format $drifted)
        if ($null -eq $answer) { return }
        # Enter was the answer to the question: the menu comes back at once.
        if ($answer -eq '') { $Context.Pause = $false; return }
        if ($answer -ieq (Get-TuneupText -Key 'menu.status.reapplyKey')) {
            Invoke-TuneupReapply -Context $Context -Items $items -Interactive
            return
        }
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.invalid')
    }
}

# The runs that can be undone, newest first (the 15 newest; older ones by command line); then the
# whole run or one of its tweaks. What is already undone is said, not asked about.
function Invoke-TuneupMenuUndo {
    param([Parameter(Mandatory)]$Context)
    $maxRuns = 15
    $all = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupRunList -StateRoot $Context.StateRoot } |
        Where-Object { Test-TuneupRunHasJournal -Dir $_.Dir })
    [array]::Reverse($all)
    $runs = @($all | Select-Object -First $maxRuns)
    if (-not $runs.Count) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'undo.none')
        $Context.Pause = $true
        return
    }
    Write-TuneupMenuLine -Context $Context
    Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.header')
    for ($i = 0; $i -lt $runs.Count; $i++) {
        $run = $runs[$i]
        $count = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupJournal -Path (Join-Path $run.Dir 'snapshot.jsonl') -Root $run.Root }).Count
        $state = $(if ($run.Undone -or (Test-TuneupRunAllNotedUndone -Run $run)) { 'menu.undo.state.undone' }
            elseif (@(Get-TuneupUndoneTweakId -Run $run).Count) { 'menu.undo.state.partly' } else { 'menu.undo.state.pending' })
        $where = switch ($run.Root) { 'machine' { 'menu.undo.root.machine' } 'user' { 'menu.undo.root.user' } default { 'menu.undo.root.custom' } }
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1}  {2}  {3}  {4}' -f ($i + 1), $run.Id, (Get-TuneupText -Key 'menu.undo.tweaks' -Format $count),
            (Get-TuneupText -Key $state), (Get-TuneupText -Key $where))
    }
    if ($all.Count -gt $maxRuns) { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.more' -Format $maxRuns) }
    $number = Read-TuneupMenuNumber -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickRun') -Count $runs.Count
    if ($null -eq $number) { return }
    $run = $runs[$number - 1]
    if ($run.Undone -or (Test-TuneupRunAllNotedUndone -Run $run)) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $run.Id)
        $Context.Pause = $true
        return
    }
    $wholeKey = Get-TuneupText -Key 'menu.undo.wholeKey'
    $tweakKey = Get-TuneupText -Key 'menu.undo.tweakKey'
    $how = Read-TuneupMenuKey -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.how') -Keys @($wholeKey, $tweakKey)
    if ($null -eq $how) { return }
    if ($how -eq $wholeKey) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmRun' -Format $run.Id)) {
            $Context.Pause = $true
            Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id
        }
        return
    }
    $entries = @(Invoke-TuneupContextStep -Context $Context -Step { Read-TuneupRunJournal -Run $run })
    $done = @(Get-TuneupUndoneTweakId -Run $run)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $mark = $(if ($done -contains $entries[$i].id) { ' ' + (Get-TuneupText -Key 'menu.undo.state.undone') } else { '' })
        Write-TuneupMenuLine -Context $Context -Text ('  {0,2}. {1} ({2}){3}' -f ($i + 1), (Get-TuneupTitle -Tweak $entries[$i].tweak), $entries[$i].id, $mark)
    }
    $number = Read-TuneupMenuNumber -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.pickTweak') -Count $entries.Count
    if ($null -eq $number) { return }
    $entry = $entries[$number - 1]
    $title = Get-TuneupTitle -Tweak $entry.tweak
    if ($done -contains $entry.id) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.undo.tweakAlreadyUndone' -Format $title)
        $Context.Pause = $true
        return
    }
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.undo.confirmTweak' -Format $title)) {
        $Context.Pause = $true
        Invoke-TuneupUndoCommand -Context $Context -RunId $run.Id -TweakId ([string]$entry.id)
    }
}

# SFC and DISM, and when they find damage that can be repaired, the offer to repair it now (without
# checking again: the check that was just made is reused).
function Invoke-TuneupMenuHealth {
    param([Parameter(Mandatory)]$Context)
    if (-not (Get-TuneupContextEnvironment -Context $Context).IsAdmin) {
        Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.health.needsAdmin')
        $Context.Pause = $true
        return
    }
    if (-not (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.confirm'))) { return }
    $Context.Pause = $true
    Invoke-TuneupHealthCommand -Context $Context
    $report = $Context.Result
    if ($null -eq $report -or $report.recommendation -ne 'run-repair') { return }
    if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.health.repair')) {
        Invoke-TuneupHealthCommand -Context $Context -Repair -Previous $report
    }
}

# A measurement after some seconds idle, compared with the last one if there is one and the person wants.
function Invoke-TuneupMenuMeasure {
    param([Parameter(Mandatory)]$Context)
    $seconds = $null
    while ($null -eq $seconds) {
        $answer = Read-TuneupMenuAnswer -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.idle')
        if ($null -eq $answer) { return }
        if ($answer -eq '') { $seconds = 0; break }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 0 -and $number -le 3600) { $seconds = $number }
        else { Write-TuneupMenuLine -Context $Context -Text (Get-TuneupText -Key 'menu.measure.range' -Format 0, 3600) }
    }
    $compare = $null
    $earlier = @(Invoke-TuneupContextStep -Context $Context -Step { Get-TuneupMeasurementList -StateRoot $Context.StateRoot })
    if ($earlier.Count) {
        if (Read-TuneupMenuConfirmation -Context $Context -Prompt (Get-TuneupText -Key 'menu.measure.compare' -Format $earlier[-1].Id)) { $compare = 'last' }
        if ($Context.InputEnded) { return }
    }
    $Context.Pause = $true
    Invoke-TuneupMeasureCommand -Context $Context -IdleSeconds $seconds -Compare $compare
}
```

- [ ] **Step 4: Comandos, informe y textos**

```diff
diff --git a/engine/Commands.ps1 b/engine/Commands.ps1
index 6dc5858..b74a321 100644
--- a/engine/Commands.ps1
+++ b/engine/Commands.ps1
@@ -6,6 +6,8 @@
 # What one invocation shares between its steps: JSON or text, the folders for testing, the warnings
 # collected so far, the questions and answers (Io), the exit code and the last result. The exit code
 # starts at 1 and every command sets 0 when it succeeds, so one that dies before reporting is a failure.
+# Menu is on while the menu runs, so what a command says about undoing names the menu and not a
+# parameter; Pause is set by a menu option that printed something to be read before the menu returns.
 function New-TuneupContext {
     param([switch]$Json, $Io)
     [pscustomobject]@{
@@ -20,6 +22,8 @@ function New-TuneupContext {
         ScriptRoot   = $null
         Io           = $(if ($null -ne $Io) { $Io } else { New-TuneupConsoleIo })
         InputEnded   = $false
+        Menu         = $false
+        Pause        = $false
         ExitCode     = 1
         Result       = $null
     }
@@ -97,16 +101,12 @@ function Invoke-TuneupReapply {
         $Context.ExitCode = 0
         return
     }
-    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
-    if ($unsupported) {
-        Write-TuneupCommandError -Context $Context -Message $unsupported
-        return
-    }
-    $definition = Import-TuneupContextDefinition -Context $Context
-    if ($definition.Problems.Count) {
-        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
+    $ready = Get-TuneupPlanningDefinition -Context $Context
+    if ($ready.Message) {
+        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
         return
     }
+    $definition = $ready.Definition
     $known = @{}
     foreach ($tweak in $definition.Catalog) { $known[[string]$tweak.id] = $true }
     $missing = @($drifted | Where-Object { -not $known.ContainsKey($_) })
@@ -227,6 +227,21 @@ function Get-TuneupUnsupportedMessage {
     if ($environment.IsServer) { $environment.Edition = 'Enterprise' }
 }
 
+# The start of every command that plans: the refusal of an unsupported Windows and the catalog with
+# its profiles. Gives { Definition, Message, Details }; Message is set when the command cannot go on
+# and its caller writes the error (with -Json the report is output, and written here it would be
+# mixed into what this returns).
+function Get-TuneupPlanningDefinition {
+    param([Parameter(Mandatory)]$Context)
+    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
+    if ($unsupported) { return [pscustomobject]@{ Definition = $null; Message = $unsupported; Details = [string[]]@() } }
+    $definition = Import-TuneupContextDefinition -Context $Context
+    if ($definition.Problems.Count) {
+        return [pscustomobject]@{ Definition = $null; Message = (Get-TuneupText -Key 'err.catalog'); Details = $definition.Problems }
+    }
+    [pscustomobject]@{ Definition = $definition; Message = $null; Details = [string[]]@() }
+}
+
 # The catalog and the profiles, with the problems that the checks found (none when they are valid).
 function Import-TuneupContextDefinition {
     param([Parameter(Mandatory)]$Context)
@@ -271,16 +286,12 @@ function Invoke-TuneupApplyCommand {
         [switch]$PlanOnly,
         [switch]$Yes
     )
-    $unsupported = Get-TuneupUnsupportedMessage -Context $Context
-    if ($unsupported) {
-        Write-TuneupCommandError -Context $Context -Message $unsupported
-        return
-    }
-    $definition = Import-TuneupContextDefinition -Context $Context
-    if ($definition.Problems.Count) {
-        Write-TuneupCommandError -Context $Context -Message (Get-TuneupText -Key 'err.catalog') -Details $definition.Problems
+    $ready = Get-TuneupPlanningDefinition -Context $Context
+    if ($ready.Message) {
+        Write-TuneupCommandError -Context $Context -Message $ready.Message -Details $ready.Details
         return
     }
+    $definition = $ready.Definition
     $plan = @(New-TuneupContextPlan -Context $Context -Definition $definition -ProfileIds $ProfileIds -Include $Include -Exclude $Exclude)
     $request = New-TuneupApplyRequest -Source 'profiles' -Profiles $ProfileIds -Include $Include -Exclude $Exclude
     Invoke-TuneupPlannedApply -Context $Context -Plan $plan -Request $request -PlanOnly:$PlanOnly -Yes:$Yes
@@ -382,7 +393,7 @@ function Invoke-TuneupPlannedApply {
     $saved = Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyReport -Run $run -Report $report }
     Invoke-TuneupContextStep -Context $Context -Step { Save-TuneupApplyTranscript -Context $Context -Run $run -Request $Request -Plan $Plan -Report $report }
     $Context.Result = $report
-    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json
+    Write-TuneupApplyReport -Report $report -Warnings $Context.Warnings.ToArray() -Json:$Context.Json -FromMenu:$Context.Menu
     $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
 }
 
@@ -459,7 +470,9 @@ function Save-TuneupStoppedApply {
     $Context.Result = $report
     $Context.ExitCode = Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved)
     if (-not $Context.Json) {
-        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key $(if ($Failure) { 'aborted.saved' } else { 'interrupted.saved' }) -Format $Run.Id)
+        $savedKey = $(if ($Failure) { 'aborted.saved' } else { 'interrupted.saved' })
+        if ($Context.Menu) { $savedKey += '.menu' }
+        Write-TuneupIoLine -Io $Context.Io -Text (Get-TuneupText -Key $savedKey -Format $Run.Id)
     }
 }
 
@@ -547,7 +560,12 @@ function Invoke-TuneupCli {
     Get-TuneupContextEnvironment -Context $Context | Out-Null
 
     # No command and no option of applying: the menu (with -Json there is nobody to ask).
-    if (-not $present.Count -and -not $Context.Json) { Invoke-TuneupMenu -Context $Context; return }
+    if (-not $present.Count -and -not $Context.Json) {
+        $blocked = Get-TuneupMenuBlockMessage
+        if ($blocked) { Write-TuneupCommandError -Context $Context -Message $blocked; return }
+        Invoke-TuneupMenu -Context $Context
+        return
+    }
     if ($Status) { Invoke-TuneupStatusCommand -Context $Context -Reapply:$Reapply -PlanOnly:$PlanOnly -Yes:$Yes; return }
     if ($Undo) { Invoke-TuneupUndoCommand -Context $Context -RunId $Undo -TweakId $Tweak; return }
     if ($Health) { Invoke-TuneupHealthCommand -Context $Context -Repair:$Repair; return }
diff --git a/engine/Output.ps1 b/engine/Output.ps1
index 69f436d..d60d918 100644
--- a/engine/Output.ps1
+++ b/engine/Output.ps1
@@ -179,9 +179,12 @@ function Write-TuneupApplyReport {
     param(
         [Parameter(Mandatory)]$Report,
         [AllowEmptyCollection()][string[]]$Warnings = @(),
-        [switch]$Json
+        [switch]$Json,
+        # Shown from the menu: what it says about undoing names the menu, not a parameter.
+        [switch]$FromMenu
     )
     if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
+    $suffix = $(if ($FromMenu) { '.menu' } else { '' })
     $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red'; 'skipped' = 'Yellow' }
     foreach ($result in $Report.results) {
         if ($result.reason -eq 'journal-error') {
@@ -202,10 +205,10 @@ function Write-TuneupApplyReport {
     Write-Host ''
     Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.partial, $summary.notApplied, $summary.failed, $summary.skipped, $summary.refused)
     if ($summary.PSObject.Properties['interrupted'] -and $summary.interrupted) {
-        Write-Host (Get-TuneupText -Key 'interrupted.summary' -Format $summary.interrupted) -ForegroundColor Yellow
+        Write-Host (Get-TuneupText -Key "interrupted.summary$suffix" -Format $summary.interrupted) -ForegroundColor Yellow
     }
     Write-Host (Get-TuneupText -Key "restore.$($Report.restorePoint)")
-    Write-Host (Get-TuneupText -Key 'run.saved' -Format $Report.runId, $Report.runDir)
+    Write-Host (Get-TuneupText -Key "run.saved$suffix" -Format $Report.runId, $Report.runDir)
     if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
     # A restart also signs the user out, so the sign-out line is only needed without one.
     elseif ($Report.signOutRequired) { Write-Host (Get-TuneupText -Key 'signOut') -ForegroundColor Yellow }
```

```diff
diff --git a/i18n/en.json b/i18n/en.json
index e84cd30..400564b 100644
--- a/i18n/en.json
+++ b/i18n/en.json
@@ -18,7 +18,7 @@
   "plan.skip": "  - {0}: {1}",
   "plan.needsAdmin": "To apply the system changes, open PowerShell as administrator.",
   "nothing": "Nothing to change.",
-  "confirm": "Apply {0} changes? (y/n)",
+  "confirm": "Changes to apply: {0}. Apply? (y/n)",
   "confirm.pattern": "^(y|yes)$",
   "aborted": "Cancelled. Nothing was changed.",
   "risk.low": "low risk",
@@ -109,7 +109,7 @@
   "err.measurementNotFound": "Measurement {0} does not exist.",
   "err.noMeasurements": "There are no saved measurements to compare against.",
   "err.idleSecondsRange": "-IdleSeconds must be between {0} and {1}.",
-  "measure.waiting": "Waiting {0} seconds idle before measuring...",
+  "measure.waiting": "Waiting idle before measuring ({0} s)...",
   "measure.header": "Measurement {0}:",
   "measure.line": "  {0}: {1}",
   "measure.saved": "Saved in {0}.",
@@ -131,7 +131,7 @@
   "undo.manual": "To restore it by hand, run this in PowerShell as administrator (a user tweak does not need it):",
   "undo.manual.action": "Restore it by hand: README (Tweak types) explains what the '{0}' action changes.",
   "reason.interrupted": "not applied: the run was stopped with Ctrl+C",
-  "interrupted.summary": "Stopped with Ctrl+C: {0} tweaks were not applied. What was applied can be undone with -Undo.",
+  "interrupted.summary": "Stopped with Ctrl+C. Tweaks not applied: {0}. What was applied can be undone with -Undo.",
   "interrupted.saved": "Stopped with Ctrl+C. The result of run {0} was saved; to undo it: .\\tuneup.ps1 -Undo {0}",
   "transcript.header": "windows-tuneup {0} - run {1} - {2}",
   "transcript.request.profiles": "Asked for: profiles {0}; included {1}; excluded {2}",
@@ -151,9 +151,9 @@
   "preflight.restoreEnableFailed": "System Restore could not be turned on: {0}",
   "reapply.none": "Nothing to apply again: Windows reverted no tweak.",
   "interrupted.hint": "Ctrl+C stops after the tweak in progress; Ctrl+Break interrupts at once",
-  "aborted.saved": "The run stopped because of an error. The result of run {0} was saved; to undo it: .\tuneup.ps1 -Undo {0}",
+  "aborted.saved": "The run stopped because of an error. The result of run {0} was saved; to undo it: .\\tuneup.ps1 -Undo {0}",
   "reason.aborted": "not applied: the run stopped because of an error",
-  "reapply.noneUnverified": "Nothing to apply again among what could be checked, but {0} tweaks need administrator to be checked: run it again as administrator.",
+  "reapply.noneUnverified": "Nothing to apply again among what could be checked. Tweaks that need administrator to be checked: {0}; run it again as administrator.",
   "reapply.leftOut": "Not applied again, {0}: {1}",
   "menu.title": "windows-tuneup {0} - Windows {1} {2} (build {3})",
   "menu.admin.yes": "Running as administrator.",
@@ -168,10 +168,10 @@
   "menu.choose": "Choose an option:",
   "menu.invalid": "That is not one of the options. Try again.",
   "menu.back": "Press Enter to go back to the menu.",
-  "menu.status.reapply": "Windows reverted {0} tweaks. Type r and Enter to apply them again, or Enter alone to go back:",
+  "menu.status.reapply": "Tweaks reverted by Windows: {0}. Type r and Enter to apply them again, or Enter alone to go back:",
   "menu.status.reapplyKey": "r",
   "menu.undo.header": "Runs, newest first:",
-  "menu.undo.tweaks": "{0} tweaks",
+  "menu.undo.tweaks": "tweaks: {0}",
   "menu.undo.state.undone": "[undone]",
   "menu.undo.state.partly": "[partly undone]",
   "menu.undo.state.pending": "[pending]",
@@ -194,19 +194,30 @@
   "menu.profile.admin": "(administrator)",
   "menu.profile.always": "(always)",
   "menu.select.prompt": "Type numbers to select or clear them (for example 2,4), Enter to go on, 0 to go back:",
-  "menu.high.offer": "There are {0} high-risk tweaks that no profile applies. Look at them? (y/n)",
+  "menu.high.offer": "High-risk tweaks that no profile applies: {0}. Look at them? (y/n)",
   "menu.high.mark": "[high risk]",
   "menu.high.warning": "High-risk tweaks lower the protection of Windows or remove data that undo cannot bring back (docs/en/profiles.md explains each one).",
   "menu.high.word": "yes",
-  "menu.high.confirm": "To add them, type {0} in full:",
-  "menu.high.notAdded": "They were not added.",
-  "menu.ask.header": "{0} tweaks ask before being applied:",
-  "menu.ask.prompt": "Apply it? y = yes, n = no, a = yes to all the rest, x = no to all the rest:",
+  "menu.high.confirm": "To add what you chose, type {0} in full:",
+  "menu.high.notAdded": "Nothing was added.",
+  "menu.ask.header": "Tweaks that ask before being applied: {0}",
+  "menu.ask.prompt": "Apply it? y = yes, n = no, a = yes to this one and all the rest, x = no to this one and all the rest:",
   "menu.ask.yes": "y",
   "menu.ask.no": "n",
   "menu.ask.all": "a",
   "menu.ask.none": "x",
   "menu.optimize.needsAdmin": "This plan has system changes: open PowerShell as administrator and run tuneup.ps1 again, or choose only profiles without (administrator).",
   "menu.reapply.highConfirm": "Windows reverted it. To apply it again, type {0} in full:",
-  "menu.reapply.highSkipped": "Not applied again: {0}."
+  "menu.reapply.highSkipped": "Not applied again: {0}.",
+  "run.saved.menu": "Run {0} saved in {1}. To undo it, choose option 3 in the menu.",
+  "interrupted.summary.menu": "Stopped with Ctrl+C. Tweaks not applied: {0}. What was applied can be undone with option 3 in the menu.",
+  "interrupted.saved.menu": "Stopped with Ctrl+C. The result of run {0} was saved; to undo it, choose option 3 in the menu.",
+  "aborted.saved.menu": "The run stopped because of an error. The result of run {0} was saved; to undo it, choose option 3 in the menu.",
+  "menu.high.pattern": "^yes$",
+  "menu.select.locked": "Option {0} always stays selected: it cannot be changed.",
+  "menu.undo.more": "Only the {0} newest runs are listed; to undo an older one use -Undo <run> from the command line.",
+  "menu.undo.tweakAlreadyUndone": "The tweak \"{0}\" was already undone.",
+  "menu.health.needsAdmin": "The health check needs PowerShell as administrator: open it that way and run tuneup.ps1 again.",
+  "menu.measure.range": "Type a number between {0} and {1}.",
+  "menu.nonInteractive": "The menu needs to be able to ask questions, and PowerShell was started with -NonInteractive. Open it without that option, redirect the input, or use a command (for example -WhatIf or -Status)."
 }
diff --git a/i18n/es.json b/i18n/es.json
index 5c5172c..0f034ff 100644
--- a/i18n/es.json
+++ b/i18n/es.json
@@ -18,7 +18,7 @@
   "plan.skip": "  - {0}: {1}",
   "plan.needsAdmin": "Para aplicar los cambios de sistema, abre PowerShell como administrador.",
   "nothing": "No hay cambios pendientes.",
-  "confirm": "¿Aplicar {0} cambios? (s/n)",
+  "confirm": "Cambios por aplicar: {0}. ¿Aplicar? (s/n)",
   "confirm.pattern": "^(s|si|sí|y|yes)$",
   "aborted": "Cancelado. No se cambió nada.",
   "risk.low": "riesgo bajo",
@@ -109,7 +109,7 @@
   "err.measurementNotFound": "No existe la medición {0}.",
   "err.noMeasurements": "No hay mediciones guardadas para comparar.",
   "err.idleSecondsRange": "-IdleSeconds debe estar entre {0} y {1}.",
-  "measure.waiting": "Esperando {0} segundos en reposo antes de medir...",
+  "measure.waiting": "Esperando en reposo antes de medir ({0} s)...",
   "measure.header": "Medición {0}:",
   "measure.line": "  {0}: {1}",
   "measure.saved": "Guardada en {0}.",
@@ -131,7 +131,7 @@
   "undo.manual": "Para restaurarlo a mano, ejecuta esto en PowerShell como administrador (un ajuste del usuario no lo necesita):",
   "undo.manual.action": "Restáuralo a mano: el README (Tipos de ajuste) explica qué cambia la acción '{0}'.",
   "reason.interrupted": "no se aplicó: la corrida se detuvo con Ctrl+C",
-  "interrupted.summary": "Detenido con Ctrl+C: {0} ajustes no se aplicaron. Lo aplicado se puede deshacer con -Undo.",
+  "interrupted.summary": "Detenido con Ctrl+C. Ajustes sin aplicar: {0}. Lo aplicado se puede deshacer con -Undo.",
   "interrupted.saved": "Detenido con Ctrl+C. El resultado de la corrida {0} quedó guardado; para deshacerla: .\\tuneup.ps1 -Undo {0}",
   "transcript.header": "windows-tuneup {0} - corrida {1} - {2}",
   "transcript.request.profiles": "Pedido: perfiles {0}; incluidos {1}; excluidos {2}",
@@ -151,9 +151,9 @@
   "preflight.restoreEnableFailed": "No se pudo activar Restaurar sistema: {0}",
   "reapply.none": "Nada que volver a aplicar: Windows no revirtió ningún ajuste.",
   "interrupted.hint": "Ctrl+C se detiene después del ajuste en curso; Ctrl+Pausa interrumpe de inmediato",
-  "aborted.saved": "La corrida se detuvo por un error. El resultado de la corrida {0} quedó guardado; para deshacerla: .\tuneup.ps1 -Undo {0}",
+  "aborted.saved": "La corrida se detuvo por un error. El resultado de la corrida {0} quedó guardado; para deshacerla: .\\tuneup.ps1 -Undo {0}",
   "reason.aborted": "no se aplicó: la corrida se detuvo por un error",
-  "reapply.noneUnverified": "Nada que volver a aplicar entre lo que se pudo comprobar, pero {0} ajustes necesitan administrador para comprobarse: ejecútalo de nuevo como administrador.",
+  "reapply.noneUnverified": "Nada que volver a aplicar entre lo que se pudo comprobar. Ajustes que necesitan administrador para comprobarse: {0}; ejecútalo de nuevo como administrador.",
   "reapply.leftOut": "No se vuelve a aplicar {0}: {1}",
   "menu.title": "windows-tuneup {0} - Windows {1} {2} (compilación {3})",
   "menu.admin.yes": "Corre como administrador.",
@@ -168,10 +168,10 @@
   "menu.choose": "Elige una opción:",
   "menu.invalid": "Esa no es una de las opciones. Prueba otra vez.",
   "menu.back": "Presiona Enter para volver al menú.",
-  "menu.status.reapply": "Windows revirtió {0} ajustes. Escribe r y Enter para volver a aplicarlos, o solo Enter para volver:",
+  "menu.status.reapply": "Ajustes revertidos por Windows: {0}. Escribe r y Enter para volver a aplicarlos, o solo Enter para volver:",
   "menu.status.reapplyKey": "r",
   "menu.undo.header": "Corridas, de la más nueva a la más vieja:",
-  "menu.undo.tweaks": "{0} ajustes",
+  "menu.undo.tweaks": "ajustes: {0}",
   "menu.undo.state.undone": "[deshecha]",
   "menu.undo.state.partly": "[deshecha en parte]",
   "menu.undo.state.pending": "[pendiente]",
@@ -194,19 +194,30 @@
   "menu.profile.admin": "(administrador)",
   "menu.profile.always": "(siempre)",
   "menu.select.prompt": "Escribe números para marcar o desmarcar (por ejemplo 2,4), Enter para seguir, 0 para volver:",
-  "menu.high.offer": "Hay {0} ajustes de riesgo alto que ningún perfil aplica. ¿Quieres verlos? (s/n)",
+  "menu.high.offer": "Ajustes de riesgo alto que ningún perfil aplica: {0}. ¿Quieres verlos? (s/n)",
   "menu.high.mark": "[riesgo alto]",
   "menu.high.warning": "Los ajustes de riesgo alto bajan la protección de Windows o borran datos que deshacer no puede devolver (docs/es/profiles.md explica cada uno).",
-  "menu.high.word": "si",
-  "menu.high.confirm": "Para agregarlos, escribe {0} completo:",
-  "menu.high.notAdded": "No se agregaron.",
-  "menu.ask.header": "{0} ajustes preguntan antes de aplicarse:",
-  "menu.ask.prompt": "¿Aplicarlo? s = sí, n = no, t = sí a todos los que quedan, x = no a todos los que quedan:",
+  "menu.high.word": "sí",
+  "menu.high.confirm": "Para agregar lo que elegiste, escribe {0} completo:",
+  "menu.high.notAdded": "No se agregó nada.",
+  "menu.ask.header": "Ajustes que preguntan antes de aplicarse: {0}",
+  "menu.ask.prompt": "¿Aplicarlo? s = sí, n = no, t = sí a este y a todos los que quedan, x = no a este y a todos los que quedan:",
   "menu.ask.yes": "s",
   "menu.ask.no": "n",
   "menu.ask.all": "t",
   "menu.ask.none": "x",
   "menu.optimize.needsAdmin": "Este plan tiene cambios de sistema: abre PowerShell como administrador y vuelve a correr tuneup.ps1, o elige solo perfiles sin (administrador).",
   "menu.reapply.highConfirm": "Windows lo revirtió. Para volver a aplicarlo, escribe {0} completo:",
-  "menu.reapply.highSkipped": "No se vuelve a aplicar {0}."
+  "menu.reapply.highSkipped": "No se vuelve a aplicar {0}.",
+  "run.saved.menu": "Corrida {0} guardada en {1}. Para deshacerla, elige la opción 3 del menú.",
+  "interrupted.summary.menu": "Detenido con Ctrl+C. Ajustes sin aplicar: {0}. Lo aplicado se puede deshacer con la opción 3 del menú.",
+  "interrupted.saved.menu": "Detenido con Ctrl+C. El resultado de la corrida {0} quedó guardado; para deshacerla, elige la opción 3 del menú.",
+  "aborted.saved.menu": "La corrida se detuvo por un error. El resultado de la corrida {0} quedó guardado; para deshacerla, elige la opción 3 del menú.",
+  "menu.high.pattern": "^(sí|si)$",
+  "menu.select.locked": "La opción {0} queda siempre marcada: no se puede cambiar.",
+  "menu.undo.more": "Solo se listan las {0} corridas más nuevas; para deshacer una anterior usa -Undo <corrida> desde la línea de comandos.",
+  "menu.undo.tweakAlreadyUndone": "El ajuste \"{0}\" ya estaba deshecho.",
+  "menu.health.needsAdmin": "La salud de Windows necesita PowerShell como administrador: ábrelo así y vuelve a correr tuneup.ps1.",
+  "menu.measure.range": "Escribe un número entre {0} y {1}.",
+  "menu.nonInteractive": "El menú necesita poder preguntar, y PowerShell se abrió con -NonInteractive. Ábrelo sin esa opción, redirige la entrada, o usa un comando (por ejemplo -WhatIf o -Status)."
 }
```

- [ ] **Step 5: Verificar**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Menu.Tests.ps1`
Expected: PASS (`Tests Passed: 43, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Tests Passed: 1212, Failed: 0, Skipped: 1`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 6: Commit**

```bash
git add engine/Prompts.ps1 engine/Menu.ps1 engine/Commands.ps1 engine/Output.ps1 i18n/es.json i18n/en.json tests/Menu.Tests.ps1 tests/Commands.Tests.ps1 tests/Output.Tests.ps1 tests/Preflight.Tests.ps1 tests/I18n.Tests.ps1
git commit -m "fix: menú con plurales, sí con tilde y entradas inválidas"
```

---

### Task 11: Instalador y paquete de la release

**Files:**
- Create: `install.ps1`, `build/package.ps1`, `build/release-notes.md`, `tests/Package.Tests.ps1`
- Modify: `build/lint.ps1` (también `install.ps1`)
- Test: `tests/Package.Tests.ps1`

Diseño (sección 12, punto 9):

- `build/package.ps1 -OutputPath <carpeta> [-Version <x.y.z>]` arma `windows-tuneup-<versión>.zip` con una carpeta `windows-tuneup-<versión>/` y solo lo que corre y lo que se lee (`tuneup.ps1`, `engine/**`, `i18n`, `catalog/*.json` sin `notes`, `profiles`, `actions`, `docs/es`, `docs/en`, `README.md`, `LICENSE`). En un checkout de git toma solo archivos seguidos (`git ls-files`): **los archivos nuevos tienen que estar commiteados** antes de empaquetar; fuera de un checkout (una copia extraída) toma los archivos de las carpetas previstas. git se llama con `$ErrorActionPreference = 'Continue'`: fuera de un checkout escribe en la salida de error y, con `Stop`, Windows PowerShell 5.1 lanzaba la excepción aunque se redirigiera con `2>$null` (lo encontró la copia rearmada desde el plan, que no es un repositorio; una prueba arma el paquete desde una copia así). Las entradas van ordenadas y con la fecha del último commit, así el mismo commit da el mismo zip en la misma máquina (comprobado: dos armados seguidos, mismo SHA256). Escribe además `install.ps1` con la versión y el SHA256 del zip reemplazando `'__TUNEUP_VERSION__'` y `'__TUNEUP_ZIP_SHA256__'`, `SHA256SUMS` (formato de `sha256sum`: hash, dos espacios, nombre; LF) y `release-notes.md` desde la plantilla. El zip se arma con `System.IO.Compression` y barras `/`, no con `Compress-Archive` (en Windows PowerShell 5.1 escribe `\`).
- `install.ps1`: sin una versión y un hash válidos se niega; solo descarga por HTTPS (`-Source` que no empiece con `https://` y no sea una carpeta se rechaza); descarga `<Source>/v<versión>/windows-tuneup-<versión>.zip` (o lo copia si `-Source` es una carpeta: pruebas y sin conexión), compara el SHA256 y no extrae nada si difiere (nada de lo descargado se lee más que como bytes antes de esa comprobación); rechaza entradas fuera de su carpeta **y entradas que no cuelguen de `windows-tuneup-<versión>/`**; exige `tuneup.ps1` y `engine\Tuneup.psm1`; reemplaza solo una copia anterior de windows-tuneup y **se niega si esa carpeta es un vínculo (junction o enlace simbólico)**; quita la marca de descarga (`Unblock-File`). Elevado instala en `%ProgramFiles%\windows-tuneup` (se resuelve con `[Environment]::GetFolderPath`) y **le da a la carpeta una lista de acceso solo de administradores** (dueño Administradores, sin herencia, Administradores y SYSTEM control total, Usuarios lectura y ejecución; se fija con la carpeta aún vacía para que lo copiado la herede, con `[System.IO.Directory]::SetAccessControl`, que no pide el privilegio de auditoría que sí pide `Set-Acl`); **antes de reemplazar una copia elevada anterior comprueba que sea de los administradores y que ningún otro pueda escribirla (`Get-InstallFolderProblem` / `Get-InstallFolderWriter`), y si no, se niega sin instalar nada**. Sin elevar, instala en `windows-tuneup-<versión>` de la carpeta actual y avisa que esa copia no debe correrse como administrador. Todo corre dentro de `& { }` y los errores se lanzan (nunca `exit`): por `irm | iex` los valores por defecto del `param()` se aplican, `$ErrorActionPreference` y las variables del instalador no quedan en la sesión y un error no cierra la consola (salvedad: si la sesión ya tiene una variable con el nombre de un parámetro, p. ej. `$Version`, el `iex` la pisa con el valor por defecto). Mensajes en inglés (corre antes de que existan los textos de la herramienta).
- Comprobado en la copia: instalar desde la carpeta del paquete, el `install.ps1` armado por `iex` (con `-Source` cambiado a la carpeta local en el texto), un hash equivocado (no crea la carpeta de destino), el `install.ps1` del repositorio sin versión, un zip con `../escaped.txt` y la copia instalada corriendo `-WhatIf -Json` con `toolVersion` 0.1.0.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/Package.Tests.ps1`:

```powershell
BeforeDiscovery {
    $script:Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:Version = Get-TuneupVersion
    $script:Top = "windows-tuneup-$Version"

    function Invoke-Package([string]$Output) {
        & $PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '$Repo\build\package.ps1' -OutputPath '$Output' | ConvertTo-Json" | Out-String | ConvertFrom-Json
    }
    # Runs an installer the way people do (powershell -File) and gives its exit code and output.
    function Invoke-Installer([string]$Installer, [string[]]$Arguments, [string]$WorkingFolder = $TestDrive) {
        # Its errors come on standard error; with Stop, Windows PowerShell 5.1 would throw on the first line.
        $ErrorActionPreference = 'Continue'
        Push-Location -LiteralPath $WorkingFolder
        try {
            $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Installer @Arguments 2>&1
        } finally {
            Pop-Location
        }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    }
    function Get-ZipEntry([string]$Path) {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
    }

    # The folder checks of the installer live inside it (it is one file); they are loaded from its syntax tree.
    $installerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'install.ps1'), [ref]$null, [ref]$null)
    foreach ($functionName in 'Get-InstallFolderProblem', 'Get-InstallFolderWriter', 'New-InstallFolderSecurity') {
        $definition = $installerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    $script:Dist = Join-Path $TestDrive 'dist'
    $script:Built = Invoke-Package $Dist
}

Describe 'build/package.ps1' {
    It 'packs only what runs and what people read, under one folder' {
        $entries = @(Get-ZipEntry $Built.Zip)
        @($entries | Where-Object { -not $_.StartsWith("$Top/") }).Count | Should -Be 0
        $names = @($entries | ForEach-Object { $_.Substring($Top.Length + 1) })
        foreach ($expected in 'tuneup.ps1', 'README.md', 'LICENSE', 'engine/Tuneup.psm1', 'engine/Commands.ps1', 'engine/Menu.ps1',
            'engine/handlers/Registry.ps1', 'i18n/es.json', 'i18n/en.json', 'catalog/apps.json', 'profiles/lite.json',
            'actions/onedrive.ps1', 'docs/es/profiles.md', 'docs/en/catalog.md') {
            $names | Should -Contain $expected
        }
        foreach ($folder in 'tests/', 'build/', '.github/', 'docs/superpowers/', 'catalog/notes/') {
            @($names | Where-Object { $_.StartsWith($folder) }).Count | Should -Be 0 -Because $folder
        }
        $names | Should -Not -Contain 'install.ps1'
        $names | Should -Not -Contain '.gitignore'
        $engine = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine') -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }).Count
        @($names | Where-Object { $_ -match '^engine/[^/]+$' }).Count | Should -Be $engine
    }

    It 'builds the same files from a copy that is not a git checkout' {
        $copy = Join-Path $TestDrive 'not-git'
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($item in 'tuneup.ps1', 'install.ps1', 'README.md', 'LICENSE', 'engine', 'i18n', 'catalog', 'profiles', 'actions', 'docs', 'build') {
            Copy-Item -LiteralPath (Join-Path $Repo $item) -Destination (Join-Path $copy $item) -Recurse
        }
        $output = Join-Path $TestDrive 'dist-not-git'
        $built = & $PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '$copy\build\package.ps1' -OutputPath '$output' | ConvertTo-Json" | Out-String | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        @(Get-ZipEntry $built.Zip) -join ',' | Should -Be (@(Get-ZipEntry $Built.Zip) -join ',')
    }

    It 'gives the same zip for the same files' {
        $again = Invoke-Package (Join-Path $TestDrive 'dist-again')
        $again.ZipSha256 | Should -Be $Built.ZipSha256
    }

    It 'writes the version and the SHA256 of the zip into install.ps1, and both hashes into SHA256SUMS' {
        $installer = [System.IO.File]::ReadAllText($Built.Installer)
        $installer | Should -Match ([regex]::Escape("[string]`$Version = '$Version'"))
        $installer | Should -Match ([regex]::Escape("[string]`$Sha256 = '$($Built.ZipSha256)'"))
        $installer | Should -Not -Match '__TUNEUP_'
        $lines = @([System.IO.File]::ReadAllText($Built.Sums).TrimEnd("`n").Split("`n"))
        $lines | Should -Be @("$($Built.ZipSha256)  $Top.zip", "$($Built.InstallerSha256)  install.ps1")
        (Get-FileHash -LiteralPath $Built.Zip -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $Built.ZipSha256
        $notes = [System.IO.File]::ReadAllText($Built.Notes)
        $notes | Should -Not -Match '\{\{'
        $notes | Should -Match ([regex]::Escape("releases/download/v$Version/install.ps1 | iex"))
    }
}

Describe 'install.ps1' {
    It 'checks the SHA256 and installs the release in -Destination' {
        $destination = Join-Path $TestDrive 'installed'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match "SHA256 checked: $($Built.ZipSha256.ToUpperInvariant())"
        Test-Path -LiteralPath (Join-Path $destination 'engine\Tuneup.psm1') | Should -BeTrue
        $plan = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destination 'tuneup.ps1') -StateRoot (Join-Path $TestDrive 'state') -WhatIf -Json
        $LASTEXITCODE | Should -Be 0
        ($plan | Out-String | ConvertFrom-Json).toolVersion | Should -Be $Version
    }

    It 'replaces an earlier copy and leaves any other folder alone' {
        $destination = Join-Path $TestDrive 'twice'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText((Join-Path $destination 'stale.txt'), 'old')
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $destination 'stale.txt') | Should -BeFalse
        $other = Join-Path $TestDrive 'other'
        New-Item -ItemType Directory -Path $other | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $other 'keep.txt'), 'mine')
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $other)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'is not a copy of windows-tuneup'
        Test-Path -LiteralPath (Join-Path $other 'keep.txt') | Should -BeTrue
    }

    It 'installs nothing when the SHA256 does not match' {
        $destination = Join-Path $TestDrive 'mismatch'
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', $Version, '-Sha256', ('0' * 64), '-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'it is not that release. Nothing was installed.'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'asks for a version and a SHA256 when it is the copy of the repository' {
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Source', $Dist, '-Destination', (Join-Path $TestDrive 'none'))
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'has no release in it'
    }

    It 'only downloads over HTTPS' {
        $destination = Join-Path $TestDrive 'plain-http'
        $run = Invoke-Installer $Built.Installer @('-Source', 'http://example.invalid/releases', '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'only downloads over HTTPS'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'refuses a zip with an entry outside its folder' {
        $source = Join-Path $TestDrive 'evil'
        New-Item -ItemType Directory -Path $source | Out-Null
        $zip = Join-Path $source 'windows-tuneup-9.9.9.zip'
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in 'windows-tuneup-9.9.9/tuneup.ps1', 'windows-tuneup-9.9.9/engine/Tuneup.psm1', '../escaped.txt') {
                $writer = New-Object System.IO.StreamWriter -ArgumentList $archive.CreateEntry($name).Open()
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally {
            $archive.Dispose()
        }
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', '9.9.9', '-Sha256', $hash, '-Source', $source, '-Destination', (Join-Path $TestDrive 'evil-out'))
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'entry outside its folder: \.\./escaped\.txt'
        Test-Path -LiteralPath (Join-Path $TestDrive 'evil-out') | Should -BeFalse
    }

    It 'refuses a zip whose entries are not under the folder of its version' {
        $source = Join-Path $TestDrive 'stray'
        New-Item -ItemType Directory -Path $source | Out-Null
        $zip = Join-Path $source 'windows-tuneup-9.9.9.zip'
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in 'windows-tuneup-9.9.9/tuneup.ps1', 'windows-tuneup-9.9.9/engine/Tuneup.psm1', 'other-folder/payload.ps1') {
                $writer = New-Object System.IO.StreamWriter -ArgumentList $archive.CreateEntry($name).Open()
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally {
            $archive.Dispose()
        }
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', '9.9.9', '-Sha256', $hash, '-Source', $source, '-Destination', (Join-Path $TestDrive 'stray-out'))
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'entry outside its folder: other-folder/payload\.ps1'
        Test-Path -LiteralPath (Join-Path $TestDrive 'stray-out') | Should -BeFalse
    }

    It 'extracts to the current folder when not elevated' -Skip:$Elevated {
        $folder = Join-Path $TestDrive 'here'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist) -WorkingFolder $folder
        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match 'never as administrator'
        Test-Path -LiteralPath (Join-Path $folder "$Top\tuneup.ps1") | Should -BeTrue
    }

    It 'installs with a folder that only administrators can change when elevated' -Skip:(-not $Elevated) {
        $destination = Join-Path $TestDrive 'admin-only'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Get-InstallFolderProblem $destination | Should -BeNullOrEmpty
        Get-InstallFolderProblem (Join-Path $destination 'engine') | Should -BeNullOrEmpty
    }

    It 'refuses to replace an elevated copy that users can change' -Skip:(-not $Elevated) {
        $destination = Join-Path $TestDrive 'weakened'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        $acl = [System.IO.Directory]::GetAccessControl($destination)
        $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
        [System.IO.Directory]::SetAccessControl($destination, $acl)
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'cannot be trusted'
    }
}

Describe 'the folder checks of install.ps1' {
    It 'trusts a folder that belongs to the system and that users cannot change' {
        $system32 = Join-Path $env:SystemRoot 'System32'
        Get-InstallFolderProblem $system32 | Should -BeNullOrEmpty
    }

    It 'finds who besides the administrators and the system can change a folder' {
        $folder = Join-Path $TestDrive 'users-write'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $acl = [System.IO.Directory]::GetAccessControl($folder)
        $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
        [System.IO.Directory]::SetAccessControl($folder, $acl)
        Get-InstallFolderWriter $folder | Should -Not -BeNullOrEmpty
        Get-InstallFolderProblem $folder | Should -Not -BeNullOrEmpty
        Get-InstallFolderWriter (Join-Path $env:SystemRoot 'System32') | Should -BeNullOrEmpty
    }

    It 'does not trust a folder owned by a user' -Skip:$Elevated {
        $folder = Join-Path $TestDrive 'owned-by-user'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Get-InstallFolderProblem $folder | Should -Match 'not by Administrators'
    }

    It 'does not trust a link, whatever it points to' {
        $target = Join-Path $TestDrive 'link-target'
        $link = Join-Path $TestDrive 'link'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try {
            Get-InstallFolderProblem $link | Should -Match 'is a link'
        } finally {
            [System.IO.Directory]::Delete($link)
        }
    }

    It 'builds a folder security that is owned by Administrators and gives users only read and run' {
        $security = New-InstallFolderSecurity
        $sddl = $security.GetSecurityDescriptorSddlForm('All')
        $sddl | Should -Match '^O:BA'
        $sddl | Should -Match 'D:P'
        $rules = @($security.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
        $rules.Count | Should -Be 3
        $write = [int][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
        $users = @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' })
        $users.Count | Should -Be 1
        ([int]$users[0].FileSystemRights -band $write) | Should -Be 0
        @($rules | Where-Object { $_.IdentityReference.Value -in 'S-1-5-32-544', 'S-1-5-18' }).Count | Should -Be 2
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Package.Tests.ps1`
Expected: FAIL: `build\package.ps1` no existe.

- [ ] **Step 3: El instalador**

Crear `install.ps1`:

```powershell
<#
.SYNOPSIS
    Downloads a release of windows-tuneup, checks its SHA256 and installs it.
.DESCRIPTION
    The install.ps1 attached to a release carries the version and the SHA256 of its zip, so
        irm https://github.com/edgarlugo/windows-tuneup/releases/download/v<version>/install.ps1 | iex
    installs exactly that release: a zip whose SHA256 differs is never extracted, and nothing that
    was downloaded runs before that check.

    As administrator it installs in %ProgramFiles%\windows-tuneup and gives the folder an access list
    that only administrators can change (users can read and run it). It refuses to replace an existing
    folder that does not belong to the administrators or that users can change: whoever can change the
    files of that folder could run code as administrator the next time it is used. Without elevation
    it extracts to -Destination (by default windows-tuneup-<version> in the current folder); that copy
    is for the tweaks of your user only and must not be run as administrator, because other programs of
    your account can change it.

    The copy of install.ps1 in the repository has no version: give -Version and -Sha256 (the line of
    the zip in SHA256SUMS of that release).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Destination D:\Tools\windows-tuneup
#>
param(
    [string]$Version = '__TUNEUP_VERSION__',
    [string]$Sha256 = '__TUNEUP_ZIP_SHA256__',
    [string]$Destination,
    # A release URL base (HTTPS only), or a folder that holds windows-tuneup-<version>.zip (offline and tests).
    [string]$Source = 'https://github.com/edgarlugo/windows-tuneup/releases/download'
)

# Everything runs in its own scope: through "irm | iex" nothing is left behind in the caller's session,
# and an error is thrown, never "exit", which would close that session.
& {
    param([string]$Version, [string]$Sha256, [string]$Destination, [string]$Source)
    $ErrorActionPreference = 'Stop'

    # Gives the reason a folder cannot be trusted to hold code that runs as administrator, or nothing.
    function Get-InstallFolderProblem {
        param([Parameter(Mandatory)][string]$Path, [switch]$LinkOnly)
        # Administrators, SYSTEM and TrustedInstaller are the owners and writers a folder of programs may have.
        $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return "$Path is a link" }
        if ($LinkOnly) { return }
        $acl = Get-Acl -LiteralPath $Path
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($trustedSid -notcontains $owner) { return "it is owned by $($acl.Owner), not by Administrators" }
        $writer = Get-InstallFolderWriter -Path $Path
        if ($writer) { return "$writer can change it" }
    }

    # Gives the first principal other than the administrators and the system that can change a folder, or nothing.
    function Get-InstallFolderWriter {
        param([Parameter(Mandatory)][string]$Path)
        $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
        $write = [int64][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
        foreach ($rule in (Get-Acl -LiteralPath $Path).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
            if (([int64]$rule.FileSystemRights -band $write) -eq 0) { continue }
            # CREATOR OWNER only matters for what its owner could do, and the owner is checked apart.
            if ($trustedSid -contains $rule.IdentityReference.Value -or $rule.IdentityReference.Value -eq 'S-1-3-0') { continue }
            $who = $rule.IdentityReference.Value
            try { $who = $rule.IdentityReference.Translate([System.Security.Principal.NTAccount]).Value } catch { Write-Verbose "No name for $who" }
            return $who
        }
    }

    # Owner Administrators; no inherited rules; administrators and SYSTEM full control; users read and run.
    function New-InstallFolderSecurity {
        $administrators = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $system = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $security = New-Object System.Security.AccessControl.DirectorySecurity
        $security.SetOwner($administrators)
        $security.SetAccessRuleProtection($true, $false)
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $none = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        foreach ($entry in @(@($system, 'FullControl'), @($administrators, 'FullControl'), @($users, 'ReadAndExecute'))) {
            $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $entry[0], ([System.Security.AccessControl.FileSystemRights]$entry[1]), $inherit, $none, $allow))
        }
        $security
    }

    if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw 'This install.ps1 has no release in it: use the one attached to a release, or give -Version and -Sha256 (the line of the zip in SHA256SUMS of that release).'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $admin = (New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $Destination) {
        if ($admin) { $Destination = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'windows-tuneup' }
        else { $Destination = Join-Path (Get-Location).ProviderPath "windows-tuneup-$Version" }
    }
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    $name = "windows-tuneup-$Version.zip"
    $fromFolder = Test-Path -LiteralPath $Source -PathType Container
    if (-not $fromFolder -and $Source -notmatch '^https://') { throw "This installer only downloads over HTTPS: -Source must start with https:// (or be a folder that holds $name)." }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-tuneup-install-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work $name
        if ($fromFolder) {
            Copy-Item -LiteralPath (Join-Path $Source $name) -Destination $zip
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $url = "$($Source.TrimEnd('/'))/v$Version/$name"
            Write-Host "Downloading $url ..."
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        }
        # Nothing of what was downloaded is read as anything but bytes until this check passes.
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($actual -ne $Sha256.ToUpperInvariant()) {
            throw "The SHA256 of $name is $actual, not $($Sha256.ToUpperInvariant()): it is not that release. Nothing was installed."
        }
        Write-Host "SHA256 checked: $actual"

        # Every entry must be under windows-tuneup-<version>/ and land inside the folder it is extracted to.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extract = Join-Path $work 'extract'
        $inside = [System.IO.Path]::GetFullPath($extract).TrimEnd('\') + '\'
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                $target = $null
                try { $target = [System.IO.Path]::GetFullPath((Join-Path $extract $entry.FullName)) } catch { $target = $null }
                if (-not $entry.FullName.StartsWith("windows-tuneup-$Version/", [StringComparison]::Ordinal) -or
                    -not $target -or -not $target.StartsWith($inside, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "The zip has an entry outside its folder: $($entry.FullName)"
                }
            }
        } finally {
            $archive.Dispose()
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
        $top = Join-Path $extract "windows-tuneup-$Version"
        if (-not (Test-Path -LiteralPath (Join-Path $top 'tuneup.ps1')) -or -not (Test-Path -LiteralPath (Join-Path $top 'engine\Tuneup.psm1'))) {
            throw "$name is not a release of windows-tuneup."
        }

        # An earlier copy is replaced; any other folder is left alone. As administrator the earlier copy
        # must also be one that only administrators could have changed.
        if (Test-Path -LiteralPath $Destination) {
            $link = Get-InstallFolderProblem -Path $Destination -LinkOnly
            if ($link) { throw "${link}: choose another -Destination. Nothing was installed." }
            $earlier = (Test-Path -LiteralPath (Join-Path $Destination 'tuneup.ps1')) -and (Test-Path -LiteralPath (Join-Path $Destination 'engine\Tuneup.psm1'))
            if (-not $earlier) { throw "$Destination exists and is not a copy of windows-tuneup: choose another -Destination." }
            if ($admin) {
                $problem = Get-InstallFolderProblem -Path $Destination
                if ($problem) { throw "$Destination cannot be trusted ($problem): remove it yourself or choose another -Destination. Nothing was installed." }
            }
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        if ($admin) {
            # The access list is set while the folder is still empty, so what is copied in inherits it.
            try {
                [System.IO.Directory]::SetAccessControl($Destination, (New-InstallFolderSecurity))
            } catch {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
                throw
            }
        }
        Copy-Item -Path (Join-Path $top '*') -Destination $Destination -Recurse
        # Files saved by a browser carry a mark that PowerShell checks; these were not, but a copy made
        # by hand from a downloaded zip would, so it is cleared the same way.
        Get-ChildItem -LiteralPath $Destination -Recurse -File | Unblock-File

        Write-Host "windows-tuneup $Version is in $Destination"
        Write-Host "Run: powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Destination 'tuneup.ps1')`""
        if (-not $admin) {
            Write-Warning 'This copy is in a folder that programs of your account can change: use it for the tweaks of your user only, never as administrator. For system tweaks, run this installer in PowerShell as administrator: it installs in Program Files.'
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
} -Version $Version -Sha256 $Sha256 -Destination $Destination -Source $Source
```

- [ ] **Step 4: El paquete y las notas**

Crear `build/package.ps1`:

```powershell
<#
.SYNOPSIS
    Builds the files of a release in -OutputPath.
.DESCRIPTION
    windows-tuneup-<version>.zip holds what runs (tuneup.ps1, engine, i18n, catalog, profiles,
    actions) and what people read (docs/es, docs/en, README.md, LICENSE) under one folder,
    windows-tuneup-<version>. In a git checkout only tracked files go in. Entries are sorted and carry
    the date of the last commit, so the same commit gives the same zip on the same machine.
    install.ps1 is the installer of the repository with the version and the SHA256 of the zip written
    in, SHA256SUMS lists both, and release-notes.md is build/release-notes.md with the version and the
    hashes filled in.
#>
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$root = Split-Path $PSScriptRoot -Parent
if (-not $Version) {
    Import-Module (Join-Path $root 'engine\Tuneup.psm1') -Force
    $Version = Get-TuneupVersion
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid version '$Version': expected major.minor.patch" }

# What goes in, as paths relative to the repository with forward slashes.
$patterns = @(
    '^tuneup\.ps1$', '^README\.md$', '^LICENSE$',
    '^engine/[^/]+\.(ps1|psm1)$', '^engine/handlers/[^/]+\.ps1$',
    '^i18n/[^/]+\.json$', '^catalog/[^/]+\.json$', '^profiles/[^/]+\.json$', '^actions/[^/]+\.ps1$',
    '^docs/(es|en)/[^/]+\.md$'
)
# git answers on standard error outside a checkout; with Stop, Windows PowerShell 5.1 would throw on
# that line, so it runs with Continue and its exit code decides.
function Invoke-PackageGit {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $output = @(& git -C $root @Arguments 2>$null)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}
$inGit = $false
$tracked = @()
if (Get-Command git -ErrorAction SilentlyContinue) {
    $listed = Invoke-PackageGit -Arguments @('ls-files')
    $tracked = @($listed.Output)
    $inGit = ($listed.ExitCode -eq 0 -and $tracked.Count -gt 0)
}
if (-not $inGit) {
    $prefix = $root.TrimEnd('\') + '\'
    $tracked = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix.Length).Replace('\', '/') })
}
$files = @($tracked | Where-Object { $path = $_; @($patterns | Where-Object { $path -cmatch $_ }).Count -gt 0 } | Sort-Object -CaseSensitive)
foreach ($required in 'tuneup.ps1', 'engine/Tuneup.psm1', 'LICENSE', 'README.md') {
    if ($files -notcontains $required) { throw "$required is missing from the package" }
}

$timestamp = [datetime]'2026-01-01T00:00:00'
if ($inGit) {
    $last = Invoke-PackageGit -Arguments @('log', '-1', '--format=%cI')
    if ($last.ExitCode -eq 0 -and $last.Output.Count) { $timestamp = ([datetimeoffset]::Parse([string]$last.Output[0])).UtcDateTime }
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).ProviderPath
$top = "windows-tuneup-$Version"
$zipPath = Join-Path $OutputPath "$top.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$stream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
try {
    $archive = New-Object System.IO.Compression.ZipArchive -ArgumentList $stream, ([System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $entry = $archive.CreateEntry("$top/$file", [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $timestamp
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $root ($file.Replace('/', '\'))))
            $writer = $entry.Open()
            try { $writer.Write($bytes, 0, $bytes.Length) } finally { $writer.Dispose() }
        }
    } finally {
        $archive.Dispose()
    }
} finally {
    $stream.Dispose()
}
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

# The installer of this release knows its version and the SHA256 of its zip.
$installer = [System.IO.File]::ReadAllText((Join-Path $root 'install.ps1'))
foreach ($placeholder in "'__TUNEUP_VERSION__'", "'__TUNEUP_ZIP_SHA256__'") {
    if (-not $installer.Contains($placeholder)) { throw "install.ps1 has no $placeholder to fill in" }
}
$installer = $installer.Replace("'__TUNEUP_VERSION__'", "'$Version'").Replace("'__TUNEUP_ZIP_SHA256__'", "'$zipHash'")
$installerPath = Join-Path $OutputPath 'install.ps1'
[System.IO.File]::WriteAllText($installerPath, $installer, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()

# The format of sha256sum: the hash, two spaces and the name; one line each, LF.
$sumsPath = Join-Path $OutputPath 'SHA256SUMS'
[System.IO.File]::WriteAllText($sumsPath, "$zipHash  $top.zip`n$installerHash  install.ps1`n", (New-Object System.Text.UTF8Encoding -ArgumentList $false))

$notes = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'release-notes.md'), [System.Text.Encoding]::UTF8)
$notes = $notes.Replace('{{VERSION}}', $Version).Replace('{{ZIP_SHA256}}', $zipHash).Replace('{{INSTALLER_SHA256}}', $installerHash)
$notesPath = Join-Path $OutputPath 'release-notes.md'
[System.IO.File]::WriteAllText($notesPath, $notes, (New-Object System.Text.UTF8Encoding -ArgumentList $false))

[pscustomobject]@{
    Version         = $Version
    Zip             = $zipPath
    ZipSha256       = $zipHash
    Installer       = $installerPath
    InstallerSha256 = $installerHash
    Sums            = $sumsPath
    Notes           = $notesPath
    Files           = $files.Count
}
```

Crear `build/release-notes.md`:

````markdown
# windows-tuneup {{VERSION}}

## Instalar / Install

Abre PowerShell **como administrador** e instala esta versión en `%ProgramFiles%\windows-tuneup` (solo los administradores pueden cambiar esa carpeta):
Open PowerShell **as administrator** and install this version in `%ProgramFiles%\windows-tuneup` (only administrators can change that folder):

```powershell
irm https://github.com/edgarlugo/windows-tuneup/releases/download/v{{VERSION}}/install.ps1 | iex
```

`install.ps1` trae dentro la versión y el SHA256 del zip, y no extrae un zip que no coincida. `irm | iex` ejecuta lo que descarga sin mostrarlo: si prefieres revisarlo, descarga `install.ps1`, compara su SHA256 con el de abajo, léelo y córrelo con `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`.
`install.ps1` carries the version and the SHA256 of the zip, and never extracts a zip that does not match. `irm | iex` runs what it downloads without showing it: if you prefer to review it, download `install.ps1`, compare its SHA256 with the one below, read it and run it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`.

## SHA256

| Archivo / File | SHA256 |
|---|---|
| `windows-tuneup-{{VERSION}}.zip` | `{{ZIP_SHA256}}` |
| `install.ps1` | `{{INSTALLER_SHA256}}` |

```powershell
(Get-FileHash .\windows-tuneup-{{VERSION}}.zip -Algorithm SHA256).Hash
```
````

En `build/lint.ps1`, reemplazar:

```powershell
    (Join-Path $root 'tuneup.ps1'),
    (Join-Path $root 'engine'),
```

por:

```powershell
    (Join-Path $root 'tuneup.ps1'),
    (Join-Path $root 'install.ps1'),
    (Join-Path $root 'engine'),
```

- [ ] **Step 5: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Package.Tests.ps1`
Expected: PASS (`Tests Passed: 17, Failed: 0, Skipped: 2` sin elevar: se saltan las dos que solo corren elevadas, la que comprueba la lista de acceso de lo instalado y la que se niega a reemplazar una copia que los usuarios pueden cambiar; elevado, 17 pasan y se saltan las dos que solo corren sin elevar. Ninguna instala en `Program Files`: todas usan `-Destination` en `TestDrive`).

- [ ] **Step 6: Mirar el paquete**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/package.ps1 -OutputPath $env:TEMP\tuneup-dist` y luego `Get-Content $env:TEMP\tuneup-dist\SHA256SUMS`
Expected: el objeto con `Version 0.1.0`, `Files` 70 (72 cuando la Task 15 agregue las dos `vm-checklist.md`) y dos líneas en `SHA256SUMS` (`windows-tuneup-0.1.0.zip` e `install.ps1`). Borrar la carpeta después.

- [ ] **Step 7: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 8: Commit**

```bash
git add install.ps1 build/package.ps1 build/release-notes.md build/lint.ps1 tests/Package.Tests.ps1
git commit -m "feat: instalador que verifica el SHA256 y paquete de la release"
```

---

### Task 12: Workflow de release

**Files:**
- Create: `.github/workflows/release.yml`

Una etiqueta `v*` corre en `windows-latest`: comprueba que la etiqueta sea `v` + `Get-TuneupVersion` (si no, falla antes de todo), lint, pruebas, `build/package.ps1 -OutputPath dist` y `gh release create … --draft --verify-tag` con el zip, `install.ps1`, `SHA256SUMS` y `release-notes.md` como notas. Queda un **borrador**: se publica a mano después de adjuntar los reportes (Task 17). Necesita `permissions: contents: write`. No se puede probar sin empujar una etiqueta: eso lo hace la Task 17 con el permiso del usuario.

- [ ] **Step 1: El workflow**

Crear `.github/workflows/release.yml`:

```yaml
name: release
# A tag v<version> builds the release files, checks them like CI and leaves a draft release with the
# zip, install.ps1, SHA256SUMS and the notes. Publishing the draft is done by hand, after attaching the
# end-to-end and measurement reports (docs/es/vm-checklist.md).
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  release:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Pester and PSScriptAnalyzer
        shell: powershell
        run: |
          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
          Install-Module Pester -MinimumVersion 5.6.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
          Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
      - name: Tag and version agree
        shell: powershell
        run: |
          Import-Module .\engine\Tuneup.psm1
          $expected = "v$(Get-TuneupVersion)"
          if ($env:GITHUB_REF_NAME -cne $expected) { throw "Tag $env:GITHUB_REF_NAME does not match the version of the engine ($expected)" }
      - name: Lint
        shell: powershell
        run: .\build\lint.ps1
      - name: Test
        shell: powershell
        run: .\build\test.ps1
      - name: Package
        shell: powershell
        run: .\build\package.ps1 -OutputPath dist
      - name: Draft release
        shell: powershell
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          $zip = "dist\windows-tuneup-$($env:GITHUB_REF_NAME.Substring(1)).zip"
          gh release create $env:GITHUB_REF_NAME $zip dist\install.ps1 dist\SHA256SUMS --draft --verify-tag --title "windows-tuneup $env:GITHUB_REF_NAME" --notes-file dist\release-notes.md
          if ($LASTEXITCODE) { throw "gh release create failed with exit code $LASTEXITCODE" }
```

- [ ] **Step 2: Revisar lo que se puede revisar sin publicar**

Run: `powershell -NoProfile -Command "Import-Module .\engine\Tuneup.psm1; 'v' + (Get-TuneupVersion)"`
Expected: `v0.1.0` (la etiqueta que espera el workflow).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/package.ps1 -OutputPath dist` y `Get-ChildItem dist -Name`
Expected: `install.ps1`, `release-notes.md`, `SHA256SUMS`, `windows-tuneup-0.1.0.zip` (lo que sube el último paso). Borrar `dist` (no se commitea).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: borrador de release desde una etiqueta v*"
```

---

### Task 13: Pruebas sin elevar en CI

**Files:**
- Create: `build/test-standard-user.ps1`
- Modify: `.github/workflows/ci.yml` (reemplazo completo)

Los runners de GitHub son administradores, así que las pruebas `-Skip:$Elevated` (8 con este plan: 7 de `tests/Cli.Tests.ps1`, entre ellas las que comprueban que sin elevar se niega aplicar cambios de sistema, y 1 de `tests/Package.Tests.ps1`) nunca corrían en CI. `build/test-standard-user.ps1` las corre con un token de usuario estándar: desde un proceso elevado lanza `build/test.ps1` con `runas /trustlevel:0x20000` (Basic User: la misma cuenta, con el grupo Administradores solo para denegar). `runas` abre otra ventana y vuelve enseguida, así que el script hijo escribe en `TestResults\standard-user` si estaba elevado, la salida y el código, y el script espera esos archivos; falla si el proceso no arranca en 2 minutos o si sigue elevado. Sin elevar corre `build/test.ps1` directo. `-Restricted` fuerza `runas` también sin elevar (para probar el script).

Comprobado en la copia, sin elevar y con `-Restricted`: `runas` arrancó la suite de `tests/Arguments.Tests.ps1`, el hijo escribió `False` (no elevado), la salida (`Tests Passed: 29`) y el código `0`. **Sin comprobar:** que `runas /trustlevel` funcione en un runner elevado de GitHub (sesión de servicio). Si el trabajo `test-standard-user` falla en el primer PR por eso, quitar el trabajo de `ci.yml`, dejar el script para uso local y anotarlo en el README (las pruebas sin elevar ya corren con `build/test.ps1` desde un PowerShell sin elevar).

- [ ] **Step 1: El script**

Crear `build/test-standard-user.ps1`:

```powershell
<#
.SYNOPSIS
    Runs the test suite as a standard user.
.DESCRIPTION
    GitHub runners are elevated, so the tests marked -Skip:$Elevated never run there. From an elevated
    process this script starts the suite with runas /trustlevel:0x20000: the same account with a Basic
    User token, where the Administrators group only denies, as for a standard user. runas starts the
    process in its own window and returns at once, so the run writes its output, whether it was
    elevated and its exit code to files under TestResults\standard-user, which this script waits for.
    Without elevation it runs build\test.ps1 directly (that already is a standard user).
.PARAMETER Path
    A test file or folder, as for build\test.ps1.
.PARAMETER Restricted
    Uses runas also when not elevated (to check this script itself).
#>
param([string]$Path, [switch]$Restricted, [int]$TimeoutMinutes = 45)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$test = Join-Path $PSScriptRoot 'test.ps1'
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated -and -not $Restricted) {
    & $test -Path $Path
    exit $LASTEXITCODE
}

$work = Join-Path $root 'TestResults\standard-user'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$log = Join-Path $work 'output.log'
$role = Join-Path $work 'elevated.txt'
$done = Join-Path $work 'exit-code.txt'
foreach ($file in $log, $role, $done) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
$pathArgument = $(if ($Path) { " -Path '$((Resolve-Path -LiteralPath $Path).ProviderPath)'" } else { '' })
$child = Join-Path $work 'run.ps1'
[System.IO.File]::WriteAllText($child, @"
`$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
[System.IO.File]::WriteAllText('$role', [string]`$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
& '$test'$pathArgument *> '$log'
[System.IO.File]::WriteAllText('$done', [string]`$LASTEXITCODE)
"@)

& runas.exe /trustlevel:0x20000 "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$child`""
if ($LASTEXITCODE) { throw "runas could not start the run as a standard user (exit code $LASTEXITCODE)" }

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (-not (Test-Path -LiteralPath $done)) {
    if (-not (Test-Path -LiteralPath $role) -and (Get-Date) -gt $deadline.AddMinutes(-$TimeoutMinutes + 2)) {
        throw 'The run as a standard user did not start within 2 minutes (runas may not work on this machine).'
    }
    if ((Get-Date) -gt $deadline) { throw "The run as a standard user did not finish within $TimeoutMinutes minutes." }
    Start-Sleep -Seconds 5
}
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
if ([System.IO.File]::ReadAllText($role).Trim() -ne 'False') { throw 'The run was still elevated: the Basic User token did not take effect.' }
exit [int][System.IO.File]::ReadAllText($done).Trim()
```

- [ ] **Step 2: El trabajo de CI**

Reemplazar `.github/workflows/ci.yml` completo por:

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Pester and PSScriptAnalyzer
        shell: powershell
        run: |
          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
          Install-Module Pester -MinimumVersion 5.6.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
          Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
      - name: Lint
        shell: powershell
        run: .\build\lint.ps1
      - name: Test
        shell: powershell
        run: .\build\test.ps1
  # The runner is elevated: this job runs the suite again with a standard-user token, so the tests
  # that only run without elevation (-Skip:$Elevated) run in CI too.
  test-standard-user:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Pester
        shell: powershell
        run: |
          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
          Install-Module Pester -MinimumVersion 5.6.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
      - name: Test as a standard user
        shell: powershell
        run: .\build\test-standard-user.ps1
```

- [ ] **Step 3: Probar el script en este equipo**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test-standard-user.ps1 -Path tests/Arguments.Tests.ps1 -Restricted`
Expected: se abre y se cierra una ventana; la salida termina en `Tests Passed: 29, Failed: 0`, código 0, y `TestResults\standard-user\elevated.txt` dice `False`.

- [ ] **Step 4: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 5: Commit**

```bash
git add build/test-standard-user.ps1 .github/workflows/ci.yml
git commit -m "ci: la suite también con un token de usuario estándar"
```

---

### Task 14: Prueba de extremo a extremo en Windows Sandbox

**Files:**
- Create: `tests/sandbox/e2e.wsb`, `tests/sandbox/E2E.psm1`, `tests/sandbox/Invoke-E2E.ps1`, `tests/sandbox/Start-E2E.ps1`, `tests/E2E.Tests.ps1`
- Modify: `build/lint.ps1` (también `tests\sandbox`)
- Test: `tests/E2E.Tests.ps1`

Diseño (sección 6, capa 5, y sección 12, punto 11):

- `Start-E2E.ps1` (en el equipo): exige `WindowsSandbox.exe`, llena la plantilla `e2e.wsb` con `New-E2EConfiguration` (rutas escapadas para XML: el repositorio en `C:\windows-tuneup` **solo lectura**, la carpeta de salida en `C:\e2e-out` con escritura, 8 GB), la abre y espera `e2e-report.json`; muestra `e2e-report.md` y termina con 1 si algo falló. `.wsb` no acepta rutas relativas, por eso la plantilla y el relleno.
- `Invoke-E2E.ps1` (el comando de inicio de sesión del sandbox, elevado): usa las carpetas de estado reales del sandbox (así también se prueba la carpeta protegida). Por perfil: foto inicial, aplicar con `-Yes` (los `ask` del perfil pedidos con `-Include`, las apps de la Store y OneDrive con `-Exclude`), `-Status` (todo `ok`), aplicar otra vez (`plan` con `summary.apply` = 0), `-Undo last`, foto y comparación. Después, reaplicar: aplicar `base`, devolver un valor de registro como si Windows lo hubiera revertido, `-Status` con ese `drift`, `-Status -Reapply -Yes`, todo `ok` y dos `-Undo last` sin diferencias. Escribe `e2e-report.json`, `e2e-report.md` y `e2e.log`, y apaga el sandbox (salvo `-KeepOpen`).
- `E2E.psm1`: la foto lee el estado de cada ajuste del catálogo con los manejadores (sin `appx`), el tipo de arranque de cada servicio, si cada tarea está habilitada y las apps de todos los usuarios; la comparación da cada diferencia y marca como volátil la de un servicio que solo empezó o dejó de correr.
- Las apps de la Store y OneDrive quedan fuera porque el sandbox no tiene Store ni winget (deshacer fallaría); los cubre `docs/{es,en}/vm-checklist.md` (Task 15).

**Sin comprobar:** el sandbox no está activado en el equipo donde se escribió el plan (no hay `WindowsSandbox.exe`), así que `Start-E2E.ps1` e `Invoke-E2E.ps1` no corrieron. Sí se probaron en el equipo, con `tests/E2E.Tests.ps1`, la foto y la comparación (un ajuste aplicado y deshecho con el motor, servicios y tareas reales leídos), la marca de volátil y la plantilla `.wsb` como XML válido. La Task 17 exige correrla antes de la release.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/E2E.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'sandbox\E2E.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-Snapshot([hashtable]$Tweaks = @{}, [hashtable]$Services = @{}, [string[]]$Apps = @()) {
        $map = [ordered]@{}
        foreach ($name in $Tweaks.Keys) { $map[$name] = [pscustomobject]@{ type = $Tweaks[$name][0]; state = $Tweaks[$name][1] } }
        $serviceMap = [ordered]@{}
        foreach ($name in $Services.Keys) { $serviceMap[$name] = $Services[$name] }
        [pscustomobject]@{ takenAt = 'now'; tweaks = $map; services = $serviceMap; tasks = [ordered]@{}; apps = $Apps }
    }
}

Describe 'End-to-end snapshots' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'sees the change of an applied tweak and nothing once it is undone' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = 'E2E'; kind = 'DWord'; value = 1 })
        $before = Get-E2ESnapshot -Catalog @($tweak) -Parts 'Tweaks'
        $run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -WarningAction SilentlyContinue
        $plan = @(New-TuneupPlan -Catalog @($tweak) -Profiles @(New-TestProfile -Id 'base' -Include @('test.sample')) `
            -Environment (New-TestEnvironment) -TestState { param($item) Test-TuneupState -Tweak $item })
        Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir | Out-Null
        $changed = @(Compare-E2ESnapshot -Before $before -After (Get-E2ESnapshot -Catalog @($tweak) -Parts 'Tweaks'))
        ($changed | ForEach-Object { "$($_.kind) $($_.name) $($_.volatile)" }) -join ',' | Should -Be 'tweak test.sample False'
        Invoke-TuneupUndo -Run $run | Out-Null
        @(Compare-E2ESnapshot -Before $before -After (Get-E2ESnapshot -Catalog @($tweak) -Parts 'Tweaks')).Count | Should -Be 0
    }

    It 'reads the services and the scheduled tasks of the machine' {
        $snapshot = Get-E2ESnapshot -Catalog @() -Parts 'Services', 'Tasks'
        $snapshot.services.Count | Should -BeGreaterThan 50
        $snapshot.tasks.Count | Should -BeGreaterThan 10
        $snapshot.services['EventLog'] | Should -Match '^start=\d delayed=\d$'
    }

    It 'calls volatile a service that only started or stopped, and not a change of its start type' {
        $before = New-Snapshot -Tweaks @{ 's.one' = @('service', '{"present":true,"startType":"Manual","running":false}') }
        $started = New-Snapshot -Tweaks @{ 's.one' = @('service', '{"present":true,"startType":"Manual","running":true}') }
        $disabled = New-Snapshot -Tweaks @{ 's.one' = @('service', '{"present":true,"startType":"Disabled","running":false}') }
        @(Compare-E2ESnapshot -Before $before -After $started)[0].volatile | Should -BeTrue
        @(Compare-E2ESnapshot -Before $before -After $disabled)[0].volatile | Should -BeFalse
    }

    It 'reports services that changed and apps that went missing or appeared' {
        $before = New-Snapshot -Services @{ 'A' = 'start=3 delayed=0' } -Apps @('App.One', 'App.Two')
        $after = New-Snapshot -Services @{ 'A' = 'start=4 delayed=0' } -Apps @('App.Two', 'App.Three')
        $differences = @(Compare-E2ESnapshot -Before $before -After $after)
        ($differences | ForEach-Object { "$($_.kind):$($_.name):$($_.after)" }) -join ',' | Should -Be 'service:A:start=4 delayed=0,app:App.One:missing,app:App.Three:installed'
    }

    It 'fills the .wsb template with the folders escaped, as valid XML' {
        $template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'sandbox\e2e.wsb'))
        [xml]$xml = New-E2EConfiguration -Template $template -Repo 'C:\code & more\windows-tuneup' -Output 'C:\out' -Arguments '-Profiles base,lite -KeepOpen'
        $folders = @($xml.Configuration.MappedFolders.MappedFolder)
        $folders[0].HostFolder | Should -Be 'C:\code & more\windows-tuneup'
        $folders[0].ReadOnly | Should -Be 'true'
        $folders[1].HostFolder | Should -Be 'C:\out'
        $folders[1].ReadOnly | Should -Be 'false'
        $xml.Configuration.LogonCommand.Command | Should -Match 'Invoke-E2E\.ps1 -Repo C:\\windows-tuneup -Output C:\\e2e-out -Profiles base,lite -KeepOpen$'
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/E2E.Tests.ps1`
Expected: FAIL: no existe `tests\sandbox\E2E.psm1`.

- [ ] **Step 3: Foto, comparación y plantilla**

Crear `tests/sandbox/E2E.psm1`:

```powershell
# Helpers of the end-to-end test in Windows Sandbox (Invoke-E2E.ps1 runs inside it, Start-E2E.ps1 on the
# host). They need the engine module loaded first: tweak states are read with the same handlers as the
# tool.
$ErrorActionPreference = 'Stop'

# What windows-tuneup can touch, read before and after: the state of every catalog tweak (minus the
# types left out), the start type of every service, whether every scheduled task is enabled, and the
# Store apps of all users. -Parts limits what is read (the host tests read only tweaks).
function Get-E2ESnapshot {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog,
        [string[]]$SkipTypes = @(),
        [ValidateSet('Tweaks', 'Services', 'Tasks', 'Apps')][string[]]$Parts = @('Tweaks', 'Services', 'Tasks', 'Apps')
    )
    $tweaks = [ordered]@{}
    if ($Parts -contains 'Tweaks') {
        foreach ($tweak in @($Catalog | Sort-Object -Property id)) {
            if ($SkipTypes -contains $tweak.type) { continue }
            try {
                $tweaks[[string]$tweak.id] = [pscustomobject]@{ type = [string]$tweak.type; state = (ConvertTo-Json -InputObject (Get-TuneupState -Tweak $tweak) -Depth 10 -Compress) }
            } catch {
                $tweaks[[string]$tweak.id] = [pscustomobject]@{ type = [string]$tweak.type; state = "unreadable: $($_.Exception.Message)" }
            }
        }
    }
    $services = [ordered]@{}
    if ($Parts -contains 'Services') {
        foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services' | Sort-Object -Property PSChildName)) {
            $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($null -ne $values -and $null -ne $values.Start) { $services[$key.PSChildName] = "start=$($values.Start) delayed=$([int]$values.DelayedAutostart)" }
        }
    }
    $tasks = [ordered]@{}
    if ($Parts -contains 'Tasks') {
        foreach ($task in @(Get-ScheduledTask | Sort-Object -Property TaskPath, TaskName)) {
            $tasks["$($task.TaskPath)$($task.TaskName)"] = ([string]$task.State -ne 'Disabled')
        }
    }
    $apps = @()
    if ($Parts -contains 'Apps') {
        $apps = @(Get-AppxPackage -AllUsers | ForEach-Object { $_.PackageFullName } | Sort-Object -Unique)
    }
    [pscustomobject]@{ takenAt = (Get-Date).ToString('s'); tweaks = $tweaks; services = $services; tasks = $tasks; apps = $apps }
}

# A service tweak's state also says whether the service is running, which Windows changes on its own
# (trigger-started services): a difference only there is reported as volatile, not as a failure.
function Test-E2EVolatileDifference {
    param([Parameter(Mandatory)][string]$Type, [AllowNull()][string]$Before, [AllowNull()][string]$After)
    if ($Type -ne 'service' -or -not $Before -or -not $After) { return $false }
    try {
        $one = $Before | ConvertFrom-Json
        $two = $After | ConvertFrom-Json
    } catch {
        return $false
    }
    $one.present -eq $two.present -and $one.startType -eq $two.startType
}

function Compare-E2EMap {
    param([Parameter(Mandatory)][string]$Kind, $Before, $After, [scriptblock]$Volatile)
    $names = @(@($Before.Keys) + @($After.Keys) | Sort-Object -Unique)
    foreach ($name in $names) {
        $one = $(if ($Before.Contains($name)) { $Before[$name] } else { $null })
        $two = $(if ($After.Contains($name)) { $After[$name] } else { $null })
        $oneText = $(if ($null -ne $one -and $one.PSObject.Properties['state']) { $one.state } else { [string]$one })
        $twoText = $(if ($null -ne $two -and $two.PSObject.Properties['state']) { $two.state } else { [string]$two })
        if ($oneText -ceq $twoText) { continue }
        $isVolatile = $(if ($Volatile) { [bool](& $Volatile $one $two) } else { $false })
        [pscustomobject]@{ kind = $Kind; name = $name; before = $oneText; after = $twoText; volatile = $isVolatile }
    }
}

# Every difference between two snapshots; zero non-volatile differences is the goal after an undo.
function Compare-E2ESnapshot {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    $serviceVolatile = {
        param($one, $two)
        $type = $(if ($null -ne $one) { $one.type } elseif ($null -ne $two) { $two.type } else { '' })
        Test-E2EVolatileDifference -Type $type -Before $(if ($one) { $one.state }) -After $(if ($two) { $two.state })
    }
    Compare-E2EMap -Kind 'tweak' -Before $Before.tweaks -After $After.tweaks -Volatile $serviceVolatile
    Compare-E2EMap -Kind 'service' -Before $Before.services -After $After.services
    Compare-E2EMap -Kind 'task' -Before $Before.tasks -After $After.tasks
    foreach ($app in @($Before.apps | Where-Object { @($After.apps) -notcontains $_ })) {
        [pscustomobject]@{ kind = 'app'; name = $app; before = 'installed'; after = 'missing'; volatile = $false }
    }
    foreach ($app in @($After.apps | Where-Object { @($Before.apps) -notcontains $_ })) {
        [pscustomobject]@{ kind = 'app'; name = $app; before = 'missing'; after = 'installed'; volatile = $false }
    }
}

# The .wsb file for a run: the repository mapped read-only, the output folder writable, and the logon
# command that starts Invoke-E2E.ps1. Paths are escaped for XML.
function New-E2EConfiguration {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Output,
        [AllowEmptyString()][string]$Arguments = ''
    )
    $text = $Template.Replace('__REPO__', [Security.SecurityElement]::Escape($Repo)).
        Replace('__OUTPUT__', [Security.SecurityElement]::Escape($Output)).
        Replace('__ARGUMENTS__', [Security.SecurityElement]::Escape($Arguments))
    [xml]$text | Out-Null
    $text
}

Export-ModuleMember -Function Get-E2ESnapshot, Compare-E2ESnapshot, Test-E2EVolatileDifference, New-E2EConfiguration
```

Crear `tests/sandbox/e2e.wsb`:

```xml
<Configuration>
  <MemoryInMB>8192</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>__REPO__</HostFolder>
      <SandboxFolder>C:\windows-tuneup</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>__OUTPUT__</HostFolder>
      <SandboxFolder>C:\e2e-out</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\windows-tuneup\tests\sandbox\Invoke-E2E.ps1 -Repo C:\windows-tuneup -Output C:\e2e-out __ARGUMENTS__</Command>
  </LogonCommand>
</Configuration>
```

- [ ] **Step 4: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/E2E.Tests.ps1`
Expected: PASS (`Tests Passed: 5, Failed: 0`).

- [ ] **Step 5: Lo que corre dentro del sandbox y lo que lo abre**

Crear `tests/sandbox/Invoke-E2E.ps1`:

```powershell
<#
.SYNOPSIS
    End-to-end test of every profile, inside Windows Sandbox (design, section 6, layer 5).
.DESCRIPTION
    Runs as the logon command of tests/sandbox/e2e.wsb, elevated, with the repository mapped read-only.
    It uses the real state folders of the sandbox (no -StateRoot), so the hardened folder is tested
    too. For each profile: snapshot, apply with -Yes (the tweaks that ask first are asked for by
    name), -Status (all in place), apply again (nothing left to apply), -Undo last, snapshot again and
    compare: no difference may remain. Then a re-apply check: a tweak of base is put back as it was,
    -Status shows the drift, -Status -Reapply applies it again, and two undos leave no difference.
    Store apps and OneDrive are left out: the sandbox has no Store and no winget, so their undo cannot
    run here (docs/es/vm-checklist.md covers them in a virtual machine). Writes e2e-report.json and
    e2e-report.md to -Output, then shuts the sandbox down unless -KeepOpen.
#>
param(
    [string]$Repo = 'C:\windows-tuneup',
    [string]$Output = 'C:\e2e-out',
    [string[]]$Profiles = @('base', 'dev', 'gaming', 'privacy', 'laptop', 'legacy', 'work', 'lite'),
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$Profiles = @($Profiles -split ',' | Where-Object { $_ })
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tuneup = Join-Path $Repo 'tuneup.ps1'
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$log = Join-Path $Output 'e2e.log'
function Write-E2ELog([string]$Text) { Add-Content -LiteralPath $log -Value "$((Get-Date).ToString('s')) $Text" -Encoding UTF8 }

# One command of the tool, with -Json: its exit code and its document.
function Invoke-E2ETuneup([string[]]$Arguments) {
    Write-E2ELog "tuneup.ps1 $($Arguments -join ' ')"
    $text = & $powershell -NoProfile -ExecutionPolicy Bypass -File $tuneup -Lang en -Json @Arguments | Out-String
    $code = $LASTEXITCODE
    $document = $null
    try { $document = $text | ConvertFrom-Json } catch { Write-E2ELog "not JSON: $text" }
    [pscustomobject]@{ ExitCode = $code; Document = $document }
}

function Get-E2EProblem($Result) {
    @($Result.Document.results | Where-Object { $_.status -in 'failed', 'partial', 'not-applied' } |
        ForEach-Object { "$($_.id): $($_.status) $($_.error) $($_.detail)".Trim() })
}

$report = [ordered]@{ startedAt = (Get-Date).ToString('s'); passed = $false; error = $null; environment = $null; systemRestore = $null; profiles = @(); reapply = $null }
try {
    Import-Module (Join-Path $Repo 'engine\Tuneup.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'E2E.psm1') -Force
    Initialize-TuneupI18n -Root (Join-Path $Repo 'i18n') -Lang en
    $environment = Get-TuneupEnvironment
    $report.environment = ConvertTo-TuneupEnvironmentView -Environment $environment
    if (-not $environment.IsAdmin) { throw 'The logon command of the sandbox is not elevated.' }
    $report.systemRestore = Get-TuneupSystemRestoreState
    $catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    $profileSet = @(Import-TuneupProfileSet -Path (Join-Path $Repo 'profiles'))
    $left = @($catalog | Where-Object { $_.type -eq 'appx' -or ($_.type -eq 'action' -and $_.set.script -eq 'onedrive') } | ForEach-Object { [string]$_.id })
    $initial = Get-E2ESnapshot -Catalog $catalog -SkipTypes @('appx')
    $initial | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Output 'snapshot-initial.json') -Encoding UTF8

    foreach ($profileId in $Profiles) {
        Write-E2ELog "profile $profileId"
        $profileData = $profileSet | Where-Object { $_.id -eq $profileId }
        $base = $profileSet | Where-Object { $_.id -eq 'base' }
        $ask = @(@($base.include) + @($profileData.include) | Where-Object { $_ } | Sort-Object -Unique |
            Where-Object { $id = $_; $tweak = $catalog | Where-Object { $_.id -eq $id }; $tweak.ask -and $left -notcontains $id })
        $arguments = @('-Profile', $profileId, '-Exclude', ($left -join ','), '-Yes')
        if ($ask.Count) { $arguments += @('-Include', ($ask -join ',')) }
        $apply = Invoke-E2ETuneup $arguments
        $status = Invoke-E2ETuneup @('-Status')
        $again = Invoke-E2ETuneup $arguments
        $undo = Invoke-E2ETuneup @('-Undo', 'last')
        $after = Get-E2ESnapshot -Catalog $catalog -SkipTypes @('appx')
        $differences = @(Compare-E2ESnapshot -Before $initial -After $after)
        $entry = [ordered]@{
            profile        = $profileId
            applyExitCode  = $apply.ExitCode
            applied        = $apply.Document.summary.applied
            refused        = @($apply.Document.results | Where-Object { $_.refused } | ForEach-Object { "$($_.id): $($_.reason)" })
            problems       = @(Get-E2EProblem $apply)
            notInPlace     = @($status.Document.items | Where-Object { $_.status -ne 'ok' } | ForEach-Object { "$($_.id): $($_.status)" })
            secondApply    = $(if ($again.Document.command -eq 'plan') { $again.Document.summary.apply } else { "ran again: $($again.Document.command)" })
            undoExitCode   = $undo.ExitCode
            undoProblems   = @($undo.Document.results | Where-Object { $_.status -eq 'failed' } | ForEach-Object { "$($_.id): $($_.error)" })
            differences    = @($differences | Where-Object { -not $_.volatile })
            volatile       = @($differences | Where-Object { $_.volatile })
        }
        $entry.passed = ($apply.ExitCode -eq 0 -and $entry.notInPlace.Count -eq 0 -and $entry.secondApply -eq 0 -and
            $undo.ExitCode -eq 0 -and $entry.differences.Count -eq 0)
        $report.profiles += [pscustomobject]$entry
    }

    # Re-apply: one registry tweak of base put back as it was before, as if Windows had reverted it.
    Write-E2ELog 'reapply'
    Invoke-E2ETuneup @('-Profile', 'base', '-Yes') | Out-Null
    $run = Resolve-TuneupRun -RunId 'last'
    $entry = @(Read-TuneupRunJournal -Run $run | Where-Object { $_.tweak.type -eq 'registry' })[0]
    Restore-TuneupState -Tweak $entry.tweak -State $entry.state | Out-Null
    $drift = Invoke-E2ETuneup @('-Status')
    $reapply = Invoke-E2ETuneup @('-Status', '-Reapply', '-Yes')
    $statusAfter = Invoke-E2ETuneup @('-Status')
    $undoReapply = Invoke-E2ETuneup @('-Undo', 'last')
    $undoBase = Invoke-E2ETuneup @('-Undo', 'last')
    $differences = @(Compare-E2ESnapshot -Before $initial -After (Get-E2ESnapshot -Catalog $catalog -SkipTypes @('appx')))
    $report.reapply = [pscustomobject]@{
        tweak       = $entry.id
        drifted     = @($drift.Document.items | Where-Object { $_.status -eq 'drift' } | ForEach-Object { $_.id })
        reapplied   = @($reapply.Document.results | Where-Object { $_.status -eq 'applied' } | ForEach-Object { $_.id })
        notInPlace  = @($statusAfter.Document.items | Where-Object { $_.status -ne 'ok' } | ForEach-Object { $_.id })
        undoCodes   = @($undoReapply.ExitCode, $undoBase.ExitCode)
        differences = @($differences | Where-Object { -not $_.volatile })
    }
    $report.reapply | Add-Member -NotePropertyName passed -NotePropertyValue (
        (@($report.reapply.drifted) -join ',') -eq $entry.id -and (@($report.reapply.reapplied) -join ',') -eq $entry.id -and
        $report.reapply.notInPlace.Count -eq 0 -and (@($report.reapply.undoCodes) -join ',') -eq '0,0' -and $report.reapply.differences.Count -eq 0)
    $report.passed = (@($report.profiles | Where-Object { -not $_.passed }).Count -eq 0) -and $report.reapply.passed
} catch {
    $report.error = "$($_.Exception.Message) $($_.ScriptStackTrace)"
    Write-E2ELog "error: $($report.error)"
}
$report.finishedAt = (Get-Date).ToString('s')
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Output 'e2e-report.json') -Encoding UTF8

$lines = @("# windows-tuneup end-to-end ($(if ($report.passed) { 'PASS' } else { 'FAIL' }))", '',
    "Build $($report.environment.build).$($report.environment.ubr), $($report.environment.edition); System Restore: $($report.systemRestore)", '')
if ($report.error) { $lines += @("Error: $($report.error)", '') }
$lines += '| Profile | Result | Applied | Apply exit | Not in place | Second apply | Undo exit | Differences |'
$lines += '|---|---|---|---|---|---|---|---|'
foreach ($entry in $report.profiles) {
    $lines += "| $($entry.profile) | $(if ($entry.passed) { 'PASS' } else { 'FAIL' }) | $($entry.applied) | $($entry.applyExitCode) | $($entry.notInPlace.Count) | $($entry.secondApply) | $($entry.undoExitCode) | $($entry.differences.Count) |"
}
foreach ($entry in $report.profiles | Where-Object { -not $_.passed }) {
    $lines += @('', "## $($entry.profile)")
    foreach ($line in @($entry.problems) + @($entry.notInPlace) + @($entry.undoProblems)) { $lines += "- $line" }
    foreach ($difference in $entry.differences) { $lines += "- $($difference.kind) $($difference.name): $($difference.before) -> $($difference.after)" }
}
if ($report.reapply) { $lines += @('', "Re-apply of $($report.reapply.tweak): $(if ($report.reapply.passed) { 'PASS' } else { 'FAIL' })") }
Set-Content -LiteralPath (Join-Path $Output 'e2e-report.md') -Value $lines -Encoding UTF8
Write-E2ELog 'done'
if (-not $KeepOpen) { & shutdown.exe /s /t 5 }
```

Crear `tests/sandbox/Start-E2E.ps1`:

```powershell
<#
.SYNOPSIS
    Opens Windows Sandbox and runs the end-to-end test of every profile in it.
.DESCRIPTION
    Needs Windows 10/11 Pro, Enterprise or Education with Windows Sandbox turned on (Windows features:
    "Windows Sandbox", or Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
    as administrator, then restart). It writes the .wsb file to -Output, opens it and waits for
    e2e-report.json there; the sandbox closes itself when the run ends (unless -KeepOpen). Nothing of
    the host changes: the repository is mapped read-only and everything runs inside the sandbox.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1 -Profiles base,lite -KeepOpen
#>
param(
    [string]$Output,
    [string[]]$Profiles = @(),
    [switch]$KeepOpen,
    [int]$TimeoutMinutes = 240
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).ProviderPath
$sandbox = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandbox)) {
    throw 'Windows Sandbox is not turned on: turn on the Windows feature "Windows Sandbox" (Containers-DisposableClientVM) and restart.'
}
if (-not $Output) { $Output = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-tuneup-e2e-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$Output = (Resolve-Path -LiteralPath $Output).ProviderPath
foreach ($name in 'e2e-report.json', 'e2e-report.md', 'e2e.log') {
    if (Test-Path -LiteralPath (Join-Path $Output $name)) { Remove-Item -LiteralPath (Join-Path $Output $name) -Force }
}

Import-Module (Join-Path $PSScriptRoot 'E2E.psm1') -Force
$arguments = @()
if ($Profiles.Count) { $arguments += "-Profiles $((@($Profiles -split ',' | Where-Object { $_ })) -join ',')" }
if ($KeepOpen) { $arguments += '-KeepOpen' }
$template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'e2e.wsb'))
$configuration = Join-Path $Output 'e2e.wsb'
[System.IO.File]::WriteAllText($configuration, (New-E2EConfiguration -Template $template -Repo $repo -Output $Output -Arguments ($arguments -join ' ')))

Write-Host "Opening Windows Sandbox; the report goes to $Output"
Start-Process -FilePath $sandbox -ArgumentList "`"$configuration`""
$report = Join-Path $Output 'e2e-report.json'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (-not (Test-Path -LiteralPath $report)) {
    if ((Get-Date) -gt $deadline) { throw "No report after $TimeoutMinutes minutes: see $(Join-Path $Output 'e2e.log')" }
    Start-Sleep -Seconds 15
}
Start-Sleep -Seconds 2
Get-Content -LiteralPath (Join-Path $Output 'e2e-report.md') -Encoding UTF8
$result = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $result.passed) { exit 1 }
```

En `build/lint.ps1`, reemplazar:

```powershell
    (Join-Path $root 'build')
)
```

por:

```powershell
    (Join-Path $root 'build'),
    (Join-Path $root 'tests\sandbox')
)
```

- [ ] **Step 6: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 7: Correrla, si el equipo tiene Windows Sandbox**

Requiere Windows Pro, Enterprise o Education con "Windows Sandbox" activado (Características de Windows, o `Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM` como administrador y reiniciar).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1 -Profiles base -KeepOpen`
Expected: se abre el sandbox, corre el perfil `base` y la prueba de reaplicar; en la consola del equipo aparece `e2e-report.md` con `PASS`. Con `-KeepOpen` el sandbox queda abierto para mirar `C:\e2e-out\e2e.log`. Si el equipo no tiene el sandbox, saltar este paso: la Task 17 lo exige antes de la release.

- [ ] **Step 8: Commit**

```bash
git add tests/sandbox/e2e.wsb tests/sandbox/E2E.psm1 tests/sandbox/Invoke-E2E.ps1 tests/sandbox/Start-E2E.ps1 tests/E2E.Tests.ps1 build/lint.ps1
git commit -m "test: prueba de extremo a extremo de cada perfil en Windows Sandbox"
```

---

### Task 15: Lista de la máquina virtual y contrato JSON

**Files:**
- Create: `docs/es/vm-checklist.md`, `docs/en/vm-checklist.md`, `docs/json-contract.md`, `tests/JsonContract.Tests.ps1`
- Test: `tests/Docs.Tests.ps1`, `tests/JsonContract.Tests.ps1`

`vm-checklist.md` cubre lo que el sandbox no puede: apps de la Store (quitar con el menú y reinstalar al deshacer), las negativas de OneDrive, el aviso de Restaurar sistema y su activación, Ctrl+C a mano, el menú en las dos consolas, el instalador y la medición contra LTSC. Cita los textos tal como los muestra la herramienta. `docs/json-contract.md` queda en inglés (es para desarrolladores y la skill del Plan 5) y `tests/JsonContract.Tests.ps1` arma cada documento con los comandos reales (catálogo de prueba) y exige que la página nombre cada campo (`environment.*` y `preflight[].*` en la sección `shared`; `after.*` de `health` como `before.*`).

- [ ] **Step 1: Pruebas que fallan**

En `tests/Docs.Tests.ps1`, reemplazar:

```powershell
        @{ Name = 'catalog.md' }
    ) {
```

por:

```powershell
        @{ Name = 'catalog.md' }
        @{ Name = 'vm-checklist.md' }
    ) {
```

En `tests/Docs.Tests.ps1`, agregar antes de `Describe 'Documentation in both languages' {`:

```powershell
Describe 'Virtual machine checklist' {
    It 'covers what Windows Sandbox cannot, in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'vm-checklist.md'
            foreach ($term in 'Start-E2E.ps1', 'install.ps1', 'winget', 'apps.onedrive', 'onedrive-known-folders', 'Ctrl+C', '-Measure -IdleSeconds 120', '-Undo last', 'measuring.md') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }
}
```

Crear `tests/JsonContract.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:Contract = [System.IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\json-contract.md'))

    # Every field of a document as a path: a.b for objects, a[].b for the objects of an array.
    function Get-JsonPath($Value, [string]$Prefix = '') {
        if ($null -eq $Value) { return }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($property in $Value.PSObject.Properties) {
                $path = $(if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name })
                $path
                Get-JsonPath $property.Value $path
            }
        } elseif ($Value -is [array]) {
            foreach ($item in $Value) { Get-JsonPath $item "$Prefix[]" }
        }
    }
    # The text of one section of the contract (from its ## heading to the next).
    function Get-ContractSection([string]$Name) {
        $match = [regex]::Match($Contract, '(?ms)^## `' + [regex]::Escape($Name) + '`\s*$(.*?)(?=^## |\z)')
        if (-not $match.Success) { throw "docs/json-contract.md has no section ## ``$Name``" }
        $match.Groups[1].Value
    }
    # The fields of a document that its section (or, for the shared ones, the shared section) does not name.
    function Get-UndocumentedPath([string]$Command, $Document) {
        $section = Get-ContractSection $Command
        $shared = Get-ContractSection 'shared'
        foreach ($path in @(Get-JsonPath $Document | Sort-Object -Unique)) {
            if (@('schemaVersion', 'command', 'toolVersion', 'warnings') -contains $path) { $text = $shared; $name = $path }
            elseif ($path -match '(^|\.)environment\.(?<field>\w+)$') { $text = $shared; $name = "environment.$($Matches.field)" }
            elseif ($path -match '(^|\.)preflight\[\]\.(?<field>\w+)$') { $text = $shared; $name = "preflight[].$($Matches.field)" }
            # A health report after a repair has the same fields as the check before it.
            elseif ($Command -eq 'health' -and $path -like 'after.*') { $text = $section; $name = 'before.' + $path.Substring('after.'.Length) }
            else { $text = $section; $name = $path }
            if (-not $text.Contains("``$name``")) { "$Command`: $name" }
        }
    }
    function New-TestContext {
        $context = New-TuneupContext -Json -Io (New-TestIo)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context
    }
}

Describe 'docs/json-contract.md' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'state'
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'pending-reboot'; message = 'Windows has a restart pending.' } }
        $context = New-TestContext
        $script:Documents = [ordered]@{}
        $Documents.plan = Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -PlanOnly | ConvertFrom-Json
        $Documents.apply = Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Yes | ConvertFrom-Json
        $Documents.status = Invoke-TuneupStatusCommand -Context $context | ConvertFrom-Json
        $Documents.undo = Invoke-TuneupUndoCommand -Context $context -RunId 'last' | ConvertFrom-Json
        Invoke-TuneupMeasureCommand -Context $context | Out-Null
        $Documents.measure = Invoke-TuneupMeasureCommand -Context $context -Compare 'last' | ConvertFrom-Json
        $Documents.error = Write-TuneupErrorReport -Message 'x' -Details @('y') -Json | ConvertFrom-Json
        $cbs = Join-Path $Fixtures 'cbs'
        $lines = @(Get-Content -LiteralPath (Join-Path $cbs 'sfc-unrepaired.log') -Encoding UTF8) + @(Get-Content -LiteralPath (Join-Path $cbs 'scanhealth-corrupt.log') -Encoding UTF8)
        $scan = New-TuneupHealthScan -Lines $lines -SfcRun ([pscustomobject]@{ ExitCode = 1; Output = 'x' }) -DismRun ([pscustomobject]@{ ExitCode = 0; Output = '' })
        $health = [pscustomobject]@{ schemaVersion = 1; command = 'health'; startedAt = 's'; finishedAt = 'f'; repairRequested = $true; repairRan = $true
            before = $scan; after = $scan; recommendation = 'manual-repair'; rebootRecommended = $false }
        $Documents.health = Write-TuneupHealthReport -Report $health -Json | ConvertFrom-Json
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'names every field of the <Command> document' -TestCases @(
        @{ Command = 'plan' }
        @{ Command = 'apply' }
        @{ Command = 'status' }
        @{ Command = 'undo' }
        @{ Command = 'measure' }
        @{ Command = 'health' }
        @{ Command = 'error' }
    ) {
        param($Command)
        $Documents[$Command].command | Should -Be $Command
        @(Get-UndocumentedPath $Command $Documents[$Command]) -join "`n" | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: FAIL en `has vm-checklist.md in Spanish and English...` y `covers what Windows Sandbox cannot...`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/JsonContract.Tests.ps1`
Expected: FAIL: `docs\json-contract.md` no existe.

- [ ] **Step 3: La lista de la máquina virtual**

Crear `docs/es/vm-checklist.md`:

````markdown
# Lista para la máquina virtual antes de cada release

Windows Sandbox (`tests/sandbox/Start-E2E.ps1`) prueba cada perfil de punta a punta, pero no trae Microsoft Store ni winget, se reinicia en limpio y no tiene OneDrive con sesión iniciada. Esta lista cubre lo demás en una máquina virtual con Windows 11 Pro. Se hace a mano antes de publicar cada release y su resultado se adjunta a la release junto con `e2e-report.md` y la medición de [measuring.md](measuring.md).

## Preparar la máquina virtual

1. Windows 11 Pro de la última versión, con las actualizaciones al día, la Microsoft Store y winget funcionando (`winget --version`).
2. Una cuenta local de administrador con la sesión iniciada en el escritorio.
3. OneDrive con una cuenta iniciada y una carpeta con archivos solo en la nube (Liberar espacio).
4. Restaurar sistema **desactivado** en `C:` (Propiedades del sistema > Protección del sistema), para probar el aviso.
5. Una instantánea (checkpoint) de la máquina en este estado.

## Instalar la versión candidata

Copia a la máquina virtual el zip y `SHA256SUMS` del borrador de la release (o genéralos con `build/package.ps1 -OutputPath <carpeta>`). En PowerShell como administrador:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Source <carpeta> -Version <versión> -Sha256 <hash del zip>
```

- [ ] Instala en `C:\Program Files\windows-tuneup` y dice `SHA256 checked`.
- [ ] Con un hash equivocado no instala nada.

## Probar

- [ ] `tuneup.ps1 -Status`: no hay ajustes aplicados.
- [ ] Reiniciar, iniciar sesión y correr `tuneup.ps1 -Measure -IdleSeconds 120`.
- [ ] `tuneup.ps1` sin parámetros abre el menú, en la consola clásica de Windows PowerShell y en Windows Terminal; cada opción se recorre solo con el teclado.
- [ ] Menú > Optimizar > `lite`: aparece el aviso de Restaurar sistema desactivado; responder sí lo activa (comprobar en Propiedades del sistema) y la corrida informa "Punto de restauración creado".
- [ ] Las apps que preguntan se responden una por una (sí a todas menos una); las elegidas desaparecen de `Get-AppxPackage -AllUsers` y la otra queda con el motivo "dijiste que no".
- [ ] OneDrive con Escritorio, Documentos o Imágenes en OneDrive: `apps.onedrive` queda negado (`onedrive-known-folders`); sin esas carpetas pero con archivos solo en la nube, negado (`onedrive-online-only-files`); sin nada de eso, se desinstala.
- [ ] Ctrl+C durante una corrida larga de `lite`: termina el ajuste en curso, el resumen dice "Detenido con Ctrl+C" y el código de salida es 2.
- [ ] Reiniciar; `tuneup.ps1 -Status` muestra todo `ok`; `tuneup.ps1 -Measure -IdleSeconds 120 -Compare last` da la diferencia.
- [ ] `tuneup.ps1 -Undo last` (las veces que haga falta, hasta "No hay corridas para deshacer"): las apps se reinstalan con winget (motivo "reinstalada desde Microsoft Store para el usuario actual"), OneDrive se reinstala y `-Status` queda vacío.
- [ ] Contra la instantánea: las apps volvieron (su versión puede ser otra) y OneDrive sincroniza otra vez después de iniciar sesión.
- [ ] Liviano frente a LTSC: el método de [measuring.md](measuring.md), con su reporte.

## Adjuntar a la release

- `e2e-report.md` de Windows Sandbox.
- Esta lista marcada, con la compilación de Windows usada.
- La salida de `-Measure -Compare` y el reporte de Liviano frente a LTSC.
````

Crear `docs/en/vm-checklist.md`:

````markdown
# Virtual machine checklist before each release

Windows Sandbox (`tests/sandbox/Start-E2E.ps1`) tests every profile end to end, but it has no Microsoft Store and no winget, it starts clean every time and has no OneDrive signed in. This checklist covers the rest in a Windows 11 Pro virtual machine. It is done by hand before publishing each release, and its result is attached to the release with `e2e-report.md` and the measurement of [measuring.md](measuring.md).

## Prepare the virtual machine

1. Windows 11 Pro of the latest version, fully updated, with the Microsoft Store and winget working (`winget --version`).
2. A local administrator account signed in at the desktop.
3. OneDrive signed in, with a folder of files that only live in the cloud (Free up space).
4. System Restore **turned off** on `C:` (System Properties > System Protection), to test the warning.
5. A snapshot (checkpoint) of the machine in this state.

## Install the release candidate

Copy the zip and `SHA256SUMS` of the draft release to the virtual machine (or build them with `build/package.ps1 -OutputPath <folder>`). In PowerShell as administrator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Source <folder> -Version <version> -Sha256 <hash of the zip>
```

- [ ] It installs in `C:\Program Files\windows-tuneup` and says `SHA256 checked`.
- [ ] With a wrong hash it installs nothing.

## Test

- [ ] `tuneup.ps1 -Status`: no tweak is applied.
- [ ] Restart, sign in and run `tuneup.ps1 -Measure -IdleSeconds 120`.
- [ ] `tuneup.ps1` without parameters opens the menu, in the classic Windows PowerShell console and in Windows Terminal; every option works with the keyboard only.
- [ ] Menu > Optimize > `lite`: the warning about System Restore being off appears; answering yes turns it on (check in System Properties) and the run reports `Restore point created`.
- [ ] The apps that ask first are answered one by one (yes to all but one); the chosen ones disappear from `Get-AppxPackage -AllUsers` and the other one stays with the reason "you said no".
- [ ] OneDrive with Desktop, Documents or Pictures in OneDrive: `apps.onedrive` is refused (`onedrive-known-folders`); without those folders but with files only in the cloud, refused (`onedrive-online-only-files`); with neither, it is uninstalled.
- [ ] Ctrl+C during a long `lite` run: the tweak in progress finishes, the summary says "Stopped with Ctrl+C" and the exit code is 2.
- [ ] Restart; `tuneup.ps1 -Status` shows everything `ok`; `tuneup.ps1 -Measure -IdleSeconds 120 -Compare last` gives the difference.
- [ ] `tuneup.ps1 -Undo last` (as many times as needed, until "There are no runs to undo"): the apps are reinstalled with winget (reason "reinstalled from the Microsoft Store"), OneDrive is reinstalled and `-Status` is empty.
- [ ] Against the snapshot: the apps are back (their version may differ) and OneDrive syncs again after signing in.
- [ ] Lite versus LTSC: the method of [measuring.md](measuring.md), with its report.

## Attach to the release

- `e2e-report.md` from Windows Sandbox.
- This checklist, ticked, with the Windows build used.
- The output of `-Measure -Compare` and the Lite versus LTSC report.
````

- [ ] **Step 4: El contrato JSON**

Crear `docs/json-contract.md`:

```markdown
# windows-tuneup JSON contract

What `tuneup.ps1 ... -Json` writes, for programs that drive it (the Claude skill of Plan 5 among them). This page is for developers and is kept in English; `tests/JsonContract.Tests.ps1` fails when a document has a field that this page does not name.

## Rules

- Standard output is **one** JSON document, ASCII only (every non-ASCII character is `\uXXXX`), with camelCase keys. Nothing else is printed around it; warnings go inside it.
- Every document has `schemaVersion` (`1`), `command`, `toolVersion` and `warnings`. A field is never removed or renamed within a `schemaVersion`; new fields can appear, so readers ignore what they do not know.
- The exit code completes the document: `0` everything done, `2` not everything was done (read the document), `1` nothing was done or it could not start (the document is usually an `error`).
- An unknown parameter or a `-Lang` other than `es`/`en` is rejected by PowerShell itself: no JSON document, exit code `1`.
- `-Json` never asks anything. Applying needs `-Yes`; without it a plan with changes ends in an `error` (exit `1`). Without a command and without `-Json` the tool opens the menu, which has no JSON output.
- Texts meant for people (`title`, `message`, `detail`, `error`, `warnings`) follow `-Lang`; ids, statuses and reasons never change with the language.

| Command line | `command` of the document |
|---|---|
| `-WhatIf -Json`, or nothing to apply | `plan` |
| `-Yes -Json` | `apply` (or `plan` when there was nothing to apply) |
| `-Status -Json` | `status` |
| `-Status -Reapply -Json` with `-WhatIf` or `-Yes` | `plan` or `apply`, with `source` = `reapply` |
| `-Undo <id\|last> [-Tweak <id>] -Json` | `undo` |
| `-Health [-Repair] -Json` | `health` |
| `-Measure [-Compare <id\|last>] [-IdleSeconds <n>] -Json` | `measure` |
| any refusal or failure before the work | `error` |

## `shared`

Fields that several documents carry.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | number | `1`. |
| `command` | string | Which document this is (see the table above). |
| `toolVersion` | string | Version of windows-tuneup that wrote it (`major.minor.patch`). |
| `warnings` | string[] | Warnings raised while running (untrusted state files ignored, action scripts that did not load, `-StateRoot` in use...). |
| `environment.build` | number | Windows build (`CurrentBuild`). |
| `environment.ubr` | number | Update build revision. |
| `environment.family` | string | `10` or `11`. |
| `environment.edition` | string | `Home`, `Pro`, `Enterprise`, `Education` or `Server` (`Server` plans as `Enterprise` with `-Force`). |
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
| `items[].risk` | string | `low`, `medium` or `high`. |
| `items[].scope` | string | `user` or `machine`. |
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

Ctrl+C with `-Json`: when it reaches the console as a key (between two tweaks, with a console of its own) the usual `apply` document comes out, with `interrupted` true and the exit code above. When it stops PowerShell itself (a native program such as DISM or winget was running) nothing is written to the standard output: the exit code is `2` and the document is the `result.json` of the newest folder under `runs` of the state folder (the tweak that was cut is `failed`, with its journal entry, so `-Undo last` restores it; the ones not reached are `interrupted`). A caller must read an empty output with exit code `2` as "look at `result.json`". A failure that is not Ctrl+C leaves the same `result.json` with the tweaks not reached as `aborted`, and the error report on the standard output.

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

## `error`

| Field | Type | Meaning |
|---|---|---|
| `message` | string | What went wrong, for people. |
| `details` | string[] | More lines (for example, each problem of the catalog). |

Exit code: `1`.
```

- [ ] **Step 5: Verificar que pasan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: PASS (`Tests Passed: 12, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/JsonContract.Tests.ps1`
Expected: PASS (`Tests Passed: 7, Failed: 0`). Si falla, el mensaje lista cada campo sin nombrar (`apply: summary.interrupted`): agregarlo a la sección de ese comando.

- [ ] **Step 6: Commit**

```bash
git add docs/es/vm-checklist.md docs/en/vm-checklist.md docs/json-contract.md tests/Docs.Tests.ps1 tests/JsonContract.Tests.ps1
git commit -m "docs: lista de la máquina virtual y contrato JSON"
```

---

### Task 16: README, lint y suite completa

**Files:**
- Modify: `README.md` (reemplazo completo)

Cambios: el aviso pasa a "Antes de la primera release"; sección Instalación (la línea `irm … | iex` fijada a `v0.1.0`, qué verifica `install.ps1`, la copia sin elevar, a mano con `SHA256SUMS` y `Unblock-File`, el aviso `untrusted-location`); el menú; `-Status -Reapply`; los avisos antes de aplicar, Ctrl+C, `transcript.log` y deshacer a mano en "Qué hace hoy"; la salud repara desde el menú; códigos de salida con Ctrl+C y el menú; el JSON con `toolVersion`, `preflight`, `source`, `interrupted`, `manual` y el enlace a `docs/json-contract.md`; limitaciones (Restaurar sistema solo elevado, `install.ps1` en inglés; sale "No hay menú"); desarrollo (lint de `install.ps1` y `tests/sandbox`, consolas ocultas de las pruebas de Ctrl+C, `test-standard-user.ps1`, la prueba de extremo a extremo y cómo se hace una release).

- [ ] **Step 1: README**

Reemplazar `README.md` completo por:

````markdown
# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> **Antes de la primera release.** El motor, el catálogo (166 ajustes: 162 alcanzables desde los 8 perfiles y 4 de riesgo alto que solo se aplican con `-Include`), el menú y la distribución están completos; falta correr la prueba de extremo a extremo de cada perfil en Windows Sandbox y la lista de la máquina virtual ([docs/es/vm-checklist.md](docs/es/vm-checklist.md)) antes de publicar la versión 0.1.0. Revisa siempre el plan antes de aplicar.
> **Before the first release.** The engine, the catalog (166 tweaks: 162 reachable from the 8 profiles and 4 high-risk ones that are only applied with `-Include`), the menu and the distribution are complete; the end-to-end test of every profile in Windows Sandbox and the virtual machine checklist ([docs/en/vm-checklist.md](docs/en/vm-checklist.md)) still have to run before version 0.1.0 is published. Always review the plan before applying.

## Perfiles / Profiles

| Perfil / Profile | Alias | Qué hace / What it does | Administrador / Administrator |
|---|---|---|---|
| `base` | | Sin anuncios ni sugerencias, ID de publicidad apagado, extensiones visibles. Siempre se aplica. / No ads or suggestions, advertising ID off, extensions shown. Always applied. | No |
| `dev` | `desarrollo` | Modo desarrollador, rutas largas, archivos ocultos, "Finalizar tarea"; respeta WSL y Hyper-V. / Developer Mode, long paths, hidden files, "End task"; keeps WSL and Hyper-V. | Sí / Yes |
| `gaming` | `juegos` | Modo Juego, sin grabación en segundo plano ni aceleración del mouse, GPU con menos latencia; conserva Xbox. / Game Mode, no background recording or mouse acceleration, lower GPU latency; keeps Xbox. | Sí / Yes |
| `privacy` | `privacidad` | Telemetría al mínimo, historial de actividad, Bing, Copilot, Edge (Recall solo con `-Include`). / Minimum telemetry, activity history, Bing, Copilot, Edge (Recall only with `-Include`). | Sí / Yes |
| `laptop` | `portatil`, `portátil` | Más batería: sin compartir descargas, Edge sin procesos de fondo, escáner y mapas en manual, sin red en suspensión con batería (pregunta); apps en segundo plano solo en Windows 10 (pregunta). / More battery: no download sharing, Edge without background processes, scanner and maps manual, no network in standby on battery (asks); background apps on Windows 10 only (asks). | Sí / Yes |
| `legacy` | `equipo-antiguo`, `antiguo` | Sin transparencia ni animaciones, menos tareas de fondo y apps preinstaladas. / No transparency or animations, fewer background tasks and preinstalled apps. | Sí / Yes |
| `work` | `trabajo` | Solo ajustes de tu usuario, sin directivas; conserva Teams, Outlook, OneDrive, To Do y Carpetas de trabajo. / Only settings of your user, no policies; keeps Teams, Outlook, OneDrive, To Do and Work Folders. | No |
| `lite` | `liviano` | Quita lo que LTSC no trae y recorta servicios y tareas; Teams, Xbox, Vínculo móvil, la app Copilot, Outlook, Correo y OneDrive preguntan antes, y casi todos los servicios también; sin tocar Defender, Update ni WinRE. / Removes what LTSC does not ship and trims services and tasks; Teams, Xbox, Phone Link, the Copilot app, Outlook, Mail and OneDrive ask first, and so do most services; Defender, Update and WinRE untouched. | Sí / Yes |

Guía de cada perfil / Guide to each profile: [docs/es/profiles.md](docs/es/profiles.md) · [docs/en/profiles.md](docs/en/profiles.md). Catálogo completo / Full catalog: [docs/es/catalog.md](docs/es/catalog.md) · [docs/en/catalog.md](docs/en/catalog.md). Lo que nunca se aplica / What is never applied: [docs/es/blacklist.md](docs/es/blacklist.md) · [docs/en/blacklist.md](docs/en/blacklist.md).

**Liviano frente a LTSC / Lite versus LTSC:** el objetivo es que Liviano quede por debajo de una instalación limpia de Windows 11 LTSC 2024 en RAM, procesos y servicios en reposo. **Todavía no está medido**; el método está en [docs/es/measuring.md](docs/es/measuring.md). / The goal is for Lite to end below a clean Windows 11 LTSC 2024 install in idle RAM, processes and services. **It is not measured yet**; the method is in [docs/en/measuring.md](docs/en/measuring.md).

## Requisitos / Requirements

- Windows 10 u 11 (build 19041 o posterior) con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1. Windows Server y builds anteriores se rechazan salvo con `-Force`.
- Windows 10 or 11 (build 19041 or later) with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1. Windows Server and older builds are refused unless `-Force` is given.
- Los ajustes de sistema y las directivas de tu usuario (las claves `Policies` de `HKCU`, que Windows solo deja leer y escribir a un administrador) necesitan PowerShell como administrador. Sin elevar, un plan que contenga cualquiera de ellos se rechaza completo (no se aplica nada): usar `-Exclude` para dejar fuera esos ajustes o abrir PowerShell como administrador. Los perfiles `base` (siempre aplicado) y `work` solo tienen ajustes de registro de usuario (`HKCU`) que no son directivas y se aplican sin elevar; los demás traen cambios de sistema o directivas.
- System-wide tweaks and policies of your user (the `Policies` keys of `HKCU`, which Windows only lets an administrator read and write) need PowerShell as administrator. Without elevation, a plan that contains any of them is refused entirely (nothing is applied): use `-Exclude` to leave those tweaks out or open PowerShell as administrator. The `base` (always applied) and `work` profiles only hold user registry tweaks (`HKCU`) that are not policies and apply without elevation; the others bring system changes or policies.
- Si elevas con la contraseña de otro administrador (la cuenta del proceso no es la que inició sesión en el escritorio), el plan omite todos los ajustes de usuario con el motivo `session-user`: escribirían en el `HKCU` de esa otra cuenta. Los ajustes de sistema siguen su curso; para los de usuario, abre PowerShell como administrador desde la cuenta que inició sesión. Una ejecución sin elevar no cambia.
- `-Health` necesita administrador. `-Measure` no, pero sin administrador no puede leer la duración del arranque. Deshacer la quita de una app de la Store usa `winget` (App Installer); elevado, solo el `winget.exe` que Windows instaló en `Program Files\WindowsApps`, nunca el alias de la carpeta del usuario.
- If you elevate with another administrator's password (the account of the process is not the one signed in at the desktop), the plan skips every user tweak with the reason `session-user`: they would land in that other account's `HKCU`. System tweaks go on; for the user ones, open PowerShell as administrator from the account that is signed in. A run that is not elevated is unaffected.
- `-Health` needs administrator. `-Measure` does not, but without administrator it cannot read the boot duration. Undoing the removal of a Store app uses `winget` (App Installer); elevated, only the `winget.exe` that Windows installed under `Program Files\WindowsApps`, never the alias in the user's folder.
- Ejecutar `windows-tuneup` desde una carpeta donde solo escriban administradores (por ejemplo bajo `Program Files`): quien pueda modificar `actions/` o `engine/` ejecuta código con los permisos de quien aplica los ajustes. La revisión de las acciones (solo se leen definiciones de funciones, sin ejecutar nada al cargar) es defensa en profundidad, no sustituye ese permiso de carpeta.
- Run `windows-tuneup` from a folder that only administrators can write to (for example under `Program Files`): anyone who can change `actions/` or `engine/` runs code with the rights of whoever applies the tweaks. The check of action scripts (only function definitions are read, nothing runs while loading) is defense in depth, not a substitute for that folder permission.

## Instalación / Installation

Abre PowerShell **como administrador** e instala una versión fija (nunca `main`) en `%ProgramFiles%\windows-tuneup`, que solo los administradores pueden cambiar:
Open PowerShell **as administrator** and install a fixed version (never `main`) in `%ProgramFiles%\windows-tuneup`, which only administrators can change:

```powershell
irm https://github.com/edgarlugo/windows-tuneup/releases/download/v0.1.0/install.ps1 | iex
```

- El `install.ps1` de cada release trae dentro su versión y el SHA256 de su zip: descarga el zip, comprueba el SHA256 y no extrae nada si no coincide. `irm | iex` ejecuta lo que descarga sin mostrarlo; si prefieres revisarlo antes, descarga `install.ps1` de la release, compara su SHA256 con el de `SHA256SUMS` y las notas de la release, léelo y córrelo con `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`.
  The `install.ps1` of each release carries its version and the SHA256 of its zip: it downloads the zip, checks the SHA256 and extracts nothing if it does not match. `irm | iex` runs what it downloads without showing it; if you prefer to review it first, download `install.ps1` from the release, compare its SHA256 with the one in `SHA256SUMS` and in the release notes, read it and run it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`.
- Sin elevar, `install.ps1` extrae la versión en la carpeta actual (`windows-tuneup-<versión>`): esa copia la pueden cambiar los programas de tu cuenta, así que sirve para los ajustes de tu usuario y no debe correrse como administrador. `-Destination <carpeta>` elige otra carpeta.
  Without elevation, `install.ps1` extracts the version into the current folder (`windows-tuneup-<version>`): programs of your account can change that copy, so it is for the tweaks of your user and must not be run as administrator. `-Destination <folder>` picks another folder.
- A mano: descarga `windows-tuneup-<versión>.zip` y `SHA256SUMS` de la release, compara `(Get-FileHash .\windows-tuneup-<versión>.zip).Hash` con la línea del zip, extráelo y quita la marca de descarga del navegador con `Get-ChildItem -Recurse | Unblock-File`; para los ajustes de sistema, cópialo en `%ProgramFiles%\windows-tuneup` como administrador.
  By hand: download `windows-tuneup-<version>.zip` and `SHA256SUMS` from the release, compare `(Get-FileHash .\windows-tuneup-<version>.zip).Hash` with the line of the zip, extract it and clear the browser's download mark with `Get-ChildItem -Recurse | Unblock-File`; for system tweaks, copy it to `%ProgramFiles%\windows-tuneup` as administrator.
- Corrido como administrador desde una carpeta que otras cuentas pueden cambiar, el plan lo avisa (`untrusted-location`).
  Run as administrator from a folder that other accounts can change, the plan warns about it (`untrusted-location`).

## Uso / Usage

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1                        # menú / menu
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base -WhatIf   # ver el plan / show the plan
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base,privacy   # aplicar (pregunta antes) / apply (asks first)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Status                 # estado / status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Status -Reapply        # volver a aplicar lo revertido / apply again what was reverted
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Undo last              # deshacer / undo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Health                 # SFC + DISM (administrador / administrator)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Health -Repair         # + DISM /RestoreHealth si hace falta / if needed
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Measure -IdleSeconds 120                 # medir / measure
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Measure -IdleSeconds 120 -Compare last   # comparar / compare
```

`-ExecutionPolicy Bypass` solo afecta a ese proceso y permite ejecutar el script aunque la política de PowerShell sea `Restricted`; no cambia la configuración del equipo.
`-ExecutionPolicy Bypass` only affects that process and lets the script run even if the PowerShell policy is `Restricted`; it does not change the machine configuration.

### Menú / Menu

Sin parámetros, `tuneup.ps1` abre un menú en la consola (Windows PowerShell o Windows Terminal), solo con el teclado: cada respuesta es un número o una letra y Enter. Optimizar elige los perfiles (marca `(administrador)` los que lo necesitan), ofrece aparte los ajustes de riesgo alto (hay que escribir `si` completo para agregarlos), pregunta uno por uno los ajustes que preguntan antes (`s`, `n`, `t` = sí a todos los que quedan, `x` = no a todos los que quedan), muestra el plan con sus avisos y pide confirmación. También: Estado (y volver a aplicar lo que Windows revirtió), Deshacer (una corrida o un ajuste, elegidos de una lista), Salud (y reparar si hace falta) y Medir.
Without parameters, `tuneup.ps1` opens a menu in the console (Windows PowerShell or Windows Terminal), keyboard only: every answer is a number or a letter and Enter. Optimize picks the profiles (it marks with `(administrator)` the ones that need it), offers the high-risk tweaks apart (typing `yes` in full adds them), asks one by one about the tweaks that ask first (`y`, `n`, `a` = yes to all the rest, `x` = no to all the rest), shows the plan with its warnings and asks for confirmation. Also: Status (and apply again what Windows reverted), Undo (a run or one tweak, picked from a list), Health (and repair when needed) and Measure.

### Parámetros / Parameters

| Parámetro / Parameter | Qué hace / What it does |
|---|---|
| `-Profile <lista>` | Perfiles a aplicar, separados por comas. `base` se aplica siempre. Un perfil también se llama por su alias (`privacidad`). / Profiles to apply, comma separated. `base` is always applied. A profile can also be named by its alias (`privacidad`). |
| `-Include <ids>` / `-Exclude <ids>` | Ajustes extra o excluidos. Solo con `-Include` se aplican los de riesgo alto o que piden confirmación. / Extra or excluded tweaks. Only `-Include` applies tweaks of high risk or that ask for confirmation. |
| `-WhatIf` | Muestra el plan y no cambia nada. / Shows the plan and changes nothing. |
| `-Yes` | Aplica sin preguntar. / Applies without asking. |
| (ninguno / none) | Menú interactivo. / Interactive menu. |
| `-Status [-Reapply]` | Qué sigue aplicado y qué revirtió Windows; con `-Reapply`, vuelve a aplicar lo revertido como una corrida nueva (acepta `-Yes` y `-WhatIf`). / What is still applied and what Windows reverted; with `-Reapply`, applies again what was reverted as a new run (takes `-Yes` and `-WhatIf`). |
| `-Undo <id\|last> [-Tweak <id>]` | Deshace una corrida o solo un ajuste de ella. / Undoes a run, or just one tweak of it. |
| `-Health [-Repair]` | SFC + DISM `/ScanHealth`; con `-Repair`, DISM `/RestoreHealth` y SFC otra vez si hace falta. Administrador. / SFC + DISM `/ScanHealth`; with `-Repair`, DISM `/RestoreHealth` and SFC again if needed. Administrator. |
| `-Measure [-Compare <id\|last>] [-IdleSeconds <n>]` | Guarda una medición; `-Compare` la compara con una anterior; `-IdleSeconds` (0 a 3600) espera antes de medir. / Saves a measurement; `-Compare` compares it with an earlier one; `-IdleSeconds` (0 to 3600) waits before measuring. |
| `-Json` | Salida como un documento JSON (ver abajo). / Output as one JSON document (see below). |
| `-Lang es\|en` | Idioma de los mensajes. / Language of the messages. |
| `-Force` | Permite Windows Server o builds no soportados. / Allows Windows Server or unsupported builds. |
| `-StateRoot`, `-ActionsPath`, `-CatalogPath`, `-ProfilesPath` | Solo para pruebas y desarrollo (ver más abajo). / For testing and development only (see below). |

`-Status`, `-Undo`, `-Health` y `-Measure` se excluyen entre sí y no se combinan con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` ni `-Yes` (salvo `-Status -Reapply`, que acepta `-Yes` y `-WhatIf`). `-Tweak` exige `-Undo`, `-Repair` exige `-Health`, `-Reapply` exige `-Status`, y `-Compare` e `-IdleSeconds` exigen `-Measure`. Una combinación inválida termina con código 1 antes de leer nada.
`-Status`, `-Undo`, `-Health` and `-Measure` exclude each other and cannot be combined with `-Profile`, `-Include`, `-Exclude`, `-WhatIf` or `-Yes` (except `-Status -Reapply`, which takes `-Yes` and `-WhatIf`). `-Tweak` requires `-Undo`, `-Repair` requires `-Health`, `-Reapply` requires `-Status`, and `-Compare` and `-IdleSeconds` require `-Measure`. An invalid combination ends with code 1 before anything is read.

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
- `-Health` corre `sfc /scannow` y `DISM /ScanHealth` y resume lo que dejaron en `CBS.log`: archivos reparados o sin reparar, estado del almacén de componentes y componentes dañados agrupados, con una recomendación (`none`, `run-repair`, `manual-repair`, `check-logs`). `-Health -Repair` corre además `DISM /RestoreHealth` y SFC otra vez, solo si hace falta, y muestra antes y después. En la línea de comandos la reparación se pide con `-Repair`; el menú la ofrece después de una revisión que encuentra daños reparables, sin volver a revisar.
  `-Health` runs `sfc /scannow` and `DISM /ScanHealth` and summarizes what they left in `CBS.log`: repaired and unrepaired files, component store state and damaged components grouped, with a recommendation (`none`, `run-repair`, `manual-repair`, `check-logs`). `-Health -Repair` also runs `DISM /RestoreHealth` and SFC again, only when needed, and shows before and after. On the command line the repair is asked for with `-Repair`; the menu offers it after a check that finds repairable damage, without checking again.
- `-Measure` guarda RAM en uso, procesos, servicios en ejecución, tareas programadas habilitadas, espacio libre del disco del sistema, duración del último arranque y minutos desde el arranque; `-Compare <id|last>` muestra la diferencia con una medición anterior (se resuelve antes de medir, así `last` nunca es la medición nueva). Los números siguen el idioma de `-Lang` (coma decimal en `es`, punto en `en`) y, si un valor falta, la comparación dice el motivo (por ejemplo, requiere administrador).
  `-Measure` saves RAM in use, processes, running services, enabled scheduled tasks, free space on the system drive, last boot duration and minutes since boot; `-Compare <id|last>` shows the difference from an earlier measurement (it is resolved before measuring, so `last` is never the new measurement). Numbers follow the `-Lang` language (decimal comma in `es`, point in `en`) and, when a value is missing, the comparison says why (for example, needs administrator).
- Antes de aplicar avisa, sin detenerse, de un reinicio pendiente, menos de 2 GB libres en el disco del sistema, Restaurar sistema desactivado (y ofrece activarlo antes, solo si respondes que sí), un equipo administrado por una organización y una copia de windows-tuneup que otras cuentas pueden cambiar. Con `-Yes` los muestra y sigue; con `-Json` van en el arreglo `preflight`.
  Before applying it warns, without stopping, about a pending restart, less than 2 GB free on the system drive, System Restore turned off (and offers to turn it on first, only if you answer yes), a machine managed by an organization and a copy of windows-tuneup that other accounts can change. With `-Yes` it shows them and goes on; with `-Json` they go in the `preflight` array.
- Ctrl+C mientras aplica termina el ajuste en curso y deja el resto sin aplicar: el resumen lo dice, el resultado se guarda y el código de salida es 2 (o 1 si todavía no había tocado nada). Si Ctrl+C llega mientras corre un programa externo (DISM, winget), detiene todo en el acto; el resultado se guarda igual y el diario, escrito antes de cada cambio, permite deshacer el ajuste cortado.
  Ctrl+C while applying finishes the tweak in progress and leaves the rest unapplied: the summary says so, the result is saved and the exit code is 2 (or 1 if nothing had been touched yet). If Ctrl+C arrives while an external program runs (DISM, winget), everything stops at once; the result is still saved and the journal, written before each change, lets you undo the tweak that was cut.
- Cada corrida guarda `transcript.log` con lo que se vio en pantalla (lo pedido, el plan, los avisos, los resultados y cada deshacer posterior), escrito por la herramienta: sin nombres de cuenta ni de equipo ni la línea de comandos.
  Every run keeps `transcript.log` with what was shown (what was asked for, the plan, the warnings, the results and every later undo), written by the tool itself: no account or machine names and no command line.
- `-Status -Reapply` (o el menú) vuelve a aplicar, como una corrida nueva, los ajustes que Windows revirtió (`drift`), con la definición del catálogo actual. Un ajuste que pregunta antes o de riesgo alto no se vuelve a aplicar solo: queda omitido, con su motivo (el menú pregunta por cada uno).
  `-Status -Reapply` (or the menu) applies again, as a new run, the tweaks that Windows reverted (`drift`), with the definition of the current catalog. A tweak that asks first or has high risk is not applied again on its own: it stays out, with its reason (the menu asks about each one).
- Si `-Undo` no puede restaurar un ajuste, muestra cómo hacerlo a mano con líneas de PowerShell (`New-ItemProperty`, `Set-Service`, `Enable-ScheduledTask`, `Add-WindowsCapability`, `powercfg.exe` o `winget`); con `-Json`, en `results[].manual`.
  When `-Undo` cannot restore a tweak, it shows how to do it by hand with PowerShell lines (`New-ItemProperty`, `Set-Service`, `Enable-ScheduledTask`, `Add-WindowsCapability`, `powercfg.exe` or `winget`); with `-Json`, in `results[].manual`.
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
| Aplicar / Apply | Todo hecho (o nada que aplicar). / Everything done (or nothing to apply). | No todo se completó: algún ajuste parcial, fallido o sin efecto, Ctrl+C después de algún cambio, o no se pudo guardar un respaldo o `result.json`; leer el resumen. / Not everything completed: some tweak was partial, failed or had no effect, Ctrl+C after some change, or a backup or `result.json` could not be saved; read the summary. | Abortado antes de cambiar nada (respuesta negativa, sin administrador, argumentos o catálogo inválidos, ningún respaldo se pudo escribir, Ctrl+C antes del primer ajuste). / Aborted before changing anything (answered no, not administrator, invalid arguments or catalog, no backup could be written, Ctrl+C before the first tweak). |
| `-Undo` | Todo restaurado (lo ya deshecho no cuenta). / Everything restored (what was already undone does not count). | Restauración parcial: quedan fallos o ajustes de otro usuario. / Partly restored: failures or another user's tweaks remain. | Nada se restauró, o no se pudo empezar. / Nothing was restored, or it could not start. |
| `-Status` | Siempre. / Always. | | Error al leer. / Read error. |
| `-Health` | Sin problemas (`recommendation` = `none`). / No problems (`recommendation` = `none`). | Quedan problemas o no se pudo confirmar el resultado. / Problems remain or the result could not be confirmed. | Sin administrador. / Not administrator. |
| `-Measure` | Medición guardada. / Measurement saved. | | No pudo medir o guardar, o `-Compare` no encontró la medición. / It could not measure or save, or `-Compare` did not find the measurement. |
| Menú / Menu | Al salir. / On exit. | | |

Un parámetro desconocido o un `-Lang` fuera de `es`/`en` lo informa PowerShell por la salida de errores, sin documento JSON, con código 1.
An unknown parameter or a `-Lang` other than `es`/`en` is reported by PowerShell on the error stream, without a JSON document, with code 1.

## Salida JSON / JSON output

Con `-Json` la salida estándar es un único documento JSON en ASCII (todo carácter no ASCII va como `\uXXXX`, así la página de códigos de la consola no lo altera), con claves en camelCase. Los avisos no se escriben sueltos: van dentro del documento, en el arreglo `warnings`. Para aplicar sin preguntar usar `-Yes`; con `-Json` y sin `-Yes` un plan con cambios termina con un error en JSON (código 1).
With `-Json` standard output is a single ASCII JSON document (every non-ASCII character is written as `\uXXXX`, so the console code page cannot alter it), with camelCase keys. Warnings are not printed loose: they go inside the document, in the `warnings` array. To apply without asking use `-Yes`; with `-Json` and without `-Yes` a plan with changes ends with a JSON error (code 1).

Todos los documentos llevan `schemaVersion` (hoy `1`), `command`, `toolVersion` y `warnings`. Cada campo está descrito en [docs/json-contract.md](docs/json-contract.md) (en inglés; una prueba lo mantiene al día):
Every document carries `schemaVersion` (currently `1`), `command`, `toolVersion` and `warnings`. Every field is described in [docs/json-contract.md](docs/json-contract.md) (kept up to date by a test):

| `command` | Campos principales / Main fields |
|---|---|
| `plan` | `source` (`profiles`, `reapply`), `environment`, `requiresAdmin` (hay cambios de sistema / there are system changes), `preflight` (`id`, `message`), `items` (`id`, `title`, `risk`, `scope`, `action`, `reason`, `rebootRequired`, `signOutRequired`, `requires`), `summary` (`apply`, `skip`) |
| `apply` | `source`, `runId`, `runDir`, `finishedAt`, `environment`, `preflight`, `restorePoint`, `rebootRequired`, `signOutRequired`, `interrupted`, `summary` (`applied`, `partial`, `notApplied`, `failed`, `skipped`, `refused`, `journalErrors`, `interrupted`), `results` (`id`, `title`, `status`, `reason`, `error`, `detail`, `rebootRequired`, `signOutRequired`, `refused`) |
| `status` | `items` (`id`, `title`, `status`, `runId`) |
| `undo` | `runId`, `rebootRequired`, `signOutRequired`, `results` (`id`, `title`, `status`, `reason`, `error`, `detail`, `rebootRequired`, `signOutRequired`, `manual`), `summary` (`restored`, `failed`, `skipped`) |
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
- Restaurar sistema solo se puede leer como administrador: sin elevar no hay aviso, y nunca se activa sin preguntar (tampoco con `-Yes`).
  System Restore can only be read as administrator: without elevation there is no warning, and it is never turned on without asking (not even with `-Yes`).
- Los mensajes de `install.ps1` están solo en inglés: corre antes de que existan los textos de la herramienta.
  The messages of `install.ps1` are in English only: it runs before the texts of the tool exist.
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

Las pruebas usan Pester 5 y el lint PSScriptAnalyzer (sobre `tuneup.ps1`, `install.ps1`, `engine/`, `actions/`, `build/` y `tests/sandbox/`). Las pruebas no instalan, quitan ni cambian nada real del sistema: Appx, DISM, winget, powercfg, sfc, el visor de eventos y el desinstalador de OneDrive se simulan. Solo escriben archivos temporales y la clave de prueba `HKCU:\Software\windows-tuneup-test` (se borra al terminar), hacen consultas de solo lectura (CIM, eventos y la consulta de capacidades de la GPU) y ejecutan `cmd.exe` con comandos inofensivos, `reg.exe` sobre esa clave de prueba y PowerShell en consolas ocultas (las pruebas de Ctrl+C) y en procesos hijos (las líneas de deshacer a mano, sobre esa clave).
Tests use Pester 5 and lint uses PSScriptAnalyzer (over `tuneup.ps1`, `install.ps1`, `engine/`, `actions/`, `build/` and `tests/sandbox/`). Tests never install, remove or change anything real on the system: Appx, DISM, winget, powercfg, sfc, the event log and the OneDrive uninstaller are mocked. They only write temporary files and the test key `HKCU:\Software\windows-tuneup-test` (removed when they finish), run read-only queries (CIM, events and the GPU capability query) and run `cmd.exe` with harmless commands, `reg.exe` on that test key and PowerShell in hidden consoles (the Ctrl+C tests) and in child processes (the manual-restore lines, on that key).

Algunas pruebas solo corren sin elevar (`-Skip:$Elevated`). Como los runners de GitHub son administradores, CI corre la suite otra vez con `build/test-standard-user.ps1`, que la lanza con `runas /trustlevel:0x20000` (la misma cuenta con un token de usuario estándar). En tu equipo, `build/test.ps1` desde un PowerShell sin elevar ya las corre.
Some tests only run without elevation (`-Skip:$Elevated`). Since GitHub runners are administrators, CI runs the suite again with `build/test-standard-user.ps1`, which starts it with `runas /trustlevel:0x20000` (the same account with a standard-user token). On your machine, `build/test.ps1` from a PowerShell that is not elevated already runs them.

`docs/{es,en}/catalog.md` se genera con `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1` a partir del catálogo, los perfiles y `catalog/notes/excluded.json`; una prueba falla si no se regeneró después de cambiar el catálogo.
`docs/{es,en}/catalog.md` is generated with `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1` from the catalog, the profiles and `catalog/notes/excluded.json`; a test fails if it was not regenerated after changing the catalog.

`-StateRoot`, `-ActionsPath`, `-CatalogPath` y `-ProfilesPath` son solo para pruebas y desarrollo. `-StateRoot <carpeta>` guarda corridas y mediciones en otra carpeta, sin la protección de la carpeta de máquina (no usarlo en un equipo real). `-ActionsPath <carpeta>` carga scripts de acción de otra carpeta, que corren con tus permisos (con administrador si estás elevado): usar solo una carpeta de confianza.
`-StateRoot`, `-ActionsPath`, `-CatalogPath` and `-ProfilesPath` are for testing and development only. `-StateRoot <folder>` keeps runs and measurements in another folder, without the protection of the machine folder (do not use it on a real machine). `-ActionsPath <folder>` loads action scripts from another folder, which run with your rights (administrator when elevated): use only a folder you trust.

### Prueba de extremo a extremo y releases / End-to-end test and releases

`powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1` abre Windows Sandbox (Windows Pro, Enterprise o Education con la característica "Windows Sandbox" activada), con el repositorio en solo lectura, y corre en él cada perfil: aplicar, `-Status`, aplicar otra vez (nada que hacer), `-Undo last` y comparar el sistema con el de antes (registro de los ajustes, servicios, tareas y apps), más una prueba de `-Status -Reapply`. Deja `e2e-report.md` en la carpeta que indica. Las apps de la Store y OneDrive se dejan fuera (el sandbox no tiene Store ni winget): los cubre [docs/es/vm-checklist.md](docs/es/vm-checklist.md).
`powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1` opens Windows Sandbox (Windows Pro, Enterprise or Education with the "Windows Sandbox" feature turned on), with the repository read-only, and runs every profile in it: apply, `-Status`, apply again (nothing to do), `-Undo last` and compare the system with how it was (registry of the tweaks, services, tasks and apps), plus a `-Status -Reapply` check. It leaves `e2e-report.md` in the folder it names. Store apps and OneDrive are left out (the sandbox has no Store and no winget): [docs/en/vm-checklist.md](docs/en/vm-checklist.md) covers them.

Una etiqueta `v<versión>` (igual a la de `engine/Version.ps1`) hace que GitHub Actions corra el lint y las pruebas, arme con `build/package.ps1` el zip, `install.ps1` y `SHA256SUMS`, y deje un borrador de release. Se publica a mano, después de adjuntar `e2e-report.md`, la lista de la máquina virtual y la medición de Liviano frente a LTSC.
A tag `v<version>` (equal to the one in `engine/Version.ps1`) makes GitHub Actions run lint and tests, build the zip, `install.ps1` and `SHA256SUMS` with `build/package.ps1`, and leave a draft release. It is published by hand, after attaching `e2e-report.md`, the virtual machine checklist and the Lite versus LTSC measurement.

Licencia / License: MIT
````

- [ ] **Step 2: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 3: Suite completa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Tests Passed: 1178, Failed: 0, Skipped: 1`). Los saltos son pruebas que corren solo elevadas o solo sin elevar.

- [ ] **Step 4: Las páginas generadas siguen al día**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1` y luego `git status --short docs`
Expected: sin cambios en `docs/es/catalog.md` ni `docs/en/catalog.md`.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: README del Plan 4: menú, instalación, avisos y releases"
```

---

### Task 17: Antes de etiquetar `v0.1.0` (preguntar al usuario)

**Files:** ninguno.

Publicar es irreversible para quien ya descargó: **no se etiqueta ni se empuja nada sin un "sí" explícito del usuario en esta conversación.** Esta tarea junta la evidencia y hace la pregunta.

- [ ] **Step 1: Integrar y ver CI**

Con el permiso del usuario (empujar y abrir un PR también publica), empujar la rama de este plan y abrir su PR hacia `main`, o usar el que indique el usuario. Expected: los dos trabajos de `ci.yml` en verde. Si `test-standard-user` falla porque `runas /trustlevel` no arranca en el runner (mensaje "did not start within 2 minutes" o "still elevated"), aplicar la salida prevista en la Task 13 (quitar el trabajo y dejar el script para uso local) en un commit `ci: sin el trabajo de usuario estándar (runas no corre en el runner)` y avisar al usuario.

- [ ] **Step 2: Extremo a extremo**

En un equipo con Windows Sandbox: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\sandbox\Start-E2E.ps1`. Expected: `e2e-report.md` con `PASS` en los ocho perfiles y en la prueba de reaplicar. Un `FAIL` se corrige antes de seguir (el informe dice qué ajuste quedó distinto).

- [ ] **Step 3: Máquina virtual y medición**

Hacer `docs/es/vm-checklist.md` en una máquina virtual con Windows 11 Pro (con la versión candidata armada por `build/package.ps1`) y la medición de `docs/es/measuring.md`. Guardar la lista marcada y los reportes.

- [ ] **Step 4: Preguntar**

Mostrar al usuario: el resultado de CI, `e2e-report.md`, la lista de la máquina virtual y la medición, y preguntar textualmente: "¿Etiqueto `v0.1.0` en `main` y lo empujo? El workflow dejará un borrador de release con el zip, `install.ps1` y `SHA256SUMS`; publicarlo será otro paso tuyo." **Si la respuesta no es un sí explícito, terminar aquí.**

- [ ] **Step 5: Solo con el sí del usuario**

```bash
git switch main
git pull
git tag -a v0.1.0 -m "windows-tuneup 0.1.0"
git push origin v0.1.0
```

Expected: el workflow `release` en verde y un borrador `windows-tuneup v0.1.0` con `windows-tuneup-0.1.0.zip`, `install.ps1` y `SHA256SUMS`. Adjuntar al borrador `e2e-report.md`, la lista de la máquina virtual y el reporte de medición, y avisar al usuario que el borrador está listo para que lo publique (o que pida publicarlo). Después de publicar, comprobar desde una consola nueva como administrador `irm https://github.com/edgarlugo/windows-tuneup/releases/download/v0.1.0/install.ps1 | iex` (instala en `Program Files` y dice `SHA256 checked`). En el repositorio, recomendar al usuario activar las releases inmutables de GitHub (Settings > General > Releases), así nadie puede reemplazar los archivos de una release publicada.

---

## Qué se probó y qué no

Probado en la copia de `db1bcf0` (Windows 11 Pro 26H2, build 26300, sin elevar), además de la suite:

- **Ctrl+C, los dos caminos**, en consolas ocultas nuevas: la tecla escrita en la entrada (`WriteConsoleInput`) con la trampa activa llega como `C` + `Control` y PowerShell no se detiene; `cmd.exe /c` deja `TreatControlCAsInput` en `False` (de ahí la reactivación en cada revisión); la señal (`GenerateConsoleCtrlEvent`) detiene la tubería sin pasar por `catch`, el `finally` sí corre, puede escribir archivos y al host pero no a la salida, y `exit 2` dentro del `finally` fija el código. Las tres pruebas de `tests/Interrupt.Tests.ps1` lo repiten con el motor: el ajuste en curso termina, el resto queda `interrupted`, código 2, y por el camino de la señal `result.json` queda guardado y `-Undo` restaura el ajuste cortado.
- **El menú con respuestas guionadas** (13 pruebas en el proceso) y **por la entrada estándar** de `powershell -File` (dos pruebas de `tests/Cli.Tests.ps1`): `Read-Host` lee líneas redirigidas y devuelve `$null` al final.
- **`install.ps1`**: con el zip correcto instala y la copia instalada corre; con un SHA256 equivocado, sin versión o con una entrada `../` no instala nada; por `iex` (con la fuente cambiada a una carpeta local) aplica los valores del `param()` y no deja `$ErrorActionPreference` ni variables en la sesión.
- **El zip**: 70 archivos al probarlo (con los de este plan, 72), solo de las carpetas previstas, el mismo SHA256 en dos armados seguidos.
- **`runas /trustlevel:0x20000`** desde un proceso sin elevar con `-Restricted`: arranca, el hijo no está elevado, escribe salida y código.
- **Lecturas reales de solo lectura**: el GUID del volumen del sistema, el espacio libre, `Test-TuneupTrustedLocation` (falso en `Documents`) y Restaurar sistema sin elevar (`unknown`: `SPP\Clients` da `SecurityException`). Las líneas de PowerShell de deshacer a mano, ejecutadas en un proceso hijo sobre la clave de prueba.
- **Coherencia del plan**: aplicar las tareas en orden sobre `db1bcf0` da exactamente los archivos de la copia probada (comparación archivo por archivo; los `.json` de textos por contenido). Esa copia rearmada desde el plan pasó la suite completa (`Tests Passed: 1178, Failed: 0, Skipped: 1`) y el lint, y los estados intermedios (después de las Tasks 2 a 15) pasaron el lint y, de la Task 3 a la 10, los archivos de prueba de cada tarea con los recuentos que dice cada paso "Expected".

Sin verificar al escribir el plan:

- **Elevado no se corrió nada.** En particular `Get-TuneupSystemRestoreState` con `SPP\Clients` legible (la Task 7, Step 7, lo compara con Propiedades del sistema), `Enable-ComputerRestore`, el aviso `untrusted-location` real, `install.ps1` instalando en `Program Files` y las pruebas que solo corren elevadas (CI las corre).
- **`runas /trustlevel` en un runner de GitHub** (Task 13: si no arranca, se quita el trabajo).
- **Windows Sandbox**: no está activado en este equipo; `Start-E2E.ps1` e `Invoke-E2E.ps1` no corrieron (Task 14, Step 7, y Task 17). Tampoco que Windows Sandbox acepte la plantilla `.wsb` tal cual (es XML válido y sigue el esquema documentado: `MappedFolder` con `SandboxFolder` y `ReadOnly`, `LogonCommand`, `MemoryInMB`).
- **El workflow de release y `gh release create --draft --verify-tag`**: solo corre con una etiqueta (Task 17, con permiso del usuario).
- **Una Ctrl+C con el teclado real** (la prueba escribe la tecla en la entrada de la consola, que es lo que hace el teclado, pero no hay una persona presionándola) y el menú en Windows Terminal (la lista de la VM lo pide).

## Arrastres de las revisiones

- `signOutRequired` en los resultados de `-Undo` (sección 11, 4e): Task 4.
- La sección 7 de la especificación (instrucción manual al deshacer, reaplicar la deriva) y la fila de `transcript.log` de la sección 5: Tasks 1, 4, 6 y 8.
- Notas del contrato JSON para el Plan 5: `docs/json-contract.md` (Task 15).
- Siguen como ideas (sección 11, 4f; sección 12, 13): detectar Windows Insider y Defender for Endpoint, tipos de registro con varios valores, acciones de usuario, PSScriptAnalyzer sobre las pruebas, mensajes de `install.ps1` en español.

## Autorrevisión

**Cobertura del pedido:**

| Pedido | Dónde |
|---|---|
| 1. Extraer la orquestación a funciones del motor compartidas por la línea de comandos y el menú, sin cambiar el comportamiento | Task 3 (`tests/Cli.Tests.ps1` sin cambios y en verde; `tests/Commands.Tests.ps1`) |
| 2. Menú: perfiles con descripción y administrador, plan con riesgo, motivos y `requiresAdmin`, preguntas `ask` (sí/no/todos/ninguno) con `-Interactive`, riesgo alto detrás de una confirmación extra, Estado con reaplicar, Deshacer (corrida o ajuste), Salud, Medir/Comparar, Salir; solo teclado, consola y Windows Terminal, sin módulos externos, `Io` inyectable, sin significado solo por color | Tasks 9 y 10 |
| 3. Avisos antes de aplicar con confirmación; reglas con `-Json`/`-Yes` (ninguno bloquea) | Task 7 |
| 4. Ctrl+C limpio, probado | Task 5 |
| 5. `transcript.log` sin secretos y con las reglas de confianza | Task 6 |
| 6. `-Status -Reapply` y deshacer a mano | Tasks 8 y 4 |
| 7. Release en `v*`: zip solo con lo de ejecución y documentos, `SHA256SUMS`, notas, `install.ps1` fijado a una versión que verifica el SHA256, `Program Files`, sección del README; preguntar antes de etiquetar | Tasks 11, 12, 16 y 17 |
| 8. CI sin elevar | Task 13 |
| 9. Windows Sandbox: repo en solo lectura, cada perfil con `-Yes`, `-Status`, reaplicar con 0 cambios, deshacer, diferencia cero, reporte; lista de la VM | Tasks 14 y 15 |
| 10. Arrastres: `signOutRequired` al deshacer, README, contrato JSON | Tasks 4, 15 y 16 |

**Búsqueda de marcadores pendientes:** no quedan "TBD", "TODO", "similar a la Task N" ni pasos sin código. Cada archivo nuevo va completo; cada cambio a un archivo existente da el bloque exacto a reemplazar, la función completa nueva o el punto exacto donde agregar.

**Consistencia de nombres:**

- Contexto: `New-TuneupContext` (`Json`, `StateRoot`, `CatalogPath`, `ProfilesPath`, `Force`, `Warnings`, `Environment`, `ScriptRoot`, `Io`, `InputEnded`, `ExitCode`, `Result`), `Invoke-TuneupContextStep`, `Write-TuneupCommandError`, `Get-TuneupContextEnvironment`, `Get-TuneupUnsupportedMessage`, `Import-TuneupContextDefinition` (`Catalog`, `Profiles`, `Problems`), `New-TuneupContextPlan`, `New-TuneupApplyRequest` (`Source` = `profiles` | `reapply`).
- Comandos: `Invoke-TuneupCli`, `Invoke-TuneupApplyCommand`, `Invoke-TuneupPlannedApply`, `Invoke-TuneupStatusCommand` (`-Reapply`, `-PlanOnly`, `-Yes`), `Invoke-TuneupReapply`, `Invoke-TuneupUndoCommand`, `Invoke-TuneupHealthCommand` (`-Previous`), `Invoke-TuneupMeasureCommand`, `Save-TuneupStoppedApply`, `Save-TuneupApplyTranscript`, `Save-TuneupUndoTranscript`.
- Privacidad y confianza: `Hide-TuneupPersonalData` (`%USERPROFILE%`, `%USERNAME%`), `Write-TuneupRunResult`, `Test-TuneupTrustedEntry`.
- Campos JSON nuevos: `toolVersion` (todos), `preflight[].id`/`message` (`plan`, `apply`), `source` (`plan`, `apply`), `interrupted` y `summary.interrupted` (`apply`), `signOutRequired` y `results[].manual`/`signOutRequired` (`undo`). Todos en `docs/json-contract.md`, que la prueba mantiene al día.
- Motivos nuevos con texto en los dos idiomas: `interrupted`, `aborted`, `declined`. Ids de avisos: `pending-reboot`, `low-disk`, `restore-disabled`, `restore-blocked`, `managed-device`, `untrusted-location` (claves `preflight.<id>`).
- Marcadores del instalador: `'__TUNEUP_VERSION__'` y `'__TUNEUP_ZIP_SHA256__'` (con las comillas) en `install.ps1`, que `build/package.ps1` reemplaza y exige.

**Correcciones hechas al ejecutar el plan en la copia:** el ayudante que escribía el error del catálogo y devolvía `$null` mezclaba el documento JSON con su valor de retorno (ahora devuelve `Problems`); PSScriptAnalyzer marcaba parámetros usados solo dentro de un bloque de paso (tablas de argumentos) y un `-WhatIf` propio (`-PlanOnly`); `Get-ItemProperty` devuelve un DWORD como `UInt32`, por eso la prueba de `reg.exe` lee con `GetValue`; la prueba de cobertura tomaba `transcript.log` por una clave; `[pscustomobject]` no tiene `.Count` en Windows PowerShell 5.1, por eso las pruebas envuelven con `@()`; con `$ErrorActionPreference = 'Stop'` la salida de error de `install.ps1` se volvía una excepción en las pruebas (se baja a `Continue` solo ahí); la prueba de reaplicar con un ajuste que ya no está en el catálogo también tiene que quitar el perfil que lo nombra; `build/package.ps1` fallaba fuera de un checkout de git (la salida de error de git con `Stop`), lo que mostró la copia rearmada desde el plan; un texto de `i18n` escrito a mano con `.\tuneup.ps1` quedó con un tabulador (`\t` en JSON) y lo detectó la comparación del plan con la copia: en los `.json` de textos la barra se escribe doble (`.\\tuneup.ps1`), como en `run.saved`.
