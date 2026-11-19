# InformeVisual.ps1 - Informe para el cliente con diseño de portafolio: puntaje de salud, áreas con
# semáforo, gráficos SVG (temperatura, espacio, arranques, RAM, batería), recomendaciones en una matriz
# impacto/esfuerzo y glosario. Lo usan las dos apps: el diagnóstico remoto (abrir_diagnostico.ps1) y el
# kit del pendrive (a partir del diagnostico.json de una atención).
# - Entra el diagnostico.json y, si hay, el resumen de Read-SensoresCsv. Lo que falta no se inventa: el
#   área se marca "no medida" y no cuenta en el puntaje.
# - Los gráficos son SVG armados aquí, sin JavaScript ni internet. Los números del SVG van con punto
#   (cultura invariante); los que lee el cliente, con coma (Format-Numero).
# - Necesita Comun.ps1 (contexto, Format-Numero), Mejoras.ps1 y, para el PDF, Informe.ps1 (Export-PdfInforme).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:InvVisual = [Globalization.CultureInfo]::InvariantCulture
$script:ColoresVisual = [ordered]@{ verde = '#1e8a52'; lima = '#6aa84f'; ambar = '#d4900a'; naranjo = '#e0661b'; rojo = '#c0392b'; gris = '#9aa5b1'; azul = '#1f5fa8' }

# Nombres que entiende el cliente para entradas de inicio conocidas.
$script:NombresInicio = @(
    @('^MicrosoftEdgeAutoLaunch', 'Microsoft Edge'), @('^TeamsTfwStartupTask|^MSTeams|^com\.squirrel\.Teams', 'Microsoft Teams'),
    @('^CrossDevice', 'Vínculo móvil'), @('^MicrosoftStartFeedProvider', 'Noticias del menú Inicio'), @('^btweb', 'BitTorrent Web'),
    @('^utweb|^uTorrent', 'uTorrent'), @('^RtkAudUService', 'Audio Realtek'), @('^SecurityHealth', 'Seguridad de Windows'),
    @('^launcherrsxruntime|^AMD', 'AMD Software'), @('^DAEMON Tools', 'DAEMON Tools'), @('^Steam$', 'Steam'), @('^OneDrive', 'OneDrive'),
    @('^Discord', 'Discord'), @('^Spotify', 'Spotify'), @('^EpicGames', 'Epic Games'), @('^YourPhone|^PhoneExperienceHost', 'Vínculo móvil')
)

function Get-NumSvg {
    param([double]$Valor, [int]$Decimales = 1)
    [math]::Round($Valor, $Decimales).ToString($script:InvVisual)
}

function Get-HtmlVisual { param($Texto) [Net.WebUtility]::HtmlEncode("$Texto") }

function Get-ColorPuntaje {
    param($Puntaje)
    if ($null -eq $Puntaje) { return $script:ColoresVisual.gris }
    if ($Puntaje -ge 85) { $script:ColoresVisual.verde } elseif ($Puntaje -ge 70) { $script:ColoresVisual.lima } elseif ($Puntaje -ge 55) { $script:ColoresVisual.ambar } elseif ($Puntaje -ge 40) { $script:ColoresVisual.naranjo } else { $script:ColoresVisual.rojo }
}

function Get-EtiquetaPuntaje {
    param($Puntaje)
    if ($null -eq $Puntaje) { return 'No medido' }
    if ($Puntaje -ge 85) { 'Muy bien' } elseif ($Puntaje -ge 70) { 'Bien' } elseif ($Puntaje -ge 55) { 'Mejorable' } elseif ($Puntaje -ge 40) { 'Necesita atención' } else { 'Urgente' }
}

function Get-NombreInicioCliente {
    param([string]$Nombre)
    foreach ($p in $script:NombresInicio) { if ($Nombre -match $p[0]) { return $p[1] } }
    $Nombre
}

function Get-NombreModeloVisual {
    # "Acer" + "Nitro AN515-43" + familia "Nitro 5" -> "Acer Nitro 5 AN515-43". Sin familia útil, fabricante y modelo.
    param([Parameter(Mandatory)]$Equipo)
    $mod = "$($Equipo.Modelo)".Trim()
    $fam = "$($Equipo.Familia)".Trim()
    if ($fam -and $fam -notmatch '(?i)^(default|to be filled|n/?a|0+|none)' -and $mod -notmatch [regex]::Escape($fam)) {
        $primera = ($fam -split ' ')[0]
        if ($mod -match "^$([regex]::Escape($primera))\s+(.+)$") { $mod = "$fam $($Matches[1])" }
    }
    $fab = "$($Equipo.Fabricante)".Trim()
    $txt = if ($fab -and $mod -notmatch "^$([regex]::Escape($fab))") { "$fab $mod" } else { $mod }
    ($txt -replace '\s+', ' ').Trim()
}

function Get-TemperaturaSensores {
    # Métrica de temperatura de CPU del resumen de sensores (paquete o, si no, el núcleo más caliente).
    param($Sensores)
    if (-not $Sensores -or -not $Sensores.metricas) { return $null }
    if ($Sensores.metricas.cpu_temp_paquete) { $Sensores.metricas.cpu_temp_paquete } else { $Sensores.metricas.cpu_temp_nucleo_max }
}

function Get-ReposoSensores {
    # Promedios de la serie antes del tramo bajo carga (el reposo de la prueba CALOR). $null si no hay tramo.
    param($Sensores)
    if (-not $Sensores -or -not $Sensores.carga -or -not $Sensores.serie) { return $null }
    $antes = @($Sensores.serie | Where-Object { $_ -and [double]$_.minuto -lt ([double]$Sensores.carga.inicio_min - 0.2) })
    if ($antes.Count -lt 3) { return $null }
    $prom = {
        param([string]$k)
        $v = @($antes | ForEach-Object { $_.$k } | Where-Object { $null -ne $_ })
        if ($v.Count) { [math]::Round(($v | Measure-Object -Average).Average, 1) } else { $null }
    }
    $temp = & $prom 'cpu_temp_paquete'
    if ($null -eq $temp) { $temp = & $prom 'cpu_temp_nucleo_max' }
    [ordered]@{ temp = $temp; uso = (& $prom 'cpu_uso'); frec = (& $prom 'cpu_frec_efectiva'); ventilador = (& $prom 'ventilador_cpu') }
}

# ---------------------------------------------------------------- puntaje por área

function Get-AreasSalud {
    # Seis áreas con puntaje 0-100 (o $null si no se midió), estado y una frase para el cliente. El puntaje
    # es una guía con reglas fijas (se explican al final del informe), no una medición de laboratorio.
    param([Parameter(Mandatory)]$Doc, $Sensores)
    $d = $Doc.datos
    $areas = New-Object System.Collections.Generic.List[object]
    $nueva = { param($clave, $nombre, $peso, $puntaje, $valor, $frase) $areas.Add([pscustomobject][ordered]@{ Clave = $clave; Nombre = $nombre; Peso = $peso; Puntaje = $(if ($null -ne $puntaje) { [int][math]::Round([math]::Max(0, [math]::Min(100, $puntaje))) } else { $null }); Valor = $valor; Frase = $frase }) }

    # Temperatura (prueba CALOR).
    $t = Get-TemperaturaSensores -Sensores $Sensores
    if ($t) {
        $max = [double]$t.max
        $p = if ($max -lt 80) { 100 } elseif ($max -lt 90) { 100 - ($max - 80) * 3 } elseif ($max -lt 95) { 70 - ($max - 90) * 6 } else { 30 }
        if ($Sensores.pierde_velocidad -and $Sensores.pierde_velocidad.valor) { $p = [math]::Min($p, 30) }
        $frase = if ($max -lt 80) { 'Temperatura cómoda bajo carga.' } elseif ($max -lt 90) { 'Se calienta bastante con carga, aún bajo el límite.' } elseif ($max -lt 95) { 'Trabaja muy caliente bajo carga.' } else { 'Llega a su límite de temperatura.' }
        & $nueva 'temperatura' 'Temperatura' 25 $p "$(Format-Numero $max 1) °C máx." $frase
    } else {
        & $nueva 'temperatura' 'Temperatura' 25 $null 'Sin prueba' 'No se hizo la prueba de temperatura.'
    }

    # Almacenamiento: espacio libre en el disco de Windows y salud de los discos.
    $c = @($d.espacio.Volumenes | Where-Object { $_ -and $_.EsSistema }) | Select-Object -First 1
    $discosMal = @($d.hardware.Discos | Where-Object { $_ -and -not $_.DelKit -and ("$($_.Salud)" -notmatch '^(Healthy|)$' -or ($null -ne $_.DesgastePct -and [double]$_.DesgastePct -ge [double]$script:Ctx.Config.umbrales.ssd_desgaste_pct)) })
    if ($c) {
        $lp = [double]$c.LibrePct
        $p = if ($lp -ge 25) { 100 } elseif ($lp -ge 20) { 85 } elseif ($lp -ge 15) { 70 } elseif ($lp -ge 10) { 50 } else { 25 }
        if ($discosMal.Count) { $p = [math]::Min($p, 30) }
        $frase = if ($discosMal.Count) { 'Un disco muestra señales de desgaste o falla.' } elseif ($lp -lt 20) { 'Discos sanos, pero el de Windows está casi lleno.' } else { 'Discos sanos y con espacio.' }
        & $nueva 'almacenamiento' 'Almacenamiento' 25 $p "$(Format-Numero $lp 0) % libre en $($c.Unidad)" $frase
    }

    # Estabilidad: apagados inesperados, pantallazos azules y errores de disco del último mes.
    $e = $d.estabilidad
    if ($e) {
        $p = 100 - 10 * [int]$e.Apagados - 20 * [int]$e.Pantallazos - 20 * [int]$e.ErroresDisco
        $frase = if ($p -ge 100) { 'Sin cortes ni errores en el último mes.' } else { '{0} apagado(s) inesperado(s), {1} pantallazo(s) azul(es) en {2} días.' -f $e.Apagados, $e.Pantallazos, $e.Dias }
        & $nueva 'estabilidad' 'Estabilidad' 15 $p "$([int]$e.Apagados + [int]$e.Pantallazos) eventos" $frase
    }

    # Seguridad: antivirus, firmas, arranque seguro, TPM, activación y soporte de Windows.
    $s = $d.seguridad
    $fallas = New-Object System.Collections.Generic.List[string]
    if (-not $s.Defender -or -not ($s.Defender.TiempoReal -or @($s.Antivirus | Where-Object { $_ -and $_.Activo }).Count)) { $fallas.Add('antivirus') }
    if ($s.Defender -and $s.Defender.Antivirus -and $null -ne $s.Defender.FirmasDias -and [int]$s.Defender.FirmasDias -gt [int]$script:Ctx.Config.umbrales.defender_firmas_dias) { $fallas.Add('firmas') }
    if ($s.SecureBoot -and $s.SecureBoot.Firmware -eq 'UEFI' -and -not $s.SecureBoot.Activo) { $fallas.Add('arranque seguro') }
    if ($d.windows.Licencia -and $d.windows.Licencia.Estado -ne 'Activado') { $fallas.Add('activación') }
    if ($d.windows.Soporte -and $d.windows.Soporte.EnTabla -and -not $d.windows.Soporte.Vigente) { $fallas.Add('soporte de Windows') }
    & $nueva 'seguridad' 'Seguridad' 15 (100 - 20 * $fallas.Count) $(if ($fallas.Count) { "$($fallas.Count) punto(s) a revisar" } else { 'Protegido' }) $(if ($fallas.Count) { 'Revisar: ' + ($fallas -join ', ') + '.' } else { 'Antivirus al día, Windows activado y con soporte.' })

    # Batería.
    $b = @($d.hardware.Baterias | Where-Object { $_ -and $null -ne $_.SaludPct }) | Select-Object -First 1
    if ($b) {
        $sp = [double]$b.SaludPct
        & $nueva 'bateria' 'Batería' 10 $sp "$(Format-Numero $sp 0) % de salud" $(if ($sp -ge 80) { 'Batería en buen estado.' } elseif ($sp -ge 50) { 'Desgaste normal por los años de uso.' } else { 'Batería gastada: conviene cambiarla.' })
    }

    # Encendido: tiempo del último arranque y cantidad de programas al inicio.
    $ta = $d.arranque.TiempoArranque
    if ($ta -and $ta.Disponible -and $null -ne $ta.UltimoSeg) {
        $seg = [double]$ta.UltimoSeg
        $p = if ($seg -le 30) { 100 } elseif ($seg -le 60) { 85 } elseif ($seg -le 90) { 70 } elseif ($seg -le 120) { 55 } else { 40 }
        $n = @(Get-InicioCliente -Doc $Doc).Count
        if ($n -gt 10) { $p -= 5 }
        & $nueva 'arranque' 'Encendido' 10 $p "$(Format-Numero $seg 0) s" "Tarda $(Format-Numero $seg 0) s en quedar listo; $n programas arrancan solos."
    }
    $areas.ToArray()
}

function Get-PuntajeGeneral {
    # Promedio ponderado de las áreas medidas.
    param([object[]]$Areas)
    $med = @($Areas | Where-Object { $null -ne $_.Puntaje })
    if (-not $med.Count) { return $null }
    $suma = 0.0; $pesos = 0.0
    foreach ($a in $med) { $suma += $a.Puntaje * $a.Peso; $pesos += $a.Peso }
    [int][math]::Round($suma / $pesos)
}

function Get-InicioCliente {
    # Programas que arrancan con Windows, con nombre para el cliente (sin RunOnce, que corre una sola vez).
    param([Parameter(Mandatory)]$Doc)
    $vistos = @{}
    $todas = @($Doc.datos.arranque.Entradas) + @($Doc.datos.arranque.AppsStore)
    foreach ($e in @($todas | Where-Object { $_ -and $_.Habilitado -and "$($_.Ubicacion)" -notmatch 'RunOnce' })) {
        $n = Get-NombreInicioCliente -Nombre $e.Nombre
        if ($vistos.ContainsKey($n)) { continue }
        $vistos[$n] = $true
        $win = "$($e.Empresa)" -match '(?i)^microsoft' -or "$($e.Ubicacion)" -match '(?i)^Store: (Microsoft|MSTeams)' -or $n -eq 'Seguridad de Windows'
        [pscustomobject]@{ Nombre = $n; Empresa = "$($e.Empresa)"; Windows = $win; Store = ("$($e.Ubicacion)" -like 'Store:*') }
    }
}

# ---------------------------------------------------------------- recomendaciones

function Get-PapeleraGB {
    # Lo que ocupa la papelera según el top de carpetas: por unidad, la carpeta $RECYCLE.BIN si aparece, o
    # si no, la suma de sus subcarpetas (una por usuario) del nivel 2.
    param([Parameter(Mandatory)]$Doc)
    $total = 0.0
    $tops = @($Doc.datos.espacio.TopCarpetas | Where-Object { $_ -and "$($_.Carpeta)" -match '^[A-Z]:\\\$RECYCLE\.BIN' })
    foreach ($u in @($tops | ForEach-Object { "$($_.Carpeta)".Substring(0, 2) } | Select-Object -Unique)) {
        $raiz = @($tops | Where-Object { "$($_.Carpeta)" -ieq "$u\`$RECYCLE.BIN" })
        if ($raiz.Count) { $total += [double]$raiz[0].TamanoGB; continue }
        foreach ($x in @($tops | Where-Object { "$($_.Carpeta)".StartsWith("$u\") -and $_.Nivel -eq 2 })) { $total += [double]$x.TamanoGB }
    }
    $total
}

function Get-RecomendacionesVisual {
    # Recomendaciones ordenadas por impacto (3 alto) y esfuerzo (1 bajo). Tipo: Servicio, Sin costo, Compra.
    param([Parameter(Mandatory)]$Doc, $Sensores)
    $d = $Doc.datos
    $u = $script:Ctx.Config.umbrales
    $r = New-Object System.Collections.Generic.List[object]
    $nueva = { param($titulo, $detalle, $tipo, $impacto, $esfuerzo) $r.Add([pscustomobject][ordered]@{ Titulo = $titulo; Detalle = $detalle; Tipo = $tipo; Impacto = $impacto; Esfuerzo = $esfuerzo }) }

    $t = Get-TemperaturaSensores -Sensores $Sensores
    if ($t) {
        $mt = Get-MejoraTermica -TempMaxC ([double]$t.max)
        if ($mt) { & $nueva 'Mantención térmica' "$($mt.Motivo) $($mt.Beneficio)" 'Servicio' 3 2 }
        elseif ([double]$t.max -ge [double]$u.mejora_temp_preventiva_c) { & $nueva 'Mantención térmica preventiva' "Llegó a $(Format-Numero ([double]$t.max) 1) °C con carga. Una limpieza interna y pasta térmica nueva bajan la temperatura, el ruido del ventilador y alargan la vida del equipo." 'Servicio' 3 2 }
    }
    $c = @($d.espacio.Volumenes | Where-Object { $_ -and $_.EsSistema }) | Select-Object -First 1
    $papelera = Get-PapeleraGB -Doc $Doc
    $hib = if ($d.energia.Hibernacion) { [double]$d.energia.Hibernacion.HiberfilGB } else { 0 }
    if ($c -and [double]$c.LibrePct -lt [double]$u.libre_aviso_pct) {
        $partes = New-Object System.Collections.Generic.List[string]
        if ($papelera -ge 1) { $partes.Add("vaciar la papelera ($(Format-Numero $papelera 1) GB)") }
        if ($hib -ge [double]$u.hiberfil_gb) { $partes.Add("quitar el archivo de hibernación ($(Format-Numero $hib 1) GB)") }
        $partes.Add('borrar instaladores y descargas que ya no se usan')
        $txtPartes = if ($partes.Count -gt 1) { (($partes | Select-Object -First ($partes.Count - 1)) -join ', ') + ' y ' + $partes[$partes.Count - 1] } else { $partes[0] }
        & $nueva 'Liberar espacio' "El disco de Windows tiene solo $(Format-Numero ([double]$c.LibrePct) 0) % libre, y con poco espacio Windows se pone lento. Se puede $txtPartes." 'Sin costo' 3 1
    } elseif ($papelera -ge 10) {
        & $nueva 'Vaciar la papelera' "Hay $(Format-Numero $papelera 1) GB en la papelera de reciclaje." 'Sin costo' 1 1
    }
    $todosIni = @(Get-InicioCliente -Doc $Doc)
    $ini = @($todosIni | Where-Object { -not $_.Windows -and $_.Nombre -notmatch '(?i)audio|realtek|synaptics|touchpad|elan|amd|nvidia|intel' })
    $ta = $d.arranque.TiempoArranque
    $lento = $ta -and $null -ne $ta.UltimoSeg -and [double]$ta.UltimoSeg -gt 60
    if ($ini.Count -ge 5 -or $lento) {
        $ej = ($ini | ForEach-Object { $_.Nombre }) -join ', '
        & $nueva 'Ordenar el inicio de Windows' "$($todosIni.Count) programas arrancan solos$(if ($lento) { " y el encendido tarda $(Format-Numero ([double]$ta.UltimoSeg) 0) s" }). Candidatos a desactivar (motivo LENTO, con deshacer): $(if ($ej) { $ej } else { 'ninguno de terceros; revisar los de Microsoft' })." 'Sin costo' $(if ($lento) { 3 } else { 2 }) 1
    }
    foreach ($m in @($Doc.mejoras | Where-Object { $_ -and $_.Codigo -ne 'MEJ-TERMICA' })) {
        $imp = switch ("$($m.Prioridad)") { 'Alta' { 3 } 'Media' { 2 } default { 1 } }
        & $nueva $m.Titulo "$($m.Motivo) $($m.Comprar) $($m.Beneficio)" 'Compra' $imp 3
    }
    if (@($d.seguridad.BitLocker | Where-Object { $_ -and $_.Cifrado }).Count) {
        & $nueva 'Guardar la clave de recuperación' 'El disco está cifrado. La clave está en tu cuenta Microsoft (aka.ms/myrecoverykey): comprueba que aparece antes de cualquier reparación.' 'Sin costo' 1 1
    }
    $e = $d.estabilidad
    if ($e -and ([int]$e.Apagados + [int]$e.Pantallazos) -ge 2) {
        & $nueva 'Revisar los apagados' "Hubo $([int]$e.Apagados) apagado(s) inesperado(s) y $([int]$e.Pantallazos) pantallazo(s) azul(es) en $($e.Dias) días. Si se apagó solo, conviene contar qué se estaba haciendo." 'Sin costo' 2 1
    }
    $err = @($d.dispositivos.ConError | Where-Object { $_ })
    if ($err.Count) {
        & $nueva 'Instalar un driver faltante' ("Sin driver o con error: " + (($err | Select-Object -First 3 | ForEach-Object { "$($_.Dispositivo) (código $($_.Codigo), $($_.Id))" }) -join '; ') + '. Driver desde la página oficial (③ Trabajo → Drivers).') 'Sin costo' 1 1
    }
    @($r | Sort-Object @{ Expression = 'Impacto'; Descending = $true }, @{ Expression = 'Esfuerzo'; Descending = $false })
}

function Get-ServiciosCliente {
    # Lo que ve el cliente: las recomendaciones agrupadas en servicios, con lo encontrado y lo que gana, sin
    # el cómo (eso va en la hoja técnica). Optimización de Windows junta espacio, inicio, drivers y apagados.
    param([Parameter(Mandatory)]$Doc, $Sensores)
    $d = $Doc.datos
    $recos = @(Get-RecomendacionesVisual -Doc $Doc -Sensores $Sensores)
    $s = New-Object System.Collections.Generic.List[object]
    $nuevo = { param($titulo, $tipo, $desc, $hall, $gana, $imp) $s.Add([pscustomobject][ordered]@{ Titulo = $titulo; Tipo = $tipo; Descripcion = $desc; Hallazgos = @($hall); Gana = @($gana); Impacto = $imp }) }

    $hall = New-Object System.Collections.Generic.List[string]
    $gana = New-Object System.Collections.Generic.List[string]
    $imp = 0
    $c = @($d.espacio.Volumenes | Where-Object { $_ -and $_.EsSistema }) | Select-Object -First 1
    if (@($recos | Where-Object { $_.Titulo -match '^(Liberar espacio|Vaciar la papelera)' }).Count) {
        $hall.Add("El disco de Windows ($($c.Unidad)) tiene solo $(Format-Numero ([double]$c.LibrePct) 0) % libre.")
        $pap = Get-PapeleraGB -Doc $Doc
        if ($pap -ge 1) { $hall.Add("Hay espacio ocupado que se puede recuperar (más de $(Format-Numero ([math]::Floor($pap)) 0) GB).") }
        $gana.Add('Más espacio'); $gana.Add('Windows más fluido')
        $imp = [math]::Max($imp, @($recos | Where-Object { $_.Titulo -match '^(Liberar espacio|Vaciar la papelera)' } | ForEach-Object { $_.Impacto } | Measure-Object -Maximum).Maximum)
    }
    $rIni = @($recos | Where-Object { $_.Titulo -eq 'Ordenar el inicio de Windows' }) | Select-Object -First 1
    if ($rIni) {
        $n = @(Get-InicioCliente -Doc $Doc).Count
        $ta = $d.arranque.TiempoArranque
        $hall.Add("$n programas arrancan solos con Windows$(if ($ta -and $null -ne $ta.UltimoSeg) { "; el encendido tarda $(Format-Numero ([double]$ta.UltimoSeg) 0) segundos" }).")
        $gana.Add('Encendido más rápido'); $gana.Add('Más memoria libre')
        $imp = [math]::Max($imp, $rIni.Impacto)
    }
    $err = @($d.dispositivos.ConError | Where-Object { $_ })
    if ($err.Count) { $hall.Add("$($err.Count) dispositivo(s) sin driver o con error."); $gana.Add('Todo funcionando') }
    $e = $d.estabilidad
    if ($e -and ([int]$e.Apagados + [int]$e.Pantallazos) -ge 2) { $hall.Add("$([int]$e.Apagados + [int]$e.Pantallazos) apagados o pantallazos inesperados en $($e.Dias) días: reviso la causa."); $gana.Add('Más estabilidad'); $imp = [math]::Max($imp, 2) }
    if ($hall.Count) {
        & $nuevo 'Optimización de Windows' 'Servicio' 'Dejo Windows liviano y ordenado para que el equipo vuelva a andar rápido. Cada cambio queda respaldado y se puede deshacer.' $hall @($gana | Select-Object -Unique) $imp
    }

    $rT = @($recos | Where-Object { $_.Titulo -match '^Mantención térmica' }) | Select-Object -First 1
    if ($rT) {
        $t = Get-TemperaturaSensores -Sensores $Sensores
        $hT = New-Object System.Collections.Generic.List[string]
        $hT.Add("Con el procesador al 100 % llegó a $(Format-Numero ([double]$t.max) 1) °C.")
        $vent = if ($Sensores.metricas.ventilador_cpu) { $Sensores.metricas.ventilador_cpu } else { $null }
        if ($vent -and $vent.p95 -ge 0.97 * $vent.max) { $hT.Add('El ventilador trabaja a su velocidad máxima.') }
        & $nuevo 'Mantención térmica' 'Servicio' 'Limpieza interna de ventiladores y disipador, y cambio de pasta térmica.' $hT @('Menos temperatura', 'Menos ruido', 'Más vida útil') $rT.Impacto
    }

    foreach ($m in @($Doc.mejoras | Where-Object { $_ -and $_.Codigo -ne 'MEJ-TERMICA' })) {
        $impM = switch ("$($m.Prioridad)") { 'Alta' { 3 } 'Media' { 2 } default { 1 } }
        $ganaM = switch -Regex ("$($m.Codigo)") { 'SSD|DISCO' { @('Más espacio', 'Más velocidad') } 'RAM' { @('Más velocidad', 'Más programas a la vez') } 'BATERIA' { @('Más autonomía') } default { @('Mejor rendimiento') } }
        & $nuevo "$($m.Titulo)" 'Compra + instalación' "$($m.Comprar) $($m.Beneficio)" @("$($m.Motivo)") $ganaM $impM
    }
    # A igual impacto: optimización, después mantención, después compras.
    @($s | Sort-Object @{ Expression = 'Impacto'; Descending = $true }, @{ Expression = { if ($_.Titulo -eq 'Optimización de Windows') { 0 } elseif ($_.Tipo -eq 'Servicio') { 1 } else { 2 } } })
}

# ---------------------------------------------------------------- gráficos SVG

function Get-SvgAnillo {
    # Anillo de puntaje con el número al centro.
    param($Puntaje, [int]$Tam = 150, [string]$Fondo = 'rgba(255,255,255,.18)', [string]$Texto = '#fff')
    $r = $Tam / 2 - 10
    $cir = 2 * [math]::PI * $r
    $pct = if ($null -ne $Puntaje) { [double]$Puntaje / 100 } else { 0 }
    $col = Get-ColorPuntaje $Puntaje
    $c = Get-NumSvg ($Tam / 2)
    $num = if ($null -ne $Puntaje) { $Puntaje } else { '–' }
    "<svg viewBox='0 0 $Tam $Tam' width='$Tam' height='$Tam'><circle cx='$c' cy='$c' r='$(Get-NumSvg $r)' fill='none' stroke='$Fondo' stroke-width='12'/>" +
    "<circle cx='$c' cy='$c' r='$(Get-NumSvg $r)' fill='none' stroke='$col' stroke-width='12' stroke-linecap='round' stroke-dasharray='$(Get-NumSvg ($cir * $pct)) $(Get-NumSvg $cir)' transform='rotate(-90 $c $c)'/>" +
    "<text x='$c' y='$(Get-NumSvg ($Tam / 2 + 4))' text-anchor='middle' font-size='$(Get-NumSvg ($Tam * 0.3) 0)' font-weight='700' fill='$Texto'>$num</text>" +
    "<text x='$c' y='$(Get-NumSvg ($Tam / 2 + $Tam * 0.2))' text-anchor='middle' font-size='$(Get-NumSvg ($Tam * 0.085) 0)' fill='$Texto' opacity='.85'>de 100</text></svg>"
}

function Get-SvgDona {
    # Dona de uso (0-100 %) con el porcentaje al centro y una etiqueta abajo.
    param([double]$Pct, [string]$Color, [string]$Centro, [string]$Abajo, [int]$Tam = 120)
    $r = $Tam / 2 - 12
    $cir = 2 * [math]::PI * $r
    $c = Get-NumSvg ($Tam / 2)
    $p = [math]::Max(0, [math]::Min(100, $Pct)) / 100
    "<svg viewBox='0 0 $Tam $($Tam + 18)' width='$Tam' height='$($Tam + 18)'><circle cx='$c' cy='$c' r='$(Get-NumSvg $r)' fill='none' stroke='#e9edf2' stroke-width='16'/>" +
    "<circle cx='$c' cy='$c' r='$(Get-NumSvg $r)' fill='none' stroke='$Color' stroke-width='16' stroke-dasharray='$(Get-NumSvg ($cir * $p)) $(Get-NumSvg $cir)' transform='rotate(-90 $c $c)'/>" +
    "<text x='$c' y='$(Get-NumSvg ($Tam / 2 + 6))' text-anchor='middle' font-size='18' font-weight='700' fill='#1b2430'>$(Get-HtmlVisual $Centro)</text>" +
    "<text x='$c' y='$($Tam + 14)' text-anchor='middle' font-size='11' fill='#5a6675'>$(Get-HtmlVisual $Abajo)</text></svg>"
}

function Get-SvgTemperatura {
    # Curva de temperatura de la CPU (rojo) y ventilador (azul, eje derecho) con la franja de carga.
    param([Parameter(Mandatory)]$Sensores)
    $serie = @($Sensores.serie | Where-Object { $_ })
    $clave = if (@($serie | Where-Object { $null -ne $_.cpu_temp_paquete }).Count) { 'cpu_temp_paquete' } else { 'cpu_temp_nucleo_max' }
    $pts = @($serie | Where-Object { $null -ne $_.$clave })
    if ($pts.Count -lt 2) { return '' }
    $W = 700; $H = 225; $L = 46; $R = 52; $T = 14; $B = 28
    $xmax = [math]::Max(1.0, [double]$pts[$pts.Count - 1].minuto)
    $temps = @($pts | ForEach-Object { [double]$_.$clave })
    $tmin = [math]::Floor(([math]::Min(40, ($temps | Measure-Object -Minimum).Minimum)) / 10) * 10
    $tmax = 100
    $fans = @($serie | Where-Object { $null -ne $_.ventilador_cpu -and [double]$_.ventilador_cpu -gt 0 })
    $fmax = if ($fans.Count) { [math]::Ceiling((($fans | ForEach-Object { [double]$_.ventilador_cpu } | Measure-Object -Maximum).Maximum * 1.2) / 1000) * 1000 } else { 0 }
    $X = { param($m) $L + ($W - $L - $R) * [double]$m / $xmax }
    $Yt = { param($v) $T + ($H - $T - $B) * (1 - ([double]$v - $tmin) / ($tmax - $tmin)) }
    $Yf = { param($v) $T + ($H - $T - $B) * (1 - [double]$v / $fmax) }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<svg viewBox='0 0 $W $H' width='100%' font-family='Segoe UI, Arial'>")
    if ($Sensores.carga) {
        $x1 = & $X $Sensores.carga.inicio_min; $x2 = & $X $Sensores.carga.fin_min
        [void]$sb.Append("<rect x='$(Get-NumSvg $x1)' y='$T' width='$(Get-NumSvg ($x2 - $x1))' height='$($H - $T - $B)' fill='#fff4e0'/>")
        [void]$sb.Append("<text x='$(Get-NumSvg (($x1 + $x2) / 2))' y='$($T + 14)' text-anchor='middle' font-size='11' font-weight='600' fill='#b7700a'>Procesador al 100 %</text>")
        if ($x1 - $L -gt 60) { [void]$sb.Append("<text x='$(Get-NumSvg (($L + $x1) / 2))' y='$(Get-NumSvg ($H - $B - 8))' text-anchor='middle' font-size='11' fill='#5a6675'>Reposo</text>") }
    }
    for ($v = $tmin; $v -le $tmax; $v += 10) {
        $y = Get-NumSvg (& $Yt $v)
        [void]$sb.Append("<line x1='$L' x2='$($W - $R)' y1='$y' y2='$y' stroke='#e9edf2'/><text x='$($L - 6)' y='$(Get-NumSvg ((& $Yt $v) + 4))' text-anchor='end' font-size='10' fill='#5a6675'>$v°</text>")
    }
    if ($fmax -gt 0) {
        for ($f = 0; $f -le $fmax; $f += [math]::Max(1000, $fmax / 5)) { [void]$sb.Append("<text x='$($W - $R + 6)' y='$(Get-NumSvg ((& $Yf $f) + 4))' font-size='10' fill='#1f5fa8'>$(Get-NumSvg ($f / 1000) 1)k</text>") }
    }
    $paso = if ($xmax -gt 30) { 5 } elseif ($xmax -gt 12) { 2 } else { 1 }
    for ($m = 0; $m -le $xmax; $m += $paso) { [void]$sb.Append("<text x='$(Get-NumSvg (& $X $m))' y='$($H - $B + 16)' text-anchor='middle' font-size='10' fill='#5a6675'>$m min</text>") }
    $tj = [double](Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'sensores.json')).tjmax_aviso_c
    $ytj = Get-NumSvg (& $Yt $tj)
    [void]$sb.Append("<line x1='$L' x2='$($W - $R)' y1='$ytj' y2='$ytj' stroke='#c0392b' stroke-dasharray='5 4'/>")
    [void]$sb.Append("<text x='$($L + 4)' y='$(Get-NumSvg ((& $Yt $tj) - 4))' font-size='10' fill='#c0392b'>límite del procesador (~$tj °C)</text>")
    if ($fans.Count -gt 1) {
        $d = ($fans | ForEach-Object { '{0} {1}' -f (Get-NumSvg (& $X $_.minuto)), (Get-NumSvg (& $Yf $_.ventilador_cpu)) }) -join ' L'
        [void]$sb.Append("<path d='M$d' fill='none' stroke='#1f5fa8' stroke-width='1.4' opacity='.55'/>")
    }
    $d = ($pts | ForEach-Object { '{0} {1}' -f (Get-NumSvg (& $X $_.minuto)), (Get-NumSvg (& $Yt $_.$clave)) }) -join ' L'
    [void]$sb.Append("<path d='M$d' fill='none' stroke='#c0392b' stroke-width='2.2' stroke-linejoin='round'/>")
    $mx = $pts | Sort-Object { [double]$_.$clave } -Descending | Select-Object -First 1
    $metTemp = Get-TemperaturaSensores -Sensores $Sensores
    $txtMax = if ($metTemp) { Format-Numero ([double]$metTemp.max) 1 } else { Format-Numero ([double]$mx.$clave) 1 }
    [void]$sb.Append("<circle cx='$(Get-NumSvg (& $X $mx.minuto))' cy='$(Get-NumSvg (& $Yt $mx.$clave))' r='4.5' fill='#c0392b'/>")
    [void]$sb.Append("<text x='$(Get-NumSvg ((& $X $mx.minuto) - 8))' y='$(Get-NumSvg ((& $Yt $mx.$clave) - 9))' text-anchor='end' font-size='11' font-weight='700' fill='#c0392b'>máx. $txtMax °C</text>")
    [void]$sb.Append('</svg>')
    $sb.ToString()
}

function Get-SvgZoomCarga {
    # Zoom al tramo bajo carga: eje de temperatura acotado a lo medido para que se vea la subida, relleno
    # degradado, franjas por zona (cómoda < 80, caliente < 90, al límite), promedio y cuánto subió.
    param([Parameter(Mandatory)]$Sensores)
    if (-not $Sensores.carga) { return '' }
    $ini = [double]$Sensores.carga.inicio_min; $fin = [double]$Sensores.carga.fin_min
    $serie = @($Sensores.serie | Where-Object { $_ })
    $clave = if (@($serie | Where-Object { $null -ne $_.cpu_temp_paquete }).Count) { 'cpu_temp_paquete' } else { 'cpu_temp_nucleo_max' }
    $pts = @($serie | Where-Object { $null -ne $_.$clave -and [double]$_.minuto -ge $ini -and [double]$_.minuto -le $fin })
    if ($pts.Count -lt 5) { return '' }
    $vals = @($pts | ForEach-Object { [double]$_.$clave })
    $vmin = ($vals | Measure-Object -Minimum).Minimum; $vmax = ($vals | Measure-Object -Maximum).Maximum
    $ymin = [math]::Floor(($vmin - 2) / 2) * 2; $ymax = [math]::Ceiling(($vmax + 2) / 2) * 2
    if ($ymax - $ymin -lt 10) { $ymin = $ymax - 10 }
    $W = 700; $H = 180; $L = 46; $R = 24; $T = 12; $B = 26
    $dur = [math]::Max(0.5, $fin - $ini)
    $X = { param($m) $L + ($W - $L - $R) * ([double]$m - $ini) / $dur }
    $Y = { param($v) $T + ($H - $T - $B) * (1 - ([double]$v - $ymin) / ($ymax - $ymin)) }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<svg viewBox='0 0 $W $H' width='100%' font-family='Segoe UI, Arial'><defs>")
    [void]$sb.Append("<linearGradient id='zcRelleno' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#e74c3c' stop-opacity='.55'/><stop offset='.6' stop-color='#f39c12' stop-opacity='.22'/><stop offset='1' stop-color='#f9e79f' stop-opacity='.05'/></linearGradient>")
    [void]$sb.Append("<linearGradient id='zcLinea' x1='0' y1='0' x2='1' y2='0'><stop offset='0' stop-color='#f39c12'/><stop offset='1' stop-color='#c0392b'/></linearGradient></defs>")
    # Franjas por zona, recortadas al rango del zoom.
    foreach ($z in @(@(0, 80, '#e8f6ee', 'cómoda'), @(80, 90, '#fff4e0', 'caliente'), @(90, 200, '#fde8e4', 'al límite'))) {
        $lo = [math]::Max($ymin, $z[0]); $hi = [math]::Min($ymax, $z[1])
        if ($hi -le $lo) { continue }
        $y1 = & $Y $hi; $y2 = & $Y $lo
        [void]$sb.Append("<rect x='$L' y='$(Get-NumSvg $y1)' width='$($W - $L - $R)' height='$(Get-NumSvg ($y2 - $y1))' fill='$($z[2])'/>")
        # Etiqueta al pie de la franja y al centro: la curva sube, así que ahí no la tapa.
        if ($y2 - $y1 -ge 14) { [void]$sb.Append("<text x='$(Get-NumSvg ($L + 0.45 * ($W - $L - $R)))' y='$(Get-NumSvg ($y2 - 4))' text-anchor='middle' font-size='9' font-weight='700' fill='#8a96a3' letter-spacing='1'>$($z[3].ToUpper())</text>") }
    }
    $paso = if ($ymax - $ymin -gt 20) { 5 } else { 2 }
    for ($v = $ymin; $v -le $ymax; $v += $paso) {
        $yl = Get-NumSvg (& $Y $v)
        [void]$sb.Append("<line x1='$L' x2='$($W - $R)' y1='$yl' y2='$yl' stroke='#ffffff' stroke-opacity='.8'/><text x='$($L - 6)' y='$(Get-NumSvg ((& $Y $v) + 4))' text-anchor='end' font-size='10' fill='#5a6675'>$v°</text>")
    }
    $pasoX = if ($dur -gt 12) { 2 } else { 1 }
    for ($m = 0; $m -le $dur + 0.01; $m += $pasoX) { [void]$sb.Append("<text x='$(Get-NumSvg (& $X ($ini + $m)))' y='$($H - $B + 16)' text-anchor='middle' font-size='10' fill='#5a6675'>+$m min</text>") }
    $linea = ($pts | ForEach-Object { '{0} {1}' -f (Get-NumSvg (& $X $_.minuto)), (Get-NumSvg (& $Y $_.$clave)) }) -join ' L'
    $x0 = Get-NumSvg (& $X $pts[0].minuto); $xN = Get-NumSvg (& $X $pts[$pts.Count - 1].minuto); $yB = Get-NumSvg ($H - $B)
    [void]$sb.Append("<path d='M$x0 $yB L$linea L$xN $yB Z' fill='url(#zcRelleno)'/>")
    [void]$sb.Append("<path d='M$linea' fill='none' stroke='url(#zcLinea)' stroke-width='2.6' stroke-linejoin='round' stroke-linecap='round'/>")
    $prom = ($vals | Measure-Object -Average).Average
    $yp = Get-NumSvg (& $Y $prom)
    [void]$sb.Append("<line x1='$L' x2='$($W - $R)' y1='$yp' y2='$yp' stroke='#1b2430' stroke-dasharray='3 4' stroke-opacity='.55'/><text x='$($L + 6)' y='$(Get-NumSvg ((& $Y $prom) - 5))' font-size='10' fill='#1b2430' opacity='.75'>promedio $(Format-Numero $prom 1) °C</text>")
    $p0 = $pts[0]
    [void]$sb.Append("<circle cx='$x0' cy='$(Get-NumSvg (& $Y $p0.$clave))' r='4' fill='#f39c12' stroke='#fff' stroke-width='1.5'/>")
    [void]$sb.Append("<text x='$(Get-NumSvg ((& $X $p0.minuto) + 7))' y='$(Get-NumSvg ((& $Y $p0.$clave) - 7))' font-size='10' font-weight='600' fill='#b7700a'>inicio $(Format-Numero ([double]$p0.$clave) 0) °C</text>")
    $mx = $pts | Sort-Object { [double]$_.$clave } -Descending | Select-Object -First 1
    $xm = & $X $mx.minuto; $ym = & $Y $mx.$clave
    [void]$sb.Append("<circle cx='$(Get-NumSvg $xm)' cy='$(Get-NumSvg $ym)' r='9' fill='#c0392b' opacity='.18'/><circle cx='$(Get-NumSvg $xm)' cy='$(Get-NumSvg $ym)' r='4.5' fill='#c0392b' stroke='#fff' stroke-width='1.5'/>")
    # Cuánto subió: del primer minuto de carga al máximo.
    $sube = [double]$mx.$clave - [double]$p0.$clave
    $minSube = [double]$mx.minuto - [double]$p0.minuto
    $txt = "+$(Format-Numero $sube 0) °C en $(Format-Numero $minSube 0) min"
    # Etiqueta abajo a la derecha, donde la curva (que sube) no pasa.
    $bx = $W - $R - 150; $by = $H - $B - 34
    [void]$sb.Append("<rect x='$bx' y='$by' width='142' height='26' rx='13' fill='#c0392b' stroke='#fff' stroke-width='2'/><text x='$($bx + 71)' y='$($by + 17)' text-anchor='middle' font-size='11.5' font-weight='700' fill='#fff'>$txt</text>")
    [void]$sb.Append("<text x='$(Get-NumSvg ($xm - 8))' y='$(Get-NumSvg ($ym - 8))' text-anchor='end' font-size='10.5' font-weight='700' fill='#c0392b'>máx. $(Format-Numero ([double]$mx.$clave) 1) °C</text>")
    [void]$sb.Append('</svg>')
    $sb.ToString()
}

function Get-SvgBarrasArranque {
    # Barras de los últimos arranques (segundos hasta quedar listo), del más antiguo al más reciente.
    param([object[]]$Arranques)
    $a = @($Arranques | Where-Object { $_ -and $null -ne $_.TotalSeg } | Select-Object -First 8)
    if ($a.Count -lt 2) { return '' }
    [array]::Reverse($a)
    $W = 330; $H = 170; $L = 30; $B = 34; $T = 10
    $max = [math]::Ceiling((($a | ForEach-Object { [double]$_.TotalSeg } | Measure-Object -Maximum).Maximum) / 30) * 30
    $ancho = ($W - $L - 6) / $a.Count
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<svg viewBox='0 0 $W $H' width='100%' font-family='Segoe UI, Arial'>")
    for ($v = 0; $v -le $max; $v += 30) { $y = Get-NumSvg ($H - $B - ($H - $B - $T) * $v / $max); [void]$sb.Append("<line x1='$L' x2='$W' y1='$y' y2='$y' stroke='#eef1f5'/><text x='$($L - 4)' y='$(Get-NumSvg ([double]$y + 3))' text-anchor='end' font-size='9' fill='#5a6675'>$v</text>") }
    for ($i = 0; $i -lt $a.Count; $i++) {
        $v = [double]$a[$i].TotalSeg
        $alto = ($H - $B - $T) * $v / $max
        $x = $L + 4 + $i * $ancho
        $col = if ($v -le 60) { '#6aa84f' } elseif ($v -le 120) { '#d4900a' } else { '#c0392b' }
        if ($i -eq $a.Count - 1) { $col = '#1f5fa8' }
        [void]$sb.Append("<rect x='$(Get-NumSvg $x)' y='$(Get-NumSvg ($H - $B - $alto))' width='$(Get-NumSvg ($ancho - 8))' height='$(Get-NumSvg $alto)' rx='3' fill='$col'/>")
        [void]$sb.Append("<text x='$(Get-NumSvg ($x + ($ancho - 8) / 2))' y='$(Get-NumSvg ($H - $B - $alto - 3))' text-anchor='middle' font-size='9' fill='#1b2430'>$([int][math]::Round($v))</text>")
        $f = "$($a[$i].Fecha)"
        $et = if ($f -match '^(\d{4})-(\d{2})-(\d{2})') { "$($Matches[3])/$($Matches[2])" } else { '' }
        [void]$sb.Append("<text x='$(Get-NumSvg ($x + ($ancho - 8) / 2))' y='$($H - $B + 13)' text-anchor='middle' font-size='9' fill='#5a6675'>$et</text>")
        if ($f -match '^(\d{4})') { [void]$sb.Append("<text x='$(Get-NumSvg ($x + ($ancho - 8) / 2))' y='$($H - $B + 24)' text-anchor='middle' font-size='8' fill='#9aa5b1'>$($Matches[1])</text>") }
    }
    [void]$sb.Append('</svg>')
    $sb.ToString()
}

# ---------------------------------------------------------------- HTML

function Get-CssVisual {
    @'
@page { size: A4; margin: 0; }
:root { --tinta:#1b2430; --suave:#5a6675; --linea:#e3e8ee; --fondo:#f4f6f9; --azul:#1f5fa8; --azul2:#e8f0fa; --verde:#1e8a52; --verde2:#e6f4ec; --ambar:#b7700a; --ambar2:#fdf3e2; --rojo:#c0392b; --rojo2:#fbeae8; }
* { box-sizing: border-box; }
body { margin:0; font-family:"Segoe UI", Arial, sans-serif; color:var(--tinta); font-size:10.2pt; line-height:1.45; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
.hoja { width:210mm; min-height:297mm; padding:13mm 14mm 14mm; position:relative; page-break-after:always; overflow:hidden; }
.hoja:last-child { page-break-after:auto; }
h2 { font-size:15pt; margin:0 0 4px; letter-spacing:-.2px; }
h2 small { display:block; font-size:9pt; font-weight:400; color:var(--suave); letter-spacing:0; margin-top:1px; }
h3 { font-size:10.5pt; margin:0 0 4px; }
p { margin:3px 0 7px; }
.eti { text-transform:uppercase; letter-spacing:1.4px; font-size:7.8pt; color:var(--suave); font-weight:600; }
.sec { margin-bottom:14px; page-break-inside:avoid; }
.num-sec { display:inline-flex; width:26px; height:26px; border-radius:7px; background:var(--azul); color:#fff; font-size:11pt; align-items:center; justify-content:center; margin-right:8px; vertical-align:2px; }
/* portada */
.portada { padding:0; background:linear-gradient(160deg,#0f2a4a 0%,#17406f 55%,#1f5fa8 100%); color:#fff; }
.portada .arriba { padding:16mm 16mm 0; }
.portada .marca { font-size:9pt; letter-spacing:3px; text-transform:uppercase; opacity:.8; }
.portada h1 { font-size:30pt; line-height:1.1; margin:14mm 0 3mm; letter-spacing:-.6px; }
.portada .sub { font-size:12pt; opacity:.9; max-width:140mm; }
.portada .datos { display:grid; grid-template-columns:repeat(4,1fr); gap:10px; margin-top:10mm; font-size:8.5pt; }
.portada .datos b { display:block; font-size:10.5pt; margin-top:2px; }
.portada .puntaje { margin:12mm 16mm 0; background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.18); border-radius:14px; padding:14px 18px; display:grid; grid-template-columns:160px 1fr; gap:18px; align-items:center; }
.portada .puntaje .nivel { font-size:20pt; font-weight:700; }
.portada .puntaje p { opacity:.92; font-size:10.5pt; }
.portada .areas-mini { margin:8mm 16mm 0; display:grid; grid-template-columns:repeat(3,1fr); gap:9px; }
.portada .am { background:#fff; color:var(--tinta); border-radius:10px; padding:9px 11px; display:grid; grid-template-columns:44px 1fr; gap:9px; align-items:center; }
.portada .am .bola { width:44px; height:44px; border-radius:50%; color:#fff; font-weight:700; display:flex; align-items:center; justify-content:center; font-size:13pt; }
.portada .am .n { font-size:8pt; text-transform:uppercase; letter-spacing:.8px; color:var(--suave); font-weight:600; }
.portada .am .v { font-weight:600; font-size:10pt; }
.portada .pie-portada { position:absolute; bottom:12mm; left:16mm; right:16mm; display:flex; justify-content:space-between; font-size:8.5pt; opacity:.8; border-top:1px solid rgba(255,255,255,.25); padding-top:8px; }
/* bloques */
.resumen { display:grid; grid-template-columns:repeat(4,1fr); gap:8px; margin:6px 0 10px; }
.kpi { background:var(--fondo); border-radius:10px; padding:10px 12px; border-left:4px solid var(--azul); }
.kpi .v { font-size:16pt; font-weight:700; line-height:1.15; }
.kpi .t { font-size:8.3pt; color:var(--suave); }
.dos { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
.tres { display:grid; grid-template-columns:repeat(3,1fr); gap:10px; }
.caja { border:1px solid var(--linea); border-radius:12px; padding:11px 13px; background:#fff; }
.explica { background:var(--azul2); border-radius:10px; padding:9px 12px; font-size:9.4pt; margin:8px 0; }
.explica b { color:var(--azul); }
.aviso { background:var(--ambar2); border-left:4px solid var(--ambar); border-radius:8px; padding:9px 12px; font-size:9.4pt; margin:8px 0; }
table { width:100%; border-collapse:collapse; font-size:9.3pt; }
td, th { padding:5px 7px; border-bottom:1px solid var(--linea); text-align:left; vertical-align:top; }
th { color:var(--suave); font-size:8pt; text-transform:uppercase; letter-spacing:.5px; font-weight:600; }
td.k { color:var(--suave); width:34%; }
.area { display:grid; grid-template-columns:120px 1fr 44px; gap:10px; align-items:center; padding:6px 0; border-bottom:1px solid var(--linea); }
.area:last-child { border-bottom:0; }
.area .nom { font-weight:600; }
.area .fr { grid-column:2 / 4; font-size:8.8pt; color:var(--suave); margin-top:-4px; }
.barra { height:10px; background:#e9edf2; border-radius:6px; overflow:hidden; }
.barra > div { height:100%; border-radius:6px; }
.area .pt { font-weight:700; text-align:right; }
.chips { display:flex; flex-wrap:wrap; gap:5px; }
.chip { font-size:8.5pt; padding:3px 9px; border-radius:20px; background:var(--fondo); border:1px solid var(--linea); }
.chip.win { background:var(--azul2); border-color:#cfdff2; color:var(--azul); }
.chip.ter { background:var(--ambar2); border-color:#f0dbb1; color:#8a5a06; }
.check { display:grid; grid-template-columns:22px 1fr; gap:6px; padding:5px 0; border-bottom:1px solid var(--linea); font-size:9.3pt; }
.check:last-child { border-bottom:0; }
.check i { width:18px; height:18px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center; color:#fff; font-style:normal; font-size:10pt; font-weight:700; }
.reco { display:grid; grid-template-columns:28px 1fr; gap:9px; padding:8px 0; border-bottom:1px solid var(--linea); page-break-inside:avoid; }
.reco:last-child { border-bottom:0; }
.reco .bn { width:24px; height:24px; border-radius:50%; color:#fff; font-weight:700; display:flex; align-items:center; justify-content:center; font-size:10pt; }
.reco .det { font-size:9pt; color:var(--suave); }
.tag { display:inline-block; font-size:7.6pt; font-weight:700; padding:1px 8px; border-radius:10px; margin-left:6px; vertical-align:1px; text-transform:uppercase; letter-spacing:.4px; }
.tag.Servicio { background:var(--rojo2); color:var(--rojo); } .tag.Compra { background:var(--ambar2); color:var(--ambar); } .tag.Sin { background:var(--verde2); color:var(--verde); }
.leyenda { display:flex; gap:14px; font-size:8.4pt; color:var(--suave); flex-wrap:wrap; margin-top:3px; }
.leyenda i { display:inline-block; width:12px; height:4px; border-radius:2px; vertical-align:middle; margin-right:4px; }
.glosario { display:grid; grid-template-columns:1fr 1fr; gap:6px 16px; font-size:9pt; }
.glosario b { color:var(--azul); }
.pie { position:absolute; bottom:8mm; left:14mm; right:14mm; display:flex; justify-content:space-between; font-size:7.8pt; color:var(--suave); border-top:1px solid var(--linea); padding-top:5px; }
.slot { border:2px solid var(--azul); border-radius:6px; padding:6px 8px; text-align:center; font-size:8.6pt; background:var(--azul2); }
.slot.vacio { border-style:dashed; border-color:#c3ccd6; background:#fff; color:var(--suave); }
'@
}

function ConvertTo-InformeVisual {
    # Arma el HTML del informe. -Origen: 'remoto' o 'kit' (cambia la frase de cómo se hizo).
    param([Parameter(Mandatory)]$Doc, $Sensores, [string]$Origen = 'remoto', [string]$Cliente)
    $d = $Doc.datos
    $H = { param($t) Get-HtmlVisual $t }
    $areas = @(Get-AreasSalud -Doc $Doc -Sensores $Sensores)
    $puntaje = Get-PuntajeGeneral -Areas $areas
    $tecnico = $script:Ctx.Config.tecnico
    $contacto = "$($tecnico.contacto)"
    $fechaDoc = [datetime]::ParseExact(("$($Doc.kit.generado)").Substring(0, 10), 'yyyy-MM-dd', $script:InvVisual)
    $fechaTxt = $fechaDoc.ToString("d 'de' MMMM 'de' yyyy", [Globalization.CultureInfo]'es-CL')
    $eq = $d.equipo
    $modelo = Get-NombreModeloVisual -Equipo $eq
    $pie = { param($n) "<div class='pie'><div>$(& $H $modelo) · $(& $H $fechaTxt)</div><div>$(& $H "$($tecnico.nombre)") · Servicio técnico$(if ($contacto) { ' · ' + (& $H $contacto) })</div><div>$n</div></div>" }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Informe · $(& $H $modelo)</title><style>$(Get-CssVisual)</style></head><body>")

    # ---- Portada
    $nivel = Get-EtiquetaPuntaje $puntaje
    $malas = @($areas | Where-Object { $null -ne $_.Puntaje -and $_.Puntaje -lt 70 } | Sort-Object Puntaje)
    $frase = if (-not $malas.Count) { 'El equipo está en buena forma. Abajo están los detalles y algunas ideas para mantenerlo así.' }
    else { "El equipo funciona, y hay $(if ($malas.Count -eq 1) { 'un punto' } else { "$($malas.Count) puntos" }) que conviene atender: " + (($malas | ForEach-Object { $_.Nombre.ToLower() }) -join ', ') + '. En las páginas siguientes te explico qué significa cada uno y qué hacer.' }
    [void]$sb.Append("<div class='hoja portada'><div class='arriba'><div class='marca'>Informe de diagnóstico$(if ($Origen -eq 'remoto') { ' · a distancia' })</div>")
    [void]$sb.Append("<h1>$(& $H $modelo)</h1><div class='sub'>Revisión completa del equipo$(if ($Sensores) { ' y prueba de temperatura' }): cómo está, qué significa y qué conviene hacer.</div>")
    [void]$sb.Append("<div class='datos'><div>Fecha<b>$(& $H $fechaTxt)</b></div><div>Equipo<b>$(& $H $eq.NombreEquipo)</b></div><div>Windows<b>$(& $H ("$($d.windows.Nombre)" -replace '^Windows (\d+) (Home|Pro).*$', 'Windows $1 $2')) $(& $H $d.windows.Version)</b></div><div>$(if ($Cliente) { 'Cliente' } else { 'Técnico' })<b>$(& $H $(if ($Cliente) { $Cliente } else { $tecnico.nombre }))</b></div></div></div>")
    [void]$sb.Append("<div class='puntaje'><div>$(Get-SvgAnillo -Puntaje $puntaje -Tam 150)</div><div><div class='eti' style='color:#cfe0f5'>Salud general</div><div class='nivel'>$(& $H $nivel)</div><p>$(& $H $frase)</p></div></div>")
    [void]$sb.Append("<div class='areas-mini'>")
    foreach ($a in $areas) {
        [void]$sb.Append("<div class='am'><div class='bola' style='background:$(Get-ColorPuntaje $a.Puntaje)'>$(if ($null -ne $a.Puntaje) { $a.Puntaje } else { '–' })</div><div><div class='n'>$(& $H $a.Nombre)</div><div class='v'>$(& $H $a.Valor)</div></div></div>")
    }
    [void]$sb.Append("</div><div class='pie-portada'><div>$(& $H "$($tecnico.nombre)") · Servicio técnico de notebooks y PC</div><div>$(& $H $contacto)</div></div></div>")

    # ---- Página 2: áreas y equipo
    [void]$sb.Append("<div class='hoja'>")
    [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>1</span>Cómo está cada área<small>Puntaje de 0 a 100: sobre 85 muy bien, 70 a 84 bien, 55 a 69 mejorable, bajo 55 necesita atención.</small></h2><div class='caja'>")
    foreach ($a in $areas) {
        $col = Get-ColorPuntaje $a.Puntaje
        $w = if ($null -ne $a.Puntaje) { $a.Puntaje } else { 0 }
        [void]$sb.Append("<div class='area'><div class='nom'>$(& $H $a.Nombre)</div><div class='barra'><div style='width:$w%;background:$col'></div></div><div class='pt' style='color:$col'>$(if ($null -ne $a.Puntaje) { $a.Puntaje } else { '–' })</div><div></div><div class='fr'>$(& $H $a.Frase)</div></div>")
    }
    [void]$sb.Append('</div></div>')

    $cpu = $d.hardware.Cpu
    $ram = $d.hardware.Ram
    $gpus = @($d.hardware.Gpu | Where-Object { $_ })
    $discos = @($d.hardware.Discos | Where-Object { $_ -and -not $_.DelKit -and "$($_.Bus)" -ne 'USB' })
    [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>2</span>Qué tiene tu equipo<small>Las piezas principales y para qué sirve cada una.</small></h2>")
    [void]$sb.Append("<div class='resumen'><div class='kpi'><div class='v'>$($cpu.Nucleos)<span style='font-size:10pt'> núcleos</span></div><div class='t'>Procesador · $($cpu.Hilos) hilos</div></div>")
    [void]$sb.Append("<div class='kpi'><div class='v'>$(Format-Numero ([double]$ram.TotalGB) 0)<span style='font-size:10pt'> GB</span></div><div class='t'>Memoria RAM · $($ram.CantidadModulos) módulo(s)</div></div>")
    $alm = ($discos | Measure-Object -Property TamanoGB -Sum).Sum
    [void]$sb.Append("<div class='kpi'><div class='v'>$(if ($alm -ge 1000) { "$(Format-Numero ($alm / 1000) 1)<span style='font-size:10pt'> TB</span>" } else { "$(Format-Numero $alm 0)<span style='font-size:10pt'> GB</span>" })</div><div class='t'>Almacenamiento · $($discos.Count) disco(s)</div></div>")
    $vram = ($gpus | Where-Object { $_.Nombre -notmatch '(?i)vega|uhd|iris|radeon\(tm\) graphics|intel' } | Select-Object -First 1)
    [void]$sb.Append("<div class='kpi'><div class='v'>$(if ($vram) { "$(Format-Numero ([double]$vram.VramGB) 0)<span style='font-size:10pt'> GB</span>" } else { 'Integrada' })</div><div class='t'>Video$(if ($vram) { ' dedicado' })</div></div></div>")
    [void]$sb.Append("<table><tr><td class='k'>Procesador</td><td>$(& $H ($cpu.Nombre -replace ' with .*$', ''))<br><span style='color:var(--suave);font-size:8.6pt'>El cerebro: hace los cálculos de todo lo que usas.</span></td></tr>")
    $mods = @($ram.Modulos | Where-Object { $_ })
    $dual = $mods.Count -ge 2 -and @($mods | ForEach-Object { $_.CapacidadGB } | Select-Object -Unique).Count -eq 1
    [void]$sb.Append("<tr><td class='k'>Memoria RAM</td><td>$(Format-Numero ([double]$ram.TotalGB) 0) GB$(if ($mods.Count) { " $(& $H $mods[0].Tipo) a $($mods[0].VelocidadMTs) MT/s" })$(if ($dual) { ' · doble canal' })<br><span style='color:var(--suave);font-size:8.6pt'>La mesa de trabajo: cuanta más, más programas abiertos a la vez sin que se ponga lento.</span></td></tr>")
    foreach ($g in $gpus) { [void]$sb.Append("<tr><td class='k'>Video</td><td>$(& $H $g.Nombre)$(if ($g.VramGB) { " · $(Format-Numero ([double]$g.VramGB) 0) GB" })</td></tr>") }
    foreach ($k in $discos) {
        $tipo = if ($k.Tipo -eq 'SSD') { "SSD $($k.Bus) (rápido)" } elseif ($k.Tipo -eq 'HDD') { 'Disco duro mecánico (más lento)' } else { "$($k.Tipo) $($k.Bus)" }
        [void]$sb.Append("<tr><td class='k'>Disco $(& $H $k.Letras)</td><td>$(& $H $k.Modelo) · $($k.TamanoGB) GB · $(& $H $tipo)$(if ($k.Sistema) { ' · tiene Windows' })<br><span style='color:var(--suave);font-size:8.6pt'>Salud: $(if ("$($k.Salud)" -eq 'Healthy') { 'buena' } else { & $H $k.Salud })$(if ($null -ne $k.DesgastePct) { " · desgaste $($k.DesgastePct) %" })$(if ($k.HorasEncendido) { " · $(Format-Numero ([double]$k.HorasEncendido) 0) horas encendido" })</span></td></tr>")
    }
    $lic = $d.windows.Licencia
    [void]$sb.Append("<tr><td class='k'>Windows</td><td>$(& $H $d.windows.Nombre) $(& $H $d.windows.Version) · $(if ($lic.Estado -eq 'Activado') { 'activado' } else { & $H $lic.Estado })$(if ("$($lic.Canal)" -match '^OEM') { ' (licencia original de fábrica)' })$(if ($d.windows.Soporte.Fin) { " · con actualizaciones hasta $(& $H $d.windows.Soporte.Fin)" })</td></tr></table></div>")
    [void]$sb.Append("$(& $pie '2')</div>")

    # ---- Página 3: temperatura
    $t = Get-TemperaturaSensores -Sensores $Sensores
    if ($t) {
        $rep = Get-ReposoSensores -Sensores $Sensores
        $m = $Sensores.metricas
        $min = if ($Sensores.carga) { $Sensores.carga.minutos } else { $Sensores.duracion_min }
        [void]$sb.Append("<div class='hoja'><div class='sec'><h2><span class='num-sec'>3</span>Prueba de temperatura<small>Primero el equipo en reposo y después el procesador al 100 % por $(Format-Numero ([double]$min) 0) minutos, como cuando juegas o abres algo pesado. Se registró cada $(Format-Numero ([double]$Sensores.intervalo_seg) 0) segundos.</small></h2>")
        [void]$sb.Append("<div class='resumen'><div class='kpi' style='border-color:var(--rojo)'><div class='v'>$(Format-Numero ([double]$t.max) 1) °C</div><div class='t'>Temperatura máxima</div></div>")
        [void]$sb.Append("<div class='kpi' style='border-color:var(--ambar)'><div class='v'>$(Format-Numero ([double]$t.media) 1) °C</div><div class='t'>Promedio con carga</div></div>")
        [void]$sb.Append("<div class='kpi'><div class='v'>$(if ($m.cpu_frec_efectiva) { "$(Format-Numero ([double]$m.cpu_frec_efectiva.media / 1000) 1) GHz" } else { '–' })</div><div class='t'>Velocidad con carga</div></div>")
        [void]$sb.Append("<div class='kpi' style='border-color:var(--verde)'><div class='v'>$(if ($null -eq $Sensores.pierde_velocidad.valor) { '–' } elseif ($Sensores.pierde_velocidad.valor) { 'Sí' } else { 'No' })</div><div class='t'>¿Se frenó por calor?</div></div></div>")
        [void]$sb.Append("<div class='caja'>$(Get-SvgTemperatura -Sensores $Sensores)<div class='leyenda'><span><i style='background:#c0392b'></i>Temperatura del procesador</span>$(if ($m.ventilador_cpu) { "<span><i style='background:#1f5fa8;opacity:.6'></i>Ventilador (RPM, eje derecho)</span>" })<span><i style='background:#fff4e0;height:9px;border:1px solid #f0dbb1'></i>Procesador al 100 %</span></div></div>")
        $zoom = Get-SvgZoomCarga -Sensores $Sensores
        if ($zoom) { [void]$sb.Append("<div class='caja' style='margin-top:10px;padding-top:9px'><div class='eti' style='margin-bottom:2px'>Zoom a la prueba: los $(Format-Numero ([double]$Sensores.carga.minutos) 0) minutos al 100 %</div>$zoom</div>") }
        [void]$sb.Append("<div class='dos' style='margin-top:10px;grid-template-columns:1fr 1fr;align-items:start'><div>")
        [void]$sb.Append("<table><tr><th></th><th>En reposo</th><th>Al 100 %</th></tr>")
        [void]$sb.Append("<tr><td class='k'>Temperatura</td><td>$(if ($rep -and $null -ne $rep.temp) { "$(Format-Numero ([double]$rep.temp) 0) °C" } else { '–' })</td><td><b>$(Format-Numero ([double]$t.media) 0) °C</b> (máx. $(Format-Numero ([double]$t.max) 1))</td></tr>")
        if ($m.ventilador_cpu) { [void]$sb.Append("<tr><td class='k'>Ventilador</td><td>$(if ($rep -and $null -ne $rep.ventilador) { "$(Format-Numero ([double]$rep.ventilador) 0) RPM" } else { '–' })</td><td><b>$(Format-Numero ([double]$m.ventilador_cpu.media) 0) RPM</b> (máx. $(Format-Numero ([double]$m.ventilador_cpu.max) 0))</td></tr>") }
        if ($m.cpu_frec_efectiva) { [void]$sb.Append("<tr><td class='k'>Velocidad</td><td>$(if ($rep -and $null -ne $rep.frec) { "$(Format-Numero ([double]$rep.frec / 1000) 1) GHz" } else { '–' })</td><td>$(Format-Numero ([double]$m.cpu_frec_efectiva.media / 1000) 1) GHz</td></tr>") }
        if ($m.cpu_potencia) { [void]$sb.Append("<tr><td class='k'>Consumo del procesador</td><td></td><td>$(Format-Numero ([double]$m.cpu_potencia.media) 1) W</td></tr>") }
        [void]$sb.Append('</table>')
        if ($rep -and $null -ne $rep.uso -and [double]$rep.uso -gt 15) { [void]$sb.Append("<div style='font-size:8.3pt;color:var(--suave);margin-top:5px'>* En el reposo Windows trabajaba en segundo plano ($(Format-Numero ([double]$rep.uso) 0) % de uso), así que esos valores salen algo más altos que un reposo real.</div>") }
        [void]$sb.Append('</div><div>')
        $tj = [double](Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'sensores.json')).tjmax_aviso_c
        $max = [double]$t.max
        $txt = if ($max -lt 80) { "Con carga máxima se mantuvo bajo 80 °C: la refrigeración trabaja holgada." }
        elseif ($max -lt 90) { "El procesador aguanta hasta unos $tj °C antes de frenarse para protegerse, así que <b>hoy no hay peligro</b>. Pero con carga trabaja caliente$(if ($m.ventilador_cpu -and $m.ventilador_cpu.p95 -ge 0.97 * $m.ventilador_cpu.max) { ' y con el ventilador a su máxima velocidad' }): la refrigeración está cerca de su límite. Con el tiempo el polvo y la pasta térmica seca lo empeoran." }
        elseif ($max -lt $tj) { "Trabaja muy cerca del límite ($tj °C). Si sube un poco más, el procesador se frena y el equipo se pone lento justo cuando más lo necesitas." }
        else { "Llegó al límite de temperatura: el procesador se protege bajando su velocidad. Conviene hacer la mantención pronto." }
        [void]$sb.Append("<div class='explica' style='margin-top:0'><b>¿Qué significa?</b> $txt</div>")
        [void]$sb.Append("</div></div></div>$(& $pie '3')</div>")
    }

    # ---- Página: espacio, memoria y encendido
    $np = if ($t) { 4 } else { 3 }
    [void]$sb.Append("<div class='hoja'><div class='sec'><h2><span class='num-sec'>$np</span>Espacio en disco<small>Windows necesita espacio libre para actualizarse y trabajar fluido; bajo 20 % libre empieza a ponerse lento.</small></h2>")
    $vols = @($d.espacio.Volumenes | Where-Object { $_ -and ($_.EsSistema -or -not $_.EsKit) })
    [void]$sb.Append("<div class='caja'><div style='display:flex;gap:18px;flex-wrap:wrap;align-items:flex-start'>")
    foreach ($v in $vols) {
        $uso = 100 - [double]$v.LibrePct
        $col = if ([double]$v.LibrePct -lt 10) { '#c0392b' } elseif ([double]$v.LibrePct -lt 20) { '#d4900a' } else { '#1e8a52' }
        [void]$sb.Append("<div style='text-align:center'>$(Get-SvgDona -Pct $uso -Color $col -Centro "$(Format-Numero $uso 0) %" -Abajo "$($v.Unidad) usado" -Tam 112)<div style='font-size:8.6pt;color:var(--suave)'>$(Format-Numero ([double]$v.LibreGB) 0) GB libres de $(Format-Numero ([double]$v.TotalGB) 0)<br>$(if ($v.Medio -eq 'SSD') { 'SSD' } elseif ($v.Medio -eq 'HDD') { 'Disco duro' } else { '' })$(if ($v.EsSistema) { ' · Windows' })</div></div>")
    }
    # Lo que más ocupa, por carpeta de primer nivel: el top omite carpetas que solo contienen a otra, así que
    # cada carpeta de primer nivel toma el tamaño de su entrada más grande.
    $porRaiz = @{}
    foreach ($x in @($d.espacio.TopCarpetas | Where-Object { $_ -and $_.Carpeta -notmatch '\$RECYCLE\.BIN' })) {
        $p = "$($x.Carpeta)".Split('\')
        if ($p.Count -lt 2) { continue }
        $raiz = "$($p[0])\$($p[1])"
        if (-not $porRaiz.ContainsKey($raiz) -or [double]$x.TamanoGB -gt $porRaiz[$raiz]) { $porRaiz[$raiz] = [double]$x.TamanoGB }
    }
    $top = @($porRaiz.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6 | ForEach-Object { [pscustomobject]@{ Carpeta = $_.Key; TamanoGB = $_.Value } })
    if ($top.Count) {
        $mx = [double]$top[0].TamanoGB
        [void]$sb.Append("<div style='flex:1;min-width:250px'><div class='eti' style='margin-bottom:5px'>Lo que más ocupa</div>")
        foreach ($x in $top) {
            $nombre = $x.Carpeta -replace '\\Users\\[^\\]+', '\Usuario' -replace '^([A-Z]:)\\', '$1 '
            [void]$sb.Append("<div style='display:grid;grid-template-columns:150px 1fr 52px;gap:8px;align-items:center;font-size:8.8pt;margin:4px 0'><div style='white-space:nowrap;overflow:hidden;text-overflow:ellipsis'>$(& $H $nombre)</div><div class='barra'><div style='width:$(Get-NumSvg (100 * [double]$x.TamanoGB / $mx) 0)%;background:#1f5fa8'></div></div><div style='text-align:right'>$(Format-Numero ([double]$x.TamanoGB) 1) GB</div></div>")
        }
        $pap = Get-PapeleraGB -Doc $Doc
        if ($pap -ge 1) { [void]$sb.Append("<div style='display:grid;grid-template-columns:150px 1fr 52px;gap:8px;align-items:center;font-size:8.8pt;margin:4px 0;color:var(--rojo)'><div>Papelera</div><div class='barra'><div style='width:$(Get-NumSvg ([math]::Min(100, 100 * $pap / $mx)) 0)%;background:#c0392b'></div></div><div style='text-align:right'>$(Format-Numero $pap 1) GB</div></div>") }
        [void]$sb.Append('</div>')
    }
    [void]$sb.Append('</div></div></div>')

    # Memoria y encendido
    $mem = $d.uso.Memoria
    $ta = $d.arranque.TiempoArranque
    [void]$sb.Append("<div class='dos'><div class='sec'><h2><span class='num-sec'>$($np + 1)</span>Memoria RAM</h2><div class='caja'><div style='display:grid;grid-template-columns:112px 1fr;gap:12px;align-items:center'>")
    if ($mem) { [void]$sb.Append("<div>$(Get-SvgDona -Pct ([double]$mem.UsoPct) -Color $(if ([double]$mem.UsoPct -ge 85) { '#c0392b' } elseif ([double]$mem.UsoPct -ge 70) { '#d4900a' } else { '#1f5fa8' }) -Centro "$(Format-Numero ([double]$mem.UsoPct) 0) %" -Abajo 'en uso al revisar' -Tam 104)</div>") } else { [void]$sb.Append('<div></div>') }
    $slots = [math]::Max($mods.Count, [math]::Min(4, [int]$ram.Slots))
    [void]$sb.Append("<div><div style='display:grid;grid-template-columns:repeat($([math]::Max(1, $slots)),1fr);gap:6px'>")
    for ($i = 0; $i -lt $slots; $i++) { if ($i -lt $mods.Count) { [void]$sb.Append("<div class='slot'><b>$($mods[$i].CapacidadGB) GB</b><br>$(& $H $mods[$i].Tipo)</div>") } else { [void]$sb.Append("<div class='slot vacio'>libre</div>") } }
    [void]$sb.Append("</div><p style='font-size:8.8pt;color:var(--suave);margin-top:7px'>$(if ($dual) { 'Dos módulos iguales trabajan en <b>doble canal</b>: la memoria rinde casi el doble que con uno solo.' } elseif ($mods.Count -eq 1) { 'Un solo módulo: agregar otro igual activa el doble canal y mejora el rendimiento.' } else { '' })$(if ($mem) { " Al revisar estaban en uso $(Format-Numero ([double]$mem.UsadaGB) 1) de $(Format-Numero ([double]$mem.TotalGB) 1) GB." })</p></div></div></div></div>")
    [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>$($np + 2)</span>Encendido</h2><div class='caja'>")
    if ($ta -and $ta.Ultimos) { [void]$sb.Append("$(Get-SvgBarrasArranque -Arranques $ta.Ultimos)<div class='leyenda'><span><i style='background:#1f5fa8'></i>último encendido</span><span>segundos hasta quedar listo</span></div>") }
    [void]$sb.Append('</div></div></div>')
    $ini = @(Get-InicioCliente -Doc $Doc)
    if ($ini.Count) {
        [void]$sb.Append("<div class='sec'><div class='caja'><div class='eti' style='margin-bottom:6px'>Arrancan solos con Windows ($($ini.Count))</div><div class='chips'>")
        foreach ($x in $ini) { [void]$sb.Append("<span class='chip $(if ($x.Windows) { 'win' } else { 'ter' })'>$(& $H $x.Nombre)</span>") }
        [void]$sb.Append("</div><div class='leyenda' style='margin-top:7px'><span><i style='background:#cfdff2;height:9px'></i>de Windows o Microsoft</span><span><i style='background:#f0dbb1;height:9px'></i>de otros programas</span></div><p style='font-size:8.8pt;color:var(--suave);margin:6px 0 0'>Cada programa que arranca solo suma segundos al encendido y ocupa memoria aunque no lo estés usando.</p></div></div>")
    }
    [void]$sb.Append("$(& $pie $np)</div>")

    # ---- Página: batería, seguridad, estabilidad
    $np2 = $np + 3
    [void]$sb.Append("<div class='hoja'><div class='dos'>")
    $b = @($d.hardware.Baterias | Where-Object { $_ -and $null -ne $_.SaludPct }) | Select-Object -First 1
    if ($b) {
        $sp = [double]$b.SaludPct
        $colB = if ($sp -ge 80) { '#1e8a52' } elseif ($sp -ge 50) { '#d4900a' } else { '#c0392b' }
        $cod = ConvertTo-CodigoBateria -Texto "$($b.Id)"
        [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>$np2</span>Batería</h2><div class='caja'><div style='display:flex;align-items:center;gap:6px;margin:4px 0 8px'><div style='flex:1;height:34px;border:3px solid #1b2430;border-radius:7px;padding:3px'><div style='height:100%;width:$(Get-NumSvg $sp 0)%;background:$colB;border-radius:3px'></div></div><div style='width:6px;height:14px;background:#1b2430;border-radius:0 3px 3px 0'></div></div>")
        [void]$sb.Append("<div style='display:flex;justify-content:space-between;font-size:9pt'><span><b style='font-size:14pt;color:$colB'>$(Format-Numero $sp 1) %</b> de su capacidad original</span><span style='color:var(--suave)'>$(Format-Numero ([double]$b.CargaCompletaMWh / 1000) 1) de $(Format-Numero ([double]$b.DisenoMWh / 1000) 1) Wh</span></div>")
        [void]$sb.Append("<p style='font-size:8.8pt;color:var(--suave);margin-top:8px'>$(if ($sp -ge 80) { 'Está en buen estado.' } elseif ($sp -ge 50) { 'Es el desgaste normal de unos años de uso. No hace falta cambiarla todavía; cuando dure muy poco desenchufada, se reemplaza.' } else { 'Está gastada: dura mucho menos que nueva. Conviene cambiarla.' })$(if ($cod) { " Código para el repuesto: <b>$(& $H $cod)</b>$(if ($b.Fabricante) { " ($(& $H $b.Fabricante))" })." })</p></div></div>")
    }
    $s = $d.seguridad
    $chk = New-Object System.Collections.Generic.List[object]
    $chk.Add(@(([bool]($s.Defender -and $s.Defender.TiempoReal)), 'Antivirus activo', $(if ($s.Defender.FirmasFecha) { "Windows Defender, actualizado el $($s.Defender.FirmasFecha)" } else { '' })))
    $chk.Add(@(($lic.Estado -eq 'Activado'), 'Windows activado', "$(if ("$($lic.Canal)" -match '^OEM') { 'Licencia original de fábrica' })"))
    if ($d.windows.Soporte -and $d.windows.Soporte.EnTabla) { $chk.Add(@([bool]$d.windows.Soporte.Vigente, 'Recibe actualizaciones', "Hasta $($d.windows.Soporte.Fin)")) }
    if ($s.SecureBoot) { $chk.Add(@([bool]$s.SecureBoot.Activo, 'Arranque seguro', 'Impide que programas maliciosos se carguen al encender')) }
    if ($s.Tpm) { $chk.Add(@([bool]($s.Tpm.Presente -and $s.Tpm.Activado), "Chip de seguridad TPM $($s.Tpm.Version)", 'Requisito de Windows 11')) }
    $cif = @($s.BitLocker | Where-Object { $_ -and $_.Cifrado })
    if ($cif.Count) { $chk.Add(@($true, "Disco cifrado ($((($cif | ForEach-Object { $_.Volumen }) -join ', ')))", 'Guarda la clave de recuperación: aka.ms/myrecoverykey')) }
    [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>$($np2 + $(if ($b) { 1 } else { 0 }))</span>Seguridad</h2><div class='caja'>")
    foreach ($c in $chk) { [void]$sb.Append("<div class='check'><i style='background:$(if ($c[0]) { '#1e8a52' } else { '#c0392b' })'>$(if ($c[0]) { '✓' } else { '!' })</i><div><b>$(& $H $c[1])</b>$(if ($c[2]) { "<br><span style='color:var(--suave);font-size:8.6pt'>$(& $H $c[2])</span>" })</div></div>") }
    [void]$sb.Append('</div></div></div>')
    $e = $d.estabilidad
    if ($e) {
        $n3 = $np2 + $(if ($b) { 2 } else { 1 })
        [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>$n3</span>Estabilidad (últimos $($e.Dias) días)</h2><div class='caja'>")
        $W = 680; $hoy = $fechaDoc.AddDays(1)
        $sv = New-Object Text.StringBuilder
        [void]$sv.Append("<svg viewBox='0 0 $W 70' width='100%' font-family='Segoe UI, Arial'><line x1='20' x2='$($W - 20)' y1='34' y2='34' stroke='#c3ccd6' stroke-width='2'/>")
        for ($i = 0; $i -le [int]$e.Dias; $i += 5) { $x = Get-NumSvg (20 + ($W - 40) * $i / [int]$e.Dias); [void]$sv.Append("<line x1='$x' x2='$x' y1='30' y2='38' stroke='#c3ccd6'/><text x='$x' y='56' text-anchor='middle' font-size='9' fill='#5a6675'>$($hoy.AddDays(-[int]$e.Dias + $i).ToString('dd/MM'))</text>") }
        foreach ($ev in @($e.Eventos | Where-Object { $_ })) {
            $f = [datetime]::MinValue
            if (-not [datetime]::TryParseExact("$($ev.Fecha)", 'yyyy-MM-dd HH:mm:ss', $script:InvVisual, 'None', [ref]$f)) { continue }
            $dias = ($f - $hoy.AddDays(-[int]$e.Dias)).TotalDays
            if ($dias -lt 0) { continue }
            $x = Get-NumSvg (20 + ($W - 40) * $dias / [int]$e.Dias)
            $col = if ("$($ev.Tipo)" -match '(?i)pantallazo|bugcheck') { '#c0392b' } elseif ("$($ev.Tipo)" -match '(?i)disco') { '#8e44ad' } else { '#d4900a' }
            [void]$sv.Append("<circle cx='$x' cy='34' r='7' fill='$col' stroke='#fff' stroke-width='2'/><text x='$x' y='18' text-anchor='middle' font-size='9' fill='$col'>$($f.ToString('dd/MM'))</text>")
        }
        [void]$sv.Append('</svg>')
        [void]$sb.Append($sv.ToString())
        [void]$sb.Append("<div class='leyenda'><span><i style='background:#d4900a;height:8px'></i>apagado inesperado ($($e.Apagados))</span><span><i style='background:#c0392b;height:8px'></i>pantallazo azul ($($e.Pantallazos))</span><span><i style='background:#8e44ad;height:8px'></i>error de disco ($($e.ErroresDisco))</span></div>")
        [void]$sb.Append("<p style='font-size:8.8pt;color:var(--suave);margin:7px 0 0'>$(if ([int]$e.Apagados + [int]$e.Pantallazos + [int]$e.ErroresDisco -eq 0) { 'Sin cortes ni errores: el equipo está estable.' } else { 'Un apagado inesperado ocurre al mantener apretado el botón de encendido, si se agota la batería o si el equipo se protege del calor. Si se apagó solo, cuéntame qué estabas haciendo.' })</p></div></div>")
    }
    $err = @($d.dispositivos.ConError | Where-Object { $_ })
    if ($err.Count) { [void]$sb.Append("<div class='aviso'><b>Dispositivo con problema:</b> $(& $H (($err | ForEach-Object { $_.Dispositivo }) -join ', ')). Windows no tiene su driver; lo dejo resuelto en la optimización.</div>") }
    $nr = $np2 + $(if ($b) { 1 } else { 0 }) + $(if ($e) { 2 } else { 1 })
    [void]$sb.Append("<div class='sec'><h2><span class='num-sec'>$nr</span>Palabras útiles</h2><div class='caja glosario'>")
    foreach ($g in @(@('SSD', 'disco sin piezas móviles, muy rápido. Ideal para Windows y programas.'), @('Disco duro (HDD)', 'disco mecánico, más lento pero con más espacio por el mismo precio.'), @('RAM', 'memoria de trabajo. Dos módulos iguales (doble canal) la hacen más rápida.'), @('Pasta térmica', 'capa que pasa el calor del procesador al disipador. Con los años se seca.'), @('Freno térmico', 'cuando el procesador se calienta demasiado, baja su velocidad para protegerse.'), @('RPM', 'vueltas por minuto del ventilador. Más RPM, más ruido y más esfuerzo.'), @('Salud de batería', 'cuánta carga guarda hoy comparada con cuando era nueva.'), @('Cifrado (BitLocker)', 'protege tus datos si te roban el equipo. Necesita una clave de recuperación.'))) {
        [void]$sb.Append("<div><b>$(& $H $g[0]):</b> $(& $H $g[1])</div>")
    }
    [void]$sb.Append('</div></div>')
    [void]$sb.Append("$(& $pie ($np + 1))</div>")

    # ---- Recomendaciones
    $nr++
    $servicios = @(Get-ServiciosCliente -Doc $Doc -Sensores $Sensores)
    [void]$sb.Append("<div class='hoja'><div class='sec'><h2><span class='num-sec'>$nr</span>Lo que te propongo<small>Lo que encontré en el diagnóstico, agrupado en lo que puedo hacer por tu equipo, de lo más importante a lo menos.</small></h2>")
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        $x = $servicios[$i]
        $col = if ($x.Tipo -eq 'Servicio') { '#1f5fa8' } else { '#d4900a' }
        [void]$sb.Append("<div class='caja' style='margin-bottom:9px;page-break-inside:avoid;border-left:5px solid $col'><div style='display:grid;grid-template-columns:30px 1fr;gap:10px'><div class='reco' style='padding:0;border:0;display:block'><div class='bn' style='background:$col'>$($i + 1)</div></div><div>")
        [void]$sb.Append("<h3 style='font-size:11.5pt'>$(& $H $x.Titulo)<span class='tag' style='background:$(if ($x.Tipo -eq 'Servicio') { 'var(--azul2);color:var(--azul)' } else { 'var(--ambar2);color:var(--ambar)' })'>$(& $H $x.Tipo)</span></h3>")
        [void]$sb.Append("<div style='font-size:9.3pt;margin:2px 0 6px'>$(& $H $x.Descripcion)</div>")
        [void]$sb.Append("<div style='display:grid;grid-template-columns:1fr 1fr;gap:12px'><div><div class='eti'>Lo que encontré</div><ul style='margin:3px 0 0 16px;padding:0;font-size:9pt'>")
        foreach ($hallazgo in $x.Hallazgos) { [void]$sb.Append("<li>$(& $H $hallazgo)</li>") }
        [void]$sb.Append("</ul></div><div><div class='eti'>Qué ganas</div><div class='chips' style='margin-top:4px'>")
        foreach ($g in $x.Gana) { [void]$sb.Append("<span class='chip' style='background:var(--verde2);border-color:#bfe3cd;color:var(--verde)'>✓ $(& $H $g)</span>") }
        [void]$sb.Append('</div></div></div></div></div></div>')
    }
    $como = if ($Origen -eq 'remoto') { 'Se ejecutó el <b>diagnóstico a distancia</b>: revisa 13 áreas del equipo <b>solo leyendo</b>, sin modificar nada, sin instalar programas y sin internet. El resultado viajó cifrado: solo el técnico puede abrirlo.' } else { 'Se ejecutó el <b>kit de servicio técnico</b> desde un pendrive: revisa 13 áreas del equipo <b>solo leyendo</b>, sin modificar nada y sin instalar programas.' }
    $bloqueComo = "<div class='caja' style='font-size:8.7pt;page-break-inside:avoid'><h3>Cómo se hizo</h3><p>$como$(if ($Sensores) { ' La prueba de temperatura usó HWiNFO y OCCT.' }) No se revisaron documentos, fotos, contraseñas ni historial de navegación.</p>" +
    "<p style='color:var(--suave);font-size:8pt;margin-bottom:0'><b>Sobre el puntaje:</b> cada área se califica con reglas fijas (espacio según el % libre del disco de Windows, batería según su capacidad, temperatura según el máximo con carga...). La salud general es su promedio: temperatura y almacenamiento 25 % cada una, estabilidad y seguridad 15 %, batería y encendido 10 %. Es una guía para priorizar, no una medición de laboratorio.</p></div>"
    if (-not $servicios.Count) {
        [void]$sb.Append("<div class='explica'>No hay nada urgente: el equipo está bien. Lo ideal es una mantención preventiva una vez al año para que siga así.</div>")
    }
    [void]$sb.Append('</div>')
    [void]$sb.Append("<div style='background:linear-gradient(135deg,#17406f,#1f5fa8);color:#fff;border-radius:12px;padding:13px 16px;margin:4px 0 12px;display:flex;justify-content:space-between;align-items:center;gap:14px;page-break-inside:avoid'><div><div style='font-size:12.5pt;font-weight:700'>¿Lo dejamos listo?</div><div style='font-size:9.4pt;opacity:.9'>Me encargo de todo, con respaldo de lo que se cambia y un informe del antes y el después para que veas la diferencia.</div></div><div style='text-align:right;font-size:9.4pt;white-space:nowrap'><b>$(& $H "$($tecnico.nombre)")</b><br>$(& $H $contacto)</div></div>")
    [void]$sb.Append($bloqueComo)
    [void]$sb.Append("$(& $pie ($np + 2))</div></body></html>")
    $sb.ToString()
}

function ConvertTo-HojaTecnica {
    # Para el técnico, NO para el cliente: qué hacer en concreto (lo que el informe del cliente solo menciona
    # como servicio). Recomendaciones con detalle, programas al inicio, lo que más ocupa y dispositivos con error.
    param([Parameter(Mandatory)]$Doc, $Sensores)
    $d = $Doc.datos
    $H = { param($t) Get-HtmlVisual $t }
    $recos = @(Get-RecomendacionesVisual -Doc $Doc -Sensores $Sensores)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Hoja técnica · $(& $H (Get-NombreModeloVisual -Equipo $d.equipo))</title><style>body{font-family:'Segoe UI',Arial;font-size:10pt;color:#1b2430;max-width:900px;margin:20px auto;padding:0 16px}h1{font-size:16pt;margin:0}h2{font-size:12pt;color:#1f5fa8;margin:18px 0 6px;border-bottom:2px solid #e3e8ee;padding-bottom:3px}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #e3e8ee;padding:4px 6px;text-align:left;vertical-align:top}th{color:#5a6675;font-size:8.5pt;text-transform:uppercase}.t{font-size:8pt;font-weight:700;padding:1px 6px;border-radius:8px;background:#eef1f5}.aviso{background:#fdf3e2;border-left:4px solid #b7700a;padding:6px 10px;margin:8px 0}</style></head><body>")
    [void]$sb.Append("<h1>Hoja técnica · $(& $H (Get-NombreModeloVisual -Equipo $d.equipo))</h1><div>Equipo $(& $H $d.equipo.NombreEquipo) · serie $(& $H $d.equipo.Serie) · diagnóstico $(& $H $Doc.kit.generado)</div>")
    [void]$sb.Append("<div class='aviso'>Solo para ti: el informe del cliente muestra estos puntos como servicios, sin el cómo.</div>")
    [void]$sb.Append('<h2>Qué hacer</h2><table><tr><th>#</th><th>Tarea</th><th>Tipo</th><th>Impacto</th><th>Detalle</th></tr>')
    for ($i = 0; $i -lt $recos.Count; $i++) { $x = $recos[$i]; [void]$sb.Append("<tr><td>$($i + 1)</td><td><b>$(& $H $x.Titulo)</b></td><td><span class='t'>$(& $H $x.Tipo)</span></td><td>$('●' * [int]$x.Impacto)</td><td>$(& $H $x.Detalle)</td></tr>") }
    [void]$sb.Append('</table><h2>Programas al inicio</h2><table><tr><th>Nombre</th><th>Empresa</th><th>Microsoft</th><th>De la Store</th></tr>')
    foreach ($x in @(Get-InicioCliente -Doc $Doc)) { [void]$sb.Append("<tr><td>$(& $H $x.Nombre)</td><td>$(& $H $x.Empresa)</td><td>$(if ($x.Windows) { 'sí' })</td><td>$(if ($x.Store) { 'sí' })</td></tr>") }
    [void]$sb.Append('</table><h2>Lo que más ocupa</h2><table><tr><th>Carpeta</th><th>GB</th></tr>')
    foreach ($x in @($d.espacio.TopCarpetas | Where-Object { $_ } | Sort-Object { [double]$_.TamanoGB } -Descending | Select-Object -First 15)) { [void]$sb.Append("<tr><td>$(& $H $x.Carpeta)</td><td>$(Format-Numero ([double]$x.TamanoGB) 1)</td></tr>") }
    [void]$sb.Append("</table><p>Papelera: $(Format-Numero (Get-PapeleraGB -Doc $Doc) 1) GB$(if ($d.energia.Hibernacion) { " · hiberfil.sys: $(Format-Numero ([double]$d.energia.Hibernacion.HiberfilGB) 1) GB" })</p>")
    $err = @($d.dispositivos.ConError | Where-Object { $_ })
    if ($err.Count) {
        [void]$sb.Append('<h2>Dispositivos con error</h2><table><tr><th>Dispositivo</th><th>Código</th><th>Problema</th><th>ID</th></tr>')
        foreach ($x in $err) { [void]$sb.Append("<tr><td>$(& $H $x.Dispositivo)</td><td>$(& $H $x.Codigo)</td><td>$(& $H $x.Problema)</td><td style='font-size:8pt'>$(& $H $x.Id)</td></tr>") }
        [void]$sb.Append('</table>')
    }
    [void]$sb.Append('</body></html>')
    $sb.ToString()
}

function Export-InformeVisual {
    # Lee el diagnostico.json (y el CSV de sensores si se da), escribe el HTML y lo imprime a PDF con Edge.
    # Además deja la hoja técnica (<nombre>_tecnico.html), que no es para el cliente.
    # Devuelve [pscustomobject]@{ Html; Pdf; Tecnico; Error } (Pdf $null si Edge no pudo, con el motivo en Error).
    param([Parameter(Mandatory)][string]$Diagnostico, [string]$CsvSensores, [Parameter(Mandatory)][string]$Salida, [string]$Origen = 'remoto', [string]$Cliente)
    $doc = Read-JsonKit $Diagnostico
    $sens = $null
    if ($CsvSensores -and [IO.File]::Exists($CsvSensores)) { $sens = Read-SensoresCsv -Ruta $CsvSensores }
    $html = ConvertTo-InformeVisual -Doc $doc -Sensores $sens -Origen $Origen -Cliente $Cliente
    $rutaHtml = [IO.Path]::ChangeExtension($Salida, '.html')
    [IO.File]::WriteAllText($rutaHtml, $html, (New-Object Text.UTF8Encoding $true))
    $rutaTec = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Salida), [IO.Path]::GetFileNameWithoutExtension($Salida) + '_tecnico.html')
    [IO.File]::WriteAllText($rutaTec, (ConvertTo-HojaTecnica -Doc $doc -Sensores $sens), (New-Object Text.UTF8Encoding $true))
    $pdf = $null; $err = $null
    try { $pdf = Export-PdfInforme -Html $rutaHtml -Pdf ([IO.Path]::ChangeExtension($Salida, '.pdf')) } catch { $err = $_.Exception.Message }
    [pscustomobject]@{ Html = $rutaHtml; Pdf = $pdf; Tecnico = $rutaTec; Error = $err }
}
