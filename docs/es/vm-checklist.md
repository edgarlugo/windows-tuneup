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
- [ ] Menú > Optimizar > `lite`: antes de confirmar aparece el aviso "Restaurar sistema está desactivado en el disco del sistema…"; confirmada la corrida, la pregunta de activarla se responde que sí, se comprueba en Propiedades del sistema y la corrida informa "Punto de restauración creado.". Repetir respondiendo que no: sigue sin punto de restauración y con el respaldo de la herramienta.
- [ ] Las apps que preguntan se responden una por una (sí a todas menos una); las elegidas desaparecen de `Get-AppxPackage -AllUsers` y la otra queda con el motivo "dijiste que no".
- [ ] OneDrive con Escritorio, Documentos o Imágenes en OneDrive: `apps.onedrive` queda negado (`onedrive-known-folders`); sin esas carpetas pero con archivos solo en la nube, negado (`onedrive-online-only-files`); sin nada de eso, se desinstala.
- [ ] Ctrl+C durante una corrida larga de `lite` (línea de comandos): termina el ajuste en curso, el resumen dice "Detenido con Ctrl+C" y el código de salida es 2; `tuneup.ps1 -Undo last` restaura lo aplicado.
- [ ] Ctrl+C mientras corre un programa nativo (por ejemplo winget al deshacer apps) y con `-Json`: la salida estándar queda vacía, el código de salida es 2 y el documento está en `result.json` de la carpeta más nueva de `runs` (`docs/json-contract.md`, sección `apply`).
- [ ] `transcript.log` de la carpeta de la corrida cuenta lo que se vio y no contiene el nombre de la cuenta ni la carpeta del perfil.
- [ ] Reiniciar; `tuneup.ps1 -Status` muestra todo `ok`; `tuneup.ps1 -Measure -IdleSeconds 120 -Compare last` da la diferencia.
- [ ] `tuneup.ps1 -Undo last` (las veces que haga falta, hasta "No hay corridas para deshacer"): las apps se reinstalan con winget (motivo "reinstalada desde Microsoft Store para el usuario actual"), OneDrive se reinstala y `-Status` queda vacío.
- [ ] Contra la instantánea: las apps volvieron (su versión puede ser otra) y OneDrive sincroniza otra vez después de iniciar sesión.
- [ ] Liviano frente a LTSC: el método de [measuring.md](measuring.md), con su reporte.

## Adjuntar a la release

- `e2e-report.md` de Windows Sandbox.
- Esta lista marcada, con la compilación de Windows usada.
- La salida de `-Measure -Compare` y el reporte de Liviano frente a LTSC.
