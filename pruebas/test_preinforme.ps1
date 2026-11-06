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
} finally {
    if ($Conservar) { "Carpeta conservada: $tmp" } else { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
