# Lista para la máquina virtual antes de cada release

Windows Sandbox (`tests/sandbox/Start-E2E.ps1`) prueba cada perfil de punta a punta, pero no trae Microsoft Store ni winget, se reinicia en limpio y no tiene OneDrive con sesión iniciada. Esta lista cubre lo demás en una máquina virtual con Windows 11 Pro. Se hace a mano antes de publicar cada release y su resultado se adjunta a la release junto con `e2e-report.md` y la medición de [measuring.md](measuring.md).

## Preparar la máquina virtual

1. Windows 11 Pro de la última versión, con las actualizaciones al día, la Microsoft Store y winget funcionando (`winget --version`).
2. Una cuenta local de administrador con la sesión iniciada en el escritorio.
3. OneDrive con una cuenta iniciada y una carpeta con archivos solo en la nube (Liberar espacio).
4. Restaurar sistema **desactivado** en `C:` (Propiedades del sistema > Protección del sistema), para probar el aviso.
5. Una instantánea (checkpoint) de la máquina en este estado.

## Instalar la versión candidata

Copia a una carpeta de la máquina virtual el zip, `install.ps1` y `SHA256SUMS` del borrador de la release (o genéralos en la carpeta del repositorio con `powershell -NoProfile -ExecutionPolicy Bypass -File .\build\package.ps1 -OutputPath <carpeta>`). En PowerShell como administrador, en esa carpeta:

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
- [ ] Arranque, sin elevar: `tuneup.ps1 -Startup` lista lo que muestran el Administrador de tareas > Aplicaciones de arranque y Configuración > Aplicaciones > Inicio, más las tareas y los servicios de terceros. Instalar antes Steam (o Discord) y Dropbox y agregar un acceso directo a la carpeta Inicio: salen recomendados; Defender, la VPN (si hay) y el audio salen protegidos. Para cada `wingetId` de `catalog/startup/rules.json`, `winget show --id <id> --exact` encuentra el programa (anotar los que no).
- [ ] Sin elevar, `tuneup.ps1 -Startup -Disable '<ids>' -Yes` con las entradas de usuario: una de Run del usuario, un acceso directo de la carpeta Inicio del usuario y una app de la Store con tarea de inicio (Teams, por ejemplo). Con un id de máquina en la lista se niega entero (`needs-admin` con `-Json`) y no apaga ninguna. Con el id de una entrada protegida (Defender) se niega y dice por qué.
- [ ] Como administrador, `tuneup.ps1 -Startup -Disable '<ids>' -Yes` con las de máquina: una de Run de máquina, una tarea programada y un servicio automático de terceros. El Administrador de tareas y Configuración muestran todas deshabilitadas, los valores de `StartupApproved` empiezan con `03` y el `State` de la tarea de la Store vale 1 (`reg query "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData" /s /v State`), la tarea queda deshabilitada y el servicio en Manual sin detenerse. Reiniciar: no arrancan, y lo protegido sí.
- [ ] `tuneup.ps1 -Status` las muestra `ok`; volver a apagar una desde el Administrador de tareas la deja `ok` (la fecha nueva no cuenta) y encenderla desde ahí la deja en `drift`, y `tuneup.ps1 -Status -Reapply -WhatIf` la deja fuera con el aviso de apagarla con `-Startup -Disable`. Apagarla otra vez con `-Startup -Disable` la deja apagada (y otra vez más no cambia nada).
- [ ] Desinstalar una de las apps apagadas (por ejemplo Dropbox): `tuneup.ps1 -Status` la muestra `not-present` (no `drift`) y `tuneup.ps1 -Undo` de esa corrida termina sin error, con esa entrada restaurada con el motivo `not-present` y sin crear claves para ella.
- [ ] Menú > 6 (Lo que arranca con Windows): lista lo mismo que `-Startup`, nada viene marcado y lo recomendado va primero; lo protegido está en la tabla pero no se puede elegir; elegir una entrada de usuario la apaga después del plan y la confirmación; elegir una de máquina sin elevar dice que necesita administrador y no cambia nada.
- [ ] Con NVIDIA app, AMD Software o Armoury Crate instalados (si se puede): salen recomendados como app de acompañamiento, no protegidos; el servicio de audio de Realtek y el panel táctil siguen protegidos. Con la inscripción MDM simulada de [skill-checklist.md](skill-checklist.md) (sección "Equipo administrado"), OneDrive y Teams salen sin recomendar (`work-app`) y el documento de `-Startup -Json` dice `workPc`; se borra la clave al terminar.
- [ ] En la PowerShell de 32 bits (`C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`), `tuneup.ps1 -Startup` se niega (necesita PowerShell de 64 bits), código 1, sin listar ni apagar nada.
- [ ] `tuneup.ps1 -Undo` de cada corrida de arranque (la de máquina, elevado): todo vuelve como estaba (los valores de `StartupApproved` que no existían desaparecen, la tarea se habilita y el servicio vuelve a Automático); reiniciar y comprobar que arrancan.
- [ ] Liviano frente a LTSC: el método de [measuring.md](measuring.md), con su reporte.

## Adjuntar a la release

- `e2e-report.md` de Windows Sandbox.
- Esta lista marcada, con la compilación de Windows usada.
- La salida de `-Measure -Compare` y el reporte de Liviano frente a LTSC.
