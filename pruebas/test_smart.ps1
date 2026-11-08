# Pruebas de desarrollo de la lectura de discos.txt (CrystalDiskInfo). Con un discos.txt de ejemplo (series
# inventadas) comprueba lo que se lee por ID de atributo. Si en KIT\clientes de este PC hay una medición con
# admin (solo en el de Isaac), además muestra sus alertas, resumen y métricas de discos.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'secciones\02_hardware.ps1')
. (Join-Path $PSScriptRoot '_datos_ejemplo.ps1')
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_smart_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
try {
    '== discos.txt de ejemplo'
    Write-DiscosEjemplo -Ruta "$tmp\discos.txt"
    $d = @(Read-DiscosCrystal -Ruta "$tmp\discos.txt")
    Assert 'lee los dos discos del detalle, no la lista del inicio' ($d.Count -eq 2 -and $d[0].Numero -eq 1 -and $d[1].Modelo -eq 'DISCO HDD DE EJEMPLO 1TB') -D "discos: $($d.Count)"
    Assert 'NVMe: interfaz, salud, temperatura y horas' ($d[0].Nvme -and $d[0].SaludPct -eq 95 -and $d[0].SaludTexto -eq 'Bueno' -and $d[0].TemperaturaC -eq 41 -and $d[0].HorasEncendido -eq 3200)
    Assert 'NVMe por ID: aviso 0, repuesto 100 %, uso 5 %, 10 apagados no seguros, 152 errores de medio' ($d[0].AvisoCritico -eq 0 -and $d[0].RepuestoPct -eq 100 -and $d[0].UsoPct -eq 5 -and $d[0].ApagadosNoSeguros -eq 10 -and $d[0].ErroresMedio -eq 152)
    Assert 'SATA por ID: 8 reasignados, 2 pendientes, 0 no corregibles' (-not $d[1].Nvme -and $d[1].Reasignados -eq 8 -and $d[1].Pendientes -eq 2 -and $d[1].NoCorregibles -eq 0)
    Assert 'salud sin porcentaje: solo el texto' ($d[1].SaludTexto -eq 'Precaución' -and $null -eq $d[1].SaludPct)

    '== Última medición con admin de este PC (solo se muestra; en otro equipo se omite)'
    $clientes = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\clientes'
    $hay = [IO.Directory]::Exists($clientes) -and @(Get-ChildItem $clientes -Recurse -Filter discos.txt).Count
    if (-not $hay) { '  OMITIDA  medición real con discos.txt (no hay en este equipo)' }
    else {
        # La medición más reciente que tenga discos.txt (hecha con admin) en KIT\clientes de este PC.
        $med = (Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\clientes') -Recurse -Filter discos.txt | Sort-Object LastWriteTime | Select-Object -Last 1).DirectoryName
        $doc = ConvertTo-Diccionario (Read-JsonKit (Join-Path $med 'diagnostico.json'))
        $script:Ctx.Datos['hardware'] = $doc['datos']['hardware']
        $script:Ctx.Datos['uso'] = $doc['datos']['uso']
        $script:Ctx.Datos.hardware['SmartCrystal'] = @(Read-DiscosCrystal -Ruta (Join-Path $med 'discos.txt'))
        $script:Ctx.SeccionActual = '02 Hardware'; $script:Ctx.SeccionNumero = 2
        Test-AlertasHardware
        '=== alertas de hardware'
        $todas = Get-AlertasOrdenadas; $todas | ForEach-Object { '[{0}] {1}: {2}' -f $_.Severidad, $_.Codigo, $_.Texto }
        '=== resumen (discos)'
        Format-ResumenHardware | Where-Object { $_ -match '^Disco|CrystalDiskInfo|^SMART' }
        '=== metricas.json (discos)'
        (Get-Metricas).discos | ForEach-Object { $_ | ConvertTo-Json -Compress }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }