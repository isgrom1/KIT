#Requires -Version 5.1
# Drivers: links a las páginas oficiales, armados con lo que ya midió el diagnóstico. El kit no instala nada
# ni se conecta a internet: el navegador se abre solo cuando el técnico hace clic, y lo que hay que buscar
# (serie, modelo o ID del hardware) queda copiado para pegarlo en esa página. Las direcciones están en
# config\drivers.json, para cambiarlas sin tocar código cuando un fabricante las mueva.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

function Get-ConfigDrivers {
    $ruta = Join-Path $script:Ctx.CarpetaConfig 'drivers.json'
    if (-not [IO.File]::Exists($ruta)) { return $null }
    Read-JsonKit $ruta
}

function Get-TextoBusquedaHardware {
    # Lo que sirve para buscar un dispositivo en el catálogo de Microsoft Update: VEN_xxxx&DEV_xxxx (PCI y audio),
    # VID_xxxx&PID_xxxx (USB), el ID de ACPI o, si el ID no dice nada útil (dispositivos de software), el nombre.
    param([AllowNull()][string]$Id, [AllowNull()][string]$Nombre)
    $t = "$Id".ToUpperInvariant()
    foreach ($patron in 'VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}', 'VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') {
        $m = [regex]::Match($t, $patron)
        if ($m.Success) { return $m.Value }
    }
    $m = [regex]::Match($t, '^ACPI\\VEN_([A-Z0-9]{3,4})&DEV_([A-Z0-9]{4})')
    if ($m.Success) { return $m.Groups[1].Value + $m.Groups[2].Value }
    $m = [regex]::Match($t, '^ACPI\\([A-Z0-9]{7,8})(\\|$)')
    if ($m.Success) { return $m.Groups[1].Value }
    "$Nombre".Trim()
}

function Get-FabricanteGpu {
    # NVIDIA, AMD o Intel: el que dejó el diagnóstico (por el ID del hardware) o, en diagnósticos anteriores, por el nombre.
    param($Gpu)
    if ($Gpu.PSObject.Properties['Fabricante'] -and $Gpu.Fabricante) { return "$($Gpu.Fabricante)" }
    switch -Regex ("$($Gpu.Nombre)") {
        '(?i)nvidia|geforce|quadro' { return 'NVIDIA' }
        '(?i)\bamd\b|radeon' { return 'AMD' }
        '(?i)intel' { return 'Intel' }
    }
    $null
}

function Get-DiagnosticoReciente {
    # diagnostico.json más nuevo de la atención (después y si no antes) o, si no tiene, de las atenciones anteriores.
    param([Parameter(Mandatory)]$Expediente, [string]$Atencion)
    $carpetas = @(Get-ListaAtenciones -Expediente $Expediente | ForEach-Object { $_['carpeta'] })
    [array]::Reverse($carpetas)
    if ($Atencion) { $carpetas = @($Atencion) + @($carpetas | Where-Object { $_ -ne $Atencion }) }
    foreach ($c in $carpetas) {
        foreach ($mo in 'despues', 'antes') {
            $j = Read-JsonKitOpcional (Join-Path (Join-Path (Join-Path $Expediente.Ruta $c) $mo) 'diagnostico.json')
            if ($j) { return $j }
        }
    }
    $null
}

function Get-LinksDrivers {
    # Lista ordenada: Windows Update (actualizaciones opcionales), página de soporte del fabricante para este modelo,
    # drivers de video y, por cada dispositivo sin driver o con error, su búsqueda en el catálogo de Microsoft Update.
    # Cada link: Tipo (windows, fabricante, video, dispositivo), Titulo, Url ($null si no hay página conocida),
    # Copiar (lo que se pega en el buscador de la página) y Nota.
    param([Parameter(Mandatory)]$Expediente, [string]$Atencion, $Diagnostico, [switch]$SinWindowsUpdate)
    $cfg = Get-ConfigDrivers
    if (-not $cfg) { return @() }
    if (-not $PSBoundParameters.ContainsKey('Diagnostico')) { $Diagnostico = Get-DiagnosticoReciente -Expediente $Expediente -Atencion $Atencion }
    $eq = $Expediente.Ficha['equipo']
    $lista = New-Object System.Collections.Generic.List[object]
    $nuevo = { param($Tipo, $Titulo, $Url, $Copiar, $Nota) [pscustomobject][ordered]@{ Tipo = $Tipo; Titulo = $Titulo; Url = $Url; Copiar = $Copiar; Nota = $Nota } }

    if (-not $SinWindowsUpdate -and $cfg.windows_update) {
        $lista.Add((& $nuevo 'windows' 'Windows Update: actualizaciones opcionales (drivers)' $cfg.windows_update.url $null $cfg.windows_update.nota))
    }

    # Fabricante: el del equipo; en un PC armado registrado antes como Generico, el de la placa madre.
    $fab = "$($eq['fabricante'])"; $modelo = "$($eq['modelo'])"; $placa = "$($eq['placa'])"; $serie = "$($eq['serie'])"
    if (($fab -eq 'Generico' -or $modelo -eq 'Generico') -and $placa) {
        $fabPlaca = ConvertTo-FabricanteCorto $placa
        if ($fabPlaca -and $fabPlaca -ne 'Generico') {
            # "ASUSTeK COMPUTER INC. PRIME B450M-A" -> "PRIME B450M-A"; "ASRock B450M Pro4" -> "B450M Pro4".
            $sinMarca = $placa -replace '^(?i).*\b(inc|ltd|limited|corp(oration)?)\.?,?\s+', ''
            if ($sinMarca -eq $placa) { $sinMarca = $placa -replace "^(?i)$([regex]::Escape($fabPlaca))\S*\s+", '' }
            $fab = $fabPlaca; $modelo = $sinMarca.Trim(); $serie = ''
        }
    }
    $fabUrl = $null; $fabCopiar = $null; $fabQue = $null
    if ($fab -and $fab -ne 'Generico') {
        $f = $cfg.fabricantes.PSObject.Properties[$fab]
        if ($f) {
            $porSerie = $f.Value.copiar -eq 'serie' -and $serie
            $fabUrl = $f.Value.url
            $fabCopiar = if ($porSerie) { $serie } else { $modelo }
            $fabQue = if ($porSerie) { 'la serie' } else { 'el modelo' }
            $nota = "$($f.Value.nota) Se copia ${fabQue}: $fabCopiar."
            $lista.Add((& $nuevo 'fabricante' "Drivers de $fab $modelo (página oficial de $fab)" $fabUrl $fabCopiar $nota))
        } else {
            $lista.Add((& $nuevo 'fabricante' "Drivers de $fab $modelo" $null $modelo "No tengo la página oficial de ${fab}: búscala en su sitio y agrégala en config\drivers.json."))
        }
    }

    if ($Diagnostico) {
        $gpus = @($Diagnostico.datos.hardware.Gpu | Where-Object { $_ })
        $dos = ("$($eq['tipo'])" -eq 'Notebook' -and $gpus.Count -gt 1)
        foreach ($g in $gpus) {
            $vend = Get-FabricanteGpu $g
            $cg = if ($vend) { $cfg.gpu.PSObject.Properties[$vend] } else { $null }
            if (-not $cg) { continue }
            $estado = if ($g.DriverGenerico) { 'driver genérico de Microsoft' } elseif ($g.DriverFecha) { "driver del $($g.DriverFecha)" } else { 'driver sin fecha' }
            $nota = $cg.Value.nota
            if ($dos -and $fab -and $fab -ne 'Generico') { $nota = "Notebook con dos tarjetas de video: primero el driver de la página de $fab; el de $vend solo si ese es muy viejo. $nota" }
            $lista.Add((& $nuevo 'video' "Video: $($g.Nombre) ($estado)" $cg.Value.url "$($g.Nombre)" $nota))
        }
        # Los deshabilitados a mano, los que solo piden reiniciar y los que Windows está quitando no son de driver.
        foreach ($x in @($Diagnostico.datos.dispositivos.ConError | Where-Object { $_ -and [int]$_.Codigo -notin 14, 21, 22, 47 })) {
            $titulo = "Sin driver o con error: $($x.Dispositivo) ($($x.Problema))"
            $q = Get-TextoBusquedaHardware -Id $x.Id -Nombre $x.Dispositivo
            if (-not $q) { continue }
            if ($q -eq "$($x.Dispositivo)".Trim()) {
                # Sin ID de hardware: es un componente de software de otro driver (p. ej. los efectos de audio Waves).
                if ($fabUrl) {
                    $lista.Add((& $nuevo 'dispositivo' $titulo $fabUrl $fabCopiar "No trae ID de hardware: es parte de otro driver del fabricante (casi siempre el de audio). Se arregla instalando ese driver desde la página de $fab. Se copia ${fabQue}: $fabCopiar."))
                    continue
                }
                # El catálogo busca por palabras del título: con el nombre completo no suele encontrar nada.
                $q = (@(($q -replace '\((R|TM)\)', '') -split '\s+' | Where-Object { $_ }) | Select-Object -First 2) -join ' '
            }
            $url = "$($cfg.catalogo.url)".Replace('{q}', [uri]::EscapeDataString($q))
            $lista.Add((& $nuevo 'dispositivo' $titulo $url $q $cfg.catalogo.nota))
        }
    }
    $lista
}

function Open-LinkDriver {
    # Copia lo que hay que buscar y abre la página en el navegador predeterminado. Devuelve qué hizo.
    [OutputType([string])]
    param([Parameter(Mandatory)]$Link)
    $partes = New-Object System.Collections.Generic.List[string]
    if ($Link.Copiar) {
        try { Set-Clipboard -Value "$($Link.Copiar)"; $partes.Add("Copiado: $($Link.Copiar) (pégalo en el buscador de la página).") }
        catch { $partes.Add("Busca: $($Link.Copiar).") }
    }
    if ($Link.Url) {
        Start-Process -FilePath "$($Link.Url)"
        $partes.Add($(if ("$($Link.Url)" -like 'ms-settings:*') { 'Abrí Windows Update.' } else { "Abrí $(([uri]$Link.Url).Host)." }))
    } else { $partes.Add("$($Link.Nota)") }
    $partes -join ' '
}

function Get-HtmlDrivers {
    # Tabla para el informe técnico: los links que abren una página web (Windows Update va como texto).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Links)
    if ($Links.Count -eq 0) { return '' }
    $enc = { param($t) [Net.WebUtility]::HtmlEncode("$t") }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<h2>Drivers (páginas oficiales)</h2><p>El kit no instala drivers. Se buscan con lo de la tercera columna en la página oficial.</p><table><tr><th>Para</th><th>Página</th><th>Buscar con</th></tr>')
    foreach ($l in $Links) {
        $pagina = if ("$($l.Url)" -match '^https://') { "<a href=""$(& $enc $l.Url)"">$(& $enc ([uri]$l.Url).Host)</a>" } elseif ($l.Tipo -eq 'windows') { 'Configuración, Windows Update, Opciones avanzadas, Actualizaciones opcionales' } else { & $enc $l.Nota }
        [void]$sb.AppendLine("<tr><td>$(& $enc $l.Titulo)</td><td>$pagina</td><td>$(& $enc $l.Copiar)</td></tr>")
    }
    [void]$sb.AppendLine('</table>')
    $sb.ToString()
}
