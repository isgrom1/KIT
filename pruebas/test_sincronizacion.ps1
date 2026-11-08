#Requires -Version 5.1
# Pruebas de lib\Sincronizacion.ps1 y sincronizar.ps1 con expedientes sintéticos.
# Solo escribe en -Base (carpeta de prueba creada aquí): nunca toca KIT\clientes ni el maestro real.
param([string]$Kit = (Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT'), [string]$Base = $(if (Test-Path 'X:\') { 'X:\kitservicio_prueba\sync con espacios ñ' } else { Join-Path $env:SystemDrive 'kitprueba\sync con espacios ñ' }))
$ErrorActionPreference = 'Stop'
$scripts = Join-Path $Kit 'scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente', 'Sincronizacion') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:mal = 0
function Test-Caso([string]$Nombre, [bool]$Cond, [string]$Detalle = '') {
    if ($Cond) { $script:ok++; Write-Host "OK    $Nombre" } else { $script:mal++; Write-Host "FALLA $Nombre  $Detalle" -ForegroundColor Red }
}
function Hash([string]$r) { (Get-FileHash -LiteralPath $r -Algorithm SHA256).Hash }
function Escribir([string]$r, [string]$t) { $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $r)); [IO.File]::WriteAllText($r, $t, (New-Object Text.UTF8Encoding($true))) }

if ($Base -notlike 'X:\kitservicio_prueba\*' -and $Base -notlike '*:\kitprueba*') { throw "Base de prueba inesperada: $Base" }
if ([IO.Directory]::Exists($Base)) { [IO.Directory]::Delete($Base, $true) }
$usb = Join-Path $Base 'usb\clientes'
$maestro = Join-Path $Base 'maestro\clientes'
$null = [IO.Directory]::CreateDirectory($usb)
$script:Ctx.CarpetaClientes = $usb
Write-Host "Kit: $Kit"
Write-Host "Base: $Base"

# ---------------------------------------------------------------- datos sintéticos
function New-ExpPrueba([string]$Fab, [string]$Modelo, [string]$Serie, [string]$Nombre, [string[]]$Fechas, [int]$Entregadas) {
    $id = [pscustomobject]@{ Fabricante = $Fab; Modelo = $Modelo; Serie = $Serie; SerieOriginal = $Serie; Uuid = $null; PlacaSerie = $null }
    $e = New-Expediente -Identidad $id
    Set-Ficha -Expediente $e -Valores @{ 'cliente.nombre' = $Nombre; 'cliente.contacto' = '+56 9 1111 2222'; 'cliente.comuna' = 'Ñuñoa' } -ErrorAction SilentlyContinue
    $i = 0
    foreach ($f in $Fechas) {
        $at = New-Atencion -Expediente $e -Fecha ([datetime]::ParseExact($f, 'yyyy-MM-dd', $null))
        $c = Join-Path $e.Ruta $at
        Escribir (Join-Path $c 'antes\diagnostico.json') "{ ""prueba"": ""$at"" }"
        Escribir (Join-Path $c 'antes\resumen.txt') "Resumen de prueba $at"
        Escribir (Join-Path $c 'trabajo.log') "2026-11-01 10:00 | INICIO | $at`r`n"
        Escribir (Join-Path $c 'informe_cliente.html') "<html>informe $at</html>"
        if ($i -lt $Entregadas) { Set-Ficha -Expediente $e -Atencion $at -Valores @{ entregado = $f } }
        $i++
    }
    Escribir (Join-Path $e.Ruta 'fotos_recepcion\20261020_foto1.jpg') ('JPGFALSO' * 500)
    Read-Expediente $e.Ruta
}
$expA = New-ExpPrueba 'HP' 'Pavilion 15' '5CD1234XYZ' 'Ana Pérez' @('2026-10-20', '2026-11-01') 1
$expB = New-ExpPrueba 'Lenovo' 'IdeaPad 3' 'PF2ABCDE' 'Bruno Díaz' @('2026-10-15') 1
$expC = New-ExpPrueba 'ASUS' 'TUF F15' 'N1NXCV00' 'Carla Soto' @('2026-10-10') 1
$atA1 = '2026-10-20_atencion'; $atA2 = '2026-11-01_atencion'
Test-Caso 'datos: A tiene 1 abierta' ((Get-AtencionAbierta -Expediente $expA) -eq $atA2)

$avances = New-Object System.Collections.Generic.List[string]
$sinc = { param([switch]$Liberar) Invoke-Sincronizacion -Clientes $usb -Maestro $maestro -LiberarUsb:$Liberar -AlAvance { param($t) $avances.Add($t) } }

# ---------------------------------------------------------------- 1. primera sincronización
$r1 = & $sinc
$total = @(Get-ArchivosExpedientes -Clientes $usb).Archivos.Count
Test-Caso '1 todo nuevo' ($r1.Nuevos -eq $total -and $r1.Iguales -eq 0 -and @($r1.Conflictos).Count -eq 0 -and @($r1.Errores).Count -eq 0) "nuevos=$($r1.Nuevos) total=$total err=$(@($r1.Errores) -join ';')"
$distintos = @((Get-ArchivosExpedientes -Clientes $usb).Archivos | Where-Object { (Hash $_.Ruta) -ne (Hash (Join-Path $maestro $_.Rel)) })
Test-Caso '1 hashes idénticos en el maestro' ($distintos.Count -eq 0)
Test-Caso '1 sin .bak ni .tmp en el maestro' (@(Get-ChildItem -LiteralPath $maestro -Recurse -File | Where-Object { $_.Name -match '\.(bak|tmp|sync_tmp)$' }).Count -eq 0)
Test-Caso '1 estado y log' ([IO.File]::Exists($r1.Log) -and @(Get-ChildItem -LiteralPath (Join-Path $maestro '_sincronizacion') -Filter 'estado_*.tsv').Count -eq 1)
Test-Caso '1 copia del log en el USB' ([IO.File]::Exists((Join-Path $usb "_sincronizacion\logs\$([IO.Path]::GetFileName($r1.Log))")))
Test-Caso '1 log con NUEVO e INICIO/FIN' ((Get-Content -LiteralPath $r1.Log -Raw) -match 'NUEVO' -and (Get-Content -LiteralPath $r1.Log -Raw) -match '\| FIN')
Test-Caso '1 avance informado' ($avances.Count -gt 0)
Test-Caso '1 sin candado al terminar' (-not [IO.File]::Exists((Join-Path $maestro '_sincronizacion\sincronizando.lock')))
Test-Caso '1 _sincronizacion del USB no se copia' (-not [IO.Directory]::Exists((Join-Path $maestro '_sincronizacion\kit.json')) -and -not [IO.File]::Exists((Join-Path $maestro '_sincronizacion\kit.json')))

# ---------------------------------------------------------------- 2. sin cambios
$r2 = & $sinc
Test-Caso '2 sin cambios: todo igual' ($r2.Nuevos -eq 0 -and $r2.Iguales -eq $total -and $r2.Actualizados -eq 0) "nuevos=$($r2.Nuevos) iguales=$($r2.Iguales)"

# ---------------------------------------------------------------- 3. cambia en el USB -> se actualiza y se guarda la anterior
$fichaMaestroAntes = Hash (Join-Path $maestro "$($expA.Id)\ficha.json")
Set-Ficha -Expediente $expA -Atencion $atA2 -Valores @{ notas = 'cambio en el USB' }
$r3 = & $sinc
$ant = @(Get-ChildItem -LiteralPath (Join-Path $maestro '_sincronizacion\anteriores') -Recurse -Filter ficha.json)
Test-Caso '3 actualizado (solo cambió en el USB)' ($r3.Actualizados -eq 1 -and @($r3.Conflictos).Count -eq 0) "act=$($r3.Actualizados) conf=$(@($r3.Conflictos) -join ';')"
Test-Caso '3 maestro = USB' ((Hash (Join-Path $maestro "$($expA.Id)\ficha.json")) -eq (Hash (Join-Path $expA.Ruta 'ficha.json')))
Test-Caso '3 versión anterior guardada' ($ant.Count -eq 1 -and (Hash $ant[0].FullName) -eq $fichaMaestroAntes)

# ---------------------------------------------------------------- 4. cambia en el maestro -> se deja el del maestro
$infM = Join-Path $maestro "$($expA.Id)\$atA1\informe_cliente.html"
Escribir $infM '<html>regenerado en el maestro</html>'
$hInfM = Hash $infM
$r4 = & $sinc
Test-Caso '4 más nuevo en el maestro: no se toca' ($r4.MaestroMasNuevo -eq 1 -and (Hash $infM) -eq $hInfM -and @($r4.Conflictos).Count -eq 0)

# ---------------------------------------------------------------- 5. cambia en los dos -> conflicto, se conservan ambos
$logU = Join-Path $expA.Ruta "$atA2\trabajo.log"; $logM = Join-Path $maestro "$($expA.Id)\$atA2\trabajo.log"
[IO.File]::AppendAllText($logU, "linea USB`r`n"); [IO.File]::AppendAllText($logM, "linea maestro`r`n")
$hLogM = Hash $logM
$r5 = & $sinc
$copias = @(Get-CopiasConflicto $logM)
Test-Caso '5 conflicto avisado' (@($r5.Conflictos) -contains "$($expA.Id)\$atA2\trabajo.log")
Test-Caso '5 el del maestro no se tocó' ((Hash $logM) -eq $hLogM)
Test-Caso '5 el del USB quedó como copia de conflicto' ($copias.Count -eq 1 -and (Hash $copias[0]) -eq (Hash $logU)) "copias=$($copias.Count)"
$r5b = & $sinc
Test-Caso '5 no repite el aviso ni la copia' (@($r5b.Conflictos).Count -eq 0 -and @(Get-CopiasConflicto $logM).Count -eq 1)

# ---------------------------------------------------------------- 6. medición en curso -> se omite
Escribir (Join-Path $expA.Ruta "$atA2\despues_en_curso\log.txt") 'a medias'
$r6 = & $sinc
Test-Caso '6 medición en curso omitida' (@($r6.EnCurso).Count -eq 1 -and -not [IO.Directory]::Exists((Join-Path $maestro "$($expA.Id)\$atA2\despues_en_curso")))
[IO.Directory]::Delete((Join-Path $expA.Ruta "$atA2\despues_en_curso"), $true)

# ---------------------------------------------------------------- 7. liberar el USB
# A1: informe regenerado y diagnóstico cambiado en el maestro (cambiaron allá después de recibirlos): se
#     libera y la versión del USB queda en anteriores. B: un archivo no pudo llegar al maestro: su
#     atención NO se libera, pero sus fotos sí (no tiene abiertas). C: trabajo.log en conflicto (el del
#     USB está como copia de conflicto): se libera. A2 abierta: queda.
$diagA1M = Join-Path $maestro "$($expA.Id)\$atA1\antes\diagnostico.json"
Escribir $diagA1M '{ "cambiado en el maestro": true }'
$hDiagA1U = Hash (Join-Path $expA.Ruta "$atA1\antes\diagnostico.json"); $hInfA1U = Hash (Join-Path $expA.Ruta "$atA1\informe_cliente.html")
$logCU = Join-Path $expC.Ruta '2026-10-10_atencion\trabajo.log'; $logCM = Join-Path $maestro "$($expC.Id)\2026-10-10_atencion\trabajo.log"
[IO.File]::AppendAllText($logCU, "USB`r`n"); [IO.File]::AppendAllText($logCM, "MAESTRO`r`n")
[IO.File]::WriteAllText((Join-Path $expA.Ruta "$atA1\_gui_parametros.json"), '{}')   # transitorio del kit
Escribir (Join-Path $expB.Ruta '2026-10-15_atencion\extra.txt') 'no va a poder copiarse'
$bloqueo = Join-Path $maestro "$($expB.Id)\2026-10-15_atencion\extra.txt"
$null = [IO.Directory]::CreateDirectory($bloqueo)   # una carpeta con el mismo nombre impide la copia
$bytesUsbAntes = (Get-ChildItem -LiteralPath $usb -Recurse -File | Measure-Object Length -Sum).Sum
$r7 = & $sinc -Liberar
Test-Caso '7 copia imposible: queda como error' (@($r7.Errores | Where-Object { $_ -like '*extra.txt*' }).Count -eq 1) "$(@($r7.Errores) -join ' | ')"
Test-Caso '7 B con un archivo sin copiar: NO se libera' ([IO.Directory]::Exists((Join-Path $expB.Ruta '2026-10-15_atencion')) -and @($r7.NoLiberadas | Where-Object { $_ -like "$($expB.Id)\2026-10-15_atencion*" }).Count -eq 1) "$(@($r7.NoLiberadas) -join ' | ')"
Test-Caso '7 B: los demás archivos siguen en el USB' ([IO.File]::Exists((Join-Path $expB.Ruta '2026-10-15_atencion\antes\diagnostico.json')))
Test-Caso '7 B: fotos liberadas (sin atenciones abiertas)' (@($r7.Liberadas) -contains "$($expB.Id)\fotos_recepcion" -and [IO.File]::Exists((Join-Path $maestro "$($expB.Id)\fotos_recepcion\20261020_foto1.jpg")) -and -not [IO.File]::Exists((Join-Path $expB.Ruta 'fotos_recepcion\20261020_foto1.jpg')))
Test-Caso '7 B: ficha y carpeta de fotos quedan' ([IO.File]::Exists((Join-Path $expB.Ruta 'ficha.json')) -and [IO.Directory]::Exists((Join-Path $expB.Ruta 'fotos_recepcion')))
Test-Caso '7 A1 cambiada en el maestro: se libera' (-not [IO.Directory]::Exists((Join-Path $expA.Ruta $atA1)) -and @($r7.Liberadas) -contains "$($expA.Id)\$atA1") "$(@($r7.NoLiberadas) -join ' | ')"
$antA1 = @(Get-ChildItem -LiteralPath (Join-Path $maestro '_sincronizacion\anteriores') -Recurse -File | Where-Object { $_.FullName -like "*\$($expA.Id)\$atA1\*" } | ForEach-Object { Hash $_.FullName })
Test-Caso '7 A1: las versiones del USB quedaron en anteriores' ($antA1 -contains $hDiagA1U -and $antA1 -contains $hInfA1U) "hashes en anteriores: $($antA1.Count)"
Test-Caso '7 A1: el maestro conserva lo suyo' ((Get-Content -LiteralPath $diagA1M -Raw) -match 'cambiado en el maestro' -and (Get-Content -LiteralPath $infM -Raw) -match 'regenerado')
Test-Caso '7 el transitorio se fue con la atención' (-not [IO.File]::Exists((Join-Path $expA.Ruta "$atA1\_gui_parametros.json")) -and -not [IO.File]::Exists((Join-Path $maestro "$($expA.Id)\$atA1\_gui_parametros.json")))
Test-Caso '7 A2 abierta queda' ([IO.Directory]::Exists((Join-Path $expA.Ruta $atA2)))
Test-Caso '7 fotos de A quedan (tiene abierta)' ([IO.File]::Exists((Join-Path $expA.Ruta 'fotos_recepcion\20261020_foto1.jpg')))
Test-Caso '7 C liberada con copia de conflicto' (@($r7.Liberadas) -contains "$($expC.Id)\2026-10-10_atencion") "$(@($r7.Liberadas) -join ' | ')"
Test-Caso '7 bytes liberados' ($r7.BytesLiberados -gt 0 -and (Get-ChildItem -LiteralPath $usb -Recurse -File | Measure-Object Length -Sum).Sum -lt $bytesUsbAntes)
$textoLog7 = Get-Content -LiteralPath $r7.Log -Raw
Test-Caso '7 log con LIBERADO, NO LIBERADO y ANTERIORES' ($textoLog7 -match '\| LIBERADO' -and $textoLog7 -match 'NO LIBERADO' -and $textoLog7 -match 'ANTERIORES')
# Se saca el estorbo del maestro y se vuelve a sincronizar: ahora B sí se libera.
[IO.Directory]::Delete($bloqueo)
$r7b = & $sinc -Liberar
Test-Caso '7 B liberada al poder copiarse' (-not [IO.Directory]::Exists((Join-Path $expB.Ruta '2026-10-15_atencion')) -and @($r7b.Liberadas) -contains "$($expB.Id)\2026-10-15_atencion" -and [IO.File]::Exists($bloqueo)) "$(@($r7b.NoLiberadas) -join ' | ')"

# ---------------------------------------------------------------- 8. el kit sigue funcionando con lo liberado
$expA = Read-Expediente $expA.Ruta
Test-Caso '8 A sigue reconociendo la atención abierta' ((Get-AtencionAbierta -Expediente $expA) -eq $atA2)
$nueva = New-Atencion -Expediente $expA -Fecha ([datetime]'2026-10-20')
Test-Caso '8 atención nueva no choca con una liberada' ($nueva -eq '2026-10-20_atencion_2')
$filasU = @(Get-ListaExpedientes -Carpeta $usb -EsUsb)
$filaA = $filasU | Where-Object { $_.Ruta -eq $expA.Ruta }
Test-Caso '8 lista USB marca lo que está en el maestro' ($filasU.Count -eq 3 -and $filaA.Atenciones -match 'en el maestro' -and $filaA.Cliente -eq 'Ana Pérez') "$($filaA.Atenciones)"
$filasM = @(Get-ListaExpedientes -Carpeta $maestro)
Test-Caso '8 lista del maestro (sin _sincronizacion)' ($filasM.Count -eq 3 -and @($filasM | Where-Object { $_.Atenciones -match 'sin carpeta' }).Count -eq 0)

# ---------------------------------------------------------------- 9. otro kit, sin estado: diferencia = conflicto; igual = igual
[IO.File]::Delete((Join-Path $usb '_sincronizacion\kit.json'))
Set-Ficha -Expediente $expA -Atencion $atA2 -Valores @{ notas = 'otro kit' }
$r9 = & $sinc
Test-Caso '9 kit nuevo: cambio sin estado = conflicto' (@($r9.Conflictos) -contains "$($expA.Id)\ficha.json" -and $r9.Actualizados -eq 0) "conf=$(@($r9.Conflictos) -join ';')"
Test-Caso '9 kit nuevo: lo idéntico es igual' ($r9.Iguales -gt 0)
Test-Caso '9 dos archivos de estado (uno por kit)' (@(Get-ChildItem -LiteralPath (Join-Path $maestro '_sincronizacion') -Filter 'estado_*.tsv').Count -eq 2)

# ---------------------------------------------------------------- 10. restos de una copia cortada
$nuevoU = Join-Path $expA.Ruta "$atA2\nota.txt"; Escribir $nuevoU 'archivo nuevo'
Escribir "$(Join-Path $maestro "$($expA.Id)\$atA2\nota.txt").sync_tmp" 'resto de una copia cortada'
$r10 = & $sinc
Test-Caso '10 copia cortada: se rehace bien' ((Hash (Join-Path $maestro "$($expA.Id)\$atA2\nota.txt")) -eq (Hash $nuevoU) -and -not [IO.File]::Exists("$(Join-Path $maestro "$($expA.Id)\$atA2\nota.txt").sync_tmp"))

# ---------------------------------------------------------------- 11. candado, rutas inválidas
$fs = [IO.File]::Open((Join-Path $maestro '_sincronizacion\sincronizando.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$msg = ''; try { & $sinc | Out-Null } catch { $msg = $_.Exception.Message } finally { $fs.Dispose() }
Test-Caso '11 dos sincronizaciones a la vez: la segunda se niega' ($msg -match 'otra sincronización en curso') $msg
$msg = ''; try { Invoke-Sincronizacion -Clientes $usb -Maestro (Join-Path $usb 'maestro') | Out-Null } catch { $msg = $_.Exception.Message }
Test-Caso '11 maestro dentro del USB: se niega' ($msg -match 'no puede ser') $msg
$msg = ''; try { Invoke-Sincronizacion -Clientes $usb -Maestro 'Q:\no\existe' | Out-Null } catch { $msg = $_.Exception.Message }
Test-Caso '11 unidad del maestro ausente: se niega' ($msg -match 'No está la unidad') $msg

# ---------------------------------------------------------------- 12. sincronizar.ps1 (como lo llaman INICIAR y la interfaz)
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$script = Join-Path $scripts 'sincronizar.ps1'
& $ps -NoProfile -ExecutionPolicy Bypass -File $script -EsTecnico; $c1 = $LASTEXITCODE
$guardado = $env:COMPUTERNAME
try {
    $env:COMPUTERNAME = 'OTRO-PC'
    & $ps -NoProfile -ExecutionPolicy Bypass -File $script -EsTecnico; $c2 = $LASTEXITCODE
    $salidaOtro = & $ps -NoProfile -ExecutionPolicy Bypass -File $script -Clientes $usb -Maestro $maestro -ProgresoGui; $c3 = $LASTEXITCODE
} finally { $env:COMPUTERNAME = $guardado }
Test-Caso '12 -EsTecnico: este PC sí (0), otro no (1)' ($c1 -eq 0 -and $c2 -eq 1) "c1=$c1 c2=$c2"
Test-Caso '12 otro PC: se niega con ##ERROR' ($c3 -eq 1 -and (@($salidaOtro) -join "`n") -match '##ERROR\|Sincronizar es solo para tus equipos') "$(@($salidaOtro) -join ' / ')"
$psi = New-Object Diagnostics.ProcessStartInfo $ps
$psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Clientes "{1}" -Maestro "{2}" -ProgresoGui -LiberarUsb' -f $script, $usb, $maestro
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$p = [Diagnostics.Process]::Start($psi); $salida = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
$res = ($salida -split "`r?`n" | Where-Object { $_ -like '##RESULTADO|*' } | Select-Object -First 1)
$obj = if ($res) { $res.Substring(12) | ConvertFrom-Json } else { $null }
Test-Caso '12 -ProgresoGui: ##LOG y ##RESULTADO legibles (UTF-8)' ($p.ExitCode -eq 0 -and $salida -match '##LOG\|' -and $obj -and $obj.Usb -eq [IO.Path]::GetFullPath($usb)) "exit=$($p.ExitCode) $($salida.Substring(0, [Math]::Min(300, $salida.Length)))"
$salidaConsola = & $ps -NoProfile -ExecutionPolicy Bypass -File $script -Clientes $usb -Maestro $maestro 6>&1 2>&1 | Out-String
Test-Caso '12 consola: resumen' ($LASTEXITCODE -eq 0 -and $salidaConsola -match 'archivos revisados') ($salidaConsola.Substring(0, [Math]::Min(300, $salidaConsola.Length)))

Write-Host ''
Write-Host "Resultado: $script:ok OK, $script:mal fallas" -ForegroundColor $(if ($script:mal) { 'Red' } else { 'Green' })
exit $script:mal
