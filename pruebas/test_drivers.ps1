#Requires -Version 5.1
<#
.SYNOPSIS
    Placa madre en la ficha, modelo de PC armado y links a drivers oficiales (lib\Drivers.ps1).
.DESCRIPTION
    Con expedientes sintéticos en una carpeta temporal y un Get-Cim falso para simular equipos. No abre el
    navegador ni se conecta a internet: solo revisa los links que arma el kit.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente', 'Informe', 'Drivers') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_drv_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$script:Ctx.CarpetaClientes = Join-Path $tmp 'clientes'
$utf8 = New-Object Text.UTF8Encoding($false)

# Equipo simulado para Get-IdentidadEquipo: reemplaza al Get-Cim del kit en esta batería.
$script:Falso = $null
function Get-Cim {
    param([string]$Clase, [string[]]$Propiedades, [string]$Filtro)
    $null = $Propiedades, $Filtro
    $script:Falso[$Clase]
}
function Set-EquipoFalso([string]$Fab, [string]$Modelo, [string]$Serie, [string]$PlacaFab, [string]$PlacaProd, [string]$Version = '', [string]$Uuid = '11112222-3333-4444-5555-666677778888') {
    $script:Falso = @{
        Win32_ComputerSystem        = [pscustomobject]@{ Manufacturer = $Fab; Model = $Modelo }
        Win32_BIOS                  = [pscustomobject]@{ SerialNumber = $Serie }
        Win32_ComputerSystemProduct = [pscustomobject]@{ Version = $Version; UUID = $Uuid }
        Win32_BaseBoard             = [pscustomobject]@{ Manufacturer = $PlacaFab; Product = $PlacaProd; SerialNumber = 'PLACA-0001' }
    }
}
function Write-Diag {
    param($Exp, [string]$At, [object[]]$Gpu, [object[]]$Disp)
    $dir = Join-Path (Join-Path $Exp.Ruta $At) 'antes'
    $null = New-Item -ItemType Directory -Force $dir
    $json = [ordered]@{ kit = @{ generado = '2026-11-08 10:00:00' }; alertas = @(); datos = [ordered]@{ hardware = @{ Gpu = $Gpu }; dispositivos = @{ ConError = $Disp } } } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $dir 'diagnostico.json'), $json, $utf8)
}
function New-ExpPrueba([string]$Fab, [string]$Modelo, [string]$Serie, [string]$Tipo = 'Notebook', [string]$Placa = $null) {
    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = $Fab; Modelo = $Modelo; Serie = $Serie; SerieOriginal = $Serie; Uuid = $null; PlacaSerie = $null })
    $x = Read-Expediente $e.Ruta; $x.Ficha['equipo']['tipo'] = $Tipo; $x.Ficha['equipo']['placa'] = $Placa; Save-Ficha -Expediente $x
    $at = New-Atencion -Expediente (Read-Expediente $e.Ruta)
    [pscustomobject]@{ Ruta = $e.Ruta; At = $at }
}

try {
    '== Equipo y placa madre'
    Assert 'reconoce los rellenos de los PC armados' ((Test-ValorGenerico 'System Product Name') -and (Test-ValorGenerico 'System manufacturer') -and (Test-ValorGenerico 'To Be Filled By O.E.M.') -and (Test-ValorGenerico 'System Version') -and -not (Test-ValorGenerico 'Inspiron 3493') -and -not (Test-ValorGenerico 'PRIME B450M-A'))
    Assert 'nombres cortos de fabricantes de placas' ((ConvertTo-FabricanteCorto 'ASRock') -eq 'ASRock' -and (ConvertTo-FabricanteCorto 'ASUSTeK COMPUTER INC.') -eq 'ASUS' -and (ConvertTo-FabricanteCorto 'Micro-Star International Co., Ltd.') -eq 'MSI' -and (ConvertTo-FabricanteCorto 'System manufacturer') -eq 'Generico')
    Set-EquipoFalso 'System manufacturer' 'System Product Name' 'System Serial Number' 'ASUSTeK COMPUTER INC.' 'PRIME B450M-A'
    $i = Get-IdentidadEquipo
    Assert 'PC armado: el modelo sale de la placa madre' ($i.Fabricante -eq 'ASUS' -and $i.Modelo -eq 'PRIME B450M-A' -and $i.ModeloEsPlaca -and $i.Serie -eq '') -D "$($i.Fabricante) | $($i.Modelo) | $($i.Serie)"
    Set-EquipoFalso 'Dell Inc.' 'Inspiron 3493' 'ABC1234' 'Dell Inc.' '0XXXXX'
    $i = Get-IdentidadEquipo
    Assert 'notebook de marca: sigue con su modelo, no el de la placa' ($i.Fabricante -eq 'Dell' -and $i.Modelo -eq 'Inspiron 3493' -and -not $i.ModeloEsPlaca)
    Set-EquipoFalso 'LENOVO' '82H8' 'PF2ABCDE' 'LENOVO' 'LNVNB161216' 'IdeaPad 3 15ITL6'
    Assert 'Lenovo: sigue con el nombre comercial' ((Get-IdentidadEquipo).Modelo -eq 'IdeaPad 3 15ITL6')
    Set-EquipoFalso 'To Be Filled By O.E.M.' 'To Be Filled By O.E.M.' 'To Be Filled By O.E.M.' 'ASRock' 'To Be Filled By O.E.M.'
    Assert 'si la placa tampoco dice modelo, queda Generico' ((Get-IdentidadEquipo).Modelo -eq 'Generico')
    # Un PC armado que ya tenía expediente como Generico se sigue encontrando (por el UUID).
    $viejo = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Generico'; Modelo = 'Generico'; Serie = ''; SerieOriginal = 'System Serial Number'; Uuid = '11112222-3333-4444-5555-666677778888'; PlacaSerie = 'PLACA-0001' })
    Set-EquipoFalso 'System manufacturer' 'System Product Name' 'System Serial Number' 'ASUSTeK COMPUTER INC.' 'PRIME B450M-A'
    $hallado = Get-Expediente -Identidad (Get-IdentidadEquipo)
    Assert 'el expediente anterior (Generico) se sigue encontrando con el modelo nuevo' ($hallado -and $hallado.Id -eq $viejo.Id) -D "$($hallado.Id) / $($viejo.Id)"
    $p = New-ExpPrueba 'ASUS' 'PRIME B450M-A' '' 'Escritorio'
    $x = Read-Expediente $p.Ruta
    Update-FichaDesdeDiagnostico -Expediente $x -Atencion $p.At -Momento 'antes' -Datos ([pscustomobject]@{ equipo = [pscustomobject]@{ Tipo = 'Escritorio'; BiosVersion = '3604'; BiosFecha = '2024-05-01'; PlacaBase = 'ASUSTeK COMPUTER INC. PRIME B450M-A' } }) -Generado '2026-11-08 10:00:00' -Admin $true -Alertas @()
    Assert 'la placa madre queda en la ficha' ((Read-Expediente $p.Ruta).Ficha['equipo']['placa'] -eq 'ASUSTeK COMPUTER INC. PRIME B450M-A')
    Assert 'los expedientes nuevos traen el campo placa' ((Read-Expediente $viejo.Ruta).Ficha['equipo'].Contains('placa'))

    '== Texto para buscar un dispositivo'
    $casos = [ordered]@{
        'PCI\VEN_8086&DEV_02F9&SUBSYS_00011028&REV_00\3&11583659&0&A0' = 'VEN_8086&DEV_02F9'
        'HDAUDIO\FUNC_01&VEN_10EC&DEV_0256&SUBSYS_10280978&REV_1000\4&1' = 'VEN_10EC&DEV_0256'
        'USB\VID_0BDA&PID_B023\00E04C000001' = 'VID_0BDA&PID_B023'
        'ACPI\INT33A1\1' = 'INT33A1'
        'ACPI\VEN_INT&DEV_33A1\0' = 'INT33A1'
    }
    $mal = @(foreach ($k in $casos.Keys) { $r = Get-TextoBusquedaHardware -Id $k -Nombre 'x'; if ($r -ne $casos[$k]) { "$k -> $r" } })
    Assert 'saca VEN/DEV, VID/PID o el ID de ACPI' ($mal.Count -eq 0) -D ($mal -join '; ')
    Assert 'un dispositivo de software se busca por el nombre' ((Get-TextoBusquedaHardware -Id 'SWD\DRIVERENUM\{5b2b1c0e}#WAVES&1' -Nombre 'Waves Audio Effects Component') -eq 'Waves Audio Effects Component')

    '== Links de un notebook de marca (Dell)'
    $d = New-ExpPrueba 'Dell' 'Inspiron 3493' 'ABC1234'
    Write-Diag -Exp (Read-Expediente $d.Ruta) -At $d.At -Gpu @([ordered]@{ Nombre = 'Intel(R) UHD Graphics'; Fabricante = 'Intel'; DriverFecha = '2023-11-13'; DriverGenerico = $false }) -Disp @(
        [ordered]@{ Dispositivo = 'Controlador de comunicaciones'; Codigo = 28; Problema = 'Sin driver'; Id = 'PCI\VEN_8086&DEV_02E0&SUBSYS_00011028&REV_00\3&1&0&90' },
        [ordered]@{ Dispositivo = 'Cámara'; Codigo = 22; Problema = 'Deshabilitado'; Id = 'USB\VID_0C45&PID_6A10\1' })
    $l = @(Get-LinksDrivers -Expediente (Read-Expediente $d.Ruta) -Atencion $d.At)
    $tipos = ($l | ForEach-Object { $_.Tipo }) -join ','
    Assert 'orden: Windows Update, fabricante, video y dispositivos con error' ($tipos -eq 'windows,fabricante,video,dispositivo') -D $tipos
    Assert 'Windows Update abre las actualizaciones opcionales' ($l[0].Url -eq 'ms-settings:windowsupdate-optionalupdates')
    Assert 'página oficial de Dell Chile y copia la serie' ($l[1].Url -eq 'https://www.dell.com/support/home/es-cl' -and $l[1].Copiar -eq 'ABC1234' -and $l[1].Nota -match 'Se copia la serie')
    Assert 'video: dice de cuándo es el driver y copia el nombre' ($l[2].Titulo -match 'Intel\(R\) UHD Graphics \(driver del 2023-11-13\)' -and $l[2].Url -like 'https://www.intel.la/*' -and $l[2].Copiar -eq 'Intel(R) UHD Graphics')
    Assert 'sin driver: búsqueda en el catálogo de Microsoft Update, y no los deshabilitados a mano' ($l[3].Url -eq 'https://www.catalog.update.microsoft.com/Search.aspx?q=VEN_8086%26DEV_02E0' -and $l[3].Copiar -eq 'VEN_8086&DEV_02E0' -and @($l | Where-Object { $_.Titulo -match 'Cámara' }).Count -eq 0) -D $l[3].Url
    Assert 'en consulta se puede omitir Windows Update' (@(Get-LinksDrivers -Expediente (Read-Expediente $d.Ruta) -Atencion $d.At -SinWindowsUpdate)[0].Tipo -eq 'fabricante')

    '== Otros equipos'
    $a = New-ExpPrueba 'ASUS' 'VivoBook_ASUSLaptop X512DA_X512DA' 'K1N0CV12345678A'
    $la = @(Get-LinksDrivers -Expediente (Read-Expediente $a.Ruta) -Atencion $a.At)
    Assert 'ASUS se busca por modelo, no por serie' ($la[1].Url -like 'https://www.asus.com/cl/*' -and $la[1].Copiar -eq 'VivoBook_ASUSLaptop X512DA_X512DA' -and $la[1].Nota -match 'Se copia el modelo')
    $s = New-ExpPrueba 'Dell' 'Inspiron 3493' ''
    Assert 'sin serie, copia el modelo aunque el fabricante busque por serie' (@(Get-LinksDrivers -Expediente (Read-Expediente $s.Ruta) -Atencion $s.At)[1].Copiar -eq 'Inspiron 3493')
    $g = New-ExpPrueba 'Generico' 'Generico' '' 'Escritorio' 'Micro-Star International Co., Ltd. B450M PRO-VDH MAX (MS-7A38)'
    $lg = @(Get-LinksDrivers -Expediente (Read-Expediente $g.Ruta) -Atencion $g.At)
    Assert 'PC armado registrado como Generico: usa la placa (MSI) y copia su modelo' ($lg[1].Url -eq 'https://www.msi.com/support/download' -and $lg[1].Copiar -eq 'B450M PRO-VDH MAX (MS-7A38)') -D "$($lg[1].Url) | $($lg[1].Copiar)"
    $r = New-ExpPrueba 'Generico' 'Generico' '' 'Escritorio' 'ASRock B450M Pro4'
    Assert 'placa ASRock sin "Inc." en el nombre' (@(Get-LinksDrivers -Expediente (Read-Expediente $r.Ruta) -Atencion $r.At)[1].Copiar -eq 'B450M Pro4')
    $u = New-ExpPrueba 'Positivo' 'Master N250i' 'XYZ'
    $lu = @(Get-LinksDrivers -Expediente (Read-Expediente $u.Ruta) -Atencion $u.At)
    Assert 'fabricante sin página conocida: lo dice y no inventa una dirección' ($null -eq $lu[1].Url -and $lu[1].Nota -match 'drivers\.json')
    $n = New-ExpPrueba 'Acer' 'Nitro AN515-43' 'NXQ0000000000000000000'
    Write-Diag -Exp (Read-Expediente $n.Ruta) -At $n.At -Gpu @(
        [ordered]@{ Nombre = 'Microsoft Basic Display Adapter'; Fabricante = 'NVIDIA'; DriverFecha = '2006-06-21'; DriverGenerico = $true },
        [ordered]@{ Nombre = 'AMD Radeon(TM) Vega 8 Graphics'; DriverFecha = '2020-07-14'; DriverGenerico = $false }) -Disp @()
    $ln = @(Get-LinksDrivers -Expediente (Read-Expediente $n.Ruta) -Atencion $n.At)
    $video = @($ln | Where-Object Tipo -eq 'video')
    Assert 'driver genérico: el fabricante sale del ID del hardware (NVIDIA)' ($video[0].Titulo -match 'driver genérico de Microsoft' -and $video[0].Url -like 'https://www.nvidia.com/*')
    Assert 'diagnóstico anterior sin fabricante de GPU: lo saca del nombre (AMD)' ($video[1].Url -like 'https://www.amd.com/*')
    Assert 'notebook con dos tarjetas de video: primero la página del fabricante' ($video[0].Nota -match 'dos tarjetas de video: primero el driver de la página de Acer')
    $waves = [ordered]@{ Dispositivo = 'Waves Audio Effects Component'; Codigo = 28; Problema = 'Sin driver'; Id = 'SWD\DRIVERENUM\{5B2B1C0E}#WAVES&1' }
    Write-Diag -Exp (Read-Expediente $n.Ruta) -At $n.At -Gpu @() -Disp @($waves)
    $sw = @(Get-LinksDrivers -Expediente (Read-Expediente $n.Ruta) -Atencion $n.At | Where-Object Tipo -eq 'dispositivo')
    Assert 'componente de software sin ID: lleva a la página del fabricante (driver de audio)' ($sw[0].Url -eq 'https://www.acer.com/cl-es/support' -and $sw[0].Nota -match 'casi siempre el de audio' -and $sw[0].Copiar -eq 'NXQ0000000000000000000')
    Write-Diag -Exp (Read-Expediente $u.Ruta) -At $u.At -Gpu @() -Disp @($waves)
    $sw2 = @(Get-LinksDrivers -Expediente (Read-Expediente $u.Ruta) -Atencion $u.At | Where-Object Tipo -eq 'dispositivo')
    Assert 'sin página del fabricante: catálogo con las dos primeras palabras' ($sw2[0].Url -like '*Search.aspx?q=Waves%20Audio' -and $sw2[0].Copiar -eq 'Waves Audio') -D $sw2[0].Url
    $sinDiag = New-ExpPrueba 'HP' 'HP Laptop 15-dw1xxx' '5CD0000000'
    $tiposSin = (@(Get-LinksDrivers -Expediente (Read-Expediente $sinDiag.Ruta) -Atencion $sinDiag.At) | ForEach-Object { $_.Tipo }) -join ','
    Assert 'sin diagnóstico: solo Windows Update y el fabricante' ($tiposSin -eq 'windows,fabricante') -D $tiposSin

    '== Configuración e informe'
    $cfg = Get-ConfigDrivers
    $urls = @($cfg.fabricantes.PSObject.Properties | ForEach-Object { $_.Value.url }) + @($cfg.gpu.PSObject.Properties | ForEach-Object { $_.Value.url }) + $cfg.catalogo.url
    Assert 'todas las páginas son https y cada fabricante dice qué copiar' (@($urls | Where-Object { $_ -notlike 'https://*' }).Count -eq 0 -and @($cfg.fabricantes.PSObject.Properties | Where-Object { $_.Value.copiar -notin 'serie', 'modelo' }).Count -eq 0)
    $bytes = [IO.File]::ReadAllBytes((Join-Path $scripts 'config\drivers.json'))
    Assert 'drivers.json sin BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
    $html = Get-HtmlDrivers -Links $l
    Assert 'tabla para el informe técnico con links a las páginas' ($html -match '<h2>Drivers' -and $html -match 'href="https://www.dell.com/support/home/es-cl"' -and $html -match 'VEN_8086&amp;DEV_02E0' -and $html -notmatch 'href="ms-settings')
    Assert 'sin links, no agrega la sección' ((Get-HtmlDrivers -Links @()) -eq '')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
