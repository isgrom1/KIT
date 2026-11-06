# Guía de atención paso a paso

Cómo atender un equipo con el kit: desde que lo recibes hasta que lo entregas y queda archivado en tu PC. El detalle técnico de cada parte está en `LEEME.md`.

## 0. Antes de salir (en tu PC)

1. **Herramientas al día:** corre `actualizar_herramientas.ps1` (raíz del USB). Baja solo de las fuentes oficiales y verifica los hashes.
2. **Tu contacto en `KIT\scripts\config\config_local.json` → `tecnico.contacto`** (ya está tu correo). Sin él no se generan informes. Ese archivo no se sube a GitHub: cópialo al pendrive junto con el kit.
3. **OCCT y HWiNFO** van en `KIT\herramientas\OCCT` y `KIT\herramientas\HWiNFO` (la versión portable). Aparecen solos como botones en **Herramientas** y no se suben a GitHub. Hay que copiarlos a mano: el actualizador no los baja.
4. **Si vienes de atender, sincroniza primero** (punto 7).
5. **Para actualizar el kit del USB** con una versión nueva, copia encima `INICIAR.cmd`, `KIT\scripts` y `KIT\docs`. **No borres `KIT\clientes` del USB**: ahí están las atenciones abiertas.

## 1. Recepción, con el cliente presente (10-15 min)

1. Enciende el equipo del cliente, conecta el USB y abre **`KIT\INICIAR.cmd`**. Se abre la ventana del kit. La consola negra queda de respaldo: no la cierres.
2. Arriba a la derecha, si dice **Admin: no**, toca **Relanzar como admin** y acepta el aviso de Windows. Sin admin el kit funciona igual, pero no lee el SMART real de los discos, BitLocker, TPM ni el tiempo de arranque.
3. En la barra de arriba ves el equipo y su serie. Si ya vino antes, dice **Cliente conocido — última atención…**.
4. **Inicio:** marca por qué viene (puede ser más de uno): **Se calienta**, **Está lento**, **Archivos y espacio** o **Revisión completa**. Eso abre la atención de hoy.
5. **① Ficha**, delante del cliente:
   - nombre, contacto (WhatsApp o correo) y comuna. **Nada de RUT ni dirección**: la ficha los rechaza;
   - síntoma, con sus palabras, y estado físico (golpes, piezas sueltas, bisagras);
   - si tiene respaldo de sus archivos y si confirmó la clave de recuperación de BitLocker;
   - **checklist funcional**: prueba cada cosa con él (enciende, pantalla, teclado, touchpad, USB, carga, batería, wifi, audio, cámara);
   - paquete y precio;
   - con **Archivos**: consentimiento (solo leer, mover o "borrar aprobado", que igual solo mueve) y **carpetas protegidas**, que nunca se tocan;
   - **Guardar ficha**. Si falta algo obligatorio, lo dice.
6. **Agregar fotos de recepción**: fotos del estado físico; se copian al expediente.

## 2. Diagnóstico ANTES (1-4 min)

1. **② Antes → Diagnosticar ANTES**. Tarda 15-20 segundos. Con **recorrido de carpetas** son hasta 3 minutos más: úsalo con Archivos o si el disco está lleno.
2. Revisa las alertas: rojo = crítico, naranjo = aviso. Doble clic muestra el detalle. Lo crítico (un disco fallando, por ejemplo) conviene contárselo al cliente antes de tocar nada.

**Con "Se calienta", mide antes de abrir el equipo:**

1. Enchufa el equipo y déjalo **5 minutos en reposo**, hasta que la temperatura deje de bajar.
2. **Herramientas → HWiNFO**, en modo *Sensors only*, y parte el registro (el botón del documento con el "+" verde). Guarda el CSV con un nombre claro, por ejemplo `antes.csv`.
3. **Herramientas → OCCT**: prueba de CPU por **10 minutos**, siempre con la misma configuración. Pide permiso de administrador y la primera vez en cada equipo puede tardar un rato en abrir. Si no abre, mira "Si algo no anda".
4. Cuando OCCT termine, detén el registro de HWiNFO, toca **Importar CSV de sensores** y completa las **condiciones**: enchufado, plan de energía, modo de ventiladores, superficie, temperatura ambiente, tipo de carga ("OCCT CPU") y duración (10). **Guardar condiciones**.

El DESPUÉS tiene que medirse igual: misma carga, duración y condiciones. El kit te propone las del ANTES y avisa si algo cambia, si la duración difiere más de un 20 % o si la CPU trabajó mucho menos que en el ANTES (más de un 25 % menos de velocidad: la baja de temperatura no sería una mejora real). Esos avisos son para ti: al generar los informes, el del cliente no los muestra.

## 3. Trabajo (③ Trabajo)

- **Se calienta:** desarme, limpieza, pasta o PTM, putty o pads, fotos del disipador antes y después. Marca el checklist, anota los materiales y toca **Guardar checklist**.
- **Está lento:** **Ver acciones sugeridas**. Ninguna viene marcada. Cada una dice qué hace y cómo se deshace; "admin" = necesita admin, "revisar" = consúltalo con el cliente (por ejemplo, el anti-cheat de un juego). Marca las que acordaron y toca **Aplicar seleccionadas**: antes crea un punto de restauración (con admin). **Deshacer acciones aplicadas** las revierte todas.
- **Archivos:** **Analizar** busca temporales, instaladores repetidos, duplicados, fotos parecidas, logs gigantes y restos de programas. Revisa la lista y desmarca lo que no. **Mover marcados** muestra el total antes de confirmar. **Nada se borra**: todo va a `<disco>:\_PARA_BORRAR\<fecha_hora>`, con un `_DESHACER.ps1` y un LEEME. El cliente lo borra él mismo después de 30 días si no echa nada de menos. **Deshacer** devuelve todo a su lugar.
- **Revisión:** el semáforo por área (discos, batería, Windows y seguridad, espacio, temperatura) sirve para explicarle al cliente cómo está su equipo.
- Al terminar: **Marcar trabajo terminado**, que te lleva al DESPUÉS.

## 4. Diagnóstico DESPUÉS

1. **④ Después → Diagnosticar DESPUÉS**: queda en la misma atención, para comparar.
2. Con **Se calienta**: repite la medición igual que en el ANTES (5 minutos de reposo, HWiNFO grabando y la misma prueba de OCCT por 10 minutos) e importa el CSV.

## 5. Informe y explicación al cliente

1. **⑤ Informe → Generar informes**. Si falta algo de la ficha, dice qué.
2. **Informe del cliente** (una página A4): semáforo, frase principal, antes → después, lo que se hizo, hasta 3 recomendaciones, garantía y próxima mantención. **Abrir informe del cliente → Ctrl+P → Guardar como PDF**, y se lo mandas por WhatsApp o correo.
3. **Informe técnico**: todo el detalle, para ti.
4. **Mostrar al cliente**: pantalla completa con el semáforo y las tarjetas antes → después. **Esc** para salir.

## 6. Entrega

**① Ficha → Marcar entregado hoy** cierra la atención y deja la garantía hasta hoy + 30 días.

## 7. De vuelta en tu PC: sincronizar

1. Conecta el USB, abre `INICIAR.cmd` y ve a **Expedientes → Sincronizar**. En consola es la opción **S**. Solo aparece en tus equipos.
2. Marca **"dejar en el USB solo las atenciones abiertas"** para liberar espacio. Del USB solo se borra lo que quedó verificado por hash en el maestro, y las fichas se quedan para reconocer a los clientes.
3. El maestro queda en `X:\kitservicio_datos\clientes`. En **Expedientes → En el maestro** abres cualquier expediente antiguo (en modo consulta, con la barra ámbar) y regeneras sus informes.
4. Si algo cambió en el USB y en el maestro a la vez, se guardan las dos versiones y te avisa: revisa el `(conflicto USB …)`.

## Cliente que vuelve

El kit lo reconoce solo por la serie (o por el UUID o la placa, si la serie es genérica). La ficha ya trae sus datos y se abre una atención nueva. El informe compara con la visita anterior. Si esa atención ya pasó al maestro, el detalle está allá.

## Si algo no anda

- **La ventana no abre:** el equipo tiene PowerShell restringido (AppLocker, WDAC o Smart App Control). INICIAR muestra el menú de consola. Si el diagnóstico dice "código 3", no puede correr en ese equipo. **Nunca desactives la seguridad del cliente.**
- **"No hay diagnóstico ANTES":** el DESPUÉS necesita un ANTES en la misma atención.
- **Cancelar:** botón de la barra de abajo. La medición anterior queda intacta.
- **Se cortó la luz o sacaron el USB a mitad:** lo cortado queda como `_incompleto_` y la medición anterior queda intacta.
- **Modo técnico:** diagnóstico suelto por secciones (en una atención aparte), y abrir `resumen.txt`, `trabajo.log` o el menú de consola.
- **Sin admin:** el diagnóstico corre y marca qué quedó incompleto. Relanza como admin para completarlo.
- **OCCT no abre** (no sale la ventana, o en el Administrador de tareas aparece "Suspendido"):
  1. Ábrelo con **Herramientas → OCCT**, no con doble clic: el botón apaga la capa antigua de AMD solo para OCCT. Pasó en un notebook con AMD Vega 8 y GTX 1650. Desinstalar el antivirus no lo arregló, así que no se lo saques al cliente.
  2. Si el kit avisa que ya está corriendo y no ves la ventana, quedó colgado: ciérralo en el Administrador de tareas (`OCCT` y `OCCTGUI`) y prueba de nuevo.
  3. Para ver el motivo: **Visor de eventos → Registros de Windows → Aplicación**, el error de `OCCTGUI.exe` y su "módulo con errores". Con `vulkan-1.dll` es este caso. Si es otro, revisa si hay un `CrashReport-*.log` en `%TEMP%\OCCT`.
  4. A mano, en un `cmd` con admin: `set DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1=1` y corre `OCCT.exe` desde esa misma ventana. Las variables `VK_LOADER_...` no hicieron efecto con admin.

## Tiempos de referencia (aproximados)

| Paso | Tiempo |
|---|---|
| Recepción y ficha | 10-15 min |
| Diagnóstico ANTES o DESPUÉS | 20 s (con recorrido de carpetas: hasta 3 min más) |
| Medición de temperatura (Se calienta) | 15 min (5 de reposo y 10 de OCCT), dos veces |
| Acciones de Está lento | 10-20 min |
| Análisis de Archivos | 1-5 min, más tu revisión |
| Informes | 1-2 min |
