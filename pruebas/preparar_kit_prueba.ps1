#Requires -Version 5.1
# Copia el KIT a <Destino>\KIT y deja datos de prueba SOLO en la copia:
# - config: contacto del técnico de relleno (el real está vacío y sin él no se generan informes).
# - Nitro: atención 1 entregada y con ficha completa (para liberar y regenerar desde el maestro);
#   la atención 2 sigue abierta.
# - Un cliente sintético de otro equipo (HP Pavilion) con una atención entregada.
param([Parameter(Mandatory)][string]$Destino, [switch]$SinHerramientas)
$ErrorActionPreference = 'Stop'
$origen = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT'
$kit = Join-Path $Destino 'KIT'
if ([IO.Directory]::Exists($kit)) { throw "Ya existe $kit (bórralo antes)" }
$xd = @(); if ($SinHerramientas) { $xd = @('/XD', (Join-Path $origen 'herramientas')) }
& robocopy.exe $origen $kit /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP @xd | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falló ($LASTEXITCODE)" }
$cfg = Join-Path $kit 'scripts\config\config.json'
$t = [IO.File]::ReadAllText($cfg)
if (-not $t.Contains('"contacto": ""')) { throw 'No encontré tecnico.contacto vacío en la copia' }
[IO.File]::WriteAllText($cfg, $t.Replace('"contacto": ""', '"contacto": "+56 9 0000 0000 (prueba)"'), (New-Object Text.UTF8Encoding($false)))

$scripts = Join-Path $kit 'scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$nitro = Read-Expediente (Get-ChildItem (Join-Path $kit 'clientes') -Directory -Filter 'Acer_Nitro*' | Select-Object -First 1).FullName
Set-Ficha -Expediente $nitro -Valores @{ 'cliente.nombre' = 'Cliente de prueba'; 'cliente.contacto' = '+56 9 1234 5678'; 'cliente.comuna' = 'Providencia' }
Set-Ficha -Expediente $nitro -Atencion '2026-11-01_atencion' -Valores ([ordered]@{ motivos = @('REVISION'); sintoma = 'Revisión general (prueba)'; paquete = 'Revisión'; precio = '15000'; entregado = '2026-11-01' })

$id = [pscustomobject]@{ Fabricante = 'HP'; Modelo = 'Pavilion 15'; Serie = '5CD1234XYZ'; SerieOriginal = '5CD1234XYZ'; Uuid = $null; PlacaSerie = $null }
$hp = New-Expediente -Identidad $id
Set-Ficha -Expediente $hp -Valores @{ 'cliente.nombre' = 'Ana Pérez (sintético)'; 'cliente.contacto' = '+56 9 1111 2222'; 'cliente.comuna' = 'Ñuñoa' }
$at = New-Atencion -Expediente $hp -Fecha ([datetime]'2026-10-20')
$c = Join-Path $hp.Ruta $at
$null = [IO.Directory]::CreateDirectory((Join-Path $c 'antes'))
[IO.File]::WriteAllText((Join-Path $c 'antes\resumen.txt'), 'Resumen sintético de prueba', (New-Object Text.UTF8Encoding($true)))
[IO.File]::WriteAllText((Join-Path $c 'trabajo.log'), "2026-10-20 10:00 | FICHA | prueba`r`n", (New-Object Text.UTF8Encoding($true)))
Set-Ficha -Expediente $hp -Atencion $at -Valores ([ordered]@{ motivos = @('LENTO'); sintoma = 'Lento al iniciar'; paquete = 'Optimización'; precio = '20000'; entregado = '2026-10-22' })
"Kit de prueba listo en $kit ($([math]::Round((Get-ChildItem $kit -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)) MB)"
