# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> Estado: en desarrollo (Plan 1: núcleo del motor). No usar todavía en equipos reales.
> Status: work in progress. Do not use on real machines yet.

## Requisitos / Requirements

- Windows 10 u 11 con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1.
- Windows 10 or 11 with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1.
- Los ajustes de sistema necesitan PowerShell como administrador. Sin elevar solo se aplican ajustes de usuario.
- System-wide tweaks need PowerShell as administrator. Without elevation only user-level tweaks are applied.

## Uso / Usage

```powershell
.\tuneup.ps1 -Profile base -WhatIf     # ver el plan / show the plan
.\tuneup.ps1 -Profile base,privacy     # aplicar / apply
.\tuneup.ps1 -Status                   # estado / status
.\tuneup.ps1 -Undo last                # deshacer / undo
```

## Qué hace hoy / What works today

- Perfiles `base` y `privacy` con 5 ajustes de ejemplo (registro, servicio, tarea programada).
  Profiles `base` and `privacy` with 5 sample tweaks (registry, service, scheduled task).
- `-WhatIf` muestra el plan con el motivo de cada omisión (ya aplicado, versión o edición no compatible, equipo administrado...). No cambia nada.
  `-WhatIf` shows the plan with the reason for every skipped tweak (already applied, unsupported version or edition, managed machine...). It changes nothing.
- Antes de tocar un ajuste guarda su valor anterior. Con administrador la corrida queda en `%ProgramData%\windows-tuneup\runs\` (carpeta protegida); sin elevar, en `%LOCALAPPDATA%\windows-tuneup\runs\` (solo ajustes de usuario).
  Before touching a tweak it saves the previous value. Elevated, the run goes to `%ProgramData%\windows-tuneup\runs\` (hardened folder); otherwise to `%LOCALAPPDATA%\windows-tuneup\runs\` (user-level tweaks only).
- `-Undo last` o `-Undo <id> -Tweak <ajuste>` devuelve el valor exacto anterior. Una corrida ya deshecha no se deshace dos veces.
  `-Undo last` or `-Undo <id> -Tweak <tweak>` restores the exact previous value. A run that was already undone is not undone twice.
- `-Status` muestra qué sigue aplicado y qué revirtió Windows.
  `-Status` shows what is still applied and what Windows reverted.
- `-Json` para automatización: un único documento JSON por la salida estándar, con claves en camelCase, `warnings` (los avisos van dentro del documento) y `requiresAdmin` en el plan. Para aplicar sin preguntar usar `-Yes`.
  `-Json` for automation: a single JSON document on standard output, camelCase keys, `warnings` (warnings are carried inside the document) and `requiresAdmin` in the plan. To apply without asking use `-Yes`.
- Códigos de salida: 0 (ok), 2 (parcial: parte se aplicó o restauró y parte falló), 1 (abortado o error).
  Exit codes: 0 (ok), 2 (partial: part was applied or restored and part failed), 1 (aborted or error).
- Idioma con `-Lang es|en`.
  Language with `-Lang es|en`.

## Desarrollo / Development

```powershell
powershell -NoProfile -File build\test.ps1
powershell -NoProfile -File build\lint.ps1
```

Las pruebas usan Pester 5 y el lint PSScriptAnalyzer. / Tests use Pester 5 and lint uses PSScriptAnalyzer.

Licencia / License: MIT
