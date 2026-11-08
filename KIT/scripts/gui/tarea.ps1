#Requires -Version 5.1
<#
.SYNOPSIS
    Ejecutor de trabajos largos para la interfaz gráfica.
.DESCRIPTION
    Corre en un proceso aparte para que la ventana nunca se congele (la ventana lo puede cancelar).
    Escribe en la salida, en UTF-8: "##LOG|texto", "##RESULTADO|json" al terminar bien o "##ERROR|mensaje".
    -Parametros: ruta a un JSON con lo que necesita la acción (ids elegidos, ruta del CSV...).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Sin Write-Host: escribe en [Console]::Out')]
param(
    [Parameter(Mandatory)][ValidateSet('analizar_archivos', 'mover_archivos', 'deshacer_archivos', 'aplicar_lento', 'deshacer_lento', 'generar_informes', 'importar_sensores', 'guardar_pdf')][string]$Accion,
    [Parameter(Mandatory)][string]$Expediente,
    [Parameter(Mandatory)][string]$Atencion,
    [string]$Parametros
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Write-Gui {
    param([string]$Tipo, [string]$Texto)
    # Doble paréntesis: con uno solo, PowerShell 5.1 toma la coma como separador de argumentos del método.
    [Console]::Out.WriteLine(('##{0}|{1}' -f $Tipo, ($Texto -replace "`r?`n", ' ')))
    [Console]::Out.Flush()
}

try {
    $raiz = Split-Path -Parent $PSScriptRoot
    foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe') { . (Join-Path $raiz "lib\$lib.ps1") }
    foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $raiz "motivos\$m.ps1") }
    Initialize-Contexto -RaizScripts $raiz
    Initialize-Privacidad
    $script:Ctx.Admin = Get-EstadoAdmin
    $exp = Read-Expediente $Expediente
    $p = if ($Parametros -and [IO.File]::Exists($Parametros)) { ConvertTo-Diccionario (Read-JsonKit $Parametros) } else { [ordered]@{} }
    $resultado = $null
    switch ($Accion) {
        'analizar_archivos' {
            Write-Gui 'LOG' 'Analizando archivos (Temp, Descargas, duplicados, fotos...). Puede tardar unos minutos.'
            # 'perfil' solo llega desde un escenario de prueba (carpeta de prueba en vez del perfil real).
            $r = Invoke-AnalisisArchivos -Expediente $exp -Atencion $Atencion -Perfil $(if ($p['perfil']) { [string]$p['perfil'] } else { '' })
            $resultado = [ordered]@{ candidatos = @($r.candidatos).Count; marcados = @($r.candidatos | Where-Object { $_.seleccionado }).Count; parcial = $r.parcial; segundos = $r.duracion_seg }
        }
        'mover_archivos' {
            Write-Gui 'LOG' "Moviendo $(@($p['ids']).Count) elementos a _PARA_BORRAR..."
            $r = Move-ArchivosParaBorrar -Expediente $exp -Atencion $Atencion -Ids @($p['ids'] | ForEach-Object { [int]$_ })
            $resultado = [ordered]@{ movidos = $r.Movidos; bytes = $r.Bytes; destinos = @($r.Destinos); saltados = @($r.Saltados) }
        }
        'deshacer_archivos' {
            $r = Undo-MovimientoArchivos -Expediente $exp -Atencion $Atencion
            $resultado = [ordered]@{ devueltos = $r.Devueltos; problemas = @($r.Problemas) }
        }
        'aplicar_lento' {
            $ids = @($p['ids'])
            $acciones = @(Get-AccionesLento -Expediente $exp -Atencion $Atencion | Where-Object { $_.Id -in $ids })
            if (-not $p['sin_punto']) { Write-Gui 'LOG' 'Creando el punto de restauración (puede tardar un minuto)...' }
            try {
                $hechas = @(Invoke-AccionesLento -Expediente $exp -Atencion $Atencion -Acciones $acciones -SinPuntoRestauracion:([bool]$p['sin_punto']) -WarningVariable avisos -WarningAction SilentlyContinue)
                $resultado = [ordered]@{ hechas = $hechas; errores = @($avisos | ForEach-Object { "$_" }) }
            } catch {
                # Windows no deja crear el punto: no se aplicó nada y la ventana le pregunta al técnico.
                $msj = "$($_.Exception.Message)"
                if (-not $msj.StartsWith($script:PrefijoSinPunto)) { throw }
                $resultado = [ordered]@{ hechas = @(); errores = @(); punto_fallo = $msj.Substring($script:PrefijoSinPunto.Length) }
            }
        }
        'deshacer_lento' {
            $d = @(Undo-AccionesLento -Expediente $exp -Atencion $Atencion -WarningVariable avisos -WarningAction SilentlyContinue)
            $resultado = [ordered]@{ deshechas = $d; errores = @($avisos | ForEach-Object { "$_" }) }
        }
        'generar_informes' {
            $r = Export-Informes -Expediente $exp -Atencion $Atencion
            $resultado = [ordered]@{ generado = $r.Generado; faltan = @($r.Faltan | ForEach-Object { $_.Texto }); cliente = $r.Cliente; tecnico = $r.Tecnico; advertencias = @($(if ($r.Datos) { $r.Datos.Advertencias })) }
        }
        'guardar_pdf' {
            # PDF del pre-informe (rehecho con lo último) o del informe del cliente, con Edge sin ventana.
            if ($p['cual'] -eq 'pre') {
                $pre = Export-PreInforme -Expediente $exp -Atencion $Atencion
                if (-not $pre.Generado) { throw 'Primero haz el diagnóstico ANTES' }
                $html = $pre.Ruta
            } else {
                $html = Join-Path (Join-Path $exp.Ruta $Atencion) 'informe_cliente.html'
                if (-not [IO.File]::Exists($html)) { throw 'Primero genera los informes' }
            }
            Write-Gui 'LOG' 'Imprimiendo a PDF con Edge (sin ventana)...'
            $pdf = Export-PdfInforme -Html $html
            Write-TrabajoLog -Expediente $exp -Atencion $Atencion -Texto "PDF | $([IO.Path]::GetFileName($pdf)) guardado"
            $resultado = [ordered]@{ pdf = $pdf }
        }
        'importar_sensores' {
            $r = Import-SensoresMedicion -Expediente $exp -Atencion $Atencion -Momento $p['momento'] -Ruta $p['ruta']
            $cpu = if ($r.metricas.cpu_temp_paquete) { $r.metricas.cpu_temp_paquete } else { $r.metricas.cpu_temp_nucleo_max }
            $resultado = [ordered]@{ formato = $r.formato; minutos = $r.duracion_min; cpu_media = $(if ($cpu) { $cpu.media }); cpu_max = $(if ($cpu) { $cpu.max })
                gpu_media = $(if ($r.metricas.gpu_temp) { $r.metricas.gpu_temp.media }); gpu_max = $(if ($r.metricas.gpu_temp) { $r.metricas.gpu_temp.max }); pierde = $r.pierde_velocidad.valor; fuente = $r.pierde_velocidad.fuente }
        }
    }
    Write-Gui 'RESULTADO' ($resultado | ConvertTo-Json -Compress -Depth 4)
    exit 0
} catch {
    Write-Gui 'ERROR' $_.Exception.Message
    exit 1
}
