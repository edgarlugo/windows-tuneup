# windows-tuneup — Plan 1: núcleo del motor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un `tuneup.ps1` funcional que carga un catálogo validado, arma un plan por perfiles, aplica ajustes de registro, servicios y tareas programadas guardando antes el estado anterior, y permite ver el estado y deshacer, con salida para personas o JSON.

**Architecture:** Módulo `engine/Tuneup.psm1` que carga archivos `.ps1` de una responsabilidad cada uno (entorno, catálogo, planificador, manejadores, estado, ejecutor, deshacer, salida). Los manejadores comparten el contrato Get/Test/Set/Restore y un despachador elige según `type`. El planificador no toca el sistema: recibe un scriptblock para consultar el estado. `tuneup.ps1` solo orquesta.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.6+, PSScriptAnalyzer, GitHub Actions (`windows-latest`).

**Especificación:** `docs/superpowers/specs/2026-09-30-windows-tuneup-design.md`

---

## Hoja de ruta (5 planes)

| Plan | Alcance | Depende de |
|---|---|---|
| **1. Núcleo del motor (este)** | Entorno, catálogo y perfiles con validación, planificador, manejadores `registry`/`service`/`task`, diario, ejecutor, `-Status`, `-Undo`, punto de restauración, CLI por parámetros con `-Json`, i18n mínimo, CI | — |
| 2. Manejadores restantes y salud | `appx` (usuario + provisionado, reinstalación por `storeId`), `capability`, `feature`, `powercfg`, `action`; `-Health` (SFC/DISM con resumen); `-Measure` y `-Compare` | 1 |
| 3. Catálogo y perfiles reales | Investigación de cada ajuste contra Win11Debloat, Sophia, winutil, privacy.sexy y Microsoft Learn; los 8 perfiles; lista negra; docs `es/` y `en/`; catálogo generado para la documentación | 1, 2 |
| 4. Menú interactivo y distribución | Menú en consola con preguntas `ask`; avisos con confirmación por reinicio pendiente, menos de 2 GB libres y restauración del sistema desactivada (con opción de activarla); Ctrl+C limpio; release zip + `SHA256SUMS`; línea `irm` fijada a versión; Windows Sandbox `tests/sandbox/e2e.wsb` | 1–3 |
| 5. Skill de Claude | `claude/skills/windows-tuneup/SKILL.md` con los modos asistido y directo, inventario, barreras | 1–4 |

## Convenciones de este plan

- **Código, comentarios, identificadores y errores para desarrolladores en inglés.** Los textos para el usuario van en `i18n/es.json` y `i18n/en.json`. Razón: el repo es público y Windows PowerShell 5.1 lee los `.ps1` sin BOM como ANSI, así que todo `.ps1`/`.psm1`/`.psd1` debe ser **ASCII** (lo verifica una prueba).
- **Funciones emiten elementos a la salida; quien llama envuelve con `@()`.** Nunca `return ,$array`.
- **`ConvertTo-Json` siempre con `-Depth 10`** (el valor por defecto de 5.1 es 2 y trunca).
- **Comparaciones con null: `$null -eq $x`.**
- Los parámetros de arreglo que pueden venir vacíos llevan `[AllowEmptyCollection()]`.
- Todas las pruebas corren en **Windows PowerShell 5.1**: `powershell -NoProfile -File build/test.ps1`.
- Directorio del repo: `C:\Users\Edgar\Documents\GitHub\windows-tuneup` (comandos relativos a esa raíz).
- Commits **sin** línea `Co-Authored-By` (preferencia del autor).

## Desviaciones menores respecto de la especificación

| Especificación | Plan 1 | Motivo |
|---|---|---|
| Campo `category` en cada ajuste | La categoría es el primer segmento del `id` y debe coincidir con el nombre del archivo (`privacy.json` → `privacy.*`) | Una sola fuente de verdad |
| `schemas/*.schema.json` | Validación en `engine/Catalog.ps1` | PowerShell 5.1 no tiene `Test-Json -Schema`; los esquemas para editores se generan en el Plan 3 |
| Módulos `.psm1` separados | Un `Tuneup.psm1` que carga `.ps1` por responsabilidad | Un solo nombre de módulo para `Mock -ModuleName Tuneup` |
| IDs de perfil en español | IDs en inglés (`base`, `dev`, `gaming`…) con `aliases` en ambos idiomas | Neutralidad; `-Profile Desarrollo` funciona por alias |
| Punto de restauración siempre | Solo si el plan tiene ajustes `machine` | Los cambios de usuario no lo necesitan y así las pruebas no crean puntos |

## Estructura de archivos del Plan 1

```
windows-tuneup/
├── tuneup.ps1                         Orquestación de la CLI
├── engine/
│   ├── Tuneup.psm1                    Carga todos los .ps1 y exporta
│   ├── I18n.ps1                       Textos y títulos en el idioma activo
│   ├── Environment.ps1                Edición, build, empresa, admin, batería, reinicio
│   ├── Catalog.ps1                    Carga y validación de catálogo y perfiles
│   ├── Planner.ps1                    Perfiles -> plan con motivos
│   ├── Dispatch.ps1                   Elige manejador por type
│   ├── StateSecurity.ps1              ACL de la carpeta de máquina, creación atómica, confianza
│   ├── StateFiles.ps1                 Raíces, archivos de estado, JSON y diario
│   ├── Runs.ps1                       Corridas, run.json, listado, resolución, filtro por usuario
│   ├── Executor.ps1                   Diario -> aplicar -> verificar
│   ├── Undo.ps1                       Deshacer y estado actual
│   ├── RestorePoint.ps1               Punto de restauración
│   ├── Output.ps1                     Reportes para personas y JSON
│   └── handlers/
│       ├── Registry.ps1
│       ├── Service.ps1
│       └── Task.ps1
├── i18n/es.json, i18n/en.json
├── catalog/privacy.json, ui.json, services.json, tasks.json   (semilla)
├── profiles/base.json, privacy.json                           (semilla)
├── tests/
│   ├── TestHelpers.ps1
│   ├── Repo.Tests.ps1, I18n.Tests.ps1, Environment.Tests.ps1, Catalog.Tests.ps1
│   ├── Registry.Tests.ps1, Service.Tests.ps1, Task.Tests.ps1, Dispatch.Tests.ps1
│   ├── Planner.Tests.ps1, StateSecurity.Tests.ps1, StateFiles.Tests.ps1, Runs.Tests.ps1
│   ├── Executor.Tests.ps1, Undo.Tests.ps1
│   ├── RestorePoint.Tests.ps1, Output.Tests.ps1, Cli.Tests.ps1
│   └── fixtures/catalog/test.json, fixtures/profiles/base.json, extra.json, nested.json, system.json
├── build/test.ps1, build/lint.ps1, build/PSScriptAnalyzerSettings.psd1
├── .github/workflows/ci.yml
├── README.md, LICENSE, .gitignore, .gitattributes
```

---

### Task 0: Herramientas y andamiaje

**Files:**
- Create: `.gitignore`, `.gitattributes`, `LICENSE`, `README.md`
- Create: `build/test.ps1`, `build/lint.ps1`, `build/PSScriptAnalyzerSettings.psd1`
- Create: `.github/workflows/ci.yml`
- Test: `tests/Repo.Tests.ps1`

- [ ] **Step 1: Instalar Pester 5 y PSScriptAnalyzer para el usuario actual**

Run (en Windows PowerShell 5.1):
```powershell
powershell -NoProfile -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null; Install-Module Pester -MinimumVersion 5.6.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck; Install-Module PSScriptAnalyzer -Scope CurrentUser -Force; Get-Module -ListAvailable Pester, PSScriptAnalyzer | Select-Object Name, Version"
```
Expected: aparece `Pester 5.x` y `PSScriptAnalyzer 1.x` (además del Pester 3.4.0 del sistema, que no se usa).

- [ ] **Step 2: Archivos base**

`.gitignore`:
```
TestResults/
*.log
```

`.gitattributes`:
```
* text=auto
*.ps1 text eol=crlf
*.psm1 text eol=crlf
*.psd1 text eol=crlf
*.json text eol=crlf
*.md text eol=crlf
```

`LICENSE`:
```
MIT License

Copyright (c) 2026 Edgar Lugo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`README.md` (provisional; la versión completa es del Plan 3):
```markdown
# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> Estado: en desarrollo (Plan 1: núcleo del motor). No usar todavía en equipos reales.
> Status: work in progress. Do not use on real machines yet.

## Uso / Usage

```powershell
.\tuneup.ps1 -Profile base -WhatIf     # ver el plan / show the plan
.\tuneup.ps1 -Profile base,privacy     # aplicar / apply
.\tuneup.ps1 -Status                   # estado / status
.\tuneup.ps1 -Undo last                # deshacer / undo
```

Licencia / License: MIT
```

- [ ] **Step 3: Scripts de build**

`build/test.ps1`:
```powershell
param([string]$Path)

$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.6.0 -MaximumVersion 5.99.99

$root = Split-Path $PSScriptRoot -Parent
$resultsDir = Join-Path $root 'TestResults'
if (-not (Test-Path -LiteralPath $resultsDir)) { New-Item -ItemType Directory -Path $resultsDir | Out-Null }

$config = New-PesterConfiguration
$config.Run.Path = $(if ($Path) { $Path } else { Join-Path $root 'tests' })
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $resultsDir 'pester.xml'
Invoke-Pester -Configuration $config
```

`build/PSScriptAnalyzerSettings.psd1`:
```powershell
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # tuneup.ps1 is an interactive console tool; Write-Host is intended.
        'PSAvoidUsingWriteHost',
        # Confirmation is asked once for the whole plan, not per function.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
```

`build/lint.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
Import-Module PSScriptAnalyzer

$root = Split-Path $PSScriptRoot -Parent
$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
$targets = @(
    (Join-Path $root 'tuneup.ps1'),
    (Join-Path $root 'engine'),
    (Join-Path $root 'build')
) | Where-Object { Test-Path -LiteralPath $_ }

$findings = @(foreach ($target in $targets) {
    Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settings
})
if ($findings.Count) {
    $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 220 | Write-Output
    exit 1
}
Write-Output 'PSScriptAnalyzer: no findings'
```

- [ ] **Step 4: Prueba de higiene del repo**

`tests/Repo.Tests.ps1`:
```powershell
Describe 'Repository hygiene' {
    BeforeAll {
        $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    }

    It 'keeps PowerShell files ASCII so Windows PowerShell 5.1 reads them correctly' {
        $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' -and $_.FullName -notmatch '\\\.git\\' }
        $bad = foreach ($file in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            if ([Array]::Exists($bytes, [Predicate[byte]] { param($b) $b -gt 127 })) { $file.FullName }
        }
        ($bad -join ', ') | Should -BeNullOrEmpty
    }

    It 'has JSON files that parse' {
        $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.json' |
            Where-Object { $_.FullName -notmatch '\\\.git\\' }
        foreach ($file in $files) {
            { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Should -Not -Throw -Because $file.FullName
        }
    }
}
```

- [ ] **Step 5: CI**

`.github/workflows/ci.yml`:
```yaml
name: ci
on:
  push:
  pull_request:
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
          Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
      - name: Lint
        shell: powershell
        run: .\build\lint.ps1
      - name: Test
        shell: powershell
        run: .\build\test.ps1
```

- [ ] **Step 6: Correr la prueba**

Run: `powershell -NoProfile -File build/test.ps1`
Expected: `Tests Passed: 2, Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore .gitattributes LICENSE README.md build .github tests/Repo.Tests.ps1
git commit -m "chore: andamiaje, CI y prueba de higiene"
```

---

### Task 1: Cargador del módulo e i18n

**Files:**
- Create: `engine/Tuneup.psm1`, `engine/I18n.ps1`, `i18n/es.json`, `i18n/en.json`
- Create: `tests/TestHelpers.ps1`
- Test: `tests/I18n.Tests.ps1`

- [ ] **Step 1: Ayudantes de prueba**

`tests/TestHelpers.ps1`:
```powershell
function New-TestTweak {
    param(
        [string]$Id = 'test.sample',
        [string]$Type = 'registry',
        [string]$Scope = 'user',
        [string]$Risk = 'low',
        [bool]$Ask = $false,
        [string[]]$Families = @('10', '11'),
        [int]$MinBuild = 19041,
        [string[]]$Editions = @('Home', 'Pro', 'Enterprise', 'Education'),
        [object]$Set = $null,
        [bool]$RebootRequired = $false
    )
    if ($null -eq $Set) {
        $Set = [pscustomobject]@{ path = 'HKCU:\Software\windows-tuneup-test'; name = 'Sample'; kind = 'DWord'; value = 1 }
    }
    [pscustomobject]@{
        id             = $Id
        title          = [pscustomobject]@{ es = "Titulo $Id"; en = "Title $Id" }
        why            = [pscustomobject]@{ es = 'Motivo'; en = 'Reason' }
        risk           = $Risk
        ask            = $Ask
        os             = [pscustomobject]@{ families = $Families; minBuild = $MinBuild; editions = $Editions }
        type           = $Type
        scope          = $Scope
        set            = $Set
        rebootRequired = $RebootRequired
        sources        = @('https://example.com/source')
    }
}

function New-TestEnvironment {
    param(
        [string]$Family = '11',
        [int]$Build = 26100,
        [string]$Edition = 'Pro',
        [bool]$IsManaged = $false
    )
    [pscustomobject]@{
        Family = $Family; Build = $Build; UBR = 0; Edition = $Edition; IsServer = $false
        IsManaged = $IsManaged; IsAdmin = $true; HasBattery = $false; PendingReboot = $false
    }
}

function New-TestProfile {
    param(
        [string]$Id,
        [string[]]$Include = @(),
        [string[]]$Keep = @(),
        [string[]]$Aliases = @()
    )
    [pscustomobject]@{
        id          = $Id
        aliases     = $Aliases
        title       = [pscustomobject]@{ es = $Id; en = $Id }
        description = [pscustomobject]@{ es = 'Descripcion'; en = 'Description' }
        include     = $Include
        keep        = $Keep
    }
}
```

- [ ] **Step 2: Prueba que falla**

`tests/I18n.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:I18nRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
}

Describe 'i18n' {
    It 'defines the same keys in es and en' {
        $es = (Get-Content -LiteralPath (Join-Path $I18nRoot 'es.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object
        $en = (Get-Content -LiteralPath (Join-Path $I18nRoot 'en.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object
        (Compare-Object -ReferenceObject $es -DifferenceObject $en | ForEach-Object { $_.InputObject }) -join ', ' | Should -BeNullOrEmpty
    }

    It 'formats texts with arguments' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        Get-TuneupText -Key 'plan.header' -Format 3, 1 | Should -Be 'Plan: 3 to apply, 1 skipped'
    }

    It 'returns the key when the text does not exist' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        Get-TuneupText -Key 'no.such.key' | Should -Be 'no.such.key'
    }

    It 'picks the tweak title in the active language' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'es'
        Get-TuneupTitle -Tweak (New-TestTweak -Id 'test.a') | Should -Be 'Titulo test.a'
    }

    It 'falls back to English for an unknown language' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'fr'
        Get-TuneupLang | Should -Be 'en'
    }
}
```

- [ ] **Step 3: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/I18n.Tests.ps1`
Expected: FAIL, el módulo `engine\Tuneup.psm1` no existe.

- [ ] **Step 4: Implementación**

`engine/Tuneup.psm1`:
```powershell
$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
foreach ($folder in @($engineRoot, (Join-Path $engineRoot 'handlers'))) {
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.ps1' | Sort-Object Name) {
        . $file.FullName
    }
}
Export-ModuleMember -Function *
```

`engine/I18n.ps1`:
```powershell
$script:TuneupLang = 'en'
$script:TuneupStrings = @{}

function Initialize-TuneupI18n {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Lang
    )
    if (-not $Lang) {
        $Lang = $(if ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') { 'es' } else { 'en' })
    }
    $file = Join-Path $Root "$Lang.json"
    if (-not (Test-Path -LiteralPath $file)) {
        $Lang = 'en'
        $file = Join-Path $Root 'en.json'
    }
    $json = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:TuneupStrings = @{}
    foreach ($property in $json.PSObject.Properties) {
        $script:TuneupStrings[$property.Name] = [string]$property.Value
    }
    $script:TuneupLang = $Lang
}

function Get-TuneupLang {
    $script:TuneupLang
}

function Get-TuneupText {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$Format = @()
    )
    $text = $script:TuneupStrings[$Key]
    if ($null -eq $text) { return $Key }
    if ($Format.Count) { return ($text -f $Format) }
    $text
}

function Get-TuneupTitle {
    param([Parameter(Mandatory)]$Tweak)
    $title = $Tweak.title.($script:TuneupLang)
    if (-not $title) { $title = $Tweak.title.en }
    if (-not $title) { $title = $Tweak.id }
    $title
}
```

`i18n/es.json`:
```json
{
  "err.catalog": "El catálogo o los perfiles tienen errores:",
  "err.server": "windows-tuneup no está pensado para Windows Server. Usa -Force solo si sabes lo que haces.",
  "err.unsupported": "Esta versión de Windows no está soportada (mínimo Windows 10 20H1, build 19041). Usa -Force bajo tu responsabilidad.",
  "err.notAdmin": "Hay cambios de sistema en el plan: abre PowerShell como administrador.",
  "err.jsonNeedsYes": "Con -Json hay que confirmar con -Yes (o revisar primero con -WhatIf).",
  "err.unknownProfile": "Perfil desconocido: {0}",
  "err.unknownTweak": "Ajuste desconocido: {0}",
  "err.tweakNotInRun": "El ajuste {0} no está en esa corrida.",
  "err.runAlreadyUndone": "La corrida {0} ya estaba deshecha.",
  "err.badArgs": "Combinación de parámetros no válida: {0}",
  "undo.none": "No hay corridas para deshacer.",
  "plan.header": "Plan: {0} para aplicar, {1} omitidos",
  "plan.apply": "  + {0} [{1}]",
  "plan.skip": "  - {0}: {1}",
  "plan.needsAdmin": "Para aplicar los cambios de sistema, abre PowerShell como administrador.",
  "nothing": "No hay cambios pendientes.",
  "confirm": "¿Aplicar {0} cambios? (s/n)",
  "confirm.pattern": "^(s|si|sí|y|yes)$",
  "aborted": "Cancelado. No se cambió nada.",
  "risk.low": "riesgo bajo",
  "risk.medium": "riesgo medio",
  "risk.high": "riesgo alto",
  "reason.excluded": "excluido con -Exclude",
  "reason.kept-by-profile": "un perfil elegido lo mantiene",
  "reason.incompatible": "no aplica a esta versión o edición de Windows",
  "reason.managed-device": "equipo administrado por una organización: no se tocan políticas",
  "reason.high-risk-not-requested": "riesgo alto: solo se aplica si lo pides con -Include",
  "reason.needs-confirmation": "requiere confirmación: pídelo con -Include",
  "reason.already-applied": "ya estaba aplicado",
  "reason.not-present": "no existe en este equipo",
  "reason.state-unreadable": "no se pudo leer su estado actual",
  "reason.journal-error": "no se pudo guardar el respaldo, así que no se aplicó",
  "reason.already-undone": "ya se había deshecho",
  "reason.other-user": "pertenece a otro usuario",
  "status.applied": "aplicado",
  "status.not-applied": "sin efecto (Windows o una política lo revirtió)",
  "status.failed": "falló",
  "status.skipped": "omitido",
  "status.restored": "restaurado",
  "status.ok": "vigente",
  "status.drift": "revertido desde que se aplicó",
  "status.not-present": "ya no existe",
  "status.unknown": "no se pudo leer",
  "result.line": "  [{0}] {1}",
  "summary": "Aplicados: {0} · Sin efecto: {1} · Fallidos: {2} · Omitidos: {3}",
  "run.saved": "Corrida {0} guardada en {1}. Para deshacer: .\\tuneup.ps1 -Undo {0}",
  "reboot": "Reinicia el equipo para completar los cambios.",
  "restore.created": "Punto de restauración creado.",
  "restore.skipped-recent": "Windows no creó un punto de restauración nuevo porque ya hay uno reciente. Los cambios igual se pueden deshacer con -Undo.",
  "restore.failed": "No se pudo crear el punto de restauración (¿está desactivada la restauración del sistema?). Los cambios igual se pueden deshacer con -Undo.",
  "restore.unavailable": "La restauración del sistema no está disponible en este equipo. Los cambios igual se pueden deshacer con -Undo.",
  "restore.not-needed": "Solo hubo cambios de usuario: no hacía falta un punto de restauración.",
  "status.header": "Ajustes aplicados por windows-tuneup:",
  "status.empty": "windows-tuneup no ha aplicado ajustes en este equipo.",
  "undo.header": "Deshaciendo la corrida {0}:",
  "undo.summary": "Restaurados: {0} · Fallidos: {1} · Omitidos: {2}"
}
```

`i18n/en.json`:
```json
{
  "err.catalog": "The catalog or the profiles have errors:",
  "err.server": "windows-tuneup is not meant for Windows Server. Use -Force only if you know what you are doing.",
  "err.unsupported": "This Windows version is not supported (minimum Windows 10 20H1, build 19041). Use -Force at your own risk.",
  "err.notAdmin": "The plan has system changes: open PowerShell as administrator.",
  "err.jsonNeedsYes": "With -Json you must confirm with -Yes (or review first with -WhatIf).",
  "err.unknownProfile": "Unknown profile: {0}",
  "err.unknownTweak": "Unknown tweak: {0}",
  "err.tweakNotInRun": "Tweak {0} is not part of that run.",
  "err.runAlreadyUndone": "Run {0} was already undone.",
  "err.badArgs": "Invalid parameter combination: {0}",
  "undo.none": "There are no runs to undo.",
  "plan.header": "Plan: {0} to apply, {1} skipped",
  "plan.apply": "  + {0} [{1}]",
  "plan.skip": "  - {0}: {1}",
  "plan.needsAdmin": "To apply the system changes, open PowerShell as administrator.",
  "nothing": "Nothing to change.",
  "confirm": "Apply {0} changes? (y/n)",
  "confirm.pattern": "^(y|yes)$",
  "aborted": "Cancelled. Nothing was changed.",
  "risk.low": "low risk",
  "risk.medium": "medium risk",
  "risk.high": "high risk",
  "reason.excluded": "excluded with -Exclude",
  "reason.kept-by-profile": "a selected profile keeps it",
  "reason.incompatible": "does not apply to this Windows version or edition",
  "reason.managed-device": "managed by an organization: policies are left alone",
  "reason.high-risk-not-requested": "high risk: only applied when you ask for it with -Include",
  "reason.needs-confirmation": "needs confirmation: ask for it with -Include",
  "reason.already-applied": "already applied",
  "reason.not-present": "not present on this machine",
  "reason.state-unreadable": "its current state could not be read",
  "reason.journal-error": "the backup could not be saved, so it was not applied",
  "reason.already-undone": "already undone",
  "reason.other-user": "belongs to another user",
  "status.applied": "applied",
  "status.not-applied": "no effect (Windows or a policy reverted it)",
  "status.failed": "failed",
  "status.skipped": "skipped",
  "status.restored": "restored",
  "status.ok": "in place",
  "status.drift": "reverted since it was applied",
  "status.not-present": "no longer present",
  "status.unknown": "could not be read",
  "result.line": "  [{0}] {1}",
  "summary": "Applied: {0} · No effect: {1} · Failed: {2} · Skipped: {3}",
  "run.saved": "Run {0} saved in {1}. To undo: .\\tuneup.ps1 -Undo {0}",
  "reboot": "Restart the computer to finish the changes.",
  "restore.created": "Restore point created.",
  "restore.skipped-recent": "Windows did not create a new restore point because a recent one exists. Changes can still be undone with -Undo.",
  "restore.failed": "The restore point could not be created (is System Restore turned off?). Changes can still be undone with -Undo.",
  "restore.unavailable": "System Restore is not available on this machine. Changes can still be undone with -Undo.",
  "restore.not-needed": "Only user settings changed: no restore point was needed.",
  "status.header": "Tweaks applied by windows-tuneup:",
  "status.empty": "windows-tuneup has not applied any tweak on this machine.",
  "undo.header": "Undoing run {0}:",
  "undo.summary": "Restored: {0} · Failed: {1} · Skipped: {2}"
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/I18n.Tests.ps1`
Expected: 5 passed.

- [ ] **Step 6: Commit**

```bash
git add engine/Tuneup.psm1 engine/I18n.ps1 i18n tests/TestHelpers.ps1 tests/I18n.Tests.ps1
git commit -m "feat: cargador del módulo e i18n es/en"
```

---

### Task 2: Detección del entorno

**Files:**
- Create: `engine/Environment.ps1`
- Test: `tests/Environment.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Environment.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
}

Describe 'ConvertTo-TuneupEdition' {
    It 'maps <EditionId> to <Expected>' -TestCases @(
        @{ EditionId = 'Core'; Expected = 'Home' }
        @{ EditionId = 'CoreSingleLanguage'; Expected = 'Home' }
        @{ EditionId = 'Professional'; Expected = 'Pro' }
        @{ EditionId = 'ProfessionalWorkstation'; Expected = 'Pro' }
        @{ EditionId = 'ProfessionalEducation'; Expected = 'Pro' }
        @{ EditionId = 'Enterprise'; Expected = 'Enterprise' }
        @{ EditionId = 'EnterpriseS'; Expected = 'Enterprise' }
        @{ EditionId = 'IoTEnterpriseS'; Expected = 'Enterprise' }
        @{ EditionId = 'Education'; Expected = 'Education' }
        @{ EditionId = 'ServerDatacenter'; Expected = 'Server' }
        @{ EditionId = 'Mystery'; Expected = 'Unknown' }
    ) {
        ConvertTo-TuneupEdition -EditionId $EditionId | Should -Be $Expected
    }
}

Describe 'Get-TuneupFamily' {
    It 'returns <Expected> for build <Build>' -TestCases @(
        @{ Build = 19045; Expected = '10' }
        @{ Build = 22000; Expected = '11' }
        @{ Build = 26300; Expected = '11' }
    ) {
        Get-TuneupFamily -Build $Build | Should -Be $Expected
    }
}

Describe 'Get-TuneupEnvironment' {
    It 'describes the current machine' {
        $environment = Get-TuneupEnvironment
        $environment.Build | Should -BeGreaterThan 0
        $environment.Family | Should -BeIn @('10', '11')
        $environment.Edition | Should -Not -BeNullOrEmpty
        $environment.IsAdmin | Should -BeOfType [bool]
        $environment.IsManaged | Should -BeOfType [bool]
        $environment.PendingReboot | Should -BeOfType [bool]
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Environment.Tests.ps1`
Expected: FAIL, `ConvertTo-TuneupEdition` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/Environment.ps1`:
```powershell
function ConvertTo-TuneupEdition {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$EditionId)
    switch -Regex ($EditionId) {
        '^Server' { return 'Server' }
        '^Core' { return 'Home' }
        '^Professional' { return 'Pro' }
        '^(IoT)?Enterprise' { return 'Enterprise' }
        '^Education' { return 'Education' }
        default { return 'Unknown' }
    }
}

function Get-TuneupFamily {
    param([Parameter(Mandatory)][int]$Build)
    if ($Build -ge 22000) { '11' } else { '10' }
}

function Test-TuneupAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TuneupMdmEnrollment {
    $root = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    if (-not (Test-Path -LiteralPath $root)) { return $false }
    foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
        $provider = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProviderID
        if ($provider -eq 'MS DM Server') { return $true }
    }
    $false
}

function Test-TuneupPendingReboot {
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    [bool]$sessionManager.PendingFileRenameOperations
}

function Get-TuneupEnvironment {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$currentVersion.CurrentBuild
    $edition = ConvertTo-TuneupEdition -EditionId ([string]$currentVersion.EditionID)
    if ($currentVersion.InstallationType -eq 'Server') { $edition = 'Server' }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    [pscustomobject]@{
        Build         = $build
        UBR           = [int]$currentVersion.UBR
        Family        = Get-TuneupFamily -Build $build
        Edition       = $edition
        IsServer      = ($edition -eq 'Server')
        IsManaged     = ([bool]$computer.PartOfDomain -or (Test-TuneupMdmEnrollment))
        IsAdmin       = [bool](Test-TuneupAdmin)
        HasBattery    = (@(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0)
        PendingReboot = [bool](Test-TuneupPendingReboot)
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Environment.Tests.ps1`
Expected: 15 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/Environment.ps1 tests/Environment.Tests.ps1
git commit -m "feat: detección de edición, build y equipo administrado"
```

---

### Task 3: Catálogo y perfiles (carga y validación) con semilla

**Files:**
- Create: `engine/Catalog.ps1`
- Create: `catalog/privacy.json`, `catalog/ui.json`, `catalog/services.json`, `catalog/tasks.json`
- Create: `profiles/base.json`, `profiles/privacy.json`
- Test: `tests/Catalog.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Catalog.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
}

Describe 'Test-TuneupTweak' {
    It 'accepts a valid registry tweak' {
        (Test-TuneupTweak -Tweak (New-TestTweak)) -join '; ' | Should -BeNullOrEmpty
    }
    It 'rejects an invalid id' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Id 'Bad Id')) -join '; ' | Should -Match 'invalid id'
    }
    It 'rejects a missing translation' {
        $tweak = New-TestTweak
        $tweak.title.en = ''
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'missing title.en'
    }
    It 'rejects an unknown risk' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Risk 'extreme')) -join '; ' | Should -Match 'invalid risk'
    }
    It 'rejects sources that are not https' {
        $tweak = New-TestTweak
        $tweak.sources = @('http://example.com')
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'https sources'
    }
    It 'rejects a user tweak that writes HKLM' {
        $set = [pscustomobject]@{ path = 'HKLM:\SOFTWARE\Example'; name = 'A'; kind = 'DWord'; value = 1 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'scope does not match'
    }
    It 'rejects an unknown registry kind' {
        $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'Text'; value = 1 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'invalid registry kind'
    }
    It 'accepts a registry tweak that removes a value' {
        $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = $null; value = $null }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -BeNullOrEmpty
    }
    It 'rejects a service tweak with an unknown start type' {
        $set = [pscustomobject]@{ name = 'RetailDemo'; startType = 'Sometimes'; stop = $false }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'service' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'invalid startType'
    }
    It 'rejects a task path without trailing backslash' {
        $set = [pscustomobject]@{ path = '\Microsoft\Windows'; name = 'X'; state = 'Disabled' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'task' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'backslash'
    }
    It 'rejects wildcard characters in a task name or path' {
        foreach ($set in @(
                [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Sample*'; state = 'Disabled' },
                [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Sam?le'; state = 'Disabled' },
                [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Sample[1]'; state = 'Disabled' },
                [pscustomobject]@{ path = '\Microsoft\*\'; name = 'Sample'; state = 'Disabled' })) {
            (Test-TuneupTweak -Tweak (New-TestTweak -Type 'task' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'cannot contain wildcard characters'
        }
    }
    It 'rejects an unsupported type' {
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'magic')) -join '; ' | Should -Match "unsupported type 'magic'"
    }
    It 'accepts DWord values in the unsigned and signed Int32 range' {
        foreach ($value in 0, 1, 4294967295, -1, -2147483648) {
            $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'DWord'; value = $value }
            (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -BeNullOrEmpty
        }
    }
    It 'rejects a DWord value out of range' {
        foreach ($value in 4294967296, -2147483649) {
            $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'DWord'; value = $value }
            (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'value that does not match kind DWord'
        }
    }
    It 'rejects a DWord value that is a string, a boolean, a fraction or an array' {
        foreach ($value in '1', $true, 1.5, @(1, 2)) {
            $set = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'DWord'; value = $value }
            (Test-TuneupTweak -Tweak (New-TestTweak -Set $set)) -join '; ' | Should -Match 'value that does not match kind DWord'
        }
    }
    It 'validates QWord and String values against their kind' {
        $ok = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'QWord'; value = 4294967296 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $ok)) -join '; ' | Should -BeNullOrEmpty
        $bad = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'QWord'; value = 'x' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $bad)) -join '; ' | Should -Match 'value that does not match kind QWord'
        $ok = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'String'; value = 'text' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $ok)) -join '; ' | Should -BeNullOrEmpty
        $bad = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'String'; value = 5 }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $bad)) -join '; ' | Should -Match 'value that does not match kind String'
        $bad = [pscustomobject]@{ path = 'HKCU:\Software\Example'; name = 'A'; kind = 'ExpandString'; value = @('a', 'b') }
        (Test-TuneupTweak -Tweak (New-TestTweak -Set $bad)) -join '; ' | Should -Match 'value that does not match kind ExpandString'
    }
    It 'rejects ask and rebootRequired that are not booleans' {
        $tweak = New-TestTweak
        $tweak.ask = 'no'
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'ask must be true or false'
        $tweak = New-TestTweak
        $tweak.PSObject.Properties.Remove('rebootRequired')
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'rebootRequired must be true or false'
    }
    It 'rejects a service tweak whose stop is not a boolean' {
        $set = [pscustomobject]@{ name = 'RetailDemo'; startType = 'Disabled' }
        (Test-TuneupTweak -Tweak (New-TestTweak -Type 'service' -Scope 'machine' -Set $set)) -join '; ' | Should -Match 'set.stop must be true or false'
    }
    It 'reports a load error before anything else' {
        $placeholder = [pscustomobject]@{ id = $null; sourceFile = 'x.json'; loadError = 'file x.json has no tweaks array' }
        (Test-TuneupTweak -Tweak $placeholder) -join '; ' | Should -Be 'file x.json has no tweaks array'
    }
}

Describe 'Test-TuneupCatalog' {
    It 'does not report duplicate ids for load errors' {
        $first = [pscustomobject]@{ id = $null; sourceFile = 'a.json'; loadError = 'file a.json has no tweaks array' }
        $second = [pscustomobject]@{ id = $null; sourceFile = 'b.json'; loadError = 'file b.json has no tweaks array' }
        $errors = @(Test-TuneupCatalog -Catalog @($first, $second))
        $errors.Count | Should -Be 2
        $errors -join '; ' | Should -Not -Match 'duplicate'
    }
    It 'reports duplicated ids' {
        $catalog = @((New-TestTweak -Id 'test.a'), (New-TestTweak -Id 'test.a'))
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -Match 'duplicate id test.a'
    }
}

Describe 'Import-TuneupCatalog' {
    It 'rejects a tweak whose id does not match its file' {
        $dir = Join-Path $TestDrive 'catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $tweak = New-TestTweak -Id 'privacy.example'
        ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = @($tweak) }) -Depth 10 |
            Set-Content -LiteralPath (Join-Path $dir 'ui.json') -Encoding UTF8
        $catalog = @(Import-TuneupCatalog -Path $dir)
        $catalog.Count | Should -Be 1
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -Match 'does not match file ui.json'
    }
    It 'reports a file without a tweaks array' {
        $dir = Join-Path $TestDrive 'bad-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.json') -Value '{ "other": [] }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'b.json') -Value '{ "tweaks": { "id": "b.one" } }' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'c.json') -Value '[ { "id": "c.one" } ]' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'd.json') -Value '{ "tweaks": null }' -Encoding UTF8
        $errors = Test-TuneupCatalog -Catalog @(Import-TuneupCatalog -Path $dir)
        foreach ($name in 'a.json', 'b.json', 'c.json', 'd.json') {
            $errors -join '; ' | Should -Match "file $([regex]::Escape($name)) has no tweaks array"
        }
    }
    It 'reports an empty file as a load error without throwing' {
        $dir = Join-Path $TestDrive 'blank-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ui.json') -Value '' -Encoding UTF8
        $ErrorActionPreference = 'Stop'
        $catalog = @(Import-TuneupCatalog -Path $dir)
        $catalog.Count | Should -Be 1
        (Test-TuneupCatalog -Catalog $catalog) -join '; ' | Should -Be 'file ui.json has no tweaks array'
    }
    It 'accepts a file with an empty tweaks array' {
        $dir = Join-Path $TestDrive 'empty-catalog'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ui.json') -Value '{ "tweaks": [] }' -Encoding UTF8
        @(Import-TuneupCatalog -Path $dir).Count | Should -Be 0
    }
}

Describe 'Test-TuneupProfileSet' {
    BeforeAll {
        $script:Catalog = @((New-TestTweak -Id 'ui.a'), (New-TestTweak -Id 'ui.danger' -Risk 'high'))
    }
    It 'requires a base profile' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'gaming') -Catalog $Catalog) -join '; ' | Should -Match 'base profile is missing'
    }
    It 'rejects unknown tweak ids' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'base' -Include @('ui.nope')) -Catalog $Catalog) -join '; ' | Should -Match 'unknown tweak ui.nope'
    }
    It 'rejects unknown tweak ids in keep' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'base' -Keep @('ui.gone')) -Catalog $Catalog) -join '; ' | Should -Match 'unknown tweak ui.gone'
    }
    It 'rejects high-risk tweaks inside a profile' {
        (Test-TuneupProfileSet -Profiles @(New-TestProfile -Id 'base' -Include @('ui.danger')) -Catalog $Catalog) -join '; ' | Should -Match 'high-risk tweak ui.danger'
    }
    It 'rejects a name used twice' {
        $profiles = @((New-TestProfile -Id 'base'), (New-TestProfile -Id 'dev' -Aliases @('base')))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $Catalog) -join '; ' | Should -Match "name 'base' is used"
    }
}

Describe 'Shipped catalog and profiles' {
    It 'the catalog is valid and not empty' {
        $catalog = @(Import-TuneupCatalog -Path (Join-Path $RepoRoot 'catalog'))
        $catalog.Count | Should -BeGreaterThan 0
        (Test-TuneupCatalog -Catalog $catalog) -join "`n" | Should -BeNullOrEmpty
    }
    It 'the profiles are valid' {
        $catalog = @(Import-TuneupCatalog -Path (Join-Path $RepoRoot 'catalog'))
        $profiles = @(Import-TuneupProfileSet -Path (Join-Path $RepoRoot 'profiles'))
        (Test-TuneupProfileSet -Profiles $profiles -Catalog $catalog) -join "`n" | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Catalog.Tests.ps1`
Expected: FAIL, `Test-TuneupTweak` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/Catalog.ps1`:
```powershell
$script:TweakRisks = @('low', 'medium', 'high')
$script:TweakScopes = @('machine', 'user')
$script:TweakFamilies = @('10', '11')
$script:TweakEditions = @('Home', 'Pro', 'Enterprise', 'Education')
$script:RegistryKinds = @('DWord', 'QWord', 'String', 'ExpandString')
$script:ServiceStartTypes = @('Automatic', 'AutomaticDelayed', 'Manual', 'Disabled')
$script:TaskStates = @('Enabled', 'Disabled')

function Import-TuneupCatalog {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object Name) {
        $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $tweaksProperty = $null
        if ($null -ne $data) { $tweaksProperty = $data.PSObject.Properties['tweaks'] }
        if ($null -eq $tweaksProperty -or $tweaksProperty.Value -isnot [array]) {
            [pscustomobject]@{ id = $null; sourceFile = $file.Name; loadError = "file $($file.Name) has no tweaks array" }
            continue
        }
        foreach ($tweak in @($tweaksProperty.Value)) {
            if ($null -eq $tweak) { continue }
            $tweak | Add-Member -NotePropertyName sourceFile -NotePropertyValue $file.Name -Force
            $tweak
        }
    }
}

function Test-TuneupRegistryValue {
    param([string]$Kind, $Value)
    if ($Value -is [array]) { return $false }
    switch ($Kind) {
        'DWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -2147483648 -Max 4294967295) }
        'QWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -9223372036854775808 -Max 9223372036854775807) }
        default { return ($Value -is [string]) }
    }
}

function Test-TuneupIntegerInRange {
    param($Value, [decimal]$Min, [decimal]$Max)
    $integerTypes = @([int], [long], [uint32], [uint64], [int16], [uint16], [byte], [sbyte])
    $isInteger = $false
    foreach ($type in $integerTypes) { if ($Value -is $type) { $isInteger = $true } }
    if (-not $isInteger) { return $false }
    $number = [decimal]$Value
    return ($number -ge $Min -and $number -le $Max)
}

function Test-TuneupTweak {
    param([Parameter(Mandatory)]$Tweak)
    $errors = New-Object System.Collections.Generic.List[string]
    if ($Tweak.loadError) {
        $errors.Add([string]$Tweak.loadError)
        return $errors.ToArray()
    }
    $id = [string]$Tweak.id
    if ($id -cnotmatch '^[a-z]+(\.[a-z0-9-]+)+$') {
        $errors.Add("invalid id '$id'")
        return $errors.ToArray()
    }
    if ($Tweak.sourceFile -and ($id.Split('.')[0] + '.json') -ne $Tweak.sourceFile) {
        $errors.Add("$id does not match file $($Tweak.sourceFile)")
    }
    foreach ($field in 'title', 'why') {
        foreach ($lang in 'es', 'en') {
            if ([string]::IsNullOrWhiteSpace([string]$Tweak.$field.$lang)) { $errors.Add("$id is missing $field.$lang") }
        }
    }
    if ($script:TweakRisks -notcontains $Tweak.risk) { $errors.Add("$id has an invalid risk '$($Tweak.risk)'") }
    if ($script:TweakScopes -notcontains $Tweak.scope) { $errors.Add("$id has an invalid scope '$($Tweak.scope)'") }
    if ($Tweak.ask -isnot [bool]) { $errors.Add("$id ask must be true or false") }
    if ($Tweak.rebootRequired -isnot [bool]) { $errors.Add("$id rebootRequired must be true or false") }

    $families = @($Tweak.os.families | Where-Object { $_ })
    if (-not $families.Count -or @($families | Where-Object { $script:TweakFamilies -notcontains $_ }).Count) {
        $errors.Add("$id has invalid os.families")
    }
    $editions = @($Tweak.os.editions | Where-Object { $_ })
    if (-not $editions.Count -or @($editions | Where-Object { $script:TweakEditions -notcontains $_ }).Count) {
        $errors.Add("$id has invalid os.editions")
    }
    $minBuild = 0
    if (-not [int]::TryParse([string]$Tweak.os.minBuild, [ref]$minBuild) -or $minBuild -le 0) {
        $errors.Add("$id is missing os.minBuild")
    }
    $sources = @($Tweak.sources | Where-Object { $_ })
    if (-not $sources.Count -or @($sources | Where-Object { $_ -notmatch '^https://' }).Count) {
        $errors.Add("$id needs https sources")
    }

    $set = $Tweak.set
    switch ($Tweak.type) {
        'registry' {
            if ([string]$set.path -notmatch '^(HKLM|HKCU):\\.+') {
                $errors.Add("$id has an invalid registry path")
            } elseif (([string]$set.path -match '^HKCU:') -ne ($Tweak.scope -eq 'user')) {
                $errors.Add("$id scope does not match its registry hive")
            }
            if ([string]::IsNullOrEmpty([string]$set.name)) { $errors.Add("$id is missing set.name") }
            if ($null -ne $set.value) {
                if ($script:RegistryKinds -notcontains $set.kind) {
                    $errors.Add("$id has an invalid registry kind '$($set.kind)'")
                } elseif (-not (Test-TuneupRegistryValue -Kind $set.kind -Value $set.value)) {
                    $errors.Add("$id has a value that does not match kind $($set.kind)")
                }
            }
        }
        'service' {
            if ([string]::IsNullOrEmpty([string]$set.name)) { $errors.Add("$id is missing set.name") }
            if ($script:ServiceStartTypes -notcontains $set.startType) { $errors.Add("$id has an invalid startType '$($set.startType)'") }
            if ($set.stop -isnot [bool]) { $errors.Add("$id set.stop must be true or false") }
            if ($Tweak.scope -ne 'machine') { $errors.Add("$id must use scope machine") }
        }
        'task' {
            if ([string]$set.path -notmatch '^\\(.*\\)?$') { $errors.Add("$id task path must start and end with a backslash") }
            if ([string]::IsNullOrEmpty([string]$set.name)) { $errors.Add("$id is missing set.name") }
            if (([string]$set.name + [string]$set.path) -match '[*?\[\]]') { $errors.Add("$id task name and path cannot contain wildcard characters") }
            if ($script:TaskStates -notcontains $set.state) { $errors.Add("$id has an invalid task state '$($set.state)'") }
            if ($Tweak.scope -ne 'machine') { $errors.Add("$id must use scope machine") }
        }
        default { $errors.Add("$id has an unsupported type '$($Tweak.type)'") }
    }
    $errors.ToArray()
}

function Test-TuneupCatalog {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog)
    $seen = @{}
    foreach ($tweak in $Catalog) {
        Test-TuneupTweak -Tweak $tweak
        if ($tweak.loadError) { continue }
        $id = [string]$tweak.id
        if ($seen.ContainsKey($id)) { "duplicate id $id" } else { $seen[$id] = $true }
    }
}

function Import-TuneupProfileSet {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object Name) {
        $profileData = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $profileData | Add-Member -NotePropertyName sourceFile -NotePropertyValue $file.Name -Force
        $profileData
    }
}

function Test-TuneupProfileSet {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Profiles,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $byId = @{}
    foreach ($tweak in $Catalog) { $byId[[string]$tweak.id] = $tweak }
    if (-not @($Profiles | Where-Object { $_.id -eq 'base' }).Count) { $errors.Add('the base profile is missing') }
    $names = @{}
    foreach ($profileData in $Profiles) {
        $profileId = [string]$profileData.id
        if ($profileId -cnotmatch '^[a-z]+$') { $errors.Add("invalid profile id '$profileId'"); continue }
        if ($profileData.sourceFile -and "$profileId.json" -ne $profileData.sourceFile) {
            $errors.Add("profile $profileId does not match file $($profileData.sourceFile)")
        }
        foreach ($name in @($profileId) + @($profileData.aliases | Where-Object { $_ })) {
            $key = ([string]$name).ToLowerInvariant()
            if ($names.ContainsKey($key)) { $errors.Add("profile name '$name' is used by $($names[$key]) and $profileId") }
            else { $names[$key] = $profileId }
        }
        foreach ($field in 'title', 'description') {
            foreach ($lang in 'es', 'en') {
                if ([string]::IsNullOrWhiteSpace([string]$profileData.$field.$lang)) { $errors.Add("profile $profileId is missing $field.$lang") }
            }
        }
        foreach ($tweakId in @($profileData.include | Where-Object { $_ }) + @($profileData.keep | Where-Object { $_ })) {
            if (-not $byId.ContainsKey($tweakId)) { $errors.Add("profile $profileId references unknown tweak $tweakId") }
        }
        foreach ($tweakId in @($profileData.include | Where-Object { $_ })) {
            if ($byId.ContainsKey($tweakId) -and $byId[$tweakId].risk -eq 'high') {
                $errors.Add("profile $profileId includes high-risk tweak $tweakId")
            }
        }
    }
    $errors.ToArray()
}
```

- [ ] **Step 4: Catálogo semilla**

Solo cinco ajustes para ejercitar los tres manejadores; el Plan 3 revisa cada uno y completa el catálogo.

`catalog/privacy.json`:
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
    }
  ]
}
```

`catalog/ui.json`:
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
    }
  ]
}
```

`catalog/services.json`:
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
      "sources": ["https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server"]
    }
  ]
}
```

`catalog/tasks.json`:
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
      "sources": ["https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1"]
    }
  ]
}
```

`profiles/base.json`:
```json
{
  "id": "base",
  "aliases": [],
  "title": { "es": "Base", "en": "Base" },
  "description": { "es": "Lo seguro para cualquier equipo. Siempre se aplica.", "en": "Safe for any machine. Always applied." },
  "include": ["ui.show-file-extensions", "privacy.advertising-id", "services.retail-demo"],
  "keep": []
}
```

`profiles/privacy.json`:
```json
{
  "id": "privacy",
  "aliases": ["privacidad"],
  "title": { "es": "Privacidad", "en": "Privacy" },
  "description": { "es": "Menos datos enviados a Microsoft y a los anunciantes.", "en": "Less data sent to Microsoft and advertisers." },
  "include": ["privacy.tailored-experiences", "tasks.ceip-consolidator"],
  "keep": []
}
```

- [ ] **Step 5: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Catalog.Tests.ps1`
Expected: 32 passed.

- [ ] **Step 6: Commit**

```bash
git add engine/Catalog.ps1 catalog profiles tests/Catalog.Tests.ps1
git commit -m "feat: carga y validación de catálogo y perfiles, con semilla"
```

---

### Task 4: Manejador de registro

**Files:**
- Create: `engine/handlers/Registry.ps1`
- Test: `tests/Registry.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Usa una clave real y aislada en `HKCU:\Software\windows-tuneup-test`, que se borra después de cada prueba.

`tests/Registry.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-RegTweak([string]$Path, [string]$Name, $Kind, $Value) {
        New-TestTweak -Set ([pscustomobject]@{ path = $Path; name = $Name; kind = $Kind; value = $Value })
    }
}

Describe 'Registry handler' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'captures a missing value and the nearest existing ancestor' {
        $tweak = New-RegTweak "$Key\Sub" 'A' 'DWord' 1
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'not-applied'
        $state = Get-RegistryTweakState -Tweak $tweak
        $state.exists | Should -BeFalse
        $state.keyExisted | Should -BeFalse
        $state.existingAncestor | Should -Be 'HKCU:\Software'
    }

    It 'applies a DWord and reports it as applied' {
        $tweak = New-RegTweak "$Key\Sub" 'A' 'DWord' 1
        Set-RegistryTweakDesired -Tweak $tweak
        (Get-ItemProperty -LiteralPath "$Key\Sub").A | Should -Be 1
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'applied'
    }

    It 'handles DWord values above 2^31' {
        $tweak = New-RegTweak $Key 'Big' 'DWord' 4294967295
        Set-RegistryTweakDesired -Tweak $tweak
        (Get-Item -LiteralPath $Key).GetValue('Big') | Should -Be -1
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'applied'
    }

    It 'treats a different kind as not applied' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType String -Value '1' | Out-Null
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'A' 'DWord' 1) | Should -Be 'not-applied'
    }

    It 'removes the keys it created when restoring a value that did not exist' {
        $tweak = New-RegTweak "$Key\Sub\Deep" 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Restore-RegistryTweakState -Tweak $tweak -State $state
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'restores the previous value and kind after a JSON round trip' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType String -Value 'old' | Out-Null
        $tweak = New-RegTweak $Key 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Set-RegistryTweakDesired -Tweak $tweak
        Restore-RegistryTweakState -Tweak $tweak -State $state
        $item = Get-Item -LiteralPath $Key
        $item.GetValueKind('A') | Should -Be 'String'
        $item.GetValue('A') | Should -Be 'old'
    }

    It 'keeps a key that existed before' {
        New-Item -Path $Key -Force | Out-Null
        $tweak = New-RegTweak $Key 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Restore-RegistryTweakState -Tweak $tweak -State $state
        Test-Path -LiteralPath $Key | Should -BeTrue
        (Get-Item -LiteralPath $Key).GetValueNames() -contains 'A' | Should -BeFalse
    }

    It 'removes a value when the desired value is null and restores it' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType DWord -Value 7 | Out-Null
        $tweak = New-RegTweak $Key 'A' $null $null
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'not-applied'
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'applied'
        Restore-RegistryTweakState -Tweak $tweak -State $state
        (Get-ItemProperty -LiteralPath $Key).A | Should -Be 7
    }

    It 'does not equate a MultiString element that contains a space with two elements' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'M' -PropertyType MultiString -Value @('a b') | Out-Null
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'M' 'MultiString' @('a', 'b')) | Should -Be 'not-applied'
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'M' 'MultiString' @('a b')) | Should -Be 'applied'
    }

    It 'compares Binary values byte by byte' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'B' -PropertyType Binary -Value ([byte[]]@(1, 2, 3)) | Out-Null
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'B' 'Binary' @(1, 2, 3)) | Should -Be 'applied'
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'B' 'Binary' @(1, 2)) | Should -Be 'not-applied'
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'B' 'Binary' @(1, 2, 4)) | Should -Be 'not-applied'
    }

    It 'restores a REG_NONE value with its kind and bytes after a JSON round trip' {
        $hive = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\windows-tuneup-test')
        $hive.SetValue('N', [byte[]]@(1, 2, 3), [Microsoft.Win32.RegistryValueKind]::None)
        $hive.Close()
        $tweak = New-RegTweak $Key 'N' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $state.kind | Should -Be 'None'
        Set-RegistryTweakDesired -Tweak $tweak
        (Get-Item -LiteralPath $Key).GetValueKind('N') | Should -Be 'DWord'
        Restore-RegistryTweakState -Tweak $tweak -State $state
        $item = Get-Item -LiteralPath $Key
        $item.GetValueKind('N') | Should -Be 'None'
        ($item.GetValue('N') -join ',') | Should -Be '1,2,3'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Registry.Tests.ps1`
Expected: FAIL, `Test-RegistryTweakState` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/handlers/Registry.ps1`:
```powershell
function ConvertTo-TuneupDWord {
    param([Parameter(Mandatory)]$Value)
    $number = [int64]$Value
    if ($number -lt 0) { $number += 4294967296 }
    [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$number), 0)
}

function ConvertTo-TuneupByteArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return , ([byte[]]@()) }
    , ([byte[]]@($Value))
}

function Test-TuneupRegistryValueEqual {
    param([Parameter(Mandatory)][string]$Kind, $Current, $Desired)
    switch ($Kind) {
        'DWord' { return (ConvertTo-TuneupDWord -Value $Current) -eq (ConvertTo-TuneupDWord -Value $Desired) }
        'QWord' { return [int64]$Current -eq [int64]$Desired }
        'MultiString' {
            $left = [string[]]@($Current)
            $right = [string[]]@($Desired)
            if ($left.Count -ne $right.Count) { return $false }
            for ($i = 0; $i -lt $left.Count; $i++) {
                if ($left[$i] -cne $right[$i]) { return $false }
            }
            return $true
        }
        { $_ -in 'Binary', 'None', 'Unknown' } {
            $left = ConvertTo-TuneupByteArray -Value $Current
            $right = ConvertTo-TuneupByteArray -Value $Desired
            if ($left.Length -ne $right.Length) { return $false }
            for ($i = 0; $i -lt $left.Length; $i++) {
                if ($left[$i] -ne $right[$i]) { return $false }
            }
            return $true
        }
        default { return [string]$Current -ceq [string]$Desired }
    }
}

function Write-TuneupRawRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()]$Value
    )
    if ($Path -match '^HKCU:\\?(?<sub>.*)$') { $root = [Microsoft.Win32.Registry]::CurrentUser }
    elseif ($Path -match '^HKLM:\\?(?<sub>.*)$') { $root = [Microsoft.Win32.Registry]::LocalMachine }
    else { throw "Unsupported registry path for kind ${Kind}: $Path" }
    $key = $root.OpenSubKey($Matches['sub'], $true)
    if ($null -eq $key) { throw "Cannot open registry key for writing: $Path" }
    try {
        $key.SetValue($Name, (ConvertTo-TuneupByteArray -Value $Value), [Microsoft.Win32.RegistryValueKind]$Kind)
    }
    finally {
        $key.Close()
    }
}

function Write-TuneupRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()]$Value
    )
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    if ($Kind -in 'None', 'Unknown') {
        Write-TuneupRawRegistryValue -Path $Path -Name $Name -Kind $Kind -Value $Value
        return
    }
    if ($Kind -eq 'DWord') { $data = ConvertTo-TuneupDWord -Value $Value }
    elseif ($Kind -eq 'QWord') { $data = [int64]$Value }
    elseif ($Kind -eq 'Binary') { $data = ConvertTo-TuneupByteArray -Value $Value }
    elseif ($Kind -eq 'MultiString') { $data = [string[]]@($Value) }
    else { $data = [string]$Value }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Kind -Value $data -Force -ErrorAction Stop | Out-Null
}

function Get-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $path = [string]$Tweak.set.path
    $name = [string]$Tweak.set.name
    $ancestor = $path
    while ($ancestor -and -not (Test-Path -LiteralPath $ancestor)) {
        $ancestor = Split-Path -Path $ancestor -Parent
    }
    $state = [pscustomobject]@{
        keyExisted       = ($ancestor -eq $path)
        existingAncestor = $ancestor
        exists           = $false
        kind             = $null
        value            = $null
    }
    if ($state.keyExisted) {
        $key = Get-Item -LiteralPath $path
        if ($key.GetValueNames() -contains $name) {
            $state.exists = $true
            $state.kind = $key.GetValueKind($name).ToString()
            $state.value = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        }
        $key.Close()
    }
    $state
}

function Test-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $desired = $Tweak.set
    $current = Get-RegistryTweakState -Tweak $Tweak
    if ($null -eq $desired.value) {
        if ($current.exists) { return 'not-applied' }
        return 'applied'
    }
    if (-not $current.exists -or $current.kind -ne $desired.kind) { return 'not-applied' }
    if (Test-TuneupRegistryValueEqual -Kind $desired.kind -Current $current.value -Desired $desired.value) { return 'applied' }
    'not-applied'
}

function Set-RegistryTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $desired = $Tweak.set
    if ($null -eq $desired.value) {
        if (Test-Path -LiteralPath $desired.path) {
            Remove-ItemProperty -LiteralPath $desired.path -Name $desired.name -ErrorAction SilentlyContinue
        }
        return
    }
    Write-TuneupRegistryValue -Path $desired.path -Name $desired.name -Kind $desired.kind -Value $desired.value
}

function Restore-RegistryTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $path = [string]$Tweak.set.path
    $name = [string]$Tweak.set.name
    if ($State.exists) {
        Write-TuneupRegistryValue -Path $path -Name $name -Kind $State.kind -Value $State.value
        return
    }
    if (Test-Path -LiteralPath $path) {
        Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
    }
    $current = $path
    while ($current -and $current -ne $State.existingAncestor -and (Test-Path -LiteralPath $current)) {
        $key = Get-Item -LiteralPath $current
        $isEmpty = ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0)
        $key.Close()
        if (-not $isEmpty) { break }
        Remove-Item -LiteralPath $current -Force -ErrorAction Stop
        $current = Split-Path -Path $current -Parent
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Registry.Tests.ps1`
Expected: 11 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Registry.ps1 tests/Registry.Tests.ps1
git commit -m "feat: manejador de registro con reversa exacta"
```

---

### Task 5: Manejador de servicios

**Files:**
- Create: `engine/handlers/Service.ps1`
- Test: `tests/Service.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Service.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'services.retail-demo' -Type 'service' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'RetailDemo'; startType = 'Disabled'; stop = $true })
}

Describe 'Service handler' {
    It 'maps Start=<Start> Delayed=<Delayed> to <Expected>' -TestCases @(
        @{ Start = 2; Delayed = 1; Expected = 'AutomaticDelayed' }
        @{ Start = 2; Delayed = $null; Expected = 'Automatic' }
        @{ Start = 3; Delayed = $null; Expected = 'Manual' }
        @{ Start = 4; Delayed = $null; Expected = 'Disabled' }
        @{ Start = 0; Delayed = $null; Expected = 'Boot' }
    ) {
        Mock -ModuleName Tuneup Test-Path { $true }
        Mock -ModuleName Tuneup Get-ItemProperty { [pscustomobject]@{ Start = $Start; DelayedAutostart = $Delayed } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        (Get-ServiceTweakState -Tweak $Tweak).startType | Should -Be $Expected
    }

    It 'reports a missing service as not-present' {
        Mock -ModuleName Tuneup Test-Path { $false }
        Test-ServiceTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'is applied when the start type matches' {
        Mock -ModuleName Tuneup Test-Path { $true }
        Mock -ModuleName Tuneup Get-ItemProperty { [pscustomobject]@{ Start = 4; DelayedAutostart = $null } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        Test-ServiceTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'treats a service key without a Start value as not-present' {
        Mock -ModuleName Tuneup Test-Path { $true }
        Mock -ModuleName Tuneup Get-ItemProperty { [pscustomobject]@{ ImagePath = 'x.exe' } }
        Mock -ModuleName Tuneup Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        $state = Get-ServiceTweakState -Tweak $Tweak
        $state.present | Should -BeFalse
        Test-ServiceTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'sets the start type with sc.exe and stops a running service without -Force' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        Set-ServiceTweakDesired -Tweak $Tweak
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Name -eq 'RetailDemo' -and $Start -eq 'disabled' }
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { -not $Force -and $ErrorAction -eq 'Stop' }
    }

    It 'does not stop a service that is not running' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $false } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        Set-ServiceTweakDesired -Tweak $Tweak
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'throws a clear error when stopping fails after the start type was changed' {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { throw 'cannot stop' }
        { Set-ServiceTweakDesired -Tweak $Tweak } |
            Should -Throw 'Start type of RetailDemo set to Disabled, but stopping it failed: cannot stop'
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'refuses to change a <Current> driver before calling sc.exe' -TestCases @(
        @{ Current = 'Boot' }
        @{ Current = 'System' }
    ) {
        Mock -ModuleName Tuneup Get-ServiceTweakState { [pscustomobject]@{ present = $true; startType = $Current; running = $false } }
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Stop-Service { }
        { Set-ServiceTweakDesired -Tweak $Tweak } | Should -Throw 'Refusing to change boot or system driver RetailDemo'
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Stop-Service -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'restores the previous start type and starts the service if it was running' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Start-Service { }
        $state = [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true }
        Restore-ServiceTweakState -Tweak $Tweak -State $state
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Start -eq 'demand' }
        Should -Invoke Start-Service -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'surfaces a failed service start from restore' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        Mock -ModuleName Tuneup Start-Service { throw 'cannot start' }
        $state = [pscustomobject]@{ present = $true; startType = 'Manual'; running = $true }
        { Restore-ServiceTweakState -Tweak $Tweak -State $state } | Should -Throw '*cannot start*'
    }

    It 'does not touch boot or system drivers on restore' {
        Mock -ModuleName Tuneup Invoke-TuneupSc { }
        $state = [pscustomobject]@{ present = $true; startType = 'Boot'; running = $false }
        Restore-ServiceTweakState -Tweak $Tweak -State $state
        Should -Invoke Invoke-TuneupSc -ModuleName Tuneup -Times 0 -Exactly
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Service.Tests.ps1`
Expected: FAIL, `Get-ServiceTweakState` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/handlers/Service.ps1`:
```powershell
$script:ScStartArguments = @{
    Automatic        = 'auto'
    AutomaticDelayed = 'delayed-auto'
    Manual           = 'demand'
    Disabled         = 'disabled'
}

function Invoke-TuneupSc {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Start)
    $sc = Join-Path $env:SystemRoot 'System32\sc.exe'
    $output = & $sc config $Name start= $Start 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe config $Name start= $Start failed with exit code ${LASTEXITCODE}: $output"
    }
}

function Set-TuneupServiceStartType {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$StartType)
    Invoke-TuneupSc -Name $Name -Start $script:ScStartArguments[$StartType]
}

function Get-ServiceTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return [pscustomobject]@{ present = $false; startType = $null; running = $false }
    }
    $properties = Get-ItemProperty -LiteralPath $registryPath
    if ($null -eq $properties.Start) {
        return [pscustomobject]@{ present = $false; startType = $null; running = $false }
    }
    $startType = switch ([int]$properties.Start) {
        0 { 'Boot' }
        1 { 'System' }
        2 { if ($properties.DelayedAutostart -eq 1) { 'AutomaticDelayed' } else { 'Automatic' } }
        3 { 'Manual' }
        4 { 'Disabled' }
        default { "Unknown$($properties.Start)" }
    }
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    [pscustomobject]@{
        present   = $true
        startType = $startType
        running   = [bool]($service -and $service.Status -eq 'Running')
    }
}

function Test-ServiceTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-ServiceTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.startType -eq $Tweak.set.startType) { return 'applied' }
    'not-applied'
}

function Set-ServiceTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $startType = [string]$Tweak.set.startType
    $current = Get-ServiceTweakState -Tweak $Tweak
    if ($current.startType -eq 'Boot' -or $current.startType -eq 'System') {
        throw "Refusing to change boot or system driver $name"
    }
    Set-TuneupServiceStartType -Name $name -StartType $startType
    if ($Tweak.set.stop -and $current.running) {
        try {
            Stop-Service -Name $name -ErrorAction Stop
        }
        catch {
            throw "Start type of $name set to $startType, but stopping it failed: $($_.Exception.Message)"
        }
    }
}

function Restore-ServiceTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    if ($script:ScStartArguments.ContainsKey([string]$State.startType)) {
        Set-TuneupServiceStartType -Name $Tweak.set.name -StartType $State.startType
    }
    if ($State.running) { Start-Service -Name $Tweak.set.name -ErrorAction Stop }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Service.Tests.ps1`
Expected: 16 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Service.ps1 tests/Service.Tests.ps1
git commit -m "feat: manejador de servicios"
```

---

### Task 6: Manejador de tareas programadas

**Files:**
- Create: `engine/handlers/Task.ps1`
- Test: `tests/Task.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Task.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'tasks.sample' -Type 'task' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = '\Microsoft\Windows\Test\'; name = 'Sample'; state = 'Disabled' })
    $script:EnabledTweak = New-TestTweak -Id 'tasks.sample2' -Type 'task' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = '\Microsoft\Windows\Test\'; name = 'Sample'; state = 'Enabled' })
    # Client-only CIM instance: the real cmdlets type -InputObject as CimInstance, and this never touches a real task.
    $script:NewFakeTask = {
        param([string]$Name, [string]$State)
        New-CimInstance -ClientOnly -ClassName MSFT_ScheduledTask -Namespace 'Root/Microsoft/Windows/TaskScheduler' `
            -Property @{ TaskName = $Name; TaskPath = '\Microsoft\Windows\Test\'; State = $State }
    }
}

Describe 'Task handler' {
    It 'reports an enabled task as not applied when the goal is Disabled' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeTrue
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'counts a running task as enabled' {
        $fake = & $NewFakeTask 'Sample' 'Running'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeTrue
    }

    It 'reports a disabled task as applied' {
        $fake = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a missing task as not-present' {
        Mock -ModuleName Tuneup Get-ScheduledTask { $null }
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'resolves only the exact match when the wildcard lookup returns several tasks' {
        $near = & $NewFakeTask 'SampleOther' 'Ready'
        $exact = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $near; $exact }.GetNewClosure()
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeFalse
    }

    It 'reports not-present when the lookup only returns near matches' {
        $near = & $NewFakeTask 'SampleOther' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $near }.GetNewClosure()
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'disables the exact task object with errors made terminating' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Set-TaskTweakDesired -Tweak $Tweak
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $InputObject.TaskName -eq 'Sample' -and $InputObject.TaskPath -eq '\Microsoft\Windows\Test\' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'enables the task when the goal state is Enabled' {
        $fake = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Set-TaskTweakDesired -Tweak $EnabledTweak
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $InputObject.TaskName -eq 'Sample' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'enables the task again when it was enabled before' {
        $fake = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; enabled = $true })
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'disables the task again when it was disabled before' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $EnabledTweak -State ([pscustomobject]@{ present = $true; enabled = $false })
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'does nothing on restore when the task was not present' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $false; enabled = $null })
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'throws when the task is missing at write time' {
        Mock -ModuleName Tuneup Get-ScheduledTask { $null }
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        { Set-TaskTweakDesired -Tweak $Tweak } | Should -Throw '*Scheduled task \Microsoft\Windows\Test\Sample not found*'
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'propagates a failure from Disable-ScheduledTask' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Disable-ScheduledTask { throw 'access denied' }
        { Set-TaskTweakDesired -Tweak $Tweak } | Should -Throw '*access denied*'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Task.Tests.ps1`
Expected: FAIL, `Get-TaskTweakState` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/handlers/Task.ps1`:
```powershell
function Get-TuneupScheduledTask {
    param([Parameter(Mandatory)]$Tweak)
    # Get-ScheduledTask treats names and paths as wildcards, so keep only the exact match.
    $found = @(Get-ScheduledTask -TaskPath $Tweak.set.path -TaskName $Tweak.set.name -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -eq $Tweak.set.name -and $_.TaskPath -eq $Tweak.set.path })
    if ($found.Count -eq 0) { return $null }
    $found[0]
}

function Get-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $task = Get-TuneupScheduledTask -Tweak $Tweak
    if ($null -eq $task) { return [pscustomobject]@{ present = $false; enabled = $null } }
    [pscustomobject]@{ present = $true; enabled = ([string]$task.State -ne 'Disabled') }
}

function Test-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-TaskTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.enabled -eq ($Tweak.set.state -eq 'Enabled')) { return 'applied' }
    'not-applied'
}

function Set-TuneupTaskEnabled {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][bool]$Enabled)
    $task = Get-TuneupScheduledTask -Tweak $Tweak
    if ($null -eq $task) { throw "Scheduled task $($Tweak.set.path)$($Tweak.set.name) not found" }
    if ($Enabled) {
        Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
    } else {
        Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
    }
}

function Set-TaskTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupTaskEnabled -Tweak $Tweak -Enabled ($Tweak.set.state -eq 'Enabled')
}

function Restore-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    Set-TuneupTaskEnabled -Tweak $Tweak -Enabled ([bool]$State.enabled)
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Task.Tests.ps1`
Expected: 13 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/handlers/Task.ps1 tests/Task.Tests.ps1
git commit -m "feat: manejador de tareas programadas"
```

---

### Task 7: Despachador

**Files:**
- Create: `engine/Dispatch.ps1`
- Test: `tests/Dispatch.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Dispatch.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Dispatch' {
    It 'routes <Type> tweaks to the <Handler> handler' -TestCases @(
        @{ Type = 'registry'; Handler = 'Registry' }
        @{ Type = 'service'; Handler = 'Service' }
        @{ Type = 'task'; Handler = 'Task' }
    ) {
        Get-TuneupHandlerName -Tweak (New-TestTweak -Type $Type) | Should -Be $Handler
    }

    It 'calls the handler test function' {
        Mock -ModuleName Tuneup Test-RegistryTweakState { 'applied' }
        Test-TuneupState -Tweak (New-TestTweak) | Should -Be 'applied'
    }

    It 'passes the saved state to the handler restore function' {
        Mock -ModuleName Tuneup Restore-RegistryTweakState { }
        $state = [pscustomobject]@{ exists = $false }
        Restore-TuneupState -Tweak (New-TestTweak) -State $state
        Should -Invoke Restore-RegistryTweakState -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $State.exists -eq $false }
    }

    It 'rejects unknown types' {
        { Get-TuneupState -Tweak (New-TestTweak -Type 'magic') } | Should -Throw "*Unsupported tweak type 'magic'*"
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: FAIL, `Get-TuneupHandlerName` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/Dispatch.ps1`:
```powershell
function Get-TuneupHandlerName {
    param([Parameter(Mandatory)]$Tweak)
    switch ($Tweak.type) {
        'registry' { 'Registry' }
        'service' { 'Service' }
        'task' { 'Task' }
        default { throw "Unsupported tweak type '$($Tweak.type)'" }
    }
}

function Get-TuneupState {
    param([Parameter(Mandatory)]$Tweak)
    & "Get-$(Get-TuneupHandlerName -Tweak $Tweak)TweakState" -Tweak $Tweak
}

function Test-TuneupState {
    param([Parameter(Mandatory)]$Tweak)
    & "Test-$(Get-TuneupHandlerName -Tweak $Tweak)TweakState" -Tweak $Tweak
}

function Set-TuneupDesired {
    param([Parameter(Mandatory)]$Tweak)
    & "Set-$(Get-TuneupHandlerName -Tweak $Tweak)TweakDesired" -Tweak $Tweak
}

function Restore-TuneupState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    & "Restore-$(Get-TuneupHandlerName -Tweak $Tweak)TweakState" -Tweak $Tweak -State $State
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Dispatch.Tests.ps1`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/Dispatch.ps1 tests/Dispatch.Tests.ps1
git commit -m "feat: despachador de manejadores"
```

---

### Task 8: Planificador

**Files:**
- Create: `engine/Planner.ps1`
- Test: `tests/Planner.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Planner.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $policySet = [pscustomobject]@{ path = 'HKLM:\SOFTWARE\Policies\Microsoft\Example'; name = 'A'; kind = 'DWord'; value = 1 }
    $script:Catalog = @(
        (New-TestTweak -Id 'ui.a'),
        (New-TestTweak -Id 'ui.b'),
        (New-TestTweak -Id 'apps.xbox'),
        (New-TestTweak -Id 'gaming.vbs-off' -Risk 'high'),
        (New-TestTweak -Id 'apps.onedrive' -Ask $true),
        (New-TestTweak -Id 'policy.example' -Scope 'machine' -Set $policySet),
        (New-TestTweak -Id 'ui.home-only' -Editions @('Home')),
        (New-TestTweak -Id 'ui.future' -MinBuild 30000),
        (New-TestTweak -Id 'ui.edge-build' -MinBuild 26100),
        (New-TestTweak -Id 'ui.only-11' -Families @('11')),
        (New-TestTweak -Id 'svc.policy-path' -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\Policies\Microsoft\Example'; name = 'Spooler'; startup = 'Disabled' }))
    )
    $script:Profiles = @(
        (New-TestProfile -Id 'base' -Include @('ui.a')),
        (New-TestProfile -Id 'gaming' -Aliases @('juegos') -Include @('ui.b') -Keep @('apps.xbox')),
        (New-TestProfile -Id 'lite' -Aliases @('liviano') -Include @('apps.xbox', 'apps.onedrive', 'policy.example', 'ui.home-only', 'ui.future')),
        (New-TestProfile -Id 'unsafe' -Include @('gaming.vbs-off'))
    )
    $script:NotApplied = { param($tweak) 'not-applied' }
    function Invoke-Plan {
        param([string[]]$ProfileIds = @(), [string[]]$Include = @(), [string[]]$Exclude = @(), $Environment = (New-TestEnvironment), [scriptblock]$TestState = $NotApplied, [switch]$Interactive)
        @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -ProfileIds $ProfileIds -Include $Include -Exclude $Exclude -Environment $Environment -TestState $TestState -Interactive:$Interactive)
    }
    function Get-Reason($Plan, [string]$Id) { ($Plan | Where-Object { $_.Id -eq $Id }).Reason }
    function Get-Action($Plan, [string]$Id) { ($Plan | Where-Object { $_.Id -eq $Id }).Action }
}

Describe 'New-TuneupPlan' {
    It 'always includes the base profile' {
        $plan = Invoke-Plan
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a'
        Get-Action $plan 'ui.a' | Should -Be 'apply'
    }

    It 'resolves profile aliases case-insensitively' {
        $plan = Invoke-Plan -ProfileIds 'JUEGOS'
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
    }

    It 'throws on an unknown profile' {
        { Invoke-Plan -ProfileIds 'nope' } | Should -Throw '*nope*'
    }

    It 'throws on an unknown included tweak' {
        { Invoke-Plan -Include 'ui.nope' } | Should -Throw '*ui.nope*'
    }

    It 'lets keep win over another profile' {
        Get-Reason (Invoke-Plan -ProfileIds 'gaming', 'lite') 'apps.xbox' | Should -Be 'kept-by-profile'
    }

    It 'lets an explicit include win over keep' {
        Get-Action (Invoke-Plan -ProfileIds 'gaming', 'lite' -Include 'apps.xbox') 'apps.xbox' | Should -Be 'apply'
    }

    It 'honors -Exclude' {
        Get-Reason (Invoke-Plan -Exclude 'ui.a') 'ui.a' | Should -Be 'excluded'
    }

    It 'skips high-risk tweaks unless included by name' {
        Get-Reason (Invoke-Plan -ProfileIds 'unsafe') 'gaming.vbs-off' | Should -Be 'high-risk-not-requested'
        Get-Action (Invoke-Plan -Include 'gaming.vbs-off') 'gaming.vbs-off' | Should -Be 'apply'
    }

    It 'skips ask tweaks when not interactive unless included' {
        Get-Reason (Invoke-Plan -ProfileIds 'lite') 'apps.onedrive' | Should -Be 'needs-confirmation'
        Get-Action (Invoke-Plan -ProfileIds 'lite' -Include 'apps.onedrive') 'apps.onedrive' | Should -Be 'apply'
        Get-Action (Invoke-Plan -ProfileIds 'lite' -Interactive) 'apps.onedrive' | Should -Be 'apply'
    }

    It 'leaves policies alone on managed devices' {
        $plan = Invoke-Plan -ProfileIds 'lite' -Environment (New-TestEnvironment -IsManaged $true)
        Get-Reason $plan 'policy.example' | Should -Be 'managed-device'
    }

    It 'skips tweaks for other editions and newer builds' {
        $plan = Invoke-Plan -ProfileIds 'lite'
        Get-Reason $plan 'ui.home-only' | Should -Be 'incompatible'
        Get-Reason $plan 'ui.future' | Should -Be 'incompatible'
    }

    It 'marks tweaks that are already applied or not present' {
        $state = { param($tweak) if ($tweak.id -eq 'ui.a') { 'applied' } else { 'not-present' } }
        $plan = Invoke-Plan -ProfileIds 'gaming' -TestState $state
        Get-Reason $plan 'ui.a' | Should -Be 'already-applied'
        Get-Reason $plan 'ui.b' | Should -Be 'not-present'
    }

    It 'lists each tweak once' {
        $plan = Invoke-Plan -ProfileIds 'lite', 'liviano' -Include 'apps.xbox'
        @($plan | Where-Object { $_.Id -eq 'apps.xbox' }).Count | Should -Be 1
    }
    It 'applies a tweak whose minBuild equals the current build' {
        Get-Action (Invoke-Plan -Include 'ui.edge-build' -Environment (New-TestEnvironment -Build 26100)) 'ui.edge-build' | Should -Be 'apply'
        Get-Reason (Invoke-Plan -Include 'ui.edge-build' -Environment (New-TestEnvironment -Build 26099)) 'ui.edge-build' | Should -Be 'incompatible'
    }

    It 'skips a tweak whose OS family does not match' {
        Get-Reason (Invoke-Plan -Include 'ui.only-11' -Environment (New-TestEnvironment -Family '10' -Build 19045)) 'ui.only-11' | Should -Be 'incompatible'
        Get-Action (Invoke-Plan -Include 'ui.only-11') 'ui.only-11' | Should -Be 'apply'
    }

    It 'resolves a profile name with surrounding spaces' {
        ((Invoke-Plan -ProfileIds ' gaming ') | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
    }

    It 'reports excluded when a tweak is both excluded and kept' {
        Get-Reason (Invoke-Plan -ProfileIds 'gaming', 'lite' -Exclude 'apps.xbox') 'apps.xbox' | Should -Be 'excluded'
    }

    It 'treats ids case-insensitively and lists each tweak once' {
        $plan = Invoke-Plan -Include 'UI.A'
        @($plan).Count | Should -Be 1
        $plan[0].Id | Should -Be 'ui.a'
        Get-Reason (Invoke-Plan -Exclude 'UI.A') 'ui.a' | Should -Be 'excluded'
        Get-Action (Invoke-Plan -ProfileIds 'gaming', 'lite' -Include 'APPS.XBOX') 'apps.xbox' | Should -Be 'apply'
        $plan = Invoke-Plan -ProfileIds 'gaming' -Include 'Ui.B'
        @($plan | Where-Object { $_.Id -eq 'ui.b' }).Count | Should -Be 1
    }

    It 'ignores blank entries' {
        $plan = Invoke-Plan -ProfileIds '', ' ' -Include '', '  ' -Exclude ''
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a'
    }

    It 'skips a tweak whose state cannot be read instead of aborting the plan' {
        $state = { param($tweak) if ($tweak.id -eq 'ui.b') { throw 'boom' } else { 'not-applied' } }
        $plan = Invoke-Plan -ProfileIds 'gaming' -TestState $state
        Get-Action $plan 'ui.b' | Should -Be 'skip'
        Get-Reason $plan 'ui.b' | Should -Be 'state-unreadable'
        Get-Action $plan 'ui.a' | Should -Be 'apply'
    }

    It 'reports the current state before high-risk and confirmation reasons' {
        $applied = { param($tweak) 'applied' }
        Get-Reason (Invoke-Plan -ProfileIds 'unsafe' -TestState $applied) 'gaming.vbs-off' | Should -Be 'already-applied'
        $absent = { param($tweak) 'not-present' }
        Get-Reason (Invoke-Plan -ProfileIds 'lite' -TestState $absent) 'apps.onedrive' | Should -Be 'not-present'
    }
    It 'lists a tweak that only arrives through -Include' {
        $plan = Invoke-Plan -Include 'UI.B'
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
        Get-Action $plan 'ui.b' | Should -Be 'apply'
    }

    It 'trims spaces around -Include entries' {
        $plan = Invoke-Plan -Include ' ui.b '
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
    }

    It 'does not treat non-registry tweaks as policies on managed devices' {
        $plan = Invoke-Plan -Include 'svc.policy-path' -Environment (New-TestEnvironment -IsManaged $true)
        Get-Action $plan 'svc.policy-path' | Should -Be 'apply'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: FAIL, `New-TuneupPlan` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/Planner.ps1`:
```powershell
function Resolve-TuneupProfileId {
    param(
        [Parameter(Mandatory)][object[]]$Profiles,
        [Parameter(Mandatory)][string]$Name
    )
    $needle = $Name.Trim().ToLowerInvariant()
    foreach ($profileData in $Profiles) {
        if ($profileData.id -eq $needle -or @($profileData.aliases) -contains $needle) { return [string]$profileData.id }
    }
    throw (Get-TuneupText -Key 'err.unknownProfile' -Format $Name)
}

function Test-TuneupCompatible {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Environment)
    (@($Tweak.os.families) -contains $Environment.Family) -and
    ($Environment.Build -ge [int]$Tweak.os.minBuild) -and
    (@($Tweak.os.editions) -contains $Environment.Edition)
}

function Test-TuneupPolicyTweak {
    param([Parameter(Mandatory)]$Tweak)
    ($Tweak.type -eq 'registry') -and ([string]$Tweak.set.path -match '\\Policies\\')
}

function Get-TuneupCleanList {
    param([AllowEmptyCollection()][AllowNull()][string[]]$Values)
    @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

function New-TuneupPlan {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][object[]]$Profiles,
        [AllowEmptyCollection()][AllowNull()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][AllowNull()][string[]]$Include = @(),
        [AllowEmptyCollection()][AllowNull()][string[]]$Exclude = @(),
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)][scriptblock]$TestState,
        [switch]$Interactive
    )
    $ProfileIds = @(Get-TuneupCleanList $ProfileIds)
    $Include = @(Get-TuneupCleanList $Include)
    $Exclude = @(Get-TuneupCleanList $Exclude)

    # Hashtable lookups are case-insensitive; every id is canonicalized to the catalog's own spelling.
    $byId = @{}
    foreach ($tweak in $Catalog) { $byId[[string]$tweak.id] = $tweak }
    $canonical = {
        param([string]$TweakId)
        if ($byId.ContainsKey($TweakId)) { [string]$byId[$TweakId].id } else { $TweakId }
    }
    foreach ($tweakId in @($Include) + @($Exclude)) {
        if (-not $byId.ContainsKey($tweakId)) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
    }
    $Include = @($Include | ForEach-Object { & $canonical $_ })
    $Exclude = @($Exclude | ForEach-Object { & $canonical $_ })
    $profilesById = @{}
    foreach ($profileData in $Profiles) { $profilesById[[string]$profileData.id] = $profileData }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('base') + @($ProfileIds)) {
        $profileId = Resolve-TuneupProfileId -Profiles $Profiles -Name $name
        if ($selected -notcontains $profileId) { $selected.Add($profileId) }
    }

    $wanted = New-Object System.Collections.Generic.List[string]
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($profileId in $selected) {
        $profileData = $profilesById[$profileId]
        foreach ($tweakId in @($profileData.include | Where-Object { $_ } | ForEach-Object { & $canonical $_ })) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }
        foreach ($tweakId in @($profileData.keep | Where-Object { $_ } | ForEach-Object { & $canonical $_ })) { if ($keep -notcontains $tweakId) { $keep.Add($tweakId) } }
    }
    foreach ($tweakId in $Include) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }

    foreach ($tweakId in $wanted) {
        $tweak = $byId[$tweakId]
        if ($null -eq $tweak) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
        $requested = $Include -contains $tweakId
        $reason = $null
        if ($Exclude -contains $tweakId) { $reason = 'excluded' }
        elseif (($keep -contains $tweakId) -and -not $requested) { $reason = 'kept-by-profile' }
        elseif (-not (Test-TuneupCompatible -Tweak $tweak -Environment $Environment)) { $reason = 'incompatible' }
        elseif ($Environment.IsManaged -and (Test-TuneupPolicyTweak -Tweak $tweak)) { $reason = 'managed-device' }
        else {
            try { $state = & $TestState $tweak } catch { $state = 'unreadable' }
            if ($state -eq 'applied') { $reason = 'already-applied' }
            elseif ($state -eq 'not-present') { $reason = 'not-present' }
            elseif ($state -eq 'unreadable') { $reason = 'state-unreadable' }
            elseif ($tweak.risk -eq 'high' -and -not $requested) { $reason = 'high-risk-not-requested' }
            elseif ($tweak.ask -and -not $Interactive -and -not $requested) { $reason = 'needs-confirmation' }
        }
        [pscustomobject]@{
            Id     = $tweakId
            Tweak  = $tweak
            Action = $(if ($reason) { 'skip' } else { 'apply' })
            Reason = $reason
        }
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Planner.Tests.ps1`
Expected: 24 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/Planner.ps1 tests/Planner.Tests.ps1
git commit -m "feat: planificador con conflictos, compatibilidad y motivos"
```

---

### Task 9: Estado en disco (corridas, diario y seguridad de la carpeta de estado)

**Files:**
- Create: `engine/StateSecurity.ps1` — SID de confianza, ACL de la carpeta de máquina, creación atómica, pruebas de confianza (dueño, DACL, enlaces, carpeta base), conteo de enlaces por identificador, `Open-TuneupTrustedStream`, `Initialize-TuneupStateRoot`
- Create: `engine/StateFiles.ps1` — raíces de estado, lectura y escritura de archivos de estado, `Save-TuneupJson`, `Read-TuneupTrustedJson`, diario (`Add-TuneupJournalEntry`, `Read-TuneupJournal`)
- Create: `engine/Runs.ps1` — `New-TuneupRun`, `run.json`, listado y resolución de corridas, filtro por usuario, marcas de deshacer
- Modify: `tests/TestHelpers.ps1` — ayudantes de ACL (SDDL, reglas), SID de confianza inyectables y carpetas de máquina de prueba
- Test: `tests/StateSecurity.Tests.ps1`, `tests/StateFiles.Tests.ps1`, `tests/Runs.Tests.ps1`

Esta tarea empezó como un solo `engine/State.ps1` y se rehízo en tres revisiones de seguridad, así que el código ya no se copia en este plan: **la fuente de verdad son los tres archivos del motor y los tres de pruebas de arriba**. El diseño (dos carpetas, ACL, confianza por dueño, DACL y enlaces, carpeta base, `run.json`, reglas de `-Undo`) está en la especificación, §5 "Estado en disco". Las pruebas nunca tocan las carpetas reales: inyectan `-MachineRoot`/`-UserRoot` en `$TestDrive`, cambian los SID de confianza al usuario actual (`Use-CurrentUserAsTrusted`) para crear y verificar ACL reales dentro de una carpeta base endurecida (`New-TestMachineRoot`), y simulan `Get-Acl`, `Set-Acl`, `Test-TuneupAdmin` y la creación segura donde hace falta.

API que usan las tareas siguientes:

| Función | Qué hace |
|---|---|
| `New-TuneupRun [-StateRoot] [-Machine] [-MachineRoot] [-UserRoot]` | Abre una corrida y escribe `run.json`; devuelve `{ Id, Dir, Root, UserSid }` (`Root` = `machine`, `user` o `custom`) |
| `Add-TuneupJournalEntry -Path -Tweak -State [-Root]` | Anota un ajuste en el diario; la carpeta de usuario rechaza ajustes de máquina |
| `Read-TuneupJournal -Path [-Root]` | Lee el diario (confianza en la carpeta de máquina, sin entradas de máquina en la de usuario) |
| `Save-TuneupJson -Path -Object [-Root]` / `Write-TuneupStateFile -Path -Text [-Append] [-Root]` | Escriben archivos de estado; en la carpeta de máquina los crean ya protegidos |
| `Read-TuneupStateFile -Path [-Root] [-IgnoreUntrusted]` / `Read-TuneupTrustedJson -Path [-Root]` | Leen archivos de estado; lo no confiable o en uso se ignora con advertencia |
| `Get-TuneupRunList [-StateRoot]` | Corridas de las dos carpetas: `{ Id, Dir, Undone, Root, UserSid }` |
| `Resolve-TuneupRun [-StateRoot] -RunId <id\|last>` | Elige la corrida; `last` respeta las reglas de elevación y de usuario |
| `Get-TuneupRunJournal -Run` / `Read-TuneupRunJournal -Run` | Entradas que el usuario actual puede restaurar (`Entries`) y las de otro usuario (`Skipped` con sus ids, `SkippedEntries` completas) |
| `Get-TuneupUndoneTweakId -Run` | Ajustes ya deshechos uno por uno (`undone-tweaks.txt`) |
| `Assert-TuneupRunUndoable -Run` | Falla si la corrida es de la carpeta de máquina y el proceso no está elevado |

- [ ] **Step 1: Pruebas que fallan**

Escribir `tests/StateSecurity.Tests.ps1`, `tests/StateFiles.Tests.ps1`, `tests/Runs.Tests.ps1` y los ayudantes de `tests/TestHelpers.ps1`.

- [ ] **Step 2: Verificar que fallan**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/Runs.Tests.ps1` (y los otros dos)
Expected: FAIL, las funciones no se reconocen.

- [ ] **Step 3: Implementación**

Escribir `engine/StateSecurity.ps1`, `engine/StateFiles.ps1` y `engine/Runs.ps1`.

Nota: el sufijo de las corridas usa dos dígitos (`-02`, `-03`…) para que el orden alfabético coincida con el orden de creación.

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File build/test.ps1 -Path tests/StateSecurity.Tests.ps1`, luego `tests/StateFiles.Tests.ps1` y `tests/Runs.Tests.ps1`
Expected: 42, 21 y 30 passed (93 en total).

- [ ] **Step 5: Commit**

```bash
git add engine/StateSecurity.ps1 engine/StateFiles.ps1 engine/Runs.ps1 tests/TestHelpers.ps1 tests/StateSecurity.Tests.ps1 tests/StateFiles.Tests.ps1 tests/Runs.Tests.ps1
git commit -m "feat: corridas y diario en disco"
```

Historia (ya incluida en el estado final): `fix: diario tolerante a cortes y listado de corridas estricto`, `fix: carpeta de estado protegida contra diarios plantados`, `fix: confianza del estado por DACL, enlaces y usuario` y `fix: deshacer según elevación, carpeta base validada y estado en tres archivos`.

---

### Task 10: Ejecutor

**Files:**
- Create: `engine/Executor.ps1`
- Test: `tests/Executor.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Executor.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:One = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'One'; kind = 'DWord'; value = 1 })
    $script:Two = New-TestTweak -Id 'test.two' -RebootRequired $true -Set ([pscustomobject]@{ path = $Key; name = 'Two'; kind = 'String'; value = 'x' })
    function New-TestPlan {
        New-TuneupPlan -Catalog @($One, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak }
    }
}

Describe 'Invoke-TuneupPlan' {
    BeforeEach {
        $script:Run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
    }

    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'applies the plan, journals each tweak first and reports the result' {
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'applied,applied'
        $results[0].rebootRequired | Should -BeFalse
        $results[1].rebootRequired | Should -BeTrue
        $journal = @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl'))
        $journal.Count | Should -Be 2
        $journal[0].id | Should -Be 'test.one'
        $journal[0].state.exists | Should -BeFalse
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
    }

    It 'passes skipped items through with their reason' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'One' -PropertyType DWord -Value 1 | Out-Null
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'skipped'
        $results[0].reason | Should -Be 'already-applied'
    }

    It 'marks a tweak that does not stick as not-applied' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'not-applied,not-applied'
    }

    It 'continues after a failing tweak' {
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { throw 'boom' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        $results[0].status | Should -Be 'failed'
        $results[0].error | Should -Be 'boom'
        $results[1].status | Should -Be 'applied'
    }

    It 'stops applying once the journal cannot be written' {
        Mock -ModuleName Tuneup Add-TuneupJournalEntry { throw 'disk full' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan @(New-TestPlan) -RunDir $Run.Dir)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'skipped,skipped'
        ($results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'journal-error,journal-error'
        $results[0].error | Should -Be 'disk full'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'fails a tweak whose state cannot be read, without journaling or applying it' {
        $plan = @(New-TestPlan)
        Mock -ModuleName Tuneup Get-RegistryTweakState { throw 'cannot read' } -ParameterFilter { $Tweak.id -eq 'test.one' }
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { } -ParameterFilter { $Tweak.id -eq 'test.one' }
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $Run.Dir)
        $results[0].status | Should -Be 'failed'
        $results[0].error | Should -Be 'cannot read'
        $results[1].status | Should -Be 'applied'
        $journal = @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl'))
        $journal.Count | Should -Be 1
        $journal[0].id | Should -Be 'test.two'
        Should -Invoke -ModuleName Tuneup Set-RegistryTweakDesired -Times 0 -ParameterFilter { $Tweak.id -eq 'test.one' }
    }

    It 'does not leak handler output into the results' {
        $plan = @(New-TestPlan)
        Mock -ModuleName Tuneup Set-RegistryTweakDesired { 'noise' }
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $Run.Dir)
        $results.Count | Should -Be 2
        @($results | Where-Object { $_ -is [string] }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: FAIL, `Invoke-TuneupPlan` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/Executor.ps1`:
```powershell
function New-TuneupResult {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason,
        [string]$ErrorText
    )
    [pscustomobject]@{
        id             = $Item.Id
        title          = Get-TuneupTitle -Tweak $Item.Tweak
        status         = $Status
        reason         = $(if ($Reason) { $Reason } else { $null })
        error          = $(if ($ErrorText) { $ErrorText } else { $null })
        rebootRequired = [bool]$Item.Tweak.rebootRequired
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
            $null = Set-TuneupDesired -Tweak $tweak
            if ((Test-TuneupState -Tweak $tweak) -eq 'applied') {
                New-TuneupResult -Item $item -Status 'applied'
            } else {
                New-TuneupResult -Item $item -Status 'not-applied'
            }
        } catch {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $_.Exception.Message
        }
    }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Executor.Tests.ps1`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/Executor.ps1 tests/Executor.Tests.ps1
git commit -m "feat: ejecutor con diario previo y verificación"
```

---

### Task 11: Deshacer y estado actual

**Files:**
- Create: `engine/Undo.ps1`
- Test: `tests/Undo.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

`tests/Undo.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:One = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'One'; kind = 'DWord'; value = 1 })
    $script:Two = New-TestTweak -Id 'test.two' -Set ([pscustomobject]@{ path = $Key; name = 'Two'; kind = 'String'; value = 'x' })
    function Invoke-TestApply([string]$Root) {
        $plan = @(New-TuneupPlan -Catalog @($One, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        $run = New-TuneupRun -StateRoot $Root
        $results = @(Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir)
        Save-TuneupJson -Path (Join-Path $run.Dir 'result.json') -Object ([pscustomobject]@{ results = $results })
        $run
    }
}

Describe 'Undo and status' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        $env:TUNEUP_TEST_FAIL_RESTORE = $null
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'restores the exact previous state' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'Two' -PropertyType String -Value 'old' | Out-Null
        $run = Invoke-TestApply $Root
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'restored,restored'
        $item = Get-Item -LiteralPath $Key
        $item.GetValueNames() -contains 'One' | Should -BeFalse
        $item.GetValue('Two') | Should -Be 'old'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
    }

    It 'removes keys that did not exist before' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run | Out-Null
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'reports a failure when the undo cannot be recorded' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Save-TuneupJson { throw [System.UnauthorizedAccessException]::new('Access denied') } -ParameterFilter { $Path -like '*undone.json' }
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.status }) -join ',' | Should -Be 'restored,restored,failed'
        $results[2].error | Should -BeLike '*Access denied*'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'refuses to undo a machine run without elevation' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        $machineRun = [pscustomobject]@{ Id = $run.Id; Dir = $run.Dir; Root = 'machine'; UserSid = $run.UserSid }
        { Invoke-TuneupUndo -Run $machineRun } | Should -Throw '*needs an elevated process'
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
    }

    It 'does not mark a run of another user as undone' {
        $run = Invoke-TestApply $Root
        $foreign = [pscustomobject]@{ Id = $run.Id; Dir = $run.Dir; Root = $run.Root; UserSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        $results = @(Invoke-TuneupUndo -Run $foreign -WarningAction SilentlyContinue)
        ($results | ForEach-Object { "$($_.id):$($_.status):$($_.reason)" }) -join ',' | Should -Be 'test.two:skipped:other-user,test.one:skipped:other-user'
        $results[0].title | Should -Be 'Title test.two'
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone-tweaks.txt') | Should -BeFalse
    }

    It 'skips a single tweak of another user' {
        $run = Invoke-TestApply $Root
        $foreign = [pscustomobject]@{ Id = $run.Id; Dir = $run.Dir; Root = $run.Root; UserSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        $results = @(Invoke-TuneupUndo -Run $foreign -TweakId 'test.one' -WarningAction SilentlyContinue)
        ($results | ForEach-Object { "$($_.id):$($_.status):$($_.reason)" }) -join ',' | Should -Be 'test.one:skipped:other-user'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }

    It 'undoes a single tweak' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        $item = Get-Item -LiteralPath $Key
        $item.GetValueNames() -contains 'One' | Should -BeFalse
        $item.GetValue('Two') | Should -Be 'x'
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.two'
    }

    It 'throws when the tweak is not in the run' {
        $run = Invoke-TestApply $Root
        { Invoke-TuneupUndo -Run $run -TweakId 'test.nope' } | Should -Throw
    }

    It 'reports ok and drift' {
        Invoke-TestApply $Root | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $status = @(Get-TuneupStatus -StateRoot $Root)
        ($status | Where-Object { $_.id -eq 'test.one' }).status | Should -Be 'drift'
        ($status | Where-Object { $_.id -eq 'test.two' }).status | Should -Be 'ok'
    }

    It 'ignores runs that were undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run | Out-Null
        @(Get-TuneupStatus -StateRoot $Root).Count | Should -Be 0
    }

    It 'plans nothing when applied twice' {
        Invoke-TestApply $Root | Out-Null
        $plan = @(New-TuneupPlan -Catalog @($One, $Two) -Profiles @(New-TestProfile -Id 'base' -Include @('test.one', 'test.two')) `
            -Environment (New-TestEnvironment) -TestState { param($tweak) Test-TuneupState -Tweak $tweak })
        @($plan | Where-Object { $_.Action -eq 'apply' }).Count | Should -Be 0
    }

    It 'keeps the run pending when a restore fails and finishes it on retry' {
        $run = Invoke-TestApply $Root
        Mock -ModuleName Tuneup Restore-TuneupState { throw 'restore broke' } -ParameterFilter { $Tweak.id -eq 'test.two' }
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.id + ':' + $_.status }) -join ',' | Should -Be 'test.two:failed,test.one:restored'
        $results[0].error | Should -BeLike '*restore broke*'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone-tweaks.txt') | Should -BeTrue
        (Get-Item -LiteralPath $Key).GetValueNames() -contains 'One' | Should -BeFalse
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        Should -Invoke -ModuleName Tuneup Restore-TuneupState -Times 1 -Exactly -ParameterFilter { $Tweak.id -eq 'test.two' }
    }

    It 'retries the failed tweaks through the last pending run and then marks it undone' {
        $run = Invoke-TestApply $Root
        $env:TUNEUP_TEST_FAIL_RESTORE = '1'
        Mock -ModuleName Tuneup Restore-TuneupState {
            if ($env:TUNEUP_TEST_FAIL_RESTORE) { throw 'restore broke' }
            Restore-RegistryTweakState -Tweak $Tweak -State $State
        } -ParameterFilter { $Tweak.id -eq 'test.two' }
        Invoke-TuneupUndo -Run $run | Out-Null
        $env:TUNEUP_TEST_FAIL_RESTORE = $null
        $last = Resolve-TuneupRun -StateRoot $Root -RunId 'last'
        $last.Id | Should -Be $run.Id
        $results = @(Invoke-TuneupUndo -Run $last)
        ($results | ForEach-Object { $_.id + ':' + $_.status }) -join ',' | Should -Be 'test.two:restored'
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
        (Get-Item -LiteralPath $Key).GetValueNames() -contains 'Two' | Should -BeFalse
        $null -eq (Resolve-TuneupRun -StateRoot $Root -RunId 'last') | Should -BeTrue
    }

    It 'skips a tweak that was already undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 7
        $results = @(Invoke-TuneupUndo -Run $run -TweakId 'test.one')
        $results.Count | Should -Be 1
        $results[0].status | Should -Be 'skipped'
        $results[0].reason | Should -Be 'already-undone'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 7
    }

    It 'does not restore again a tweak undone on its own when the whole run is undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 7
        $results = @(Invoke-TuneupUndo -Run $run)
        ($results | ForEach-Object { $_.id + ':' + $_.status }) -join ',' | Should -Be 'test.two:restored'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 7
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
    }

    It 'marks the run undone once every tweak was undone one by one' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run -TweakId 'test.one' | Out-Null
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeFalse
        Invoke-TuneupUndo -Run $run -TweakId 'test.two' | Out-Null
        Test-Path -LiteralPath (Join-Path $run.Dir 'undone.json') | Should -BeTrue
        @(Get-TuneupStatus -StateRoot $Root).Count | Should -Be 0
    }

    It 'leaves out of the status a tweak whose apply failed' {
        $run = Invoke-TestApply $Root
        $results = @(
            [pscustomobject]@{ id = 'test.one'; status = 'failed' },
            [pscustomobject]@{ id = 'test.two'; status = 'applied' }
        )
        Save-TuneupJson -Path (Join-Path $run.Dir 'result.json') -Object ([pscustomobject]@{ results = $results })
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.two'
    }

    It 'counts the journaled tweaks of a run that was cut before its result' {
        $run = Invoke-TestApply $Root
        Remove-Item -LiteralPath (Join-Path $run.Dir 'result.json')
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.id } | Sort-Object) -join ',' | Should -Be 'test.one,test.two'
    }

    It 'takes the definition from the latest run for the same tweak' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'OneB' -PropertyType DWord -Value 1 | Out-Null
        $first = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'One'; kind = 'DWord'; value = 1 })
        $second = New-TestTweak -Id 'test.one' -Set ([pscustomobject]@{ path = $Key; name = 'OneB'; kind = 'DWord'; value = 1 })
        New-RunFolder -Root $Root -Id '20250101-000001' -Tweaks @($first) | Out-Null
        New-RunFolder -Root $Root -Id '20250101-000002' -Tweaks @($second) | Out-Null
        $status = @(Get-TuneupStatus -StateRoot $Root)
        $status.Count | Should -Be 1
        $status[0].runId | Should -Be '20250101-000002'
        $status[0].status | Should -Be 'ok'
    }

    It 'reports unknown when the state cannot be read' {
        Invoke-TestApply $Root | Out-Null
        Mock -ModuleName Tuneup Test-TuneupState { throw 'cannot read' }
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.status } | Select-Object -Unique) -join ',' | Should -Be 'unknown'
    }

    It 'reports not-present when the handler says so' {
        Invoke-TestApply $Root | Out-Null
        Mock -ModuleName Tuneup Test-TuneupState { 'not-present' }
        (@(Get-TuneupStatus -StateRoot $Root) | ForEach-Object { $_.status } | Select-Object -Unique) -join ',' | Should -Be 'not-present'
    }

    It 'refuses to undo a run that was already undone' {
        $run = Invoke-TestApply $Root
        Invoke-TuneupUndo -Run $run | Out-Null
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'One' -PropertyType DWord -Value 9 | Out-Null
        { Invoke-TuneupUndo -Run $run } | Should -Throw '*already undone*'
        $resolved = Resolve-TuneupRun -StateRoot $Root -RunId $run.Id
        $resolved.Undone | Should -BeTrue
        { Invoke-TuneupUndo -Run $resolved } | Should -Throw '*already undone*'
        { Invoke-TuneupUndo -Run $resolved -TweakId 'test.one' } | Should -Throw '*already undone*'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 9
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Undo.Tests.ps1`
Expected: FAIL, `Invoke-TuneupUndo` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/Undo.ps1`:
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
    $skip = { param($entry, $reason) [pscustomobject]@{ id = $entry.id; title = Get-TuneupTitle -Tweak $entry.tweak; status = 'skipped'; reason = $reason; error = $null } }
    if ($TweakId) {
        $entries = @($entries | Where-Object { $_.id -eq $TweakId })
        $foreign = @($foreign | Where-Object { $_.id -eq $TweakId })
        if (-not $entries.Count -and -not $foreign.Count) { throw (Get-TuneupText -Key 'err.tweakNotInRun' -Format $TweakId) }
        if ($alreadyUndone -contains $TweakId) {
            # Restoring again would overwrite whatever the tweak holds now with a stale value.
            return (& $skip (@($entries) + @($foreign))[0] 'already-undone')
        }
        if (-not $entries.Count) { return (& $skip $foreign[0] 'other-user') }
    } else {
        $entries = @($entries | Where-Object { $alreadyUndone -notcontains $_.id })
        $foreign = @($foreign | Where-Object { $alreadyUndone -notcontains $_.id })
    }
    [array]::Reverse($entries)
    [array]::Reverse($foreign)
    $results = @(foreach ($entry in $entries) {
        try {
            Restore-TuneupState -Tweak $entry.tweak -State $entry.state
            [pscustomobject]@{ id = $entry.id; title = Get-TuneupTitle -Tweak $entry.tweak; status = 'restored'; reason = $null; error = $null }
        } catch {
            [pscustomobject]@{ id = $entry.id; title = Get-TuneupTitle -Tweak $entry.tweak; status = 'failed'; reason = $null; error = $_.Exception.Message }
        }
    })
    $results += @(foreach ($entry in $foreign) { & $skip $entry 'other-user' })
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
        $results += [pscustomobject]@{ id = $null; title = "run $($Run.Id)"; status = 'failed'; reason = $null; error = "The undo could not be recorded: $($_.Exception.Message)" }
    }
    $results
}

function Get-TuneupStatus {
    param([string]$StateRoot)
    $latest = [ordered]@{}
    foreach ($run in @(Get-TuneupRunList -StateRoot $StateRoot)) {
        if ($run.Undone) { continue }
        $undoneIds = @(Get-TuneupUndoneTweakId -Run $run)
        $touchedIds = $null
        $result = Read-TuneupTrustedJson -Path (Join-Path $run.Dir 'result.json') -Root $run.Root
        if ($null -ne $result) {
            $touchedIds = @($result.results | Where-Object { $_.status -eq 'applied' -or $_.status -eq 'not-applied' } | ForEach-Object { $_.id })
        }
        foreach ($entry in @(Read-TuneupRunJournal -Run $run)) {
            if ($undoneIds -contains $entry.id) { continue }
            if ($null -ne $touchedIds -and $touchedIds -notcontains $entry.id) { continue }
            $latest[[string]$entry.id] = [pscustomobject]@{ tweak = $entry.tweak; runId = $run.Id }
        }
    }
    foreach ($id in @($latest.Keys)) {
        $item = $latest[$id]
        try {
            $state = Test-TuneupState -Tweak $item.tweak
            $status = switch ($state) { 'applied' { 'ok' } 'not-applied' { 'drift' } default { 'not-present' } }
        } catch {
            $status = 'unknown'
        }
        [pscustomobject]@{ id = $id; title = Get-TuneupTitle -Tweak $item.tweak; status = $status; runId = $item.runId }
    }
}
```

Nota: si una corrida se cortó antes de escribir `result.json`, `$touchedIds` queda en `$null` y se consideran todos los ajustes del diario, porque pudieron quedar aplicados.

Nota: todo lo que se lee de una corrida pasa por los lectores de la Task 9: `Get-TuneupRunJournal` (confianza de la carpeta de máquina, sin entradas de máquina en la de usuario; las entradas de usuario de otra persona quedan en `Skipped`), `Read-TuneupTrustedJson` para `result.json`, `Get-TuneupUndoneTweakId` para `undone-tweaks.txt` y `Undone` del listado para `undone.json`. Las marcas se escriben con `Save-TuneupJson`/`Write-TuneupStateFile`, que en la carpeta de máquina crean el archivo ya protegido. `Assert-TuneupRunUndoable` exige elevación para cualquier corrida de la carpeta de máquina.

Nota: `undone.json` se escribe solo cuando todos los ajustes de la corrida quedaron restaurados (ya anotados antes o restaurados ahora). Si alguno falló o es de otro usuario, se anotan en `undone-tweaks.txt` solo los restaurados y la corrida sigue pendiente: `-Undo last` reintenta lo que falta y un deshacer completo posterior salta los ya anotados. `-TweakId` sobre un ajuste ya deshecho no restaura de nuevo: devuelve `skipped` con `reason = 'already-undone'`. Al deshacer ajuste por ajuste, cuando el último queda anotado también se escribe `undone.json`. Una corrida ya deshecha (`undone.json` confiable) no se deshace de nuevo: `Invoke-TuneupUndo` falla con `err.runAlreadyUndone`; se consulta la marca y no solo `$Run.Undone`, porque un objeto de corrida armado antes del deshacer no la trae.

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Undo.Tests.ps1`
Expected: 22 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/Undo.ps1 tests/Undo.Tests.ps1
git commit -m "feat: deshacer por corrida o ajuste y estado con deriva"
```

---

### Task 12: Punto de restauración

**Files:**
- Create: `engine/RestorePoint.ps1`
- Test: `tests/RestorePoint.Tests.ps1`

- [ ] **Step 1: Prueba que falla**

Los cmdlets de restauración no existen en Windows Server (el runner de CI); la prueba define funciones vacías para poder simularlos.

`tests/RestorePoint.Tests.ps1`:
```powershell
BeforeAll {
    if (-not (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue)) {
        function global:Get-ComputerRestorePoint { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    }
    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        function global:Checkpoint-Computer { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    }
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
}

Describe 'New-TuneupRestorePoint' {
    BeforeEach {
        $script:Points = 1
        Mock -ModuleName Tuneup Get-ComputerRestorePoint {
            if ($script:Points -gt 0) { 1..$script:Points | ForEach-Object { [pscustomobject]@{ SequenceNumber = $_ } } }
        }
    }

    It 'reports created when a new point appears' {
        Mock -ModuleName Tuneup Checkpoint-Computer { $script:Points++ }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'created'
    }

    It 'reports skipped-recent when Windows keeps the last one' {
        Mock -ModuleName Tuneup Checkpoint-Computer { }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'skipped-recent'
    }

    It 'reports failed when the checkpoint throws' {
        Mock -ModuleName Tuneup Checkpoint-Computer { throw 'disabled' }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'failed'
    }

    It 'reports unavailable when restore points cannot be listed' {
        Mock -ModuleName Tuneup Get-ComputerRestorePoint { throw 'not supported' }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'unavailable'
    }
}
```

- [ ] **Step 2: Verificar que falla**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/RestorePoint.Tests.ps1`
Expected: FAIL, `New-TuneupRestorePoint` no se reconoce.

- [ ] **Step 3: Implementación**

`engine/RestorePoint.ps1`:
```powershell
function New-TuneupRestorePoint {
    param([Parameter(Mandatory)][string]$Description)
    try {
        $before = @(Get-ComputerRestorePoint -ErrorAction Stop).Count
    } catch {
        return 'unavailable'
    }
    try {
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        return 'failed'
    }
    $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    if ($after -gt $before) { 'created' } else { 'skipped-recent' }
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/RestorePoint.Tests.ps1`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add engine/RestorePoint.ps1 tests/RestorePoint.Tests.ps1
git commit -m "feat: punto de restauración con resultado explícito"
```

---

### Task 13: Salida y CLI

**Files:**
- Create: `engine/Output.ps1`, `tuneup.ps1`
- Create: `tests/fixtures/catalog/test.json`, `tests/fixtures/profiles/base.json`, `extra.json`, `nested.json`, `system.json`
- Modify: `engine/Tuneup.psm1` y `i18n/*.json` (Task 1), `engine/Runs.ps1` (Task 9), `engine/Undo.ps1` y `tests/Undo.Tests.ps1` (Task 11), `tests/Runs.Tests.ps1`
- Test: `tests/Cli.Tests.ps1`, `tests/Output.Tests.ps1`

Decisiones de la revisión de esta tarea (ya incluidas en el código de abajo y en los bloques de las tareas 1, 9 y 11):

- **Advertencias con `-Json`.** `powershell.exe -File` escribe las advertencias en la salida estándar, así que cada llamada al motor pasa por `Invoke-TuneupStep`, que con `-Json` redirige el flujo de advertencias (`3>&1`) y las guarda, sin repetir, para el arreglo `warnings` que llevan todos los documentos (plan, apply, status, undo y error). Sin `-Json` se muestran como siempre. Se descartó `$WarningPreference = 'SilentlyContinue'`: una herramienta pública no debe callar advertencias de seguridad del estado. `result.json` no lleva `warnings`.
- **JSON en ASCII.** `Write-TuneupJson` escapa todo carácter no ASCII como `\uXXXX`: la página de códigos de la consola no puede alterar los acentos. El entorno va en camelCase (`ConvertTo-TuneupEnvironmentView`); el objeto interno sigue en PascalCase.
- **Códigos de salida.** Aplicar: un resultado con motivo `journal-error` cuenta como no hecho (`summary.journalErrors`, aparte de `skipped`): `1` si no se aplicó, quedó sin efecto ni falló nada; si no, `2`. Si `result.json` no se puede guardar después de aplicar, `Save-TuneupApplyReport` avisa, el reporte igual sale y el código es `2`. Deshacer: `0` todo restaurado (lo ya deshecho no cuenta), `2` parcial (fallos o ajustes de otro usuario), `1` nada restaurado. Las reglas viven en `Get-TuneupApplyExitCode` y `Get-TuneupUndoExitCode` para probarlas sin simular fallos de disco.
- **Otro usuario.** `Invoke-TuneupUndo` devuelve `skipped` con motivo `other-user` para cada entrada de otro usuario (`SkippedEntries` del diario); el resumen para personas cuenta los omitidos.
- **Parámetros.** Rutas relativas de `-StateRoot`, `-CatalogPath` y `-ProfilesPath` se resuelven con `GetUnresolvedProviderPathFromPSPath`. Se rechazan (`err.badArgs`, código `1`): `-Tweak` sin `-Undo`, `-Status` con `-Undo`, y `-Status` o `-Undo` con `-Profile`, `-Include`, `-Exclude`, `-WhatIf` o `-Yes`.
- **Elevación.** El plan JSON lleva `requiresAdmin`; `-WhatIf` sin elevar y con cambios de sistema lo recuerda con `plan.needsAdmin`. Al deshacer, la lectura previa del diario (para saber si hace falta elevación) va con `-WarningAction SilentlyContinue` para no repetir avisos.
- **Motor.** `engine/Tuneup.psm1` fija `$ErrorActionPreference = 'Stop'` para todo el módulo.

- [ ] **Step 1: Fixtures**

`test.machine` (HKLM) solo se usa para planificar y para comprobar el rechazo sin elevación: nunca se escribe. `test.four` vive en una subclave para poder negar la escritura solo ahí.

`tests/fixtures/catalog/test.json`:
```json
{
  "tweaks": [
    {
      "id": "test.one",
      "title": { "es": "Prueba uno", "en": "Test one" },
      "why": { "es": "Prueba", "en": "Test" },
      "risk": "low", "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry", "scope": "user",
      "set": { "path": "HKCU:\\Software\\windows-tuneup-test", "name": "One", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://example.com/test"]
    },
    {
      "id": "test.two",
      "title": { "es": "Prueba dos", "en": "Test two" },
      "why": { "es": "Prueba", "en": "Test" },
      "risk": "low", "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry", "scope": "user",
      "set": { "path": "HKCU:\\Software\\windows-tuneup-test", "name": "Two", "kind": "String", "value": "x" },
      "rebootRequired": true,
      "sources": ["https://example.com/test"]
    },
    {
      "id": "test.three",
      "title": { "es": "Prueba tres: configuración", "en": "Test three: settings" },
      "why": { "es": "Prueba", "en": "Test" },
      "risk": "low", "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry", "scope": "user",
      "set": { "path": "HKCU:\\Software\\windows-tuneup-test", "name": "Three", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://example.com/test"]
    },
    {
      "id": "test.four",
      "title": { "es": "Prueba cuatro", "en": "Test four" },
      "why": { "es": "Prueba", "en": "Test" },
      "risk": "low", "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry", "scope": "user",
      "set": { "path": "HKCU:\\Software\\windows-tuneup-test\\Sub", "name": "Four", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://example.com/test"]
    },
    {
      "id": "test.machine",
      "title": { "es": "Prueba de sistema", "en": "System test" },
      "why": { "es": "Prueba", "en": "Test" },
      "risk": "low", "ask": false,
      "os": { "families": ["10", "11"], "minBuild": 19041, "editions": ["Home", "Pro", "Enterprise", "Education"] },
      "type": "registry", "scope": "machine",
      "set": { "path": "HKLM:\\SOFTWARE\\windows-tuneup-test", "name": "Machine", "kind": "DWord", "value": 1 },
      "rebootRequired": false,
      "sources": ["https://example.com/test"]
    }
  ]
}
```

`tests/fixtures/profiles/base.json`:
```json
{
  "id": "base", "aliases": [],
  "title": { "es": "Base", "en": "Base" },
  "description": { "es": "Prueba", "en": "Test" },
  "include": ["test.one", "test.two"], "keep": []
}
```

`tests/fixtures/profiles/extra.json`:
```json
{
  "id": "extra", "aliases": ["adicional"],
  "title": { "es": "Extra", "en": "Extra" },
  "description": { "es": "Prueba", "en": "Test" },
  "include": ["test.three"], "keep": []
}
```

`tests/fixtures/profiles/nested.json`:
```json
{
  "id": "nested", "aliases": [],
  "title": { "es": "Anidado", "en": "Nested" },
  "description": { "es": "Prueba", "en": "Test" },
  "include": ["test.four"], "keep": []
}
```

`tests/fixtures/profiles/system.json`:
```json
{
  "id": "system", "aliases": [],
  "title": { "es": "Sistema", "en": "System" },
  "description": { "es": "Prueba", "en": "Test" },
  "include": ["test.machine"], "keep": []
}
```

- [ ] **Step 2: Pruebas que fallan**

La prueba del diario usa que Windows PowerShell 5.1 no acepta rutas de 260 caracteres o más: la carpeta de la corrida y sus archivos cortos caben, `snapshot.jsonl` no. Si el PowerShell acepta rutas largas, la prueba se marca como omitida. Las de elevación se omiten en un proceso elevado (los runners de CI lo son).

`tests/Cli.Tests.ps1`:
```powershell
BeforeDiscovery {
    $script:Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:SubKey = 'HKCU:\Software\windows-tuneup-test\Sub'
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    function Invoke-Tuneup([string[]]$Arguments, [string]$Lang = 'en') {
        $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tuneup.ps1') `
            -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles') `
            -StateRoot $script:Root -Force -Lang $Lang @Arguments
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
    function Get-Ids($Items) { ($Items | ForEach-Object { $_.id }) -join ',' }
    function Get-RunDir { @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'runs') -Directory | Sort-Object Name)[-1].FullName }
    # The whole standard output has to be one JSON document, with nothing printed around it.
    function ConvertFrom-PureJson([string]$Text) {
        $Text.Trim() | Should -Match '^\{[\s\S]*\}$'
        $Text | ConvertFrom-Json
    }
    # Denies the current user writing values in the Sub key only, so a change there fails. The key is
    # opened for its ACL alone: Set-Acl would ask for write access, which the deny itself blocks.
    function Set-TestSetValueDeny([switch]$Remove) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\windows-tuneup-test\Sub',
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]'ReadPermissions, ChangePermissions')
        try {
            $acl = $key.GetAccessControl()
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList `
                ([Security.Principal.WindowsIdentity]::GetCurrent().User), 'SetValue', 'None', 'None', 'Deny'
            if ($Remove) { [void]$acl.RemoveAccessRule($rule) } else { $acl.AddAccessRule($rule) }
            $key.SetAccessControl($acl)
        } finally {
            $key.Close()
        }
    }
    function Remove-TestKey {
        if (Test-Path -LiteralPath $SubKey) { Set-TestSetValueDeny -Remove }
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }
}

Describe 'ConvertTo-TuneupList' {
    It 'splits comma separated values from a single argument' {
        (ConvertTo-TuneupList -Value @('base, extra', 'dev')) -join '|' | Should -Be 'base|extra|dev'
    }
}

Describe 'tuneup.ps1' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Remove-TestKey
    }

    AfterAll {
        Remove-TestKey
    }

    It 'shows the plan as JSON without changing anything' {
        $result = Invoke-Tuneup @('-WhatIf', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.schemaVersion | Should -Be 1
        $json.command | Should -Be 'plan'
        $json.requiresAdmin | Should -BeFalse
        Get-Ids $json.items | Should -Be 'test.one,test.two'
        $json.environment.PSObject.Properties.Name -join ',' | Should -Be 'build,ubr,family,edition,isServer,isManaged,isAdmin,hasBattery,pendingReboot'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'applies, reports and is idempotent' {
        $result = Invoke-Tuneup @('-Yes', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'apply'
        $json.summary.applied | Should -Be 2
        $json.rebootRequired | Should -BeTrue
        $json.restorePoint | Should -Be 'not-needed'
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
        $saved = Get-Content -LiteralPath (Join-Path $json.runDir 'result.json') -Raw | ConvertFrom-Json
        $saved.runId | Should -Be $json.runId
        $saved.PSObject.Properties.Name | Should -Not -Contain 'warnings'
        $again = (Invoke-Tuneup @('-WhatIf', '-Json')).Output | ConvertFrom-Json
        $again.summary.apply | Should -Be 0
    }

    It 'exits with 2 when part of the plan fails' {
        New-Item -Path $SubKey -Force | Out-Null
        Set-TestSetValueDeny
        $result = Invoke-Tuneup @('-Profile', 'nested', '-Yes', '-Json')
        $result.ExitCode | Should -Be 2
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.applied | Should -Be 2
        $json.summary.failed | Should -Be 1
        ($json.results | Where-Object { $_.id -eq 'test.four' }).status | Should -Be 'failed'
    }

    It 'exits with 1 when the journal cannot be written before any change' {
        # Windows PowerShell 5.1 does not take paths of 260 characters or more: the run folder and
        # its small files fit, the journal (snapshot.jsonl) does not.
        $script:Root = Join-Path $TestDrive ('j' * (224 - $TestDrive.Length))
        New-Item -ItemType Directory -Path $Root | Out-Null
        $probe = Join-Path $Root ('p' * (260 - $Root.Length))
        try { [System.IO.File]::WriteAllText($probe, 'x') } catch { $probe = $null }
        if ($probe) {
            Remove-Item -LiteralPath $probe -Force
            Set-ItResult -Skipped -Because 'this PowerShell accepts long paths'
            return
        }
        $result = Invoke-Tuneup @('-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.applied | Should -Be 0
        $json.summary.journalErrors | Should -Be 2
        ($json.results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'journal-error,journal-error'
        $json.results[0].error | Should -Not -BeNullOrEmpty
        (Get-ChildItem -LiteralPath (Get-RunDir) -Name) | Should -Contain 'result.json'
        Test-Path -LiteralPath $Key | Should -BeFalse
        $script:Root = Join-Path $TestDrive ('k' * (224 - $TestDrive.Length))
        $human = Invoke-Tuneup @('-Yes')
        $human.ExitCode | Should -Be 1
        $human.Output | Should -Match 'the backup could not be saved'
    }

    It 'reports drift in -Status' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-Status', '-Json')).Output
        ($json.items | Where-Object { $_.id -eq 'test.one' }).status | Should -Be 'drift'
        ($json.items | Where-Object { $_.id -eq 'test.two' }).status | Should -Be 'ok'
    }

    It 'undoes the last run' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $result.Output).summary.restored | Should -Be 2
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'exits with 2 when an undo restores only part of the run' {
        New-Item -Path $SubKey -Force | Out-Null
        New-ItemProperty -LiteralPath $SubKey -Name 'Four' -PropertyType DWord -Value 0 | Out-Null
        (Invoke-Tuneup @('-Profile', 'nested', '-Yes', '-Json')).ExitCode | Should -Be 0
        Set-TestSetValueDeny
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 2
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.restored | Should -Be 2
        $json.summary.failed | Should -Be 1
        (Get-ItemProperty -LiteralPath $SubKey).Four | Should -Be 1
    }

    It 'skips a tweak that was already undone and refuses to undo a run twice' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $runId = Split-Path (Get-RunDir) -Leaf
        (Invoke-Tuneup @('-Undo', $runId, '-Tweak', 'test.two', '-Json')).ExitCode | Should -Be 0
        $again = Invoke-Tuneup @('-Undo', $runId, '-Tweak', 'test.two', '-Json')
        $again.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $again.Output
        $json.results[0].status | Should -Be 'skipped'
        $json.results[0].reason | Should -Be 'already-undone'
        $json.summary.skipped | Should -Be 1
        (Invoke-Tuneup @('-Undo', $runId, '-Json')).ExitCode | Should -Be 0
        $twice = Invoke-Tuneup @('-Undo', $runId, '-Json')
        $twice.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $twice.Output).message | Should -Match 'already undone'
    }

    It 'accepts comma separated profiles and aliases' {
        $json = (Invoke-Tuneup @('-Profile', 'adicional,base', '-WhatIf', '-Json')).Output | ConvertFrom-Json
        Get-Ids $json.items | Should -Be 'test.one,test.two,test.three'
    }

    It 'resolves a relative -StateRoot against the current folder' {
        $script:Root = [guid]::NewGuid().ToString()
        Push-Location -LiteralPath $TestDrive
        try {
            $result = Invoke-Tuneup @('-Yes', '-Json')
        } finally {
            Pop-Location
        }
        $result.ExitCode | Should -Be 0
        (ConvertFrom-PureJson $result.Output).runDir | Should -BeLike (Join-Path $TestDrive "$Root\runs\*")
    }

    It 'writes JSON as pure ASCII and keeps the accents' {
        $result = Invoke-Tuneup @('-Profile', 'extra', '-WhatIf', '-Json') -Lang 'es'
        [regex]::IsMatch($result.Output, '[^\x00-\x7F]') | Should -BeFalse
        $json = ConvertFrom-PureJson $result.Output
        ($json.items | Where-Object { $_.id -eq 'test.three' }).title | Should -Be ('Prueba tres: configuraci' + [char]0x00F3 + 'n')
        $failure = Invoke-Tuneup @('-Tweak', 'test.one', '-Json') -Lang 'es'
        [regex]::IsMatch($failure.Output, '[^\x00-\x7F]') | Should -BeFalse
        (ConvertFrom-PureJson $failure.Output).message | Should -BeLike ('Combinaci' + [char]0x00F3 + 'n de par' + [char]0x00E1 + 'metros no v' + [char]0x00E1 + 'lida*')
    }

    It 'exits with 1 on an unknown profile' {
        $result = Invoke-Tuneup @('-Profile', 'nope', '-WhatIf', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        $json.message | Should -Match 'nope'
    }

    It 'rejects <Arguments>' -TestCases @(
        @{ Arguments = @('-Tweak', 'test.one') }
        @{ Arguments = @('-Status', '-Undo', 'last') }
        @{ Arguments = @('-Status', '-WhatIf') }
        @{ Arguments = @('-Status', '-Include', 'test.three') }
        @{ Arguments = @('-Undo', 'last', '-Profile', 'extra') }
        @{ Arguments = @('-Undo', 'last', '-Yes') }
        @{ Arguments = @('-Undo', 'last', '-Exclude', 'test.one') }
    ) {
        param($Arguments)
        $result = Invoke-Tuneup (@($Arguments) + '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Match 'Invalid parameter combination'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'refuses to apply with -Json but without -Yes' {
        (Invoke-Tuneup @('-Json')).ExitCode | Should -Be 1
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'marks a plan with system changes as requiring elevation' {
        $json = ConvertFrom-PureJson (Invoke-Tuneup @('-Profile', 'system', '-WhatIf', '-Json')).Output
        $json.requiresAdmin | Should -BeTrue
        ($json.items | Where-Object { $_.id -eq 'test.machine' }).action | Should -Be 'apply'
    }

    It 'hints at elevation in a plan with system changes' -Skip:$Elevated {
        (Invoke-Tuneup @('-Profile', 'system', '-WhatIf')).Output | Should -Match 'To apply the system changes, open PowerShell as administrator'
    }

    It 'refuses system changes without elevation' -Skip:$Elevated {
        $result = Invoke-Tuneup @('-Profile', 'system', '-Yes', '-Json')
        $result.ExitCode | Should -Be 1
        (ConvertFrom-PureJson $result.Output).message | Should -Be 'The plan has system changes: open PowerShell as administrator.'
        Test-Path -LiteralPath $Key | Should -BeFalse
        Test-Path -LiteralPath 'HKLM:\SOFTWARE\windows-tuneup-test' | Should -BeFalse
    }

    It 'carries every JSON document a warnings array' {
        foreach ($arguments in @(@('-WhatIf', '-Json'), @('-Yes', '-Json'), @('-Status', '-Json'), @('-Undo', 'last', '-Json'), @('-Profile', 'nope', '-Json'))) {
            $json = ConvertFrom-PureJson (Invoke-Tuneup $arguments).Output
            $json.PSObject.Properties.Name | Should -Contain 'warnings' -Because ($arguments -join ' ')
        }
    }

    It 'puts -Status warnings inside the JSON document' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        [System.IO.File]::AppendAllText((Join-Path (Get-RunDir) 'snapshot.jsonl'), '{"id":"test.bro')
        $result = Invoke-Tuneup @('-Status', '-Json')
        $result.ExitCode | Should -Be 0
        $json = ConvertFrom-PureJson $result.Output
        @($json.warnings | Where-Object { $_ -match 'incomplete last journal line' }).Count | Should -Be 1
        Get-Ids $json.items | Should -Be 'test.one,test.two'
    }

    It 'skips the tweaks of another user and exits with 1 when nothing was restored' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        $runDir = Get-RunDir
        $info = Get-Content -LiteralPath (Join-Path $runDir 'run.json') -Raw | ConvertFrom-Json
        $info.userSid = 'S-1-5-21-1-2-3-1001'
        [System.IO.File]::WriteAllText((Join-Path $runDir 'run.json'), ($info | ConvertTo-Json))
        $result = Invoke-Tuneup @('-Undo', (Split-Path $runDir -Leaf), '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.summary.restored | Should -Be 0
        $json.summary.skipped | Should -Be 2
        ($json.results | ForEach-Object { $_.reason }) -join ',' | Should -Be 'other-user,other-user'
        @($json.warnings | Where-Object { $_ -match 'belongs to another user' }).Count | Should -Be 2
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        $human = Invoke-Tuneup @('-Undo', (Split-Path $runDir -Leaf))
        $human.ExitCode | Should -Be 1
        $human.Output | Should -Match 'Skipped: 2'
        @([regex]::Matches($human.Output, "Ignoring user-scope entry 'test.one'")).Count | Should -Be 1
    }

    It 'puts warnings inside the JSON error document' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path (Get-RunDir) 'run.json'), '{ broken')
        $result = Invoke-Tuneup @('-Undo', 'last', '-Json')
        $result.ExitCode | Should -Be 1
        $json = ConvertFrom-PureJson $result.Output
        $json.command | Should -Be 'error'
        @($json.warnings | Where-Object { $_ -match 'unreadable state file' }).Count | Should -Be 1
    }

    It 'prints warnings normally without -Json' {
        Invoke-Tuneup @('-Yes', '-Json') | Out-Null
        [System.IO.File]::AppendAllText((Join-Path (Get-RunDir) 'snapshot.jsonl'), '{"id":"test.bro')
        $result = Invoke-Tuneup @('-Status')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'incomplete last journal line'
    }
}
```

`tests/Output.Tests.ps1`:
```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    function New-TestResult([string]$Status, [string]$Reason, [string]$ErrorText) {
        [pscustomobject]@{ id = "test.$Status"; title = "Title $Status"; status = $Status; reason = $Reason; error = $ErrorText; rebootRequired = $false }
    }
    function New-TestReport([object[]]$Results) {
        New-TuneupApplyReport -Run ([pscustomobject]@{ Id = '20250101-000000'; Dir = 'C:\runs\20250101-000000' }) -Results $Results `
            -RestorePoint 'not-needed' -Environment (New-TestEnvironment)
    }
    function New-TestPlanItem([string]$Scope, [string]$Action) {
        $path = $(if ($Scope -eq 'machine') { 'HKLM:\SOFTWARE\windows-tuneup-test' } else { 'HKCU:\Software\windows-tuneup-test' })
        $tweak = New-TestTweak -Id "test.$Scope" -Scope $Scope -Set ([pscustomobject]@{ path = $path; name = 'X'; kind = 'DWord'; value = 1 })
        [pscustomobject]@{ Id = $tweak.id; Tweak = $tweak; Action = $Action; Reason = $(if ($Action -eq 'skip') { 'already-applied' } else { $null }) }
    }
    $script:JournalError = New-TestResult -Status 'skipped' -Reason 'journal-error' -ErrorText 'Disk full'
    $script:PlanSkip = New-TestResult -Status 'skipped' -Reason 'already-applied'
}

Describe 'Module' {
    It 'stops on errors inside the engine' {
        & (Get-Module Tuneup) { Get-Variable -Name ErrorActionPreference -Scope Script -ValueOnly -ErrorAction SilentlyContinue } | Should -Be 'Stop'
    }
}

Describe 'Write-TuneupJson' {
    It 'escapes every non-ASCII character' {
        $text = 'acci' + [char]0x00F3 + 'n ' + [char]::ConvertFromUtf32(0x1F600)
        $json = Write-TuneupJson ([pscustomobject]@{ text = $text })
        [regex]::IsMatch($json, '[^\x00-\x7F]') | Should -BeFalse
        $json | Should -Match '\\u00f3'
        ($json | ConvertFrom-Json).text | Should -Be $text
    }
}

Describe 'ConvertTo-TuneupEnvironmentView' {
    It 'uses camelCase keys' {
        $view = ConvertTo-TuneupEnvironmentView -Environment (New-TestEnvironment -Edition 'Home')
        $view.PSObject.Properties.Name -join ',' | Should -Be 'build,ubr,family,edition,isServer,isManaged,isAdmin,hasBattery,pendingReboot'
        $view.edition | Should -Be 'Home'
        $view.isAdmin | Should -BeTrue
    }
}

Describe 'New-TuneupApplyReport' {
    It 'counts journal errors apart from the skipped tweaks' {
        $report = New-TestReport @((New-TestResult -Status 'applied'), $JournalError, $PlanSkip)
        $report.summary.applied | Should -Be 1
        $report.summary.journalErrors | Should -Be 1
        $report.summary.skipped | Should -Be 1
        $report.environment.PSObject.Properties.Name | Should -Contain 'isAdmin'
    }
}

Describe 'Get-TuneupApplyExitCode' {
    It 'returns <Expected> for <Name>' -TestCases @(
        @{ Name = 'everything applied'; Statuses = @('applied', 'plan-skip'); NotSaved = $false; Expected = 0 }
        @{ Name = 'a tweak without effect'; Statuses = @('applied', 'not-applied'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a failed tweak'; Statuses = @('applied', 'failed'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a journal error before any change'; Statuses = @('journal-error', 'plan-skip'); NotSaved = $false; Expected = 1 }
        @{ Name = 'a journal error after a change'; Statuses = @('applied', 'journal-error'); NotSaved = $false; Expected = 2 }
        @{ Name = 'a journal error after a failure'; Statuses = @('failed', 'journal-error'); NotSaved = $false; Expected = 2 }
        @{ Name = 'an unsaved result'; Statuses = @('applied'); NotSaved = $true; Expected = 2 }
        @{ Name = 'an unsaved result with nothing applied'; Statuses = @('journal-error'); NotSaved = $true; Expected = 1 }
    ) {
        param($Statuses, $NotSaved, $Expected)
        $results = @(foreach ($status in $Statuses) {
            switch ($status) {
                'plan-skip' { $PlanSkip }
                'journal-error' { $JournalError }
                default { New-TestResult -Status $status }
            }
        })
        Get-TuneupApplyExitCode -Report (New-TestReport $results) -ResultNotSaved:$NotSaved | Should -Be $Expected
    }
}

Describe 'Get-TuneupUndoExitCode' {
    It 'returns <Expected> for <Name>' -TestCases @(
        @{ Name = 'everything restored'; Results = @('restored', 'restored'); Expected = 0 }
        @{ Name = 'restored and already undone'; Results = @('restored', 'already-undone'); Expected = 0 }
        @{ Name = 'only already undone'; Results = @('already-undone'); Expected = 0 }
        @{ Name = 'restored and failed'; Results = @('restored', 'failed'); Expected = 2 }
        @{ Name = 'restored and of another user'; Results = @('restored', 'other-user'); Expected = 2 }
        @{ Name = 'only failed'; Results = @('failed'); Expected = 1 }
        @{ Name = 'only of another user'; Results = @('other-user', 'other-user'); Expected = 1 }
    ) {
        param($Results, $Expected)
        $items = @(foreach ($kind in $Results) {
            if ($kind -in 'already-undone', 'other-user') { New-TestResult -Status 'skipped' -Reason $kind } else { New-TestResult -Status $kind }
        })
        Get-TuneupUndoExitCode -Results $items | Should -Be $Expected
    }
}

Describe 'Save-TuneupApplyReport' {
    It 'saves result.json without warnings' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $dir; Root = 'custom' }
        Save-TuneupApplyReport -Run $run -Report (New-TestReport @(New-TestResult -Status 'applied')) | Should -BeTrue
        $saved = Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json
        $saved.runId | Should -Be '20250101-000000'
        $saved.PSObject.Properties.Name | Should -Not -Contain 'warnings'
    }

    It 'warns instead of failing when result.json cannot be saved' {
        Mock -ModuleName Tuneup Save-TuneupJson { throw [System.UnauthorizedAccessException]::new('Access denied') }
        $run = [pscustomobject]@{ Id = '20250101-000000'; Dir = $TestDrive; Root = 'custom' }
        $saved = Save-TuneupApplyReport -Run $run -Report (New-TestReport @(New-TestResult -Status 'applied')) -WarningVariable warned -WarningAction SilentlyContinue
        $saved | Should -BeFalse
        "$($warned[0])" | Should -BeLike '*20250101-000000*Access denied*'
    }
}

Describe 'Write-TuneupApplyReport' {
    It 'lists journal errors with their error and hides plain skips' {
        $report = New-TestReport @((New-TestResult -Status 'applied'), $JournalError, $PlanSkip)
        $text = (Write-TuneupApplyReport -Report $report 6>&1 | Out-String)
        $text | Should -Match 'Title skipped'
        $text | Should -Match 'the backup could not be saved'
        $text | Should -Match 'Disk full'
        @([regex]::Matches($text, 'Title skipped')).Count | Should -Be 1
    }

    It 'adds the warnings only to the JSON document' {
        $report = New-TestReport @(New-TestResult -Status 'applied')
        $json = Write-TuneupApplyReport -Report $report -Warnings @('careful') -Json | ConvertFrom-Json
        @($json.warnings) -join ',' | Should -Be 'careful'
        $report.PSObject.Properties.Name | Should -Not -Contain 'warnings'
    }
}

Describe 'Write-TuneupPlanReport' {
    It 'marks a plan with system changes as requiring elevation' {
        $json = Write-TuneupPlanReport -Plan @((New-TestPlanItem 'user' 'apply'), (New-TestPlanItem 'machine' 'apply')) -Environment (New-TestEnvironment) -Json | ConvertFrom-Json
        $json.requiresAdmin | Should -BeTrue
        $json.environment.PSObject.Properties.Name | Should -Contain 'isAdmin'
        $json.environment.PSObject.Properties.Name -ccontains 'IsAdmin' | Should -BeFalse
    }

    It 'does not require elevation for skipped system tweaks' {
        $json = Write-TuneupPlanReport -Plan @((New-TestPlanItem 'user' 'apply'), (New-TestPlanItem 'machine' 'skip')) -Environment (New-TestEnvironment) -Json | ConvertFrom-Json
        $json.requiresAdmin | Should -BeFalse
    }

    It 'hints at elevation only when it is missing' {
        $plan = @(New-TestPlanItem 'machine' 'apply')
        $user = New-TestEnvironment
        $user.IsAdmin = $false
        (Write-TuneupPlanReport -Plan $plan -Environment $user 6>&1 | Out-String) | Should -Match 'To apply the system changes'
        (Write-TuneupPlanReport -Plan $plan -Environment (New-TestEnvironment) 6>&1 | Out-String) | Should -Not -Match 'To apply the system changes'
    }
}

Describe 'Write-TuneupUndoReport' {
    It 'shows skipped tweaks with their reason and counts them' {
        $results = @((New-TestResult -Status 'restored'), (New-TestResult -Status 'skipped' -Reason 'other-user'))
        $text = (Write-TuneupUndoReport -RunId '20250101-000000' -Results $results 6>&1 | Out-String)
        $text | Should -Match 'Title skipped: belongs to another user'
        $text | Should -Match 'Restored: 1 . Failed: 0 . Skipped: 1'
    }
}
```

- [ ] **Step 3: Verificar que fallan**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Cli.Tests.ps1` (y `tests/Output.Tests.ps1`)
Expected: FAIL, `ConvertTo-TuneupList` no se reconoce y `tuneup.ps1` no existe.

- [ ] **Step 4: Salida**

`engine/Output.ps1`:
```powershell
function ConvertTo-TuneupList {
    param([AllowEmptyCollection()][string[]]$Value = @())
    @($Value | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function ConvertTo-TuneupPlanView {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan)
    foreach ($item in $Plan) {
        [pscustomobject]@{
            id             = $item.Id
            title          = Get-TuneupTitle -Tweak $item.Tweak
            risk           = $item.Tweak.risk
            scope          = $item.Tweak.scope
            action         = $item.Action
            reason         = $item.Reason
            rebootRequired = [bool]$item.Tweak.rebootRequired
        }
    }
}

function ConvertTo-TuneupEnvironmentView {
    param([Parameter(Mandatory)]$Environment)
    [pscustomobject]@{
        build         = $Environment.Build
        ubr           = $Environment.UBR
        family        = $Environment.Family
        edition       = $Environment.Edition
        isServer      = $Environment.IsServer
        isManaged     = $Environment.IsManaged
        isAdmin       = $Environment.IsAdmin
        hasBattery    = $Environment.HasBattery
        pendingReboot = $Environment.PendingReboot
    }
}

function Write-TuneupJson {
    param([Parameter(Mandatory)]$Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    # ASCII only, so the console code page cannot garble accents on the way out.
    $escaped = [regex]::Replace($json, '[^\x00-\x7F]', { param($match) '\u{0:x4}' -f [int][char]$match.Value })
    Write-Output $escaped
}

function Add-TuneupJsonWarning {
    param([Parameter(Mandatory)]$Document, [AllowEmptyCollection()][string[]]$Warnings = @())
    # A copy, so the report saved in the run folder does not change.
    $copy = $Document | Select-Object -Property *
    $copy | Add-Member -NotePropertyName warnings -NotePropertyValue ([string[]]@($Warnings)) -Force
    $copy
}

function Write-TuneupPlanReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)]$Environment,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    $items = @(ConvertTo-TuneupPlanView -Plan $Plan)
    $toApply = @($items | Where-Object { $_.action -eq 'apply' }).Count
    $requiresAdmin = @($items | Where-Object { $_.action -eq 'apply' -and $_.scope -eq 'machine' }).Count -gt 0
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'plan'
            environment   = ConvertTo-TuneupEnvironmentView -Environment $Environment
            requiresAdmin = $requiresAdmin
            items         = $items
            summary       = [pscustomobject]@{ apply = $toApply; skip = $items.Count - $toApply }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'plan.header' -Format $toApply, ($items.Count - $toApply))
    foreach ($item in $items) {
        if ($item.action -eq 'apply') {
            Write-Host (Get-TuneupText -Key 'plan.apply' -Format $item.title, (Get-TuneupText -Key "risk.$($item.risk)")) -ForegroundColor Cyan
        } else {
            Write-Host (Get-TuneupText -Key 'plan.skip' -Format $item.title, (Get-TuneupText -Key "reason.$($item.reason)")) -ForegroundColor DarkGray
        }
    }
    if (-not $toApply) { Write-Host (Get-TuneupText -Key 'nothing') -ForegroundColor Green }
    if ($requiresAdmin -and -not $Environment.IsAdmin) { Write-Host (Get-TuneupText -Key 'plan.needsAdmin') -ForegroundColor Yellow }
}

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
        rebootRequired = (@($Results | Where-Object { $_.status -eq 'applied' -and $_.rebootRequired }).Count -gt 0)
        summary        = [pscustomobject]@{
            applied       = & $count 'applied'
            notApplied    = & $count 'not-applied'
            failed        = & $count 'failed'
            skipped       = & $count 'skipped'
            journalErrors = @($Results | Where-Object { $_.reason -eq 'journal-error' }).Count
        }
        results        = $Results
    }
}

function Save-TuneupApplyReport {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Report)
    # The changes are already made; losing result.json must not hide the report of what was done.
    try {
        Save-TuneupJson -Path (Join-Path $Run.Dir 'result.json') -Root $Run.Root -Object $Report
        $true
    } catch {
        Write-Warning "The result of run $($Run.Id) could not be saved: $($_.Exception.Message)"
        $false
    }
}

function Get-TuneupApplyExitCode {
    param([Parameter(Mandatory)]$Report, [switch]$ResultNotSaved)
    $summary = $Report.summary
    $touched = $summary.applied + $summary.notApplied + $summary.failed
    if ($summary.journalErrors -and -not $touched) { return 1 }
    if ($summary.notApplied -or $summary.failed -or $summary.journalErrors -or $ResultNotSaved) { return 2 }
    0
}

function Get-TuneupUndoExitCode {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)
    $restored = @($Results | Where-Object { $_.status -eq 'restored' }).Count
    $pending = @($Results | Where-Object { $_.status -eq 'failed' -or ($_.status -eq 'skipped' -and $_.reason -ne 'already-undone') }).Count
    if (-not $pending) { return 0 }
    if ($restored) { return 2 }
    1
}

function Write-TuneupApplyReport {
    param(
        [Parameter(Mandatory)]$Report,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Report -Warnings $Warnings); return }
    $colors = @{ 'applied' = 'Green'; 'not-applied' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Report.results) {
        if ($result.reason -eq 'journal-error') {
            Write-Host ((Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key 'status.skipped'), $result.title) + ": $(Get-TuneupText -Key 'reason.journal-error')") -ForegroundColor Red
            if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
            continue
        }
        if ($result.status -eq 'skipped') { continue }
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title) -ForegroundColor $colors[$result.status]
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    $summary = $Report.summary
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'summary' -Format $summary.applied, $summary.notApplied, $summary.failed, $summary.skipped)
    Write-Host (Get-TuneupText -Key "restore.$($Report.restorePoint)")
    Write-Host (Get-TuneupText -Key 'run.saved' -Format $Report.runId, $Report.runDir)
    if ($Report.rebootRequired) { Write-Host (Get-TuneupText -Key 'reboot') -ForegroundColor Yellow }
}

function Write-TuneupStatusReport {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{ schemaVersion = 1; command = 'status'; items = $Items }))
        return
    }
    if (-not $Items.Count) { Write-Host (Get-TuneupText -Key 'status.empty'); return }
    Write-Host (Get-TuneupText -Key 'status.header')
    $colors = @{ 'ok' = 'Green'; 'drift' = 'Yellow'; 'not-present' = 'DarkGray'; 'unknown' = 'Red' }
    foreach ($item in $Items) {
        Write-Host (Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($item.status)"), "$($item.title) ($($item.runId))") -ForegroundColor $colors[$item.status]
    }
}

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
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'undo'
            runId         = $RunId
            results       = $Results
            summary       = [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
        }))
        return
    }
    Write-Host (Get-TuneupText -Key 'undo.header' -Format $RunId)
    $colors = @{ 'restored' = 'Green'; 'skipped' = 'Yellow'; 'failed' = 'Red' }
    foreach ($result in $Results) {
        $line = Get-TuneupText -Key 'result.line' -Format (Get-TuneupText -Key "status.$($result.status)"), $result.title
        if ($result.reason) { $line += ": $(Get-TuneupText -Key "reason.$($result.reason)")" }
        Write-Host $line -ForegroundColor $colors[$result.status]
        if ($result.error) { Write-Host "    $($result.error)" -ForegroundColor Red }
    }
    Write-Host (Get-TuneupText -Key 'undo.summary' -Format $restored, $failed, $skipped)
}

function Write-TuneupErrorReport {
    param(
        [Parameter(Mandatory)][string]$Message,
        [AllowEmptyCollection()][string[]]$Details = @(),
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) {
        Write-TuneupJson (Add-TuneupJsonWarning -Warnings $Warnings -Document ([pscustomobject]@{
            schemaVersion = 1
            command       = 'error'
            message       = $Message
            details       = [string[]]@($Details)
        }))
        return
    }
    Write-Host $Message -ForegroundColor Red
    foreach ($detail in $Details) { Write-Host "  - $detail" -ForegroundColor Red }
}
```

- [ ] **Step 5: CLI**

`tuneup.ps1`:
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
    [string]$ProfilesPath
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

$ProfileName = @(ConvertTo-TuneupList -Value $ProfileName)
$Include = @(ConvertTo-TuneupList -Value $Include)
$Exclude = @(ConvertTo-TuneupList -Value $Exclude)

$conflict = $null
if ($Tweak -and -not $Undo) { $conflict = '-Tweak (-Undo)' }
elseif ($Status -and $Undo) { $conflict = '-Status -Undo' }
elseif ($Status -or $Undo) {
    $extra = @()
    if ($ProfileName.Count) { $extra += '-Profile' }
    if ($Include.Count) { $extra += '-Include' }
    if ($Exclude.Count) { $extra += '-Exclude' }
    if ($WhatIf) { $extra += '-WhatIf' }
    if ($Yes) { $extra += '-Yes' }
    if ($extra.Count) { $conflict = (@($(if ($Status) { '-Status' } else { '-Undo' })) + $extra) -join ' ' }
}
if ($conflict) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.badArgs' -Format $conflict) }

try {
    # Relative paths follow the current PowerShell location, not the process folder that .NET uses.
    $pathApi = $ExecutionContext.SessionState.Path
    if ($StateRoot) { $StateRoot = $pathApi.GetUnresolvedProviderPathFromPSPath($StateRoot) }
    $CatalogPath = $(if ($CatalogPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($CatalogPath) } else { Join-Path $PSScriptRoot 'catalog' })
    $ProfilesPath = $(if ($ProfilesPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($ProfilesPath) } else { Join-Path $PSScriptRoot 'profiles' })

    $catalog = @(Invoke-TuneupStep { Import-TuneupCatalog -Path $CatalogPath })
    $profileSet = @(Invoke-TuneupStep { Import-TuneupProfileSet -Path $ProfilesPath })
    $problems = @(Test-TuneupCatalog -Catalog $catalog) + @(Test-TuneupProfileSet -Profiles $profileSet -Catalog $catalog)
    if ($problems.Count) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.catalog') -Details $problems }

    $environment = Invoke-TuneupStep { Get-TuneupEnvironment }
    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
    if (($environment.Build -lt 19041 -or $environment.Edition -eq 'Unknown') -and -not $Force) {
        Stop-Tuneup -Message (Get-TuneupText -Key 'err.unsupported')
    }
    # Server supports every policy that Enterprise supports.
    if ($environment.IsServer) { $environment.Edition = 'Enterprise' }

    if ($Status) {
        $items = @(Invoke-TuneupStep { Get-TuneupStatus -StateRoot $StateRoot })
        Write-TuneupStatusReport -Items $items -Warnings $script:Warnings.ToArray() -Json:$Json
        exit 0
    }

    if ($Undo) {
        $run = Invoke-TuneupStep { Resolve-TuneupRun -StateRoot $StateRoot -RunId $Undo }
        if (-not $run) { Stop-Tuneup -Message (Get-TuneupText -Key 'undo.none') }
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

- [ ] **Step 6: Verificar que pasa**

Run: `powershell -NoProfile -File build/test.ps1 -Path tests/Cli.Tests.ps1`, luego `tests/Output.Tests.ps1`, `tests/Undo.Tests.ps1` y `tests/Runs.Tests.ps1`
Expected: 29, 27, 22 y 30 passed (en un proceso elevado, 2 de las 29 quedan omitidas).

- [ ] **Step 7: Prueba manual en español**

Run:
```powershell
powershell -NoProfile -File tuneup.ps1 -CatalogPath tests\fixtures\catalog -ProfilesPath tests\fixtures\profiles -StateRoot $env:TEMP\tuneup-manual -Lang es -WhatIf
```
Expected: `Plan: 2 para aplicar, 0 omitidos` con las líneas `+ Prueba uno [riesgo bajo]` y `+ Prueba dos [riesgo bajo]`, con acentos correctos.

- [ ] **Step 8: Commit**

```bash
git add engine/Output.ps1 tuneup.ps1 tests/fixtures tests/Cli.Tests.ps1 tests/Output.Tests.ps1
git commit -m "feat: CLI con plan, aplicar, estado, deshacer y salida JSON"
```

---

### Task 14: Lint, suite completa y README

**Files:**
- Modify: los archivos que marque PSScriptAnalyzer
- Modify: `README.md`

- [ ] **Step 1: Lint**

Run: `powershell -NoProfile -File build/lint.ps1`
Expected: `PSScriptAnalyzer: no findings`. Si aparece un hallazgo, corregir el código (no agregar exclusiones nuevas sin justificarlas con un comentario en `build/PSScriptAnalyzerSettings.psd1`) y volver a correr.

- [ ] **Step 2: Suite completa**

Run: `powershell -NoProfile -File build/test.ps1`
Expected: todas las pruebas pasan (306), 0 fallidas.

- [ ] **Step 3: Prueba real, solo lectura, en este PC**

Run:
```powershell
powershell -NoProfile -File tuneup.ps1 -Profile privacy -WhatIf -Lang es
```
Expected: el plan con los 5 ajustes de la semilla y un motivo claro para cada uno que se omita. No cambia nada.

- [ ] **Step 4: Completar el README con lo que ya funciona**

Agregar al `README.md`, después de "Uso / Usage":
```markdown
## Qué hace hoy / What works today

- Perfiles `base` y `privacy` con 5 ajustes de ejemplo (registro, servicio, tarea programada).
- `-WhatIf` muestra el plan con el motivo de cada omisión.
- Guarda el valor anterior de cada ajuste antes de tocarlo, en `%ProgramData%\windows-tuneup\runs\` (como administrador, carpeta protegida) o `%LOCALAPPDATA%\windows-tuneup\runs\` (sin elevar, solo ajustes de usuario).
- `-Undo last` o `-Undo <id> -Tweak <ajuste>` devuelve el valor exacto anterior.
- `-Status` muestra qué sigue aplicado y qué revirtió Windows.
- `-Json` para automatización; códigos de salida 0 (ok), 2 (parcial), 1 (abortado).

## Desarrollo / Development

```powershell
powershell -NoProfile -File build\test.ps1
powershell -NoProfile -File build\lint.ps1
```
```

- [ ] **Step 5: Commit**

```bash
git add -A engine tuneup.ps1 build README.md
git commit -m "chore: lint limpio y README del núcleo"
```

---

### Task 15: Publicar en GitHub (requiere confirmación del autor)

Crear un repositorio público es publicar contenido: **detenerse y pedir confirmación explícita** antes de ejecutar estos pasos.

- [ ] **Step 1: Confirmar con el autor** nombre (`edgarlugo/windows-tuneup`), visibilidad pública y descripción.

- [ ] **Step 2: Crear y subir**

```bash
gh repo create edgarlugo/windows-tuneup --public --description "Goal-based, reversible and measurable Windows 10/11 optimization / Optimización de Windows por objetivos, reversible y medible" --source . --remote origin --push
```

- [ ] **Step 3: Verificar CI**

Run: `gh run list --repo edgarlugo/windows-tuneup --limit 1`
Expected: el workflow `ci` en `completed success`. Si falla, leer el log con `gh run view --log-failed`, corregir y volver a subir.
