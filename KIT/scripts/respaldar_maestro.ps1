#Requires -Version 5.1
<#
.SYNOPSIS
    Respaldo cifrado del maestro de expedientes, en TU PC (no en el del cliente).
.DESCRIPTION
    Sin parámetros: respalda el maestro (config.json -> sincronizacion.ruta_maestro) en el destino de
    config.json -> respaldo (por defecto Z:\kitservicio_respaldos), lo verifica leyéndolo de vuelta y deja
    los últimos "conservar". Después de cada sincronización esto corre solo.
    -NuevaClave: pide la contraseña dos veces y la guarda cifrada para tu usuario (DPAPI). Hazlo una vez.
    ANÓTALA EN UN LUGAR SEGURO: sin ella el respaldo no se puede abrir, ni siquiera en tu PC si cambias de
    usuario o reinstalas Windows.
    -Verificar <archivo>: comprueba un respaldo sin restaurarlo.
    -Restaurar <archivo> -En <carpeta nueva>: lo descifra en una carpeta nueva; nunca escribe sobre el maestro.
    En otro PC (sin la contraseña guardada) la pide.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\respaldar_maestro.ps1 -NuevaClave
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\respaldar_maestro.ps1 -Restaurar Z:\kitservicio_respaldos\maestro_20261108_150000.kitresp -En X:\restaurado
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Salida para el técnico en consola')]
param([switch]$NuevaClave, [string]$Verificar, [string]$Restaurar, [string]$En, [string]$Maestro, [string]$Destino, [string]$ArchivoClave)

$ErrorActionPreference = 'Stop'
try {
    foreach ($lib in 'Comun', 'Log', 'Sincronizacion', 'Respaldo') { . (Join-Path $PSScriptRoot "lib\$lib.ps1") }
    Initialize-Contexto -RaizScripts $PSScriptRoot
    if (-not $ArchivoClave) { $ArchivoClave = Get-RutaClaveRespaldo }
    $pedir = {
        param([string]$Texto)
        $c = Read-Host -AsSecureString $Texto
        if ($c.Length -lt 1) { throw 'No escribiste la contraseña.' }
        $c
    }
    if ($NuevaClave) {
        Write-Host ''
        Write-Host ' CONTRASEÑA DEL RESPALDO' -ForegroundColor Cyan
        Write-Host ' Mínimo 10 caracteres. Anótala en un lugar seguro: sin ella el respaldo no se abre.' -ForegroundColor Yellow
        $a = & $pedir ' Contraseña'
        $b = & $pedir ' Repítela'
        $ta = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
        $tb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))
        if ($ta -cne $tb) { throw 'Las contraseñas no coinciden.' }
        if ($ta.Length -lt 10) { throw 'Muy corta: usa al menos 10 caracteres.' }
        Set-ClaveRespaldo -Clave $a -Ruta $ArchivoClave
        Write-Host " Guardada para tu usuario en $ArchivoClave" -ForegroundColor Green
        exit 0
    }
    $clave = Get-ClaveRespaldo -Ruta $ArchivoClave
    if ($Verificar -or $Restaurar) {
        if (-not $clave) { $clave = & $pedir ' Contraseña del respaldo' }
        if ($Verificar) {
            $l = @(Read-ArchivosRespaldo -Ruta $Verificar -Clave $clave)
            Write-Host " Respaldo correcto: $($l.Count) archivos, cada uno con su SHA-256 verificado." -ForegroundColor Green
            exit 0
        }
        if (-not $En) { throw 'Falta -En <carpeta nueva> para restaurar.' }
        $l = @(Restore-RespaldoMaestro -Ruta $Restaurar -Destino $En -Clave $clave)
        Write-Host " Restaurados $($l.Count) archivos en $En (verificados). Revísalos y, si corresponde, reemplaza el maestro a mano." -ForegroundColor Green
        exit 0
    }
    if (-not (Test-EquipoTecnico)) { throw "El respaldo es solo para tus equipos (config.json -> equipos_tecnico) y este es $env:COMPUTERNAME." }
    $cfg = Get-ConfigRespaldo
    if (-not $Maestro) { $Maestro = Get-RutaMaestro }
    if (-not $Destino) { if (-not $cfg) { throw 'Falta config.json -> respaldo.destino.' }; $Destino = $cfg.Destino }
    if (-not $clave) { throw 'Falta la contraseña: corre una vez respaldar_maestro.ps1 -NuevaClave.' }
    $r = New-RespaldoMaestro -Maestro $Maestro -Destino $Destino -Clave $clave -Conservar $(if ($cfg) { $cfg.Conservar } else { 10 })
    Write-Host (" Respaldo listo y verificado: {0} ({1} archivos, {2})" -f $r.Ruta, $r.Archivos, (Format-Tamano $r.Bytes)) -ForegroundColor Green
    if (@($r.Borrados).Count) { Write-Host " Borrados por antiguos: $(@($r.Borrados) -join ', ')" }
    exit 0
} catch {
    Write-Host " No se pudo: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
