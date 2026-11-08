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

function Merge-ConfigLocal {
    # Pone encima de config.json lo de config_local.json (los datos propios del técnico, como su contacto,
    # que no se suben al repositorio). Solo pisa las claves que trae; las demás quedan como están.
    param([Parameter(Mandatory)]$Base, [Parameter(Mandatory)]$Local)
    foreach ($p in $Local.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }
        $actual = $Base.PSObject.Properties[$p.Name]
        if ($actual -and $actual.Value -is [System.Management.Automation.PSCustomObject] -and $p.Value -is [System.Management.Automation.PSCustomObject]) { Merge-ConfigLocal -Base $actual.Value -Local $p.Value }
        elseif ($actual) { $actual.Value = $p.Value }
        else { $Base | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
}

# Versión del kit. La copia que hace actualizar_pendrive.ps1 agrega el commit y la fecha (KIT\version.json).
$script:VersionBase = '0.2.0'

function Get-VersionKit {
    # "0.2.0 · 2f98fd2 · 2026-11-08" si el kit vino de actualizar_pendrive.ps1; si no, la versión base.
    param([Parameter(Mandatory)][string]$RaizKit)
    $v = $null
    try { $v = Read-JsonKitOpcional (Join-Path $RaizKit 'version.json') } catch { $v = $null }
    if ($v -and $v.commit) { return ('{0} · {1} · {2}' -f $script:VersionBase, $v.commit, $v.fecha_commit) }
    "$script:VersionBase (copia de trabajo)"
}

function Get-ArchivosVerificablesKit {
    # Archivos del kit que se verifican, relativos a KIT\: INICIAR.cmd, scripts\ (menos config_local.json,
    # que es de cada técnico) y docs\. Sale ordenado; quien llama lo junta con @().
    param([Parameter(Mandatory)][string]$RaizKit)
    $base = $RaizKit.TrimEnd('\')
    $lista = New-Object System.Collections.Generic.List[string]
    if ([IO.File]::Exists((Join-Path $base 'INICIAR.cmd'))) { $lista.Add('INICIAR.cmd') }
    foreach ($sub in 'scripts', 'docs') {
        $dir = Join-Path $base $sub
        if (-not [IO.Directory]::Exists($dir)) { continue }
        foreach ($f in [IO.Directory]::GetFiles($dir, '*', [IO.SearchOption]::AllDirectories)) {
            $rel = $f.Substring($base.Length + 1)
            if ($rel -ieq 'scripts\config\config_local.json') { continue }
            $lista.Add($rel)
        }
    }
    $lista | Sort-Object
}

function Test-IntegridadKit {
    # Compara los archivos del kit con los hashes que dejó actualizar_pendrive.ps1 en KIT\version.json.
    # Solo lee. Estado: ok, cambios (distinto, faltante o sobrante), sin_manifiesto (copia de trabajo) o error.
    # Detecta un pendrive dañado (exFAT sacado sin expulsar) o scripts alterados en el PC de un cliente.
    param([Parameter(Mandatory)][string]$RaizKit)
    $r = [ordered]@{ Estado = 'sin_manifiesto'; Cambiados = @(); Faltan = @(); Nuevos = @(); Copiado = $null; Version = $null; Detalle = $null }
    try {
        $v = Read-JsonKitOpcional (Join-Path $RaizKit 'version.json')
        if (-not $v -or -not $v.archivos) { return [pscustomobject]$r }
        $r.Copiado = $v.copiado; $r.Version = $v.commit
        $esperados = @{}
        foreach ($p in $v.archivos.PSObject.Properties) { $esperados[$p.Name] = "$($p.Value)" }
        $cambiados = New-Object System.Collections.Generic.List[string]
        $faltan = New-Object System.Collections.Generic.List[string]
        foreach ($rel in $esperados.Keys) {
            $ruta = Join-Path $RaizKit $rel
            if (-not [IO.File]::Exists($ruta)) { $faltan.Add($rel); continue }
            if ((Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash -ne $esperados[$rel]) { $cambiados.Add($rel) }
        }
        $r.Cambiados = @($cambiados | Sort-Object)
        $r.Faltan = @($faltan | Sort-Object)
        $r.Nuevos = @(Get-ArchivosVerificablesKit -RaizKit $RaizKit | Where-Object { -not $esperados.ContainsKey($_) })
        $r.Estado = if ($r.Cambiados.Count -or $r.Faltan.Count -or $r.Nuevos.Count) { 'cambios' } else { 'ok' }
    } catch {
        $r.Estado = 'error'
        $r.Detalle = $_.Exception.Message
    }
    [pscustomobject]$r
}

function Initialize-Contexto {
    param([Parameter(Mandatory)][string]$RaizScripts)
    $raizKit = Split-Path -Parent $RaizScripts
    $config = Read-JsonKit (Join-Path $RaizScripts 'config\config.json')
    try {
        $local = Read-JsonKitOpcional (Join-Path $RaizScripts 'config\config_local.json')
        if ($local) { Merge-ConfigLocal -Base $config -Local $local }
    } catch {
        # Un config_local.json roto no detiene el kit: solo faltan esos datos (los informes avisan qué).
        Write-Warning "config_local.json no se pudo leer y se ignora: $($_.Exception.Message)"
    }
    $script:Ctx = [ordered]@{
        Version         = Get-VersionKit -RaizKit $raizKit
        Inicio          = Get-Date
        Reloj           = [Diagnostics.Stopwatch]::StartNew()
        RaizKit         = $raizKit
        RaizScripts     = $RaizScripts
        CarpetaConfig   = Join-Path $RaizScripts 'config'
        CarpetaClientes = Join-Path $raizKit 'clientes'
        CarpetaCliente  = $null
        Config          = $config
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
