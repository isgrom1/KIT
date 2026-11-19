# Diagnóstico remoto (herramienta aparte del kit)

Para mandarle a un familiar o cliente: con doble clic revisa su computador, hace la prueba CALOR
(HWiNFO grabando + OCCT cargando la CPU) y deja en su Escritorio un archivo `.kitdiag` cifrado que
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
