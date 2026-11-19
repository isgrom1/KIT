#Requires -Version 5.1
<#
.SYNOPSIS
    Abre un diagnóstico remoto (.kitdiag) que mandó un familiar o cliente. Solo funciona en el PC de Isaac.
.DESCRIPTION
    Descifra con la llave privada (DPAPI, %LOCALAPPDATA%\kitservicio) y extrae el contenido en una carpeta
    con el mismo nombre del archivo, al lado de él (o en -Destino). Después abre la carpeta.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remoto\abrir_diagnostico.ps1 -Archivo "$env:USERPROFILE\Downloads\Diagnostico_....kitdiag"
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para Isaac')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'ProtectedData viene con .NET Framework y se carga con Add-Type -AssemblyName System.Security')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archivo,
    [string]$Destino,
    [string]$Cliente,
    [switch]$NoAbrir,
    [switch]$SinInforme
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot 'motor\Cifrado.ps1')

$Archivo = (Resolve-Path -LiteralPath $Archivo).ProviderPath
$privada = Join-Path $env:LOCALAPPDATA 'kitservicio\remoto_llave_privada.dat'
if (-not [IO.File]::Exists($privada)) { throw "No está la llave privada en este PC ($privada). Se crea con remoto\crear_llaves.ps1." }
$xml = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($privada), $null, 'CurrentUser'))
$zip = Unprotect-DatosRemoto -Datos ([IO.File]::ReadAllBytes($Archivo)) -LlavePrivadaXml $xml
$xml = $null
if (-not $Destino) { $Destino = Join-Path (Split-Path -Parent $Archivo) ([IO.Path]::GetFileNameWithoutExtension($Archivo)) }
if ([IO.Directory]::Exists($Destino) -and @(Get-ChildItem -LiteralPath $Destino -Force).Count) { throw "La carpeta $Destino ya existe y tiene archivos: no se sobrescribe." }
$null = [IO.Directory]::CreateDirectory($Destino)
$ms = New-Object IO.MemoryStream (, $zip)
$z = New-Object IO.Compression.ZipArchive ($ms, [IO.Compression.ZipArchiveMode]::Read)
try {
    $raiz = [IO.Path]::GetFullPath($Destino).TrimEnd('\') + '\'
    foreach ($e in $z.Entries) {
        $dest = [IO.Path]::GetFullPath((Join-Path $Destino $e.FullName))
        if (-not $dest.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { throw "Ruta peligrosa dentro del archivo: $($e.FullName)" }
        if ($e.FullName.EndsWith('/')) { $null = [IO.Directory]::CreateDirectory($dest); continue }
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $false)
    }
} finally { $z.Dispose(); $ms.Dispose() }
Write-Host "Listo: $Destino" -ForegroundColor Green
$res = Join-Path $Destino 'RESUMEN.txt'
if ([IO.File]::Exists($res)) { Get-Content -LiteralPath $res -Encoding UTF8 }

# Informe para el cliente (PDF con diseño): lo arma la misma librería que usa el kit del pendrive.
$pdf = $null
$tec = $null
if (-not $SinInforme) {
    try {
        $scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
        foreach ($lib in 'Comun', 'Log', 'Sensores', 'Mejoras', 'Expediente', 'Informe', 'InformeVisual') { . (Join-Path $scripts "lib\$lib.ps1") }
        . (Join-Path $scripts 'motivos\lento.ps1')
        Initialize-Contexto -RaizScripts $scripts
        # Diagnóstico remoto: solo ANTES. Trabajo remoto (Trabajo_para_Isaac_*.kitdiag): ANTES y DESPUÉS.
        $todos = @(Get-ChildItem -LiteralPath $Destino -Recurse -Filter diagnostico.json)
        $json = @($todos | Where-Object { $_.Directory.Name -eq 'antes' }) | Select-Object -First 1
        $despues = @($todos | Where-Object { $_.Directory.Name -eq 'despues' }) | Select-Object -First 1
        $csv = Join-Path $Destino 'calor\sensores_calor.csv'
        if (-not $json) { throw 'no viene diagnostico.json' }
        $doc = Read-JsonKit $(if ($despues) { $despues.FullName } else { $json.FullName })
        $nombre = ('{0}_{1}_{2}' -f $(if ($despues) { 'Informe_trabajo' } else { 'Informe' }), ("$($doc.datos.equipo.Fabricante) $($doc.datos.equipo.Modelo)" -replace '[^\w-]+', '_').Trim('_'), ("$($doc.kit.generado)").Substring(0, 10))
        if ($despues) {
            $r = Export-InformeVisual -Diagnostico $despues.FullName -Antes $json.FullName -RutaAtencion $json.Directory.Parent.FullName -Salida (Join-Path $Destino "$nombre.pdf") -Origen 'remoto' -Cliente $Cliente
        } else {
            $r = Export-InformeVisual -Diagnostico $json.FullName -CsvSensores $csv -Salida (Join-Path $Destino "$nombre.pdf") -Origen 'remoto' -Cliente $Cliente
        }
        $tec = $r.Tecnico
        Write-Host "Hoja técnica (solo para ti): $tec" -ForegroundColor Cyan
        if ($r.Pdf) { $pdf = $r.Pdf; Write-Host "Informe para el cliente: $pdf" -ForegroundColor Green }
        else { Write-Host "Informe en HTML (sin PDF: $($r.Error)): $($r.Html)" -ForegroundColor Yellow }
    } catch {
        Write-Host "No se pudo armar el informe: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
if (-not $NoAbrir) {
    Start-Process explorer.exe -ArgumentList "`"$Destino`""
    if ($pdf) { Start-Process -FilePath $pdf }
    if ($tec) { Start-Process -FilePath $tec }
}
