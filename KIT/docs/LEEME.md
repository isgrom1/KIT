# KIT SERVICIO

Herramienta portable para diagnosticar notebooks y PC con Windows 10/11 desde un pendrive Ventoy.
Corre con el Windows PowerShell 5.1 que trae Windows: no instala nada en el equipo del cliente y no usa internet.

**¿Primera vez?** Lee `GUIA_ATENCION.md`: una atención completa, paso a paso, de la recepción a la entrega.

## Estructura

```
<raíz del USB>\
├─ actualizar_herramientas.ps1   se corre en TU equipo, nunca en el del cliente
└─ KIT\
   ├─ INICIAR.cmd                abre la ventana; menú de consola de respaldo
   ├─ scripts\
   │  ├─ diagnostico.ps1         orquestador
   │  ├─ ficha.ps1               ficha del cliente por consola
   │  ├─ trabajo.ps1             trabajo según el motivo, por consola
   │  ├─ sincronizar.ps1         copia los expedientes al maestro de tu PC
   │  ├─ motivos\                calor.ps1, lento.ps1, archivos.ps1, revision.ps1
   │  ├─ gui\                    principal.xaml, kit.ps1 (ventana) y tarea.ps1 (trabajos en segundo plano)
   │  ├─ herramientas.ps1        menú de herramientas portables
   │  ├─ secciones\              01_equipo.ps1 … 13_estabilidad.ps1
   │  ├─ lib\                    Comun, Log, Privacidad, Salidas, Alertas, Expediente, Sincronizacion...
   │  └─ config\                 config.json, software_conocido.json, ciclo_vida_windows.json
   ├─ herramientas\              una carpeta por herramienta + versiones.json
   ├─ clientes\                  un expediente por equipo (ver "Expedientes")
   └─ docs\                     LEEME.md (esto) y GUIA_ATENCION.md (una atención paso a paso)
```

## Expedientes

Cada equipo tiene un expediente, y cada vez que viene es una atención:

```
clientes\<fabricante>_<modelo>_<serie>\      (serie genérica → <fabricante>_<modelo>_<GUID corto>)
  ficha.json            cliente, equipo y atenciones (ficha.json.bak = versión anterior)
  fotos_recepcion\      fotos del equipo al recibirlo (cópialas aquí)
  AAAA-MM-DD_atencion\  (si ese día ya hubo otra: _2, _3...)
    antes\              diagnóstico antes del trabajo
    despues\            diagnóstico después del trabajo
    trabajo.log         una línea por medición, cambio de ficha y acción
```

- **El equipo se reconoce solo** por la serie del BIOS. Si la serie es genérica ("To be filled by O.E.M."), por el UUID o la serie de la placa guardados en la ficha.
- **Diagnóstico ANTES**: va a la atención de hoy si existe y todavía no tiene "después". Si no hay, abre una nueva.
- **Diagnóstico DESPUÉS**: va a la atención abierta más reciente que tenga "antes". **No existe "después" sin "antes"**: si no hay, no crea nada y sale con código 4.
- **Una atención se cierra** al marcarla entregada en la ficha. La garantía queda por defecto hasta la entrega + 30 días (`expediente.garantia_dias`).
- **Repetir una medición** (por ejemplo, al relanzar como admin) no borra la anterior: queda como `antes_reemplazado_HHMMSS`. Si la anterior se hizo con admin y la nueva no, el kit avisa.
- **Si una medición se corta** (se cerró la ventana, se cortó la luz), la anterior queda intacta: se escribe en `antes_en_curso\` y recién al terminar bien pasa a `antes\`. Lo cortado queda como `antes_incompleto_HHMMSS`.
- Las carpetas de la fase 0 (`clientes\AAAA-MM-DD_HHMM_...`) se migran solas al expediente la primera vez que corre el diagnóstico o la ficha.

### Ficha del cliente (opción 3 de INICIAR)

Pregunta los datos de la atención abierta. Enter deja el valor actual y `-` lo borra.

- **Cliente:** nombre*, contacto* (WhatsApp o correo) y comuna. Nada de RUT ni dirección: si se escribe un RUT o una comuna con números, la ficha lo rechaza.
- **Atención:** motivos* (CALOR, LENTO, ARCHIVOS, REVISION; se pueden escribir como letras: `CL`), síntoma* (en palabras del cliente), estado físico, respaldo, clave de BitLocker confirmada, checklist funcional, paquete* y precio*.
- **Con motivo ARCHIVOS** también son obligatorios el consentimiento (solo leer, mover o borrar aprobado) y las carpetas protegidas.
- Los datos del equipo y las mediciones los llena el diagnóstico.
- El nombre y contacto del técnico van en `config.json` (`tecnico`).

(* = obligatorio para generar informes. El diagnóstico y la ficha avisan qué falta.)

### Trabajo según el motivo (opción 4 de INICIAR)

Solo aparece lo de los motivos marcados en la ficha. Nada se aplica sin confirmar.

- **CALOR**
  - *Condiciones de medición*, antes y después: enchufado, plan, ventiladores, superficie, °C ambiente, tipo y duración de la carga. El DESPUÉS propone las del ANTES.
  - *Importar el CSV* de HWiNFO (inglés o español) o LibreHardwareMonitor. Queda como `sensores.csv` + `sensores_resumen.json` en `antes\` o `despues\`, con:
    - media, p95 y máximo de cada métrica;
    - % del tiempo con throttling y minutos sobre 90 °C;
    - "pierde velocidad por calor", diciendo de dónde lo saca.
  - Lo que el CSV no tenga queda vacío: nunca se inventa. Los patrones de columnas están en `config\sensores.json`.
  - *Checklist físico*: desarme, limpieza, pasta/PTM, putty/pads, fotos del disipador y materiales.
  - *Métricas*: temperatura promedio y máxima de CPU y GPU, y si pierde velocidad por calor. Avisa si las mediciones duran más de un 20 % distinto o si cambiaron las condiciones.
- **LENTO**
  - *Acciones sugeridas* a partir del diagnóstico ANTES. Cada una dice qué hace y cómo se deshace; las marcadas [revisar] son utilidades del fabricante o anti-trampas, y las [manual] son recomendaciones. Las acciones posibles:
    - desactivar elementos de inicio, igual que el Administrador de tareas;
    - pasar a Manual los servicios y desactivar las tareas de software detectado como optimizador, PUP o bloat;
    - cambiar el plan de un optimizador por Equilibrado;
    - devolver el turbo o el estado máximo de la CPU al 100 %;
    - desactivar la hibernación, solo si falta espacio;
    - poner la GPU de alto rendimiento en las apps forzadas a la de ahorro.
  - *Punto de restauración* antes de la primera acción. Necesita admin; sin admin solo se sigue si el técnico lo decide.
  - El valor anterior exacto de cada cambio queda en `lento_acciones.json` y en `trabajo.log`; *Deshacer* lo restaura.
  - Nunca toca Defender, Seguridad de Windows, el antivirus, Smart App Control ni VBS.
- **ARCHIVOS**: exige el consentimiento y las carpetas protegidas en la ficha.
  - *Analizar* deja `archivos\reporte.csv` para revisar. Busca:
    - Temp viejo y carpetas `scoped_dir` de Chrome;
    - instaladores repetidos en Descargas;
    - logs gigantes y cachés de juegos;
    - archivos `~$` de Office;
    - duplicados (tamaño → hash parcial → MD5 completo antes de mover).
  - De los duplicados se conserva la copia en Imágenes/Documentos y se aparta la de Descargas o la "(1)".
  - *Solo se informan*: los posibles restos de desinstalaciones y las fotos parecidas.
  - *Nunca toca*: lo modificado en los últimos 7 días, partidas guardadas, archivos con credenciales, el Escritorio ni las carpetas protegidas.
  - *Mover* lleva lo marcado a `<unidad>:\_PARA_BORRAR\<fecha_hora>` en el mismo disco, con `_DESHACER.ps1` y `LEEME.txt` para el cliente. **Nunca borra.**
- **REVISION**: semáforo por área (temperatura si hay CSV, discos, batería, Windows y seguridad, rendimiento, espacio) con el motivo de cada color.

- **I) Generar informes**: crea en la carpeta de la atención:
  - `informe_cliente.html`: 1 página A4, en lenguaje simple, con:
    - semáforo y una frase;
    - tarjetas antes → después con flecha verde o roja;
    - qué se hizo (máximo 5) y recomendaciones (máximo 3);
    - próxima mantención, garantía y, con ARCHIVOS, dónde quedó lo apartado.
  - `informe_tecnico.html`, con todo el detalle:
    - todas las métricas y el gráfico de temperatura (antes y después superpuestos);
    - condiciones de medición, alertas, discos y batería;
    - acciones con su deshacer, advertencias y enlaces a los CSV.

  Son autocontenidos (sin internet) y se imprimen a PDF desde el navegador (Ctrl+P, "Guardar como PDF"). Solo se generan con la ficha completa; si falta algo, dice qué. Garantía, próxima mantención y días para borrar lo apartado se ajustan en `config.json` → `expediente`.

Con admin, el diagnóstico también lee el SMART de `discos.txt` (CrystalDiskInfo). Así detecta errores de medio, sectores dañados, desgaste y temperatura reales aunque Windows no los reciba.

## Preparar el USB (en tu equipo)

1. Copia la carpeta del kit a la partición de datos del Ventoy (la grande, en exFAT). Corre desde cualquier letra: todas las rutas salen de la carpeta del kit y los expedientes no guardan rutas del USB.
2. Si bajaste el kit como .zip, desbloquéalo antes de descomprimir (ver "Mark of the Web").
3. Actualiza las herramientas:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\actualizar_herramientas.ps1
   ```
   - Solo corre si tu equipo está en `equipos_tecnico` de `KIT\scripts\config\config.json` (o con `-Forzar`).
   - `-SoloRevisar` compara versiones sin descargar; `-Reinstalar` baja todo de nuevo; `-Solo Rufus,WinDirStat` procesa solo esas.
   - Baja solo de las fuentes oficiales, verifica el hash cuando el sitio lo publica, desbloquea lo descargado y anota versión, fecha, hash y licencia en `KIT\herramientas\versiones.json`.

## Sincronizar con el maestro (en tu equipo)

El USB lleva las atenciones en curso; el historial completo vive en el **maestro** de tu PC (`config.json` → `sincronizacion.ruta_maestro`, por defecto `X:\kitservicio_datos\clientes`). **Sincronizar** solo aparece en los equipos de `equipos_tecnico`: en la ventana (Expedientes → Sincronizar) y en el menú de consola (opción **S**).

- **Copia del USB al maestro, nunca al revés, y nunca pisa:** lo nuevo se copia; lo idéntico (mismo SHA-256) se salta. Cada copia se verifica por hash antes de darla por buena.
- **Si un archivo cambió**, el kit sabe quién lo cambió (guarda el hash que dejó la sincronización anterior):
  - solo en el USB (p. ej. la ficha con una atención nueva): se actualiza el maestro y su versión anterior queda en `_sincronizacion\anteriores\<fecha>\`;
  - solo en el maestro (p. ej. un informe regenerado allá): se deja el del maestro;
  - en los dos: **conflicto**. El del maestro no se toca, el del USB queda al lado como `nombre (conflicto USB <fecha>).ext` y se avisa.
- **Dejar en el USB solo las atenciones abiertas** (casilla en la ventana; en consola lo pregunta): después de copiar, cada atención **entregada** se borra del USB solo si **cada archivo** tiene una copia idéntica en el maestro (hash recalculado en los dos lados). Si uno solo no llegó, la atención queda entera en el USB. La ficha se queda en el USB para seguir reconociendo al cliente; las fotos de recepción salen cuando el expediente ya no tiene atenciones abiertas.
- Las mediciones en curso (`*_en_curso`) no se copian: se copian cuando terminan.
- **Log de cada sincronización** en `<maestro>\_sincronizacion\logs\`, con copia en `KIT\clientes\_sincronizacion\logs\`.
- Desde el maestro, Expedientes → "En el maestro" abre cualquier expediente y regenera sus informes.

## Interfaz gráfica

`INICIAR.cmd` abre la ventana del kit (WPF, sin instalar nada). La ventana de consola queda abierta de respaldo.

- **Barra superior:**
  - equipo, serie, "Admin: sí/no" y **Relanzar como admin**, que conserva el expediente y la atención;
  - cliente activo y, si el equipo ya vino antes, "Cliente conocido — última atención…".
- **Inicio:** "¿Por qué viene el equipo?" con 4 tarjetas, en las que se puede marcar más de una. Debajo va el avance ① Ficha ② Antes ③ Trabajo ④ Después ⑤ Informe: cada paso se habilita al completar el anterior y lleva ✓ cuando está hecho.
- **Por motivo:** cada paso muestra solo lo de los motivos elegidos.
- **Ficha:** obligatorios marcados con *, checklist funcional y **Agregar fotos de recepción** (se copian a `fotos_recepcion\`).
- **Antes / Después:**
  - **Diagnosticar** muestra el progreso por sección y el registro en vivo;
  - las alertas van en colores (doble clic = detalle);
  - con CALOR: importar el CSV de sensores y las condiciones de medición (el Después propone las del Antes).
- **Trabajo:**
  - checklist físico (CALOR);
  - acciones sugeridas con casillas y "Aplicar seleccionadas" (LENTO);
  - Analizar → revisar (desmarcar lo que no se mueve) → Mover, con el total antes de confirmar, y Deshacer (ARCHIVOS);
  - semáforo (REVISIÓN).
- **Informe:** vista previa de ambos informes, Generar, Abrir y Abrir carpeta.
- **Mostrar al cliente:** pantalla completa con el semáforo y las tarjetas antes → después del motivo principal. Esc para salir.
- **Expedientes:** lista los expedientes del USB (o del maestro, en tus equipos) con buscador; se elige la atención y **Abrir**. El de otro equipo, o cualquiera del maestro, se abre en **modo consulta** (barra ámbar): no se mide ni se aplican acciones, pero se puede completar la ficha y **regenerar los informes**. **Volver a este equipo** regresa al flujo normal. En tus equipos, abajo está **Sincronizar** (ver "Sincronizar con el maestro").
- **Modo técnico:** diagnóstico suelto por secciones (en una atención aparte), atajos y menú de consola.
- **Herramientas:** un botón por herramienta; las que faltan aparecen en gris.

Los trabajos largos corren en segundo plano: la ventana no se congela y la barra de abajo tiene **Cancelar**. Si se cancela un diagnóstico, la medición anterior queda intacta.

Si PowerShell está restringido (AppLocker, WDAC, Smart App Control) o WPF no carga, INICIAR lo explica y usa el menú de consola. Para ir directo al menú de consola: `INICIAR.cmd consola`.

## Uso en el equipo del cliente (menú de consola)

1. Abre `KIT\INICIAR.cmd consola` (o deja que caiga solo al menú si la interfaz no abre).
2. Si dice `Admin: NO`, conviene la opción **A** (relanzar como administrador). Sin admin quedan incompletos:
   - el SMART de los discos y `discos.txt`;
   - BitLocker y TPM;
   - la clave OEM y `hypervisorlaunchtype`;
   - las tareas protegidas y el tiempo de arranque.

   El diagnóstico igual corre y marca qué faltó.
3. **3) Ficha del cliente**: datos del cliente y de la atención. Se puede llenar antes o después del diagnóstico.
4. **1) Diagnóstico ANTES** del trabajo. Pregunta si incluir el recorrido de carpetas (hasta 3 min más; sin él tarda unos 15-20 s) y si abrir `resumen.txt` al terminar.
5. Haces el trabajo.
6. **2) Diagnóstico DESPUÉS** del trabajo, en la misma atención.
7. En la ficha, marca la atención como entregada.

El diagnóstico **solo lee**: no cambia registro, servicios, planes de energía ni archivos del cliente. Lo único que escribe es la carpeta de la atención dentro del USB.
Lo que Windows hace solo al abrir PowerShell (Prefetch, registros de eventos, `%LOCALAPPDATA%\Microsoft\Windows\PowerShell\StartupProfileData-NonInteractive`) no lo controla el kit.

### Lo que queda en cada medición (`antes\` o `despues\`)

| Archivo | Contenido |
|---|---|
| `resumen.txt` | Para leer: alertas ordenadas por severidad, tiempos y detalle por sección |
| `diagnostico.json` | Todo lo medido (fechas `yyyy-MM-dd HH:mm:ss`) |
| `metricas.json` | Los números que comparan "antes" y "después": arranque, RAM y CPU, programas al inicio, espacio libre, discos, batería |
| `csv\NN_*.csv` | Una tabla por archivo, con `;` y UTF-8 con BOM (Excel en español) |
| `log.txt` | Paso a paso, con el tiempo de cada sección |
| `bateria.html` / `bateria.xml` | `powercfg /batteryreport` |
| `discos.txt` | Informe de CrystalDiskInfo, que lee el SMART aunque Windows no lo reciba (Intel RST/VMD). Solo con admin y si CrystalDiskInfo está en `herramientas\`. Se corre una copia temporal dentro de la medición, para que el historial SMART de los discos de cada cliente no quede en el USB. |

### Parámetros de `diagnostico.ps1`

```
powershell -NoProfile -ExecutionPolicy Bypass -File KIT\scripts\diagnostico.ps1 [-Momento Antes|Despues] [-NuevaAtencion] [-AbrirResumen] [-SinEspacio] [-TiempoMaxEspacio 300] [-Secciones 2,4,7]
```

`-NuevaAtencion` abre otra atención aunque hoy ya haya una abierta.

| Código de salida | Significado |
|---|---|
| 0 | Terminó (aunque alguna sección haya fallado: queda en "ERRORES" del resumen) |
| 1 | No se pudieron escribir los resultados |
| 2 | Parámetros inválidos, faltan archivos del kit o no se pudo crear la carpeta (¿USB de solo lectura o BitLocker To Go bloqueado?) |
| 3 | PowerShell en modo restringido (AppLocker, WDAC o Smart App Control): el kit no puede correr en ese equipo |
| 4 | Diagnóstico DESPUÉS sin un ANTES abierto: no se creó nada |

## Privacidad

- Clave de producto: de la instalada, solo los 5 caracteres que Windows ya muestra. De la OEM del firmware, si existe y sus últimos 5 caracteres; la clave completa nunca se escribe.
- El número de serie va completo en el JSON, el resumen y el nombre del expediente (para garantías).
- Ficha del cliente: solo nombre, contacto y comuna. Nada de RUT ni dirección exacta. La ficha no se enmascara, porque el nombre del cliente podría coincidir con el usuario de Windows. Las únicas rutas que guarda son las carpetas protegidas que anotes.
- Los perfiles de usuario quedan como `C:\Users\<U1>` (`enmascarar_perfiles` en config.json).
- Nunca se guardan contraseñas, historial, cookies, redes Wi-Fi, líneas de comando de procesos ni contenido de archivos. Nombres de archivo, solo de los mayores a 1 GB y de los logs mayores a 500 MB.

## Mark of the Web, Unblock-File y por qué igual corre

**Qué es.** Cuando bajas un archivo, Windows le pega una marca invisible: un flujo alternativo NTFS llamado `Zone.Identifier` con `ZoneId=3` (Internet). Si descomprimes un .zip marcado con el Explorador, todo lo de adentro hereda la marca. Con la marca:
- PowerShell con política `RemoteSigned` se niega a correr scripts sin firma.
- SmartScreen muestra "Windows protegió su PC" al abrir un .exe.
- Office abre los documentos en vista protegida.

**Cómo se quita.** En tu equipo, antes de copiar al USB:
```
Get-ChildItem -Recurse .\KIT | Unblock-File
```
Si bajaste el kit como .zip, desbloquea el .zip (`Unblock-File .\kit.zip` o Propiedades → Desbloquear) antes de descomprimir. `actualizar_herramientas.ps1` ya desbloquea lo que baja.

**Por qué exFAT la pierde.** La marca vive en un flujo alternativo, y eso solo existe en NTFS. La partición de datos de Ventoy es exFAT por defecto, así que al copiar al USB la marca se pierde sola. Si formateas el USB en NTFS, la marca viaja con los archivos.

**Qué hace `-ExecutionPolicy Bypass`.** INICIAR.cmd abre PowerShell con esa opción solo para ese proceso: así no importa la política del equipo ni la marca de los .ps1. No cambia nada en el equipo del cliente.

**Lo que `-ExecutionPolicy Bypass` NO salta:**
- **Política de ejecución por GPO** (MachinePolicy/UserPolicy, típico en equipos de empresa): manda sobre la línea de comandos. El diagnóstico la informa en Seguridad.
- **AppLocker o WDAC con reglas para scripts**: PowerShell queda en modo restringido (ConstrainedLanguage) y el kit se detiene con código 3.
- **Smart App Control** (Windows 11): puede bloquear los .exe portables sin firma reconocida y, como es una política de WDAC, también puede restringir PowerShell.
- **El antivirus**: puede marcar herramientas como DDU o Czkawka por reputación.

En el equipo del cliente **nunca** desactives Defender, Smart App Control, VBS ni ninguna protección para que corra el kit. Si algo se bloquea, se informa y se sigue con lo que sí funciona.

## Herramientas

| Herramienta | Fuente | Hash verificado | Licencia |
|---|---|---|---|
| CrystalDiskInfo | crystalmark.info → SourceForge del autor | MD5 (SourceForge) | MIT |
| CrystalDiskMark | crystalmark.info → SourceForge del autor | MD5 (SourceForge) | MIT |
| LibreHardwareMonitor | GitHub del proyecto | SHA-256 (GitHub) | MPL-2.0 |
| Czkawka (interfaz GTK) | GitHub del proyecto | SHA-256 (GitHub) | MIT |
| WinDirStat | GitHub del proyecto | SHA-256 (GitHub y lista del proyecto) | GPL-3.0 |
| Rufus (portable) | GitHub del proyecto | SHA-256 (GitHub) | GPL-3.0 |
| DDU | wagnardsoft.com, **a mano** | no publica | Freeware; la página no publica términos de uso comercial |

Notas:
- **DDU** no se baja solo: el enlace real está detrás de una verificación anti-bots. El actualizador te avisa la versión vigente; bájalo desde https://www.wagnardsoft.com/display-driver-uninstaller-ddu y descomprímelo en `KIT\herramientas\DDU\`.
- **LibreHardwareMonitor** usa el driver PawnIO para leer sensores, y ese driver se instala en el equipo: pide permiso al cliente.
- **CrystalDiskInfo** lee el SMART también detrás de Intel RST/VMD, donde Windows no lo entrega (el diagnóstico lo avisa).
- **CrystalDiskMark** escribe archivos de prueba en el disco que mide.
- **Herramientas agregadas a mano**: crea `KIT\herramientas\<nombre>\` con el programa adentro. Aparece en el menú y queda en `versiones.json` la próxima vez que corras el actualizador.
- **HWiNFO64, OCCT y WizTree**: su versión gratuita es solo para uso personal. En el servicio técnico úsalas solo si tienes licencia comercial. El menú las marca en amarillo.

## Configuración

- `config.json`: umbrales de las alertas, límite de tiempo del recorrido (`espacio.tiempo_max_seg`, 180 s), profundidad del top de carpetas (3), enmascarado de perfiles, `equipos_tecnico` y la carpeta maestra (`sincronizacion.ruta_maestro`).
- `software_conocido.json`: optimizadores, actualizadores de drivers, activadores, PUP y bloatware que se detectan. Es una lista de expresiones regulares: agrega lo que vayas encontrando.
- `ciclo_vida_windows.json`: fechas de fin de soporte por versión y edición (fuente: Microsoft Learn, "Windows release information"). Revísalas cada cierto tiempo.

## Problemas comunes

- **La ventana se cierra al tiro**: abre `cmd`, entra a la carpeta del kit y corre `INICIAR.cmd` para ver el mensaje.
- **"No se pudo crear la carpeta del cliente"**: el USB está protegido contra escritura o tiene BitLocker To Go sin desbloquear.
- **Secciones INCOMPLETA**: faltó admin. Relanza con la opción A.
- **SMART "no confiable"**: el controlador (Intel RST/VMD en modo RAID) no le pasa los datos a Windows. Usa CrystalDiskInfo.
