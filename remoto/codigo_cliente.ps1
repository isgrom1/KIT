#Requires -Version 5.1
<#
.SYNOPSIS
    Crea el código de un cliente para el diagnóstico a distancia y deja listo el mensaje para WhatsApp.
.DESCRIPTION
    El código (NOMBRE-XXXX-XXXX) lo pide la ventana del paquete antes de empezar: sin él, un link reenviado no
    sirve. Vence en "dias_codigo" días (config.json, remoto). El mensaje (con el link de la página, el código y
    el código de Isaac) queda copiado para pegar, y cada código se anota en privado\codigos_emitidos.csv.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remoto\codigo_cliente.ps1 -Nombre Beli
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para Isaac')]
[CmdletBinding()]
param(
    [string]$Nombre,
    [int]$Dias,
    [switch]$SinCopiar,
    [switch]$PassThru   # devuelve Codigo/Vence/Mensaje (la ventana del Centro y las pruebas)
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'motor\Cifrado.ps1')
$cfg = Get-Content -LiteralPath (Join-Path $repo 'KIT\scripts\config\config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $Dias) { $Dias = if ($cfg.remoto.dias_codigo) { [int]$cfg.remoto.dias_codigo } else { 7 } }
if (-not $Nombre) { $Nombre = Read-Host ' Nombre del cliente (como para reconocerlo: Beli, JuanPerez)' }
$rutaClave = Get-RutaClaveCodigo -Repo $repo -Crear
if (-not $rutaClave) { throw 'No está la carpeta del maestro (config.json, sincronizacion.ruta_maestro): ahí va la clave de los códigos.' }
$clave = [Convert]::FromBase64String([IO.File]::ReadAllText($rutaClave).Trim())
$codigo = New-CodigoCliente -Nombre $Nombre -Dias $Dias -Clave $clave
$v = Test-CodigoCliente -Codigo $codigo -Clave $clave
$isaac = Get-CodigoIsaac -LlavePublicaXml ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'llave_publica.xml')))
$pagina = "$($cfg.remoto.pagina)"
$saludo = (Get-Culture).TextInfo.ToTitleCase("$Nombre".Trim().ToLower())
$mensaje = "¡Hola $saludo! Este es el diagnóstico a distancia de tu computador:`r`n$pagina`r`n`r`n" +
"Tu código para empezar: $codigo (sirve hasta el $($v.Vence.ToString('dd-MM-yyyy')))`r`n`r`n" +
"Descargas el ZIP, lo descomprimes y abres DIAGNOSTICO.cmd. La ventana tiene que decir ""Paquete verificado"" y mostrar ISAAC · $isaac; ahí escribes tu código y aprietas Empezar. Al final me mandas el archivo .kitdiag que te queda (va cifrado, solo yo lo puedo abrir)."

# Registro de códigos entregados (para saber de quién es cada .kitdiag que llega).
$reg = Join-Path (Split-Path -Parent $rutaClave) 'codigos_emitidos.csv'
$linea = '{0};{1};{2};{3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), $v.Nombre, $codigo, $v.Vence.ToString('yyyy-MM-dd')
if (-not [IO.File]::Exists($reg)) { [IO.File]::WriteAllText($reg, "fecha;cliente;codigo;vence`r`n", (New-Object Text.UTF8Encoding $true)) }
[IO.File]::AppendAllText($reg, "$linea`r`n", (New-Object Text.UTF8Encoding $false))

if (-not $SinCopiar) { try { Set-Clipboard -Value $mensaje } catch { Write-Verbose $_ } }
if ($PassThru) { return [pscustomobject]@{ Codigo = $codigo; Vence = $v.Vence; Mensaje = $mensaje } }
Write-Host ''
Write-Host " Código para $($v.Nombre): $codigo" -ForegroundColor Green
Write-Host " Vence el $($v.Vence.ToString('dd-MM-yyyy'))" -ForegroundColor Gray
Write-Host ''
Write-Host $mensaje
Write-Host ''
if (-not $SinCopiar) { Write-Host ' (El mensaje quedó copiado: pégalo en WhatsApp.)' -ForegroundColor Cyan }
