# Prueba de desarrollo: alertas, resumen y métricas con SMART de discos.txt, usando la última medición
# con admin del Nitro (sin volver a correr el diagnóstico elevado).
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'secciones\02_hardware.ps1')
Initialize-Contexto -RaizScripts $scripts
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
