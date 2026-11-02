# revision.ps1 - Motivo REVISION: solo diagnóstico. Semáforo por área a partir de las alertas del
# diagnóstico (CRÍTICO = rojo, AVISO = amarillo) y, si hay CSV de sensores, de las temperaturas.
# Requiere lib\Comun y Expediente.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:AreasRevision = [ordered]@{
    'Discos'              = @{ Patron = '^(HW-DISCO|HW-SMART|EST-DISCO)'; Verde = 'Los discos están sanos'; Amarillo = 'Un disco necesita atención'; Rojo = 'Un disco muestra fallas: respaldar y planificar el cambio' }
    'Batería'             = @{ Patron = '^HW-BATERIA'; Verde = 'La batería está bien'; Amarillo = 'La batería está gastada'; Rojo = 'La batería está muy gastada: conviene cambiarla' }
    'Windows y seguridad' = @{ Patron = '^(WIN-|SEG-|NAV-)'; Verde = 'Windows y la protección están al día'; Amarillo = 'Hay detalles de Windows o seguridad por revisar'; Rojo = 'Windows o la protección tienen un problema importante' }
    'Rendimiento'         = @{ Patron = '^(HW-RAM|HW-GPU|USO-|ARR-|ENE-|SW-|EST-BSOD|EST-APAGADOS|DIS-|GPU-)'; Verde = 'Funciona sin problemas de rendimiento'; Amarillo = 'Hay cosas que lo hacen más lento o inestable'; Rojo = 'Tiene problemas serios de rendimiento o estabilidad' }
    'Espacio'             = @{ Patron = '^ESP-'; Verde = 'Hay espacio suficiente'; Amarillo = 'Queda poco espacio'; Rojo = 'Casi sin espacio' }
}
$script:OrdenColor = @{ gris = 0; verde = 1; amarillo = 2; rojo = 3 }

function Get-SemaforoRevision {
    # Devuelve una fila por área (Area, Color, Frase, Motivos) más el color general (el peor).
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [ValidateSet('antes', 'despues')][string]$Momento = 'antes')
    $carpeta = Join-Path (Join-Path $Expediente.Ruta $Atencion) $Momento
    $diag = if ([IO.File]::Exists((Join-Path $carpeta 'diagnostico.json'))) { Read-JsonKit (Join-Path $carpeta 'diagnostico.json') } else { $null }
    $sens = if ([IO.File]::Exists((Join-Path $carpeta 'sensores_resumen.json'))) { Read-JsonKit (Join-Path $carpeta 'sensores_resumen.json') } else { $null }
    $filas = New-Object System.Collections.Generic.List[object]

    # Temperatura: solo con CSV de sensores (el diagnóstico no mide bajo carga).
    if ($sens) {
        $cpu = if ($sens.metricas.cpu_temp_paquete) { $sens.metricas.cpu_temp_paquete } else { $sens.metricas.cpu_temp_nucleo_max }
        $tj = [double](Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'sensores.json')).tjmax_aviso_c
        $motivos = @()
        if ($cpu) { $motivos += "CPU {0} °C de promedio y {1} °C de máximo" -f (Format-Numero $cpu.media 1), (Format-Numero $cpu.max 1) }
        if ($sens.pierde_velocidad.valor) { $motivos += "Pierde velocidad por calor ($($sens.pierde_velocidad.fuente))" }
        $color = if (-not $cpu) { 'gris' } elseif ($sens.pierde_velocidad.valor -or $cpu.max -ge $tj) { 'rojo' } elseif ($cpu.media -ge 85 -or $cpu.max -ge 90) { 'amarillo' } else { 'verde' }
        $frase = @{ gris = 'Sin temperatura de CPU en el CSV'; verde = 'Temperaturas normales bajo carga'; amarillo = 'Trabaja caliente bajo carga'; rojo = 'Se sobrecalienta y pierde rendimiento' }[$color]
        $filas.Add([pscustomobject][ordered]@{ Area = 'Temperatura'; Color = $color; Frase = $frase; Motivos = $motivos })
    } else {
        $filas.Add([pscustomobject][ordered]@{ Area = 'Temperatura'; Color = 'gris'; Frase = 'Sin medición de temperatura (no se importó CSV de sensores)'; Motivos = @() })
    }

    $alertas = if ($diag) { @($diag.alertas) } else { @() }
    foreach ($area in $script:AreasRevision.Keys) {
        $def = $script:AreasRevision[$area]
        if (-not $diag) { $filas.Add([pscustomobject][ordered]@{ Area = $area; Color = 'gris'; Frase = "Falta el diagnóstico $($Momento.ToUpperInvariant())"; Motivos = @() }); continue }
        $propias = @($alertas | Where-Object { $_.Codigo -match $def.Patron -and $_.Severidad -ne 'INFO' })
        $color = if (@($propias | Where-Object { $_.Severidad -eq 'CRITICO' }).Count -gt 0) { 'rojo' } elseif ($propias.Count -gt 0) { 'amarillo' } else { 'verde' }
        if ($area -eq 'Batería' -and $color -eq 'verde' -and $diag.datos.equipo -and -not $diag.datos.equipo.TieneBateria) {
            $filas.Add([pscustomobject][ordered]@{ Area = $area; Color = 'gris'; Frase = 'Equipo sin batería'; Motivos = @() }); continue
        }
        $frase = switch ($color) { 'rojo' { $def.Rojo } 'amarillo' { $def.Amarillo } default { $def.Verde } }
        $filas.Add([pscustomobject][ordered]@{ Area = $area; Color = $color; Frase = $frase; Motivos = @($propias | ForEach-Object { $_.Texto }) })
    }
    $general = ($filas | Sort-Object { $script:OrdenColor[$_.Color] } -Descending | Select-Object -First 1).Color
    [pscustomobject][ordered]@{ Motivo = 'REVISION'; Momento = $Momento; General = $general; Areas = $filas.ToArray() }
}
