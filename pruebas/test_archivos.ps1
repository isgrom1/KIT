# Prueba de desarrollo del motivo ARCHIVOS, SOLO sobre una carpeta de prueba creada aquí
# (X:\kitservicio_prueba). Nunca toca carpetas reales de Isaac. Al final borra todo lo de prueba.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'motivos\archivos.ps1')
Initialize-Contexto -RaizScripts $scripts
$script:Ctx.Config.espacio.log_grande_mb = 1      # en la prueba, "log gigante" = 1 MB
$script:Ctx.Config.archivos.restos_min_mb = 1
# En el PC de Isaac, X:\kitservicio_prueba; donde no hay X: (GitHub), C:\kitprueba. Nunca bajo Temp: ARCHIVOS lo trata distinto.
$base = if (Test-Path 'X:\') { 'X:\kitservicio_prueba\archivos' } else { Join-Path $env:SystemDrive 'kitprueba\archivos' }
$paraBorrar = $base.Substring(0, 2) + '\_PARA_BORRAR'
$relBase = $base.Substring(3)
if (Test-Path $base) { throw "Ya existe ${base}: revisar a mano" }
if (Test-Path $paraBorrar) { throw "Ya existe ${paraBorrar}: la prueba no corre para no tocar nada real" }
$perfil = "$base\Users\Ana"
$clientes = "$base\clientes"
$script:Ctx.CarpetaClientes = $clientes
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N $D" } }
$viejo = (Get-Date).AddDays(-30)
$rnd = New-Object Random 7
function New-Archivo { param([string]$Ruta, [int]$Bytes, [byte[]]$Contenido, [switch]$Reciente, [datetime]$Fecha)
    $null = New-Item -ItemType Directory -Force (Split-Path -Parent $Ruta)
    if (-not $Contenido) { $Contenido = New-Object byte[] $Bytes; $rnd.NextBytes($Contenido) }
    [IO.File]::WriteAllBytes($Ruta, $Contenido)
    if (-not $Reciente) { (Get-Item -LiteralPath $Ruta).LastWriteTime = $(if ($Fecha) { $Fecha } else { $viejo }) }
    , $Contenido }
function New-Foto { param([string]$Ruta, [int]$Ruido)
    $null = New-Item -ItemType Directory -Force (Split-Path -Parent $Ruta)
    $bmp = New-Object Drawing.Bitmap 200, 200
    for ($x = 0; $x -lt 200; $x += 4) { for ($y = 0; $y -lt 200; $y += 4) { $v = [int][math]::Min(255, $x + $rnd.Next(0, $Ruido + 1)); $c = [Drawing.Color]::FromArgb($v, [int]($y * 1.2) % 256, 128); for ($i = 0; $i -lt 4; $i++) { for ($j = 0; $j -lt 4; $j++) { $bmp.SetPixel($x + $i, $y + $j, $c) } } } }
    $bmp.Save($Ruta, [Drawing.Imaging.ImageFormat]::Jpeg); $bmp.Dispose(); (Get-Item $Ruta).LastWriteTime = $viejo }

'== Armando la carpeta de prueba'
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
$null = New-Archivo "$perfil\AppData\Roaming\Programa\debug.log" 2MB
$null = New-Archivo "$perfil\AppData\Roaming\Viejo\datos.bin" 1500KB -Fecha (Get-Date).AddDays(-400)
New-Foto "$perfil\Pictures\Terreno\IMG_001.jpg" 3
New-Foto "$perfil\Pictures\Terreno\IMG_002.jpg" 6
$null = New-Item -ItemType Directory -Force "$perfil\Videos", "$perfil\Music"
$antes = @{}
Get-ChildItem $perfil -Recurse -File | ForEach-Object { $antes[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash }
"  $($antes.Count) archivos de prueba"

'== Expediente de prueba con permiso'
$id = [pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Archivos'; Serie = 'PRUEBA001'; SerieOriginal = 'PRUEBA001'; Uuid = $null; PlacaSerie = $null }
$exp = New-Expediente -Identidad $id
$at = New-Atencion -Expediente $exp
try { $null = Invoke-AnalisisArchivos -Expediente $exp -Atencion $at -Perfil $perfil; Assert 'sin permiso no analiza' $false } catch { Assert 'sin motivo/consentimiento no analiza' ($_.Exception.Message -match 'Falta en la ficha') $_.Exception.Message }
Set-Ficha -Expediente $exp -Atencion $at -Valores @{ motivos = 'ARCHIVOS'; consentimiento_archivos = 'solo_leer'; carpetas_protegidas = "$perfil\Documents\Tesis" }

'== Análisis'
$rep = Invoke-AnalisisArchivos -Expediente $exp -Atencion $at -Perfil $perfil
$c = @($rep.candidatos)
$porRuta = @{}; foreach ($x in $c) { $porRuta[$x.ruta] = $x }
foreach ($x in $c) { '     [{0,-19}] {1,-3} {2}' -f $x.categoria, $(if ($x.seleccionado) { 'sí' } else { 'no' }), $x.ruta.Substring($perfil.Length + 1) }
"     excluidos: $(($rep.excluidos.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
Assert 'duplicado en Descargas "(1)" -> apartar' ($porRuta["$perfil\Downloads\informe (1).pdf"].categoria -eq 'duplicado')
Assert 'Documentos\informe.pdf se conserva' (-not $porRuta.ContainsKey("$perfil\Documents\informe.pdf"))
Assert 'el Escritorio no se toca' (-not $porRuta.ContainsKey("$perfil\Desktop\informe.pdf"))
Assert 'duplicado modificado hace poco no se toca' (-not $porRuta.ContainsKey("$perfil\Downloads\informe_reciente.pdf"))
Assert 'zip "(1)" en Descargas -> apartar' ($porRuta["$perfil\Downloads\fotos (1).zip"].categoria -eq 'duplicado')
Assert 'copia de carpeta protegida en Descargas -> apartar, la protegida se conserva' ($porRuta["$perfil\Downloads\capitulo1.docx"].categoria -eq 'duplicado' -and -not $porRuta.ContainsKey("$perfil\Documents\Tesis\capitulo1.docx"))
Assert 'archivo con "clave" no se toca' (-not $porRuta.ContainsKey("$perfil\Downloads\clave_banco (1).txt"))
Assert 'partida guardada no se toca (ni su copia)' (-not $porRuta.ContainsKey("$perfil\Saved Games\Juego\save1.dat"))
Assert 'instaladores repetidos: se aparta el viejo y (1), se conserva el más nuevo' ($porRuta["$perfil\Downloads\ChromeSetup.exe"].categoria -eq 'instalador_repetido' -and $porRuta["$perfil\Downloads\ChromeSetup (1).exe"] -and -not $porRuta.ContainsKey("$perfil\Downloads\ChromeSetup (2).exe"))
Assert '~$ de Office' ($porRuta["$perfil\Documents\~`$carta.docx"].categoria -eq 'office_temporal')
Assert 'Temp viejo sí, Temp reciente no' ($porRuta["$perfil\AppData\Local\Temp\viejo.tmp"].categoria -eq 'temp' -and -not $porRuta.ContainsKey("$perfil\AppData\Local\Temp\nuevo.tmp"))
Assert 'scoped_dir como carpeta' ($porRuta["$perfil\AppData\Local\Temp\scoped_dir123_456"].es_carpeta)
Assert 'caché de juegos' ($porRuta["$perfil\AppData\Local\NVIDIA\DXCache\x.bin"].categoria -eq 'cache_juegos')
Assert 'log gigante' ($porRuta["$perfil\AppData\Roaming\Programa\debug.log"].categoria -eq 'log_gigante')
Assert 'posible resto: solo reportado' ($porRuta["$perfil\AppData\Roaming\Viejo"].categoria -eq 'posible_resto' -and -not $porRuta["$perfil\AppData\Roaming\Viejo"].seleccionable)
Assert 'fotos parecidas: solo reportadas' (@($c | Where-Object { $_.categoria -eq 'foto_parecida' -and -not $_.seleccionable }).Count -eq 2)
Assert 'reporte.json y reporte.csv' ((Test-Path "$($exp.Ruta)\$at\archivos\reporte.json") -and (Test-Path "$($exp.Ruta)\$at\archivos\reporte.csv"))

'== Mover'
try { $null = Move-ArchivosParaBorrar -Expediente $exp -Atencion $at; Assert 'con solo_leer no mueve' $false } catch { Assert 'con consentimiento solo_leer no mueve' ($_.Exception.Message -match 'Sin permiso') }
Set-Ficha -Expediente $exp -Atencion $at -Valores @{ consentimiento_archivos = 'mover' }
$r = Move-ArchivosParaBorrar -Expediente $exp -Atencion $at
"     movidos: $($r.Movidos) ($(Format-Tamano $r.Bytes)) a $($r.Destinos -join ', ') | saltados: $($r.Saltados.Count)"
$r.Saltados | ForEach-Object { "       saltado: $_" }
$dest = $r.Destinos[0]
Assert 'todo va a <disco>:\_PARA_BORRAR\<fecha_hora>' ($dest -match ('^' + [regex]::Escape($paraBorrar) + '\\\d{4}-\d{2}-\d{2}_\d{4}$')) -D $dest
Assert 'informe (1).pdf ya no está y quedó en _PARA_BORRAR' (-not (Test-Path "$perfil\Downloads\informe (1).pdf") -and (Test-Path "$dest\$relBase\Users\Ana\Downloads\informe (1).pdf"))
Assert 'lo protegido, el Escritorio, credenciales y partidas siguen en su lugar' ((Test-Path "$perfil\Documents\Tesis\capitulo1.docx") -and (Test-Path "$perfil\Desktop\informe.pdf") -and (Test-Path "$perfil\Downloads\clave_banco (1).txt") -and (Test-Path "$perfil\Saved Games\Juego\save1.dat"))
Assert 'fotos parecidas y restos no se movieron' ((Test-Path "$perfil\Pictures\Terreno\IMG_001.jpg") -and (Test-Path "$perfil\AppData\Roaming\Viejo\datos.bin"))
Assert '_DESHACER.ps1 y LEEME.txt en _PARA_BORRAR y en el expediente' ((Test-Path "$dest\_DESHACER.ps1") -and (Test-Path "$dest\LEEME.txt") -and (Test-Path "$($exp.Ruta)\$at\archivos\_DESHACER.ps1"))
$m = Get-MetricasArchivos -Expediente $exp -Atencion $at
"     métricas: $($m.GBApartados) GB, $($m.Elementos) elementos, $($m.Duplicados) duplicados, en $($m.Ubicaciones -join ', ')"
Assert 'métricas con duplicados apartados' ($m.Duplicados -eq 3 -and $m.Elementos -eq $r.Movidos)

'== Deshacer con la función'
$u = Undo-MovimientoArchivos -Expediente $exp -Atencion $at
"     devueltos: $($u.Devueltos) | problemas: $($u.Problemas.Count)"
$despues = @{}; Get-ChildItem $perfil -Recurse -File | ForEach-Object { $despues[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash }
$iguales = @($antes.Keys | Where-Object { $despues[$_] -eq $antes[$_] }).Count
Assert 'todos los archivos volvieron, mismo hash y misma ruta' ($iguales -eq $antes.Count -and $despues.Count -eq $antes.Count) "$iguales de $($antes.Count)"
Assert 'la carpeta del lote, vacía, se retira (solo tenía lo del kit)' (-not (Test-Path $dest) -and -not (Test-Path $paraBorrar))

'== Mover otra vez y deshacer con el _DESHACER.ps1 autónomo (como lo haría el cliente)'
Start-Sleep -Seconds 61   # marca de tiempo distinta para la carpeta del segundo lote
$rep2 = Invoke-AnalisisArchivos -Expediente $exp -Atencion $at -Perfil $perfil
$r2 = Move-ArchivosParaBorrar -Expediente $exp -Atencion $at
$salida = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$($r2.Destinos[0])\_DESHACER.ps1" 2>&1 | Out-String
"     $($salida.Trim())"
$despues2 = @{}; Get-ChildItem $perfil -Recurse -File | ForEach-Object { $despues2[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash }
Assert '_DESHACER.ps1 devolvió todo, mismo hash y misma ruta' (@($antes.Keys | Where-Object { $despues2[$_] -eq $antes[$_] }).Count -eq $antes.Count -and $despues2.Count -eq $antes.Count)
'== trabajo.log'
Get-Content -Encoding UTF8 "$($exp.Ruta)\$at\trabajo.log" | ForEach-Object { "     $_" }
''
"Resultado: $script:ok OK, $script:fallas fallas"
# Limpieza: solo lo creado por esta prueba
Remove-Item $base -Recurse -Force
if (Test-Path $paraBorrar) { Remove-Item $paraBorrar -Recurse -Force }   # no existía antes de la prueba
"Limpieza: kitservicio_prueba\archivos existe: $(Test-Path $base) | $paraBorrar existe: $(Test-Path $paraBorrar)"
