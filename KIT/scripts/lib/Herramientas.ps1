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
        $esOcct = $nombre -match '(?i)^occt'
        $nota = if ($e) { $e.nota } else { $null }
        if (-not $nota -and $esOcct) { $nota = 'pide admin y la primera vez en cada equipo puede tardar un rato en abrir' }
        [pscustomobject]@{
            Nombre    = $nombre
            Version   = $(if ($e -and $e.version) { $e.version } elseif ($exe) { [Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion } else { $null })
            Exe       = $exe
            Licencia  = $(if ($e) { $e.licencia } else { 'agregada a mano: revisa su licencia' })
            Nota      = $nota
            Personal  = ($nombre -match '(?i)hwinfo|occt|wiztree' -or ($e -and $e.uso_comercial -eq $false))
            # OCCT se cae en vulkan-1.dll en notebooks AMD + NVIDIA con la capa antigua de AMD: se apaga solo para este proceso.
            Variables = $(if ($esOcct) { @{ DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1 = '1' } } else { $null })
            # Si queda uno colgado ("Suspendido"), el nuevo no abre ni avisa.
            Procesos  = $(if ($esOcct) { @('OCCT', 'OCCTGUI') } else { $null })
            # Prueba fija de CALOR (CPU, 10 min, Normal, Steady): se aplica a su configuración al abrirlo.
            ConfigBase = $(if ($esOcct) { Join-Path (Split-Path -Parent $PSScriptRoot) 'config\occt_prueba.json' } else { $null })
        }
    }
}

function Get-InicioHerramienta {
    # Parámetros de Start-Process para abrir una herramienta. Sin variables propias, se abre tal cual.
    # Con variables no se puede contar con que pasen por el UAC: un cmd elevado las fija y lanza el
    # programa, que hereda el admin. Es un solo UAC y el cmd se cierra de inmediato.
    param([Parameter(Mandatory)]$Opcion)
    $dir = Split-Path -Parent $Opcion.Exe
    if (-not $Opcion.Variables) { return @{ FilePath = $Opcion.Exe; WorkingDirectory = $dir } }
    $sets = @($Opcion.Variables.GetEnumerator() | Sort-Object Name | ForEach-Object { 'set "{0}={1}"&&' -f $_.Name, $_.Value }) -join ' '
    $inicio = @{
        FilePath     = (Join-Path $env:SystemRoot 'System32\cmd.exe')
        # cmd /c quita la primera y la última comilla y deja intactas las demás: así aguanta espacios y & en la ruta.
        ArgumentList = ('/c "{0} start "" /d "{1}" "{2}""' -f $sets, $dir, $Opcion.Exe)
        WindowStyle  = 'Hidden'
    }
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) { $inicio['Verb'] = 'RunAs' }
    $inicio
}

function Start-Herramienta {
    # Abre una opción de Get-OpcionesHerramientas. Lanza una excepción con el motivo si no se puede.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Opcion)
    if ($Opcion.Procesos) {
        $vivos = @(Get-Process -Name $Opcion.Procesos -ErrorAction SilentlyContinue)
        if ($vivos.Count) {
            throw "$($Opcion.Nombre) ya está corriendo. Si no ves su ventana, quedó colgado: ciérralo en el Administrador de tareas ($($Opcion.Procesos -join ', ')) y prueba de nuevo."
        }
    }
    # Devuelve una nota para el técnico (la prueba fija de OCCT) o $null.
    $nota = $null
    if ($Opcion.PSObject.Properties['ConfigBase'] -and $Opcion.ConfigBase -and [IO.File]::Exists($Opcion.ConfigBase)) {
        try {
            $c = Set-ConfigOcct -Carpeta (Split-Path -Parent $Opcion.Exe) -Base $Opcion.ConfigBase -WhatIf:$WhatIfPreference
            $nota = switch ($c.Estado) {
                'ok' { 'Prueba fijada: CPU, 10 min, Normal, Steady. Revísala y acepta la licencia si la pide.' }
                'parcial' { "Esta versión de OCCT no tiene $(@($c.NoEncontrados) -join ', '): revisa la prueba antes de partir (CPU, 10 min, Normal, Steady)." }
                default { 'Primera vez de OCCT en este pendrive: elige CPU, 10 min, Normal, Steady. Desde la próxima vez, el kit la deja fija.' }
            }
        } catch { $nota = "No se pudo fijar la prueba de OCCT ($($_.Exception.Message)): revísala antes de partir." }
    }
    $inicio = Get-InicioHerramienta -Opcion $Opcion
    if ($PSCmdlet.ShouldProcess($Opcion.Exe, 'Abrir herramienta')) { Start-Process @inicio -ErrorAction Stop }
    $nota
}

function Set-ConfigOcct {
    # Copia en OCCT.config.json la prueba fija de config\occt_prueba.json y quita los datos del último equipo.
    # Solo cambia valores que ya existen: si OCCT cambió el formato, no inventa campos y los devuelve en
    # NoEncontrados. Sin OCCT.config.json (OCCT nunca se abrió en este pendrive) no hace nada. La prueba
    # anterior queda en OCCT.config.json.bak (sin los datos del equipo). No toca la aceptación de la licencia.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Carpeta, [Parameter(Mandatory)][string]$Base)
    $ruta = Join-Path $Carpeta 'OCCT.config.json'
    if (-not [IO.File]::Exists($ruta)) { return [pscustomobject]@{ Estado = 'sin_config'; Cambios = 0; NoEncontrados = @() } }
    $b = [IO.File]::ReadAllText($Base, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $original = [IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8)
    $cfg = $original | ConvertFrom-Json
    $faltan = New-Object System.Collections.Generic.List[string]
    $cambios = 0
    foreach ($par in $b.valores.PSObject.Properties) {
        $obj = $cfg
        $partes = $par.Name -split '\.'
        $encontrado = $false
        for ($i = 0; $i -lt $partes.Count; $i++) {
            $nombre = $partes[$i]
            $indice = $null
            if ($nombre -match '^(.+)\[(\d+)\]$') { $nombre = $Matches[1]; $indice = [int]$Matches[2] }
            $prop = if ($obj -is [Management.Automation.PSCustomObject]) { $obj.PSObject.Properties[$nombre] } else { $null }
            if (-not $prop) { break }
            if ($i -eq $partes.Count - 1 -and $null -eq $indice) {
                if ("$($prop.Value)" -ne "$($par.Value)") { $prop.Value = $par.Value; $cambios++ }
                $encontrado = $true
                break
            }
            $obj = $prop.Value
            if ($null -ne $indice) {
                $arr = @($obj)
                if ($indice -ge $arr.Count) { break }
                $obj = $arr[$indice]
            }
        }
        if (-not $encontrado) { $faltan.Add($par.Name) }
    }
    foreach ($q in @($b.quitar)) { if ($cfg.PSObject.Properties[$q]) { $cfg.PSObject.Properties.Remove($q); $cambios++ } }
    if ($cambios -and $PSCmdlet.ShouldProcess($ruta, 'Fijar la prueba de OCCT')) {
        # El respaldo guarda la prueba anterior, pero tampoco los datos del equipo anterior.
        $respaldo = $original | ConvertFrom-Json
        foreach ($q in @($b.quitar)) { if ($respaldo.PSObject.Properties[$q]) { $respaldo.PSObject.Properties.Remove($q) } }
        [IO.File]::WriteAllText("$ruta.bak", ($respaldo | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($ruta, ($cfg | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
    }
    [pscustomobject]@{ Estado = $(if ($faltan.Count) { 'parcial' } else { 'ok' }); Cambios = $cambios; NoEncontrados = $faltan.ToArray() }
}
