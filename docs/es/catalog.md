# Catálogo de ajustes

Este archivo lo genera `build/catalog-doc.ps1` a partir de `catalog/*.json`, `profiles/*.json` y `catalog/notes/excluded.json`. No se edita a mano: después de cambiar el catálogo, ejecuta `powershell -NoProfile -ExecutionPolicy Bypass -File build/catalog-doc.ps1`.

English version: [../en/catalog.md](../en/catalog.md).

## Resumen

| Categoría | Ajustes |
|---|---|
| Privacidad y telemetría (`privacy`) | 18 |
| Anuncios y sugerencias (`ads`) | 28 |
| Interfaz (`ui`) | 12 |
| Copilot, Recall e IA (`ai`) | 10 |
| Microsoft Edge (`edge`) | 17 |
| Servicios (`services`) | 10 |
| Tareas programadas (`tasks`) | 21 |
| Rendimiento (`performance`) | 3 |
| Energía (`power`) | 3 |
| Juegos (`gaming`) | 11 |
| Desarrollo (`dev`) | 3 |
| Apps (`apps`) | 30 |
| **Total** | **166** |

## Perfiles

| Perfil | Alias | Incluye | Mantiene |
|---|---|---|---|
| `base` Base |  | 21 | 0 |
| `dev` Desarrollo | `desarrollo` | 6 | 0 |
| `gaming` Juegos | `juegos` | 12 | 3 |
| `privacy` Privacidad | `privacidad` | 53 | 0 |
| `laptop` Portátil | `portatil`, `portátil` | 7 | 0 |
| `legacy` Equipo antiguo | `equipo-antiguo`, `antiguo` | 30 | 0 |
| `work` Trabajo | `trabajo` | 10 | 8 |
| `lite` Liviano | `liviano` | 102 | 0 |

## Ajustes que preguntan

Estos ajustes llevan `ask: true`: sin menú interactivo y con `-Yes` se omiten, salvo que los pidas por nombre con `-Include`.

- `privacy.diagnostic-data-required`: Enviar solo los datos de diagnóstico requeridos
- `privacy.location-off`: Desactivar la ubicación del equipo
- `privacy.find-my-device-off`: Desactivar Encontrar mi dispositivo
- `privacy.error-reporting-off`: Desactivar el informe de errores de Windows
- `ai.recall-snapshots-off`: Recall: no guardar capturas (directiva de usuario)
- `ai.recall-unavailable`: Recall: no disponible en el equipo
- `services.diagtrack`: Desactivar el servicio de telemetría (DiagTrack)
- `services.geolocation`: Desactivar el servicio de ubicación del sistema
- `services.connected-devices`: Desactivar la plataforma de dispositivos conectados
- `services.connected-devices-user`: Desactivar el servicio de dispositivos conectados de cada usuario
- `services.contact-data`: Desactivar la indexación de contactos
- `services.user-data-storage`: Desactivar el almacén de datos de usuario (contactos, calendario, mensajes)
- `services.user-data-access`: Desactivar el acceso a datos de usuario (contactos, calendario, mensajes)
- `tasks.appraiser`: Desactivar el evaluador de compatibilidad de aplicaciones
- `tasks.appraiser-exp`: Desactivar el evaluador de compatibilidad (variante Exp)
- `tasks.program-data-updater`: Desactivar el actualizador de datos de programas
- `tasks.mare-backup`: Desactivar la recopilación de apps para Copia de seguridad de Windows
- `tasks.xbox-game-save`: Desactivar la tarea de partidas guardadas de Xbox
- `tasks.family-safety-monitor`: Desactivar el monitor de Seguridad familiar
- `tasks.family-safety-refresh`: Desactivar la actualización de Seguridad familiar
- `performance.background-apps-off`: No dejar que las apps de la Store corran en segundo plano
- `power.high-performance-plan`: Usar el plan de energía Alto rendimiento
- `power.standby-network-off-battery`: Sin red en suspensión moderna con batería
- `gaming.gamebar-controller-off`: El botón del mando no abre Game Bar
- `dev.sudo-enable`: Activar sudo para Windows
- `apps.copilot`: Quitar la app Copilot
- `apps.get-help`: Quitar Obtener ayuda
- `apps.alarms-clock`: Quitar Alarmas y reloj
- `apps.media-player`: Quitar el Reproductor multimedia
- `apps.quick-assist`: Quitar Asistencia rápida
- `apps.phone-link`: Quitar Vínculo con el móvil (Phone Link)
- `apps.xbox-gaming-app`: Quitar la app Xbox
- `apps.xbox-game-bar`: Quitar la Xbox Game Bar
- `apps.outlook-new`: Quitar el nuevo Outlook para Windows
- `apps.family-safety`: Quitar Seguridad familiar
- `apps.mail-calendar`: Quitar Correo y Calendario (descontinuada)
- `apps.msteams`: Quitar Microsoft Teams
- `apps.onedrive`: Desinstalar OneDrive (sin borrar tus archivos)

## Ajustes de riesgo alto

Ningún perfil los incluye. Solo se aplican si los pides por nombre con `-Include`.

- `privacy.diagnostic-data-off`: Apagar los datos de diagnóstico (Enterprise y Education)
- `ai.recall-snapshots-off`: Recall: no guardar capturas (directiva de usuario)
- `ai.recall-unavailable`: Recall: no disponible en el equipo
- `gaming.memory-integrity-off`: Desactivar la integridad de memoria (VBS/HVCI)

## Ajustes que no se aplican en Home

Son directivas que Windows Home ignora o funciones que Microsoft documenta solo para otras ediciones. En Home el plan los muestra como "no aplica" en lugar de fingir que funcionaron.

| Id | Ajuste | Ediciones |
|---|---|---|
| `privacy.diagnostic-data-required` | Enviar solo los datos de diagnóstico requeridos | Pro, Enterprise, Education |
| `privacy.diagnostic-data-off` | Apagar los datos de diagnóstico (Enterprise y Education) | Enterprise, Education |
| `privacy.activity-publish-off` | No publicar el historial de actividad | Pro, Enterprise, Education |
| `privacy.activity-upload-off` | No subir el historial de actividad a Microsoft | Pro, Enterprise, Education |
| `privacy.clipboard-cloud-off` | Desactivar el portapapeles en la nube | Pro, Enterprise, Education |
| `privacy.location-off` | Desactivar la ubicación del equipo | Pro, Enterprise, Education |
| `privacy.find-my-device-off` | Desactivar Encontrar mi dispositivo | Pro, Enterprise, Education |
| `ads.consumer-features` | Sin experiencias de consumo de Microsoft | Enterprise, Education |
| `ads.settings-home-365` | Sin anuncios de Microsoft 365 en Configuración | Enterprise, Education |
| `ads.start-hide-recommended-policy` | Ocultar la sección Recomendado de Inicio (directiva) | Pro, Enterprise, Education |
| `ui.widgets-off` | Desactivar Widgets (directiva) | Pro, Enterprise, Education |
| `ui.news-interests-win10` | Desactivar Noticias e intereses (Windows 10) | Pro, Enterprise, Education |
| `ai.copilot-policy-off` | Desactivar Windows Copilot (directiva de usuario) | Pro, Enterprise, Education |
| `ai.recall-snapshots-off` | Recall: no guardar capturas (directiva de usuario) | Pro, Enterprise, Education |
| `ai.recall-unavailable` | Recall: no disponible en el equipo | Pro, Enterprise, Education |
| `ai.click-to-do-off` | Desactivar Click to Do | Pro, Enterprise, Education |
| `ai.paint-cocreator-off` | Paint sin Cocreator | Pro, Enterprise, Education |
| `ai.paint-image-creator-off` | Paint sin Image Creator | Pro, Enterprise, Education |
| `ai.paint-generative-fill-off` | Paint sin Relleno generativo | Pro, Enterprise, Education |
| `performance.delivery-optimization-http-only` | No compartir descargas de Windows con otros equipos | Pro, Enterprise, Education |
| `power.standby-network-off-battery` | Sin red en suspensión moderna con batería | Pro, Enterprise, Education |

## Privacidad y telemetría (`catalog/privacy.json`)

### `privacy.advertising-id`

**Desactivar el ID de publicidad**

Las apps lo usan para mostrarte anuncios personalizados.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>

### `privacy.tailored-experiences`

**Desactivar experiencias personalizadas con datos de diagnóstico**

Evita que Microsoft use tus datos de diagnóstico para sugerencias y anuncios.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>

### `privacy.diagnostic-data-required`

**Enviar solo los datos de diagnóstico requeridos**

Impide los datos de diagnóstico opcionales (uso, navegación, volcados); Requerido es el mínimo en Pro. Pregunta antes porque un equipo del programa Windows Insider necesita los datos opcionales y dejaría de recibir compilaciones: no lo apliques ahí.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system>, <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>

### `privacy.diagnostic-data-off`

**Apagar los datos de diagnóstico (Enterprise y Education)**

Windows no envía datos de diagnóstico, ni los de Windows Update. Solo existe en Enterprise y Education; aplícalo junto con -Exclude privacy.diagnostic-data-required.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** alto; **Pregunta:** no
- **En perfiles:** ninguno; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system>

### `privacy.feedback-never`

**No pedir comentarios a Microsoft**

Quita las ventanas que piden valorar Windows.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `privacy.ceip-off`

**Desactivar el Programa de mejora de la experiencia**

Evita que Windows envíe estadísticas de uso por el CEIP.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/win32/devnotes/ceipenable>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-icm>

### `privacy.app-launch-tracking-off`

**No registrar qué apps abres**

Windows deja de contar tus aperturas para ordenar Inicio y la búsqueda.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>

### `privacy.online-speech-off`

**Desactivar el reconocimiento de voz en línea**

Tu voz no se envía a Microsoft; el dictado de Win+H deja de funcionar.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://support.microsoft.com/en-us/windows/privacy/speech-voice-activation-inking-typing-and-privacy>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `privacy.inking-typing-improve-off`

**No enviar cómo escribes para mejorar el teclado**

Microsoft deja de recibir muestras de tu escritura y tinta.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://support.microsoft.com/en-us/windows/privacy/speech-voice-activation-inking-typing-and-privacy>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `privacy.input-personalization-text-off`

**Desactivar el aprendizaje de lo que escribes**

Windows deja de recopilar tu texto para personalizar sugerencias.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>

### `privacy.input-personalization-ink-off`

**Desactivar el aprendizaje de tu escritura a mano**

Windows deja de recopilar tu tinta para personalizar el reconocimiento.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>

### `privacy.language-list-off`

**No compartir tu lista de idiomas con los sitios web**

Evita que los sitios vean los idiomas que tienes instalados.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>

### `privacy.activity-publish-off`

**No publicar el historial de actividad**

Windows no registra qué apps y archivos usaste para la línea de tiempo.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>

### `privacy.activity-upload-off`

**No subir el historial de actividad a Microsoft**

Tu historial de actividad no se envía a la nube ni a tus otros equipos.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `privacy.clipboard-cloud-off`

**Desactivar el portapapeles en la nube**

Lo que copias no viaja a tus otros equipos; el historial local de Win+V sigue funcionando.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy>

### `privacy.location-off`

**Desactivar la ubicación del equipo**

Ninguna app usa tu ubicación; el clima automático, Mapas y la zona horaria automática dejan de funcionar.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Location_Services.reg>

### `privacy.find-my-device-off`

**Desactivar Encontrar mi dispositivo**

El equipo deja de registrar su ubicación en tu cuenta Microsoft; no podrás localizarlo si lo pierdes.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Find_My_Device.reg>, <https://learn.microsoft.com/windows/client-management/mdm/policy-csp-experience>

### `privacy.error-reporting-off`

**Desactivar el informe de errores de Windows**

Los bloqueos no se envían a Microsoft; sin informes no llegan soluciones a problemas de controladores.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/win32/wer/wer-settings>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

## Anuncios y sugerencias (`catalog/ads.json`)

### `ads.start-suggestions`

**Sin sugerencias en Inicio**

Windows deja de mostrar apps sugeridas en el menú Inicio.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.start-system-pane`

**Sin sugerencias en el panel de Inicio**

Quita las sugerencias de aplicaciones del panel del sistema.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>

### `ads.start-recommendations`

**Sin consejos y apps nuevas en Recomendado**

Oculta los consejos, atajos y apps nuevas de la sección Recomendado de Inicio.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.start-account-notifications`

**Sin avisos de cuenta en Inicio**

Quita los avisos sobre tu cuenta Microsoft (copias de seguridad, ofertas) del menú Inicio.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22000 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.tips-and-tricks`

**Sin consejos y trucos de Windows**

Evita las notificaciones con consejos y sugerencias mientras usas Windows.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.welcome-experience`

**Sin pantalla de bienvenida tras actualizar**

Quita la pantalla "qué hay de nuevo" que aparece tras actualizar o iniciar sesión.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.settings-suggestions-1`

**Sin contenido sugerido en Configuración (1/3)**

Quita el contenido sugerido de la aplicación Configuración.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.settings-suggestions-2`

**Sin contenido sugerido en Configuración (2/3)**

Quita el contenido sugerido de la aplicación Configuración.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.settings-suggestions-3`

**Sin contenido sugerido en Configuración (3/3)**

Quita el contenido sugerido de la aplicación Configuración.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.finish-setup-prompts`

**Sin avisos para terminar de configurar el equipo**

Quita las sugerencias para "sacar más partido a Windows".

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.sync-provider-notifications`

**Sin anuncios de OneDrive y Microsoft 365 en el Explorador**

Oculta las notificaciones promocionales de proveedores de sincronización.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.silent-installed-apps`

**Sin instalación silenciosa de apps sugeridas**

Evita que Windows instale apps sugeridas sin preguntar.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.suggested-notifications`

**Sin notificaciones de apps sugeridas**

Desactiva los avisos "Sugerido" que promocionan servicios de Microsoft.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>

### `ads.phone-link-suggestions`

**Sin sugerencias para vincular el móvil**

Quita las sugerencias de usar el teléfono con Windows.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>

### `ads.backup-reminders`

**Sin recordatorios de Copia de seguridad de Windows**

Quita los avisos que insisten en activar Windows Backup con OneDrive.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22000 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Windows_Suggestions.reg>

### `ads.start-phone-link`

**Sin el móvil vinculado en Inicio**

Oculta el panel de Vínculo con el móvil del menú Inicio.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Phone_Link_In_Start.reg>

### `ads.lockscreen-tips`

**Sin datos curiosos ni consejos en la pantalla de bloqueo**

Quita los consejos y sugerencias sobre el fondo de la pantalla de bloqueo.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Lockscreen_Tips.reg>

### `ads.lockscreen-overlay`

**Sin recuadro de datos sobre el fondo de bloqueo**

Quita el recuadro con datos y enlaces que Spotlight pone sobre la imagen.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Lockscreen_Tips.reg>

### `ads.consumer-features`

**Sin experiencias de consumo de Microsoft**

Impide las apps promocionadas y las instalaciones tras la primera configuración (solo Enterprise y Education).

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `ads.settings-home-365`

**Sin anuncios de Microsoft 365 en Configuración**

Oculta el contenido de cuenta en la nube (Microsoft 365 y similares) de la página de inicio de Configuración. Microsoft documenta la directiva solo para Enterprise y Education; en otras ediciones puede no tener efecto.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22000 o posterior; **Ediciones:** Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Settings_365_Ads.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience>

### `ads.start-hide-recommended-policy`

**Ocultar la sección Recomendado de Inicio (directiva)**

Quita por directiva la sección de archivos y apps recomendados (Pro, Enterprise y Education, según la documentación de Microsoft).

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Start_Recommended.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-start>

### `ads.start-recent-files-off`

**Sin archivos recientes en Inicio ni en el Explorador**

Deja de registrar y mostrar archivos abiertos recientemente en Inicio, listas de salto y Acceso rápido.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.start-recent-apps-off`

**Sin apps agregadas recientemente en Inicio**

Oculta la lista de apps agregadas recientemente.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22000 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.start-most-used-off`

**Sin apps más usadas en Inicio**

Oculta la lista de apps más usadas.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22000 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.bing-search-off`

**Sin resultados de Bing en la búsqueda de Windows**

La búsqueda de Inicio no envía lo que escribes a Bing.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.search-box-suggestions-off`

**Sin sugerencias web en el cuadro de búsqueda (directiva)**

Directiva de usuario que apaga las sugerencias de búsqueda en línea del cuadro de búsqueda.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Bing_Cortana_In_Search.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.search-highlights-off`

**Sin Búsqueda destacada**

Quita la ilustración y el contenido de actualidad del cuadro de búsqueda.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19043 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Search_Highlights.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ads.search-history-off`

**Sin historial de búsqueda en este equipo**

Deja de guardar lo que buscas en Windows.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Search_History.reg>

## Interfaz (`catalog/ui.json`)

### `ui.show-file-extensions`

**Mostrar las extensiones de archivo**

Permite distinguir un documento de un ejecutable disfrazado (factura.pdf.exe).

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `base`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Show_Extensions_For_Known_File_Types.reg>

### `ui.show-hidden-files`

**Mostrar archivos y carpetas ocultos**

Útil al programar: deja ver .git, AppData y otros elementos ocultos.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `dev`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Show_Hidden_Folders.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ui.taskbar-end-task`

**"Finalizar tarea" en la barra de tareas**

Agrega Finalizar tarea al menú contextual de las apps de la barra de tareas.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `dev`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22631 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Enable_End_Task.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ui.task-view-button-off`

**Ocultar el botón Vista de tareas**

Libera espacio en la barra de tareas; Win+Tab sigue funcionando.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Hide_Taskview_Taskbar.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `ui.widgets-off`

**Desactivar Widgets (directiva)**

Quita el panel de Widgets y sus procesos web en segundo plano. No funciona en Home. En la compilación 26300 Windows no deja que los programas escriban este valor, ni como administrador: se informa como rechazado sin cambiar nada.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22000 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Si el acceso está denegado, cambiarlo a mano en:** Configuración > Personalización > Barra de tareas > Widgets
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `ui.news-interests-win10`

**Desactivar Noticias e intereses (Windows 10)**

Quita el widget de noticias de la barra de tareas de Windows 10.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_10/Module/Sophia.psm1>

### `ui.meet-now-win10`

**Ocultar Reunirse ahora (Windows 10)**

Quita el icono de Reunirse ahora de la barra de tareas de Windows 10.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Chat_Taskbar.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_10/Module/Sophia.psm1>

### `ui.transparency-off`

**Desactivar la transparencia**

Menos trabajo para la GPU en equipos modestos.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Transparency.reg>

### `ui.window-animations-off`

**Sin animación al minimizar y maximizar**

Las ventanas aparecen y desaparecen sin animación; se nota al volver a iniciar sesión.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `ui.listview-shadow-off`

**Sin sombra en las etiquetas de iconos**

Quita la sombra del texto de los iconos del escritorio.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `ui.listview-alpha-select-off`

**Sin selección translúcida**

El rectángulo de selección es sólido, sin efecto de transparencia.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `ui.aero-peek-off`

**Sin vista previa al pasar sobre el escritorio**

Desactiva Aero Peek, que redibuja las ventanas al pasar el ratón por la esquina de la barra.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

## Copilot, Recall e IA (`catalog/ai.json`)

### `ai.copilot-button-off`

**Ocultar el botón de Copilot**

Quita el icono de Copilot de la barra de tareas.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `work`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Copilot.reg>

### `ai.copilot-policy-off`

**Desactivar Windows Copilot (directiva de usuario)**

Directiva (en desuso) que apaga el panel de Copilot; no cubre la app nueva.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19045 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Copilot.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.recall-snapshots-off`

**Recall: no guardar capturas (directiva de usuario)**

Impide que Recall guarde capturas de pantalla y borra las que ya existen; deshacer no puede devolverlas.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** alto; **Pregunta:** sí
- **En perfiles:** ninguno; **Lo mantienen:** ninguno
- **Windows:** 11, build 26100 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_AI_Recall.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.recall-unavailable`

**Recall: no disponible en el equipo**

Quita Recall del equipo (hace falta reiniciar) y borra las capturas guardadas; deshacer no puede devolverlas.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** alto; **Pregunta:** sí
- **En perfiles:** ninguno; **Lo mantienen:** ninguno
- **Windows:** 11, build 26100 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** reiniciar
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_AI_Recall.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.click-to-do-off`

**Desactivar Click to Do**

Apaga el análisis de pantalla de Click to Do (usuario).

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 26100 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Click_to_Do.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.notepad-ai-off`

**Bloc de notas sin funciones de IA**

Desactiva Reescribir, Resumir y otras funciones de IA del Bloc de notas.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/client-management/manage-notepad>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Notepad_AI_Features.reg>

### `ai.paint-cocreator-off`

**Paint sin Cocreator**

Desactiva Cocreator en Paint (función de IA en la nube).

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Paint_AI_Features.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.paint-image-creator-off`

**Paint sin Image Creator**

Desactiva Image Creator en Paint (función de IA en la nube).

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Paint_AI_Features.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.paint-generative-fill-off`

**Paint sin Relleno generativo**

Desactiva Relleno generativo en Paint (función de IA en la nube).

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Paint_AI_Features.reg>, <https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai>

### `ai.fabric-service-manual`

**Servicio de estructura de IA solo a petición**

WSAIFabricSvc deja de arrancar siempre con Windows; se inicia cuando una función de IA lo pide.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 26100 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_AI_Service_Auto_Start.reg>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

## Microsoft Edge (`catalog/edge.json`)

### `edge.personalization-reporting-off`

**Edge no envía tu navegación para personalizar anuncios**

Microsoft no recibe tu historial y favoritos para anuncios, búsqueda y noticias.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/personalizationreportingenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `edge.diagnostic-data-required`

**Edge envía solo los datos de diagnóstico requeridos**

Edge deja de enviar a Microsoft los datos opcionales de uso, sitios visitados y errores; solo envía los requeridos para mantenerse seguro y al día.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/diagnosticdata>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Telemetry.reg>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `edge.feedback-off`

**Edge sin el envío de comentarios**

Quita Enviar comentarios de Edge, que adjunta datos del navegador.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/deployedge/microsoft-edge-browser-policies/userfeedbackallowed>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `edge.new-tab-feed-off`

**Edge sin noticias en la pestaña nueva**

Quita el contenido de MSN de la pestaña nueva.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagecontentenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.shopping-off`

**Edge sin asistente de compras**

Apaga la comparación de precios y los cupones automáticos.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/edgeshoppingassistantenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.recommendations-off`

**Edge sin recomendaciones de funciones**

Quita los avisos que sugieren probar funciones del navegador.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/showrecommendationsenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.spotlight-off`

**Edge sin Spotlight ni consejos de Microsoft**

Quita fondos, sugerencias y consejos sobre servicios de Microsoft.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/spotlightexperiencesandrecommendationsenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.default-browser-campaign-off`

**Edge sin campañas para ser el navegador predeterminado**

No te pide cambiar el navegador ni el buscador a Edge y Bing.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/defaultbrowsersettingscampaignenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.acrobat-button-off`

**Edge sin botón de suscripción a Acrobat**

Quita el botón que promociona Acrobat en el lector de PDF.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/showacrobatsubscriptionbutton>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.first-run-off`

**Edge sin pantalla de primer inicio**

Omite la bienvenida que ofrece iniciar sesión y activar la sincronización.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/hidefirstrunexperience>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `edge.alternate-error-pages-off`

**Edge sin páginas de error alternativas**

No envía a Microsoft la dirección que falló para sugerir otra página.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/alternateerrorpagesenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_Ads_And_Suggestions.reg>

### `edge.sidebar-off`

**Edge sin barra lateral**

Oculta la barra lateral de Edge (Copilot, Descubrir, accesos de compras). No rige en perfiles con cuenta Microsoft; el icono de Copilot de la barra de herramientas lo controla otra directiva (Microsoft365CopilotChatIconEnabled).

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/hubssidebarenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg>

### `edge.new-tab-bing-chat-off`

**Edge sin accesos a Bing Chat en la pestaña nueva**

Quita los accesos a Bing Chat de la pestaña nueva.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagebingchatenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg>

### `edge.history-ai-search-off`

**Edge sin búsqueda con IA en el historial**

El historial solo busca coincidencias exactas.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/edgehistoryaisearchenabled>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg>

### `edge.local-ai-model-off`

**Edge sin descarga del modelo de IA local**

Evita descargar el modelo de IA local y borra el que ya exista.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/genailocalfoundationalmodelsettings>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Edge_AI_Features.reg>

### `edge.startup-boost-off`

**Que Edge no arranque procesos al iniciar sesión**

Sin el impulso de inicio, Edge no deja procesos precargados en memoria; se abre un poco más lento la primera vez. Tú puedes cambiarlo en edge://settings/system.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `laptop`, `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/deployedge/microsoft-edge-policies/startupboostenabled>

### `edge.background-mode-off`

**Que Edge no siga en segundo plano al cerrarlo**

Al cerrar la última ventana, Edge termina del todo y libera su memoria. Tú puedes cambiarlo en edge://settings/system.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `laptop`, `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/deployedge/microsoft-edge-policies/backgroundmodeenabled>

## Servicios (`catalog/services.json`)

### `services.retail-demo`

**Desactivar el servicio de demostración para tiendas**

Solo se usa en equipos de exhibición en tiendas.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-unattendenableretaildemo>

### `services.diagtrack`

**Desactivar el servicio de telemetría (DiagTrack)**

Detiene el envío de datos de diagnóstico; puede afectar Feedback Hub, Xbox y Defender for Endpoint.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>, <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/Services.json>

### `services.wia`

**Pasar a manual el servicio de adquisición de imágenes (WIA)**

Solo hace falta al usar un escáner o una cámara; Windows lo inicia solo cuando conectas el dispositivo.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `laptop`, `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>

### `services.maps-broker`

**Pasar a manual el servicio de mapas descargados**

Solo sirve a las apps que usan mapas sin conexión; se inicia cuando una app lo pide y deja de arrancar con Windows.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `laptop`, `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `services.geolocation`

**Desactivar el servicio de ubicación del sistema**

Apaga la ubicación para todo el equipo. Las apps que la usan (clima, mapas, zona horaria automática) dejan de saber dónde estás.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>, <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/Services.json>

### `services.connected-devices`

**Desactivar la plataforma de dispositivos conectados**

Alimenta compartir con dispositivos cercanos, Vínculo móvil y el portapapeles entre equipos. Si no los usas, es un servicio menos.

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>, <https://learn.microsoft.com/windows/application-management/per-user-services-in-windows>

### `services.connected-devices-user`

**Desactivar el servicio de dispositivos conectados de cada usuario**

Es la parte por usuario del servicio anterior. Windows deja de crearla al iniciar sesión (surte efecto en la próxima sesión).

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://learn.microsoft.com/windows/application-management/per-user-services-in-windows>, <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>

### `services.contact-data`

**Desactivar la indexación de contactos**

Indexa contactos para la búsqueda. Sin Correo, Calendario ni Contactos de Windows no aporta nada (surte efecto en la próxima sesión).

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://learn.microsoft.com/windows/application-management/per-user-services-in-windows>, <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>

### `services.user-data-storage`

**Desactivar el almacén de datos de usuario (contactos, calendario, mensajes)**

Guarda contactos, calendarios y mensajes para las apps de Windows que los usan. Sin esas apps es memoria sin uso (surte efecto en la próxima sesión).

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://learn.microsoft.com/windows/application-management/per-user-services-in-windows>, <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>

### `services.user-data-access`

**Desactivar el acceso a datos de usuario (contactos, calendario, mensajes)**

Da a las apps acceso a esos datos. Va junto con el almacén de datos de usuario (surte efecto en la próxima sesión).

- **Tipo:** `service`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://learn.microsoft.com/windows/application-management/per-user-services-in-windows>, <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>

## Tareas programadas (`catalog/tasks.json`)

### `tasks.ceip-consolidator`

**Desactivar la tarea de consolidación del Programa de mejora de la experiencia**

Recopila y envía datos de uso a Microsoft.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.ceip-usbceip`

**Desactivar la tarea de estadísticas USB del programa de mejora**

Envía a Microsoft estadísticas de los dispositivos USB conectados.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.autochk-proxy`

**Desactivar la tarea de datos de Autochk**

Recoge datos de la revisión de disco al arrancar para enviarlos a Microsoft.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.disk-diagnostic-data-collector`

**Desactivar el envío de datos del diagnóstico de discos**

Envía información general de tus discos y del sistema a Microsoft.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.appraiser`

**Desactivar el evaluador de compatibilidad de aplicaciones**

Envía el inventario de programas y controladores; sin él Windows puede no ofrecer actualizaciones de función.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.appraiser-exp`

**Desactivar el evaluador de compatibilidad (variante Exp)**

Variante del evaluador de compatibilidad; mismo envío de inventario y mismo riesgo para las actualizaciones.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.program-data-updater`

**Desactivar el actualizador de datos de programas**

Recoge datos de los programas instalados para la telemetría de compatibilidad.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>

### `tasks.mare-backup`

**Desactivar la recopilación de apps para Copia de seguridad de Windows**

Recoge la lista de tus programas para la copia en la nube (esa lista no se restaurará). En compilaciones recientes también ejecuta el evaluador de compatibilidad, así que desactivarla puede detener las ofertas de actualizaciones de función.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.startup-app-task`

**Desactivar el aviso de demasiadas apps de inicio**

Deja de revisar el inicio para avisarte; no recopila datos, es solo una molestia.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Scripts/Features/Telemetry-ScheduledTasks.ps1>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `tasks.maps-toast`

**Desactivar la tarea de avisos de Mapas**

Muestra avisos de mapas descargados; sin esa función solo gasta un arranque.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.maps-update`

**Desactivar la tarea de actualización de mapas**

Descarga actualizaciones de mapas sin conexión que casi nadie usa.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows-server/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server>, <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.xbox-game-save`

**Desactivar la tarea de partidas guardadas de Xbox**

Despierta el servicio de partidas guardadas de Xbox Live aunque no juegues. Pregunta antes porque los juegos de Game Pass pueden perder la sincronización de sus partidas guardadas; el perfil Gaming la conserva.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** `gaming`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.power-efficiency-analyze`

**Desactivar el análisis semanal de eficiencia energética**

Genera un informe de energía que casi nadie lee. Puedes pedirlo cuando quieras con powercfg /energy.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.disk-footprint-diagnostics`

**Desactivar la tarea de diagnóstico de uso de disco**

Recoge datos de uso de almacenamiento para diagnóstico; no limpia ni cambia nada en tu disco.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.work-folders-logon`

**Desactivar la sincronización de Carpetas de trabajo al iniciar sesión**

Carpetas de trabajo es una función de empresa; sin ella la tarea solo se ejecuta en cada inicio de sesión sin hacer nada.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.work-folders-maintenance`

**Desactivar el mantenimiento de Carpetas de trabajo**

Mantenimiento periódico de una función de empresa que no se usa en equipos personales.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.winsat`

**Desactivar la evaluación periódica del rendimiento (WinSAT)**

Ejecuta una prueba de disco y gráficos en segundo plano; en discos mecánicos se nota. Windows ya no usa el índice de experiencia.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.recommended-troubleshooting`

**Desactivar el análisis de soluciones recomendadas**

Busca problemas en segundo plano para sugerir solucionadores. Siguen disponibles a mano en Configuración.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.family-safety-monitor`

**Desactivar el monitor de Seguridad familiar**

Solo sirve si el equipo usa controles parentales de Microsoft. Con ellos activos, dejan de aplicarse.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.family-safety-refresh`

**Desactivar la actualización de Seguridad familiar**

Va de la mano del monitor de Seguridad familiar: sin controles parentales no hace falta.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

### `tasks.speech-model-download`

**Desactivar la descarga de modelos de voz**

Descarga en segundo plano datos para el reconocimiento de voz en línea; no hace falta si no dictas.

- **Tipo:** `task`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/blob/main/2009/ConfigurationFiles/ScheduledTasks.json>

## Rendimiento (`catalog/performance.json`)

### `performance.delivery-optimization-http-only`

**No compartir descargas de Windows con otros equipos**

Delivery Optimization descarga solo por HTTP y deja de subir actualizaciones a otros equipos de tu red. Las actualizaciones siguen llegando igual.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `laptop`, `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/windows/deployment/do/waas-delivery-optimization-reference>, <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `performance.explorer-folder-type-general`

**Que el Explorador no adivine el tipo de cada carpeta**

Explorer deja de analizar el contenido para elegir columnas (imágenes, música); las carpetas grandes abren más rápido, sobre todo en disco mecánico.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>

### `performance.background-apps-off`

**No dejar que las apps de la Store corran en segundo plano**

Ahorra batería y memoria; a cambio, apps como Correo o Alarmas no avisan con la app cerrada y los fondos de Windows Spotlight pueden dejar de actualizarse. Puedes permitir apps una a una en Configuración.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `laptop`, `legacy`; **Lo mantienen:** ninguno
- **Windows:** 10, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json>, <https://www.elevenforum.com/t/enable-or-disable-background-apps-in-windows-11.923/>

## Energía (`catalog/power.json`)

### `power.high-performance-plan`

**Usar el plan de energía Alto rendimiento**

Para escritorios: mantiene el procesador listo y evita ahorros que añaden latencia. En portátiles gasta batería.

- **Tipo:** `powercfg`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Solo en:** equipos sin batería
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-power-slider>, <https://github.com/farag2/Sophia-Script-for-Windows>

### `power.usb-selective-suspend-ac-off`

**No suspender los USB con corriente**

Evita cortes y retardos al despertar mouse, teclado, mando o dispositivos de depuración. Con batería no cambia nada.

- **Tipo:** `powercfg`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `dev`, `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options>

### `power.standby-network-off-battery`

**Sin red en suspensión moderna con batería**

Ahorra batería mientras la tapa está cerrada. Se pierden notificaciones y Escritorio remoto hasta que despiertes el equipo.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `laptop`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Pro, Enterprise, Education
- **Solo en:** equipos con batería
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-network-connectivity>, <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Modern_Standby_Networking.reg>

## Juegos (`catalog/gaming.json`)

### `gaming.game-mode-on`

**Activar el Modo Juego**

Windows da prioridad al juego en primer plano y evita instalar drivers mientras juegas.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `gaming.game-dvr-off`

**Desactivar Game DVR**

Evita que Windows grabe el juego en segundo plano y consuma GPU y disco.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_DVR.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `gaming.app-capture-off`

**Desactivar la captura de juegos y apps**

Apaga la captura de pantalla y video de Xbox Game Bar. Las apps de Xbox siguen instaladas.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_DVR.reg>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `gaming.background-recording-off`

**Desactivar la grabación en segundo plano**

Impide que Game Bar guarde en memoria los últimos minutos de juego.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/main/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `gaming.gamebar-controller-off`

**El botón del mando no abre Game Bar**

Evita que el botón Xbox del mando abra el overlay y te saque del juego.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** sí
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Game_Bar_Integration.reg>

### `gaming.mouse-accel-off`

**Desactivar la aceleración del mouse**

El puntero se mueve igual que la mano (1:1), sin "Mejorar la precisión del puntero".

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Enhance_Pointer_Precision.reg>

### `gaming.mouse-accel-threshold-1`

**Mouse sin aceleración: primer umbral en 0**

Va junto con la aceleración desactivada; deja el primer umbral de velocidad en 0.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Enhance_Pointer_Precision.reg>

### `gaming.mouse-accel-threshold-2`

**Mouse sin aceleración: segundo umbral en 0**

Va junto con la aceleración desactivada; deja el segundo umbral de velocidad en 0.

- **Tipo:** `registry`; **Ámbito:** usuario (sin administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** cerrar sesión
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Regfiles/Disable_Enhance_Pointer_Precision.reg>

### `gaming.windowed-optimizations`

**Optimizaciones para juegos en ventana**

Los juegos DirectX 10 y 11 en ventana o sin bordes usan el modelo flip: menos latencia, Auto HDR y VRR. Reinicia el juego.

- **Tipo:** `action`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://support.microsoft.com/topic/3f006843-2c7e-4ed0-9a5e-f9389e535952>

### `gaming.hags-on`

**Programación de GPU acelerada por hardware**

La GPU gestiona su propia cola de trabajo y baja la latencia de envío. Solo si el driver lo admite.

- **Tipo:** `action`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** no
- **En perfiles:** `gaming`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** reiniciar
- **Fuentes:** <https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/>, <https://learn.microsoft.com/windows-hardware/drivers/ddi/d3dkmthk/ne-d3dkmthk-_kmtqueryadapterinfotype>, <https://github.com/farag2/Sophia-Script-for-Windows/blob/master/src/Sophia_Script_for_Windows_11/Module/Sophia.psm1>

### `gaming.memory-integrity-off`

**Desactivar la integridad de memoria (VBS/HVCI)**

Puede dar entre 1 y 15 % más de FPS en algunos juegos (poco en CPU recientes), a cambio de menos protección contra drivers maliciosos. Reinicia.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** alto; **Pregunta:** no
- **En perfiles:** ninguno; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** reiniciar
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity>, <https://www.tomshardware.com/news/windows-11-gaming-benchmarks-performance-vbs-hvci-security/>, <https://petri.com/windows-11-memory-integrity-eligible-devices/>

## Desarrollo (`catalog/dev.json`)

### `dev.developer-mode`

**Activar el Modo desarrollador**

Permite instalar apps de prueba sin licencia y crear vínculos simbólicos sin ser administrador (git, npm, pnpm).

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** no
- **En perfiles:** `dev`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode>, <https://blogs.windows.com/windowsdeveloper/2016/12/02/symlinks-windows-10/>

### `dev.long-paths`

**Permitir rutas de más de 260 caracteres**

Evita errores en node_modules, git y compiladores con carpetas muy anidadas. Solo lo usan las apps preparadas; el Explorador no.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `dev`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** reiniciar
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation>

### `dev.sudo-enable`

**Activar sudo para Windows**

Permite ejecutar un comando como administrador desde una consola normal, en una ventana nueva y con confirmación de UAC.

- **Tipo:** `registry`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `dev`; **Lo mantienen:** ninguno
- **Windows:** 11, build 26100 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/en-us/windows/advanced-settings/sudo/>, <https://github.com/microsoft/sudo>

## Apps (`catalog/apps.json`)

### `apps.clipchamp`

**Quitar Clipchamp**

Editor de video preinstalado que casi nunca se usa.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9p1j8s7ccwwt>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.bing-news`

**Quitar Noticias (Microsoft News)**

App de noticias de Microsoft; nada más depende de ella.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfhvfw>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.bing-weather`

**Quitar la app Tiempo (MSN Weather)**

App del clima; el clima de la barra de tareas viene de Widgets, no de esta app.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfj3q2>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.bing-finance`

**Quitar Finanzas (MSN Money)**

App descontinuada de noticias financieras, propia de Windows 10.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfhv4v>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.office-hub`

**Quitar la app Microsoft 365 (Copilot)**

Es solo un acceso a Office y publicidad de suscripciones; Word y Excel no dependen de ella.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrd29v9>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.power-automate`

**Quitar Power Automate**

Herramienta de automatización (RPA) que casi nadie usa; se puede reinstalar.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nftch6j7fhv>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.dev-home`

**Quitar Dev Home (descontinuada)**

Microsoft retiró Dev Home. Al deshacer, la Store instala la app que hoy ocupa su lugar (Configuración avanzada de Windows).

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9n8mhtphngvv>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.messaging`

**Quitar Mensajes (Windows 10)**

App de mensajes atada a Skype, descontinuada.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfjbq6>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.mixed-reality-portal`

**Quitar el Portal de realidad mixta**

Solo sirve con visores de realidad mixta de Windows.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9ng1h8b3zc7m>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.movies-tv`

**Quitar Películas y TV**

Reproductor y tienda de video de Microsoft, ya reemplazado por el Reproductor multimedia.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `legacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfj3p2>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.bing-search`

**Quitar la integración de Bing en la búsqueda**

Es el componente que lleva la búsqueda web de Bing al menú Inicio.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nzbf4gt040c>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.copilot`

**Quitar la app Copilot**

Asistente de IA; se quita para reducir procesos y datos enviados.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `privacy`, `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nht9rb2f4hd>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.get-help`

**Quitar Obtener ayuda**

Algunos solucionadores de problemas y enlaces de soporte la abren; sin ella no hay ayuda en la app.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9pkdzbmv1h3t>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.feedback-hub`

**Quitar el Centro de opiniones**

Solo sirve para enviar comentarios a Microsoft o para Insiders.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nblggh4r32n>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.todos`

**Quitar Microsoft To Do**

Las tareas viven en tu cuenta Microsoft; reaparecen al reinstalar.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nblggh5r558>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.alarms-clock`

**Quitar Alarmas y reloj**

Se pierden alarmas, temporizadores y sesiones de concentración.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfj3pr>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.sound-recorder`

**Quitar la Grabadora de sonidos**

Grabadora básica; las grabaciones ya hechas quedan en Documentos.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** bajo; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfhwkn>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.media-player`

**Quitar el Reproductor multimedia**

Es el reproductor predeterminado de audio y video; sin él hay que instalar otro.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfj3pt>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.quick-assist`

**Quitar Asistencia rápida**

Es la herramienta con la que otros te ayudan a distancia; sin ella no podrán.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9p7bp5vnwkx5>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.phone-link`

**Quitar Vínculo con el móvil (Phone Link)**

Conecta el teléfono al PC; si lo usas, deja de funcionar.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nmpj99vjbwv>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.xbox-gaming-app`

**Quitar la app Xbox**

Necesaria para Game Pass y para instalar algunos juegos de la Store.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** `gaming`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9mv0b5hzvk9z>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.xbox-game-bar`

**Quitar la Xbox Game Bar**

Barra de juego con captura; sin ella Win+G no hace nada.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** `gaming`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nzkpstsnw4p>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.widgets-web-experience`

**Quitar el paquete de experiencia web (Widgets)**

Es lo que muestra el panel de Widgets y su fuente de noticias.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9mssgkg348sp>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.widgets-platform-runtime`

**Quitar el runtime de Widgets**

Componente que hace funcionar los Widgets; sin Widgets no hace falta.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9n3rk8zv2zr8>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.start-experiences`

**Quitar la app de experiencias de Inicio**

Alimenta el contenido de Widgets y de Inicio; puede irse con ellos.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** no
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 11, build 22621 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9pc1h9vn18cm>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.outlook-new`

**Quitar el nuevo Outlook para Windows**

Cliente de correo; si es tu correo, conviene conservarlo.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9nrx63209r7b>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.family-safety`

**Quitar Seguridad familiar**

Controles parentales; en cuentas de menores deja de aplicarlos.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9pdjdjs743xf>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.mail-calendar`

**Quitar Correo y Calendario (descontinuada)**

Microsoft la reemplazó por el nuevo Outlook; People depende de ella.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** ninguno
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/9wzdncrfhvqm>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.msteams`

**Quitar Microsoft Teams**

Reuniones y chat; si lo usas en el trabajo, conviene conservarlo.

- **Tipo:** `appx`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>, <https://apps.microsoft.com/detail/xp8bt8dw290mpq>, <https://learn.microsoft.com/windows/application-management/overview-windows-apps>, <https://learn.microsoft.com/powershell/module/appx/remove-appxpackage>

### `apps.onedrive`

**Desinstalar OneDrive (sin borrar tus archivos)**

Quita el cliente de sincronización; tus carpetas y archivos no se tocan. Se rechaza si Escritorio, Documentos o Imágenes están en OneDrive o hay archivos solo en la nube.

- **Tipo:** `action`; **Ámbito:** equipo (administrador); **Riesgo:** medio; **Pregunta:** sí
- **En perfiles:** `lite`; **Lo mantienen:** `work`
- **Windows:** 10, 11, build 19041 o posterior; **Ediciones:** Home, Pro, Enterprise, Education
- **Después de aplicar:** nada
- **Fuentes:** <https://learn.microsoft.com/sharepoint/per-machine-installation>, <https://support.microsoft.com/office/turn-off-disable-or-uninstall-onedrive-f32a17ce-3336-40fe-9c38-6efb09f944b0>, <https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json>

## No incluido

Lo que se evaluó y quedó fuera del catálogo, con el motivo. La lista de lo que no se aplica nunca, ni siquiera con `-Include`, está en [blacklist.md](blacklist.md).

### Apps que no se pueden reinstalar al deshacer

Deshacer reinstala una app con winget desde la Microsoft Store. Para estas apps winget no encuentra el producto (código 0x8A150014, comprobado el 2026-10-01), así que quitarlas no se podría deshacer: quedan fuera.

- **Microsoft Solitaire Collection** (`Microsoft.MicrosoftSolitaireCollection`): winget no resuelve 9WZDNCRFHWD2.
- **Microsoft Tips** (`Microsoft.Getstarted`): winget no resuelve 9WZDNCRDTBJJ.
- **People** (`Microsoft.People`): winget no resuelve 9NBLGGH10PG8.
- **Windows Maps** (`Microsoft.WindowsMaps`): winget no resuelve 9WZDNCRDTBVB.
- **3D Viewer** (`Microsoft.Microsoft3DViewer`): winget no resuelve 9NBLGGH42THS.
- **Paint 3D** (`Microsoft.MSPaint`): winget no resuelve 9NBLGGH5FV99 (no es el Paint actual).
- **Print 3D** (`Microsoft.Print3D`): winget no resuelve 9PBPCH085S3S.
- **3D Builder** (`Microsoft.3DBuilder`): winget no resuelve 9WZDNCRFJ3T6.
- **Microsoft Wallet** (`Microsoft.Wallet`): winget no resuelve 9NBLGGH52CKV.
- **Mobile Plans** (`Microsoft.OneConnect`): winget no resuelve 9NBLGGH5PNB1.
- **MSN Sports** (`Microsoft.BingSports`): winget no resuelve 9WZDNCRFHVH4.
- **Translator** (`Microsoft.BingTranslator`): winget no resuelve 9WZDNCRFJ3PG.
- **Xbox Game Bar Plugin** (`Microsoft.XboxGameOverlay`): winget no resuelve 9NBLGGH537C2.
- **Xbox Console Companion** (`Microsoft.XboxApp`): winget no resuelve 9WZDNCRFJBD8.
- **Cortana** (`Microsoft.549981C3F5F10`): winget no resuelve 9NFFX4SZZ23L; Cortana ya no existe en Windows 11.
- **Microsoft PC Manager** (`Microsoft.PCManager`): winget no resuelve 9P35S3ZNMCHL.
- **Network Speed Test** (`Microsoft.NetworkSpeedTest`): winget no resuelve 9WZDNCRFHX52.
- **Sway** (`Microsoft.Office.Sway`): winget no resuelve 9WZDNCRD2G0J.

### Apps sin producto en la Store

Llegan con Windows o con Windows Update y no tienen un id de la Store con el que reinstalarlas, o no se pudo comprobar qué paquete instala su id.

- **Microsoft 365 Companions** (`Microsoft.M365Companions`): Sin producto en la Store.
- **AI Hub** (`Microsoft.Windows.AIHub`): Sin producto en la Store.
- **Cross Device Experience Host** (`MicrosoftWindows.CrossDevice`): Paquete del sistema que acompaña a Vínculo móvil; sin producto en la Store.
- **Skype** (`Microsoft.SkypeApp`): Ya no tiene producto en la Store.
- **Microsoft Teams (clásico personal)** (`MicrosoftTeams`): Sin producto en la Store; el Teams nuevo (MSTeams) sí está en el catálogo.
- **Microsoft Copilot (XP9CXNGPPJ97XX)**: winget lo resuelve, pero no se pudo saber qué paquete Appx instala; la app Copilot de Windows (9NHT9RB2F4HD) sí está.

### Apps que no se quitan nunca

Otras apps dependen de ellas, Windows no deja quitarlas o guardan datos del usuario dentro de la app.

- **Microsoft Store** (`Microsoft.WindowsStore`): Deshacer cualquier app depende de ella. Quitarla sería una opción aparte con advertencia; hoy no existe.
- **Instalador de aplicación (winget)** (`Microsoft.DesktopAppInstaller`): Es winget: sin él no hay deshacer. Windows no deja quitarlo.
- **Seguridad de Windows** (`Microsoft.SecHealthUI`): Interfaz de Defender; Windows no deja quitarla.
- **Xbox Identity Provider, Xbox TCUI, Xbox Speech To Text Overlay, Game Callable UI**: La Store, Game Pass y los juegos los usan para iniciar sesión.
- **Fotos, Calculadora, Bloc de notas, Paint, Recortes, Cámara, Terminal**: Herramientas básicas y predeterminadas; no son apps basura.
- **Notas rápidas, Journal, Whiteboard, OneNote**: Guardan notas del usuario dentro de la app: quitarlas las borra.
- **Microsoft Edge, WebView2, códecs y frameworks (Microsoft.NET.*, Microsoft.VCLibs.*, Microsoft.UI.Xaml.*)**: Otras apps dependen de ellos.

### Servicios de Xbox

Estaban en el catálogo y se quitaron: ya vienen en manual y Windows los inicia solos cuando un juego los necesita, así que deshabilitarlos no ahorra nada y rompe el inicio de sesión de Xbox y de los juegos de Game Pass. La app y la tarea de Xbox sí se pueden quitar (el perfil `gaming` las conserva).

- **XblGameSave**: Partidas guardadas de Xbox Live; ya viene en manual.
- **XblAuthManager**: Inicio de sesión de Xbox Live; deshabilitarlo impide entrar a los juegos que lo usan.
- **XboxNetApiSvc**: Red de Xbox Live para el multijugador; ya viene en manual.

### Directivas que Windows Home ignora

Windows Home ignora muchas directivas de grupo. Los ajustes del catálogo que son directivas declaran las ediciones donde Microsoft las documenta y el plan los muestra como "no aplica" en Home (la lista está más arriba, en "Ajustes que no se aplican en Home"). Lo que sigue quedó fuera porque en Home no hay una forma que funcione y se pueda deshacer.

- **Telemetría al mínimo por directiva en Home**: AllowTelemetry en las directivas no rige en Home; lo único que corta la subida de datos ahí es el servicio DiagTrack (services.diagtrack, con pregunta).
- **Contenido de consumidor y tarjetas de Microsoft 365 en Home y Pro**: DisableWindowsConsumerFeatures y DisableConsumerAccountStateContent solo rigen en Enterprise y Education; en Home y Pro los ajustes de usuario de anuncios cubren lo que se puede.
- **Widgets en Home (TaskbarDa)**: Windows bloquea la escritura de ese valor desde PowerShell (UCPD); la directiva solo rige en Pro y superiores.
- **Red en suspensión moderna y Delivery Optimization en Home**: Sin una directiva que Home respete hay que escribir en otras colmenas o subgrupos que el motor no admite.

### Acciones descartadas

Se evaluaron como acciones propias y se descartaron porque no se pudo verificar, en solo lectura, que hacen lo que prometen y que se pueden deshacer.

- **power-mode-overlay: modo de energía "Mejor rendimiento" con corriente**: Es una superposición del plan que solo se cambia con una función de Windows sin documentar (PowerSetActiveOverlayScheme); no se sabe si cambia CA y CC juntos ni si escribir el registro surte efecto en caliente.
- **dev-defender-performance-mode: modo de rendimiento de Defender para Dev Drive**: Microsoft lo activa por defecto en un Dev Drive de confianza y el valor leído en un equipo sin Dev Drive contradice esa documentación; sin un Dev Drive no se puede comprobar, y toca Defender.

### Ajustes que no se pudieron verificar

Quedan fuera hasta que se compruebe que hacen lo que prometen y que se pueden deshacer.

- **Animaciones de la barra de tareas (TaskbarAnimations)**: Sin evidencia de efecto en Windows 11.
- **Directiva AllowGameDVR**: Microsoft: solo rige en Windows 10 de escritorio; los valores de usuario de Game DVR ya cubren el objetivo.
- **Búsqueda en la nube (IsMSACloudSearchEnabled, IsAADCloudSearchEnabled)**: Solo fuentes de la comunidad; la de cuentas de trabajo rompe la búsqueda de OneDrive y Outlook.
- **Servicios InventorySvc y PcaSvc**: Sin guía de Microsoft para equipos cliente; el primero alimenta las actualizaciones de función.

### Pendientes de una capacidad del motor

Serían útiles, pero el motor todavía no los puede aplicar y deshacer con exactitud.

- **Efectos visuales (UserPreferencesMask)**: Es un valor binario y el catálogo todavía no acepta valores Binary.
- **Menú contextual clásico de Windows 11**: Usa el valor predeterminado de una clave, que el manejador de registro no admite; además es una preferencia.
- **Hibernación, apps de inicio, reducir la indexación, impresoras**: Necesitan una acción propia con pregunta; quedan como ideas.
