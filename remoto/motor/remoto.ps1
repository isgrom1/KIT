#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico remoto: lo corre el familiar o cliente con DIAGNOSTICO.cmd y deja en su Escritorio un archivo
    cifrado que solo Isaac puede abrir (remoto\abrir_diagnostico.ps1 en su PC).
.DESCRIPTION
    1. Diagnóstico del kit (solo lee, sin red) en una carpeta temporal.
    2. Prueba CALOR: HWiNFO grabando, -ReposoMin de reposo y -Minutos de OCCT cargando la CPU.
    3. RESUMEN.txt con lo principal.
    4. ZIP de todo, cifrado con la llave pública de Isaac (llave_publica.xml), en el Escritorio.
    5. Borra la carpeta temporal: en el equipo solo queda el archivo cifrado.
    No instala nada ni cambia la configuración de Windows. Necesita administrador (OCCT y HWiNFO lo piden).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Consola para el familiar')]
[CmdletBinding()]
param(
    [double]$Minutos = 10,
    [double]$ReposoMin = 5,
    [switch]$SinCalor,
    [string]$Destino = [Environment]::GetFolderPath('Desktop')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$motor = $PSScriptRoot
$raiz = Split-Path -Parent $motor
$scripts = Join-Path $motor 'scripts'
$herr = Join-Path $raiz 'herramientas'
. (Join-Path $motor 'Cifrado.ps1')

function Write-Titulo([string]$Texto) { Write-Host ''; Write-Host " $Texto" -ForegroundColor Cyan }

$Host.UI.RawUI.WindowTitle = 'Diagnóstico para Isaac - no cierres esta ventana'
Write-Host ''
Write-Host ' DIAGNÓSTICO PARA ISAAC' -ForegroundColor Cyan
Write-Host ' Revisa el computador y prueba la temperatura con carga. No instala nada.' -ForegroundColor Gray
$total = if ($SinCalor) { 'unos 5 minutos' } else { "unos $([int]($Minutos + $ReposoMin + 5)) minutos" }
Write-Host " Demora $total. No cierres esta ventana ni las que se abran solas." -ForegroundColor Yellow

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ' Hay que abrirlo con DIAGNOSTICO.cmd y aceptar el permiso de administrador.' -ForegroundColor Red
    exit 2
}
$llave = Join-Path $motor 'llave_publica.xml'
if (-not [IO.File]::Exists($llave)) { Write-Host ' Falta llave_publica.xml en el paquete: pídele a Isaac uno nuevo.' -ForegroundColor Red; exit 2 }

# Un ZIP bajado de internet o WhatsApp marca cada archivo; sin quitar esa marca, OCCT o HWiNFO pueden quedar
# detenidos en un aviso de seguridad que nadie aprieta.
Get-ChildItem -LiteralPath $raiz -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

$sello = Get-Date -Format 'yyyyMMdd_HHmm'
$trabajo = Join-Path $env:TEMP "kit_remoto_$sello"
$null = [IO.Directory]::CreateDirectory($trabajo)
$ps = Join-Path $PSHOME 'powershell.exe'

# Con 'Stop', una línea en stderr de un proceso hijo redirigido con 2>&1 corta todo (PS 5.1).
$ErrorActionPreference = 'Continue'

# 1. Diagnóstico del kit
Write-Titulo '1/3 Revisando el computador'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'diagnostico.ps1') -Clientes (Join-Path $trabajo 'diagnostico') 2>&1 |
    Tee-Object -FilePath (Join-Path $trabajo 'diagnostico.log') | Out-Host
$codDiag = $LASTEXITCODE

# 2. CALOR
$codCalor = $null
if (-not $SinCalor) {
    Write-Titulo '2/3 Prueba de temperatura (se abren HWiNFO y OCCT: no los toques)'
    $dirCalor = Join-Path $trabajo 'calor'
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $motor 'calor.ps1') -Salida $dirCalor -Herramientas $herr -Scripts $scripts -Minutos $Minutos -ReposoMin $ReposoMin 2>&1 |
        Tee-Object -FilePath (Join-Path $trabajo 'calor.log') | Out-Host
    $codCalor = $LASTEXITCODE
    # Si la prueba se cortó a medias, HWiNFO u OCCT pueden seguir abiertos y con el CSV tomado: el ZIP fallaría.
    Get-Process | Where-Object { $_.ProcessName -match '(?i)^(hwinfo|occt)' } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$ErrorActionPreference = 'Stop'

# 3. Resumen
Write-Titulo '3/3 Preparando el archivo para Isaac'
$lineas = New-Object System.Collections.Generic.List[string]
$lineas.Add("Diagnóstico remoto - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$lineas.Add("Diagnóstico del kit: código de salida $codDiag (0 = bien)")
if ($SinCalor) { $lineas.Add('CALOR: no se hizo (-SinCalor)') }
else {
    $lineas.Add("CALOR: código de salida $codCalor (0 = bien); reposo $ReposoMin min, carga $Minutos min")
    $csv = Join-Path $trabajo 'calor\sensores_calor.csv'
    if ([IO.File]::Exists($csv)) {
        try {
            foreach ($lib in 'Comun', 'Log', 'Sensores', 'Mejoras') { . (Join-Path $scripts "lib\$lib.ps1") }
            Initialize-Contexto -RaizScripts $scripts
            $r = Read-SensoresCsv -Ruta $csv
            $m = $r.metricas
            $cpuT = if ($m.cpu_temp_paquete) { $m.cpu_temp_paquete } else { $m.cpu_temp_nucleo_max }
            $lineas.Add(('CSV: {0}, {1} filas, {2:N1} min' -f $r.formato, $r.filas, $r.duracion_min))
            if ($cpuT) { $lineas.Add(('CPU: {0} °C promedio, {1} °C máximo' -f $cpuT.media, $cpuT.max)) }
            $mt = if ($cpuT) { Get-MejoraTermica -TempMaxC ([double]$cpuT.max) } else { $null }
            if ($mt) { $lineas.Add('MEJORA POR TEMPERATURA:'); foreach ($x in @(Format-MejorasTexto -Mejoras @($mt))) { $lineas.Add($x) } }
            $lineas.Add($(if ($r.carga) { 'Carga detectada: {0:N1} min' -f $r.carga.minutos } else { 'Carga detectada: no' }))
        } catch { $lineas.Add("No se pudo leer el CSV de sensores: $($_.Exception.Message)") }
    } else { $lineas.Add('No quedó CSV de sensores') }
}
$res = Get-ChildItem -LiteralPath (Join-Path $trabajo 'diagnostico') -Recurse -Filter 'resumen.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($res) { $lineas.Add(''); $lineas.Add('--- resumen del diagnóstico ---'); foreach ($l in [IO.File]::ReadAllLines($res.FullName)) { $lineas.Add($l) } }
[IO.File]::WriteAllLines((Join-Path $trabajo 'RESUMEN.txt'), $lineas, (New-Object Text.UTF8Encoding $true))

# 4. ZIP + cifrado
$archivo = $null
try {
    # ZIP en memoria, archivo por archivo: uno tomado por otro programa se salta y se anota, no corta todo.
    $ms = New-Object IO.MemoryStream
    $za = New-Object IO.Compression.ZipArchive ($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    $saltados = New-Object System.Collections.Generic.List[string]
    $base = $trabajo.TrimEnd('\').Length + 1
    foreach ($f in Get-ChildItem -LiteralPath $trabajo -Recurse -File) {
        $rel = $f.FullName.Substring($base).Replace('\', '/')
        try {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            $en = $za.CreateEntry($rel, [IO.Compression.CompressionLevel]::Optimal)
            $s = $en.Open(); $s.Write($bytes, 0, $bytes.Length); $s.Dispose()
        } catch { $saltados.Add("$rel ($($_.Exception.Message))") }
    }
    if ($saltados.Count) {
        $txt = [Text.Encoding]::UTF8.GetBytes("No se pudieron leer:`r`n" + ($saltados -join "`r`n"))
        $s = $za.CreateEntry('NO_INCLUIDOS.txt').Open(); $s.Write($txt, 0, $txt.Length); $s.Dispose()
    }
    $za.Dispose()
    $cifrado = Protect-DatosRemoto -Datos $ms.ToArray() -LlavePublicaXml ([IO.File]::ReadAllText($llave))
    $ms.Dispose()
    $null = [IO.Directory]::CreateDirectory($Destino)
    $archivo = Join-Path $Destino ("Diagnostico_para_Isaac_{0}_{1}.kitdiag" -f $env:COMPUTERNAME, $sello)
    [IO.File]::WriteAllBytes($archivo, $cifrado)
} catch {
    Write-Host ''
    Write-Host " No se pudo armar el archivo: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host " Los datos quedaron en $trabajo : avísale a Isaac." -ForegroundColor Red
    exit 1
}
# 5. En el equipo no queda nada sin cifrar
Remove-Item -LiteralPath $trabajo -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ' LISTO.' -ForegroundColor Green
Write-Host " Mándale a Isaac este archivo (por WhatsApp o correo):" -ForegroundColor Green
Write-Host "   $archivo"
Write-Host ' Va cifrado: solo él lo puede abrir.' -ForegroundColor Gray
Start-Process explorer.exe -ArgumentList "/select,`"$archivo`""
exit 0
