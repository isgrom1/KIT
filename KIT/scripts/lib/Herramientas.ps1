# Herramientas.ps1 - Las herramientas portables de KIT\herramientas: una opción por carpeta con un .exe
# (las del actualizador según versiones.json y las agregadas a mano). Lo usan el menú de consola y la GUI.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

function Get-OpcionesHerramientas {
    param([Parameter(Mandatory)][string]$Carpeta)
    $excluir = '(?i)unins|uninst|setup|install|update|vcredist|crash|helper'
    $registro = @{}
    $rutaVersiones = Join-Path $Carpeta 'versiones.json'
    if (Test-Path -LiteralPath $rutaVersiones) {
        try { foreach ($e in @(([IO.File]::ReadAllText($rutaVersiones) | ConvertFrom-Json).herramientas)) { $registro[$e.carpeta] = $e } } catch { $registro = @{} }
    }
    $nombres = @($registro.Keys)
    if (Test-Path -LiteralPath $Carpeta) {
        $nombres += @(Get-ChildItem -LiteralPath $Carpeta -Directory | Where-Object { $_.Name -notmatch '\.nuevo$|_manual_\d' } | ForEach-Object { $_.Name })
    }
    foreach ($nombre in ($nombres | Sort-Object -Unique)) {
        $e = $registro[$nombre]
        $dir = Join-Path $Carpeta $nombre
        $exe = $null
        if ($e -and $e.ejecutable -and (Test-Path -LiteralPath (Join-Path $dir $e.ejecutable))) {
            $exe = Join-Path $dir $e.ejecutable
        } elseif (Test-Path -LiteralPath $dir) {
            # Agregada a mano (o sin registro): el exe de 64 bits con la ruta más corta.
            $exe = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.exe | Where-Object { $_.Name -notmatch $excluir } |
                    Sort-Object @{ Expression = { if ($_.FullName -match '(?i)arm64') { 2 } elseif ($_.Name -match '64') { 0 } else { 1 } } }, @{ Expression = { $_.FullName.Length } } |
                    Select-Object -First 1 | ForEach-Object { $_.FullName })
            if ($exe.Count -eq 0) { $exe = $null } else { $exe = $exe[0] }
        }
        [pscustomobject]@{
            Nombre   = $nombre
            Version  = $(if ($e -and $e.version) { $e.version } elseif ($exe) { [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion } else { $null })
            Exe      = $exe
            Licencia = $(if ($e) { $e.licencia } else { 'agregada a mano: revisa su licencia' })
            Nota     = $(if ($e) { $e.nota } else { $null })
            Personal = ($nombre -match '(?i)hwinfo|occt|wiztree' -or ($e -and $e.uso_comercial -eq $false))
        }
    }
}
