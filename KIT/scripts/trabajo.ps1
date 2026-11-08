#Requires -Version 5.1
<#
.SYNOPSIS
    Paso "Trabajo" por consola: lo que corresponde a cada motivo de la atención abierta.
.DESCRIPTION
    CALOR: condiciones de medición, importar CSV de sensores, checklist físico y métricas.
    LENTO: acciones sugeridas (con qué hace y cómo se deshace), aplicar las elegidas, deshacer.
    ARCHIVOS: analizar, mover a _PARA_BORRAR lo marcado (nunca borra), deshacer.
    REVISION: semáforo por área.
    Nada se aplica sin confirmar. Respaldo de consola de la interfaz gráfica.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Menú de consola')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$ErrorActionPreference = 'Stop'
$raizScripts = $PSScriptRoot
try {
    foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe', 'Flujo', 'Soporte') { . (Join-Path $raizScripts "lib\$lib.ps1") }
    foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $raizScripts "motivos\$m.ps1") }
    Initialize-Contexto -RaizScripts $raizScripts
    Initialize-Privacidad
    $script:Ctx.Admin = Get-EstadoAdmin
} catch {
    Write-Host " No se pudo cargar el kit: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

function Read-Linea {
    param([string]$Pregunta, [AllowNull()]$Actual)
    $mostrar = if ($null -ne $Actual -and "$Actual" -ne '') { " [$Actual]" } else { '' }
    Write-Host ('  {0}{1}: ' -f $Pregunta, $mostrar) -NoNewline
    $r = if ([Console]::IsInputRedirected) { $x = [Console]::In.ReadLine(); Write-Host $x; $x } else { Read-Host }
    if ($null -eq $r) { return '' }
    $r.Trim()
}

function Test-Si { param([string]$T) $T -match '^(?i)(s|si|sí)$' }

function Show-Error { param([string]$Texto) Write-Host "    $Texto" -ForegroundColor Red }

function Show-Tarjetas {
    param($Metricas)
    foreach ($t in @($Metricas.Tarjetas)) {
        $fmt = { param($v) if ($null -eq $v) { '—' } elseif ($v -is [bool]) { if ($v) { 'sí' } else { 'no' } } else { "$(Format-Numero $v 1) $($t.Unidad)".Trim() } }
        $flecha = if ($null -eq $t.Mejoro) { '' } elseif ($t.Mejoro) { '  (mejoró)' } else { '  (empeoró)' }
        $color = if ($null -eq $t.Mejoro) { 'Gray' } elseif ($t.Mejoro) { 'Green' } else { 'Red' }
        Write-Host ('   {0,-30} {1,12}  ->  {2,-12}{3}' -f $t.Titulo, (& $fmt $t.Antes), (& $fmt $t.Despues), $flecha) -ForegroundColor $color
    }
    foreach ($a in @($Metricas.Advertencias)) { Write-Host "   Ojo: $a" -ForegroundColor Yellow }
}

# ------------------------------------------------------------------------------ calor

function Edit-CondicionesCalor {
    param($Exp, [string]$At, [string]$Momento)
    $previas = (Get-EntradaAtencion -Expediente $Exp -Carpeta $At)['condiciones_medicion'][$Momento]
    if (-not $previas -and $Momento -eq 'despues') { $previas = (Get-EntradaAtencion -Expediente $Exp -Carpeta $At)['condiciones_medicion']['antes'] }
    Write-Host "  Condiciones de la medición $($Momento.ToUpperInvariant()) (Enter = deja el valor; el DESPUÉS propone las del ANTES)" -ForegroundColor White
    $v = [ordered]@{}
    foreach ($k in $script:CamposCondiciones.Keys) {
        $actual = if ($previas) { $previas[$k] } else { $null }
        $r = Read-Linea -Pregunta $script:CamposCondiciones[$k] -Actual $actual
        $v[$k] = if ($r -eq '') { $actual } else { $r }
    }
    try { Set-CondicionesCalor -Expediente $Exp -Atencion $At -Momento $Momento -Valores $v; Write-Host '    Guardadas.' -ForegroundColor Green }
    catch { Show-Error $_.Exception.Message }
}

function Import-CsvConsola {
    param($Exp, [string]$At, [string]$Momento)
    # El CSV que dejó HWiNFO (raíz del pendrive, Escritorio, Documentos...): Enter lo usa.
    $hallado = $null
    try { $h = @(Find-CsvSensores -Expediente $Exp -Atencion $At -Momento $Momento); if ($h.Count) { $hallado = $h[0] } } catch { Write-Verbose "Sin búsqueda de CSV: $($_.Exception.Message)" }
    if ($hallado) {
        Write-Host ('    Encontré {0} en {1} ({2}, {3} KB){4}' -f $hallado.Nombre, $hallado.Donde, $hallado.Fecha.ToString('dd-MM HH:mm'), $hallado.KB, $(if ($hallado.EnCurso) { ': todavía se está grabando, detén HWiNFO primero' } else { '' })) -ForegroundColor Cyan
    }
    $ruta = "$(Read-Linea -Pregunta "Ruta del CSV de sensores ($($Momento.ToUpperInvariant()))$(if ($hallado) { ', Enter = el encontrado' })" -Actual $null)".Trim('"')
    if (-not $ruta -and $hallado) { $ruta = $hallado.Ruta }
    if (-not $ruta) { return }
    try {
        $r = Import-SensoresMedicion -Expediente $Exp -Atencion $At -Momento $Momento -Ruta $ruta
        $cpu = if ($r.metricas.cpu_temp_paquete) { $r.metricas.cpu_temp_paquete } else { $r.metricas.cpu_temp_nucleo_max }
        Write-Host ("    {0}, {1} filas, {2} min" -f $r.formato, $r.filas, (Format-Numero $r.duracion_min 1)) -ForegroundColor Green
        if ($cpu) { Write-Host ("    CPU {0} °C promedio, {1} °C máximo, {2} min sobre {3} °C" -f (Format-Numero $cpu.media 1), (Format-Numero $cpu.max 1), (Format-Numero $r.minutos_sobre_umbral 1), $r.umbral_c) }
        if ($r.metricas.gpu_temp) { Write-Host ("    GPU {0} °C promedio, {1} °C máximo" -f (Format-Numero $r.metricas.gpu_temp.media 1), (Format-Numero $r.metricas.gpu_temp.max 1)) }
        if ($hallado -and $ruta -eq $hallado.Ruta -and (Test-Si (Read-Linea -Pregunta "    ¿Lo saco de $($hallado.Donde) para no dejarlo en el equipo? (s/N)" -Actual $null))) {
            if (Remove-CsvSensoresOrigen -Expediente $Exp -Atencion $At -Momento $Momento -Ruta $ruta) { Write-Host '    Sacado: quedó la copia en el expediente.' -ForegroundColor Green }
        }
        Write-Host ("    Pierde velocidad por calor: {0} ({1})" -f $(if ($null -eq $r.pierde_velocidad.valor) { 'sin dato' } elseif ($r.pierde_velocidad.valor) { 'sí' } else { 'no' }), $r.pierde_velocidad.fuente)
    } catch { Show-Error $_.Exception.Message }
}

function Edit-ChecklistFisico {
    param($Exp, [string]$At)
    $a = Get-EntradaAtencion -Expediente $Exp -Carpeta $At
    $c = $a['checklist_fisico']
    $preguntas = [ordered]@{ desarme = '¿Desarme? (s/n)'; limpieza = '¿Limpieza? (s/n)'; pasta = 'Pasta térmica o PTM usada'; putty_pads = 'Putty o pads usados'; fotos_disipador_antes = '¿Fotos del disipador antes? (s/n)'; fotos_disipador_despues = '¿Fotos del disipador después? (s/n)' }
    foreach ($k in $preguntas.Keys) {
        $r = Read-Linea -Pregunta $preguntas[$k] -Actual $c[$k]
        if ($r -eq '') { continue }
        try { Set-Ficha -Expediente $Exp -Atencion $At -Valores @{ "checklist_fisico.$k" = $(if ($r -eq '-') { $null } else { $r }) } } catch { Show-Error ($_.Exception.Message -replace '^No se guardó la ficha:\s*-\s*', '') }
    }
    $r = Read-Linea -Pregunta 'Materiales (separados por ;)' -Actual ((@($a['materiales']) -join '; '))
    if ($r) { try { Set-Ficha -Expediente $Exp -Atencion $At -Valores @{ materiales = $(if ($r -eq '-') { $null } else { $r }) } } catch { Show-Error $_.Exception.Message } }
    Write-TrabajoLog -Expediente $Exp -Atencion $At -Texto 'CALOR | checklist físico actualizado'
}

# ------------------------------------------------------------------------------ lento

function Invoke-LentoConsola {
    param($Exp, [string]$At)
    try { $acciones = @(Get-AccionesLento -Expediente $Exp -Atencion $At) } catch { Show-Error $_.Exception.Message; return }
    if ($acciones.Count -eq 0) { Write-Host '    No hay acciones sugeridas para este equipo.' -ForegroundColor Green; return }
    for ($i = 0; $i -lt $acciones.Count; $i++) {
        $a = $acciones[$i]
        $marcas = @(); if ($a.RequiereAdmin) { $marcas += 'admin' }; if ($a.Riesgo -eq 'revisar') { $marcas += 'revisar' }; if ($a.Tipo -eq 'manual') { $marcas += 'manual' }
        Write-Host ('  {0,2}) {1}{2}' -f ($i + 1), $a.Titulo, $(if ($marcas) { "  [$($marcas -join ', ')]" } else { '' })) -ForegroundColor $(if ($a.Riesgo -eq 'revisar') { 'Yellow' } elseif ($a.Tipo -eq 'manual') { 'DarkGray' } else { 'Gray' })
        Write-Host "      Qué hace: $($a.QueHace)$(if ($a.Deshacer) { ' | Deshacer: ' + $a.Deshacer })" -ForegroundColor DarkGray
    }
    $r = Read-Linea -Pregunta 'Números a aplicar (ej: 1,3,5; Enter = ninguno)' -Actual $null
    if (-not $r) { return }
    $nums = @($r -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 1 -and $_ -le $acciones.Count })
    $elegidas = @($nums | Select-Object -Unique | ForEach-Object { $acciones[$_ - 1] })
    if ($elegidas.Count -eq 0) { return }
    if (-not (Test-Si (Read-Linea -Pregunta "¿Aplicar $($elegidas.Count) acciones? (s/N)" -Actual $null))) { return }
    $sinPunto = $false
    if (-not $script:Ctx.Admin.Elevado) {
        Write-Host '    Sin admin no se puede crear el punto de restauración (y algunas acciones lo necesitan).' -ForegroundColor Yellow
        $sinPunto = Test-Si (Read-Linea -Pregunta '¿Seguir sin punto de restauración? Lo recomendado es relanzar como admin (s/N)' -Actual $null)
        if (-not $sinPunto) { return }
    }
    try {
        try {
            $hechas = @(Invoke-AccionesLento -Expediente $Exp -Atencion $At -Acciones $elegidas -SinPuntoRestauracion:$sinPunto)
        } catch {
            # Windows no deja crear el punto: no se aplicó nada y el técnico decide si sigue sin él.
            $msj = "$($_.Exception.Message)"
            if (-not $msj.StartsWith($script:PrefijoSinPunto)) { throw }
            Write-Host "    No se pudo crear el punto de restauración: $($msj.Substring($script:PrefijoSinPunto.Length))" -ForegroundColor Yellow
            Write-Host '    No se aplicó nada. El kit no cambia esa configuración del equipo.' -ForegroundColor Yellow
            if (-not (Test-Si (Read-Linea -Pregunta '¿Aplicar igual sin punto de restauración? Cada acción se puede deshacer (s/N)' -Actual $null))) { return }
            $hechas = @(Invoke-AccionesLento -Expediente $Exp -Atencion $At -Acciones $elegidas -SinPuntoRestauracion)
        }
        foreach ($h in $hechas) { Write-Host "    Hecho: $h" -ForegroundColor Green }
    } catch { Show-Error $_.Exception.Message }
}

function Undo-LentoConsola {
    param($Exp, [string]$At)
    $reg = Read-RegistroLento -Expediente $Exp -Atencion $At
    $vivas = @($reg['acciones'] | Where-Object { $_ -and -not $_['deshecha'] })
    if ($vivas.Count -eq 0) { Write-Host '    No hay acciones aplicadas.'; return }
    foreach ($v in $vivas) { Write-Host "   - $($v['titulo']) (aplicada $($v['aplicada']))" }
    if (Test-Si (Read-Linea -Pregunta "¿Deshacer las $($vivas.Count)? (s/N)" -Actual $null)) {
        foreach ($d in @(Undo-AccionesLento -Expediente $Exp -Atencion $At)) { Write-Host "    Deshecha: $d" -ForegroundColor Green }
    }
}

# ------------------------------------------------------------------------------ archivos

function Invoke-ArchivosConsola {
    param($Exp, [string]$At, [string]$Accion)
    try {
        switch ($Accion) {
            'analizar' {
                Write-Host '    Analizando (puede tardar unos minutos)...' -ForegroundColor DarkGray
                $rep = Invoke-AnalisisArchivos -Expediente $Exp -Atencion $At
                foreach ($k in $rep.resumen.Keys) { Write-Host ('   {0,-20} {1,6} elementos {2,10}  marcados: {3}' -f $k, $rep.resumen[$k].cantidad, (Format-Tamano $rep.resumen[$k].bytes), $rep.resumen[$k].seleccionados) }
                Write-Host "    Detalle para revisar: $(Join-Path (Join-Path (Join-Path $Exp.Ruta $At) 'archivos') 'reporte.csv')" -ForegroundColor DarkGray
            }
            'mover' {
                $rep = Read-ReporteArchivos -Expediente $Exp -Atencion $At
                if (-not $rep) { Show-Error 'Primero analiza.'; return }
                $marcados = @($rep['candidatos'] | Where-Object { $_['seleccionado'] })
                $r = Read-Linea -Pregunta 'Ids a NO mover (ej: 4,7; Enter = ninguno; ver reporte.csv)' -Actual $null
                $fuera = @($r -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                $ids = @($marcados | Where-Object { $_['id'] -notin $fuera } | ForEach-Object { [int]$_['id'] })
                $bytes = [long](@($marcados | Where-Object { $_['id'] -in $ids } | ForEach-Object { $_['tamano'] }) | Measure-Object -Sum).Sum
                if ($ids.Count -eq 0) { return }
                if (-not (Test-Si (Read-Linea -Pregunta "¿Mover $($ids.Count) elementos ($(Format-Tamano $bytes)) a _PARA_BORRAR en su mismo disco? No se borra nada (s/N)" -Actual $null))) { return }
                $m = Move-ArchivosParaBorrar -Expediente $Exp -Atencion $At -Ids $ids
                Write-Host "    Movidos $($m.Movidos) ($(Format-Tamano $m.Bytes)) a $($m.Destinos -join ', '). Para devolverlos: _DESHACER.ps1 en esa carpeta." -ForegroundColor Green
                foreach ($s in $m.Saltados) { Write-Host "    No movido: $s" -ForegroundColor Yellow }
            }
            'deshacer' {
                if (Test-Si (Read-Linea -Pregunta '¿Devolver a su lugar todo lo movido? (s/N)' -Actual $null)) {
                    $u = Undo-MovimientoArchivos -Expediente $Exp -Atencion $At
                    Write-Host "    Devueltos: $($u.Devueltos)" -ForegroundColor Green
                    foreach ($p in $u.Problemas) { Write-Host "    $p" -ForegroundColor Yellow }
                }
            }
        }
    } catch { Show-Error $_.Exception.Message }
}

# ------------------------------------------------------------------------------ inicio

$identidad = Get-IdentidadEquipo
$exp = Get-Expediente -Identidad $identidad
if (-not $exp) { Write-Host ' Este equipo no tiene expediente: empieza por la ficha o el diagnóstico ANTES.' -ForegroundColor Yellow; exit 0 }
$at = Get-AtencionAbierta -Expediente $exp
if (-not $at) { Write-Host ' No hay una atención abierta: empieza por la ficha o el diagnóstico ANTES.' -ForegroundColor Yellow; exit 0 }

while ($true) {
    $a = Get-EntradaAtencion -Expediente $exp -Carpeta $at
    $motivos = @($a['motivos'] | Where-Object { $_ })
    Write-Host ''
    Write-Host " TRABAJO | $($exp.Id) | $at | motivos: $(if ($motivos) { $motivos -join ', ' } else { '(ninguno: complétalos en la ficha)' }) | admin: $(if ($script:Ctx.Admin.Elevado) { 'sí' } else { 'no' })" -ForegroundColor Cyan
    try { Write-Host " Siguiente: $((Get-SiguientePaso -Expediente (Read-Expediente $exp.Ruta) -Atencion $at).Texto)" -ForegroundColor White } catch { Write-Verbose "Sin siguiente paso: $($_.Exception.Message)" }
    $op = [ordered]@{}
    if ($motivos -contains 'CALOR') { $op['1'] = 'CALOR: condiciones ANTES'; $op['2'] = 'CALOR: importar CSV ANTES'; $op['3'] = 'CALOR: checklist físico y materiales'; $op['4'] = 'CALOR: condiciones DESPUÉS'; $op['5'] = 'CALOR: importar CSV DESPUÉS'; $op['6'] = 'CALOR: ver métricas' }
    if ($motivos -contains 'LENTO') { $op['7'] = 'LENTO: acciones sugeridas'; $op['8'] = 'LENTO: deshacer acciones'; $op['9'] = 'LENTO: ver métricas' }
    if ($motivos -contains 'ARCHIVOS') { $op['A'] = 'ARCHIVOS: analizar'; $op['M'] = 'ARCHIVOS: mover lo marcado a _PARA_BORRAR'; $op['D'] = 'ARCHIVOS: deshacer movimiento'; $op['V'] = 'ARCHIVOS: ver resultado' }
    $op['S'] = 'Semáforo de revisión'
    $op['P'] = 'Generar pre-informe (cómo está antes del trabajo)'
    $op['I'] = 'Generar informes (cliente y técnico)'
    $op['W'] = 'PDF y mensaje para WhatsApp (del informe, o del pre-informe si aún no hay informe)'
    $op['Z'] = 'Paquete de soporte (.zip sin datos del cliente, en KIT\soporte)'
    $op['0'] = 'Volver'
    foreach ($k in $op.Keys) { Write-Host ('  {0}) {1}' -f $k, $op[$k]) }
    $r = (Read-Linea -Pregunta 'Opción' -Actual $null).ToUpperInvariant()
    if (-not $op.Contains($r) -or $r -eq '0') { if ($r -eq '0' -or $r -eq '') { break } else { continue } }
    switch ($r) {
        '1' { Edit-CondicionesCalor -Exp $exp -At $at -Momento 'antes' }
        '2' { Import-CsvConsola -Exp $exp -At $at -Momento 'antes' }
        '3' { Edit-ChecklistFisico -Exp $exp -At $at }
        '4' { Edit-CondicionesCalor -Exp $exp -At $at -Momento 'despues' }
        '5' { Import-CsvConsola -Exp $exp -At $at -Momento 'despues' }
        '6' { Show-Tarjetas (Get-MetricasCalor -Expediente $exp -Atencion $at) }
        '7' { Invoke-LentoConsola -Exp $exp -At $at }
        '8' { Undo-LentoConsola -Exp $exp -At $at }
        '9' { Show-Tarjetas (Get-MetricasLento -Expediente $exp -Atencion $at) }
        'A' { Invoke-ArchivosConsola -Exp $exp -At $at -Accion 'analizar' }
        'M' { Invoke-ArchivosConsola -Exp $exp -At $at -Accion 'mover' }
        'D' { Invoke-ArchivosConsola -Exp $exp -At $at -Accion 'deshacer' }
        'V' { $m = Get-MetricasArchivos -Expediente $exp -Atencion $at; Show-Tarjetas $m; Write-Host "   Apartado: $($m.GBApartados) GB en $($m.Elementos) elementos ($($m.Duplicados) duplicados) | $($m.Ubicaciones -join ', ')"; Write-Host "   Cómo recuperar: $($m.ComoRecuperar)" -ForegroundColor DarkGray }
        'P' {
            try {
                $pre = Export-PreInforme -Expediente (Read-Expediente $exp.Ruta) -Atencion $at
                if (-not $pre.Generado) { Write-Host '    Primero haz el diagnóstico ANTES.' -ForegroundColor Yellow }
                else {
                    Write-Host "    Listo: $($pre.Ruta)" -ForegroundColor Green
                    if (@($pre.Falta).Count) { Write-Host "    Parcial, falta: $(@($pre.Falta) -join ' y ')" -ForegroundColor Yellow }
                    if (Test-Si (Read-Linea -Pregunta '¿Abrir el pre-informe? (s/N)' -Actual $null)) { Open-InformeNavegador -Ruta $pre.Ruta }
                }
            } catch { Show-Error $_.Exception.Message }
        }
        'I' {
            try {
                $inf = Export-Informes -Expediente $exp -Atencion $at
                if (-not $inf.Generado) {
                    Write-Host '    No se generaron: falta en la ficha (opción 3 de INICIAR):' -ForegroundColor Yellow
                    foreach ($f in $inf.Faltan) { Write-Host "     - $($f.Texto)" -ForegroundColor Yellow }
                } else {
                    Write-Host "    Listos: $($inf.Cliente)" -ForegroundColor Green
                    Write-Host "            $($inf.Tecnico)" -ForegroundColor Green
                    foreach ($x in @($inf.Datos.Advertencias)) { Write-Host "    Ojo: $x" -ForegroundColor Yellow }
                    if (Test-Si (Read-Linea -Pregunta '¿Abrir el informe del cliente? (s/N)' -Actual $null)) { Open-InformeNavegador -Ruta $inf.Cliente }
                }
            } catch { Show-Error $_.Exception.Message }
        }
        'W' {
            try {
                $e2 = Read-Expediente $exp.Ruta
                $html = Join-Path (Join-Path $exp.Ruta $at) 'informe_cliente.html'
                $final = [IO.File]::Exists($html)
                if (-not $final) {
                    $pre = Export-PreInforme -Expediente $e2 -Atencion $at
                    $html = if ($pre.Generado) { $pre.Ruta } else { $null }
                }
                if (-not $html) { Write-Host '    Primero haz el diagnóstico ANTES.' -ForegroundColor Yellow }
                else {
                    Write-Host '    Guardando el PDF con Edge (sin ventana)...'
                    $pdf = Export-PdfInforme -Html $html
                    Write-TrabajoLog -Expediente $e2 -Atencion $at -Texto "PDF | $([IO.Path]::GetFileName($pdf)) guardado"
                    Write-Host "    PDF: $pdf" -ForegroundColor Green
                    $msg = Get-MensajeWhatsApp -Expediente $e2 -Atencion $at -Tipo $(if ($final) { 'final' } else { 'pre' })
                    Write-Host ''
                    Write-Host $msg
                    Write-Host ''
                    try { Set-Clipboard -Value $msg; Write-Host '    Mensaje copiado: pégalo en WhatsApp y adjunta el PDF.' -ForegroundColor Green } catch { Write-Host '    Copia el mensaje de arriba.' -ForegroundColor Yellow }
                }
            } catch { Show-Error $_.Exception.Message }
        }
        'Z' {
            try { Write-Host "    Listo: $(Export-PaqueteSoporte -Expediente (Read-Expediente $exp.Ruta) -Atencion $at)" -ForegroundColor Green } catch { Show-Error $_.Exception.Message }
        }
        'S' {
            $s = Get-SemaforoRevision -Expediente $exp -Atencion $at -Momento $(if (Test-Medicion -Expediente $exp -Atencion $at -Momento 'despues') { 'despues' } else { 'antes' })
            $col = @{ verde = 'Green'; amarillo = 'Yellow'; rojo = 'Red'; gris = 'DarkGray' }
            Write-Host "   General: $($s.General.ToUpperInvariant()) (medición $($s.Momento))" -ForegroundColor $col[$s.General]
            foreach ($f in $s.Areas) { Write-Host ('   {0,-20} {1,-9} {2}' -f $f.Area, $f.Color, $f.Frase) -ForegroundColor $col[$f.Color]; foreach ($m in $f.Motivos) { Write-Host "        - $m" -ForegroundColor DarkGray } }
        }
    }
}
exit 0
