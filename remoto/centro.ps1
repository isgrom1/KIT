#Requires -Version 5.1
<#
.SYNOPSIS
    Centro de mando de Isaac para lo remoto: un menú con números, sin arrastrar archivos.
.DESCRIPTION
    1  Abrir lo que llegó: busca los .kitdiag nuevos (pendrive, Descargas, Escritorio) y abre el que elijas.
    2  Armar un trabajo remoto: elige uno de los diagnósticos ya abiertos y deja el ZIP también en el pendrive.
    3  Para enviar: abre la carpeta con un pack por carpeta (la arma si no está).
    4  Abrir la carpeta de remotos (lo ya abierto: informes, hojas técnicas).
    5  Rearmar el diagnóstico para mandar (ZIP nuevo + Para enviar + copia al pendrive).
    6  Código para un cliente: lo pide la ventana del diagnóstico; deja copiado el mensaje para WhatsApp.
    El pendrive se reconoce solo: la unidad que tiene KIT\INICIAR.cmd.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Menú de consola para Isaac')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$aqui = $PSScriptRoot
$ps = Join-Path $PSHOME 'powershell.exe'

function Get-Pendrive {
    # Unidad del pendrive del kit (tiene KIT\INICIAR.cmd), sin contar la del repo. $null si no está conectado.
    $repo = [IO.Path]::GetPathRoot($aqui)
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady -or $d.RootDirectory.FullName -eq $repo) { continue }
        if ([IO.File]::Exists((Join-Path $d.RootDirectory.FullName 'KIT\INICIAR.cmd'))) { return $d.RootDirectory.FullName }
    }
    $null
}

function Get-CarpetaRemotos {
    $cfg = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $aqui) 'KIT\scripts\config\config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $m = "$($cfg.sincronizacion.ruta_maestro)"
    if ($m -and [IO.Directory]::Exists((Split-Path -Parent $m))) { return Join-Path (Split-Path -Parent $m) 'remotos' }
    $null
}

function Get-KitdiagNuevos {
    # .kitdiag en el pendrive, Descargas y Escritorio que todavía no tienen carpeta abierta en remotos. El más nuevo primero.
    param([string]$Remotos)
    $lugares = @((Get-Pendrive), [Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads')) | Where-Object { $_ -and [IO.Directory]::Exists($_) }
    $vistos = @{}
    foreach ($l in $lugares) {
        foreach ($f in @(Get-ChildItem -LiteralPath $l -Filter '*.kitdiag' -File -ErrorAction SilentlyContinue)) {
            if ($vistos.ContainsKey($f.Name)) { continue }
            $vistos[$f.Name] = $true
            $abierto = $Remotos -and [IO.Directory]::Exists((Join-Path $Remotos $f.BaseName))
            [pscustomobject]@{ Archivo = $f.FullName; Nombre = $f.Name; Fecha = $f.LastWriteTime; Abierto = $abierto }
        }
    }
}

function Read-Opcion {
    param([string]$Texto, [int]$Max)
    $r = Read-Host $Texto
    if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $Max) { return [int]$r }
    $null
}

$remotos = Get-CarpetaRemotos
while ($true) {
    $pen = Get-Pendrive
    Clear-Host
    Write-Host ''
    Write-Host ' CENTRO REMOTO - KIT SERVICIO' -ForegroundColor Cyan
    Write-Host " Pendrive: $(if ($pen) { $pen } else { 'no conectado' })   |   Remotos: $(if ($remotos) { $remotos } else { '(sin maestro)' })" -ForegroundColor DarkGray
    $nuevos = @(Get-KitdiagNuevos -Remotos $remotos | Where-Object { -not $_.Abierto })
    Write-Host ''
    Write-Host "  1) Abrir lo que llegó$(if ($nuevos.Count) { "  ($($nuevos.Count) nuevo(s))" })"
    Write-Host '  2) Armar un trabajo remoto'
    Write-Host '  3) Para enviar (un pack por carpeta)'
    Write-Host '  4) Abrir la carpeta de remotos'
    Write-Host '  5) Rearmar el diagnóstico para mandar'
    Write-Host '  6) Código para un cliente (y el mensaje para WhatsApp)'
    Write-Host '  0) Salir'
    $op = Read-Host ' Opción'
    switch ($op) {
        '1' {
            $lista = @(Get-KitdiagNuevos -Remotos $remotos | Sort-Object Fecha -Descending)
            if (-not $lista.Count) { Write-Host ' No hay .kitdiag en el pendrive, Descargas ni Escritorio.' -ForegroundColor Yellow; break }
            for ($i = 0; $i -lt $lista.Count; $i++) { Write-Host ('  {0}) {1}  {2:dd-MM HH:mm}{3}' -f ($i + 1), $lista[$i].Nombre, $lista[$i].Fecha, $(if ($lista[$i].Abierto) { '  (ya abierto)' } else { '' })) }
            $n = Read-Opcion ' Cuál (Enter = el 1)' $lista.Count
            if (-not $n) { $n = 1 }
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aqui 'abrir_diagnostico.ps1') -Archivo $lista[$n - 1].Archivo
        }
        '2' {
            if (-not $remotos) { Write-Host ' Sin carpeta de remotos.' -ForegroundColor Yellow; break }
            $diags = @(Get-ChildItem -LiteralPath $remotos -Directory -Filter 'Diagnostico_para_Isaac_*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 9)
            if (-not $diags.Count) { Write-Host ' No hay diagnósticos abiertos: primero la opción 1.' -ForegroundColor Yellow; break }
            for ($i = 0; $i -lt $diags.Count; $i++) { Write-Host ('  {0}) {1}' -f ($i + 1), $diags[$i].Name) }
            $n = Read-Opcion ' Cuál (Enter = el 1)' $diags.Count
            if (-not $n) { $n = 1 }
            $antes = @(Get-ChildItem -LiteralPath (Join-Path $aqui '_salida') -Filter 'Trabajo_*.zip' -ErrorAction SilentlyContinue | ForEach-Object FullName)
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aqui 'armar_trabajo.ps1') -Carpeta $diags[$n - 1].FullName
            $zip = @(Get-ChildItem -LiteralPath (Join-Path $aqui '_salida') -Filter 'Trabajo_*.zip' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $antes } | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
            if ($zip -and $pen) {
                $dest = Join-Path $pen 'PARA_ENVIAR'
                $null = [IO.Directory]::CreateDirectory($dest)
                Copy-Item -LiteralPath $zip.FullName -Destination $dest -Force
                Write-Host " Copiado al pendrive: $(Join-Path $dest $zip.Name)" -ForegroundColor Green
            } elseif ($zip) { Write-Host " Conecta el pendrive para copiarlo; está en $($zip.FullName)" -ForegroundColor Yellow }
        }
        '3' {
            $pe = Join-Path $aqui '_salida\Para_enviar'
            if (-not [IO.Directory]::Exists($pe)) { & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aqui 'armar_envios.ps1') }
            Start-Process explorer.exe -ArgumentList "`"$pe`""
        }
        '4' { if ($remotos) { $null = [IO.Directory]::CreateDirectory($remotos); Start-Process explorer.exe -ArgumentList "`"$remotos`"" } }
        '5' {
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aqui 'armar_paquete.ps1')
            & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aqui 'armar_envios.ps1')
            $zip = @(Get-ChildItem -LiteralPath (Join-Path $aqui '_salida') -Filter 'Diagnostico_remoto_*.zip' | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
            if ($zip -and $pen) {
                $dest = Join-Path $pen 'PARA_ENVIAR'
                $null = [IO.Directory]::CreateDirectory($dest)
                Get-ChildItem -LiteralPath $dest -Filter 'Diagnostico_remoto_*.zip' | Where-Object Name -NE $zip.Name | Remove-Item -Force
                Copy-Item -LiteralPath $zip.FullName -Destination $dest -Force
                Write-Host " Copiado al pendrive: $(Join-Path $dest $zip.Name)" -ForegroundColor Green
            }
        }
        '6' { & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aqui 'codigo_cliente.ps1') }
        '0' { return }
        default { continue }
    }
    Write-Host ''
    $null = Read-Host ' Enter para volver al menú'
}
