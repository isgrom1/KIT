#Requires -Version 5.1
<#
.SYNOPSIS
    Arma un paquete de TRABAJO REMOTO a partir de un diagnóstico remoto ya abierto (en el PC de Isaac).
.DESCRIPTION
    Muestra las acciones de LENTO que corresponden a ese equipo (ninguna marcada), el técnico elige, y deja en
    remoto\_salida\Trabajo_<equipo>_<fecha>.zip un paquete chico con:
      TRABAJO.cmd, DESHACER.cmd y LEEME.txt (remoto\paquete_trabajo),
      motor\ (trabajo.ps1, Cifrado.ps1, llave_publica.xml y el motor del kit con motivos\lento.ps1),
      plan\plan.json + plan.firma (firmado con la llave privada de Isaac) y el expediente ANTES del equipo.
    El plan queda amarrado a ese equipo (serie y UUID) y vence en -DiasVigencia días.
.PARAMETER Carpeta
    La carpeta que dejó abrir_diagnostico.ps1 al abrir el .kitdiag.
.PARAMETER Elegir
    Números de las acciones separados por coma (para no preguntar). Sin esto, pregunta.
.PARAMETER PermitirSinPunto
    Si Windows no deja crear el punto de restauración en el equipo, aplica igual. Por defecto no aplica nada.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remoto\armar_trabajo.ps1 -Carpeta "D:\Diagnostico_para_Isaac_BELI_20261119_1600"
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para Isaac')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'ProtectedData viene con .NET Framework y se carga con Add-Type -AssemblyName System.Security')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Carpeta,
    [string]$Elegir,
    [switch]$PermitirSinPunto,
    [int]$DiasVigencia = 7,
    [string]$Salida,
    [string]$LlavePrivadaXml   # solo para pruebas; lo normal es la llave del PC (DPAPI)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not $Salida) { $Salida = Join-Path $PSScriptRoot '_salida' }
$kitScripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
. (Join-Path $PSScriptRoot 'motor\Cifrado.ps1')
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $kitScripts "lib\$lib.ps1") }
. (Join-Path $kitScripts 'motivos\lento.ps1')
Initialize-Contexto -RaizScripts $kitScripts

# Expediente del diagnóstico remoto: <Carpeta>\diagnostico\<id>\<atención>\antes\diagnostico.json
$clientes = Join-Path $Carpeta 'diagnostico'
$json = @(Get-ChildItem -LiteralPath $clientes -Recurse -Filter diagnostico.json -ErrorAction Stop | Where-Object { $_.Directory.Name -eq 'antes' }) | Select-Object -First 1
if (-not $json) { throw "No encontré el diagnóstico ANTES en $clientes" }
$atencion = $json.Directory.Parent.Name
$rutaExp = $json.Directory.Parent.Parent.FullName
$script:Ctx.CarpetaClientes = $clientes
$exp = Read-Expediente $rutaExp
$doc = Read-JsonKit $json.FullName
$ident = $doc.kit.identidad

$acciones = @(Get-AccionesLento -Expediente $exp -Atencion $atencion | Where-Object { $_.Tipo -ne 'manual' })
if (-not $acciones.Count) { throw 'Para este equipo no hay acciones de LENTO que se puedan aplicar a distancia.' }
Write-Host ''
Write-Host " Trabajo remoto para $($ident.Fabricante) $($ident.Modelo) ($($doc.datos.equipo.NombreEquipo))" -ForegroundColor Cyan
Write-Host ' Ninguna viene marcada. [admin] la aplica igual (TRABAJO.cmd pide admin); [revisar] = confírmalo con el cliente.' -ForegroundColor DarkGray
for ($i = 0; $i -lt $acciones.Count; $i++) {
    $a = $acciones[$i]
    $marcas = @(); if ($a.RequiereAdmin) { $marcas += 'admin' }; if ($a.Riesgo -eq 'revisar') { $marcas += 'revisar' }
    Write-Host ('  {0,2}) {1}{2}' -f ($i + 1), $a.Titulo, $(if ($marcas) { "  [$($marcas -join ', ')]" } else { '' })) -ForegroundColor $(if ($a.Riesgo -eq 'revisar') { 'Yellow' } else { 'Gray' })
}
if (-not $Elegir) { $Elegir = Read-Host ' Números de las acciones (ej. 1,3,4)' }
$nums = @("$Elegir" -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Select-Object -Unique)
$malos = @($nums | Where-Object { $_ -lt 1 -or $_ -gt $acciones.Count })
if ($malos.Count -or -not $nums.Count) { throw "Selección no válida: '$Elegir'" }
$elegidas = @($nums | ForEach-Object { $acciones[$_ - 1] })

# Plan firmado
$ahora = Get-Date
$plan = [ordered]@{
    formato            = 'KITTRABAJO1'
    id                 = [guid]::NewGuid().ToString('N')
    creado             = $ahora.ToString('yyyy-MM-dd HH:mm:ss')
    vence              = $ahora.AddDays($DiasVigencia).ToString('yyyy-MM-dd HH:mm:ss')
    equipo             = [ordered]@{ fabricante = $ident.Fabricante; modelo = $ident.Modelo; serie = $ident.Serie; uuid = $ident.Uuid; nombre = $doc.datos.equipo.NombreEquipo }
    expediente         = Split-Path -Leaf $rutaExp
    atencion           = $atencion
    permitir_sin_punto = [bool]$PermitirSinPunto
    acciones           = @($elegidas | ForEach-Object { [ordered]@{ Id = $_.Id; Tipo = $_.Tipo; Titulo = $_.Titulo; QueHace = $_.QueHace; Deshacer = $_.Deshacer; RequiereAdmin = $_.RequiereAdmin; Riesgo = $_.Riesgo; Datos = $_.Datos } })
}
$bytesPlan = (New-Object Text.UTF8Encoding $false).GetBytes(($plan | ConvertTo-Json -Depth 8))
if (-not $LlavePrivadaXml) {
    $privada = Join-Path $env:LOCALAPPDATA 'kitservicio\remoto_llave_privada.dat'
    if (-not [IO.File]::Exists($privada)) { throw "No está la llave privada en este PC ($privada)." }
    $LlavePrivadaXml = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($privada), $null, 'CurrentUser'))
}
$firma = Get-FirmaRemoto -Datos $bytesPlan -LlavePrivadaXml $LlavePrivadaXml
$LlavePrivadaXml = $null

# Paquete
$nombre = 'Trabajo_{0}_{1}' -f (Get-NombreArchivo "$($doc.datos.equipo.NombreEquipo)" 20), $ahora.ToString('yyyyMMdd_HHmm')
$dir = Join-Path $Salida $nombre
if ([IO.Directory]::Exists($dir)) { Remove-Item -LiteralPath $dir -Recurse -Force }
$motor = Join-Path $dir 'motor'
$null = [IO.Directory]::CreateDirectory($motor)
foreach ($f in 'TRABAJO.cmd', 'DESHACER.cmd', 'LEEME.txt') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "paquete_trabajo\$f") -Destination $dir }
foreach ($f in 'trabajo.ps1', 'Cifrado.ps1') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "motor\$f") -Destination $motor }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'llave_publica.xml') -Destination $motor
$dScripts = Join-Path $motor 'scripts'
$null = [IO.Directory]::CreateDirectory($dScripts)
Copy-Item -LiteralPath (Join-Path $kitScripts 'diagnostico.ps1') -Destination $dScripts
foreach ($sub in 'lib', 'secciones', 'config', 'motivos') { Copy-Item -LiteralPath (Join-Path $kitScripts $sub) -Destination $dScripts -Recurse }
Remove-Item -LiteralPath (Join-Path $dScripts 'config\config_local.json') -Force -ErrorAction SilentlyContinue
$dPlan = Join-Path $dir 'plan'
$null = [IO.Directory]::CreateDirectory($dPlan)
[IO.File]::WriteAllBytes((Join-Path $dPlan 'plan.json'), $bytesPlan)
[IO.File]::WriteAllText((Join-Path $dPlan 'plan.firma'), [Convert]::ToBase64String($firma), [Text.Encoding]::ASCII)
# Expediente ANTES (ficha + diagnóstico y métricas): en el equipo, el DESPUÉS se mide contra esto.
$dExp = Join-Path (Join-Path $dPlan 'clientes') (Split-Path -Leaf $rutaExp)
$null = [IO.Directory]::CreateDirectory((Join-Path (Join-Path $dExp $atencion) 'antes'))
Copy-Item -LiteralPath (Join-Path $rutaExp 'ficha.json') -Destination $dExp
foreach ($f in 'diagnostico.json', 'metricas.json') { $o = Join-Path $json.Directory.FullName $f; if ([IO.File]::Exists($o)) { Copy-Item -LiteralPath $o -Destination (Join-Path (Join-Path $dExp $atencion) 'antes') } }

$zip = "$dir.zip"
if ([IO.File]::Exists($zip)) { Remove-Item -LiteralPath $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($dir, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host ''
Write-Host (" Listo: {0} ({1:N1} MB), {2} acciones, vence el {3}" -f $zip, ((Get-Item -LiteralPath $zip).Length / 1MB), $elegidas.Count, $plan.vence) -ForegroundColor Green
Write-Host ' Mándaselo al cliente: lo descomprime y abre TRABAJO.cmd. Después te devuelve un archivo .kitdiag.' -ForegroundColor Gray
[pscustomobject]@{ Zip = $zip; Carpeta = $dir; Plan = $plan.id; Acciones = $elegidas.Count }
