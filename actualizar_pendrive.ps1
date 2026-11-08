#Requires -Version 5.1
<#
.SYNOPSIS
    Copia el kit de este repositorio al pendrive, verifica cada archivo y deja la versión y los hashes en
    KIT\version.json. Se corre en TU PC, nunca en el del cliente.
.DESCRIPTION
    Copia INICIAR.cmd, KIT\scripts, KIT\docs y actualizar_herramientas.ps1.
    - Nunca toca KIT\clientes ni KIT\herramientas, y no pisa un config_local.json que ya esté en el pendrive.
    - No borra nada: los scripts que ya no existen en el repositorio se mueven a KIT\_obsoletos\<fecha>.
    - Al terminar compara cada archivo con el original por SHA-256 y revisa que KIT\clientes no haya cambiado.
    Con el version.json, la ventana y el diagnóstico muestran la versión y avisan si un script cambió.
.PARAMETER Destino
    Letra o carpeta raíz del pendrive (E:, E:\ o una carpeta de prueba). Sin él, busca el volumen "Ventoy".
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\actualizar_pendrive.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Salida para el técnico en consola')]
param([string]$Destino)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$kitOrigen = Join-Path $repo 'KIT'
. (Join-Path $kitOrigen 'scripts\lib\Comun.ps1')

function Write-Paso([string]$Texto, [string]$Color = 'Gray') { Write-Host " $Texto" -ForegroundColor $Color }

function Get-FotoCarpeta {
    # Hash de cada archivo de una carpeta (para comprobar que no cambió). Vacío si no existe.
    param([string]$Carpeta)
    $h = @{}
    if (-not [IO.Directory]::Exists($Carpeta)) { return $h }
    foreach ($f in [IO.Directory]::GetFiles($Carpeta, '*', [IO.SearchOption]::AllDirectories)) { $h[$f.Substring($Carpeta.Length)] = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
    $h
}

try {
    Write-Host ''
    Write-Host ' ACTUALIZAR EL PENDRIVE' -ForegroundColor Cyan
    Write-Host ' ----------------------' -ForegroundColor Cyan
    if (-not [IO.Directory]::Exists($kitOrigen)) { throw "No encuentro KIT\ junto a este script ($repo)." }

    # Destino: el indicado o el único volumen llamado Ventoy.
    if (-not $Destino) {
        $vols = @(Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'Ventoy' })
        if ($vols.Count -ne 1) { throw "Encontré $($vols.Count) pendrives llamados Ventoy. Indica cuál con -Destino E:" }
        $Destino = $vols[0].DeviceID
    }
    if ($Destino -match '^[A-Za-z]:?\\?$') { $Destino = $Destino.Substring(0, 1) + ':\' }
    $raiz = [IO.Path]::GetFullPath($Destino)
    if (-not [IO.Directory]::Exists($raiz)) { throw "No existe $raiz. ¿Está conectado el pendrive?" }
    if ($raiz.TrimEnd('\') -ieq ([IO.Path]::GetFullPath($repo)).TrimEnd('\')) { throw 'El destino es este mismo repositorio: elige el pendrive.' }
    $kitDestino = Join-Path $raiz 'KIT'
    Write-Paso "Origen : $repo"
    Write-Paso "Destino: $raiz"

    # Versión: el último commit (y si hay cambios sin commit en el kit, se marca).
    $commit = $null; $fecha = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $l = & git -C $repo log -1 '--format=%h|%cs' 2>$null
        if ($LASTEXITCODE -eq 0 -and $l) { $commit, $fecha = "$l".Split('|') }
        $pendientes = & git -C $repo status --porcelain -- KIT actualizar_herramientas.ps1 2>$null
        if ($commit -and $pendientes) { $commit = "$commit+cambios" }
    }
    if (-not $commit) { $commit = 'sin-git'; $fecha = (Get-Date).ToString('yyyy-MM-dd') }
    Write-Paso "Versión: $script:VersionBase · $commit · $fecha"

    $clientes = Join-Path $kitDestino 'clientes'
    $fotoClientes = Get-FotoCarpeta $clientes
    Write-Paso "KIT\clientes en el pendrive: $($fotoClientes.Count) archivos (no se tocan)"

    # Copia. config_local.json se excluye: si el pendrive ya tiene uno, es el de ese técnico.
    foreach ($sub in 'scripts', 'docs') {
        $null = & robocopy.exe (Join-Path $kitOrigen $sub) (Join-Path $kitDestino $sub) /E /COPY:DAT /R:2 /W:1 /NP /NFL /NDL /NJH /NJS /XF config_local.json
        if ($LASTEXITCODE -ge 8) { throw "robocopy falló copiando KIT\$sub (código $LASTEXITCODE)" }
    }
    $localOrigen = Join-Path $kitOrigen 'scripts\config\config_local.json'
    $localDestino = Join-Path $kitDestino 'scripts\config\config_local.json'
    if ([IO.File]::Exists($localDestino)) { Write-Paso 'config_local.json: se mantiene el del pendrive' }
    elseif ([IO.File]::Exists($localOrigen)) { [IO.File]::Copy($localOrigen, $localDestino); Write-Paso 'config_local.json: copiado (no había en el pendrive)' }
    else { Write-Paso 'config_local.json: no hay en ninguno de los dos (los informes pedirán el contacto)' -Color Yellow }
    [IO.File]::Copy((Join-Path $kitOrigen 'INICIAR.cmd'), (Join-Path $kitDestino 'INICIAR.cmd'), $true)
    $herr = Join-Path $repo 'actualizar_herramientas.ps1'
    if ([IO.File]::Exists($herr)) { [IO.File]::Copy($herr, (Join-Path $raiz 'actualizar_herramientas.ps1'), $true) }

    # Los scripts que ya no están en el repositorio no se borran: se apartan.
    $esperados = @(Get-ArchivosVerificablesKit -RaizKit $kitOrigen)
    $sobran = @(Get-ArchivosVerificablesKit -RaizKit $kitDestino | Where-Object { $esperados -notcontains $_ })
    if ($sobran.Count) {
        $apartado = Join-Path $kitDestino ('_obsoletos\' + (Get-Date).ToString('yyyyMMdd_HHmmss'))
        foreach ($rel in $sobran) {
            $nuevo = Join-Path $apartado $rel
            $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $nuevo))
            [IO.File]::Move((Join-Path $kitDestino $rel), $nuevo)
        }
        Write-Paso "Apartados (ya no están en el repositorio): $($sobran -join ', ') -> $apartado" -Color Yellow
    }

    # Verificación: cada archivo igual al original, por SHA-256.
    $manifiesto = [ordered]@{}
    $distintos = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $esperados) {
        $hash = (Get-FileHash -LiteralPath (Join-Path $kitOrigen $rel) -Algorithm SHA256).Hash
        $manifiesto[$rel] = $hash
        $copia = Join-Path $kitDestino $rel
        if (-not [IO.File]::Exists($copia) -or (Get-FileHash -LiteralPath $copia -Algorithm SHA256).Hash -ne $hash) { $distintos.Add($rel) }
    }
    if ($distintos.Count) { throw "Quedaron distintos en el pendrive: $($distintos -join ', '). No se escribió version.json." }
    Write-Paso "Verificados por SHA-256: $($esperados.Count) archivos" -Color Green

    $info = [ordered]@{
        _leeme        = 'Lo escribe actualizar_pendrive.ps1. La ventana y el diagnóstico comparan los scripts con estos hashes.'
        version_base  = $script:VersionBase
        commit        = $commit
        fecha_commit  = $fecha
        copiado       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        archivos      = $manifiesto
    }
    [IO.File]::WriteAllText((Join-Path $kitDestino 'version.json'), ($info | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    $control = Test-IntegridadKit -RaizKit $kitDestino
    if ($control.Estado -ne 'ok') { throw "La verificación final no cuadra ($($control.Estado))." }

    $fotoDespues = Get-FotoCarpeta $clientes
    $cambios = @($fotoClientes.Keys | Where-Object { $fotoDespues[$_] -ne $fotoClientes[$_] }) + @($fotoDespues.Keys | Where-Object { -not $fotoClientes.ContainsKey($_) })
    if ($cambios.Count) { throw "KIT\clientes cambió durante la copia ($($cambios.Count) archivos). Revisa el pendrive." }
    Write-Paso 'KIT\clientes: intacto' -Color Green
    Write-Host ''
    Write-Paso "Listo: el pendrive tiene el kit $script:VersionBase · $commit · $fecha" -Color Green
    exit 0
} catch {
    Write-Host ''
    Write-Paso "No se completó: $($_.Exception.Message)" -Color Red
    exit 1
}
