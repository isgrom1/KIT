# Prueba de desarrollo: "después" sin atención abierta con "antes" -> código 4 y nada creado.
param([ValidateSet('entregar', 'reabrir')][string]$Accion)
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$exp = Get-Expediente -Identidad (Get-IdentidadEquipo)
foreach ($a in @(Get-ListaAtenciones -Expediente $exp)) {
    if ($Accion -eq 'entregar') { Set-Ficha -Expediente $exp -Atencion $a['carpeta'] -Valores @{ entregado = (Get-Date).ToString('yyyy-MM-dd') } }
    else { Set-Ficha -Expediente $exp -Atencion $a['carpeta'] -Valores @{ entregado = $null; garantia_hasta = $null } }
    $e = Get-EntradaAtencion -Expediente $exp -Carpeta $a['carpeta']
    '{0}: entregado={1} garantia_hasta={2}' -f $a['carpeta'], $e['entregado'], $e['garantia_hasta']
}
