# KIT SERVICIO

Kit portable para diagnosticar y hacer servicio a notebooks y PC con Windows 10/11 desde un pendrive Ventoy, sin instalar nada en el equipo del cliente. Corre con el Windows PowerShell 5.1 que trae Windows y tiene ventana propia (WPF), con menú de consola de respaldo.

- **Cómo se usa una atención, paso a paso:** [KIT/docs/GUIA_ATENCION.md](KIT/docs/GUIA_ATENCION.md)
- **Manual completo:** [KIT/docs/LEEME.md](KIT/docs/LEEME.md)
- **Reglas del proyecto y estado de las fases** (también para las sesiones de Claude): [CLAUDE.md](CLAUDE.md)

## Qué hace

- Diagnóstico de solo lectura en 13 secciones (hardware, SMART, Windows, seguridad, energía, software, arranque, espacio, estabilidad…), con y sin admin.
- Expediente por equipo y atención: ficha del cliente, mediciones ANTES y DESPUÉS, `trabajo.log`.
- Trabajo por motivo: **CALOR** (sensores bajo carga), **LENTO** (acciones con deshacer y punto de restauración), **ARCHIVOS** (nunca borra: mueve a `_PARA_BORRAR`), **REVISIÓN** (semáforo).
- Informe para el cliente (una página A4) e informe técnico, en HTML.
- Sincronización con el maestro del técnico, sin pisar nada y verificada por hash.

## Estructura

```
actualizar_herramientas.ps1   baja las herramientas portables (solo en el PC del técnico)
KIT\                          lo que va al USB (INICIAR.cmd, scripts, docs)
pruebas\                      pruebas de desarrollo (no van al USB)
```

Los expedientes de clientes (`KIT\clientes`) y las herramientas de terceros (`KIT\herramientas`) **no** se suben a este repositorio.
