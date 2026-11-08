#Requires -Version 5.1
<#
.SYNOPSIS
    Fase G: versión y verificación del kit, actualizar_pendrive.ps1 y el siguiente paso de la atención.
.DESCRIPTION
    Todo en una carpeta temporal que se borra al terminar: un kit falso, un "pendrive" de prueba con un
    cliente y un config_local propios, y expedientes sintéticos. No toca el pendrive real ni KIT\clientes.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $repo 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe', 'Flujo') { . (Join-Path $scripts "lib\$lib.ps1") }
foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $scripts "motivos\$m.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_faseG_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$utf8 = New-Object Text.UTF8Encoding($false)
function Write-Texto([string]$Ruta, [string]$Texto) { $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Ruta)); [IO.File]::WriteAllText($Ruta, $Texto, $utf8) }

try {
    '== Versión y verificación del kit'
    $k = Join-Path $tmp 'kitfalso\KIT'
    Write-Texto "$k\INICIAR.cmd" '@echo off'
    Write-Texto "$k\scripts\a.ps1" 'a'
    Write-Texto "$k\scripts\config\config.json" '{}'
    Write-Texto "$k\scripts\config\config_local.json" '{"tecnico":{}}'
    Write-Texto "$k\docs\guia.md" '# guía'
    $lista = @(Get-ArchivosVerificablesKit -RaizKit $k)
    Assert 'lista INICIAR, scripts y docs, sin config_local' ($lista.Count -eq 4 -and $lista -notcontains 'scripts\config\config_local.json') -D "lista: $($lista -join ', ')"
    Assert 'sin version.json: copia de trabajo' ((Test-IntegridadKit -RaizKit $k).Estado -eq 'sin_manifiesto' -and (Get-VersionKit -RaizKit $k) -like '*copia de trabajo*')
    $man = [ordered]@{}; foreach ($rel in $lista) { $man[$rel] = (Get-FileHash -LiteralPath (Join-Path $k $rel) -Algorithm SHA256).Hash }
    Write-Texto "$k\version.json" (([ordered]@{ version_base = '0.2.0'; commit = 'abc1234'; fecha_commit = '2026-11-08'; copiado = '2026-11-08 10:00:00'; archivos = $man }) | ConvertTo-Json -Depth 4)
    Assert 'con version.json: OK' ((Test-IntegridadKit -RaizKit $k).Estado -eq 'ok')
    Assert 'la versión muestra commit y fecha' ((Get-VersionKit -RaizKit $k) -eq "$script:VersionBase · abc1234 · 2026-11-08")
    Write-Texto "$k\scripts\config\config_local.json" '{"tecnico":{"contacto":"otro"}}'
    Assert 'cambiar config_local no cuenta' ((Test-IntegridadKit -RaizKit $k).Estado -eq 'ok')
    Write-Texto "$k\scripts\a.ps1" 'a modificado'
    Remove-Item -LiteralPath "$k\docs\guia.md"
    Write-Texto "$k\scripts\intruso.ps1" 'x'
    $i = Test-IntegridadKit -RaizKit $k
    Assert 'detecta el script cambiado' ($i.Estado -eq 'cambios' -and $i.Cambiados -contains 'scripts\a.ps1')
    Assert 'detecta el que falta y el que sobra' ($i.Faltan -contains 'docs\guia.md' -and $i.Nuevos -contains 'scripts\intruso.ps1')
    Write-Texto "$k\version.json" '{ esto no es json'
    Assert 'un version.json roto se informa como error' ((Test-IntegridadKit -RaizKit $k).Estado -eq 'error')

    '== actualizar_pendrive.ps1 sobre un pendrive de prueba'
    $usb = Join-Path $tmp 'usb'
    Write-Texto "$usb\KIT\clientes\Prueba_X\ficha.json" '{"cliente":{"nombre":"no tocar"}}'
    Write-Texto "$usb\KIT\scripts\config\config_local.json" '{"tecnico":{"contacto":"del pendrive"}}'
    Write-Texto "$usb\KIT\scripts\viejo.ps1" 'ya no existe en el repositorio'
    $fichaAntes = (Get-FileHash -LiteralPath "$usb\KIT\clientes\Prueba_X\ficha.json").Hash
    $salida = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'actualizar_pendrive.ps1') -Destino $usb 2>&1 | Out-String
    $codigo = $LASTEXITCODE
    Assert 'termina bien' ($codigo -eq 0) -D "código $codigo | $salida"
    $v = Read-JsonKitOpcional "$usb\KIT\version.json"
    Assert 'deja version.json con commit y hashes' ($v -and $v.commit -match '^([0-9a-f]{7,}|sin-git)' -and @($v.archivos.PSObject.Properties).Count -gt 40)
    Assert 'la copia queda verificada' ((Test-IntegridadKit -RaizKit "$usb\KIT").Estado -eq 'ok')
    Assert 'KIT\clientes queda intacto' ((Get-FileHash -LiteralPath "$usb\KIT\clientes\Prueba_X\ficha.json").Hash -eq $fichaAntes)
    Assert 'no pisa el config_local del pendrive' ([IO.File]::ReadAllText("$usb\KIT\scripts\config\config_local.json") -match 'del pendrive')
    Assert 'aparta el script obsoleto, no lo borra' (-not (Test-Path "$usb\KIT\scripts\viejo.ps1") -and @(Get-ChildItem "$usb\KIT\_obsoletos" -Recurse -Filter 'viejo.ps1').Count -eq 1)
    Assert 'copia INICIAR.cmd y actualizar_herramientas.ps1' ((Test-Path "$usb\KIT\INICIAR.cmd") -and (Test-Path "$usb\actualizar_herramientas.ps1"))
    Assert 'sin -ConHerramientas no copia herramientas de terceros' (-not (Test-Path "$usb\KIT\herramientas\OCCT"))
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'actualizar_pendrive.ps1') -Destino $usb 2>&1
    Assert 'se puede repetir sin problemas' ($LASTEXITCODE -eq 0 -and @(Get-ChildItem "$usb\KIT\_obsoletos" -Directory).Count -eq 1)
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'actualizar_pendrive.ps1') -Destino $repo 2>&1
    Assert 'se niega a copiar sobre el mismo repositorio' ($LASTEXITCODE -eq 1)
    $herrFalsas = Join-Path $tmp 'herramientas_falsas'
    Write-Texto "$herrFalsas\OCCT\OCCT.exe" 'programa falso'
    Write-Texto "$herrFalsas\HWiNFO\HWiNFO64.exe" 'otro programa falso'
    Write-Texto "$usb\KIT\herramientas\Propia\mia.exe" 'una herramienta que solo está en el pendrive'
    $salidaH = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'actualizar_pendrive.ps1') -Destino $usb -ConHerramientas -Herramientas $herrFalsas 2>&1 | Out-String
    Assert 'repuesto: copia y verifica las herramientas' ($LASTEXITCODE -eq 0 -and (Test-Path "$usb\KIT\herramientas\OCCT\OCCT.exe") -and $salidaH -match 'Herramientas verificadas por SHA-256: 2 archivos') -D $salidaH
    Assert 'repuesto: no borra lo que el pendrive ya tenía' (Test-Path "$usb\KIT\herramientas\Propia\mia.exe")
    $script:Ctx.RaizKit = "$usb\KIT"
    Assert 'el kit copiado muestra su versión' ((Get-VersionKit -RaizKit "$usb\KIT") -like "$script:VersionBase · *")

    '== Siguiente paso de la atención'
    $script:Ctx.CarpetaClientes = Join-Path $tmp 'clientes'
    $script:Ctx.Config.tecnico.nombre = 'Técnico de prueba'
    $script:Ctx.Config.tecnico.contacto = ''
    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Flujo'; Serie = 'FLU001'; SerieOriginal = 'FLU001'; Uuid = $null; PlacaSerie = $null })
    $sig = { param($At) (Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $At).Codigo }
    Assert 'sin atención: marcar el motivo' ((& $sig $null) -eq 'motivos')
    $at = New-Atencion -Expediente $e
    Assert 'sin motivos: marcar el motivo' ((& $sig $at) -eq 'motivos')
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Valores ([ordered]@{ motivos = 'CALOR' })
    $s = Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'después: completar la ficha, y dice qué falta' ($s.Codigo -eq 'ficha' -and $s.Texto -match 'Nombre del cliente' -and $s.Panel -eq 'pnlFicha')
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Valores @{ 'cliente.nombre' = 'Cliente de prueba'; 'cliente.contacto' = '+56 9 1111 2222' }
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Valores ([ordered]@{ sintoma = 'Se calienta' })
    $s = Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'después: el diagnóstico ANTES, en ② Antes' ($s.Codigo -eq 'diagnostico_antes' -and $s.Panel -eq 'pnlMedicion' -and $s.Momento -eq 'antes')
    $diag = { param($Momento) $d = Join-Path (Join-Path $e.Ruta $at) $Momento; $null = New-Item -ItemType Directory -Force $d; Write-Texto "$d\diagnostico.json" '{"kit":{"generado":"2026-11-08 10:00:00"},"alertas":[],"datos":{}}' }
    $csv = {
        param($Ruta, [int]$Temp)
        $l = @('Date,Time,"CPU Package [°C]","Average Effective Clock [MHz]"')
        for ($i = 0; $i -lt 300; $i++) { $l += ('8.11.2026,10:{0}:{1}.000,{2}.0,3000.0' -f [int][math]::Floor($i * 2 / 60), (($i * 2) % 60), $Temp) }
        [IO.File]::WriteAllLines($Ruta, $l, (New-Object Text.UTF8Encoding($true)))
    }
    $cond = [ordered]@{ enchufado = 's'; plan = 'Equilibrado'; ventiladores = 'Auto'; superficie = 'Mesa'; temp_ambiente_c = '22'; carga_tipo = 'OCCT CPU'; carga_duracion_min = '10' }
    & $diag 'antes'
    Assert 'después: medir la temperatura ANTES' ((& $sig $at) -eq 'csv_antes')
    & $csv "$tmp\antes.csv" 90
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Momento antes -Ruta "$tmp\antes.csv"
    Assert 'después: las condiciones del ANTES' ((& $sig $at) -eq 'condiciones_antes')
    Set-CondicionesCalor -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Momento antes -Valores $cond
    $s = Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'después: el trabajo, en ③ Trabajo' ($s.Codigo -eq 'trabajo' -and $s.Panel -eq 'pnlTrabajo')
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Valores @{ trabajo_terminado = $true }
    $s = Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'después: el diagnóstico DESPUÉS' ($s.Codigo -eq 'diagnostico_despues' -and $s.Momento -eq 'despues' -and $s.Texto -match 'DESPUÉS')
    & $diag 'despues'
    Assert 'después: medir la temperatura DESPUÉS' ((& $sig $at) -eq 'csv_despues')
    & $csv "$tmp\despues.csv" 70
    $null = Import-SensoresMedicion -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Momento despues -Ruta "$tmp\despues.csv"
    Set-CondicionesCalor -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Momento despues -Valores $cond
    $s = Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'después: lo que falta para los informes' ($s.Codigo -eq 'ficha_informe' -and $s.Texto -match 'Paquete' -and $s.Texto -match 'Contacto del técnico')
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Valores ([ordered]@{ paquete = 'Mantención'; precio = '30000' })
    $script:Ctx.Config.tecnico.contacto = 'contacto de prueba'
    Assert 'después: generar los informes' ((& $sig $at) -eq 'informe')
    Write-Texto (Join-Path (Join-Path $e.Ruta $at) 'informe_cliente.html') '<html></html>'
    Assert 'después: entregar' ((& $sig $at) -eq 'entregar')
    Set-Ficha -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Valores @{ entregado = '2026-11-08' }
    $s = Get-SiguientePaso -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'entregada: recuerda sincronizar y no lleva a ningún panel' ($s.Codigo -eq 'entregada' -and -not $s.Panel)
    $e2 = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Revision'; Serie = 'FLU002'; SerieOriginal = 'FLU002'; Uuid = $null; PlacaSerie = $null })
    $at2 = New-Atencion -Expediente $e2
    Set-Ficha -Expediente (Read-Expediente $e2.Ruta) -Valores @{ 'cliente.nombre' = 'Otro'; 'cliente.contacto' = 'otro@ejemplo.cl' }
    Set-Ficha -Expediente (Read-Expediente $e2.Ruta) -Atencion $at2 -Valores ([ordered]@{ motivos = 'REVISION'; sintoma = 'Revisión' })
    $d2 = Join-Path (Join-Path $e2.Ruta $at2) 'antes'; $null = New-Item -ItemType Directory -Force $d2; Write-Texto "$d2\diagnostico.json" '{"kit":{},"alertas":[],"datos":{}}'
    Assert 'sin CALOR no pide CSV: pasa al trabajo' ((Get-SiguientePaso -Expediente (Read-Expediente $e2.Ruta) -Atencion $at2).Codigo -eq 'trabajo')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
