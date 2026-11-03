#Requires -Version 5.1
# Prueba de desarrollo de la velocidad sostenida en CALOR, con CSV sintéticos en la carpeta temporal.
# El caso que importa: la CPU llega a su límite de temperatura antes y después de la mantención, así
# que los grados no cambian, pero sostiene más velocidad. -Conservar deja el informe generado.
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
$tmp = Join-Path $env:TEMP ('kit_prueba_vel_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$script:Ctx.CarpetaClientes = Join-Path $tmp 'clientes'

function New-CsvHwinfo {
    # 10 minutos de HWiNFO en inglés, una fila cada 2 s.
    param([string]$Ruta, [int]$TempBase, [int]$Mhz)
    $l = @('Date,Time,"CPU Package [°C]","Average Effective Clock [MHz]","Package/Ring Thermal Throttling [Yes/No]"')
    for ($i = 0; $i -lt 300; $i++) { $l += ('2.11.2026,10:{0}:{1}.000,{2}.0,{3}.0,Yes' -f [int][math]::Floor($i * 2 / 60), (($i * 2) % 60), ($TempBase + ($i % 5)), ($Mhz + ($i % 40))) }
    [IO.File]::WriteAllLines($Ruta, $l, (New-Object Text.UTF8Encoding($true)))
}
function New-AtencionPrueba {
    param([string]$Serie, [int]$TempAntes, [int]$MhzAntes, [int]$TempDespues, [int]$MhzDespues)
    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Velocidad'; Serie = $Serie; SerieOriginal = $Serie; Uuid = $null; PlacaSerie = $null })
    $a = New-Atencion -Expediente $e
    Set-Ficha -Expediente $e -Valores @{ 'cliente.nombre' = 'Cliente de prueba'; 'cliente.contacto' = '+56 9 1111 2222' }
    Set-Ficha -Expediente $e -Atencion $a -Valores ([ordered]@{ motivos = 'CALOR'; sintoma = 'Se calienta'; paquete = 'Mantención'; precio = '30000'; 'checklist_fisico.limpieza' = 's'; 'checklist_fisico.pasta' = 'Pasta de prueba' })
    $cond = [ordered]@{ enchufado = 's'; plan = 'Equilibrado'; ventiladores = 'Auto'; superficie = 'Mesa'; temp_ambiente_c = '22'; carga_tipo = 'OCCT CPU'; carga_duracion_min = '10' }
    Set-CondicionesCalor -Expediente $e -Atencion $a -Momento antes -Valores $cond
    Set-CondicionesCalor -Expediente $e -Atencion $a -Momento despues -Valores $cond
    New-CsvHwinfo -Ruta "$tmp\$Serie-antes.csv" -TempBase $TempAntes -Mhz $MhzAntes
    New-CsvHwinfo -Ruta "$tmp\$Serie-despues.csv" -TempBase $TempDespues -Mhz $MhzDespues
    $null = Import-SensoresMedicion -Expediente $e -Atencion $a -Momento antes -Ruta "$tmp\$Serie-antes.csv"
    $null = Import-SensoresMedicion -Expediente $e -Atencion $a -Momento despues -Ruta "$tmp\$Serie-despues.csv"
    [pscustomobject]@{ Exp = Read-Expediente $e.Ruta; At = $a }
}

'== Misma temperatura, más velocidad (2,6 -> 3,3 GHz)'
$x = New-AtencionPrueba -Serie 'VEL001' -TempAntes 96 -MhzAntes 2600 -TempDespues 96 -MhzDespues 3300
$m = Get-MetricasCalor -Expediente $x.Exp -Atencion $x.At
$v = $m.Tarjetas[5]
"     velocidad: $($v.Antes) -> $($v.Despues) GHz | mejoró: $($v.Mejoro)"
Assert 'la velocidad sube y cuenta como mejora' ($v.Antes -eq 2.6 -and $v.Despues -eq 3.3 -and $v.Mejoro -eq $true)
Assert 'la máxima no cambia' ($null -eq $m.Tarjetas[1].Mejoro)
Assert 'sin aviso de carga distinta' (@($m.Advertencias | Where-Object { $_ -like '*trabajó mucho menos*' }).Count -eq 0)
$d = Get-DatosInforme -Expediente $x.Exp -Atencion $x.At
"     frase: $($d.Frase)"
Assert 'la frase dice que rinde más' ($d.Frase -like '*rinde más con una temperatura similar*')
$r = Export-Informes -Expediente $x.Exp -Atencion $x.At
$h = [IO.File]::ReadAllText($r.Cliente)
Assert 'el informe del cliente trae la velocidad en GHz' ($h -match 'velocidad sostenida' -and $h -match '3,3 GHz' -and $h -match '2,6 GHz')
Assert 'al cliente no se le muestran tarjetas sin datos (el CSV no trae GPU)' ($h -notmatch 'GPU, temperatura')
$tec = [IO.File]::ReadAllText($r.Tecnico)
Assert 'el técnico sí ve la tarjeta sin datos' ($tec -match 'GPU, temperatura')

'== Sí / No: si no cambió, no mejoró ni empeoró'
$sn = { param($a, $d) (Get-TarjetaMetrica -Titulo 'x' -Antes $a -Despues $d -Unidad '' -Mejor si_no).Mejoro }
Assert 'Sí -> No mejora' ((& $sn $true $false) -eq $true)
Assert 'No -> Sí empeora' ((& $sn $false $true) -eq $false)
Assert 'Sí -> Sí sin color' ($null -eq (& $sn $true $true))
Assert 'No -> No sin color' ($null -eq (& $sn $false $false))
Assert 'sin dato, sin color' ($null -eq (& $sn $null $false))

'== Temperatura igual y velocidad casi igual (ruido): no es mejora'
$x2 = New-AtencionPrueba -Serie 'VEL002' -TempAntes 96 -MhzAntes 3300 -TempDespues 96 -MhzDespues 3310
$m2 = Get-MetricasCalor -Expediente $x2.Exp -Atencion $x2.At
Assert 'la diferencia de 10 MHz no cuenta' ($null -eq $m2.Tarjetas[5].Mejoro) "$($m2.Tarjetas[5].Antes) -> $($m2.Tarjetas[5].Despues)"
$d2 = Get-DatosInforme -Expediente $x2.Exp -Atencion $x2.At
Assert 'la frase no inventa una mejora' ($d2.Frase -like '*sigue calentándose*') $d2.Frase

'== Más fresco y misma velocidad: manda la temperatura'
$x3 = New-AtencionPrueba -Serie 'VEL003' -TempAntes 96 -MhzAntes 3300 -TempDespues 91 -MhzDespues 3300
$d3 = Get-DatosInforme -Expediente $x3.Exp -Atencion $x3.At
Assert 'la frase habla de temperatura' ($d3.Frase -like '*más fresco*') $d3.Frase

'== Más velocidad pero bastante más caliente: no dice "temperatura similar"'
$x4 = New-AtencionPrueba -Serie 'VEL004' -TempAntes 90 -MhzAntes 2600 -TempDespues 96 -MhzDespues 3300
$d4 = Get-DatosInforme -Expediente $x4.Exp -Atencion $x4.At
Assert 'la frase no dice que rinde más con temperatura similar' ($d4.Frase -notlike '*temperatura similar*') $d4.Frase

'== CSV sin el sensor de velocidad: sin tarjeta y sin error'
$x5 = New-AtencionPrueba -Serie 'VEL005' -TempAntes 96 -MhzAntes 3000 -TempDespues 90 -MhzDespues 3000
foreach ($mo in 'antes', 'despues') {
    $j = Join-Path (Join-Path (Join-Path $x5.Exp.Ruta $x5.At) $mo) 'sensores_resumen.json'
    $o = Read-JsonKit $j
    $o.metricas.PSObject.Properties.Remove('cpu_frec_efectiva')
    [IO.File]::WriteAllText($j, ($o | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}
$m5 = Get-MetricasCalor -Expediente $x5.Exp -Atencion $x5.At
Assert 'quedan las 5 tarjetas de antes' (@($m5.Tarjetas).Count -eq 5)
Assert 'la pantalla del cliente usa la GPU en su lugar' ($m5.Pantalla[2].Titulo -eq 'GPU, temperatura promedio')

''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($Conservar) { "Expediente conservado: $($x.Exp.Ruta)" } else { [IO.Directory]::Delete($tmp, $true) }
exit $script:fallas
