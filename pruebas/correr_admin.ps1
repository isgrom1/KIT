# Herramienta de desarrollo (no es parte del kit): se lanza elevado, corre diagnostico.ps1 en un
# proceso nuevo y guarda lo que muestra en pantalla para revisarlo después.
# Con -File los arreglos llegan como un solo texto, por eso -Secciones es un string ("1,7").
param([Parameter(Mandatory)][string]$Salida, [string]$Secciones, [switch]$SinEspacio)
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argumentos = @()
if ($Secciones) { $argumentos += '-Secciones', $Secciones }
if ($SinEspacio) { $argumentos += '-SinEspacio' }
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts\diagnostico.ps1') @argumentos 2>&1 | Tee-Object -FilePath $Salida
"--- código de salida: $LASTEXITCODE" | Tee-Object -FilePath $Salida -Append
Start-Sleep -Seconds 3
