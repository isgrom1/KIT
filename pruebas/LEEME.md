# Pruebas de desarrollo

No son parte del kit y no van al USB. Corren en el PC del técnico con Windows PowerShell 5.1:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\pruebas\<prueba>.ps1
```

Todas encuentran el kit en `..\KIT` y **solo escriben en carpetas de prueba** (`X:\kitservicio_prueba`, `%TEMP%` o copias del kit). Nunca tocan carpetas reales de usuario.

| Script | Qué prueba | Resultado al cierre de la Fase E |
|---|---|---|
| `probar.ps1` | Runner: agrega BOM a los `.ps1`, revisa la sintaxis, corre `diagnostico.ps1` y muestra el resumen. `-Argumentos` se pasa al diagnóstico | — |
| `correr_admin.ps1` | Corre el diagnóstico guardando la salida; para lanzarlo con `Start-Process -Verb RunAs` (el técnico acepta el UAC) | — |
| `test_expediente.ps1` | Expedientes: IDs, ficha, atenciones, validaciones (RUT, comuna), mediciones en curso, reemplazadas e incompletas | 45/45 |
| `test_sin_antes.ps1` | Herramienta manual, **no** es una batería: `-Accion entregar` marca como entregadas (o `reabrir` reabre) las atenciones del expediente REAL de este equipo, para probar a mano que el DESPUÉS sin ANTES sale con código 4 | — |
| `test_sensores.ps1` | CSV de sensores: LibreHardwareMonitor, HWiNFO con punto y coma, coma decimal y ANSI, UTF-16, un CSV que no es de sensores y uno de ejemplo de HWiNFO en español. Si están los CSV reales de Isaac en Documentos, además los muestra | 11/11 |
| `test_smart.ps1` | Lectura de `discos.txt` (CrystalDiskInfo) por ID de atributo con un archivo de ejemplo. Si hay una medición con admin en `KIT\clientes`, además muestra sus alertas, resumen y métricas de discos | 5/5 |
| `test_archivos.ps1` | Motivo ARCHIVOS completo en `X:\kitservicio_prueba\archivos`: analizar, mover a `_PARA_BORRAR`, deshacer (y retirar la carpeta vacía del lote) | 28/28 |
| `test_faseB.ps1` | Integración de motivos: CALOR con CSV de ejemplo, LENTO solo con datos de prueba en HKCU (forzando "sin admin" donde corresponde), REVISIÓN; la parte sobre la medición real del Nitro solo corre en su PC | 23/23 |
| `test_velocidad.ps1` | Velocidad sostenida de CALOR con CSV sintéticos: frases, ruido de 10 MHz, tarjetas sin datos y flechas Sí/No. `-Conservar` deja el informe generado | 18/18 |
| `test_sincronizacion.ps1` | Sincronización: nuevos, iguales, cambios en cada lado, conflictos, liberar el USB, copia imposible, candado, otro equipo. `-Kit` y `-Base` para correrla en otra unidad | 50/50 (NTFS y exFAT) |
| `test_preinforme.ps1` | Pre-informe con datos sintéticos: sin diagnóstico, parcial, completo, siempre con el ANTES y los textos del técnico fuera de lo que se imprime. También CSV de Ryzen, tramo bajo carga y atención suelta. `-Conservar` deja la carpeta para mirar el HTML | ver la salida |
| `test_terreno.ps1` | Arreglos de atenciones reales: punto de restauración que Windows no deja crear (con reemplazos falsos de `Checkpoint-Computer` y `Get-Service`), el USB del kit entre los discos y la atención suelta del modo técnico | 19/19 |
| `test_herramientas.ps1` | Cómo se abren las herramientas: OCCT con la variable de AMD desde un `cmd`, aviso si quedó uno colgado y rutas con espacios, acentos y `&`, con programas falsos y sin elevar. `-ConUac` prueba además el paso por el UAC (el técnico lo acepta) | — |
| `test_faseG.ps1` | Versión e integridad del kit (cambiado, falta, sobra, `version.json` roto, `config_local` no cuenta), `actualizar_pendrive.ps1 -Destino` sobre un pendrive de prueba (no toca `clientes` ni `config_local`, aparta lo obsoleto, se puede repetir, se niega a copiar sobre el repo) y la franja "Siguiente" en una atención CALOR completa y en una REVISIÓN | 33/33 |
| `faseG_ventana.ps1` | Escenario para `kit.ps1 -Captura -Escenario`: atención CALOR completa siguiendo solo el botón de la franja "Siguiente", con CSV sintéticos, "Mostrar al cliente" y entregada. Correrlo desde una copia hecha con `actualizar_pendrive.ps1 -Destino X:\kitservicio_prueba\...` para ver la versión y la verificación | — |
| `correr_baterias.ps1` | Corre todas las baterías con Pester 3.4 (viene con Windows) mediante `Baterias.Tests.ps1`: una sección por batería y una prueba por cada línea OK/FALLA (OMITIDA = omitida). Deja `resultado.xml` (NUnit), `resumen.md` y la salida de cada batería en `-Salida`. `-Solo "test_a,test_b"` corre algunas. Es lo mismo que corre GitHub (`.github\workflows\pruebas.yml`) | 374/374 en el PC de Isaac |
| `_datos_ejemplo.ps1` | No es una batería: genera CSV de HWiNFO en español con las mañas del real (hora sin ceros, columnas repetidas, encabezado repetido al final) y un `discos.txt` de CrystalDiskInfo con series inventadas | — |
| `test_respaldo.ps1` | Respaldo cifrado: crear, leer de vuelta y comparar SHA-256, otra contraseña, un byte cambiado, restaurar en carpeta nueva (no sobre una con archivos), los últimos N, contraseña guardada con DPAPI y el paso al final de `sincronizar.ps1` (con y sin contraseña) | 15/15 |
| `test_faseH.ps1` | CSV de sensores encontrado solo (de hoy, el más nuevo, no los ya importados, aviso si HWiNFO sigue grabando, sacar el original solo si es idéntico; los de otro equipo no se ofrecen: equipo y CPU de la fila de grupos, Lenovo solo por CPU, fila de más de 64 KB, sin BOM, nota en `trabajo.log`), prueba fija de OCCT sobre una configuración falsa (valores, datos del último equipo, licencia intacta, `-WhatIf`, otro formato, sin archivo), PDF con Edge (1 página, sin perfil ni Edge que quede, PDF abierto), mensaje para WhatsApp (pre y final, sin serie ni contacto) y paquete de soporte (contenido y datos del cliente tapados) | 48/48 |
| `faseH_admin.ps1` | Con admin (un UAC): PDF con Edge elevado y OCCT real con la prueba fija. Copia OCCT y una configuración real (`-Config`) a `X:\kitservicio_prueba\faseH`, le cambia la prueba, lo abre como el botón, lo cierra y revisa que OCCT haya guardado la prueba fija. Deja `resultado.txt` (sin capturas de pantalla: OCCT puede abrirse detrás de lo que tengas abierto) | — |
| `vista_previa_informe.ps1` | Genera los informes con datos reales del equipo en `pruebas\vista_previa` (no toca el expediente real) | — |
| `preparar_kit_prueba.ps1` | Copia el kit a `-Destino` con datos de prueba (contacto de relleno, atención entregada y un cliente sintético) | — |
| `prueba_exfat.ps1` | Con admin: crea un disco virtual exFAT (L:), corre el diagnóstico y la sincronización desde ahí, y al terminar lo desmonta y lo borra | — |
| `limpiar_ficha_prueba.ps1` | Deja en blanco la ficha del expediente del equipo después de las pruebas | — |

## Prueba completa (Fase F)

Atenciones de punta a punta desde un "USB" de prueba: un disco virtual exFAT en K:, recorriendo la ventana con los botones reales.

| Script | Qué hace |
|---|---|
| `faseF_admin.ps1` | Con admin (un UAC): crea K:, corre solo trabajos fijos pedidos en `faseF\cola` y al final desmonta y borra el disco |
| `faseF_preparar.ps1` | Kit sin expedientes en K: (`-RestaurarClientes` para retomar), carpeta de prueba de ARCHIVOS, entrada de inicio `KitPruebaInicio` (inocua) y foto inicial del sistema |
| `faseF_e1.ps1` ... `faseF_e6.ps1` | Escenarios para `kit.ps1 -Captura <carpeta> -Escenario <archivo>`: 1 CALOR con cliente nuevo (sin admin → relanzar → con admin), 2 LENTO con cliente conocido, 3 ARCHIVOS, 4 CALOR + LENTO, 6 sincronizar y regenerar desde el maestro |
| `faseF_estado.ps1` | Foto (solo lectura) de lo que toca LENTO: inicio, GPU, hibernación, energía |
| `faseF_hashes.ps1` | SHA-256 de una carpeta y comparación (ARCHIVOS vuelve igual) |
| `faseF_limpiar.ps1` | Borra `KitPruebaInicio` y compara el sistema con la foto inicial |

La interfaz se prueba con su modo captura:

```
powershell -STA -File KIT\scripts\gui\kit.ps1 -Captura <carpeta> [-CapturaDiag] [-RutaMaestro <maestro de prueba>]
```
