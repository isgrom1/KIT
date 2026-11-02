# Log.ps1 - log.txt de la atención y mensajes en pantalla.
# Antes de que exista la carpeta del cliente, las líneas quedan en memoria y se vuelcan al crearla.

function Write-LogKit {
    param(
        [ValidateSet('INFO', 'AVISO', 'ERROR')][string]$Nivel = 'INFO',
        [Parameter(Mandatory)][AllowEmptyString()][string]$Mensaje
    )
    $prefijo = if ($script:Ctx.SeccionActual) { "[$($script:Ctx.SeccionActual)] " } else { '' }
    $linea = '{0} {1,-5} {2}{3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff', $script:Invariante), $Nivel, $prefijo, $Mensaje
    $linea = Protect-Texto $linea
    if ($script:Ctx.CarpetaCliente) {
        [IO.File]::AppendAllText((Join-Path $script:Ctx.CarpetaCliente 'log.txt'), $linea + "`r`n", $script:Utf8Bom)
    } else {
        $script:Ctx.LogPendiente.Add($linea)
    }
}

function Write-LogPendiente {
    if (-not $script:Ctx.CarpetaCliente -or $script:Ctx.LogPendiente.Count -eq 0) { return }
    $texto = ($script:Ctx.LogPendiente | ForEach-Object { Protect-Texto $_ }) -join "`r`n"
    [IO.File]::AppendAllText((Join-Path $script:Ctx.CarpetaCliente 'log.txt'), $texto + "`r`n", $script:Utf8Bom)
    $script:Ctx.LogPendiente.Clear()
}

function Show-Mensaje {
    param(
        [AllowEmptyString()][string]$Texto = '',
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$SinSalto
    )
    Write-Host $Texto -ForegroundColor $Color -NoNewline:$SinSalto
}

function Show-Progreso {
    param(
        [Parameter(Mandatory)][string]$Actividad,
        [Parameter(Mandatory)][string]$Estado,
        [ValidateRange(0, 100)][int]$Porcentaje = 0,
        [switch]$Terminado
    )
    if ($Terminado) { Write-Progress -Activity $Actividad -Completed; return }
    Write-Progress -Activity $Actividad -Status $Estado -PercentComplete $Porcentaje
}
