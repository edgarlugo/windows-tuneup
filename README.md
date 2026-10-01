# windows-tuneup

Optimización de Windows 10/11 por objetivos, reversible y medible.
Goal-based, reversible and measurable Windows 10/11 optimization.

> Estado: en desarrollo (Plan 1: núcleo del motor). No usar todavía en equipos reales.
> Status: work in progress. Do not use on real machines yet.

## Requisitos / Requirements

- Windows 10 u 11 con Windows PowerShell 5.1. Si se lanza desde PowerShell 7 (`pwsh`), el script se relanza solo en Windows PowerShell 5.1.
- Windows 10 or 11 with Windows PowerShell 5.1. If started from PowerShell 7 (`pwsh`), the script relaunches itself in Windows PowerShell 5.1.
- Los ajustes de sistema necesitan PowerShell como administrador. Sin elevar, un plan que contenga cualquier cambio de sistema se rechaza completo (no se aplica nada): usar `-Exclude` para dejar fuera esos ajustes o abrir PowerShell como administrador. El perfil `base` incluye un ajuste de servicio, así que aplicarlo exige administrador (o `-Exclude services.retail-demo`).
- System-wide tweaks need PowerShell as administrator. Without elevation, a plan that contains any system-level change is refused entirely (nothing is applied): use `-Exclude` to leave those tweaks out or open PowerShell as administrator. The `base` profile includes a service tweak, so applying it requires administrator (or `-Exclude services.retail-demo`).

## Uso / Usage

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base -WhatIf   # ver el plan / show the plan
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Profile base,privacy   # aplicar / apply
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Status                 # estado / status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tuneup.ps1 -Undo last              # deshacer / undo
```

`-ExecutionPolicy Bypass` solo afecta a ese proceso y permite ejecutar el script aunque la política de PowerShell sea `Restricted`; no cambia la configuración del equipo.
`-ExecutionPolicy Bypass` only affects that process and lets the script run even if the PowerShell policy is `Restricted`; it does not change the machine configuration.

## Qué hace hoy / What works today

- Perfiles `base` y `privacy` con 5 ajustes de ejemplo (registro, servicio, tarea programada).
  Profiles `base` and `privacy` with 5 sample tweaks (registry, service, scheduled task).
- `-WhatIf` muestra el plan con el motivo de cada omisión (ya aplicado, versión o edición no compatible, equipo administrado...). No cambia nada.
  `-WhatIf` shows the plan with the reason for every skipped tweak (already applied, unsupported version or edition, managed machine...). It changes nothing.
- Antes de tocar un ajuste guarda su valor anterior. Con administrador la corrida queda en `%ProgramData%\windows-tuneup\runs\` (carpeta protegida); sin elevar, en `%LOCALAPPDATA%\windows-tuneup\runs\` (solo ajustes de usuario).
  Before touching a tweak it saves the previous value. Elevated, the run goes to `%ProgramData%\windows-tuneup\runs\` (hardened folder); otherwise to `%LOCALAPPDATA%\windows-tuneup\runs\` (user-level tweaks only).
- `-Undo last` o `-Undo <id> -Tweak <ajuste>` devuelve el valor exacto anterior. Una corrida ya deshecha no se deshace dos veces.
  `-Undo last` or `-Undo <id> -Tweak <tweak>` restores the exact previous value. A run that was already undone is not undone twice.
- `-Status` muestra qué sigue aplicado y qué revirtió Windows. `-Status` y `-Undo` no dependen del catálogo: funcionan con lo guardado en la corrida.
  `-Status` shows what is still applied and what Windows reverted. `-Status` and `-Undo` do not depend on the catalog: they work from what the run saved.
- `-Json` para automatización: un único documento JSON por la salida estándar, con claves en camelCase, `warnings` (los avisos van dentro del documento) y `requiresAdmin` en el plan. Para aplicar sin preguntar usar `-Yes`.
  `-Json` for automation: a single JSON document on standard output, camelCase keys, `warnings` (warnings are carried inside the document) and `requiresAdmin` in the plan. To apply without asking use `-Yes`.
- Códigos de salida: 0 (todo hecho), 2 (no todo se completó: puede haberse cambiado algo, leer el resumen), 1 (abortado antes de cambiar nada; al deshacer, nada se restauró).
  Exit codes: 0 (everything done), 2 (not everything was completed: some changes may have been made, read the summary), 1 (aborted before changing anything; for undo, nothing was restored).
- Idioma con `-Lang es|en`.
  Language with `-Lang es|en`.
- Ajustes de apps (`appx`): quitar una app la quita para todos los usuarios y la desaprovisiona. Deshacer la reinstala desde la Store con `winget` **solo para la cuenta que ejecuta el deshacer** (si elevas con otra cuenta, la app queda en esa cuenta, no en la tuya), y no puede volver a provisionarla ni reponerla a otros usuarios. El catálogo no debe incluir paquetes `NonRemovable` ni de framework (`Microsoft.NET.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`): Windows los protege y otras apps dependen de ellos.
  App tweaks (`appx`): removing an app removes it for all users and deprovisions it. Undo reinstalls it from the Store with `winget` **only for the account that runs the undo** (if you elevate with a different account, the app lands in that account, not yours), and it cannot provision it again or restore it for other users. The catalog must not include `NonRemovable` or framework packages (`Microsoft.NET.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`): Windows protects them and other apps depend on them.

## Desarrollo / Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build\test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File build\lint.ps1
```

Las pruebas usan Pester 5 y el lint PSScriptAnalyzer. / Tests use Pester 5 and lint uses PSScriptAnalyzer.

Licencia / License: MIT
