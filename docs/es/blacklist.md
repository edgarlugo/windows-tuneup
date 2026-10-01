# Lista negra

English version: [../en/blacklist.md](../en/blacklist.md).

Estos cambios **no se aplican nunca**: no están en ningún perfil ni se pueden pedir con `-Include`, y `-Force` no los habilita. La skill de Claude tampoco los propone aunque se los pidan; explica por qué no. Las pruebas del catálogo (`tests/CatalogQuality.Tests.ps1`, bloque "Blacklist guard") fallan si un ajuste del catálogo toca alguno de los servicios, valores de registro, tareas o apps de esta lista.

Lo que se evaluó y quedó fuera por otros motivos (apps que no se pueden reinstalar, ajustes sin verificar, límites del motor) está al final de [catalog.md](catalog.md#no-incluido).

## Seguridad

| Cambio | Por qué no |
|---|---|
| Apagar Microsoft Defender, su protección en tiempo real o la protección en la nube (`DisableAntiSpyware`, `DisableRealtimeMonitoring`, `Set-MpPreference -SubmitSamplesConsent 2`) | Deja el equipo expuesto y la ganancia de rendimiento es mínima. Para carpetas de código, Microsoft recomienda un Dev Drive, no exclusiones. |
| Apagar SmartScreen (`EnableSmartScreen`, `SmartScreenEnabled`) | Es la defensa contra descargas y sitios maliciosos conocidos. |
| Apagar el Control de cuentas de usuario (`EnableLUA`, `ConsentPromptBehaviorAdmin`) | Todo programa correría con permisos de administrador sin preguntar. |
| Apagar el firewall (`EnableFirewall`, servicio `mpssvc`, `BFE`) | Deja abiertos los puertos de todos los servicios a la red. |
| Apagar las mitigaciones de CPU para Spectre y Meltdown (`FeatureSettingsOverride`) | Riesgo de seguridad real a cambio de poco rendimiento. |
| Apagar la integridad de memoria (VBS/HVCI) **por defecto** | Solo existe como ajuste de riesgo alto, `gaming.memory-integrity-off`, que ningún perfil incluye y que se aplica únicamente si se pide por nombre. Apagar VBS completo no existe. |
| Apagar Seguridad de Windows, `webthreatdefsvc` o `webthreatdefusersvc` | Son la interfaz de Defender y la protección contra robo de credenciales. |
| Cambiar las directivas de ejecución de PowerShell | Es un ajuste de seguridad del equipo. |

## Actualizaciones y recuperación

| Cambio | Por qué no |
|---|---|
| Desactivar Windows Update por completo (servicios `wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `BITS`; `NoAutoUpdate`, `DisableWindowsUpdateAccess`; tareas de `WindowsUpdate`, `UpdateOrchestrator` y `WaaSMedic`) | Sin parches de seguridad. Como mucho se evita que reinicie solo o se retrasan las actualizaciones de funciones. |
| Bloquear dominios de Microsoft en `hosts` o en el firewall | Rompe Windows Update, la Store y la activación. |
| Desactivar o borrar WinRE (`C:\Recovery`, tareas de `RecoveryEnvironment`) | Sin recuperación local ante un arranque roto. |
| Desactivar Restaurar sistema o sus tareas (`SystemRestore`, servicios `VSS` y `swprv`) | Además de la protección del usuario, el propio motor crea un punto de restauración antes de los cambios de sistema. |
| `DISM /ResetBase` por defecto | Impide desinstalar actualizaciones problemáticas. |
| Borrar los registros de CBS y DISM | Se necesitan para diagnosticar reparaciones (`-Health`). |
| Desactivar las tareas `Chkdsk`, `Defrag`, `Servicing\StartComponentCleanup` o `Registry\RegIdleBackup`, o la tarea `DiskDiagnosticResolver` | Salud del disco y del sistema: TRIM en SSD, avisos de fallos SMART, limpieza del almacén de componentes. |
| Quitar la Microsoft Store o App Installer (winget) | Deshacer cualquier app depende de ellos. Quitar la Store sería, como mucho, una opción aparte con advertencia; hoy no existe. |

## Memoria, disco y datos

| Cambio | Por qué no |
|---|---|
| Quitar el archivo de paginación (`PagingFiles`) | Cuelgues por falta de memoria y sin volcados de error. |
| Limpiadores de registro | Sin beneficio medible; riesgo de romper programas. |
| Borrar carpetas del usuario (por ejemplo `%UserProfile%\OneDrive`) | Pérdida de datos. Desinstalar OneDrive (`apps.onedrive`) nunca borra archivos y se niega si hay carpetas movidas a OneDrive o archivos solo en la nube. |
| Encender el Sensor de almacenamiento | Borra archivos de la papelera y de Descargas sin preguntar. |
| Quitar apps que guardan datos del usuario dentro de la app (Notas rápidas, Journal, Whiteboard, OneNote) | Quitar la app borra esas notas. |

## "Optimizaciones" que son placebo

| Cambio | Por qué no |
|---|---|
| Agrupar procesos de svchost (`SvcHostSplitThresholdInKB`) | Solo baja el número visible de procesos y quita el aislamiento entre servicios. |
| Ajustes de red (`NetworkThrottlingIndex`, `SystemResponsiveness`, autotuning de TCP, `TcpAckFrequency`, `TCPNoDelay`, algoritmo de Nagle) | Sin efecto demostrable en equipos modernos; la mayoría de los juegos en tiempo real usan UDP. |
| Forzar HPET (`bcdedit /set useplatformclock`) | Windows no lo usa salvo que se fuerce, y forzarlo suele empeorar la latencia. Además toca la configuración de arranque. |
| Resolución del temporizador, `Win32PrioritySeparation`, prioridades de MMCSS | Valores ya óptimos o ignorados; desde Windows 10 2004 la resolución es por proceso. |
| Estado mínimo del procesador al 100 %, plan "Máximo rendimiento" (`powercfg -duplicatescheme e9a42b02...`) | En CPU modernas no mejora los FPS, sube temperatura y consumo; el plan nuevo no se puede deshacer limpio. |
| Desactivar las optimizaciones de pantalla completa | Suele perder latencia y el overlay; solo ayuda en casos concretos. |
| `NtfsDisable8dot3NameCreation`, `NtfsDisableLastAccessUpdate` | Mejora marginal y puede romper instaladores antiguos. |

## Servicios que no se tocan

| Servicio | Por qué no |
|---|---|
| `SharedAccess` (Conexión compartida a Internet) | Sostiene la NAT de WSL2, el conmutador Default Switch de Hyper-V, Docker Desktop y el punto de acceso móvil. |
| `vmcompute`, `vmms`, `hns`, `HvHost`, `LxssManager`, `WslService` | Virtualización, WSL, Hyper-V y contenedores (el perfil Desarrollo los conserva). |
| `LanmanServer`, `LanmanWorkstation` | Microsoft: "no deshabilitar"; compartir archivos, IPC$ y administración remota. |
| `WerSvc`, `DPS`, `WdiServiceHost`, `WdiSystemHost` | Manejo de bloqueos, solucionadores y diagnósticos. Apagar el envío de informes (`privacy.error-reporting-off`) no toca el servicio. |
| `RmSvc` | Radio y modo avión: sin él no se controlan Wi-Fi ni Bluetooth desde Configuración. |
| `WpnService` | Notificaciones y mosaicos. |
| `SysMain`, `WSearch` | La especificación conserva SysMain (ayuda en discos mecánicos); sin WSearch la búsqueda de Inicio y del Explorador deja de encontrar archivos. |
| `XblGameSave`, `XblAuthManager`, `XboxNetApiSvc` | Ya vienen en manual y Windows los inicia cuando hacen falta; deshabilitarlos rompe el inicio de sesión de Xbox y de los juegos de Game Pass. |
| `Spooler` | Sin él no se imprime; solo tendría sentido con detección de impresoras. |
| `EventLog`, `Schedule`, `Winmgmt`, `RpcSs`, `CryptSvc`, `sppsvc`, `AppIDSvc`, `TrustedInstaller` | Infraestructura de Windows: registros, tareas, WMI, RPC, certificados, activación, AppLocker y servicing. |

## Edge

| Cambio | Por qué no |
|---|---|
| Quitar Microsoft Edge o WebView2 | Rompe Widgets, la ayuda y muchas apps que muestran contenido web, y deja el equipo sin navegador soportado. |
