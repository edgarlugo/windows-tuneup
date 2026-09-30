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
