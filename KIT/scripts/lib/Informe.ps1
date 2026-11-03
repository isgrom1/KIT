# Informe.ps1 - informe_cliente.html (1 página A4, lenguaje simple) e informe_tecnico.html (completo),
# en la carpeta de la atención. Autocontenidos: CSS y SVG en línea, sin internet; imprimen bien a PDF.
# Solo se generan si Test-FichaCompleta pasa. Requiere lib\Comun, Expediente, Sensores y motivos\*.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:Recomendacion = [ordered]@{
    '^(HW-SMART-MEDIO|HW-SMART-AVISO|HW-SMART-SECTORES|HW-DISCO-SALUD|HW-DISCO-ERRORES|EST-DISCO)$' = 'Respalda tus archivos cuanto antes: uno de los discos muestra fallas y conviene cambiarlo.'
    '^HW-BATERIA$'      = 'La batería ya no dura como nueva: considera cambiarla.'
    '^SEG-SIN-AV$'      = 'Activa un antivirus (Windows Defender viene incluido y es gratis).'
    '^WIN-ACTIVACION$'  = 'Windows no está activado: conviene regularizarlo.'
    '^WIN-SOPORTE$'     = 'Tu versión de Windows se queda sin actualizaciones de seguridad: conviene actualizarla.'
    '^ESP-LIBRE$'       = 'Queda poco espacio en el disco: guarda fotos y videos en otro lugar o libera espacio.'
    '^HW-DISCO-HDD$'    = 'Cambiar el disco mecánico por uno SSD haría el equipo mucho más rápido.'
    '^HW-RAM-POCA$'     = 'Agregar memoria RAM haría el equipo más ágil.'
    '^(EST-APAGADOS|EST-BSOD)$' = 'El equipo se apagó solo varias veces: si vuelve a pasar, tráelo a revisión.'
    '^HW-GPU-(DRIVER|GENERICO)$' = 'Mantén actualizado el driver de video desde el sitio del fabricante.'
    '^EQ-BIOS$'         = 'Consulta en el servicio oficial de la marca por una actualización de BIOS.'
}
$script:OrdenSeveridadInforme = @{ CRITICO = 0; AVISO = 1; INFO = 2 }

function Get-Html { param($Texto) [Net.WebUtility]::HtmlEncode("$Texto") }

function Format-Celda {
    # Sí/no para booleanos y números en formato chileno; lo demás como texto.
    param($Valor)
    if ($null -eq $Valor) { return '' }
    if ($Valor -is [bool]) { if ($Valor) { return 'sí' } else { return 'no' } }
    if ($Valor -is [double] -or $Valor -is [decimal]) { return (Format-Numero $Valor 1) }
    "$Valor"
}

function Get-NombreMomento { param([string]$Momento) if ($Momento -eq 'despues') { 'después' } else { $Momento } }

function Format-ValorTarjeta {
    param($Valor, [string]$Unidad)
    if ($null -eq $Valor) { return '—' }
    if ($Valor -is [bool]) { if ($Valor) { return 'Sí' } else { return 'No' } }
    "$(Format-Numero ([double]$Valor) $(if ([double]$Valor -eq [math]::Round([double]$Valor)) { 0 } else { 1 })) $Unidad".Trim()
}

function Get-HechoSimple {
    # "Qué se hizo" en palabras del cliente (máximo 5).
    param([object[]]$Acciones, $Checklist)
    $p = New-Object System.Collections.Generic.List[string]
    if ($Checklist) {
        if ($Checklist['desarme'] -or $Checklist['limpieza']) { $p.Add('Limpieza interna del equipo y de su sistema de enfriamiento') }
        if ($Checklist['pasta']) { $p.Add("Cambio de pasta térmica ($($Checklist['pasta']))") }
        if ($Checklist['putty_pads']) { $p.Add("Cambio de pads o putty térmico ($($Checklist['putty_pads']))") }
    }
    $a = @($Acciones | Where-Object { $_ } | ForEach-Object { "$_" })
    # Singular y plural de cada grupo de acciones.
    $grupos = [ordered]@{
        '^Desactivar (al inicio|entrada de inicio)' = @('Quitamos 1 programa que arrancaba solo con Windows', 'Quitamos {0} programas que arrancaban solos con Windows')
        '^Servicio a manual'                        = @('Desactivamos 1 servicio innecesario', 'Desactivamos {0} servicios innecesarios')
        '^Desactivar tarea'                         = @('Desactivamos 1 tarea automática innecesaria', 'Desactivamos {0} tareas automáticas innecesarias')
        'GPU de alto rendimiento'                   = @('Configuramos 1 programa para usar la tarjeta gráfica potente', 'Configuramos {0} programas para usar la tarjeta gráfica potente')
        '^Desinstalar'                              = @('Desinstalamos 1 programa innecesario', 'Desinstalamos {0} programas innecesarios')
    }
    foreach ($k in $grupos.Keys) {
        $n = @($a | Where-Object { $_ -match $k }).Count
        if ($n -eq 1) { $p.Add($grupos[$k][0]) } elseif ($n -gt 1) { $p.Add($grupos[$k][1] -f $n) }
    }
    if ($a -match 'plan de energía') { $p.Add('Ajustamos el plan de energía') }
    if ($a -match 'procesador') { $p.Add('Recuperamos la velocidad máxima del procesador') }
    if ($a -match 'hibernación') { $p.Add('Desactivamos la hibernación para liberar espacio') }
    foreach ($x in @($a | Where-Object { $_ -like 'Se apartaron *' })) { $p.Add($x) }
    @($p | Select-Object -First 5)
}

function Get-DatosInforme {
    # Todo lo que usan ambos informes, en un objeto.
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $f = $Expediente.Ficha
    $a = Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion
    $motivos = @($a['motivos'] | Where-Object { $_ })
    $momentoFinal = if (Test-Medicion -Expediente $Expediente -Atencion $Atencion -Momento 'despues') { 'despues' } else { 'antes' }
    $sem = Get-SemaforoRevision -Expediente $Expediente -Atencion $Atencion -Momento $momentoFinal
    $met = [ordered]@{}
    if ($motivos -contains 'CALOR') { $met['CALOR'] = Get-MetricasCalor -Expediente $Expediente -Atencion $Atencion }
    if ($motivos -contains 'LENTO') { $met['LENTO'] = Get-MetricasLento -Expediente $Expediente -Atencion $Atencion }
    if ($motivos -contains 'ARCHIVOS') { $met['ARCHIVOS'] = Get-MetricasArchivos -Expediente $Expediente -Atencion $Atencion }

    # Frase principal según el motivo (la del primero y, si hay, la del segundo).
    $frases = New-Object System.Collections.Generic.List[string]
    foreach ($m in $motivos) {
        switch ($m) {
            'CALOR' {
                $c = $met['CALOR']; $max = $c.Tarjetas[1]; $pierde = $c.Tarjetas[4]; $vel = $c.Tarjetas[5]
                if ($null -eq $max.Despues) { $frases.Add('Falta la medición final de temperatura') }
                elseif ($pierde.Despues -ne $true -and [double]$max.Despues -lt 90) { $frases.Add('Tu equipo ya no se sobrecalienta') }
                elseif ($max.Mejoro) { $frases.Add('Tu equipo trabaja más fresco') }
                elseif ($vel -and $vel.Mejoro -and [double]$max.Despues -le [double]$max.Antes + 2) { $frases.Add('Tu equipo rinde más con una temperatura similar') }
                else { $frases.Add('Tu equipo sigue calentándose: revisa las recomendaciones') }
            }
            'LENTO' {
                $l = $met['LENTO']
                if ($l.Tarjetas[0].Mejoro) { $frases.Add('Tu equipo arranca más rápido') } elseif ($l.Tarjetas[2].Mejoro) { $frases.Add('Tu equipo inicia con menos programas') } else { $frases.Add('Optimizamos el inicio y el rendimiento de tu equipo') }
            }
            'ARCHIVOS' { $frases.Add("Apartamos $(Format-Numero $met['ARCHIVOS'].GBApartados 1) GB de archivos innecesarios") }
            'REVISION' { $frases.Add(@{ verde = 'Tu equipo está en buen estado'; amarillo = 'Tu equipo funciona, pero hay cosas que conviene atender'; rojo = 'Tu equipo necesita atención'; gris = 'Revisamos tu equipo' }[$sem.General]) }
        }
    }
    $frase = (@($frases | Select-Object -First 2) -join '. ') + '.'

    # Recomendaciones (máximo 3) desde las alertas de la medición final, las críticas primero.
    $diagFinal = Read-JsonKitOpcional (Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) $momentoFinal) 'diagnostico.json')
    $recs = New-Object System.Collections.Generic.List[string]
    if ($met['CALOR'] -and $met['CALOR'].Tarjetas[4].Despues -eq $true) { $recs.Add('Usa el equipo sobre una superficie dura y despejada, sin tapar las rejillas.') }
    foreach ($al in @($(if ($diagFinal) { $diagFinal.alertas } else { @() }) | Sort-Object { $script:OrdenSeveridadInforme["$($_.Severidad)"] })) {
        foreach ($k in $script:Recomendacion.Keys) { if ($al.Codigo -match $k -and -not $recs.Contains($script:Recomendacion[$k])) { $recs.Add($script:Recomendacion[$k]) } }
    }
    $cfgExp = $script:Ctx.Config.expediente
    $base = if ($a['entregado']) { [datetime]::ParseExact($a['entregado'], 'yyyy-MM-dd', $script:Invariante) } else { Get-Date }
    $garantia = if ($a['garantia_hasta']) { $a['garantia_hasta'] } else { $base.AddDays([int]$cfgExp.garantia_dias).ToString('yyyy-MM-dd', $script:Invariante) }

    # "Comparado con tu visita de <fecha>": la atención anterior con medición.
    $lista = @(Get-ListaAtenciones -Expediente $Expediente)
    $idx = [array]::IndexOf(@($lista | ForEach-Object { $_['carpeta'] }), $Atencion)
    $anterior = $null
    for ($i = $idx - 1; $i -ge 0 -and -not $anterior; $i--) {
        $prev = $lista[$i]
        $sp = Read-SensoresMedicion -Expediente $Expediente -Atencion $prev['carpeta'] -Momento 'despues'
        $sa = if ($met['CALOR']) { $met['CALOR'].Despues } else { $null }
        if ($sp -and $sa) {
            $cp = if ($sp.metricas.cpu_temp_paquete) { $sp.metricas.cpu_temp_paquete } else { $sp.metricas.cpu_temp_nucleo_max }
            $ca = if ($sa.metricas.cpu_temp_paquete) { $sa.metricas.cpu_temp_paquete } else { $sa.metricas.cpu_temp_nucleo_max }
            if ($cp -and $ca) { $anterior = "Comparado con tu visita del $($prev['fecha']): CPU máxima $(Format-Numero $cp.max 0) °C entonces, $(Format-Numero $ca.max 0) °C hoy." }
        } elseif ($prev['mediciones']['antes']) {
            $anterior = "Comparado con tu visita del $($prev['fecha']): ver el informe técnico para el detalle."
        }
    }
    $adv = New-Object System.Collections.Generic.List[string]
    foreach ($k in $met.Keys) { foreach ($x in @($met[$k].Advertencias)) { $adv.Add("${k}: $x") } }
    if ($momentoFinal -eq 'antes') { $adv.Add('Sin diagnóstico DESPUÉS: el semáforo y las recomendaciones son del ANTES') }

    [pscustomobject][ordered]@{
        Tecnico         = $script:Ctx.Config.tecnico
        Cliente         = $f['cliente']
        Equipo          = $f['equipo']
        Fecha           = $(if ($a['fecha']) { $a['fecha'] } else { (Get-Date).ToString('yyyy-MM-dd') })
        Atencion        = $a
        Carpeta         = $Atencion
        Motivos         = $motivos
        Metricas        = $met
        Semaforo        = $sem
        Color           = $sem.General
        Frase           = $frase
        Hecho           = @(Get-HechoSimple -Acciones $a['acciones_realizadas'] -Checklist $a['checklist_fisico'])
        Recomendaciones = @($recs | Select-Object -First 3)
        Proxima         = $base.AddMonths([int]$cfgExp.proxima_mantencion_meses).ToString('yyyy-MM', $script:Invariante)
        Garantia        = $garantia
        Condiciones     = $cfgExp.condiciones_garantia
        DiasParaBorrar  = [int]$cfgExp.dias_para_borrar
        Anterior        = $anterior
        Advertencias    = $adv.ToArray()
        MomentoFinal    = $momentoFinal
    }
}

# ---------------------------------------------------------------- informe del cliente

function Get-SvgFlecha {
    # Flecha según el cambio del valor; verde si mejoró, roja si empeoró, gris si no cambió o falta.
    param($Tarjeta)
    $color = if ($null -eq $Tarjeta.Mejoro) { '#8c959f' } elseif ($Tarjeta.Mejoro) { '#1a7f37' } else { '#cf222e' }
    $baja = $false
    if ($Tarjeta.Mejor -eq 'si_no') { $baja = ($Tarjeta.Antes -eq $true -and $Tarjeta.Despues -eq $false) }
    elseif ($null -ne $Tarjeta.Antes -and $null -ne $Tarjeta.Despues) { $baja = [double]$Tarjeta.Despues -lt [double]$Tarjeta.Antes }
    $camino = if ($null -eq $Tarjeta.Mejoro) { 'M4 12 H20' } elseif ($baja) { 'M12 4 V20 M5 13 L12 20 L19 13' } else { 'M12 20 V4 M5 11 L12 4 L19 11' }
    "<svg class=""flecha"" viewBox=""0 0 24 24"" aria-hidden=""true""><path d=""$camino"" fill=""none"" stroke=""$color"" stroke-width=""3"" stroke-linecap=""round"" stroke-linejoin=""round""/></svg>"
}

function ConvertTo-InformeCliente {
    param([Parameter(Mandatory)]$Datos)
    $d = $Datos
    $css = @'
@page { size: A4; margin: 12mm; }
* { box-sizing: border-box; }
body { margin: 0; font-family: "Segoe UI", Arial, sans-serif; color: #1f2328; font-size: 10.5pt; line-height: 1.35; background: #fff; }
.hoja { width: 186mm; margin: 0 auto; padding: 6mm 0; }
header { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 2.5pt solid #0b6bcb; padding-bottom: 3mm; }
h1 { font-size: 17pt; margin: 0; color: #0b3d75; }
.sub { color: #57606a; font-size: 9.5pt; }
.datos { display: flex; flex-wrap: wrap; margin: 4mm 0; font-size: 10pt; } .datos > div { width: 50%; padding: .5mm 3mm .5mm 0; }
.datos b { color: #57606a; font-weight: 600; }
.estado { display: flex; align-items: center; gap: 5mm; border: 1pt solid #d0d7de; border-radius: 3mm; padding: 4mm; margin: 3mm 0 4mm; }
.luces { display: flex; gap: 2mm; }
.luz { width: 9mm; height: 9mm; border-radius: 50%; background: #e6e8eb; }
.luz.rojo.on { background: #cf222e; } .luz.amarillo.on { background: #d4a72c; } .luz.verde.on { background: #2da44e; } .luz.gris.on { background: #8c959f; }
.frase { font-size: 14pt; font-weight: 600; }
h2 { font-size: 11.5pt; color: #0b3d75; margin: 4mm 0 2mm; text-transform: uppercase; letter-spacing: .3pt; }
.tarjetas { display: flex; flex-wrap: wrap; margin: 0 -1.25mm; }
.tarjeta { width: calc(25% - 2.5mm); margin: 0 1.25mm 2.5mm; border: 1pt solid #d0d7de; border-radius: 2.5mm; padding: 2.5mm 3mm; }
.tarjeta .t { font-size: 9pt; color: #57606a; min-height: 7mm; }
.tarjeta .v { display: flex; align-items: center; gap: 1.5mm; font-size: 12.5pt; font-weight: 600; white-space: nowrap; }
.tarjeta .v .antes { color: #57606a; font-weight: 400; font-size: 10.5pt; }
.flecha { width: 5mm; height: 5mm; }
ul { margin: 0; padding-left: 5mm; } li { margin: .6mm 0; }
.dos { display: flex; } .dos > div { width: 50%; padding-right: 4mm; }
.caja { border-left: 2pt solid #0b6bcb; padding-left: 3mm; }
.nota { font-size: 9pt; color: #57606a; }
.archivos { background: #f6f8fa; border-radius: 2.5mm; padding: 3mm; margin-top: 3mm; font-size: 9.5pt; }
footer { margin-top: 5mm; border-top: 1pt solid #d0d7de; padding-top: 2mm; font-size: 9pt; color: #57606a; display: flex; justify-content: space-between; }
@media print { .hoja { width: auto; padding: 0; } }
'@
    $sb = New-Object System.Text.StringBuilder
    $eq = $d.Equipo
    $equipoTxt = "$($eq['fabricante']) $($eq['modelo'])"
    [void]$sb.AppendLine('<!doctype html><html lang="es"><head><meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge">')
    [void]$sb.AppendLine("<title>Informe de servicio - $(Get-Html $equipoTxt)</title><style>$css</style></head><body><div class=""hoja"">")
    [void]$sb.AppendLine('<header><div><h1>Informe de servicio</h1>')
    [void]$sb.AppendLine("<div class=""sub"">$(Get-Html $d.Tecnico.nombre) · $(Get-Html $d.Tecnico.contacto)</div></div>")
    [void]$sb.AppendLine("<div class=""sub"">$(Get-Html $d.Fecha)</div></header>")
    [void]$sb.AppendLine('<div class="datos">')
    [void]$sb.AppendLine("<div><b>Cliente:</b> $(Get-Html $d.Cliente['nombre'])$(if ($d.Cliente['comuna']) { ' · ' + (Get-Html $d.Cliente['comuna']) })</div>")
    [void]$sb.AppendLine("<div><b>Equipo:</b> $(Get-Html $equipoTxt)</div>")
    [void]$sb.AppendLine("<div><b>Motivo:</b> $(Get-Html ((@($d.Motivos | ForEach-Object { @{ CALOR = 'se calienta'; LENTO = 'está lento'; ARCHIVOS = 'archivos y espacio'; REVISION = 'revisión completa' }[$_] }) -join ', ')))</div>")
    [void]$sb.AppendLine("<div><b>N.º de serie:</b> $(Get-Html $(if ($eq['serie']) { $eq['serie'] } else { '—' }))</div></div>")
    [void]$sb.AppendLine('<div class="estado"><div class="luces">')
    foreach ($c in 'rojo', 'amarillo', 'verde') { [void]$sb.AppendLine("<div class=""luz $c$(if ($d.Color -eq $c) { ' on' })""></div>") }
    [void]$sb.AppendLine("</div><div class=""frase"">$(Get-Html $d.Frase)</div></div>")
    $titulos = @{ CALOR = 'Temperatura'; LENTO = 'Rapidez'; ARCHIVOS = 'Espacio' }
    foreach ($k in $d.Metricas.Keys) {
        $m = $d.Metricas[$k]
        # Al cliente no se le muestran tarjetas sin ningún dato (GPU en un equipo sin GPU dedicada, arranque sin admin).
        $tarj = @($m.Tarjetas | Where-Object { $_ -and ($null -ne $_.Antes -or $null -ne $_.Despues) })
        if ($tarj.Count -eq 0 -and $k -ne 'ARCHIVOS') { continue }
        [void]$sb.AppendLine("<h2>$(Get-Html $titulos[$k]): antes → después</h2><div class=""tarjetas"">")
        foreach ($t in $tarj) {
            [void]$sb.AppendLine("<div class=""tarjeta""><div class=""t"">$(Get-Html $t.Titulo)</div><div class=""v""><span class=""antes"">$(Get-Html (Format-ValorTarjeta $t.Antes $t.Unidad))</span>$(Get-SvgFlecha $t)<span>$(Get-Html (Format-ValorTarjeta $t.Despues $t.Unidad))</span></div></div>")
        }
        if ($k -eq 'ARCHIVOS') {
            [void]$sb.AppendLine("<div class=""tarjeta""><div class=""t"">Espacio apartado</div><div class=""v""><span>$(Get-Html (Format-Numero $m.GBApartados 1)) GB</span></div></div>")
            [void]$sb.AppendLine("<div class=""tarjeta""><div class=""t"">Duplicados apartados</div><div class=""v""><span>$($m.Duplicados)</span></div></div>")
        }
        [void]$sb.AppendLine('</div>')
    }
    if ($d.Anterior) { [void]$sb.AppendLine("<p class=""nota"">$(Get-Html $d.Anterior)</p>") }
    [void]$sb.AppendLine('<div class="dos"><div><h2>Qué hicimos</h2><ul>')
    foreach ($h in @($d.Hecho)) { [void]$sb.AppendLine("<li>$(Get-Html $h)</li>") }
    if (@($d.Hecho).Count -eq 0) { [void]$sb.AppendLine('<li>Revisión y diagnóstico completo del equipo</li>') }
    [void]$sb.AppendLine('</ul></div><div><h2>Te recomendamos</h2><ul>')
    foreach ($r in @($d.Recomendaciones)) { [void]$sb.AppendLine("<li>$(Get-Html $r)</li>") }
    if (@($d.Recomendaciones).Count -eq 0) { [void]$sb.AppendLine('<li>Seguir usándolo como hasta ahora.</li>') }
    [void]$sb.AppendLine("</ul><p class=""caja"">Próxima mantención sugerida: <b>$(Get-Html $d.Proxima)</b></p></div></div>")
    if ($d.Metricas['ARCHIVOS'] -and $d.Metricas['ARCHIVOS'].Elementos -gt 0) {
        $ar = $d.Metricas['ARCHIVOS']
        [void]$sb.AppendLine("<div class=""archivos""><b>Tus archivos apartados</b> ($($ar.Elementos), $(Get-Html (Format-Numero $ar.GBApartados 1)) GB) quedaron en <b>$(Get-Html ($ar.Ubicaciones -join ', '))</b>. No se borró nada. Si en $($d.DiasParaBorrar) días no echas nada de menos, esa carpeta se puede borrar. Para recuperarlos: clic derecho en <b>_DESHACER.ps1</b> (en esa misma carpeta) y «Ejecutar con PowerShell».</div>")
    }
    [void]$sb.AppendLine("<footer><div><b>Garantía hasta $(Get-Html $d.Garantia).</b> $(Get-Html $d.Condiciones)</div></footer>")
    [void]$sb.AppendLine('</div></body></html>')
    $sb.ToString()
}

# ---------------------------------------------------------------- informe técnico

function Get-SvgTemperaturas {
    # Temperatura de CPU (línea) y GPU (segmentos) en el tiempo, antes (rojo) y después (verde).
    param($Antes, $Despues)
    $w = 900; $h = 300; $ml = 46; $mr = 16; $mt = 14; $mb = 34
    $series = @()
    foreach ($par in @(@{ S = $Antes; C = '#cf222e'; N = 'antes' }, @{ S = $Despues; C = '#1a7f37'; N = 'después' })) {
        if (-not $par.S) { continue }
        $cpu = if ($par.S.metricas.cpu_temp_paquete) { 'cpu_temp_paquete' } else { 'cpu_temp_nucleo_max' }
        $series += @{ Puntos = @($par.S.serie); Clave = $cpu; Color = $par.C; Raya = ''; Nombre = "CPU $($par.N)" }
        $series += @{ Puntos = @($par.S.serie); Clave = 'gpu_temp'; Color = $par.C; Raya = '6 4'; Nombre = "GPU $($par.N)" }
    }
    if ($series.Count -eq 0) { return '<p>Sin CSV de sensores.</p>' }
    $xmax = [double](@($series | ForEach-Object { $_.Puntos | ForEach-Object { $_.minuto } }) | Measure-Object -Maximum).Maximum
    if ($xmax -le 0) { $xmax = 1 }
    $ymin = 20.0; $ymax = 105.0
    $fx = { param($x) ($ml + ($w - $ml - $mr) * $x / $xmax).ToString('0.0', $script:Invariante) }
    $fy = { param($y) ($mt + ($h - $mt - $mb) * (1 - ([math]::Min($ymax, [math]::Max($ymin, $y)) - $ymin) / ($ymax - $ymin))).ToString('0.0', $script:Invariante) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<svg viewBox=""0 0 $w $h"" class=""grafico"" role=""img"" aria-label=""Temperaturas en el tiempo"">")
    for ($t = 30; $t -le 100; $t += 10) {
        $y = & $fy $t
        $color = if ($t -eq 90) { '#d4a72c' } else { '#e6e8eb' }
        [void]$sb.Append("<line x1=""$ml"" y1=""$y"" x2=""$($w - $mr)"" y2=""$y"" stroke=""$color""/><text x=""$($ml - 6)"" y=""$y"" font-size=""11"" text-anchor=""end"" dominant-baseline=""middle"" fill=""#57606a"">$t°</text>")
    }
    $paso = @(1, 2, 5, 10, 15, 20, 30, 60) | Where-Object { $xmax / $_ -le 10 } | Select-Object -First 1
    if (-not $paso) { $paso = 120 }
    for ($m = 0; $m -le $xmax; $m += $paso) { [void]$sb.Append("<text x=""$(& $fx $m)"" y=""$($h - 12)"" font-size=""11"" text-anchor=""middle"" fill=""#57606a"">$m min</text>") }
    foreach ($s in $series) {
        $pts = @($s.Puntos | Where-Object { $null -ne $_.($s.Clave) } | ForEach-Object { "$(& $fx $_.minuto),$(& $fy $_.($s.Clave))" })
        if ($pts.Count -lt 2) { continue }
        $raya = if ($s.Raya) { 'stroke-dasharray="' + $s.Raya + '"' } else { '' }
        [void]$sb.Append("<polyline fill=""none"" stroke=""$($s.Color)"" stroke-width=""1.8"" $raya points=""$($pts -join ' ')""/>")
    }
    $lx = $ml + 10
    foreach ($s in $series) {
        $raya = if ($s.Raya) { 'stroke-dasharray="' + $s.Raya + '"' } else { '' }
        [void]$sb.Append("<line x1=""$lx"" y1=""$($mt + 8)"" x2=""$($lx + 22)"" y2=""$($mt + 8)"" stroke=""$($s.Color)"" stroke-width=""2"" $raya/><text x=""$($lx + 26)"" y=""$($mt + 8)"" font-size=""11"" dominant-baseline=""middle"">$(Get-Html $s.Nombre)</text>")
        $lx += 120
    }
    [void]$sb.Append('</svg>')
    $sb.ToString()
}

function ConvertTo-InformeTecnico {
    param([Parameter(Mandatory)]$Datos, [Parameter(Mandatory)]$Expediente)
    $d = $Datos
    $ruta = Join-Path $Expediente.Ruta $d.Carpeta
    $css = @'
body { font-family: "Segoe UI", Arial, sans-serif; color: #1f2328; font-size: 10pt; margin: 0; background: #fff; }
.hoja { max-width: 1000px; margin: 0 auto; padding: 16px; }
h1 { font-size: 18pt; color: #0b3d75; margin: 0 0 4px; } h2 { font-size: 13pt; color: #0b3d75; border-bottom: 1px solid #d0d7de; padding-bottom: 3px; margin-top: 18px; }
h3 { font-size: 11pt; margin: 12px 0 4px; }
table { border-collapse: collapse; width: 100%; margin: 4px 0 8px; } th, td { border: 1px solid #d0d7de; padding: 3px 6px; text-align: left; vertical-align: top; } th { background: #f6f8fa; }
td.n { text-align: right; white-space: nowrap; } .ok { color: #1a7f37; } .mal { color: #cf222e; }
.adv { background: #fff8c5; border: 1px solid #d4a72c; padding: 6px 10px; border-radius: 4px; }
.CRITICO { color: #cf222e; font-weight: 600; } .AVISO { color: #9a6700; } .INFO { color: #57606a; }
.grafico { width: 100%; height: auto; border: 1px solid #d0d7de; border-radius: 4px; }
.rojo { color: #cf222e; } .amarillo { color: #9a6700; } .verde { color: #1a7f37; } .gris { color: #57606a; }
code { background: #f6f8fa; padding: 0 3px; }
@media print { h2 { break-after: avoid; } table, .grafico { break-inside: avoid; } }
'@
    $sb = New-Object System.Text.StringBuilder
    $eq = $d.Equipo
    $a = $d.Atencion
    $fila = { param([object[]]$Celdas, [string]$Tag = 'td') '<tr>' + (($Celdas | ForEach-Object { "<$Tag>$(Get-Html $_)</$Tag>" }) -join '') + '</tr>' }
    [void]$sb.AppendLine("<!doctype html><html lang=""es""><head><meta charset=""utf-8""><meta http-equiv=""X-UA-Compatible"" content=""IE=edge""><title>Informe técnico - $(Get-Html "$($eq['fabricante']) $($eq['modelo'])") - $(Get-Html $d.Fecha)</title><style>$css</style></head><body><div class=""hoja"">")
    [void]$sb.AppendLine("<h1>Informe técnico</h1><div>$(Get-Html "$($eq['fabricante']) $($eq['modelo'])") · S/N $(Get-Html $eq['serie']) · expediente <code>$(Get-Html $Expediente.Id)</code> · atención <code>$(Get-Html $d.Carpeta)</code></div>")
    [void]$sb.AppendLine("<p>Cliente: $(Get-Html $d.Cliente['nombre']) · $(Get-Html $d.Cliente['contacto']) · $(Get-Html $d.Cliente['comuna']) | Motivos: $(Get-Html ($d.Motivos -join ', ')) | Síntoma: $(Get-Html $a['sintoma'])</p>")
    [void]$sb.AppendLine("<p>Equipo: $(Get-Html $eq['cpu']) · $(Get-Html $eq['ram_gb']) GB RAM · $(Get-Html (@($eq['gpu']) -join ' + ')) · $(Get-Html $eq['windows']) · BIOS $(Get-Html $eq['bios'])</p>")
    $med = $a['mediciones']
    [void]$sb.AppendLine("<p>Mediciones: ANTES $(Get-Html $(if ($med['antes']) { "$($med['antes']['fecha']) (admin: $(Format-Celda $med['antes']['admin']))" } else { 'no' })) · DESPUÉS $(Get-Html $(if ($med['despues']) { "$($med['despues']['fecha']) (admin: $(Format-Celda $med['despues']['admin']))" } else { 'no' })) | Paquete: $(Get-Html $a['paquete']) · Precio: $(Get-Html $(if ($null -ne $a['precio']) { '$' + (Format-Numero $a['precio'] 0) })) | Garantía hasta $(Get-Html $d.Garantia)</p>")
    if (@($d.Advertencias).Count -gt 0) { [void]$sb.AppendLine("<div class=""adv""><b>Advertencias</b><ul>$((@($d.Advertencias) | ForEach-Object { "<li>$(Get-Html $_)</li>" }) -join '')</ul></div>") }

    [void]$sb.AppendLine("<h2>Semáforo (medición $(Get-Html (Get-NombreMomento $d.MomentoFinal))): <span class=""$($d.Color)"">$(Get-Html $d.Color)</span></h2><table>$(& $fila @('Área', 'Color', 'Frase', 'Motivos') 'th')")
    foreach ($f in $d.Semaforo.Areas) { [void]$sb.AppendLine("<tr><td>$(Get-Html $f.Area)</td><td class=""$($f.Color)"">$(Get-Html $f.Color)</td><td>$(Get-Html $f.Frase)</td><td>$((@($f.Motivos) | ForEach-Object { Get-Html $_ }) -join '<br>')</td></tr>") }
    [void]$sb.AppendLine('</table>')

    foreach ($k in $d.Metricas.Keys) {
        $m = $d.Metricas[$k]
        [void]$sb.AppendLine("<h2>$k</h2><table>$(& $fila @('Métrica', 'Antes', 'Después', 'Resultado') 'th')")
        foreach ($t in @($m.Tarjetas | Where-Object { $_ })) {
            $res = if ($null -eq $t.Mejoro) { '—' } elseif ($t.Mejoro) { '<span class="ok">mejoró</span>' } else { '<span class="mal">empeoró</span>' }
            [void]$sb.AppendLine("<tr><td>$(Get-Html $t.Titulo)</td><td class=""n"">$(Get-Html (Format-ValorTarjeta $t.Antes $t.Unidad))</td><td class=""n"">$(Get-Html (Format-ValorTarjeta $t.Despues $t.Unidad))</td><td>$res</td></tr>")
        }
        [void]$sb.AppendLine('</table>')
        if ($k -eq 'CALOR') {
            [void]$sb.AppendLine('<h3>Condiciones de medición</h3><table>' + (& $fila @('Condición', 'Antes', 'Después') 'th'))
            foreach ($c in $script:CamposCondiciones.Keys) {
                $va = if ($a['condiciones_medicion']['antes']) { $a['condiciones_medicion']['antes'][$c] } else { $null }
                $vd = if ($a['condiciones_medicion']['despues']) { $a['condiciones_medicion']['despues'][$c] } else { $null }
                [void]$sb.AppendLine((& $fila @($script:CamposCondiciones[$c], (Format-Celda $va), (Format-Celda $vd))))
            }
            [void]$sb.AppendLine('</table><h3>Sensores</h3><table>' + (& $fila @('Métrica', 'Antes: media / p95 / máx', 'Después: media / p95 / máx', 'Columna (antes)') 'th'))
            $nombres = @{}
            foreach ($s in @($m.Antes, $m.Despues)) { if ($s) { foreach ($p in $s.metricas.PSObject.Properties) { $nombres[$p.Name] = 1 } } }
            foreach ($n in $nombres.Keys | Sort-Object) {
                $tx = { param($s) if ($s -and $s.metricas.$n) { $x = $s.metricas.$n; '{0} / {1} / {2} {3}' -f (Format-Numero $x.media 1), (Format-Numero $x.p95 1), (Format-Numero $x.max 1), $x.unidad } else { '—' } }
                [void]$sb.AppendLine((& $fila @($n, (& $tx $m.Antes), (& $tx $m.Despues), $(if ($m.Antes) { $m.Antes.columnas.$n } else { '' }))))
            }
            foreach ($par in @(@{ S = $m.Antes; N = 'ANTES' }, @{ S = $m.Despues; N = 'DESPUÉS' })) {
                if ($par.S) { [void]$sb.AppendLine("<p>$($par.N): $(Get-Html $par.S.archivo) ($(Get-Html $par.S.formato), $(Get-Html $par.S.codificacion)) · $(Format-Numero $par.S.duracion_min 1) min · throttling $(Get-Html $(if ($null -ne $par.S.throttling_pct) { "$(Format-Numero $par.S.throttling_pct 1) %" } else { 'sin sensor' })) · $(Format-Numero $par.S.minutos_sobre_umbral 1) min sobre $($par.S.umbral_c) °C · pierde velocidad: $(Get-Html (Format-Celda $par.S.pierde_velocidad.valor)) ($(Get-Html $par.S.pierde_velocidad.fuente))</p>") }
            }
            [void]$sb.AppendLine('</table>' + (Get-SvgTemperaturas -Antes $m.Antes -Despues $m.Despues))
            $cf = $m.Checklist
            [void]$sb.AppendLine("<h3>Checklist físico</h3><p>Desarme: $(Get-Html (Format-Celda $cf['desarme'])) · limpieza: $(Get-Html (Format-Celda $cf['limpieza'])) · pasta: $(Get-Html $cf['pasta']) · putty/pads: $(Get-Html $cf['putty_pads']) · fotos antes/después: $(Get-Html (Format-Celda $cf['fotos_disipador_antes']))/$(Get-Html (Format-Celda $cf['fotos_disipador_despues'])) · materiales: $(Get-Html (@($m.Materiales) -join ', '))</p>")
        }
        if ($k -eq 'LENTO') {
            $reg = Read-RegistroLento -Expediente $Expediente -Atencion $d.Carpeta
            $pr = $reg['punto_restauracion']
            [void]$sb.AppendLine("<p>Punto de restauración: $(Get-Html $(if ($pr) { "$($pr['descripcion']) ($($pr['fecha']))" } else { 'no se aplicaron acciones' }))</p><table>$(& $fila @('Acción', 'Aplicada', 'Deshecha', 'Para deshacer') 'th')")
            foreach ($r in @($reg['acciones'] | Where-Object { $_ })) { [void]$sb.AppendLine((& $fila @($r['titulo'], $r['aplicada'], $r['deshecha'], (($r['deshacer'] | ConvertTo-Json -Compress))))) }
            [void]$sb.AppendLine('</table>')
        }
        if ($k -eq 'ARCHIVOS') {
            [void]$sb.AppendLine("<p>Apartados: $($m.Elementos) elementos, $(Format-Numero $m.GBApartados 2) GB, $($m.Duplicados) duplicados · en $(Get-Html ($m.Ubicaciones -join ', ')) · deshacer: <a href=""archivos/_DESHACER.ps1"">archivos/_DESHACER.ps1</a> · <a href=""archivos/reporte.csv"">reporte.csv</a></p>")
        }
    }

    foreach ($mo in 'antes', 'despues') {
        $diag = Read-JsonKitOpcional (Join-Path (Join-Path $ruta $mo) 'diagnostico.json')
        if (-not $diag) { continue }
        [void]$sb.AppendLine("<h2>Alertas $($mo.ToUpperInvariant())</h2><table>$(& $fila @('Severidad', 'Código', 'Texto') 'th')")
        foreach ($al in @($diag.alertas)) { [void]$sb.AppendLine("<tr><td class=""$($al.Severidad)"">$(Get-Html $al.Severidad)</td><td>$(Get-Html $al.Codigo)</td><td>$(Get-Html $al.Texto)</td></tr>") }
        [void]$sb.AppendLine('</table>')
    }
    $diagF = Read-JsonKitOpcional (Join-Path (Join-Path $ruta $d.MomentoFinal) 'diagnostico.json')
    if ($diagF -and $diagF.datos.hardware) {
        $hw = $diagF.datos.hardware
        [void]$sb.AppendLine("<h2>Discos ($(Get-NombreMomento $d.MomentoFinal))</h2><table>$(& $fila @('Disco', 'Modelo', 'Tipo / bus', 'GB', 'Salud Windows', 'SMART (CrystalDiskInfo)', 'Letras') 'th')")
        foreach ($k in @($hw.Discos)) {
            $c = Find-SmartCrystal -Lista @($hw.SmartCrystal) -Disco $k
            $smart = if ($c) { "salud $($c.SaludTexto) $($c.SaludPct) % · $($c.TemperaturaC) °C · uso $($c.UsoPct) % · errores de medio $($c.ErroresMedio) · $($c.HorasEncendido) h" } else { "$($k.Smart)" }
            [void]$sb.AppendLine((& $fila @($k.Disco, $k.Modelo, "$($k.Tipo) $($k.Bus)", $k.TamanoGB, $k.Salud, $smart, $k.Letras)))
        }
        [void]$sb.AppendLine('</table>')
        foreach ($b in @($hw.Baterias | Where-Object { $_ })) { [void]$sb.AppendLine("<h2>Batería</h2><p>$(Get-Html "$($b.Fabricante) $($b.Id)") · salud $(Format-Numero $b.SaludPct 1) % ($($b.CargaCompletaMWh) de $($b.DisenoMWh) mWh) · $($b.Ciclos) ciclos · <a href=""$($d.MomentoFinal)/bateria.html"">informe de batería</a></p>") }
    }
    [void]$sb.AppendLine('<h2>Archivos</h2><ul>')
    foreach ($mo in 'antes', 'despues') {
        foreach ($n in 'resumen.txt', 'diagnostico.json', 'metricas.json', 'sensores.csv', 'sensores_resumen.json', 'discos.txt', 'log.txt') {
            if ([IO.File]::Exists((Join-Path (Join-Path $ruta $mo) $n))) { [void]$sb.AppendLine("<li><a href=""$mo/$n"">$mo/$n</a></li>") }
        }
        if ([IO.Directory]::Exists((Join-Path (Join-Path $ruta $mo) 'csv'))) { [void]$sb.AppendLine("<li><a href=""$mo/csv/"">$mo/csv/</a> (una tabla por archivo)</li>") }
    }
    [void]$sb.AppendLine('<li><a href="trabajo.log">trabajo.log</a></li></ul>')
    [void]$sb.AppendLine("<p class=""INFO"">Generado $(Get-Html (ConvertTo-TextoFecha (Get-Date))) con KIT SERVICIO v$(Get-Html $script:Ctx.Version).</p></div></body></html>")
    $sb.ToString()
}

function Export-Informes {
    # Genera ambos informes en la carpeta de la atención si la ficha está completa. Si falta algo,
    # no genera nada y devuelve la lista.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $faltan = @(Test-FichaCompleta -Expediente $Expediente -Atencion $Atencion)
    if ($faltan.Count -gt 0) { return [pscustomobject]@{ Generado = $false; Faltan = $faltan; Cliente = $null; Tecnico = $null } }
    $datos = Get-DatosInforme -Expediente $Expediente -Atencion $Atencion
    $carpeta = Join-Path $Expediente.Ruta $Atencion
    $cliente = Join-Path $carpeta 'informe_cliente.html'
    $tecnico = Join-Path $carpeta 'informe_tecnico.html'
    if (-not $PSCmdlet.ShouldProcess($carpeta, 'Generar informes')) { return }
    [IO.File]::WriteAllText($cliente, (ConvertTo-InformeCliente -Datos $datos), $script:Utf8Bom)
    [IO.File]::WriteAllText($tecnico, (ConvertTo-InformeTecnico -Datos $datos -Expediente $Expediente), $script:Utf8Bom)
    Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "INFORMES | generados informe_cliente.html e informe_tecnico.html (semáforo $($datos.Color))"
    [pscustomobject]@{ Generado = $true; Faltan = @(); Cliente = $cliente; Tecnico = $tecnico; Datos = $datos }
}
