# Comun.ps1 - Contexto del kit, rutas, permisos y lectura de CIM, registro y comandos externos.
# Todo aquí es de solo lectura. Las carpetas del cliente las crea lib\Expediente.ps1, dentro de
# KIT\clientes (la única escritura que hace el diagnóstico).

$script:CulturaCL = [Globalization.CultureInfo]::GetCultureInfo('es-CL')
$script:Invariante = [Globalization.CultureInfo]::InvariantCulture
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Utf8SinBom = New-Object System.Text.UTF8Encoding($false)

function Read-JsonKit {
    param([Parameter(Mandatory)][string]$Ruta)
    [IO.File]::ReadAllText($Ruta, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Read-JsonKitOpcional {
    # Como Read-JsonKit, pero $null si el archivo no existe.
    param([string]$Ruta)
    if ($Ruta -and [IO.File]::Exists($Ruta)) { Read-JsonKit $Ruta } else { $null }
}

function Initialize-Contexto {
    param([Parameter(Mandatory)][string]$RaizScripts)
    $raizKit = Split-Path -Parent $RaizScripts
    $script:Ctx = [ordered]@{
        Version         = '0.1.0'
        Inicio          = Get-Date
        Reloj           = [Diagnostics.Stopwatch]::StartNew()
        RaizKit         = $raizKit
        RaizScripts     = $RaizScripts
        CarpetaConfig   = Join-Path $RaizScripts 'config'
        CarpetaClientes = Join-Path $raizKit 'clientes'
        CarpetaCliente  = $null
        Config          = Read-JsonKit (Join-Path $RaizScripts 'config\config.json')
        Parametros      = $null
        Admin           = $null
        Identidad       = $null
        Expediente      = $null
        Datos           = [ordered]@{}
        Tablas          = [ordered]@{}
        Alertas         = New-Object System.Collections.Generic.List[object]
        Incompletos     = New-Object System.Collections.Generic.List[object]
        Errores         = New-Object System.Collections.Generic.List[object]
        Secciones       = New-Object System.Collections.Generic.List[object]
        SeccionActual   = ''
        SeccionNumero   = 0
        EstadoForzado   = $null
        LogPendiente    = New-Object System.Collections.Generic.List[string]
        Reemplazos      = @()
        AliasPerfiles   = @{}
        CodificacionOem = $null
        CacheEmpresa    = @{}
    }
}

# ---------------------------------------------------------------- permisos

function Get-EstadoAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $elevado = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $miembro = $elevado
    if (-not $elevado) {
        # Con UAC, un admin sin elevar tiene el grupo Administradores como "solo denegar";
        # whoami lo lista igual, así distinguimos "admin sin elevar" de "usuario estándar".
        try {
            $r = Invoke-Externo -Exe (Get-RutaSistema 'whoami.exe') -Argumentos '/groups' -TimeoutSeg 15
            $miembro = $r.Salida -match 'S-1-5-32-544'
        } catch {
            $miembro = $false
        }
    }
    [pscustomobject][ordered]@{ Elevado = [bool]$elevado; MiembroAdministradores = [bool]$miembro }
}

# ---------------------------------------------------------------- CIM

function Get-Cim {
    param(
        [Parameter(Mandatory)][string]$Clase,
        [string]$Namespace = 'root/cimv2',
        [string]$Filtro,
        [string[]]$Propiedades
    )
    $p = @{
        ClassName           = $Clase
        Namespace           = $Namespace
        OperationTimeoutSec = [int]$script:Ctx.Config.cim_timeout_seg
        ErrorAction         = 'Stop'
    }
    if ($Filtro) { $p.Filter = $Filtro }
    if ($Propiedades) { $p.Property = $Propiedades }
    Get-CimInstance @p
}

# ---------------------------------------------------------------- registro (siempre solo lectura)

function Open-ClaveRegistro {
    param(
        [Parameter(Mandatory)][ValidateSet('HKLM', 'HKCU')][string]$Colmena,
        [Parameter(Mandatory)][string]$Ruta,
        [ValidateSet(64, 32)][int]$Vista = 64
    )
    $h = if ($Colmena -eq 'HKLM') { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
    $v = if ($Vista -eq 32) { [Microsoft.Win32.RegistryView]::Registry32 } else { [Microsoft.Win32.RegistryView]::Registry64 }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, $v)
    try { $base.OpenSubKey($Ruta, $false) } finally { $base.Dispose() }
}

function Get-ValoresRegistro {
    # Diccionario nombre -> valor; vacío si la clave no existe.
    param(
        [Parameter(Mandatory)][string]$Colmena,
        [Parameter(Mandatory)][string]$Ruta,
        [int]$Vista = 64
    )
    $r = [ordered]@{}
    $k = Open-ClaveRegistro -Colmena $Colmena -Ruta $Ruta -Vista $Vista
    if ($null -eq $k) { return $r }
    try {
        foreach ($n in $k.GetValueNames()) { $r[$n] = $k.GetValue($n) }
    } finally { $k.Dispose() }
    $r
}

function Get-ValorRegistro {
    param(
        [Parameter(Mandatory)][string]$Colmena,
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Nombre,
        [int]$Vista = 64
    )
    $k = Open-ClaveRegistro -Colmena $Colmena -Ruta $Ruta -Vista $Vista
    if ($null -eq $k) { return $null }
    try { $k.GetValue($Nombre) } finally { $k.Dispose() }
}

function Get-SubclavesRegistro {
    param(
        [Parameter(Mandatory)][string]$Colmena,
        [Parameter(Mandatory)][string]$Ruta,
        [int]$Vista = 64
    )
    $k = Open-ClaveRegistro -Colmena $Colmena -Ruta $Ruta -Vista $Vista
    if ($null -eq $k) { return @() }
    try { $k.GetSubKeyNames() } finally { $k.Dispose() }
}

# ---------------------------------------------------------------- comandos externos

function Get-RutaSistema {
    param([Parameter(Mandatory)][string]$Exe)
    $dir = 'System32'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $dir = 'Sysnative' }
    Join-Path (Join-Path $env:SystemRoot $dir) $Exe
}

function Get-CodificacionOem {
    if ($null -eq $script:Ctx.CodificacionOem) {
        $cp = 850
        try {
            $v = Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Nombre 'OEMCP'
            if ($v) { $cp = [int]$v }
            $script:Ctx.CodificacionOem = [Text.Encoding]::GetEncoding($cp)
        } catch {
            $script:Ctx.CodificacionOem = [Text.Encoding]::GetEncoding(850)
        }
    }
    $script:Ctx.CodificacionOem
}

function Invoke-Externo {
    # Ejecuta un comando de Windows sin ventana, con timeout, y devuelve su salida como texto.
    param(
        [Parameter(Mandatory)][string]$Exe,
        [string]$Argumentos = '',
        [int]$TimeoutSeg = 0
    )
    if ($TimeoutSeg -le 0) { $TimeoutSeg = [int]$script:Ctx.Config.externo_timeout_seg }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Argumentos
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Sin consola propia, las herramientas de Windows escriben en la página de códigos OEM del sistema.
    $psi.StandardOutputEncoding = Get-CodificacionOem
    $psi.StandardErrorEncoding = Get-CodificacionOem
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $salida = $p.StandardOutput.ReadToEndAsync()
        $errores = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeg * 1000)) {
            try { $p.Kill() } catch { Write-LogKit -Nivel AVISO -Mensaje "No se pudo cerrar $Exe tras el timeout: $($_.Exception.Message)" }
            return [pscustomobject]@{ Codigo = -1; Salida = ''; Error = "timeout de $TimeoutSeg s"; TimeOut = $true }
        }
        $p.WaitForExit()
        [pscustomobject]@{ Codigo = $p.ExitCode; Salida = $salida.Result; Error = $errores.Result; TimeOut = $false }
    } finally { $p.Dispose() }
}

# ---------------------------------------------------------------- ejecutables y empresa

function Get-RutaDesdeComando {
    # Ruta del ejecutable dentro de una línea de comando: "C:\a b\x.exe" -p, C:\x.exe /b, rundll32 a.dll,F
    param([AllowEmptyString()][string]$Comando)
    if (-not $Comando) { return '' }
    $c = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($c.StartsWith('"')) {
        $fin = $c.IndexOf('"', 1)
        if ($fin -gt 1) { return $c.Substring(1, $fin - 1) }
        return $c.Trim('"')
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd|vbs|vbe|js|jse|wsf|ps1|scr|lnk|dll|cpl|msc))(?=\s|,|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    ($c -split '\s+')[0]
}

function Resolve-RutaEjecutable {
    # Normaliza rutas de servicios y Run (\??\, \SystemRoot\, system32\..., nombres sueltos).
    param([AllowEmptyString()][string]$Ruta)
    if (-not $Ruta) { return '' }
    $r = $Ruta -replace '^\\\?\?\\', ''
    $r = $r -replace '^(?i)\\SystemRoot\\', ($env:SystemRoot + '\')
    if ($r -match '^(?i)system32\\') { $r = Join-Path $env:SystemRoot $r }
    if ($r -notmatch '\\') {
        $candidato = Join-Path (Join-Path $env:SystemRoot 'System32') $r
        if ([IO.File]::Exists($candidato)) { return $candidato }
        if ([IO.File]::Exists("$candidato.exe")) { return "$candidato.exe" }
    }
    $r
}

function Get-EmpresaArchivo {
    # CompanyName del archivo. No se verifica la firma: Get-AuthenticodeSignature puede consultar
    # revocación de certificados por red, y el diagnóstico no usa red. '' si no se puede leer.
    param([AllowEmptyString()][string]$Ruta)
    if (-not $Ruta) { return '' }
    if ($script:Ctx.CacheEmpresa.ContainsKey($Ruta)) { return $script:Ctx.CacheEmpresa[$Ruta] }
    $empresa = ''
    try {
        if ([IO.File]::Exists($Ruta)) { $empresa = "$([Diagnostics.FileVersionInfo]::GetVersionInfo($Ruta).CompanyName)".Trim() }
    } catch {
        $empresa = ''
    }
    $script:Ctx.CacheEmpresa[$Ruta] = $empresa
    $empresa
}

# ---------------------------------------------------------------- software conocido (config\software_conocido.json)

function Get-ListaSoftwareConocido {
    if (-not $script:Ctx.Contains('SoftwareConocido')) {
        $script:Ctx.SoftwareConocido = Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'software_conocido.json')
    }
    $script:Ctx.SoftwareConocido
}

function Find-SoftwareConocido {
    # Devuelve la primera entrada de la lista cuyo patrón aparece en alguno de los textos, o $null.
    param([AllowEmptyString()][string[]]$Textos)
    $lista = Get-ListaSoftwareConocido
    foreach ($e in $lista.programas) {
        foreach ($t in $Textos) {
            if ($t -and $t -match "(?i)$($e.patron)") {
                $cat = $lista.categorias.($e.categoria)
                return [pscustomobject]@{ Categoria = $e.categoria; Severidad = $cat.severidad; Texto = $cat.texto; Patron = $e.patron }
            }
        }
    }
    $null
}

function Add-AlertasSoftwareConocido {
    # Una alerta por categoría: "Optimizador detectado: Hone (HKCU), ..."
    param([AllowEmptyCollection()][object[]]$Hallazgos, [string]$Prefijo)
    foreach ($g in @($Hallazgos | Where-Object { $_ } | Group-Object Categoria)) {
        $primero = $g.Group[0]
        $nombres = @($g.Group | ForEach-Object { "$($_.Nombre) ($($_.Donde))" } | Sort-Object -Unique)
        Add-Alerta -Severidad $primero.Severidad -Codigo ("$Prefijo-" + $g.Name.ToUpper()) -Texto "$($primero.Texto): $($nombres -join ', ')"
    }
}

# ---------------------------------------------------------------- formatos

function ConvertTo-TextoFecha {
    param($Fecha, [switch]$SoloFecha)
    if ($null -eq $Fecha -or $Fecha -isnot [datetime]) { return $null }
    $formato = if ($SoloFecha) { 'yyyy-MM-dd' } else { 'yyyy-MM-dd HH:mm:ss' }
    $Fecha.ToString($formato, $script:Invariante)
}

function ConvertTo-GB {
    param([double]$Bytes, [int]$Decimales = 2)
    [math]::Round($Bytes / 1GB, $Decimales)
}

function Format-Numero {
    param([double]$Valor, [int]$Decimales = 1)
    $Valor.ToString("N$Decimales", $script:CulturaCL)
}

function Format-Tamano {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return "$(Format-Numero ($Bytes / 1TB) 2) TB" }
    if ($Bytes -ge 1GB) { return "$(Format-Numero ($Bytes / 1GB) 1) GB" }
    if ($Bytes -ge 1MB) { return "$(Format-Numero ($Bytes / 1MB) 0) MB" }
    "$(Format-Numero ($Bytes / 1KB) 0) KB"
}

function Format-Duracion {
    param([double]$Segundos)
    $t = [TimeSpan]::FromSeconds($Segundos)
    if ($t.TotalHours -ge 1) { return '{0}:{1:00}:{2:00}' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds }
    '{0:00}:{1:00}' -f $t.Minutes, $t.Seconds
}

# ---------------------------------------------------------------- identidad y carpeta del cliente

function Test-ValorGenerico {
    param([AllowEmptyString()][string]$Valor)
    $Valor -match '^(?i)\s*(to be filled.*|default string|system (serial|product) number|chassis serial number|none|n/?a|not applicable|oem|0+|1234567890?|x+)?\s*$'
}

function ConvertTo-FabricanteCorto {
    param([AllowEmptyString()][string]$Fabricante)
    $m = "$Fabricante".Trim()
    switch -Regex ($m) {
        '^(?i)asus' { return 'ASUS' }
        '^(?i)(hewlett|hp\b)' { return 'HP' }
        '^(?i)dell' { return 'Dell' }
        '^(?i)lenovo' { return 'Lenovo' }
        '^(?i)acer' { return 'Acer' }
        '^(?i)(micro-star|msi\b)' { return 'MSI' }
        '^(?i)gigabyte' { return 'Gigabyte' }
        '^(?i)samsung' { return 'Samsung' }
        '^(?i)microsoft' { return 'Microsoft' }
        '^(?i)huawei' { return 'Huawei' }
        '^(?i)(toshiba|dynabook)' { return 'Toshiba' }
    }
    if (Test-ValorGenerico $m) { return 'Generico' }
    ($m -replace '(?i)[,.]?\s*\b(inc|corp(oration)?|co|ltd|limited|gmbh|s\.?a)\b\.?', '').Trim()
}

function Get-IdentidadEquipo {
    $cs = Get-Cim -Clase Win32_ComputerSystem -Propiedades Manufacturer, Model
    $bios = Get-Cim -Clase Win32_BIOS -Propiedades SerialNumber
    $fabricante = ConvertTo-FabricanteCorto $cs.Manufacturer
    $modelo = "$($cs.Model)".Trim()
    if ($fabricante -eq 'Lenovo') {
        # En Lenovo, Model es el tipo de máquina (20XW...); el nombre comercial viene en Version.
        $csp = Get-Cim -Clase Win32_ComputerSystemProduct -Propiedades Version
        $version = "$($csp.Version)".Trim()
        if ($version -and $version -notmatch '^(?i)(lenovo|none)$') { $modelo = $version }
    }
    if (Test-ValorGenerico $modelo) { $modelo = 'Generico' }
    $serieOriginal = "$($bios.SerialNumber)".Trim()
    $serie = if (Test-ValorGenerico $serieOriginal) { '' } else { $serieOriginal }
    # UUID y serie de la placa: para reconocer después un equipo con serie genérica. Hay UUID de
    # relleno (todo ceros, todo F o 03000200-0400-...-0009) que no sirven para identificar.
    $uuid = $null
    $placaSerie = $null
    try {
        $u = "$((Get-Cim -Clase Win32_ComputerSystemProduct -Propiedades UUID).UUID)".Trim().ToUpperInvariant()
        if ($u -and $u -notmatch '^[0F-]+$' -and $u -ne '03000200-0400-0500-0006-000700080009') { $uuid = $u }
        $p = "$((Get-Cim -Clase Win32_BaseBoard -Propiedades SerialNumber).SerialNumber)".Trim()
        if (-not (Test-ValorGenerico $p)) { $placaSerie = $p }
    } catch {
        Write-LogKit -Nivel AVISO -Mensaje "No se pudo leer UUID o serie de placa: $($_.Exception.Message)"
    }
    [pscustomobject][ordered]@{ Fabricante = $fabricante; Modelo = $modelo; Serie = $serie; SerieOriginal = $serieOriginal; Uuid = $uuid; PlacaSerie = $placaSerie }
}

function Get-NombreArchivo {
    param([AllowEmptyString()][string]$Texto, [int]$Max = 30)
    $t = ($Texto -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max).Trim('-') }
    if (-not $t) { $t = 'X' }
    $t
}
