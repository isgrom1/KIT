#Requires -Version 5.1
<#
.SYNOPSIS
    Fase N: trabajo remoto. Firma del plan, armar_trabajo.ps1 (paquete), trabajo.ps1 rechazando paquetes
    modificados, de otro equipo o vencidos, y el informe del trabajo (antes -> después, lo hecho).
.DESCRIPTION
    Usa un par de llaves de prueba (nunca la llave de Isaac). Con admin además hace la pasada completa en este
    equipo: aplica una entrada de inicio inventada (HKCU\Run\KitPruebaTrabajo), mide el DESPUÉS, abre el
    .kitdiag con la llave de prueba, arma el informe y deshace. Sin admin, esa parte sale OMITIDA.
    Sin punto de restauración (-PruebaSinPunto): la prueba no llena el equipo de puntos.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $repo 'KIT\scripts'
. (Join-Path $repo 'remoto\motor\Cifrado.ps1')
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Mejoras', 'Informe', 'InformeVisual') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'motivos\lento.ps1')
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:ok = 0; $script:fallas = 0; $script:omitidas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
function Skip-Prueba { param([string]$N) $script:omitidas++; "  OMITIDA $N" }
$ps = Join-Path $PSHOME 'powershell.exe'
function Invoke-Trabajo {
    # Corre trabajo.ps1 de un paquete en otro proceso y devuelve la salida y el código.
    param([string]$Paquete, [string[]]$Argumentos)
    $sal = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Paquete 'motor\trabajo.ps1') @Argumentos 2>&1 | Out-String
    [pscustomobject]@{ Salida = $sal; Codigo = $LASTEXITCODE }
}

$tmp = Join-Path $env:TEMP ('kit_prueba_N_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$llaves = Get-LlavesNuevasRemoto
$ident = Get-IdentidadEquipo
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$aprob = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$clientesReales = $script:Ctx.CarpetaClientes

function New-CarpetaRemota {
    # Imita la carpeta que deja abrir_diagnostico.ps1: diagnostico\<expediente>\<atención>\antes\ con una entrada
    # de inicio inventada que LENTO ofrece desactivar.
    param([string]$Ruta, $Identidad)
    $script:Ctx.CarpetaClientes = Join-Path $Ruta 'diagnostico'
    $null = [IO.Directory]::CreateDirectory($script:Ctx.CarpetaClientes)
    $exp = New-Expediente -Identidad $Identidad
    $at = New-Atencion -Expediente $exp
    $antes = Join-Path (Join-Path $exp.Ruta $at) 'antes'
    $null = [IO.Directory]::CreateDirectory($antes)
    $doc = [ordered]@{
        kit     = [ordered]@{ generado = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); identidad = $Identidad }
        alertas = @(); mejoras = @()
        datos   = [ordered]@{
            equipo    = [ordered]@{ Fabricante = $Identidad.Fabricante; Modelo = $Identidad.Modelo; NombreEquipo = $env:COMPUTERNAME }
            seguridad = [ordered]@{ Antivirus = @() }
            arranque  = [ordered]@{ Entradas = @([ordered]@{ Nombre = 'KitPruebaTrabajo'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Comando = 'C:\Windows\notepad.exe'; Ejecutable = 'C:\Windows\notepad.exe'; Existe = $true; Empresa = 'Prueba SA' }); AppsStore = @(); Servicios = [ordered]@{ Terceros = @() }; Tareas = @() }
            energia   = $null; espacio = [ordered]@{ Volumenes = @() }; gpu_apps = $null; software = [ordered]@{ Detectados = @() }
        }
    }
    [IO.File]::WriteAllText((Join-Path $antes 'diagnostico.json'), ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
    $met = [ordered]@{ arranque = [ordered]@{ disponible = $true; ultimo_seg = 93.2 }; ram = [ordered]@{ usada_gb = 6.9 }; inicio = [ordered]@{ programas_habilitados = 11 }; espacio = @([ordered]@{ sistema = $true; libre_gb = 33.1 }) }
    [IO.File]::WriteAllText((Join-Path $antes 'metricas.json'), ($met | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
    $script:Ctx.CarpetaClientes = $clientesReales
}
function New-PaquetePrueba {
    param([string]$Nombre, $Identidad, [int]$Dias = 7)
    $carpeta = Join-Path $tmp $Nombre
    New-CarpetaRemota -Ruta $carpeta -Identidad $Identidad
    $r = & (Join-Path $repo 'remoto\armar_trabajo.ps1') -Carpeta $carpeta -Elegir '1' -Salida (Join-Path $tmp "salida_$Nombre") -LlavePrivadaXml $llaves.Privada -DiasVigencia $Dias -PassThru 6>$null | Select-Object -Last 1
    # El paquete trae la llave pública de Isaac: para la prueba, la de prueba.
    [IO.File]::WriteAllText((Join-Path $r.Carpeta 'motor\llave_publica.xml'), $llaves.Publica)
    $r
}

try {
    '== Firma'
    $datos = [Text.Encoding]::UTF8.GetBytes('{"plan":1}')
    $firma = Get-FirmaRemoto -Datos $datos -LlavePrivadaXml $llaves.Privada
    Assert 'firma válida' (Test-FirmaRemoto -Datos $datos -Firma $firma -LlavePublicaXml $llaves.Publica)
    Assert 'un cambio en el plan la invalida' (-not (Test-FirmaRemoto -Datos ([Text.Encoding]::UTF8.GetBytes('{"plan":2}')) -Firma $firma -LlavePublicaXml $llaves.Publica))
    Assert 'otra llave no la valida' (-not (Test-FirmaRemoto -Datos $datos -Firma $firma -LlavePublicaXml (Get-LlavesNuevasRemoto).Publica))

    '== Armar el paquete'
    $p = New-PaquetePrueba -Nombre 'bueno' -Identidad $ident
    $plan = [IO.File]::ReadAllText((Join-Path $p.Carpeta 'plan\plan.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert 'ZIP y carpeta, una acción' ([IO.File]::Exists($p.Zip) -and $p.Acciones -eq 1)
    Assert 'trae TRABAJO.cmd, DESHACER.cmd, plan firmado y LENTO' (@(@('TRABAJO.cmd', 'DESHACER.cmd', 'LEEME.txt', 'plan\plan.json', 'plan\plan.firma', 'motor\trabajo.ps1', 'motor\scripts\motivos\lento.ps1', 'motor\scripts\diagnostico.ps1') | Where-Object { -not (Test-Path (Join-Path $p.Carpeta $_)) }).Count -eq 0)
    Assert 'sin config_local.json (contacto de Isaac)' (-not (Test-Path (Join-Path $p.Carpeta 'motor\scripts\config\config_local.json')))
    Assert 'plan amarrado a este equipo, con la acción elegida' ($plan.equipo.serie -eq $ident.Serie -and @($plan.acciones).Count -eq 1 -and $plan.acciones[0].Titulo -match 'KitPruebaTrabajo')
    Assert 'trae el expediente ANTES' (@(Get-ChildItem (Join-Path $p.Carpeta 'plan\clientes') -Recurse -Filter diagnostico.json).Count -eq 1)
    Assert 'TRABAJO.cmd y DESHACER.cmd en ASCII' (@([IO.File]::ReadAllBytes((Join-Path $p.Carpeta 'TRABAJO.cmd')) + [IO.File]::ReadAllBytes((Join-Path $p.Carpeta 'DESHACER.cmd')) | Where-Object { $_ -gt 127 }).Count -eq 0)

    '== trabajo.ps1 rechaza sin tocar nada'
    $mod = Join-Path $tmp 'modificado'
    Copy-Item $p.Carpeta $mod -Recurse
    $txt = [IO.File]::ReadAllText((Join-Path $mod 'plan\plan.json')).Replace('KitPruebaTrabajo', 'KitPruebaOtraCosa')
    [IO.File]::WriteAllText((Join-Path $mod 'plan\plan.json'), $txt, (New-Object Text.UTF8Encoding $false))
    $r = Invoke-Trabajo -Paquete $mod -Argumentos @('-Si', '-Estado', (Join-Path $tmp 'estado_mod'))
    Assert 'plan modificado: no aplica nada' ($r.Codigo -eq 2 -and $r.Salida -match 'firma' -and -not (Test-Path (Join-Path $tmp 'estado_mod'))) $r.Salida
    $otroEq = [pscustomobject]@{ Fabricante = 'Otra'; Modelo = 'Maquina'; Serie = 'SERIE-QUE-NO-ES'; SerieOriginal = 'SERIE-QUE-NO-ES'; Uuid = $null; PlacaSerie = $null }
    $po = New-PaquetePrueba -Nombre 'otro' -Identidad $otroEq
    $r = Invoke-Trabajo -Paquete $po.Carpeta -Argumentos @('-Si', '-Estado', (Join-Path $tmp 'estado_otro'))
    Assert 'paquete de otro equipo: no aplica nada' ($r.Codigo -eq 2 -and $r.Salida -match 'otro computador' -and -not (Test-Path (Join-Path $tmp 'estado_otro'))) $r.Salida
    $pv = New-PaquetePrueba -Nombre 'vencido' -Identidad $ident -Dias -1
    $r = Invoke-Trabajo -Paquete $pv.Carpeta -Argumentos @('-Si', '-Estado', (Join-Path $tmp 'estado_vencido'))
    Assert 'paquete vencido: no aplica nada' ($r.Codigo -eq 2 -and $r.Salida -match 'venci' -and -not (Test-Path (Join-Path $tmp 'estado_vencido'))) $r.Salida

    '== Lo hecho en palabras del cliente'
    $h = @(Get-HechasCliente -Acciones @(
            [pscustomobject]@{ titulo = 'Desactivar al inicio: btweb (BitTorrent Limited)'; deshecha = $null },
            [pscustomobject]@{ titulo = 'Desactivar al inicio (app de la Store): Microsoft Teams'; deshecha = $null },
            [pscustomobject]@{ titulo = 'Desactivar al inicio: Steam (Valve Corporation)'; deshecha = '2026-11-19 10:00:00' },
            [pscustomobject]@{ titulo = 'Desactivar la hibernación (libera 5,6 GB en C:)'; deshecha = $null }))
    Assert 'programas del inicio juntos y con nombre claro' ($h[0] -eq 'Ya no arrancan solos con Windows: BitTorrent Web, Microsoft Teams.') "$($h -join ' | ')"
    Assert 'lo deshecho no aparece' (($h -join ' ') -notmatch 'Steam')
    Assert 'hibernación en palabras simples' (($h -join ' ') -match 'Se recuperaron 5,6 GB en C:')

    '== Pasada completa en este equipo (necesita admin)'
    if (-not $script:Ctx.Admin.Elevado) {
        foreach ($n in 'aplica la acción', 'pide reiniciar', 'mide el DESPUÉS y deja el .kitdiag', 'informe del trabajo para el cliente', 'el .kitdiag se abre con la llave', 'informe del trabajo', 'deshacer') { Skip-Prueba "$n (sin admin)" }
    } else {
        New-ItemProperty -Path $runKey -Name 'KitPruebaTrabajo' -Value 'C:\Windows\notepad.exe' -PropertyType String -Force | Out-Null
        $estado = Join-Path $tmp 'estado'
        $dest = Join-Path $tmp 'destino'
        $r = Invoke-Trabajo -Paquete $p.Carpeta -Argumentos @('-Si', '-Estado', $estado, '-Destino', $dest, '-PruebaSinPunto')
        $bytes = (Get-ItemProperty -Path $aprob -Name 'KitPruebaTrabajo' -ErrorAction SilentlyContinue).KitPruebaTrabajo
        Assert 'aplica la acción (03 en StartupApproved)' ($r.Codigo -eq 0 -and $bytes -and $bytes[0] -eq 3) $r.Salida
        $r2 = Invoke-Trabajo -Paquete $p.Carpeta -Argumentos @('-Si', '-Estado', $estado, '-Destino', $dest)
        Assert 'sin reiniciar pide reiniciar' ($r2.Salida -match 'reinicia') $r2.Salida
        $r3 = Invoke-Trabajo -Paquete (Join-Path $estado '.') -Argumentos @('-Si', '-Estado', $estado, '-Destino', $dest, '-SinReinicio', '-EsperaMin', '0')
        $kd = @(Get-ChildItem $dest -Filter 'Trabajo_para_Isaac_*.kitdiag' -ErrorAction SilentlyContinue)
        Assert 'mide el DESPUÉS (desde la copia en el perfil) y deja el .kitdiag' ($r3.Codigo -eq 0 -and $kd.Count -eq 1) $r3.Salida
        $infC = @(Get-ChildItem $dest -Filter 'Informe_del_trabajo_*.html' -ErrorAction SilentlyContinue)
        $txtC = if ($infC.Count) { [Net.WebUtility]::HtmlDecode([IO.File]::ReadAllText($infC[0].FullName)) } else { '' }
        Assert 'deja el informe del trabajo para el cliente (sin propuesta)' ($infC.Count -eq 1 -and $txtC -match 'Lo que hicimos y cómo cambió' -and $txtC -match 'Lo que sigue' -and $txtC -notmatch 'Lo que te propongo') $r3.Salida
        $abierto = Join-Path $tmp 'abierto'
        $zipBytes = Unprotect-DatosRemoto -Datos ([IO.File]::ReadAllBytes($kd[0].FullName)) -LlavePrivadaXml $llaves.Privada
        $null = [IO.Directory]::CreateDirectory($abierto)
        $ms = New-Object IO.MemoryStream (, $zipBytes)
        $za = New-Object IO.Compression.ZipArchive ($ms, [IO.Compression.ZipArchiveMode]::Read)
        foreach ($e in $za.Entries) { $dd = Join-Path $abierto $e.FullName; $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $dd)); [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dd, $true) }
        $za.Dispose(); $ms.Dispose()
        $despues = @(Get-ChildItem $abierto -Recurse -Filter diagnostico.json | Where-Object { $_.Directory.Name -eq 'despues' }) | Select-Object -First 1
        $lento = @(Get-ChildItem $abierto -Recurse -Filter lento_acciones.json) | Select-Object -First 1
        Assert 'el .kitdiag trae ANTES, DESPUÉS y lo aplicado' ($despues -and $lento -and @(Get-ChildItem $abierto -Recurse -Filter metricas.json).Count -eq 2)
        $res = Get-ResultadoTrabajo -RutaAtencion $despues.Directory.Parent.FullName
        $html = [Net.WebUtility]::HtmlDecode((ConvertTo-InformeVisual -Doc (Read-JsonKit $despues.FullName) -DocAntes (Read-JsonKit (Join-Path $despues.Directory.Parent.FullName 'antes\diagnostico.json')) -Resultado $res))
        Assert 'informe del trabajo: antes -> después y lo hecho' ($html -match 'Lo que hicimos y cómo cambió' -and $html -match 'Programas al inicio' -and $html -match 'KitPruebaTrabajo') ($res.Hechas -join ' | ')
        $r4 = Invoke-Trabajo -Paquete $estado -Argumentos @('-Deshacer', '-Estado', $estado)
        Assert 'deshacer deja el inicio como estaba' ($r4.Codigo -eq 0 -and $null -eq (Get-ItemProperty -Path $aprob -Name 'KitPruebaTrabajo' -ErrorAction SilentlyContinue)) $r4.Salida
    }
} catch {
    "  ERROR: $($_.Exception.Message) (línea $($_.InvocationInfo.ScriptLineNumber))"
    $script:fallas++
} finally {
    $script:Ctx.CarpetaClientes = $clientesReales
    Remove-ItemProperty -Path $runKey -Name 'KitPruebaTrabajo' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $aprob -Name 'KitPruebaTrabajo' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"  limpieza: Run=$($null -ne (Get-ItemProperty $runKey -Name KitPruebaTrabajo -ErrorAction SilentlyContinue)) Aprob=$($null -ne (Get-ItemProperty $aprob -Name KitPruebaTrabajo -ErrorAction SilentlyContinue))"
''
"Resultado: $script:ok OK, $script:fallas fallas$(if ($script:omitidas) { ", $script:omitidas omitidas" }) ($($script:ok + $script:fallas) comprobaciones)"
if ($script:fallas) { exit 1 }
exit 0
