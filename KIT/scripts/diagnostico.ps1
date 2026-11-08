#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico de solo lectura para equipos Windows 10/11 de clientes.

.DESCRIPTION
    Lee equipo, hardware, Windows, seguridad, energía, software, arranque, políticas de navegador,
    preferencias de GPU, uso actual, espacio, dispositivos y estabilidad.
    No usa red, no instala nada y no cambia configuración. Lo único que escribe es el expediente del
    equipo: KIT\clientes\<fabricante_modelo_serie>\<AAAA-MM-DD_atencion>\antes (o despues) con
    diagnostico.json, metricas.json, csv\, resumen.txt, log.txt, informe de batería y discos.txt,
    más ficha.json y trabajo.log.

.PARAMETER Momento
    Antes (por defecto) o Despues del trabajo. "Después" va a la atención abierta que ya tiene "antes";
    si no hay ninguna, no se crea nada y sale con código 4.

.PARAMETER NuevaAtencion
    Abre una atención nueva aunque hoy ya haya una abierta (solo con -Momento Antes).

.PARAMETER AbrirResumen
    Abre resumen.txt en el Bloc de notas al terminar.

.PARAMETER SinEspacio
    Omite el recorrido de carpetas de la sección 11. El libre/total por volumen se calcula igual.

.PARAMETER TiempoMaxEspacio
    Segundos máximos para el recorrido de carpetas. 0 = usar config.json (espacio.tiempo_max_seg).

.PARAMETER Secciones
    Números de sección a ejecutar (por defecto todas). Ej.: -Secciones 2,5

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnostico.ps1 -SinEspacio
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Mensajes de arranque antes de cargar lib\Log.ps1')]
[CmdletBinding()]
param(
    [ValidateSet('Antes', 'Despues')][string]$Momento = 'Antes',
    [switch]$NuevaAtencion,
    # Atención exacta donde medir (la GUI la pasa para no depender de la regla automática).
    [string]$Atencion,
    # Carpeta de expedientes alternativa (la usa la GUI cuando trabaja con otra carpeta).
    [string]$Clientes,
    [switch]$AbrirResumen,
    # Para la interfaz gráfica: agrega líneas "##SECCION|n|nombre" y "##FIN|carpeta" a la salida.
    [switch]$ProgresoGui,
    [switch]$SinEspacio,
    [ValidateRange(0, 7200)][int]$TiempoMaxEspacio = 0,
    [string[]]$Secciones
)

$ErrorActionPreference = 'Stop'

# Con -File, "-Secciones 5,6" llega como un solo texto: se acepta "5,6", "5 6" o 5,6.
if ($Secciones) {
    $numeros = @($Secciones -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })
    if (@($numeros | Where-Object { $_ -lt 1 -or $_ -gt 13 }).Count -gt 0) {
        Write-Host "Secciones válidas: 1 a 13 (recibido: $($Secciones -join ' '))" -ForegroundColor Red
        exit 2
    }
    $Secciones = $numeros
}

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host "PowerShell está en modo $($ExecutionContext.SessionState.LanguageMode) (AppLocker/WDAC)." -ForegroundColor Red
    Write-Host 'El diagnóstico necesita FullLanguage; en este equipo no se puede correr.' -ForegroundColor Red
    exit 3
}

$raizScripts = $PSScriptRoot
try {
    foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $raizScripts "lib\$lib.ps1") }
    Initialize-Contexto -RaizScripts $raizScripts
    if ($Clientes) { $script:Ctx.CarpetaClientes = $Clientes }
} catch {
    Write-Host "No se pudo cargar el kit desde $raizScripts : $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$script:Catalogo = @(
    [pscustomobject]@{ N = 1; Nombre = 'Equipo'; Base = 'Equipo'; Clave = 'equipo' }
    [pscustomobject]@{ N = 2; Nombre = 'Hardware'; Base = 'Hardware'; Clave = 'hardware' }
    [pscustomobject]@{ N = 3; Nombre = 'Windows'; Base = 'Windows'; Clave = 'windows' }
    [pscustomobject]@{ N = 4; Nombre = 'Seguridad'; Base = 'Seguridad'; Clave = 'seguridad' }
    [pscustomobject]@{ N = 5; Nombre = 'Energía'; Base = 'Energia'; Clave = 'energia' }
    [pscustomobject]@{ N = 6; Nombre = 'Software'; Base = 'Software'; Clave = 'software' }
    [pscustomobject]@{ N = 7; Nombre = 'Arranque'; Base = 'Arranque'; Clave = 'arranque' }
    [pscustomobject]@{ N = 8; Nombre = 'Políticas navegador'; Base = 'Navegador'; Clave = 'navegador' }
    [pscustomobject]@{ N = 9; Nombre = 'GPU por app'; Base = 'GpuApps'; Clave = 'gpu_apps' }
    [pscustomobject]@{ N = 10; Nombre = 'Uso actual'; Base = 'Uso'; Clave = 'uso' }
    [pscustomobject]@{ N = 11; Nombre = 'Espacio'; Base = 'Espacio'; Clave = 'espacio' }
    [pscustomobject]@{ N = 12; Nombre = 'Dispositivos'; Base = 'Dispositivos'; Clave = 'dispositivos' }
    [pscustomobject]@{ N = 13; Nombre = 'Estabilidad'; Base = 'Estabilidad'; Clave = 'estabilidad' }
)

function Invoke-Seccion {
    param([Parameter(Mandatory)]$Def)
    $script:Ctx.SeccionActual = '{0:00} {1}' -f $Def.N, $Def.Nombre
    $script:Ctx.SeccionNumero = $Def.N
    $script:Ctx.EstadoForzado = $null
    $incompletosAntes = $script:Ctx.Incompletos.Count
    $erroresAntes = $script:Ctx.Errores.Count
    if ($ProgresoGui) { Show-Mensaje ('##SECCION|{0}|{1}' -f $Def.N, $Def.Nombre) }
    Show-Mensaje (' [{0,2}/13] {1,-22}' -f $Def.N, $Def.Nombre) -SinSalto
    Write-LogKit -Mensaje 'Inicio de sección'
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $estado = 'OK'
    try {
        if (-not (Get-Command "Get-Datos$($Def.Base)" -ErrorAction SilentlyContinue)) { throw "No está cargado secciones\$($Def.Archivo)" }
        $script:Ctx.Datos[$Def.Clave] = & "Get-Datos$($Def.Base)"
    } catch {
        $estado = 'ERROR'
        Add-ErrorPaso -Paso 'sección completa' -Registro $_
    }
    $reloj.Stop()
    if ($estado -eq 'OK') {
        if ($script:Ctx.EstadoForzado) { $estado = $script:Ctx.EstadoForzado }
        elseif ($script:Ctx.Errores.Count -gt $erroresAntes) { $estado = 'CON ERRORES' }
        elseif ($script:Ctx.Incompletos.Count -gt $incompletosAntes) { $estado = 'INCOMPLETA' }
    }
    $seg = [math]::Round($reloj.Elapsed.TotalSeconds, 1)
    $script:Ctx.Secciones.Add([pscustomobject][ordered]@{ N = $Def.N; Seccion = $Def.Nombre; Estado = $estado; Segundos = $seg })
    $color = switch ($estado) { 'OK' { 'Green' } 'ERROR' { 'Red' } default { 'Yellow' } }
    Show-Mensaje ('{0,-12} {1,7} s' -f $estado, (Format-Numero $seg 1)) -Color $color
    Write-LogKit -Mensaje "Fin de sección: $estado en $seg s"
}

# ------------------------------------------------------------------------------ inicio

$script:Ctx.Parametros = [ordered]@{
    Momento          = $Momento.ToLowerInvariant()
    NuevaAtencion    = [bool]$NuevaAtencion
    SinEspacio       = [bool]$SinEspacio
    TiempoMaxEspacio = if ($TiempoMaxEspacio -gt 0) { $TiempoMaxEspacio } else { [int]$script:Ctx.Config.espacio.tiempo_max_seg }
    Secciones        = if ($Secciones) { $Secciones } else { 'todas' }
}

Show-Mensaje ''
Show-Mensaje ' KIT SERVICIO - Diagnóstico (solo lectura, sin red)' -Color Cyan
Show-Mensaje (' ' + ('-' * 52)) -Color DarkCyan

try {
    $script:Ctx.Admin = Get-EstadoAdmin
    Initialize-Privacidad
} catch {
    $script:Ctx.Admin = [pscustomobject]@{ Elevado = $false; MiembroAdministradores = $false }
    Write-LogKit -Nivel ERROR -Mensaje "Inicio (admin/privacidad): $($_.Exception.Message)"
}

try {
    $script:Ctx.Identidad = Get-IdentidadEquipo
} catch {
    $script:Ctx.Identidad = [pscustomobject]@{ Fabricante = 'Desconocido'; Modelo = 'Desconocido'; Serie = ''; SerieOriginal = ''; Uuid = $null; PlacaSerie = $null }
    Write-LogKit -Nivel ERROR -Mensaje "No se pudo leer la identidad del equipo: $($_.Exception.Message)"
}

try {
    $exp = Initialize-Expediente -Identidad $script:Ctx.Identidad -Momento $script:Ctx.Parametros.Momento -NuevaAtencion:$NuevaAtencion -Atencion $Atencion
} catch {
    Show-Mensaje " No se puede escribir en $($script:Ctx.CarpetaClientes)" -Color Red
    Show-Mensaje " ($($_.Exception.Message))" -Color Red
    Show-Mensaje ' ¿El USB está en solo lectura o hay una política de BitLocker To Go? No se guardó nada.' -Color Red
    exit 2
}
if ($exp.PSObject.Properties['SinAntes']) {
    Show-Mensaje ' No hay un diagnóstico ANTES abierto para este equipo: no existe "después" sin "antes".' -Color Red
    Show-Mensaje ' Corre primero el diagnóstico ANTES (INICIAR, opción 1). No se guardó nada.' -Color Red
    exit 4
}

Write-LogKit -Mensaje ("Kit v{0} | PowerShell {1} | 64 bits: {2} | Elevado: {3} | Miembro de Administradores: {4}" -f $script:Ctx.Version,
    $PSVersionTable.PSVersion, [Environment]::Is64BitProcess, $script:Ctx.Admin.Elevado, $script:Ctx.Admin.MiembroAdministradores)
Write-LogKit -Mensaje ('Parámetros: ' + (($script:Ctx.Parametros.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value -join ',')" }) -join ' '))
# ¿Los scripts son los que copió actualizar_pendrive.ps1? Solo se avisa: no detiene el diagnóstico.
$integridad = Test-IntegridadKit -RaizKit $script:Ctx.RaizKit
switch ($integridad.Estado) {
    'ok' { Write-LogKit -Mensaje "Integridad del kit: OK (copia del $($integridad.Copiado))" }
    'sin_manifiesto' { Write-LogKit -Mensaje 'Integridad del kit: sin version.json (copia de trabajo, no se verifica)' }
    'error' { Write-LogKit -Nivel AVISO -Mensaje "Integridad del kit: no se pudo verificar ($($integridad.Detalle))" }
    default {
        $distintos = @($integridad.Cambiados + $integridad.Faltan + $integridad.Nuevos)
        Write-LogKit -Nivel AVISO -Mensaje "Integridad del kit: $($distintos.Count) archivo(s) no coinciden con la copia del $($integridad.Copiado): $($distintos -join ', ')"
        Show-Mensaje " Ojo: $($distintos.Count) archivo(s) del kit no coinciden con la copia verificada. Vuelve a copiar el kit desde tu PC." -Color Yellow
    }
}
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    Write-LogKit -Nivel AVISO -Mensaje 'PowerShell de 32 bits en Windows de 64 bits: el registro se lee con vista explícita de 64 bits.'
}

if ($script:Ctx.Admin.Elevado) {
    Show-Mensaje ' Admin: SÍ (elevado)' -Color Green
} else {
    $quien = if ($script:Ctx.Admin.MiembroAdministradores) { 'usuario admin sin elevar' } else { 'usuario estándar' }
    Show-Mensaje " Admin: NO ($quien). Algunas partes quedarán incompletas." -Color Yellow
}
Show-Mensaje (" Expediente: {0}{1}" -f $exp.Id, $(if ($exp.Nuevo) { ' (nuevo)' } else { '' }))
Show-Mensaje (" Atención: {0} | medición: {1}" -f $exp.Atencion, $exp.Momento.ToUpperInvariant())
Write-LogKit -Mensaje "Expediente $($exp.Id)$(if ($exp.Nuevo) { ' (nuevo)' }) | atención $($exp.Atencion) | $($exp.Momento)"
if ($exp.Anterior) {
    Show-Mensaje " Ya hay una medición $($exp.Momento.ToUpperInvariant()) en esta atención: al terminar queda como respaldo." -Color DarkGray
    # Si la anterior se hizo con admin y esta no, los informes usarían la más incompleta.
    try {
        if (-not $script:Ctx.Admin.Elevado -and (Read-JsonKit $exp.Anterior).kit.admin.Elevado) {
            Show-Mensaje ' Ojo: la medición anterior se hizo con admin y esta no. Los informes usan la última: relanza como admin.' -Color Yellow
            Write-LogKit -Nivel AVISO -Mensaje 'Se va a reemplazar una medición con admin por una sin admin'
        }
    } catch { Write-LogKit -Nivel AVISO -Mensaje "No se pudo leer la medición anterior: $($_.Exception.Message)" }
}
Show-Mensaje ''

foreach ($def in $script:Catalogo) {
    $def | Add-Member -NotePropertyName Archivo -NotePropertyValue ('{0:00}_{1}.ps1' -f $def.N, $def.Base.ToLower())
    if ($Secciones -and $def.N -notin $Secciones) { continue }
    $ruta = Join-Path $raizScripts "secciones\$($def.Archivo)"
    try {
        . $ruta
    } catch {
        Write-LogKit -Nivel ERROR -Mensaje "No se pudo cargar $($def.Archivo): $(($_.Exception.Message -split '\r?\n' | Where-Object { $_.Trim() }) -join ' / ')"
    }
}

$ejecutadas = @($script:Catalogo | Where-Object { -not $Secciones -or $_.N -in $Secciones })
foreach ($def in $ejecutadas) { Invoke-Seccion -Def $def }

# discos.txt: informe SMART de CrystalDiskInfo (con admin, si está en herramientas\).
if ($script:Ctx.Datos['hardware']) {
    $script:Ctx.SeccionActual = '02 Hardware'
    $script:Ctx.SeccionNumero = 2
    Show-Mensaje (' {0,-30}' -f '        discos.txt') -SinSalto
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $hecho = $false
    try { $hecho = [bool](Export-DiscosCrystal) } catch { Add-ErrorPaso -Paso 'discos.txt (CrystalDiskInfo)' -Registro $_ }
    $script:Ctx.Datos.hardware['DiscosTxt'] = $hecho
    if ($hecho) {
        try {
            $script:Ctx.Datos.hardware['SmartCrystal'] = @(Read-DiscosCrystal -Ruta (Join-Path $script:Ctx.CarpetaCliente 'discos.txt'))
            Add-Tabla -Nombre 'smart_crystaldiskinfo' -Filas $script:Ctx.Datos.hardware['SmartCrystal']
        } catch { Add-ErrorPaso -Paso 'lectura de discos.txt' -Registro $_ }
    }
    Show-Mensaje ('{0,-12} {1,7} s' -f $(if ($hecho) { 'OK' } else { 'no' }), (Format-Numero $reloj.Elapsed.TotalSeconds 1)) -Color $(if ($hecho) { 'Green' } else { 'DarkGray' })
}

# Las alertas se evalúan al final, con los datos de todas las secciones ya leídos.
foreach ($def in $ejecutadas) {
    $script:Ctx.SeccionActual = '{0:00} {1}' -f $def.N, $def.Nombre
    $script:Ctx.SeccionNumero = $def.N
    if ($null -eq $script:Ctx.Datos[$def.Clave]) { continue }
    if (-not (Get-Command "Test-Alertas$($def.Base)" -ErrorAction SilentlyContinue)) { continue }
    try { & "Test-Alertas$($def.Base)" } catch { Add-ErrorPaso -Paso 'alertas' -Registro $_ }
}
$script:Ctx.SeccionActual = ''
$script:Ctx.SeccionNumero = 0
if (-not $script:Ctx.Admin.Elevado) {
    $partes = @($script:Ctx.Incompletos | ForEach-Object { $_.Parte }) -join ', '
    $quien = if ($script:Ctx.Admin.MiembroAdministradores) { 'usuario admin sin elevar' } else { 'usuario estándar' }
    if ($partes) {
        Add-Alerta -Severidad AVISO -Codigo 'KIT-ADMIN' -Texto "Sin admin ($quien). Incompleto: $partes. Relanza INICIAR como administrador para completarlo."
    } else {
        Add-Alerta -Severidad INFO -Codigo 'KIT-ADMIN' -Texto "Sin admin ($quien): las secciones que corrieron no necesitaban admin."
    }
}

try {
    Export-Resultados
} catch {
    Show-Mensaje " Error al escribir los resultados: $($_.Exception.Message)" -Color Red
    Write-LogKit -Nivel ERROR -Mensaje "Export-Resultados: $($_.Exception.Message) ($($_.InvocationInfo.ScriptLineNumber))"
    exit 1
}

# Recién con todo escrito, <momento>_en_curso pasa a ser la medición oficial.
try {
    $exp.Reemplazada = Complete-Medicion -Expediente $exp.Objeto -Atencion $exp.Atencion -Momento $exp.Momento
    $script:Ctx.CarpetaCliente = Join-Path (Join-Path $exp.Ruta $exp.Atencion) $exp.Momento
    if ($exp.Reemplazada) { Write-LogKit -Mensaje "Medición anterior respaldada como $($exp.Reemplazada)" }
} catch {
    Show-Mensaje " Los resultados quedaron en $($script:Ctx.CarpetaCliente), pero no se pudo cerrar la medición: $($_.Exception.Message)" -Color Red
    Write-LogKit -Nivel ERROR -Mensaje "Complete-Medicion: $($_.Exception.Message)"
    exit 1
}

$alertas = Get-AlertasOrdenadas
# La ficha y trabajo.log se actualizan al final: si fallan, los resultados ya quedaron escritos.
try {
    # Se relee del disco: la ficha pudo cambiar mientras corría el diagnóstico.
    $exp.Objeto = Read-Expediente $exp.Ruta
    Update-FichaDesdeDiagnostico -Expediente $exp.Objeto -Atencion $exp.Atencion -Momento $exp.Momento -Datos $script:Ctx.Datos `
        -Generado (ConvertTo-TextoFecha $script:Ctx.Inicio) -Admin $script:Ctx.Admin.Elevado -Alertas $alertas
    $cuenta = '{0} críticas, {1} avisos, {2} info' -f @($alertas | Where-Object Severidad -EQ 'CRITICO').Count, @($alertas | Where-Object Severidad -EQ 'AVISO').Count, @($alertas | Where-Object Severidad -EQ 'INFO').Count
    $texto = '{0} | diagnóstico (admin: {1}, {2}{3}) | alertas: {4}' -f $exp.Momento.ToUpperInvariant(), $(if ($script:Ctx.Admin.Elevado) { 'sí' } else { 'no' }),
        (Format-Duracion $script:Ctx.Reloj.Elapsed.TotalSeconds), $(if ($exp.Reemplazada) { ", reemplaza a $($exp.Reemplazada)" } else { '' }), $cuenta
    Write-TrabajoLog -Expediente $exp.Objeto -Atencion $exp.Atencion -Texto $texto
} catch {
    Show-Mensaje " Los resultados quedaron guardados, pero no se pudo actualizar ficha.json: $($_.Exception.Message)" -Color Yellow
    Write-LogKit -Nivel ERROR -Mensaje "Ficha/trabajo.log: $($_.Exception.Message)"
}
Show-Mensaje ''
Show-Mensaje (' Alertas: {0} críticas, {1} avisos, {2} info' -f @($alertas | Where-Object Severidad -EQ 'CRITICO').Count,
    @($alertas | Where-Object Severidad -EQ 'AVISO').Count, @($alertas | Where-Object Severidad -EQ 'INFO').Count) -Color Cyan
foreach ($a in $alertas | Where-Object Severidad -NE 'INFO') {
    $color = if ($a.Severidad -eq 'CRITICO') { 'Red' } else { 'Yellow' }
    Show-Mensaje ('  {0,-9} {1}' -f "[$($a.Severidad)]", $a.Texto) -Color $color
}
Show-Mensaje ''
Show-Mensaje (" Tiempo total: {0}" -f (Format-Duracion $script:Ctx.Reloj.Elapsed.TotalSeconds))
Show-Mensaje " Resultados en: $($script:Ctx.CarpetaCliente)" -Color Green
if ($exp.Reemplazada) { Show-Mensaje " La medición anterior quedó como $($exp.Reemplazada)" -Color DarkGray }
$faltan = @(Test-FichaCompleta -Expediente $exp.Objeto -Atencion $exp.Atencion)
if ($faltan.Count -gt 0) {
    $cuantos = if ($faltan.Count -eq 1) { 'falta 1 dato' } else { "faltan $($faltan.Count) datos" }
    Show-Mensaje (" Ficha: {0} para los informes ({1}). Complétala con la opción 3 de INICIAR." -f $cuantos, (($faltan | ForEach-Object { $_.Texto }) -join '; ')) -Color DarkGray
}
Write-LogKit -Mensaje ("Fin. Duración total {0:N1} s" -f $script:Ctx.Reloj.Elapsed.TotalSeconds)
if ($ProgresoGui) { Show-Mensaje "##FIN|$($script:Ctx.CarpetaCliente)" }
if ($AbrirResumen) {
    try { Start-Process -FilePath (Get-RutaSistema 'notepad.exe') -ArgumentList "`"$(Join-Path $script:Ctx.CarpetaCliente 'resumen.txt')`"" } catch { Write-LogKit -Nivel AVISO -Mensaje "No se pudo abrir el Bloc de notas: $($_.Exception.Message)" }
}
exit 0
