# Pruebas de desarrollo de lib\Sensores.ps1 (no es parte del kit). Lee los CSV reales de Isaac sin
# modificarlos y crea CSV sintéticos en una carpeta temporal.
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

$archivos = (Join-Path $docs '08 Datos sueltos (csv-json)\reg.CSV'), (Join-Path $docs '08 Datos sueltos (csv-json)\ESTO.CSV'), (Join-Path $docs 'asdasd.CSV'), (Join-Path $docs 'temp.CSV'), "$tmp\lhm.csv", "$tmp\pc.csv", "$tmp\utf16.csv", "$tmp\malo.csv"
foreach ($a in $archivos) {
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Read-SensoresCsv -Ruta $a
        "=== {0} | {1} | {2} | sep '{3}' coma decimal: {4} | {5} filas ({6} descartadas) | {7} min, cada {8} s | {9:N1} s" -f $r.archivo, $r.formato, $r.codificacion, $r.separador, $r.coma_decimal, $r.filas, $r.filas_descartadas, $r.duracion_min, $r.intervalo_seg, $reloj.Elapsed.TotalSeconds
        foreach ($k in $r.metricas.Keys) {
            $m = $r.metricas[$k]
            if ($m) { '   {0,-20} media {1,7}  p95 {2,7}  máx {3,7} {4,-4} <- {5}' -f $k, $m.media, $m.p95, $m.max, $m.unidad, $r.columnas[$k] }
            else { '   {0,-20} (no está en el CSV)' -f $k }
        }
        '   throttling: {0} % ({1}) | minutos > {2} °C: {3} | % del tiempo ≥ 95 °C: {4}' -f $r.throttling_pct, $r.columnas['cpu_throttling'], $r.umbral_c, $r.minutos_sobre_umbral, $r.pct_tiempo_tjmax
        '   pierde velocidad por calor: {0} ({1}) | serie: {2} puntos' -f $r.pierde_velocidad.valor, $r.pierde_velocidad.fuente, @($r.serie).Count
    } catch {
        "=== $(Split-Path -Leaf $a): ERROR esperado/inesperado -> $($_.Exception.Message)"
    }
}
Remove-Item $tmp -Recurse -Force
