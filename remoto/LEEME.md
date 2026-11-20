# Diagnóstico remoto (herramienta aparte del kit)

Para mandarle a un familiar o cliente: con doble clic revisa su computador, hace la prueba CALOR
(HWiNFO grabando + OCCT cargando la CPU) y deja en su Escritorio (o en `%USERPROFILE%\Diagnostico_para_Isaac`
si el Escritorio se respalda en OneDrive) un archivo `.kitdiag` cifrado que
solo Isaac puede abrir. No instala nada ni cambia la configuración de Windows.

## Una sola vez, en el PC de Isaac

```powershell
powershell -ExecutionPolicy Bypass -File .\remoto\crear_llaves.ps1
```

- La llave pública queda en `remoto\llave_publica.xml` (va dentro de cada paquete).
- La privada queda en `%LOCALAPPDATA%\kitservicio\remoto_llave_privada.dat`, protegida con DPAPI:
  solo la abre este usuario en este PC. Si se pierde (Windows reinstalado), los `.kitdiag` ya no se abren.

## Armar el paquete para mandar

```powershell
powershell -ExecutionPolicy Bypass -File .\remoto\armar_paquete.ps1
```

Deja `remoto\_salida\Diagnostico_remoto_<fecha>.zip` (~190 MB, con OCCT y HWiNFO). Usa las herramientas
de `KIT\herramientas` (o `-Herramientas D:\KIT\herramientas`). `remoto\_salida` no va a GitHub.

## Lo más fácil: arrastrar y soltar

- **`remoto\ABRIR_KITDIAG.cmd`**: arrastra encima el `.kitdiag` que te mandaron (diagnóstico o trabajo).
  Lo abre en `X:\kitservicio_datos\remotos\<nombre>` (con una copia del `.kitdiag`), nunca en el pendrive ni en Descargas,`r`n  y abre el PDF para el cliente y tu hoja técnica. Si ya lo abriste, crea `<nombre>_2`.
- **`remoto\ARMAR_TRABAJO.cmd`**: arrastra encima esa carpeta. Elige las acciones con números y deja el
  paquete en `remoto\_salida\Trabajo_<equipo>_<fecha>.zip` para mandárselo al cliente.

## Para enviar: una carpeta por pack

```powershell
powershell -ExecutionPolicy Bypass -File .\remoto\armar_envios.ps1
```

Arma `remoto\_salida\Para_enviar\` con una carpeta por pack del catálogo (`KIT\scripts\config\config.json`,
`paquetes`): `QUE_HACE.txt` para el cliente (qué hace, qué NO hace, cuánto demora y cuesta), `MENSAJE_WHATSAPP.txt`
listo para pegar, el ZIP del diagnóstico donde corresponde (enlazado, sin copiar 200 MB) y `PASOS_ISAAC.txt` en los
packs con un paso tuyo. `LEEME_ISAAC.txt` dice qué mandar según lo que pida el cliente. Los precios salen de
`config_local.json` (`precios`): cámbialos ahí y vuelve a correrlo.

## Abrir lo que te mandan

```powershell
powershell -ExecutionPolicy Bypass -File .\remoto\abrir_diagnostico.ps1 -Archivo "<ruta>\Diagnostico_para_Isaac_....kitdiag"
```

Lo extrae al lado del archivo, en una carpeta con el mismo nombre: `RESUMEN.txt`, el expediente del
diagnóstico (como el del kit), `calor\sensores_calor.csv` y los logs. Además arma el **informe para el
cliente** (`Informe_<marca>_<modelo>_<fecha>.pdf` + `.html`, con `KIT\scripts\lib\InformeVisual.ps1`) y lo abre:
puntaje de salud, áreas con semáforo, curva de temperatura con el ventilador, espacio, RAM, arranques,
batería, seguridad, estabilidad y recomendaciones en un mapa impacto/esfuerzo. `-Cliente "<nombre>"` pone
el nombre en la portada; `-SinInforme` no lo arma. El PDF lleva tu contacto de `config_local.json`.
El kit del pendrive puede usar la misma librería (`Export-InformeVisual -Origen kit`) con el
`diagnostico.json` de una atención; falta ponerle un botón en la ventana.

## Trabajo remoto (aplicar LENTO a distancia)

Después de abrir un diagnóstico remoto:

```powershell
powershell -ExecutionPolicy Bypass -File .\remoto\armar_trabajo.ps1 -Carpeta "<carpeta que dejó abrir_diagnostico>"
```

- Muestra las acciones de LENTO de ese equipo (ninguna marcada) y eliges con números. `-PermitirSinPunto`
  deja aplicar si Windows no puede crear el punto de restauración (por defecto no aplica nada).
- Deja `remoto\_salida\Trabajo_<equipo>_<fecha>.zip` (unos pocos MB, sin OCCT ni HWiNFO) con `TRABAJO.cmd`,
  `DESHACER.cmd`, `LEEME.txt`, el motor y `plan\plan.json` **firmado con tu llave** (RSA-3072, SHA-256),
  amarrado a la serie del equipo y con vencimiento (`-DiasVigencia`, 7 por defecto).
- En el equipo del cliente, `TRABAJO.cmd`:
  1. Revisa la firma, que sea el mismo equipo y que no esté vencido **antes de pedir admin**: si algo no calza, no toca nada.
  2. Muestra los cambios y pide escribir SI. Punto de restauración, aplica con el motor de LENTO (guarda cada
     valor anterior) y deja todo en `%USERPROFILE%\Diagnostico_para_Isaac\Trabajo_<id>` con `DESHACER.cmd`.
  3. Pide reiniciar. Al volver a abrirlo espera 5 min desde el encendido, mide el DESPUÉS y deja
     `Trabajo_para_Isaac_<PC>_<fecha>.kitdiag` cifrado (en el Escritorio o, si se respalda en OneDrive, en
     `%USERPROFILE%\Diagnostico_para_Isaac`).
- Ese `.kitdiag` se abre con `abrir_diagnostico.ps1` como siempre: sale el **informe del trabajo** (página
  "Lo que hicimos y cómo cambió": tarjetas y barras antes/después, lo hecho en palabras del cliente).

Lo que la firma protege y lo que no: impide que alguien cambie el plan en el camino o lo use en otro equipo;
no impide que alguien reemplace el paquete entero (eso requiere certificado de firma de código, descartado).
El motor solo conoce acciones de LENTO: nunca antivirus, Seguridad de Windows ni archivos del cliente.

## Qué hace en el equipo del familiar (`motor\remoto.ps1`)

1. Diagnóstico del kit (solo lectura, sin red) en una carpeta temporal.
2. CALOR (`motor\calor.ps1`): HWiNFO graba, 5 min de reposo, 10 min de OCCT en STABILITY TEST. Si
   HWiNFO avisa por el sensor del Embedded Controller (Acer Nitro AMD), aprieta "No controle este sensor".
   Aprieta START, espera el diálogo "Enjoying OCCT?" de la versión gratis y aprieta Start.
3. `RESUMEN.txt`, ZIP en memoria, cifrado (AES-256 + HMAC-SHA256, llaves con RSA-3072 OAEP).
4. Borra la carpeta temporal: en el equipo solo queda el `.kitdiag`.

Para probar más corto: `DIAGNOSTICO.cmd -Minutos 1 -ReposoMin 0.5 -Destino <carpeta>`.

## Excepción a las reglas del kit

`motor\calor.ps1` usa `Add-Type -MemberDefinition` (P/Invoke a `user32!PostMessage`) para apretar el
botón de grabar de HWiNFO, que no se puede apretar de otra forma. Eso compila código en `%TEMP%` y
el kit no lo permite. Por eso vive aquí, fuera de `KIT\`.
