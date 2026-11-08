#Requires -Version 5.1
<#
.SYNOPSIS
    Arreglos que salieron en atenciones reales: punto de restauración bloqueado por Windows, el USB del
    kit entre los discos del cliente y la atención suelta del modo técnico.
.DESCRIPTION
    No cambia nada del equipo: Checkpoint-Computer, Get-ComputerRestorePoint y Get-Service se reemplazan
    por funciones falsas, y los expedientes van a una carpeta temporal que se borra al terminar.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Funciones falsas de prueba')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe') { . (Join-Path $scripts "lib\$lib.ps1") }
foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $scripts "motivos\$m.ps1") }
. (Join-Path $scripts 'secciones\02_hardware.ps1')
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$script:Ctx.Admin = Get-EstadoAdmin
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ('kit_prueba_terreno_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$null = New-Item -ItemType Directory $tmp
$script:Ctx.CarpetaClientes = Join-Path $tmp 'clientes'

# Reemplazos: tapan a los cmdlets reales mientras dura la prueba.
$script:InicioVss = 'Disabled'
$script:CheckpointFalla = $true
function Checkpoint-Computer { param($Description, $RestorePointType) if ($script:CheckpointFalla) { throw 'No se puede iniciar el servicio porque está deshabilitado o no tiene dispositivos habilitados asociados a él.' } }
function Get-ComputerRestorePoint { @() }
function Get-Service { param($Name) [pscustomobject]@{ Name = $Name; StartType = $script:InicioVss } }

try {
    '== Punto de restauración que Windows no deja crear'
    $script:Ctx.Admin = [pscustomobject]@{ Elevado = $true; MiembroAdministradores = $true }
    $msj = $null
    try { $null = Initialize-PuntoRestauracion } catch { $msj = $_.Exception.Message }
    Assert 'el error lleva la marca que reconocen la ventana y la consola' ("$msj".StartsWith($script:PrefijoSinPunto)) "salió: $msj"
    Assert 'explica que el servicio está deshabilitado' ("$msj" -match 'Instantáneas de volumen está deshabilitado')
    Assert 'incluye lo que dijo Windows' ("$msj" -match 'Windows dice: No se puede iniciar el servicio')
    $script:InicioVss = 'Manual'
    try { $null = Initialize-PuntoRestauracion } catch { $msj = $_.Exception.Message }
    Assert 'con el servicio normal, apunta a la Protección del sistema' ("$msj" -match 'Protección del sistema')
    $script:CheckpointFalla = $false
    try { $null = Initialize-PuntoRestauracion; $msj = '' } catch { $msj = $_.Exception.Message }
    Assert 'si Windows no crea nada sin fallar, también se marca' ("$msj".StartsWith($script:PrefijoSinPunto))
    $script:CheckpointFalla = $true

    $e = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Lento'; Serie = 'TER001'; SerieOriginal = 'TER001'; Uuid = $null; PlacaSerie = $null })
    $at = New-Atencion -Expediente $e
    $accion = [pscustomobject]@{ Id = 'prueba|1'; Tipo = 'inicio'; Titulo = 'Acción de prueba'; RequiereAdmin = $false; Riesgo = 'bajo'; QueHace = ''; Deshacer = ''; Datos = [ordered]@{} }
    $msj = $null
    try { $null = Invoke-AccionesLento -Expediente (Read-Expediente $e.Ruta) -Atencion $at -Acciones @($accion) } catch { $msj = $_.Exception.Message }
    $reg = Read-RegistroLento -Expediente (Read-Expediente $e.Ruta) -Atencion $at
    Assert 'aplicar se detiene con la marca' ("$msj".StartsWith($script:PrefijoSinPunto)) "salió: $msj"
    Assert 'no se aplicó ninguna acción' (@($reg['acciones'] | Where-Object { $_ }).Count -eq 0 -and -not $reg['punto_restauracion'])
    $tarea = [IO.File]::ReadAllText((Join-Path $scripts 'gui\tarea.ps1'))
    $ventana = [IO.File]::ReadAllText((Join-Path $scripts 'gui\kit.ps1'))
    Assert 'la tarea lo devuelve como resultado, no como error' ($tarea -match 'punto_fallo = \$msj\.Substring')
    Assert 'la ventana pregunta y reintenta sin punto' ($ventana -match 'if \(\$r\.punto_fallo\)' -and $ventana -match 'sin_punto = \$true')
    $script:Ctx.Admin = Get-EstadoAdmin

    '== El USB del kit no se avisa como disco del cliente'
    $script:Ctx.Alertas.Clear()
    $script:Ctx.SeccionActual = '02 Hardware'; $script:Ctx.SeccionNumero = 2
    $disco = { param([int]$N, [string]$Modelo, [string]$Letras, [bool]$DelKit) [pscustomobject]@{ Disco = $N; Modelo = $Modelo; Tipo = 'SSD'; Bus = 'USB'; TamanoGB = 58; Salud = 'Healthy'; EstadoOperativo = 'OK'; Firmware = ''; Letras = $Letras; Sistema = $false; DelKit = $DelKit; DesgastePct = $null; TemperaturaC = $null; TemperaturaMaxC = $null; Smart = 'no confiable (el controlador no entrega SMART a Windows)' } }
    $script:Ctx.Datos = [ordered]@{ hardware = [ordered]@{ Discos = @((& $disco 2 'Kingston DataTraveler 3.0' 'E' $true), (& $disco 3 'Caja USB del cliente' 'F' $false)); SmartCrystal = @(); DiscosTxt = $true } }
    Test-AlertasHardware
    $smart = @($script:Ctx.Alertas | Where-Object { $_.Codigo -eq 'HW-DISCO-SMART' })
    Assert 'no avisa del USB del kit' (@($smart | Where-Object { $_.Texto -match 'Kingston' }).Count -eq 0)
    Assert 'sí avisa del USB del cliente' (@($smart | Where-Object { $_.Texto -match 'Caja USB' }).Count -eq 1)
    Assert 'si CrystalDiskInfo corrió, no manda a revisarlo con él' (@($smart | Where-Object { $_.Texto -match 'ni Windows ni CrystalDiskInfo' }).Count -eq 1)
    $script:Ctx.Alertas.Clear()
    $script:Ctx.Datos.hardware['DiscosTxt'] = $false
    Test-AlertasHardware
    Assert 'sin CrystalDiskInfo, dice que con admin lo lee' (@($script:Ctx.Alertas | Where-Object { $_.Codigo -eq 'HW-DISCO-SMART' -and $_.Texto -match 'con admin' }).Count -eq 1)
    $resumen = (Format-ResumenHardware) -join "`n"
    Assert 'el resumen marca el USB del kit' ($resumen -match 'Kingston[^\n]*\(USB del kit\)')
    $script:Ctx.RaizKit = Join-Path $PSScriptRoot '..\KIT'
    $letra = ([IO.Path]::GetPathRoot((Resolve-Path $script:Ctx.RaizKit).Path)).Substring(0, 1)
    $script:Ctx.RaizKit = (Resolve-Path $script:Ctx.RaizKit).Path
    $reales = @(Get-DiscosKit)
    $marcados = @($reales | Where-Object { $_.DelKit })
    $discoKit = @($reales | Where-Object { ($_.Letras -split ' ') -contains $letra })
    Assert 'nunca marca el disco de Windows' (@($marcados | Where-Object { $_.Sistema }).Count -eq 0)
    if ($discoKit.Count -and -not $discoKit[0].Sistema) {
        Assert "en este PC marca solo el disco con $letra`:" ($marcados.Count -eq 1 -and ($marcados[0].Letras -split ' ') -contains $letra)
    } else {
        Assert "el kit está en el disco de Windows ($letra`:): no marca ninguno" ($marcados.Count -eq 0) "marcados: $(($marcados | ForEach-Object { "$($_.Disco)=$($_.Letras)" }) -join ', ')"
    }

    '== La atención suelta no se lleva la atención del día'
    $e2 = New-Expediente -Identidad ([pscustomobject]@{ Fabricante = 'Prueba'; Modelo = 'Suelta'; Serie = 'TER002'; SerieOriginal = 'TER002'; Uuid = $null; PlacaSerie = $null })
    $a1 = New-Atencion -Expediente $e2
    Set-Ficha -Expediente (Read-Expediente $e2.Ruta) -Atencion $a1 -Valores ([ordered]@{ sintoma = 'Se calienta' })
    $a2 = New-Atencion -Expediente (Read-Expediente $e2.Ruta)
    Assert 'con la ficha empezada (sin motivos), gana esa' ((Get-AtencionAbierta -Expediente (Read-Expediente $e2.Ruta)) -eq $a1) "ganó: $(Get-AtencionAbierta -Expediente (Read-Expediente $e2.Ruta))"
    Assert 'el modo técnico mide el ANTES de la atención si está completo y sin ANTES' ($ventana -match 'secs\.Count -eq \$script:Ui\.wpSecciones\.Children\.Count' -and $ventana -match 'no cuenta como el ANTES')
    Assert 'tras el diagnóstico ANTES se abre el pre-informe' ($ventana -match "Momento -eq 'antes'\) \{ Invoke-PreInformeGui -Abrir \}")
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
