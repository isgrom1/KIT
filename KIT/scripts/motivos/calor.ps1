# calor.ps1 - Motivo CALOR (se calienta, hace ruido, se apaga, baja FPS).
# - Condiciones de medición obligatorias antes y después, para que la comparación sea justa.
# - Importa el CSV del monitor de sensores a antes\ o despues\ (sensores.csv + sensores_resumen.json).
# - Checklist físico en la ficha (desarme, limpieza, pasta/PTM, putty/pads, fotos, materiales).
# - Métricas para el cliente: temperatura promedio y máxima de CPU y GPU, y si pierde velocidad por calor.
# Requiere lib\Comun, Log, Privacidad, Expediente y Sensores.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:CamposCondiciones = [ordered]@{
    enchufado          = 'Enchufado (sí/no)'
    plan               = 'Plan de energía'
    ventiladores       = 'Modo de ventiladores (auto, máximo, turbo...)'
    superficie         = 'Superficie (mesa, cama, base refrigerante...)'
    temp_ambiente_c    = 'Temperatura ambiente (°C)'
    carga_tipo         = 'Tipo de carga (juego, Cinebench, render...)'
    carga_duracion_min = 'Duración de la carga (minutos)'
}

function ConvertTo-CondicionesCalor {
    # Valida y normaliza las condiciones. Lanza un error con todo lo que no sirve.
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Valores)
    $errores = New-Object System.Collections.Generic.List[string]
    $c = [ordered]@{}
    foreach ($k in $script:CamposCondiciones.Keys) {
        $v = if ($Valores.Contains($k)) { $Valores[$k] } else { $null }
        if ($null -eq $v -or "$v".Trim() -eq '') { $c[$k] = $null; continue }
        $t = "$v".Trim()
        switch ($k) {
            'enchufado' {
                if ($v -is [bool]) { $c[$k] = $v }
                elseif ($t -match '^(?i)(s|si|sí|true|1)$') { $c[$k] = $true }
                elseif ($t -match '^(?i)(n|no|false|0)$') { $c[$k] = $false }
                else { $errores.Add('enchufado: responde sí o no') }
            }
            'temp_ambiente_c' {
                $n = 0.0
                if ([double]::TryParse(($t -replace ',', '.'), [Globalization.NumberStyles]::Float, $script:Invariante, [ref]$n) -and $n -ge 0 -and $n -le 50) { $c[$k] = [math]::Round($n, 1) }
                else { $errores.Add('temperatura ambiente: número entre 0 y 50') }
            }
            'carga_duracion_min' {
                $n = 0.0
                if ([double]::TryParse(($t -replace ',', '.'), [Globalization.NumberStyles]::Float, $script:Invariante, [ref]$n) -and $n -gt 0 -and $n -le 1440) { $c[$k] = [math]::Round($n, 1) }
                else { $errores.Add('duración de la carga: minutos, entre 1 y 1440') }
            }
            default {
                if ($t.Length -gt 80) { $errores.Add("${k}: máximo 80 caracteres") } else { $c[$k] = $t }
            }
        }
    }
    if ($errores.Count -gt 0) { throw ("Condiciones no válidas:`n- " + ($errores -join "`n- ")) }
    $c
}

function Get-CondicionesFaltantes {
    param([AllowNull()][System.Collections.IDictionary]$Condiciones)
    foreach ($k in $script:CamposCondiciones.Keys) {
        if (-not $Condiciones -or $null -eq $Condiciones[$k]) { $script:CamposCondiciones[$k] }
    }
}

function Set-CondicionesCalor {
    # Guarda las condiciones de la medición antes/después en la ficha (completas o por partes: lo
    # que no viene se conserva).
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][string]$Atencion,
        [Parameter(Mandatory)][ValidateSet('antes', 'despues')][string]$Momento,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Valores
    )
    $a = Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion
    $previas = $a['condiciones_medicion'][$Momento]
    $todas = [ordered]@{}
    foreach ($k in $script:CamposCondiciones.Keys) {
        $todas[$k] = if ($Valores.Contains($k)) { $Valores[$k] } elseif ($previas) { $previas[$k] } else { $null }
    }
    $c = ConvertTo-CondicionesCalor -Valores $todas
    if ($PSCmdlet.ShouldProcess("$Atencion\$Momento", 'Guardar condiciones de medición')) {
        Set-Ficha -Expediente $Expediente -Atencion $Atencion -Valores @{ "condiciones_medicion.$Momento" = $c }
    }
}

function Import-SensoresMedicion {
    # Copia el CSV a <atención>\<momento>\sensores.csv, guarda el resumen y lo anota en trabajo.log.
    # Si el diagnóstico de ese momento aún no se corre, la carpeta se crea y sus sensores pasan a la
    # medición cuando se haga (Complete-Medicion).
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][string]$Atencion,
        [Parameter(Mandatory)][ValidateSet('antes', 'despues')][string]$Momento,
        [Parameter(Mandatory)][string]$Ruta
    )
    if ($Momento -eq 'despues' -and -not (Test-Medicion -Expediente $Expediente -Atencion $Atencion -Momento 'antes') -and
        -not [IO.File]::Exists((Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'antes') 'sensores_resumen.json'))) {
        throw 'No existe "después" sin "antes": importa primero los sensores o el diagnóstico ANTES'
    }
    $resumen = Read-SensoresCsv -Ruta $Ruta
    $destino = Join-Path (Join-Path $Expediente.Ruta $Atencion) $Momento
    if (-not $PSCmdlet.ShouldProcess($destino, 'Importar sensores')) { return }
    $null = [IO.Directory]::CreateDirectory($destino)
    [IO.File]::Copy($Ruta, (Join-Path $destino 'sensores.csv'), $true)
    [IO.File]::WriteAllText((Join-Path $destino 'sensores_resumen.json'), ($resumen | ConvertTo-Json -Depth 6), $script:Utf8SinBom)
    $m = $resumen.metricas
    $cpu = if ($m.cpu_temp_paquete) { $m.cpu_temp_paquete } else { $m.cpu_temp_nucleo_max }
    $txt = '{0} | sensores importados: {1} ({2}, {3} min){4}{5}' -f $Momento.ToUpperInvariant(), $resumen.archivo, $resumen.formato, (Format-Numero $resumen.duracion_min 1),
        $(if ($cpu) { " | CPU $(Format-Numero $cpu.media 1)/$(Format-Numero $cpu.max 1) °C" } else { '' }),
        $(if ($m.gpu_temp) { " | GPU $(Format-Numero $m.gpu_temp.media 1)/$(Format-Numero $m.gpu_temp.max 1) °C" } else { '' })
    Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto ("CALOR $txt")
    $resumen
}

function Read-SensoresMedicion {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)][string]$Momento)
    $r = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) $Momento) 'sensores_resumen.json'
    if ([IO.File]::Exists($r)) { Read-JsonKit $r } else { $null }
}

function Get-MetricasCalor {
    # Tarjetas para el cliente y advertencias para el técnico (duraciones que difieren más de 20 % o
    # condiciones distintas entre antes y después).
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $sa = Read-SensoresMedicion -Expediente $Expediente -Atencion $Atencion -Momento 'antes'
    $sd = Read-SensoresMedicion -Expediente $Expediente -Atencion $Atencion -Momento 'despues'
    $cpu = { param($s) if (-not $s) { $null } elseif ($s.metricas.cpu_temp_paquete) { $s.metricas.cpu_temp_paquete } else { $s.metricas.cpu_temp_nucleo_max } }
    $gpu = { param($s) if ($s) { $s.metricas.gpu_temp } else { $null } }
    $ca = & $cpu $sa; $cd = & $cpu $sd; $ga = & $gpu $sa; $gd = & $gpu $sd
    $tarjetas = @(
        Get-TarjetaMetrica -Titulo 'CPU, temperatura promedio' -Antes $(if ($ca) { $ca.media }) -Despues $(if ($cd) { $cd.media }) -Unidad '°C' -Mejor menor
        Get-TarjetaMetrica -Titulo 'CPU, temperatura máxima' -Antes $(if ($ca) { $ca.max }) -Despues $(if ($cd) { $cd.max }) -Unidad '°C' -Mejor menor
        Get-TarjetaMetrica -Titulo 'GPU, temperatura promedio' -Antes $(if ($ga) { $ga.media }) -Despues $(if ($gd) { $gd.media }) -Unidad '°C' -Mejor menor
        Get-TarjetaMetrica -Titulo 'GPU, temperatura máxima' -Antes $(if ($ga) { $ga.max }) -Despues $(if ($gd) { $gd.max }) -Unidad '°C' -Mejor menor
        Get-TarjetaMetrica -Titulo 'Pierde velocidad por calor' -Antes $(if ($sa) { $sa.pierde_velocidad.valor }) -Despues $(if ($sd) { $sd.pierde_velocidad.valor }) -Unidad '' -Mejor si_no
    )
    $advertencias = New-Object System.Collections.Generic.List[string]
    $a = Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion
    foreach ($mo in 'antes', 'despues') {
        $falta = @(Get-CondicionesFaltantes -Condiciones $a['condiciones_medicion'][$mo])
        if ($falta.Count -gt 0) { $advertencias.Add("Condiciones de la medición $($mo.ToUpperInvariant()) incompletas: $($falta -join ', ')") }
    }
    $condA = $a['condiciones_medicion']['antes']; $condD = $a['condiciones_medicion']['despues']
    if ($condA -and $condD) {
        foreach ($k in $script:CamposCondiciones.Keys) {
            if ($k -eq 'carga_duracion_min') { continue }
            if ($null -ne $condA[$k] -and $null -ne $condD[$k] -and "$($condA[$k])" -ne "$($condD[$k])") {
                $txt = { param($v) if ($v -is [double]) { Format-Numero $v 1 } elseif ($v -is [bool]) { if ($v) { 'sí' } else { 'no' } } else { "$v" } }
                $advertencias.Add("Cambió '$($script:CamposCondiciones[$k])': antes '$(& $txt $condA[$k])', después '$(& $txt $condD[$k])'")
            }
        }
    }
    if ($sa -and $sd -and $sa.duracion_min -gt 0) {
        $dif = [math]::Abs($sd.duracion_min - $sa.duracion_min) / $sa.duracion_min
        if ($dif -gt 0.2) { $advertencias.Add(('Las mediciones duran distinto: antes {0} min, después {1} min ({2:N0} % de diferencia)' -f (Format-Numero $sa.duracion_min 1), (Format-Numero $sd.duracion_min 1), (100 * $dif))) }
    }
    if (-not $sa) { $advertencias.Add('Falta el CSV de sensores ANTES') }
    if (-not $sd) { $advertencias.Add('Falta el CSV de sensores DESPUÉS') }
    [pscustomobject][ordered]@{
        Motivo       = 'CALOR'
        Tarjetas     = $tarjetas
        Advertencias = $advertencias.ToArray()
        Antes        = $sa
        Despues      = $sd
        Checklist    = $a['checklist_fisico']
        Materiales   = @($a['materiales'])
    }
}
