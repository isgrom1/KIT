#Requires -Version 5.1
<#
.SYNOPSIS
    Crea el par de llaves del diagnóstico remoto (se corre UNA vez, en el PC de Isaac).
.DESCRIPTION
    - La llave PÚBLICA queda en remoto\llave_publica.xml: va dentro de cada paquete y solo sirve para cifrar.
    - La llave PRIVADA queda en %LOCALAPPDATA%\kitservicio\remoto_llave_privada.dat, protegida con DPAPI
      (solo la abre este usuario de Windows en este PC). Sin ella no se puede abrir ningún diagnóstico.
    Si ya existe, no hace nada salvo con -Reemplazar (los diagnósticos cifrados con la llave vieja ya no se abrirán).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remoto\crear_llaves.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para Isaac')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'ProtectedData viene con .NET Framework y se carga con Add-Type -AssemblyName System.Security')]
[CmdletBinding()]
param([switch]$Reemplazar)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
. (Join-Path $PSScriptRoot 'motor\Cifrado.ps1')

$carpeta = Join-Path $env:LOCALAPPDATA 'kitservicio'
$privada = Join-Path $carpeta 'remoto_llave_privada.dat'
$publica = Join-Path $PSScriptRoot 'llave_publica.xml'
if ([IO.File]::Exists($privada) -and -not $Reemplazar) {
    Write-Host "Ya existe la llave privada ($privada). No se cambió nada." -ForegroundColor Yellow
    Write-Host 'Para crear otra (y perder la posibilidad de abrir lo cifrado con la anterior): -Reemplazar'
    exit 0
}
$par = Get-LlavesNuevasRemoto
$null = [IO.Directory]::CreateDirectory($carpeta)
$prot = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($par.Privada), $null, 'CurrentUser')
[IO.File]::WriteAllBytes($privada, $prot)
[IO.File]::WriteAllText($publica, $par.Publica, (New-Object Text.UTF8Encoding $false))
Write-Host 'Llaves creadas.' -ForegroundColor Green
Write-Host "  Pública (va en el paquete): $publica"
Write-Host "  Privada (solo este PC y este usuario): $privada"
