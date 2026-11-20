#Requires -Version 5.1
<#
.SYNOPSIS
    Trabajo remoto: aplica en el equipo del cliente las acciones que Isaac eligió (plan firmado), con punto de
    restauración y deshacer, y después del reinicio mide el DESPUÉS y deja un .kitdiag cifrado para Isaac.
.DESCRIPTION
    1ª vez (TRABAJO.cmd): verifica la firma del plan, que sea este equipo y que no esté vencido; muestra lo que
       va a cambiar y pide confirmar; punto de restauración; aplica con el motor de LENTO (guarda el valor
       anterior de cada cambio); deja todo en %USERPROFILE%\Diagnostico_para_Isaac\Trabajo_<id> con DESHACER.cmd.
    2ª vez, después de reiniciar: espera 5 min desde el encendido, diagnóstico DESPUÉS y .kitdiag cifrado.
    -Deshacer (DESHACER.cmd): deshace todo lo aplicado, de lo último a lo primero.
    Solo conoce las acciones de LENTO: nunca toca antivirus, Seguridad de Windows ni archivos del cliente.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Consola para el cliente')]
[CmdletBinding()]
param(
    [switch]$Deshacer,
    [switch]$Si,                 # no preguntar (pruebas)
    [string]$Estado,             # carpeta de estado (pruebas); por defecto en el perfil del usuario
    [string]$Destino,            # dónde dejar el .kitdiag (pruebas)
    [double]$EsperaMin = 5,      # minutos desde el encendido antes de medir
    [switch]$SinReinicio,        # medir sin exigir reinicio (pruebas)
    [switch]$PruebaSinPunto      # sin punto de restauración (solo pruebas: no llenar el equipo de puntos)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$motor = $PSScriptRoot
$raiz = Split-Path -Parent $motor
$scripts = Join-Path $motor 'scripts'
. (Join-Path $motor 'Cifrado.ps1')
function Write-Titulo([string]$Texto) { Write-Host ''; Write-Host " $Texto" -ForegroundColor Cyan }
function Exit-Trabajo([string]$Texto, [int]$Codigo = 2) { Write-Host ''; Write-Host " $Texto" -ForegroundColor Red; exit $Codigo }

$Host.UI.RawUI.WindowTitle = 'Trabajo de Isaac en tu computador - no cierres esta ventana'
Get-ChildItem -LiteralPath $raiz -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

# 0. Firma de Isaac sobre todo el paquete (también en la copia del perfil, que trae su manifiesto).
$verif = Test-ManifiestoPaquete -Raiz $raiz
if (-not $verif.Ok) { Exit-Trabajo "Este paquete no es de Isaac o fue modificado (la firma no coincide): no se aplica nada. $($verif.Motivo)" 3 }

# 1. Plan: firma, equipo y vigencia.
$rutaPlan = Join-Path $raiz 'plan\plan.json'
$rutaFirma = Join-Path $raiz 'plan\plan.firma'
if (-not [IO.File]::Exists($rutaPlan) -or -not [IO.File]::Exists($rutaFirma)) { Exit-Trabajo 'Falta el plan del trabajo: pídele a Isaac el paquete de nuevo.' }
$bytesPlan = [IO.File]::ReadAllBytes($rutaPlan)
$firmaOk = $false
try { $firmaOk = Test-FirmaRemoto -Datos $bytesPlan -Firma ([Convert]::FromBase64String([IO.File]::ReadAllText($rutaFirma).Trim())) -LlavePublicaXml ([IO.File]::ReadAllText((Join-Path $motor 'llave_publica.xml'))) } catch { $firmaOk = $false }
if (-not $firmaOk) { Exit-Trabajo 'El plan no tiene la firma de Isaac o fue modificado: no se aplica nada.' }
$plan = (New-Object Text.UTF8Encoding $false).GetString($bytesPlan) | ConvertFrom-Json
if ($plan.formato -ne 'KITTRABAJO1') { Exit-Trabajo 'Formato de plan desconocido: pídele a Isaac un paquete nuevo.' }

foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'motivos\lento.ps1')
Initialize-Contexto -RaizScripts $scripts
$script:Ctx.Admin = Get-EstadoAdmin
$ident = Get-IdentidadEquipo
$mismo = ($plan.equipo.serie -and $ident.Serie -eq $plan.equipo.serie) -or (-not $plan.equipo.serie -and $plan.equipo.uuid -and $ident.Uuid -eq $plan.equipo.uuid)
if (-not $mismo) { Exit-Trabajo "Este paquete es para otro computador ($($plan.equipo.fabricante) $($plan.equipo.modelo), $($plan.equipo.nombre)): no se aplica nada." }

if (-not $Estado) { $Estado = Join-Path $env:USERPROFILE ('Diagnostico_para_Isaac\Trabajo_' + $plan.id.Substring(0, 8)) }
$rutaEstado = Join-Path $Estado 'estado.json'
$estadoActual = if ([IO.File]::Exists($rutaEstado)) { Read-JsonKit $rutaEstado } else { $null }
$script:Ctx.CarpetaClientes = Join-Path $Estado 'clientes'
Initialize-Privacidad
$identExp = [pscustomobject]@{ Fabricante = $plan.equipo.fabricante; Modelo = $plan.equipo.modelo; Serie = $plan.equipo.serie; SerieOriginal = $plan.equipo.serie; Uuid = $plan.equipo.uuid; PlacaSerie = $null }
$vence = [datetime]::ParseExact($plan.vence, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
$primeraVez = -not $estadoActual -or $estadoActual.fase -eq 'deshecho'
if (-not $Deshacer -and $primeraVez -and (Get-Date) -gt $vence) { Exit-Trabajo "Este paquete venció el $($plan.vence): pídele a Isaac uno nuevo." }
# Todo lo anterior solo lee: un paquete ajeno, modificado o vencido se rechaza antes de pedir nada.
if (-not $script:Ctx.Admin.Elevado) { Exit-Trabajo 'Hay que abrirlo con TRABAJO.cmd y aceptar el permiso de administrador.' }

function Save-Estado([hashtable]$Valores) {
    $e = [ordered]@{}
    if ($estadoActual) { foreach ($p in $estadoActual.PSObject.Properties) { $e[$p.Name] = $p.Value } }
    foreach ($k in $Valores.Keys) { $e[$k] = $Valores[$k] }
    [IO.File]::WriteAllText($rutaEstado, ($e | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
    $script:estadoActual = [pscustomobject]$e
}

# ---------------------------------------------------------------- deshacer
if ($Deshacer) {
    if (-not $estadoActual) { Exit-Trabajo 'No hay nada aplicado en este computador con este paquete.' 0 }
    $exp = Get-Expediente -Identidad $identExp
    Write-Titulo 'Deshaciendo los cambios de Isaac'
    $hechas = @(Undo-AccionesLento -Expediente $exp -Atencion $plan.atencion)
    foreach ($h in $hechas) { Write-Host "  - deshecho: $h" }
    Save-Estado @{ fase = 'deshecho'; deshecho = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
    Write-Host ''
    Write-Host " Listo: se deshicieron $($hechas.Count) cambios. Reinicia el computador para que se note." -ForegroundColor Green
    exit 0
}

$arranque = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime

# ---------------------------------------------------------------- 1ª vez: aplicar
if ($primeraVez) {
    Write-Host ''
    Write-Host ' TRABAJO DE ISAAC EN TU COMPUTADOR' -ForegroundColor Cyan
    Write-Host ' Estos son los cambios que Isaac preparó para este equipo:' -ForegroundColor Gray
    foreach ($a in @($plan.acciones)) { Write-Host "  - $($a.Titulo)"; Write-Host "      $($a.QueHace)" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ' Antes se crea un punto de restauración de Windows, y todo se puede deshacer con DESHACER.cmd.' -ForegroundColor Gray
    if (-not $Si) {
        $r = Read-Host ' Escribe SI y presiona Enter para aplicar (cualquier otra cosa cancela)'
        if ("$r".Trim() -notmatch '^(?i)s[ií]$') { Exit-Trabajo 'Cancelado: no se cambió nada.' 0 }
    }
    # Estado: el expediente ANTES del paquete, el motor y los .cmd (para deshacer aunque se borre el paquete).
    # Copy-Item de una carpeta a otra que ya existe la mete adentro: solo se copia lo que falta (al volver a
    # aplicar después de deshacer, el expediente con lo ya hecho se conserva).
    $null = [IO.Directory]::CreateDirectory($Estado)
    if (-not [IO.Directory]::Exists((Join-Path $Estado 'plan'))) { Copy-Item -LiteralPath (Join-Path $raiz 'plan') -Destination $Estado -Recurse }
    if (-not [IO.Directory]::Exists((Join-Path $Estado 'clientes'))) { Copy-Item -LiteralPath (Join-Path $raiz 'plan\clientes') -Destination $Estado -Recurse }
    if (-not [IO.Directory]::Exists((Join-Path $Estado 'motor'))) { Copy-Item -LiteralPath $motor -Destination $Estado -Recurse }
    foreach ($f in 'TRABAJO.cmd', 'DESHACER.cmd', 'LEEME.txt') { $o = Join-Path $raiz $f; if ([IO.File]::Exists($o)) { Copy-Item -LiteralPath $o -Destination $Estado -Force } }
    $exp = Get-Expediente -Identidad $identExp
    if (-not $exp) { Exit-Trabajo 'No se encontró el expediente del equipo dentro del paquete.' }
    $acc = @($plan.acciones | ForEach-Object { ConvertTo-AccionLento -Id $_.Id -Tipo $_.Tipo -Titulo $_.Titulo -QueHace $_.QueHace -Deshacer $_.Deshacer -Admin ([bool]$_.RequiereAdmin) -Riesgo $_.Riesgo -Datos (ConvertTo-Diccionario $_.Datos) })
    Write-Titulo '1/2 Aplicando los cambios'
    $hechas = $null
    try {
        $hechas = @(Invoke-AccionesLento -Expediente $exp -Atencion $plan.atencion -Acciones $acc -SinPuntoRestauracion:$PruebaSinPunto)
    } catch {
        if ("$($_.Exception.Message)".StartsWith($script:PrefijoSinPunto) -and $plan.permitir_sin_punto) {
            Write-Host "  Windows no dejó crear el punto de restauración; Isaac autorizó seguir igual." -ForegroundColor Yellow
            $hechas = @(Invoke-AccionesLento -Expediente $exp -Atencion $plan.atencion -Acciones $acc -SinPuntoRestauracion)
        } elseif ("$($_.Exception.Message)".StartsWith($script:PrefijoSinPunto)) {
            Exit-Trabajo "Windows no deja crear el punto de restauración ($("$($_.Exception.Message)".Substring($script:PrefijoSinPunto.Length))). No se cambió nada: avísale a Isaac."
        } else { throw }
    }
    foreach ($h in $hechas) { Write-Host "  - hecho: $h" -ForegroundColor Green }
    Save-Estado @{ fase = 'aplicado'; plan = $plan.id; aplicado = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); arranque = $arranque.ToString('yyyy-MM-dd HH:mm:ss') }
    Write-Host ''
    Write-Host ' LISTO LA PRIMERA PARTE.' -ForegroundColor Green
    Write-Host ' Ahora REINICIA el computador y, cuando vuelva, abre otra vez TRABAJO.cmd para la medición final' -ForegroundColor Yellow
    Write-Host " (también está en $Estado)." -ForegroundColor Yellow
    if (-not $Si) { Start-Process explorer.exe -ArgumentList "`"$Estado`"" }
    exit 0
}

if ($estadoActual.fase -eq 'terminado') {
    Write-Host ''
    Write-Host " Este trabajo ya terminó. El archivo para Isaac es: $($estadoActual.archivo)" -ForegroundColor Green
    Write-Host " Si quieres volver atrás, abre DESHACER.cmd en $Estado." -ForegroundColor Gray
    exit 0
}

# ---------------------------------------------------------------- 2ª vez: medir el DESPUÉS
$aplicadoArranque = [datetime]::ParseExact($estadoActual.arranque, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
if (-not $SinReinicio -and $arranque -le $aplicadoArranque.AddSeconds(30)) {
    Exit-Trabajo 'Falta reiniciar: reinicia el computador y vuelve a abrir TRABAJO.cmd.' 0
}
$minutos = ((Get-Date) - $arranque).TotalMinutes
if ($minutos -lt $EsperaMin) {
    $faltan = [int][math]::Ceiling(($EsperaMin - $minutos) * 60)
    Write-Titulo "Esperando que Windows termine de encender ($([math]::Ceiling($faltan / 60)) min). No uses el computador."
    for ($s = $faltan; $s -gt 0; $s -= 10) { Write-Host ("`r  faltan {0,3} s " -f $s) -NoNewline; Start-Sleep -Seconds ([math]::Min(10, $s)) }
    Write-Host ''
}
Write-Titulo '2/2 Midiendo cómo quedó'
$ps = Join-Path $PSHOME 'powershell.exe'
$ErrorActionPreference = 'Continue'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'diagnostico.ps1') -Clientes (Join-Path $Estado 'clientes') -Momento Despues -Atencion $plan.atencion -SinEspacio 2>&1 |
    Tee-Object -FilePath (Join-Path $Estado 'diagnostico_despues.log') | Out-Host
$codDiag = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($codDiag -ne 0) { Write-Host "  El diagnóstico terminó con código $codDiag; se manda igual." -ForegroundColor Yellow }

# .kitdiag cifrado: el expediente (antes, después, lo aplicado) y los logs.
if (-not $Destino) {
    $Destino = [Environment]::GetFolderPath('Desktop')
    $raicesOd = @(@($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ })
    if (@($raicesOd | Where-Object { $Destino.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }).Count) { $Destino = Split-Path -Parent $Estado }
}
$ms = New-Object IO.MemoryStream
$za = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
foreach ($f in @(Get-ChildItem -LiteralPath $Estado -Recurse -File | Where-Object { $_.FullName -notmatch '\\(motor|plan)\\' -and $_.Extension -ne '.cmd' })) {
    $rel = $f.FullName.Substring($Estado.TrimEnd('\').Length + 1)
    $e = $za.CreateEntry($rel)
    $s = $e.Open(); $b = [IO.File]::ReadAllBytes($f.FullName); $s.Write($b, 0, $b.Length); $s.Dispose()
}
$za.Dispose()
$cifrado = Protect-DatosRemoto -Datos $ms.ToArray() -LlavePublicaXml ([IO.File]::ReadAllText((Join-Path $motor 'llave_publica.xml')))
$ms.Dispose()
$null = [IO.Directory]::CreateDirectory($Destino)
$archivo = Join-Path $Destino ("Trabajo_para_Isaac_{0}_{1}.kitdiag" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
[IO.File]::WriteAllBytes($archivo, $cifrado)
Save-Estado @{ fase = 'terminado'; terminado = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); archivo = $archivo }

# Informe del trabajo para el cliente (antes y después, sin propuesta ni precios). Si falla, el .kitdiag ya está.
$informe = $null
try {
    $todos = @(Get-ChildItem -LiteralPath (Join-Path $Estado 'clientes') -Recurse -Filter 'diagnostico.json' -ErrorAction SilentlyContinue)
    $jAntes = @($todos | Where-Object { $_.Directory.Name -eq 'antes' }) | Select-Object -First 1
    $jDespues = @($todos | Where-Object { $_.Directory.Name -eq 'despues' }) | Select-Object -First 1
    if ($jAntes -and $jDespues) {
        foreach ($lib in 'Sensores', 'Mejoras', 'Informe', 'InformeVisual') { . (Join-Path $scripts "lib\$lib.ps1") }
        $informe = Export-InformeCliente -Diagnostico $jDespues.FullName -Antes $jAntes.FullName -RutaAtencion $jAntes.Directory.Parent.FullName -Salida (Join-Path $Destino ("Informe_del_trabajo_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmm')))
    }
} catch { Write-Host " (No se pudo armar tu informe: $($_.Exception.Message). El archivo para Isaac está bien.)" -ForegroundColor Gray }

Write-Host ''
Write-Host ' LISTO.' -ForegroundColor Green
Write-Host ' Mándale a Isaac este archivo (por WhatsApp o correo):' -ForegroundColor Green
Write-Host "   $archivo"
if ($informe) {
    Write-Host ''
    Write-Host ' Y este es tu informe (se abre en el navegador): qué se hizo y cómo cambió tu equipo.' -ForegroundColor Cyan
    Write-Host "   $informe"
}
Write-Host " Si algo no te gusta, DESHACER.cmd (en $Estado) vuelve todo atrás." -ForegroundColor Gray
if (-not $Si) {
    Start-Process explorer.exe -ArgumentList "/select,`"$archivo`""
    if ($informe) { Start-Process $informe }
}
exit 0
