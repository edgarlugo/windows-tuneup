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
- **Administrador:** `base` y `work` solo tienen ajustes de tu usuario que no son directivas y se aplican sin elevar. Los demás traen cambios de sistema o directivas de tu usuario (Windows solo deja leerlas y escribirlas a un administrador): abre PowerShell como administrador, o deja fuera esos ajustes con `-Exclude`. Sin elevar, el plan los marca como de administrador y aplicar se niega.
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

**Qué hace:** apaga la transparencia, las animaciones de ventanas, las sombras y la selección translúcida y Aero Peek (algunas se notan al volver a iniciar sesión), Widgets y Noticias e intereses, el análisis del tipo de cada carpeta en el Explorador, las apps de la Store en segundo plano y Edge en segundo plano; deja de compartir descargas de Windows con otros equipos, pasa a manual los servicios de escáner y de mapas; desactiva tareas de fondo que pesan en discos mecánicos (WinSAT, diagnósticos, mapas, Carpetas de trabajo) y quita apps preinstaladas que casi nadie usa (Clipchamp, Noticias, Tiempo, Finanzas, Mensajes, Portal de realidad mixta, Películas y TV).

**Pregunta antes de:** `performance.background-apps-off` (solo Windows 10; ver Portátil).

**Qué conserva:** todo lo de Base, Defender, Windows Update y la búsqueda (reducir la indexación todavía no está en el catálogo).

**Administrador:** sí.

## Trabajo (`work`, alias `trabajo`)

**Qué hace:** solo ajustes de tu usuario que no son directivas: privacidad de escritura y voz, lista de idiomas, seguimiento de apps, Bing, historial de búsqueda, archivos recientes y el botón de Copilot.

**Por qué:** en un equipo de una organización las directivas son de TI. Este perfil no toca ninguna y no necesita administrador.

**Qué conserva:** Teams, Outlook (nuevo), OneDrive, Microsoft 365 y Power Automate, aunque lo combines con Liviano.

**Administrador:** no.

## Liviano (`lite`, alias `liviano`)

**Qué hace:** quita lo que Windows 11 LTSC no trae (apps preinstaladas, Widgets, Copilot, Teams, Xbox, Vínculo móvil, Outlook nuevo, Correo y Calendario; OneDrive pregunta antes) y recorta servicios y tareas que LTSC sí mantiene: telemetría, mapas, escáner, la tarea de partidas guardadas de Xbox, dispositivos conectados, Carpetas de trabajo, WinSAT. La búsqueda queda solo local (sin Bing). Edge sin contenido promocional ni procesos en segundo plano.

**Pregunta antes de:** `services.diagtrack`, `services.geolocation`, `services.connected-devices`, `services.connected-devices-user`, `services.contact-data`, `services.user-data-storage`, `services.user-data-access`, `tasks.appraiser`, `tasks.appraiser-exp`, `tasks.program-data-updater`, `tasks.mare-backup`, `tasks.family-safety-monitor`, `tasks.family-safety-refresh`, `apps.copilot`, `apps.get-help`, `apps.alarms-clock`, `apps.media-player`, `apps.quick-assist`, `apps.phone-link`, `apps.xbox-gaming-app`, `apps.xbox-game-bar`, `apps.outlook-new`, `apps.family-safety`, `apps.mail-calendar`, `apps.msteams` y `apps.onedrive`. Desinstalar OneDrive nunca borra archivos: se niega si Escritorio, Documentos o Imágenes están en OneDrive, si hay archivos solo en la nube, si no se pudo revisar cada archivo, si otra cuenta del equipo tiene datos en riesgo o si el proceso no corre con la cuenta que inició sesión en el escritorio.

**Qué conserva:** Defender, las actualizaciones de seguridad, WinRE, la Store y winget (de ellos depende deshacer). Quitar la Store no está en el catálogo.

**¿Más liviano que LTSC?** Es el objetivo, pero todavía no está medido. El método está en [measuring.md](measuring.md).

**Administrador:** sí.
