#Requires -Version 5.1
<#
.SYNOPSIS
    Fase M: revisión de OneDrive, reinicio pendiente por actualización, LENTO ampliado (apps de la Store,
    Edge/Teams/OneDrive, acciones manuales nuevas) y su paso al informe visual y la hoja técnica.
.DESCRIPTION
    Datos sintéticos. Lo único que se escribe en el registro es una tarea de inicio de la Store inventada
    (HKCU\...\SystemAppData\KitPrueba.Paquete_*), que esta misma prueba crea y borra.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe', 'InformeVisual') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'motivos\lento.ps1')
foreach ($s in '03_windows', '11_espacio') { . (Join-Path $scripts "secciones\$s.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
function Get-AlertasDe { param([string]$Codigo) @($script:Ctx.Alertas | Where-Object Codigo -EQ $Codigo) }

function New-OneDrivePrueba {
    param([string]$Tipo = 'Personal', [double]$TotalGB = 2, [object[]]$Duplicadas = @(), [object[]]$Locales = @())
    [pscustomobject][ordered]@{
        Vinculado = $true; EnEjecucion = $true
        Cuentas = @([pscustomobject]@{ Cuenta = $(if ($Tipo -eq 'Personal') { 'Personal' } else { 'Business1' }); Tipo = $Tipo; Carpeta = 'C:\Users\<U1>\OneDrive'; Existe = $true })
        Respaldadas = @([pscustomobject]@{ Carpeta = 'Escritorio'; Ruta = 'C:\Users\<U1>\OneDrive\Escritorio' }, [pscustomobject]@{ Carpeta = 'Documentos'; Ruta = 'C:\Users\<U1>\OneDrive\Documentos' })
        Duplicadas = $Duplicadas; CopiasLocales = $Locales
        Recorrido = [pscustomobject]@{ Completo = $true; Segundos = 1.2; Archivos = 1500; TotalGB = $TotalGB; SoloNubeGB = 0.5; LocalGB = $TotalGB - 0.5; Conflictos = 3 }
    }
}

$tmp = Join-Path $env:TEMP ('kit_prueba_M_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$clientesReales = $script:Ctx.CarpetaClientes
$script:Ctx.CarpetaClientes = $tmp
$paquete = 'KitPrueba.Paquete_' + [guid]::NewGuid().ToString('N').Substring(0, 13)
$rutaStore = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$paquete"
try {
    '== Reinicio pendiente (lee el equipo, solo lectura)'
    $r = Get-ReinicioPendiente
    Assert 'devuelve si hay reinicio pendiente y de dónde' ($r -and $r.Pendiente -is [bool] -and $r.WindowsUpdate -is [bool] -and $r.Componentes -is [bool])

    '== OneDrive en este equipo (solo lectura)'
    $od = Get-OneDriveKit
    Assert 'responde si está vinculado' ($od -and $od.Vinculado -is [bool])
    Assert 'nunca guarda el correo de la cuenta' (($od | ConvertTo-Json -Depth 5) -notmatch '@')
    Assert 'sin -Recorrer no recorre' ($null -eq $od.Recorrido)

    '== Alertas de OneDrive'
    $script:Ctx.Alertas.Clear()
    Test-AlertasOneDrive -OneDrive (New-OneDrivePrueba -TotalGB 12.4)
    Assert 'personal sobre 5 GB: aviso de respaldo lleno' (@(Get-AlertasDe 'ESP-ONEDRIVE').Count -eq 1 -and @(Get-AlertasDe 'ESP-ONEDRIVE')[0].Severidad -eq 'AVISO')
    Assert 'el aviso dice qué carpetas respalda' (@(Get-AlertasDe 'ESP-ONEDRIVE')[0].Texto -match 'Escritorio, Documentos')
    Assert 'conflictos como info' (@(Get-AlertasDe 'ESP-ONEDRIVE-CONFLICTOS').Count -eq 1)
    $script:Ctx.Alertas.Clear()
    Test-AlertasOneDrive -OneDrive (New-OneDrivePrueba -Tipo 'Empresa o colegio' -TotalGB 40)
    Assert 'cuenta de empresa: sin aviso de 5 GB' (@(Get-AlertasDe 'ESP-ONEDRIVE').Count -eq 0)
    $script:Ctx.Alertas.Clear()
    Test-AlertasOneDrive -OneDrive (New-OneDrivePrueba -Duplicadas @([pscustomobject]@{ Raiz = 'x'; Carpetas = 'Documents y Documentos'; Motivo = 'm' }) -Locales @([pscustomobject]@{ Carpeta = 'Escritorio'; Ruta = 'x'; Archivos = 7 }))
    Assert 'repetidas y copias locales como info' (@(Get-AlertasDe 'ESP-ONEDRIVE-DUP').Count -eq 1 -and @(Get-AlertasDe 'ESP-ONEDRIVE-LOCAL').Count -eq 1 -and @(Get-AlertasDe 'ESP-ONEDRIVE-LOCAL')[0].Texto -match '7 archivos')
    $script:Ctx.Alertas.Clear()
    Test-AlertasOneDrive -OneDrive (New-OneDrivePrueba -Locales @([pscustomobject]@{ Carpeta = 'Documentos'; Ruta = 'C:\Users\<U1>\Documents'; Archivos = 5400; GB = 102.7; Completo = $true }))
    $loc = @(@(Get-AlertasDe 'ESP-ONEDRIVE-LOCAL'))
    Assert 'carpeta local antigua con GB: aviso con el tamaño' ($loc.Count -eq 1 -and $loc[0].Severidad -eq 'AVISO' -and $loc[0].Texto -match '102,7 GB') "$($loc.Texto)"

    '== Medir una carpeta con subcarpetas'
    $med = Join-Path $tmp 'medir'
    $null = New-Item -ItemType Directory (Join-Path $med 'a\b') -Force
    [IO.File]::WriteAllBytes((Join-Path $med 'uno.bin'), (New-Object byte[] 1000))
    [IO.File]::WriteAllBytes((Join-Path $med 'a\b\dos.bin'), (New-Object byte[] 3000))
    [IO.File]::WriteAllText((Join-Path $med 'desktop.ini'), 'x')
    $m = Measure-CarpetaKit -Ruta $med -LimiteSeg 10
    Assert 'cuenta subcarpetas y no desktop.ini' ($m.Archivos -eq 2 -and $m.Bytes -eq 4000 -and $m.Completo)

    $script:Ctx.Alertas.Clear()
    Test-AlertasOneDrive -OneDrive ([pscustomobject]@{ Vinculado = $false })
    Assert 'sin OneDrive: sin alertas' ($script:Ctx.Alertas.Count -eq 0)

    '== LENTO ampliado'
    $doc = [ordered]@{
        alertas = @(
            [pscustomobject]@{ Severidad = 'AVISO'; Codigo = 'WIN-REINICIO'; Seccion = '03'; Texto = 'Windows tiene una actualización a medias esperando reinicio' },
            [pscustomobject]@{ Severidad = 'AVISO'; Codigo = 'ESP-ONEDRIVE'; Seccion = '11'; Texto = 'OneDrive personal guarda 12 GB' })
        datos   = [ordered]@{
            seguridad = [ordered]@{ Antivirus = @() }
            arranque  = [ordered]@{
                Entradas  = @(
                    [pscustomobject]@{ Nombre = 'MicrosoftEdgeAutoLaunch_ABC'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Comando = 'msedge.exe --no-startup-window'; Ejecutable = 'msedge.exe'; Existe = $true; Empresa = 'Microsoft Corporation' },
                    [pscustomobject]@{ Nombre = 'OneDrive'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Comando = 'OneDrive.exe /background'; Ejecutable = 'OneDrive.exe'; Existe = $true; Empresa = 'Microsoft Corporation' },
                    [pscustomobject]@{ Nombre = 'SecurityHealth'; Ubicacion = 'HKLM\Run'; Habilitado = $true; Comando = 'SecurityHealthSystray.exe'; Ejecutable = 'x'; Existe = $true; Empresa = 'Microsoft Corporation' },
                    [pscustomobject]@{ Nombre = 'OtraCosaDeMicrosoft'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Comando = 'x.exe'; Ejecutable = 'x.exe'; Existe = $true; Empresa = 'Microsoft Corporation' },
                    [pscustomobject]@{ Nombre = 'btweb'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Comando = 'btweb.exe'; Ejecutable = 'btweb.exe'; Existe = $true; Empresa = 'BitTorrent Limited' })
                AppsStore = @(
                    [pscustomobject]@{ Nombre = 'TeamsTfwStartupTask'; Ubicacion = 'Store: MSTeams'; Habilitado = $true; Comando = 'MSTeams_8wekyb3d8bbwe' },
                    [pscustomobject]@{ Nombre = 'Xbox.App.Tasks'; Ubicacion = 'Store: Microsoft.GamingApp'; Habilitado = $false; Comando = 'Microsoft.GamingApp_8wekyb3d8bbwe' },
                    [pscustomobject]@{ Nombre = 'launcherrsxruntimeTask'; Ubicacion = 'Store: AdvancedMicroDevicesInc-2.AMDRadeonSoftware'; Habilitado = $true; Comando = 'AdvancedMicroDevicesInc-2.AMDRadeonSoftware_0a9344xs7nr4m' })
                Servicios = [ordered]@{ Terceros = @() }; Tareas = @()
            }
            energia   = $null; espacio = [ordered]@{ Volumenes = @() }; gpu_apps = $null; software = [ordered]@{ Detectados = @() }
        }
    }
    $exp = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Fase M'; Serie = 'FASEM001'; SerieOriginal = 'FASEM001'; Uuid = $null; PlacaSerie = $null })
    $at = New-Atencion -Expediente $exp
    $antes = Join-Path (Join-Path $exp.Ruta $at) 'antes'
    $null = [IO.Directory]::CreateDirectory($antes)
    [IO.File]::WriteAllText((Join-Path $antes 'diagnostico.json'), ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
    $acc = @(Get-AccionesLento -Expediente $exp -Atencion $at)
    $tit = ($acc | ForEach-Object Titulo) -join ' | '
    Assert 'ofrece Edge al inicio, riesgo bajo' (@($acc | Where-Object { $_.Tipo -eq 'inicio' -and $_.Titulo -match 'MicrosoftEdgeAutoLaunch' -and $_.Riesgo -eq 'bajo' }).Count -eq 1) $tit
    Assert 'ofrece OneDrive marcado revisar' (@($acc | Where-Object { $_.Tipo -eq 'inicio' -and $_.Titulo -match 'OneDrive' -and $_.Riesgo -eq 'revisar' }).Count -eq 1) $tit
    Assert 'no ofrece Seguridad de Windows ni otras cosas de Microsoft' (@($acc | Where-Object { $_.Titulo -match 'SecurityHealth|OtraCosaDeMicrosoft' }).Count -eq 0) $tit
    Assert 'ofrece Teams de la Store' (@($acc | Where-Object { $_.Tipo -eq 'inicio_store' -and $_.Titulo -match 'Microsoft Teams' -and $_.Datos.Paquete -eq 'MSTeams_8wekyb3d8bbwe' }).Count -eq 1) $tit
    Assert 'no ofrece apps de la Store ya deshabilitadas' (@($acc | Where-Object { $_.Titulo -match 'Xbox' }).Count -eq 0)
    Assert 'AMD de la Store marcado revisar' (@($acc | Where-Object { $_.Tipo -eq 'inicio_store' -and $_.Titulo -match 'AMD' -and $_.Riesgo -eq 'revisar' }).Count -eq 1)
    Assert 'acción manual: reiniciar por la actualización' (@($acc | Where-Object { $_.Tipo -eq 'manual' -and $_.QueHace -match 'Reiniciar' }).Count -eq 1)
    Assert 'acción manual: OneDrive con el cliente' (@($acc | Where-Object { $_.Tipo -eq 'manual' -and $_.QueHace -match 'OneDrive' }).Count -eq 1)

    '== Aplicar y deshacer una app de la Store (tarea inventada en HKCU)'
    $null = New-Item -Path "$rutaStore\KitTarea" -Force
    New-ItemProperty -Path "$rutaStore\KitTarea" -Name 'State' -Value 2 -PropertyType DWord -Force | Out-Null
    $accion = ConvertTo-AccionLento -Id "store|$paquete|KitTarea" -Tipo 'inicio_store' -Titulo 'prueba' -QueHace '' -Deshacer '' -Admin $false -Datos ([ordered]@{ Paquete = $paquete; Tarea = 'KitTarea' })
    $deshacer = Invoke-CambioLento -Accion $accion
    Assert 'queda deshabilitada por el usuario (State 1)' ((Get-ItemProperty "$rutaStore\KitTarea").State -eq 1 -and $deshacer.previo -eq 2)
    Undo-CambioLento -Registro ([ordered]@{ tipo = 'inicio_store'; datos = [ordered]@{ Paquete = $paquete; Tarea = 'KitTarea' }; deshacer = $deshacer })
    Assert 'deshacer la deja como estaba (State 2)' ((Get-ItemProperty "$rutaStore\KitTarea").State -eq 2)
    $falla = $null
    try { $null = Invoke-CambioLento -Accion (ConvertTo-AccionLento -Id 'x' -Tipo 'inicio_store' -Titulo '' -QueHace '' -Deshacer '' -Admin $false -Datos ([ordered]@{ Paquete = $paquete; Tarea = 'NoExiste' })) } catch { $falla = $_.Exception.Message }
    Assert 'una tarea que no existe no se crea' ($falla -match 'No existe' -and -not (Test-Path "$rutaStore\NoExiste"))

    '== Informe visual y hoja técnica'
    $docV = [pscustomobject]@{
        kit = [pscustomobject]@{ generado = '2026-11-19 16:00:00' }; alertas = @(); mejoras = @()
        datos = [pscustomobject]@{
            equipo = [pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Prueba'; NombreEquipo = 'PC'; Serie = 'X' }
            windows = [pscustomobject]@{ Reinicio = [pscustomobject]@{ Pendiente = $true; WindowsUpdate = $true; Componentes = $false } }
            espacio = [pscustomobject]@{ Volumenes = @(); TopCarpetas = @(); OneDrive = (New-OneDrivePrueba -TotalGB 12.4 -Duplicadas @([pscustomobject]@{ Raiz = 'x'; Carpetas = 'Documents y Documentos'; Motivo = 'm' })) }
            arranque = [pscustomobject]@{ Entradas = @(); AppsStore = @() }; dispositivos = [pscustomobject]@{ ConError = @() }; estabilidad = $null; energia = $null
        }
    }
    $sv = @(Get-ServiciosCliente -Doc $docV)
    $opt = $sv | Where-Object Titulo -EQ 'Optimización de Windows'
    Assert 'optimización con OneDrive lleno, repetidas y reinicio' ($opt -and (@($opt.Hallazgos) -join ' ') -match '12,4 GB' -and (@($opt.Hallazgos) -join ' ') -match 'repetidas' -and (@($opt.Hallazgos) -join ' ') -match 'reinicio') "$(@($opt.Hallazgos) -join ' | ')"
    Assert 'OneDrive lleno pesa como impacto alto' ($opt.Impacto -eq 3)
    $docV.datos.espacio.OneDrive = New-OneDrivePrueba -Locales @([pscustomobject]@{ Carpeta = 'Documentos'; Ruta = 'C:\Users\<U1>\Documents'; Archivos = 5400; GB = 102.7; Completo = $true })
    $optL = @(Get-ServiciosCliente -Doc $docV) | Where-Object Titulo -EQ 'Optimización de Windows'
    Assert 'el cliente ve los GB de las carpetas antiguas' ((@($optL.Hallazgos) -join ' ') -match '103 GB en carpetas antiguas \(Documentos\)') "$(@($optL.Hallazgos) -join ' | ')"
    $tec = [Net.WebUtility]::HtmlDecode((ConvertTo-HojaTecnica -Doc $docV))
    Assert 'hoja técnica con OneDrive y reinicio' ($tec -match '<h2>OneDrive</h2>' -and $tec -match 'Escritorio, Documentos' -and $tec -match 'Reinicio pendiente')
} finally {
    Remove-Item -Path $rutaStore -Recurse -Force -ErrorAction SilentlyContinue
    $script:Ctx.CarpetaClientes = $clientesReales
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"  limpieza: tarea de prueba en el registro = $(Test-Path $rutaStore)"
''
"Resultado: $script:ok OK, $script:fallas fallas ($($script:ok + $script:fallas) comprobaciones)"
if ($script:fallas) { exit 1 }
exit 0
