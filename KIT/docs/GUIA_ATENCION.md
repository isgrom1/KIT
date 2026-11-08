# Guía de atención paso a paso

Cómo atender un equipo con el kit: desde que lo recibes hasta que lo entregas y queda archivado en tu PC. El detalle técnico de cada parte está en `LEEME.md`.

## 0. Antes de salir (en tu PC)

1. **Herramientas al día:** corre `actualizar_herramientas.ps1` (raíz del USB). Baja solo de las fuentes oficiales y verifica los hashes.
2. **Tu contacto en `KIT\scripts\config\config_local.json` → `tecnico.contacto`** (ya está tu correo). Sin él no se generan informes. Ese archivo no se sube a GitHub: cópialo al pendrive junto con el kit.
3. **OCCT y HWiNFO** van en `KIT\herramientas\OCCT` y `KIT\herramientas\HWiNFO` (la versión portable). Aparecen solos como botones en **Herramientas** y no se suben a GitHub. Hay que copiarlos a mano: el actualizador no los baja.
4. **Si vienes de atender, sincroniza primero** (punto 7).
5. **Para actualizar el kit del USB** con una versión nueva: conecta el pendrive y, en la carpeta del repositorio, corre `actualizar_pendrive.ps1` (clic derecho → Ejecutar con PowerShell, o `powershell -ExecutionPolicy Bypass -File .\actualizar_pendrive.ps1`). Busca solo el pendrive "Ventoy" (si hay otro, se lo indicas con `-Destino E:`). Copia `INICIAR.cmd`, `KIT\scripts` y `KIT\docs`, compara cada archivo por SHA-256 y deja la versión en `KIT\version.json`. **No toca `KIT\clientes` ni `KIT\herramientas`**, no pisa el `config_local.json` del pendrive y no borra nada: si un script ya no existe, lo aparta en `KIT\_obsoletos`. Debe terminar en **"Listo"**; si dice "No se completó", repítelo antes de salir.
6. **Versión del kit:** abajo a la derecha de la ventana dice la versión y el commit con que se copió, por ejemplo `Kit 0.2.0 · a1b2c3d · 2026-11-08`. Si sale una franja ámbar "Ojo: … archivos del kit no coinciden", el pendrive tiene un script dañado o cambiado: vuelve a correr `actualizar_pendrive.ps1` en tu PC. El kit sigue funcionando igual.
7. **Pendrive de repuesto:** conecta el segundo pendrive (sin el principal, o indica la letra) y corre `actualizar_pendrive.ps1 -Destino <letra>: -ConHerramientas`. Copia el kit y también `KIT\herramientas` (OCCT, HWiNFO, CrystalDiskInfo…), verificando cada archivo por SHA-256. No borra nada de lo que ya tenga. Si se te cae el principal, sigues con este.

## 1. Recepción, con el cliente presente (10-15 min)

1. Enciende el equipo del cliente, conecta el USB y abre **`KIT\INICIAR.cmd`**. Se abre la ventana del kit. La consola negra queda de respaldo: no la cierres.
2. Arriba a la derecha, si dice **Admin: no**, toca **Relanzar como admin** y acepta el aviso de Windows. Sin admin el kit funciona igual, pero no lee el SMART real de los discos, BitLocker, TPM ni el tiempo de arranque.
3. En la barra de arriba ves el equipo y su serie. Si ya vino antes, dice **Cliente conocido — última atención…**.
4. **Inicio:** marca por qué viene (puede ser más de uno): **Se calienta**, **Está lento**, **Archivos y espacio** o **Revisión completa**. Eso abre la atención de hoy.
   - Desde ahí, la **franja azul "Siguiente:"**, bajo los pasos, dice qué le falta a la atención (la ficha, el ANTES, el CSV, las condiciones, el trabajo, el DESPUÉS, los informes o la entrega) y su botón te lleva al panel. Puedes seguirla de principio a fin o moverte por los pasos a tu gusto.
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
2. Revisa las alertas: rojo = crítico, naranjo = aviso. Doble clic muestra el detalle. Lo crítico (un disco fallando, por ejemplo) conviene contárselo al cliente antes de tocar nada. Qué herramienta usar según lo que salga: "Herramientas y drivers, paso a paso", más abajo.

**Con "Se calienta", mide antes de abrir el equipo:**

1. Enchufa el equipo y déjalo **5 minutos en reposo**, hasta que la temperatura deje de bajar.
2. **Herramientas → HWiNFO**, en modo *Sensors only*, y parte el registro (el botón del documento con el "+" verde). Guarda el CSV con un nombre claro, por ejemplo `antes.csv`, en la raíz del pendrive, el Escritorio o Documentos: ahí lo busca el kit.
3. **Herramientas → OCCT**: prueba de CPU por **10 minutos**, siempre la misma: **CPU**, `0h 10min`, Mode `Normal`, Load Type `Steady`, Start at cycle `1`, Instruction Set `Auto` y Threads `Auto`. **El botón del kit la deja fijada** antes de abrir OCCT (y lo dice abajo, en Herramientas): igual revísala y sácale una foto antes de partir. La primera vez que OCCT se abre desde un pendrive todavía no hay configuración: elígela a mano y desde la siguiente queda fija. Pide permiso de administrador y la primera vez en cada equipo puede tardar un rato en abrir. Si no abre, mira "Si algo no anda".
4. Cuando OCCT termine, detén el registro de HWiNFO y **vuelve a la ventana del kit**: en **② Antes** aparece "Encontré un CSV de HWiNFO en …" con el botón **Importar este CSV**. Al importarlo te pregunta si lo saca de ahí, para no dejarlo en el equipo del cliente (solo lo saca si quedó una copia idéntica en el expediente). Si es otro archivo, usa **Importar CSV de sensores...**. Si grabó de más no hay problema: el kit calcula los promedios solo con el tramo bajo carga (CPU sobre 80 % de uso por al menos 3 minutos, con el resto en reposo). Completa las **condiciones**: enchufado, plan de energía, modo de ventiladores, superficie, temperatura ambiente, tipo de carga ("OCCT CPU") y duración (10). **Guardar condiciones**.

**Pre-informe:** al terminar el diagnóstico ANTES, el kit abre `pre_informe.html`: una hoja para el cliente con el semáforo, las temperaturas, las recomendaciones y el trabajo y precio de la ficha. Si todavía falta algo (con "Se calienta", el CSV y las condiciones), lo dice, y se vuelve a abrir cuando queda completo. **Ver pre-informe** lo abre cuando quieras. Para mandárselo:
- **PDF del pre-informe** lo imprime con Edge, sin abrir ventanas, y te muestra `pre_informe.pdf` en su carpeta, listo para arrastrarlo a WhatsApp Web o al correo.
- **Copiar mensaje** deja en el portapapeles un texto corto para WhatsApp (saludo, cómo está el equipo, la temperatura y el trabajo y precio propuestos) y te lo muestra para revisarlo.
- No le mandes el `.html`: abajo trae un detalle de las alertas para ti, que no sale en el PDF.

El DESPUÉS tiene que medirse igual: misma carga, duración y condiciones. El kit te propone las del ANTES y avisa si algo cambia, si la duración difiere más de un 20 % o si la CPU trabajó mucho menos que en el ANTES (más de un 25 % menos de velocidad: la baja de temperatura no sería una mejora real). Esos avisos son para ti: al generar los informes, el del cliente no los muestra.

## 3. Trabajo (③ Trabajo)

- **Se calienta:** desarme, limpieza, pasta o PTM, putty o pads, fotos del disipador antes y después. Marca el checklist, anota los materiales y toca **Guardar checklist**.
- **Está lento:** **Ver acciones sugeridas**. Ninguna viene marcada. Cada una dice qué hace y cómo se deshace; "admin" = necesita admin, "revisar" = consúltalo con el cliente (por ejemplo, el anti-cheat de un juego). Marca las que acordaron y toca **Aplicar seleccionadas**: antes crea un punto de restauración (con admin). Si Windows no deja crearlo (por ejemplo, un optimizador deshabilitó el servicio Instantáneas de volumen), no aplica nada y te pregunta si seguir sin él. El kit no cambia esa configuración. **Deshacer acciones aplicadas** las revierte todas.
- **Archivos:** **Analizar** busca temporales, instaladores repetidos, duplicados, fotos parecidas, logs gigantes y restos de programas. Revisa la lista y desmarca lo que no. **Mover marcados** muestra el total antes de confirmar. **Nada se borra**: todo va a `<disco>:\_PARA_BORRAR\<fecha_hora>`, con un `_DESHACER.ps1` y un LEEME. El cliente lo borra él mismo después de 30 días si no echa nada de menos. **Deshacer** devuelve todo a su lugar.
- **Revisión:** el semáforo por área (discos, batería, Windows y seguridad, espacio, temperatura) sirve para explicarle al cliente cómo está su equipo.
- Al terminar: **Marcar trabajo terminado**, que te lleva al DESPUÉS.

## 4. Diagnóstico DESPUÉS

1. **④ Después → Diagnosticar DESPUÉS**: queda en la misma atención, para comparar.
2. Con **Se calienta**: repite la medición igual que en el ANTES (5 minutos de reposo, HWiNFO grabando y la misma prueba de OCCT por 10 minutos) e importa el CSV: al volver a la ventana, **④ Después** lo ofrece igual que en el ANTES (solo los grabados después de importar el ANTES).

## 5. Informe y explicación al cliente

1. **⑤ Informe → Generar informes**. Si falta algo de la ficha, dice qué.
2. **Informe del cliente** (una página A4): semáforo, frase principal, antes → después, lo que se hizo, hasta 3 recomendaciones, garantía y próxima mantención. **Guardar PDF del cliente** deja `informe_cliente.pdf` en la carpeta de la atención y te la muestra. **Copiar mensaje para WhatsApp** prepara el texto: que está listo, el antes → después principal y la garantía. Pega el mensaje y adjunta el PDF. Si el equipo no tiene Edge, el kit lo dice: **Abrir informe del cliente → Ctrl+P → Guardar como PDF**.
3. **Informe técnico**: todo el detalle, para ti.
4. **Mostrar al cliente**: pantalla completa. Arriba, el **estado general del equipo** (las luces por área y, si hay algo en rojo o naranjo, cuáles son). Abajo, separado, el **resultado de lo que vino a hacer** (temperatura, rapidez o espacio) con las tarjetas antes → después. Así no se confunde "el equipo está en buen estado" con "la temperatura bajó". **Esc** para salir.

## 6. Entrega

**① Ficha → Marcar entregado hoy** cierra la atención y deja la garantía hasta hoy + 30 días.

## 7. De vuelta en tu PC: sincronizar

1. Conecta el USB, abre `INICIAR.cmd` y ve a **Expedientes → Sincronizar**. En consola es la opción **S**. Solo aparece en tus equipos.
2. Marca **"dejar en el USB solo las atenciones abiertas"** para liberar espacio. Del USB solo se borra lo que quedó verificado por hash en el maestro, y las fichas se quedan para reconocer a los clientes.
3. El maestro queda en `X:\kitservicio_datos\clientes`. En **Expedientes → En el maestro** abres cualquier expediente antiguo (en modo consulta, con la barra ámbar) y regeneras sus informes.
4. Si algo cambió en el USB y en el maestro a la vez, se guardan las dos versiones y te avisa: revisa el `(conflicto USB …)`.
5. **Respaldo cifrado:** al terminar de sincronizar, el kit guarda una copia cifrada del maestro en `Z:\kitservicio_respaldos` (`maestro_<fecha_hora>.kitresp`), la vuelve a leer para comprobar cada archivo y deja las últimas 10. El aviso final dice "Respaldo verificado" o por qué no se hizo.
   - **La primera vez**, crea la contraseña: en `KIT\scripts`, `powershell -ExecutionPolicy Bypass -File .\respaldar_maestro.ps1 -NuevaClave`. **Anótala en un lugar seguro**: sin ella el respaldo no se abre. Queda guardada cifrada solo para tu usuario de Windows, así que después no la pide.
   - **Para recuperar:** `respaldar_maestro.ps1 -Restaurar Z:\kitservicio_respaldos\maestro_….kitresp -En <carpeta nueva>`. Nunca escribe sobre el maestro: revisas la carpeta y reemplazas a mano. En otro PC te pide la contraseña.
   - **Ojo:** Z: es el NVMe Samsung que marca errores de integridad en el SMART. Sirve como segunda copia, pero no debería ser la única.

## Cliente que vuelve

El kit lo reconoce solo por la serie (o por el UUID o la placa, si la serie es genérica). La ficha ya trae sus datos y se abre una atención nueva. El informe compara con la visita anterior. Si esa atención ya pasó al maestro, el detalle está allá.

## Herramientas y drivers, paso a paso

Abre una herramienta solo cuando el diagnóstico o el motivo de la atención lo pidan. Varias piden permiso de administrador. Salvo HWiNFO y OCCT, estos pasos todavía no se prueban en una atención real.

**Paso 1. Lee las alertas del ANTES.** Te dicen qué revisar: discos, temperatura, espacio o drivers. No cambies drivers ni piezas antes de terminar el ANTES.

**Paso 2. Salud de los discos.**
1. Corre el diagnóstico con **admin**: el kit lee el SMART con CrystalDiskInfo y deja `discos.txt` en la medición.
2. Abre **Herramientas → CrystalDiskInfo** solo si necesitas ver más detalle. Desde el botón, el historial de los discos del cliente puede quedar guardado en el USB.
3. Si un disco sale en **Precaución** o **Malo**, detente, cuéntaselo al cliente y asegura su respaldo antes de seguir.

**Paso 3. Velocidad del disco, solo con "Está lento".**
1. Hazlo solo si el paso 2 salió bien: la prueba exige al disco y escribe archivos de prueba.
2. Abre **Herramientas → CrystalDiskMark**, elige la unidad, deja `1GiB` y toca **All**.
3. Sácale una foto al resultado y repite igual en el DESPUÉS.

**Paso 4. Temperatura, con "Se calienta".** Usa HWiNFO y OCCT como dice el punto 2.

**Paso 5. Espacio, con "Archivos y espacio".**
1. Abre **Herramientas → WinDirStat** y elige la unidad para ver qué ocupa más.
2. Abre **Herramientas → Czkawka** si necesitas buscar duplicados en una carpeta puntual.
3. Usa estas dos solo para mirar. Lo que haya que sacar va por **③ Trabajo → Archivos**, que mueve en vez de borrar y se puede deshacer.

**Paso 6. Drivers, al final.** Si vas a medir el DESPUÉS, actualízalos cuando termines de medir: así sabes que la mejora vino del trabajo.
1. Actualiza solo lo que el diagnóstico marque: driver de video genérico, driver de video de más de 12 meses o un dispositivo con error.
2. Pídele el OK al cliente.
3. Baja el driver del sitio del fabricante del notebook o del componente. **No uses actualizadores de drivers:** el kit los marca como aviso.
4. Crea un punto de restauración si el equipo lo permite, instala el driver y reinicia.
5. Comprueba que todo siga funcionando y anótalo en **Notas**, en la ficha.

**Paso 7. DDU, solo si el driver de video está dañado** y reinstalarlo encima no resultó.
1. Pídele el OK al cliente, asegura su respaldo y, si tiene BitLocker, ten la clave de recuperación a mano.
2. Baja primero el instalador del driver nuevo.
3. Desconecta internet, para que Windows Update no instale otro driver.
4. Reinicia en modo seguro y abre DDU desde `KIT\herramientas\DDU`.
5. Elige GPU y el fabricante, y toca **Clean and restart**.
6. Instala el driver nuevo, reinicia y vuelve a conectar internet.

**Para casos puntuales:**
- **LibreHardwareMonitor:** úsalo solo si HWiNFO no sirve en ese equipo. Instala el driver PawnIO, así que pide permiso al cliente. **Options → Log Sensors** guarda un CSV para importar, y el ANTES y el DESPUÉS tienen que usar la misma herramienta. Con un CSV real todavía no se prueba: solo con uno de ejemplo.
- **Rufus:** úsalo en tu PC para crear un USB de arranque, cuando una ISO no parte con Ventoy. **Borra el USB de destino: nunca elijas el pendrive del kit.**

## Si algo no anda

- **La ventana no abre:** el equipo tiene PowerShell restringido (AppLocker, WDAC o Smart App Control). INICIAR muestra el menú de consola. Si el diagnóstico dice "código 3", no puede correr en ese equipo. **Nunca desactives la seguridad del cliente.**
- **"No hay diagnóstico ANTES":** el DESPUÉS necesita un ANTES en la misma atención.
- **Cancelar:** botón de la barra de abajo. La medición anterior queda intacta.
- **Algo raro en una atención y no tienes el pendrive a mano para revisarlo:** **Modo técnico → Armar paquete de soporte** (en consola, Trabajo → Z). Deja en `KIT\soporte` un .zip chico con los registros, las alertas y el estado de todas las atenciones del equipo, sin el nombre, el contacto ni la comuna del cliente. Tráelo a tu PC para revisarlo.
- **Franja ámbar "Ojo: … archivos del kit no coinciden":** un script del pendrive no es igual al que se copió (pendrive dañado o archivo cambiado). Termina la atención si quieres, pero al volver corre `actualizar_pendrive.ps1`. Si abajo dice "copia de trabajo", el kit se copió a mano (o corre desde el repositorio) y no hay contra qué verificarlo.
- **Se cortó la luz o sacaron el USB a mitad:** lo cortado queda como `_incompleto_` y la medición anterior queda intacta.
- **Modo técnico:** diagnóstico suelto por secciones, y abrir `resumen.txt`, `trabajo.log` o el menú de consola. Si la atención en curso todavía no tiene ANTES y marcas todas las secciones, cuenta como su ANTES. Si no, pregunta antes de abrir una atención aparte, que no reemplaza a la que estás trabajando. Lo normal es medir en **② Antes**.
- **Sin admin:** el diagnóstico corre y marca qué quedó incompleto. Relanza como admin para completarlo.
- **Un informe no se abre:** en **② Antes** dice dónde quedó `pre_informe.html`: ábrelo a mano con cualquier navegador. Revisa también si se abrió en una pestaña de fondo.
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
