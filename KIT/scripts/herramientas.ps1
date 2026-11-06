#Requires -Version 5.1
<#
.SYNOPSIS
    Menú de las herramientas portables del kit (KIT\herramientas).
.DESCRIPTION
    Muestra una opción por cada carpeta de herramientas\ que tenga un .exe: las que baja
    actualizar_herramientas.ps1 (versiones.json dice cuál es el ejecutable) y las que agregaste
    a mano. No modifica nada: solo abre el programa que elijas.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Menú interactivo de consola')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'Clear-Host es una función integrada de 5.1; el perfil de compatibilidad solo lista cmdlets de módulos')]
param()

$ErrorActionPreference = 'Stop'
$carpeta = Join-Path (Split-Path -Parent $PSScriptRoot) 'herramientas'

. (Join-Path $PSScriptRoot 'lib\Herramientas.ps1')

while ($true) {
    Clear-Host
    Write-Host ''
    Write-Host ' HERRAMIENTAS DEL KIT' -ForegroundColor Cyan
    Write-Host ' --------------------' -ForegroundColor Cyan
    $opciones = @(Get-OpcionesHerramientas -Carpeta $carpeta)
    if ($opciones.Count -eq 0) {
        Write-Host ' No hay herramientas en KIT\herramientas. Corre actualizar_herramientas.ps1 en tu equipo.' -ForegroundColor Yellow
        Write-Host ''
        Read-Host ' Enter para volver' | Out-Null
        return
    }
    for ($i = 0; $i -lt $opciones.Count; $i++) {
        $o = $opciones[$i]
        $texto = ' {0,2}) {1,-22} {2,-14}' -f ($i + 1), $o.Nombre, $(if ($o.Version) { $o.Version } else { '' })
        if (-not $o.Exe) { Write-Host "$texto (falta: no hay ejecutable en la carpeta)" -ForegroundColor DarkGray; continue }
        if ($o.Personal) { Write-Host "$texto (solo con licencia comercial)" -ForegroundColor Yellow; continue }
        Write-Host $texto
    }
    Write-Host ''
    $r = Read-Host ' Número (Enter para volver)'
    if (-not $r) { return }
    $n = 0
    if (-not [int]::TryParse($r, [ref]$n) -or $n -lt 1 -or $n -gt $opciones.Count) { continue }
    $o = $opciones[$n - 1]
    if (-not $o.Exe) { continue }
    Write-Host ''
    Write-Host " $($o.Nombre) | licencia: $($o.Licencia)"
    if ($o.Nota) { Write-Host " Ojo: $($o.Nota)" -ForegroundColor Yellow }
    try {
        Start-Herramienta -Opcion $o
        Write-Host ' Abierta.' -ForegroundColor Green
    } catch {
        Write-Host " No se pudo abrir: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}
