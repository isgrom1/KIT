# Salidas.ps1 - diagnostico.json, metricas.json, csv\*.csv y resumen.txt dentro de la carpeta de la atención.
# Todo pasa por ConvertTo-Protegido antes de escribirse.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

function Add-Tabla {
    # Registra una tabla para exportarla como csv\NN_<nombre>.csv (NN = sección actual).
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [AllowNull()][AllowEmptyCollection()][object[]]$Filas
    )
    $clave = '{0:00}_{1}' -f $script:Ctx.SeccionNumero, $Nombre
    $script:Ctx.Tablas[$clave] = @($Filas | Where-Object { $null -ne $_ })
}

function ConvertTo-CeldaCsv {
    # Excel en español: decimales con coma, Sí/No, listas separadas con " | ".
    param([AllowNull()]$Valor)
    if ($null -eq $Valor) { return '' }
    if ($Valor -is [bool]) { if ($Valor) { return 'Sí' } else { return 'No' } }
    if ($Valor -is [double] -or $Valor -is [single] -or $Valor -is [decimal]) { return ([double]$Valor).ToString('0.##', $script:CulturaCL) }
    if ($Valor -is [string]) { return $Valor }
    if ($Valor -is [System.Collections.IEnumerable] -and $Valor -isnot [System.Collections.IDictionary]) {
        return (@($Valor | ForEach-Object { ConvertTo-CeldaCsv $_ }) -join ' | ')
    }
    "$Valor"
}

function Export-Resultados {
    $carpeta = $script:Ctx.CarpetaCliente
    $doc = [ordered]@{
        kit         = [ordered]@{
            version      = $script:Ctx.Version
            generado     = ConvertTo-TextoFecha $script:Ctx.Inicio
            duracion_seg = [math]::Round($script:Ctx.Reloj.Elapsed.TotalSeconds, 1)
            parametros   = $script:Ctx.Parametros
            expediente   = $(if ($script:Ctx.Expediente) { [ordered]@{ id = $script:Ctx.Expediente.Id; atencion = $script:Ctx.Expediente.Atencion; momento = $script:Ctx.Expediente.Momento } } else { $null })
            identidad    = $script:Ctx.Identidad
            admin        = $script:Ctx.Admin
            secciones    = $script:Ctx.Secciones
        }
        alertas     = Get-AlertasOrdenadas
        incompletos = $script:Ctx.Incompletos
        errores     = $script:Ctx.Errores
        datos       = $script:Ctx.Datos
    }
    $json = ConvertTo-Protegido $doc | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText((Join-Path $carpeta 'diagnostico.json'), $json, $script:Utf8SinBom)
    try {
        $metricas = ConvertTo-Protegido (Get-Metricas) | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText((Join-Path $carpeta 'metricas.json'), $metricas, $script:Utf8SinBom)
    } catch {
        Add-ErrorPaso -Paso 'metricas.json' -Registro $_
    }

    $carpetaCsv = Join-Path $carpeta 'csv'
    foreach ($nombre in $script:Ctx.Tablas.Keys) {
        $filas = @($script:Ctx.Tablas[$nombre])
        if ($filas.Count -eq 0) { continue }
        $salida = foreach ($f in (ConvertTo-Protegido $filas)) {
            $o = [ordered]@{}
            foreach ($p in $f.PSObject.Properties) { $o[$p.Name] = ConvertTo-CeldaCsv $p.Value }
            [pscustomobject]$o
        }
        $salida | Export-Csv -LiteralPath (Join-Path $carpetaCsv "$nombre.csv") -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    }
    Export-Resumen
}

function Export-DiscosCrystal {
    # discos.txt = informe de CrystalDiskInfo (/CopyExit), que lee el SMART aunque Windows no lo reciba
    # (Intel RST/VMD). Se corre una copia dentro de la carpeta de la medición para que el historial SMART
    # que guarda junto a su exe (con las series de los discos) no se acumule en el USB; la copia se
    # borra al terminar. Devuelve $true si quedó discos.txt.
    $origen = Join-Path $script:Ctx.RaizKit 'herramientas\CrystalDiskInfo'
    $exe = if ([Environment]::Is64BitOperatingSystem) { 'DiskInfo64.exe' } else { 'DiskInfo32.exe' }
    if (-not [IO.File]::Exists((Join-Path $origen $exe))) {
        Write-LogKit -Mensaje 'CrystalDiskInfo no está en herramientas\: no se genera discos.txt'
        return $false
    }
    if (-not $script:Ctx.Admin.Elevado) {
        Add-Incompleto -Parte 'discos.txt (CrystalDiskInfo)'
        return $false
    }
    $copia = Join-Path $script:Ctx.CarpetaCliente '_crystaldiskinfo'
    try {
        Copy-Item -LiteralPath $origen -Destination $copia -Recurse -Force
        $r = Invoke-Externo -Exe (Join-Path $copia $exe) -Argumentos '/CopyExit' -TimeoutSeg 120
        $txt = Join-Path $copia 'DiskInfo.txt'
        if (-not [IO.File]::Exists($txt)) {
            throw ('CrystalDiskInfo no generó DiskInfo.txt (código {0}{1})' -f $r.Codigo, $(if ($r.TimeOut) { ', tiempo agotado' } else { '' }))
        }
        # ReadAllText reconoce el BOM de UTF-16 si viene; se reescribe en UTF-8 con BOM como el resto.
        [IO.File]::WriteAllText((Join-Path $script:Ctx.CarpetaCliente 'discos.txt'), (Protect-Texto ([IO.File]::ReadAllText($txt))), $script:Utf8Bom)
        Write-LogKit -Mensaje "discos.txt generado con CrystalDiskInfo (código $($r.Codigo))"
        $true
    } finally {
        if ([IO.Directory]::Exists($copia)) { Remove-Item -LiteralPath $copia -Recurse -Force }
    }
}

function Read-DiscosCrystal {
    # Lee discos.txt de CrystalDiskInfo. Los nombres de los atributos vienen traducidos, así que se
    # leen por ID: NVMe 01 aviso crítico, 03 repuesto disponible, 05 % de uso, 0D apagados no seguros,
    # 0E errores de integridad de datos; ATA 05 reasignados, C5 pendientes, C6 no corregibles.
    param([Parameter(Mandatory)][string]$Ruta)
    $lineas = [IO.File]::ReadAllLines($Ruta)
    $discos = New-Object System.Collections.Generic.List[object]
    $d = $null
    $enTabla = $false
    $ata = $false
    foreach ($l in $lineas) {
        # Bloque de detalle: " (02) SAMSUNG MZVLQ512HBLU-00BTW" (la lista del inicio trae " : " y se salta).
        if ($l -match '^\s*\((\d+)\)\s+(.+?)\s*$' -and $l -notmatch ' : ') {
            $d = [ordered]@{ Numero = [int]$Matches[1]; Modelo = $Matches[2]; Interfaz = $null; SaludPct = $null; SaludTexto = $null; TemperaturaC = $null; HorasEncendido = $null
                Nvme = $false; AvisoCritico = $null; RepuestoPct = $null; UsoPct = $null; ApagadosNoSeguros = $null; ErroresMedio = $null; Reasignados = $null; Pendientes = $null; NoCorregibles = $null; Letras = $null }
            $discos.Add($d)
            $enTabla = $false
            continue
        }
        if (-not $d) { continue }
        if ($l -match '^-- (\S+)') { $enTabla = ($Matches[1] -eq 'S.M.A.R.T.'); continue }
        if ($enTabla) {
            if ($l -match '^ID\s') { $ata = $l -match '\bCur\b'; continue }
            $m = if ($ata) { [regex]::Match($l, '^([0-9A-F]{2})\s+\S+\s+\S+\s+\S+\s+([0-9A-F]{12})\s') } else { [regex]::Match($l, '^([0-9A-F]{2})\s+([0-9A-F]{12})\s') }
            if (-not $m.Success) { continue }
            $raw = [Convert]::ToInt64($m.Groups[2].Value, 16)
            switch ("$($ata)|$($m.Groups[1].Value)") {
                'False|01' { $d.AvisoCritico = $raw }
                'False|03' { $d.RepuestoPct = $raw }
                'False|05' { $d.UsoPct = $raw }
                'False|0D' { $d.ApagadosNoSeguros = $raw }
                'False|0E' { $d.ErroresMedio = $raw }
                'True|05' { $d.Reasignados = $raw }
                'True|C5' { $d.Pendientes = $raw }
                'True|C6' { $d.NoCorregibles = $raw }
            }
            continue
        }
        if ($l -notmatch '^\s*([A-Za-z][A-Za-z .]+?) : (.*)$') { continue }
        $valor = $Matches[2].Trim()
        switch ($Matches[1]) {
            'Model' { $d.Modelo = $valor }
            'Interface' { $d.Interfaz = $valor; $d.Nvme = ($valor -match 'NVM') }
            'Temperature' { if ($valor -match '^(\d+)\s*C') { $d.TemperaturaC = [int]$Matches[1] } }
            'Power On Hours' { if ($valor -match '^(\d+)') { $d.HorasEncendido = [int]$Matches[1] } }
            'Health Status' { $d.SaludTexto = ($valor -replace '\s*\(.*$', ''); if ($valor -match '\((\d+)\s*%\)') { $d.SaludPct = [int]$Matches[1] } }
            'Drive Letter' { $d.Letras = $valor }
        }
    }
    foreach ($x in $discos) { [pscustomobject]$x }
}

function Find-SmartCrystal {
    # El disco de discos.txt que corresponde a uno de Windows (Windows antepone "NVMe" al modelo).
    param([AllowNull()][object[]]$Lista, [Parameter(Mandatory)]$Disco)
    foreach ($c in @($Lista | Where-Object { $_ -and $_.Modelo })) {
        if ("$($Disco.Modelo)" -like "*$($c.Modelo)*" -or "$($c.Modelo)" -like "*$($Disco.Modelo)*") { return $c }
    }
    $null
}

function Get-Metricas {
    # Los valores que comparan los motivos LENTO y REVISION entre el "antes" y el "después".
    # Lo que no se midió (sección omitida o sin admin) queda en null.
    $datos = $script:Ctx.Datos
    $eq = $datos['equipo']; $uso = $datos['uso']; $arr = $datos['arranque']; $esp = $datos['espacio']
    $hw = $datos['hardware']; $sw = $datos['software']; $est = $datos['estabilidad']
    $minutos = $null
    if ($eq -and $eq.UltimoArranque) {
        $ua = $eq.UltimoArranque
        if ($ua -isnot [datetime]) { $ua = [datetime]::ParseExact("$ua", 'yyyy-MM-dd HH:mm:ss', $script:Invariante) }
        $minutos = [int][math]::Round(($script:Ctx.Inicio - $ua).TotalMinutes)
    }
    $arranque = $null
    if ($arr -and $arr.TiempoArranque) {
        $t = $arr.TiempoArranque
        # Solo cuenta como medida si es reciente: un arranque de hace meses no sirve para comparar.
        $arranque = [ordered]@{ disponible = ($t.Disponible -and $t.Vigente); motivo = $t.Motivo; ultimo_seg = $t.UltimoSeg; escritorio_seg = $t.EscritorioSeg; posterior_seg = $t.PosteriorSeg; mediana_ultimos5_seg = $t.MedianaSeg; fecha = $t.Fecha }
    }
    $inicio = $null
    if ($arr) {
        $hab = @(@($arr.Entradas) + @($arr.AppsStore) | Where-Object { $_ -and $_.Habilitado -and $_.Ubicacion -notlike '*RunOnce*' })
        $inicio = [ordered]@{
            programas_habilitados = $hab.Count
            tareas_terceros       = @($arr.Tareas | Where-Object { $_ }).Count
            servicios_terceros    = $(if ($arr.Servicios) { @($arr.Servicios.Terceros).Count } else { $null })
        }
    }
    $bateria = $null
    $b = @($hw.Baterias | Where-Object { $_ }) | Select-Object -First 1
    if ($b) { $bateria = [ordered]@{ salud_pct = $b.SaludPct; ciclos = $b.Ciclos; diseno_mwh = $b.DisenoMWh; carga_completa_mwh = $b.CargaCompletaMWh } }
    $vigilar = 'optimizador', 'driver_updater', 'limpiador', 'activador', 'pup'
    [ordered]@{
        version                = 1
        generado               = ConvertTo-TextoFecha $script:Ctx.Inicio
        admin                  = [bool]$script:Ctx.Admin.Elevado
        minutos_desde_arranque = $minutos
        arranque               = $arranque
        ram                    = $(if ($uso -and $uso.Memoria) { [ordered]@{ total_gb = $uso.Memoria.TotalGB; usada_gb = $uso.Memoria.UsadaGB; uso_pct = $uso.Memoria.UsoPct } } else { $null })
        cpu                    = $(if ($uso -and $uso.Cpu) { [ordered]@{ uso_total_pct = $uso.Cpu.UsoTotalPct; muestra_seg = $uso.Cpu.MuestraSeg } } else { $null })
        inicio                 = $inicio
        espacio                = @($esp.Volumenes | Where-Object { $_ -and -not $_.EsKit } | ForEach-Object { [ordered]@{ unidad = $_.Unidad; sistema = $_.EsSistema; medio = $_.Medio; total_gb = $_.TotalGB; libre_gb = $_.LibreGB; libre_pct = $_.LibrePct } })
        discos                 = @($hw.Discos | Where-Object { $_ } | ForEach-Object {
                # Con discos.txt (CrystalDiskInfo) se usan sus datos SMART, que valen aunque Windows no los reciba.
                $c = if ($hw.Contains('SmartCrystal')) { Find-SmartCrystal -Lista $hw['SmartCrystal'] -Disco $_ } else { $null }
                [ordered]@{
                    disco = $_.Disco; modelo = $_.Modelo; tipo = $_.Tipo; salud = $_.Salud; smart = $(if ($c) { 'CrystalDiskInfo' } else { $_.Smart })
                    salud_smart_pct = $(if ($c) { $c.SaludPct } else { $null })
                    desgaste_pct = $(if ($c -and $null -ne $c.UsoPct) { $c.UsoPct } else { $_.DesgastePct })
                    temperatura_c = $(if ($c -and $c.TemperaturaC) { $c.TemperaturaC } else { $_.TemperaturaC })
                    errores_medio = $(if ($c) { $c.ErroresMedio } else { $null })
                }
            })
        bateria                = $bateria
        software_a_revisar     = @($sw.Detectados | Where-Object { $_ -and $_.Categoria -in $vigilar } | ForEach-Object { "$($_.Nombre) ($($_.Categoria))" } | Sort-Object -Unique)
        estabilidad            = $(if ($est) { [ordered]@{ dias = $est.Dias; apagados_inesperados = $est.Apagados; pantallazos = $est.Pantallazos; errores_disco = $est.ErroresDisco } } else { $null })
    }
}

function Get-LineaTiempos {
    $total = $script:Ctx.Reloj.Elapsed.TotalSeconds
    $esp = $script:Ctx.Datos['espacio']
    if ($esp -and $esp.Recorrido -and $esp.Recorrido.Ejecutado) {
        $rec = [double]$esp.Recorrido.Segundos
        $estado = if ($esp.Recorrido.Parcial) { 'PARCIAL' } else { 'completo' }
        return 'Tiempo     : total {0} | sin recorrido de espacio {1} | recorrido de espacio {2} ({3})' -f (Format-Duracion $total), (Format-Duracion ($total - $rec)), (Format-Duracion $rec), $estado
    }
    'Tiempo     : total {0} (sin recorrido de espacio)' -f (Format-Duracion $total)
}

function Export-Resumen {
    $l = New-Object System.Collections.Generic.List[string]
    $doble = '=' * 100
    $simple = '-' * 100
    $l.Add($doble)
    $l.Add((' DIAGNÓSTICO KIT SERVICIO | {0} | v{1}' -f (ConvertTo-TextoFecha $script:Ctx.Inicio), $script:Ctx.Version))
    $l.Add($doble)
    foreach ($clave in 'equipo', 'windows', 'hardware') {
        $d = $script:Ctx.Datos[$clave]
        if ($d -and $d.Linea) { $l.Add($d.Linea) }
    }
    $admin = if ($script:Ctx.Admin.Elevado) { 'SÍ (elevado)' } elseif ($script:Ctx.Admin.MiembroAdministradores) { 'NO (usuario admin sin elevar)' } else { 'NO (usuario estándar)' }
    $l.Add("Admin      : $admin")
    $l.Add((Get-LineaTiempos))
    if ($script:Ctx.Expediente) {
        $l.Add(('Expediente : {0} | atención {1} | medición {2}' -f $script:Ctx.Expediente.Id, $script:Ctx.Expediente.Atencion, $script:Ctx.Expediente.Momento.ToUpperInvariant()))
    } else {
        $l.Add('Carpeta    : ' + (Split-Path -Leaf $script:Ctx.CarpetaCliente))
    }

    $alertas = Get-AlertasOrdenadas
    $n = @{ CRITICO = 0; AVISO = 0; INFO = 0 }
    foreach ($a in $alertas) { $n[$a.Severidad]++ }
    $l.Add('')
    $l.Add(('ALERTAS ({0} críticas, {1} avisos, {2} info)' -f $n.CRITICO, $n.AVISO, $n.INFO))
    $l.Add($simple)
    if ($alertas.Count -eq 0) { $l.Add('(sin alertas)') }
    foreach ($a in $alertas) { $l.Add(('{0,-9} {1}' -f "[$($a.Severidad)]", $a.Texto)) }

    $l.Add('')
    $l.Add('SECCIONES')
    $l.Add($simple)
    foreach ($s in $script:Ctx.Secciones) {
        $l.Add(('{0,2}. {1,-22} {2,-12} {3,7} s' -f $s.N, $s.Seccion, $s.Estado, (Format-Numero $s.Segundos 1)))
    }
    if ($script:Ctx.Incompletos.Count -gt 0) {
        $l.Add('')
        $l.Add('INCOMPLETO')
        $l.Add($simple)
        foreach ($i in $script:Ctx.Incompletos) { $l.Add("- [$($i.Seccion)] $($i.Parte): $($i.Motivo)") }
    }
    if ($script:Ctx.Errores.Count -gt 0) {
        $l.Add('')
        $l.Add('ERRORES (la sección siguió con lo demás)')
        $l.Add($simple)
        foreach ($e in $script:Ctx.Errores) { $l.Add("- [$($e.Seccion)] $($e.Paso): $($e.Mensaje) $($e.Ubicacion)") }
    }

    $l.Add('')
    $l.Add('DETALLE')
    $l.Add($doble)
    foreach ($s in $script:Ctx.Secciones) {
        $def = $script:Catalogo | Where-Object { $_.N -eq $s.N }
        $funcion = "Format-Resumen$($def.Base)"
        if ($null -eq $script:Ctx.Datos[$def.Clave] -or -not (Get-Command $funcion -ErrorAction SilentlyContinue)) { continue }
        $l.Add('')
        $l.Add("--- $($s.N). $($s.Seccion) " + ('-' * [math]::Max(3, 92 - $s.Seccion.Length)))
        try {
            foreach ($linea in @(& $funcion)) { $l.Add([string]$linea) }
        } catch {
            $l.Add("(no se pudo armar el detalle: $($_.Exception.Message))")
        }
    }
    $texto = ($l | ForEach-Object { Protect-Texto $_ }) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $script:Ctx.CarpetaCliente 'resumen.txt'), $texto + "`r`n", $script:Utf8Bom)
}
