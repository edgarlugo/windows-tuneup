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
