#Requires -Version 5.1
<#
.SYNOPSIS
    Fase H: CSV de sensores detectado solo, prueba fija de OCCT, PDF con Edge, mensaje para WhatsApp y
    paquete de soporte.
.DESCRIPTION
    Todo con datos sintéticos en una carpeta temporal que se borra al terminar. La configuración de OCCT es
    un archivo falso con la misma forma que el de OCCT 17; no abre OCCT. El PDF usa el Edge de este equipo.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe', 'Herramientas', 'Soporte') { . (Join-Path $scripts "lib\$lib.ps1") }
foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $scripts "motivos\$m.ps1") }
. (Join-Path $PSScriptRoot '_datos_ejemplo.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:Ctx.Config.tecnico.nombre = 'Técnico de prueba'
$script:Ctx.Config.tecnico.contacto = 'contacto de prueba'
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_H_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$script:Ctx.CarpetaClientes = Join-Path $tmp 'clientes'
$utf8 = New-Object Text.UTF8Encoding($false)

function Write-CsvHwinfo {
    param([string]$Ruta, [int]$Temp)
    $l = @('Date,Time,"CPU Package [°C]","Average Effective Clock [MHz]","Total CPU Usage [%]"')
    for ($i = 0; $i -lt 300; $i++) { $l += ('8.11.2026,10:{0}:{1}.000,{2}.0,3000.0,100.0' -f [int][math]::Floor($i * 2 / 60), (($i * 2) % 60), ($Temp + ($i % 3))) }
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Ruta))
    [IO.File]::WriteAllLines($Ruta, $l, (New-Object Text.UTF8Encoding($true)))
}
function Write-Diagnostico {
    param($Exp, [string]$At, [string]$Momento)
    $dir = Join-Path (Join-Path $Exp.Ruta $At) $Momento
    $null = New-Item -ItemType Directory -Force $dir
    $alertas = @([ordered]@{ Severidad = 'CRITICO'; Codigo = 'HW-SMART-AVISO'; Texto = 'Disco 0 con sectores reasignados' })
    $json = [ordered]@{ kit = @{ generado = '2026-11-08 10:00:00'; admin = @{ Elevado = $true }; parametros = @{ Momento = $Momento } }; alertas = $alertas; datos = @{ equipo = @{ TieneBateria = $true } } } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $dir 'diagnostico.json'), $json, $utf8)
    [IO.File]::WriteAllText((Join-Path $dir 'log.txt'), "INFO inicio`r`nINFO cliente visto: Cliente Prueba H, +56 9 5555 0009, Ñuñoa`r`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $dir 'discos.txt'), 'Serial Number : SERIEFALSA123', $utf8)
    [IO.File]::WriteAllText((Join-Path $dir '06_programas.csv'), 'nombre;version', $utf8)
}
$cond = [ordered]@{ enchufado = 's'; plan = 'Equilibrado'; ventiladores = 'Auto'; superficie = 'Mesa'; temp_ambiente_c = '22'; carga_tipo = 'OCCT CPU'; carga_duracion_min = '10' }

try {
    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Fase H'; Serie = 'FASEH001'; SerieOriginal = 'FASEH001'; Uuid = $null; PlacaSerie = $null })
    $at = New-Atencion -Expediente $e
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Valores @{ 'cliente.nombre' = 'Cliente Prueba H'; 'cliente.contacto' = '+56 9 5555 0009'; 'cliente.comuna' = 'Ñuñoa' }
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Valores ([ordered]@{ motivos = 'CALOR'; sintoma = 'Se calienta'; paquete = 'Mantención por temperatura'; precio = '35000' })
    $exp = { Read-Expediente $e.Ruta }

    '== CSV de sensores detectado solo'
    $raiz = Join-Path $tmp 'usb'; $docs = Join-Path $tmp 'docs'; $esc = Join-Path $tmp 'escritorio'
    $carpetas = [ordered]@{ 'la raíz del pendrive' = $raiz; 'Documentos' = $docs; 'el Escritorio' = $esc; 'Descargas' = (Join-Path $tmp 'no_existe') }
    Write-CsvHwinfo "$raiz\antes.CSV" 90
    Write-CsvHwinfo "$docs\viejo.CSV" 80
    [IO.File]::SetLastWriteTime("$docs\viejo.CSV", (Get-Date).AddDays(-3))
    $null = [IO.Directory]::CreateDirectory($esc)
    [IO.File]::WriteAllText("$esc\duplicados_reporte.csv", "grupo;tamano_MB;copias;sugerencia;ruta`r`n" + ('1;2;3;mover;C:\x' * 30), $utf8)
    [IO.File]::WriteAllText("$docs\lhm.csv", (',"/intelcpu/0/temperature/0"' + "`r`n" + '"Time","CPU Package"' + "`r`n" + ('"11/08/2026 10:00:00","70"' + "`r`n") * 20), $utf8)
    [IO.File]::SetLastWriteTime("$docs\lhm.csv", (Get-Date).AddMinutes(-30))
    [IO.File]::SetLastWriteTime("$raiz\antes.CSV", (Get-Date).AddMinutes(-2))
    $c = @(Find-CsvSensores -Expediente (& $exp) -Atencion $at -Momento antes -Carpetas $carpetas)
    Assert 'encuentra los CSV de sensores de hoy, el más nuevo primero' ($c.Count -eq 2 -and $c[0].Nombre -eq 'antes.CSV' -and $c[0].Formato -eq 'HWiNFO' -and $c[1].Formato -eq 'LibreHardwareMonitor') -D "encontró: $(($c | ForEach-Object { $_.Nombre }) -join ', ')"
    Assert 'ignora los de días anteriores y los CSV que no son de sensores' (-not ($c | Where-Object { $_.Nombre -in 'viejo.CSV', 'duplicados_reporte.csv' }))
    Assert 'dice dónde lo encontró' ($c[0].Donde -eq 'la raíz del pendrive' -and -not $c[0].EnCurso)
    $c2 = @(Find-CsvSensores -Expediente (& $exp) -Atencion $at -Momento antes -Carpetas $carpetas -Ahora ([IO.File]::GetLastWriteTime("$raiz\antes.CSV").AddSeconds(5)))
    Assert 'si cambió hace segundos, avisa que HWiNFO sigue grabando' ($c2[0].EnCurso)
    Assert 'sin ANTES importado, no busca el DESPUÉS' (@(Find-CsvSensores -Expediente (& $exp) -Atencion $at -Momento despues -Carpetas $carpetas).Count -eq 0)
    Write-Diagnostico -Exp (& $exp) -At $at -Momento 'antes'
    $null = Import-SensoresMedicion -Expediente (& $exp) -Atencion $at -Momento antes -Ruta "$raiz\antes.CSV"
    Assert 'con el ANTES importado, ya no lo ofrece' (@(Find-CsvSensores -Expediente (& $exp) -Atencion $at -Momento antes -Carpetas $carpetas).Count -eq 0)
    $d = @(Find-CsvSensores -Expediente (& $exp) -Atencion $at -Momento despues -Carpetas $carpetas)
    Assert 'para el DESPUÉS no ofrece el mismo CSV del ANTES ni los anteriores' ($d.Count -eq 0) -D "ofreció: $(($d | ForEach-Object { $_.Nombre }) -join ', ')"
    Assert 'saca el original idéntico al importado' ((Remove-CsvSensoresOrigen -Expediente (& $exp) -Atencion $at -Momento antes -Ruta "$raiz\antes.CSV") -and -not (Test-Path "$raiz\antes.CSV"))
    Assert 'queda anotado en trabajo.log' ([IO.File]::ReadAllText((Join-Path (Join-Path $e.Ruta $at) 'trabajo.log')) -match 'CSV original antes\.CSV sacado del equipo')
    Start-Sleep -Milliseconds 1100
    Write-CsvHwinfo "$esc\despues.CSV" 70
    $d = @(Find-CsvSensores -Expediente (& $exp) -Atencion $at -Momento despues -Carpetas $carpetas)
    Assert 'para el DESPUÉS ofrece el nuevo' ($d.Count -eq 1 -and $d[0].Nombre -eq 'despues.CSV' -and $d[0].Donde -eq 'el Escritorio')
    Write-Diagnostico -Exp (& $exp) -At $at -Momento 'despues'
    $null = Import-SensoresMedicion -Expediente (& $exp) -Atencion $at -Momento despues -Ruta "$esc\despues.CSV"
    Add-Content -LiteralPath "$esc\despues.CSV" -Value 'fila nueva'
    $error1 = $null; try { $null = Remove-CsvSensoresOrigen -Expediente (& $exp) -Atencion $at -Momento despues -Ruta "$esc\despues.CSV" } catch { $error1 = $_.Exception.Message }
    Assert 'no saca un CSV que cambió después de importarlo' ($error1 -match 'cambió' -and (Test-Path "$esc\despues.CSV"))

    '== CSV de otro equipo'
    $e2 = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Nitro AN515-43'; Serie = 'FASEH002'; SerieOriginal = 'FASEH002'; Uuid = $null; PlacaSerie = $null })
    $x2 = Read-Expediente $e2.Ruta; $x2.Ficha['equipo']['cpu'] = 'AMD Ryzen 5 3550H with Radeon Vega Mobile Gfx'; Save-Ficha -Expediente $x2
    $at2 = New-Atencion -Expediente (Read-Expediente $e2.Ruta)
    Set-Ficha -Expediente (Read-Expediente $e2.Ruta) -Atencion $at2 -Valores ([ordered]@{ motivos = 'CALOR'; sintoma = 'Se calienta'; paquete = 'Mantención'; precio = '20000' })
    $exp2 = { Read-Expediente $e2.Ruta }
    $dirEq = Join-Path $tmp 'equipos'
    Write-CsvHwinfoEs -Ruta "$dirEq\propio.CSV" -Sistema 'Acer Nitro AN515-43' -Cpu 'AMD Ryzen 5 3550H' -Minutos 1
    Write-CsvHwinfoEs -Ruta "$dirEq\sin_bom.CSV" -Sistema 'Acer Nitro AN515-43' -Cpu 'AMD Ryzen 5 3550H' -Minutos 1 -SinBom
    Write-CsvHwinfoEs -Ruta "$dirEq\dell.CSV" -Sistema 'DELL Inspiron 3493' -Cpu 'Intel Core i3-1005G1' -Minutos 1
    Write-CsvHwinfoEs -Ruta "$dirEq\misma_cpu.CSV" -Sistema 'HP Laptop 15-db1xxx' -Cpu 'AMD Ryzen 5 3550H' -Minutos 1
    Write-CsvHwinfo "$dirEq\grabando.CSV" 80
    $minutos = @{ 'grabando.CSV' = -6; 'sin_bom.CSV' = -5; 'propio.CSV' = -4; 'misma_cpu.CSV' = -2; 'dell.CSV' = -1 }
    foreach ($n in $minutos.Keys) { [IO.File]::SetLastWriteTime("$dirEq\$n", (Get-Date).AddMinutes($minutos[$n])) }
    $g = Get-EquipoCsvSensores -Ruta "$dirEq\dell.CSV"
    Assert 'lee el equipo y la CPU de la fila de grupos de HWiNFO' ($g.Sistema -eq 'DELL Inspiron 3493' -and $g.Cpu -eq 'Intel Core i3-1005G1') -D "$($g.Sistema) | $($g.Cpu)"
    Assert 'sin fila de grupos (HWiNFO grabando, LibreHardwareMonitor) no dice nada' ($null -eq (Get-EquipoCsvSensores -Ruta "$dirEq\grabando.CSV") -and $null -eq (Get-EquipoCsvSensores -Ruta "$docs\lhm.csv") -and $null -eq (Test-EquipoCsvSensores -Expediente (& $exp2) -Ruta "$dirEq\grabando.CSV").Coincide)
    Assert 'el del mismo equipo coincide, aunque HWiNFO y Windows escriban distinto la CPU' ((Test-EquipoCsvSensores -Expediente (& $exp2) -Ruta "$dirEq\propio.CSV").Coincide -eq $true -and (Test-EquipoCsvSensores -Expediente (& $exp2) -Ruta "$dirEq\sin_bom.CSV").Coincide -eq $true)
    $t = Test-EquipoCsvSensores -Expediente (& $exp2) -Ruta "$dirEq\dell.CSV"
    Assert 'el de otro equipo no coincide y dice de cuál es' ($t.Coincide -eq $false -and $t.Texto -eq 'DELL Inspiron 3493 (Intel Core i3-1005G1)') -D $t.Texto
    Assert 'la misma CPU en otro modelo tampoco coincide' ((Test-EquipoCsvSensores -Expediente (& $exp2) -Ruta "$dirEq\misma_cpu.CSV").Coincide -eq $false)
    $lenovo = [pscustomobject]@{ Ficha = @{ equipo = @{ fabricante = 'Lenovo'; modelo = 'IdeaPad 3 15ITL6'; cpu = '11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz' } } }
    Write-CsvHwinfoEs -Ruta "$tmp\lenovo\l.CSV" -Sistema 'LENOVO 82H8' -Cpu 'Intel Core i5-1135G7' -Minutos 1
    Write-CsvHwinfoEs -Ruta "$tmp\lenovo\otra.CSV" -Sistema 'LENOVO 82H8' -Cpu 'Intel Core i7-1165G7' -Minutos 1
    Assert 'en Lenovo compara solo la CPU (el modelo de la ficha es el nombre comercial)' ((Test-EquipoCsvSensores -Expediente $lenovo -Ruta "$tmp\lenovo\l.CSV").Coincide -eq $true -and (Test-EquipoCsvSensores -Expediente $lenovo -Ruta "$tmp\lenovo\otra.CSV").Coincide -eq $false)
    $cols = 3000
    $largo = @(('Date,Time,' + ((1..$cols | ForEach-Object { '"Sensor ' + $_ + ' [°C]"' }) -join ',')), ('8.11.2026,10:0:0.000,' + ((1..$cols | ForEach-Object { '50.0' }) -join ',')))
    $largo += $largo[0]
    $largo += ',,Sistema: Acer Nitro AN515-43,CPU [#0]: AMD Ryzen 5 3550H,' + ((1..$cols | ForEach-Object { 'CPU [#0]: AMD Ryzen 5 3550H: Enhanced' }) -join ',')
    $null = [IO.Directory]::CreateDirectory("$tmp\grande"); [IO.File]::WriteAllLines("$tmp\grande\largo.CSV", $largo, (New-Object Text.UTF8Encoding($true)))
    $gl = Get-EquipoCsvSensores -Ruta "$tmp\grande\largo.CSV"
    Assert 'una fila de grupos de más de 64 KB también se lee' ($largo[-1].Length -gt 65536 -and $gl.Sistema -eq 'Acer Nitro AN515-43' -and $gl.Cpu -eq 'AMD Ryzen 5 3550H') -D "$($largo[-1].Length) bytes: $($gl.Sistema)"
    $c = @(Find-CsvSensores -Expediente (& $exp2) -Atencion $at2 -Momento antes -Carpetas @{ 'la raíz del pendrive' = $dirEq } -Ahora (Get-Date).AddMinutes(10))
    $orden = ($c | ForEach-Object { "$($_.Nombre)$(if ($_.OtroEquipo) { '*' })" }) -join ', '
    Assert 'ofrece primero los de este equipo y deja al final, marcados, los de otro' ($orden -eq 'propio.CSV, sin_bom.CSV, grabando.CSV, dell.CSV*, misma_cpu.CSV*' -and $c[3].Equipo -eq 'DELL Inspiron 3493 (Intel Core i3-1005G1)') -D $orden
    $null = Import-SensoresMedicion -Expediente (& $exp2) -Atencion $at2 -Momento antes -Ruta "$dirEq\propio.CSV"
    $null = Import-SensoresMedicion -Expediente (& $exp2) -Atencion $at2 -Momento despues -Ruta "$dirEq\dell.CSV"
    $log2 = @([IO.File]::ReadAllLines((Join-Path (Join-Path $e2.Ruta $at2) 'trabajo.log')))
    Assert 'importar uno de otro equipo queda anotado en trabajo.log; el propio no' ($log2[-1] -match 'DESPUES.*ojo: el CSV dice que es de DELL Inspiron 3493 \(Intel Core i3-1005G1\)' -and $log2[-2] -match 'ANTES \| sensores importados' -and $log2[-2] -notmatch 'ojo') -D ($log2[-2..-1] -join ' // ')
    $resumen2 = [IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $e2.Ruta $at2) 'despues') 'sensores_resumen.json'))
    Assert 'las series de los discos de la fila de grupos no quedan en el resumen ni en el log' ($resumen2 -notmatch 'EJEMPLO-0001' -and ($log2 -join "`n") -notmatch 'EJEMPLO-0001')

    '== Prueba fija de OCCT'
    $occt = Join-Path $tmp 'herramientas\OCCT'
    $null = [IO.Directory]::CreateDirectory($occt)
    [IO.File]::WriteAllBytes("$occt\OCCT.exe", [byte[]](0x4D, 0x5A))
    $falsa = [ordered]@{
        Version = 1210; EulaVersion = 20240402; SaveReportPath = 'C:\Users\alguien\Documents'; SaveScreenshotPath = 'C:\Users\alguien\Documents'; MotherboardName = 'PLACA X'
        FontSizeOffset = 0.0; AllowOcbaseUpload = $true; EnabledFanSensors = @()
        StabilitySchedule = [ordered]@{ ScheduleType = 'Stability'; Periods = @([ordered]@{ Duration = '01:00:00'; IsInfinite = $true; TestType = 'CpuOcct'
                    CpuOnlyOcctConfig = [ordered]@{ DataSet = 'Small'; OcctInstructionSet = 'Avx2'; LoadType = 'Variable'; Mode = 'Extreme'; Threads = 'Fixed'; StartAtCycle = 3 }
                    CpuOcctConfig = [ordered]@{ LoadType = 'Variable' } }) }
    }
    [IO.File]::WriteAllText("$occt\OCCT.config.json", ($falsa | ConvertTo-Json -Depth 10), $utf8)
    $base = Join-Path $scripts 'config\occt_prueba.json'
    $o = @(Get-OpcionesHerramientas -Carpeta (Join-Path $tmp 'herramientas') | Where-Object { $_.Nombre -eq 'OCCT' })[0]
    Assert 'la opción de OCCT trae su prueba fija' ($o.ConfigBase -and [IO.File]::Exists($o.ConfigBase))
    $hashAntes = (Get-FileHash "$occt\OCCT.config.json").Hash
    $null = Set-ConfigOcct -Carpeta $occt -Base $base -WhatIf
    Assert 'con -WhatIf no cambia nada' ((Get-FileHash "$occt\OCCT.config.json").Hash -eq $hashAntes)
    $r = Set-ConfigOcct -Carpeta $occt -Base $base
    $j = [IO.File]::ReadAllText("$occt\OCCT.config.json") | ConvertFrom-Json
    $p = $j.StabilitySchedule.Periods[0]
    Assert 'fija CPU, 10 min, Normal, Steady' ($r.Estado -eq 'ok' -and $p.TestType -eq 'CpuOnlyOcct' -and $p.Duration -eq '00:10:00' -and $p.IsInfinite -eq $false -and $p.CpuOnlyOcctConfig.Mode -eq 'Normal' -and $p.CpuOnlyOcctConfig.LoadType -eq 'Steady' -and $p.CpuOnlyOcctConfig.StartAtCycle -eq 1 -and $p.CpuOnlyOcctConfig.Threads -eq 'Auto')
    Assert 'quita los datos del último equipo y apaga el envío a internet' (-not $j.PSObject.Properties['SaveReportPath'] -and -not $j.PSObject.Properties['MotherboardName'] -and $j.AllowOcbaseUpload -eq $false)
    Assert 'no toca la licencia ni lo demás' ($j.EulaVersion -eq 20240402 -and $j.Version -eq 1210 -and $p.CpuOcctConfig.LoadType -eq 'Variable' -and @($j.EnabledFanSensors).Count -eq 0)
    $bak = [IO.File]::ReadAllText("$occt\OCCT.config.json.bak")
    Assert 'deja la prueba anterior en .bak, sin los datos del equipo' ($bak -match '01:00:00' -and $bak -notmatch 'alguien|PLACA X')
    $h1 = (Get-FileHash "$occt\OCCT.config.json").Hash
    $r2 = Set-ConfigOcct -Carpeta $occt -Base $base
    Assert 'la segunda vez no reescribe nada' ($r2.Cambios -eq 0 -and (Get-FileHash "$occt\OCCT.config.json").Hash -eq $h1)
    $sin = [ordered]@{ Version = 1300; StabilitySchedule = [ordered]@{ Periods = @([ordered]@{ Duration = '00:30:00'; TestType = 'Cpu'; IsInfinite = $false }) } }
    [IO.File]::WriteAllText("$occt\OCCT.config.json", ($sin | ConvertTo-Json -Depth 10), $utf8)
    $r3 = Set-ConfigOcct -Carpeta $occt -Base $base
    $j3 = [IO.File]::ReadAllText("$occt\OCCT.config.json") | ConvertFrom-Json
    Assert 'con otro formato no inventa campos y dice cuáles faltan' ($r3.Estado -eq 'parcial' -and @($r3.NoEncontrados | Where-Object { $_ -like '*CpuOnlyOcctConfig*' }).Count -eq 6 -and -not $j3.StabilitySchedule.Periods[0].PSObject.Properties['CpuOnlyOcctConfig'] -and $j3.StabilitySchedule.Periods[0].Duration -eq '00:10:00')
    Remove-Item "$occt\OCCT.config.json*"
    Assert 'sin configuración (primera vez) no crea nada' ((Set-ConfigOcct -Carpeta $occt -Base $base).Estado -eq 'sin_config' -and -not (Test-Path "$occt\OCCT.config.json"))
    $nota = Start-Herramienta -Opcion $o -WhatIf
    Assert 'el botón avisa que la primera vez se elige a mano' ($nota -match 'Primera vez')

    '== PDF con Edge'
    $edge = Find-Edge
    Assert 'encuentra Edge' ($edge -and [IO.File]::Exists($edge)) -D "Edge: $edge"
    Set-CondicionesCalor -Expediente (& $exp) -Atencion $at -Momento antes -Valores $cond
    $pre = Export-PreInforme -Expediente (& $exp) -Atencion $at
    $pdf = Export-PdfInforme -Html $pre.Ruta
    $bytes = [IO.File]::ReadAllBytes($pdf)
    $texto = [Text.Encoding]::ASCII.GetString($bytes)
    $paginas = ([regex]::Matches($texto, '/Type\s*/Page[^s]')).Count
    Assert 'deja pre_informe.pdf junto al HTML' ($pdf -eq [IO.Path]::ChangeExtension($pre.Ruta, '.pdf') -and $texto.StartsWith('%PDF'))
    Assert 'el pre-informe cabe en una página' ($paginas -eq 1) -D "páginas: $paginas"
    Assert 'no deja el perfil temporal de Edge' (@(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'kit_pdf_*').Count -eq 0)
    Assert 'no deja Edge corriendo' (@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -match 'kit_pdf_' }).Count -eq 0)
    $bloqueo = [IO.File]::Open($pdf, 'Open', 'Read', 'None')
    $error2 = $null; try { $null = Export-PdfInforme -Html $pre.Ruta } catch { $error2 = $_.Exception.Message } finally { $bloqueo.Dispose() }
    Assert 'si el PDF está abierto, lo dice' ($error2 -match 'ciérralo') -D "mensaje: $error2"
    $error3 = $null; try { $null = Export-PdfInforme -Html (Join-Path $tmp 'no_existe.html') } catch { $error3 = $_.Exception.Message }
    Assert 'sin HTML, pide generarlo' ($error3 -match 'genéralo')

    '== Mensaje para WhatsApp'
    $m = Get-MensajeWhatsApp -Expediente (& $exp) -Atencion $at -Tipo pre
    Assert 'pre: saluda por el nombre y nombra el equipo' ($m -match '^Hola Cliente, ya revisé tu Prueba Fase H\.') -D "mensaje: $m"
    Assert 'pre: estado, alerta, temperatura y propuesta con precio' ($m -match 'necesita atención' -and $m -match '• Discos' -and $m -match '9\d °C' -and $m -match 'Te propongo: Mantención por temperatura, \$35\.000\.') -D "mensaje: $m"
    Assert 'pre: firma el técnico y no lleva serie ni contacto' ($m -match 'Técnico de prueba\s*$' -and $m -notmatch 'FASEH001|5555')
    Set-CondicionesCalor -Expediente (& $exp) -Atencion $at -Momento despues -Valores $cond
    $f = Get-MensajeWhatsApp -Expediente (& $exp) -Atencion $at -Tipo final
    Assert 'final: listo, antes → después y garantía' ($f -match 'ya está listo' -and $f -match '• CPU, temperatura promedio: 9\d °C → 7\d °C' -and $f -match 'Garantía hasta el \d{2}-\d{2}-\d{4}\.') -D "mensaje: $f"
    Assert 'final: sin serie ni contacto' ($f -notmatch 'FASEH001|5555')

    '== Paquete de soporte'
    $at2 = New-Atencion -Expediente (& $exp)
    $zip = Export-PaqueteSoporte -Expediente (& $exp) -Atencion $at -Destino (Join-Path $tmp 'soporte')
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $nombres = @($z.Entries | ForEach-Object { $_.FullName })
        $todo = ($z.Entries | ForEach-Object { $s = New-Object IO.StreamReader($_.Open(), [Text.Encoding]::UTF8); try { $s.ReadToEnd() } finally { $s.Dispose() } }) -join "`n"
        $fichaZip = (New-Object IO.StreamReader(($z.Entries | Where-Object { $_.FullName -eq 'ficha.json' }).Open())).ReadToEnd() | ConvertFrom-Json
    } finally { $z.Dispose() }
    Assert 'queda en la carpeta de soporte con el modelo en el nombre' ((Split-Path -Leaf $zip) -match '^soporte_Prueba-Fase-H_\d{8}_\d{6}\.zip$')
    $faltan = @(@('LEEME.txt', 'ficha.json', "$at/trabajo.log", "$at/archivos.txt", "$at/antes/log.txt", "$at/antes/alertas.json", "$at/despues/sensores_resumen.json") | Where-Object { $nombres -notcontains $_ })
    Assert 'lleva LEEME, ficha, trabajo.log, lista de archivos, log y alertas, de todas las atenciones' ($faltan.Count -eq 0 -and @($nombres -match "^$at2/").Count -ge 1) -D "faltan: $($faltan -join ', ') | entradas: $($nombres -join ', ')"
    Assert 'no lleva CSV, discos.txt, informes ni fotos' (-not ($nombres | Where-Object { $_ -match '\.(csv|html|pdf|jpg|png)$|discos\.txt' }))
    Assert 'no lleva el nombre, el contacto ni la comuna del cliente' ($todo -notmatch 'Cliente Prueba H|5555 0009|Ñuñoa' -and $todo -match '<NOMBRE>|<CONTACTO>' -and $fichaZip.cliente.nombre -eq '<NOMBRE>')
    Assert 'la lista de archivos sí muestra que existen' ($todo -match 'antes\\discos\.txt' -and $todo -match 'pre_informe\.pdf')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
