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
