# Herramienta de desarrollo: borra los datos de prueba de la ficha del Nitro (cliente y campos de la
# atención _2) dejando las mediciones. Usa Set-Ficha, así que queda ficha.json.bak con lo anterior.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$exp = Get-Expediente -Identidad (Get-IdentidadEquipo)
$valores = [ordered]@{ 'cliente.nombre' = $null; 'cliente.contacto' = $null; 'cliente.comuna' = $null }
Set-Ficha -Expediente $exp -Valores $valores
$at = [ordered]@{ motivos = $null; sintoma = $null; estado_fisico = $null; respaldo = $null; paquete = $null; precio = $null }
foreach ($i in $script:ItemsChecklist) { $at["checklist_funcional.$i"] = $null }
Set-Ficha -Expediente $exp -Atencion '2026-11-01_atencion_2' -Valores $at
Write-TrabajoLog -Expediente $exp -Atencion '2026-11-01_atencion_2' -Texto 'FICHA | se borraron los datos de prueba (cliente y campos de la atención)'
$f = (Get-Expediente -Identidad (Get-IdentidadEquipo)).Ficha
'cliente: ' + ($f.cliente | ConvertTo-Json -Compress)
foreach ($a in $f.atenciones) { '{0}: motivos=[{1}] sintoma={2} precio={3} antes={4} despues={5}' -f $a.carpeta, ($a.motivos -join ','), $a.sintoma, $a.precio, $a.mediciones.antes.fecha, $a.mediciones.despues.fecha }
