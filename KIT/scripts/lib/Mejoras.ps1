# Mejoras.ps1 - mejoras de hardware recomendadas (SSD, RAM en dual channel, más RAM, disco más grande,
# batería, mantención térmica) a partir de los datos del diagnóstico. Solo lee datos ya juntados: sirve
# durante el diagnóstico ($script:Ctx.Datos) y después, con los datos de diagnostico.json.
# Cada mejora dice qué es, por qué, qué comprar y qué gana el cliente. No pone precios ni enlaces a tiendas.
# Se carga desde Alertas.ps1.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:OrdenPrioridadMejora = @{ Alta = 0; Media = 1; Opcional = 2 }

function Get-UmbralMejora {
    # Umbral de config.json; si no está (o no hay contexto), el valor por defecto.
    param([Parameter(Mandatory)][string]$Nombre, [Parameter(Mandatory)][double]$PorDefecto)
    $v = $null
    try { $v = $script:Ctx.Config.umbrales.$Nombre } catch { $v = $null }
    if ($null -eq $v) { $PorDefecto } else { [double]$v }
}

function Get-ValorDato {
    # Lee una propiedad igual si el objeto es un diccionario (durante el diagnóstico) o un PSCustomObject (JSON).
    param($Objeto, [Parameter(Mandatory)][string]$Nombre)
    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [Collections.IDictionary]) { return $Objeto[$Nombre] }
    $p = $Objeto.PSObject.Properties[$Nombre]
    if ($p) { $p.Value } else { $null }
}

function New-Mejora {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Solo arma un objeto en memoria')]
    param([string]$Codigo, [string]$Prioridad, [string]$Titulo, [string]$Motivo, [string]$Comprar, [string]$Beneficio)
    [pscustomobject][ordered]@{ Codigo = $Codigo; Prioridad = $Prioridad; Titulo = $Titulo; Motivo = $Motivo; Comprar = $Comprar; Beneficio = $Beneficio }
}

function Get-CapacidadSsdSugerida {
    # Capacidad comercial de SSD: la que alcanza al disco actual, nunca menos de 500 GB.
    param([double]$ActualGB)
    foreach ($c in 500, 1000, 2000, 4000) { if ($c -ge $ActualGB * 0.95) { return $c } }
    4000
}

function Format-CapacidadComercial {
    param([double]$GB)
    if ($GB -ge 1000) { '{0} TB' -f ($GB / 1000) } else { '{0} GB' -f $GB }
}

function ConvertTo-CodigoBateria {
    # Algunas baterías informan su código como bytes en hexadecimal ("0x41,0x50,0x31" = "AP1").
    param([string]$Texto)
    $t = $Texto.Trim()
    if ($t -match '^(0x[0-9A-Fa-f]{2})(\s*,\s*0x[0-9A-Fa-f]{2})*$') {
        $t = -join @($t -split '\s*,\s*' | ForEach-Object { [char][Convert]::ToInt32($_.Substring(2), 16) })
        $t = $t.Trim([char]0).Trim()
    }
    if ($t -match '^[\w .\-/]{2,40}$') { $t } else { '' }
}

function Get-TipoSsd {
    # "NVMe" o "SATA" según el bus o el modelo del disco; vacío si no se sabe (p. ej. bus RAID/VMD sin "NVMe" en el nombre).
    param($Disco)
    $txt = "$(Get-ValorDato $Disco 'Bus') $(Get-ValorDato $Disco 'Modelo')"
    if ($txt -match '(?i)nvme') { 'NVMe M.2' } elseif ($txt -match '(?i)\bsata\b') { 'SATA' } else { '' }
}

function Get-MejoraTermica {
    # Mantención térmica según la temperatura máxima de CPU con carga (la prueba CALOR).
    param([Nullable[double]]$TempMaxC)
    if ($null -eq $TempMaxC) { return $null }
    $alta = Get-UmbralMejora -Nombre 'mejora_temp_alta_c' -PorDefecto 95
    $media = Get-UmbralMejora -Nombre 'mejora_temp_media_c' -PorDefecto 90
    if ($TempMaxC -lt $media) { return $null }
    $prio = if ($TempMaxC -ge $alta) { 'Alta' } else { 'Media' }
    New-Mejora -Codigo 'MEJ-TERMICA' -Prioridad $prio -Titulo 'Limpieza interna y cambio de pasta térmica' `
        -Motivo ('La CPU llegó a {0:N0} °C con carga.' -f $TempMaxC) `
        -Comprar 'Pasta térmica de buena calidad (y pads térmicos si el modelo los usa).' `
        -Beneficio 'Trabaja más fresco y sin perder velocidad por temperatura; el ventilador suena menos.'
}

function Get-MejorasRecomendadas {
    # Lista de mejoras, las de prioridad alta primero. $Datos: los datos del diagnóstico (hardware, equipo,
    # uso, espacio). $Alertas: las alertas de esa misma medición (para los discos con fallas).
    param($Datos, [object[]]$Alertas = @(), [Nullable[double]]$TempMaxC)
    $lista = New-Object System.Collections.Generic.List[object]
    $hw = Get-ValorDato $Datos 'hardware'
    $eq = Get-ValorDato $Datos 'equipo'
    $tipoEquipo = "$(Get-ValorDato $eq 'Tipo')"
    $esNotebook = $tipoEquipo -eq 'Notebook'
    $codigos = @($Alertas | Where-Object { $_ } | ForEach-Object { "$(Get-ValorDato $_ 'Codigo')" })

    # --- Discos
    $discos = @(Get-ValorDato $hw 'Discos' | Where-Object { $_ })
    $sistema = $discos | Where-Object { (Get-ValorDato $_ 'Sistema') -eq $true } | Select-Object -First 1
    $falla = @($codigos | Where-Object { $_ -match '^(HW-SMART-MEDIO|HW-SMART-AVISO|HW-SMART-SECTORES|HW-DISCO-SALUD|HW-DISCO-ERRORES)$' }).Count -gt 0
    if ($sistema -and "$(Get-ValorDato $sistema 'Tipo')" -like 'HDD*') {
        $gb = [double](Get-ValorDato $sistema 'TamanoGB')
        $cap = Format-CapacidadComercial (Get-CapacidadSsdSugerida -ActualGB $gb)
        $forma = if ($esNotebook) { 'SSD SATA de 2,5" (o NVMe M.2 si el notebook tiene la ranura)' } else { 'SSD NVMe M.2 si la placa tiene la ranura; si no, SSD SATA de 2,5"' }
        $lista.Add((New-Mejora -Codigo 'MEJ-SSD' -Prioridad 'Alta' -Titulo 'Cambiar el disco mecánico por un SSD' `
                    -Motivo ('Windows está en un disco mecánico ({0}, {1:N0} GB).' -f (Get-ValorDato $sistema 'Modelo'), $gb) `
                    -Comprar "$forma de $cap, más el clonado del disco actual (no se pierde nada)." `
                    -Beneficio 'Enciende y abre programas varias veces más rápido. Es la mejora que más se nota.'))
    } elseif ($falla) {
        $gb = if ($sistema) { [double](Get-ValorDato $sistema 'TamanoGB') } else { 500 }
        $lista.Add((New-Mejora -Codigo 'MEJ-DISCO-FALLA' -Prioridad 'Alta' -Titulo 'Cambiar el disco que muestra fallas' `
                    -Motivo 'Uno de los discos reporta errores de salud (SMART).' `
                    -Comprar "SSD de $(Format-CapacidadComercial (Get-CapacidadSsdSugerida -ActualGB $gb)) y respaldo de los archivos antes de que falle." `
                    -Beneficio 'Evita perder fotos y documentos si el disco deja de funcionar.'))
    }

    # --- Disco de Windows lleno y chico (si es grande, alcanza con ordenar: lo cubre la alerta de espacio)
    $esp = Get-ValorDato $Datos 'espacio'
    $volC = @(Get-ValorDato $esp 'Volumenes' | Where-Object { $_ -and (Get-ValorDato $_ 'EsSistema') -eq $true }) | Select-Object -First 1
    $chicoGB = Get-UmbralMejora -Nombre 'mejora_disco_chico_gb' -PorDefecto 300
    if ($volC -and $sistema -and "$(Get-ValorDato $sistema 'Tipo')" -notlike 'HDD*' -and -not $falla) {
        $librePct = [double](Get-ValorDato $volC 'LibrePct')
        $tam = [double](Get-ValorDato $sistema 'TamanoGB')
        if ($librePct -lt (Get-UmbralMejora -Nombre 'libre_aviso_pct' -PorDefecto 20) -and $tam -gt 0 -and $tam -le $chicoGB) {
            $lista.Add((New-Mejora -Codigo 'MEJ-SSD-GRANDE' -Prioridad 'Media' -Titulo 'SSD de más capacidad' `
                        -Motivo ('El disco de Windows es de {0:N0} GB y le queda {1:N0} % libre.' -f $tam, $librePct) `
                        -Comprar ("SSD {0}de {1}, más el clonado del actual (no se pierde nada)." -f $(if (Get-TipoSsd $sistema) { "$(Get-TipoSsd $sistema) " } else { 'del mismo formato que el actual ' }), (Format-CapacidadComercial (Get-CapacidadSsdSugerida -ActualGB ($tam * 2)))) `
                        -Beneficio 'Espacio de sobra para fotos, programas y actualizaciones de Windows, sin que el equipo se ponga lento por disco lleno.'))
        }
    }

    # --- RAM
    $ram = Get-ValorDato $hw 'Ram'
    $mods = @(Get-ValorDato $ram 'Modulos' | Where-Object { $_ })
    $total = [double](Get-ValorDato $ram 'TotalGB')
    $minGB = Get-UmbralMejora -Nombre 'ram_min_gb' -PorDefecto 8
    $formato = if ($esNotebook) { 'SO-DIMM' } else { 'DIMM' }
    $uso = Get-ValorDato (Get-ValorDato $Datos 'uso') 'Memoria'
    $usoPct = if ($uso) { [double](Get-ValorDato $uso 'UsoPct') } else { $null }
    if ($mods.Count -eq 1) {
        $m = $mods[0]
        $cap = [double](Get-ValorDato $m 'CapacidadGB')
        $tipoRam = "$(Get-ValorDato $m 'Tipo')"
        $vel = Get-ValorDato $m 'VelocidadMTs'
        $desc = (@($tipoRam, $(if ($vel) { "$vel MT/s" }), $formato) | Where-Object { $_ }) -join ' '
        $parte = "$(Get-ValorDato $m 'NumeroParte')".Trim()
        # Con 4 GB o menos, duplicar no alcanza: conviene pasar a 2 x 8 GB.
        if ($cap -gt 0 -and $cap -le 4) {
            $lista.Add((New-Mejora -Codigo 'MEJ-RAM-DUAL' -Prioridad 'Alta' -Titulo 'Más memoria RAM y en dual channel' `
                        -Motivo ('Tiene {0:N0} GB en un solo módulo.' -f $total) `
                        -Comprar "2 módulos de 8 GB $desc (16 GB en total, reemplazando el actual)." `
                        -Beneficio 'Puede tener más programas y pestañas abiertas sin trabarse, y la memoria trabaja al doble de ancho.'))
        } elseif ($cap -gt 0) {
            $prio = if ($total -lt $minGB) { 'Alta' } else { 'Media' }
            $igual = if ($parte) { " (igual al que tiene: $parte)" } else { '' }
            $lista.Add((New-Mejora -Codigo 'MEJ-RAM-DUAL' -Prioridad $prio -Titulo 'Segundo módulo de RAM (dual channel)' `
                        -Motivo ('Tiene un solo módulo de {0:N0} GB: la memoria trabaja en canal simple.' -f $cap) `
                        -Comprar ("1 módulo de {0:N0} GB {1}{2}. Antes, confirmar que hay un slot libre (algunos notebooks traen memoria soldada)." -f $cap, $desc, $igual) `
                        -Beneficio ('Queda con {0:N0} GB y la memoria al doble de ancho: más fluido en juegos, video integrado y multitarea.' -f ($total + $cap))))
        }
    } elseif ($mods.Count -ge 2 -and $total -gt 0 -and $total -lt $minGB) {
        $tipoRam = "$(Get-ValorDato $mods[0] 'Tipo')"
        $lista.Add((New-Mejora -Codigo 'MEJ-RAM' -Prioridad 'Alta' -Titulo 'Más memoria RAM' `
                    -Motivo ('Tiene {0:N0} GB de RAM.' -f $total) `
                    -Comprar "2 módulos de 8 GB $tipoRam $formato (16 GB en total)." `
                    -Beneficio 'Puede tener más programas y pestañas abiertas sin trabarse.'))
    } elseif ($total -gt 0 -and $total -lt 16 -and $null -ne $usoPct -and $usoPct -ge (Get-UmbralMejora -Nombre 'ram_uso_pct' -PorDefecto 85)) {
        $lista.Add((New-Mejora -Codigo 'MEJ-RAM' -Prioridad 'Opcional' -Titulo 'Más memoria RAM' `
                    -Motivo ('Tiene {0:N0} GB y estaba usando el {1:N0} % durante la revisión.' -f $total, $usoPct) `
                    -Comprar "Llegar a 16 GB con módulos $formato del mismo tipo y velocidad." `
                    -Beneficio 'Menos esperas al cambiar entre programas.'))
    }

    # --- Batería
    foreach ($b in @(Get-ValorDato $hw 'Baterias' | Where-Object { $_ })) {
        $salud = Get-ValorDato $b 'SaludPct'
        if ($null -eq $salud) { continue }
        $salud = [double]$salud
        $aviso = Get-UmbralMejora -Nombre 'bateria_aviso_pct' -PorDefecto 70
        if ($salud -ge $aviso) { continue }
        $prio = if ($salud -lt (Get-UmbralMejora -Nombre 'bateria_critico_pct' -PorDefecto 50)) { 'Alta' } else { 'Media' }
        $modelo = (@((Get-ValorDato $eq 'Fabricante'), (Get-ValorDato $eq 'Modelo')) | Where-Object { $_ }) -join ' '
        $id = ConvertTo-CodigoBateria "$(Get-ValorDato $b 'Id')"
        $lista.Add((New-Mejora -Codigo 'MEJ-BATERIA' -Prioridad $prio -Titulo 'Cambiar la batería' `
                    -Motivo ('La batería guarda el {0:N0} % de la carga que tenía nueva.' -f $salud) `
                    -Comprar ("Batería para {0}{1}, de {2:N0} mWh o más." -f $modelo, $(if ($id) { " (código $id)" } else { '' }), (Get-ValorDato $b 'DisenoMWh')) `
                    -Beneficio 'Vuelve a durar como nuevo lejos del enchufe.'))
        break
    }

    $t = Get-MejoraTermica -TempMaxC $TempMaxC
    if ($t) { $lista.Add($t) }

    @($lista | Sort-Object { $script:OrdenPrioridadMejora[$_.Prioridad] })
}

function Format-MejorasTexto {
    # Líneas para resumen.txt y el RESUMEN del diagnóstico remoto.
    param([object[]]$Mejoras)
    $l = New-Object System.Collections.Generic.List[string]
    if (@($Mejoras).Count -eq 0) { $l.Add('(ninguna: el hardware está bien para su uso)'); return $l.ToArray() }
    foreach ($m in $Mejoras) {
        $l.Add(('[{0}] {1}' -f $m.Prioridad.ToUpperInvariant(), $m.Titulo))
        $l.Add("    Por qué : $($m.Motivo)")
        $l.Add("    Comprar : $($m.Comprar)")
        $l.Add("    Gana    : $($m.Beneficio)")
    }
    $l.ToArray()
}
