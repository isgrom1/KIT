# Pruebas de desarrollo de la Fase B: CALOR, LENTO y REVISION (no es parte del kit).
# CALOR usa CSV de ejemplo (_datos_ejemplo.ps1). La parte sobre la medición real del Nitro solo corre en su PC. Lo que se escribe en su registro (HKCU) son valores de prueba
# que esta misma prueba crea y borra.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores') { . (Join-Path $scripts "lib\$lib.ps1") }
foreach ($m in 'calor', 'lento', 'revision') { . (Join-Path $scripts "motivos\$m.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N $D" } }
$clientesReales = $script:Ctx.CarpetaClientes
$tmp = Join-Path $env:TEMP ('kit_prueba_B_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$script:Ctx.CarpetaClientes = $tmp
$null = New-Item -ItemType Directory $tmp
. (Join-Path $PSScriptRoot '_datos_ejemplo.ps1')
# ANTES caliente (91,1 °C, 1,9 GHz, 20 % con desaceleración); DESPUÉS en reposo (35,2 °C, 0,4 GHz).
$antesCsv = Join-Path $tmp 'antes_ejemplo.csv'
$despuesCsv = Join-Path $tmp 'despues_ejemplo.csv'
Write-CsvHwinfoEs -Ruta $antesCsv -Temp 91.1 -Mhz 1900 -PctDesaceleracion 20 -Uso 100
Write-CsvHwinfoEs -Ruta $despuesCsv -Temp 35.2 -Mhz 400 -PctDesaceleracion 0 -Uso 5

'== CALOR'
$exp = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Prueba Calor'; Serie = 'CALOR001'; SerieOriginal = 'CALOR001'; Uuid = $null; PlacaSerie = $null })
$at = New-Atencion -Expediente $exp
try { $null = Import-SensoresMedicion -Expediente $exp -Atencion $at -Momento despues -Ruta $despuesCsv; Assert 'después sin antes' $false } catch { Assert 'no se importa DESPUÉS sin ANTES' ($_.Exception.Message -match 'sin "antes"') }
try { Set-CondicionesCalor -Expediente $exp -Atencion $at -Momento antes -Valores @{ temp_ambiente_c = '80' }; Assert 'ambiente 80' $false } catch { Assert 'condición inválida rechazada (ambiente 80 °C)' ($_.Exception.Message -match 'ambiente') }
Set-CondicionesCalor -Expediente $exp -Atencion $at -Momento antes -Valores ([ordered]@{ enchufado = 's'; plan = 'Alto rendimiento'; ventiladores = 'auto'; superficie = 'mesa'; temp_ambiente_c = '24,5'; carga_tipo = 'Render en R'; carga_duracion_min = '108' })
Set-CondicionesCalor -Expediente $exp -Atencion $at -Momento despues -Valores ([ordered]@{ enchufado = 's'; plan = 'Alto rendimiento'; ventiladores = 'turbo'; superficie = 'mesa'; temp_ambiente_c = '22'; carga_tipo = 'Reposo'; carga_duracion_min = '112' })
$ra = Import-SensoresMedicion -Expediente $exp -Atencion $at -Momento antes -Ruta $antesCsv
Assert 'sensores.csv y sensores_resumen.json en antes\' ((Test-Path "$($exp.Ruta)\$at\antes\sensores.csv") -and (Test-Path "$($exp.Ruta)\$at\antes\sensores_resumen.json"))
$rd = Import-SensoresMedicion -Expediente $exp -Atencion $at -Momento despues -Ruta $despuesCsv
Set-Ficha -Expediente $exp -Atencion $at -Valores @{ 'checklist_fisico.desarme' = 's'; 'checklist_fisico.limpieza' = 's'; 'checklist_fisico.pasta' = 'PTM7950'; materiales = 'PTM7950;alcohol isopropílico' }
$m = Get-MetricasCalor -Expediente $exp -Atencion $at
foreach ($t in $m.Tarjetas) { '     {0,-28} {1,8} -> {2,-8} mejoró: {3}' -f $t.Titulo, $t.Antes, $t.Despues, $t.Mejoro }
foreach ($a in $m.Advertencias) { "     advertencia: $a" }
Assert 'tarjeta CPU promedio 91,1 -> 35,2 (mejoró)' ($m.Tarjetas[0].Antes -eq 91.1 -and $m.Tarjetas[0].Despues -eq 35.2 -and $m.Tarjetas[0].Mejoro)
Assert 'pierde velocidad: sí -> no (mejoró)' ($m.Tarjetas[4].Antes -eq $true -and $m.Tarjetas[4].Despues -eq $false -and $m.Tarjetas[4].Mejoro)
Assert 'avisa que cambiaron ventiladores, ambiente y tipo de carga' (@($m.Advertencias | Where-Object { $_ -like 'Cambió*' -and $_ -match 'ventiladores|ambiente|carga' }).Count -eq 3)
Assert 'tarjeta de velocidad sostenida en GHz: 1,9 -> 0,4 (empeoró)' ($m.Tarjetas[5].Unidad -eq 'GHz' -and $m.Tarjetas[5].Antes -eq 1.9 -and $m.Tarjetas[5].Despues -eq 0.4 -and $m.Tarjetas[5].Mejoro -eq $false)
Assert 'avisa que la CPU trabajó mucho menos en el DESPUÉS' (@($m.Advertencias | Where-Object { $_ -like '*trabajó mucho menos*' }).Count -eq 1)
Assert 'la pantalla del cliente lleva CPU, velocidad y pierde velocidad' ((@($m.Pantalla | ForEach-Object { $_.Titulo }) -join '|') -eq 'CPU, temperatura promedio|CPU, temperatura máxima|CPU, velocidad sostenida|Pierde velocidad por calor')
Assert 'checklist y materiales en la métrica' ($m.Checklist.pasta -eq 'PTM7950' -and @($m.Materiales).Count -eq 2)
# Sensores importados antes de correr el diagnóstico: pasan a la medición al completarla.
$en = Initialize-Medicion -Expediente $exp -Atencion $at -Momento 'antes'
[IO.File]::WriteAllText((Join-Path $en 'diagnostico.json'), '{}')
$rem = Complete-Medicion -Expediente $exp -Atencion $at -Momento 'antes'
Assert 'al correr el diagnóstico después, los sensores pasan a antes\' ((Test-Path "$($exp.Ruta)\$at\antes\sensores_resumen.json") -and (Test-Path "$($exp.Ruta)\$at\antes\diagnostico.json")) $rem
Get-Content -Encoding UTF8 "$($exp.Ruta)\$at\trabajo.log" | ForEach-Object { "     $_" }

'== REVISION (semáforo con sensores, en la prueba)'
$s = Get-SemaforoRevision -Expediente $exp -Atencion $at -Momento antes
foreach ($f in $s.Areas) { '     {0,-20} {1,-9} {2}' -f $f.Area, $f.Color, $f.Frase }
Assert 'temperatura en rojo con el CSV del ANTES' (($s.Areas | Where-Object Area -EQ 'Temperatura').Color -eq 'rojo')

'== REVISION y LENTO sobre la medición real del Nitro (solo lectura; solo en su PC)'
$script:Ctx.CarpetaClientes = $clientesReales
$nitro = $null
try { $nitro = Get-Expediente -Identidad (Get-IdentidadEquipo) } catch { $nitro = $null }
if (-not $nitro -or -not (Test-Path (Join-Path $nitro.Ruta '2026-11-01_atencion_2\antes\diagnostico.json'))) {
    '  OMITIDA  medición real del Nitro (no está en este equipo)'
} else {
    $s = Get-SemaforoRevision -Expediente $nitro -Atencion '2026-11-01_atencion_2' -Momento antes
    "     general: $($s.General)"
    foreach ($f in $s.Areas) { '     {0,-20} {1,-9} {2}' -f $f.Area, $f.Color, $f.Frase }
    Assert 'discos en rojo (152 errores de medio del Samsung)' (($s.Areas | Where-Object Area -EQ 'Discos').Color -eq 'rojo')
    $acc = @(Get-AccionesLento -Expediente $nitro -Atencion '2026-11-01_atencion_2')
    foreach ($a in $acc) { '     [{0,-9}] {1}{2}{3}' -f $a.Tipo, $a.Titulo, $(if ($a.RequiereAdmin) { ' [admin]' } else { '' }), $(if ($a.Riesgo -eq 'revisar') { ' [revisar]' } else { '' }) }
    Assert 'no ofrece desactivar SecurityHealth (Microsoft)' (@($acc | Where-Object { $_.Titulo -match 'SecurityHealth' }).Count -eq 0)
    Assert 'ofrece las entradas huérfanas' (@($acc | Where-Object { $_.Titulo -match 'huérfana' }).Count -ge 1)
}

'== LENTO: aplicar y deshacer sobre valores de prueba (HKCU)'
$script:Ctx.CarpetaClientes = $tmp
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$aprob = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$gpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$app = 'C:\kit_prueba_no_existe\juego.exe'
New-ItemProperty -Path $runKey -Name 'KitPruebaInicio' -Value 'C:\kit_prueba_no_existe\app.exe' -PropertyType String -Force | Out-Null
if (-not (Test-Path $gpuKey)) { New-Item -Path $gpuKey -Force | Out-Null }
New-ItemProperty -Path $gpuKey -Name $app -Value 'GpuPreference=1;' -PropertyType String -Force | Out-Null
try {
    $acciones = @(
        ConvertTo-AccionLento -Id 'inicio|HKCU|Run|KitPruebaInicio' -Tipo 'inicio' -Titulo 'Desactivar al inicio: KitPruebaInicio' -QueHace 'prueba' -Deshacer 'prueba' -Admin $false -Datos ([ordered]@{ Colmena = 'HKCU'; Clave = 'Run'; Nombre = 'KitPruebaInicio' })
        ConvertTo-AccionLento -Id "gpu|$app" -Tipo 'gpu' -Titulo 'GPU alto rendimiento en juego.exe' -QueHace 'prueba' -Deshacer 'prueba' -Admin $false -Datos ([ordered]@{ App = $app })
    )
    $expL = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Prueba Lento'; Serie = 'LENTO001'; SerieOriginal = 'LENTO001'; Uuid = $null; PlacaSerie = $null })
    $atL = New-Atencion -Expediente $expL
    # Se prueba como sin admin aunque la batería corra elevada (en GitHub corre así): con admin crearía un punto de restauración.
    $adminReal = $script:Ctx.Admin
    $script:Ctx.Admin = [pscustomobject]@{ Elevado = $false; MiembroAdministradores = $true }
    try { $null = Invoke-AccionesLento -Expediente $expL -Atencion $atL -Acciones @(ConvertTo-AccionLento -Id 'servicio|x' -Tipo 'servicio' -Titulo 'Servicio X' -QueHace '' -Deshacer '' -Admin $true -Datos ([ordered]@{ Servicio = 'x' })); Assert 'admin' $false }
    catch { Assert 'sin admin rechaza acciones que lo necesitan' ($_.Exception.Message -match 'Necesitan admin') }
    try { $null = Invoke-AccionesLento -Expediente $expL -Atencion $atL -Acciones $acciones; Assert 'punto' $false } catch { Assert 'sin admin y sin -SinPuntoRestauracion no aplica nada' ($_.Exception.Message -match 'punto de restauración') }
    $script:Ctx.Admin = $adminReal
    $hechas = @(Invoke-AccionesLento -Expediente $expL -Atencion $atL -Acciones $acciones -SinPuntoRestauracion)
    $bytes = (Get-ItemProperty -Path $aprob -Name 'KitPruebaInicio').KitPruebaInicio
    Assert 'inicio marcado como deshabilitado (03 en StartupApproved)' ($hechas.Count -eq 2 -and $bytes[0] -eq 3)
    Assert 'GPU pasó a GpuPreference=2;' ((Get-ItemProperty -Path $gpuKey -Name $app).$app -eq 'GpuPreference=2;')
    Assert 'acciones_realizadas en la ficha' (@((Get-EntradaAtencion -Expediente (Get-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Prueba Lento'; Serie = 'LENTO001' })) -Carpeta $atL)['acciones_realizadas']).Count -eq 2)
    $deshechas = @(Undo-AccionesLento -Expediente $expL -Atencion $atL)
    Assert 'deshacer: StartupApproved vuelve a como estaba (no existía)' ($deshechas.Count -eq 2 -and $null -eq (Get-ItemProperty -Path $aprob -Name 'KitPruebaInicio' -ErrorAction SilentlyContinue))
    Assert 'deshacer: GPU vuelve a GpuPreference=1;' ((Get-ItemProperty -Path $gpuKey -Name $app).$app -eq 'GpuPreference=1;')
    Assert 'acciones_realizadas vacía tras deshacer' (@((Get-EntradaAtencion -Expediente (Get-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Prueba Lento'; Serie = 'LENTO001' })) -Carpeta $atL)['acciones_realizadas'] | Where-Object { $_ }).Count -eq 0)
    Get-Content -Encoding UTF8 "$($expL.Ruta)\$atL\trabajo.log" | ForEach-Object { "     $_" }
} finally {
    Remove-ItemProperty -Path $runKey -Name 'KitPruebaInicio' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $aprob -Name 'KitPruebaInicio' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $gpuKey -Name $app -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force
}
"  limpieza: Run=$($null -ne (Get-ItemProperty $runKey -Name KitPruebaInicio -ErrorAction SilentlyContinue)) Aprob=$($null -ne (Get-ItemProperty $aprob -Name KitPruebaInicio -ErrorAction SilentlyContinue)) GPU=$($null -ne (Get-ItemProperty $gpuKey -Name $app -ErrorAction SilentlyContinue))"
''
"Resultado: $script:ok OK, $script:fallas fallas"
