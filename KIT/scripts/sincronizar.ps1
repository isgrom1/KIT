#Requires -Version 5.1
<#
.SYNOPSIS
    Copia los expedientes del USB al maestro de tu PC sin pisar nada (solo en tus equipos).
.DESCRIPTION
    Las reglas (nuevos, iguales, cambiados, conflictos y liberar el USB) están en lib\Sincronizacion.ps1.
    Lo usan el menú de consola (opción S) y la interfaz (Expedientes -> Sincronizar).
    Códigos de salida: 0 bien (aunque haya conflictos: se avisan), 1 error o equipo no autorizado.
.PARAMETER LiberarUsb
    Después de copiar, deja en el USB solo las atenciones abiertas. Una entregada se borra del USB solo
    si cada archivo suyo está idéntico (SHA-256) en el maestro.
.PARAMETER Maestro
    Carpeta maestra. Por defecto config.json -> sincronizacion.ruta_maestro.
.PARAMETER Clientes
    Carpeta de expedientes del USB. Por defecto KIT\clientes.
.PARAMETER ProgresoGui
    Para la interfaz: escribe "##LOG|texto", "##RESULTADO|json" o "##ERROR|mensaje" en UTF-8.
.PARAMETER EsTecnico
    Solo responde con el código de salida: 0 si este equipo está en equipos_tecnico, 1 si no.
.PARAMETER Forzar
    Pruebas: sincroniza aunque este equipo no esté en equipos_tecnico.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Salida en consola con colores para el técnico')]
param([switch]$LiberarUsb, [string]$Maestro, [string]$Clientes, [switch]$ProgresoGui, [switch]$EsTecnico, [switch]$Forzar)

$ErrorActionPreference = 'Stop'
if ($ProgresoGui) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }

function Write-Gui {
    param([string]$Tipo, [string]$Texto)
    # Doble paréntesis: con uno solo, PowerShell 5.1 toma la coma como separador de argumentos del método.
    [Console]::Out.WriteLine(('##{0}|{1}' -f $Tipo, ($Texto -replace "`r?`n", ' ')))
    [Console]::Out.Flush()
}

function Show-Lista {
    param([string]$Titulo, [string[]]$Items, [ConsoleColor]$Color, [int]$Max = 10)
    if (-not $Items -or $Items.Count -eq 0) { return }
    Write-Host "  $Titulo" -ForegroundColor $Color
    foreach ($i in @($Items | Select-Object -First $Max)) { Write-Host "    - $i" -ForegroundColor $Color }
    if ($Items.Count -gt $Max) { Write-Host "    ... y $($Items.Count - $Max) más (ver el log)" -ForegroundColor $Color }
}

try {
    foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente', 'Sincronizacion') { . (Join-Path $PSScriptRoot "lib\$lib.ps1") }
    Initialize-Contexto -RaizScripts $PSScriptRoot
    if ($EsTecnico) { exit $(if (Test-EquipoTecnico) { 0 } else { 1 }) }
    if (-not (Test-EquipoTecnico) -and -not $Forzar) { throw "Sincronizar es solo para tus equipos (config.json -> equipos_tecnico) y este es $env:COMPUTERNAME." }
    if (-not $Clientes) { $Clientes = $script:Ctx.CarpetaClientes }
    if (-not $Maestro) { $Maestro = Get-RutaMaestro }
    if (-not $Maestro) { throw 'Falta la carpeta maestra en config.json -> sincronizacion.ruta_maestro.' }
    $avance = if ($ProgresoGui) { { param($t) Write-Gui 'LOG' $t } } else { { param($t) Write-Host "  $t" -ForegroundColor DarkGray } }
    if (-not $ProgresoGui) {
        Write-Host ''
        Write-Host "  USB:     $Clientes"
        Write-Host "  Maestro: $Maestro"
        Write-Host ''
    }
    $r = Invoke-Sincronizacion -Clientes $Clientes -Maestro $Maestro -LiberarUsb:$LiberarUsb -AlAvance $avance
    if ($ProgresoGui) {
        Write-Gui 'RESULTADO' ($r | ConvertTo-Json -Compress -Depth 4)
        exit 0
    }
    Write-Host ''
    Write-Host ('  {0} archivos revisados: {1} nuevos, {2} iguales, {3} actualizados.' -f $r.Archivos, $r.Nuevos, $r.Iguales, $r.Actualizados) -ForegroundColor Green
    if ($r.MaestroMasNuevo) { Write-Host "  $($r.MaestroMasNuevo) estaban más nuevos en el maestro: se dejaron como estaban." }
    Show-Lista -Titulo "Mediciones en curso que no se copiaron ($(@($r.EnCurso).Count)):" -Items $r.EnCurso -Color Yellow
    Show-Lista -Titulo "OJO, $(@($r.Conflictos).Count) conflictos (cambiaron en el USB y en el maestro). Se guardaron ambas versiones; la del USB quedó como '(conflicto USB ...)':" -Items $r.Conflictos -Color Yellow
    Show-Lista -Titulo "No se pudieron copiar ($(@($r.Errores).Count)):" -Items $r.Errores -Color Red
    if ($LiberarUsb) {
        Write-Host ''
        Write-Host "  Liberadas del USB: $(@($r.Liberadas).Count) ($(Format-Tamano $r.BytesLiberados))." -ForegroundColor Green
        Show-Lista -Titulo 'Liberadas:' -Items $r.Liberadas -Color Gray
        Show-Lista -Titulo 'Quedaron en el USB:' -Items $r.NoLiberadas -Color Yellow
    }
    Write-Host ''
    Write-Host "  Log: $($r.Log)"
    exit 0
} catch {
    if ($ProgresoGui) { Write-Gui 'ERROR' $_.Exception.Message } else { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red }
    exit 1
}
