# Herramienta de desarrollo (no es parte del kit): asegura BOM UTF-8 en los .ps1 del kit, revisa
# la sintaxis, corre diagnostico.ps1 en un proceso nuevo (como INICIAR.cmd) y muestra lo generado.
param([string[]]$Argumentos = @(), [switch]$SoloResumen, [string[]]$Csv = @())
$raiz = Split-Path -Parent $PSScriptRoot
$bom = [byte[]](0xEF, 0xBB, 0xBF)
Get-ChildItem $raiz -Recurse -Include *.ps1 | Where-Object FullName -NotMatch '\\herramientas\\' | ForEach-Object {
    $b = [IO.File]::ReadAllBytes($_.FullName)
    if ($b.Length -lt 3 -or $b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF) {
        [IO.File]::WriteAllBytes($_.FullName, $bom + $b)
        "(BOM agregado a $($_.Name))"
    }
}
$malos = 0
Get-ChildItem $raiz -Recurse -Include *.ps1 | Where-Object FullName -NotMatch '\\herramientas\\' | ForEach-Object {
    $tokens = $null; $errores = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errores)
    foreach ($e in $errores) { "PARSE $($_.Name):$($e.Extent.StartLineNumber):$($e.Extent.StartColumnNumber) $($e.Message)"; $malos++ }
}
if ($malos) { return }
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$inicio = Get-Date
& $ps -NoProfile -ExecutionPolicy Bypass -File "$raiz\KIT\scripts\diagnostico.ps1" @Argumentos
"--- código de salida: $LASTEXITCODE"
$resumen = Get-ChildItem "$raiz\KIT\clientes" -Recurse -Filter resumen.txt -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $inicio } | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $resumen) { 'No se generó resumen.txt'; return }
$nueva = $resumen.Directory
"=== resumen.txt ($($nueva.FullName.Substring($raiz.Length + 1))) ==="
Get-Content -Encoding UTF8 $resumen.FullName
if (-not $SoloResumen) {
    "=== archivos ==="
    Get-ChildItem $nueva.FullName -Recurse -File | ForEach-Object { '{0,-40} {1,10:N0} B' -f $_.FullName.Substring($nueva.FullName.Length + 1), $_.Length }
    $err = Select-String -Path (Join-Path $nueva.FullName 'log.txt') -Pattern ' ERROR ' -SimpleMatch -CaseSensitive -ErrorAction SilentlyContinue
    if ($err) { "=== errores en log.txt ==="; $err | ForEach-Object { $_.Line } }
}
foreach ($c in $Csv) {
    "=== csv\$c.csv ==="
    Import-Csv -Delimiter ';' -Encoding UTF8 (Join-Path $nueva.FullName "csv\$c.csv") | Format-Table -AutoSize | Out-String -Width 220
}
