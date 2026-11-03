# Vista previa de los informes con datos reales del Nitro, en una carpeta aparte (no toca el expediente
# real del kit). Contacto del cliente, contacto del técnico y precio son de relleno, marcados como tales.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
$docs = [Environment]::GetFolderPath('MyDocuments')   # CSV reales de HWiNFO usados en las pruebas de CALOR
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe') { . (Join-Path $scripts "lib\$lib.ps1") }
foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $scripts "motivos\$m.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$real = $script:Ctx.CarpetaClientes
$nitroReal = Get-Expediente -Identidad (Get-IdentidadEquipo)
$destino = Join-Path $PSScriptRoot 'vista_previa'
if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
$script:Ctx.CarpetaClientes = Join-Path $destino 'clientes'
$null = New-Item -ItemType Directory $script:Ctx.CarpetaClientes
if (-not $script:Ctx.Config.tecnico.contacto) { $script:Ctx.Config.tecnico.contacto = '(tu contacto: config_local.json)' }

$exp = New-Expediente -Identidad (Get-IdentidadEquipo)
$at = New-Atencion -Expediente $exp
# Mediciones reales: ANTES con admin (atención _2) y la última DESPUÉS de hoy (atención 1).
Copy-Item -Recurse (Join-Path $nitroReal.Ruta '2026-11-01_atencion_2\antes') (Join-Path $exp.Ruta "$at\antes")
Copy-Item -Recurse (Join-Path $nitroReal.Ruta '2026-11-01_atencion\despues') (Join-Path $exp.Ruta "$at\despues")
$exp = Read-Expediente $exp.Ruta
$da = Read-JsonKit (Join-Path $exp.Ruta "$at\antes\diagnostico.json")
Update-FichaDesdeDiagnostico -Expediente $exp -Atencion $at -Momento 'antes' -Datos $da.datos -Generado $da.kit.generado -Admin $true -Alertas @($da.alertas)
$dd = Read-JsonKit (Join-Path $exp.Ruta "$at\despues\diagnostico.json")
Update-FichaDesdeDiagnostico -Expediente $exp -Atencion $at -Momento 'despues' -Datos $dd.datos -Generado $dd.kit.generado -Admin $false -Alertas @($dd.alertas)
Set-Ficha -Expediente $exp -Atencion $at -Valores ([ordered]@{
        'cliente.nombre' = 'Isaac (vista previa)'; 'cliente.contacto' = '+56 9 0000 0000'; 'cliente.comuna' = 'Santiago'
        motivos = 'CALOR'; sintoma = 'Se calienta mucho con carga pesada'; paquete = 'Mantención por temperatura'; precio = '0'
    })
$null = Import-SensoresMedicion -Expediente $exp -Atencion $at -Momento 'antes' -Ruta (Join-Path $docs '08 Datos sueltos (csv-json)\reg.CSV')
$r = Export-Informes -Expediente (Read-Expediente $exp.Ruta) -Atencion $at
if (-not $r.Generado) { 'NO GENERADO, falta:'; $r.Faltan | ForEach-Object { " - $($_.Texto)" }; return }
"Cliente: $($r.Cliente)"
"Técnico: $($r.Tecnico)"
"Frase: $($r.Datos.Frase) | color: $($r.Datos.Color)"
"Hecho: $($r.Datos.Hecho -join ' | ')"
"Recomendaciones: $($r.Datos.Recomendaciones -join ' | ')"
"Advertencias: $($r.Datos.Advertencias -join ' | ')"
