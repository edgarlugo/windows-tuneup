# windows-tuneup — Plan 3: catálogo real, perfiles, lista negra y documentación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar el catálogo de ejemplo por el catálogo real (166 ajustes en 12 archivos, cada uno con fuente y verificado en solo lectura), con tres acciones reales (`onedrive`, `gaming-hags`, `gaming-windowed-optimizations`), los ocho perfiles de la especificación, la lista negra, las guías por objetivo, el método de medición contra LTSC y un catálogo documentado que se genera solo; más los cinco cambios pequeños del motor que el catálogo necesita (`storeId` de 14 caracteres, `requires`, `ac`/`dc` opcionales en `powercfg`, `Set` que se niega sin cambiar nada y `signOutRequired`).

**Architecture:** El motor no cambia de forma: los cambios del motor (Tasks 2 a 6) son extensiones de los validadores (`Test-<Tipo>TweakDefinition` y `Test-TuneupTweak`), del planificador (un motivo nuevo), del manejador `powercfg`, de `New-TuneupOutcome` y del ejecutor. El catálogo vive en `catalog/<categoría>.json` (el prefijo del id es el nombre del archivo) y los perfiles en `profiles/<id>.json`. Las acciones son scripts de `actions/` que el cargador analiza sin ejecutar; cada una lee el sistema por ayudantes `<Verbo>-<Pascal>ActionHelper<Nombre>` que las pruebas simulan con `Mock -ModuleName Tuneup`. La calidad del catálogo se fija con pruebas propias (`tests/CatalogQuality.Tests.ps1`, `tests/CatalogContent.Tests.ps1`) y la documentación del catálogo se genera con `build/catalog-doc.ps1` (una prueba exige que esté al día).

**Tech Stack:** Windows PowerShell 5.1, Pester 5.9.1, PSScriptAnalyzer 1.25, GitHub Actions (`windows-latest`).

**Especificación:** `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md` (la Task 1 le agrega la sección 11, "Catálogo (Plan 3)").

**Planes anteriores:** `docs/superpowers/plans/2026-09-30-plan-1-motor-nucleo.md` y `docs/superpowers/plans/2026-09-30-plan-2-manejadores-salud-medicion.md`. Como dicen sus encabezados, **los archivos del repositorio son la fuente de verdad**; este plan se escribió leyendo el código de `main` después de mergear el Plan 2 (`6d73e65`, 742 pruebas).

**Evidencia:** los ajustes salen de cinco informes de investigación (privacidad y telemetría; interfaz, anuncios e IA; rendimiento, servicios y tareas; juegos, desarrollo y energía; apps y OneDrive), escritos el 2026-10-01 en un Windows 11 Pro 26H2 (build 26300.9457) sin elevar y en solo lectura. Este plan ya resuelve sus preguntas abiertas con las decisiones aprobadas (sección "Decisiones"). Todo el código y el JSON de este plan se ejecutó en una copia del repositorio antes de escribirlo: la suite completa queda en **877 pruebas, 0 fallos** y PSScriptAnalyzer sin hallazgos. Los estados que cada tarea de catálogo muestra como "esperado" son los que dio ese equipo; en otro equipo cambian, lo que importa es que ninguna línea diga `ERROR`.

---

## Convenciones de este plan

Se heredan las de los Planes 1 y 2:

- **Código, comentarios, identificadores y errores para desarrolladores en inglés.** Los textos para el usuario van en `i18n/es.json` e `i18n/en.json` (mismas claves y marcadores `{n}`; lo verifica `tests/I18n.Tests.ps1`), y los del catálogo en el propio JSON (`title` y `why` en `es` y `en`).
- **Todo `.ps1`/`.psm1`/`.psd1` en ASCII** (lo verifica `tests/Repo.Tests.ps1`): por eso las etiquetas en español del generador de documentación están en `build/catalog-doc.labels.json` y no en el script, y las acciones no tienen acentos. Los `.json` y `.md` van en UTF-8 sin BOM y con fin de línea CRLF (`.gitattributes`).
- **Las funciones emiten elementos; quien llama envuelve con `@()`.** Nunca `return ,$array`. **`ConvertTo-Json` siempre con `-Depth 10`.** **Comparaciones con null: `$null -eq $x`.**
- **Los fallos se lanzan, nunca se tragan.** Un `catch` solo existe para convertir el error en otro más claro, en un resultado `partial`/`failed`/`skipped` explícito o en un aviso.
- Pruebas con **Pester 5.9.1** en Windows PowerShell 5.1: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 [-Path tests/X.Tests.ps1]`. `BeforeEach`/`AfterEach` solo dentro de un `Describe`.
- **Las pruebas nunca modifican el sistema real.** Appx, DISM, winget, powercfg, sfc, el visor de eventos y el desinstalador de OneDrive se simulan con `Mock -ModuleName Tuneup`. El registro real solo se escribe bajo `HKCU:\Software\windows-tuneup-test`. Las acciones leen y escriben el sistema por ayudantes que las pruebas simulan (por ejemplo `Get-GamingHagsActionHelperValue` devuelve en la prueba una ruta bajo la clave de prueba). La única consulta real nueva es de solo lectura: la capacidad de la GPU (`D3DKMTQueryAdapterInfo`).
- Lint: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`. Verbo aprobado y sustantivo en singular. `PSReviewUnusedParameter` está activo: cada función de una acción usa su `$Tweak` (por eso los ayudantes reciben `-Tweak`).
- Commits **sin** `Co-Authored-By`. **Nunca `git add -A` ni `git add .`**: cada paso de commit nombra sus archivos.
- Directorio del repo: `C:\Users\Edgar\Documents\GitHub\windows-tuneup` (comandos relativos a esa raíz, rama `main`).

Nuevas para este plan:

- **Verificación de solo lectura de cada categoría.** Cada tarea de catálogo termina con este bloque, que se pega en una ventana de Windows PowerShell 5.1 abierta en la raíz del repo (sin elevar). Lee el estado de cada ajuste del archivo con el manejador real y no cambia nada; `<archivo>` es el archivo de la tarea:

  ```powershell
  Import-Module .\engine\Tuneup.psm1 -Force
  Import-TuneupCatalog -Path .\catalog | Where-Object { $_.sourceFile -eq '<archivo>' } | ForEach-Object {
      $state = if (Test-TuneupHandlerReadNeedsAdmin -Tweak $_) { 'needs-admin' } else { try { Test-TuneupState -Tweak $_ } catch { "ERROR $($_.Exception.Message)" } }
      '{0,-45} {1}' -f $_.id, $state
  }
  ```

  Ninguna línea puede decir `ERROR`: un `ERROR` es una ruta, un servicio o una tarea mal escrita, o un manejador que no sabe leer ese valor. `not-present` es válido (la tarea o el servicio no existe en ese build; el plan lo omitirá con su motivo). `needs-admin` es lo esperado para `appx` sin elevar.
- **Formato de los archivos del catálogo.** Un ajuste por bloque, con los campos en este orden: `id`, `title`, `why`, `risk`, `ask`, `os`, `type`, `scope`, `set`, `requires` (opcional), `rebootRequired`, `signOutRequired` (opcional), `sources`. Los bloques de este plan son el contenido completo del archivo.
- **Pruebas de contenido por categoría.** `tests/CatalogContent.Tests.ps1` fija, para cada archivo, la lista exacta de ids en orden. Es la prueba que falla primero en cada tarea de catálogo (el archivo todavía no tiene esos ids).

## Decisiones

Aprobadas antes de escribir el plan. La Task 1 las copia, resumidas, como sección 11 de la especificación.

| # | Decisión | Dónde |
|---|---|---|
| 1 | `base` solo con ajustes `scope: user` (sin administrador); `services.retail-demo` pasa a `lite`; las directivas de Edge no van en `base` | Task 7 (base) y Task 22 (perfiles) |
| 2 | Ediciones según Microsoft: `DisableWindowsConsumerFeatures` y `DisableConsumerAccountStateContent` solo Enterprise/Education (`HideRecommendedSection`: el CSP de Start lo lista para Pro, Enterprise y Education); `AllowTelemetry = 1` en `Policies\...\DataCollection` para Pro/Enterprise/Education; `privacy.diagnostic-data-off` (`0`) Enterprise/Education de riesgo alto; DiagTrack `medium` con `ask`; rutas no documentadas fuera | Tasks 8, 9 y 13 |
| 3 | Solo apps cuyo deshacer funciona; `storeId` acepta `XP` + 12; Teams nuevo incluido (nombre Appx y `storeId` verificados); `ask` para OneDrive, Teams, Outlook nuevo, Vínculo móvil, Copilot, Reproductor multimedia, Asistencia rápida, Obtener ayuda y Seguridad familiar | Tasks 2 y 21 |
| 4a | `storeId` de 14 caracteres | Task 2 |
| 4b | `requires` con `battery`/`no-battery` y motivo `not-applicable-hardware` | Task 3 |
| 4c | `ac`/`dc` opcionales en `powercfg` `setting` | Task 4 |
| 4d | `New-TuneupOutcome -Refused` → `skipped` con motivo, sin deshacer | Task 5 |
| 4e | `signOutRequired` en el catálogo, en cada resultado y en el reporte | Task 6 |
| 4f | Sin tipo multi-valor, `Binary`, `(default)`, acciones de usuario ni precondiciones: quedan como ideas en la especificación y en `catalog/notes/excluded.json` | Tasks 1 y 24 |
| 5 | Acciones `onedrive`, `gaming-hags`, `gaming-windowed-optimizations`; `power-mode-overlay` y `dev-defender-performance-mode` quedan fuera (ver "Acciones descartadas") | Tasks 16, 17 y 20 |
| 6 | Ocho perfiles con alias; `gaming` conserva Xbox; `work` conserva Teams/Outlook/OneDrive; nada toca WSL/Hyper-V/`SharedAccess`; `high` solo con `-Include` | Task 22 |
| 7 | `docs/{es,en}/blacklist.md`, `profiles.md`, `catalog.md` generado por `build/catalog-doc.ps1` con la sección "No incluido" desde `catalog/notes/excluded.json` | Tasks 23, 24 y 26 |
| 8 | Pruebas de calidad del catálogo | Tasks 7, 8 a 21 y 22 |
| 9 | `docs/{es,en}/measuring.md` (método manual contra LTSC 2024) | Task 25 |
| 10 | README y sección 11 de la especificación | Tasks 1 y 27 |
| 11 | Verificación de solo lectura de cada ajuste en este equipo | Bloque final de las Tasks 8 a 21 |

### Decisiones tomadas al escribir el plan (además de la lista)

- **Un dueño por valor de registro.** Los informes repetían algunos valores con dos ids (`DisableSearchBoxSuggestions` como `privacy.bing-search-off` y `ads.search-box-suggestions-off`; transparencia y animación de minimizar en `ui.*` y `performance.*`; inicio acelerado y segundo plano de Edge en `edge.*` y `performance.*`; la red en suspensión como `power.modern-standby-network-off-battery` y `power.standby-network-off-battery`; la app Copilot como `ai.copilot-app-remove` y `apps.copilot`; archivos ocultos y "Finalizar tarea" en `dev.*` y `ui.*`). Queda un solo id por valor (`ads.search-box-suggestions-off`, `ui.transparency-off`, `ui.window-animations-off`, `edge.startup-boost-off`, `edge.background-mode-off`, `power.standby-network-off-battery`, `apps.copilot`, `ui.show-hidden-files`, `ui.taskbar-end-task`) y una prueba impide que vuelva a pasar (salvo la pareja documentada de `AllowTelemetry`).
- **Edge en su archivo.** Las tres directivas de Edge del informe de privacidad (`privacy.edge-*`) pasan a `edge.json` como `edge.personalization-reporting-off`, `edge.diagnostic-data-required` (`DiagnosticData = 1`, solo datos requeridos, riesgo bajo) y `edge.feedback-off`; todas las de Edge declaran las cuatro ediciones (la documentación de Edge no las limita por edición). Inicio acelerado y segundo plano usan la clave `Edge\Recommended` (el usuario puede cambiarlas en `edge://settings`).
- **`requires` en energía:** `power.high-performance-plan` lleva `no-battery` y `power.standby-network-off-battery` lleva `battery` (y queda en Pro/Enterprise/Education, como documenta el CSP de Power). `power.usb-selective-suspend-ac-off` solo fija `ac: 0` gracias a la Task 4.
- **`signOutRequired`** en lo que se nota al volver a iniciar sesión: animaciones y sombras del Explorador, Aero Peek, Widgets, el botón de Copilot, la aceleración del mouse (antes marcada como reinicio) y las plantillas de servicios por usuario (`CDPUserSvc`, `PimIndexMaintenanceSvc`, `UnistoreSvc`, `UserDataSvc`, antes marcadas como reinicio).
- **Recall, riesgo alto:** `ai.recall-snapshots-off` y `ai.recall-unavailable` borran capturas de Recall que `deshacer` no puede devolver: `high` (solo con `-Include`, ningún perfil los incluye), con `ask: true` y el texto lo dice.
- **Revisión del catálogo (Tasks 7 a 21):** `tasks.mare-backup` es `medium` con `ask` (también alimenta el evaluador de compatibilidad); `apps.xbox-gaming-app`, `apps.xbox-game-bar`, `apps.alarms-clock` y `apps.mail-calendar` preguntan; los servicios de Xbox (`XblGameSave`, `XblAuthManager`, `XboxNetApiSvc`) salen del catálogo (ya vienen en manual y deshabilitarlos rompe el inicio de sesión de Xbox); `performance.background-apps-off` pregunta y queda solo en Windows 10; `ads.settings-home-365` solo Enterprise/Education; `ui.news-interests-win10` sin Home; `ai.notepad-ai-off` incluye Home (la documentación del Bloc de notas no limita ediciones).
- **Una directiva bajo HKCU exige administrador.** El ACL de `HKCU\Software\Policies` y de `...\CurrentVersion\Policies` solo deja leer a un usuario estándar. Un ajuste de registro cuya ruta contiene `\Policies\` bajo HKCU sigue con `scope: user` (son datos del usuario y el diario de usuario acepta HKCU), pero `Test-TuneupTweakNeedsAdmin` (motor, `Planner.ps1`) lo trata como de administrador: el plan marca `requiresAdmin`, aplicar sin elevar se niega y `base` no puede contenerlo. Con elevación por UAC en la misma cuenta se escribe el HKCU de esa cuenta; con otra cuenta de administrador, el de esa otra cuenta (el diario guarda el SID, y deshacer solo restaura entradas de usuario de la cuenta que las hizo).
- **Apps:** las apps "seguras" (Clipchamp, Noticias, Tiempo, Finanzas, Mensajes, Portal de realidad mixta, Películas y TV) van en `lite` y `legacy`, no en `base` (decisión 1). `apps.dev-home` avisa en `why` que deshacer instala la app que hoy ocupa su lugar en la Store ("Configuración avanzada de Windows").
- **Placebo fuera:** `TaskbarAnimations` (sin efecto demostrado en Windows 11) no entra aunque un informe lo proponía.
- **Fuente de `services.retail-demo`:** la guía de servicios de Windows Server no lista RetailDemo; se cita la documentación de Microsoft del modo de demostración (`UnattendEnableRetailDemo`).
- **Una negativa no se deshace:** el ejecutor anota el ajuste que se negó en `undone-tweaks.txt` (los ajustes que no necesitan deshacerse), así `-Undo` no llama a su `Restore`; `-Undo -Tweak <id>` de ese ajuste responde `already-undone`. Una negativa no cambia el código de salida (como cualquier omisión).
- **`signOutRequired` en `-Undo`:** no se agrega todavía (queda anotado en la especificación).
- **`work` no necesita administrador:** solo trae ajustes de usuario sin directivas.
- **Documentación del catálogo:** "No incluido" es una sección generada dentro de `catalog.md` a partir de `catalog/notes/excluded.json` (no un archivo aparte escrito a mano), y el generador agrega las listas de ajustes que preguntan, de riesgo alto y que no rigen en Home.

### Acciones descartadas

- **`power-mode-overlay`** (modo de energía "Mejor rendimiento" con corriente): el modo es una superposición del plan que solo se cambia con `powrprof.dll!PowerSetActiveOverlayScheme`, una función que Microsoft no documenta; no se sabe si cambia CA y CC juntos ni si escribir el registro surte efecto en caliente. No se pudo verificar sin escribir: queda fuera y se documenta en "No incluido".
- **`dev-defender-performance-mode`**: Microsoft documenta que el modo de rendimiento viene activado por defecto en un Dev Drive de confianza ("0 = Enable (default)"), mientras que en el equipo de verificación, sin Dev Drive, `Get-MpPreference` devuelve `PerformanceModeStatus = 1`. Sin un Dev Drive no se puede comprobar qué significa ese valor, y el ajuste toca Defender: queda fuera y se documenta.

## Desviaciones respecto de la especificación

| Especificación | Plan 3 | Motivo |
|---|---|---|
| Base: salud, punto de restauración, telemetría al mínimo, apps basura | Base: solo ajustes de usuario (anuncios, sugerencias, ID de publicidad, extensiones) | Decisión 1: Base se aplica siempre y sin administrador. La salud es `-Health`; el punto de restauración lo crea el motor; telemetría y apps van en otros perfiles |
| Gaming: plan de energía de alto rendimiento | Con `ask` y solo en equipos sin batería | En portátiles gasta batería; en Windows 11 con Modern Standby el plan ni aparece |
| Gaming: programación de GPU acelerada | Solo si el driver la admite | El valor de registro solo no la activa en drivers sin soporte |
| Desarrollo: sugiere Dev Drive y exclusiones de Defender | No | Las exclusiones quitan protección (lista negra); Dev Drive exige formatear un volumen |
| Equipo antiguo: revisión de apps de inicio, indexación reducida | No todavía | Necesitan acciones propias con pregunta; quedan como ideas |
| Liviano: Teams personal | Teams nuevo (`MSTeams`), con `ask` | El Teams personal clásico no tiene producto en la Store |
| Docs: "catálogo generado" | `docs/{es,en}/catalog.md` con secciones de preguntas, riesgo alto, Home y "No incluido" | Una sola página por idioma, al día por prueba |

## Estructura de archivos del Plan 3

```
windows-tuneup/
├── actions/                                   (nueva)
│   ├── gaming-windowed-optimizations.ps1      Optimizaciones para juegos en ventana (token en DirectXUserGlobalSettings)
│   ├── gaming-hags.ps1                        GPU acelerada solo con soporte del driver (D3DKMT)
│   └── onedrive.ps1                           Desinstala OneDrive sin borrar archivos; se niega si hay datos en riesgo
├── catalog/
│   ├── privacy.json, ads.json, ui.json, ai.json, edge.json, services.json, tasks.json,
│   │   performance.json, power.json, gaming.json, dev.json, apps.json        166 ajustes
│   └── notes/excluded.json                    Lo que quedó fuera y por qué (no es catálogo: no se carga)
├── profiles/
│   └── base, dev, gaming, privacy, laptop, legacy, work, lite .json
├── engine/
│   ├── Catalog.ps1                            + requires, signOutRequired
│   ├── Planner.ps1                            + Test-TuneupHardwareMatch, not-applicable-hardware
│   ├── Dispatch.ps1                           + New-TuneupOutcome -Refused
│   ├── Executor.ps1                           + negativas (skipped), signOutRequired en cada resultado
│   ├── Output.ps1                             + signOutRequired, negativas en el resumen
│   └── handlers/Appx.ps1, Powercfg.ps1        + storeId XP, ac/dc opcionales
├── i18n/es.json, i18n/en.json                 + reason.not-applicable-hardware, signOut, motivos de onedrive
├── build/
│   ├── catalog-doc.ps1                        (nuevo) genera docs/{es,en}/catalog.md
│   └── catalog-doc.labels.json                (nuevo) textos de esa página en es y en
├── docs/
│   ├── es/ y en/: blacklist.md, profiles.md, measuring.md, catalog.md (generado)
│   └── superpowers/specs/…-design.md          + sección 11
├── tests/
│   ├── CatalogQuality, CatalogContent, CatalogDoc, Docs .Tests.ps1                          (nuevos)
│   ├── GamingWindowedOptimizations, GamingHags, OneDrive .Tests.ps1                       (nuevos)
│   └── Appx, Catalog, Planner, Powercfg, Dispatch, Executor, Output, I18nCoverage .Tests.ps1 (se amplían)
│       y TestHelpers.ps1 (New-TestTweak -Requires, New-TestEnvironment -HasBattery)
└── README.md
```

---

### Task 1: Sección 11 de la especificación

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`

- [ ] **Step 1: Agregar la sección 11 al final de la especificación**

Agregar al final del archivo (después del punto 12 de la sección 10, con una línea en blanco antes):

````markdown

## 11. Catálogo (Plan 3, 2026-10-01)

Decisiones tomadas al armar el catálogo real, los perfiles y la documentación. Donde contradicen secciones anteriores, manda esta.

1. **Base sin administrador.** `base` solo incluye ajustes `scope: user` de registro `HKCU:` que no son directivas: anuncios y sugerencias, ID de publicidad, experiencias personalizadas, encuestas de opinión y extensiones de archivo. La salud, el punto de restauración, la telemetría mínima y las apps basura de la sección 3 pasan a otros perfiles (`-Health` es un comando aparte; la telemetría va en `privacy` y `lite`; las apps en `lite` y `legacy`). `services.retail-demo` pasa a `lite`. Las directivas de Edge no van en `base` porque Edge muestra "administrado por tu organización": van en `privacy`, `lite`, `laptop` y `legacy`. `work` también se aplica sin administrador.
2. **Ediciones según Microsoft.** Una directiva que Microsoft documenta solo para Enterprise y Education se declara así (`DisableWindowsConsumerFeatures`, `DisableConsumerAccountStateContent`) y el plan la omite en las demás. Datos de diagnóstico: `privacy.diagnostic-data-required` escribe `AllowTelemetry = 1` en `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` (Pro, Enterprise y Education; Home ignora esa directiva); `privacy.diagnostic-data-off` (`0`) es de riesgo alto, solo Enterprise y Education y solo con `-Include` (junto con `-Exclude privacy.diagnostic-data-required`, que escribe el mismo valor). El servicio DiagTrack es `medium` con `ask: true`. Las rutas que Microsoft no documenta (`CurrentVersion\Policies\DataCollection`) quedan fuera.
3. **Apps solo con deshacer.** Una app entra al catálogo solo si `winget --source msstore` encuentra su `storeId` y ese producto instala el mismo paquete Appx. Las que no (Solitaire, Tips, People, Mapas, las apps 3D, Wallet...) quedan fuera y se listan en `catalog/notes/excluded.json`. El `storeId` acepta además ids de 14 caracteres `XP` + 12 (Teams nuevo `XP8BT8DW290MPQ`). Preguntan antes (`ask: true`): OneDrive, Teams, Outlook nuevo, Vínculo móvil, Copilot, Reproductor multimedia, Asistencia rápida, Obtener ayuda y Seguridad familiar.
4. **Cambios del motor.**
   a. `storeId` acepta `^(?:[0-9A-Z]{12}|XP[0-9A-Z]{12})$`.
   b. Campo opcional `requires` en un ajuste: lista de `battery` y `no-battery` (la validación rechaza otros valores, una lista vacía, un texto suelto que no es lista y los dos juntos). El planificador, después de la compatibilidad de Windows, omite el ajuste con el motivo `not-applicable-hardware` si `HasBattery` no coincide.
   c. `powercfg` `setting`: `ac` y `dc` son opcionales cada uno (ausente o nulo = no se toca), pero hace falta al menos uno. `Test`, `Set` y `Restore` solo miran y escriben los que el ajuste da; si solo hay `dc` y falla, es un error, no `partial`.
   d. Un `Set` puede negarse sin cambiar nada: `New-TuneupOutcome -Refused -Reason <código> -Detail <texto>` (motivo y detalle obligatorios, nunca junto con `-Partial`). El ejecutor lo informa `skipped` con ese motivo (no `failed`; no cambia el código de salida), conserva la entrada del diario (se escribió antes) y anota el ajuste en `undone-tweaks.txt`, así `-Undo` nunca llama a su `Restore`; si esa nota no se puede escribir, avisa, y el `Restore` de un manejador que puede negarse solo devuelve lo que difiere del estado guardado. **Contrato: una negativa solo vale si no se cambió nada.** Después de una negativa el ejecutor vuelve a leer el estado y lo compara con el del diario (`ConvertTo-Json -Depth 10 -Compress`): si es igual, el ajuste queda `skipped` y anotado como arriba; si difiere, no se anota, el resultado es `failed` con el error "refused after changing; undo can restore it" y `-Undo` puede restaurarlo. Un resultado `skipped` (del plan o negado) nunca pide reinicio ni cierre de sesión. El resumen de aplicar cuenta las negativas aparte (`summary.refused`, "Negados"/"Refused"; el resultado trae `refused`) y las muestra con su motivo; no cambian el código de salida (`0` si todo lo demás se aplicó). Una ejecución cuyos ajustes quedaron todos anotados como deshechos (todos se negaron) se trata como ya deshecha: `last` no la elige y `-Undo` de la ejecución responde que ya está deshecha (`-Undo -Tweak <id>` responde `already-undone`). Motivos de `onedrive`: `onedrive-known-folders` y `onedrive-online-only-files`. La prueba de cobertura de textos también lee `actions/`.
   e. Campo opcional `signOutRequired` (booleano) en un ajuste. Cada resultado de aplicar trae `signOutRequired` y el reporte también (si algún ajuste aplicado o parcial lo pide); sin reinicio pendiente, el resumen dice "Cierra sesión y vuelve a entrar para completar los cambios". El resultado de `-Undo` todavía no lo trae.
   f. Quedan como ideas, sin implementar: tipo de registro con varios valores, `Binary` en el catálogo, el valor predeterminado `(default)` de una clave, acciones con `scope: user` y precondiciones por ajuste (por ejemplo, omitir DiagTrack si existe Defender for Endpoint).
   g. `HasBattery` es verdadero si hay batería (`Win32_Battery`) **y** el chasis es portátil (`Win32_SystemEnclosure.ChassisTypes` con 8, 9, 10, 14, 30, 31 o 32) o no hay información de chasis. Limitación: un escritorio con UPS que se informa como batería y sin información de chasis cuenta como equipo con batería; con chasis de escritorio no.
   h. Una directiva bajo HKCU exige administrador: el ACL de `HKCU\Software\Policies` y de `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies` solo deja leer a un usuario estándar. Un ajuste `registry` cuya ruta contiene `\Policies\` (sin distinguir mayúsculas) bajo `HKCU:` conserva `scope: user` (son datos del usuario y el diario de usuario acepta HKCU), pero `Test-TuneupTweakNeedsAdmin` lo cuenta como de administrador: el plan indica `requiresAdmin`, aplicar sin elevar se niega con el mismo mensaje que para un ajuste de sistema, deshacer una ejecución con una entrada así también exige elevación, y `base` no puede contenerlo. Una ejecución elevada escribe el `HKCU` de la cuenta elevada (la misma cuenta con el aviso de UAC normal; otra cuenta de administrador si se escribe su contraseña en el aviso). El diario guarda el SID y deshacer solo restaura entradas de usuario de la cuenta que las hizo.
5. **Acciones.** `actions/onedrive.ps1` (desinstala el cliente sin borrar archivos; se niega con Known Folder Move o archivos solo en la nube; deshacer reinstala `Microsoft.OneDrive` con winget, por máquina con `/allusers` si así estaba), `actions/gaming-hags.ps1` (`HwSchMode = 2` solo si `D3DKMTQueryAdapterInfo` con `KMTQAITYPE_WDDM_2_7_CAPS` dice que algún adaptador lo admite; si no, `not-present`; pide reinicio) y `actions/gaming-windowed-optimizations.ps1` (agrega o cambia solo `SwapEffectUpgradeEnable=1` dentro de `DirectXUserGlobalSettings`, conservando los demás pares y su orden; vive en `HKCU` y se acepta `scope: machine` porque corre elevado por el mismo usuario). Quedan fuera: el modo de energía "Mejor rendimiento" (solo se cambia con una función sin documentar) y el modo de rendimiento de Defender para Dev Drive (Microsoft lo activa por defecto en un Dev Drive de confianza y no se pudo verificar sin uno).
6. **Perfiles.** Ocho: `base`, `dev` (`desarrollo`), `gaming` (`juegos`), `privacy` (`privacidad`), `laptop` (`portatil`, `portátil`), `legacy` (`equipo-antiguo`, `antiguo`), `work` (`trabajo`) y `lite` (`liviano`). `gaming` conserva las apps y la tarea de Xbox (los servicios de Xbox no están en el catálogo: ya vienen en manual y deshabilitarlos rompe el inicio de sesión); `work` conserva Teams, Outlook nuevo, OneDrive, Microsoft 365 y Power Automate; ningún ajuste toca WSL, Hyper-V, contenedores ni `SharedAccess`. Ningún perfil incluye ajustes `high`.
7. **Documentación.** `docs/{es,en}/blacklist.md` (sección 4 más las exclusiones de la investigación), `docs/{es,en}/profiles.md` (qué hace cada perfil, qué conserva, qué pregunta y si necesita administrador), `docs/{es,en}/measuring.md` (método manual en VM contra LTSC 2024) y `docs/{es,en}/catalog.md`, generado por `build/catalog-doc.ps1` desde el catálogo, los perfiles y `catalog/notes/excluded.json` (con una sección "No incluido"); una prueba falla si no está al día.
8. **Calidad del catálogo.** Pruebas en `tests/CatalogQuality.Tests.ps1`, `tests/CatalogContent.Tests.ps1`, `tests/CatalogDoc.Tests.ps1` y `tests/Docs.Tests.ps1`: fuentes, ids y títulos únicos, un solo ajuste por valor de registro (salvo la pareja de `AllowTelemetry`), archivos UTF-8 sin BOM, `requires` válidos, scripts de acciones presentes y cargados, `base` solo de usuario sin directivas, `work` solo de usuario sin directivas, nada en `include` y `keep` a la vez, la lista negra (servicios, valores de registro, claves de configuración de los servicios protegidos, UAC y seguridad basada en virtualización, tareas y apps que se conservan; sin distinguir mayúsculas ni comodines, con pruebas que comprueban que cada regla detecta su caso) y la planificación de cada perfil en Home, Pro, Enterprise administrado y Windows 10, con y sin batería.
9. **Liviano frente a LTSC.** La afirmación de la sección 1 queda pendiente de medir con el método de `docs/{es,en}/measuring.md`; el README lo dice.
````

- [ ] **Step 2: Verificar que la suite sigue verde**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Tests Passed: 742, Failed: 0`). Solo cambió documentación.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-30-windows-tuneup-design.md
git commit -m "docs: sección 11 de la especificación, decisiones del catálogo"
```

---

### Task 2: `storeId` de 14 caracteres (`XP` + 12)

**Files:**
- Modify: `engine/handlers/Appx.ps1`
- Test: `tests/Appx.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

En `tests/Appx.Tests.ps1`, dentro de `Describe 'Appx definition'`, agregar después del `It 'accepts a valid appx tweak'`:

```powershell
    It 'accepts the 14-character Store ids that start with XP' {
        $set = [pscustomobject]@{ name = 'MSTeams'; storeId = 'XP8BT8DW290MPQ'; action = 'remove' }
        (Test-AppxTweakDefinition -Tweak (New-TestTweak -Type 'appx' -Scope 'machine' -Set $set)) -join '; ' | Should -BeNullOrEmpty
    }
```

y en los `-TestCases` de `It 'rejects <Problem>'`, después de la línea `@{ Problem = 'a Store id with a trailing newline'; ... }`, agregar:

```powershell
        @{ Problem = 'an XP Store id one character short'; Field = 'storeId'; Value = 'XP8BT8DW290MP'; Message = 'Microsoft Store id' }
        @{ Problem = 'a 14-character Store id that does not start with XP'; Field = 'storeId'; Value = 'XQ8BT8DW290MPQ'; Message = 'Microsoft Store id' }
        @{ Problem = 'a lowercase XP Store id'; Field = 'storeId'; Value = 'xp8bt8dw290mpq'; Message = 'Microsoft Store id' }
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Appx.Tests.ps1`
Expected: FAIL solo en `accepts the 14-character Store ids that start with XP` (el validador pide 12 caracteres). Los tres casos nuevos de rechazo ya pasan.

- [ ] **Step 3: Aceptar los ids `XP`**

En `engine/handlers/Appx.ps1`, reemplazar:

```powershell
# Appx package names look like Microsoft.BingNews; Store ids are the 12-character product ids
# that winget uses with --source msstore.
$script:AppxNamePattern = '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}\z'
$script:StoreIdPattern = '^[0-9A-Z]{12}\z'
```

por:

```powershell
# Appx package names look like Microsoft.BingNews; Store ids are the product ids that winget uses
# with --source msstore: 12 characters (9WZDNCRFHVFW), or XP plus 12 for the newer Win32-based
# Store products (XP8BT8DW290MPQ, new Teams).
$script:AppxNamePattern = '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}\z'
$script:StoreIdPattern = '^(?:[0-9A-Z]{12}|XP[0-9A-Z]{12})\z'
```

y en `Test-AppxTweakDefinition` reemplazar el texto `'needs a Microsoft Store id (12 capital letters or digits) in set.storeId'` por `'needs a Microsoft Store id (12 capital letters or digits, or XP and 12 more) in set.storeId'`.

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Appx.Tests.ps1`
Expected: PASS (`Tests Passed: 64, Failed: 0`).

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Appx.ps1 tests/Appx.Tests.ps1
git commit -m "feat: el id de la Store acepta los de 14 caracteres que empiezan con XP"
```

---

### Task 3: `requires` y el motivo `not-applicable-hardware`

> **Corrección posterior a la revisión.** `requires` debe ser una lista (un texto suelto se rechaza: `$requiresProperty.Value -isnot [System.Array]`), la prueba de orden usa `HasBattery $false` para la edición antes del hardware, y `HasBattery` sale de `Test-TuneupHasBattery` (batería y chasis portátil 8, 9, 10, 14, 30, 31 o 32; sin información de chasis manda la batería).

**Files:**
- Modify: `engine/Catalog.ps1`, `engine/Planner.ps1`, `i18n/es.json`, `i18n/en.json`
- Modify: `tests/TestHelpers.ps1`
- Test: `tests/Catalog.Tests.ps1`, `tests/Planner.Tests.ps1`

- [ ] **Step 1: Ayudantes de prueba**

En `tests/TestHelpers.ps1`, en `New-TestTweak`, reemplazar el final del bloque `param` y el objeto:

```powershell
        [object]$Set = $null,
        [bool]$RebootRequired = $false
    )
```

por:

```powershell
        [object]$Set = $null,
        [bool]$RebootRequired = $false,
        [string[]]$Requires
    )
```

reemplazar `    [pscustomobject]@{` (la primera línea del objeto que devuelve `New-TestTweak`, justo antes de `        id             = $Id`) por `    $tweak = [pscustomobject]@{`, y reemplazar el cierre de la función:

```powershell
        sources        = @('https://example.com/source')
    }
}
```

por:

```powershell
        sources        = @('https://example.com/source')
    }
    if ($PSBoundParameters.ContainsKey('Requires')) { $tweak | Add-Member -NotePropertyName requires -NotePropertyValue $Requires }
    $tweak
}
```

En `New-TestEnvironment`, reemplazar:

```powershell
        [bool]$IsManaged = $false
    )
    [pscustomobject]@{
        Family = $Family; Build = $Build; UBR = 0; Edition = $Edition; IsServer = $false
        IsManaged = $IsManaged; IsAdmin = $true; HasBattery = $false; PendingReboot = $false
    }
```

por:

```powershell
        [bool]$IsManaged = $false,
        [bool]$HasBattery = $false
    )
    [pscustomobject]@{
        Family = $Family; Build = $Build; UBR = 0; Edition = $Edition; IsServer = $false
        IsManaged = $IsManaged; IsAdmin = $true; HasBattery = $HasBattery; PendingReboot = $false
    }
```

- [ ] **Step 2: Pruebas que fallan**

Agregar al final de `tests/Catalog.Tests.ps1`:

```powershell
Describe 'Test-TuneupTweak requires' {
    It 'accepts a tweak without requires and one with known tokens' {
        (Test-TuneupTweak -Tweak (New-TestTweak)) -join '; ' | Should -BeNullOrEmpty
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires @('battery'))) -join '; ' | Should -BeNullOrEmpty
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires @('no-battery'))) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'an unknown token'; Requires = @('desktop') }
        @{ Problem = 'a token in another case'; Requires = @('Battery') }
        @{ Problem = 'an empty list'; Requires = @() }
    ) {
        param($Requires)
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires $Requires)) -join '; ' | Should -Match 'invalid requires'
    }

    It 'rejects a requires that is not a list of text' {
        $tweak = New-TestTweak
        $tweak | Add-Member -NotePropertyName requires -NotePropertyValue $null
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'invalid requires'
    }

    It 'rejects battery and no-battery together' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Requires @('battery', 'no-battery'))) -join '; ' | Should -Match 'requires both battery and no-battery'
    }

    It 'reads requires from a catalog file' {
        $dir = Join-Path $TestDrive 'requires-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $tweak = New-TestTweak -Id 'power.sample' -Requires @('battery')
        ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = @($tweak) }) -Depth 10 |
            Set-Content -LiteralPath (Join-Path $dir 'power.json') -Encoding UTF8
        $catalog = @(Import-TuneupCatalog -Path $dir)
        @($catalog[0].requires) -join ',' | Should -Be 'battery'
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -BeNullOrEmpty
    }
}
```

En `tests/Planner.Tests.ps1`, en el `BeforeAll`, reemplazar el último elemento de `$script:Catalog`:

```powershell
        (New-TestTweak -Id 'svc.policy-path' -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\Policies\Microsoft\Example'; name = 'Spooler'; startup = 'Disabled' }))
    )
```

por:

```powershell
        (New-TestTweak -Id 'svc.policy-path' -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\Policies\Microsoft\Example'; name = 'Spooler'; startup = 'Disabled' })),
        (New-TestTweak -Id 'power.on-battery' -Requires @('battery')),
        (New-TestTweak -Id 'power.plugged-in' -Requires @('no-battery')),
        (New-TestTweak -Id 'power.old-laptop' -Requires @('battery') -Editions @('Home'))
    )
```

y agregar al final del archivo:

```powershell
Describe 'New-TuneupPlan with hardware requirements' {
    It 'skips a tweak for machines with a battery on a machine without one' {
        $plan = Invoke-Plan -Include 'power.on-battery', 'power.plugged-in' -Environment (New-TestEnvironment -HasBattery $false)
        Get-Reason $plan 'power.on-battery' | Should -Be 'not-applicable-hardware'
        Get-Action $plan 'power.plugged-in' | Should -Be 'apply'
    }

    It 'skips a tweak for machines without a battery on a laptop' {
        $plan = Invoke-Plan -Include 'power.on-battery', 'power.plugged-in' -Environment (New-TestEnvironment -HasBattery $true)
        Get-Action $plan 'power.on-battery' | Should -Be 'apply'
        Get-Reason $plan 'power.plugged-in' | Should -Be 'not-applicable-hardware'
    }

    It 'reports the edition before the hardware, and the hardware before reading the state' {
        $plan = Invoke-Plan -Include 'power.old-laptop', 'power.plugged-in' -Environment (New-TestEnvironment -HasBattery $true) -TestState { throw 'must not read' }
        Get-Reason $plan 'power.old-laptop' | Should -Be 'incompatible'
        Get-Reason $plan 'power.plugged-in' | Should -Be 'not-applicable-hardware'
    }

    It 'has a text for the new reason in both languages' {
        foreach ($lang in 'es', 'en') {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $lang
            Get-TuneupText -Key 'reason.not-applicable-hardware' | Should -Not -Be 'reason.not-applicable-hardware'
        }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }
}
```

- [ ] **Step 3: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Catalog.Tests.ps1`
Expected: FAIL en `rejects <Problem>` (los tres casos), `rejects a requires that is not a list of text` y `rejects battery and no-battery together`: el validador todavía no mira `requires`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: FAIL en los cuatro casos de `New-TuneupPlan with hardware requirements` (los ajustes se aplican y el texto no existe).

- [ ] **Step 4: Validar `requires`**

En `engine/Catalog.ps1`, después de la línea `$script:TweakEditions = @('Home', 'Pro', 'Enterprise', 'Education')`, agregar:

```powershell
# Hardware a tweak can ask for in its optional requires list; the planner checks them.
$script:TweakRequirements = @('battery', 'no-battery')
```

y en `Test-TuneupTweak`, después de la línea `    if ($Tweak.rebootRequired -isnot [bool]) { $errors.Add("$id rebootRequired must be true or false") }`, agregar:

```powershell
    $requiresProperty = $Tweak.PSObject.Properties['requires']
    if ($null -ne $requiresProperty) {
        $requires = @($requiresProperty.Value)
        if (-not $requires.Count -or @($requires | Where-Object { $_ -isnot [string] -or $script:TweakRequirements -cnotcontains $_ }).Count) {
            $errors.Add("$id has invalid requires: use a list of $($script:TweakRequirements -join ', ')")
        } elseif ($requires -ccontains 'battery' -and $requires -ccontains 'no-battery') {
            $errors.Add("$id requires both battery and no-battery")
        }
    }
```

- [ ] **Step 5: Omitir en el hardware que no corresponde**

En `engine/Planner.ps1`, antes de `function Test-TuneupPolicyTweak {`, agregar:

```powershell
# The optional requires list of a tweak names the hardware it is meant for.
function Test-TuneupHardwareMatch {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Environment)
    $requiresProperty = $Tweak.PSObject.Properties['requires']
    if ($null -eq $requiresProperty) { return $true }
    foreach ($requirement in @($requiresProperty.Value)) {
        switch -CaseSensitive ([string]$requirement) {
            'battery' { if (-not $Environment.HasBattery) { return $false } }
            'no-battery' { if ($Environment.HasBattery) { return $false } }
            default { throw "Unknown requirement '$requirement' in tweak $($Tweak.id)" }
        }
    }
    $true
}

```

y en `New-TuneupPlan`, después de la línea `        elseif (-not (Test-TuneupCompatible -Tweak $tweak -Environment $Environment)) { $reason = 'incompatible' }`, agregar:

```powershell
        elseif (-not (Test-TuneupHardwareMatch -Tweak $tweak -Environment $Environment)) { $reason = 'not-applicable-hardware' }
```

En `i18n/es.json`, después de la línea de `"reason.incompatible"`, agregar:

```json
  "reason.not-applicable-hardware": "no aplica al hardware de este equipo (por ejemplo, solo para equipos con batería o sin ella)",
```

En `i18n/en.json`, después de la línea de `"reason.incompatible"`, agregar:

```json
  "reason.not-applicable-hardware": "does not apply to this machine's hardware (for example, only for machines with or without a battery)",
```

- [ ] **Step 6: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: PASS (`Tests Passed: 31, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/Catalog.Tests.ps1`, `tests/I18n.Tests.ps1` y `tests/I18nCoverage.Tests.ps1` (el motivo nuevo tiene texto en los dos idiomas).

- [ ] **Step 7: Commit**

```bash
git add engine/Catalog.ps1 engine/Planner.ps1 i18n/es.json i18n/en.json tests/TestHelpers.ps1 tests/Catalog.Tests.ps1 tests/Planner.Tests.ps1
git commit -m "feat: un ajuste puede pedir equipo con o sin batería (requires)"
```

---

### Task 4: `ac` y `dc` opcionales en `powercfg`

**Files:**
- Modify: `engine/handlers/Powercfg.ps1`
- Test: `tests/Powercfg.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

En `tests/Powercfg.Tests.ps1`, dentro de `Describe 'Power setting'`, agregar antes de `    It 'restores the scheme that was active' {`:

```powershell
    It 'writes, compares and restores only the AC value when the tweak gives no DC value' {
        $tweak = New-TestTweak -Id 'power.ac-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = 0 })
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'applied'
        $script:Keys[$UserValues] = [pscustomobject]@{ ACSettingIndex = 600 }
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'not-applied'
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 0" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setdcvalueindex' }
        Restore-PowercfgTweakState -Tweak $tweak -State ([pscustomobject]@{ kind = 'setting'; scheme = $Balanced; present = $true; ac = 600; dc = 300 })
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setacvalueindex $Balanced $Sleep $StandbyIdle 600" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setdcvalueindex' }
    }

    It 'treats a null value like an absent one and writes only DC' {
        $tweak = New-TestTweak -Id 'power.dc-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = $null; dc = 600 })
        Test-PowercfgTweakState -Tweak $tweak | Should -Be 'not-applied'
        Set-PowercfgTweakDesired -Tweak $tweak
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq '/setacvalueindex' }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setdcvalueindex $Balanced $Sleep $StandbyIdle 600" }
        Should -Invoke Invoke-TuneupPowercfg -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq "/setactive $Balanced" }
    }

    It 'fails, without a partial result, when the only value cannot be written' {
        $script:FailDc = $true
        $tweak = New-TestTweak -Id 'power.dc-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; dc = 600 })
        { Set-PowercfgTweakDesired -Tweak $tweak } | Should -Throw '*setdcvalueindex failed*'
    }

    It 'names the one value that was changed when activating the scheme again fails' {
        Mock -ModuleName Tuneup Invoke-TuneupPowercfg { throw 'powercfg /setactive failed with exit code 1: Invalid Parameters' } -ParameterFilter { $Arguments[0] -eq '/setactive' }
        $tweak = New-TestTweak -Id 'power.ac-only' -Type 'powercfg' -Scope 'machine' `
            -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $Sleep; setting = $StandbyIdle; ac = 5 })
        $outcome = Get-TuneupOutcome -Output @(Set-PowercfgTweakDesired -Tweak $tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike 'The value on AC power was changed, but activating the scheme again failed*'
    }

```

En `Describe 'Powercfg definition and registration'`, en los `-TestCases` de `It 'accepts a valid <Kind> tweak'`, después del caso `@{ Kind = 'setting'; ... }`, agregar:

```powershell
        @{ Kind = 'setting with only AC'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = 0 } }
        @{ Kind = 'setting with only DC'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = $null; dc = 1 } }
```

y en los `-TestCases` de `It 'rejects <Problem>'`, después del caso `@{ Problem = 'a value that is text'; ... }`, agregar:

```powershell
        @{ Problem = 'neither an AC nor a DC value'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' }; Message = 'needs set.ac, set.dc or both' }
        @{ Problem = 'both values null'; Set = @{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; ac = $null; dc = $null }; Message = 'needs set.ac, set.dc or both' }
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Powercfg.Tests.ps1`
Expected: FAIL en las cuatro pruebas nuevas de `Power setting`, en los dos casos nuevos de `accepts a valid <Kind> tweak` ("set.dc must be an integer") y en los dos de `rejects <Problem>` (falta el mensaje "needs set.ac, set.dc or both").

- [ ] **Step 3: Valores opcionales en el manejador**

En `engine/handlers/Powercfg.ps1`, reemplazar la función `Set-TuneupPowerSettingIndex` completa por:

```powershell
# The values a setting tweak asks for: ac and dc are each optional (absent or null leaves that power
# source as it is), but at least one is given (the catalog check makes sure).
function Get-TuneupPowerSettingTarget {
    param([Parameter(Mandatory)]$Set)
    $target = @{ ac = $null; dc = $null }
    foreach ($field in 'ac', 'dc') {
        $property = $Set.PSObject.Properties[$field]
        if ($null -ne $property -and $null -ne $property.Value) { $target[$field] = [long]$property.Value }
    }
    [pscustomobject]$target
}

function Set-TuneupPowerSettingIndex {
    param(
        [Parameter(Mandatory)][string]$Scheme,
        [Parameter(Mandatory)][string]$Subgroup,
        [Parameter(Mandatory)][string]$Setting,
        [AllowNull()]$Ac,
        [AllowNull()]$Dc,
        [switch]$ReportPartial
    )
    # Only the power sources that are given are written; the other one keeps its value.
    $written = @()
    if ($null -ne $Ac) {
        Invoke-TuneupPowercfg -Arguments @('/setacvalueindex', $Scheme, $Subgroup, $Setting, [string][long]$Ac) | Out-Null
        $written += 'AC'
    }
    if ($null -ne $Dc) {
        try {
            Invoke-TuneupPowercfg -Arguments @('/setdcvalueindex', $Scheme, $Subgroup, $Setting, [string][long]$Dc) | Out-Null
        } catch {
            # Nothing was written yet when DC is the only value: a plain failure.
            if (-not $written.Count) { throw }
            $message = "The value on AC power was changed, but not the rest: $($_.Exception.Message)"
            if ($ReportPartial) { return (New-TuneupOutcome -Partial -Detail $message) }
            throw $message
        }
        $written += 'DC'
    }
    # A change to the active scheme takes effect once it is activated again.
    try {
        if ($Scheme -eq (Get-TuneupActivePowerScheme)) { Invoke-TuneupPowercfg -Arguments @('/setactive', $Scheme) | Out-Null }
    } catch {
        $changed = $(if ($written.Count -eq 2) { 'The values on AC and DC power were changed' } else { "The value on $($written[0]) power was changed" })
        $message = "$changed, but activating the scheme again failed: $($_.Exception.Message)"
        if ($ReportPartial) { return (New-TuneupOutcome -Partial -Detail $message) }
        throw $message
    }
}
```

En `Test-PowercfgTweakDefinition`, reemplazar:

```powershell
            foreach ($field in 'ac', 'dc') {
                if (-not (Test-TuneupIntegerInRange -Value $set.$field -Min 0 -Max 4294967295)) { "set.$field must be an integer from 0 to 4294967295" }
            }
```

por:

```powershell
            # ac and dc are each optional (left as they are when absent or null), but one is needed.
            $given = @('ac', 'dc' | Where-Object { $null -ne $set.PSObject.Properties[$_] -and $null -ne $set.$_ })
            if (-not $given.Count) { 'needs set.ac, set.dc or both' }
            foreach ($field in $given) {
                if (-not (Test-TuneupIntegerInRange -Value $set.$field -Min 0 -Max 4294967295)) { "set.$field must be an integer from 0 to 4294967295" }
            }
```

En `Test-PowercfgTweakState`, reemplazar:

```powershell
    $state = Get-TuneupPowerSettingState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ([long]$state.ac -eq [long]$Tweak.set.ac -and [long]$state.dc -eq [long]$Tweak.set.dc) { return 'applied' }
    'not-applied'
```

por:

```powershell
    $state = Get-TuneupPowerSettingState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    # A power source the tweak leaves alone does not count.
    $target = Get-TuneupPowerSettingTarget -Set $Tweak.set
    if ($null -ne $target.ac -and [long]$state.ac -ne $target.ac) { return 'not-applied' }
    if ($null -ne $target.dc -and [long]$state.dc -ne $target.dc) { return 'not-applied' }
    'applied'
```

En `Set-PowercfgTweakDesired`, reemplazar:

```powershell
    $scheme = Resolve-TuneupPowerScheme -Scheme ([string]$set.scheme)
    Set-TuneupPowerSettingIndex -Scheme $scheme -Subgroup ([string]$set.subgroup).ToLowerInvariant() `
        -Setting ([string]$set.setting).ToLowerInvariant() -Ac ([long]$set.ac) -Dc ([long]$set.dc) -ReportPartial
```

por:

```powershell
    $scheme = Resolve-TuneupPowerScheme -Scheme ([string]$set.scheme)
    $target = Get-TuneupPowerSettingTarget -Set $set
    Set-TuneupPowerSettingIndex -Scheme $scheme -Subgroup ([string]$set.subgroup).ToLowerInvariant() `
        -Setting ([string]$set.setting).ToLowerInvariant() -Ac $target.ac -Dc $target.dc -ReportPartial
```

En `Restore-PowercfgTweakState`, reemplazar:

```powershell
    if (-not $State.present) { return }
    Set-TuneupPowerSettingIndex -Scheme ([string]$State.scheme) -Subgroup ([string]$Tweak.set.subgroup).ToLowerInvariant() `
        -Setting ([string]$Tweak.set.setting).ToLowerInvariant() -Ac ([long]$State.ac) -Dc ([long]$State.dc)
```

por:

```powershell
    if (-not $State.present) { return }
    # Only the power sources that the tweak changed are given back; the other one may have been
    # changed since by someone else.
    $target = Get-TuneupPowerSettingTarget -Set $Tweak.set
    $ac = $(if ($null -ne $target.ac) { [long]$State.ac } else { $null })
    $dc = $(if ($null -ne $target.dc) { [long]$State.dc } else { $null })
    Set-TuneupPowerSettingIndex -Scheme ([string]$State.scheme) -Subgroup ([string]$Tweak.set.subgroup).ToLowerInvariant() `
        -Setting ([string]$Tweak.set.setting).ToLowerInvariant() -Ac $ac -Dc $dc
```

El estado guardado (`Get-TuneupPowerSettingState`) sigue leyendo CA y CC: el diario no cambia.

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Powercfg.Tests.ps1`
Expected: PASS (`Tests Passed: 51, Failed: 0`), incluidas las pruebas anteriores con `ac` y `dc` (mismos mensajes de `partial`).

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Powercfg.ps1 tests/Powercfg.Tests.ps1
git commit -m "feat: un ajuste de powercfg puede fijar solo CA o solo CC"
```

---

### Task 5: Un `Set` puede negarse sin cambiar nada

**Files:**
- Modify: `engine/Dispatch.ps1`, `engine/Executor.ps1`, `engine/Output.ps1`
- Test: `tests/Dispatch.Tests.ps1`, `tests/Executor.Tests.ps1`, `tests/Output.Tests.ps1`, `tests/I18nCoverage.Tests.ps1`

Diseño: la acción decide si se niega **después** de que el ejecutor escribió su entrada en el diario (el diario siempre va primero) y **antes** de cambiar nada. El ejecutor informa el ajuste como `skipped` con el motivo de la negativa (no `failed`: el código de salida no cambia, como cualquier omisión), no lo verifica con `Test`, y lo anota en `undone-tweaks.txt`, el archivo donde `-Undo` ya lleva los ajustes que no hay que restaurar. Así un deshacer posterior nunca llama a su `Restore` (que podría reinstalar algo que el usuario quitó después). Si la nota no se puede escribir, avisa; por eso el `Restore` de un manejador que puede negarse solo devuelve lo que difiere del estado guardado (el de `onedrive`, Task 20, no hace nada si nada cambió). El resumen de aplicar ya ocultaba las omisiones del plan; ahora muestra las que traen `detail`, que son las negativas.

> **Corrección posterior a la revisión.** Una negativa solo vale si no se cambió nada: tras ella el ejecutor vuelve a leer el estado (`Test-TuneupStateUnchanged`) y lo compara con el del diario; si difiere, no anota el ajuste y lo informa `failed` con "refused after changing; undo can restore it". El resultado trae `refused`, el resumen cuenta `refused` aparte (el código de salida no cambia), un `skipped` nunca pide reinicio ni cierre de sesión, y una ejecución cuyos ajustes quedaron todos anotados como deshechos se trata como ya deshecha (`Test-TuneupRunAllNotedUndone`: `last` no la elige y `-Undo` responde que ya está deshecha). Ver la sección 11 de la especificación.

- [ ] **Step 1: Pruebas que fallan**

En `tests/Dispatch.Tests.ps1`, dentro de `Describe 'Handler outcomes'`, agregar antes de `    It 'refuses a partial outcome without a detail' {`:

```powershell
    It 'builds a refused outcome only with a reason and a detail, and never together with partial' {
        $outcome = Get-TuneupOutcome -Output @(New-TuneupOutcome -Refused -Reason 'sample-refusal' -Detail 'why')
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be 'sample-refusal'
        $outcome.detail | Should -Be 'why'
        $outcome.partial | Should -BeFalse
        { New-TuneupOutcome -Refused -Detail 'why' } | Should -Throw '*refused outcome needs a reason and a detail*'
        { New-TuneupOutcome -Refused -Reason 'sample-refusal' } | Should -Throw '*refused outcome needs a reason and a detail*'
        { New-TuneupOutcome -Refused -Partial -Reason 'sample-refusal' -Detail 'why' } | Should -Throw '*cannot be refused and partial*'
        (Get-TuneupOutcome -Output @(New-TuneupOutcome -Detail 'plain')).refused | Should -BeFalse
    }

```

Agregar al final de `tests/Executor.Tests.ps1`:

```powershell
Describe 'Invoke-TuneupPlan with a refusal' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { New-TuneupOutcome -Refused -Reason 'sample-refusal' -Detail 'nothing was changed' } -ParameterFilter { $Tweak.id -eq 'test.one' }
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'reports a refused tweak as skipped with its reason and detail, and goes on' {
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'skipped'
        $results[0].reason | Should -Be 'sample-refusal'
        $results[0].detail | Should -Be 'nothing was changed'
        $results[0].error | Should -BeNullOrEmpty
        $results[1].status | Should -Be 'applied'
    }

    It 'keeps the journal entry and notes the tweak as needing no undo' {
        Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir | Out-Null
        @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl') | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.one,test.two'
        @(Get-TuneupUndoneTweakId -Run $Run) -join ',' | Should -Be 'test.one'
    }

    It 'never restores the refused tweak when the run is undone' {
        Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir | Out-Null
        Mock -ModuleName Tuneup Restore-RegistryTweakState { } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupUndo -Run $Run)
        ($results | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.two=restored'
        Should -Invoke Restore-RegistryTweakState -ModuleName Tuneup -Times 0 -Exactly -ParameterFilter { $Tweak.id -eq 'test.one' }
        Test-Path -LiteralPath (Join-Path $Run.Dir 'undone.json') | Should -BeTrue
    }

    It 'warns, without failing the tweak, when the note cannot be written' {
        Mock -ModuleName Tuneup Write-TuneupStateFile { throw 'disk full' } -ParameterFilter { $Path -like '*undone-tweaks.txt' }
        $warnings = @()
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir -WarningVariable warnings -WarningAction SilentlyContinue)
        $results[0].status | Should -Be 'skipped'
        ($warnings -join ' ') | Should -BeLike '*test.one changed nothing*disk full*'
    }
}
```

En `tests/Output.Tests.ps1`, dentro de `Describe 'Write-TuneupApplyReport'`, agregar antes de `    It 'shows a partial tweak with its explanation' {`:

```powershell
    It 'shows a tweak that refused to change anything, with its reason and detail' {
        $refused = [pscustomobject]@{ id = 'test.refused'; title = 'Title refused'; status = 'skipped'; reason = 'other-user'; error = $null; detail = 'Nothing was changed'; rebootRequired = $false }
        $text = (Write-TuneupApplyReport -Report (New-TestReport @($refused, $PlanSkip)) 6>&1 | Out-String)
        $text | Should -Match '\[skipped\] Title refused: belongs to another user'
        $text | Should -Match 'Nothing was changed'
        $text | Should -Not -Match 'Title skipped'
    }

```

(La prueba usa el motivo `other-user` solo porque ya tiene texto; los motivos reales de las negativas llegan con la acción `onedrive`, Task 20.)

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: FAIL, `A parameter cannot be found that matches parameter name 'Refused'`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: FAIL en las cuatro pruebas de `Invoke-TuneupPlan with a refusal`.

- [ ] **Step 3: El resultado de manejador `Refused`**

En `engine/Dispatch.ps1`, reemplazar desde el comentario `# What a handler's Set or Restore can report besides doing its work.` hasta la línea `        if ($item.partial) { $merged.partial = $true }` (inclusive) por:

```powershell
# What a handler's Set or Restore can report besides doing its work. The type name marks it, so
# anything else a handler or a cmdlet prints is never mistaken for it. Refused: Set looked at the
# system and chose not to change anything (for example, files that only live in the cloud); the
# tweak is reported as skipped with that reason instead of failed.
function New-TuneupOutcome {
    param([switch]$Partial, [string]$Detail, [switch]$RebootRequired, [string]$Reason, [switch]$Refused)
    if ($Partial -and -not $Detail) { throw 'A partial outcome needs a detail' }
    if ($Refused -and (-not $Reason -or -not $Detail)) { throw 'A refused outcome needs a reason and a detail' }
    if ($Refused -and $Partial) { throw 'An outcome cannot be refused and partial: a refusal changes nothing' }
    [pscustomobject]@{
        PSTypeName     = 'Tuneup.Outcome'
        partial        = [bool]$Partial
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = [bool]$RebootRequired
        reason         = $(if ($Reason) { $Reason } else { $null })
        refused        = [bool]$Refused
    }
}

function Get-TuneupOutcome {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Output = @())
    $merged = [pscustomobject]@{ partial = $false; detail = $null; rebootRequired = $false; reason = $null; refused = $false }
    foreach ($item in @($Output)) {
        if ($null -eq $item -or $item.PSObject.TypeNames -notcontains 'Tuneup.Outcome') { continue }
        if ($item.partial) { $merged.partial = $true }
        if ($item.PSObject.Properties['refused'] -and $item.refused) { $merged.refused = $true }
```

El resto de `Get-TuneupOutcome` no cambia.

- [ ] **Step 4: El ejecutor informa la negativa y la anota**

En `engine/Executor.ps1`, antes de `function Invoke-TuneupPlan {`, agregar:

```powershell
# A refused tweak changed nothing, so it is noted with the tweaks already undone. If the note cannot
# be written, an undo calls its restore, which leaves it as it is (handlers that can refuse restore
# only what differs from the saved state).
function Add-TuneupRefusedMark {
    param([Parameter(Mandatory)][string]$RunDir, [Parameter(Mandatory)]$Tweak)
    try {
        Write-TuneupStateFile -Path (Join-Path $RunDir 'undone-tweaks.txt') -Append -Text ([string]$Tweak.id + [Environment]::NewLine)
    } catch {
        Write-Warning "Tweak $($Tweak.id) changed nothing, but that could not be noted for -Undo: $($_.Exception.Message)"
    }
}

```

y en `Invoke-TuneupPlan`, reemplazar:

```powershell
            $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $tweak)
            if ($outcome.partial) {
```

por:

```powershell
            $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $tweak)
            if ($outcome.refused) {
                # Nothing was changed. Its journal entry stays (it was written first), and the tweak
                # is noted as needing no undo, so -Undo never calls its restore.
                Add-TuneupRefusedMark -RunDir $RunDir -Tweak $tweak
                New-TuneupResult -Item $item -Status 'skipped' -Reason $outcome.reason -Detail $outcome.detail
                continue
            }
            if ($outcome.partial) {
```

`Write-TuneupStateFile` decide las reglas de la carpeta por la ruta (máquina, usuario o `-StateRoot`), igual que el diario. `-Status` no lista la negativa: solo cuenta los resultados `applied`, `partial` y `not-applied` de `result.json`.

- [ ] **Step 5: El resumen muestra la negativa**

En `engine/Output.ps1`, en `Write-TuneupApplyReport`, reemplazar:

```powershell
    $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red' }
```

por:

```powershell
    $colors = @{ 'applied' = 'Green'; 'partial' = 'Yellow'; 'not-applied' = 'Yellow'; 'failed' = 'Red'; 'skipped' = 'Yellow' }
```

y reemplazar:

```powershell
        if ($result.status -eq 'skipped') { continue }
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title) -ForegroundColor $colors[$result.status]
```

por:

```powershell
        # Skips of the plan were already shown; a skip with a detail is a tweak that refused to change
        # anything when it was applied, so it is shown with its reason.
        if ($result.status -eq 'skipped' -and -not $result.detail) { continue }
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.status -eq 'skipped' -and $result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
```

- [ ] **Step 6: La cobertura de textos también lee las acciones**

Las negativas las emiten scripts de `actions/` (`-Reason 'onedrive-...'`), así que la prueba que exige texto para cada motivo debe leerlos. En `tests/I18nCoverage.Tests.ps1`, reemplazar:

```powershell
    $script:Files = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine') -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine\handlers') -Filter '*.ps1' -File)
```

por:

```powershell
    $script:Files = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine') -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine\handlers') -Filter '*.ps1' -File)
    # Action scripts report their own reasons (a refusal, a reinstall), which the reports look up too.
    $actionsFolder = Join-Path $Repo 'actions'
    if (Test-Path -LiteralPath $actionsFolder) { $script:Files += @(Get-ChildItem -LiteralPath $actionsFolder -Filter '*.ps1' -File) }
```

- [ ] **Step 7: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: PASS (`Tests Passed: 15, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`).

- [ ] **Step 8: Commit**

```bash
git add engine/Dispatch.ps1 engine/Executor.ps1 engine/Output.ps1 tests/Dispatch.Tests.ps1 tests/Executor.Tests.ps1 tests/Output.Tests.ps1 tests/I18nCoverage.Tests.ps1
git commit -m "feat: un ajuste puede negarse sin cambiar nada y queda omitido con su motivo"
```

---

### Task 6: `signOutRequired`

**Files:**
- Modify: `engine/Catalog.ps1`, `engine/Executor.ps1`, `engine/Output.ps1`, `i18n/es.json`, `i18n/en.json`
- Test: `tests/Catalog.Tests.ps1`, `tests/Executor.Tests.ps1`, `tests/Output.Tests.ps1`

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Catalog.Tests.ps1`:

```powershell
Describe 'Test-TuneupTweak signOutRequired' {
    It 'accepts a tweak without signOutRequired and one with a boolean' {
        $tweak = New-TestTweak
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -BeNullOrEmpty
        $tweak | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $true
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects a signOutRequired that is not a boolean (<Value>)' -TestCases @(
        @{ Value = 'yes' }
        @{ Value = 1 }
        @{ Value = $null }
    ) {
        param($Value)
        $tweak = New-TestTweak
        $tweak | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $Value
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'signOutRequired must be true or false'
    }
}
```

Agregar al final de `tests/Executor.Tests.ps1`:

```powershell
Describe 'Invoke-TuneupPlan and signing out' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'carries signOutRequired of the catalog into each result' {
        $signOut = New-TestTweak -Id 'test.one' -Set $One.set
        $signOut | Add-Member -NotePropertyName signOutRequired -NotePropertyValue $true
        $plan = @(New-TuneupPlan -Catalog @($signOut, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $Run.Dir)
        $results[0].signOutRequired | Should -BeTrue
        $results[1].signOutRequired | Should -BeFalse
    }
}
```

En `tests/Output.Tests.ps1`, dentro de `Describe 'Write-TuneupApplyReport'`, agregar antes de `    It 'shows a tweak that refused to change anything, with its reason and detail' {`:

```powershell
    It 'asks to sign out when an applied tweak needs it and no restart is needed' {
        $signOut = [pscustomobject]@{ id = 'test.sign'; title = 'Title sign'; status = 'applied'; reason = $null; error = $null; detail = $null; rebootRequired = $false; signOutRequired = $true }
        $report = New-TestReport @($signOut)
        $report.signOutRequired | Should -BeTrue
        (Write-TuneupApplyReport -Report $report 6>&1 | Out-String) | Should -Match 'Sign out and sign in again'
        ($report | ConvertTo-Json -Depth 10 | ConvertFrom-Json).signOutRequired | Should -BeTrue
    }

    It 'asks only to restart when one tweak needs a restart and another a sign-out' {
        $signOut = [pscustomobject]@{ id = 'test.sign'; title = 'Title sign'; status = 'applied'; reason = $null; error = $null; detail = $null; rebootRequired = $false; signOutRequired = $true }
        $reboot = [pscustomobject]@{ id = 'test.boot'; title = 'Title boot'; status = 'applied'; reason = $null; error = $null; detail = $null; rebootRequired = $true; signOutRequired = $false }
        $text = (Write-TuneupApplyReport -Report (New-TestReport @($signOut, $reboot)) 6>&1 | Out-String)
        $text | Should -Match 'Restart the computer'
        $text | Should -Not -Match 'Sign out and sign in again'
    }

    It 'does not ask to sign out for a tweak that was skipped' {
        $skipped = [pscustomobject]@{ id = 'test.sign'; title = 'Title sign'; status = 'skipped'; reason = 'already-applied'; error = $null; detail = $null; rebootRequired = $false; signOutRequired = $true }
        (New-TestReport @($skipped)).signOutRequired | Should -BeFalse
    }

```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Output.Tests.ps1`
Expected: FAIL en `asks to sign out when an applied tweak needs it and no restart is needed` (el reporte no tiene `signOutRequired`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: FAIL en `carries signOutRequired of the catalog into each result`.

- [ ] **Step 3: Validar el campo**

En `engine/Catalog.ps1`, en `Test-TuneupTweak`, reemplazar:

```powershell
    $requiresProperty = $Tweak.PSObject.Properties['requires']
    if ($null -ne $requiresProperty) {
```

por:

```powershell
    $signOutProperty = $Tweak.PSObject.Properties['signOutRequired']
    if ($null -ne $signOutProperty -and $signOutProperty.Value -isnot [bool]) { $errors.Add("$id signOutRequired must be true or false") }
    $requiresProperty = $Tweak.PSObject.Properties['requires']
    if ($null -ne $requiresProperty) {
```

- [ ] **Step 4: Cada resultado y el reporte lo traen**

En `engine/Executor.ps1`, en `New-TuneupResult`, reemplazar el objeto:

```powershell
    [pscustomobject]@{
        id             = $Item.Id
        title          = Get-TuneupTitle -Tweak $Item.Tweak
        status         = $Status
        reason         = $(if ($Reason) { $Reason } else { $null })
        error          = $(if ($ErrorText) { $ErrorText } else { $null })
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = ([bool]$Item.Tweak.rebootRequired -or [bool]$RebootRequired)
    }
```

por:

```powershell
    # signOutRequired is optional in the catalog: the change shows once the user signs in again.
    $signOut = $Item.Tweak.PSObject.Properties['signOutRequired']
    [pscustomobject]@{
        id              = $Item.Id
        title           = Get-TuneupTitle -Tweak $Item.Tweak
        status          = $Status
        reason          = $(if ($Reason) { $Reason } else { $null })
        error           = $(if ($ErrorText) { $ErrorText } else { $null })
        detail          = $(if ($Detail) { $Detail } else { $null })
        rebootRequired  = ([bool]$Item.Tweak.rebootRequired -or [bool]$RebootRequired)
        signOutRequired = ($null -ne $signOut -and $signOut.Value -eq $true)
    }
```

En `engine/Output.ps1`, en `New-TuneupApplyReport`, después de la línea `        rebootRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.rebootRequired }).Count -gt 0)`, agregar:

```powershell
        signOutRequired = (@($Results | Where-Object { ($_.status -eq 'applied' -or $_.status -eq 'partial') -and $_.signOutRequired }).Count -gt 0)
```

y en `Write-TuneupApplyReport`, reemplazar la última línea de la función:

```powershell
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}

function Write-TuneupStatusReport {
```

por:

```powershell
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
    # A restart also signs the user out, so the sign-out line is only needed without one.
    elseif ($Report.signOutRequired) { Write-Host (Get-TuneupText -Key 'signOut') -ForegroundColor Yellow }
}

function Write-TuneupStatusReport {
```

En `i18n/es.json`, después de la línea de `"reboot"`, agregar:

```json
  "signOut": "Cierra sesión y vuelve a entrar para completar los cambios.",
```

En `i18n/en.json`, después de la línea de `"reboot"`, agregar:

```json
  "signOut": "Sign out and sign in again to finish the changes.",
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`). Los resultados de `-Undo` no cambian (no traen `signOutRequired`).

- [ ] **Step 6: Commit**

```bash
git add engine/Catalog.ps1 engine/Executor.ps1 engine/Output.ps1 i18n/es.json i18n/en.json tests/Catalog.Tests.ps1 tests/Executor.Tests.ps1 tests/Output.Tests.ps1
git commit -m "feat: los ajustes que se notan al volver a iniciar sesión lo dicen en el resumen"
```

---

### Task 7: Pruebas de calidad del catálogo y `base` sin administrador

**Files:**
- Create: `tests/CatalogQuality.Tests.ps1`
- Modify: `profiles/base.json`

- [ ] **Step 1: Pruebas de calidad**

Crear `tests/CatalogQuality.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:CatalogDir = Join-Path $RepoRoot 'catalog'
    $script:ProfilesDir = Join-Path $RepoRoot 'profiles'
    $script:Catalog = @(Import-TuneupCatalog -Path $CatalogDir)
    $script:Profiles = @(Import-TuneupProfileSet -Path $ProfilesDir)
    $script:ById = @{}
    foreach ($tweak in $Catalog) { $script:ById[[string]$tweak.id] = $tweak }
    function Get-ProfileById([string]$Id) { $Profiles | Where-Object { $_.id -eq $Id } }
}

Describe 'Shipped catalog quality' {
    It 'validates without problems' {
        $Catalog.Count | Should -BeGreaterThan 0
        (Test-TuneupCatalog -Catalog $Catalog) -join "`n" | Should -BeNullOrEmpty
        (Test-TuneupProfileSet -Profiles $Profiles -Catalog $Catalog) -join "`n" | Should -BeNullOrEmpty
    }

    It 'keeps every catalog and profile file in UTF-8 without a byte order mark' {
        $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        foreach ($file in @(Get-ChildItem -LiteralPath $CatalogDir -Filter '*.json' -File) + @(Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' -File)) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse -Because "$($file.Name) has no BOM"
            { $strict.GetString($bytes) } | Should -Not -Throw -Because "$($file.Name) is UTF-8"
        }
    }

    It 'uses only the known category files' {
        $known = @('privacy', 'ads', 'ui', 'ai', 'edge', 'services', 'tasks', 'performance', 'power', 'gaming', 'dev', 'apps')
        foreach ($file in Get-ChildItem -LiteralPath $CatalogDir -Filter '*.json' -File) {
            $known | Should -Contain $file.BaseName
        }
    }

    It 'gives every tweak at least one source and a title and reason in each language' {
        foreach ($tweak in $Catalog) {
            @($tweak.sources | Where-Object { $_ }).Count | Should -BeGreaterThan 0 -Because $tweak.id
            foreach ($lang in 'es', 'en') {
                [string]$tweak.title.$lang | Should -Not -BeNullOrEmpty -Because "$($tweak.id) title.$lang"
                [string]$tweak.why.$lang | Should -Not -BeNullOrEmpty -Because "$($tweak.id) why.$lang"
            }
        }
    }

    It 'has unique ids and a different title for every tweak in each language' {
        @($Catalog | Group-Object -Property id | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) -join ', ' | Should -BeNullOrEmpty
        foreach ($lang in 'es', 'en') {
            @($Catalog | Group-Object -Property { [string]$_.title.$lang } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) -join ', ' |
                Should -BeNullOrEmpty -Because $lang
        }
    }

    It 'writes each registry value from a single tweak, except the documented alternatives' {
        # Two tweaks for the same value would undo each other. The allowed pair are alternatives that
        # the documentation tells apart (one of them is high risk and is only applied by name).
        $allowed = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry')
        $groups = $Catalog | Where-Object { $_.type -eq 'registry' } | Group-Object -Property { "$($_.set.path)|$($_.set.name)" }
        @($groups | Where-Object { $_.Count -gt 1 -and $allowed -notcontains $_.Name } | ForEach-Object { $_.Name }) -join ', ' | Should -BeNullOrEmpty
    }

    It 'uses only known requires tokens' {
        foreach ($tweak in $Catalog | Where-Object { $null -ne $_.PSObject.Properties['requires'] }) {
            foreach ($token in @($tweak.requires)) { @('battery', 'no-battery') | Should -Contain $token -Because $tweak.id }
        }
    }

    It 'finds the script of every action tweak in actions/ and loads it' {
        $loadErrors = @(Get-TuneupActionLoadError)
        foreach ($tweak in $Catalog | Where-Object { $_.type -eq 'action' }) {
            Test-Path -LiteralPath (Join-Path $RepoRoot "actions\$($tweak.set.script).ps1") -PathType Leaf | Should -BeTrue -Because $tweak.id
            @($loadErrors | Where-Object { $_.name -eq $tweak.set.script }).Count | Should -Be 0 -Because $tweak.id
        }
    }
}

Describe 'Blacklist guard' {
    BeforeAll {
        # Every comparison ignores case: Windows paths, service names and package names do.
        $script:ProtectedServices = @('WinDefend', 'WdNisSvc', 'Sense', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE', 'wuauserv', 'UsoSvc',
            'WaaSMedicSvc', 'BITS', 'DoSvc', 'InstallService', 'AppXSvc', 'ClipSVC', 'wlidsvc', 'TrustedInstaller', 'CryptSvc', 'SharedAccess',
            'LanmanServer', 'LanmanWorkstation', 'WerSvc', 'DPS', 'RmSvc', 'WpnService', 'webthreatdefsvc', 'webthreatdefusersvc', 'SysMain',
            'WSearch', 'vmcompute', 'vmms', 'hns', 'HvHost', 'LxssManager', 'WslService', 'EventLog', 'Schedule', 'Winmgmt', 'RpcSs', 'sppsvc',
            'VSS', 'swprv', 'AppIDSvc', 'Spooler')
        $script:BlockedValueNames = @('SvcHostSplitThresholdInKB', 'NetworkThrottlingIndex', 'SystemResponsiveness', 'TcpAckFrequency', 'TCPNoDelay',
            'DisableAntiSpyware', 'DisableRealtimeMonitoring', 'EnableSmartScreen', 'SmartScreenEnabled', 'NoAutoUpdate', 'DisableWindowsUpdateAccess',
            'FeatureSettingsOverride', 'FeatureSettingsOverrideMask', 'PagingFiles', 'EnableFirewall',
            'EnableLUA', 'ConsentPromptBehaviorAdmin', 'ConsentPromptBehaviorUser', 'PromptOnSecureDesktop', 'EnableVirtualization',
            'FilterAdministratorToken', 'LocalAccountTokenFilterPolicy',
            'EnableVirtualizationBasedSecurity', 'RequirePlatformSecurityFeatures', 'HypervisorEnforcedCodeIntegrity', 'LsaCfgFlags')
        $script:BlockedPathFragments = @('\Windows Defender', '\WindowsUpdate', '\WindowsFirewall', '\Session Manager\Memory Management', '\DeviceGuard')
        # The one tweak that is meant to turn memory integrity off (high risk, only with -Include).
        $script:VirtualizationSecurityException = 'gaming.memory-integrity-off'
        $script:ProtectedTaskFolders = @('\Microsoft\Windows\Windows Defender\', '\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\',
            '\Microsoft\Windows\WaaSMedic\', '\Microsoft\Windows\SystemRestore\', '\Microsoft\Windows\RecoveryEnvironment\',
            '\Microsoft\Windows\Chkdsk\', '\Microsoft\Windows\Defrag\', '\Microsoft\Windows\Servicing\', '\Microsoft\Windows\Registry\')
        $script:ProtectedTaskNames = @('Microsoft-Windows-DiskDiagnosticResolver')
        # The apps Windows needs or that people expect to keep, plus the frameworks and sign-in components.
        $script:ProtectedApps = @('Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.WindowsTerminal',
            'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad', 'Microsoft.Paint', 'Microsoft.ScreenSketch',
            'Microsoft.WindowsCamera', 'Microsoft.SecHealthUI', 'Microsoft.MicrosoftEdge*', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.XboxGameCallableUI', 'MicrosoftWindows.Client.CoreAI', 'MicrosoftWindows.Client.CBS',
            'Microsoft.NET.*', 'Microsoft.VCLibs.*', 'Microsoft.UI.Xaml.*', 'Microsoft.WindowsAppRuntime*', 'MicrosoftCorporationII.WinAppRuntime*')

        function Get-BlacklistViolation($Tweak) {
            $type = [string]$Tweak.type
            $set = $Tweak.set
            $id = [string]$Tweak.id
            if ($type -eq 'service') {
                if ($ProtectedServices -contains [string]$set.name) { "$id touches the protected service $($set.name)" }
            }
            if ($type -eq 'registry') {
                $path = [string]$set.path
                if ($BlockedValueNames -contains [string]$set.name -and $id -ne $VirtualizationSecurityException) { "$id writes the protected value $($set.name)" }
                foreach ($fragment in $BlockedPathFragments) {
                    if ($id -eq $VirtualizationSecurityException) { continue }
                    if ($path.IndexOf($fragment, [StringComparison]::OrdinalIgnoreCase) -ge 0) { "$id writes under $fragment" }
                }
                foreach ($service in $ProtectedServices) {
                    if ($path -match ('(?i)\\Services\\' + [regex]::Escape($service) + '(\\|$)')) { "$id writes the configuration of the protected service $service" }
                }
            }
            if ($type -eq 'task') {
                $folder = ([string]$set.path).TrimEnd('\') + '\'
                foreach ($protectedFolder in $ProtectedTaskFolders) {
                    # Also catches a subfolder and a path written without its final backslash.
                    if ($folder.StartsWith($protectedFolder, [StringComparison]::OrdinalIgnoreCase)) { "$id disables a task under $protectedFolder" }
                }
                if ($ProtectedTaskNames -contains [string]$set.name) { "$id disables the task $($set.name)" }
            }
            if ($type -eq 'appx') {
                foreach ($pattern in $ProtectedApps) {
                    # A wildcard in the catalog name must not slip past the list either.
                    if (([string]$set.name -like $pattern) -or ($pattern -like [string]$set.name)) { "$id removes the protected app $pattern" }
                }
            }
            if ($type -eq 'feature' -or $type -eq 'capability') {
                if ([string]$set.name -match '^(Microsoft-Hyper-V|VirtualMachinePlatform|HypervisorPlatform|Containers|Microsoft-Windows-Subsystem-Linux)') {
                    "$id touches a virtualization feature that WSL, Hyper-V or containers need"
                }
            }
        }
    }

    It 'trips no rule of the blacklist' {
        $violations = @($Catalog | ForEach-Object { Get-BlacklistViolation $_ })
        $violations -join "`n" | Should -BeNullOrEmpty
    }

    It 'keeps every protected service, task and app of the lists out of the catalog by name' {
        $services = @($Catalog | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        @($services | Where-Object { $ProtectedServices -contains $_ }) -join ', ' | Should -BeNullOrEmpty
        $apps = @($Catalog | Where-Object { $_.type -eq 'appx' } | ForEach-Object { [string]$_.set.name })
        foreach ($keep in 'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.WindowsTerminal', 'Microsoft.WindowsCalculator',
            'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad', 'Microsoft.Paint', 'Microsoft.ScreenSketch', 'Microsoft.WindowsCamera', 'Microsoft.SecHealthUI') {
            $apps | Should -Not -Contain $keep
        }
    }

    It 'catches <Name>' -TestCases @(
        # The four ways past the first version of these checks.
        @{ Name = 'a registry path written in another case'; Type = 'registry'; Set = @{ path = 'HKLM:\software\policies\microsoft\WINDOWS DEFENDER'; name = 'Foo'; kind = 'DWord'; value = 1 } }
        @{ Name = 'a value inside the key of a protected service'; Type = 'registry'; Set = @{ path = 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend'; name = 'Start'; kind = 'DWord'; value = 4 } }
        @{ Name = 'a task in a subfolder of a protected folder, in another case'; Type = 'task'; Set = @{ path = '\microsoft\windows\windowsupdate\Sub'; name = 'Any'; state = 'Disabled' } }
        @{ Name = 'a keep-list app'; Type = 'appx'; Set = @{ name = 'Microsoft.WindowsCalculator'; storeId = '9WZDNCRFHVN5'; action = 'remove' } }
        # More of the same kind.
        @{ Name = 'the Store written with a wildcard'; Type = 'appx'; Set = @{ name = 'Microsoft.Windows*'; storeId = '9WZDNCRFHVN5'; action = 'remove' } }
        @{ Name = 'a protected service in another case'; Type = 'service'; Set = @{ name = 'wuauserv'.ToUpper(); startType = 'Disabled'; stop = $true } }
        @{ Name = 'a UAC value'; Type = 'registry'; Set = @{ path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'PromptOnSecureDesktop'; kind = 'DWord'; value = 0 } }
        @{ Name = 'a UAC value for standard users'; Type = 'registry'; Set = @{ path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; name = 'ConsentPromptBehaviorUser'; kind = 'DWord'; value = 0 } }
        @{ Name = 'a virtualization-based security key'; Type = 'registry'; Set = @{ path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; name = 'EnableVirtualizationBasedSecurity'; kind = 'DWord'; value = 0 } }
        @{ Name = 'a task of the update orchestrator'; Type = 'task'; Set = @{ path = '\Microsoft\Windows\UpdateOrchestrator'; name = 'Schedule Scan'; state = 'Disabled' } }
        @{ Name = 'the disk diagnostic task'; Type = 'task'; Set = @{ path = '\Microsoft\Windows\DiskDiagnostic\'; name = 'Microsoft-Windows-DiskDiagnosticResolver'; state = 'Disabled' } }
        @{ Name = 'a virtualization feature'; Type = 'feature'; Set = @{ name = 'Microsoft-Hyper-V-All'; state = 'Disabled' } }
    ) {
        param($Type, $Set)
        $tweak = [pscustomobject]@{ id = 'test.bad'; type = $Type; set = [pscustomobject]$Set }
        @(Get-BlacklistViolation $tweak).Count | Should -BeGreaterThan 0
    }

    It 'lets a harmless tweak and the explicit memory integrity tweak through' {
        $harmless = [pscustomobject]@{ id = 'test.ok'; type = 'registry'; set = [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; kind = 'DWord'; value = 0 } }
        @(Get-BlacklistViolation $harmless).Count | Should -Be 0
        $memory = $ById['gaming.memory-integrity-off']
        $memory.risk | Should -Be 'high'
        @(Get-BlacklistViolation $memory).Count | Should -Be 0
        $copy = $memory | Select-Object -Property *
        $copy.id = 'test.other'
        @(Get-BlacklistViolation $copy).Count | Should -BeGreaterThan 0
    }
}

Describe 'Shipped profiles' {
    It 'never lists a tweak both in include and in keep of the same profile' {
        foreach ($profileData in $Profiles) {
            @(@($profileData.include) | Where-Object { @($profileData.keep) -contains $_ }) -join ', ' | Should -BeNullOrEmpty -Because $profileData.id
        }
    }

    It 'keeps base to user tweaks that need no administrator and are not policies' {
        foreach ($tweakId in @((Get-ProfileById 'base').include)) {
            $tweak = $ById[$tweakId]
            Test-TuneupUserScopedTweak -Tweak $tweak | Should -BeTrue -Because $tweakId
            Test-TuneupPolicyTweak -Tweak $tweak | Should -BeFalse -Because $tweakId
            Test-TuneupTweakNeedsAdmin -Tweak $tweak | Should -BeFalse -Because $tweakId
        }
    }

    It 'treats the HKCU policies of the catalog as needing an administrator, so base cannot hold them' {
        $policies = @($Catalog | Where-Object { $_.scope -eq 'user' -and (Test-TuneupPolicyTweak -Tweak $_) } | ForEach-Object { $_.id })
        $policies | Should -Contain 'ads.start-hide-recommended-policy'
        $policies | Should -Contain 'ai.copilot-policy-off'
        foreach ($id in $policies) { Test-TuneupTweakNeedsAdmin -Tweak $ById[$id] | Should -BeTrue -Because $id }
        foreach ($id in $policies) { @((Get-ProfileById 'base').include) | Should -Not -Contain $id }
    }

    It 'has no high-risk tweak in any profile' {
        foreach ($profileData in $Profiles) {
            foreach ($tweakId in @($profileData.include)) { $ById[$tweakId].risk | Should -Not -Be 'high' -Because "$($profileData.id) $tweakId" }
        }
    }
}
```

Las listas de "Blacklist guard" salen de la sección 4 de la especificación y de las exclusiones de la investigación; `docs/{es,en}/blacklist.md` (Task 23) explica cada caso.

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogQuality.Tests.ps1`
Expected: FAIL solo en `keeps base to user tweaks that need no administrator and are not policies`, por `services.retail-demo`.

- [ ] **Step 3: `base` solo con ajustes de usuario**

En `profiles/base.json`, reemplazar la línea `"include"` por:

```json
  "include": ["ui.show-file-extensions", "privacy.advertising-id"],
```

`services.retail-demo` sigue en el catálogo y entra en `lite` en la Task 22.

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogQuality.Tests.ps1`
Expected: PASS (`Tests Passed: 16, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`). Las pruebas de la CLI usan sus propios catálogos de `tests/fixtures`.

- [ ] **Step 5: Commit**

```bash
git add tests/CatalogQuality.Tests.ps1 profiles/base.json
git commit -m "test: calidad del catálogo y lista negra; base sin administrador"
```

---

### Task 8: Catálogo `privacy.json` (privacidad y telemetría)

**Files:**
- Modify: `catalog/privacy.json`
- Create: `tests/CatalogContent.Tests.ps1`

Reemplaza el archivo de ejemplo (que traía `privacy.advertising-id` y `privacy.tailored-experiences`, que se conservan con el mismo id). Decisiones aplicadas:

- `privacy.diagnostic-data-required` escribe `AllowTelemetry = 1` en la ruta que documenta Microsoft (`HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection`), declarada Pro/Enterprise/Education: Home ignora esa directiva y el plan lo dirá. Microsoft documenta que `0` en otras ediciones equivale a `1` (verificado en el equipo: un `0` en la ruta no documentada no impidió la subida).
- `privacy.diagnostic-data-off` (`0`) es de riesgo **alto** (solo con `-Include`), solo Enterprise/Education, y su `why` pide combinarlo con `-Exclude privacy.diagnostic-data-required`. Es la única pareja de ajustes que escribe el mismo valor (`tests/CatalogQuality.Tests.ps1` la permite por nombre).
- La ruta no documentada `CurrentVersion\Policies\DataCollection` no se usa.
- Ubicación, Encontrar mi dispositivo y el informe de errores son `medium` con `ask: true`: rompen funciones que alguien puede estar usando.
- `privacy.bing-search-off` no está: el mismo valor (`DisableSearchBoxSuggestions`) es `ads.search-box-suggestions-off` (Task 9). Las tres directivas de privacidad de Edge pasan a `edge.json` (Task 12).
- `privacy.ceip-off` y `privacy.error-reporting-off` no son rutas `\Policies\`: se aplican también en equipos administrados (son valores de Win32 documentados, no directivas).

- [ ] **Step 1: Prueba que falla**

Crear `tests/CatalogContent.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:CatalogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog'
    function Get-CategoryTweak([string]$Name) {
        @(Import-TuneupCatalog -Path $CatalogDir | Where-Object { $_.sourceFile -eq "$Name.json" })
    }
    function Get-CategoryId([string]$Name) { @(Get-CategoryTweak $Name | ForEach-Object { $_.id }) -join ',' }
}

Describe 'privacy catalog' {
    It 'ships the privacy tweaks in this order' {
        $expected = @(
            'privacy.advertising-id',
            'privacy.tailored-experiences',
            'privacy.diagnostic-data-required',
            'privacy.diagnostic-data-off',
            'privacy.feedback-never',
            'privacy.ceip-off',
            'privacy.app-launch-tracking-off',
            'privacy.online-speech-off',
            'privacy.inking-typing-improve-off',
            'privacy.input-personalization-text-off',
            'privacy.input-personalization-ink-off',
            'privacy.language-list-off',
            'privacy.activity-publish-off',
            'privacy.activity-upload-off',
            'privacy.clipboard-cloud-off',
            'privacy.location-off',
            'privacy.find-my-device-off',
            'privacy.error-reporting-off'
        ) -join ','
        Get-CategoryId 'privacy' | Should -Be $expected
    }

    It 'keeps diagnostic data off as a high-risk alternative for Enterprise and Education only' {
        $off = Get-CategoryTweak 'privacy' | Where-Object { $_.id -eq 'privacy.diagnostic-data-off' }
        $off.risk | Should -Be 'high'
        @($off.os.editions) -join ',' | Should -Be 'Enterprise,Education'
        $required = Get-CategoryTweak 'privacy' | Where-Object { $_.id -eq 'privacy.diagnostic-data-required' }
        $required.set.value | Should -Be 1
        @($required.os.editions) -join ',' | Should -Be 'Pro,Enterprise,Education'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `privacy catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/privacy.json`**

Contenido completo de `catalog/privacy.json` (18 ajustes):

```json
{
  "tweaks": [
    {
      "id": "privacy.advertising-id",
      "title": { "es": "Desactivar el ID de publicidad", "en": "Disable the advertising ID" },
      "why": { "es": "Las apps lo usan para mostrarte anuncios personalizados.", "en": "Apps use it to show you personalized ads." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo", "name": "Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services"]
    },
    {
      "id": "privacy.tailored-experiences",
      "title": { "es": "Desactivar experiencias personalizadas con datos de diagnóstico", "en": "Disable tailored experiences based on diagnostic data" },
      "why": { "es": "Evita que Microsoft use tus datos de diagnóstico para sugerencias y anuncios.", "en": "Stops Microsoft from using your diagnostic data for tips and ads." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Privacy", "name": "TailoredExperiencesWithDiagnosticDataEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services"]
    },
    {
      "id": "privacy.diagnostic-data-required",
      "title": { "es": "Enviar solo los datos de diagnóstico requeridos", "en": "Send only required diagnostic data" },
      "why": { "es": "Impide los datos de diagnóstico opcionales (uso, navegación, volcados); Requerido es el mínimo en Pro. Las compilaciones de Windows Insider necesitan los datos opcionales: no lo apliques en un equipo del programa Insider.", "en": "Blocks optional diagnostic data (usage, browsing, crash dumps); Required is the minimum on Pro. Windows Insider builds need optional data: do not apply it on an Insider device." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection", "name": "AllowTelemetry", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system", "https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services"]
    },
    {
      "id": "privacy.diagnostic-data-off",
      "title": { "es": "Apagar los datos de diagnóstico (Enterprise y Education)", "en": "Turn diagnostic data off (Enterprise and Education)" },
      "why": { "es": "Windows no envía datos de diagnóstico, ni los de Windows Update. Solo existe en Enterprise y Education; aplícalo junto con -Exclude privacy.diagnostic-data-required.", "en": "Windows sends no diagnostic data, not even for Windows Update. Only exists on Enterprise and Education; apply it together with -Exclude privacy.diagnostic-data-required." },
      "risk": "high",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection", "name": "AllowTelemetry", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system"]
    },
    {
      "id": "privacy.feedback-never",
      "title": { "es": "No pedir comentarios a Microsoft", "en": "Never ask for feedback" },
      "why": { "es": "Quita las ventanas que piden valorar Windows.", "en": "Removes the pop-ups that ask you to rate Windows." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Siuf\\Rules", "name": "NumberOfSIUFInPeriod", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "privacy.ceip-off",
      "title": { "es": "Desactivar el Programa de mejora de la experiencia", "en": "Turn off the Customer Experience Improvement Program" },
      "why": { "es": "Evita que Windows envíe estadísticas de uso por el CEIP.", "en": "Stops Windows from sending usage statistics through the CEIP." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\SQMClient\\Windows", "name": "CEIPEnable", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/win32/devnotes/ceipenable", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-icm"]
    },
    {
      "id": "privacy.app-launch-tracking-off",
      "title": { "es": "No registrar qué apps abres", "en": "Stop tracking app launches" },
      "why": { "es": "Windows deja de contar tus aperturas para ordenar Inicio y la búsqueda.", "en": "Windows stops counting your app launches to rank Start and search." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "Start_TrackProgs", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg"]
    },
    {
      "id": "privacy.online-speech-off",
      "title": { "es": "Desactivar el reconocimiento de voz en línea", "en": "Turn off online speech recognition" },
      "why": { "es": "Tu voz no se envía a Microsoft; el dictado de Win+H deja de funcionar.", "en": "Your voice is not sent to Microsoft; Win+H dictation stops working." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Speech_OneCore\\Settings\\OnlineSpeechPrivacy", "name": "HasAccepted", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://support.microsoft.com/en-us/windows/privacy/speech-voice-activation-inking-typing-and-privacy", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "privacy.inking-typing-improve-off",
      "title": { "es": "No enviar cómo escribes para mejorar el teclado", "en": "Do not send how you type to improve inking and typing" },
      "why": { "es": "Microsoft deja de recibir muestras de tu escritura y tinta.", "en": "Microsoft stops receiving samples of your typing and inking." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Input\\TIPC", "name": "Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://support.microsoft.com/en-us/windows/privacy/speech-voice-activation-inking-typing-and-privacy", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "privacy.input-personalization-text-off",
      "title": { "es": "Desactivar el aprendizaje de lo que escribes", "en": "Turn off typing personalization" },
      "why": { "es": "Windows deja de recopilar tu texto para personalizar sugerencias.", "en": "Windows stops collecting your text to personalize suggestions." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\InputPersonalization", "name": "RestrictImplicitTextCollection", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg"]
    },
    {
      "id": "privacy.input-personalization-ink-off",
      "title": { "es": "Desactivar el aprendizaje de tu escritura a mano", "en": "Turn off handwriting personalization" },
      "why": { "es": "Windows deja de recopilar tu tinta para personalizar el reconocimiento.", "en": "Windows stops collecting your ink to personalize recognition." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\InputPersonalization", "name": "RestrictImplicitInkCollection", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg"]
    },
    {
      "id": "privacy.language-list-off",
      "title": { "es": "No compartir tu lista de idiomas con los sitios web", "en": "Do not share your language list with websites" },
      "why": { "es": "Evita que los sitios vean los idiomas que tienes instalados.", "en": "Stops websites from seeing the languages you have installed." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Control Panel\\International\\User Profile", "name": "HttpAcceptLanguageOptOut", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services"]
    },
    {
      "id": "privacy.activity-publish-off",
      "title": { "es": "No publicar el historial de actividad", "en": "Do not publish activity history" },
      "why": { "es": "Windows no registra qué apps y archivos usaste para la línea de tiempo.", "en": "Windows does not record the apps and files you used for the activity timeline." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System", "name": "PublishUserActivities", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg"]
    },
    {
      "id": "privacy.activity-upload-off",
      "title": { "es": "No subir el historial de actividad a Microsoft", "en": "Do not upload activity history to Microsoft" },
      "why": { "es": "Tu historial de actividad no se envía a la nube ni a tus otros equipos.", "en": "Your activity history is not sent to the cloud or your other devices." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System", "name": "UploadUserActivities", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "privacy.clipboard-cloud-off",
      "title": { "es": "Desactivar el portapapeles en la nube", "en": "Turn off cloud clipboard sync" },
      "why": { "es": "Lo que copias no viaja a tus otros equipos; el historial local de Win+V sigue funcionando.", "en": "What you copy does not roam to other devices; local Win+V history keeps working." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System", "name": "AllowCrossDeviceClipboard", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy"]
    },
    {
      "id": "privacy.location-off",
      "title": { "es": "Desactivar la ubicación del equipo", "en": "Turn off device location" },
      "why": { "es": "Ninguna app usa tu ubicación; el clima automático, Mapas y la zona horaria automática dejan de funcionar.", "en": "No app can use your location; automatic weather, Maps and automatic time zone stop working." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\LocationAndSensors", "name": "DisableLocation", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Location_Services.reg"]
    },
    {
      "id": "privacy.find-my-device-off",
      "title": { "es": "Desactivar Encontrar mi dispositivo", "en": "Turn off Find My Device" },
      "why": { "es": "El equipo deja de registrar su ubicación en tu cuenta Microsoft; no podrás localizarlo si lo pierdes.", "en": "The PC stops registering its location with your Microsoft account; you cannot locate it if lost." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\FindMyDevice", "name": "AllowFindMyDevice", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Find_My_Device.reg", "https://learn.microsoft.com/windows/client-management/mdm/policy-csp-experience"]
    },
    {
      "id": "privacy.error-reporting-off",
      "title": { "es": "Desactivar el informe de errores de Windows", "en": "Turn off Windows Error Reporting" },
      "why": { "es": "Los bloqueos no se envían a Microsoft; sin informes no llegan soluciones a problemas de controladores.", "en": "Crashes are not sent to Microsoft; without reports no fixes arrive for driver problems." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting", "name": "Disabled", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/win32/wer/wer-settings", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'privacy.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
privacy.advertising-id                        applied
privacy.tailored-experiences                  applied
privacy.diagnostic-data-required              not-applied
privacy.diagnostic-data-off                   not-applied
privacy.feedback-never                        applied
privacy.ceip-off                              applied
privacy.app-launch-tracking-off               applied
privacy.online-speech-off                     applied
privacy.inking-typing-improve-off             applied
privacy.input-personalization-text-off        applied
privacy.input-personalization-ink-off         applied
privacy.language-list-off                     not-applied
privacy.activity-publish-off                  applied
privacy.activity-upload-off                   not-applied
privacy.clipboard-cloud-off                   not-applied
privacy.location-off                          not-applied
privacy.find-my-device-off                    not-applied
privacy.error-reporting-off                   not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/privacy.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de privacidad y telemetría"
```

---

### Task 9: Catálogo `ads.json` (anuncios y sugerencias)

**Files:**
- Create: `catalog/ads.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Archivo nuevo. Casi todo es `HKCU` sin directivas (los interruptores de Configuración: sugerencias de Inicio, consejos, contenido sugerido, pantalla de bloqueo): es lo que `base` puede aplicar sin administrador. Decisiones aplicadas:

- `ads.consumer-features` (`DisableWindowsConsumerFeatures`) y `ads.settings-home-365` (`DisableConsumerAccountStateContent`) se declaran solo Enterprise/Education, como documenta Microsoft; `ads.start-hide-recommended-policy` (`HideRecommendedSection`) incluye Pro porque el CSP de Start lo lista así. En Home el mismo efecto sale de los interruptores de usuario (`ads.start-recommendations`, `ads.start-recent-*`, `ads.start-most-used-off`).
- `ads.start-hide-recommended-policy` y `ads.search-box-suggestions-off` son directivas bajo HKCU: exigen administrador (ver la Task 7) y no van en `base`.
- Un ajuste por valor de registro: el catálogo no tiene tipo multi-valor (decisión 4f), por eso "contenido sugerido en Configuración" son tres ajustes (1/3, 2/3, 3/3).
- `ads.search-box-suggestions-off` es el único dueño de `DisableSearchBoxSuggestions`.

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'ads catalog' {
    It 'ships the ads tweaks in this order' {
        $expected = @(
            'ads.start-suggestions',
            'ads.start-system-pane',
            'ads.start-recommendations',
            'ads.start-account-notifications',
            'ads.tips-and-tricks',
            'ads.welcome-experience',
            'ads.settings-suggestions-1',
            'ads.settings-suggestions-2',
            'ads.settings-suggestions-3',
            'ads.finish-setup-prompts',
            'ads.sync-provider-notifications',
            'ads.silent-installed-apps',
            'ads.suggested-notifications',
            'ads.phone-link-suggestions',
            'ads.backup-reminders',
            'ads.start-phone-link',
            'ads.lockscreen-tips',
            'ads.lockscreen-overlay',
            'ads.consumer-features',
            'ads.settings-home-365',
            'ads.start-hide-recommended-policy',
            'ads.start-recent-files-off',
            'ads.start-recent-apps-off',
            'ads.start-most-used-off',
            'ads.bing-search-off',
            'ads.search-box-suggestions-off',
            'ads.search-highlights-off',
            'ads.search-history-off'
        ) -join ','
        Get-CategoryId 'ads' | Should -Be $expected
    }

    It 'declares the policies that only Enterprise and Education honor' {
        foreach ($id in 'ads.consumer-features', 'ads.settings-home-365') {
            @((Get-CategoryTweak 'ads' | Where-Object { $_.id -eq $id }).os.editions) -join ',' | Should -Be 'Enterprise,Education' -Because $id
        }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `ads catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/ads.json`**

Contenido completo de `catalog/ads.json` (28 ajustes):

```json
{
  "tweaks": [
    {
      "id": "ads.start-suggestions",
      "title": { "es": "Sin sugerencias en Inicio", "en": "No suggestions in Start" },
      "why": { "es": "Windows deja de mostrar apps sugeridas en el menú Inicio.", "en": "Windows stops showing suggested apps in the Start menu." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-338388Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.start-system-pane",
      "title": { "es": "Sin sugerencias en el panel de Inicio", "en": "No suggestions in the Start pane" },
      "why": { "es": "Quita las sugerencias de aplicaciones del panel del sistema.", "en": "Removes app suggestions from the system pane." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SystemPaneSuggestionsEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg"]
    },
    {
      "id": "ads.start-recommendations",
      "title": { "es": "Sin consejos y apps nuevas en Recomendado", "en": "No tips and new apps in Recommended" },
      "why": { "es": "Oculta los consejos, atajos y apps nuevas de la sección Recomendado de Inicio.", "en": "Hides tips, shortcuts and new apps in the Start Recommended section." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "Start_IrisRecommendations", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.start-account-notifications",
      "title": { "es": "Sin avisos de cuenta en Inicio", "en": "No account notifications in Start" },
      "why": { "es": "Quita los avisos sobre tu cuenta Microsoft (copias de seguridad, ofertas) del menú Inicio.", "en": "Removes Microsoft account notices (backup, offers) from the Start menu." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22000, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "Start_AccountNotifications", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.tips-and-tricks",
      "title": { "es": "Sin consejos y trucos de Windows", "en": "No Windows tips and tricks" },
      "why": { "es": "Evita las notificaciones con consejos y sugerencias mientras usas Windows.", "en": "Stops the tips and suggestions notifications while you use Windows." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-338389Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.welcome-experience",
      "title": { "es": "Sin pantalla de bienvenida tras actualizar", "en": "No welcome screen after updates" },
      "why": { "es": "Quita la pantalla \"qué hay de nuevo\" que aparece tras actualizar o iniciar sesión.", "en": "Removes the \"what's new\" screen shown after updates or sign-in." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-310093Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.settings-suggestions-1",
      "title": { "es": "Sin contenido sugerido en Configuración (1/3)", "en": "No suggested content in Settings (1/3)" },
      "why": { "es": "Quita el contenido sugerido de la aplicación Configuración.", "en": "Removes suggested content from the Settings app." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-338393Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.settings-suggestions-2",
      "title": { "es": "Sin contenido sugerido en Configuración (2/3)", "en": "No suggested content in Settings (2/3)" },
      "why": { "es": "Quita el contenido sugerido de la aplicación Configuración.", "en": "Removes suggested content from the Settings app." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-353694Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.settings-suggestions-3",
      "title": { "es": "Sin contenido sugerido en Configuración (3/3)", "en": "No suggested content in Settings (3/3)" },
      "why": { "es": "Quita el contenido sugerido de la aplicación Configuración.", "en": "Removes suggested content from the Settings app." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-353696Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.finish-setup-prompts",
      "title": { "es": "Sin avisos para terminar de configurar el equipo", "en": "No prompts to finish setting up the device" },
      "why": { "es": "Quita las sugerencias para \"sacar más partido a Windows\".", "en": "Removes the \"get the most out of Windows\" suggestions." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\UserProfileEngagement", "name": "ScoobeSystemSettingEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.sync-provider-notifications",
      "title": { "es": "Sin anuncios de OneDrive y Microsoft 365 en el Explorador", "en": "No OneDrive and Microsoft 365 promos in File Explorer" },
      "why": { "es": "Oculta las notificaciones promocionales de proveedores de sincronización.", "en": "Hides promotional sync provider notifications." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "ShowSyncProviderNotifications", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.silent-installed-apps",
      "title": { "es": "Sin instalación silenciosa de apps sugeridas", "en": "No silent installs of suggested apps" },
      "why": { "es": "Evita que Windows instale apps sugeridas sin preguntar.", "en": "Stops Windows from installing suggested apps without asking." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SilentInstalledAppsEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.suggested-notifications",
      "title": { "es": "Sin notificaciones de apps sugeridas", "en": "No suggested-app notifications" },
      "why": { "es": "Desactiva los avisos \"Sugerido\" que promocionan servicios de Microsoft.", "en": "Turns off the \"Suggested\" toasts that promote Microsoft services." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings\\Windows.SystemToast.Suggested", "name": "Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg"]
    },
    {
      "id": "ads.phone-link-suggestions",
      "title": { "es": "Sin sugerencias para vincular el móvil", "en": "No suggestions to link your phone" },
      "why": { "es": "Quita las sugerencias de usar el teléfono con Windows.", "en": "Removes the suggestions to use your phone with Windows." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Mobility", "name": "OptedIn", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg"]
    },
    {
      "id": "ads.backup-reminders",
      "title": { "es": "Sin recordatorios de Copia de seguridad de Windows", "en": "No Windows Backup reminders" },
      "why": { "es": "Quita los avisos que insisten en activar Windows Backup con OneDrive.", "en": "Removes the nags that push you to enable Windows Backup with OneDrive." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22000, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings\\Windows.SystemToast.BackupReminder", "name": "Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg"]
    },
    {
      "id": "ads.start-phone-link",
      "title": { "es": "Sin el móvil vinculado en Inicio", "en": "No linked phone in Start" },
      "why": { "es": "Oculta el panel de Vínculo con el móvil del menú Inicio.", "en": "Hides the Phone Link panel in the Start menu." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Start\\Companions\\Microsoft.YourPhone_8wekyb3d8bbwe", "name": "IsEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Phone_Link_In_Start.reg"]
    },
    {
      "id": "ads.lockscreen-tips",
      "title": { "es": "Sin datos curiosos ni consejos en la pantalla de bloqueo", "en": "No fun facts or tips on the lock screen" },
      "why": { "es": "Quita los consejos y sugerencias sobre el fondo de la pantalla de bloqueo.", "en": "Removes tips and suggestions over the lock screen background." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "SubscribedContent-338387Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Lockscreen_Tips.reg"]
    },
    {
      "id": "ads.lockscreen-overlay",
      "title": { "es": "Sin recuadro de datos sobre el fondo de bloqueo", "en": "No info overlay on the lock screen picture" },
      "why": { "es": "Quita el recuadro con datos y enlaces que Spotlight pone sobre la imagen.", "en": "Removes the box with facts and links that Spotlight puts over the picture." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "name": "RotatingLockScreenOverlayEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Lockscreen_Tips.reg"]
    },
    {
      "id": "ads.consumer-features",
      "title": { "es": "Sin experiencias de consumo de Microsoft", "en": "No Microsoft consumer experiences" },
      "why": { "es": "Impide las apps promocionadas y las instalaciones tras la primera configuración (solo Enterprise y Education).", "en": "Blocks promoted apps and post-setup installs (Enterprise and Education only)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent", "name": "DisableWindowsConsumerFeatures", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "ads.settings-home-365",
      "title": { "es": "Sin anuncios de Microsoft 365 en Configuración", "en": "No Microsoft 365 ads in Settings" },
      "why": { "es": "Oculta el contenido de cuenta en la nube (Microsoft 365 y similares) de la página de inicio de Configuración. Microsoft documenta la directiva solo para Enterprise y Education; en otras ediciones puede no tener efecto.", "en": "Hides the cloud account content (Microsoft 365 and similar) on the Settings home page. Microsoft documents the policy for Enterprise and Education only; on other editions it may have no effect." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22000, "editions": ["Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent", "name": "DisableConsumerAccountStateContent", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Settings_365_Ads.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience"]
    },
    {
      "id": "ads.start-hide-recommended-policy",
      "title": { "es": "Ocultar la sección Recomendado de Inicio (directiva)", "en": "Hide the Start Recommended section (policy)" },
      "why": { "es": "Quita por directiva la sección de archivos y apps recomendados (Pro, Enterprise y Education, según la documentación de Microsoft).", "en": "Removes the recommended files and apps section by policy (Pro, Enterprise and Education, according to Microsoft documentation)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer", "name": "HideRecommendedSection", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Start_Recommended.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-start"]
    },
    {
      "id": "ads.start-recent-files-off",
      "title": { "es": "Sin archivos recientes en Inicio ni en el Explorador", "en": "No recent files in Start and File Explorer" },
      "why": { "es": "Deja de registrar y mostrar archivos abiertos recientemente en Inicio, listas de salto y Acceso rápido.", "en": "Stops tracking and showing recently opened files in Start, jump lists and Quick access." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "Start_TrackDocs", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.start-recent-apps-off",
      "title": { "es": "Sin apps agregadas recientemente en Inicio", "en": "No recently added apps in Start" },
      "why": { "es": "Oculta la lista de apps agregadas recientemente.", "en": "Hides the recently added apps list." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22000, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Start", "name": "ShowRecentList", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.start-most-used-off",
      "title": { "es": "Sin apps más usadas en Inicio", "en": "No most-used apps in Start" },
      "why": { "es": "Oculta la lista de apps más usadas.", "en": "Hides the most-used apps list." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22000, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Start", "name": "ShowFrequentList", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.bing-search-off",
      "title": { "es": "Sin resultados de Bing en la búsqueda de Windows", "en": "No Bing web results in Windows search" },
      "why": { "es": "La búsqueda de Inicio no envía lo que escribes a Bing.", "en": "Start search no longer sends what you type to Bing." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search", "name": "BingSearchEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.search-box-suggestions-off",
      "title": { "es": "Sin sugerencias web en el cuadro de búsqueda (directiva)", "en": "No web suggestions in the search box (policy)" },
      "why": { "es": "Directiva de usuario que apaga las sugerencias de búsqueda en línea del cuadro de búsqueda.", "en": "User policy that turns off online suggestions in the search box." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer", "name": "DisableSearchBoxSuggestions", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Bing_Cortana_In_Search.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.search-highlights-off",
      "title": { "es": "Sin Búsqueda destacada", "en": "No search highlights" },
      "why": { "es": "Quita la ilustración y el contenido de actualidad del cuadro de búsqueda.", "en": "Removes the doodle and trending content from the search box." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19043, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\SearchSettings", "name": "IsDynamicSearchBoxEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Search_Highlights.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ads.search-history-off",
      "title": { "es": "Sin historial de búsqueda en este equipo", "en": "No search history on this device" },
      "why": { "es": "Deja de guardar lo que buscas en Windows.", "en": "Stops saving what you search for in Windows." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\SearchSettings", "name": "IsDeviceSearchHistoryEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Search_History.reg"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'ads.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
ads.start-suggestions                         applied
ads.start-system-pane                         applied
ads.start-recommendations                     applied
ads.start-account-notifications               applied
ads.tips-and-tricks                           applied
ads.welcome-experience                        applied
ads.settings-suggestions-1                    applied
ads.settings-suggestions-2                    applied
ads.settings-suggestions-3                    applied
ads.finish-setup-prompts                      applied
ads.sync-provider-notifications               applied
ads.silent-installed-apps                     applied
ads.suggested-notifications                   applied
ads.phone-link-suggestions                    applied
ads.backup-reminders                          applied
ads.start-phone-link                          applied
ads.lockscreen-tips                           applied
ads.lockscreen-overlay                        applied
ads.consumer-features                         not-applied
ads.settings-home-365                         applied
ads.start-hide-recommended-policy             applied
ads.start-recent-files-off                    not-applied
ads.start-recent-apps-off                     not-applied
ads.start-most-used-off                       applied
ads.bing-search-off                           not-applied
ads.search-box-suggestions-off                applied
ads.search-highlights-off                     not-applied
ads.search-history-off                        not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/ads.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de anuncios y sugerencias"
```

---

### Task 10: Catálogo `ui.json` (interfaz)

**Files:**
- Modify: `catalog/ui.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Reemplaza el archivo de ejemplo y conserva `ui.show-file-extensions` igual. Decisiones aplicadas:

- `ui.show-hidden-files` y `ui.taskbar-end-task` son los únicos dueños de esos valores (el informe de desarrollo los repetía como `dev.*`); el perfil `dev` los incluye.
- Widgets se apaga con la directiva de máquina (`Dsh\AllowNewsAndInterests`, Pro y superiores). `TaskbarDa` (`HKCU`) no se usa: Windows bloquea su escritura desde PowerShell (servicio UCPD).
- `TaskbarAnimations` no entra: sin efecto demostrado en Windows 11. Las animaciones se cubren con `MinAnimate`, `ListviewShadow`, `ListviewAlphaSelect` y `EnableAeroPeek`; la máscara binaria `UserPreferencesMask` espera el tipo `Binary` (decisión 4f).
- `signOutRequired: true` donde el cambio se ve al volver a iniciar sesión o al reiniciar el Explorador: Widgets, animación de ventanas, sombras, selección translúcida y Aero Peek.

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'ui catalog' {
    It 'ships the ui tweaks in this order' {
        $expected = @(
            'ui.show-file-extensions',
            'ui.show-hidden-files',
            'ui.taskbar-end-task',
            'ui.task-view-button-off',
            'ui.widgets-off',
            'ui.news-interests-win10',
            'ui.meet-now-win10',
            'ui.transparency-off',
            'ui.window-animations-off',
            'ui.listview-shadow-off',
            'ui.listview-alpha-select-off',
            'ui.aero-peek-off'
        ) -join ','
        Get-CategoryId 'ui' | Should -Be $expected
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `ui catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/ui.json`**

Contenido completo de `catalog/ui.json` (12 ajustes):

```json
{
  "tweaks": [
    {
      "id": "ui.show-file-extensions",
      "title": { "es": "Mostrar las extensiones de archivo", "en": "Show file extensions" },
      "why": { "es": "Permite distinguir un documento de un ejecutable disfrazado (factura.pdf.exe).", "en": "Lets you tell a document from a disguised executable (invoice.pdf.exe)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "HideFileExt", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Show_Extensions_For_Known_File_Types.reg"]
    },
    {
      "id": "ui.show-hidden-files",
      "title": { "es": "Mostrar archivos y carpetas ocultos", "en": "Show hidden files and folders" },
      "why": { "es": "Útil al programar: deja ver .git, AppData y otros elementos ocultos.", "en": "Useful for development: shows .git, AppData and other hidden items." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "Hidden", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Show_Hidden_Folders.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ui.taskbar-end-task",
      "title": { "es": "\"Finalizar tarea\" en la barra de tareas", "en": "\"End task\" in the taskbar" },
      "why": { "es": "Agrega Finalizar tarea al menú contextual de las apps de la barra de tareas.", "en": "Adds End task to the taskbar app context menu." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22631, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings", "name": "TaskbarEndTask", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Enable_End_Task.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ui.task-view-button-off",
      "title": { "es": "Ocultar el botón Vista de tareas", "en": "Hide the Task View button" },
      "why": { "es": "Libera espacio en la barra de tareas; Win+Tab sigue funcionando.", "en": "Frees taskbar space; Win+Tab still works." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "ShowTaskViewButton", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Hide_Taskview_Taskbar.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "ui.widgets-off",
      "title": { "es": "Desactivar Widgets (directiva)", "en": "Turn off Widgets (policy)" },
      "why": { "es": "Quita el panel de Widgets y sus procesos web en segundo plano. No funciona en Home.", "en": "Removes the Widgets board and its background web processes. Does not work on Home." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22000, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Dsh", "name": "AllowNewsAndInterests", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "ui.news-interests-win10",
      "title": { "es": "Desactivar Noticias e intereses (Windows 10)", "en": "Turn off News and interests (Windows 10)" },
      "why": { "es": "Quita el widget de noticias de la barra de tareas de Windows 10.", "en": "Removes the news widget from the Windows 10 taskbar." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Feeds", "name": "EnableFeeds", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_10/Module/Sophia.psm1"]
    },
    {
      "id": "ui.meet-now-win10",
      "title": { "es": "Ocultar Reunirse ahora (Windows 10)", "en": "Hide Meet Now (Windows 10)" },
      "why": { "es": "Quita el icono de Reunirse ahora de la barra de tareas de Windows 10.", "en": "Removes the Meet Now icon from the Windows 10 taskbar." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer", "name": "HideSCAMeetNow", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Chat_Taskbar.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_10/Module/Sophia.psm1"]
    },
    {
      "id": "ui.transparency-off",
      "title": { "es": "Desactivar la transparencia", "en": "Turn off transparency effects" },
      "why": { "es": "Menos trabajo para la GPU en equipos modestos.", "en": "Less GPU work on modest machines." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", "name": "EnableTransparency", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Transparency.reg"]
    },
    {
      "id": "ui.window-animations-off",
      "title": { "es": "Sin animación al minimizar y maximizar", "en": "No minimize and maximize animation" },
      "why": { "es": "Las ventanas aparecen y desaparecen sin animación; se nota al volver a iniciar sesión.", "en": "Windows appear and disappear without animation; applies after you sign in again." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Control Panel\\Desktop\\WindowMetrics", "name": "MinAnimate", "kind": "String", "value": "0" },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "ui.listview-shadow-off",
      "title": { "es": "Sin sombra en las etiquetas de iconos", "en": "No shadow on icon labels" },
      "why": { "es": "Quita la sombra del texto de los iconos del escritorio.", "en": "Removes the shadow from desktop icon labels." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "ListviewShadow", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "ui.listview-alpha-select-off",
      "title": { "es": "Sin selección translúcida", "en": "No translucent selection rectangle" },
      "why": { "es": "El rectángulo de selección es sólido, sin efecto de transparencia.", "en": "The selection rectangle is solid, without transparency." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "ListviewAlphaSelect", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "ui.aero-peek-off",
      "title": { "es": "Sin vista previa al pasar sobre el escritorio", "en": "No Peek at desktop preview" },
      "why": { "es": "Desactiva Aero Peek, que redibuja las ventanas al pasar el ratón por la esquina de la barra.", "en": "Turns off Aero Peek, which redraws windows when you hover the taskbar corner." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\DWM", "name": "EnableAeroPeek", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'ui.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
ui.show-file-extensions                       applied
ui.show-hidden-files                          not-applied
ui.taskbar-end-task                           applied
ui.task-view-button-off                       not-applied
ui.widgets-off                                not-applied
ui.news-interests-win10                       not-applied
ui.meet-now-win10                             applied
ui.transparency-off                           not-applied
ui.window-animations-off                      not-applied
ui.listview-shadow-off                        not-applied
ui.listview-alpha-select-off                  not-applied
ui.aero-peek-off                              not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/ui.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de interfaz"
```

---

### Task 11: Catálogo `ai.json` (Copilot, Recall e IA)

**Files:**
- Create: `catalog/ai.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Archivo nuevo. Decisiones aplicadas:

- Recall en dos capas: la directiva de usuario (`DisableAIDataAnalysis`) y la de máquina (`AllowRecallEnablement = 0`, pide reinicio). Las dos borran capturas existentes y `deshacer` no puede devolverlas: `high` con `ask: true`, solo con `-Include`.
- Solo las funciones de IA **en la nube** de Paint y del Bloc de notas; las locales (quitar fondo, borrado generativo) no.
- `ai.fabric-service-manual` deja `WSAIFabricSvc` en `Manual` (no `Disabled`): las funciones locales lo piden a demanda.
- La app Copilot no está aquí: es `apps.copilot` (Task 21). Nunca se toca `MicrosoftWindows.Client.CoreAI` (`NonRemovable`).
- `ai.copilot-button-off` lleva `signOutRequired: true` (el botón desaparece al reiniciar el Explorador).

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'ai catalog' {
    It 'ships the ai tweaks in this order' {
        $expected = @(
            'ai.copilot-button-off',
            'ai.copilot-policy-off',
            'ai.recall-snapshots-off',
            'ai.recall-unavailable',
            'ai.click-to-do-off',
            'ai.notepad-ai-off',
            'ai.paint-cocreator-off',
            'ai.paint-image-creator-off',
            'ai.paint-generative-fill-off',
            'ai.fabric-service-manual'
        ) -join ','
        Get-CategoryId 'ai' | Should -Be $expected
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `ai catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/ai.json`**

Contenido completo de `catalog/ai.json` (10 ajustes):

```json
{
  "tweaks": [
    {
      "id": "ai.copilot-button-off",
      "title": { "es": "Ocultar el botón de Copilot", "en": "Hide the Copilot button" },
      "why": { "es": "Quita el icono de Copilot de la barra de tareas.", "en": "Removes the Copilot icon from the taskbar." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", "name": "ShowCopilotButton", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Copilot.reg"]
    },
    {
      "id": "ai.copilot-policy-off",
      "title": { "es": "Desactivar Windows Copilot (directiva de usuario)", "en": "Turn off Windows Copilot (user policy)" },
      "why": { "es": "Directiva (en desuso) que apaga el panel de Copilot; no cubre la app nueva.", "en": "Deprecated policy that turns off the Copilot pane; it does not cover the new app." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19045, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\WindowsCopilot", "name": "TurnOffWindowsCopilot", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Copilot.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.recall-snapshots-off",
      "title": { "es": "Recall: no guardar capturas (directiva de usuario)", "en": "Recall: do not save snapshots (user policy)" },
      "why": { "es": "Impide que Recall guarde capturas de pantalla y borra las que ya existen; deshacer no puede devolverlas.", "en": "Stops Recall from saving screenshots and deletes the ones that exist; undo cannot bring them back." },
      "risk": "high",
      "ask": true,
      "os": { "families": ["11"], "minBuild": 26100, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\WindowsAI", "name": "DisableAIDataAnalysis", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_AI_Recall.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.recall-unavailable",
      "title": { "es": "Recall: no disponible en el equipo", "en": "Recall: not available on the device" },
      "why": { "es": "Quita Recall del equipo (hace falta reiniciar) y borra las capturas guardadas; deshacer no puede devolverlas.", "en": "Removes Recall from the device (needs a restart) and deletes saved snapshots; undo cannot bring them back." },
      "risk": "high",
      "ask": true,
      "os": { "families": ["11"], "minBuild": 26100, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsAI", "name": "AllowRecallEnablement", "kind": "DWord", "value": 0 },
      "rebootRequired": true,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_AI_Recall.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.click-to-do-off",
      "title": { "es": "Desactivar Click to Do", "en": "Turn off Click to Do" },
      "why": { "es": "Apaga el análisis de pantalla de Click to Do (usuario).", "en": "Turns off Click to Do screen analysis (user)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 26100, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\WindowsAI", "name": "DisableClickToDo", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Click_to_Do.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.notepad-ai-off",
      "title": { "es": "Bloc de notas sin funciones de IA", "en": "Notepad without AI features" },
      "why": { "es": "Desactiva Reescribir, Resumir y otras funciones de IA del Bloc de notas.", "en": "Turns off Rewrite, Summarize and other AI features in Notepad." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\WindowsNotepad", "name": "DisableAIFeatures", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows/client-management/manage-notepad", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Notepad_AI_Features.reg"]
    },
    {
      "id": "ai.paint-cocreator-off",
      "title": { "es": "Paint sin Cocreator", "en": "Paint without Cocreator" },
      "why": { "es": "Desactiva Cocreator en Paint (función de IA en la nube).", "en": "Turns off Cocreator in Paint (cloud AI feature)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Paint", "name": "DisableCocreator", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Paint_AI_Features.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.paint-image-creator-off",
      "title": { "es": "Paint sin Image Creator", "en": "Paint without Image Creator" },
      "why": { "es": "Desactiva Image Creator en Paint (función de IA en la nube).", "en": "Turns off Image Creator in Paint (cloud AI feature)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Paint", "name": "DisableImageCreator", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Paint_AI_Features.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.paint-generative-fill-off",
      "title": { "es": "Paint sin Relleno generativo", "en": "Paint without Generative fill" },
      "why": { "es": "Desactiva Relleno generativo en Paint (función de IA en la nube).", "en": "Turns off Generative fill in Paint (cloud AI feature)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Paint", "name": "DisableGenerativeFill", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Paint_AI_Features.reg", "https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai"]
    },
    {
      "id": "ai.fabric-service-manual",
      "title": { "es": "Servicio de estructura de IA solo a petición", "en": "AI Fabric service on demand only" },
      "why": { "es": "WSAIFabricSvc deja de arrancar siempre con Windows; se inicia cuando una función de IA lo pide.", "en": "WSAIFabricSvc no longer always starts with Windows; it starts when an AI feature asks for it." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 26100, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "WSAIFabricSvc", "startType": "Manual", "stop": false },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_AI_Service_Auto_Start.reg", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'ai.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
ai.copilot-button-off                         applied
ai.copilot-policy-off                         applied
ai.recall-snapshots-off                       applied
ai.recall-unavailable                         applied
ai.click-to-do-off                            applied
ai.notepad-ai-off                             applied
ai.paint-cocreator-off                        applied
ai.paint-image-creator-off                    applied
ai.paint-generative-fill-off                  applied
ai.fabric-service-manual                      applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/ai.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de Copilot, Recall e IA"
```

---

### Task 12: Catálogo `edge.json` (Microsoft Edge)

**Files:**
- Create: `catalog/edge.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Archivo nuevo, todo directivas de máquina en `HKLM:\SOFTWARE\Policies\Microsoft\Edge`. Decisiones aplicadas:

- Ninguna entra en `base`: Edge muestra "Administrado por tu organización" con cualquier directiva. Van en `privacy`, `lite`, `laptop` y `legacy`.
- Las tres de privacidad (antes `privacy.edge-*`) se llaman `edge.personalization-reporting-off`, `edge.diagnostic-data-required` (`DiagnosticData = 1`: solo los datos requeridos; `0` sería "Apagado", que Microsoft no recomienda) y `edge.feedback-off`. `edge.sidebar-off` avisa que la directiva no rige en perfiles con cuenta Microsoft. Todas declaran las cuatro ediciones: la documentación de Edge no las limita por edición.
- `edge.startup-boost-off` y `edge.background-mode-off` usan la clave `Edge\Recommended` (directiva recomendada: el usuario puede volver a activarlas en `edge://settings/system`).
- Las directivas de Copilot de Edge que solo rigen en perfiles de Microsoft Entra ID, `DefaultBrowserSettingEnabled` (solo Windows 7) y las obsoletas (`MetricsReportingEnabled`, `SendSiteInfoToImproveServices`) no entran.

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'edge catalog' {
    It 'ships the edge tweaks in this order' {
        $expected = @(
            'edge.personalization-reporting-off',
            'edge.diagnostic-data-required',
            'edge.feedback-off',
            'edge.new-tab-feed-off',
            'edge.shopping-off',
            'edge.recommendations-off',
            'edge.spotlight-off',
            'edge.default-browser-campaign-off',
            'edge.acrobat-button-off',
            'edge.first-run-off',
            'edge.alternate-error-pages-off',
            'edge.sidebar-off',
            'edge.new-tab-bing-chat-off',
            'edge.history-ai-search-off',
            'edge.local-ai-model-off',
            'edge.startup-boost-off',
            'edge.background-mode-off'
        ) -join ','
        Get-CategoryId 'edge' | Should -Be $expected
    }

    It 'only writes Microsoft Edge policies of the machine' {
        foreach ($tweak in Get-CategoryTweak 'edge') {
            $tweak.scope | Should -Be 'machine' -Because $tweak.id
            [string]$tweak.set.path | Should -BeLike 'HKLM:\SOFTWARE\Policies\Microsoft\Edge*' -Because $tweak.id
        }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `edge catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/edge.json`**

Contenido completo de `catalog/edge.json` (17 ajustes):

```json
{
  "tweaks": [
    {
      "id": "edge.personalization-reporting-off",
      "title": { "es": "Edge no envía tu navegación para personalizar anuncios", "en": "Edge does not send browsing data to personalize ads" },
      "why": { "es": "Microsoft no recibe tu historial y favoritos para anuncios, búsqueda y noticias.", "en": "Microsoft does not receive your history and favorites for ads, search and news." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "PersonalizationReportingEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/personalizationreportingenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "edge.diagnostic-data-required",
      "title": { "es": "Edge envía solo los datos de diagnóstico requeridos", "en": "Edge sends only required diagnostic data" },
      "why": { "es": "Edge deja de enviar a Microsoft los datos opcionales de uso, sitios visitados y errores; solo envía los requeridos para mantenerse seguro y al día.", "en": "Edge stops sending optional usage, visited-site and crash data to Microsoft; it only sends the data required to stay secure and up to date." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "DiagnosticData", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/diagnosticdata", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "edge.feedback-off",
      "title": { "es": "Edge sin el envío de comentarios", "en": "Edge without the feedback feature" },
      "why": { "es": "Quita Enviar comentarios de Edge, que adjunta datos del navegador.", "en": "Removes Edge's Send feedback, which attaches browser data." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "UserFeedbackAllowed", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/userfeedbackallowed", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "edge.new-tab-feed-off",
      "title": { "es": "Edge sin noticias en la pestaña nueva", "en": "Edge without the news feed on the new tab" },
      "why": { "es": "Quita el contenido de MSN de la pestaña nueva.", "en": "Removes MSN content from the new tab page." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "NewTabPageContentEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagecontentenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.shopping-off",
      "title": { "es": "Edge sin asistente de compras", "en": "Edge without the shopping assistant" },
      "why": { "es": "Apaga la comparación de precios y los cupones automáticos.", "en": "Turns off price comparison and automatic coupons." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "EdgeShoppingAssistantEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/edgeshoppingassistantenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.recommendations-off",
      "title": { "es": "Edge sin recomendaciones de funciones", "en": "Edge without feature recommendations" },
      "why": { "es": "Quita los avisos que sugieren probar funciones del navegador.", "en": "Removes the prompts that suggest trying browser features." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "ShowRecommendationsEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/showrecommendationsenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.spotlight-off",
      "title": { "es": "Edge sin Spotlight ni consejos de Microsoft", "en": "Edge without Spotlight and Microsoft tips" },
      "why": { "es": "Quita fondos, sugerencias y consejos sobre servicios de Microsoft.", "en": "Removes backgrounds, suggestions and tips about Microsoft services." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "SpotlightExperiencesAndRecommendationsEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/spotlightexperiencesandrecommendationsenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.default-browser-campaign-off",
      "title": { "es": "Edge sin campañas para ser el navegador predeterminado", "en": "Edge without default-browser campaigns" },
      "why": { "es": "No te pide cambiar el navegador ni el buscador a Edge y Bing.", "en": "Stops asking you to switch your browser and search engine to Edge and Bing." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "DefaultBrowserSettingsCampaignEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/defaultbrowsersettingscampaignenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.acrobat-button-off",
      "title": { "es": "Edge sin botón de suscripción a Acrobat", "en": "Edge without the Acrobat subscription button" },
      "why": { "es": "Quita el botón que promociona Acrobat en el lector de PDF.", "en": "Removes the button that promotes Acrobat in the PDF viewer." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "ShowAcrobatSubscriptionButton", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/showacrobatsubscriptionbutton", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.first-run-off",
      "title": { "es": "Edge sin pantalla de primer inicio", "en": "Edge without the first-run experience" },
      "why": { "es": "Omite la bienvenida que ofrece iniciar sesión y activar la sincronización.", "en": "Skips the welcome that offers sign-in and sync." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "HideFirstRunExperience", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/hidefirstrunexperience", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "edge.alternate-error-pages-off",
      "title": { "es": "Edge sin páginas de error alternativas", "en": "Edge without alternate error pages" },
      "why": { "es": "No envía a Microsoft la dirección que falló para sugerir otra página.", "en": "Does not send the failed address to Microsoft to suggest another page." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "AlternateErrorPagesEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/alternateerrorpagesenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg"]
    },
    {
      "id": "edge.sidebar-off",
      "title": { "es": "Edge sin barra lateral", "en": "Edge without the sidebar" },
      "why": { "es": "Oculta la barra lateral de Edge (Copilot, Descubrir, accesos de compras). No rige en perfiles con cuenta Microsoft; el icono de Copilot de la barra de herramientas lo controla otra directiva (Microsoft365CopilotChatIconEnabled).", "en": "Hides the Edge sidebar (Copilot, Discover, shopping shortcuts). It does not apply to profiles signed in with a Microsoft account; the Copilot icon in the toolbar is controlled by another policy (Microsoft365CopilotChatIconEnabled)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "HubsSidebarEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/hubssidebarenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg"]
    },
    {
      "id": "edge.new-tab-bing-chat-off",
      "title": { "es": "Edge sin accesos a Bing Chat en la pestaña nueva", "en": "Edge without Bing Chat entry points on the new tab" },
      "why": { "es": "Quita los accesos a Bing Chat de la pestaña nueva.", "en": "Removes the Bing Chat entry points from the new tab page." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "NewTabPageBingChatEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagebingchatenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg"]
    },
    {
      "id": "edge.history-ai-search-off",
      "title": { "es": "Edge sin búsqueda con IA en el historial", "en": "Edge without AI search in History" },
      "why": { "es": "El historial solo busca coincidencias exactas.", "en": "History only searches for exact matches." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "EdgeHistoryAISearchEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/edgehistoryaisearchenabled", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg"]
    },
    {
      "id": "edge.local-ai-model-off",
      "title": { "es": "Edge sin descarga del modelo de IA local", "en": "Edge without the local AI model download" },
      "why": { "es": "Evita descargar el modelo de IA local y borra el que ya exista.", "en": "Avoids downloading the local AI model and deletes an existing one." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge", "name": "GenAILocalFoundationalModelSettings", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/genailocalfoundationalmodelsettings", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg"]
    },
    {
      "id": "edge.startup-boost-off",
      "title": { "es": "Que Edge no arranque procesos al iniciar sesión", "en": "Stop Edge from starting processes at sign-in" },
      "why": { "es": "Sin el impulso de inicio, Edge no deja procesos precargados en memoria; se abre un poco más lento la primera vez. Tú puedes cambiarlo en edge://settings/system.", "en": "Without startup boost Edge keeps no preloaded processes in memory; it opens slightly slower the first time. You can change it in edge://settings/system." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\\Recommended", "name": "StartupBoostEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/deployedge/microsoft-edge-policies/startupboostenabled"]
    },
    {
      "id": "edge.background-mode-off",
      "title": { "es": "Que Edge no siga en segundo plano al cerrarlo", "en": "Stop Edge from running in the background after closing" },
      "why": { "es": "Al cerrar la última ventana, Edge termina del todo y libera su memoria. Tú puedes cambiarlo en edge://settings/system.", "en": "When the last window closes, Edge exits completely and frees its memory. You can change it in edge://settings/system." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\\Recommended", "name": "BackgroundModeEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/deployedge/microsoft-edge-policies/backgroundmodeenabled"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'edge.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
edge.personalization-reporting-off            applied
edge.diagnostic-data-required                 applied
edge.feedback-off                             applied
edge.new-tab-feed-off                         applied
edge.shopping-off                             applied
edge.recommendations-off                      applied
edge.spotlight-off                            applied
edge.default-browser-campaign-off             applied
edge.acrobat-button-off                       applied
edge.first-run-off                            not-applied
edge.alternate-error-pages-off                applied
edge.sidebar-off                              applied
edge.new-tab-bing-chat-off                    applied
edge.history-ai-search-off                    applied
edge.local-ai-model-off                       applied
edge.startup-boost-off                        not-applied
edge.background-mode-off                      not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/edge.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de directivas de Microsoft Edge"
```

---

### Task 13: Catálogo `services.json` (servicios)

**Files:**
- Modify: `catalog/services.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Reemplaza el archivo de ejemplo y conserva `services.retail-demo` (con una fuente nueva: la guía de servicios de Windows Server no lista RetailDemo). Decisiones aplicadas:

- `services.diagtrack` es `medium` con `ask: true`: es lo único que corta la subida de telemetría en Pro, pero Defender for Endpoint lo exige y lo usan Feedback Hub y Xbox.
- Los servicios por usuario (`CDPUserSvc`, `PimIndexMaintenanceSvc`, `UnistoreSvc`, `UserDataSvc`) se deshabilitan en su plantilla con `stop: false` (la instancia viva sigue hasta cerrar sesión): `signOutRequired: true` y `rebootRequired: false`. Con `ask: true`, porque Vínculo móvil, compartir cercano, Contactos, Correo y Calendario dependen de ellos.
- WIA y Mapas pasan a `Manual` (Windows los inicia por disparador cuando hacen falta); los servicios de Xbox no entran (ya vienen en manual y deshabilitarlos rompe el inicio de sesión de Xbox); `gaming` conserva las apps de Xbox y su tarea.
- Ninguno de la lista negra (`SharedAccess`, `WSearch`, `SysMain`, `WerSvc`, `DPS`, `Spooler`, virtualización...): lo comprueba "Blacklist guard".

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'services catalog' {
    It 'ships the services tweaks in this order' {
        $expected = @(
            'services.retail-demo',
            'services.diagtrack',
            'services.wia',
            'services.maps-broker',
            'services.geolocation',
            'services.connected-devices',
            'services.connected-devices-user',
            'services.contact-data',
            'services.user-data-storage',
            'services.user-data-access'
        ) -join ','
        Get-CategoryId 'services' | Should -Be $expected
    }

    It 'asks before the services that apps or features of the user rely on' {
        $asked = @(Get-CategoryTweak 'services' | Where-Object { $_.ask } | ForEach-Object { $_.id }) -join ','
        $asked | Should -Be 'services.diagtrack,services.geolocation,services.connected-devices,services.connected-devices-user,services.contact-data,services.user-data-storage,services.user-data-access'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `services catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/services.json`**

Contenido completo de `catalog/services.json` (10 ajustes):

```json
{
  "tweaks": [
    {
      "id": "services.retail-demo",
      "title": { "es": "Desactivar el servicio de demostración para tiendas", "en": "Disable the retail demo service" },
      "why": { "es": "Solo se usa en equipos de exhibición en tiendas.", "en": "Only used on store display machines." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "RetailDemo", "startType": "Disabled", "stop": true },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-unattendenableretaildemo"]
    },
    {
      "id": "services.diagtrack",
      "title": { "es": "Desactivar el servicio de telemetría (DiagTrack)", "en": "Disable the telemetry service (DiagTrack)" },
      "why": { "es": "Detiene el envío de datos de diagnóstico; puede afectar Feedback Hub, Xbox y Defender for Endpoint.", "en": "Stops diagnostic data uploads; may affect Feedback Hub, Xbox and Defender for Endpoint." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "DiagTrack", "startType": "Disabled", "stop": true },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json", "https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/Services.json"]
    },
    {
      "id": "services.wia",
      "title": { "es": "Pasar a manual el servicio de adquisición de imágenes (WIA)", "en": "Set the Windows Image Acquisition (WIA) service to manual" },
      "why": { "es": "Solo hace falta al usar un escáner o una cámara; Windows lo inicia solo cuando conectas el dispositivo.", "en": "Only needed with a scanner or camera; Windows starts it by itself when you plug the device in." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "StiSvc", "startType": "Manual", "stop": true },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server"]
    },
    {
      "id": "services.maps-broker",
      "title": { "es": "Pasar a manual el servicio de mapas descargados", "en": "Set the Downloaded Maps Manager service to manual" },
      "why": { "es": "Solo sirve a las apps que usan mapas sin conexión; se inicia cuando una app lo pide y deja de arrancar con Windows.", "en": "Only serves apps that use offline maps; it starts when an app asks for it and no longer starts with Windows." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "MapsBroker", "startType": "Manual", "stop": false },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "services.geolocation",
      "title": { "es": "Desactivar el servicio de ubicación del sistema", "en": "Disable the system Geolocation service" },
      "why": { "es": "Apaga la ubicación para todo el equipo. Las apps que la usan (clima, mapas, zona horaria automática) dejan de saber dónde estás.", "en": "Turns location off for the whole machine. Apps that use it (weather, maps, automatic time zone) can no longer tell where you are." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "lfsvc", "startType": "Disabled", "stop": true },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server", "https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/Services.json"]
    },
    {
      "id": "services.connected-devices",
      "title": { "es": "Desactivar la plataforma de dispositivos conectados", "en": "Disable the Connected Devices Platform service" },
      "why": { "es": "Alimenta compartir con dispositivos cercanos, Vínculo móvil y el portapapeles entre equipos. Si no los usas, es un servicio menos.", "en": "It powers nearby sharing, Phone Link and the clipboard across devices. If you do not use them, it is one service less." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "CDPSvc", "startType": "Disabled", "stop": true },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server", "https://learn.microsoft.com/windows/application-management/per-user-services-in-windows"]
    },
    {
      "id": "services.connected-devices-user",
      "title": { "es": "Desactivar el servicio de dispositivos conectados de cada usuario", "en": "Disable the per-user Connected Devices Platform service" },
      "why": { "es": "Es la parte por usuario del servicio anterior. Windows deja de crearla al iniciar sesión (surte efecto en la próxima sesión).", "en": "It is the per-user part of the service above. Windows stops creating it at sign-in (takes effect next session)." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "CDPUserSvc", "startType": "Disabled", "stop": false },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://learn.microsoft.com/windows/application-management/per-user-services-in-windows", "https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server"]
    },
    {
      "id": "services.contact-data",
      "title": { "es": "Desactivar la indexación de contactos", "en": "Disable contact data indexing" },
      "why": { "es": "Indexa contactos para la búsqueda. Sin Correo, Calendario ni Contactos de Windows no aporta nada (surte efecto en la próxima sesión).", "en": "Indexes contacts for search. Without Windows Mail, Calendar or People it adds nothing (takes effect next session)." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "PimIndexMaintenanceSvc", "startType": "Disabled", "stop": false },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://learn.microsoft.com/windows/application-management/per-user-services-in-windows", "https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server"]
    },
    {
      "id": "services.user-data-storage",
      "title": { "es": "Desactivar el almacén de datos de usuario (contactos, calendario, mensajes)", "en": "Disable the user data storage service (contacts, calendar, messages)" },
      "why": { "es": "Guarda contactos, calendarios y mensajes para las apps de Windows que los usan. Sin esas apps es memoria sin uso (surte efecto en la próxima sesión).", "en": "Stores contacts, calendars and messages for the Windows apps that use them. Without those apps it is unused memory (takes effect next session)." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "UnistoreSvc", "startType": "Disabled", "stop": false },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://learn.microsoft.com/windows/application-management/per-user-services-in-windows", "https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server"]
    },
    {
      "id": "services.user-data-access",
      "title": { "es": "Desactivar el acceso a datos de usuario (contactos, calendario, mensajes)", "en": "Disable the user data access service (contacts, calendar, messages)" },
      "why": { "es": "Da a las apps acceso a esos datos. Va junto con el almacén de datos de usuario (surte efecto en la próxima sesión).", "en": "Gives apps access to that data. It goes together with the user data storage service (takes effect next session)." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "service",
      "scope": "machine",
      "set": { "name": "UserDataSvc", "startType": "Disabled", "stop": false },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://learn.microsoft.com/windows/application-management/per-user-services-in-windows", "https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'services.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
services.retail-demo                          not-applied
services.diagtrack                            not-applied
services.wia                                  not-applied
services.maps-broker                          not-applied
services.geolocation                          not-applied
services.connected-devices                    not-applied
services.connected-devices-user               not-applied
services.contact-data                         not-applied
services.user-data-storage                    not-applied
services.user-data-access                     not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/services.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de servicios"
```

---

### Task 14: Catálogo `tasks.json` (tareas programadas)

**Files:**
- Modify: `catalog/tasks.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Reemplaza el archivo de ejemplo y conserva `tasks.ceip-consolidator`. Decisiones aplicadas:

- El evaluador de compatibilidad (`tasks.appraiser`, `tasks.appraiser-exp`, `tasks.program-data-updater`) es `medium` con `ask: true`: sin su inventario Windows puede no ofrecer actualizaciones de función. `tasks.mare-backup` también pregunta (en compilaciones recientes ejecuta el evaluador). En el build 26300 dos de ellas ya no existen; el plan las informa `not-present`.
- `tasks.family-safety-*` preguntan: con controles parentales activos dejarían de aplicarse.
- No se toca `DiskDiagnosticResolver` (avisa de fallos SMART), `Flighting\*`, `Defrag`, `Chkdsk`, `Servicing` ni `RegIdleBackup` (lista negra y "No incluido").
- Una tarea que no existe en un build (por ejemplo `SpeechModelDownloadTask` en 26300) se omite como `not-present`, sin error.

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'tasks catalog' {
    It 'ships the tasks tweaks in this order' {
        $expected = @(
            'tasks.ceip-consolidator',
            'tasks.ceip-usbceip',
            'tasks.autochk-proxy',
            'tasks.disk-diagnostic-data-collector',
            'tasks.appraiser',
            'tasks.appraiser-exp',
            'tasks.program-data-updater',
            'tasks.mare-backup',
            'tasks.startup-app-task',
            'tasks.maps-toast',
            'tasks.maps-update',
            'tasks.xbox-game-save',
            'tasks.power-efficiency-analyze',
            'tasks.disk-footprint-diagnostics',
            'tasks.work-folders-logon',
            'tasks.work-folders-maintenance',
            'tasks.winsat',
            'tasks.recommended-troubleshooting',
            'tasks.family-safety-monitor',
            'tasks.family-safety-refresh',
            'tasks.speech-model-download'
        ) -join ','
        Get-CategoryId 'tasks' | Should -Be $expected
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `tasks catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/tasks.json`**

Contenido completo de `catalog/tasks.json` (21 ajustes):

```json
{
  "tweaks": [
    {
      "id": "tasks.ceip-consolidator",
      "title": { "es": "Desactivar la tarea de consolidación del Programa de mejora de la experiencia", "en": "Disable the Customer Experience Improvement Program consolidator task" },
      "why": { "es": "Recopila y envía datos de uso a Microsoft.", "en": "Collects and sends usage data to Microsoft." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\", "name": "Consolidator", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.ceip-usbceip",
      "title": { "es": "Desactivar la tarea de estadísticas USB del programa de mejora", "en": "Disable the USB customer experience task" },
      "why": { "es": "Envía a Microsoft estadísticas de los dispositivos USB conectados.", "en": "Sends statistics about connected USB devices to Microsoft." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\", "name": "UsbCeip", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.autochk-proxy",
      "title": { "es": "Desactivar la tarea de datos de Autochk", "en": "Disable the Autochk data task" },
      "why": { "es": "Recoge datos de la revisión de disco al arrancar para enviarlos a Microsoft.", "en": "Collects boot-time disk check data to send to Microsoft." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Autochk\\", "name": "Proxy", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.disk-diagnostic-data-collector",
      "title": { "es": "Desactivar el envío de datos del diagnóstico de discos", "en": "Disable the disk diagnostic data upload" },
      "why": { "es": "Envía información general de tus discos y del sistema a Microsoft.", "en": "Sends general disk and system information to Microsoft." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\DiskDiagnostic\\", "name": "Microsoft-Windows-DiskDiagnosticDataCollector", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.appraiser",
      "title": { "es": "Desactivar el evaluador de compatibilidad de aplicaciones", "en": "Disable the application compatibility appraiser" },
      "why": { "es": "Envía el inventario de programas y controladores; sin él Windows puede no ofrecer actualizaciones de función.", "en": "Sends your program and driver inventory; without it Windows may not offer feature updates." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Application Experience\\", "name": "Microsoft Compatibility Appraiser", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.appraiser-exp",
      "title": { "es": "Desactivar el evaluador de compatibilidad (variante Exp)", "en": "Disable the compatibility appraiser (Exp variant)" },
      "why": { "es": "Variante del evaluador de compatibilidad; mismo envío de inventario y mismo riesgo para las actualizaciones.", "en": "Variant of the compatibility appraiser; same inventory upload and same update risk." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Application Experience\\", "name": "Microsoft Compatibility Appraiser Exp", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.program-data-updater",
      "title": { "es": "Desactivar el actualizador de datos de programas", "en": "Disable the program data updater" },
      "why": { "es": "Recoge datos de los programas instalados para la telemetría de compatibilidad.", "en": "Collects installed-program data for compatibility telemetry." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Application Experience\\", "name": "ProgramDataUpdater", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1"]
    },
    {
      "id": "tasks.mare-backup",
      "title": { "es": "Desactivar la recopilación de apps para Copia de seguridad de Windows", "en": "Disable app collection for Windows Backup" },
      "why": { "es": "Recoge la lista de tus programas para la copia en la nube (esa lista no se restaurará). En compilaciones recientes también ejecuta el evaluador de compatibilidad, así que desactivarla puede detener las ofertas de actualizaciones de función.", "en": "Collects your program list for the cloud backup (that list will not be restored). On recent builds it also runs the compatibility appraiser, so disabling it may stop feature-update offers." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Application Experience\\", "name": "MareBackup", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.startup-app-task",
      "title": { "es": "Desactivar el aviso de demasiadas apps de inicio", "en": "Disable the too-many-startup-apps notice" },
      "why": { "es": "Deja de revisar el inicio para avisarte; no recopila datos, es solo una molestia.", "en": "Stops scanning startup entries to nag you; it collects no data, it is just noise." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Application Experience\\", "name": "StartupAppTask", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "tasks.maps-toast",
      "title": { "es": "Desactivar la tarea de avisos de Mapas", "en": "Disable the Maps notification task" },
      "why": { "es": "Muestra avisos de mapas descargados; sin esa función solo gasta un arranque.", "en": "Shows notifications about downloaded maps; without that feature it only costs a wake-up." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Maps\\", "name": "MapsToastTask", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.maps-update",
      "title": { "es": "Desactivar la tarea de actualización de mapas", "en": "Disable the Maps update task" },
      "why": { "es": "Descarga actualizaciones de mapas sin conexión que casi nadie usa.", "en": "Downloads offline map updates that almost nobody uses." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Maps\\", "name": "MapsUpdateTask", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server", "https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.xbox-game-save",
      "title": { "es": "Desactivar la tarea de partidas guardadas de Xbox", "en": "Disable the Xbox game save task" },
      "why": { "es": "Despierta el servicio de partidas guardadas de Xbox Live aunque no juegues. El perfil Gaming la conserva.", "en": "Wakes the Xbox Live game save service even if you do not play. The Gaming profile keeps it." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\XblGameSave\\", "name": "XblGameSaveTask", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.power-efficiency-analyze",
      "title": { "es": "Desactivar el análisis semanal de eficiencia energética", "en": "Disable the weekly power efficiency analysis" },
      "why": { "es": "Genera un informe de energía que casi nadie lee. Puedes pedirlo cuando quieras con powercfg /energy.", "en": "Builds a power report that almost nobody reads. You can ask for it any time with powercfg /energy." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Power Efficiency Diagnostics\\", "name": "AnalyzeSystem", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.disk-footprint-diagnostics",
      "title": { "es": "Desactivar la tarea de diagnóstico de uso de disco", "en": "Disable the disk footprint diagnostics task" },
      "why": { "es": "Recoge datos de uso de almacenamiento para diagnóstico; no limpia ni cambia nada en tu disco.", "en": "Collects storage usage data for diagnostics; it does not clean or change anything on your disk." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\DiskFootprint\\", "name": "Diagnostics", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.work-folders-logon",
      "title": { "es": "Desactivar la sincronización de Carpetas de trabajo al iniciar sesión", "en": "Disable Work Folders synchronization at sign-in" },
      "why": { "es": "Carpetas de trabajo es una función de empresa; sin ella la tarea solo se ejecuta en cada inicio de sesión sin hacer nada.", "en": "Work Folders is a business feature; without it the task just runs at every sign-in and does nothing." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Work Folders\\", "name": "Work Folders Logon Synchronization", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.work-folders-maintenance",
      "title": { "es": "Desactivar el mantenimiento de Carpetas de trabajo", "en": "Disable Work Folders maintenance" },
      "why": { "es": "Mantenimiento periódico de una función de empresa que no se usa en equipos personales.", "en": "Periodic maintenance of a business feature that personal machines do not use." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Work Folders\\", "name": "Work Folders Maintenance Work", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.winsat",
      "title": { "es": "Desactivar la evaluación periódica del rendimiento (WinSAT)", "en": "Disable the periodic performance assessment (WinSAT)" },
      "why": { "es": "Ejecuta una prueba de disco y gráficos en segundo plano; en discos mecánicos se nota. Windows ya no usa el índice de experiencia.", "en": "Runs a disk and graphics benchmark in the background, which is noticeable on hard disks. Windows no longer uses the experience index." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Maintenance\\", "name": "WinSAT", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.recommended-troubleshooting",
      "title": { "es": "Desactivar el análisis de soluciones recomendadas", "en": "Disable the recommended troubleshooting scanner" },
      "why": { "es": "Busca problemas en segundo plano para sugerir solucionadores. Siguen disponibles a mano en Configuración.", "en": "Looks for problems in the background to suggest troubleshooters. They stay available by hand in Settings." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Diagnosis\\", "name": "RecommendedTroubleshootingScanner", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.family-safety-monitor",
      "title": { "es": "Desactivar el monitor de Seguridad familiar", "en": "Disable the Family Safety monitor" },
      "why": { "es": "Solo sirve si el equipo usa controles parentales de Microsoft. Con ellos activos, dejan de aplicarse.", "en": "Only useful if the machine uses Microsoft parental controls. With them active, they stop being applied." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Shell\\", "name": "FamilySafetyMonitor", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.family-safety-refresh",
      "title": { "es": "Desactivar la actualización de Seguridad familiar", "en": "Disable the Family Safety refresh" },
      "why": { "es": "Va de la mano del monitor de Seguridad familiar: sin controles parentales no hace falta.", "en": "Goes with the Family Safety monitor: without parental controls it is not needed." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Shell\\", "name": "FamilySafetyRefreshTask", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    },
    {
      "id": "tasks.speech-model-download",
      "title": { "es": "Desactivar la descarga de modelos de voz", "en": "Disable the speech model download" },
      "why": { "es": "Descarga en segundo plano datos para el reconocimiento de voz en línea; no hace falta si no dictas.", "en": "Downloads data for online speech recognition in the background; not needed if you do not dictate." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "task",
      "scope": "machine",
      "set": { "path": "\\Microsoft\\Windows\\Speech\\", "name": "SpeechModelDownloadTask", "state": "Disabled" },
      "rebootRequired": false,
      "sources": ["https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'tasks.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
tasks.ceip-consolidator                       applied
tasks.ceip-usbceip                            applied
tasks.autochk-proxy                           applied
tasks.disk-diagnostic-data-collector          applied
tasks.appraiser                               not-present
tasks.appraiser-exp                           applied
tasks.program-data-updater                    not-present
tasks.mare-backup                             not-applied
tasks.startup-app-task                        applied
tasks.maps-toast                              not-applied
tasks.maps-update                             applied
tasks.xbox-game-save                          not-applied
tasks.power-efficiency-analyze                not-applied
tasks.disk-footprint-diagnostics              not-applied
tasks.work-folders-logon                      not-applied
tasks.work-folders-maintenance                not-applied
tasks.winsat                                  not-applied
tasks.recommended-troubleshooting             not-applied
tasks.family-safety-monitor                   not-applied
tasks.family-safety-refresh                   not-applied
tasks.speech-model-download                   not-present
```

- [ ] **Step 6: Commit**

```bash
git add catalog/tasks.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de tareas programadas"
```

---

### Task 15: Catálogos `performance.json` y `power.json`

**Files:**
- Create: `catalog/performance.json`
- Create: `catalog/power.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Dos archivos nuevos. Decisiones aplicadas:

- `performance.delivery-optimization-http-only` usa la directiva `DODownloadMode = 0` (Pro y superiores). `100` (Bypass) está obsoleto y puede hacer fallar descargas.
- `performance.background-apps-off` (`GlobalUserDisabled`) es de usuario, `medium` con `ask: true` y solo Windows 10: Correo o Alarmas no avisan con la app cerrada y los fondos de Windows Spotlight pueden dejar de actualizarse.
- Transparencia y animación de minimizar no se repiten aquí: son `ui.transparency-off` y `ui.window-animations-off`.
- `power.high-performance-plan` lleva `requires: ["no-battery"]` y `ask: true`; en equipos con Modern Standby el plan ni aparece (`not-present`).
- `power.usb-selective-suspend-ac-off` fija solo `ac: 0` (Task 4): con batería no cambia nada.
- `power.standby-network-off-battery` es la directiva de Modern Standby (`DCSettingIndex = 0` del valor `f15576e8...`) con `requires: ["battery"]`, Pro/Enterprise/Education y `ask: true`. Se usa la directiva y no `powercfg` porque ese valor no tiene subgrupo (`SUB_NONE`) y el manejador solo lee `PowerSettings\<subgrupo>\<valor>`.
- El modo de energía "Mejor rendimiento" no entra (ver "Acciones descartadas").

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'performance catalog' {
    It 'ships the performance tweaks in this order' {
        $expected = @(
            'performance.delivery-optimization-http-only',
            'performance.explorer-folder-type-general',
            'performance.background-apps-off'
        ) -join ','
        Get-CategoryId 'performance' | Should -Be $expected
    }
}

Describe 'power catalog' {
    It 'ships the power tweaks in this order' {
        $expected = @(
            'power.high-performance-plan',
            'power.usb-selective-suspend-ac-off',
            'power.standby-network-off-battery'
        ) -join ','
        Get-CategoryId 'power' | Should -Be $expected
    }

    It 'ties the power tweaks to the hardware they are meant for' {
        $tweaks = Get-CategoryTweak 'power'
        @(($tweaks | Where-Object { $_.id -eq 'power.high-performance-plan' }).requires) -join ',' | Should -Be 'no-battery'
        @(($tweaks | Where-Object { $_.id -eq 'power.standby-network-off-battery' }).requires) -join ',' | Should -Be 'battery'
        $usb = $tweaks | Where-Object { $_.id -eq 'power.usb-selective-suspend-ac-off' }
        $usb.set.ac | Should -Be 0
        $null -eq $usb.set.PSObject.Properties['dc'] | Should -BeTrue
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `performance catalog` y `power catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/performance.json`**

Contenido completo de `catalog/performance.json` (3 ajustes):

```json
{
  "tweaks": [
    {
      "id": "performance.delivery-optimization-http-only",
      "title": { "es": "No compartir descargas de Windows con otros equipos", "en": "Do not share Windows downloads with other PCs" },
      "why": { "es": "Delivery Optimization descarga solo por HTTP y deja de subir actualizaciones a otros equipos de tu red. Las actualizaciones siguen llegando igual.", "en": "Delivery Optimization downloads over HTTP only and stops uploading updates to other PCs on your network. Updates keep arriving the same way." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization", "name": "DODownloadMode", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/windows/deployment/do/waas-delivery-optimization-reference", "https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "performance.explorer-folder-type-general",
      "title": { "es": "Que el Explorador no adivine el tipo de cada carpeta", "en": "Stop File Explorer from guessing each folder type" },
      "why": { "es": "Explorer deja de analizar el contenido para elegir columnas (imágenes, música); las carpetas grandes abren más rápido, sobre todo en disco mecánico.", "en": "Explorer stops scanning contents to pick columns (pictures, music); large folders open faster, especially on hard disks." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\\AllFolders\\Shell", "name": "FolderType", "kind": "String", "value": "NotSpecified" },
      "rebootRequired": false,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json"]
    },
    {
      "id": "performance.background-apps-off",
      "title": { "es": "No dejar que las apps de la Store corran en segundo plano", "en": "Do not let Store apps run in the background" },
      "why": { "es": "Ahorra batería y memoria; a cambio, apps como Correo o Alarmas no avisan con la app cerrada y los fondos de Windows Spotlight pueden dejar de actualizarse. Puedes permitir apps una a una en Configuración.", "en": "Saves battery and memory; in exchange, apps like Mail or Alarms do not notify while closed and Windows Spotlight backgrounds may stop refreshing. You can allow apps one by one in Settings." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications", "name": "GlobalUserDisabled", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json", "https://www.elevenforum.com/t/enable-or-disable-background-apps-in-windows-11.923/"]
    }
  ]
}
```

- [ ] **Step 4: Escribir `catalog/power.json`**

Contenido completo de `catalog/power.json` (3 ajustes):

```json
{
  "tweaks": [
    {
      "id": "power.high-performance-plan",
      "title": { "es": "Usar el plan de energía Alto rendimiento", "en": "Use the High performance power plan" },
      "why": { "es": "Para escritorios: mantiene el procesador listo y evita ahorros que añaden latencia. En portátiles gasta batería.", "en": "For desktops: keeps the processor ready and skips savings that add latency. Drains the battery on laptops." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "powercfg",
      "scope": "machine",
      "set": { "kind": "scheme", "scheme": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" },
      "requires": ["no-battery"],
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-power-slider", "https://github.com/farag2/Sophia-Script-for-Windows"]
    },
    {
      "id": "power.usb-selective-suspend-ac-off",
      "title": { "es": "No suspender los USB con corriente", "en": "Do not suspend USB devices on AC" },
      "why": { "es": "Evita cortes y retardos al despertar mouse, teclado, mando o dispositivos de depuración. Con batería no cambia nada.", "en": "Avoids dropouts and delays when waking mouse, keyboard, controller or debugging devices. Nothing changes on battery." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "powercfg",
      "scope": "machine",
      "set": { "kind": "setting", "scheme": "SCHEME_CURRENT", "subgroup": "2a737441-1930-4402-8d77-b2bebba308a3", "setting": "48e6b7a6-50f5-4782-a5d4-53bb8f07e226", "ac": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options"]
    },
    {
      "id": "power.standby-network-off-battery",
      "title": { "es": "Sin red en suspensión moderna con batería", "en": "No network in modern standby on battery" },
      "why": { "es": "Ahorra batería mientras la tapa está cerrada. Se pierden notificaciones y Escritorio remoto hasta que despiertes el equipo.", "en": "Saves battery while the lid is closed. You lose notifications and Remote Desktop until you wake the machine." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Power\\PowerSettings\\f15576e8-98b7-4186-b944-eafa664402d9", "name": "DCSettingIndex", "kind": "DWord", "value": 0 },
      "requires": ["battery"],
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-network-connectivity", "https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Modern_Standby_Networking.reg"]
    }
  ]
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 6: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'performance.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
performance.delivery-optimization-http-only   not-applied
performance.explorer-folder-type-general      not-applied
performance.background-apps-off               not-applied
```

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'power.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
power.high-performance-plan                   not-present
power.usb-selective-suspend-ac-off            not-applied
power.standby-network-off-battery             applied
```

- [ ] **Step 7: Commit**

```bash
git add catalog/performance.json catalog/power.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogos de rendimiento y energía"
```

---

### Task 16: Acción `gaming-windowed-optimizations`

> **Corrección posterior a la revisión.** La lista se lee como Windows, igual en `Test` y en `Set`: piezas separadas por `;`, el nombre es lo que va antes del primer `=` sin espacios ni distinción de mayúsculas, se toleran piezas vacías y gana la última copia; `Test` da `applied` solo si esa última vale `1` (`SwapEffectUpgradeEnableX=1` es otro par). Aplicar deja una sola copia de `SwapEffectUpgradeEnable=1` en el lugar de la primera y conserva las demás piezas tal como están escritas. Deshacer ya no devuelve la cadena entera: pone el valor guardado de su par o lo quita, y conserva lo que cambió en los otros desde que se aplicó; si nada más cambió vuelve el texto exacto y, si no existía, quita el valor y la clave que creó; si el par ya no vale `1` (el usuario lo cambió), lo deja y lo dice en `detail`. El estado agrega `currentUserSid`: el deshacer de otra cuenta lo deja como `other-user` (ver la corrección de la Task 20). Segunda revisión: como escribe en `HKCU`, aplicar se niega sin cambiar nada con el motivo `session-user` (texto en `es` y `en`) si el proceso no corre con la cuenta dueña de `explorer.exe` en su sesión.

**Files:**
- Create: `actions/gaming-windowed-optimizations.ps1`
- Test: `tests/GamingWindowedOptimizations.Tests.ps1`

Las "optimizaciones para juegos en ventana" (Configuración > Sistema > Pantalla > Gráficos) son un par `SwapEffectUpgradeEnable=1` dentro de la cadena `HKCU:\Software\Microsoft\DirectX\UserGpuPreferences\DirectXUserGlobalSettings`, que también guarda otras preferencias (`VRROptimizeEnable=0`, `AutoHDREnable=1`, la GPU preferida). Un ajuste `registry` pisaría la cadena entera; esta acción cambia solo su par y conserva los demás y su orden. Leer, escribir y deshacer el valor usan el manejador de registro (`Get-RegistryTweakState`, `Write-TuneupRegistryValue`, `Restore-RegistryTweakState`), así el deshacer es exacto y borra la clave si la creó. El valor está en `HKCU`, pero las acciones exigen `scope: machine` (decisión 4f: no hay acciones de usuario); funciona porque la elevación normal de UAC es la misma cuenta, y el comentario del script lo advierte. Verificado en el equipo (solo lectura): la clave `UserGpuPreferences` no existe, el ajuste da `not-applied`.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/GamingWindowedOptimizations.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Root = 'HKCU:\Software\windows-tuneup-test'
    $script:Key = "$Root\DirectX\UserGpuPreferences"
    $script:Tweak = New-TestTweak -Id 'gaming.windowed-optimizations' -Type 'action' -Scope 'machine' `
        -Set ([pscustomobject]@{ script = 'gaming-windowed-optimizations' })
    function Get-TestValue { (Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue).DirectXUserGlobalSettings }
}

Describe 'gaming-windowed-optimizations action' {
    BeforeEach {
        # The real value is in the user's DirectX preferences; the tests use the test key instead.
        Mock -ModuleName Tuneup Get-GamingWindowedOptimizationsActionHelperValue { [pscustomobject]@{ path = $Key; name = 'DirectXUserGlobalSettings' } }
    }

    AfterEach {
        if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    }

    It 'is loaded from actions/ and passes the catalog check' {
        @(Get-TuneupActionLoadError | Where-Object { $_.name -eq 'gaming-windowed-optimizations' }).Count | Should -Be 0
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'creates the value when it does not exist and removes it, with the key it created, on undo' {
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'SwapEffectUpgradeEnable=1;'
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $Tweak -State $state
        Test-Path -LiteralPath "$Root\DirectX" | Should -BeFalse
    }

    It 'keeps the other choices and their order, and gives back the exact text on undo' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;AutoHDREnable=1;' | Out-Null
        $state = Get-TuneupState -Tweak $Tweak
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;AutoHDREnable=1;'
        Restore-TuneupState -Tweak $Tweak -State $state
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;AutoHDREnable=1;'
    }

    It 'adds its choice at the end of a list without it' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0' | Out-Null
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;'
    }

    It 'is applied when the choice is already on, whatever else the list holds' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'AutoHDREnable=1; SwapEffectUpgradeEnable=1 ;' | Out-Null
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'leaves a value that is not text alone instead of guessing' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType DWord -Value 1 | Out-Null
        { Test-TuneupState -Tweak $Tweak } | Should -Throw '*not text*'
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*not text*'
        (Get-ItemProperty -LiteralPath $Key).DirectXUserGlobalSettings | Should -Be 1
    }
}

Describe 'gaming-windowed-optimizations target' {
    It 'points at the DirectX preferences of the current user' {
        $value = & (Get-Module Tuneup) { Get-GamingWindowedOptimizationsActionHelperValue }
        $value.path | Should -Be 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $value.name | Should -Be 'DirectXUserGlobalSettings'
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/GamingWindowedOptimizations.Tests.ps1`
Expected: FAIL: el script no existe (`uses action script 'gaming-windowed-optimizations', which is not in the actions folder`, y `Mock` no encuentra `Get-GamingWindowedOptimizationsActionHelperValue`).

- [ ] **Step 3: Escribir la acción**

Crear `actions/gaming-windowed-optimizations.ps1`:

```powershell
# Optimizations for windowed games (Settings > System > Display > Graphics). Windows keeps the
# choice as one token of a REG_SZ list, DirectXUserGlobalSettings, that also holds other choices
# (for example VRROptimizeEnable=0 or AutoHDREnable=1): a plain registry tweak would overwrite them,
# so this script changes only its own token and keeps the others and their order.
# The value lives in HKCU. Action tweaks run elevated, which on a normal UAC prompt is the same
# account; with an administrator account typed at the prompt it would be that account's setting.

function Get-GamingWindowedOptimizationsActionHelperValue {
    param()
    [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; name = 'DirectXUserGlobalSettings' }
}

function Get-GamingWindowedOptimizationsActionHelperTweak {
    param([Parameter(Mandatory)]$Tweak)
    # The registry handler reads, writes and restores the value exactly (and removes a key it created).
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    [pscustomobject]@{ id = $Tweak.id; set = [pscustomobject]@{ path = $value.path; name = $value.name; kind = 'String'; value = $null } }
}

function Get-GamingWindowedOptimizationsActionHelperToken {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    @(([string]$Text) -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
}

function Get-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak)
    Get-RegistryTweakState -Tweak (Get-GamingWindowedOptimizationsActionHelperTweak -Tweak $Tweak)
}

function Test-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingWindowedOptimizationsActionState -Tweak $Tweak
    if ($state.exists -and $state.kind -ne 'String') {
        throw "DirectXUserGlobalSettings is a $($state.kind) value, not text; it is left as it is"
    }
    if (@(Get-GamingWindowedOptimizationsActionHelperToken -Text $state.value) -ccontains 'SwapEffectUpgradeEnable=1') { return 'applied' }
    'not-applied'
}

function Set-GamingWindowedOptimizationsActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingWindowedOptimizationsActionState -Tweak $Tweak
    if ($state.exists -and $state.kind -ne 'String') {
        throw "DirectXUserGlobalSettings is a $($state.kind) value, not text; it is left as it is"
    }
    $tokens = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($token in @(Get-GamingWindowedOptimizationsActionHelperToken -Text $state.value)) {
        if ($token -like 'SwapEffectUpgradeEnable=*') {
            if (-not $found) { $tokens.Add('SwapEffectUpgradeEnable=1') }
            $found = $true
            continue
        }
        $tokens.Add($token)
    }
    if (-not $found) { $tokens.Add('SwapEffectUpgradeEnable=1') }
    $value = Get-GamingWindowedOptimizationsActionHelperValue
    Write-TuneupRegistryValue -Path $value.path -Name $value.name -Kind 'String' -Value (($tokens -join ';') + ';')
}

function Restore-GamingWindowedOptimizationsActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    Restore-RegistryTweakState -Tweak (Get-GamingWindowedOptimizationsActionHelperTweak -Tweak $Tweak) -State $State
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/GamingWindowedOptimizations.Tests.ps1`
Expected: PASS (`Tests Passed: 7, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings` (el lint ya recorre `actions/`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`). La carpeta `actions/` se carga al importar el módulo; ningún script falla al cargar.

- [ ] **Step 5: Commit**

```bash
git add actions/gaming-windowed-optimizations.ps1 tests/GamingWindowedOptimizations.Tests.ps1
git commit -m "feat: acción de optimizaciones para juegos en ventana"
```

---

### Task 17: Acción `gaming-hags`

> **Corrección posterior a la revisión.** Sin `HwSchMode` decide el controlador: el ajuste cuenta como `applied` si un adaptador que lo admite trae `HwSchEnabledByDefault` (bit 2) o `HwSchEnabled` (bit 1); `HwSchMode = 1` sigue siendo apagado y los bits de un adaptador sin soporte no cuentan. El estado agrega `driverOn`. `D3DKMTEnumAdapters2` se repite una vez si la segunda llamada responde `STATUS_BUFFER_TOO_SMALL` (apareció un adaptador entre las dos). Deshacer pide reinicio solo si cambia el valor. Una prueba fija `Marshal.SizeOf` de las cuatro estructuras (20, 16, 24 y 4 bytes en 64 bits) y el tipo de consulta 70; el tipo se carga con `Initialize-GamingHagsActionHelperNative`.

**Files:**
- Create: `actions/gaming-hags.ps1`
- Test: `tests/GamingHags.Tests.ps1`

La programación de GPU acelerada por hardware se enciende con `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode = 2` (`1` = apagada; convención de Sophia y de la configuración de Windows). El valor no dice si el driver la admite: en un driver sin soporte Windows lo ignora, y un ajuste de registro informaría un cambio que no ocurre. La acción pregunta al kernel gráfico con `D3DKMTEnumAdapters2` y `D3DKMTQueryAdapterInfo` tipo `KMTQAITYPE_WDDM_2_7_CAPS` (valor 70; el primer bit de la respuesta es `HwSchSupported`), y sin soporte en ningún adaptador el ajuste es `not-present`. La consulta es de solo lectura y cierra cada adaptador que abre. Verificado en el equipo: con la Intel Iris Xe (dxdiag: `DriverSupportState:AlwaysOff`) la consulta devuelve `0` para los dos adaptadores (Intel y el adaptador básico de Microsoft) y el ajuste da `not-present`. No se pudo verificar en un equipo con soporte; el bit sale de la definición `D3DKMT_WDDM_2_7_CAPS` de `d3dkmthk.h`.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/GamingHags.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Root = 'HKCU:\Software\windows-tuneup-test'
    $script:Key = "$Root\GraphicsDrivers"
    $script:Tweak = New-TestTweak -Id 'gaming.hags-on' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'gaming-hags' })
    function Set-TestMode([int]$Value) {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'HwSchMode' -PropertyType DWord -Value $Value -Force | Out-Null
    }
}

Describe 'gaming-hags action' {
    BeforeEach {
        # HwSchMode lives in HKLM; the tests write the test key instead. The support of the driver is
        # what the graphics kernel answers: bit 0 of the WDDM 2.7 capabilities, -1 when it cannot say.
        New-Item -Path $Key -Force | Out-Null
        Mock -ModuleName Tuneup Get-GamingHagsActionHelperValue { [pscustomobject]@{ path = $Key; name = 'HwSchMode' } }
        $script:Caps = @(0, 1)
        Mock -ModuleName Tuneup Get-GamingHagsActionHelperCapability { $script:Caps }
    }

    AfterEach {
        if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    }

    It 'is loaded from actions/ and passes the catalog check' {
        @(Get-TuneupActionLoadError | Where-Object { $_.name -eq 'gaming-hags' }).Count | Should -Be 0
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'is not-present when no adapter supports it, <Name>' -TestCases @(
        @{ Name = 'with a driver that says no'; Caps = @(0, 0) }
        @{ Name = 'with a driver older than WDDM 2.7'; Caps = @(-1) }
        @{ Name = 'without any adapter'; Caps = @() }
        @{ Name = 'with only the enabled bit set'; Caps = @(2) }
    ) {
        param($Caps)
        $script:Caps = $Caps
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-present'
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*No graphics adapter supports*'
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -BeNullOrEmpty
    }

    It 'turns it on with value 2, asks for a restart and removes the value on undo' {
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        $state.supported | Should -BeTrue
        (Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)).rebootRequired | Should -BeTrue
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -Be 2
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        (Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)).rebootRequired | Should -BeTrue
        @((Get-Item -LiteralPath $Key).GetValueNames()) | Should -Not -Contain 'HwSchMode'
        Test-Path -LiteralPath $Key | Should -BeTrue
    }

    It 'treats value 1 as off and puts it back on undo' {
        Set-TestMode 1
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Restore-TuneupState -Tweak $Tweak -State $state | Out-Null
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -Be 1
    }

    It 'is applied when it is already on' {
        Set-TestMode 2
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
    }
}

Describe 'gaming-hags support query' {
    It 'points at the graphics driver settings of the machine' {
        $value = & (Get-Module Tuneup) { Get-GamingHagsActionHelperValue }
        $value.path | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        $value.name | Should -Be 'HwSchMode'
    }

    It 'asks the graphics kernel without changing anything and gets one number per adapter' {
        $caps = @(& (Get-Module Tuneup) { Get-GamingHagsActionHelperCapability })
        foreach ($value in $caps) { $value | Should -BeOfType [int] ; $value | Should -BeGreaterOrEqual -1 }
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/GamingHags.Tests.ps1`
Expected: FAIL: el script no existe.

- [ ] **Step 3: Escribir la acción**

Crear `actions/gaming-hags.ps1`:

```powershell
# Hardware-accelerated GPU scheduling. The switch is HwSchMode (2 = on, 1 = off) under
# GraphicsDrivers, but the value alone does not say whether the graphics driver supports it: on a
# driver without support Windows ignores it, and a plain registry tweak would report a change that
# never happens. So support is asked to the graphics kernel (D3DKMTQueryAdapterInfo with
# KMTQAITYPE_WDDM_2_7_CAPS, whose first bit is HwSchSupported) and without it the tweak is
# not-present. Windows reads the value at boot: a restart is needed.

function Get-GamingHagsActionHelperValue {
    param()
    [pscustomobject]@{ path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; name = 'HwSchMode' }
}

function Get-GamingHagsActionHelperTweak {
    param([Parameter(Mandatory)]$Tweak)
    $value = Get-GamingHagsActionHelperValue
    [pscustomobject]@{ id = $Tweak.id; set = [pscustomobject]@{ path = $value.path; name = $value.name; kind = 'DWord'; value = $null } }
}

function Get-GamingHagsActionHelperCapability {
    param()
    # One number per graphics adapter: the WDDM 2.7 capability bits, or -1 when the adapter does not
    # answer the query (a driver older than WDDM 2.7). Only reads; nothing is changed.
    if (-not ('WindowsTuneupGpuScheduling' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WindowsTuneupGpuScheduling {
    [StructLayout(LayoutKind.Sequential)]
    struct AdapterInfo { public uint Handle; public uint LuidLow; public int LuidHigh; public uint Sources; public int Precise; }
    [StructLayout(LayoutKind.Sequential)]
    struct EnumAdapters2 { public uint Count; public IntPtr Adapters; }
    [StructLayout(LayoutKind.Sequential)]
    struct QueryAdapterInfo { public uint Handle; public int Type; public IntPtr Data; public uint Size; }
    [StructLayout(LayoutKind.Sequential)]
    struct CloseAdapter { public uint Handle; }
    [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref EnumAdapters2 data);
    [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QueryAdapterInfo data);
    [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref CloseAdapter data);
    const int Wddm27Caps = 70;
    public static int[] Query() {
        EnumAdapters2 list = new EnumAdapters2();
        int status = D3DKMTEnumAdapters2(ref list);
        if (status != 0) throw new InvalidOperationException("D3DKMTEnumAdapters2 failed with status 0x" + status.ToString("X8"));
        if (list.Count == 0) return new int[0];
        int size = Marshal.SizeOf(typeof(AdapterInfo));
        list.Adapters = Marshal.AllocHGlobal(size * (int)list.Count);
        IntPtr caps = Marshal.AllocHGlobal(4);
        try {
            status = D3DKMTEnumAdapters2(ref list);
            if (status != 0) throw new InvalidOperationException("D3DKMTEnumAdapters2 failed with status 0x" + status.ToString("X8"));
            int[] result = new int[list.Count];
            for (int i = 0; i < list.Count; i++) {
                AdapterInfo adapter = (AdapterInfo)Marshal.PtrToStructure(new IntPtr(list.Adapters.ToInt64() + i * size), typeof(AdapterInfo));
                Marshal.WriteInt32(caps, 0);
                QueryAdapterInfo query = new QueryAdapterInfo();
                query.Handle = adapter.Handle;
                query.Type = Wddm27Caps;
                query.Data = caps;
                query.Size = 4;
                result[i] = D3DKMTQueryAdapterInfo(ref query) == 0 ? Marshal.ReadInt32(caps) : -1;
                CloseAdapter close = new CloseAdapter();
                close.Handle = adapter.Handle;
                D3DKMTCloseAdapter(ref close);
            }
            return result;
        } finally {
            Marshal.FreeHGlobal(caps);
            Marshal.FreeHGlobal(list.Adapters);
        }
    }
}
'@
    }
    [WindowsTuneupGpuScheduling]::Query()
}

function Test-GamingHagsActionHelperSupported {
    param()
    # With a hybrid GPU the setting is global: one adapter with support is enough.
    @(Get-GamingHagsActionHelperCapability | Where-Object { $_ -ge 0 -and ($_ -band 1) }).Count -gt 0
}

function Get-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-RegistryTweakState -Tweak (Get-GamingHagsActionHelperTweak -Tweak $Tweak)
    $state | Add-Member -NotePropertyName supported -NotePropertyValue ([bool](Test-GamingHagsActionHelperSupported)) -PassThru
}

function Test-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-GamingHagsActionState -Tweak $Tweak
    if (-not $state.supported) { return 'not-present' }
    if ($state.exists -and $state.kind -eq 'DWord' -and [long]$state.value -eq 2) { return 'applied' }
    'not-applied'
}

function Set-GamingHagsActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    if (-not (Test-GamingHagsActionHelperSupported)) {
        throw 'No graphics adapter supports hardware-accelerated GPU scheduling; nothing was changed'
    }
    $target = (Get-GamingHagsActionHelperTweak -Tweak $Tweak).set
    Write-TuneupRegistryValue -Path $target.path -Name $target.name -Kind 'DWord' -Value 2
    New-TuneupOutcome -RebootRequired
}

function Restore-GamingHagsActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    Restore-RegistryTweakState -Tweak (Get-GamingHagsActionHelperTweak -Tweak $Tweak) -State $State
    New-TuneupOutcome -RebootRequired
}
```

El tipo de C# se llama `WindowsTuneupGpuScheduling` y se compila una vez por proceso (`-as [type]` evita el segundo `Add-Type`). El cargador de acciones lo acepta porque `Add-Type` está dentro de una función: al cargar el script no se ejecuta nada.

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/GamingHags.Tests.ps1`
Expected: PASS (`Tests Passed: 10, Failed: 0`). La última prueba hace la consulta real de solo lectura.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 5: Commit**

```bash
git add actions/gaming-hags.ps1 tests/GamingHags.Tests.ps1
git commit -m "feat: acción de GPU acelerada que solo la activa si el driver la admite"
```

---

### Task 18: Catálogo `gaming.json` (juegos)

**Files:**
- Create: `catalog/gaming.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Archivo nuevo. Usa las acciones de las Tasks 16 y 17. Decisiones aplicadas:

- La aceleración del mouse son tres valores de `HKCU:\Control Panel\Mouse` (uno por ajuste): `signOutRequired: true`, sin reinicio.
- `gaming.hags-on` es la acción `gaming-hags`: `not-present` sin soporte del driver.
- `gaming.memory-integrity-off` es el único ajuste de juegos de riesgo alto: ningún perfil lo incluye.
- La directiva `AllowGameDVR` no entra (solo rige en Windows 10 de escritorio; los valores de usuario ya cubren el objetivo).

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'gaming catalog' {
    It 'ships the gaming tweaks in this order' {
        $expected = @(
            'gaming.game-mode-on',
            'gaming.game-dvr-off',
            'gaming.app-capture-off',
            'gaming.background-recording-off',
            'gaming.gamebar-controller-off',
            'gaming.mouse-accel-off',
            'gaming.mouse-accel-threshold-1',
            'gaming.mouse-accel-threshold-2',
            'gaming.windowed-optimizations',
            'gaming.hags-on',
            'gaming.memory-integrity-off'
        ) -join ','
        Get-CategoryId 'gaming' | Should -Be $expected
    }

    It 'leaves memory integrity as the only high-risk gaming tweak' {
        @(Get-CategoryTweak 'gaming' | Where-Object { $_.risk -eq 'high' } | ForEach-Object { $_.id }) -join ',' | Should -Be 'gaming.memory-integrity-off'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `gaming catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/gaming.json`**

Contenido completo de `catalog/gaming.json` (11 ajustes):

```json
{
  "tweaks": [
    {
      "id": "gaming.game-mode-on",
      "title": { "es": "Activar el Modo Juego", "en": "Turn on Game Mode" },
      "why": { "es": "Windows da prioridad al juego en primer plano y evita instalar drivers mientras juegas.", "en": "Windows prioritizes the foreground game and avoids installing drivers while you play." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\GameBar", "name": "AutoGameModeEnabled", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "gaming.game-dvr-off",
      "title": { "es": "Desactivar Game DVR", "en": "Turn off Game DVR" },
      "why": { "es": "Evita que Windows grabe el juego en segundo plano y consuma GPU y disco.", "en": "Stops Windows from recording the game in the background and using GPU and disk." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\System\\GameConfigStore", "name": "GameDVR_Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_DVR.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "gaming.app-capture-off",
      "title": { "es": "Desactivar la captura de juegos y apps", "en": "Turn off game and app capture" },
      "why": { "es": "Apaga la captura de pantalla y video de Xbox Game Bar. Las apps de Xbox siguen instaladas.", "en": "Turns off Xbox Game Bar screen and video capture. The Xbox apps stay installed." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR", "name": "AppCaptureEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_DVR.reg", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "gaming.background-recording-off",
      "title": { "es": "Desactivar la grabación en segundo plano", "en": "Turn off background recording" },
      "why": { "es": "Impide que Game Bar guarde en memoria los últimos minutos de juego.", "en": "Stops Game Bar from keeping the last minutes of gameplay in memory." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR", "name": "HistoricalCaptureEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11", "https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "gaming.gamebar-controller-off",
      "title": { "es": "El botón del mando no abre Game Bar", "en": "Controller button does not open Game Bar" },
      "why": { "es": "Evita que el botón Xbox del mando abra el overlay y te saque del juego.", "en": "Stops the controller's Xbox button from opening the overlay and pulling you out of the game." },
      "risk": "low",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Software\\Microsoft\\GameBar", "name": "UseNexusForGameBarEnabled", "kind": "DWord", "value": 0 },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Game_Bar_Integration.reg"]
    },
    {
      "id": "gaming.mouse-accel-off",
      "title": { "es": "Desactivar la aceleración del mouse", "en": "Turn off mouse acceleration" },
      "why": { "es": "El puntero se mueve igual que la mano (1:1), sin \"Mejorar la precisión del puntero\".", "en": "The pointer moves exactly as your hand does (1:1), without \"Enhance pointer precision\"." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Control Panel\\Mouse", "name": "MouseSpeed", "kind": "String", "value": "0" },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Enhance_Pointer_Precision.reg"]
    },
    {
      "id": "gaming.mouse-accel-threshold-1",
      "title": { "es": "Mouse sin aceleración: primer umbral en 0", "en": "No mouse acceleration: first threshold at 0" },
      "why": { "es": "Va junto con la aceleración desactivada; deja el primer umbral de velocidad en 0.", "en": "Goes with acceleration off; sets the first speed threshold to 0." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Control Panel\\Mouse", "name": "MouseThreshold1", "kind": "String", "value": "0" },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Enhance_Pointer_Precision.reg"]
    },
    {
      "id": "gaming.mouse-accel-threshold-2",
      "title": { "es": "Mouse sin aceleración: segundo umbral en 0", "en": "No mouse acceleration: second threshold at 0" },
      "why": { "es": "Va junto con la aceleración desactivada; deja el segundo umbral de velocidad en 0.", "en": "Goes with acceleration off; sets the second speed threshold to 0." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "user",
      "set": { "path": "HKCU:\\Control Panel\\Mouse", "name": "MouseThreshold2", "kind": "String", "value": "0" },
      "rebootRequired": false,
      "signOutRequired": true,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Enhance_Pointer_Precision.reg"]
    },
    {
      "id": "gaming.windowed-optimizations",
      "title": { "es": "Optimizaciones para juegos en ventana", "en": "Optimizations for windowed games" },
      "why": { "es": "Los juegos DirectX 10 y 11 en ventana o sin bordes usan el modelo flip: menos latencia, Auto HDR y VRR. Reinicia el juego.", "en": "DirectX 10 and 11 games in windowed or borderless mode use the flip model: lower latency, Auto HDR and VRR. Restart the game." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "action",
      "scope": "machine",
      "set": { "script": "gaming-windowed-optimizations" },
      "rebootRequired": false,
      "sources": ["https://support.microsoft.com/topic/3f006843-2c7e-4ed0-9a5e-f9389e535952"]
    },
    {
      "id": "gaming.hags-on",
      "title": { "es": "Programación de GPU acelerada por hardware", "en": "Hardware-accelerated GPU scheduling" },
      "why": { "es": "La GPU gestiona su propia cola de trabajo y baja la latencia de envío. Solo si el driver lo admite.", "en": "The GPU manages its own work queue and lowers submission latency. Only when the driver supports it." },
      "risk": "medium",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "action",
      "scope": "machine",
      "set": { "script": "gaming-hags" },
      "rebootRequired": true,
      "sources": ["https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/", "https://learn.microsoft.com/windows-hardware/drivers/ddi/d3dkmthk/ne-d3dkmthk-_kmtqueryadapterinfotype", "https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1"]
    },
    {
      "id": "gaming.memory-integrity-off",
      "title": { "es": "Desactivar la integridad de memoria (VBS/HVCI)", "en": "Turn off memory integrity (VBS/HVCI)" },
      "why": { "es": "Puede dar entre 1 y 15 % más de FPS en algunos juegos (poco en CPU recientes), a cambio de menos protección contra drivers maliciosos. Reinicia.", "en": "Can give 1 to 15% more FPS in some games (little on recent CPUs), in exchange for less protection against malicious drivers. Restart needed." },
      "risk": "high",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\DeviceGuard\\Scenarios\\HypervisorEnforcedCodeIntegrity", "name": "Enabled", "kind": "DWord", "value": 0 },
      "rebootRequired": true,
      "sources": ["https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity", "https://www.tomshardware.com/news/windows-11-gaming-benchmarks-performance-vbs-hvci-security/", "https://petri.com/windows-11-memory-integrity-eligible-devices/"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'gaming.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
gaming.game-mode-on                           not-applied
gaming.game-dvr-off                           applied
gaming.app-capture-off                        applied
gaming.background-recording-off               not-applied
gaming.gamebar-controller-off                 applied
gaming.mouse-accel-off                        not-applied
gaming.mouse-accel-threshold-1                not-applied
gaming.mouse-accel-threshold-2                not-applied
gaming.windowed-optimizations                 not-applied
gaming.hags-on                                not-present
gaming.memory-integrity-off                   not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/gaming.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de juegos"
```

---

### Task 19: Catálogo `dev.json` (desarrollo)

**Files:**
- Create: `catalog/dev.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Archivo nuevo. Decisiones aplicadas:

- Modo desarrollador (`medium`), rutas largas (pide reinicio) y sudo (`ask: true`, Windows 11 24H2 o posterior).
- Archivos ocultos y "Finalizar tarea" son `ui.*` (Task 10); el perfil `dev` los incluye.
- Sin exclusiones de Defender ni modo de rendimiento de Defender (ver "Acciones descartadas" y la lista negra).

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'dev catalog' {
    It 'ships the dev tweaks in this order' {
        $expected = @(
            'dev.developer-mode',
            'dev.long-paths',
            'dev.sudo-enable'
        ) -join ','
        Get-CategoryId 'dev' | Should -Be $expected
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `dev catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/dev.json`**

Contenido completo de `catalog/dev.json` (3 ajustes):

```json
{
  "tweaks": [
    {
      "id": "dev.developer-mode",
      "title": { "es": "Activar el Modo desarrollador", "en": "Turn on Developer Mode" },
      "why": { "es": "Permite instalar apps de prueba sin licencia y crear vínculos simbólicos sin ser administrador (git, npm, pnpm).", "en": "Allows installing test apps without a license and creating symbolic links without being administrator (git, npm, pnpm)." },
      "risk": "medium",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock", "name": "AllowDevelopmentWithoutDevLicense", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode", "https://blogs.windows.com/windowsdeveloper/2016/12/02/symlinks-windows-10/"]
    },
    {
      "id": "dev.long-paths",
      "title": { "es": "Permitir rutas de más de 260 caracteres", "en": "Allow paths longer than 260 characters" },
      "why": { "es": "Evita errores en node_modules, git y compiladores con carpetas muy anidadas. Solo lo usan las apps preparadas; el Explorador no.", "en": "Avoids errors in node_modules, git and compilers with deeply nested folders. Only apps that opt in use it; Explorer does not." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem", "name": "LongPathsEnabled", "kind": "DWord", "value": 1 },
      "rebootRequired": true,
      "sources": ["https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation"]
    },
    {
      "id": "dev.sudo-enable",
      "title": { "es": "Activar sudo para Windows", "en": "Turn on sudo for Windows" },
      "why": { "es": "Permite ejecutar un comando como administrador desde una consola normal, en una ventana nueva y con confirmación de UAC.", "en": "Lets you run one command as administrator from a normal console, in a new window with a UAC prompt." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["11"], "minBuild": 26100, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry",
      "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Sudo", "name": "Enabled", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/en-us/windows/advanced-settings/sudo/", "https://github.com/microsoft/sudo"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'dev.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
dev.developer-mode                            not-applied
dev.long-paths                                not-applied
dev.sudo-enable                               not-applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/dev.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de desarrollo"
```

---

### Task 20: Acción `onedrive`

> **Corrección posterior a la revisión.**
> - **Nada se ejecuta elevado desde una ruta que el usuario pueda escribir.** winget sale del paquete App Installer (`Microsoft.DesktopAppInstaller`) de la cuenta, o de cualquier cuenta si el proceso es administrador: editor `8wekyb3d8bbwe`, `SignatureKind` `Store` o `System`, `InstallLocation` dentro de `[Environment]::GetFolderPath('ProgramFiles')\WindowsApps\` y `winget.exe` con su carpeta de confianza (`Test-TuneupTrustedExecutable`: dueño y escritura solo de SYSTEM, TrustedInstaller o Administradores, sin junction en el camino; se aceptan vínculos físicos y se ignoran las entradas solo heredables). Si Windows no deja leer el ACL, deciden la carpeta y la firma. Elevado sin un winget así, error claro; sin elevar se puede usar el del `PATH`. Verificado en el equipo (solo lectura): App Installer 1.29.379.0 en `C:\Program Files\WindowsApps\...`, dueño SYSTEM, TrustedInstaller con control total y el resto solo lectura; `Get-Acl` se pudo leer sin elevar. El SID de TrustedInstaller del motor estaba mal escrito y se corrigió (`S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464`).
> - **Desinstaladores de confianza.** La instalación por máquina se quita con el `OneDriveSetup.exe` de su carpeta solo si es de confianza; la por usuario, con `%SystemRoot%\System32\OneDriveSetup.exe /uninstall` (el de Windows, de TrustedInstaller y vínculo físico a WinSxS), nunca con la copia de `AppData`. Es el comando habitual de las respuestas de soporte de Microsoft para desinstalar OneDrive del usuario que lo corre, pero no se pudo comprobar aquí sin desinstalar nada (en este equipo el de System32 es 25.087 y el cliente instalado es más nuevo): si no quita la instalación, la espera lo detecta y el resultado es `failed` con el motivo, sin cambios. Las carpetas salen de `[Environment]::GetFolderPath` y las versiones se comparan como `[version]`.
> - **Todas las cuentas.** Antes de `/allusers` se recorre `ProfileList` (SID `S-1-5-21-*` o `S-1-12-1-*`, distintos del actual): con la colmena cargada en `HKU` se revisan Known Folder Move y los archivos solo en la nube de esa cuenta; sin ella, una carpeta `OneDrive*` del perfil con contenido, o un perfil que no se puede leer, niega (`onedrive-other-accounts`). También niega si el proceso no corre con la cuenta dueña de `explorer.exe` en su sesión, o si no la puede determinar (`onedrive-session-user`): con elevación sobre el hombro `HKCU`, `AppData` y el desinstalador por usuario serían de otra cuenta.
> - **Falla cerrado.** Lo que `Get-ChildItem` no pudo listar (`-ErrorVariable`) niega con `onedrive-scan-incomplete`; se revisan carpetas además de archivos (marcadores de carpeta), con prefijo `\\?\` para rutas largas, las bibliotecas de SharePoint o Teams sincronizadas fuera de la raíz (nombres de valor de `Accounts\*\Tenants\*`) y las carpetas `OneDrive*` del perfil. Cualquier carpeta del shell (todos los valores de `User Shell Folders`) dentro de OneDrive cuenta como Known Folder Move.
> - **Detalles.** Cada tipo de instalación se espera por separado y un tiempo agotado es un problema (aunque el desinstalador termine con 0): `partial` si el otro tipo sí se fue, `failed` si no; el detalle de los archivos en la nube solo da la cantidad y el nombre de la carpeta de la primera, nunca una ruta; si OneDrive estaba abierto se dice en `detail`. Deshacer reinstala cada tipo que falte (primero por máquina) con el motivo `reinstalled-onedrive` y dice cuál no pudo confirmar. El estado guarda `currentUserSid` cuando está instalado.
> - **Motor.** `Test-TuneupAppxEntryOfOtherUser` pasa a `Test-TuneupEntryOfOtherUser`: toda entrada cuyo estado trae un `currentUserSid` distinto del usuario actual queda `other-user` (la advertencia dice `<tipo> entry`) y `last` no elige su corrida para otra cuenta; para `appx` no cambia nada.
> - Motivos nuevos con texto en `es` y `en`: `onedrive-scan-incomplete`, `onedrive-other-accounts`, `onedrive-session-user` y `reinstalled-onedrive`.
> - **Segunda revisión.** `Get-ChildItem -Recurse` de Windows PowerShell 5.1 no entra en puntos de reanálisis (un archivo `Offline` detrás de una junction daba 0 encontrados y 0 errores), y las carpetas de OneDrive son puntos de reanálisis del filtro de la nube: el recorrido pasa a ser manual con `DirectoryInfo.EnumerateFileSystemInfos` y `\\?\`. Entra en carpetas marcador y en puntos de reanálisis que no son vínculos (`LinkType` vacío); una junction o un vínculo simbólico dentro de una raíz cuenta como no revisado (niega con `onedrive-scan-incomplete`) y toda excepción al listar es un error. Las cuentas sin sesión suman las raíces de `SyncRootManager\OneDrive!*\UserSyncRoots` (HKLM, un valor por SID). Las cuentas se toman solo por SID, sin el filtro `\Users\`, y `ProfileImagePath` se lee sin expandir y se expande con `GetFolderPath('Windows')` y su unidad. La comprobación de la cuenta del escritorio pasa al motor (`Get-TuneupSessionUserSid`, `Test-TuneupSessionUser`).

**Files:**
- Create: `actions/onedrive.ps1`
- Modify: `i18n/es.json`, `i18n/en.json`
- Test: `tests/OneDrive.Tests.ps1`

OneDrive es un programa Win32 (no tiene producto en la Store), así que no puede ser un ajuste `appx`. La acción:

- **Instalado** significa un `OneDrive.exe` real: por usuario en `%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe` o por máquina bajo `Program Files\Microsoft OneDrive` (en la raíz o una carpeta de versión más abajo). Carpetas, registros y el `OneDriveSetup.exe` que deja una desinstalación no cuentan (verificado en el equipo: quedaron restos de una desinstalación anterior y el ajuste da `applied`).
- **Se niega sin tocar nada** (`New-TuneupOutcome -Refused`, Task 5) si Escritorio, Documentos o Imágenes viven en una carpeta de OneDrive (Known Folder Move: motivo `onedrive-known-folders`) o si las carpetas de OneDrive tienen archivos solo en la nube (atributos `RECALL_ON_DATA_ACCESS`, `RECALL_ON_OPEN` u `OFFLINE`: motivo `onedrive-online-only-files`); listar una carpeta no descarga nada.
- **Desinstala** con el `OneDriveSetup.exe` que está junto al cliente: `/uninstall /allusers` si es por máquina, `/uninstall` si es por usuario; espera hasta 90 s a que `OneDrive.exe` desaparezca (el instalador delega en un proceso elevado). Nunca borra un archivo ni una carpeta del usuario.
- Otras cuentas con su propio OneDrive por usuario no se pueden tocar desde aquí: si OneDrive se fue de esta cuenta (o de la máquina) pero quedan otras, `partial` con la explicación; si no se pudo quitar nada, falla.
- **Deshacer** reinstala con `winget install --id Microsoft.OneDrive --source winget` (`--override "/silent /allusers"` si era por máquina), con los códigos de éxito del motor; no hace nada si no estaba instalado o si ya volvió. El usuario vuelve a iniciar sesión; Known Folder Move y el OneDrive de otras cuentas no se restauran. Es `ask: true` y `medium` en el catálogo (Task 21).

Todo lo que lee o ejecuta pasa por ayudantes (`Get-OnedriveActionHelperInstall`, `Test-OnedriveActionHelperRedirected`, `Get-OnedriveActionHelperOnlineOnly`, `Get-OnedriveActionHelperOtherProfile`, `Wait-OnedriveActionHelperRemoval`) y por `Invoke-TuneupNative`/`Invoke-TuneupWinget`, que las pruebas simulan.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/OneDrive.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Tweak = New-TestTweak -Id 'apps.onedrive' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
    function New-TestInstall([bool]$PerUser, [bool]$PerMachine, [string]$UserSetup, [string]$MachineSetup) {
        [pscustomobject]@{ perUser = $PerUser; perMachine = $PerMachine; userSetup = $UserSetup; machineSetup = $MachineSetup; version = '26.150.0804.0011' }
    }
}

Describe 'onedrive action' {
    BeforeEach {
        # Nothing real is read, run or installed: every look at the system goes through a helper.
        $script:Setup = Join-Path $TestDrive 'OneDriveSetup.exe'
        Set-Content -LiteralPath $Setup -Value 'fake' -Encoding ASCII
        $script:Installs = @((New-TestInstall $false $true $null $Setup))
        $script:InstallCalls = 0
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall {
            $index = [Math]::Min($script:InstallCalls, $script:Installs.Count - 1)
            $script:InstallCalls++
            $script:Installs[$index]
        }
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRedirected { $false }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOtherProfile { 0 }
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $true }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = 0; Output = 'Successfully installed' } }
    }

    It 'is loaded from actions/ and passes the catalog check' {
        @(Get-TuneupActionLoadError | Where-Object { $_.name -eq 'onedrive' }).Count | Should -Be 0
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'is applied when no OneDrive.exe is installed, so leftovers do not count' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        (Get-TuneupState -Tweak $Tweak).installed | Should -BeFalse
    }

    It 'uninstalls a per-machine OneDrive for all users with the setup next to it' {
        $script:Installs = @((New-TestInstall $false $true $null $Setup), (New-TestInstall $false $false $null $null))
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $script:InstallCalls = 0
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        $outcome.refused | Should -BeFalse
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $FilePath -eq $Setup -and ($Arguments -join ' ') -eq '/uninstall /allusers' }
    }

    It 'uninstalls a per-user OneDrive without /allusers' {
        $script:Installs = @((New-TestInstall $true $false $Setup $null), (New-TestInstall $false $false $null $null))
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq '/uninstall' }
    }

    It 'refuses, without running anything, when <Name>' -TestCases @(
        @{ Name = 'Known Folder Move is on'; Reason = 'onedrive-known-folders'; Redirected = $true; OnlineOnly = $null }
        @{ Name = 'there are online-only files'; Reason = 'onedrive-online-only-files'; Redirected = $false; OnlineOnly = 'C:\Users\me\OneDrive\notes.docx' }
    ) {
        param($Reason, $Redirected, $OnlineOnly)
        $script:Redirected = $Redirected
        $script:OnlineOnly = $OnlineOnly
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRedirected { $script:Redirected }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { $script:OnlineOnly }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be $Reason
        $outcome.detail | Should -BeLike '*nothing was changed*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'has a text for each refusal in both languages' {
        foreach ($lang in 'es', 'en') {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $lang
            foreach ($reason in 'onedrive-known-folders', 'onedrive-online-only-files') {
                Get-TuneupText -Key "reason.$reason" | Should -Not -Be "reason.$reason"
            }
        }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }

    It 'is partial when OneDrive is gone here but other accounts keep their own' {
        $script:Installs = @((New-TestInstall $false $true $null $Setup), (New-TestInstall $false $false $null $null))
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOtherProfile { 2 }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*2 other account(s)*'
    }

    It 'fails when the setup could not remove it' {
        $script:Installs = @((New-TestInstall $false $true $null $Setup))
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $false }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 5; Output = 'Access is denied' } }
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*ended with code 5*'
    }

    It 'fails, without running anything, when the setup is missing' {
        $script:Installs = @((New-TestInstall $false $true $null (Join-Path $TestDrive 'missing.exe')))
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*OneDriveSetup.exe was not found*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'reinstalls it for all users on undo when it was per-machine' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        $state = [pscustomobject]@{ installed = $true; perUser = $false; perMachine = $true; version = '26.1' }
        $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id Microsoft.OneDrive --source winget --exact --no-upgrade --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --override /silent /allusers'
        }
    }

    It 'reinstalls it for the current user on undo when it was per-user' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -notlike '*--override*' }
    }

    It 'does nothing on undo if it was not installed or is installed again' {
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $false; perUser = $false; perMachine = $false; version = $null }) | Out-Null
        $script:Installs = @((New-TestInstall $true $false $Setup $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'fails the undo with the way to install it by hand when winget fails' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No package found' } }
        { Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) } |
            Should -Throw '*winget install --id Microsoft.OneDrive*'
    }
}

Describe 'onedrive detection helpers' {
    It 'sees Known Folder Move under a OneDrive folder and not under the local profile' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperRoot { 'C:\Users\me\OneDrive - Contoso' }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperKnownFolder { 'C:\Users\me\Desktop', 'C:\Users\me\OneDrive - Contoso\Documents' }
        & (Get-Module Tuneup) { Test-OnedriveActionHelperRedirected } | Should -BeTrue
        Mock -ModuleName Tuneup Get-OnedriveActionHelperKnownFolder { 'C:\Users\me\Desktop', 'C:\Users\me\Documents' }
        & (Get-Module Tuneup) { Test-OnedriveActionHelperRedirected } | Should -BeFalse
    }

    It 'finds an online-only file by its attributes and ignores a normal one' {
        $root = Join-Path $TestDrive 'OneDrive'
        New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'local.txt') -Value 'x'
        Mock -ModuleName Tuneup Get-OnedriveActionHelperRoot { $root }
        & (Get-Module Tuneup) { Get-OnedriveActionHelperOnlineOnly } | Should -BeNullOrEmpty
        $cloud = Join-Path $root 'sub\cloud.txt'
        Set-Content -LiteralPath $cloud -Value 'x'
        # OFFLINE (0x1000) is one of the attributes of an online-only placeholder.
        (Get-Item -LiteralPath $cloud).Attributes = [System.IO.FileAttributes]::Offline
        & (Get-Module Tuneup) { Get-OnedriveActionHelperOnlineOnly } | Should -Be $cloud
    }

    It 'stops waiting as soon as OneDrive.exe is gone' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall { New-TestInstall $false $false $null $null }
        Mock -ModuleName Tuneup Start-Sleep { }
        & (Get-Module Tuneup) { Wait-OnedriveActionHelperRemoval -Seconds 5 } | Should -BeTrue
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 0 -Exactly
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/OneDrive.Tests.ps1`
Expected: FAIL: el script no existe y los motivos no tienen texto.

- [ ] **Step 3: Escribir la acción**

Crear `actions/onedrive.ps1`:

```powershell
# Uninstalls the OneDrive sync client (a Win32 program, not a Store app) and never deletes a file or
# folder of the user. It refuses, changing nothing, when Desktop, Documents or Pictures live in a
# OneDrive folder (Known Folder Move) or when OneDrive holds online-only files, which would no longer
# open from this PC. Undo reinstalls it with winget (package Microsoft.OneDrive, source winget); the
# user signs in again. Installed means a real OneDrive.exe: folders and logs left by an earlier
# uninstall do not count.

function Get-OnedriveActionHelperRoot {
    param()
    # Folders where OneDrive keeps the user's synced files.
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($name in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $roots.Add($value) }
    }
    $accounts = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path -LiteralPath $accounts) {
        foreach ($account in Get-ChildItem -LiteralPath $accounts -ErrorAction SilentlyContinue) {
            $folder = (Get-ItemProperty -LiteralPath $account.PSPath -ErrorAction SilentlyContinue).UserFolder
            if ($folder) { $roots.Add([string]$folder) }
        }
    }
    @($roots | Sort-Object -Unique)
}

function Get-OnedriveActionHelperKnownFolder {
    param()
    # Desktop, Documents and Pictures as the registry keeps them (with %USERPROFILE% unexpanded).
    $item = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    foreach ($name in 'Desktop', 'Personal', 'My Pictures') {
        $raw = $null
        if ($null -ne $item) { $raw = $item.$name }
        if ($raw) { [Environment]::ExpandEnvironmentVariables([string]$raw) }
    }
}

function Test-OnedriveActionHelperRedirected {
    param()
    # Known Folder Move: one of those folders lives under a OneDrive folder.
    $roots = @(Get-OnedriveActionHelperRoot)
    foreach ($folder in @(Get-OnedriveActionHelperKnownFolder)) {
        if ($folder -match '\\OneDrive( - [^\\]+)?(\\|$)') { return $true }
        foreach ($root in $roots) {
            if (($folder.TrimEnd('\') + '\').StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    $false
}

function Get-OnedriveActionHelperOnlineOnly {
    param()
    # Files On-Demand placeholders: RECALL_ON_DATA_ACCESS, RECALL_ON_OPEN or OFFLINE. Listing a
    # folder does not download anything. Returns the first one found, or nothing.
    $recall = 0x400000 -bor 0x40000 -bor 0x1000
    foreach ($root in @(Get-OnedriveActionHelperRoot)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { ([int]$_.Attributes -band $recall) -ne 0 } | Select-Object -First 1
        if ($null -ne $hit) { return $hit.FullName }
    }
}

function Get-OnedriveActionHelperInstall {
    param()
    $local = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\OneDrive'
    $result = [ordered]@{ perUser = $false; perMachine = $false; userSetup = $null; machineSetup = $null; version = $null }
    $userExe = Join-Path -Path $local -ChildPath 'OneDrive.exe'
    if (Test-Path -LiteralPath $userExe -PathType Leaf) {
        $result.perUser = $true
        $result.version = (Get-Item -LiteralPath $userExe).VersionInfo.FileVersion
        $setup = Get-ChildItem -LiteralPath $local -Filter 'OneDriveSetup.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue |
            Sort-Object { $_.VersionInfo.FileVersion } -Descending | Select-Object -First 1
        if ($null -ne $setup) { $result.userSetup = $setup.FullName }
    }
    # Per-machine installs keep OneDrive.exe at the root of Microsoft OneDrive or one version folder down.
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $root = Join-Path -Path $base -ChildPath 'Microsoft OneDrive'
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $exe = Get-ChildItem -LiteralPath $root -Filter 'OneDrive.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $exe) { continue }
        $result.perMachine = $true
        if (-not $result.version) { $result.version = $exe.VersionInfo.FileVersion }
        $setup = Get-ChildItem -LiteralPath $root -Filter 'OneDriveSetup.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue |
            Sort-Object { $_.VersionInfo.FileVersion } -Descending | Select-Object -First 1
        if ($null -ne $setup) { $result.machineSetup = $setup.FullName }
        break
    }
    [pscustomobject]$result
}

function Get-OnedriveActionHelperOtherProfile {
    param()
    # Other accounts with their own per-user OneDrive: it can only be removed signed in as them.
    $mine = [Environment]::GetEnvironmentVariable('USERPROFILE')
    $count = 0
    foreach ($profileKey in Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue) {
        $path = (Get-ItemProperty -LiteralPath $profileKey.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $path -or $path -ieq $mine -or $path -notlike '*\Users\*') { continue }
        if (Test-Path -LiteralPath (Join-Path -Path $path -ChildPath 'AppData\Local\Microsoft\OneDrive\OneDrive.exe') -PathType Leaf) { $count++ }
    }
    $count
}

function Wait-OnedriveActionHelperRemoval {
    param([int]$Seconds = 90)
    # The setup hands the work to an elevated child and can return before it ends.
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $now = Get-OnedriveActionHelperInstall
        if (-not ($now.perUser -or $now.perMachine)) { return $true }
        Start-Sleep -Seconds 2
    } until ((Get-Date) -gt $deadline)
    $false
}

function Get-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak)
    $install = Get-OnedriveActionHelperInstall
    [pscustomobject]@{
        id         = $Tweak.id
        installed  = ($install.perUser -or $install.perMachine)
        perUser    = $install.perUser
        perMachine = $install.perMachine
        version    = $install.version
    }
}

function Test-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak)
    if ((Get-OnedriveActionState -Tweak $Tweak).installed) { return 'not-applied' }
    'applied'
}

function Set-OnedriveActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    $install = Get-OnedriveActionHelperInstall
    if (-not ($install.perUser -or $install.perMachine)) { return }
    # The refusals come before anything is touched.
    if (Test-OnedriveActionHelperRedirected) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-known-folders' -Detail "$($Tweak.id): Desktop, Documents or Pictures are in OneDrive (Known Folder Move). Move them back to the local profile in the OneDrive settings first; nothing was changed")
    }
    $placeholder = Get-OnedriveActionHelperOnlineOnly
    if ($placeholder) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-online-only-files' -Detail "$($Tweak.id): OneDrive holds files that are only in the cloud (for example $placeholder). Make them available offline or move them, then run again; nothing was changed")
    }
    $steps = @()
    if ($install.perMachine) { $steps += , [pscustomobject]@{ setup = $install.machineSetup; arguments = @('/uninstall', '/allusers') } }
    if ($install.perUser) { $steps += , [pscustomobject]@{ setup = $install.userSetup; arguments = @('/uninstall') } }
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($step in $steps) {
        if (-not $step.setup -or -not (Test-Path -LiteralPath $step.setup -PathType Leaf)) {
            $problems.Add('OneDriveSetup.exe was not found next to the installed client')
            continue
        }
        $run = Invoke-TuneupNative -FilePath $step.setup -Arguments ([string[]]$step.arguments)
        if (-not (Wait-OnedriveActionHelperRemoval) -and $run.ExitCode -ne 0) {
            $problems.Add("OneDriveSetup.exe $($step.arguments -join ' ') ended with code $($run.ExitCode): $($run.Output)")
        }
    }
    $others = [int](Get-OnedriveActionHelperOtherProfile)
    if ($others -gt 0) { $problems.Add("$others other account(s) still have their own OneDrive; each one must remove it signed in") }
    if (-not $problems.Count) { return }
    $message = $problems -join '; '
    $now = Get-OnedriveActionHelperInstall
    # Gone for this account, or for all users, while something else is left: partly done.
    if (($install.perMachine -and -not $now.perMachine) -or ($install.perUser -and -not $now.perUser)) {
        return (New-TuneupOutcome -Partial -Detail $message)
    }
    throw $message
}

function Restore-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    # Nothing to give back if it was not installed, or if it is installed again.
    if (-not [bool]$State.installed) { return }
    $now = Get-OnedriveActionHelperInstall
    if ($now.perUser -or $now.perMachine) { return }
    $arguments = @('install', '--id', 'Microsoft.OneDrive', '--source', 'winget', '--exact', '--no-upgrade',
        '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity')
    # Installed for all users before: without /allusers the setup installs for the current user only.
    if ([bool]$State.perMachine) { $arguments += @('--override', '/silent /allusers') }
    $result = Invoke-TuneupWinget -Arguments $arguments
    if ($script:WingetSuccessCode -notcontains $result.ExitCode) {
        throw "winget could not reinstall OneDrive ($($Tweak.id)), exit code $($result.ExitCode): $($result.Output). To install it by hand: winget install --id Microsoft.OneDrive"
    }
    New-TuneupOutcome -Reason 'reinstalled' -Detail 'Sign in to OneDrive again; Known Folder Move and the OneDrive of other accounts are not restored'
}
```

- [ ] **Step 4: Textos de las negativas**

En `i18n/es.json`, después de la línea de `"reason.installed-for-other-users"`, agregar:

```json
  "reason.onedrive-known-folders": "no se tocó: Escritorio, Documentos o Imágenes están en OneDrive; devuélvelos a la carpeta local primero",
  "reason.onedrive-online-only-files": "no se tocó: OneDrive tiene archivos que solo están en la nube y dejarían de abrirse desde este equipo",
```

En `i18n/en.json`, después de la línea de `"reason.installed-for-other-users"`, agregar:

```json
  "reason.onedrive-known-folders": "left alone: Desktop, Documents or Pictures are in OneDrive; move them back to the local folder first",
  "reason.onedrive-online-only-files": "left alone: OneDrive holds files that only live in the cloud and would no longer open from this PC",
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/OneDrive.Tests.ps1`
Expected: PASS (`Tests Passed: 17, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/I18nCoverage.Tests.ps1`
Expected: PASS: la prueba ahora también lee `actions/` (Task 5) y encuentra los dos motivos nuevos y `reinstalled`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 6: Commit**

```bash
git add actions/onedrive.ps1 i18n/es.json i18n/en.json tests/OneDrive.Tests.ps1
git commit -m "feat: acción que desinstala OneDrive sin borrar archivos y se niega si hay datos en riesgo"
```

---

### Task 21: Catálogo `apps.json` (apps)

**Files:**
- Create: `catalog/apps.json`
- Modify: `tests/CatalogContent.Tests.ps1`

Archivo nuevo. Usa la acción `onedrive` (Task 20). Decisiones aplicadas:

- Solo apps cuyo deshacer funciona: `winget show --id <storeId> --source msstore --exact` las encontró el 2026-10-01 y el catálogo de la Store confirmó que ese id instala el mismo paquete Appx. Las que winget no encuentra (Solitaire, Tips, People, Mapas, las apps 3D, Wallet...) quedan fuera y se listan en `catalog/notes/excluded.json` (Task 24).
- Teams nuevo (`MSTeams`, `storeId` `XP8BT8DW290MPQ`, que acepta la Task 2): el nombre Appx y el id están verificados (la API de la Store que usa winget devuelve `MSTeams_8wekyb3d8bbwe`). El Copilot `XP9CXNGPPJ97XX` no entra: no se sabe qué paquete instala.
- `ask: true` y `medium`: Copilot, Obtener ayuda, Alarmas y reloj, Reproductor multimedia, Asistencia rápida, Vínculo móvil, la app Xbox, Xbox Game Bar, Outlook nuevo, Seguridad familiar, Correo y Calendario, Teams y OneDrive.
- `apps.dev-home` avisa que deshacer instala la app que hoy ocupa su lugar en la Store.
- Nunca la Store, winget, Seguridad de Windows, Edge, los frameworks ni los componentes de inicio de sesión de Xbox (lo comprueba "Blacklist guard").

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/CatalogContent.Tests.ps1`:

```powershell
Describe 'apps catalog' {
    It 'ships the apps tweaks in this order' {
        $expected = @(
            'apps.clipchamp',
            'apps.bing-news',
            'apps.bing-weather',
            'apps.bing-finance',
            'apps.office-hub',
            'apps.power-automate',
            'apps.dev-home',
            'apps.messaging',
            'apps.mixed-reality-portal',
            'apps.movies-tv',
            'apps.bing-search',
            'apps.copilot',
            'apps.get-help',
            'apps.feedback-hub',
            'apps.todos',
            'apps.alarms-clock',
            'apps.sound-recorder',
            'apps.media-player',
            'apps.quick-assist',
            'apps.phone-link',
            'apps.xbox-gaming-app',
            'apps.xbox-game-bar',
            'apps.widgets-web-experience',
            'apps.widgets-platform-runtime',
            'apps.start-experiences',
            'apps.outlook-new',
            'apps.family-safety',
            'apps.mail-calendar',
            'apps.msteams',
            'apps.onedrive'
        ) -join ','
        Get-CategoryId 'apps' | Should -Be $expected
    }

    It 'asks before removing the apps people often use' {
        $asked = @(Get-CategoryTweak 'apps' | Where-Object { $_.ask } | ForEach-Object { $_.id }) -join ','
        $asked | Should -Be 'apps.copilot,apps.get-help,apps.alarms-clock,apps.media-player,apps.quick-assist,apps.phone-link,apps.xbox-gaming-app,apps.xbox-game-bar,apps.outlook-new,apps.family-safety,apps.mail-calendar,apps.msteams,apps.onedrive'
    }

    It 'gives every Store app the id that winget reinstalls' {
        foreach ($tweak in Get-CategoryTweak 'apps' | Where-Object { $_.type -eq 'appx' }) {
            [string]$tweak.set.storeId | Should -MatchExactly '^(?:[0-9A-Z]{12}|XP[0-9A-Z]{12})$' -Because $tweak.id
        }
        (Get-CategoryTweak 'apps' | Where-Object { $_.id -eq 'apps.msteams' }).set.storeId | Should -Be 'XP8BT8DW290MPQ'
        (Get-CategoryTweak 'apps' | Where-Object { $_.id -eq 'apps.onedrive' }).set.script | Should -Be 'onedrive'
    }
}

Describe 'review decisions of the catalog' {
    BeforeAll {
        $script:All = @(Import-TuneupCatalog -Path $CatalogDir)
        function Get-One([string]$Id) { $found = @($All | Where-Object { $_.id -eq $Id }); $found.Count | Should -Be 1 -Because $Id; $found[0] }
    }

    It 'keeps Recall behind -Include: high risk, and it says undo cannot bring the snapshots back' {
        foreach ($id in 'ai.recall-snapshots-off', 'ai.recall-unavailable') {
            $tweak = Get-One $id
            $tweak.risk | Should -Be 'high' -Because $id
            [string]$tweak.why.es | Should -BeLike '*deshacer no puede devolverlas*' -Because $id
            [string]$tweak.why.en | Should -BeLike '*undo cannot bring them back*' -Because $id
        }
    }

    It 'asks before the compatibility backup task, which also feeds the appraiser' {
        $tweak = Get-One 'tasks.mare-backup'
        $tweak.risk | Should -Be 'medium'
        $tweak.ask | Should -BeTrue
        [string]$tweak.why.en | Should -BeLike '*appraiser*'
    }

    It 'does not ship the Xbox services: they are Manual by default and Disabled breaks the Xbox sign-in' {
        $names = @($All | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        foreach ($name in 'XblGameSave', 'XblAuthManager', 'XboxNetApiSvc', 'XboxGipSvc') { $names | Should -Not -Contain $name }
    }

    It 'asks before background apps are stopped, and only for Windows 10' {
        $tweak = Get-One 'performance.background-apps-off'
        $tweak.ask | Should -BeTrue
        @($tweak.os.families) -join ',' | Should -Be '10'
        [string]$tweak.why.en | Should -BeLike '*Spotlight*'
    }

    It 'sets Edge diagnostic data to required data only, as a low-risk tweak' {
        @($All | Where-Object { $_.id -eq 'edge.diagnostic-data-off' }).Count | Should -Be 0
        $tweak = Get-One 'edge.diagnostic-data-required'
        $tweak.set.name | Should -Be 'DiagnosticData'
        $tweak.set.value | Should -Be 1
        $tweak.risk | Should -Be 'low'
    }

    It 'declares the editions the documentation gives' -TestCases @(
        @{ Id = 'ads.settings-home-365'; Editions = 'Enterprise,Education' }
        @{ Id = 'ui.news-interests-win10'; Editions = 'Pro,Enterprise,Education' }
        @{ Id = 'ads.start-hide-recommended-policy'; Editions = 'Pro,Enterprise,Education' }
        @{ Id = 'ai.notepad-ai-off'; Editions = 'Home,Pro,Enterprise,Education' }
        @{ Id = 'privacy.diagnostic-data-required'; Editions = 'Pro,Enterprise,Education' }
    ) {
        param($Id, $Editions)
        @((Get-One $Id).os.editions) -join ',' | Should -Be $Editions
    }

    It 'says that the Edge sidebar policy skips Microsoft-account profiles, and that diagnostic data is not for Insider builds' {
        [string](Get-One 'edge.sidebar-off').why.en | Should -BeLike '*Microsoft account*'
        [string](Get-One 'privacy.diagnostic-data-required').why.en | Should -BeLike '*Insider*'
    }

    It 'cites the Microsoft settings reference for Game Mode and background recording' {
        foreach ($id in 'gaming.game-mode-on', 'gaming.background-recording-off') {
            @((Get-One $id).sources) | Should -Contain 'https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11' -Because $id
        }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: FAIL en `apps catalog`: el archivo todavía no tiene esos ajustes.

- [ ] **Step 3: Escribir `catalog/apps.json`**

Contenido completo de `catalog/apps.json` (30 ajustes):

```json
{
  "tweaks": [
    {
      "id": "apps.clipchamp",
      "title": { "es": "Quitar Clipchamp", "en": "Remove Clipchamp" },
      "why": { "es": "Editor de video preinstalado que casi nunca se usa.", "en": "Preinstalled video editor that is rarely used." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Clipchamp.Clipchamp", "storeId": "9P1J8S7CCWWT", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9p1j8s7ccwwt", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.bing-news",
      "title": { "es": "Quitar Noticias (Microsoft News)", "en": "Remove News (Microsoft News)" },
      "why": { "es": "App de noticias de Microsoft; nada más depende de ella.", "en": "Microsoft news reader; nothing else depends on it." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.BingNews", "storeId": "9WZDNCRFHVFW", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfhvfw", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.bing-weather",
      "title": { "es": "Quitar la app Tiempo (MSN Weather)", "en": "Remove the Weather app (MSN Weather)" },
      "why": { "es": "App del clima; el clima de la barra de tareas viene de Widgets, no de esta app.", "en": "Weather app; the taskbar weather comes from Widgets, not from this app." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.BingWeather", "storeId": "9WZDNCRFJ3Q2", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfj3q2", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.bing-finance",
      "title": { "es": "Quitar Finanzas (MSN Money)", "en": "Remove Finance (MSN Money)" },
      "why": { "es": "App descontinuada de noticias financieras, propia de Windows 10.", "en": "Discontinued finance news app, specific to Windows 10." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.BingFinance", "storeId": "9WZDNCRFHV4V", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfhv4v", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.office-hub",
      "title": { "es": "Quitar la app Microsoft 365 (Copilot)", "en": "Remove the Microsoft 365 (Copilot) app" },
      "why": { "es": "Es solo un acceso a Office y publicidad de suscripciones; Word y Excel no dependen de ella.", "en": "It is only a launcher and subscription promo; Word and Excel do not depend on it." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.MicrosoftOfficeHub", "storeId": "9WZDNCRD29V9", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrd29v9", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.power-automate",
      "title": { "es": "Quitar Power Automate", "en": "Remove Power Automate" },
      "why": { "es": "Herramienta de automatización (RPA) que casi nadie usa; se puede reinstalar.", "en": "RPA automation tool that few people use; it can be reinstalled." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.PowerAutomateDesktop", "storeId": "9NFTCH6J7FHV", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nftch6j7fhv", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.dev-home",
      "title": { "es": "Quitar Dev Home (descontinuada)", "en": "Remove Dev Home (discontinued)" },
      "why": { "es": "Microsoft retiró Dev Home. Al deshacer, la Store instala la app que hoy ocupa su lugar (Configuración avanzada de Windows).", "en": "Microsoft retired Dev Home. Undo installs the app that now takes its place in the Store (Windows Advanced Settings)." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.Windows.DevHome", "storeId": "9N8MHTPHNGVV", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9n8mhtphngvv", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.messaging",
      "title": { "es": "Quitar Mensajes (Windows 10)", "en": "Remove Messaging (Windows 10)" },
      "why": { "es": "App de mensajes atada a Skype, descontinuada.", "en": "Messaging app tied to Skype, discontinued." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.Messaging", "storeId": "9WZDNCRFJBQ6", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfjbq6", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.mixed-reality-portal",
      "title": { "es": "Quitar el Portal de realidad mixta", "en": "Remove the Mixed Reality Portal" },
      "why": { "es": "Solo sirve con visores de realidad mixta de Windows.", "en": "Only useful with Windows Mixed Reality headsets." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.MixedReality.Portal", "storeId": "9NG1H8B3ZC7M", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9ng1h8b3zc7m", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.movies-tv",
      "title": { "es": "Quitar Películas y TV", "en": "Remove Movies & TV" },
      "why": { "es": "Reproductor y tienda de video de Microsoft, ya reemplazado por el Reproductor multimedia.", "en": "Microsoft video player and store, replaced by Media Player." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.ZuneVideo", "storeId": "9WZDNCRFJ3P2", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfj3p2", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.bing-search",
      "title": { "es": "Quitar la integración de Bing en la búsqueda", "en": "Remove the Bing search integration" },
      "why": { "es": "Es el componente que lleva la búsqueda web de Bing al menú Inicio.", "en": "The component that brings Bing web search into Start." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.BingSearch", "storeId": "9NZBF4GT040C", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nzbf4gt040c", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.copilot",
      "title": { "es": "Quitar la app Copilot", "en": "Remove the Copilot app" },
      "why": { "es": "Asistente de IA; se quita para reducir procesos y datos enviados.", "en": "AI assistant; removed to cut processes and data sent out." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.Copilot", "storeId": "9NHT9RB2F4HD", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nht9rb2f4hd", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.get-help",
      "title": { "es": "Quitar Obtener ayuda", "en": "Remove Get Help" },
      "why": { "es": "Algunos solucionadores de problemas y enlaces de soporte la abren; sin ella no hay ayuda en la app.", "en": "Some troubleshooters and support links open it; without it there is no in-app help." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.GetHelp", "storeId": "9PKDZBMV1H3T", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9pkdzbmv1h3t", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.feedback-hub",
      "title": { "es": "Quitar el Centro de opiniones", "en": "Remove Feedback Hub" },
      "why": { "es": "Solo sirve para enviar comentarios a Microsoft o para Insiders.", "en": "Only used to send feedback to Microsoft or by Insiders." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.WindowsFeedbackHub", "storeId": "9NBLGGH4R32N", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nblggh4r32n", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.todos",
      "title": { "es": "Quitar Microsoft To Do", "en": "Remove Microsoft To Do" },
      "why": { "es": "Las tareas viven en tu cuenta Microsoft; reaparecen al reinstalar.", "en": "Tasks live in your Microsoft account; they come back when you reinstall." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.Todos", "storeId": "9NBLGGH5R558", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nblggh5r558", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.alarms-clock",
      "title": { "es": "Quitar Alarmas y reloj", "en": "Remove Alarms & Clock" },
      "why": { "es": "Se pierden alarmas, temporizadores y sesiones de concentración.", "en": "Alarms, timers and focus sessions are lost." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.WindowsAlarms", "storeId": "9WZDNCRFJ3PR", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfj3pr", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.sound-recorder",
      "title": { "es": "Quitar la Grabadora de sonidos", "en": "Remove Sound Recorder" },
      "why": { "es": "Grabadora básica; las grabaciones ya hechas quedan en Documentos.", "en": "Basic recorder; existing recordings stay in Documents." },
      "risk": "low",
      "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.WindowsSoundRecorder", "storeId": "9WZDNCRFHWKN", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfhwkn", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.media-player",
      "title": { "es": "Quitar el Reproductor multimedia", "en": "Remove Media Player" },
      "why": { "es": "Es el reproductor predeterminado de audio y video; sin él hay que instalar otro.", "en": "It is the default audio and video player; you need another one without it." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.ZuneMusic", "storeId": "9WZDNCRFJ3PT", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfj3pt", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.quick-assist",
      "title": { "es": "Quitar Asistencia rápida", "en": "Remove Quick Assist" },
      "why": { "es": "Es la herramienta con la que otros te ayudan a distancia; sin ella no podrán.", "en": "The tool others use to help you remotely; without it they cannot." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "MicrosoftCorporationII.QuickAssist", "storeId": "9P7BP5VNWKX5", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9p7bp5vnwkx5", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.phone-link",
      "title": { "es": "Quitar Vínculo con el móvil (Phone Link)", "en": "Remove Phone Link" },
      "why": { "es": "Conecta el teléfono al PC; si lo usas, deja de funcionar.", "en": "Connects your phone to the PC; it stops working if you use it." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.YourPhone", "storeId": "9NMPJ99VJBWV", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nmpj99vjbwv", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.xbox-gaming-app",
      "title": { "es": "Quitar la app Xbox", "en": "Remove the Xbox app" },
      "why": { "es": "Necesaria para Game Pass y para instalar algunos juegos de la Store.", "en": "Needed for Game Pass and for installing some Store games." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.GamingApp", "storeId": "9MV0B5HZVK9Z", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9mv0b5hzvk9z", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.xbox-game-bar",
      "title": { "es": "Quitar la Xbox Game Bar", "en": "Remove the Xbox Game Bar" },
      "why": { "es": "Barra de juego con captura; sin ella Win+G no hace nada.", "en": "Gaming bar with capture; Win+G does nothing without it." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.XboxGamingOverlay", "storeId": "9NZKPSTSNW4P", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nzkpstsnw4p", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.widgets-web-experience",
      "title": { "es": "Quitar el paquete de experiencia web (Widgets)", "en": "Remove the Web Experience Pack (Widgets)" },
      "why": { "es": "Es lo que muestra el panel de Widgets y su fuente de noticias.", "en": "It renders the Widgets panel and its news feed." },
      "risk": "medium",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "MicrosoftWindows.Client.WebExperience", "storeId": "9MSSGKG348SP", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9mssgkg348sp", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.widgets-platform-runtime",
      "title": { "es": "Quitar el runtime de Widgets", "en": "Remove the Widgets runtime" },
      "why": { "es": "Componente que hace funcionar los Widgets; sin Widgets no hace falta.", "en": "Component that runs Widgets; not needed without them." },
      "risk": "medium",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.WidgetsPlatformRuntime", "storeId": "9N3RK8ZV2ZR8", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9n3rk8zv2zr8", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.start-experiences",
      "title": { "es": "Quitar la app de experiencias de Inicio", "en": "Remove the Start Experiences app" },
      "why": { "es": "Alimenta el contenido de Widgets y de Inicio; puede irse con ellos.", "en": "Feeds the content of Widgets and Start; can go with them." },
      "risk": "medium",
      "ask": false,
      "os": { "families": ["11"], "minBuild": 22621, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.StartExperiencesApp", "storeId": "9PC1H9VN18CM", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9pc1h9vn18cm", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.outlook-new",
      "title": { "es": "Quitar el nuevo Outlook para Windows", "en": "Remove the new Outlook for Windows" },
      "why": { "es": "Cliente de correo; si es tu correo, conviene conservarlo.", "en": "Mail client; keep it if it is your mail app." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "Microsoft.OutlookForWindows", "storeId": "9NRX63209R7B", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9nrx63209r7b", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.family-safety",
      "title": { "es": "Quitar Seguridad familiar", "en": "Remove Family Safety" },
      "why": { "es": "Controles parentales; en cuentas de menores deja de aplicarlos.", "en": "Parental controls; on child accounts it stops applying them." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "MicrosoftCorporationII.MicrosoftFamily", "storeId": "9PDJDJS743XF", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9pdjdjs743xf", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.mail-calendar",
      "title": { "es": "Quitar Correo y Calendario (descontinuada)", "en": "Remove Mail and Calendar (discontinued)" },
      "why": { "es": "Microsoft la reemplazó por el nuevo Outlook; People depende de ella.", "en": "Microsoft replaced it with the new Outlook; People depends on it." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "microsoft.windowscommunicationsapps", "storeId": "9WZDNCRFHVQM", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/9wzdncrfhvqm", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.msteams",
      "title": { "es": "Quitar Microsoft Teams", "en": "Remove Microsoft Teams" },
      "why": { "es": "Reuniones y chat; si lo usas en el trabajo, conviene conservarlo.", "en": "Meetings and chat; keep it if you use it for work." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "appx",
      "scope": "machine",
      "set": { "name": "MSTeams", "storeId": "XP8BT8DW290MPQ", "action": "remove" },
      "rebootRequired": false,
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json", "https://apps.microsoft.com/detail/xp8bt8dw290mpq", "https://learn.microsoft.com/windows/application-management/overview-windows-apps", "https://learn.microsoft.com/powershell/module/appx/remove-appxpackage"]
    },
    {
      "id": "apps.onedrive",
      "title": { "es": "Desinstalar OneDrive (sin borrar tus archivos)", "en": "Uninstall OneDrive (your files are kept)" },
      "why": { "es": "Quita el cliente de sincronización; tus carpetas y archivos no se tocan. Se rechaza si Escritorio, Documentos o Imágenes están en OneDrive o hay archivos solo en la nube.", "en": "Removes the sync client; your folders and files are not touched. Refused if Desktop, Documents or Pictures live in OneDrive or there are cloud-only files." },
      "risk": "medium",
      "ask": true,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "action",
      "scope": "machine",
      "set": { "script": "onedrive" },
      "rebootRequired": false,
      "sources": ["https://learn.microsoft.com/sharepoint/per-machine-installation", "https://support.microsoft.com/office/turn-off-disable-or-uninstall-onedrive-f32a17ce-3336-40fe-9c38-6efb09f944b0", "https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json"]
    }
  ]
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogContent.Tests.ps1`
Expected: PASS (`Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluidas `tests/CatalogQuality.Tests.ps1` (fuentes, títulos únicos, un solo dueño por valor de registro, lista negra) y la validación del catálogo de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Verificación de solo lectura en este equipo**

Pegar el bloque de "Verificación de solo lectura de cada categoría" (Convenciones) con `'apps.json'`.
Expected: una línea por ajuste y ninguna `ERROR`. En el equipo de verificación (Windows 11 Pro 26300, sin elevar) dio:

```text
apps.clipchamp                                needs-admin
apps.bing-news                                needs-admin
apps.bing-weather                             needs-admin
apps.bing-finance                             needs-admin
apps.office-hub                               needs-admin
apps.power-automate                           needs-admin
apps.dev-home                                 needs-admin
apps.messaging                                needs-admin
apps.mixed-reality-portal                     needs-admin
apps.movies-tv                                needs-admin
apps.bing-search                              needs-admin
apps.copilot                                  needs-admin
apps.get-help                                 needs-admin
apps.feedback-hub                             needs-admin
apps.todos                                    needs-admin
apps.alarms-clock                             needs-admin
apps.sound-recorder                           needs-admin
apps.media-player                             needs-admin
apps.quick-assist                             needs-admin
apps.phone-link                               needs-admin
apps.xbox-gaming-app                          needs-admin
apps.xbox-game-bar                            needs-admin
apps.widgets-web-experience                   needs-admin
apps.widgets-platform-runtime                 needs-admin
apps.start-experiences                        needs-admin
apps.outlook-new                              needs-admin
apps.family-safety                            needs-admin
apps.mail-calendar                            needs-admin
apps.msteams                                  needs-admin
apps.onedrive                                 applied
```

- [ ] **Step 6: Commit**

```bash
git add catalog/apps.json tests/CatalogContent.Tests.ps1
git commit -m "feat: catálogo de apps con deshacer"
```

---

### Task 22: Los ocho perfiles

**Files:**
- Modify: `profiles/base.json`, `profiles/privacy.json`
- Create: `profiles/dev.json`, `profiles/gaming.json`, `profiles/laptop.json`, `profiles/legacy.json`, `profiles/work.json`, `profiles/lite.json`
- Modify: `tests/CatalogQuality.Tests.ps1`

Reparto (decisiones 1 y 6):

| Perfil | Incluye | Mantiene (`keep`) | Pregunta antes de | Administrador |
|---|---|---|---|---|
| `base` | 21: extensiones, ID de publicidad, experiencias personalizadas, encuestas, 17 de anuncios de usuario | — | — | No |
| `dev` (`desarrollo`) | 6: archivos ocultos, "Finalizar tarea", modo desarrollador, rutas largas, sudo, USB con corriente | — | `dev.sudo-enable` | Sí |
| `gaming` (`juegos`) | 12: los 10 de juegos menos integridad de memoria, plan Alto rendimiento, USB con corriente | apps y tarea de Xbox (3) | `gaming.gamebar-controller-off`, `power.high-performance-plan` | Sí |
| `privacy` (`privacidad`) | 53: privacidad, búsqueda, IA, Edge, DiagTrack, tareas de telemetría, Bing y Copilot | — | 9 (ubicación, Encontrar mi dispositivo, informes de errores, DiagTrack, copia de apps, evaluador x3, Copilot) | Sí |
| `laptop` (`portatil`, `portátil`) | 7: apps en segundo plano (solo Windows 10), Delivery Optimization, Edge en segundo plano e inicio acelerado, WIA, Mapas, red en suspensión con batería | — | `performance.background-apps-off`, `power.standby-network-off-battery` | Sí |
| `legacy` (`equipo-antiguo`, `antiguo`) | 30: efectos visuales, Widgets, Explorador, fondo, tareas que pesan en disco, 7 apps poco usadas | — | `performance.background-apps-off` (solo Windows 10) | Sí |
| `work` (`trabajo`) | 10: solo ajustes de usuario sin directivas | Teams, Outlook nuevo, OneDrive, Microsoft 365, Power Automate | — | No |
| `lite` (`liviano`) | 102: lo que LTSC no trae y recortes de servicios y tareas (todas las apps, servicios, tareas y Edge del catálogo, más interfaz, IA y búsqueda local) | — | 26 (servicios de usuario, evaluador y copia de apps, Seguridad familiar, apps) | Sí |

Ningún perfil incluye un ajuste `high` (`privacy.diagnostic-data-off`, `ai.recall-snapshots-off`, `ai.recall-unavailable`, `gaming.memory-integrity-off`). `lite` incluye las apps y la tarea de Xbox y Teams/Outlook/OneDrive: `gaming` y `work` los conservan cuando se combinan (`keep` gana). Nada toca WSL, Hyper-V, contenedores ni `SharedAccess` (lo comprueba "Blacklist guard").

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/CatalogQuality.Tests.ps1`:

```powershell
Describe 'The eight profiles' {
    BeforeAll {
        $script:NotApplied = { param($tweak) 'not-applied' }
        function Get-Plan([string[]]$ProfileIds, $Environment = (New-TestEnvironment), [string[]]$Include = @()) {
            @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -ProfileIds $ProfileIds -Include $Include -Environment $Environment -TestState $NotApplied)
        }
    }

    It 'ships exactly base, dev, gaming, privacy, laptop, legacy, work and lite with their aliases' {
        @($Profiles | ForEach-Object { $_.id } | Sort-Object) -join ',' | Should -Be 'base,dev,gaming,laptop,legacy,lite,privacy,work'
        $expected = @{ dev = 'desarrollo'; gaming = 'juegos'; privacy = 'privacidad'; laptop = 'portatil,port' + [char]0x00E1 + 'til'
            legacy = 'equipo-antiguo,antiguo'; work = 'trabajo'; lite = 'liviano'; base = '' }
        foreach ($profileData in $Profiles) { @($profileData.aliases) -join ',' | Should -Be $expected[$profileData.id] -Because $profileData.id }
    }

    It 'resolves every alias to its profile' {
        foreach ($profileData in $Profiles) {
            foreach ($alias in @($profileData.aliases)) { Resolve-TuneupProfileId -Profiles $Profiles -Name $alias | Should -Be $profileData.id }
        }
    }

    It 'plans every profile on <Name> without errors, listing every tweak it includes' -TestCases @(
        @{ Name = 'Home with a battery'; Edition = 'Home'; Battery = $true; Managed = $false; Family = '11'; Build = 26100 }
        @{ Name = 'Pro without a battery'; Edition = 'Pro'; Battery = $false; Managed = $false; Family = '11'; Build = 26100 }
        @{ Name = 'Enterprise managed by an organization'; Edition = 'Enterprise'; Battery = $true; Managed = $true; Family = '11'; Build = 26100 }
        @{ Name = 'Windows 10 Education'; Edition = 'Education'; Battery = $false; Managed = $false; Family = '10'; Build = 19045 }
    ) {
        param($Edition, $Battery, $Managed, $Family, $Build)
        $environment = New-TestEnvironment -Edition $Edition -HasBattery $Battery -IsManaged $Managed -Family $Family -Build $Build
        $known = @('excluded', 'kept-by-profile', 'incompatible', 'not-applicable-hardware', 'managed-device', 'high-risk-not-requested', 'needs-confirmation')
        foreach ($profileData in $Profiles) {
            $plan = Get-Plan -ProfileIds $profileData.id -Environment $environment
            foreach ($tweakId in @($profileData.include)) { @($plan | ForEach-Object { $_.Id }) | Should -Contain $tweakId -Because "$($profileData.id) on $Edition" }
            foreach ($item in $plan | Where-Object { $_.Action -eq 'skip' }) {
                $known | Should -Contain $item.Reason -Because "$($profileData.id): $($item.Id)"
                Get-TuneupText -Key "reason.$($item.Reason)" | Should -Not -Be "reason.$($item.Reason)"
            }
        }
    }

    It 'asks before every tweak marked ask, unless it is requested by name' {
        $plan = Get-Plan -ProfileIds 'lite', 'privacy', 'gaming', 'dev', 'laptop'
        foreach ($item in $plan | Where-Object { $_.Tweak.ask -and $_.Reason -ne 'incompatible' -and $_.Reason -ne 'not-applicable-hardware' -and $_.Reason -ne 'kept-by-profile' }) {
            $item.Reason | Should -Be 'needs-confirmation' -Because $item.Id
        }
        (Get-Plan -ProfileIds 'lite' -Include 'apps.onedrive' | Where-Object { $_.Id -eq 'apps.onedrive' }).Action | Should -Be 'apply'
    }

    It 'keeps the Xbox apps and task when gaming is combined with lite' {
        $plan = Get-Plan -ProfileIds 'gaming', 'lite'
        foreach ($tweakId in 'apps.xbox-gaming-app', 'apps.xbox-game-bar', 'tasks.xbox-game-save') {
            ($plan | Where-Object { $_.Id -eq $tweakId }).Reason | Should -Be 'kept-by-profile' -Because $tweakId
        }
    }

    It 'keeps Teams, Outlook, OneDrive and Microsoft 365 when work is combined with lite' {
        $plan = Get-Plan -ProfileIds 'work', 'lite'
        foreach ($tweakId in 'apps.msteams', 'apps.outlook-new', 'apps.onedrive', 'apps.office-hub', 'apps.power-automate') {
            ($plan | Where-Object { $_.Id -eq $tweakId }).Reason | Should -Be 'kept-by-profile' -Because $tweakId
        }
    }

    It 'gives work only user settings that are not policies' {
        foreach ($tweakId in @((Get-ProfileById 'work').include)) {
            Test-TuneupUserScopedTweak -Tweak $ById[$tweakId] | Should -BeTrue -Because $tweakId
            Test-TuneupPolicyTweak -Tweak $ById[$tweakId] | Should -BeFalse -Because $tweakId
        }
    }

    It 'removes in lite what LTSC does not ship' {
        $lite = @((Get-ProfileById 'lite').include)
        foreach ($tweakId in 'apps.copilot', 'apps.msteams', 'apps.xbox-gaming-app', 'apps.phone-link', 'apps.onedrive', 'apps.widgets-web-experience', 'ui.widgets-off', 'ads.bing-search-off') {
            $lite | Should -Contain $tweakId
        }
    }

    It 'leaves the plan of a machine with a battery free of the desktop power plan' {
        $plan = Get-Plan -ProfileIds 'gaming' -Environment (New-TestEnvironment -HasBattery $true)
        ($plan | Where-Object { $_.Id -eq 'power.high-performance-plan' }).Reason | Should -Be 'not-applicable-hardware'
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogQuality.Tests.ps1`
Expected: FAIL en `ships exactly base, dev, gaming, privacy, laptop, legacy, work and lite with their aliases` y en las pruebas que usan `gaming`, `work` y `lite` (`Perfil desconocido`).

- [ ] **Step 3: Escribir los perfiles**

`profiles/base.json` completo:

```json
{
  "id": "base",
  "aliases": [],
  "title": { "es": "Base", "en": "Base" },
  "description": {
    "es": "Lo seguro para cualquier equipo, sin administrador: sin anuncios ni sugerencias, ID de publicidad apagado y extensiones de archivo visibles. Siempre se aplica.",
    "en": "Safe for any machine, without administrator rights: no ads or suggestions, advertising ID off and file extensions shown. Always applied."
  },
  "include": [
    "ui.show-file-extensions",
    "privacy.advertising-id",
    "privacy.tailored-experiences",
    "privacy.feedback-never",
    "ads.start-suggestions",
    "ads.start-system-pane",
    "ads.start-recommendations",
    "ads.start-account-notifications",
    "ads.tips-and-tricks",
    "ads.welcome-experience",
    "ads.settings-suggestions-1",
    "ads.settings-suggestions-2",
    "ads.settings-suggestions-3",
    "ads.finish-setup-prompts",
    "ads.sync-provider-notifications",
    "ads.silent-installed-apps",
    "ads.suggested-notifications",
    "ads.phone-link-suggestions",
    "ads.lockscreen-tips",
    "ads.lockscreen-overlay",
    "ads.search-highlights-off"
  ],
  "keep": []
}
```

`profiles/dev.json`:

```json
{
  "id": "dev",
  "aliases": ["desarrollo"],
  "title": { "es": "Desarrollo", "en": "Development" },
  "description": {
    "es": "Modo desarrollador, rutas largas, archivos ocultos visibles y \"Finalizar tarea\" en la barra. No toca WSL, Hyper-V ni contenedores.",
    "en": "Developer Mode, long paths, hidden files shown and \"End task\" in the taskbar. Leaves WSL, Hyper-V and containers alone."
  },
  "include": [
    "ui.show-hidden-files",
    "ui.taskbar-end-task",
    "dev.developer-mode",
    "dev.long-paths",
    "dev.sudo-enable",
    "power.usb-selective-suspend-ac-off"
  ],
  "keep": []
}
```

`profiles/gaming.json`:

```json
{
  "id": "gaming",
  "aliases": ["juegos"],
  "title": { "es": "Juegos", "en": "Gaming" },
  "description": {
    "es": "Modo Juego, sin grabación en segundo plano, sin aceleración del mouse y GPU con menos latencia. Conserva las apps y servicios de Xbox.",
    "en": "Game Mode, no background recording, no mouse acceleration and lower GPU latency. Keeps the Xbox apps and services."
  },
  "include": [
    "gaming.game-mode-on",
    "gaming.game-dvr-off",
    "gaming.app-capture-off",
    "gaming.background-recording-off",
    "gaming.gamebar-controller-off",
    "gaming.mouse-accel-off",
    "gaming.mouse-accel-threshold-1",
    "gaming.mouse-accel-threshold-2",
    "gaming.windowed-optimizations",
    "gaming.hags-on",
    "power.high-performance-plan",
    "power.usb-selective-suspend-ac-off"
  ],
  "keep": [
    "apps.xbox-gaming-app",
    "apps.xbox-game-bar",
    "tasks.xbox-game-save"
  ]
}
```

`profiles/privacy.json` completo:

```json
{
  "id": "privacy",
  "aliases": ["privacidad"],
  "title": { "es": "Privacidad", "en": "Privacy" },
  "description": {
    "es": "Menos datos enviados a Microsoft y a los anunciantes: telemetría al mínimo, historial de actividad, Bing en la búsqueda, Copilot y Recall.",
    "en": "Less data sent to Microsoft and advertisers: minimum telemetry, activity history, Bing in search, Copilot and Recall."
  },
  "include": [
    "privacy.diagnostic-data-required",
    "privacy.ceip-off",
    "privacy.app-launch-tracking-off",
    "privacy.online-speech-off",
    "privacy.inking-typing-improve-off",
    "privacy.input-personalization-text-off",
    "privacy.input-personalization-ink-off",
    "privacy.language-list-off",
    "privacy.activity-publish-off",
    "privacy.activity-upload-off",
    "privacy.clipboard-cloud-off",
    "privacy.location-off",
    "privacy.find-my-device-off",
    "privacy.error-reporting-off",
    "ads.start-recent-files-off",
    "ads.bing-search-off",
    "ads.search-box-suggestions-off",
    "ads.search-history-off",
    "ads.consumer-features",
    "ads.settings-home-365",
    "ai.copilot-button-off",
    "ai.copilot-policy-off",
    "ai.click-to-do-off",
    "ai.notepad-ai-off",
    "ai.paint-cocreator-off",
    "ai.paint-image-creator-off",
    "ai.paint-generative-fill-off",
    "edge.personalization-reporting-off",
    "edge.diagnostic-data-required",
    "edge.feedback-off",
    "edge.new-tab-feed-off",
    "edge.shopping-off",
    "edge.recommendations-off",
    "edge.spotlight-off",
    "edge.default-browser-campaign-off",
    "edge.acrobat-button-off",
    "edge.first-run-off",
    "edge.alternate-error-pages-off",
    "edge.sidebar-off",
    "edge.new-tab-bing-chat-off",
    "edge.history-ai-search-off",
    "edge.local-ai-model-off",
    "services.diagtrack",
    "tasks.ceip-consolidator",
    "tasks.ceip-usbceip",
    "tasks.autochk-proxy",
    "tasks.disk-diagnostic-data-collector",
    "tasks.mare-backup",
    "tasks.appraiser",
    "tasks.appraiser-exp",
    "tasks.program-data-updater",
    "apps.bing-search",
    "apps.copilot"
  ],
  "keep": []
}
```

`profiles/laptop.json`:

```json
{
  "id": "laptop",
  "aliases": ["portatil", "portátil"],
  "title": { "es": "Portátil", "en": "Laptop" },
  "description": {
    "es": "Más batería: apps de la Store sin correr en segundo plano, Edge sin procesos precargados y sin red en suspensión con batería.",
    "en": "More battery: Store apps do not run in the background, Edge keeps no preloaded processes and no network in standby on battery."
  },
  "include": [
    "performance.background-apps-off",
    "performance.delivery-optimization-http-only",
    "edge.startup-boost-off",
    "edge.background-mode-off",
    "services.wia",
    "services.maps-broker",
    "power.standby-network-off-battery"
  ],
  "keep": []
}
```

`profiles/legacy.json`:

```json
{
  "id": "legacy",
  "aliases": ["equipo-antiguo", "antiguo"],
  "title": { "es": "Equipo antiguo", "en": "Older PC" },
  "description": {
    "es": "Para equipos lentos o con disco mecánico: sin transparencia ni animaciones, menos tareas de fondo y menos apps preinstaladas.",
    "en": "For slow machines or hard disks: no transparency or animations, fewer background tasks and fewer preinstalled apps."
  },
  "include": [
    "ui.transparency-off",
    "ui.window-animations-off",
    "ui.listview-shadow-off",
    "ui.listview-alpha-select-off",
    "ui.aero-peek-off",
    "ui.widgets-off",
    "ui.news-interests-win10",
    "performance.explorer-folder-type-general",
    "performance.background-apps-off",
    "performance.delivery-optimization-http-only",
    "edge.startup-boost-off",
    "edge.background-mode-off",
    "services.wia",
    "services.maps-broker",
    "tasks.maps-toast",
    "tasks.maps-update",
    "tasks.power-efficiency-analyze",
    "tasks.disk-footprint-diagnostics",
    "tasks.work-folders-logon",
    "tasks.work-folders-maintenance",
    "tasks.winsat",
    "tasks.recommended-troubleshooting",
    "tasks.speech-model-download",
    "apps.clipchamp",
    "apps.bing-news",
    "apps.bing-weather",
    "apps.bing-finance",
    "apps.messaging",
    "apps.mixed-reality-portal",
    "apps.movies-tv"
  ],
  "keep": []
}
```

`profiles/work.json`:

```json
{
  "id": "work",
  "aliases": ["trabajo"],
  "title": { "es": "Trabajo", "en": "Work" },
  "description": {
    "es": "Solo ajustes de tu usuario, sin políticas, para equipos de una organización. Conserva Teams, Outlook, OneDrive y Microsoft 365.",
    "en": "Only settings of your user, no policies, for machines of an organization. Keeps Teams, Outlook, OneDrive and Microsoft 365."
  },
  "include": [
    "privacy.app-launch-tracking-off",
    "privacy.online-speech-off",
    "privacy.inking-typing-improve-off",
    "privacy.input-personalization-text-off",
    "privacy.input-personalization-ink-off",
    "privacy.language-list-off",
    "ads.start-recent-files-off",
    "ads.bing-search-off",
    "ads.search-history-off",
    "ai.copilot-button-off"
  ],
  "keep": [
    "apps.msteams",
    "apps.outlook-new",
    "apps.onedrive",
    "apps.office-hub",
    "apps.power-automate"
  ]
}
```

`profiles/lite.json`:

```json
{
  "id": "lite",
  "aliases": ["liviano"],
  "title": { "es": "Liviano", "en": "Lite" },
  "description": {
    "es": "Quita lo que Windows LTSC no trae (apps, Widgets, Copilot, Teams, Xbox, Vínculo móvil; OneDrive con pregunta) y recorta servicios y tareas. Sin tocar Defender, Windows Update ni WinRE.",
    "en": "Removes what Windows LTSC does not ship (apps, Widgets, Copilot, Teams, Xbox, Phone Link; OneDrive asks first) and trims services and tasks. Defender, Windows Update and WinRE are left alone."
  },
  "include": [
    "ads.backup-reminders",
    "ads.start-phone-link",
    "ads.start-hide-recommended-policy",
    "ads.start-recent-apps-off",
    "ads.start-most-used-off",
    "ads.consumer-features",
    "ads.settings-home-365",
    "ads.bing-search-off",
    "ads.search-box-suggestions-off",
    "ui.task-view-button-off",
    "ui.widgets-off",
    "ui.news-interests-win10",
    "ui.meet-now-win10",
    "ai.copilot-button-off",
    "ai.copilot-policy-off",
    "ai.click-to-do-off",
    "ai.notepad-ai-off",
    "ai.paint-cocreator-off",
    "ai.paint-image-creator-off",
    "ai.paint-generative-fill-off",
    "ai.fabric-service-manual",
    "privacy.diagnostic-data-required",
    "privacy.ceip-off",
    "performance.delivery-optimization-http-only",
    "edge.personalization-reporting-off",
    "edge.diagnostic-data-required",
    "edge.feedback-off",
    "edge.new-tab-feed-off",
    "edge.shopping-off",
    "edge.recommendations-off",
    "edge.spotlight-off",
    "edge.default-browser-campaign-off",
    "edge.acrobat-button-off",
    "edge.first-run-off",
    "edge.alternate-error-pages-off",
    "edge.sidebar-off",
    "edge.new-tab-bing-chat-off",
    "edge.history-ai-search-off",
    "edge.local-ai-model-off",
    "edge.startup-boost-off",
    "edge.background-mode-off",
    "services.retail-demo",
    "services.diagtrack",
    "services.wia",
    "services.maps-broker",
    "services.geolocation",
    "services.connected-devices",
    "services.connected-devices-user",
    "services.contact-data",
    "services.user-data-storage",
    "services.user-data-access",
    "tasks.ceip-consolidator",
    "tasks.ceip-usbceip",
    "tasks.autochk-proxy",
    "tasks.disk-diagnostic-data-collector",
    "tasks.appraiser",
    "tasks.appraiser-exp",
    "tasks.program-data-updater",
    "tasks.mare-backup",
    "tasks.startup-app-task",
    "tasks.maps-toast",
    "tasks.maps-update",
    "tasks.xbox-game-save",
    "tasks.power-efficiency-analyze",
    "tasks.disk-footprint-diagnostics",
    "tasks.work-folders-logon",
    "tasks.work-folders-maintenance",
    "tasks.winsat",
    "tasks.recommended-troubleshooting",
    "tasks.family-safety-monitor",
    "tasks.family-safety-refresh",
    "tasks.speech-model-download",
    "apps.clipchamp",
    "apps.bing-news",
    "apps.bing-weather",
    "apps.bing-finance",
    "apps.office-hub",
    "apps.power-automate",
    "apps.dev-home",
    "apps.messaging",
    "apps.mixed-reality-portal",
    "apps.movies-tv",
    "apps.bing-search",
    "apps.copilot",
    "apps.get-help",
    "apps.feedback-hub",
    "apps.todos",
    "apps.alarms-clock",
    "apps.sound-recorder",
    "apps.media-player",
    "apps.quick-assist",
    "apps.phone-link",
    "apps.xbox-gaming-app",
    "apps.xbox-game-bar",
    "apps.widgets-web-experience",
    "apps.widgets-platform-runtime",
    "apps.start-experiences",
    "apps.outlook-new",
    "apps.family-safety",
    "apps.mail-calendar",
    "apps.msteams",
    "apps.onedrive"
  ],
  "keep": []
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogQuality.Tests.ps1`
Expected: PASS (`Tests Passed: 39, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluida `Shipped catalog and profiles` de `tests/Catalog.Tests.ps1`.

- [ ] **Step 5: Plan real de cada perfil, sin cambiar nada**

Con PowerShell sin elevar, en la raíz del repo:

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tuneup.ps1 -Profile base,dev,gaming,privacy,laptop,legacy,work,lite -WhatIf -Json -StateRoot $env:TEMP\tuneup-plan3-check`
Expected: un documento JSON con `"command": "plan"` y ningún `reason` igual a `state-unreadable`. En el equipo de verificación: 162 elementos, 55 por aplicar (13 con `unverified-needs-admin`, las apps), 65 ya aplicados, 22 que piden confirmación, 8 conservados por un perfil, 7 incompatibles (directivas de Enterprise/Education y de Windows 10), 4 que no existen en ese build y 1 que no corresponde al hardware (`power.high-performance-plan`: el equipo tiene batería).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tuneup.ps1 -Profile portátil -WhatIf -StateRoot $env:TEMP\tuneup-plan3-check`
Expected: el plan de `laptop` (el alias con tilde funciona).

`-WhatIf` no escribe en `-StateRoot`; la carpeta solo evita tocar la de máquina.

- [ ] **Step 6: Commit**

```bash
git add profiles/base.json profiles/dev.json profiles/gaming.json profiles/privacy.json profiles/laptop.json profiles/legacy.json profiles/work.json profiles/lite.json tests/CatalogQuality.Tests.ps1
git commit -m "feat: los ocho perfiles por objetivo"
```

---

### Task 23: Lista negra (`docs/{es,en}/blacklist.md`)

**Files:**
- Create: `docs/es/blacklist.md`, `docs/en/blacklist.md`
- Create: `tests/Docs.Tests.ps1`

La sección 4 de la especificación más las exclusiones de la investigación, cada una con su motivo, en los dos idiomas. "Blacklist guard" (Task 7) ya impide que el catálogo toque los servicios, valores, tareas y apps que esta página nombra.

- [ ] **Step 1: Prueba que falla**

Crear `tests/Docs.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    $script:Profiles = @(Import-TuneupProfileSet -Path (Join-Path $Repo 'profiles'))
    function Get-DocText([string]$Lang, [string]$Name) {
        [System.IO.File]::ReadAllText((Join-Path $Repo "docs\$Lang\$Name"), (New-Object System.Text.UTF8Encoding -ArgumentList $false))
    }
}

Describe 'Blacklist' {
    It 'explains the cases of the design and of the research in both languages' {
        $terms = @('Defender', 'SmartScreen', 'Windows Update', 'WinRE', '/ResetBase', 'Spectre', 'PagingFiles', 'hosts',
            'SvcHostSplitThresholdInKB', 'NetworkThrottlingIndex', 'HPET', 'SharedAccess', 'OneDrive', 'CBS', 'WerSvc', 'Spooler')
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'blacklist.md'
            foreach ($term in $terms) { $text.Contains($term) | Should -BeTrue -Because "$lang $term" }
        }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: FAIL, no se encuentra `docs\es\blacklist.md`.

- [ ] **Step 3: Escribir `docs/es/blacklist.md`**

````markdown
# Lista negra

English version: [../en/blacklist.md](../en/blacklist.md).

Estos cambios **no se aplican nunca**: no están en ningún perfil ni se pueden pedir con `-Include`, y `-Force` no los habilita. La skill de Claude tampoco los propone aunque se los pidan; explica por qué no. Las pruebas del catálogo (`tests/CatalogQuality.Tests.ps1`, bloque "Blacklist guard") fallan si un ajuste del catálogo toca alguno de los servicios, valores de registro, tareas o apps de esta lista.

Lo que se evaluó y quedó fuera por otros motivos (apps que no se pueden reinstalar, ajustes sin verificar, límites del motor) está al final de [catalog.md](catalog.md#no-incluido).

## Seguridad

| Cambio | Por qué no |
|---|---|
| Apagar Microsoft Defender, su protección en tiempo real o la protección en la nube (`DisableAntiSpyware`, `DisableRealtimeMonitoring`, `Set-MpPreference -SubmitSamplesConsent 2`) | Deja el equipo expuesto y la ganancia de rendimiento es mínima. Para carpetas de código, Microsoft recomienda un Dev Drive, no exclusiones. |
| Apagar SmartScreen (`EnableSmartScreen`, `SmartScreenEnabled`) | Es la defensa contra descargas y sitios maliciosos conocidos. |
| Apagar el Control de cuentas de usuario (`EnableLUA`, `ConsentPromptBehaviorAdmin`) | Todo programa correría con permisos de administrador sin preguntar. |
| Apagar el firewall (`EnableFirewall`, servicio `mpssvc`, `BFE`) | Deja abiertos los puertos de todos los servicios a la red. |
| Apagar las mitigaciones de CPU para Spectre y Meltdown (`FeatureSettingsOverride`) | Riesgo de seguridad real a cambio de poco rendimiento. |
| Apagar la integridad de memoria (VBS/HVCI) **por defecto** | Solo existe como ajuste de riesgo alto, `gaming.memory-integrity-off`, que ningún perfil incluye y que se aplica únicamente si se pide por nombre. Apagar VBS completo no existe. |
| Apagar Seguridad de Windows, `webthreatdefsvc` o `webthreatdefusersvc` | Son la interfaz de Defender y la protección contra robo de credenciales. |
| Cambiar las directivas de ejecución de PowerShell | Es un ajuste de seguridad del equipo. |

## Actualizaciones y recuperación

| Cambio | Por qué no |
|---|---|
| Desactivar Windows Update por completo (servicios `wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `BITS`; `NoAutoUpdate`, `DisableWindowsUpdateAccess`; tareas de `WindowsUpdate`, `UpdateOrchestrator` y `WaaSMedic`) | Sin parches de seguridad. Como mucho se evita que reinicie solo o se retrasan las actualizaciones de funciones. |
| Bloquear dominios de Microsoft en `hosts` o en el firewall | Rompe Windows Update, la Store y la activación. |
| Desactivar o borrar WinRE (`C:\Recovery`, tareas de `RecoveryEnvironment`) | Sin recuperación local ante un arranque roto. |
| Desactivar Restaurar sistema o sus tareas (`SystemRestore`, servicios `VSS` y `swprv`) | Además de la protección del usuario, el propio motor crea un punto de restauración antes de los cambios de sistema. |
| `DISM /ResetBase` por defecto | Impide desinstalar actualizaciones problemáticas. |
| Borrar los registros de CBS y DISM | Se necesitan para diagnosticar reparaciones (`-Health`). |
| Desactivar las tareas `Chkdsk`, `Defrag`, `Servicing\StartComponentCleanup` o `Registry\RegIdleBackup`, o la tarea `DiskDiagnosticResolver` | Salud del disco y del sistema: TRIM en SSD, avisos de fallos SMART, limpieza del almacén de componentes. |
| Quitar la Microsoft Store o App Installer (winget) | Deshacer cualquier app depende de ellos. Quitar la Store sería, como mucho, una opción aparte con advertencia; hoy no existe. |

## Memoria, disco y datos

| Cambio | Por qué no |
|---|---|
| Quitar el archivo de paginación (`PagingFiles`) | Cuelgues por falta de memoria y sin volcados de error. |
| Limpiadores de registro | Sin beneficio medible; riesgo de romper programas. |
| Borrar carpetas del usuario (por ejemplo `%UserProfile%\OneDrive`) | Pérdida de datos. Desinstalar OneDrive (`apps.onedrive`) nunca borra archivos y se niega si hay carpetas movidas a OneDrive o archivos solo en la nube. |
| Encender el Sensor de almacenamiento | Borra archivos de la papelera y de Descargas sin preguntar. |
| Quitar apps que guardan datos del usuario dentro de la app (Notas rápidas, Journal, Whiteboard, OneNote) | Quitar la app borra esas notas. |

## "Optimizaciones" que son placebo

| Cambio | Por qué no |
|---|---|
| Agrupar procesos de svchost (`SvcHostSplitThresholdInKB`) | Solo baja el número visible de procesos y quita el aislamiento entre servicios. |
| Ajustes de red (`NetworkThrottlingIndex`, `SystemResponsiveness`, autotuning de TCP, `TcpAckFrequency`, `TCPNoDelay`, algoritmo de Nagle) | Sin efecto demostrable en equipos modernos; la mayoría de los juegos en tiempo real usan UDP. |
| Forzar HPET (`bcdedit /set useplatformclock`) | Windows no lo usa salvo que se fuerce, y forzarlo suele empeorar la latencia. Además toca la configuración de arranque. |
| Resolución del temporizador, `Win32PrioritySeparation`, prioridades de MMCSS | Valores ya óptimos o ignorados; desde Windows 10 2004 la resolución es por proceso. |
| Estado mínimo del procesador al 100 %, plan "Máximo rendimiento" (`powercfg -duplicatescheme e9a42b02...`) | En CPU modernas no mejora los FPS, sube temperatura y consumo; el plan nuevo no se puede deshacer limpio. |
| Desactivar las optimizaciones de pantalla completa | Suele perder latencia y el overlay; solo ayuda en casos concretos. |
| `NtfsDisable8dot3NameCreation`, `NtfsDisableLastAccessUpdate` | Mejora marginal y puede romper instaladores antiguos. |

## Servicios que no se tocan

| Servicio | Por qué no |
|---|---|
| `SharedAccess` (Conexión compartida a Internet) | Sostiene la NAT de WSL2, el conmutador Default Switch de Hyper-V, Docker Desktop y el punto de acceso móvil. |
| `vmcompute`, `vmms`, `hns`, `HvHost`, `LxssManager`, `WslService` | Virtualización, WSL, Hyper-V y contenedores (el perfil Desarrollo los conserva). |
| `LanmanServer`, `LanmanWorkstation` | Microsoft: "no deshabilitar"; compartir archivos, IPC$ y administración remota. |
| `WerSvc`, `DPS`, `WdiServiceHost`, `WdiSystemHost` | Manejo de bloqueos, solucionadores y diagnósticos. Apagar el envío de informes (`privacy.error-reporting-off`) no toca el servicio. |
| `RmSvc` | Radio y modo avión: sin él no se controlan Wi-Fi ni Bluetooth desde Configuración. |
| `WpnService` | Notificaciones y mosaicos. |
| `SysMain`, `WSearch` | La especificación conserva SysMain (ayuda en discos mecánicos); sin WSearch la búsqueda de Inicio y del Explorador deja de encontrar archivos. |
| `XblGameSave`, `XblAuthManager`, `XboxNetApiSvc` | Ya vienen en manual y Windows los inicia cuando hacen falta; deshabilitarlos rompe el inicio de sesión de Xbox y de los juegos de Game Pass. |
| `Spooler` | Sin él no se imprime; solo tendría sentido con detección de impresoras. |
| `EventLog`, `Schedule`, `Winmgmt`, `RpcSs`, `CryptSvc`, `sppsvc`, `AppIDSvc`, `TrustedInstaller` | Infraestructura de Windows: registros, tareas, WMI, RPC, certificados, activación, AppLocker y servicing. |

## Edge

| Cambio | Por qué no |
|---|---|
| Quitar Microsoft Edge o WebView2 | Rompe Widgets, la ayuda y muchas apps que muestran contenido web, y deja el equipo sin navegador soportado. |
````

- [ ] **Step 4: Escribir `docs/en/blacklist.md`**

````markdown
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
````

Los enlaces a `catalog.md` se resuelven en la Task 24; la prueba de enlaces llega en la Task 26.

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: PASS (`Tests Passed: 1, Failed: 0`).

- [ ] **Step 6: Commit**

```bash
git add docs/es/blacklist.md docs/en/blacklist.md tests/Docs.Tests.ps1
git commit -m "docs: lista negra en español e inglés"
```

---

### Task 24: Catálogo documentado (`build/catalog-doc.ps1`) y lo que quedó fuera

**Files:**
- Create: `catalog/notes/excluded.json`
- Create: `build/catalog-doc.labels.json`, `build/catalog-doc.ps1`
- Create: `docs/es/catalog.md`, `docs/en/catalog.md` (generados)
- Create: `tests/CatalogDoc.Tests.ps1`

`catalog/notes/excluded.json` guarda lo que se evaluó y quedó fuera, con el motivo en los dos idiomas (apps sin deshacer, apps sin producto en la Store, apps que no se quitan nunca, los servicios de Xbox que se sacaron del catálogo, las directivas que Windows Home ignora, las acciones descartadas `power-mode-overlay` y `dev-defender-performance-mode`, ajustes sin verificar y los que esperan una capacidad del motor). Está en una subcarpeta para que `Import-TuneupCatalog` (que solo lee `catalog\*.json`) no lo tome por catálogo. `build/catalog-doc.ps1` arma una página por idioma: resumen por categoría, perfiles, ajustes que preguntan, de riesgo alto y que no rigen en Home, cada ajuste con su tipo, ámbito, riesgo, perfiles, ediciones, `requires`, qué pide después de aplicar y sus fuentes, y al final "No incluido". El script es ASCII (regla del repo): todos los textos en español están en `build/catalog-doc.labels.json`. La salida es UTF-8 sin BOM con CRLF y siempre la misma para la misma entrada, así una prueba la regenera en una carpeta temporal y la compara con la del repo.

- [ ] **Step 1: Pruebas que fallan**

Crear `tests/CatalogDoc.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Excluded = Get-Content -LiteralPath (Join-Path $Repo 'catalog\notes\excluded.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    function Get-DocText([string]$Path) {
        [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding -ArgumentList $false)) -replace "`r`n", "`n"
    }
}

Describe 'Generated catalog documentation' {
    It 'is up to date with the catalog, the profiles and the notes (<Lang>)' -TestCases @(
        @{ Lang = 'es' }
        @{ Lang = 'en' }
    ) {
        param($Lang)
        $out = Join-Path $TestDrive 'docs'
        & (Join-Path $Repo 'build\catalog-doc.ps1') -OutDir $out | Out-Null
        $committed = Join-Path $Repo "docs\$Lang\catalog.md"
        Test-Path -LiteralPath $committed | Should -BeTrue
        (Get-DocText (Join-Path $out "$Lang\catalog.md")) -ceq (Get-DocText $committed) |
            Should -BeTrue -Because 'docs/*/catalog.md must be regenerated with build/catalog-doc.ps1 after changing the catalog'
    }

    It 'lists every tweak of the catalog' {
        $text = Get-DocText (Join-Path $Repo 'docs\en\catalog.md')
        foreach ($tweak in $Catalog) { $text.Contains("### ``$($tweak.id)``") | Should -BeTrue -Because $tweak.id }
    }

    It 'writes the pages in UTF-8 without a byte order mark' {
        foreach ($lang in 'es', 'en') {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Repo "docs\$lang\catalog.md"))
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because $lang
        }
    }
}

Describe 'Notes on what is not included' {
    It 'explains every group and item in both languages' {
        foreach ($group in $Excluded.groups) {
            foreach ($lang in 'es', 'en') {
                [string]$group.title.$lang | Should -Not -BeNullOrEmpty -Because "$($group.id) title.$lang"
                [string]$group.intro.$lang | Should -Not -BeNullOrEmpty -Because "$($group.id) intro.$lang"
                foreach ($item in $group.items) {
                    $name = $(if ($item.name -is [string]) { $item.name } else { $item.name.$lang })
                    [string]$name | Should -Not -BeNullOrEmpty -Because "$($group.id) name.$lang"
                    [string]$item.why.$lang | Should -Not -BeNullOrEmpty -Because "$name why.$lang"
                }
            }
        }
    }

    It 'explains the Xbox services, the Home policies, the dropped actions and the apps without undo that were left out' {
        $ids = @($Excluded.groups | ForEach-Object { $_.id })
        foreach ($groupId in 'apps-no-undo', 'services-xbox', 'home-policies', 'actions-dropped') { $ids | Should -Contain $groupId }
        $services = @($Excluded.groups | Where-Object { $_.id -eq 'services-xbox' } | ForEach-Object { $_.items } | ForEach-Object { $_.name })
        ($services | Sort-Object) -join ',' | Should -Be 'XblAuthManager,XblGameSave,XboxNetApiSvc'
        $catalogServices = @($Catalog | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.set.name })
        foreach ($name in $services) { $catalogServices | Should -Not -Contain $name }
        $dropped = @($Excluded.groups | Where-Object { $_.id -eq 'actions-dropped' } | ForEach-Object { $_.items } | ForEach-Object { $_.name.en })
        ($dropped -join '|').Contains('power-mode-overlay') | Should -BeTrue
        ($dropped -join '|').Contains('dev-defender-performance-mode') | Should -BeTrue
    }

    It 'never lists an app that the catalog removes' {
        $removed = @($Catalog | Where-Object { $_.type -eq 'appx' } | ForEach-Object { [string]$_.set.name })
        foreach ($item in $Excluded.groups.items | Where-Object { $_.appx }) {
            $removed | Should -Not -Contain $item.appx -Because $item.name
        }
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogDoc.Tests.ps1`
Expected: FAIL, no se encuentra `catalog\notes\excluded.json`.

- [ ] **Step 3: Escribir `catalog/notes/excluded.json`**

```json
{
  "groups": [
    {
      "id": "apps-no-undo",
      "title": { "es": "Apps que no se pueden reinstalar al deshacer", "en": "Apps that cannot be reinstalled on undo" },
      "intro": {
        "es": "Deshacer reinstala una app con winget desde la Microsoft Store. Para estas apps winget no encuentra el producto (código 0x8A150014, comprobado el 2026-10-01), así que quitarlas no se podría deshacer: quedan fuera.",
        "en": "Undo reinstalls an app with winget from the Microsoft Store. For these apps winget does not find the product (code 0x8A150014, checked on 2026-10-01), so removing them could not be undone: they are left out."
      },
      "items": [
        { "name": "Microsoft Solitaire Collection", "appx": "Microsoft.MicrosoftSolitaireCollection", "why": { "es": "winget no resuelve 9WZDNCRFHWD2.", "en": "winget does not resolve 9WZDNCRFHWD2." } },
        { "name": "Microsoft Tips", "appx": "Microsoft.Getstarted", "why": { "es": "winget no resuelve 9WZDNCRDTBJJ.", "en": "winget does not resolve 9WZDNCRDTBJJ." } },
        { "name": "People", "appx": "Microsoft.People", "why": { "es": "winget no resuelve 9NBLGGH10PG8.", "en": "winget does not resolve 9NBLGGH10PG8." } },
        { "name": "Windows Maps", "appx": "Microsoft.WindowsMaps", "why": { "es": "winget no resuelve 9WZDNCRDTBVB.", "en": "winget does not resolve 9WZDNCRDTBVB." } },
        { "name": "3D Viewer", "appx": "Microsoft.Microsoft3DViewer", "why": { "es": "winget no resuelve 9NBLGGH42THS.", "en": "winget does not resolve 9NBLGGH42THS." } },
        { "name": "Paint 3D", "appx": "Microsoft.MSPaint", "why": { "es": "winget no resuelve 9NBLGGH5FV99 (no es el Paint actual).", "en": "winget does not resolve 9NBLGGH5FV99 (it is not the current Paint)." } },
        { "name": "Print 3D", "appx": "Microsoft.Print3D", "why": { "es": "winget no resuelve 9PBPCH085S3S.", "en": "winget does not resolve 9PBPCH085S3S." } },
        { "name": "3D Builder", "appx": "Microsoft.3DBuilder", "why": { "es": "winget no resuelve 9WZDNCRFJ3T6.", "en": "winget does not resolve 9WZDNCRFJ3T6." } },
        { "name": "Microsoft Wallet", "appx": "Microsoft.Wallet", "why": { "es": "winget no resuelve 9NBLGGH52CKV.", "en": "winget does not resolve 9NBLGGH52CKV." } },
        { "name": "Mobile Plans", "appx": "Microsoft.OneConnect", "why": { "es": "winget no resuelve 9NBLGGH5PNB1.", "en": "winget does not resolve 9NBLGGH5PNB1." } },
        { "name": "MSN Sports", "appx": "Microsoft.BingSports", "why": { "es": "winget no resuelve 9WZDNCRFHVH4.", "en": "winget does not resolve 9WZDNCRFHVH4." } },
        { "name": "Translator", "appx": "Microsoft.BingTranslator", "why": { "es": "winget no resuelve 9WZDNCRFJ3PG.", "en": "winget does not resolve 9WZDNCRFJ3PG." } },
        { "name": "Xbox Game Bar Plugin", "appx": "Microsoft.XboxGameOverlay", "why": { "es": "winget no resuelve 9NBLGGH537C2.", "en": "winget does not resolve 9NBLGGH537C2." } },
        { "name": "Xbox Console Companion", "appx": "Microsoft.XboxApp", "why": { "es": "winget no resuelve 9WZDNCRFJBD8.", "en": "winget does not resolve 9WZDNCRFJBD8." } },
        { "name": "Cortana", "appx": "Microsoft.549981C3F5F10", "why": { "es": "winget no resuelve 9NFFX4SZZ23L; Cortana ya no existe en Windows 11.", "en": "winget does not resolve 9NFFX4SZZ23L; Cortana no longer exists in Windows 11." } },
        { "name": "Microsoft PC Manager", "appx": "Microsoft.PCManager", "why": { "es": "winget no resuelve 9P35S3ZNMCHL.", "en": "winget does not resolve 9P35S3ZNMCHL." } },
        { "name": "Network Speed Test", "appx": "Microsoft.NetworkSpeedTest", "why": { "es": "winget no resuelve 9WZDNCRFHX52.", "en": "winget does not resolve 9WZDNCRFHX52." } },
        { "name": "Sway", "appx": "Microsoft.Office.Sway", "why": { "es": "winget no resuelve 9WZDNCRD2G0J.", "en": "winget does not resolve 9WZDNCRD2G0J." } }
      ]
    },
    {
      "id": "apps-no-store",
      "title": { "es": "Apps sin producto en la Store", "en": "Apps without a Store product" },
      "intro": {
        "es": "Llegan con Windows o con Windows Update y no tienen un id de la Store con el que reinstalarlas, o no se pudo comprobar qué paquete instala su id.",
        "en": "They come with Windows or Windows Update and have no Store id to reinstall them with, or it could not be checked which package their id installs."
      },
      "items": [
        { "name": "Microsoft 365 Companions", "appx": "Microsoft.M365Companions", "why": { "es": "Sin producto en la Store.", "en": "No Store product." } },
        { "name": "AI Hub", "appx": "Microsoft.Windows.AIHub", "why": { "es": "Sin producto en la Store.", "en": "No Store product." } },
        { "name": "Cross Device Experience Host", "appx": "MicrosoftWindows.CrossDevice", "why": { "es": "Paquete del sistema que acompaña a Vínculo móvil; sin producto en la Store.", "en": "System package that goes with Phone Link; no Store product." } },
        { "name": "Skype", "appx": "Microsoft.SkypeApp", "why": { "es": "Ya no tiene producto en la Store.", "en": "It no longer has a Store product." } },
        { "name": { "es": "Microsoft Teams (clásico personal)", "en": "Microsoft Teams (classic personal)" }, "appx": "MicrosoftTeams", "why": { "es": "Sin producto en la Store; el Teams nuevo (MSTeams) sí está en el catálogo.", "en": "No Store product; the new Teams (MSTeams) is in the catalog." } },
        { "name": "Microsoft Copilot (XP9CXNGPPJ97XX)", "why": { "es": "winget lo resuelve, pero no se pudo saber qué paquete Appx instala; la app Copilot de Windows (9NHT9RB2F4HD) sí está.", "en": "winget resolves it, but it could not be checked which Appx package it installs; the Windows Copilot app (9NHT9RB2F4HD) is included." } }
      ]
    },
    {
      "id": "apps-kept",
      "title": { "es": "Apps que no se quitan nunca", "en": "Apps that are never removed" },
      "intro": {
        "es": "Otras apps dependen de ellas, Windows no deja quitarlas o guardan datos del usuario dentro de la app.",
        "en": "Other apps depend on them, Windows does not let them be removed, or they keep the user's data inside the app."
      },
      "items": [
        { "name": "Microsoft Store", "appx": "Microsoft.WindowsStore", "why": { "es": "Deshacer cualquier app depende de ella. Quitarla sería una opción aparte con advertencia; hoy no existe.", "en": "Undoing any app depends on it. Removing it would be a separate option with a warning; it does not exist today." } },
        { "name": { "es": "Instalador de aplicación (winget)", "en": "App Installer (winget)" }, "appx": "Microsoft.DesktopAppInstaller", "why": { "es": "Es winget: sin él no hay deshacer. Windows no deja quitarlo.", "en": "It is winget: without it there is no undo. Windows does not let it be removed." } },
        { "name": { "es": "Seguridad de Windows", "en": "Windows Security" }, "appx": "Microsoft.SecHealthUI", "why": { "es": "Interfaz de Defender; Windows no deja quitarla.", "en": "The Defender interface; Windows does not let it be removed." } },
        { "name": "Xbox Identity Provider, Xbox TCUI, Xbox Speech To Text Overlay, Game Callable UI", "why": { "es": "La Store, Game Pass y los juegos los usan para iniciar sesión.", "en": "The Store, Game Pass and games use them to sign in." } },
        { "name": { "es": "Fotos, Calculadora, Bloc de notas, Paint, Recortes, Cámara, Terminal", "en": "Photos, Calculator, Notepad, Paint, Snipping Tool, Camera, Terminal" }, "why": { "es": "Herramientas básicas y predeterminadas; no son apps basura.", "en": "Basic and default tools; they are not junk." } },
        { "name": { "es": "Notas rápidas, Journal, Whiteboard, OneNote", "en": "Sticky Notes, Journal, Whiteboard, OneNote" }, "why": { "es": "Guardan notas del usuario dentro de la app: quitarlas las borra.", "en": "They keep the user's notes inside the app: removing them deletes those notes." } },
        { "name": { "es": "Microsoft Edge, WebView2, códecs y frameworks (Microsoft.NET.*, Microsoft.VCLibs.*, Microsoft.UI.Xaml.*)", "en": "Microsoft Edge, WebView2, codecs and frameworks (Microsoft.NET.*, Microsoft.VCLibs.*, Microsoft.UI.Xaml.*)" }, "why": { "es": "Otras apps dependen de ellos.", "en": "Other apps depend on them." } }
      ]
    },
    {
      "id": "services-xbox",
      "title": { "es": "Servicios de Xbox", "en": "Xbox services" },
      "intro": {
        "es": "Estaban en el catálogo y se quitaron: ya vienen en manual y Windows los inicia solos cuando un juego los necesita, así que deshabilitarlos no ahorra nada y rompe el inicio de sesión de Xbox y de los juegos de Game Pass. La app y la tarea de Xbox sí se pueden quitar (el perfil `gaming` las conserva).",
        "en": "They were in the catalog and were removed: they are already Manual and Windows starts them by itself when a game needs them, so disabling them saves nothing and breaks the Xbox and Game Pass sign-in. The Xbox app and task can be removed (the `gaming` profile keeps them)."
      },
      "items": [
        { "name": "XblGameSave", "why": { "es": "Partidas guardadas de Xbox Live; ya viene en manual.", "en": "Xbox Live game saves; it is already Manual." } },
        { "name": "XblAuthManager", "why": { "es": "Inicio de sesión de Xbox Live; deshabilitarlo impide entrar a los juegos que lo usan.", "en": "Xbox Live sign-in; disabling it stops the games that use it from signing in." } },
        { "name": "XboxNetApiSvc", "why": { "es": "Red de Xbox Live para el multijugador; ya viene en manual.", "en": "Xbox Live networking for multiplayer; it is already Manual." } }
      ]
    },
    {
      "id": "home-policies",
      "title": { "es": "Directivas que Windows Home ignora", "en": "Policies that Windows Home ignores" },
      "intro": {
        "es": "Windows Home ignora muchas directivas de grupo. Los ajustes del catálogo que son directivas declaran las ediciones donde Microsoft las documenta y el plan los muestra como \"no aplica\" en Home (la lista está más arriba, en \"Ajustes que no se aplican en Home\"). Lo que sigue quedó fuera porque en Home no hay una forma que funcione y se pueda deshacer.",
        "en": "Windows Home ignores many group policies. The catalog tweaks that are policies declare the editions where Microsoft documents them, and the plan shows them as \"does not apply\" on Home (the list is above, in \"Tweaks that do not apply on Home\"). What follows was left out because on Home there is no way that works and can be undone."
      },
      "items": [
        { "name": { "es": "Telemetría al mínimo por directiva en Home", "en": "Minimum telemetry by policy on Home" }, "why": { "es": "AllowTelemetry en las directivas no rige en Home; lo único que corta la subida de datos ahí es el servicio DiagTrack (services.diagtrack, con pregunta).", "en": "AllowTelemetry in the policies does not apply on Home; the only thing that stops the upload there is the DiagTrack service (services.diagtrack, which asks first)." } },
        { "name": { "es": "Contenido de consumidor y tarjetas de Microsoft 365 en Home y Pro", "en": "Consumer content and Microsoft 365 cards on Home and Pro" }, "why": { "es": "DisableWindowsConsumerFeatures y DisableConsumerAccountStateContent solo rigen en Enterprise y Education; en Home y Pro los ajustes de usuario de anuncios cubren lo que se puede.", "en": "DisableWindowsConsumerFeatures and DisableConsumerAccountStateContent only apply to Enterprise and Education; on Home and Pro the user ads tweaks cover what can be covered." } },
        { "name": { "es": "Widgets en Home (TaskbarDa)", "en": "Widgets on Home (TaskbarDa)" }, "why": { "es": "Windows bloquea la escritura de ese valor desde PowerShell (UCPD); la directiva solo rige en Pro y superiores.", "en": "Windows blocks writing that value from PowerShell (UCPD); the policy only applies on Pro and later." } },
        { "name": { "es": "Red en suspensión moderna y Delivery Optimization en Home", "en": "Modern standby network and Delivery Optimization on Home" }, "why": { "es": "Sin una directiva que Home respete hay que escribir en otras colmenas o subgrupos que el motor no admite.", "en": "Without a policy that Home honors they need other hives or power subgroups that the engine does not support." } }
      ]
    },
    {
      "id": "actions-dropped",
      "title": { "es": "Acciones descartadas", "en": "Dropped actions" },
      "intro": {
        "es": "Se evaluaron como acciones propias y se descartaron porque no se pudo verificar, en solo lectura, que hacen lo que prometen y que se pueden deshacer.",
        "en": "They were evaluated as actions of their own and dropped because it could not be verified, read-only, that they do what they promise and can be undone."
      },
      "items": [
        { "name": { "es": "power-mode-overlay: modo de energía \"Mejor rendimiento\" con corriente", "en": "power-mode-overlay: \"Best performance\" power mode on AC" }, "why": { "es": "Es una superposición del plan que solo se cambia con una función de Windows sin documentar (PowerSetActiveOverlayScheme); no se sabe si cambia CA y CC juntos ni si escribir el registro surte efecto en caliente.", "en": "It is an overlay of the power plan that only an undocumented Windows function changes (PowerSetActiveOverlayScheme); it is unknown whether it changes AC and DC together or whether writing the registry takes effect live." } },
        { "name": { "es": "dev-defender-performance-mode: modo de rendimiento de Defender para Dev Drive", "en": "dev-defender-performance-mode: Defender performance mode for Dev Drive" }, "why": { "es": "Microsoft lo activa por defecto en un Dev Drive de confianza y el valor leído en un equipo sin Dev Drive contradice esa documentación; sin un Dev Drive no se puede comprobar, y toca Defender.", "en": "Microsoft turns it on by default on a trusted Dev Drive, and the value read on a machine without a Dev Drive contradicts that documentation; it cannot be checked without a Dev Drive, and it touches Defender." } }
      ]
    },
    {
      "id": "unverified",
      "title": { "es": "Ajustes que no se pudieron verificar", "en": "Tweaks that could not be verified" },
      "intro": {
        "es": "Quedan fuera hasta que se compruebe que hacen lo que prometen y que se pueden deshacer.",
        "en": "Left out until it is checked that they do what they promise and that they can be undone."
      },
      "items": [
        { "name": { "es": "Animaciones de la barra de tareas (TaskbarAnimations)", "en": "Taskbar animations (TaskbarAnimations)" }, "why": { "es": "Sin evidencia de efecto en Windows 11.", "en": "No evidence of an effect on Windows 11." } },
        { "name": { "es": "Directiva AllowGameDVR", "en": "AllowGameDVR policy" }, "why": { "es": "Microsoft: solo rige en Windows 10 de escritorio; los valores de usuario de Game DVR ya cubren el objetivo.", "en": "Microsoft: it only applies to Windows 10 desktop; the user values of Game DVR already cover the goal." } },
        { "name": { "es": "Búsqueda en la nube (IsMSACloudSearchEnabled, IsAADCloudSearchEnabled)", "en": "Cloud search (IsMSACloudSearchEnabled, IsAADCloudSearchEnabled)" }, "why": { "es": "Solo fuentes de la comunidad; la de cuentas de trabajo rompe la búsqueda de OneDrive y Outlook.", "en": "Community sources only; the work-account one breaks OneDrive and Outlook results in search." } },
        { "name": { "es": "Servicios InventorySvc y PcaSvc", "en": "InventorySvc and PcaSvc services" }, "why": { "es": "Sin guía de Microsoft para equipos cliente; el primero alimenta las actualizaciones de función.", "en": "No Microsoft guidance for client machines; the first one feeds feature updates." } }
      ]
    },
    {
      "id": "engine-limits",
      "title": { "es": "Pendientes de una capacidad del motor", "en": "Waiting for an engine capability" },
      "intro": {
        "es": "Serían útiles, pero el motor todavía no los puede aplicar y deshacer con exactitud.",
        "en": "They would be useful, but the engine cannot apply and undo them exactly yet."
      },
      "items": [
        { "name": { "es": "Efectos visuales (UserPreferencesMask)", "en": "Visual effects (UserPreferencesMask)" }, "why": { "es": "Es un valor binario y el catálogo todavía no acepta valores Binary.", "en": "It is a binary value and the catalog does not accept Binary values yet." } },
        { "name": { "es": "Menú contextual clásico de Windows 11", "en": "Classic context menu of Windows 11" }, "why": { "es": "Usa el valor predeterminado de una clave, que el manejador de registro no admite; además es una preferencia.", "en": "It uses the default value of a key, which the registry handler does not support; it is also a preference." } },
        { "name": { "es": "Hibernación, apps de inicio, reducir la indexación, impresoras", "en": "Hibernation, startup apps, smaller indexing, printers" }, "why": { "es": "Necesitan una acción propia con pregunta; quedan como ideas.", "en": "They need their own action with a question; they stay as ideas." } }
      ]
    }
  ]
}
```

`name` es texto, o un objeto `{ "es", "en" }` cuando el nombre se traduce. `appx` (opcional) es el nombre del paquete: la prueba comprueba que ninguno esté en el catálogo.

- [ ] **Step 4: Escribir `build/catalog-doc.labels.json`**

```json
{
  "es": {
    "heading": "Catálogo de ajustes",
    "generated": "Este archivo lo genera `build/catalog-doc.ps1` a partir de `catalog/*.json`, `profiles/*.json` y `catalog/notes/excluded.json`. No se edita a mano: después de cambiar el catálogo, ejecuta `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1`.",
    "otherLanguage": "English version: [../en/catalog.md](../en/catalog.md).",
    "summary": "Resumen",
    "category": "Categoría",
    "tweaks": "Ajustes",
    "profiles": "Perfiles",
    "profile": "Perfil",
    "aliases": "Alias",
    "includes": "Incluye",
    "keeps": "Mantiene",
    "total": "Total",
    "askHeading": "Ajustes que preguntan",
    "askIntro": "Estos ajustes llevan `ask: true`: sin menú interactivo y con `-Yes` se omiten, salvo que los pidas por nombre con `-Include`.",
    "highHeading": "Ajustes de riesgo alto",
    "highIntro": "Ningún perfil los incluye. Solo se aplican si los pides por nombre con `-Include`.",
    "homeHeading": "Ajustes que no se aplican en Home",
    "homeIntro": "Son directivas que Windows Home ignora o funciones que Microsoft documenta solo para otras ediciones. En Home el plan los muestra como \"no aplica\" en lugar de fingir que funcionaron.",
    "id": "Id",
    "title": "Ajuste",
    "editions": "Ediciones",
    "type": "Tipo",
    "scope": "Ámbito",
    "risk": "Riesgo",
    "ask": "Pregunta",
    "inProfiles": "En perfiles",
    "keptBy": "Lo mantienen",
    "windows": "Windows",
    "requires": "Solo en",
    "afterApplying": "Después de aplicar",
    "sources": "Fuentes",
    "none": "ninguno",
    "yes": "sí",
    "no": "no",
    "scope.user": "usuario (sin administrador)",
    "scope.machine": "equipo (administrador)",
    "risk.low": "bajo",
    "risk.medium": "medio",
    "risk.high": "alto",
    "requires.battery": "equipos con batería",
    "requires.no-battery": "equipos sin batería",
    "after.reboot": "reiniciar",
    "after.signOut": "cerrar sesión",
    "after.nothing": "nada",
    "build": "build {0} o posterior",
    "excludedHeading": "No incluido",
    "excludedIntro": "Lo que se evaluó y quedó fuera del catálogo, con el motivo. La lista de lo que no se aplica nunca, ni siquiera con `-Include`, está en [blacklist.md](blacklist.md).",
    "category.privacy": "Privacidad y telemetría",
    "category.ads": "Anuncios y sugerencias",
    "category.ui": "Interfaz",
    "category.ai": "Copilot, Recall e IA",
    "category.edge": "Microsoft Edge",
    "category.services": "Servicios",
    "category.tasks": "Tareas programadas",
    "category.performance": "Rendimiento",
    "category.power": "Energía",
    "category.gaming": "Juegos",
    "category.dev": "Desarrollo",
    "category.apps": "Apps"
  },
  "en": {
    "heading": "Tweak catalog",
    "generated": "This file is generated by `build/catalog-doc.ps1` from `catalog/*.json`, `profiles/*.json` and `catalog/notes/excluded.json`. Do not edit it by hand: after changing the catalog, run `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1`.",
    "otherLanguage": "Versión en español: [../es/catalog.md](../es/catalog.md).",
    "summary": "Summary",
    "category": "Category",
    "tweaks": "Tweaks",
    "profiles": "Profiles",
    "profile": "Profile",
    "aliases": "Aliases",
    "includes": "Includes",
    "keeps": "Keeps",
    "total": "Total",
    "askHeading": "Tweaks that ask first",
    "askIntro": "These tweaks have `ask: true`: without the interactive menu and with `-Yes` they are skipped, unless you ask for them by name with `-Include`.",
    "highHeading": "High-risk tweaks",
    "highIntro": "No profile includes them. They are only applied when you ask for them by name with `-Include`.",
    "homeHeading": "Tweaks that do not apply on Home",
    "homeIntro": "They are policies that Windows Home ignores or features that Microsoft documents only for other editions. On Home the plan shows them as \"does not apply\" instead of pretending they worked.",
    "id": "Id",
    "title": "Tweak",
    "editions": "Editions",
    "type": "Type",
    "scope": "Scope",
    "risk": "Risk",
    "ask": "Asks",
    "inProfiles": "In profiles",
    "keptBy": "Kept by",
    "windows": "Windows",
    "requires": "Only on",
    "afterApplying": "After applying",
    "sources": "Sources",
    "none": "none",
    "yes": "yes",
    "no": "no",
    "scope.user": "user (no administrator)",
    "scope.machine": "machine (administrator)",
    "risk.low": "low",
    "risk.medium": "medium",
    "risk.high": "high",
    "requires.battery": "machines with a battery",
    "requires.no-battery": "machines without a battery",
    "after.reboot": "restart",
    "after.signOut": "sign out",
    "after.nothing": "nothing",
    "build": "build {0} or later",
    "excludedHeading": "Not included",
    "excludedIntro": "What was evaluated and left out of the catalog, with the reason. What is never applied, not even with `-Include`, is listed in [blacklist.md](blacklist.md).",
    "category.privacy": "Privacy and telemetry",
    "category.ads": "Ads and suggestions",
    "category.ui": "Interface",
    "category.ai": "Copilot, Recall and AI",
    "category.edge": "Microsoft Edge",
    "category.services": "Services",
    "category.tasks": "Scheduled tasks",
    "category.performance": "Performance",
    "category.power": "Power",
    "category.gaming": "Gaming",
    "category.dev": "Development",
    "category.apps": "Apps"
  }
}
```

- [ ] **Step 5: Escribir `build/catalog-doc.ps1`**

```powershell
<#
.SYNOPSIS
    Writes docs/es/catalog.md and docs/en/catalog.md from the catalog, the profiles and
    catalog/notes/excluded.json. The texts of the page come from build/catalog-doc.labels.json.
.PARAMETER OutDir
    Folder that receives es/catalog.md and en/catalog.md. By default the docs folder of the repository;
    the tests write to a temporary folder and compare.
#>
param([string]$OutDir)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'docs' }
$categories = @('privacy', 'ads', 'ui', 'ai', 'edge', 'services', 'tasks', 'performance', 'power', 'gaming', 'dev', 'apps')
$profileOrder = @('base', 'dev', 'gaming', 'privacy', 'laptop', 'legacy', 'work', 'lite')

function Read-DocJson {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Format-DocCell {
    param([AllowNull()][string]$Text)
    ([string]$Text).Replace('|', '\|')
}

$labels = Read-DocJson -Path (Join-Path $PSScriptRoot 'catalog-doc.labels.json')
$excluded = Read-DocJson -Path (Join-Path $root 'catalog\notes\excluded.json')
$tweaksByCategory = [ordered]@{}
foreach ($category in $categories) {
    $file = Join-Path $root "catalog\$category.json"
    $tweaksByCategory[$category] = @($(if (Test-Path -LiteralPath $file) { (Read-DocJson -Path $file).tweaks }))
}
$allTweaks = @($tweaksByCategory.Values | ForEach-Object { $_ })
$profiles = @($profileOrder | ForEach-Object {
        $file = Join-Path $root "profiles\$_.json"
        if (Test-Path -LiteralPath $file) { Read-DocJson -Path $file }
    })

function Get-DocProfileList {
    param([Parameter(Mandatory)][string]$TweakId, [Parameter(Mandatory)][string]$Field, [Parameter(Mandatory)]$Text)
    $names = @($profiles | Where-Object { @($_.$Field) -contains $TweakId } | ForEach-Object { '`' + $_.id + '`' })
    $(if ($names.Count) { $names -join ', ' } else { $Text.none })
}

function New-DocPage {
    param([Parameter(Mandatory)][string]$Lang)
    $text = $labels.$Lang
    $lines = New-Object System.Collections.Generic.List[string]
    $add = { param([string]$Line) $lines.Add($Line) }

    & $add "# $($text.heading)"
    & $add ''
    & $add $text.generated
    & $add ''
    & $add $text.otherLanguage
    & $add ''
    & $add "## $($text.summary)"
    & $add ''
    & $add "| $($text.category) | $($text.tweaks) |"
    & $add '|---|---|'
    foreach ($category in $categories) {
        & $add "| $($text."category.$category") (``$category``) | $($tweaksByCategory[$category].Count) |"
    }
    & $add "| **$($text.total)** | **$($allTweaks.Count)** |"
    & $add ''
    & $add "## $($text.profiles)"
    & $add ''
    & $add "| $($text.profile) | $($text.aliases) | $($text.includes) | $($text.keeps) |"
    & $add '|---|---|---|---|'
    foreach ($profileData in $profiles) {
        $aliases = @($profileData.aliases | ForEach-Object { '`' + $_ + '`' }) -join ', '
        & $add "| ``$($profileData.id)`` $(Format-DocCell $profileData.title.$Lang) | $aliases | $(@($profileData.include).Count) | $(@($profileData.keep).Count) |"
    }
    & $add ''

    & $add "## $($text.askHeading)"
    & $add ''
    & $add $text.askIntro
    & $add ''
    foreach ($tweak in $allTweaks | Where-Object { $_.ask }) { & $add "- ``$($tweak.id)``: $($tweak.title.$Lang)" }
    & $add ''
    & $add "## $($text.highHeading)"
    & $add ''
    & $add $text.highIntro
    & $add ''
    foreach ($tweak in $allTweaks | Where-Object { $_.risk -eq 'high' }) { & $add "- ``$($tweak.id)``: $($tweak.title.$Lang)" }
    & $add ''
    & $add "## $($text.homeHeading)"
    & $add ''
    & $add $text.homeIntro
    & $add ''
    & $add "| $($text.id) | $($text.title) | $($text.editions) |"
    & $add '|---|---|---|'
    foreach ($tweak in $allTweaks | Where-Object { @($_.os.editions) -notcontains 'Home' }) {
        & $add "| ``$($tweak.id)`` | $(Format-DocCell $tweak.title.$Lang) | $(@($tweak.os.editions) -join ', ') |"
    }
    & $add ''

    foreach ($category in $categories) {
        & $add "## $($text."category.$category") (``catalog/$category.json``)"
        & $add ''
        foreach ($tweak in $tweaksByCategory[$category]) {
            & $add "### ``$($tweak.id)``"
            & $add ''
            & $add "**$($tweak.title.$Lang)**"
            & $add ''
            & $add $tweak.why.$Lang
            & $add ''
            & $add "- **$($text.type):** ``$($tweak.type)``; **$($text.scope):** $($text."scope.$($tweak.scope)"); **$($text.risk):** $($text."risk.$($tweak.risk)"); **$($text.ask):** $(if ($tweak.ask) { $text.yes } else { $text.no })"
            & $add "- **$($text.inProfiles):** $(Get-DocProfileList -TweakId $tweak.id -Field 'include' -Text $text); **$($text.keptBy):** $(Get-DocProfileList -TweakId $tweak.id -Field 'keep' -Text $text)"
            $build = $text.build -f $tweak.os.minBuild
            & $add "- **$($text.windows):** $(@($tweak.os.families) -join ', '), $build; **$($text.editions):** $(@($tweak.os.editions) -join ', ')"
            if ($null -ne $tweak.PSObject.Properties['requires']) {
                & $add "- **$($text.requires):** $(@($tweak.requires | ForEach-Object { $text."requires.$_" }) -join ', ')"
            }
            $after = @()
            if ($tweak.rebootRequired) { $after += $text.'after.reboot' }
            if ($null -ne $tweak.PSObject.Properties['signOutRequired'] -and $tweak.signOutRequired) { $after += $text.'after.signOut' }
            if (-not $after.Count) { $after = @($text.'after.nothing') }
            & $add "- **$($text.afterApplying):** $($after -join ', ')"
            & $add "- **$($text.sources):** $(@($tweak.sources | ForEach-Object { "<$_>" }) -join ', ')"
            & $add ''
        }
    }

    & $add "## $($text.excludedHeading)"
    & $add ''
    & $add $text.excludedIntro
    & $add ''
    foreach ($group in $excluded.groups) {
        & $add "### $($group.title.$Lang)"
        & $add ''
        & $add $group.intro.$Lang
        & $add ''
        foreach ($item in $group.items) {
            # A product name is the same in both languages unless the notes give one per language.
            $name = $(if ($item.name -is [string]) { $item.name } else { $item.name.$Lang })
            $package = $(if ($item.appx) { " (``$($item.appx)``)" } else { '' })
            & $add "- **$name**$($package): $($item.why.$Lang)"
        }
        & $add ''
    }
    # One trailing line break, CRLF like every text file of the repository.
    ($lines.ToArray() -join "`r`n").TrimEnd() + "`r`n"
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
foreach ($lang in 'es', 'en') {
    $folder = Join-Path $OutDir $lang
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    $path = Join-Path $folder 'catalog.md'
    [System.IO.File]::WriteAllText($path, (New-DocPage -Lang $lang), $utf8)
    Write-Output "Wrote $path"
}
```

- [ ] **Step 6: Generar las páginas**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1`
Expected:

```text
Wrote C:\Users\Edgar\Documents\GitHub\windows-tuneup\docs\es\catalog.md
Wrote C:\Users\Edgar\Documents\GitHub\windows-tuneup\docs\en\catalog.md
```

Revisar a mano el principio de `docs/es/catalog.md`: el resumen dice `| **Total** | **166** |`, la tabla de perfiles tiene ocho filas (`lite` con 102 ajustes), "Ajustes que preguntan" lista 36 y "Ajustes de riesgo alto" cuatro (`privacy.diagnostic-data-off`, `ai.recall-snapshots-off`, `ai.recall-unavailable` y `gaming.memory-integrity-off`). Cada página ronda los 120 KB.

- [ ] **Step 7: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/CatalogDoc.Tests.ps1`
Expected: PASS (`Tests Passed: 7, Failed: 0`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings` (el lint ya recorre `build/`).

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Failed: 0`), incluida `has JSON files that parse` de `tests/Repo.Tests.ps1` con los dos JSON nuevos.

- [ ] **Step 8: Commit**

```bash
git add catalog/notes/excluded.json build/catalog-doc.labels.json build/catalog-doc.ps1 docs/es/catalog.md docs/en/catalog.md tests/CatalogDoc.Tests.ps1
git commit -m "docs: catálogo generado en español e inglés con lo que quedó fuera"
```

A partir de aquí, cualquier cambio en `catalog/`, `profiles/` o `catalog/notes/excluded.json` exige volver a correr `build/catalog-doc.ps1` y commitear las dos páginas; si no, falla `is up to date with the catalog, the profiles and the notes`.

---

### Task 25: Método de medición contra LTSC (`docs/{es,en}/measuring.md`)

**Files:**
- Create: `docs/es/measuring.md`, `docs/en/measuring.md`
- Modify: `tests/Docs.Tests.ps1`

Método manual en máquinas virtuales: Windows 11 Pro limpio frente a Windows 11 Enterprise LTSC 2024 limpio, reiniciar, dos minutos en reposo, `-Measure` tres veces, aplicar `lite`, reiniciar, `-Measure -Compare`. No hay automatización en este plan. La afirmación del README queda "pendiente de medir" hasta que el reporte la confirme.

- [ ] **Step 1: Prueba que falla**

Agregar al final de `tests/Docs.Tests.ps1`:

```powershell
Describe 'Measuring guide' {
    It 'gives the commands of the method and the LTSC edition in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'measuring.md'
            foreach ($term in '-Measure -IdleSeconds 120', '-Compare last', '-Profile lite -Yes', 'LTSC 2024', 'reagentc /info', '-Undo last') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: FAIL, no se encuentra `docs\es\measuring.md`.

- [ ] **Step 3: Escribir `docs/es/measuring.md`**

````markdown
# Cómo medir: Liviano frente a Windows 11 LTSC

English version: [../en/measuring.md](../en/measuring.md).

La especificación promete que el perfil Liviano (`lite`) queda por debajo de una instalación limpia de Windows 11 LTSC en RAM en reposo, procesos y servicios en ejecución, sin apagar Defender, Windows Update ni WinRE. **Esa afirmación todavía no está medida.** Este documento describe el método manual con el que se medirá antes de cada release; el reporte se adjunta a la release. En el Plan 3 no hay nada automatizado.

## Qué se compara

| Máquina | Qué tiene |
|---|---|
| A: Windows 11 Pro, instalación limpia | La ISO oficial de la misma versión que LTSC (24H2), sin cuenta Microsoft (cuenta local), con todas las actualizaciones. |
| B: Windows 11 Enterprise LTSC 2024, instalación limpia | La ISO de evaluación de LTSC 2024, cuenta local, con todas las actualizaciones. |

Se compara **A con Liviano aplicado** contra **B sin tocar**. A sin tocar sirve de referencia para ver cuánto ganó Liviano.

## Preparar las máquinas virtuales

1. Hyper-V (o la herramienta que uses) con la misma configuración para las dos: 2 procesadores virtuales, 4 GB de RAM fija (sin memoria dinámica, que cambia la RAM disponible entre mediciones), disco de 64 GB, red con NAT, TPM y arranque seguro activados.
2. Instala cada sistema con una cuenta local, acepta las opciones de privacidad que vienen marcadas (para medir lo que trae Windows por defecto) y ejecuta Windows Update hasta que no queden actualizaciones. Reinicia las veces que pida.
3. Espera a que termine el mantenimiento inicial: deja la máquina encendida y sin uso al menos 30 minutos después de la última actualización (indexación, optimización de .NET, tareas de primer inicio).
4. Copia `windows-tuneup` a `C:\Program Files\windows-tuneup` (una carpeta donde solo escriben administradores) en las dos máquinas.
5. Toma un punto de control (snapshot) de cada máquina en este estado: así puedes repetir la medición.

## Medir

En cada máquina, en este orden y con PowerShell **como administrador** (así también se lee la duración del arranque; compara siempre mediciones con el mismo nivel de elevación):

1. Reinicia, inicia sesión y no abras nada más.
2. Mide en reposo, esperando dos minutos:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Measure -IdleSeconds 120
   ```

3. Repite los pasos 1 y 2 dos veces más (tres mediciones por estado). Los números varían entre arranques; el reporte usa la mediana de las tres.

En la máquina A, además:

4. Aplica Liviano sin preguntar. Los ajustes que preguntan (`ask`) se omiten con `-Yes`; para medir el perfil completo agrégalos por nombre con `-Include <id>,<id>` (la lista está en [catalog.md](catalog.md#ajustes-que-preguntan)). Sin ellos:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Profile lite -Yes
   ```

   Anota en el reporte si se midió con o sin los ajustes que preguntan, y cuáles se incluyeron con `-Include`.
5. Reinicia, inicia sesión y espera 30 minutos (Windows reacomoda tareas después de cambios grandes).
6. Reinicia otra vez, inicia sesión y mide comparando con la última medición antes de aplicar:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Measure -IdleSeconds 120 -Compare last
   ```

   `-Compare last` toma la medición guardada más reciente, que es la tercera medición previa. Repite el paso 6 dos veces más, comparando con el id de esa medición previa (`-Compare <id>`).

## Qué se informa

Para cada máquina y estado: la mediana de RAM en uso (MB), procesos, servicios en ejecución, tareas programadas habilitadas y duración del arranque. La tabla del reporte tiene tres columnas (Pro limpio, Pro + Liviano, LTSC 2024) y una fila por métrica, más:

- La versión de `windows-tuneup` (etiqueta de la release) y el build exacto de cada máquina (`-Measure -Json` lo guarda en `environment`).
- Cuántos ajustes aplicó Liviano y cuáles se omitieron (`result.json` de la corrida).
- Que Defender, Windows Update y WinRE siguen activos en A después de aplicar: `Get-MpComputerStatus` (`AMServiceEnabled`, `RealTimeProtectionEnabled`), `Get-Service wuauserv` y `reagentc /info`.

La afirmación del README solo cambia de "pendiente de medir" a medida cuando Pro + Liviano queda por debajo de LTSC en las tres métricas principales (RAM, procesos y servicios). Si no lo logra, el reporte se publica igual, con los números.

## Volver al estado inicial

`-Undo last` deshace Liviano en A (las apps se reinstalan desde la Store para la cuenta que deshace). Para repetir la medición desde cero, vuelve al punto de control.
````

- [ ] **Step 4: Escribir `docs/en/measuring.md`**

````markdown
# How to measure: Lite versus Windows 11 LTSC

Versión en español: [../es/measuring.md](../es/measuring.md).

The design promises that the Lite profile (`lite`) ends below a clean Windows 11 LTSC install in idle RAM, processes and running services, without turning off Defender, Windows Update or WinRE. **That claim is not measured yet.** This document describes the manual method that will measure it before each release; the report is attached to the release. Plan 3 automates nothing.

## What is compared

| Machine | What it has |
|---|---|
| A: Windows 11 Pro, clean install | The official ISO of the same version as LTSC (24H2), no Microsoft account (local account), fully updated. |
| B: Windows 11 Enterprise LTSC 2024, clean install | The LTSC 2024 evaluation ISO, local account, fully updated. |

**A with Lite applied** is compared with **B untouched**. A untouched is the reference to see how much Lite gained.

## Prepare the virtual machines

1. Hyper-V (or the tool you use) with the same settings for both: 2 virtual processors, 4 GB of fixed RAM (no dynamic memory, which changes the available RAM between measurements), a 64 GB disk, NAT networking, TPM and Secure Boot on.
2. Install each system with a local account, accept the privacy options as they come (to measure what Windows ships by default) and run Windows Update until no updates are left. Restart as many times as it asks.
3. Wait for the first maintenance to finish: leave the machine on and unused for at least 30 minutes after the last update (indexing, .NET optimization, first-run tasks).
4. Copy `windows-tuneup` to `C:\Program Files\windows-tuneup` (a folder that only administrators can write to) on both machines.
5. Take a checkpoint (snapshot) of each machine in this state, so the measurement can be repeated.

## Measure

On each machine, in this order and with PowerShell **as administrator** (so the boot duration is read too; always compare measurements taken at the same elevation):

1. Restart, sign in and open nothing else.
2. Measure at idle, waiting two minutes:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Measure -IdleSeconds 120
   ```

3. Repeat steps 1 and 2 two more times (three measurements per state). The numbers vary between boots; the report uses the median of the three.

On machine A, also:

4. Apply Lite without questions. The tweaks that ask (`ask`) are skipped with `-Yes`; to measure the whole profile, add them by name with `-Include <id>,<id>` (the list is in [catalog.md](catalog.md#tweaks-that-ask-first)). Without them:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Profile lite -Yes
   ```

   Write down in the report whether it was measured with or without the tweaks that ask, and which ones were included with `-Include`.
5. Restart, sign in and wait 30 minutes (Windows reschedules tasks after big changes).
6. Restart again, sign in and measure, comparing with the last measurement taken before applying:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\windows-tuneup\tuneup.ps1" -Measure -IdleSeconds 120 -Compare last
   ```

   `-Compare last` takes the most recent saved measurement, which is the third measurement before applying. Repeat step 6 two more times, comparing with the id of that earlier measurement (`-Compare <id>`).

## What is reported

For each machine and state: the median of RAM in use (MB), processes, running services, enabled scheduled tasks and boot duration. The report table has three columns (clean Pro, Pro + Lite, LTSC 2024) and one row per metric, plus:

- The `windows-tuneup` version (release tag) and the exact build of each machine (`-Measure -Json` keeps it in `environment`).
- How many tweaks Lite applied and which ones were skipped (the run's `result.json`).
- That Defender, Windows Update and WinRE are still on in A after applying: `Get-MpComputerStatus` (`AMServiceEnabled`, `RealTimeProtectionEnabled`), `Get-Service wuauserv` and `reagentc /info`.

The README claim only changes from "pending measurement" to measured when Pro + Lite ends below LTSC in the three main metrics (RAM, processes and services). If it does not, the report is published anyway, with the numbers.

## Back to the starting point

`-Undo last` undoes Lite on A (apps are reinstalled from the Store for the account that undoes). To repeat the measurement from scratch, go back to the checkpoint.
````

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: PASS (`Tests Passed: 2, Failed: 0`).

- [ ] **Step 6: Commit**

```bash
git add docs/es/measuring.md docs/en/measuring.md tests/Docs.Tests.ps1
git commit -m "docs: método para medir Liviano frente a LTSC"
```

---

### Task 26: Guía de perfiles (`docs/{es,en}/profiles.md`)

**Files:**
- Create: `docs/es/profiles.md`, `docs/en/profiles.md`
- Modify: `tests/Docs.Tests.ps1`

Para cada perfil: qué hace, por qué, qué conserva, qué pregunta (cada id con `ask: true` que el perfil incluye, así ninguna app que pregunta queda sin documentar) y si necesita administrador. Las reglas comunes (`keep`, `ask`, riesgo alto, edición, equipos administrados, deshacer) van al principio.

- [ ] **Step 1: Pruebas que fallan**

Agregar al final de `tests/Docs.Tests.ps1`:

```powershell
Describe 'Documentation in both languages' {
    It 'has <Name> in Spanish and English, in UTF-8 without a byte order mark' -TestCases @(
        @{ Name = 'blacklist.md' }
        @{ Name = 'profiles.md' }
        @{ Name = 'measuring.md' }
        @{ Name = 'catalog.md' }
    ) {
        param($Name)
        foreach ($lang in 'es', 'en') {
            $path = Join-Path $Repo "docs\$lang\$Name"
            Test-Path -LiteralPath $path | Should -BeTrue -Because "docs/$lang/$Name"
            $bytes = [System.IO.File]::ReadAllBytes($path)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because "docs/$lang/$Name"
        }
    }

    It 'only links to files that exist' {
        foreach ($lang in 'es', 'en') {
            foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Repo "docs\$lang") -Filter '*.md' -File) {
                $text = Get-DocText $lang $file.Name
                foreach ($match in [regex]::Matches($text, '\]\((?!https?://)([^)#]+)(#[^)]*)?\)')) {
                    $target = Join-Path $file.DirectoryName ($match.Groups[1].Value -replace '/', '\')
                    Test-Path -LiteralPath $target | Should -BeTrue -Because "$lang/$($file.Name) links to $($match.Groups[1].Value)"
                }
            }
        }
    }
}

Describe 'Profile guide' {
    It 'describes every profile with its id' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'profiles.md'
            foreach ($profileData in $Profiles) { $text.Contains("(``$($profileData.id)``") | Should -BeTrue -Because "$lang $($profileData.id)" }
        }
    }

    It 'names every tweak that asks first in the profiles that include it' {
        $ask = @($Catalog | Where-Object { $_.ask } | ForEach-Object { $_.id })
        $included = @($Profiles | ForEach-Object { @($_.include) } | Where-Object { $ask -contains $_ } | Sort-Object -Unique)
        $included.Count | Should -BeGreaterThan 0
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'profiles.md'
            foreach ($tweakId in $included) { $text.Contains("``$tweakId``") | Should -BeTrue -Because "$lang $tweakId" }
        }
    }

    It 'names every high-risk tweak and how to ask for it' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'profiles.md'
            foreach ($tweak in $Catalog | Where-Object { $_.risk -eq 'high' }) { $text.Contains("``$($tweak.id)``") | Should -BeTrue -Because "$lang $($tweak.id)" }
        }
    }
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: FAIL en el caso `profiles.md` de `has <Name> in Spanish and English...` y en las tres pruebas de `Profile guide` (no se encuentra `docs\es\profiles.md`). Los otros tres casos y `only links to files that exist` ya pasan: `blacklist.md`, `catalog.md` y `measuring.md` existen y sus enlaces también.

- [ ] **Step 3: Escribir `docs/es/profiles.md`**

````markdown
# Perfiles

English version: [../en/profiles.md](../en/profiles.md).

Un perfil es una lista de ajustes del catálogo agrupados por objetivo. `base` se aplica siempre; los demás se combinan: `-Profile privacy,gaming`. Un perfil también se nombra por su alias (`privacidad`, `juegos`...). La lista completa de ajustes, con su riesgo y sus fuentes, está en [catalog.md](catalog.md); lo que no se aplica nunca, en [blacklist.md](blacklist.md).

Reglas que valen para todos:

- **Primero mira el plan:** `.\tuneup.ps1 -Profile <perfil> -WhatIf` muestra qué cambia y por qué se omite cada ajuste. No cambia nada.
- **`keep` gana:** si un perfil conserva algo (Juegos conserva Xbox) y otro lo quitaría (Liviano), se conserva. Pedirlo por nombre con `-Include` gana sobre `keep`.
- **Preguntas:** los ajustes que cambian algo que alguien podría estar usando llevan `ask: true`. Hasta que exista el menú interactivo se omiten con el motivo "requiere confirmación"; para aplicarlos, pídelos por nombre: `-Include apps.onedrive`.
- **Riesgo alto:** ningún perfil incluye ajustes de riesgo alto; solo se aplican con `-Include`.
- **Edición y hardware:** una directiva que tu edición ignora (por ejemplo, Home) o un ajuste pensado para otro hardware (con o sin batería) se omite y el plan dice por qué.
- **Equipos de una organización:** en un equipo unido a un dominio o inscrito en Intune no se tocan directivas (`\Policies\`): el plan las muestra como "equipo administrado".
- **Administrador:** `base` y `work` solo tienen ajustes de tu usuario y se aplican sin elevar. Los demás traen cambios de sistema: abre PowerShell como administrador, o deja fuera esos ajustes con `-Exclude`.
- **Deshacer:** `.\tuneup.ps1 -Undo last` devuelve todo lo de la última corrida. Las apps se reinstalan desde la Store para tu cuenta (ver el README).

## Base (`base`)

**Qué hace:** quita anuncios y sugerencias de Inicio, Configuración, la pantalla de bloqueo, el Explorador y la búsqueda (Búsqueda destacada), apaga el ID de publicidad, las experiencias personalizadas y las encuestas de opinión, y muestra las extensiones de archivo.

**Por qué:** es lo que cualquier equipo gana sin perder nada: menos ruido y un archivo `factura.pdf.exe` se ve como lo que es.

**Qué conserva:** todo lo demás. No toca servicios, tareas, apps ni directivas, así que también es seguro en un equipo de trabajo.

**Administrador:** no. Siempre se aplica junto con cualquier otro perfil.

## Desarrollo (`dev`, alias `desarrollo`)

**Qué hace:** activa el Modo desarrollador (vínculos simbólicos sin administrador, apps de prueba), las rutas de más de 260 caracteres (`node_modules`, git), muestra archivos ocultos, agrega "Finalizar tarea" al menú de la barra de tareas y no suspende los USB con el cargador conectado (dispositivos de depuración).

**Pregunta antes de:** `dev.sudo-enable` (sudo para Windows).

**Qué conserva:** WSL, Hyper-V, la Plataforma de máquina virtual, los contenedores y Windows Terminal. Ningún ajuste del catálogo toca sus servicios (`vmcompute`, `vmms`, `hns`, `HvHost`, `LxssManager`, `WslService`) ni `SharedAccess`, que sostiene la red de WSL2 y Hyper-V; una prueba lo comprueba.

**No hace:** exclusiones de Defender para tus carpetas de código (quitan protección; Microsoft recomienda un Dev Drive) ni crear un Dev Drive (exige formatear un volumen). Para git, `git config --global core.longpaths true` complementa las rutas largas.

**Administrador:** sí. Las rutas largas piden reiniciar.

## Juegos (`gaming`, alias `juegos`)

**Qué hace:** activa el Modo Juego, apaga Game DVR, la captura y la grabación en segundo plano, quita la aceleración del mouse (1:1, se nota al volver a iniciar sesión), activa las optimizaciones para juegos en ventana, la programación de GPU acelerada por hardware **solo si el driver la admite** (si no, el plan dice "no existe en este equipo") y no suspende los USB con el cargador conectado.

**Pregunta antes de:** `gaming.gamebar-controller-off` (el botón Xbox del mando deja de abrir Game Bar) y `power.high-performance-plan` (plan Alto rendimiento; solo en equipos sin batería).

**Qué conserva:** las apps de Xbox y Game Bar y su tarea de partidas guardadas, que Game Pass y muchos juegos necesitan. Los servicios de Xbox no están en el catálogo: ya vienen en manual y deshabilitarlos rompe el inicio de sesión de Xbox. Combinado con Liviano, también se conservan.

**Riesgo alto, solo con `-Include`:** `gaming.memory-integrity-off` (integridad de memoria): puede dar entre 1 y 15 % más de FPS en algunos juegos a cambio de menos protección contra drivers maliciosos.

**Administrador:** sí. La GPU acelerada pide reiniciar.

## Privacidad (`privacy`, alias `privacidad`)

**Qué hace:** deja los datos de diagnóstico en "Requeridos" (Pro, Enterprise y Education; Home ignora esa directiva), apaga el Programa de mejora de la experiencia, el historial de actividad y su subida, el portapapeles en la nube, el seguimiento de apps abiertas, la voz en línea (el dictado de Win+H deja de funcionar), el aprendizaje de lo que escribes, Bing y el historial en la búsqueda, los archivos recientes de Inicio, Copilot y Click to Do, las funciones de IA en la nube del Bloc de notas y Paint, las tareas de telemetría y lo que Edge envía a Microsoft. Quita la integración de Bing en Inicio.

**Pregunta antes de:** `privacy.location-off`, `privacy.find-my-device-off`, `privacy.error-reporting-off`, `services.diagtrack` (el servicio de telemetría; no usar con Defender for Endpoint), `tasks.mare-backup` (también ejecuta el evaluador de compatibilidad), `tasks.appraiser`, `tasks.appraiser-exp` y `tasks.program-data-updater` (pueden impedir que Windows ofrezca actualizaciones de función) y `apps.copilot`.

**Riesgo alto, solo con `-Include`:** `privacy.diagnostic-data-off` (datos de diagnóstico apagados del todo, solo Enterprise y Education). Úsalo junto con `-Exclude privacy.diagnostic-data-required`, que escribe el mismo valor. También son de riesgo alto `ai.recall-snapshots-off` y `ai.recall-unavailable` (Recall: borran las capturas ya guardadas y deshacer no puede devolverlas); ningún perfil los incluye.

**Qué conserva:** las actualizaciones de seguridad. Las directivas de Edge hacen que Edge diga "Administrado por tu organización": es solo un aviso.

**Administrador:** sí.

## Portátil (`laptop`, alias `portatil`, `portátil`)

**Qué hace:** impide que las apps de la Store corran en segundo plano (puedes permitir apps una a una en Configuración), quita los procesos precargados de Edge, deja de compartir descargas de Windows con otros equipos, pasa a manual los servicios de escáner y de mapas.

**Pregunta antes de:** `performance.background-apps-off` (solo Windows 10: las apps de la Store no avisan con la app cerrada y los fondos de Windows Spotlight pueden dejar de actualizarse) y `power.standby-network-off-battery` (sin red durante la suspensión moderna con batería; solo en equipos con batería y Pro o superior).

**Qué conserva:** SysMain, la suspensión moderna, la hibernación y el plan de energía del fabricante.

**Administrador:** sí.

## Equipo antiguo (`legacy`, alias `equipo-antiguo`, `antiguo`)

**Qué hace:** apaga la transparencia, las animaciones de ventanas, las sombras y la selección translúcida y Aero Peek (algunas se notan al volver a iniciar sesión), Widgets y Noticias e intereses, el análisis del tipo de cada carpeta en el Explorador, las apps de la Store en segundo plano y Edge en segundo plano; desactiva tareas de fondo que pesan en discos mecánicos (WinSAT, diagnósticos, mapas, Carpetas de trabajo) y quita apps preinstaladas que casi nadie usa (Clipchamp, Noticias, Tiempo, Finanzas, Mensajes, Portal de realidad mixta, Películas y TV).

**Pregunta antes de:** `performance.background-apps-off` (solo Windows 10; ver Portátil).

**Qué conserva:** todo lo de Base, Defender, Windows Update y la búsqueda (reducir la indexación todavía no está en el catálogo).

**Administrador:** sí.

## Trabajo (`work`, alias `trabajo`)

**Qué hace:** solo ajustes de tu usuario que no son directivas: privacidad de escritura y voz, lista de idiomas, seguimiento de apps, Bing, historial de búsqueda, archivos recientes y el botón de Copilot.

**Por qué:** en un equipo de una organización las directivas son de TI. Este perfil no toca ninguna y no necesita administrador.

**Qué conserva:** Teams, Outlook (nuevo), OneDrive, Microsoft 365 y Power Automate, aunque lo combines con Liviano.

**Administrador:** no.

## Liviano (`lite`, alias `liviano`)

**Qué hace:** quita lo que Windows 11 LTSC no trae (apps preinstaladas, Widgets, Copilot, Teams, Xbox, Vínculo móvil, Outlook nuevo, Correo y Calendario; OneDrive pregunta antes) y recorta servicios y tareas que LTSC sí mantiene: telemetría, mapas, escáner, Xbox Live, dispositivos conectados, Carpetas de trabajo, WinSAT. La búsqueda queda solo local (sin Bing). Edge sin contenido promocional ni procesos en segundo plano.

**Pregunta antes de:** `services.diagtrack`, `services.geolocation`, `services.connected-devices`, `services.connected-devices-user`, `services.contact-data`, `services.user-data-storage`, `services.user-data-access`, `tasks.appraiser`, `tasks.appraiser-exp`, `tasks.program-data-updater`, `tasks.mare-backup`, `tasks.family-safety-monitor`, `tasks.family-safety-refresh`, `apps.copilot`, `apps.get-help`, `apps.alarms-clock`, `apps.media-player`, `apps.quick-assist`, `apps.phone-link`, `apps.xbox-gaming-app`, `apps.xbox-game-bar`, `apps.outlook-new`, `apps.family-safety`, `apps.mail-calendar`, `apps.msteams` y `apps.onedrive`. Desinstalar OneDrive nunca borra archivos: se niega si Escritorio, Documentos o Imágenes están en OneDrive o si hay archivos solo en la nube.

**Qué conserva:** Defender, las actualizaciones de seguridad, WinRE, la Store y winget (de ellos depende deshacer). Quitar la Store no está en el catálogo.

**¿Más liviano que LTSC?** Es el objetivo, pero todavía no está medido. El método está en [measuring.md](measuring.md).

**Administrador:** sí.
````

- [ ] **Step 4: Escribir `docs/en/profiles.md`**

````markdown
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
- **Administrator:** `base` and `work` only hold settings of your user and apply without elevation. The others bring system changes: open PowerShell as administrator, or leave those tweaks out with `-Exclude`.
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

**What it does:** turns off transparency, window animations, shadows and translucent selection and Aero Peek (some show after signing in again), Widgets and News and interests, File Explorer's folder type detection, Store apps in the background and Edge in the background; turns off background tasks that weigh on hard disks (WinSAT, diagnostics, maps, Work Folders) and removes preinstalled apps that almost nobody uses (Clipchamp, News, Weather, Finance, Messaging, Mixed Reality Portal, Movies & TV).

**Asks before:** `performance.background-apps-off` (Windows 10 only; see Laptop).

**What it keeps:** everything in Base, Defender, Windows Update and search (smaller indexing is not in the catalog yet).

**Administrator:** yes.

## Work (`work`, alias `trabajo`)

**What it does:** only settings of your user that are not policies: typing and speech privacy, language list, app launch tracking, Bing, search history, recent files and the Copilot button.

**Why:** on a machine of an organization the policies belong to IT. This profile touches none and needs no administrator.

**What it keeps:** Teams, Outlook (new), OneDrive, Microsoft 365 and Power Automate, even when combined with Lite.

**Administrator:** no.

## Lite (`lite`, alias `liviano`)

**What it does:** removes what Windows 11 LTSC does not ship (preinstalled apps, Widgets, Copilot, Teams, Xbox, Phone Link, the new Outlook, Mail and Calendar; OneDrive asks first) and trims services and tasks that LTSC keeps: telemetry, maps, scanner, Xbox Live, connected devices, Work Folders, WinSAT. Search stays local (no Bing). Edge without promotional content or background processes.

**Asks before:** `services.diagtrack`, `services.geolocation`, `services.connected-devices`, `services.connected-devices-user`, `services.contact-data`, `services.user-data-storage`, `services.user-data-access`, `tasks.appraiser`, `tasks.appraiser-exp`, `tasks.program-data-updater`, `tasks.mare-backup`, `tasks.family-safety-monitor`, `tasks.family-safety-refresh`, `apps.copilot`, `apps.get-help`, `apps.alarms-clock`, `apps.media-player`, `apps.quick-assist`, `apps.phone-link`, `apps.xbox-gaming-app`, `apps.xbox-game-bar`, `apps.outlook-new`, `apps.family-safety`, `apps.mail-calendar`, `apps.msteams` and `apps.onedrive`. Uninstalling OneDrive never deletes files: it refuses when Desktop, Documents or Pictures are in OneDrive or when files only live in the cloud.

**What it keeps:** Defender, security updates, WinRE, the Store and winget (undo depends on them). Removing the Store is not in the catalog.

**Lighter than LTSC?** That is the goal, but it is not measured yet. The method is in [measuring.md](measuring.md).

**Administrator:** yes.
````

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Docs.Tests.ps1`
Expected: PASS (`Tests Passed: 10, Failed: 0`).

- [ ] **Step 6: Commit**

```bash
git add docs/es/profiles.md docs/en/profiles.md tests/Docs.Tests.ps1
git commit -m "docs: guía de perfiles en español e inglés"
```

---

### Task 27: README, lint y suite completa

**Files:**
- Modify: `README.md`

Cambios: el aviso de "catálogo de ejemplo" pasa a decir que falta el menú y la prueba de extremo a extremo; una tabla de perfiles con alias y si piden administrador; enlaces a las guías, al catálogo y a la lista negra; la afirmación de Liviano frente a LTSC queda **pendiente de medir** con enlace al método; los requisitos dicen que `base` y `work` no piden administrador; los tipos de ajuste mencionan `ac`/`dc` opcionales, el `storeId` `XP`, `requires`, `signOutRequired` y las tres acciones; el JSON de `apply` suma `signOutRequired`; las limitaciones nombran las directivas que Home ignora, las apps sin deshacer y las negativas; el desarrollo menciona la consulta de solo lectura de la GPU y `build/catalog-doc.ps1`.

- [ ] **Step 1: Reemplazar `README.md` completo**

````markdown
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
| `privacy` | `privacidad` | Telemetría al mínimo, historial de actividad, Bing, Copilot, Recall, Edge. / Minimum telemetry, activity history, Bing, Copilot, Recall, Edge. | Sí / Yes |
| `laptop` | `portatil`, `portátil` | Más batería: apps y Edge sin procesos de fondo, sin red en suspensión con batería. / More battery: apps and Edge without background processes, no network in standby on battery. | Sí / Yes |
| `legacy` | `equipo-antiguo`, `antiguo` | Sin transparencia ni animaciones, menos tareas de fondo y apps preinstaladas. / No transparency or animations, fewer background tasks and preinstalled apps. | Sí / Yes |
| `work` | `trabajo` | Solo ajustes de tu usuario, sin directivas; conserva Teams, Outlook y OneDrive. / Only settings of your user, no policies; keeps Teams, Outlook and OneDrive. | No |
| `lite` | `liviano` | Quita lo que LTSC no trae y recorta servicios y tareas; sin tocar Defender, Update ni WinRE. / Removes what LTSC does not ship and trims services and tasks; Defender, Update and WinRE untouched. | Sí / Yes |

Guía de cada perfil / Guide to each profile: [docs/es/profiles.md](docs/es/profiles.md) · [docs/en/profiles.md](docs/en/profiles.md). Catálogo completo / Full catalog: [docs/es/catalog.md](docs/es/catalog.md) · [docs/en/catalog.md](docs/en/catalog.md). Lo que nunca se aplica / What is never applied: [docs/es/blacklist.md](docs/es/blacklist.md) · [docs/en/blacklist.md](docs/en/blacklist.md).

**Liviano frente a LTSC / Lite versus LTSC:** el objetivo es que Liviano quede por debajo de una instalación limpia de Windows 11 LTSC 2024 en RAM, procesos y servicios en reposo. **Todavía no está medido**; el método está en [docs/es/measuring.md](docs/es/measuring.md). / The goal is for Lite to end below a clean Windows 11 LTSC 2024 install in idle RAM, processes and services. **It is not measured yet**; the method is in [docs/en/measuring.md](docs/en/measuring.md).

## Requisitos / Requirements

- Windows 10 u 11 (build 19041 o posterior) con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1. Windows Server y builds anteriores se rechazan salvo con `-Force`.
- Windows 10 or 11 (build 19041 or later) with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1. Windows Server and older builds are refused unless `-Force` is given.
- Los ajustes de sistema necesitan PowerShell como administrador. Sin elevar, un plan que contenga cualquier cambio de sistema se rechaza completo (no se aplica nada): usar `-Exclude` para dejar fuera esos ajustes o abrir PowerShell como administrador. Los perfiles `base` (siempre aplicado) y `work` solo tienen ajustes de registro de usuario (`HKCU`) y se aplican sin elevar; los demás traen cambios de sistema.
- System-wide tweaks need PowerShell as administrator. Without elevation, a plan that contains any system-level change is refused entirely (nothing is applied): use `-Exclude` to leave those tweaks out or open PowerShell as administrator. The `base` (always applied) and `work` profiles only hold user registry tweaks (`HKCU`) and apply without elevation; the others bring system changes.
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
- **Acciones (`action`):** el cargador analiza los scripts de `actions/` sin ejecutarlos y solo acepta definiciones de funciones con nombres del contrato. `onedrive` desinstala OneDrive sin borrar archivos y se niega (sin cambiar nada) si Escritorio, Documentos o Imágenes están en OneDrive o hay archivos solo en la nube: el ajuste queda `skipped` con el motivo; deshacer lo reinstala con `winget`. `gaming-hags` solo activa la GPU acelerada si el driver la admite. `gaming-windowed-optimizations` cambia solo su opción dentro de la lista de preferencias de DirectX. Un script que no se pueda cargar no rompe el resto: se informa como advertencia y solo falla la validación de los ajustes que lo usan (`-Status`, `-Undo`, `-Health` y `-Measure` siguen funcionando).
  **Actions (`action`):** the loader parses the scripts in `actions/` without running them and only accepts function definitions with contract names. `onedrive` uninstalls OneDrive without deleting files and refuses (changing nothing) when Desktop, Documents or Pictures are in OneDrive or files only live in the cloud: the tweak ends `skipped` with the reason; undo reinstalls it with `winget`. `gaming-hags` only turns on GPU scheduling when the driver supports it. `gaming-windowed-optimizations` changes only its own choice inside the DirectX preference list. A script that cannot be loaded does not break the rest: it is reported as a warning and only the validation of the tweaks that use it fails (`-Status`, `-Undo`, `-Health` and `-Measure` keep working).
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
| `apply` | `runId`, `runDir`, `finishedAt`, `environment`, `restorePoint`, `rebootRequired`, `signOutRequired`, `summary` (`applied`, `partial`, `notApplied`, `failed`, `skipped`, `journalErrors`), `results` (`id`, `title`, `status`, `reason`, `error`, `detail`, `rebootRequired`, `signOutRequired`) |
| `status` | `items` (`id`, `title`, `status`, `runId`) |
| `undo` | `runId`, `rebootRequired`, `results` (los de `apply` salvo `signOutRequired` / those of `apply` except `signOutRequired`), `summary` (`restored`, `failed`, `skipped`) |
| `health` | `startedAt`, `finishedAt`, `repairRequested`, `repairRan`, `before`, `after` (`sfc`, `componentStore`, `corruptComponents`), `recommendation`, `rebootRecommended` |
| `measure` | `id`, `path`, `measurement` (`takenAt`, `idleSeconds`, `environment`, `metrics`, `notes`), `comparison` (`againstId`, `items` con `metric`, `before`, `after`, `delta`; nulo sin `-Compare` / null without `-Compare`) |
| `error` | `message`, `details` |

## Limitaciones conocidas / Known limitations

- Varias directivas no rigen en Windows Home (Widgets, telemetría mínima, historial de actividad...): en Home el plan las omite como "no aplica". La lista está en [docs/es/catalog.md](docs/es/catalog.md).
  Several policies do not apply on Windows Home (Widgets, minimum telemetry, activity history...): on Home the plan skips them as "does not apply". The list is in [docs/en/catalog.md](docs/en/catalog.md).
- Las apps que winget no puede reinstalar (Solitaire, Tips, Mapas, People y otras) no están en el catálogo: quitarlas no se podría deshacer.
  Apps that winget cannot reinstall (Solitaire, Tips, Maps, People and others) are not in the catalog: removing them could not be undone.
- Un ajuste que se niega a cambiar algo (por ejemplo OneDrive con carpetas en la nube) queda omitido y no cuenta como fallo: el código de salida sigue siendo `0` si todo lo demás se aplicó.
  A tweak that refuses to change something (for example OneDrive with folders in the cloud) is skipped and does not count as a failure: the exit code stays `0` if everything else was applied.
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
````

- [ ] **Step 2: Lint**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`.

- [ ] **Step 3: Suite completa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1`
Expected: PASS (`Tests Passed: 877, Failed: 0, Skipped: 1`). El salto es la prueba de la carpeta de máquina que ya se saltaba antes de este plan.

- [ ] **Step 4: Las páginas generadas siguen al día**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1` y luego `git status --short docs`
Expected: sin cambios en `docs/es/catalog.md` ni `docs/en/catalog.md`.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: README del Plan 3, perfiles y documentación"
```

---

## Autorrevisión

**Cobertura de las decisiones aprobadas:**

| Decisión | Dónde |
|---|---|
| 1. `base` sin administrador; `services.retail-demo` a `lite`; Edge fuera de `base` | Task 7 (`profiles/base.json`, prueba `keeps base to user tweaks...`), Task 22 (`lite` incluye `services.retail-demo`; ninguna directiva de Edge en `base`) |
| 2. Ediciones según Microsoft; `AllowTelemetry` 1 y 0; DiagTrack con `ask`; rutas sin documentar fuera | Task 8 (`privacy.diagnostic-data-required`/`-off`, prueba de ediciones), Task 9 (`ads.consumer-features`, `ads.start-hide-recommended-policy`), Task 13 (`services.diagtrack`) |
| 3. Apps solo con deshacer; `XP` + 12; Teams; `ask` en las apps listadas | Task 2, Task 21 (prueba `asks before removing the apps people often use`), Task 24 (`apps-no-undo` en `excluded.json`) |
| 4a-4e. Cambios del motor | Tasks 2, 3, 4, 5 y 6, cada una con pruebas que fallan primero |
| 4f. Ideas sin implementar | Sección 11 de la especificación (Task 1) y grupo `engine-limits` de `excluded.json` (Task 24) |
| 5. Acciones; `power-mode-overlay` y `dev-defender-performance-mode` fuera | Tasks 16, 17 y 20; "Acciones descartadas" y grupo `unverified` de `excluded.json` |
| 6. Ocho perfiles, alias, `keep`, nada de virtualización, `high` solo con `-Include` | Task 22 (prueba `The eight profiles`) y "Blacklist guard" (Task 7) |
| 7. Lista negra, guías, catálogo generado y "No incluido" | Tasks 23, 24 y 26 |
| 8. Pruebas de calidad (fuentes, ids únicos, `include`/`keep`, `keep` existe, `base` de usuario, sin `high`, apps que preguntan documentadas, `requires`, scripts de acciones, UTF-8, textos es/en, catálogo válido, planificación de cada perfil en varios entornos) | `tests/CatalogQuality.Tests.ps1` (Tasks 7 y 22), `tests/CatalogContent.Tests.ps1` (Tasks 8 a 21), `tests/Docs.Tests.ps1` (`names every tweak that asks first...`, Task 26) |
| 9. Método de medición manual, sin automatizar; README dice "pendiente" | Tasks 25 y 27 |
| 10. README y sección 11 | Tasks 1 y 27 |
| 11. Verificación de solo lectura | Último paso de las Tasks 8 a 15, 18, 19 y 21 (estados reales del equipo de verificación) y Task 22, Step 5 (`-WhatIf` de los ocho perfiles) |

**Recuentos del catálogo:**

| Archivo | Ajustes | Tipos | De usuario | Preguntan | Riesgo alto |
|---|---|---|---|---|---|
| `privacy.json` | 18 | 18 registry | 9 | 3 | 1 |
| `ads.json` | 28 | 28 registry | 26 | 0 | 0 |
| `ui.json` | 12 | 12 registry | 10 | 0 | 0 |
| `ai.json` | 10 | 9 registry, 1 service | 4 | 2 | 2 |
| `edge.json` | 17 | 17 registry | 0 | 0 | 0 |
| `services.json` | 10 | 10 service | 0 | 7 | 0 |
| `tasks.json` | 21 | 21 task | 0 | 6 | 0 |
| `performance.json` | 3 | 3 registry | 2 | 1 | 0 |
| `power.json` | 3 | 2 powercfg, 1 registry | 0 | 2 | 0 |
| `gaming.json` | 11 | 9 registry, 2 action | 8 | 1 | 1 |
| `dev.json` | 3 | 3 registry | 0 | 1 | 0 |
| `apps.json` | 30 | 29 appx, 1 action | 0 | 13 | 0 |
| **Total** | **166** | | **59** | **36** | **4** |

Perfiles: `base` 21, `dev` 6, `gaming` 12 (+6 `keep`), `privacy` 55, `laptop` 7, `legacy` 30, `work` 10 (+5 `keep`), `lite` 105.

**Búsqueda de marcadores pendientes:** no quedan "TBD", "TODO", "similar a la Task N" ni pasos sin código. Cada archivo nuevo va completo; cada cambio a un archivo existente da el texto exacto a reemplazar o el punto exacto donde agregar.

**Consistencia de ids entre catálogo, perfiles y `keep`:** `Test-TuneupProfileSet` (que ya exige que todo id de `include` y `keep` exista y que ningún `include` sea `high`) pasa con los ocho perfiles; `tests/CatalogQuality.Tests.ps1` comprueba además que ningún id esté en `include` y `keep` del mismo perfil, que `gaming` + `lite` conserve los 6 ids de Xbox y `work` + `lite` los 5 de trabajo; `tests/CatalogContent.Tests.ps1` fija los ids de cada archivo en orden; `tests/Docs.Tests.ps1` exige que la guía nombre cada id que pregunta y cada id de riesgo alto; `tests/CatalogDoc.Tests.ps1` exige que el catálogo generado tenga una sección por id y que `excluded.json` no nombre un paquete que el catálogo quita.

**Consistencia de nombres:**

- Campos nuevos del catálogo: `requires` (`battery`, `no-battery`) y `signOutRequired` (booleano), validados en `Test-TuneupTweak`; el motivo `not-applicable-hardware` tiene texto `reason.*` en los dos idiomas.
- `New-TuneupOutcome -Refused` (campo `refused`) lo emite solo `actions/onedrive.ps1`, con los motivos `onedrive-known-folders` y `onedrive-online-only-files`, que tienen texto en los dos idiomas (lo verifica `tests/I18nCoverage.Tests.ps1`, que desde la Task 5 lee `actions/`).
- Resultados de aplicar: `id, title, status, reason, error, detail, rebootRequired, signOutRequired`; reporte de aplicar: `rebootRequired` y `signOutRequired`; texto `signOut` en los dos idiomas.
- Acciones y sus funciones: `gaming-windowed-optimizations` → `GamingWindowedOptimizations` (ayudantes `Value`, `Tweak`, `Token`), `gaming-hags` → `GamingHags` (`Value`, `Tweak`, `Capability`, `Supported`), `onedrive` → `Onedrive` (`Root`, `KnownFolder`, `Redirected`, `OnlineOnly`, `Install`, `OtherProfile`, `Removal`). Ningún ayudante contiene `Action` después de `ActionHelper`; los tres scripts cargan sin error (`finds the script of every action tweak in actions/ and loads it`).

**Correcciones hechas durante la revisión (al ejecutar el plan en una copia):** `PSReviewUnusedParameter` marcaba el `$Tweak` sin usar en los `Get`/`Set` de las acciones, así que los ayudantes reciben `-Tweak`; un `Mock` en el `BeforeEach` también reemplaza la función en la prueba que comprueba la ruta real, por eso esa prueba va en su propio `Describe`; `Should -BeLike` interpreta el acento grave como escape, así que las pruebas de documentación buscan texto con `.Contains()`; la primera versión de "No incluido" mezclaba los dos idiomas en un mismo nombre, por eso `name` admite `{ "es", "en" }`; la prueba de enlaces de la documentación va en la última tarea de documentación, cuando todas las páginas existen.
