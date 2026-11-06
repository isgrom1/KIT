# KIT SERVICIO — instrucciones para Claude

Isaac hace servicio técnico de notebooks y PC en Santiago de Chile. Este repo es su kit portable (pendrive Ventoy) para diagnosticar y atender equipos Windows 10/11 de clientes **sin instalar nada**.

- **Habla con Isaac en español chileno informal.**
- La raíz del repo es la raíz del USB: `actualizar_herramientas.ps1` + `KIT\`. `pruebas\` no va al USB.
- Manual: `KIT/docs/LEEME.md`. Atención paso a paso: `KIT/docs/GUIA_ATENCION.md`.

## Cómo se trabaja

- Se avanza **por fases**. Al cerrar cada una se informa: **resumen, archivos creados o cambiados, cómo lo probaste, qué quedó pendiente**. Después se **espera el OK de Isaac** antes de la siguiente.
- Todo se prueba en su equipo (Acer Nitro AN515-57, Windows 11) y se muestra la salida real. No se inventan datos: si falta algo (un CSV, un contacto), se dice.
- Las pruebas con admin necesitan que Isaac acepte el UAC: se lanzan con `Start-Process -Verb RunAs` y se le avisa antes.

### Sesiones en la nube (desde el celular)

Las sesiones en la nube corren en Linux: **no pueden correr Windows PowerShell 5.1, WPF ni las pruebas**.
- Ahí se puede leer, planificar, editar código y documentación, y revisar.
- Lo que haya que probar queda anotado para la próxima sesión en el PC de Isaac. **No digas que algo está probado si no corrió en Windows.**
- Guarda los `.ps1` en UTF-8 **con BOM** y CRLF (`.gitattributes` fija el CRLF; el BOM hay que conservarlo).
- `INICIAR.cmd` queda en ASCII puro y CRLF.

En el PC (`X:\kitservicio`): `git pull` antes de trabajar; al terminar, commit y push.

## Estado

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Motor de diagnóstico (13 secciones), `INICIAR.cmd`, `actualizar_herramientas.ps1` | entregada 2026-11-01 |
| A | Expedientes por equipo y atención (`lib\Expediente.ps1`, `ficha.ps1`) | entregada |
| B | Motivos CALOR, LENTO, ARCHIVOS, REVISION (`motivos\`, `trabajo.ps1`) | entregada |
| C | Informes HTML cliente y técnico (`lib\Informe.ps1`) | entregada |
| D | Interfaz WPF (`gui\kit.ps1`, `principal.xaml`, `tarea.ps1`) | entregada |
| E | Portabilidad (cualquier letra, exFAT) y sincronización al maestro (`lib\Sincronizacion.ps1`, `sincronizar.ps1`, panel Expedientes, modo consulta) | entregada 2026-11-01 |
| F | Prueba completa: 6 pruebas de punta a punta desde un "USB" exFAT de prueba (banco en `pruebas\faseF_*.ps1`) | cerrada 2026-11-02 (OK de Isaac) |

**Las 7 fases del prompt maestro están cerradas.** Lo que venga ahora son mejoras o arreglos que pida Isaac: cada cambio se prueba en su PC (baterías de `pruebas\` y PSScriptAnalyzer en 0) antes de darlo por hecho.

**Fase F (especificación de Isaac):** simular atenciones completas con el kit copiado a otra letra.
- **CALOR**, cliente nuevo.
- **LENTO**, cliente conocido, con aplicar y deshacer.
- **ARCHIVOS**, sobre una carpeta de prueba creada para eso (**nunca** sobre carpetas reales de Isaac).
- **CALOR + LENTO** combinado.
- Sin admin, con admin, y relanzar como admin a mitad de la atención.
- Sincronizar al maestro.
- Entregables: tabla de resultados, capturas y los dos informes.

**Pendientes conocidos:**
- El contacto del técnico vive en `KIT\scripts\config\config_local.json`, que está en `.gitignore`: solo existe en el PC de Isaac y en su pendrive. En una sesión en la nube ese archivo no existe y los informes piden el contacto; es lo esperado. **Nunca escribas su contacto en `config.json` ni en otro archivo del repo.**
- CALOR se mide con OCCT (CPU, 10 minutos) y HWiNFO grabando: la elección de esas herramientas ya la decidió Isaac. Van a mano en `KIT\herramientas` (fuera del repo). Falta una atención real con este método, antes y después, porque su Nitro ya tiene la pasta cambiada.
- El USB Ventoy real ya está armado y probado desde Windows (Kingston de 58 GB, 2026-11-05: ventana, diagnóstico con y sin admin, informes y consola). Falta arrancar una ISO desde él, si Isaac agrega ISOs.
- OCCT en notebooks AMD + NVIDIA: se caía en `vulkan-1.dll` sin mostrar ventana (`vkGetPhysicalDeviceProperties2: Invalid physicalDevice`). Confirmado a mano en un equipo con Vega 8 y GTX 1650: abre con `DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1=1` desde un `cmd` con admin; las variables `VK_LOADER_*` no hicieron efecto con admin. El botón del kit lo hace con `Start-Herramienta`. Falta probar el botón con UAC (`pruebas\test_herramientas.ps1 -ConUac`) y desde el pendrive en un equipo con este problema.
- Crear un punto de restauración NUEVO no se ejercitó: en la Fase F Windows ya tenía uno de las últimas 24 h y el kit lo reutilizó.

## Reglas duras del kit

- **Solo Windows PowerShell 5.1.** Cero módulos externos en el kit y cero instalaciones en el equipo del cliente. PSScriptAnalyzer solo en el PC de Isaac, en **0 hallazgos**, incluidas las reglas de compatibilidad 5.1.
- **Rutas:** todas salen de `$PSScriptRoot` o `%~dp0`. Nada de letras fijas: el kit corre desde cualquier letra y en exFAT.
- **Codificación:** `.ps1` y salidas de texto en UTF-8 con BOM. CSV con `;` y BOM. JSON sin BOM.
- **No parsear texto traducido:** powercfg por GUID, `Win32_PerfRawData`, Windows 11 por build ≥ 22000.
- El motor (`diagnostico.ps1`, `secciones\`, `lib\`) está separado de la interfaz (`gui\`).
- **El diagnóstico SOLO LEE:** no modifica registro, servicios, planes ni archivos del cliente; solo escribe dentro del expediente en el USB.
  - Sin red.
  - Sin `Add-Type` con código fuente (compila en `%TEMP%`); `Add-Type -AssemblyName` sí.
  - Sin `Get-AuthenticodeSignature`.
- **Sin admin funciona** y dice qué quedó incompleto; con admin completa todo. Cada sección va en su propio try/catch.
- **Seguridad del cliente:** detecta ConstrainedLanguage, AppLocker, WDAC y Smart App Control, y **nunca la desactiva**.
- **Privacidad:**
  - Del producto: solo PartialProductKey. Clave OEM: últimos 5 caracteres, nunca en logs.
  - La serie va completa en el JSON, el resumen y el ID del expediente.
  - Perfiles de usuario enmascarados como `<U1>`.
  - Nunca líneas de comando, historial, cookies, wifi, contraseñas ni contenido de archivos.
  - Ficha del cliente: solo nombre, contacto y comuna, **nada de RUT ni dirección exacta**.
- **ARCHIVOS NUNCA BORRA:** mueve a `<disco>:\_PARA_BORRAR\<fecha_hora>` con `_DESHACER.ps1`. Las pruebas, solo en carpetas creadas para eso (`X:\kitservicio_prueba`).
- **LENTO:** ninguna acción viene marcada; todas con deshacer y con punto de restauración (admin).
- **Repo público:** nunca subir `KIT\clientes`, herramientas de terceros, capturas o PDFs con datos de equipos, series ni datos personales (ver `.gitignore`).

## Trampas de PowerShell 5.1 que ya mordieron

- En llamadas a métodos, la coma separa argumentos: `WriteLine(('fmt {0}' -f $a, $b))` lleva doble paréntesis.
- `"$var:"` es un error: se escribe `"${var}:"`. Comillas escapadas `""` dentro de `$()` en un string con comillas dobles no parsean.
- La coma pesa más que `-or` en arreglos. `& $sb -or $x` le pasa `-or` como argumento.
- Las variables no distinguen mayúsculas: `$pasos` pisó a `$script:Pasos`.
- Indexar `$null` es un error.
- Una función que devuelve `,$arr` rompe el pipeline: emite los elementos y quien llama envuelve con `@()`.
- `[ordered]@{}` indexado con un entero toma la **posición**, no la clave.
- `-File` pasa los arreglos como un solo texto. `Select-Object -First` en un pipeline mata el proceso hijo.
- Verbos New/Set/Remove/Update/Start/Stop/Reset/Restart necesitan `SupportsShouldProcess` (PSScriptAnalyzer). Sustantivos en español: suprimir `PSUseSingularNouns`.

## Cómo probar (en el PC de Isaac)

- `pruebas\` tiene las baterías: `test_expediente.ps1` (45), `test_faseB.ps1` (23), `test_velocidad.ps1` (18), `test_archivos.ps1`, `test_sensores.ps1`, `test_smart.ps1`, `test_sincronizacion.ps1` (50), `test_herramientas.ps1` (22), `test_preinforme.ps1` (32) y otras. Ver `pruebas\LEEME.md`.
- La interfaz tiene modo captura: `powershell -STA -File KIT\scripts\gui\kit.ps1 -Captura <carpeta> [-CapturaDiag] [-RutaMaestro <maestro de prueba>] [-Escenario <archivo de pasos>]` recorre los paneles (o los pasos del escenario, con los botones reales) y guarda un PNG de cada uno.
- La ventana guarda el expediente en memoria y los trabajos largos corren en otro proceso que también escribe `ficha.json`: **antes de guardar desde la ventana hay que releer** (`Initialize-AtencionGui`), o se pisa lo que escribió el otro proceso (bug encontrado en la Fase F).
- PSScriptAnalyzer:

```powershell
$s = @{ IncludeDefaultRules = $true; Rules = @{
  PSUseCompatibleSyntax  = @{ Enable = $true; TargetVersions = @('5.1') }
  PSUseCompatibleCmdlets = @{ compatibility = @('desktop-5.1.14393.206-windows') }
  PSUseCompatibleTypes   = @{ Enable = $true; TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework') } } }
Invoke-ScriptAnalyzer -Path .\KIT -Recurse -Settings $s
```
