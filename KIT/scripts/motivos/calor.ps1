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
    $equipo = Test-EquipoCsvSensores -Expediente $Expediente -Ruta $Ruta
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
    if ($equipo.Coincide -eq $false) { $txt += " | ojo: el CSV dice que es de $($equipo.Texto)" }
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
    # Velocidad que sostuvo la CPU: si llega a su límite de temperatura antes y después, la mejora se ve
    # aquí y no en los grados. Se redondea a 0,1 GHz para no llamar mejora al ruido.
    $frec = { param($s) if ($s) { $s.metricas.cpu_frec_efectiva } else { $null } }
    $fa = & $frec $sa; $fd = & $frec $sd
    $velocidad = $null
    if ($fa -or $fd) {
        $velocidad = Get-TarjetaMetrica -Titulo 'CPU, velocidad sostenida' -Antes $(if ($fa) { [math]::Round($fa.media / 1000, 1) }) -Despues $(if ($fd) { [math]::Round($fd.media / 1000, 1) }) -Unidad 'GHz' -Mejor mayor
        $tarjetas += $velocidad
    }
    $advertencias = New-Object System.Collections.Generic.List[string]
    if ($fa -and $fd -and $fa.media -gt 0 -and ($fa.media - $fd.media) / $fa.media -gt 0.25) {
        $advertencias.Add(('La CPU trabajó mucho menos en el DESPUÉS ({0} -> {1} MHz): puede ser otra carga, y entonces la baja de temperatura no es una mejora real' -f (Format-Numero $fa.media 0), (Format-Numero $fd.media 0)))
    }
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
    # Se compara lo que duró la carga: el reposo que HWiNFO haya grabado de más no cuenta.
    $largo = { param($s) if ($s.carga) { [double]$s.carga.minutos } else { [double]$s.duracion_min } }
    if ($sa -and $sd -and (& $largo $sa) -gt 0) {
        $la = & $largo $sa; $ld = & $largo $sd
        $dif = [math]::Abs($ld - $la) / $la
        if ($dif -gt 0.2) { $advertencias.Add(('Las mediciones duran distinto: antes {0} min, después {1} min ({2:N0} % de diferencia)' -f (Format-Numero $la 1), (Format-Numero $ld 1), (100 * $dif))) }
    }
    if (-not $sa) { $advertencias.Add('Falta el CSV de sensores ANTES') }
    if (-not $sd) { $advertencias.Add('Falta el CSV de sensores DESPUÉS') }
    [pscustomobject][ordered]@{
        Motivo       = 'CALOR'
        Tarjetas     = $tarjetas
        # Las 4 de "Mostrar al cliente": la prueba de carga es de CPU, así que la GPU queda solo en el informe.
        Pantalla     = @($tarjetas[0], $tarjetas[1], $(if ($velocidad) { $velocidad } else { $tarjetas[2] }), $tarjetas[4])
        Advertencias = $advertencias.ToArray()
        Antes        = $sa
        Despues      = $sd
        Checklist    = $a['checklist_fisico']
        Materiales   = @($a['materiales'])
    }
}

# ------------------------------------------------------------------------------ CSV de sensores detectado solo

function Get-CarpetasCsvSensores {
    # Dónde suele quedar el CSV de HWiNFO: la raíz del pendrive, la carpeta KIT y la de HWiNFO del kit, y el
    # Escritorio, Documentos y Descargas del usuario. Solo se mira el primer nivel de cada una.
    $raizKit = $script:Ctx.RaizKit
    $c = [ordered]@{}
    $c['la raíz del pendrive'] = [IO.Path]::GetPathRoot($raizKit)
    $c['la carpeta KIT'] = $raizKit
    $c['la carpeta de HWiNFO del kit'] = Join-Path $raizKit 'herramientas\HWiNFO'
    $c['el Escritorio'] = [Environment]::GetFolderPath('Desktop')
    $c['Documentos'] = [Environment]::GetFolderPath('MyDocuments')
    $c['Descargas'] = Join-Path $env:USERPROFILE 'Downloads'
    $c
}

function Get-FormatoEncabezadoSensores {
    # HWiNFO, LibreHardwareMonitor o $null, leyendo solo la primera línea (aunque HWiNFO lo tenga abierto).
    param([Parameter(Mandatory)][string]$Ruta)
    $linea = $null
    try {
        $fs = [IO.File]::Open($Ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true); $linea = $sr.ReadLine() } finally { $fs.Dispose() }
    } catch { return $null }
    if (-not $linea) { return $null }
    $linea = $linea.TrimStart([char]0xFEFF)
    if ($linea -match '^"?Date"?,"?Time"?,') { return 'HWiNFO' }
    if ($linea -match '^,"/') { return 'LibreHardwareMonitor' }
    $null
}

function ConvertTo-ClaveEquipo {
    # Texto para comparar nombres de equipo o CPU: sin (R), (TM), espacios ni signos, en minúsculas.
    param([AllowNull()][string]$Texto)
    if (-not $Texto) { return '' }
    $Texto.ToLowerInvariant() -replace '\((r|tm)\)|®|™', '' -replace '[^a-z0-9]', ''
}

function Get-EquipoCsvSensores {
    # Equipo y CPU según la fila de grupos que HWiNFO escribe al final del CSV cuando se detiene el registro
    # ("Sistema: DELL Inspiron 3493", "CPU [#0]: Intel Core i3-1005G1"). $null si no la tiene: LibreHardwareMonitor,
    # o HWiNFO todavía grabando. Lee solo el final del archivo y devuelve esos dos nombres: esa fila también nombra
    # los discos con su serie, y eso no se guarda.
    param([Parameter(Mandatory)][string]$Ruta)
    $ultima = $null
    try {
        $fs = [IO.File]::Open($Ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $bom = New-Object byte[] 3
            $conBom = $fs.Read($bom, 0, 3) -eq 3 -and $bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF
            $cod = if ($conBom) { [Text.Encoding]::UTF8 } else { [Text.Encoding]::Default }
            # La fila de grupos mide unos 40 bytes por columna: casi siempre cabe en 64 KB; si no, se lee más.
            foreach ($tam in 65536, 1048576, 8388608) {
                $largo = [int][math]::Min($fs.Length, $tam)
                $null = $fs.Seek(-$largo, [IO.SeekOrigin]::End)
                $buf = New-Object byte[] $largo
                $leidos = 0
                while ($leidos -lt $largo) { $n = $fs.Read($buf, $leidos, $largo - $leidos); if ($n -le 0) { break }; $leidos += $n }
                $texto = $cod.GetString($buf, 0, $leidos).TrimEnd([char[]]@([char]13, [char]10, [char]32))
                $corte = $texto.LastIndexOf([char]10)
                if ($corte -ge 0) { $ultima = $texto.Substring($corte + 1); break }
                if ($largo -eq $fs.Length) { $ultima = $texto.TrimStart([char]0xFEFF); break }
            }
        } finally { $fs.Dispose() }
    } catch { return $null }
    if (-not $ultima) { return $null }
    $s = [regex]::Match($ultima, '(?:^|,)"?(?:Sistema|System)\s*:\s*([^,"]+)')
    if (-not $s.Success) { return $null }
    $c = [regex]::Match($ultima, '(?:^|,)"?CPU \[#0\]\s*:\s*([^,":]+)')
    [pscustomobject]@{
        Sistema = $s.Groups[1].Value.Trim()
        Cpu     = if ($c.Success) { $c.Groups[1].Value.Trim() } else { $null }
    }
}

function Test-EquipoCsvSensores {
    # ¿El CSV es de este equipo? Compara la fila de grupos de HWiNFO con el modelo y la CPU de la ficha.
    # Coincide: $true; $false si algo no calza (otro equipo); $null si el CSV no lo dice o no hay con qué comparar.
    # En Lenovo el modelo de la ficha es el nombre comercial y HWiNFO puede mostrar el tipo de máquina: ahí, y en
    # los equipos genéricos, se compara solo la CPU.
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Ruta)
    $r = [pscustomobject]@{ Coincide = $null; Sistema = $null; Cpu = $null; Texto = $null }
    $csv = Get-EquipoCsvSensores -Ruta $Ruta
    if (-not $csv) { return $r }
    $r.Sistema = $csv.Sistema; $r.Cpu = $csv.Cpu
    $r.Texto = $csv.Sistema + $(if ($csv.Cpu) { " ($($csv.Cpu))" } else { '' })
    $eq = $Expediente.Ficha['equipo']
    if (-not $eq) { return $r }
    $resultados = New-Object System.Collections.Generic.List[bool]
    $modelo = ConvertTo-ClaveEquipo $eq['modelo']
    if ($modelo.Length -ge 3 -and $modelo -ne 'generico' -and "$($eq['fabricante'])" -ne 'Lenovo') {
        $resultados.Add((ConvertTo-ClaveEquipo $csv.Sistema).Contains($modelo))
    }
    $cpuFicha = ConvertTo-ClaveEquipo $eq['cpu']
    if ($csv.Cpu -and $cpuFicha) {
        # HWiNFO acorta el nombre ("Intel Core i3-1005G1"); Windows lo alarga ("Intel(R) Core(TM) i3-1005G1 CPU @ 1.20GHz").
        $numero = @($csv.Cpu -split '\s+' | Where-Object { $_ -match '\d' })
        $resultados.Add($cpuFicha.Contains((ConvertTo-ClaveEquipo $csv.Cpu)) -or ($numero.Count -gt 0 -and $cpuFicha.Contains((ConvertTo-ClaveEquipo $numero[-1]))))
    }
    if ($resultados.Count) { $r.Coincide = -not $resultados.Contains($false) }
    $r
}

function Find-CsvSensores {
    # CSV de sensores que pueden ser de esta medición, el más nuevo primero: de HWiNFO o LibreHardwareMonitor,
    # modificados desde el día de la atención (en el DESPUÉS, desde que se importó el ANTES) y distintos de
    # los ya importados. Si el momento ya tiene sensores, no busca. Solo mira nombres y fechas de los .csv y
    # la primera y la última línea de los recientes; no guarda nada.
    # Los que dicen ser de otro equipo (fila de grupos de HWiNFO) van al final con OtroEquipo y Equipo: quien
    # llama no los ofrece, solo avisa que están.
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][string]$Atencion,
        [Parameter(Mandatory)][ValidateSet('antes', 'despues')][string]$Momento,
        [System.Collections.IDictionary]$Carpetas = (Get-CarpetasCsvSensores),
        [datetime]$Ahora = (Get-Date)
    )
    $dirAt = Join-Path $Expediente.Ruta $Atencion
    if ([IO.File]::Exists((Join-Path (Join-Path $dirAt $Momento) 'sensores_resumen.json'))) { return @() }
    $desde = [datetime]::MinValue
    if ($Atencion -match '^(\d{4}-\d{2}-\d{2})') { $desde = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $script:Invariante) }
    $importados = @()
    $csvAntes = Join-Path (Join-Path $dirAt 'antes') 'sensores.csv'
    if ($Momento -eq 'despues') {
        $resAntes = Join-Path (Join-Path $dirAt 'antes') 'sensores_resumen.json'
        if (-not [IO.File]::Exists($resAntes)) { return @() }
        $t = [IO.File]::GetLastWriteTime($resAntes)
        if ($t -gt $desde) { $desde = $t }
    }
    if ([IO.File]::Exists($csvAntes)) { $importados += Get-Item -LiteralPath $csvAntes }
    $vistos = @{}
    $lista = foreach ($k in $Carpetas.Keys) {
        $dir = $Carpetas[$k]
        if (-not $dir -or -not [IO.Directory]::Exists($dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.csv' -ErrorAction SilentlyContinue)) {
            if ($vistos[$f.FullName.ToLowerInvariant()] -or $f.LastWriteTime -lt $desde -or $f.Length -lt 200) { continue }
            $vistos[$f.FullName.ToLowerInvariant()] = $true
            $formato = Get-FormatoEncabezadoSensores -Ruta $f.FullName
            if (-not $formato) { continue }
            $igual = $false
            foreach ($i in $importados) {
                if ($i.Length -eq $f.Length -and (Get-FileHash -LiteralPath $i.FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash) { $igual = $true }
            }
            if ($igual) { continue }
            $equipo = Test-EquipoCsvSensores -Expediente $Expediente -Ruta $f.FullName
            [pscustomobject][ordered]@{
                Ruta       = $f.FullName
                Nombre     = $f.Name
                Donde      = $k
                Fecha      = $f.LastWriteTime
                KB         = [math]::Round($f.Length / 1KB)
                Formato    = $formato
                # HWiNFO escribe cada 2 segundos: si cambió hace poco, todavía está grabando.
                EnCurso    = (($Ahora - $f.LastWriteTime).TotalSeconds -lt 15)
                OtroEquipo = ($equipo.Coincide -eq $false)
                Equipo     = $equipo.Texto
            }
        }
    }
    @($lista | Sort-Object @{ Expression = { $_.OtroEquipo } }, @{ Expression = { $_.Fecha }; Descending = $true })
}

function Remove-CsvSensoresOrigen {
    # Saca del equipo el CSV original ya importado, solo si es idéntico (SHA-256) al sensores.csv que quedó en
    # el expediente. Devuelve $true si lo sacó. Es el registro del técnico, no un archivo del cliente.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][string]$Atencion,
        [Parameter(Mandatory)][ValidateSet('antes', 'despues')][string]$Momento,
        [Parameter(Mandatory)][string]$Ruta
    )
    $copia = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) $Momento) 'sensores.csv'
    if (-not [IO.File]::Exists($copia) -or -not [IO.File]::Exists($Ruta)) { return $false }
    if ((Get-FileHash -LiteralPath $copia -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $Ruta -Algorithm SHA256).Hash) {
        throw 'El CSV cambió desde que se importó: no se saca (¿HWiNFO sigue grabando?)'
    }
    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Sacar el CSV original del equipo')) { return $false }
    [IO.File]::Delete($Ruta)
    Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto ('CALOR {0} | CSV original {1} sacado del equipo (copia idéntica en sensores.csv)' -f $Momento.ToUpperInvariant(), [IO.Path]::GetFileName($Ruta))
    $true
}