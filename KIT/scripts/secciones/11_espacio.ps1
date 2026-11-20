# 11 Espacio: libre/total por volumen (siempre) y recorrido de carpetas con .NET (salvo -SinEspacio):
# top de carpetas por volumen, archivos grandes y logs grandes.
# - No sigue reparse points (junctions, enlaces, OneDrive): se listan como omitidas.
# - Los archivos que están solo en la nube (OneDrive a pedido) no se suman: no ocupan disco.
# - Límite de tiempo total compartido entre volúmenes; primero SSD, al final HDD. Si se corta, queda PARCIAL.
# - Las rutas se recorren con prefijo \\?\ para que no fallen las de más de 260 caracteres.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:AtribDirectorio = 0x10
$script:AtribReparse = 0x400
$script:AtribNube = 0x1000 -bor 0x40000 -bor 0x400000   # Offline, RecallOnOpen, RecallOnDataAccess

function Get-VolumenesKit {
    $letraKit = (Split-Path -Qualifier $script:Ctx.RaizKit).ToUpper()
    $medios = @{}
    try {
        $ns = 'root/Microsoft/Windows/Storage'
        $discos = @{}
        foreach ($pd in @(Get-Cim -Namespace $ns -Clase MSFT_PhysicalDisk -Propiedades DeviceId, MediaType, SpindleSpeed)) {
            $m = switch ([int]$pd.MediaType) { 3 { 'HDD' } 4 { 'SSD' } default { if ($pd.SpindleSpeed -eq 0) { 'SSD' } else { 'Desconocido' } } }
            $discos["$($pd.DeviceId)"] = $m
        }
        foreach ($p in @(Get-Cim -Namespace $ns -Clase MSFT_Partition -Propiedades DiskNumber, DriveLetter)) {
            if ([int][char]$p.DriveLetter -gt 0) { $medios["$([char]$p.DriveLetter):".ToUpper()] = $discos["$($p.DiskNumber)"] }
        }
    } catch {
        Write-LogKit -Nivel AVISO -Mensaje "No se pudo saber el tipo de disco de cada volumen: $($_.Exception.Message)"
    }
    $orden = @{ SSD = 0; Desconocido = 1; HDD = 2 }
    @(Get-Cim -Clase Win32_LogicalDisk -Filtro 'DriveType=3' -Propiedades DeviceID, VolumeName, FileSystem, Size, FreeSpace) | Where-Object { $_.Size -gt 0 } | ForEach-Object {
        $medio = $medios[$_.DeviceID.ToUpper()]
        if (-not $medio) { $medio = 'Desconocido' }
        [pscustomobject][ordered]@{
            Unidad            = $_.DeviceID
            Etiqueta          = $_.VolumeName
            SistemaArchivos   = $_.FileSystem
            Medio             = $medio
            TotalGB           = ConvertTo-GB $_.Size 1
            LibreGB           = ConvertTo-GB $_.FreeSpace 1
            LibrePct          = [math]::Round(100 * $_.FreeSpace / $_.Size, 1)
            UsadoBytes        = [double]($_.Size - $_.FreeSpace)
            EsSistema         = ($_.DeviceID -ieq $env:SystemDrive)
            EsKit             = ($_.DeviceID -ieq $letraKit -and $_.DeviceID -ine $env:SystemDrive)   # el disco de Windows se recorre igual (diagnóstico remoto copiado a C:)
            Recorrido         = 'no'
            ContabilizadoGB   = $null
            NoContabilizadoGB = $null
            EnNubeGB          = $null
            Archivos          = $null
            Carpetas          = $null
            SinAcceso         = $null
            Segundos          = $null
        }
    } | Sort-Object { $orden[$_.Medio] }, Unidad
}

function Invoke-RecorridoVolumen {
    # Recorre un volumen con una pila (sin recursión de PowerShell). Devuelve $true si terminó.
    param(
        [Parameter(Mandatory)]$Volumen,
        [Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Reloj,
        [Parameter(Mandatory)][double]$LimiteSeg,
        [Parameter(Mandatory)]$Acum
    )
    $cfg = $script:Ctx.Config.espacio
    $profMax = [int]$cfg.profundidad_top
    $umbralGrande = [int64]([double]$cfg.archivo_grande_gb * 1GB)
    $umbralLog = [int64]([double]$cfg.log_grande_mb * 1MB)
    $extLog = @{}
    foreach ($e in $cfg.extensiones_log) { $extLog[$e.ToLower()] = $true }
    $intervalo = [double]$cfg.intervalo_avance_seg
    $oneDrive = "$env:OneDrive"

    $tam = New-Object 'System.Collections.Generic.Dictionary[string,long]' ([StringComparer]::OrdinalIgnoreCase)
    $pila = New-Object 'System.Collections.Generic.Stack[object]'
    $pila.Push(@("\\?\$($Volumen.Unidad)\", 0, @()))
    [int64]$total = 0
    [int64]$nube = 0
    [int64]$archivos = 0
    [int64]$carpetas = 0
    [int64]$sinAcceso = 0
    $inicio = $Reloj.Elapsed.TotalSeconds
    $proximoAvance = $inicio + $intervalo
    $termino = $true

    while ($pila.Count -gt 0) {
        $ahora = $Reloj.Elapsed.TotalSeconds
        if ($ahora -ge $LimiteSeg) { $termino = $false; break }
        $item = $pila.Pop()
        $dir = $item[0]
        $prof = $item[1]
        $ancestros = $item[2]
        $carpetas++
        if ($ahora -ge $proximoAvance) {
            $proximoAvance = $ahora + $intervalo
            $visible = $dir.Substring(4)
            if ($visible.Length -gt 70) { $visible = '...' + $visible.Substring($visible.Length - 67) }
            Show-Progreso -Actividad "Espacio $($Volumen.Unidad) ($($Volumen.Medio))" -Estado ('{0:N0} archivos, {1} | {2}' -f $archivos, (Format-Tamano $total), $visible) -Porcentaje ([math]::Min(100, [int](100 * $ahora / $LimiteSeg)))
        }
        [int64]$local = 0
        try {
            foreach ($e in ([IO.DirectoryInfo]$dir).EnumerateFileSystemInfos()) {
                $atr = [int]$e.Attributes
                if ($atr -band $script:AtribDirectorio) {
                    if ($atr -band $script:AtribReparse) {
                        $ruta = $e.FullName.Substring(4)
                        $tipo = if ($oneDrive -and $ruta.StartsWith($oneDrive, [StringComparison]::OrdinalIgnoreCase)) { 'OneDrive/nube' } else { 'enlace o junction' }
                        $Acum.Omitidas.Add([pscustomobject][ordered]@{ Carpeta = $ruta; Tipo = $tipo })
                        continue
                    }
                    $hijaProf = $prof + 1
                    $hijaAnc = $ancestros
                    if ($hijaProf -le $profMax) { $hijaAnc = $ancestros + $e.FullName.Substring(4) }
                    $pila.Push(@($e.FullName, $hijaProf, $hijaAnc))
                } else {
                    if ($atr -band $script:AtribNube) { $nube += $e.Length; continue }
                    $largo = $e.Length
                    $local += $largo
                    $archivos++
                    if ($largo -ge $umbralGrande) {
                        $Acum.Grandes.Add([pscustomobject][ordered]@{ Archivo = $e.FullName.Substring(4); TamanoGB = ConvertTo-GB $largo 2; Modificado = ConvertTo-TextoFecha $e.LastWriteTime -SoloFecha })
                    }
                    if ($largo -ge $umbralLog -and $extLog.ContainsKey($e.Extension.ToLower())) {
                        $Acum.Logs.Add([pscustomobject][ordered]@{ Archivo = $e.FullName.Substring(4); TamanoMB = [math]::Round($largo / 1MB, 0); Modificado = ConvertTo-TextoFecha $e.LastWriteTime -SoloFecha })
                    }
                }
            }
        } catch [System.UnauthorizedAccessException] {
            $sinAcceso++
        } catch {
            $sinAcceso++
            if ($Acum.ErroresRaros -lt 20) { $Acum.ErroresRaros++; Write-LogKit -Mensaje "Recorrido: $($dir.Substring(4)): $($_.Exception.Message)" }
        }
        if ($local -gt 0) {
            $total += $local
            foreach ($k in $ancestros) {
                $actual = 0L
                [void]$tam.TryGetValue($k, [ref]$actual)
                $tam[$k] = $actual + $local
            }
        }
    }

    $Volumen.Archivos = $archivos
    $Volumen.Carpetas = $carpetas
    $Volumen.SinAcceso = $sinAcceso
    $Volumen.ContabilizadoGB = ConvertTo-GB $total 1
    $Volumen.EnNubeGB = ConvertTo-GB $nube 1
    $Volumen.Segundos = [math]::Round($Reloj.Elapsed.TotalSeconds - $inicio, 1)
    $Volumen.Recorrido = if ($termino) { 'completo' } else { 'parcial' }
    if ($termino) { $Volumen.NoContabilizadoGB = [math]::Max(0.0, (ConvertTo-GB ($Volumen.UsadoBytes - $total) 1)) }

    # Top de carpetas: si una subcarpeta tiene >= 90 % del tamaño de su padre, el padre no aporta y se omite.
    $mayorHija = @{}
    foreach ($k in $tam.Keys) {
        $i = $k.LastIndexOf('\')
        if ($i -le 2) { continue }
        $padre = $k.Substring(0, $i)
        if (-not $mayorHija.ContainsKey($padre) -or $tam[$k] -gt $mayorHija[$padre]) { $mayorHija[$padre] = $tam[$k] }
    }
    $candidatas = foreach ($k in $tam.Keys) {
        if ($mayorHija.ContainsKey($k) -and $mayorHija[$k] -ge 0.9 * $tam[$k]) { continue }
        [pscustomobject][ordered]@{ Unidad = $Volumen.Unidad; Carpeta = $k; TamanoGB = ConvertTo-GB $tam[$k] 2; Nivel = ($k.Split('\').Count - 1); Bytes = $tam[$k] }
    }
    foreach ($c in ($candidatas | Sort-Object Bytes -Descending | Select-Object -First ([int]$cfg.top_carpetas))) {
        $Acum.Top.Add(($c | Select-Object Unidad, Carpeta, TamanoGB, Nivel))
    }
    $termino
}

function Get-DatosEspacio {
    $vols = @(Get-VolumenesKit)
    $limite = [double]$script:Ctx.Parametros.TiempoMaxEspacio
    $d = [ordered]@{
        Volumenes       = $vols
        Recorrido       = [ordered]@{ Ejecutado = $false; Parcial = $false; Segundos = 0; LimiteSeg = $limite; ProfundidadTop = [int]$script:Ctx.Config.espacio.profundidad_top }
        TopCarpetas     = @()
        ArchivosGrandes = @()
        LogsGrandes     = @()
        Omitidas        = @()
    }
    Add-Tabla -Nombre 'volumenes' -Filas ($vols | Select-Object * -ExcludeProperty UsadoBytes)
    $d.OneDrive = Invoke-Paso 'OneDrive' { Get-OneDriveKit -Recorrer:(-not $script:Ctx.Parametros.SinEspacio) }
    if ($script:Ctx.Parametros.SinEspacio) {
        Write-LogKit -Mensaje 'Recorrido de carpetas omitido (-SinEspacio)'
        return $d
    }
    $acum = [pscustomobject]@{
        Top          = New-Object System.Collections.Generic.List[object]
        Grandes      = New-Object System.Collections.Generic.List[object]
        Logs         = New-Object System.Collections.Generic.List[object]
        Omitidas     = New-Object System.Collections.Generic.List[object]
        ErroresRaros = 0
    }
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $d.Recorrido.Ejecutado = $true
    Show-Mensaje ''
    foreach ($v in $vols) {
        if ($v.EsKit) { $v.Recorrido = 'omitido (unidad del kit)'; continue }
        if ($reloj.Elapsed.TotalSeconds -ge $limite) { $v.Recorrido = 'sin tiempo'; $d.Recorrido.Parcial = $true; continue }
        $ok = Invoke-RecorridoVolumen -Volumen $v -Reloj $reloj -LimiteSeg $limite -Acum $acum
        if (-not $ok) { $d.Recorrido.Parcial = $true }
        Show-Mensaje ('      {0} {1,-4} {2,12:N0} archivos  {3,10}  {4,6} s  {5}' -f $v.Unidad, $v.Medio, $v.Archivos, (Format-Tamano ($v.ContabilizadoGB * 1GB)), (Format-Numero $v.Segundos 1), $v.Recorrido.ToUpper()) -Color $(if ($ok) { 'DarkGray' } else { 'Yellow' })
        Write-LogKit -Mensaje ("Recorrido {0}: {1} en {2} s, {3:N0} archivos, {4:N0} carpetas, {5:N0} sin acceso, contabilizado {6} GB" -f $v.Unidad, $v.Recorrido, $v.Segundos, $v.Archivos, $v.Carpetas, $v.SinAcceso, $v.ContabilizadoGB)
    }
    Show-Progreso -Actividad 'Espacio' -Estado 'listo' -Terminado
    Show-Mensaje (' ' * 31) -SinSalto
    $d.Recorrido.Segundos = [math]::Round($reloj.Elapsed.TotalSeconds, 1)
    if ($d.Recorrido.Parcial) { $script:Ctx.EstadoForzado = 'PARCIAL' }
    $d.TopCarpetas = $acum.Top.ToArray()
    $d.ArchivosGrandes = @($acum.Grandes | Sort-Object TamanoGB -Descending)
    $d.LogsGrandes = @($acum.Logs | Sort-Object TamanoMB -Descending)
    $d.Omitidas = $acum.Omitidas.ToArray()
    Add-Tabla -Nombre 'volumenes' -Filas ($vols | Select-Object * -ExcludeProperty UsadoBytes)
    Add-Tabla -Nombre 'top_carpetas' -Filas $d.TopCarpetas
    Add-Tabla -Nombre 'archivos_grandes' -Filas $d.ArchivosGrandes
    Add-Tabla -Nombre 'logs_grandes' -Filas $d.LogsGrandes
    Add-Tabla -Nombre 'carpetas_omitidas' -Filas $d.Omitidas
    $d
}

function Measure-CarpetaKit {
    # Cantidad de archivos y bytes de una carpeta con sus subcarpetas, con tope de tiempo. No sigue junctions ni
    # enlaces (reparse points). Solo cuenta: no abre archivos ni guarda nombres.
    param([Parameter(Mandatory)][string]$Ruta, [double]$LimiteSeg = 30)
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $n = 0; $bytes = 0.0; $completo = $true
    $pila = New-Object System.Collections.Generic.Stack[string]
    $pila.Push($Ruta)
    while ($pila.Count) {
        if ($reloj.Elapsed.TotalSeconds -ge $LimiteSeg) { $completo = $false; break }
        try {
            foreach ($i in (New-Object IO.DirectoryInfo($pila.Pop())).EnumerateFileSystemInfos()) {
                if ($i -is [IO.DirectoryInfo]) { if (-not ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pila.Push($i.FullName) }; continue }
                if ($i.Name -ieq 'desktop.ini') { continue }
                $n++; $bytes += $i.Length
            }
        } catch { Write-Verbose $_ }
    }
    [pscustomobject]@{ Archivos = $n; Bytes = $bytes; Completo = $completo }
}

function Get-OneDriveKit {
    # OneDrive del usuario actual. Solo lee: cuentas vinculadas (tipo y carpeta, nunca el correo), qué
    # carpetas de Windows manda a la nube, carpetas repetidas (Documents/Documentos, copias "-<EQUIPO>") y,
    # con -Recorrer, cuánto pesa (local y solo en la nube) y cuántos archivos son copias en conflicto.
    # Solo cuenta archivos: nunca guarda nombres de archivos ni los abre.
    param([switch]$Recorrer)
    $cuentas = New-Object System.Collections.Generic.List[object]
    foreach ($c in @(Get-SubclavesRegistro -Colmena HKCU -Ruta 'Software\Microsoft\OneDrive\Accounts')) {
        $carpeta = "$(Get-ValorRegistro -Colmena HKCU -Ruta "Software\Microsoft\OneDrive\Accounts\$c" -Nombre 'UserFolder')"
        if (-not $carpeta) { continue }
        $cuentas.Add([pscustomobject][ordered]@{ Cuenta = $c; Tipo = $(if ($c -like 'Business*') { 'Empresa o colegio' } else { 'Personal' }); Carpeta = $carpeta; Existe = [IO.Directory]::Exists($carpeta) })
    }
    $r = [ordered]@{ Vinculado = ($cuentas.Count -gt 0); Cuentas = $cuentas.ToArray(); Respaldadas = @(); Duplicadas = @(); CopiasLocales = @(); Recorrido = $null; EnEjecucion = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue) }
    if (-not $cuentas.Count) { return [pscustomobject]$r }

    # Carpetas de Windows que apuntan dentro de OneDrive (copia de seguridad de carpetas).
    $shell = Get-ValoresRegistro -Colmena HKCU -Ruta 'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $raices = @($cuentas | ForEach-Object { $_.Carpeta.TrimEnd('\') + '\' })
    $resp = New-Object System.Collections.Generic.List[object]
    foreach ($par in @(@('Desktop', 'Escritorio'), @('Personal', 'Documentos'), @('My Pictures', 'Imágenes'), @('My Music', 'Música'), @('My Video', 'Videos'))) {
        $v = [Environment]::ExpandEnvironmentVariables("$($shell[$par[0]])")
        $dentro = @($raices | Where-Object { $v -and $v.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if ($dentro) { $resp.Add([pscustomobject][ordered]@{ Carpeta = $par[1]; Ruta = $v }) }
    }
    $r.Respaldadas = $resp.ToArray()

    # Carpetas repetidas dentro de OneDrive: el mismo tipo con nombre en inglés y en español, o la copia que
    # OneDrive crea con el nombre del equipo cuando choca ("Escritorio-BELI").
    $dup = New-Object System.Collections.Generic.List[object]
    $equipo = $env:COMPUTERNAME
    foreach ($raiz in @($cuentas | Where-Object Existe | ForEach-Object Carpeta)) {
        $nombres = @(try { [IO.Directory]::GetDirectories($raiz) | ForEach-Object { [IO.Path]::GetFileName($_) } } catch { Write-Verbose $_ })
        foreach ($par in @(@('Documents', 'Documentos'), @('Desktop', 'Escritorio'), @('Pictures', 'Imágenes'), @('Music', 'Música'), @('Videos', 'Vídeos'))) {
            if ($nombres -contains $par[0] -and $nombres -contains $par[1]) { $dup.Add([pscustomobject][ordered]@{ Raiz = $raiz; Carpetas = "$($par[0]) y $($par[1])"; Motivo = 'el mismo tipo de carpeta en inglés y en español' }) }
        }
        foreach ($n in @($nombres | Where-Object { $equipo -and $_ -match "-$([regex]::Escape($equipo))(-\d+)?$" })) { $dup.Add([pscustomobject][ordered]@{ Raiz = $raiz; Carpetas = $n; Motivo = 'copia creada por OneDrive al chocar con otra carpeta' }) }
    }
    $r.Duplicadas = $dup.ToArray()

    # Carpetas locales que quedaron con archivos después de mover la carpeta a OneDrive.
    $perfil = [Environment]::GetFolderPath('UserProfile')
    $loc = New-Object System.Collections.Generic.List[object]
    foreach ($x in @(@('Desktop', 'Escritorio'), @('Documents', 'Documentos'), @('Pictures', 'Imágenes'))) {
        $local = Join-Path $perfil $x[0]
        if (-not @($resp | Where-Object Carpeta -EQ $x[1]).Count -or -not [IO.Directory]::Exists($local)) { continue }
        # Todo lo que quedó adentro (subcarpetas incluidas): suele ser mucho y el cliente ya no lo ve como "Documentos".
        $m = Measure-CarpetaKit -Ruta $local -LimiteSeg 30
        if ($m.Archivos -gt 0) { $loc.Add([pscustomobject][ordered]@{ Carpeta = $x[1]; Ruta = $local; Archivos = $m.Archivos; GB = (ConvertTo-GB $m.Bytes 1); Completo = $m.Completo }) }
    }
    $r.CopiasLocales = $loc.ToArray()

    if ($Recorrer) {
        # Tamaño con tope de tiempo. Los archivos "solo en la nube" (marcados para descargarse al abrir) no ocupan disco.
        $reloj = [Diagnostics.Stopwatch]::StartNew()
        $limite = 60
        $total = 0.0; $nube = 0.0; $archivos = 0; $conflictos = 0; $completo = $true
        $pila = New-Object System.Collections.Generic.Stack[string]
        $vistas = New-Object System.Collections.Generic.HashSet[string]
        foreach ($raiz in @($cuentas | Where-Object Existe | ForEach-Object Carpeta)) { if ($vistas.Add($raiz.ToLowerInvariant())) { $pila.Push($raiz) } }
        while ($pila.Count) {
            if ($reloj.Elapsed.TotalSeconds -ge $limite) { $completo = $false; break }
            $dir = New-Object IO.DirectoryInfo($pila.Pop())
            try {
                foreach ($i in $dir.EnumerateFileSystemInfos()) {
                    if ($i -is [IO.DirectoryInfo]) {
                        # Dentro de OneDrive las carpetas son reparse points de nube (con o sin atributos de "a petición"):
                        # se recorren todas. Para no dar vueltas por un enlace, cada carpeta se visita una sola vez.
                        if ($vistas.Add($i.FullName.ToLowerInvariant())) { $pila.Push($i.FullName) }
                        continue
                    }
                    $archivos++
                    $total += $i.Length
                    if (([int]$i.Attributes -band 0x400000) -or ($i.Attributes -band [IO.FileAttributes]::Offline)) { $nube += $i.Length }
                    if ($equipo -and $i.Name -match "-$([regex]::Escape($equipo))(-\d+)?\.[^.]+$") { $conflictos++ }
                }
            } catch { Write-Verbose $_ }
        }
        $r.Recorrido = [pscustomobject][ordered]@{ Completo = $completo; Segundos = [math]::Round($reloj.Elapsed.TotalSeconds, 1); Archivos = $archivos; TotalGB = (ConvertTo-GB $total 2); SoloNubeGB = (ConvertTo-GB $nube 2); LocalGB = (ConvertTo-GB ($total - $nube) 2); Conflictos = $conflictos }
    }
    [pscustomobject]$r
}

function Test-AlertasOneDrive {
    param($OneDrive)
    $o = $OneDrive
    if (-not $o -or -not $o.Vinculado) { return }
    $personal = @($o.Cuentas | Where-Object Tipo -EQ 'Personal').Count -gt 0
    $gb = if ($o.Recorrido) { [double]$o.Recorrido.TotalGB } else { $null }
    $limite = [double](Get-Umbral 'onedrive_gratis_gb')
    if ($personal -and $null -ne $gb -and $gb -gt $limite) {
        $carp = if (@($o.Respaldadas).Count) { " (respalda: $((@($o.Respaldadas) | ForEach-Object Carpeta) -join ', '))" } else { '' }
        Add-Alerta -Severidad AVISO -Codigo 'ESP-ONEDRIVE' -Texto "OneDrive personal guarda $(Format-Numero $gb 1) GB$carp y la cuenta gratis trae $(Format-Numero $limite 0) GB: si no tiene un plan pagado, está lleno y lo nuevo no se respalda"
    }
    if (@($o.Duplicadas).Count) {
        Add-Alerta -Severidad INFO -Codigo 'ESP-ONEDRIVE-DUP' -Texto "Carpetas repetidas en OneDrive: $((@($o.Duplicadas) | ForEach-Object Carpetas) -join '; ')"
    }
    if (@($o.CopiasLocales).Count) {
        $gbLoc = (@($o.CopiasLocales) | ForEach-Object { [double]$_.GB } | Measure-Object -Sum).Sum
        $sev = if ($gbLoc -ge 1) { 'AVISO' } else { 'INFO' }
        Add-Alerta -Severidad $sev -Codigo 'ESP-ONEDRIVE-LOCAL' -Texto "Quedaron archivos en carpetas locales que Windows ya no muestra (usa las de OneDrive): $((@($o.CopiasLocales) | ForEach-Object { "$($_.Carpeta) local, $($_.Archivos) archivos$(if ($null -ne $_.GB) { ", $(Format-Numero ([double]$_.GB) 1) GB" })" }) -join '; '). El cliente puede creer que no los tiene, y ocupan disco"
    }
    if ($o.Recorrido -and [int]$o.Recorrido.Conflictos -gt 0) {
        Add-Alerta -Severidad INFO -Codigo 'ESP-ONEDRIVE-CONFLICTOS' -Texto "$($o.Recorrido.Conflictos) archivos duplicados por conflictos de sincronización en OneDrive (con el nombre del equipo agregado)"
    }
}

function Test-AlertasEspacio {
    $d = $script:Ctx.Datos.espacio
    foreach ($v in $d.Volumenes) {
        $critico = $v.LibrePct -lt (Get-Umbral 'libre_critico_pct') -or ($v.EsSistema -and $v.LibreGB -lt (Get-Umbral 'libre_critico_gb'))
        if ($critico) {
            Add-Alerta -Severidad CRITICO -Codigo 'ESP-LIBRE' -Texto "$($v.Unidad) con $(Format-Numero $v.LibreGB 1) GB libres de $(Format-Numero $v.TotalGB 1) GB ($(Format-Numero $v.LibrePct 1) %)"
        } elseif ($v.LibrePct -lt (Get-Umbral 'libre_aviso_pct')) {
            Add-Alerta -Severidad AVISO -Codigo 'ESP-LIBRE' -Texto "$($v.Unidad) con $(Format-Numero $v.LibreGB 1) GB libres de $(Format-Numero $v.TotalGB 1) GB ($(Format-Numero $v.LibrePct 1) %)"
        }
        if ($null -ne $v.NoContabilizadoGB -and $v.NoContabilizadoGB -ge (Get-Umbral 'no_contabilizado_gb')) {
            Add-Alerta -Severidad INFO -Codigo 'ESP-NO-CONTABILIZADO' -Texto "$($v.Unidad): $(Format-Numero $v.NoContabilizadoGB 1) GB usados que el recorrido no pudo ver (puntos de restauración en System Volume Information, carpetas sin acceso u otros perfiles$(if (-not $script:Ctx.Admin.Elevado) { '; como admin se ve más' }))"
        }
    }
    if (-not $d.Recorrido.Ejecutado) { return }
    if ($d.Recorrido.Parcial) {
        $estado = @($d.Volumenes | Where-Object { $_.Recorrido -in 'parcial', 'sin tiempo' } | ForEach-Object { "$($_.Unidad) $($_.Recorrido)" }) -join ', '
        Add-Alerta -Severidad AVISO -Codigo 'ESP-PARCIAL' -Texto "Recorrido de espacio PARCIAL: se cortó a los $($d.Recorrido.LimiteSeg) s ($estado). Para completarlo: -TiempoMaxEspacio con más segundos"
    }
    $logs = @($d.LogsGrandes)
    Test-AlertasOneDrive -OneDrive $d.OneDrive
    if ($logs.Count -gt 0) {
        $lista = @($logs | Select-Object -First 5 | ForEach-Object { "$($_.Archivo) ($(Format-Numero $_.TamanoMB 0) MB)" }) -join ', '
        Add-Alerta -Severidad AVISO -Codigo 'ESP-LOGS' -Texto "$($logs.Count) logs de más de $($script:Ctx.Config.espacio.log_grande_mb) MB: $lista"
    }
    $grandes = @($d.ArchivosGrandes)
    if ($grandes.Count -gt 0) {
        $suma = ($grandes | Measure-Object TamanoGB -Sum).Sum
        $lista = @($grandes | Select-Object -First 5 | ForEach-Object { "$(Split-Path -Leaf $_.Archivo) $(Format-Numero $_.TamanoGB 1) GB" }) -join ', '
        Add-Alerta -Severidad INFO -Codigo 'ESP-GRANDES' -Texto "$($grandes.Count) archivos de más de $($script:Ctx.Config.espacio.archivo_grande_gb) GB ($(Format-Numero $suma 1) GB en total). Mayores: $lista"
    }
}

function Format-ResumenEspacio {
    $d = $script:Ctx.Datos.espacio
    foreach ($v in $d.Volumenes) {
        $rec = ''
        if ($null -ne $v.ContabilizadoGB) { $rec = " | recorrido $($v.Recorrido.ToUpper()) en $(Format-Numero $v.Segundos 1) s: $(Format-Numero $v.ContabilizadoGB 1) GB contados, $('{0:N0}' -f $v.Archivos) archivos, $('{0:N0}' -f $v.SinAcceso) carpetas sin acceso" }
        elseif ($v.Recorrido -ne 'no') { $rec = " | recorrido: $($v.Recorrido)" }
        if ($null -ne $v.NoContabilizadoGB) { $rec += ", $(Format-Numero $v.NoContabilizadoGB 1) GB no contabilizados" }
        if ($v.EnNubeGB) { $rec += ", $(Format-Numero $v.EnNubeGB 1) GB solo en la nube" }
        "$($v.Unidad) $($v.Medio)$(if ($v.Etiqueta) { " '$($v.Etiqueta)'" }): $(Format-Numero $v.LibreGB 1) GB libres de $(Format-Numero $v.TotalGB 1) GB ($(Format-Numero $v.LibrePct 1) %)$rec"
    }
    $o = $d.OneDrive
    if ($o) {
        if (-not $o.Vinculado) { 'OneDrive   : no vinculado' }
        else {
            $rec = if ($o.Recorrido) { " | $(Format-Numero ([double]$o.Recorrido.TotalGB) 1) GB en $('{0:N0}' -f $o.Recorrido.Archivos) archivos ($(Format-Numero ([double]$o.Recorrido.LocalGB) 1) GB en el disco, $(Format-Numero ([double]$o.Recorrido.SoloNubeGB) 1) GB solo en la nube)$(if (-not $o.Recorrido.Completo) { ' PARCIAL' })" } else { '' }
            "OneDrive   : $((@($o.Cuentas) | ForEach-Object Tipo) -join ', ')$rec | $(if ($o.EnEjecucion) { 'abierto' } else { 'cerrado' })"
            "             respalda: $(if (@($o.Respaldadas).Count) { (@($o.Respaldadas) | ForEach-Object Carpeta) -join ', ' } else { 'ninguna carpeta de Windows' })"
            foreach ($x in @($o.Duplicadas)) { "             repetidas: $($x.Carpetas) ($($x.Motivo))" }
            foreach ($x in @($o.CopiasLocales)) { "             $($x.Carpeta) local con $($x.Archivos) archivos$(if ($null -ne $x.GB) { " ($(Format-Numero ([double]$x.GB) 1) GB$(if (-not $x.Completo) { ', parcial' }))" }) en $($x.Ruta) (Windows ya no la muestra: usa la de OneDrive)" }
            if ($o.Recorrido -and $o.Recorrido.Conflictos) { "             $($o.Recorrido.Conflictos) archivos en conflicto (copias con el nombre del equipo)" }
        }
    }
    if (-not $d.Recorrido.Ejecutado) { 'Recorrido de carpetas: no se ejecutó (-SinEspacio)'; return }
    "Recorrido  : $(Format-Numero $d.Recorrido.Segundos 1) s de $($d.Recorrido.LimiteSeg) s$(if ($d.Recorrido.Parcial) { ' -> PARCIAL' } else { ' -> completo' }) | profundidad del top: $($d.Recorrido.ProfundidadTop)"
    foreach ($g in @($d.TopCarpetas | Group-Object Unidad)) {
        "Top $($g.Name)"
        foreach ($c in $g.Group) { '             {0,9} GB  {1}' -f (Format-Numero $c.TamanoGB 1), $c.Carpeta }
    }
    $grandes = @($d.ArchivosGrandes)
    "Archivos > $($script:Ctx.Config.espacio.archivo_grande_gb) GB: $($grandes.Count)"
    foreach ($a in ($grandes | Select-Object -First 15)) { '             {0,9} GB  {1}  ({2})' -f (Format-Numero $a.TamanoGB 1), $a.Archivo, $a.Modificado }
    if ($grandes.Count -gt 15) { '             (lista completa en csv\11_archivos_grandes.csv)' }
    "Logs > $($script:Ctx.Config.espacio.log_grande_mb) MB: $(@($d.LogsGrandes).Count)"
    foreach ($a in @($d.LogsGrandes)) { '             {0,9} MB  {1}  ({2})' -f (Format-Numero $a.TamanoMB 0), $a.Archivo, $a.Modificado }
    $om = @($d.Omitidas)
    if ($om.Count) { "Omitidas   : $($om.Count) carpetas con reparse point no seguidas ($(@($om | Group-Object Tipo | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '))" }
}
