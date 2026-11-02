# Sensores.ps1 - Lee el CSV de un monitor de sensores (HWiNFO en inglés o español, LibreHardwareMonitor)
# y lo resume: media, p95 y máximo por métrica, % del tiempo con throttling, minutos sobre el umbral,
# duración y una serie reducida para graficar.
# - Detecta codificación (BOM, UTF-8 o ANSI), separador y formato. Descarta los encabezados repetidos
#   y la fila de grupos que HWiNFO agrega al final.
# - Reconoce las columnas con config\sensores.json. Lo que no está queda null: nunca se inventa.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'Microsoft.VisualBasic viene con .NET Framework en todo Windows 10/11 y se carga con Add-Type -AssemblyName')]
param()

Add-Type -AssemblyName Microsoft.VisualBasic

# HWiNFO escribe la hora sin ceros a la izquierda (1:50:4.974); LibreHardwareMonitor, al estilo EE.UU.
$script:FormatosHwinfo = [string[]]@('d.M.yyyy H:m:s.FFF', 'd.M.yyyy H:m:s', 'd/M/yyyy H:m:s.FFF', 'd/M/yyyy H:m:s', 'd-M-yyyy H:m:s.FFF', 'd-M-yyyy H:m:s')
$script:FormatosLhm = [string[]]@('M/d/yyyy H:mm:ss', 'MM/dd/yyyy HH:mm:ss', 'yyyy-MM-dd HH:mm:ss', 'd-M-yyyy H:mm:ss', 'd.M.yyyy H:mm:ss')

function Read-TextoSensores {
    # Texto y codificación: BOM si lo hay; si no, UTF-8 estricto y, si no calza, ANSI (Windows-1252).
    param([Parameter(Mandatory)][string]$Ruta)
    $b = [IO.File]::ReadAllBytes($Ruta)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return @{ Texto = [Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3); Codificacion = 'UTF-8 con BOM' } }
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return @{ Texto = [Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2); Codificacion = 'UTF-16 LE' } }
    if ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { return @{ Texto = [Text.Encoding]::BigEndianUnicode.GetString($b, 2, $b.Length - 2); Codificacion = 'UTF-16 BE' } }
    try {
        return @{ Texto = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b); Codificacion = 'UTF-8' }
    } catch {
        return @{ Texto = [Text.Encoding]::GetEncoding(1252).GetString($b); Codificacion = 'ANSI (Windows-1252)' }
    }
}

function Get-EstadisticaSerie {
    param([AllowEmptyCollection()][object[]]$Valores)
    $v = [double[]]@($Valores | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    [Array]::Sort($v)
    $suma = 0.0
    foreach ($x in $v) { $suma += $x }
    [ordered]@{
        n     = $v.Count
        media = [math]::Round($suma / $v.Count, 1)
        p95   = [math]::Round($v[[int][math]::Max(0, [math]::Ceiling(0.95 * $v.Count) - 1)], 1)
        max   = [math]::Round($v[$v.Count - 1], 1)
        min   = [math]::Round($v[0], 1)
    }
}

function Read-SensoresCsv {
    # Devuelve el resumen del CSV (ver comentario del archivo). Lanza un error claro si el formato no
    # es de HWiNFO ni de LibreHardwareMonitor.
    param([Parameter(Mandatory)][string]$Ruta)
    $cfg = Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'sensores.json')
    $lectura = Read-TextoSensores -Ruta $Ruta
    $texto = $lectura.Texto
    $primera = ($texto -split "`r?`n", 2)[0]
    $sinComillas = [regex]::Replace($primera, '"[^"]*"', '')
    $cuenta = @{ ',' = ($sinComillas.Split(',').Count - 1); ';' = ($sinComillas.Split(';').Count - 1); "`t" = ($sinComillas.Split("`t").Count - 1) }
    $sep = ($cuenta.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key

    $filas = New-Object System.Collections.Generic.List[string[]]
    $malas = 0
    $lector = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser((New-Object IO.StringReader($texto)))
    try {
        $lector.SetDelimiters([string]$sep)
        $lector.HasFieldsEnclosedInQuotes = $true
        $lector.TrimWhiteSpace = $true
        while (-not $lector.EndOfData) {
            try { $filas.Add($lector.ReadFields()) } catch [Microsoft.VisualBasic.FileIO.MalformedLineException] { $malas++ }
        }
    } finally { $lector.Close() }
    if ($filas.Count -lt 2) { throw 'El CSV no tiene datos' }

    $c0 = $filas[0]
    $tipos = $null
    if ($c0.Count -ge 2 -and $c0[0] -eq 'Date' -and $c0[1] -eq 'Time') {
        $formato = 'HWiNFO'
        $nombres = $c0
        $desde = 1
    } elseif ($c0.Count -ge 2 -and $c0[0] -eq '' -and $c0[1] -like '/*' -and $filas[1][0] -eq 'Time') {
        $formato = 'LibreHardwareMonitor'
        $nombres = $filas[1]
        $tipos = @($c0 | ForEach-Object { $p = "$_".Trim('/').Split('/'); if ($p.Count -ge 2) { $p[$p.Count - 2] } else { '' } })
        $desde = 2
    } else {
        throw 'Formato no reconocido: se espera un CSV de HWiNFO o de LibreHardwareMonitor'
    }

    # Filas de datos con fecha válida; lo demás (encabezados repetidos, fila de grupos) se descarta.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $datos = New-Object System.Collections.Generic.List[string[]]
    $tiempos = New-Object System.Collections.Generic.List[datetime]
    $descartadas = $malas
    for ($i = $desde; $i -lt $filas.Count; $i++) {
        $r = $filas[$i]
        $t = [datetime]::MinValue
        $ok = if ($formato -eq 'HWiNFO') {
            $r.Count -ge 2 -and $r[0] -match '^\d{1,2}[./-]\d{1,2}[./-]\d{4}$' -and [datetime]::TryParseExact("$($r[0]) $($r[1])", $script:FormatosHwinfo, $inv, 'None', [ref]$t)
        } else {
            $r.Count -ge 1 -and ([datetime]::TryParseExact($r[0], $script:FormatosLhm, $inv, 'None', [ref]$t) -or [datetime]::TryParse($r[0], $inv, 'None', [ref]$t))
        }
        if ($ok) { $datos.Add($r); $tiempos.Add($t) } else { $descartadas++ }
    }
    if ($datos.Count -eq 0) { throw 'El CSV no tiene filas de datos con fecha y hora reconocibles' }

    # Coma decimal solo si el separador no es la coma y los números la usan.
    $nfi = $inv.NumberFormat
    if ($sep -ne ',') {
        $muestra = ($datos[0] | Select-Object -Skip 2) -join ' '
        if ($muestra -match '\d,\d' -and $muestra -notmatch '\d\.\d') { $nfi = $inv.NumberFormat.Clone(); $nfi.NumberDecimalSeparator = ',' }
    }
    $numero = {
        param([string]$s)
        $v = 0.0
        if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, $nfi, [ref]$v)) { $v } else { $null }
    }
    $buscar = {
        param([object[]]$Patrones, [string]$Tipo)
        $res = New-Object System.Collections.Generic.List[int]
        foreach ($pat in @($Patrones | Where-Object { $_ })) {
            for ($c = 0; $c -lt $nombres.Count; $c++) {
                if ($tipos -and $Tipo -and $c -lt $tipos.Count -and $tipos[$c] -ne $Tipo) { continue }
                if ($nombres[$c] -match "(?i)$pat" -and -not $res.Contains($c)) { $res.Add($c) }
            }
        }
        # Sin coma: los índices salen sueltos y quien llama los junta con @().
        $res.ToArray()
    }

    $series = [ordered]@{}
    $columnas = [ordered]@{}
    foreach ($p in $cfg.metricas.PSObject.Properties) {
        $nombre = $p.Name
        $def = $p.Value
        $tipo = if ($tipos) { $def.lhm_tipo } else { $null }
        $factor = if ($tipos -and $def.lhm_factor) { [double]$def.lhm_factor } else { 1.0 }
        $patrones = if ($tipos -and $def.lhm_patrones) { $def.lhm_patrones } else { $def.patrones }
        $serie = New-Object System.Collections.Generic.List[object]
        $directa = @(& $buscar $patrones $tipo)
        if ($directa.Count -gt 0) {
            $c = $directa[0]
            foreach ($r in $datos) { $v = if ($c -lt $r.Count) { & $numero $r[$c] } else { $null }; $serie.Add($(if ($null -ne $v) { $v * $factor } else { $null })) }
            $columnas[$nombre] = $nombres[$c]
        } elseif ($def.agregado_max -or $def.agregado_prom) {
            $esMax = [bool]$def.agregado_max
            $cols = @(& $buscar $(if ($esMax) { $def.agregado_max } else { $def.agregado_prom }) $tipo)
            if ($cols.Count -gt 0) {
                foreach ($r in $datos) {
                    $vals = @(foreach ($c in $cols) { if ($c -lt $r.Count) { & $numero $r[$c] } }) | Where-Object { $null -ne $_ }
                    $serie.Add($(if (@($vals).Count -eq 0) { $null } elseif ($esMax) { ($vals | Measure-Object -Maximum).Maximum } else { ($vals | Measure-Object -Average).Average }))
                }
                $columnas[$nombre] = '{0} de {1} columnas ({2}...)' -f $(if ($esMax) { 'máximo' } else { 'promedio' }), $cols.Count, $nombres[$cols[0]]
            }
        } elseif ($def.cualquiera) {
            $cols = @(& $buscar $def.cualquiera $null)
            if ($cols.Count -gt 0) {
                foreach ($r in $datos) {
                    $celdas = @(foreach ($c in $cols) { if ($c -lt $r.Count -and $r[$c]) { $r[$c] } })
                    $serie.Add($(if ($celdas.Count -eq 0) { $null } elseif (@($celdas | Where-Object { $_ -match '^(?i)(yes|s[ií]|true|1)$' }).Count -gt 0) { 1.0 } else { 0.0 }))
                }
                $columnas[$nombre] = @($cols | ForEach-Object { $nombres[$_] }) -join ' + '
            }
        }
        if (-not $columnas.Contains($nombre)) { $columnas[$nombre] = $null }
        $series[$nombre] = $(if ($serie.Count -gt 0) { $serie.ToArray() } else { $null })
    }

    # Tiempos: intervalo típico (mediana) y duración.
    $deltas = [double[]]@(for ($i = 1; $i -lt $tiempos.Count; $i++) { ($tiempos[$i] - $tiempos[$i - 1]).TotalSeconds })
    $intervalo = $null
    if ($deltas.Count -gt 0) { [Array]::Sort($deltas); $intervalo = [math]::Round($deltas[[int][math]::Floor($deltas.Count / 2)], 2) }
    $duracion = [math]::Round(($tiempos[$tiempos.Count - 1] - $tiempos[0]).TotalMinutes, 1)

    $metricas = [ordered]@{}
    foreach ($k in $series.Keys) {
        if ($k -eq 'cpu_throttling') { continue }
        $e = if ($series[$k]) { Get-EstadisticaSerie -Valores $series[$k] } else { $null }
        if ($e) { $e['unidad'] = $cfg.metricas.$k.unidad }
        $metricas[$k] = $e
    }
    $thr = $null
    if ($series['cpu_throttling']) {
        $marcas = @($series['cpu_throttling'] | Where-Object { $null -ne $_ })
        if ($marcas.Count -gt 0) { $thr = [math]::Round(100 * ($marcas | Measure-Object -Sum).Sum / $marcas.Count, 1) }
    }
    $temp = if ($series['cpu_temp_paquete']) { 'cpu_temp_paquete' } elseif ($series['cpu_temp_nucleo_max']) { 'cpu_temp_nucleo_max' } else { $null }
    $umbral = [double]$cfg.umbral_alto_c
    $tj = [double]$cfg.tjmax_aviso_c
    $minSobre = $null
    $pctTj = $null
    if ($temp -and $intervalo) {
        $vals = @($series[$temp] | Where-Object { $null -ne $_ })
        $minSobre = [math]::Round(@($vals | Where-Object { $_ -gt $umbral }).Count * $intervalo / 60, 1)
        if ($vals.Count -gt 0) { $pctTj = [math]::Round(100 * @($vals | Where-Object { $_ -ge $tj }).Count / $vals.Count, 1) }
    }
    # ¿Pierde velocidad por calor? Primero el sensor de throttling; si no lo marca, el tiempo pegado al
    # límite térmico (dice de dónde sale). Sin ninguno de los dos: null.
    $pierde = [ordered]@{ valor = $null; fuente = $null }
    $txtThr = if ($null -ne $thr) { Format-Numero $thr 1 } else { '' }
    $txtTj = if ($null -ne $pctTj) { Format-Numero $pctTj 1 } else { '' }
    if ($null -ne $thr -and $thr -gt [double]$cfg.throttling_aviso_pct) {
        $pierde.valor = $true; $pierde.fuente = "sensor de throttling: $txtThr % del tiempo"
    } elseif ($null -ne $pctTj -and $pctTj -ge [double]$cfg.tjmax_aviso_pct_tiempo) {
        $pierde.valor = $true; $pierde.fuente = "CPU a $tj °C o más el $txtTj % del tiempo$(if ($null -ne $thr) { ' (el sensor de throttling no lo marcó)' } else { ' (sin sensor de throttling en el CSV)' })"
    } elseif ($null -ne $thr -or $null -ne $pctTj) {
        $pierde.valor = $false; $pierde.fuente = $(if ($null -ne $thr) { "sensor de throttling: $txtThr % del tiempo" } else { "CPU a $tj °C o más el $txtTj % del tiempo" })
    }

    # Serie reducida (promedio por tramo) para graficar antes y después superpuestos.
    $puntos = [math]::Min([int]$cfg.puntos_serie, $datos.Count)
    $serieGraf = New-Object System.Collections.Generic.List[object]
    for ($b = 0; $b -lt $puntos; $b++) {
        $ini = [int][math]::Floor($b * $datos.Count / $puntos)
        $fin = [int][math]::Floor(($b + 1) * $datos.Count / $puntos) - 1
        $punto = [ordered]@{ minuto = [math]::Round(($tiempos[$ini] - $tiempos[0]).TotalMinutes, 2) }
        foreach ($k in @('cpu_temp_paquete', 'cpu_temp_nucleo_max', 'gpu_temp', 'cpu_frec_efectiva')) {
            $vals = if ($series[$k]) { @($series[$k][$ini..$fin] | Where-Object { $null -ne $_ }) } else { @() }
            $punto[$k] = $(if ($vals.Count -gt 0) { [math]::Round(($vals | Measure-Object -Average).Average, 1) } else { $null })
        }
        $serieGraf.Add($punto)
    }

    [ordered]@{
        archivo           = Split-Path -Leaf $Ruta
        formato           = $formato
        codificacion      = $lectura.Codificacion
        separador         = $(if ($sep -eq "`t") { 'tab' } else { $sep })
        coma_decimal      = ($nfi.NumberDecimalSeparator -eq ',')
        filas             = $datos.Count
        filas_descartadas = $descartadas
        inicio            = $tiempos[0].ToString('yyyy-MM-dd HH:mm:ss', $inv)
        fin               = $tiempos[$tiempos.Count - 1].ToString('yyyy-MM-dd HH:mm:ss', $inv)
        duracion_min      = $duracion
        intervalo_seg     = $intervalo
        columnas          = $columnas
        metricas          = $metricas
        throttling_pct    = $thr
        umbral_c          = $umbral
        minutos_sobre_umbral = $minSobre
        pct_tiempo_tjmax  = $pctTj
        pierde_velocidad  = $pierde
        serie             = $serieGraf.ToArray()
    }
}
