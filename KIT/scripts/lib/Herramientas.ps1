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
    $inicio = Get-InicioHerramienta -Opcion $Opcion
    if ($PSCmdlet.ShouldProcess($Opcion.Exe, 'Abrir herramienta')) { Start-Process @inicio -ErrorAction Stop }
}
