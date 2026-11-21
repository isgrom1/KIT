#Requires -Version 5.1
<#
.SYNOPSIS
    Fase J (Ley 21.719): consentimiento en la ficha, retención de 18 meses, anonimizar, olvidar (y que la
    sincronización no lo traiga de vuelta), entregar sus datos, apto para Windows 11 y reglas ASR.
.DESCRIPTION
    Todo en carpetas temporales creadas aquí: no toca los expedientes reales ni el maestro.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $repo 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'DatosPersonales', 'Sincronizacion') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'secciones\04_seguridad.ps1')
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_faseJ_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$cli = Join-Path $tmp 'clientes'
$null = [IO.Directory]::CreateDirectory($cli)
$script:Ctx.CarpetaClientes = $cli
$hoy = (Get-Date).ToString('yyyy-MM-dd')

function New-ExpPrueba([string]$Serie, [string]$Nombre, [string]$Fecha) {
    $id = [pscustomobject]@{ Fabricante = 'Dell'; Modelo = 'Inspiron 3493'; Serie = $Serie; SerieOriginal = $Serie; Uuid = $null; PlacaSerie = $null }
    $e = New-Expediente -Identidad $id
    $at = New-Atencion -Expediente $e
    $ent = Get-EntradaAtencion -Expediente $e -Carpeta $at
    $ent['fecha'] = $Fecha
    $e.Ficha['creado'] = "$Fecha 10:00:00"
    Save-Ficha -Expediente $e
    Set-Ficha -Expediente $e -Atencion $at -Valores @{ 'cliente.nombre' = $Nombre; 'cliente.contacto' = '+56 9 1234 5678'; 'cliente.comuna' = 'Ñuñoa'; sintoma = 'anda lento'; notas = 'nota interna' }
    $dir = Join-Path $e.Ruta $at
    $null = [IO.Directory]::CreateDirectory((Join-Path $dir 'antes'))
    [IO.File]::WriteAllText((Join-Path $dir 'antes\diagnostico.json'), '{"ok":1}')
    [IO.File]::WriteAllText((Join-Path $dir 'informe_cliente.html'), "<p>$Nombre</p>")
    [IO.File]::WriteAllText((Join-Path $e.Ruta 'fotos_recepcion\foto1.jpg'), 'x')
    @{ Exp = (Read-Expediente $e.Ruta); At = $at }
}

try {
    '== Texto del consentimiento'
    $ct = Get-Consentimiento
    Assert 'consentimiento.json con versión, título, 5 párrafos y casillas' ($ct -and $ct.version -match '^\d{4}-\d{2}-\d{2}$' -and @($ct.parrafos).Count -eq 5 -and $ct.casilla_acepto -and $ct.casilla_anual)
    Assert 'dice 18 meses y que no registra contraseñas ni historial' ((@($ct.parrafos) -join ' ') -match '18 meses' -and (@($ct.parrafos) -join ' ') -match 'contraseñas, historial')
    Assert 'config.json: retención de 18 meses' ((Get-MesesRetencion) -eq 18)
    $bytes = [IO.File]::ReadAllBytes((Join-Path $scripts 'config\consentimiento.json'))
    Assert 'consentimiento.json sin BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))

    '== Consentimiento en la ficha'
    $p = New-ExpPrueba 'SERIEJ001' 'Ana Pérez' $hoy
    $e = $p.Exp
    Assert 'la ficha nueva trae los campos vacíos' ($e.Ficha['cliente'].Contains('consentimiento') -and $null -eq $e.Ficha['cliente']['consentimiento'] -and $e.Ficha['cliente'].Contains('aviso_anual'))
    Assert 'sin consentimiento, la ficha no está completa' (@(Test-FichaCompleta -Expediente $e -Atencion $p.At | Where-Object Campo -EQ 'cliente.consentimiento').Count -eq 1)
    Set-Ficha -Expediente $e -Valores @{ 'cliente.consentimiento' = 's'; 'cliente.aviso_anual' = 's' }
    $c = (Read-Expediente $e.Ruta).Ficha['cliente']
    Assert '"s" guarda la fecha de hoy y la versión del texto' ($c['consentimiento'] -eq $hoy -and $c['consentimiento_version'] -eq $ct.version) "$($c['consentimiento']) / $($c['consentimiento_version'])"
    Assert 'aviso anual queda en sí' ($c['aviso_anual'] -eq $true)
    Assert 'con consentimiento ya no lo pide' (@(Test-FichaCompleta -Expediente (Read-Expediente $e.Ruta) -Atencion $p.At | Where-Object Campo -EQ 'cliente.consentimiento').Count -eq 0)
    Set-Ficha -Expediente $e -Valores @{ 'cliente.consentimiento' = '2026-10-01'; 'cliente.consentimiento_version' = '2026-11-21' }
    Assert 'acepta la fecha que trae el remoto' ((Read-Expediente $e.Ruta).Ficha['cliente']['consentimiento'] -eq '2026-10-01')
    Set-Ficha -Expediente $e -Valores @{ 'cliente.consentimiento' = 'n' }
    $c = (Read-Expediente $e.Ruta).Ficha['cliente']
    Assert '"n" lo borra junto con la versión' ($null -eq $c['consentimiento'] -and $null -eq $c['consentimiento_version'])

    '== Retención'
    $viejo = New-ExpPrueba 'SERIEJ002' 'Pedro Soto' '2024-01-10'
    $ent = Get-EntradaAtencion -Expediente $viejo.Exp -Carpeta $viejo.At
    $ent['entregado'] = '2024-01-12'; Save-Ficha -Expediente $viejo.Exp
    Assert 'última atención: la fecha de entrega' ((Get-FechaUltimaAtencion -Expediente (Read-Expediente $viejo.Exp.Ruta)) -eq [datetime]'2024-01-12')
    $rev = @(Get-RevisionDatosPersonales -Clientes $cli -Hoy ([datetime]'2026-11-21') -Meses 18)
    Assert 'entregado hace más de 18 meses: vencido' (@($rev | Where-Object { $_.Vencido -and $_.Id -like '*SERIEJ002' }).Count -eq 1) (($rev | ForEach-Object { "$($_.Id)=$($_.Vencido)/$($_.Abiertas)" }) -join ' ')
    Assert 'con 17 meses todavía no' (@(Get-RevisionDatosPersonales -Clientes $cli -Hoy ([datetime]'2025-06-01') -Meses 18 | Where-Object Vencido).Count -eq 0)
    $rev2 = @(Get-RevisionDatosPersonales -Clientes $cli -Hoy ((Get-Date).AddMonths(30)) -Meses 18)
    Assert 'una atención abierta no vence nunca' (@($rev2 | Where-Object { $_.Id -like '*SERIEJ001' -and -not $_.Vencido }).Count -eq 1)

    '== Anonimizar'
    $n = Clear-DatosCliente -Ruta $viejo.Exp.Ruta -Confirm:$false
    $f = (Read-Expediente $viejo.Exp.Ruta).Ficha
    Assert 'quita nombre, contacto y comuna, y marca la fecha' (-not $f['cliente']['nombre'] -and -not $f['cliente']['contacto'] -and -not $f['cliente']['comuna'] -and $f['cliente']['anonimizado'] -eq $hoy)
    Assert 'quita síntoma y notas, deja el equipo' (-not (Get-ListaAtenciones -Expediente (Read-Expediente $viejo.Exp.Ruta))[0]['sintoma'] -and $f['equipo']['modelo'] -eq 'Inspiron 3493')
    Assert 'borra fotos e informes, deja las mediciones' (-not (Test-Path (Join-Path $viejo.Exp.Ruta 'fotos_recepcion\foto1.jpg')) -and -not (Test-Path (Join-Path $viejo.Exp.Ruta "$($viejo.At)\informe_cliente.html")) -and (Test-Path (Join-Path $viejo.Exp.Ruta "$($viejo.At)\antes\diagnostico.json")) -and $n -eq 2) "borrados: $n"
    Assert 'no queda el respaldo de la ficha con el nombre' (-not (Test-Path (Join-Path $viejo.Exp.Ruta 'ficha.json.bak')))
    $reg = [IO.File]::ReadAllText((Join-Path $cli '_registro_privacidad.csv'))
    Assert 'el registro anota ANONIMIZAR sin nombre ni serie' ($reg -match ';ANONIMIZAR;[0-9a-f]{12};' -and $reg -notmatch 'Pedro|SERIEJ002')

    '== Entregar sus datos'
    $dest = Join-Path $tmp 'entrega'
    $zip = Export-DatosCliente -Ruta $e.Ruta -Destino $dest
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try { $nombres = @($z.Entries | ForEach-Object FullName); $md = (New-Object IO.StreamReader($z.GetEntry('mis_datos.json').Open())).ReadToEnd() } finally { $z.Dispose() }
    Assert 'ZIP con mis_datos.json y su informe' ($nombres -contains 'mis_datos.json' -and @($nombres | Where-Object { $_ -match 'informe_cliente\.html$' }).Count -eq 1) ($nombres -join ', ')
    Assert 'trae su nombre y la serie, y no las notas internas' ($md -match 'Ana P' -and $md -match 'SERIEJ001' -and $md -notmatch 'nota interna')

    '== Olvidar'
    $usb = Join-Path $tmp 'usb\clientes'
    $null = [IO.Directory]::CreateDirectory($usb)
    Copy-Item -LiteralPath $e.Ruta -Destination $usb -Recurse
    Assert 'lo encuentra por el nombre' (@(Find-ExpedienteCliente -Clientes $cli -Texto 'ana pér').Count -eq 1)
    Assert 'y por la serie' (@(Find-ExpedienteCliente -Clientes $cli -Texto 'SERIEJ001').Count -eq 1)
    Remove-ExpedienteCliente -Ruta $e.Ruta -Confirm:$false
    Assert 'el expediente desaparece' (-not (Test-Path $e.Ruta))
    $olv = Get-HuellasOlvidadas -Carpetas $cli
    Assert '_olvidados.txt guarda la huella (no la serie)' ($olv.Contains((Get-HuellaExpediente $e.Id)) -and [IO.File]::ReadAllText((Join-Path $cli '_olvidados.txt')) -notmatch 'SERIEJ001')
    $r = Invoke-Sincronizacion -Clientes $usb -Maestro $cli
    Assert 'la sincronización no lo vuelve a copiar al maestro' (-not (Test-Path (Join-Path $cli $e.Id)) -and $r.Nuevos -eq 0) "nuevos: $($r.Nuevos)"
    Assert 'y lo anota como OLVIDADO en el log' ([IO.File]::ReadAllText($r.Log) -match 'OLVIDADO')

    '== Script datos_personales.ps1'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'datos_personales.ps1') -Carpetas $cli -Hoy ((Get-Date).AddMonths(19)) 2>&1 | Out-String
    Assert 'la revisión cuenta los expedientes' ($out -match 'Expedientes: 1') $out
    $p3 = New-ExpPrueba 'SERIEJ003' 'Rosa Díaz' $hoy
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'datos_personales.ps1') -Carpetas $cli -Olvidar 'Rosa' -Confirmar 2>&1 | Out-String
    Assert '-Olvidar con -Confirmar lo borra' (-not (Test-Path $p3.Exp.Ruta) -and $out -match 'Borrado') $out

    '== Apto para Windows 11'
    $casos = @{ 'Intel(R) Core(TM) i5-10400 CPU @ 2.90GHz' = 'si'; 'Intel(R) Core(TM) i7-7700HQ CPU @ 2.80GHz' = 'no'; 'AMD Ryzen 5 3500U with Radeon Vega Mobile Gfx' = 'si'; 'AMD Ryzen 5 1600 Six-Core Processor' = 'no'; 'AMD Ryzen 3 2200G' = 'revisar'; 'Intel(R) Core(TM) Ultra 7 155H' = 'si'; 'AMD Ryzen AI 9 HX 370' = 'si'; 'Intel(R) Core(TM)2 Duo CPU E8400' = 'no'; '12th Gen Intel(R) Core(TM) i5-12450H' = 'si' }
    $malos = @($casos.Keys | Where-Object { (Test-CpuWindows11 $_) -ne $casos[$_] })
    Assert 'CPU: generaciones de Intel y AMD' (-not $malos.Count) (($malos | ForEach-Object { "$_ -> $(Test-CpuWindows11 $_)" }) -join '; ')
    $script:Ctx.Datos['hardware'] = [pscustomobject]@{ Cpu = @([pscustomobject]@{ Nombre = 'Intel(R) Core(TM) i5-6200U CPU' }); Ram = [pscustomobject]@{ TotalGB = 8 }; Discos = @([pscustomobject]@{ Sistema = $true; TamanoGB = 240 }) }
    $w = Get-AptoWindows11 -SecureBoot ([pscustomobject]@{ Firmware = 'UEFI'; Activo = $false }) -Tpm ([pscustomobject]@{ Presente = $true; Version = '2.0' })
    Assert 'i5 de 6ª generación: no apto por la CPU' ($w.Apto -eq 'No' -and @($w.Faltan) -contains 'Cpu') ($w | ConvertTo-Json -Depth 3 -Compress)
    $script:Ctx.Datos['hardware'] = [pscustomobject]@{ Cpu = @([pscustomobject]@{ Nombre = 'Intel(R) Core(TM) i5-8250U CPU' }); Ram = [pscustomobject]@{ TotalGB = 8 }; Discos = @([pscustomobject]@{ Sistema = $true; TamanoGB = 240 }) }
    $w = Get-AptoWindows11 -SecureBoot ([pscustomobject]@{ Firmware = 'UEFI'; Activo = $false }) -Tpm ([pscustomobject]@{ Presente = $true; Version = '2.0' })
    Assert 'i5 de 8ª con Secure Boot apagado: apto, con la nota de activarlo' ($w.Apto -eq 'Sí' -and $w.Nota -match 'Secure Boot') ($w | ConvertTo-Json -Depth 3 -Compress)
    $w = Get-AptoWindows11 -SecureBoot ([pscustomobject]@{ Firmware = 'Legacy'; Activo = $null }) -Tpm ([pscustomobject]@{ Presente = $true; Version = '1.2' })
    Assert 'BIOS Legacy y TPM 1.2: no apto' ($w.Apto -eq 'No' -and @($w.Faltan) -contains 'Tpm' -and @($w.Faltan) -contains 'Uefi')
    $script:Ctx.Alertas.Clear()
    $script:Ctx.Datos['windows'] = [pscustomobject]@{ Build = 19045 }
    $script:Ctx.Datos['seguridad'] = [pscustomobject]@{ Antivirus = @(); Defender = [pscustomobject]@{ TiempoReal = $true; Disponible = $false }; BitLocker = @(); Vbs = $null; Hipervisor = $null; SecureBoot = $null; Tpm = $null; ControlApps = $null; NombreCifrado = 'BitLocker'; Asr = [pscustomobject]@{ Reglas = @([pscustomobject]@{ Nombre = 'scripts ofuscados'; Modo = 'Bloquear' }); Bloquear = 1; Auditar = 0 }; Windows11 = $w }
    Test-AlertasSeguridad
    $cods = @($script:Ctx.Alertas.ToArray() | ForEach-Object Codigo)
    Assert 'Windows 10 no apto: alerta SEG-WIN11 (aviso)' (@($script:Ctx.Alertas.ToArray() | Where-Object { $_.Codigo -eq 'SEG-WIN11' -and $_.Severidad -eq 'AVISO' }).Count -eq 1) ($cods -join ', ')
    Assert 'reglas ASR bloqueando: alerta SEG-ASR' ($cods -contains 'SEG-ASR')
    $script:Ctx.Alertas.Clear()
    $script:Ctx.Datos['windows'] = [pscustomobject]@{ Build = 26200 }
    Test-AlertasSeguridad
    Assert 'en Windows 11 no avisa nada de la actualización' (@($script:Ctx.Alertas.ToArray() | Where-Object Codigo -EQ 'SEG-WIN11').Count -eq 0)
    $a = Get-AsrKit
    Assert 'Get-AsrKit lee las reglas de este equipo (solo lectura)' ($a -and $null -ne $a.Bloquear)

    '== Remoto'
    $cmd = [IO.File]::ReadAllText((Join-Path $repo 'remoto\paquete\DIAGNOSTICO.cmd'))
    Assert 'DIAGNOSTICO.cmd pasa el consentimiento a remoto.ps1 (ASCII)' ($cmd -match '-Consentimiento "%~3"' -and -not @([IO.File]::ReadAllBytes((Join-Path $repo 'remoto\paquete\DIAGNOSTICO.cmd')) | Where-Object { $_ -gt 127 }).Count)
    $rem = [IO.File]::ReadAllText((Join-Path $repo 'remoto\motor\remoto.ps1'))
    Assert 'remoto.ps1 no sigue sin "Acepto" (código 5) y deja consentimiento.json' ($rem -match 'exit 5' -and $rem -match "consentimiento\.json")
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas FALLA"
if ($script:fallas) { exit 1 }
