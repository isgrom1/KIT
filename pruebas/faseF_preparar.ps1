#Requires -Version 5.1
# Fase F — prepara la prueba en K: (el disco virtual exFAT que crea faseF_admin.ps1):
# - copia el kit a K:\KIT SIN expedientes (el equipo llega como cliente nuevo), con el contacto del técnico
#   de relleno y el maestro apuntando a X:\kitservicio_prueba\faseF\maestro (nunca al maestro real);
# - arma la carpeta de prueba de ARCHIVOS en K:\perfil_prueba (nunca carpetas reales) y guarda sus hashes;
# - crea la entrada de inicio de prueba "KitPruebaInicio" (HKCU\...\Run, apunta a un .exe que no existe)
#   para que LENTO tenga algo inocuo que desactivar; faseF_limpiar.ps1 la borra;
# - guarda la foto inicial de lo que toca LENTO (faseF_estado.ps1).
# -RestaurarClientes: para retomar una prueba pausada, copia esos expedientes a K:\KIT\clientes.
param([string]$RestaurarClientes)
$ErrorActionPreference = 'Stop'
$base = 'X:\kitservicio_prueba\faseF'
$origen = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT'
$vol = Get-Volume -DriveLetter K -ErrorAction Stop
if ($vol.FileSystemType -ne 'exFAT') { throw "K: no es exFAT ($($vol.FileSystemType))" }
if (Test-Path 'K:\KIT') { throw 'Ya existe K:\KIT' }
& robocopy.exe $origen 'K:\KIT' /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD (Join-Path $origen 'clientes') | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falló ($LASTEXITCODE)" }
if ($RestaurarClientes) {
    & robocopy.exe $RestaurarClientes 'K:\KIT\clientes' /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy de los expedientes falló ($LASTEXITCODE)" }
}
if ([IO.File]::Exists('K:\KIT\scripts\config\config_local.json')) { [IO.File]::Delete('K:\KIT\scripts\config\config_local.json') }   # contacto de relleno, no el real
$cfg = 'K:\KIT\scripts\config\config.json'
$t = [IO.File]::ReadAllText($cfg)
foreach ($par in @(@('"contacto": ""', '"contacto": "+56 9 0000 0000 (prueba)"'), @('"ruta_maestro": "X:\\kitservicio_datos\\clientes"', '"ruta_maestro": "X:\\kitservicio_prueba\\faseF\\maestro\\clientes"'))) {
    if (-not $t.Contains($par[0])) { throw "No encontré $($par[0]) en la copia de config.json" }
    $t = $t.Replace($par[0], $par[1])
}
[IO.File]::WriteAllText($cfg, $t, (New-Object Text.UTF8Encoding($false)))

# Carpeta de prueba de ARCHIVOS (mismo armado que test_archivos.ps1).
$perfil = 'K:\perfil_prueba'
$viejo = (Get-Date).AddDays(-30)
$rnd = New-Object Random 7
function New-Archivo { param([string]$Ruta, [int]$Bytes, [byte[]]$Contenido, [switch]$Reciente, [datetime]$Fecha)
    $null = New-Item -ItemType Directory -Force (Split-Path -Parent $Ruta)
    if (-not $Contenido) { $Contenido = New-Object byte[] $Bytes; $rnd.NextBytes($Contenido) }
    [IO.File]::WriteAllBytes($Ruta, $Contenido)
    if (-not $Reciente) { (Get-Item -LiteralPath $Ruta).LastWriteTime = $(if ($Fecha) { $Fecha } else { $viejo }) }
    , $Contenido }
Add-Type -AssemblyName System.Drawing
function New-Foto { param([string]$Ruta, [int]$Ruido)
    $null = New-Item -ItemType Directory -Force (Split-Path -Parent $Ruta)
    $bmp = New-Object Drawing.Bitmap 200, 200
    for ($x = 0; $x -lt 200; $x += 4) { for ($y = 0; $y -lt 200; $y += 4) { $v = [int][math]::Min(255, $x + $rnd.Next(0, $Ruido + 1)); $c = [Drawing.Color]::FromArgb($v, [int]($y * 1.2) % 256, 128); for ($i = 0; $i -lt 4; $i++) { for ($j = 0; $j -lt 4; $j++) { $bmp.SetPixel($x + $i, $y + $j, $c) } } } }
    $bmp.Save($Ruta, [Drawing.Imaging.ImageFormat]::Jpeg); $bmp.Dispose(); (Get-Item $Ruta).LastWriteTime = $viejo }
$pdf = New-Archivo "$perfil\Documents\informe.pdf" 2MB
$null = New-Archivo "$perfil\Downloads\informe (1).pdf" 0 $pdf
$null = New-Archivo "$perfil\Desktop\informe.pdf" 0 $pdf
$null = New-Archivo "$perfil\Downloads\informe_reciente.pdf" 0 $pdf -Reciente
$zip = New-Archivo "$perfil\Downloads\fotos.zip" 3MB
$null = New-Archivo "$perfil\Downloads\fotos (1).zip" 0 $zip
$tes = New-Archivo "$perfil\Documents\Tesis\capitulo1.docx" 1500KB
$null = New-Archivo "$perfil\Downloads\capitulo1.docx" 0 $tes
$cla = New-Archivo "$perfil\Documents\clave_banco.txt" 1200KB
$null = New-Archivo "$perfil\Downloads\clave_banco (1).txt" 0 $cla
$sav = New-Archivo "$perfil\Saved Games\Juego\save1.dat" 1100KB
$null = New-Archivo "$perfil\Downloads\save1 (1).dat" 0 $sav
$null = New-Archivo "$perfil\Downloads\ChromeSetup.exe" 1500KB -Fecha (Get-Date).AddDays(-40)
$null = New-Archivo "$perfil\Downloads\ChromeSetup (1).exe" 1500KB -Fecha (Get-Date).AddDays(-20)
$null = New-Archivo "$perfil\Downloads\ChromeSetup (2).exe" 1500KB -Fecha (Get-Date).AddDays(-10)
$null = New-Archivo "$perfil\Documents\~`$carta.docx" 162
$null = New-Archivo "$perfil\AppData\Local\Temp\viejo.tmp" 4KB
$null = New-Archivo "$perfil\AppData\Local\Temp\nuevo.tmp" 4KB -Reciente
$null = New-Archivo "$perfil\AppData\Local\Temp\scoped_dir123_456\a.txt" 2KB
(Get-Item "$perfil\AppData\Local\Temp\scoped_dir123_456").LastWriteTime = $viejo
$null = New-Archivo "$perfil\AppData\Local\NVIDIA\DXCache\x.bin" 8KB
New-Foto "$perfil\Pictures\Terreno\IMG_001.jpg" 3
New-Foto "$perfil\Pictures\Terreno\IMG_002.jpg" 6
$null = New-Item -ItemType Directory -Force "$perfil\Videos", "$perfil\Music"
& (Join-Path $PSScriptRoot 'faseF_hashes.ps1') -Carpeta $perfil -Salida (Join-Path $base 'perfil_antes.json') | Out-Null

# Entrada de inicio de prueba (inocua: el .exe no existe).
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if ((Get-ItemProperty -Path $run -ErrorAction SilentlyContinue).KitPruebaInicio) { throw 'Ya existe la entrada de prueba KitPruebaInicio' }
New-ItemProperty -Path $run -Name 'KitPruebaInicio' -Value '"C:\kit_prueba_no_existe\app.exe" --fase-f' -PropertyType String | Out-Null

& (Join-Path $PSScriptRoot 'faseF_estado.ps1') -Salida (Join-Path $base 'estado_inicial.json') | Out-Null
"Listo: K:\KIT ($([math]::Round((Get-ChildItem 'K:\KIT' -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)) MB), $(@(Get-ChildItem $perfil -Recurse -File).Count) archivos de prueba, entrada KitPruebaInicio creada."
