#Requires -Version 5.1
<#
.SYNOPSIS
    Fase K (negocio): catálogo de packs (config.json) con precios privados (config_local.json), elegir el pack por
    número, precio de cada servicio y total en el informe visual, y remoto\armar_envios.ps1 (carpetas por pack).
.DESCRIPTION
    Los precios se ponen en memoria (no lee ni toca el config_local.json real). Las carpetas van a %TEMP%.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $repo 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Sensores', 'Mejoras', 'Informe', 'InformeVisual') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
function Set-PreciosPrueba {
    param($Precios)
    $cfg = $script:Ctx.Config
    if ($cfg.PSObject.Properties['precios']) { $cfg.PSObject.Properties.Remove('precios') }
    if ($Precios) { $cfg | Add-Member -NotePropertyName precios -NotePropertyValue ([pscustomobject]$Precios) }
}
$tmp = Join-Path $env:TEMP ('kit_prueba_K_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
try {
    '== Catálogo sin precios (como en GitHub)'
    Set-PreciosPrueba $null
    $cat = @(Get-CatalogoPaquetes)
    Assert '8 packs en orden' ($cat.Count -eq 8 -and (($cat | ForEach-Object Numero) -join ',') -eq '1,2,3,4,5,6,7,8')
    Assert 'cada pack dice qué hace' (@($cat | Where-Object { -not $_.Resumen -or @($_.QueHace).Count -lt 2 -or -not $_.Modo }).Count -eq 0)
    Assert 'sin precios: a convenir' ((Format-PrecioPaquete $cat[0]) -eq 'a convenir')
    Assert 'el repo no trae precios' ($null -eq (Get-Content (Join-Path $scripts 'config\config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties['precios'])

    '== Con precios'
    Set-PreciosPrueba ([ordered]@{ diagnostico_remoto = 10000; asesoria_compra = 5000; optimizacion_remota = 15000; optimizacion_presencial = 20000; mantencion_termica = 25000; instalacion_ssd = 15000; instalacion_simple = 10000; revision_anual = 0 })
    Assert 'precio con miles' ((Format-PrecioPaquete (Get-PaqueteCatalogo -Id 'diagnostico_remoto')) -eq '$10.000')
    Assert 'cero = sin costo' ((Format-PrecioPaquete (Get-PaqueteCatalogo -Id 'revision_anual')) -eq 'sin costo')
    Assert 'instalación: + la pieza' ((Format-PrecioPaquete (Get-PaqueteCatalogo -Id 'instalacion_ssd')) -eq '$15.000 + la pieza')
    Assert 'el número elige el pack' ((Resolve-PaqueteTexto '5').Id -eq 'mantencion_termica' -and (Resolve-PaqueteTexto ' 3 ').Precio -eq 15000)
    Assert 'el id o el nombre también' ((Resolve-PaqueteTexto 'asesoria_compra').Numero -eq 2 -and (Resolve-PaqueteTexto 'mantención térmica').Numero -eq 5)
    Assert 'texto libre no calza' ($null -eq (Resolve-PaqueteTexto 'cambio de pantalla') -and $null -eq (Resolve-PaqueteTexto '99'))
    $lineas = @(Format-CatalogoTexto)
    Assert 'lista para la consola' ($lineas.Count -eq 8 -and $lineas[0] -match '1\) Diagnóstico a distancia .*\$10\.000$')

    '== Precios en el informe visual'
    $doc = [pscustomobject]@{
        kit = [pscustomobject]@{ generado = '2026-11-19 16:00:00' }; alertas = @()
        mejoras = @([pscustomobject]@{ Codigo = 'MEJ-SSD-GRANDE'; Prioridad = 'Media'; Titulo = 'SSD de más capacidad'; Motivo = 'm'; Comprar = 'c'; Beneficio = 'b' })
        datos = [pscustomobject]@{
            equipo = [pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Prueba'; NombreEquipo = 'PC' }
            windows = [pscustomobject]@{ Reinicio = [pscustomobject]@{ Pendiente = $true } }
            espacio = [pscustomobject]@{ Volumenes = @(); TopCarpetas = @() }
            arranque = [pscustomobject]@{ Entradas = @(); AppsStore = @() }; dispositivos = [pscustomobject]@{ ConError = @() }; estabilidad = $null; energia = $null
        }
    }
    $sv = @(Get-ServiciosCliente -Doc $doc -Origen 'remoto')
    Assert 'optimización a distancia con su pack' (@($sv | Where-Object { $_.Titulo -eq 'Optimización de Windows' -and $_.Pack.Id -eq 'optimizacion_remota' }).Count -eq 1)
    Assert 'presencial con el pack presencial' (@(Get-ServiciosCliente -Doc $doc -Origen 'kit' | Where-Object { $_.Pack.Id -eq 'optimizacion_presencial' }).Count -eq 1)
    Assert 'SSD con el pack de instalación' (@($sv | Where-Object { $_.Pack.Id -eq 'instalacion_ssd' }).Count -eq 1)
    $html = [Net.WebUtility]::HtmlDecode((ConvertTo-InformeVisual -Doc $doc -Origen 'remoto'))
    Assert 'cada servicio con su precio y el total' ($html -match '\$15\.000 \+ la pieza' -and $html -match 'Todo lo propuesto' -and $html -match '\$30\.000') ([regex]::Match($html, 'Todo lo propuesto.{0,300}').Value)
    Assert 'aviso de descuento del diagnóstico' ($html -match 'se descuenta del total')
    Set-PreciosPrueba $null
    $html2 = [Net.WebUtility]::HtmlDecode((ConvertTo-InformeVisual -Doc $doc -Origen 'remoto'))
    Assert 'sin precios configurados: sin montos' ($html2 -notmatch 'Todo lo propuesto' -and $html2 -notmatch '\$15\.000')

    '== Carpetas para enviar'
    $zip = Join-Path $tmp 'Diagnostico_remoto_prueba.zip'
    [IO.File]::WriteAllBytes($zip, [byte[]](1..200))
    $sal = Join-Path $tmp 'Para_enviar'
    $null = & (Join-Path $repo 'remoto\armar_envios.ps1') -Salida $sal -ZipDiagnostico $zip 6>$null
    $dirs = @(Get-ChildItem $sal -Directory | ForEach-Object Name)
    Assert 'una carpeta por pack, sin tildes' ($dirs.Count -eq 8 -and $dirs[0] -eq '01_Diagnostico_a_distancia' -and @($dirs | Where-Object { $_ -notmatch '^\d\d_[A-Za-z0-9_]+$' }).Count -eq 0) ($dirs -join ', ')
    Assert 'en cada una QUE_HACE.txt y MENSAJE_WHATSAPP.txt' (@($dirs | Where-Object { -not (Test-Path (Join-Path $sal "$_\QUE_HACE.txt")) -or -not (Test-Path (Join-Path $sal "$_\MENSAJE_WHATSAPP.txt")) }).Count -eq 0)
    Assert 'el ZIP del diagnóstico en los packs que lo usan' ((Test-Path (Join-Path $sal "01_Diagnostico_a_distancia\$(Split-Path -Leaf $zip)")) -and (Test-Path (Join-Path $sal "08_Revision_anual\$(Split-Path -Leaf $zip)")) -and -not (Test-Path (Join-Path $sal "02_Asesoria_de_compra\$(Split-Path -Leaf $zip)")))
    $qh = [IO.File]::ReadAllText((Join-Path $sal '01_Diagnostico_a_distancia\QUE_HACE.txt'), [Text.Encoding]::UTF8)
    Assert 'QUE_HACE explica qué hace, qué no y cómo se usa' ($qh -match 'QUÉ SE HACE' -and $qh -match 'QUÉ NO SE HACE' -and $qh -match 'CÓMO SE USA' -and $qh -match 'SOLO LEE')
    Assert 'pasos para Isaac en el trabajo a distancia' ([IO.File]::ReadAllText((Join-Path $sal '03_Optimizacion_a_distancia\PASOS_ISAAC.txt'), [Text.Encoding]::UTF8) -match 'ARMAR_TRABAJO')
    Assert 'índice para Isaac' ([IO.File]::ReadAllText((Join-Path $sal 'LEEME_ISAAC.txt'), [Text.Encoding]::UTF8) -match 'Mandar:')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas ($($script:ok + $script:fallas) comprobaciones)"
if ($script:fallas) { exit 1 }
exit 0
