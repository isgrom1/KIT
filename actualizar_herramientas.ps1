#Requires -Version 5.1
<#
.SYNOPSIS
    Descarga o actualiza las herramientas portables del kit desde sus sitios oficiales.
.DESCRIPTION
    Corre solo en el equipo del técnico (config.json: equipos_tecnico), nunca en el del cliente.
    - Fuentes: el GitHub del proyecto (API de releases) o el enlace oficial del sitio del autor.
      Nada de sitios de descargas de terceros.
    - Verifica el hash cuando el sitio lo publica: SHA-256 de GitHub, MD5 de SourceForge y la
      lista de hashes que publica WinDirStat. Si no calza, no instala.
    - Desbloquea lo descargado (Unblock-File) y registra versión, fechas, fuente, hash y licencia
      en KIT\herramientas\versiones.json.
    - DDU se revisa pero no se descarga: el enlace real está detrás de una verificación anti-bots.
    - Las carpetas que agregues a mano en KIT\herramientas\<nombre>\ también quedan registradas.
.PARAMETER Forzar
    Corre aunque este equipo no esté en equipos_tecnico.
.PARAMETER SoloRevisar
    Solo compara versiones con las publicadas; no descarga nada.
.PARAMETER Reinstalar
    Descarga de nuevo aunque la versión instalada sea la vigente.
.PARAMETER Solo
    Herramientas a procesar, por nombre (por defecto, todas). Ej: -Solo Rufus,WinDirStat
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\actualizar_herramientas.ps1 -SoloRevisar
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script interactivo del técnico: los mensajes son para la pantalla')]
[CmdletBinding()]
param(
    [switch]$Forzar,
    [switch]$SoloRevisar,
    [switch]$Reinstalar,
    [string[]]$Solo
)

$ErrorActionPreference = 'Stop'
# La barra de progreso de Invoke-WebRequest en 5.1 hace las descargas varias veces más lentas.
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:Raiz = $PSScriptRoot
$script:CarpetaHerr = Join-Path $script:Raiz 'KIT\herramientas'
$script:RutaVersiones = Join-Path $script:CarpetaHerr 'versiones.json'
$script:Agente = 'kitservicio-actualizar/1.0 (Windows PowerShell)'
$script:Invariante = [Globalization.CultureInfo]::InvariantCulture
$script:Hoy = (Get-Date).ToString('yyyy-MM-dd', $script:Invariante)

# Licencias verificadas el 2026-11-01 en el sitio o repositorio de cada proyecto. En las de GitHub
# el script vuelve a mirar la licencia del repositorio y avisa si cambió.
$script:Catalogo = @(
    [pscustomobject]@{
        Nombre = 'CrystalDiskInfo'; Origen = 'crystal'; Producto = 'CrystalDiskInfo'; Proyecto = 'crystaldiskinfo'
        Ejecutable = '^DiskInfo64\.exe$'; Licencia = 'MIT'; Comercial = $true
        Pagina = 'https://crystalmark.info/en/software/crystaldiskinfo/'
        Nota = 'Lee SMART también detrás de Intel RST/VMD, donde Windows no lo entrega.'
    }
    [pscustomobject]@{
        Nombre = 'CrystalDiskMark'; Origen = 'crystal'; Producto = 'CrystalDiskMark'; Proyecto = 'crystaldiskmark'
        Ejecutable = '^DiskMark64\.exe$'; Licencia = 'MIT'; Comercial = $true
        Pagina = 'https://crystalmark.info/en/software/crystaldiskmark/'
        Nota = 'Escribe archivos de prueba en el disco que mide: úsalo con permiso y con espacio libre.'
    }
    [pscustomobject]@{
        Nombre = 'LibreHardwareMonitor'; Origen = 'github'; Repo = 'LibreHardwareMonitor/LibreHardwareMonitor'; Archivo = '^LibreHardwareMonitor\.zip$'
        Ejecutable = '^LibreHardwareMonitor\.exe$'; Licencia = 'MPL-2.0'; Comercial = $true
        Pagina = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor'
        Nota = 'Versión .NET Framework 4.7.2 (viene en Windows 10/11). Para leer sensores usa el driver PawnIO, que se instala en el equipo: pide permiso al cliente.'
    }
    [pscustomobject]@{
        Nombre = 'Czkawka'; Origen = 'github'; Repo = 'qarmin/czkawka'; Archivo = '^windows_czkawka_gui.*\.zip$'
        Ejecutable = '^czkawka_gui\.exe$'; Licencia = 'MIT'; Comercial = $true
        Pagina = 'https://github.com/qarmin/czkawka'
        Nota = 'Interfaz GTK (czkawka_gui, MIT). Krokiet, la interfaz nueva del mismo autor, es GPL-3.0 y no se descarga.'
    }
    [pscustomobject]@{
        Nombre = 'WinDirStat'; Origen = 'github'; Repo = 'windirstat/windirstat'; Archivo = '^WinDirStat\.zip$'; ListaHashes = 'WinDirStat-Hashes.txt'
        Ejecutable = '^WinDirStat\.exe$'; Licencia = 'GPL-3.0'; Comercial = $true
        Pagina = 'https://windirstat.net'
        Nota = 'Zip portable; el exe de x64 está en su subcarpeta.'
    }
    [pscustomobject]@{
        Nombre = 'Rufus'; Origen = 'github'; Repo = 'pbatard/rufus'; Archivo = '^rufus-[\d.]+p\.exe$'
        Ejecutable = '^rufus-[\d.]+p\.exe$'; Licencia = 'GPL-3.0'; Comercial = $true
        Pagina = 'https://rufus.ie'
        Nota = 'Versión portable: la "p" del nombre hace que guarde su configuración junto al exe.'
    }
    [pscustomobject]@{
        Nombre = 'DDU'; Origen = 'manual'; Ejecutable = '^Display Driver Uninstaller\.exe$'
        Licencia = 'Freeware (Wagnardsoft); la página de descarga no publica términos de uso comercial'; Comercial = $null
        Pagina = 'https://www.wagnardsoft.com/display-driver-uninstaller-ddu'
        Nota = 'Se baja a mano: el enlace real está detrás de una verificación anti-bots (Cloudflare). Descomprímelo en KIT\herramientas\DDU\.'
    }
)

# La versión gratuita de estas herramientas es solo para uso personal.
$script:SoloUsoPersonal = '(?i)hwinfo|occt|wiztree'

function Show-Linea {
    param([string]$Texto, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Texto -ForegroundColor $Color
}

function Get-VersionArchivo {
    param([string]$Ruta)
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Ruta)
    $texto = if ($v.ProductVersion) { $v.ProductVersion } else { $v.FileVersion }
    if ($texto) { ($texto -replace ',\s*', '.').Trim() } else { $null }
}

function Find-Ejecutable {
    # Busca el exe principal; si hay varios (x86/x64/arm64), prefiere el de 64 bits y la ruta más corta.
    param([string]$Carpeta, [string]$Patron)
    $candidatos = @(Get-ChildItem -LiteralPath $Carpeta -Recurse -File -Filter *.exe | Where-Object { $_.Name -match $Patron })
    if ($candidatos.Count -eq 0) { return $null }
    $elegido = $candidatos | Sort-Object @{ Expression = { if ($_.FullName -match '(?i)arm64') { 2 } elseif ($_.FullName -match '(?i)x64|amd64|64') { 0 } else { 1 } } }, @{ Expression = { $_.FullName.Length } } | Select-Object -First 1
    $elegido.FullName.Substring($Carpeta.TrimEnd('\').Length + 1)
}

function Get-UltimaGithub {
    param($Herramienta)
    $cabeceras = @{ 'User-Agent' = $script:Agente; 'Accept' = 'application/vnd.github+json' }
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Herramienta.Repo)/releases/latest" -Headers $cabeceras -TimeoutSec 30
    $asset = @($rel.assets | Where-Object { $_.name -match $Herramienta.Archivo }) | Select-Object -First 1
    if (-not $asset) { throw "El release $($rel.tag_name) no trae un archivo que calce con '$($Herramienta.Archivo)'" }
    $hash = $null
    if ("$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') { $hash = $Matches[1].ToUpperInvariant() }
    $extra = $null
    if ($Herramienta.PSObject.Properties['ListaHashes']) {
        # Lista publicada por el propio proyecto: "SHA256   <hash>   <archivo>".
        $lista = @($rel.assets | Where-Object { $_.name -eq $Herramienta.ListaHashes }) | Select-Object -First 1
        if ($lista) {
            $bytes = (Invoke-WebRequest -Uri $lista.browser_download_url -UseBasicParsing -UserAgent $script:Agente -TimeoutSec 60).Content
            $texto = if ($bytes -is [byte[]]) { [Text.Encoding]::UTF8.GetString($bytes) } else { "$bytes" }
            $m = [regex]::Match($texto, '(?im)^\s*SHA256\s+([0-9A-F]{64})\s+' + [regex]::Escape($asset.name) + '\s*$')
            if ($m.Success) { $extra = $m.Groups[1].Value.ToUpperInvariant() }
        }
    }
    $licRepo = $null
    try { $licRepo = (Invoke-RestMethod -Uri "https://api.github.com/repos/$($Herramienta.Repo)" -Headers $cabeceras -TimeoutSec 30).license.spdx_id } catch { $licRepo = $null }
    [pscustomobject]@{
        Version      = ("$($rel.tag_name)" -replace '^(release/)?v', '')
        Publicada    = "$($rel.published_at)".Substring(0, 10)
        Url          = $asset.browser_download_url
        Archivo      = $asset.name
        Algoritmo    = $(if ($hash) { 'SHA256' } else { $null })
        Hash         = $hash
        FuenteHash   = $(if ($hash) { 'GitHub (digest del archivo del release)' } else { $null })
        HashProyecto = $extra
        LicenciaRepo = $licRepo
    }
}

function Get-UltimaCrystal {
    # crystalmark.info decide la versión vigente: su enlace de descarga redirige al proyecto oficial
    # del autor en SourceForge. Se valida que apunte al proyecto esperado antes de bajar nada.
    param($Herramienta)
    $req = [Net.HttpWebRequest]::Create("https://crystalmark.info/redirect.php?product=$($Herramienta.Producto)")
    $req.AllowAutoRedirect = $false
    $req.Method = 'HEAD'
    $req.UserAgent = $script:Agente
    $req.Timeout = 30000
    try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response; if (-not $resp) { throw } }
    try { $destino = $resp.Headers['Location'] } finally { $resp.Close() }
    if (-not $destino) { throw 'crystalmark.info no devolvió el enlace de descarga' }
    $sf = if ($destino -match 'url=(.+)$') { [uri]::UnescapeDataString($Matches[1]) } else { $destino }
    $m = [regex]::Match($sf, '^https://sourceforge\.net/projects/([^/]+)/files/([^/]+)/([^/]+\.zip)/download$')
    if (-not $m.Success -or $m.Groups[1].Value -ne $Herramienta.Proyecto) { throw "Enlace inesperado desde crystalmark.info: $sf" }
    $version = $m.Groups[2].Value
    $archivo = $m.Groups[3].Value
    # SourceForge publica el MD5 de cada archivo en el RSS de la carpeta.
    $rss = [xml](Invoke-WebRequest -Uri "https://sourceforge.net/projects/$($Herramienta.Proyecto)/rss?path=/$version" -UseBasicParsing -UserAgent $script:Agente -TimeoutSec 30).Content
    $md5 = $null
    $publicada = $null
    foreach ($item in @($rss.rss.channel.item)) {
        $titulo = if ($item.title -is [string]) { $item.title } else { $item.title.'#cdata-section' }
        if ($titulo -ne "/$version/$archivo") { continue }
        $md5 = @($item.content.hash | Where-Object { $_.algo -eq 'md5' } | ForEach-Object { $_.'#text' }) | Select-Object -First 1
        # pubDate viene como "Sat, 11 Oct 2026 03:12:45 UT": DateTime.Parse no entiende "UT".
        if ("$($item.pubDate)" -match '(\d{1,2}) (\w{3}) (\d{4})') {
            $publicada = [datetime]::ParseExact("$($Matches[1]) $($Matches[2]) $($Matches[3])", 'd MMM yyyy', $script:Invariante).ToString('yyyy-MM-dd', $script:Invariante)
        }
    }
    [pscustomobject]@{
        Version      = $version
        Publicada    = $publicada
        Url          = "https://downloads.sourceforge.net/project/$($Herramienta.Proyecto)/$version/$archivo"
        Archivo      = $archivo
        Algoritmo    = $(if ($md5) { 'MD5' } else { $null })
        Hash         = $(if ($md5) { $md5.ToUpperInvariant() } else { $null })
        FuenteHash   = $(if ($md5) { 'SourceForge (MD5, el único que publica)' } else { $null })
        HashProyecto = $null
        LicenciaRepo = $null
    }
}

function Get-VersionDdu {
    param($Herramienta)
    $html = (Invoke-WebRequest -Uri $Herramienta.Pagina -UseBasicParsing -UserAgent $script:Agente -TimeoutSec 30).Content
    $m = [regex]::Match($html, 'Display Driver Uninstaller \(DDU\)\s*v?(\d+(?:\.\d+){2,3})')
    if (-not $m.Success) { $m = [regex]::Match($html, 'Download-Display-Driver-Uninstaller-DDU-(\d)(\d)(\d)(\d)(\d)') }
    if (-not $m.Success) { throw 'No se encontró la versión en la página oficial de DDU' }
    if ($m.Groups.Count -gt 2) { return ('{0}{1}.{2}.{3}.{4}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value, $m.Groups[5].Value) }
    $m.Groups[1].Value
}

function Install-Herramienta {
    # Descomprime en <Nombre>.nuevo, desbloquea, verifica que esté el exe y recién ahí reemplaza.
    param($Herramienta, [string]$Descargado, [bool]$EraAutomatica)
    $destino = Join-Path $script:CarpetaHerr $Herramienta.Nombre
    $temporal = "$destino.nuevo"
    if (Test-Path -LiteralPath $temporal) { Remove-Item -LiteralPath $temporal -Recurse -Force }
    New-Item -ItemType Directory -Path $temporal | Out-Null
    if ($Descargado -match '\.zip$') {
        [IO.Compression.ZipFile]::ExtractToDirectory($Descargado, $temporal)
    } else {
        Copy-Item -LiteralPath $Descargado -Destination (Join-Path $temporal (Split-Path -Leaf $Descargado))
    }
    Get-ChildItem -LiteralPath $temporal -Recurse -File | Unblock-File
    $exe = Find-Ejecutable -Carpeta $temporal -Patron $Herramienta.Ejecutable
    if (-not $exe) { Remove-Item -LiteralPath $temporal -Recurse -Force; throw "Lo descargado no trae el ejecutable esperado ($($Herramienta.Ejecutable))" }
    if (Test-Path -LiteralPath $destino) {
        if ($EraAutomatica) {
            Remove-Item -LiteralPath $destino -Recurse -Force
        } else {
            # Una carpeta que pusiste a mano no se borra: queda renombrada al lado.
            $aparte = '{0}_manual_{1}' -f $destino, (Get-Date).ToString('yyyyMMdd_HHmmss', $script:Invariante)
            Rename-Item -LiteralPath $destino -NewName (Split-Path -Leaf $aparte)
            Show-Linea "    La carpeta existente no era del actualizador: quedó como $(Split-Path -Leaf $aparte)" Yellow
        }
    }
    Rename-Item -LiteralPath $temporal -NewName $Herramienta.Nombre
    $exe
}

# ------------------------------------------------------------------------------ inicio

Show-Linea ''
Show-Linea ' KIT SERVICIO - Actualizar herramientas (equipo del técnico)' Cyan
Show-Linea ' ------------------------------------------------------------' Cyan

$rutaConfig = Join-Path $script:Raiz 'KIT\scripts\config\config.json'
try {
    $config = [IO.File]::ReadAllText($rutaConfig) | ConvertFrom-Json
} catch {
    Show-Linea " No se pudo leer $rutaConfig : $($_.Exception.Message)" Red
    exit 2
}
$equipos = @($config.equipos_tecnico)
if (-not $Forzar -and $equipos -notcontains $env:COMPUTERNAME) {
    Show-Linea " Este equipo ($env:COMPUTERNAME) no está en equipos_tecnico de config.json." Yellow
    Show-Linea ' El actualizador baja programas de internet: se corre en tu equipo, no en el del cliente.' Yellow
    Show-Linea ' Si este es tu equipo, agrégalo a la lista o corre con -Forzar.' Yellow
    exit 2
}

if (-not (Test-Path -LiteralPath $script:CarpetaHerr)) { New-Item -ItemType Directory -Path $script:CarpetaHerr | Out-Null }
$anteriores = @{}
if (Test-Path -LiteralPath $script:RutaVersiones) {
    try {
        foreach ($e in @(([IO.File]::ReadAllText($script:RutaVersiones) | ConvertFrom-Json).herramientas)) { $anteriores[$e.nombre] = $e }
    } catch {
        Show-Linea " versiones.json no se pudo leer ($($_.Exception.Message)); se arma de nuevo." Yellow
    }
}

$registro = [ordered]@{}
$resumen = New-Object System.Collections.Generic.List[object]
$carpetaDescarga = Join-Path $script:Raiz '_descarga_temporal'

foreach ($h in $script:Catalogo) {
    if ($Solo -and ($Solo -notcontains $h.Nombre)) {
        if ($anteriores.ContainsKey($h.Nombre)) { $registro[$h.Nombre] = $anteriores[$h.Nombre] }
        continue
    }
    Show-Linea ''
    Show-Linea " [$($h.Nombre)]" White
    $previo = $anteriores[$h.Nombre]
    $carpeta = Join-Path $script:CarpetaHerr $h.Nombre
    $exeActual = if (Test-Path -LiteralPath $carpeta) { Find-Ejecutable -Carpeta $carpeta -Patron $h.Ejecutable } else { $null }
    try {
        if ($h.Origen -eq 'manual') {
            $vigente = Get-VersionDdu -Herramienta $h
            $local = if ($exeActual) { Get-VersionArchivo (Join-Path $carpeta $exeActual) } else { $null }
            $estado = if (-not $local) { 'FALTA (bajar a mano)' } elseif ($local -like "$vigente*") { 'al día' } else { "DESACTUALIZADA ($local)" }
            Show-Linea "    Vigente en la página oficial: $vigente | en el kit: $(if ($local) { $local } else { 'no está' })" $(if ($estado -eq 'al día') { 'Green' } else { 'Yellow' })
            if ($estado -ne 'al día') { Show-Linea "    Bájalo desde $($h.Pagina) y descomprímelo en KIT\herramientas\DDU\" Yellow }
            $registro[$h.Nombre] = [ordered]@{
                nombre = $h.Nombre; carpeta = $h.Nombre; automatica = $false; version = $local; version_vigente = $vigente
                publicada = $null; descargada = $(if ($previo) { $previo.descargada } else { $null }); revisada = $script:Hoy
                fuente = $h.Pagina; archivo = $null; hash = $null; licencia = $h.Licencia; uso_comercial = $h.Comercial
                ejecutable = $exeActual; nota = $h.Nota
            }
            $resumen.Add([pscustomobject]@{ Herramienta = $h.Nombre; Version = $(if ($local) { $local } else { '-' }); Estado = $estado; Hash = 'no publicado' })
            continue
        }

        $info = if ($h.Origen -eq 'github') { Get-UltimaGithub -Herramienta $h } else { Get-UltimaCrystal -Herramienta $h }
        if ($info.LicenciaRepo -and $info.LicenciaRepo -ne 'NOASSERTION' -and $info.LicenciaRepo -ne $h.Licencia) {
            Show-Linea "    OJO: el repositorio ahora declara licencia $($info.LicenciaRepo) (registrada: $($h.Licencia)). Revísala." Yellow
        }
        $alDia = $previo -and $previo.automatica -and $previo.version -eq $info.Version -and $exeActual
        Show-Linea "    Publicada: $($info.Version) del $($info.Publicada) | en el kit: $(if ($previo -and $exeActual) { $previo.version } else { 'no está' })"
        if ($SoloRevisar -or ($alDia -and -not $Reinstalar)) {
            $estado = if ($alDia) { 'al día' } else { 'hay versión nueva' }
            Show-Linea "    $estado" $(if ($alDia) { 'Green' } else { 'Yellow' })
            if ($previo) { $registro[$h.Nombre] = $previo }
            $resumen.Add([pscustomobject]@{ Herramienta = $h.Nombre; Version = $(if ($previo) { $previo.version } else { '-' }); Estado = $estado; Hash = $(if ($previo -and $previo.hash) { $previo.hash.algoritmo } else { '-' }) })
            continue
        }

        if (-not (Test-Path -LiteralPath $carpetaDescarga)) { New-Item -ItemType Directory -Path $carpetaDescarga | Out-Null }
        $archivoLocal = Join-Path $carpetaDescarga $info.Archivo
        Show-Linea "    Descargando $($info.Url)"
        $reloj = [Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri $info.Url -OutFile $archivoLocal -UseBasicParsing -UserAgent $script:Agente -TimeoutSec 900
        $tamano = (Get-Item -LiteralPath $archivoLocal).Length
        Show-Linea ('    {0:N1} MB en {1:N0} s' -f ($tamano / 1MB), $reloj.Elapsed.TotalSeconds)

        $verificado = $false
        if ($info.Hash) {
            $calculado = (Get-FileHash -LiteralPath $archivoLocal -Algorithm $info.Algoritmo).Hash
            if ($calculado -ne $info.Hash) { throw "El $($info.Algoritmo) no calza (publicado $($info.Hash), descargado $calculado). No se instala." }
            $verificado = $true
            Show-Linea "    $($info.Algoritmo) OK ($($info.FuenteHash))" Green
        } else {
            Show-Linea '    El sitio no publica hash para este archivo: se instala sin verificar.' Yellow
        }
        if ($info.HashProyecto) {
            $sha = (Get-FileHash -LiteralPath $archivoLocal -Algorithm SHA256).Hash
            if ($sha -ne $info.HashProyecto) { throw "No calza con la lista de hashes del proyecto ($($h.ListaHashes)). No se instala." }
            Show-Linea "    SHA256 OK también contra $($h.ListaHashes) del proyecto" Green
        }

        $exe = Install-Herramienta -Herramienta $h -Descargado $archivoLocal -EraAutomatica ([bool]($previo -and $previo.automatica))
        Show-Linea "    Instalada en KIT\herramientas\$($h.Nombre)\ (ejecutable: $exe)" Green
        $registro[$h.Nombre] = [ordered]@{
            nombre = $h.Nombre; carpeta = $h.Nombre; automatica = $true; version = $info.Version; version_vigente = $info.Version
            publicada = $info.Publicada; descargada = $script:Hoy; revisada = $script:Hoy
            fuente = $info.Url; archivo = $info.Archivo
            hash = [ordered]@{ algoritmo = $info.Algoritmo; valor = $info.Hash; fuente = $info.FuenteHash; verificado = $verificado; lista_proyecto = [bool]$info.HashProyecto }
            licencia = $h.Licencia; uso_comercial = $h.Comercial; ejecutable = $exe; nota = $h.Nota
        }
        $resumen.Add([pscustomobject]@{ Herramienta = $h.Nombre; Version = $info.Version; Estado = 'instalada'; Hash = $(if ($verificado) { "$($info.Algoritmo) OK" } else { 'no publicado' }) })
    } catch {
        Show-Linea "    ERROR: $($_.Exception.Message)" Red
        if ($previo) { $registro[$h.Nombre] = $previo }
        $resumen.Add([pscustomobject]@{ Herramienta = $h.Nombre; Version = $(if ($previo) { $previo.version } else { '-' }); Estado = 'ERROR'; Hash = '-' })
    }
}
if (Test-Path -LiteralPath $carpetaDescarga) { Remove-Item -LiteralPath $carpetaDescarga -Recurse -Force }

# Carpetas agregadas a mano: se registran con la versión del exe para que aparezcan en el kit.
$conocidas = @($script:Catalogo | ForEach-Object { $_.Nombre })
foreach ($dir in @(Get-ChildItem -LiteralPath $script:CarpetaHerr -Directory | Where-Object { $_.Name -notmatch '\.nuevo$|_manual_\d' -and $conocidas -notcontains $_.Name })) {
    $exes = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter *.exe | Where-Object { $_.Name -notmatch '(?i)unins|uninst|setup|install|update|vcredist|crash|helper' })
    if ($exes.Count -eq 0) { continue }
    $principal = $exes | Sort-Object @{ Expression = { if ($_.FullName -match '(?i)arm64') { 2 } elseif ($_.Name -match '64') { 0 } else { 1 } } }, @{ Expression = { $_.FullName.Length } } | Select-Object -First 1
    $licencia = 'Agregada a mano: revisa su licencia'
    if ($dir.Name -match $script:SoloUsoPersonal) { $licencia = 'La versión gratuita es solo para uso personal: en servicio técnico se usa solo con licencia comercial' }
    $registro[$dir.Name] = [ordered]@{
        nombre = $dir.Name; carpeta = $dir.Name; automatica = $false; version = Get-VersionArchivo $principal.FullName; version_vigente = $null
        publicada = $null; descargada = $null; revisada = $script:Hoy; fuente = 'agregada a mano'; archivo = $null; hash = $null
        licencia = $licencia; uso_comercial = $(if ($dir.Name -match $script:SoloUsoPersonal) { $false } else { $null })
        ejecutable = $principal.FullName.Substring($dir.FullName.Length + 1); nota = $null
    }
    $resumen.Add([pscustomobject]@{ Herramienta = $dir.Name; Version = $registro[$dir.Name].version; Estado = 'manual'; Hash = '-' })
}

$doc = [ordered]@{ generado = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante); herramientas = @($registro.Values) }
[IO.File]::WriteAllText($script:RutaVersiones, ($doc | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

Show-Linea ''
Show-Linea ' Resumen' Cyan
$resumen | Format-Table -AutoSize | Out-String -Width 160 | ForEach-Object { Show-Linea $_.TrimEnd() }
Show-Linea " Registro: $script:RutaVersiones"
if (@($resumen | Where-Object { $_.Estado -eq 'ERROR' }).Count -gt 0) { exit 1 }
exit 0
