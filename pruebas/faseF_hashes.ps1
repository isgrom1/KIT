#Requires -Version 5.1
# Fase F — SHA-256 de cada archivo de una carpeta (ruta relativa -> hash, tamaño y fecha), para comprobar
# que ARCHIVOS deja todo igual después de mover y deshacer. Con -Comparar dice qué cambió.
param([Parameter(Mandatory)][string]$Carpeta, [string]$Salida, [string]$Comparar)
$ErrorActionPreference = 'Stop'
$raiz = $Carpeta.TrimEnd('\')
$mapa = [ordered]@{}
foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -File -Force | Sort-Object FullName)) {
    $mapa[$f.FullName.Substring($raiz.Length + 1)] = '{0}|{1}|{2}' -f (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash, $f.Length, $f.LastWriteTimeUtc.ToString('s')
}
if ($Salida) { [IO.File]::WriteAllText($Salida, ($mapa | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) }
if ($Comparar) {
    $antes = Get-Content -LiteralPath $Comparar -Raw | ConvertFrom-Json
    $a = @{}; foreach ($p in $antes.PSObject.Properties) { $a[$p.Name] = $p.Value }
    $faltan = @($a.Keys | Where-Object { -not $mapa.Contains($_) })
    $sobran = @($mapa.Keys | Where-Object { -not $a.ContainsKey($_) })
    $distintos = @($mapa.Keys | Where-Object { $a.ContainsKey($_) -and $a[$_] -ne $mapa[$_] })
    [pscustomobject]@{ Archivos = $mapa.Count; Antes = $a.Count; Faltan = $faltan; Sobran = $sobran; Distintos = $distintos; Igual = ($faltan.Count + $sobran.Count + $distintos.Count -eq 0) }
} else { "$($mapa.Count) archivos" }
