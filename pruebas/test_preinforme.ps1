#Requires -Version 5.1
<#
.SYNOPSIS
    Prueba el pre-informe con datos sintéticos, en la carpeta temporal: sin diagnóstico, parcial,
    completo, siempre con el ANTES, sin datos de la ficha y texto que no se escapa.
    -Conservar deja la carpeta para mirar el HTML.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param([switch]$Conservar)
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe') { . (Join-Path $scripts "lib\$lib.ps1") }
foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $scripts "motivos\$m.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:Ctx.Config.tecnico.contacto = 'contacto de prueba'
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_pre_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$script:Ctx.CarpetaClientes = Join-Path $tmp 'clientes'

function New-CsvHwinfo {
    # 10 minutos de HWiNFO en inglés, una fila cada 2 s.
    param([string]$Ruta, [int]$TempBase, [int]$Mhz)
    $l = @('Date,Time,"CPU Package [°C]","Average Effective Clock [MHz]","Package/Ring Thermal Throttling [Yes/No]"')
    for ($i = 0; $i -lt 300; $i++) { $l += ('2.11.2026,10:{0}:{1}.000,{2}.0,{3}.0,No' -f [int][math]::Floor($i * 2 / 60), (($i * 2) % 60), ($TempBase + ($i % 5)), ($Mhz + ($i % 40))) }
    [IO.File]::WriteAllLines($Ruta, $l, (New-Object Text.UTF8Encoding($true)))
}
function Read-Hoja {
    # Get-Html escribe los acentos como entidades (ó = &#243;): aquí se compara el texto que ve el cliente.
    param([string]$Ruta)
    [Net.WebUtility]::HtmlDecode([IO.File]::ReadAllText($Ruta))
}
function Set-DiagnosticoFalso {
    # diagnostico.json mínimo: lo único que el pre-informe lee de ahí son las alertas.
    param($Exp, [string]$At, [string]$Momento, [object[]]$Alertas)
    $dir = Join-Path (Join-Path $Exp.Ruta $At) $Momento
    $null = New-Item -ItemType Directory -Force $dir
    $json = [ordered]@{ kit = @{ generado = '2026-11-05 10:00:00'; admin = @{ Elevado = $true } }; alertas = @($Alertas); datos = @{ equipo = @{ TieneBateria = $true } } } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $dir 'diagnostico.json'), $json, (New-Object Text.UTF8Encoding($false)))
}
function New-Prueba {
    param([string]$Serie, [string]$Motivos = 'CALOR')
    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Pre'; Serie = $Serie; SerieOriginal = $Serie; Uuid = $null; PlacaSerie = $null })
    $a = New-Atencion -Expediente $e
    Set-Ficha -Expediente $e -Atencion $a -Valores ([ordered]@{ motivos = $Motivos })
    [pscustomobject]@{ Exp = Read-Expediente $e.Ruta; At = $a }
}
$alertas = @(
    [ordered]@{ Severidad = 'AVISO'; Codigo = 'HW-BATERIA'; Texto = 'Batería con 71 % de salud' }
    [ordered]@{ Severidad = 'CRITICO'; Codigo = 'HW-SMART-AVISO'; Texto = 'Disco 0 con sectores reasignados' }
    [ordered]@{ Severidad = 'AVISO'; Codigo = 'SW-RUTA'; Texto = 'Programa en C:\Users\<U1>\AppData' }
    [ordered]@{ Severidad = 'INFO'; Codigo = 'HW-GPU-DRIVER'; Texto = 'Driver de video del 2020-10-28 (más de 12 meses)' }
)
$cond = [ordered]@{ enchufado = 's'; plan = 'Equilibrado'; ventiladores = 'Auto'; superficie = 'Mesa'; temp_ambiente_c = '22'; carga_tipo = 'OCCT CPU'; carga_duracion_min = '10' }

try {
    '== Sin diagnóstico ANTES no genera nada'
    $x = New-Prueba 'PRE001'
    $r = Export-PreInforme -Expediente $x.Exp -Atencion $x.At
    $ruta = Join-Path (Join-Path $x.Exp.Ruta $x.At) 'pre_informe.html'
    Assert 'responde que no se generó' ($r.Generado -eq $false)
    Assert 'no deja archivo' (-not [IO.File]::Exists($ruta))

    '== Con diagnóstico y sin CSV: sale parcial, sin exigir la ficha'
    Set-DiagnosticoFalso -Exp $x.Exp -At $x.At -Momento antes -Alertas $alertas
    $r = Export-PreInforme -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At
    Assert 'se generó sin nombre de cliente' ($r.Generado -and [IO.File]::Exists($r.Ruta))
    Assert 'dice que falta el CSV y las condiciones' (@($r.Falta).Count -eq 2 -and ($r.Falta -join ' ') -match 'CSV' -and ($r.Falta -join ' ') -match 'condiciones')
    $h = Read-Hoja $r.Ruta
    Assert 'la hoja avisa que es parcial' ($h -match 'Pre-informe parcial')
    Assert 'no muestra temperaturas inventadas' ($h -notmatch 'temperatura promedio')
    Assert 'la temperatura sin medir no sale como área' ($h -notmatch 'Sin medición de temperatura')
    Assert 'semáforo rojo por el disco' ($r.Datos.Color -eq 'rojo' -and $h -match 'Tu equipo necesita atención')
    Assert 'la recomendación crítica va primero' ($r.Datos.Recomendaciones[0] -like 'Respalda*')
    $partes = $h -split 'Detalle para el técnico'
    Assert 'la hoja del cliente no trae los textos para el técnico' ($partes[0] -notmatch 'sectores reasignados' -and $partes[0] -notmatch 'Programa en C:')
    Assert 'el detalle del técnico sí los trae, críticos primero' ($partes[1] -match 'sectores reasignados' -and $partes[1].IndexOf('sectores reasignados') -lt $partes[1].IndexOf('71 %'))
    Assert 'ese detalle no sale al imprimir' ($h -match '@media print \{ \.tecnico \{ display: none')
    Assert 'no muestra códigos internos' ($h -notmatch 'HW-SMART')
    Assert 'queda en trabajo.log' ((Get-Content -LiteralPath (Join-Path (Join-Path $x.Exp.Ruta $x.At) 'trabajo.log') -Encoding UTF8 -Raw) -match 'PRE-INFORME')

    '== Con CSV y condiciones: completo'
    New-CsvHwinfo -Ruta "$tmp\antes.csv" -TempBase 92 -Mhz 2600
    Set-CondicionesCalor -Expediente $x.Exp -Atencion $x.At -Momento antes -Valores $cond
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At -Momento antes -Ruta "$tmp\antes.csv"
    Set-Ficha -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At -Valores ([ordered]@{ sintoma = 'Se apaga <jugando> & se calienta'; paquete = 'Mantención'; precio = '30000' })
    Set-Ficha -Expediente (Read-Expediente $x.Exp.Ruta) -Valores @{ 'cliente.nombre' = 'Ana & <b>Pérez</b>'; 'cliente.comuna' = 'Ñuñoa' }
    $r = Export-PreInforme -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At
    $h = Read-Hoja $r.Ruta
    Assert 'ya no falta nada' (@($r.Falta).Count -eq 0 -and $h -notmatch 'Pre-informe parcial')
    Assert 'trae la temperatura del CSV' ($h -match 'temperatura promedio' -and $h -match '94 °C' -and $h -match '96 °C')
    Assert 'trae la velocidad sostenida' ($h -match 'velocidad sostenida' -and $h -match '2,6 GHz')
    Assert 'trae cómo se midió' ($h -match 'OCCT CPU · 10 min · enchufado · 22 °C de ambiente · sobre Mesa')
    Assert 'sugiere limpieza por la temperatura' ($h -match 'limpieza interna')
    Assert 'trae el trabajo y el precio' ($h -match 'Mantención' -and $h -match '\$30\.000')
    $crudo = [IO.File]::ReadAllText($r.Ruta)
    Assert 'escapa lo que escribió el técnico' ($crudo -match 'Ana &amp; &lt;b&gt;P&#233;rez&lt;/b&gt;' -and $crudo -match 'Se apaga &lt;jugando&gt; &amp; se calienta')
    Assert 'el nombre se lee bien' ($h -match 'Ana & <b>Pérez</b>')
    Assert 'no muestra tarjetas sin datos (el CSV no trae GPU)' ($h -notmatch 'GPU, temperatura')
    Assert 'no se comporta como informe final' ($h -notmatch 'Garantía' -and $h -notmatch 'Qué hicimos')

    '== Con un DESPUÉS, sigue mostrando el ANTES'
    Set-DiagnosticoFalso -Exp $x.Exp -At $x.At -Momento despues -Alertas @()
    New-CsvHwinfo -Ruta "$tmp\despues.csv" -TempBase 60 -Mhz 3300
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At -Momento despues -Ruta "$tmp\despues.csv"
    $r = Export-PreInforme -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At
    $h = Read-Hoja $r.Ruta
    Assert 'las temperaturas son las del ANTES' ($h -match '94 °C' -and $h -notmatch '62 °C')
    Assert 'el semáforo es el del ANTES' ($r.Datos.Color -eq 'rojo')

    '== Sin admin avisa; con el final intacto'
    $d = Get-DatosPreInforme -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At
    $d.SinAdmin = $true
    Assert 'la nota aparece sin admin' ((ConvertTo-PreInforme -Datos $d) -match 'sin permisos de administrador')
    $d.SinAdmin = $false
    Assert 'la nota no aparece con admin' ((ConvertTo-PreInforme -Datos $d) -notmatch 'sin permisos de administrador')
    $final = Export-Informes -Expediente (Read-Expediente $x.Exp.Ruta) -Atencion $x.At
    if ($final.Generado) { Assert 'el informe final conserva su estilo' (([IO.File]::ReadAllText($final.Cliente)) -match '@page \{ size: A4') }
    else { Assert 'el informe final conserva su estilo' ((Get-CssCliente) -match '@page \{ size: A4') }

    '== Motivo sin mediciones extra: completo con solo el diagnóstico'
    $y = New-Prueba 'PRE002' 'REVISION'
    Set-DiagnosticoFalso -Exp $y.Exp -At $y.At -Momento antes -Alertas @()
    $r = Export-PreInforme -Expediente (Read-Expediente $y.Exp.Ruta) -Atencion $y.At
    $h = Read-Hoja $r.Ruta
    Assert 'no le falta nada' (@($r.Falta).Count -eq 0)
    Assert 'sin alertas no inventa consejos' ($h -match 'Por ahora, nada urgente')
    Assert 'semáforo verde' ($r.Datos.Color -eq 'verde' -and $h -match 'Tu equipo está en buen estado')

    '== CSV de un Ryzen con reposo antes y después de la prueba'
    $cabeza = 'Date,Time,"Uso total de CPU [%]","Reloj efectivo promedio [MHz]","CPU (Tctl/Tdie) [°C]","Core0 [°C]","Core1 [°C]","Potencia total de CPU [W]","Desaceleración térmica (HTC) [Yes/No]","Desaceleración térmica (PROCHOT CPU) [Yes/No]","Desaceleración térmica (PROCHOT EXT) [Yes/No]"'
    $fila = { param([int]$Seg, [double]$Uso, [int]$Mhz, [int]$Temp, [string]$Htc) '5.11.2026,10:{0}:{1}.000,{2},{3},{4},{5},{6},22.0,{7},No,No' -f [int][math]::Floor($Seg / 60), ($Seg % 60), $Uso.ToString($script:Invariante), $Mhz, $Temp, ($Temp - 1), ($Temp - 2), $Htc }
    $nuevoRyzen = {
        param([string]$Ruta, [string]$Htc = 'No')
        $l = @($cabeza)
        for ($i = 0; $i -lt 150; $i++) { $l += & $fila ($i * 2) 5 400 50 'No' }             # 5 min de reposo
        for ($i = 150; $i -lt 450; $i++) { $l += & $fila ($i * 2) 100 3000 85 $Htc }         # 10 min de OCCT
        for ($i = 450; $i -lt 600; $i++) { $l += & $fila ($i * 2) 5 400 55 'No' }            # 5 min de reposo
        [IO.File]::WriteAllLines($Ruta, $l, (New-Object Text.UTF8Encoding($true)))
    }
    & $nuevoRyzen "$tmp\ryzen.csv"
    $s = Read-SensoresCsv -Ruta "$tmp\ryzen.csv"
    Assert 'reconoce CPU (Tctl/Tdie)' ($s.columnas['cpu_temp_paquete'] -eq 'CPU (Tctl/Tdie) [°C]')
    Assert 'reconoce los núcleos Core0, Core1' ("$($s.columnas['cpu_temp_nucleo_max'])" -match 'Core0')
    Assert 'reconoce HTC y PROCHOT' ("$($s.columnas['cpu_throttling'])" -match 'HTC' -and "$($s.columnas['cpu_throttling'])" -match 'PROCHOT EXT')
    Assert 'encuentra los 10 minutos bajo carga' ([math]::Abs($s.carga.minutos - 10) -le 0.2 -and [math]::Abs($s.carga.inicio_min - 5) -le 0.2) "tramo: $($s.carga | ConvertTo-Json -Compress)"
    Assert 'la duración total sigue siendo la del archivo' ([math]::Abs($s.duracion_min - 20) -le 0.2)
    Assert 'el promedio no se diluye con el reposo' ($s.metricas.cpu_temp_paquete.media -eq 85 -and $s.metricas.cpu_frec_efectiva.media -eq 3000) "media $($s.metricas.cpu_temp_paquete.media), frec $($s.metricas.cpu_frec_efectiva.media)"
    Assert 'sin marcas: no pierde velocidad' ($s.pierde_velocidad.valor -eq $false -and $s.throttling_pct -eq 0)
    & $nuevoRyzen "$tmp\ryzen_htc.csv" 'Yes'
    $s2 = Read-SensoresCsv -Ruta "$tmp\ryzen_htc.csv"
    Assert 'HTC marcado: pierde velocidad' ($s2.pierde_velocidad.valor -eq $true -and $s2.throttling_pct -eq 100)

    '== Sin tramo de carga claro se usa todo el archivo'
    New-CsvHwinfo -Ruta "$tmp\sin_uso.csv" -TempBase 60 -Mhz 2000
    $s3 = Read-SensoresCsv -Ruta "$tmp\sin_uso.csv"
    Assert 'sin columna de uso, no hay tramo' ($null -eq $s3.carga -and $s3.filas -eq 300)
    $l = @($cabeza)
    for ($i = 0; $i -lt 300; $i++) { $l += & $fila ($i * 2) $(if ($i -ge 100 -and $i -lt 130) { 100 } else { 5 }) 1000 60 'No' }   # solo 1 min arriba
    [IO.File]::WriteAllLines("$tmp\pico.csv", $l, (New-Object Text.UTF8Encoding($true)))
    Assert 'un pico corto no cuenta como prueba' ($null -eq (Read-SensoresCsv -Ruta "$tmp\pico.csv").carga)
    $l = @($cabeza)
    for ($i = 0; $i -lt 900; $i++) { $l += & $fila ($i * 2) $(if ($i -ge 300 -and $i -lt 420) { 100 } else { 55 }) 2000 70 'No' }   # juego: 30 min, con 4 min arriba
    [IO.File]::WriteAllLines("$tmp\juego.csv", $l, (New-Object Text.UTF8Encoding($true)))
    Assert 'en un juego, un pico de minutos no reemplaza a la sesión' ($null -eq (Read-SensoresCsv -Ruta "$tmp\juego.csv").carga)

    '== Comparar sin que el reposo invente una mejora'
    $z = New-Prueba 'PRE003'
    Set-DiagnosticoFalso -Exp $z.Exp -At $z.At -Momento antes -Alertas @()
    Set-DiagnosticoFalso -Exp $z.Exp -At $z.At -Momento despues -Alertas @()
    $l = @($cabeza); for ($i = 0; $i -lt 300; $i++) { $l += & $fila ($i * 2) 100 3000 85 'No' }   # el DESPUÉS graba solo la prueba
    [IO.File]::WriteAllLines("$tmp\solo_prueba.csv", $l, (New-Object Text.UTF8Encoding($true)))
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $z.Exp.Ruta) -Atencion $z.At -Momento antes -Ruta "$tmp\ryzen.csv"
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $z.Exp.Ruta) -Atencion $z.At -Momento despues -Ruta "$tmp\solo_prueba.csv"
    $mc = Get-MetricasCalor -Expediente (Read-Expediente $z.Exp.Ruta) -Atencion $z.At
    Assert 'misma carga, misma velocidad: no marca mejora' ($null -eq $mc.Tarjetas[5].Mejoro -and $null -eq $mc.Tarjetas[0].Mejoro) "vel $($mc.Tarjetas[5].Antes) -> $($mc.Tarjetas[5].Despues), temp $($mc.Tarjetas[0].Antes) -> $($mc.Tarjetas[0].Despues)"
    Assert 'no avisa que duran distinto' (@($mc.Advertencias | Where-Object { $_ -like '*duran distinto*' }).Count -eq 0)

    '== Con CSV, muestra la temperatura aunque falte el motivo CALOR'
    $w = New-Prueba 'PRE004' 'REVISION'
    Set-DiagnosticoFalso -Exp $w.Exp -At $w.At -Momento antes -Alertas @()
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $w.Exp.Ruta) -Atencion $w.At -Momento antes -Ruta "$tmp\ryzen.csv"
    $r = Export-PreInforme -Expediente (Read-Expediente $w.Exp.Ruta) -Atencion $w.At
    $h = Read-Hoja $r.Ruta
    Assert 'trae las tarjetas de temperatura' ($h -match 'temperatura promedio' -and $h -match '85 °C')
    Assert 'no exige condiciones si no es CALOR' (@($r.Falta).Count -eq 0)

    '== El diagnóstico suelto no le quita el lugar a la atención del día'
    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Abierta'; Serie = 'PRE005'; SerieOriginal = 'PRE005'; Uuid = $null; PlacaSerie = $null })
    $a1 = New-Atencion -Expediente $e
    Assert 'una sola atención sin motivos: es esa' ((Get-AtencionAbierta -Expediente (Read-Expediente $e.Ruta)) -eq $a1)
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $a1 -Valores ([ordered]@{ motivos = 'CALOR' })
    $a2 = New-Atencion -Expediente (Read-Expediente $e.Ruta)
    Assert 'la suelta del mismo día no gana' ((Get-AtencionAbierta -Expediente (Read-Expediente $e.Ruta)) -eq $a1) "ganó: $(Get-AtencionAbierta -Expediente (Read-Expediente $e.Ruta))"
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $a2 -Valores ([ordered]@{ motivos = 'LENTO' })
    Assert 'si la nueva tiene motivos, gana la nueva' ((Get-AtencionAbierta -Expediente (Read-Expediente $e.Ruta)) -eq $a2)
    $a3 = New-Atencion -Expediente (Read-Expediente $e.Ruta) -Fecha (Get-Date).AddDays(1)
    Assert 'otro día sin motivos: gana la más reciente' ((Get-AtencionAbierta -Expediente (Read-Expediente $e.Ruta)) -eq $a3)
} finally {
    if ($Conservar) { "Carpeta conservada: $tmp" } else { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
