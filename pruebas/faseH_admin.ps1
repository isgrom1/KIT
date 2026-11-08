#Requires -Version 5.1
<#
.SYNOPSIS
    Fase H, con admin (se lanza con Start-Process -Verb RunAs; el técnico acepta un UAC): el PDF con Edge
    desde un proceso elevado y OCCT real con la prueba fija.
.DESCRIPTION
    Copia OCCT.exe y una configuración real a <Base>\OCCT y le cambia la prueba (1 hora, Variable, envío a
    internet activado). Abre OCCT con Start-Herramienta, como el botón del kit, espera su ventana, lo cierra y revisa que OCCT haya guardado la prueba fija (si no la hubiera aceptado, la habría
    reemplazado por la suya). Escribe todo en <Base>\resultado.txt. No toca la copia de OCCT del pendrive.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param(
    [Parameter(Mandatory)][string]$Config,
    [string]$Occt,
    [string]$Base = 'X:\kitservicio_prueba\faseH'
)
$ErrorActionPreference = 'Stop'
# En un proceso elevado, $PSScriptRoot llegó vacío a los valores por defecto del param(): se calcula aquí.
$aqui = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Occt) { $Occt = Join-Path (Split-Path -Parent $aqui) 'KIT\herramientas\OCCT\OCCT.exe' }
$null = [IO.Directory]::CreateDirectory($Base)
# Lo que muestra la consola elevada (que se cierra sola) queda en transcript.txt.
try { $null = Start-Transcript -LiteralPath (Join-Path $Base 'transcript.txt') -Force } catch { [IO.File]::WriteAllText((Join-Path $Base 'transcript_error.txt'), $_.Exception.Message) }
$res = New-Object System.Collections.Generic.List[string]
function Add-Linea([string]$Texto) { $res.Add("$(Get-Date -Format HH:mm:ss) $Texto") }
$utf8 = New-Object Text.UTF8Encoding($false)
try {
    $scripts = Join-Path (Split-Path -Parent $aqui) 'KIT\scripts'
    foreach ($lib in 'Comun', 'Informe', 'Herramientas') { . (Join-Path $scripts "lib\$lib.ps1") }
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Add-Linea "admin: $admin"

    # 1. PDF con Edge desde un proceso elevado.
    try {
        $d = Join-Path $Base 'pdf con ñ'
        $null = [IO.Directory]::CreateDirectory($d)
        [IO.File]::WriteAllText("$d\informe_cliente.html", '<!doctype html><meta charset="utf-8"><h1>Prueba con admin ñ</h1><p>91 °C → 71 °C</p>', (New-Object Text.UTF8Encoding($true)))
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $pdf = Export-PdfInforme -Html "$d\informe_cliente.html"
        $b = [IO.File]::ReadAllBytes($pdf)
        Add-Linea ('PDF con admin: {0} bytes, empieza con {1}, {2:n1} s, perfiles temporales que quedaron: {3}' -f $b.Length, [Text.Encoding]::ASCII.GetString($b, 0, 5), $sw.Elapsed.TotalSeconds, @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'kit_pdf_*').Count)
    } catch { Add-Linea "PDF con admin: ERROR $($_.Exception.Message)" }

    # 2. OCCT real con la prueba fija.
    if (@(Get-Process -Name OCCT, OCCTGUI -ErrorAction SilentlyContinue).Count) { Add-Linea 'OCCT ya estaba abierto: no se prueba' }
    else {
        $dir = Join-Path $Base 'OCCT'
        $null = [IO.Directory]::CreateDirectory($dir)
        Copy-Item -LiteralPath $Occt -Destination (Join-Path $dir 'OCCT.exe') -Force
        $c = [IO.File]::ReadAllText($Config, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $c.StabilitySchedule.Periods[0].Duration = '01:00:00'
        $c.StabilitySchedule.Periods[0].CpuOnlyOcctConfig.LoadType = 'Variable'
        $c.AllowOcbaseUpload = $true
        [IO.File]::WriteAllText((Join-Path $dir 'OCCT.config.json'), ($c | ConvertTo-Json -Depth 100), $utf8)
        Add-Linea 'config de prueba: 1 h, Variable, envío a internet activado'
        $op = @(Get-OpcionesHerramientas -Carpeta $Base | Where-Object { $_.Nombre -eq 'OCCT' })[0]
        $nota = Start-Herramienta -Opcion $op
        Add-Linea "botón: $nota"
        $c2 = [IO.File]::ReadAllText((Join-Path $dir 'OCCT.config.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        Add-Linea "antes de abrir: $($c2.StabilitySchedule.Periods[0].Duration) $($c2.StabilitySchedule.Periods[0].CpuOnlyOcctConfig.LoadType) envío=$($c2.AllowOcbaseUpload) SaveReportPath=$([bool]$c2.PSObject.Properties['SaveReportPath'])"
        $gui = $null
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 240 -and -not $gui) {
            Start-Sleep -Seconds 2
            $gui = @(Get-Process -Name OCCTGUI -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })[0]
        }
        if (-not $gui) { Add-Linea "OCCT no mostró su ventana en 240 s (procesos: $(@(Get-Process -Name OCCT, OCCTGUI -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '))" }
        else {
            Add-Linea ('OCCT abrió en {0:n0} s: "{1}"' -f $sw.Elapsed.TotalSeconds, $gui.MainWindowTitle)
            Start-Sleep -Seconds 10
            [void]$gui.CloseMainWindow()
            if (-not $gui.WaitForExit(30000)) { Add-Linea 'OCCT no se cerró solo en 30 s: se termina (puede no haber guardado)'; Get-Process -Name OCCT, OCCTGUI -ErrorAction SilentlyContinue | Stop-Process -Force }
            Start-Sleep -Seconds 3
            $c3 = [IO.File]::ReadAllText((Join-Path $dir 'OCCT.config.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
            $p0 = $c3.StabilitySchedule.Periods[0]
            Add-Linea "después de cerrar OCCT: $($p0.TestType) $($p0.Duration) infinita=$($p0.IsInfinite) $($p0.CpuOnlyOcctConfig.Mode) $($p0.CpuOnlyOcctConfig.LoadType) $($p0.CpuOnlyOcctConfig.DataSet) ciclo=$($p0.CpuOnlyOcctConfig.StartAtCycle) envío=$($c3.AllowOcbaseUpload) EulaVersion=$($c3.EulaVersion) Version=$($c3.Version) guardado=$([IO.File]::GetLastWriteTime((Join-Path $dir 'OCCT.config.json')).ToString('HH:mm:ss'))"
        }
    }
} catch {
    Add-Linea "ERROR: $($_.Exception.Message) (línea $($_.InvocationInfo.ScriptLineNumber))"
} finally {
    [IO.File]::WriteAllLines((Join-Path $Base 'resultado.txt'), $res, (New-Object Text.UTF8Encoding($true)))
    try { $null = Stop-Transcript } catch { Write-Verbose 'sin transcript' }
}
