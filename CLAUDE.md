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
| **F** | **Prueba completa** | **en curso (pausada 2026-11-02 03:5x): pruebas 1 y 2 OK; faltan 3 (ARCHIVOS), 4 (CALOR+LENTO, que además verifica los arreglos de GPU y "Mostrar al cliente") y 6 (sincronizar). Banco: `pruebas\faseF_*.ps1`; respaldo de los expedientes de prueba en `X:\kitservicio_prueba\faseF\respaldo_K`** |

**Fase F (especificación de Isaac):** simular atenciones completas con el kit copiado a otra letra.
- **CALOR**, cliente nuevo.
- **LENTO**, cliente conocido, con aplicar y deshacer.
- **ARCHIVOS**, sobre una carpeta de prueba creada para eso (**nunca** sobre carpetas reales de Isaac).
- **CALOR + LENTO** combinado.
- Sin admin, con admin, y relanzar como admin a mitad de la atención.
- Sincronizar al maestro.
- Entregables: tabla de resultados, capturas y los dos informes.

**Pendientes conocidos:**
- `tecnico.contacto` vacío en `config.json`: sin él no se generan informes. Lo tiene que dar Isaac.
- Falta el CSV del DESPUÉS de CALOR (59/71 °C); el ANTES es `reg.CSV` (91/100 °C).
- Probar en el USB Ventoy real (exFAT ya se probó con un disco virtual).
- Las acciones reales de LENTO y el punto de restauración, con admin (para la Fase F).

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

- `pruebas\` tiene las baterías: `test_expediente.ps1` (45), `test_faseB.ps1` (20), `test_archivos.ps1`, `test_sensores.ps1`, `test_smart.ps1`, `test_sincronizacion.ps1` (50) y otras. Ver `pruebas\LEEME.md`.
- La interfaz tiene modo captura: `powershell -STA -File KIT\scripts\gui\kit.ps1 -Captura <carpeta> [-CapturaDiag] [-RutaMaestro <maestro de prueba>]` recorre los paneles y guarda un PNG de cada uno.
- PSScriptAnalyzer:

```powershell
$s = @{ IncludeDefaultRules = $true; Rules = @{
  PSUseCompatibleSyntax  = @{ Enable = $true; TargetVersions = @('5.1') }
  PSUseCompatibleCmdlets = @{ compatibility = @('desktop-5.1.14393.206-windows') }
  PSUseCompatibleTypes   = @{ Enable = $true; TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework') } } }
Invoke-ScriptAnalyzer -Path .\KIT -Recurse -Settings $s
```
