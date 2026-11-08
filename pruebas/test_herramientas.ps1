#Requires -Version 5.1
<#
.SYNOPSIS
    Prueba cómo el kit abre las herramientas: OCCT con la variable de AMD, aviso si quedó uno colgado
    y comillas con rutas raras. No abre ningún UAC: corre el comando sin elevar, con programas falsos.
.DESCRIPTION
    Solo escribe en X:\kitservicio_prueba\herramientas (o en -Base) y lo borra al terminar.
    Lo que no cubre: el paso por el UAC, que necesita que el técnico lo acepte (-ConUac).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Salida de la batería en consola')]
param([string]$Base = $(if (Test-Path 'X:\') { 'X:\kitservicio_prueba\herramientas' } else { Join-Path $env:SystemDrive 'kitprueba\herramientas' }), [switch]$ConUac)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\KIT\scripts\lib\Herramientas.ps1')
$script:Ok = 0; $script:Mal = 0
$variable = 'DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1'

function Assert-Prueba([string]$Nombre, [bool]$Cumple, [string]$Detalle = '') {
    if ($Cumple) { $script:Ok++; Write-Host "  OK  $Nombre" -ForegroundColor Green }
    else { $script:Mal++; Write-Host "  MAL $Nombre  $Detalle" -ForegroundColor Red }
}

function New-OcctFalso([string]$Carpeta) {
    # OCCT.exe falso = copia de where.exe: termina solo y no abre nada. Solo sirve para elegir el exe.
    $dir = Join-Path $Carpeta 'OCCT'
    $null = New-Item -ItemType Directory -Force -Path $dir
    [IO.File]::Copy((Join-Path $env:SystemRoot 'System32\where.exe'), (Join-Path $dir 'OCCT.exe'), $true)
    $dir
}

function Wait-Archivo([string]$Ruta, [int]$Segundos = 15) {
    $t0 = Get-Date
    while (-not [IO.File]::Exists($Ruta) -and ((Get-Date) - $t0).TotalSeconds -lt $Segundos) { Start-Sleep -Milliseconds 200 }
    [IO.File]::Exists($Ruta)
}

if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $Base
try {
    if (@(Get-Process -Name OCCT, OCCTGUI -ErrorAction SilentlyContinue).Count) { throw 'Hay un OCCT corriendo: ciérralo antes de la prueba' }

    Write-Host 'Opciones'
    $carpeta = Join-Path $Base 'normal'
    $null = New-OcctFalso $carpeta
    $dirOtra = Join-Path $carpeta 'Otra'
    $null = New-Item -ItemType Directory -Force -Path $dirOtra
    [IO.File]::Copy((Join-Path $env:SystemRoot 'System32\where.exe'), (Join-Path $dirOtra 'otra.exe'), $true)
    $ops = @(Get-OpcionesHerramientas -Carpeta $carpeta)
    $occt = $ops | Where-Object { $_.Nombre -eq 'OCCT' }
    $otra = $ops | Where-Object { $_.Nombre -eq 'Otra' }
    Assert-Prueba 'OCCT lleva la variable de AMD' ($occt.Variables[$variable] -eq '1')
    Assert-Prueba 'OCCT vigila sus dos procesos' (($occt.Procesos -join ',') -eq 'OCCT,OCCTGUI')
    Assert-Prueba 'OCCT trae una nota' ([bool]$occt.Nota)
    Assert-Prueba 'Las demás no llevan variables ni procesos' (-not $otra.Variables -and -not $otra.Procesos)

    Write-Host 'Comando de inicio'
    $i = Get-InicioHerramienta -Opcion $otra
    Assert-Prueba 'Otra herramienta se abre directo' ($i.FilePath -eq $otra.Exe -and $i.WorkingDirectory -eq $dirOtra -and -not $i.ContainsKey('Verb'))
    $i = Get-InicioHerramienta -Opcion $occt
    Assert-Prueba 'OCCT parte desde cmd' ($i.FilePath -like '*\System32\cmd.exe')
    # En GitHub la batería corre elevada: ahí el cmd no pide elevar.
    $yaAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($yaAdmin) { Assert-Prueba 'Ya en admin no vuelve a pedir elevar' (-not $i.ContainsKey('Verb')) } else { Assert-Prueba 'Sin admin pide elevar' ($i['Verb'] -eq 'RunAs') }
    Assert-Prueba 'La ventana del cmd va oculta' ($i.WindowStyle -eq 'Hidden')
    Assert-Prueba 'El comando fija la variable' ($i.ArgumentList -like "*set ""$variable=1""&&*")

    Write-Host 'La variable llega al programa, sin elevar'
    $casos = @{
        'sin espacios'  = 'Simple'
        'con espacios'  = 'Con espacios y (parentesis)'
        'con acentos'   = 'Atención técnico ñ'
    }
    foreach ($caso in $casos.Keys) {
        $dir = Join-Path (Join-Path $Base $casos[$caso]) 'OCCT'
        $null = New-Item -ItemType Directory -Force -Path $dir
        $salida = Join-Path $dir 'salida.txt'
        # .cmd falso: anota la variable y la carpeta de trabajo. Se escribe en ASCII/OEM y sin ruta dentro.
        $falso = Join-Path $dir 'falso.cmd'
        [IO.File]::WriteAllText($falso, "@echo off`r`n>salida.txt echo [%$variable%]`r`n>>salida.txt cd`r`nexit`r`n", [Text.Encoding]::ASCII)
        $op = [pscustomobject]@{ Nombre = 'OCCT'; Exe = $falso; Variables = @{ $variable = '1' }; Procesos = $null }
        $i = Get-InicioHerramienta -Opcion $op
        $i.Remove('Verb')
        Start-Process @i -ErrorAction Stop
        $llego = Wait-Archivo $salida
        Assert-Prueba "Ruta ${caso}: el programa partió" $llego
        if ($llego) {
            Start-Sleep -Milliseconds 400
            $l = [IO.File]::ReadAllLines($salida, [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage))
            Assert-Prueba "Ruta ${caso}: recibió la variable" ($l[0] -eq '[1]') "salió: $($l -join ' | ')"
            Assert-Prueba "Ruta ${caso}: carpeta de trabajo correcta" ($l[1] -eq $dir) "salió: $($l[1])"
        }
    }

    # Con & en la ruta un .cmd no sirve de prueba: Windows lo abre con cmd /K y lo corta en el &.
    # OCCT es un .exe, así que aquí va un .exe de verdad: una copia de cmd.exe, que se queda abierta.
    Write-Host 'Ruta con ampersand, con un .exe'
    $dir = Join-Path (Join-Path $Base 'Mis cosas & otras') 'OCCT'
    $null = New-Item -ItemType Directory -Force -Path $dir
    $exe = Join-Path $dir 'OCCT.exe'
    [IO.File]::Copy((Join-Path $env:SystemRoot 'System32\cmd.exe'), $exe, $true)
    $op = [pscustomobject]@{ Nombre = 'OCCT'; Exe = $exe; Variables = @{ $variable = '1' }; Procesos = $null }
    $i = Get-InicioHerramienta -Opcion $op
    $i.Remove('Verb')
    Start-Process @i -ErrorAction Stop
    $t0 = Get-Date
    $proc = $null
    while (-not $proc -and ((Get-Date) - $t0).TotalSeconds -lt 15) {
        $proc = Get-Process -Name OCCT -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
        if (-not $proc) { Start-Sleep -Milliseconds 200 }
    }
    Assert-Prueba 'Ruta con ampersand: el programa partió' ([bool]$proc)
    if ($proc) {
        $proc | Stop-Process -Force
        $proc | ForEach-Object { $_.WaitForExit(5000) | Out-Null }
    }

    Write-Host 'Un OCCT colgado bloquea y avisa'
    $dirFalso = Join-Path $Base 'colgado'
    $null = New-Item -ItemType Directory -Force -Path $dirFalso
    $exeFalso = Join-Path $dirFalso 'OCCT.exe'
    [IO.File]::Copy((Join-Path $env:SystemRoot 'System32\PING.EXE'), $exeFalso, $true)
    $vivo = Start-Process -FilePath $exeFalso -ArgumentList '-n 30 127.0.0.1' -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 500
        $msg = $null
        try { Start-Herramienta -Opcion $occt } catch { $msg = $_.Exception.Message }
        Assert-Prueba 'Lanza el aviso en vez de abrir' ($msg -like '*ya está corriendo*Administrador de tareas*') "salió: $msg"
    } finally {
        Stop-Process -Id $vivo.Id -Force -ErrorAction SilentlyContinue
        $vivo.WaitForExit(5000) | Out-Null
    }
    $falsaOtra = [pscustomobject]@{ Nombre = 'Otra'; Exe = (Join-Path $env:SystemRoot 'System32\where.exe'); Variables = $null; Procesos = $null }
    $msg = $null
    try { Start-Herramienta -Opcion $falsaOtra } catch { $msg = $_.Exception.Message }
    Assert-Prueba 'Sin procesos vigilados abre normal' (-not $msg) "salió: $msg"
    Assert-Prueba '-WhatIf no abre nada' ($null -eq (Start-Herramienta -Opcion $falsaOtra -WhatIf))

    if ($ConUac) {
        Write-Host 'Con UAC: acepta el aviso de Windows'
        $dir = Join-Path $Base 'uac'
        $null = New-Item -ItemType Directory -Force -Path $dir
        $salida = Join-Path $dir 'salida.txt'
        $falso = Join-Path $dir 'falso.cmd'
        $elevado = 'net session >nul 2>&1 && (>>salida.txt echo admin) || (>>salida.txt echo sin-admin)'
        [IO.File]::WriteAllText($falso, "@echo off`r`n>salida.txt echo [%$variable%]`r`n$elevado`r`nexit`r`n", [Text.Encoding]::ASCII)
        $op = [pscustomobject]@{ Nombre = 'OCCT'; Exe = $falso; Variables = @{ $variable = '1' }; Procesos = $null }
        Start-Herramienta -Opcion $op
        $llego = Wait-Archivo $salida 90
        Assert-Prueba 'Con UAC: el programa partió' $llego
        if ($llego) {
            Start-Sleep -Seconds 2
            $l = [IO.File]::ReadAllLines($salida)
            Assert-Prueba 'Con UAC: recibió la variable' ($l[0] -eq '[1]') "salió: $($l -join ' | ')"
            Assert-Prueba 'Con UAC: corre como admin' ($l[1] -eq 'admin') "salió: $($l -join ' | ')"
        }
    }
} finally {
    # Si una prueba falló, no deja ventanas abiertas ni la carpeta trabada.
    Get-CimInstance Win32_Process | Where-Object { ($_.CommandLine -and $_.CommandLine.Contains($Base)) -or ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($Base)) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "Resultado: $script:Ok OK, $script:Mal mal"
if ($script:Mal) { exit 1 }
