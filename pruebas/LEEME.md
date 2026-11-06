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
| `test_sensores.ps1` | CSV de sensores HWiNFO (español e inglés) y LibreHardwareMonitor; usa CSV reales de `Documentos` y sintéticos | — |
| `test_smart.ps1` | Alertas, resumen y métricas desde `discos.txt` de CrystalDiskInfo (usa la última medición con admin del equipo) | — |
| `test_archivos.ps1` | Motivo ARCHIVOS completo en `X:\kitservicio_prueba\archivos`: analizar, mover a `_PARA_BORRAR`, deshacer (y retirar la carpeta vacía del lote) | 28/28 |
| `test_faseB.ps1` | Integración de motivos (CALOR, LENTO solo con datos de prueba en HKCU, REVISIÓN) | 23/23 |
| `test_velocidad.ps1` | Velocidad sostenida de CALOR con CSV sintéticos: frases, ruido de 10 MHz, tarjetas sin datos y flechas Sí/No. `-Conservar` deja el informe generado | 18/18 |
| `test_sincronizacion.ps1` | Sincronización: nuevos, iguales, cambios en cada lado, conflictos, liberar el USB, copia imposible, candado, otro equipo. `-Kit` y `-Base` para correrla en otra unidad | 50/50 (NTFS y exFAT) |
| `test_herramientas.ps1` | Cómo se abren las herramientas: OCCT con la variable de AMD desde un `cmd`, aviso si quedó uno colgado y rutas con espacios, acentos y `&`, con programas falsos y sin elevar. `-ConUac` prueba además el paso por el UAC (el técnico lo acepta) | — |
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
