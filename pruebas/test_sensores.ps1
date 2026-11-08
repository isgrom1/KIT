# Pruebas de desarrollo de lib\Sensores.ps1 (no es parte del kit). Con CSV sintéticos y de ejemplo (en una
# carpeta temporal) comprueba formato, codificación, separador, filas descartadas y métricas. Si están los CSV
# reales de Isaac (solo en su PC), también los muestra, sin modificarlos.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
$docs = [Environment]::GetFolderPath('MyDocuments')   # CSV reales de HWiNFO usados en las pruebas de CALOR
foreach ($lib in 'Comun', 'Log', 'Sensores') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$tmp = Join-Path $env:TEMP ('kit_prueba_sens_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp

# LibreHardwareMonitor: nombres repetidos que se distinguen por el tipo (temperatura, reloj, carga...)
$lhm = @(',"/intelcpu/0/temperature/6","/intelcpu/0/temperature/0","/intelcpu/0/temperature/1","/intelcpu/0/clock/1","/intelcpu/0/power/0","/nvidiagpu/0/temperature/0","/nvidiagpu/0/load/0","/ram/data/0"'
    '"Time","CPU Package","CPU Core #1","CPU Core #2","CPU Core #1","CPU Package","GPU Core","GPU Core","Memory Used"')
for ($i = 0; $i -lt 120; $i++) { $lhm += ('"11/01/2026 16:{0:00}:{1:00}","{2}","{3}","{4}","3500","45.5","70","95","12.5"' -f [int][math]::Floor($i / 60), ($i % 60), (80 + ($i % 20)), (78 + ($i % 15)), (79 + ($i % 17))) }
[IO.File]::WriteAllLines("$tmp\lhm.csv", $lhm, (New-Object System.Text.UTF8Encoding($false)))

# HWiNFO con punto y coma y coma decimal, más encabezado repetido al final
$pc = @('"Date";"Time";"CPU Package [°C]";"Core Max [°C]";"GPU Temperature [°C]";"Package/Ring Thermal Throttling [Yes/No]"')
for ($i = 0; $i -lt 60; $i++) { $pc += ('26.10.2026;20:0{0}:{1}.5;{2},5;{3};61,2;{4}' -f [int][math]::Floor($i / 10), ($i % 10), (88 + ($i % 10)), (90 + ($i % 9)), $(if ($i % 4 -eq 0) { 'Yes' } else { 'No' })) }
$pc += $pc[0]
$pc += ';;"CPU [#0]: Intel";"CPU [#0]: Intel";"GPU [#0]";"CPU [#0]: Intel"'
[IO.File]::WriteAllLines("$tmp\pc.csv", $pc, [Text.Encoding]::GetEncoding(1252))

# UTF-16 LE
$u16 = @('Date,Time,"CPU Package [°C]","GPU Temperature [°C]"')
for ($i = 0; $i -lt 30; $i++) { $u16 += ('1.11.2026,9:0:{0}.250,{1}.5,60.0' -f $i, (70 + $i)) }
[IO.File]::WriteAllLines("$tmp\utf16.csv", $u16, [Text.Encoding]::Unicode)
[IO.File]::WriteAllText("$tmp\malo.csv", "a,b,c`r`n1,2,3`r`n")

. (Join-Path $PSScriptRoot '_datos_ejemplo.ps1')
Write-CsvHwinfoEs -Ruta "$tmp\hwinfo_es.csv" -Temp 91.1 -Mhz 1900 -PctDesaceleracion 20 -Uso 100
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
function Show-Resumen {
    param([string]$Ruta)
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $r = Read-SensoresCsv -Ruta $Ruta
    "=== {0} | {1} | {2} | sep '{3}' coma decimal: {4} | {5} filas ({6} descartadas) | {7} min, cada {8} s | {9:N1} s" -f $r.archivo, $r.formato, $r.codificacion, $r.separador, $r.coma_decimal, $r.filas, $r.filas_descartadas, $r.duracion_min, $r.intervalo_seg, $reloj.Elapsed.TotalSeconds
    foreach ($k in $r.metricas.Keys) {
        $m = $r.metricas[$k]
        if ($m) { '   {0,-20} media {1,7}  p95 {2,7}  máx {3,7} {4,-4} <- {5}' -f $k, $m.media, $m.p95, $m.max, $m.unidad, $r.columnas[$k] }
        else { '   {0,-20} (no está en el CSV)' -f $k }
    }
    '   throttling: {0} % ({1}) | minutos > {2} °C: {3} | % del tiempo ≥ 95 °C: {4}' -f $r.throttling_pct, $r.columnas['cpu_throttling'], $r.umbral_c, $r.minutos_sobre_umbral, $r.pct_tiempo_tjmax
    '   pierde velocidad por calor: {0} ({1}) | serie: {2} puntos' -f $r.pierde_velocidad.valor, $r.pierde_velocidad.fuente, @($r.serie).Count
}

try {
    '== CSV reales de Isaac (solo se muestran; en otro equipo se omiten)'
    foreach ($a in (Join-Path $docs '08 Datos sueltos (csv-json)\reg.CSV'), (Join-Path $docs '08 Datos sueltos (csv-json)\ESTO.CSV'), (Join-Path $docs 'asdasd.CSV'), (Join-Path $docs 'temp.CSV')) {
        if (-not [IO.File]::Exists($a)) { "  OMITIDA  $(Split-Path -Leaf $a) (no está en este equipo)"; continue }
        try { Show-Resumen $a } catch { "=== $(Split-Path -Leaf $a): ERROR -> $($_.Exception.Message)" }
    }

    '== CSV sintéticos y de ejemplo'
    $l = Read-SensoresCsv -Ruta "$tmp\lhm.csv"
    Assert 'LibreHardwareMonitor: formato, 120 filas y temperatura de CPU' ($l.formato -eq 'LibreHardwareMonitor' -and $l.filas -eq 120 -and $l.metricas.cpu_temp_paquete -and $l.metricas.gpu_temp) -D "$($l.formato) $($l.filas)"
    Assert 'LibreHardwareMonitor: sin sensor de throttling, decide por la temperatura (25 % ≥ 95 °C)' ($l.pierde_velocidad.valor -eq $true -and $l.pct_tiempo_tjmax -eq 25)
    $p = Read-SensoresCsv -Ruta "$tmp\pc.csv"
    Assert 'HWiNFO con punto y coma, coma decimal y ANSI' ($p.formato -eq 'HWiNFO' -and $p.separador -eq ';' -and $p.coma_decimal -and $p.codificacion -like 'ANSI*')
    Assert 'descarta el encabezado repetido y la fila de grupos' ($p.filas -eq 60 -and $p.filas_descartadas -eq 2)
    Assert 'throttling 25 % del tiempo' ($p.throttling_pct -eq 25 -and $p.pierde_velocidad.valor)
    $u = Read-SensoresCsv -Ruta "$tmp\utf16.csv"
    Assert 'UTF-16 LE con 30 filas' ($u.codificacion -eq 'UTF-16 LE' -and $u.filas -eq 30)
    $e = $null; try { $null = Read-SensoresCsv -Ruta "$tmp\malo.csv" } catch { $e = $_.Exception.Message }
    Assert 'un CSV que no es de sensores da un error claro' ($e -match 'Formato no reconocido')
    $h = Read-SensoresCsv -Ruta "$tmp\hwinfo_es.csv"
    Assert 'HWiNFO en español: UTF-8 con BOM, hora sin ceros y 10 min' ($h.formato -eq 'HWiNFO' -and $h.codificacion -eq 'UTF-8 con BOM' -and $h.filas -eq 300 -and $h.filas_descartadas -eq 2 -and $h.duracion_min -eq 10) -D "$($h.codificacion) $($h.filas) $($h.filas_descartadas) $($h.duracion_min)"
    Assert 'HWiNFO en español: con "CPU Entera" repetida toma la primera (91,1 / 92,1 °C)' ($h.metricas.cpu_temp_paquete.media -eq 91.1 -and $h.metricas.cpu_temp_paquete.max -eq 92.1)
    Assert 'HWiNFO en español: reloj efectivo, desaceleración y pierde velocidad' ($h.metricas.cpu_frec_efectiva.media -eq 1900 -and $h.throttling_pct -eq 20 -and $h.pierde_velocidad.valor -eq $true)
    Assert 'HWiNFO en español: todo bajo carga (100 % de uso)' ([bool]$h.carga)
} finally {
    Remove-Item $tmp -Recurse -Force
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }