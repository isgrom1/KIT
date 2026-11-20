#Requires -Version 5.1
<#
.SYNOPSIS
    Arma el ZIP del diagnóstico remoto para mandárselo a un familiar o cliente (en el PC de Isaac).
.DESCRIPTION
    Junta en remoto\_salida\Diagnostico_remoto\:
      DIAGNOSTICO.cmd y LEEME.txt (remoto\paquete),
      motor\ (remoto.ps1, calor.ps1, Cifrado.ps1, llave_publica.xml),
      motor\scripts\ (el motor del kit, sin la interfaz ni config_local.json con el contacto de Isaac),
      herramientas\OCCT y herramientas\HWiNFO (con la prueba fija de OCCT y sin datos de este PC),
    y lo comprime en remoto\_salida\Diagnostico_remoto_<fecha>.zip. remoto\_salida no va a GitHub.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remoto\armar_paquete.ps1 -Herramientas D:\KIT\herramientas
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para Isaac')]
[CmdletBinding()]
param(
    [string]$Herramientas,
    [string]$Salida,
    [string]$LlavePrivadaXml   # solo para pruebas; lo normal es la llave del PC (DPAPI)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
# $PSScriptRoot no siempre está listo en los valores por defecto de param() en 5.1.
if (-not $Herramientas) { $Herramientas = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\herramientas' }
if (-not $Salida) { $Salida = Join-Path $PSScriptRoot '_salida' }
$kitScripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
$llave = Join-Path $PSScriptRoot 'llave_publica.xml'
if (-not [IO.File]::Exists($llave)) { throw 'Falta remoto\llave_publica.xml: corre primero remoto\crear_llaves.ps1.' }
foreach ($x in 'OCCT\OCCT.exe', 'OCCT\OCCT.config.json', 'HWiNFO\HWiNFO64.exe') {
    if (-not [IO.File]::Exists((Join-Path $Herramientas $x))) { throw "Falta $x en $Herramientas (OCCT.config.json aparece después de abrir OCCT una vez y aceptar su licencia)." }
}

$dir = Join-Path $Salida 'Diagnostico_remoto'
if ([IO.Directory]::Exists($dir)) { Remove-Item -LiteralPath $dir -Recurse -Force }
$motor = Join-Path $dir 'motor'
$null = [IO.Directory]::CreateDirectory($motor)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'paquete\DIAGNOSTICO.cmd'), (Join-Path $PSScriptRoot 'paquete\LEEME.txt') -Destination $dir
foreach ($f in 'remoto.ps1', 'calor.ps1', 'Cifrado.ps1', 'bienvenida.ps1') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "motor\$f") -Destination $motor }
Copy-Item -LiteralPath $llave -Destination $motor

# Motor del kit: lo que necesita diagnostico.ps1, sin la interfaz ni los datos propios de Isaac.
$dScripts = Join-Path $motor 'scripts'
$null = [IO.Directory]::CreateDirectory($dScripts)
Copy-Item -LiteralPath (Join-Path $kitScripts 'diagnostico.ps1') -Destination $dScripts
foreach ($sub in 'lib', 'secciones', 'config') { Copy-Item -LiteralPath (Join-Path $kitScripts $sub) -Destination $dScripts -Recurse }
Remove-Item -LiteralPath (Join-Path $dScripts 'config\config_local.json') -Force -ErrorAction SilentlyContinue

# Herramientas: OCCT completo (sin respaldos) y solo HWiNFO de 64 bits con su INI.
$dHerr = Join-Path $dir 'herramientas'
$null = [IO.Directory]::CreateDirectory($dHerr)   # sin esto Copy-Item copia OCCT *como* "herramientas"
Copy-Item -LiteralPath (Join-Path $Herramientas 'OCCT') -Destination $dHerr -Recurse
Get-ChildItem -LiteralPath (Join-Path $dHerr 'OCCT') -Recurse -File -Filter '*.bak' | Remove-Item -Force
$dHw = Join-Path $dHerr 'HWiNFO'
$null = [IO.Directory]::CreateDirectory($dHw)
foreach ($f in 'HWiNFO64.exe', 'HWiNFO64.INI') { $o = Join-Path $Herramientas "HWiNFO\$f"; if ([IO.File]::Exists($o)) { Copy-Item -LiteralPath $o -Destination $dHw } }

# Prueba fija de OCCT y fuera los datos de este PC (carpeta de informes con el usuario, placa madre).
foreach ($lib in 'Comun', 'Log', 'Herramientas') { . (Join-Path $kitScripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $kitScripts
$r = Set-ConfigOcct -Carpeta (Join-Path $dHerr 'OCCT') -Base (Join-Path $kitScripts 'config\occt_prueba.json')
Get-ChildItem -LiteralPath (Join-Path $dHerr 'OCCT') -Recurse -File -Filter '*.bak' | Remove-Item -Force
Write-Host "Prueba fija de OCCT: $($r.Estado) ($($r.Cambios) cambios)"
if ($r.NoEncontrados) { Write-Host "  No encontrados en OCCT.config.json: $($r.NoEncontrados -join ', ')" -ForegroundColor Yellow }

# Clave de los códigos por cliente (privado\clave_codigos.dat, fuera del repo): la ventana valida con ella.
. (Join-Path $PSScriptRoot 'motor\Cifrado.ps1')
$rutaClave = Get-RutaClaveCodigo -Repo (Split-Path -Parent $PSScriptRoot) -Crear
if (-not $rutaClave) { throw 'No está la carpeta del maestro (config.json, sincronizacion.ruta_maestro): ahí va la clave de los códigos.' }
$cfgRem = (Get-Content -LiteralPath (Join-Path $kitScripts 'config\config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).remoto
if ($cfgRem.pedir_codigo) { Copy-Item -LiteralPath $rutaClave -Destination (Join-Path $motor 'codigos.dat'); Write-Host 'Código por cliente: SÍ (la ventana lo pide)' -ForegroundColor Cyan }
else { Write-Host 'Código por cliente: no (config.json, remoto.pedir_codigo)' -ForegroundColor Gray }

# Firma de Isaac: lista de archivos con su huella, firmada. En el equipo se comprueba antes de pedir admin.
if (-not $LlavePrivadaXml) { $LlavePrivadaXml = Read-LlavePrivadaIsaac }
$nFirmados = Write-ManifiestoPaquete -Raiz $dir -LlavePrivadaXml $LlavePrivadaXml
$LlavePrivadaXml = $null
Write-Host "Firmado: $nFirmados archivos. Código de Isaac: $(Get-CodigoIsaac -LlavePublicaXml ([IO.File]::ReadAllText((Join-Path $dir 'motor\llave_publica.xml'))))" -ForegroundColor Cyan

$zip = Join-Path $Salida ("Diagnostico_remoto_{0}.zip" -f (Get-Date -Format 'yyyyMMdd'))
if ([IO.File]::Exists($zip)) { Remove-Item -LiteralPath $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($dir, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host ('Listo: {0} ({1:N0} MB)' -f $zip, ((Get-Item -LiteralPath $zip).Length / 1MB)) -ForegroundColor Green
