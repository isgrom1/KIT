# archivos.ps1 - Motivo ARCHIVOS (espacio, duplicados, desorden). Tiene consentimiento propio en la ficha.
# Analizar (reporte) -> revisar -> mover a <unidad>:\_PARA_BORRAR\<fecha_hora> con movimientos y
# _DESHACER.ps1. NUNCA borra. Nunca toca: lo modificado en los últimos N días, partidas guardadas,
# archivos con credenciales, el Escritorio ni las carpetas protegidas. Las fotos parecidas y los
# posibles restos de desinstalaciones solo se reportan.
# Requiere lib\Comun, Log, Privacidad y Expediente.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingBrokenHashAlgorithms', '', Justification = 'MD5 solo confirma que dos archivos son idénticos y que volvieron sin cambios; no es un uso de seguridad')]
param()

Add-Type -AssemblyName System.Drawing

# Archivos que en realidad están en la nube (OneDrive a pedido): leerlos los descargaría.
$script:AtributosNube = 0x1000 -bor 0x40000 -bor 0x400000
$script:SufijoCopia = '(?i)(\s*\(\d+\)| - copia( \(\d+\))?| - copy( \(\d+\))?|_copia\d*)$'
$script:SeleccionPorDefecto = 'temp', 'scoped_dir', 'office_temporal', 'cache_juegos', 'log_gigante', 'instalador_repetido', 'duplicado'

function Get-CarpetasUsuario {
    # Carpetas del usuario respetando redirecciones (Documentos en otro disco, etc.). -Perfil: raíz
    # alternativa con subcarpetas Downloads, Documents... (para probar sobre una carpeta de prueba).
    param([string]$Perfil)
    if ($Perfil) {
        return [ordered]@{ Descargas = "$Perfil\Downloads"; Documentos = "$Perfil\Documents"; Imagenes = "$Perfil\Pictures"; Videos = "$Perfil\Videos"; Musica = "$Perfil\Music"
            Escritorio = "$Perfil\Desktop"; Temp = "$Perfil\AppData\Local\Temp"; Local = "$Perfil\AppData\Local"; Roaming = "$Perfil\AppData\Roaming"; Perfil = $Perfil }
    }
    $descargas = Get-ValorRegistro -Colmena HKCU -Ruta 'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Nombre '{374DE290-123F-4565-9164-39C4925E467B}'
    [ordered]@{
        Descargas  = $(if ($descargas) { [Environment]::ExpandEnvironmentVariables($descargas) } else { Join-Path $env:USERPROFILE 'Downloads' })
        Documentos = [Environment]::GetFolderPath('MyDocuments'); Imagenes = [Environment]::GetFolderPath('MyPictures'); Videos = [Environment]::GetFolderPath('MyVideos')
        Musica     = [Environment]::GetFolderPath('MyMusic'); Escritorio = [Environment]::GetFolderPath('Desktop'); Temp = [IO.Path]::GetTempPath().TrimEnd('\')
        Local      = [Environment]::GetFolderPath('LocalApplicationData'); Roaming = [Environment]::GetFolderPath('ApplicationData'); Perfil = [Environment]::GetFolderPath('UserProfile')
    }
}

function Get-ArchivosBajo {
    # Archivos bajo una carpeta, sin seguir reparse points (junctions, OneDrive) ni leer archivos en la nube.
    param([string]$Raiz)
    if (-not $Raiz -or -not [IO.Directory]::Exists($Raiz)) { return }
    $pila = New-Object System.Collections.Generic.Stack[string]
    $pila.Push($Raiz)
    while ($pila.Count -gt 0) {
        $hijos = $null
        try { $hijos = (New-Object IO.DirectoryInfo($pila.Pop())).GetFileSystemInfos() } catch { continue }
        foreach ($h in $hijos) {
            if ($h.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($h -is [IO.DirectoryInfo]) { $pila.Push($h.FullName) }
            elseif (-not ([int]$h.Attributes -band $script:AtributosNube)) { $h }
        }
    }
}

function Get-PermisoArchivos {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $a = Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion
    $faltan = @()
    if (@($a['motivos']) -notcontains 'ARCHIVOS') { $faltan += 'el motivo ARCHIVOS en la ficha' }
    if (-not $a['consentimiento_archivos']) { $faltan += 'el consentimiento para archivos' }
    if (@($a['carpetas_protegidas'] | Where-Object { $_ }).Count -eq 0) { $faltan += 'las carpetas protegidas' }
    [pscustomobject]@{
        PuedeAnalizar = ($faltan.Count -eq 0)
        PuedeMover    = ($faltan.Count -eq 0 -and $a['consentimiento_archivos'] -in 'mover', 'borrar_aprobado')
        Falta         = $faltan
        Protegidas    = @($a['carpetas_protegidas'] | Where-Object { $_ } | ForEach-Object { "$_".TrimEnd('\') })
        Consentimiento = $a['consentimiento_archivos']
    }
}

function Get-MotivoExclusion {
    # Por qué un archivo o carpeta no se puede tocar ($null = se puede).
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item, [Parameter(Mandatory)]$Reglas)
    $ruta = $Item.FullName
    foreach ($p in $Reglas.Protegidas) { if ($ruta.StartsWith("$p\", [StringComparison]::OrdinalIgnoreCase) -or $ruta -ieq $p) { return 'carpeta protegida' } }
    if ($Reglas.Escritorio -and $ruta.StartsWith("$($Reglas.Escritorio)\", [StringComparison]::OrdinalIgnoreCase)) { return 'Escritorio' }
    if ($ruta -match $Reglas.Credenciales) { return 'posibles credenciales' }
    if ($ruta -match $Reglas.Partidas) { return 'partida guardada' }
    if ($Item.LastWriteTime -gt $Reglas.Limite) { return "modificado en los últimos $($Reglas.Dias) días" }
    $null
}

function Get-HashParcial {
    # MD5 de los primeros y últimos 64 KB: descarta rápido los que solo coinciden en tamaño.
    param([string]$Ruta)
    $md5 = [Security.Cryptography.MD5]::Create()
    $fs = [IO.File]::Open($Ruta, 'Open', 'Read', 'ReadWrite')
    try {
        $n = [int][math]::Min(65536, $fs.Length)
        $buf = New-Object byte[] ($n * 2)
        [void]$fs.Read($buf, 0, $n)
        $fs.Seek(-$n, 'End') | Out-Null
        [void]$fs.Read($buf, $n, $n)
        [BitConverter]::ToString($md5.ComputeHash($buf)) -replace '-', ''
    } finally { $fs.Close(); $md5.Dispose() }
}

function Get-HashImagen {
    # Hash promedio 8x8 en grises: fotos casi iguales dan hashes con pocos bits distintos.
    param([string]$Ruta)
    $img = [Drawing.Image]::FromFile($Ruta)
    try { $mini = New-Object Drawing.Bitmap($img, 8, 8) } finally { $img.Dispose() }
    try {
        $g = New-Object double[] 64
        for ($i = 0; $i -lt 64; $i++) { $c = $mini.GetPixel($i % 8, [math]::Floor($i / 8)); $g[$i] = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B }
    } finally { $mini.Dispose() }
    $prom = ($g | Measure-Object -Average).Average
    [uint64]$h = 0
    for ($i = 0; $i -lt 64; $i++) { if ($g[$i] -ge $prom) { $h = $h -bor ([uint64]1 -shl $i) } }
    $h
}

function Get-DistanciaBits {
    param([uint64]$A, [uint64]$B)
    $x = $A -bxor $B
    $n = 0
    while ($x -ne 0) { $x = $x -band ($x - 1); $n++ }
    $n
}

function Invoke-AnalisisArchivos {
    # Busca basura y duplicados, y deja archivos\reporte.json y reporte.csv (para revisar en Excel).
    # No mueve nada.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [string]$Perfil, [int]$TiempoMaxSeg = 600)
    $permiso = Get-PermisoArchivos -Expediente $Expediente -Atencion $Atencion
    if (-not $permiso.PuedeAnalizar) { throw "Falta en la ficha: $($permiso.Falta -join ', ')" }
    $cfg = $script:Ctx.Config.archivos
    $u = Get-CarpetasUsuario -Perfil $Perfil
    $reglas = [pscustomobject]@{ Protegidas = $permiso.Protegidas; Escritorio = "$($u.Escritorio)".TrimEnd('\'); Credenciales = $cfg.nunca_credenciales; Partidas = $cfg.nunca_partidas
        Limite = (Get-Date).AddDays(-[int]$cfg.dias_recientes); Dias = [int]$cfg.dias_recientes }
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    $candidatos = New-Object System.Collections.Generic.List[object]
    $vistos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $excluidos = @{}
    $agregar = {
        param([IO.FileSystemInfo]$Item, [string]$Categoria, [string]$Motivo, [long]$Tamano, [hashtable]$Extra)
        if (-not $vistos.Add($Item.FullName)) { return }
        $razon = Get-MotivoExclusion -Item $Item -Reglas $reglas
        if ($razon) { $excluidos[$razon] = 1 + [int]$excluidos[$razon]; return }
        $sel = $Categoria -in $script:SeleccionPorDefecto
        $c = [ordered]@{ id = $candidatos.Count + 1; categoria = $Categoria; ruta = $Item.FullName; es_carpeta = ($Item -is [IO.DirectoryInfo]); tamano = $Tamano
            modificado = $Item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante); motivo = $Motivo; seleccionable = $sel; seleccionado = $sel; conserva = $null; hash_parcial = $null; grupo = $null }
        if ($Extra) { foreach ($k in $Extra.Keys) { $c[$k] = $Extra[$k] } }
        $candidatos.Add($c)
    }
    $limiteSeg = $TiempoMaxSeg
    $sinTiempo = { if ($reloj.Elapsed.TotalSeconds -gt $limiteSeg) { $script:ParcialArchivos = $true; $true } else { $false } }
    $script:ParcialArchivos = $false

    # 1. Temporales: carpetas scoped_dir de Chrome y archivos viejos de Temp.
    if ([IO.Directory]::Exists($u.Temp)) {
        foreach ($dir in (New-Object IO.DirectoryInfo($u.Temp)).GetDirectories()) {
            if ($dir.Name -notmatch '^scoped_dir\d+_\d+$' -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            $archivos = @(Get-ArchivosBajo $dir.FullName)
            $ultimo = if ($archivos.Count) { ($archivos | Measure-Object LastWriteTime -Maximum).Maximum } else { $dir.LastWriteTime }
            if ($ultimo -gt $reglas.Limite) { $excluidos["modificado en los últimos $($reglas.Dias) días"] = 1 + [int]$excluidos["modificado en los últimos $($reglas.Dias) días"]; continue }
            & $agregar $dir 'scoped_dir' 'Carpeta temporal que Chrome dejó olvidada' ([long]($archivos | Measure-Object Length -Sum).Sum) $null
        }
        foreach ($f in Get-ArchivosBajo $u.Temp) {
            if ($f.FullName -match '\\scoped_dir\d+_\d+\\') { continue }
            & $agregar $f 'temp' 'Archivo temporal viejo' $f.Length $null
        }
    }
    # 2. Archivos de bloqueo de Office (~$) que quedaron.
    foreach ($raiz in $u.Documentos, $u.Descargas) {
        foreach ($f in Get-ArchivosBajo $raiz) {
            if ($f.Name -like '~$*' -and $f.Extension -match '^\.(doc|xls|ppt)[xm]?$' -and $f.Length -lt 4096) { & $agregar $f 'office_temporal' 'Archivo de bloqueo de Office que quedó' $f.Length $null }
        }
    }
    # 3. Logs gigantes en AppData.
    $minLog = [long]$script:Ctx.Config.espacio.log_grande_mb * 1MB
    foreach ($raiz in $u.Local, $u.Roaming) {
        if (& $sinTiempo) { break }
        foreach ($f in Get-ArchivosBajo $raiz) {
            if ($f.Length -ge $minLog -and $f.Extension -in '.log', '.etl', '.txt') { & $agregar $f 'log_gigante' ('Log de {0}' -f (Format-Tamano $f.Length)) $f.Length $null }
        }
    }
    # 4. Cachés de juegos (se regeneran solas).
    foreach ($rel in @($cfg.caches_juegos)) {
        foreach ($f in Get-ArchivosBajo (Join-Path $u.Perfil $rel)) { & $agregar $f 'cache_juegos' "Caché de sombreadores ($rel); se vuelve a generar" $f.Length $null }
    }
    # 5. Instaladores repetidos en Descargas: se conserva el más nuevo de cada programa.
    if ([IO.Directory]::Exists($u.Descargas)) {
        $inst = @((New-Object IO.DirectoryInfo($u.Descargas)).GetFiles() | Where-Object { $_.Extension -in @($cfg.instalador_extensiones) })
        foreach ($g in ($inst | Group-Object { (([IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant() -replace $script:SufijoCopia, '') -replace '[\d._-]+', ' ').Trim() + $_.Extension.ToLowerInvariant() } | Where-Object { $_.Count -ge 2 })) {
            $orden = @($g.Group | Sort-Object LastWriteTime -Descending)
            foreach ($f in $orden | Select-Object -Skip 1) { & $agregar $f 'instalador_repetido' "Instalador repetido; se conserva $($orden[0].Name)" $f.Length @{ conserva = $orden[0].FullName } }
        }
    }
    # 6. Duplicados: tamaño -> hash parcial (el MD5 completo se calcula antes de mover).
    $minDup = [long]([double]$cfg.duplicado_min_mb * 1MB)
    $raices = [ordered]@{ $u.Escritorio = 0; $u.Imagenes = 1; $u.Documentos = 1; $u.Videos = 1; $u.Musica = 1; $u.Descargas = 2 }
    $todos = New-Object System.Collections.Generic.List[object]
    foreach ($r in $raices.Keys) {
        if (& $sinTiempo) { break }
        foreach ($f in Get-ArchivosBajo $r) { if ($f.Length -ge $minDup) { $todos.Add([pscustomobject]@{ F = $f; P = $raices[$r] }) } }
    }
    $grupo = 0
    foreach ($porTam in ($todos | Group-Object { $_.F.Length } | Where-Object { $_.Count -ge 2 })) {
        if (& $sinTiempo) { break }
        $conHash = foreach ($x in $porTam.Group) {
            try { $x | Add-Member -NotePropertyName H -NotePropertyValue (Get-HashParcial $x.F.FullName) -PassThru }
            catch { Write-LogKit -Nivel AVISO -Mensaje "No se pudo leer para buscar duplicados: $($x.F.FullName)" }
        }
        foreach ($g in (@($conHash) | Group-Object H | Where-Object { $_.Count -ge 2 })) {
            $grupo++
            # Se conserva la copia de Imágenes/Documentos/Videos/Música sin "(1)" ni "copia" (o la del
            # Escritorio o una carpeta protegida). Solo se apartan las de Descargas y las "(1)"/"copia";
            # si todas están en Descargas, se conserva la mejor.
            $esProtegida = { param($f) @($reglas.Protegidas | Where-Object { $f.FullName.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 }
            $orden = @($g.Group | Sort-Object @{ E = { if (& $esProtegida $_.F) { -1 } else { $_.P } } }, @{ E = { [int]([IO.Path]::GetFileNameWithoutExtension($_.F.Name) -match $script:SufijoCopia) } }, @{ E = { $_.F.LastWriteTime } }, @{ E = { $_.F.FullName.Length } })
            $conserva = $orden[0]
            foreach ($x in $orden | Select-Object -Skip 1) {
                $esCopia = [IO.Path]::GetFileNameWithoutExtension($x.F.Name) -match $script:SufijoCopia
                if ($x.P -lt 2 -and -not $esCopia) { continue }
                & $agregar $x.F 'duplicado' "Copia idéntica de $($conserva.F.FullName)" $x.F.Length @{ conserva = $conserva.F.FullName; hash_parcial = $x.H; grupo = $grupo }
            }
        }
    }
    # 7. Posibles restos de desinstalaciones (solo se reportan): carpetas de AppData sin cambios hace meses.
    $viejo = (Get-Date).AddDays(-[int]$cfg.restos_dias)
    foreach ($raiz in $u.Local, $u.Roaming) {
        if ((& $sinTiempo) -or -not [IO.Directory]::Exists($raiz)) { continue }
        foreach ($dir in (New-Object IO.DirectoryInfo($raiz)).GetDirectories()) {
            if (& $sinTiempo) { break }
            if ($dir.Name -match '^(?i)(microsoft|packages|temp|google|mozilla|nvidia|amd|intel|programs|crashdumps|d3dscache|connecteddevicesplatform|comms|virtualstore)$' -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            $arch = @(Get-ArchivosBajo $dir.FullName)
            if ($arch.Count -eq 0) { continue }
            $m = $arch | Measure-Object Length -Sum
            $ultimo = ($arch | Measure-Object LastWriteTime -Maximum).Maximum
            if ($ultimo -lt $viejo -and $m.Sum -ge [long]$cfg.restos_min_mb * 1MB -and $vistos.Add($dir.FullName)) {
                $candidatos.Add([ordered]@{ id = $candidatos.Count + 1; categoria = 'posible_resto'; ruta = $dir.FullName; es_carpeta = $true; tamano = [long]$m.Sum; modificado = $ultimo.ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante)
                        motivo = "Sin cambios desde $($ultimo.ToString('yyyy-MM-dd')): revisar si el programa sigue instalado"; seleccionable = $false; seleccionado = $false; conserva = $null; hash_parcial = $null; grupo = $null })
            }
        }
    }
    # 8. Fotos parecidas (solo se reportan: pueden ser ráfagas de trabajo, terreno, trampas cámara...).
    $fotos = @(Get-ArchivosBajo $u.Imagenes | Where-Object { $_.Extension -match '^\.(jpe?g|png|bmp)$' } | Select-Object -First ([int]$cfg.fotos_max))
    $relojFotos = [Diagnostics.Stopwatch]::StartNew()
    $hashes = New-Object System.Collections.Generic.List[object]
    foreach ($f in $fotos) {
        if ($relojFotos.Elapsed.TotalSeconds -gt [int]$cfg.fotos_tiempo_seg -or (& $sinTiempo)) { $script:ParcialArchivos = $true; break }
        try { $hashes.Add([pscustomobject]@{ F = $f; H = (Get-HashImagen $f.FullName) }) } catch { Write-LogKit -Nivel AVISO -Mensaje "Foto ilegible: $($f.Name)" }
    }
    $yaEnGrupo = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $gf = 0
    foreach ($b in ($hashes | Group-Object { $_.H -shr 48 })) {
        $lista = @($b.Group)
        for ($i = 0; $i -lt $lista.Count; $i++) {
            if ($yaEnGrupo.Contains($lista[$i].F.FullName)) { continue }
            $parecidas = @($lista[$i]) + @(for ($j = $i + 1; $j -lt $lista.Count; $j++) { if (-not $yaEnGrupo.Contains($lista[$j].F.FullName) -and (Get-DistanciaBits $lista[$i].H $lista[$j].H) -le [int]$cfg.fotos_distancia -and $lista[$j].F.Length -ne $lista[$i].F.Length) { $lista[$j] } })
            if ($parecidas.Count -lt 2) { continue }
            $gf++
            foreach ($p in $parecidas) {
                [void]$yaEnGrupo.Add($p.F.FullName)
                $candidatos.Add([ordered]@{ id = $candidatos.Count + 1; categoria = 'foto_parecida'; ruta = $p.F.FullName; es_carpeta = $false; tamano = $p.F.Length; modificado = $p.F.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante)
                        motivo = "Grupo de fotos parecidas $gf (solo informativo: se revisan con el cliente)"; seleccionable = $false; seleccionado = $false; conserva = $null; hash_parcial = $null; grupo = "F$gf" })
            }
        }
    }

    $resumen = [ordered]@{}
    foreach ($g in ($candidatos | Group-Object { $_.categoria })) {
        $resumen[$g.Name] = [ordered]@{ cantidad = $g.Count; bytes = [long](@($g.Group | ForEach-Object { $_.tamano }) | Measure-Object -Sum).Sum; seleccionados = @($g.Group | Where-Object { $_.seleccionado }).Count }
    }
    $rep = [ordered]@{ version = 1; generado = ConvertTo-TextoFecha (Get-Date); duracion_seg = [math]::Round($reloj.Elapsed.TotalSeconds, 1); parcial = $script:ParcialArchivos
        carpetas = $u; protegidas = $permiso.Protegidas; resumen = $resumen; excluidos = $excluidos; candidatos = $candidatos.ToArray() }
    $dir = Join-Path (Join-Path $Expediente.Ruta $Atencion) 'archivos'
    $null = [IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'reporte.json'), ($rep | ConvertTo-Json -Depth 6), $script:Utf8SinBom)
    $candidatos | ForEach-Object { [pscustomobject]@{ Id = $_.id; Categoria = $_.categoria; Seleccionado = $(if ($_.seleccionado) { 'Sí' } else { 'No' }); Tamano = Format-Tamano $_.tamano; Ruta = $_.ruta; Motivo = $_.motivo; Conserva = $_.conserva; Modificado = $_.modificado } } |
        Export-Csv -LiteralPath (Join-Path $dir 'reporte.csv') -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    $sel = @($candidatos | Where-Object { $_.seleccionado })
    Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto ('ARCHIVOS | análisis: {0} candidatos, {1} marcados ({2}){3}' -f $candidatos.Count, $sel.Count, (Format-Tamano ([long](@($sel | ForEach-Object { $_.tamano }) | Measure-Object -Sum).Sum)), $(if ($script:ParcialArchivos) { ' | PARCIAL por tiempo' } else { '' }))
    [pscustomobject]$rep
}

function Read-ReporteArchivos {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $r = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'archivos') 'reporte.json'
    if ([IO.File]::Exists($r)) { ConvertTo-Diccionario (Read-JsonKit $r) } else { $null }
}

function Get-ScriptDeshacer {
    # _DESHACER.ps1 autónomo: lleva la lista adentro y devuelve todo a su lugar sin borrar nada.
    param([Parameter(Mandatory)][object[]]$Movimientos, [string]$Fecha)
    $json = ConvertTo-Json -InputObject @($Movimientos) -Depth 4
    @"
# _DESHACER.ps1 - Devuelve a su lugar los archivos que el servicio técnico apartó el $Fecha.
# Clic derecho > Ejecutar con PowerShell. No borra nada: si en el lugar original ya hay un archivo con
# el mismo nombre, el apartado se queda aquí y se avisa.
`$movimientos = @'
$json
'@ | ConvertFrom-Json
`$ok = 0; `$quedan = 0
foreach (`$m in `$movimientos) {
    if (-not (Test-Path -LiteralPath `$m.destino)) { Write-Host "Ya no está aquí: `$(`$m.destino)" -ForegroundColor Yellow; `$quedan++; continue }
    if (Test-Path -LiteralPath `$m.origen) { Write-Host "Ya existe en su lugar, se deja aquí: `$(`$m.origen)" -ForegroundColor Yellow; `$quedan++; continue }
    `$padre = Split-Path -Parent `$m.origen
    if (-not (Test-Path -LiteralPath `$padre)) { New-Item -ItemType Directory -Path `$padre -Force | Out-Null }
    Move-Item -LiteralPath `$m.destino -Destination `$m.origen
    if (`$m.md5 -and (Get-FileHash -LiteralPath `$m.origen -Algorithm MD5).Hash -ne `$m.md5) { Write-Host "OJO, el contenido no calza: `$(`$m.origen)" -ForegroundColor Red }
    `$ok++
}
Write-Host "Devueltos: `$ok | se quedaron aquí: `$quedan"
if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) { Read-Host 'Enter para cerrar' | Out-Null }
"@
}

function Move-ArchivosParaBorrar {
    # Mueve los candidatos marcados (o los -Ids) a <unidad>:\_PARA_BORRAR\<fecha_hora>, en el mismo disco.
    # Antes de mover vuelve a revisar cada uno; los duplicados se confirman con MD5 completo.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [int[]]$Ids, [string[]]$Categorias)
    $permiso = Get-PermisoArchivos -Expediente $Expediente -Atencion $Atencion
    if (-not $permiso.PuedeMover) { throw "Sin permiso para mover (consentimiento: $($permiso.Consentimiento); falta: $($permiso.Falta -join ', '))" }
    $rep = Read-ReporteArchivos -Expediente $Expediente -Atencion $Atencion
    if (-not $rep) { throw 'Primero hay que analizar (no hay reporte.json)' }
    $cfg = $script:Ctx.Config.archivos
    $reglas = [pscustomobject]@{ Protegidas = $permiso.Protegidas; Escritorio = "$($rep['carpetas']['Escritorio'])".TrimEnd('\'); Credenciales = $cfg.nunca_credenciales; Partidas = $cfg.nunca_partidas
        Limite = (Get-Date).AddDays(-[int]$cfg.dias_recientes); Dias = [int]$cfg.dias_recientes }
    $elegidos = @($rep['candidatos'] | Where-Object { $_['seleccionable'] -and ($(if ($Ids) { $_['id'] -in $Ids } else { $_['seleccionado'] })) -and (-not $Categorias -or $_['categoria'] -in $Categorias) })
    $marca = (Get-Date).ToString('yyyy-MM-dd_HHmm', $script:Invariante)
    $movs = New-Object System.Collections.Generic.List[object]
    $saltados = New-Object System.Collections.Generic.List[string]
    foreach ($c in $elegidos) {
        $ruta = $c['ruta']
        $item = if ($c['es_carpeta']) { New-Object IO.DirectoryInfo($ruta) } else { New-Object IO.FileInfo($ruta) }
        if (-not $item.Exists) { $saltados.Add("ya no existe: $ruta"); continue }
        if ($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante) -ne $c['modificado'] -and -not $c['es_carpeta']) { $saltados.Add("cambió desde el análisis: $ruta"); continue }
        $razon = Get-MotivoExclusion -Item $item -Reglas $reglas
        if ($razon -and $c['categoria'] -ne 'scoped_dir') { $saltados.Add("${razon}: $ruta"); continue }
        $md5 = $null
        if (-not $c['es_carpeta']) {
            $md5 = (Get-FileHash -LiteralPath $ruta -Algorithm MD5).Hash
            if ($c['categoria'] -eq 'duplicado') {
                if (-not [IO.File]::Exists($c['conserva']) -or (Get-FileHash -LiteralPath $c['conserva'] -Algorithm MD5).Hash -ne $md5) { $saltados.Add("no es idéntico a $($c['conserva']): $ruta"); continue }
            }
        }
        $raiz = [IO.Path]::GetPathRoot($ruta)
        $destRaiz = Join-Path $raiz "_PARA_BORRAR\$marca"
        $destino = Join-Path $destRaiz $ruta.Substring($raiz.Length)
        $n = 2
        while (Test-Path -LiteralPath $destino) { $destino = '{0} ({1}){2}' -f [IO.Path]::Combine([IO.Path]::GetDirectoryName($destino), [IO.Path]::GetFileNameWithoutExtension($destino)), $n, [IO.Path]::GetExtension($destino); $n++ }
        if (-not $PSCmdlet.ShouldProcess($ruta, "Mover a $destRaiz")) { continue }
        try {
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destino))
            if ($c['es_carpeta']) { [IO.Directory]::Move($ruta, $destino) } else { [IO.File]::Move($ruta, $destino) }
            $movs.Add([ordered]@{ origen = $ruta; destino = $destino; es_carpeta = [bool]$c['es_carpeta']; tamano = [long]$c['tamano']; md5 = $md5; categoria = $c['categoria']; raiz = $destRaiz })
        } catch {
            $saltados.Add("no se pudo mover ($($_.Exception.Message.Trim())): $ruta")
        }
    }
    $dir = Join-Path (Join-Path $Expediente.Ruta $Atencion) 'archivos'
    $archivoMovs = Join-Path $dir 'movimientos.json'
    $lotes = if ([IO.File]::Exists($archivoMovs)) { @((ConvertTo-Diccionario (Read-JsonKit $archivoMovs))['lotes'] | Where-Object { $_ }) } else { @() }
    if ($movs.Count -gt 0) {
        $fecha = ConvertTo-TextoFecha (Get-Date)
        foreach ($g in ($movs | Group-Object { $_.raiz })) {
            $lista = @($g.Group | ForEach-Object { [ordered]@{ origen = $_.origen; destino = $_.destino; md5 = $_.md5 } })
            [IO.File]::WriteAllText((Join-Path $g.Name '_DESHACER.ps1'), (Get-ScriptDeshacer -Movimientos $lista -Fecha $fecha), $script:Utf8Bom)
            $leeme = "Archivos apartados por el servicio técnico el $fecha ($($g.Count) elementos, $(Format-Tamano ([long]($g.Group | ForEach-Object { $_.tamano } | Measure-Object -Sum).Sum))).`r`n" +
                "Nada se borró. Para devolverlos a su lugar: clic derecho en _DESHACER.ps1 > Ejecutar con PowerShell.`r`n" +
                "Si en 30 días no echas nada de menos, puedes borrar esta carpeta.`r`n"
            [IO.File]::WriteAllText((Join-Path $g.Name 'LEEME.txt'), $leeme, $script:Utf8Bom)
        }
        [IO.File]::WriteAllText((Join-Path $dir '_DESHACER.ps1'), (Get-ScriptDeshacer -Movimientos @($movs | ForEach-Object { [ordered]@{ origen = $_.origen; destino = $_.destino; md5 = $_.md5 } }) -Fecha $fecha), $script:Utf8Bom)
        $lotes = @($lotes) + @([ordered]@{ marca = $marca; fecha = $fecha; deshecho = $null; items = $movs.ToArray() })
        [IO.File]::WriteAllText($archivoMovs, ([ordered]@{ lotes = $lotes } | ConvertTo-Json -Depth 6), $script:Utf8SinBom)
        $movs | ForEach-Object { [pscustomobject]$_ } | Select-Object categoria, tamano, md5, origen, destino | Export-Csv -LiteralPath (Join-Path $dir "movimientos_$marca.csv") -Delimiter ';' -Encoding UTF8 -NoTypeInformation
        $total = [long]($movs | ForEach-Object { $_.tamano } | Measure-Object -Sum).Sum
        $raices = @($movs | ForEach-Object { $_.raiz } | Select-Object -Unique)
        Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto ("ARCHIVOS | movidos $($movs.Count) elementos ($(Format-Tamano $total)) a $($raices -join ', ') | deshacer: _DESHACER.ps1 en esa carpeta o en archivos\")
        $previas = @((Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion)['acciones_realizadas'] | Where-Object { $_ })
        Set-Ficha -Expediente $Expediente -Atencion $Atencion -Valores @{ acciones_realizadas = @($previas + "Se apartaron $($movs.Count) archivos innecesarios o duplicados ($(Format-Tamano $total)) en $($raices -join ', ')") }
    }
    foreach ($s in $saltados) { Write-LogKit -Nivel AVISO -Mensaje "ARCHIVOS no movido, $s" }
    [pscustomobject]@{ Movidos = $movs.Count; Bytes = [long]($movs | ForEach-Object { $_.tamano } | Measure-Object -Sum).Sum; Saltados = $saltados.ToArray(); Destinos = @($movs | ForEach-Object { $_.raiz } | Select-Object -Unique) }
}

function Undo-MovimientoArchivos {
    # Devuelve a su lugar todo lo movido (lotes no deshechos), igual que _DESHACER.ps1.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $archivoMovs = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'archivos') 'movimientos.json'
    if (-not [IO.File]::Exists($archivoMovs)) { throw 'No hay movimientos que deshacer' }
    $doc = ConvertTo-Diccionario (Read-JsonKit $archivoMovs)
    $ok = 0; $problemas = New-Object System.Collections.Generic.List[string]
    foreach ($lote in @($doc['lotes'] | Where-Object { $_ -and -not $_['deshecho'] })) {
        foreach ($m in @($lote['items'])) {
            if (-not $PSCmdlet.ShouldProcess($m['origen'], 'Devolver')) { continue }
            if (-not (Test-Path -LiteralPath $m['destino'])) { $problemas.Add("ya no está en _PARA_BORRAR: $($m['destino'])"); continue }
            if (Test-Path -LiteralPath $m['origen']) { $problemas.Add("ya existe en su lugar: $($m['origen'])"); continue }
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($m['origen']))
            if ($m['es_carpeta']) { [IO.Directory]::Move($m['destino'], $m['origen']) } else { [IO.File]::Move($m['destino'], $m['origen']) }
            if ($m['md5'] -and (Get-FileHash -LiteralPath $m['origen'] -Algorithm MD5).Hash -ne $m['md5']) { $problemas.Add("el contenido no calza: $($m['origen'])") }
            $ok++
        }
        $lote['deshecho'] = ConvertTo-TextoFecha (Get-Date)
        # Si todo volvió, en la carpeta del lote solo quedan lo del kit (LEEME.txt y _DESHACER.ps1) y carpetas
        # vacías: se retiran para no dejarle al cliente una carpeta "para borrar" vacía. Si queda cualquier
        # otro archivo, no se toca nada. Nunca se borra un archivo del cliente.
        foreach ($raiz in @($lote['items'] | ForEach-Object { $_['raiz'] } | Select-Object -Unique)) {
            if (-not $raiz -or -not [IO.Directory]::Exists($raiz)) { continue }
            $ajenos = @([IO.Directory]::GetFiles($raiz, '*', 'AllDirectories') | Where-Object { [IO.Path]::GetDirectoryName($_) -ne $raiz -or [IO.Path]::GetFileName($_) -notin '_DESHACER.ps1', 'LEEME.txt' })
            if ($ajenos.Count -or -not $PSCmdlet.ShouldProcess($raiz, 'Retirar la carpeta vacía del lote')) { continue }
            foreach ($f in '_DESHACER.ps1', 'LEEME.txt') { $r = Join-Path $raiz $f; if ([IO.File]::Exists($r)) { [IO.File]::Delete($r) } }
            foreach ($d in @(@([IO.Directory]::GetDirectories($raiz, '*', 'AllDirectories') | Sort-Object Length -Descending) + $raiz)) {
                if (@([IO.Directory]::GetFileSystemEntries($d)).Count -eq 0) { [IO.Directory]::Delete($d) }
            }
            $padre = [IO.Path]::GetDirectoryName($raiz)
            if ([IO.Path]::GetFileName($padre) -eq '_PARA_BORRAR' -and [IO.Directory]::Exists($padre) -and @([IO.Directory]::GetFileSystemEntries($padre)).Count -eq 0) { [IO.Directory]::Delete($padre) }
        }
    }
    [IO.File]::WriteAllText($archivoMovs, ($doc | ConvertTo-Json -Depth 6), $script:Utf8SinBom)
    Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto ("ARCHIVOS | deshecho: devueltos $ok elementos$(if ($problemas.Count) { "; problemas: $($problemas.Count)" })")
    $quedan = @((Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion)['acciones_realizadas'] | Where-Object { $_ -and $_ -notlike 'Se apartaron *' })
    Set-Ficha -Expediente $Expediente -Atencion $Atencion -Valores @{ acciones_realizadas = $quedan }
    [pscustomobject]@{ Devueltos = $ok; Problemas = $problemas.ToArray() }
}

function Get-MetricasArchivos {
    # Para el cliente: GB apartados, duplicados apartados, dónde quedó todo y cómo recuperarlo.
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $archivoMovs = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'archivos') 'movimientos.json'
    $items = @()
    if ([IO.File]::Exists($archivoMovs)) { $items = @((Read-JsonKit $archivoMovs).lotes | Where-Object { $_ -and -not $_.deshecho } | ForEach-Object { $_.items }) }
    $bytes = [long](@($items | ForEach-Object { $_.tamano }) | Measure-Object -Sum).Sum
    $libre = { param($m) if ($m) { (@($m.espacio) | Where-Object { $_.sistema } | Select-Object -First 1).libre_gb } else { $null } }
    $ma = Read-JsonKitOpcional (Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'antes') 'metricas.json')
    $md = Read-JsonKitOpcional (Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'despues') 'metricas.json')
    [pscustomobject][ordered]@{
        Motivo        = 'ARCHIVOS'
        Tarjetas      = @(Get-TarjetaMetrica -Titulo 'Espacio libre en C:' -Antes (& $libre $ma) -Despues (& $libre $md) -Unidad 'GB' -Mejor mayor)
        GBApartados   = [math]::Round($bytes / 1GB, 2)
        Elementos     = $items.Count
        Duplicados    = @($items | Where-Object { $_.categoria -eq 'duplicado' }).Count
        Ubicaciones   = @($items | ForEach-Object { $_.raiz } | Select-Object -Unique)
        ComoRecuperar = 'Clic derecho en _DESHACER.ps1 (en la misma carpeta) > Ejecutar con PowerShell. Pasados 30 días, si no echas nada de menos, se puede borrar la carpeta.'
        Advertencias  = @()
    }
}
