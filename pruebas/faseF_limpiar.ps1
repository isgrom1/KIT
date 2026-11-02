#Requires -Version 5.1
# Fase F — limpieza: borra la entrada de inicio de prueba KitPruebaInicio, saca la foto final de lo que toca
# LENTO y la compara con la inicial (sin la entrada de prueba). Debe dar "igual".
$ErrorActionPreference = 'Stop'
$base = 'X:\kitservicio_prueba\faseF'
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run') {
    if ((Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).PSObject.Properties['KitPruebaInicio']) { Remove-ItemProperty -Path $k -Name 'KitPruebaInicio'; "borrada KitPruebaInicio de $k" }
}
$null = & (Join-Path $PSScriptRoot 'faseF_estado.ps1') -Salida (Join-Path $base 'estado_final.json')
$ini = Get-Content (Join-Path $base 'estado_inicial.json') -Raw | ConvertFrom-Json
$fin = Get-Content (Join-Path $base 'estado_final.json') -Raw | ConvertFrom-Json
$ini.run_hkcu.PSObject.Properties.Remove('KitPruebaInicio')
$a = $ini | ConvertTo-Json -Depth 5 -Compress; $b = $fin | ConvertTo-Json -Depth 5 -Compress
if ($a -eq $b) { 'Estado final = estado inicial (sin la entrada de prueba): igual' } else {
    'DIFERENCIAS:'
    foreach ($p in $ini.PSObject.Properties) { $x = $p.Value | ConvertTo-Json -Depth 5 -Compress; $y = $fin.($p.Name) | ConvertTo-Json -Depth 5 -Compress; if ($x -ne $y) { "  $($p.Name): antes=$x | ahora=$y" } }
}
