#Requires -Version 5.1
<#
.SYNOPSIS
    Respaldo cifrado del maestro (lib\Respaldo.ps1, respaldar_maestro.ps1 y el paso de sincronizar.ps1).
.DESCRIPTION
    Con un maestro sintético en una carpeta temporal y una contraseña de prueba generada aquí. No toca el
    maestro real, Z: ni la contraseña guardada de Isaac.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $repo 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Sincronizacion', 'Respaldo') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_resp_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$utf8 = New-Object Text.UTF8Encoding($false)
function Write-Texto([string]$Ruta, [string]$Texto) { $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Ruta)); [IO.File]::WriteAllText($Ruta, $Texto, $utf8) }
function ConvertTo-Seguro([string]$Texto) { $s = New-Object Security.SecureString; foreach ($ch in $Texto.ToCharArray()) { $s.AppendChar($ch) }; $s.MakeReadOnly(); $s }
$clave = ConvertTo-Seguro ('prueba-' + [guid]::NewGuid().ToString('N'))
$otra = ConvertTo-Seguro 'otra-contraseña-de-prueba'

try {
    $maestro = Join-Path $tmp 'maestro'
    Write-Texto "$maestro\Acer_Ejemplo_SERIE01\ficha.json" '{"cliente":{"nombre":"Cliente Ejemplo Ñandú"}}'
    Write-Texto "$maestro\Acer_Ejemplo_SERIE01\2026-11-08_atencion\trabajo.log" "línea 1`r`nlínea 2"
    Write-Texto "$maestro\Dell con espacios\fotos_recepcion\vacío.txt" ''
    $grande = New-Object byte[] (3MB + 17); (New-Object Random 7).NextBytes($grande)
    $null = [IO.Directory]::CreateDirectory("$maestro\Dell con espacios\fotos_recepcion"); [IO.File]::WriteAllBytes("$maestro\Dell con espacios\fotos_recepcion\foto.jpg", $grande)
    Write-Texto "$maestro\_sincronizacion\logs\sync.log" 'log de prueba'
    $original = @(Get-ArchivosMaestro -Maestro $maestro)
    $dest = Join-Path $tmp 'respaldos'

    '== Respaldar y verificar'
    $r = New-RespaldoMaestro -Maestro $maestro -Destino $dest -Clave $clave -Iteraciones 20000
    Assert 'deja maestro_<fecha_hora>.kitresp y nada a medias' ((Split-Path -Leaf $r.Ruta) -match '^maestro_\d{8}_\d{6}\.kitresp$' -and @(Get-ChildItem $dest -Filter '*.parcial').Count -eq 0 -and $r.Archivos -eq 5) -D "$($r.Ruta) $($r.Archivos)"
    $bytes = [IO.File]::ReadAllBytes($r.Ruta)
    $texto = [Text.Encoding]::UTF8.GetString($bytes)
    Assert 'empieza con KITRESP1 y está comprimido (pesa menos que el maestro con datos al azar)' ($texto.StartsWith('KITRESP1') -and $bytes.Length -lt (3MB + 4000))
    Assert 'no deja ver nombres de archivos ni datos del cliente' ($texto -notmatch 'ficha\.json|Ñandú|trabajo\.log|Cliente Ejemplo')
    $leidos = @(Read-ArchivosRespaldo -Ruta $r.Ruta -Clave $clave)
    Assert 'se lee completo: mismas rutas y SHA-256 que el maestro' ($leidos.Count -eq 5 -and (($leidos | ForEach-Object { "$($_.Relativa)|$($_.Hash)" }) -join ';') -eq (($original | ForEach-Object { "$($_.Relativa)|$($_.Hash)" }) -join ';'))
    $e1 = $null; try { $null = Read-ArchivosRespaldo -Ruta $r.Ruta -Clave $otra } catch { $e1 = $_.Exception.Message }
    Assert 'con otra contraseña no se abre' ($e1 -match 'contraseña no es la correcta')
    $danado = Join-Path $tmp 'danado.kitresp'
    $b2 = [byte[]]$bytes.Clone(); $b2[$b2.Length - 100] = $b2[$b2.Length - 100] -bxor 0xFF; [IO.File]::WriteAllBytes($danado, $b2)
    $e2 = $null; try { $null = Read-ArchivosRespaldo -Ruta $danado -Clave $clave } catch { $e2 = $_.Exception.Message }
    Assert 'un byte cambiado se detecta (firma)' ($e2 -match 'dañado')
    [IO.File]::WriteAllText((Join-Path $tmp 'otro.kitresp'), 'no soy un respaldo, pero tengo más de setenta y seis bytes para que se lea el encabezado completo')
    $e3 = $null; try { $null = Read-ArchivosRespaldo -Ruta (Join-Path $tmp 'otro.kitresp') -Clave $clave } catch { $e3 = $_.Exception.Message }
    Assert 'un archivo que no es respaldo lo dice' ($e3 -match 'No es un respaldo')

    '== Restaurar'
    $rest = Join-Path $tmp 'restaurado'
    $l = @(Restore-RespaldoMaestro -Ruta $r.Ruta -Destino $rest -Clave $clave)
    $vuelta = @(Get-ArchivosMaestro -Maestro $rest)
    Assert 'restaura todo idéntico, con acentos, espacios y archivos vacíos' ($l.Count -eq 5 -and (($vuelta | ForEach-Object { "$($_.Relativa)|$($_.Hash)" }) -join ';') -eq (($original | ForEach-Object { "$($_.Relativa)|$($_.Hash)" }) -join ';'))
    $e4 = $null; try { $null = Restore-RespaldoMaestro -Ruta $r.Ruta -Destino $rest -Clave $clave } catch { $e4 = $_.Exception.Message }
    Assert 'no restaura sobre una carpeta con archivos' ($e4 -match 'no está vacía')

    '== Los últimos N'
    for ($i = 0; $i -lt 4; $i++) { Start-Sleep -Milliseconds 1100; $null = New-RespaldoMaestro -Maestro $maestro -Destino $dest -Clave $clave -Iteraciones 20000 -Conservar 3 }
    $quedan = @(Get-ChildItem $dest -Filter 'maestro_*.kitresp' | Sort-Object Name)
    Assert 'deja solo los 3 más nuevos' ($quedan.Count -eq 3 -and $quedan[0].Name -ne (Split-Path -Leaf $r.Ruta)) -D "quedan: $($quedan.Count)"
    $e5 = $null; try { $null = New-RespaldoMaestro -Maestro $maestro -Destino 'Q:\no_existe_unidad' -Clave $clave } catch { $e5 = $_.Exception.Message }
    Assert 'sin la unidad del respaldo lo dice' ($e5 -match 'No está la unidad' -or $e5 -match 'unidad')

    '== Contraseña guardada (DPAPI)'
    $archivoClave = Join-Path $tmp 'clave\respaldo.clave'
    Assert 'sin archivo no hay contraseña' ($null -eq (Get-ClaveRespaldo -Ruta $archivoClave))
    Set-ClaveRespaldo -Clave $clave -Ruta $archivoClave
    $guardada = Get-ClaveRespaldo -Ruta $archivoClave
    Assert 'la guarda cifrada (no en texto) y la recupera' ([IO.File]::ReadAllText($archivoClave) -notmatch 'prueba-' -and @(Read-ArchivosRespaldo -Ruta $quedan[-1].FullName -Clave $guardada).Count -eq 5)

    '== Después de sincronizar'
    $usb = Join-Path $tmp 'usb'
    Write-Texto "$usb\Prueba_Sync_X\ficha.json" '{"version":1,"cliente":{"nombre":"x"},"atenciones":[]}'
    $sal = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'sincronizar.ps1') -Forzar -Clientes $usb -Maestro (Join-Path $tmp 'maestro_sync') -Respaldo (Join-Path $tmp 'resp_sync') -ArchivoClave $archivoClave 2>&1 | Out-String
    Assert 'sincronizar respalda el maestro y lo dice' ($LASTEXITCODE -eq 0 -and $sal -match 'Respaldo verificado' -and @(Get-ChildItem (Join-Path $tmp 'resp_sync') -Filter '*.kitresp').Count -eq 1) -D $sal
    $sal2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'sincronizar.ps1') -Forzar -Clientes $usb -Maestro (Join-Path $tmp 'maestro_sync') -Respaldo (Join-Path $tmp 'resp_sync') -ArchivoClave (Join-Path $tmp 'no_hay.clave') 2>&1 | Out-String
    Assert 'sin contraseña sincroniza igual y avisa' ($LASTEXITCODE -eq 0 -and $sal2 -match 'falta la contraseña') -D $sal2
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
