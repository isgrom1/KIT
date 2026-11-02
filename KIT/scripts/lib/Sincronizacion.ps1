# Sincronizacion.ps1 - Copia los expedientes del USB al maestro de tu PC sin pisar nada.
# - Va en un solo sentido: USB -> maestro. Un archivo nuevo se copia; uno idéntico (mismo SHA-256) se salta.
# - Si un archivo cambió, el estado de la sincronización anterior (el hash que este kit dejó en el
#   maestro) dice quién lo cambió:
#     cambió solo en el USB       -> se actualiza el maestro y su versión anterior queda en
#                                    _sincronizacion\anteriores\<fecha_hora>\ (nunca se pierde nada).
#     cambió solo en el maestro   -> se deja el del maestro (p. ej. un informe regenerado allá).
#     cambió en los dos, o este kit nunca había sincronizado ese archivo -> CONFLICTO: el del maestro
#                                    no se toca y el del USB queda al lado como
#                                    "nombre (conflicto USB AAAA-MM-DD_HHmmss).ext". Se avisa.
# - Cada copia se verifica por hash antes de darla por buena: se copia a .sync_tmp y recién se renombra.
# - Liberar el USB: una atención entregada se borra del USB solo si cada archivo suyo tiene una copia
#   idéntica en el maestro (hash recalculado en los dos lados): en su lugar, como copia de conflicto o,
#   si el maestro lo cambió después (informe regenerado allá), en _sincronizacion\anteriores. Si un
#   archivo no llegó al maestro, la atención queda entera en el USB. La ficha queda en el USB para seguir
#   reconociendo al cliente; las fotos de recepción salen cuando el expediente ya no tiene atenciones abiertas.
# - Un log por sincronización en <maestro>\_sincronizacion\logs, con copia en <USB>\clientes\_sincronizacion\logs.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:CarpetaSync = '_sincronizacion'
# Archivos propios del kit que no son datos: no se copian y, al liberar, se van con la atención.
$script:PatronTransitorio = '(?i)(\.sync_tmp|^_gui_parametros\.json|^ficha\.json\.(tmp|bak))$'

function Test-EquipoTecnico {
    # Sincronizar solo aparece en tus equipos: config.json -> equipos_tecnico.
    [OutputType([bool])]
    param()
    @($script:Ctx.Config.equipos_tecnico) -contains $env:COMPUTERNAME
}

function Get-RutaMaestro {
    [OutputType([string])]
    param()
    $s = $script:Ctx.Config.sincronizacion
    if ($s -and $s.ruta_maestro) { [Environment]::ExpandEnvironmentVariables([string]$s.ruta_maestro) } else { '' }
}

function Get-TextoArchivos { param([int]$N) if ($N -eq 1) { '1 archivo' } else { "$N archivos" } }

function Get-HashArchivo {
    param([Parameter(Mandatory)][string]$Ruta)
    (Get-FileHash -LiteralPath $Ruta -Algorithm SHA256).Hash
}

function Get-IdKit {
    # Identifica este USB ante el maestro: el estado de la sincronización anterior se guarda por kit.
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Clientes)
    $archivo = Join-Path (Join-Path $Clientes $script:CarpetaSync) 'kit.json'
    $k = Read-JsonKitOpcional $archivo
    if ($k -and $k.id) { return [string]$k.id }
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $archivo))
    $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    [IO.File]::WriteAllText($archivo, ([ordered]@{ id = $id; creado = ConvertTo-TextoFecha (Get-Date) } | ConvertTo-Json), $script:Utf8SinBom)
    $id
}

function Read-EstadoSincronizacion {
    # Hash que este kit dejó en el maestro, por ruta relativa. Archivo de texto "hash<TAB>ruta".
    param([Parameter(Mandatory)][string]$Ruta)
    $base = @{}
    if ([IO.File]::Exists($Ruta)) {
        foreach ($l in [IO.File]::ReadAllLines($Ruta, [Text.Encoding]::UTF8)) {
            $i = $l.IndexOf("`t")
            if ($l.StartsWith('#') -or $i -lt 1) { continue }
            $base[$l.Substring($i + 1)] = $l.Substring(0, $i)
        }
    }
    $base
}

function Save-EstadoSincronizacion {
    param([Parameter(Mandatory)][string]$Ruta, [Parameter(Mandatory)][hashtable]$Base)
    $lineas = New-Object System.Collections.Generic.List[string]
    $lineas.Add("# SHA-256 que este kit dejó en el maestro (para saber quién cambió cada archivo). $(ConvertTo-TextoFecha (Get-Date))")
    foreach ($k in @($Base.Keys | Sort-Object)) { $lineas.Add("$($Base[$k])`t$k") }
    $temporal = "$Ruta.tmp"
    [IO.File]::WriteAllLines($temporal, $lineas, $script:Utf8Bom)
    if ([IO.File]::Exists($Ruta)) { [IO.File]::Delete($Ruta) }
    [IO.File]::Move($temporal, $Ruta)
}

function Get-ArchivosExpedientes {
    # Archivos a copiar con su ruta relativa a clientes\. Se saltan _sincronizacion, las carpetas sin
    # ficha, las mediciones en curso (se copian cuando terminen) y los transitorios del kit.
    param([Parameter(Mandatory)][string]$Clientes)
    $archivos = New-Object System.Collections.Generic.List[object]
    $enCurso = New-Object System.Collections.Generic.List[string]
    $largo = $Clientes.TrimEnd('\').Length + 1
    foreach ($exp in [IO.Directory]::GetDirectories($Clientes)) {
        if ([IO.Path]::GetFileName($exp).StartsWith('_') -or -not [IO.File]::Exists((Join-Path $exp 'ficha.json'))) { continue }
        $pila = New-Object System.Collections.Generic.Stack[string]
        $pila.Push($exp)
        while ($pila.Count) {
            $dir = $pila.Pop()
            foreach ($d in [IO.Directory]::GetDirectories($dir)) {
                if ($d -match '_en_curso$') { $enCurso.Add($d.Substring($largo)) } else { $pila.Push($d) }
            }
            foreach ($f in [IO.Directory]::GetFiles($dir)) {
                if ([IO.Path]::GetFileName($f) -match $script:PatronTransitorio) { continue }
                $archivos.Add([pscustomobject]@{ Rel = $f.Substring($largo); Ruta = $f })
            }
        }
    }
    [pscustomobject]@{ Archivos = $archivos.ToArray(); EnCurso = $enCurso.ToArray() }
}

function Copy-ArchivoVerificado {
    # Copia a <destino>.sync_tmp, compara el hash con el del original y recién ahí renombra. Nunca pisa:
    # si el destino existe hay que dar -Respaldo, adonde se mueve la versión que había.
    param([Parameter(Mandatory)][string]$Origen, [Parameter(Mandatory)][string]$Destino, [Parameter(Mandatory)][string]$Hash, [string]$Respaldo)
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destino))
    $temporal = "$Destino.sync_tmp"
    [IO.File]::Copy($Origen, $temporal, $true)
    if ((Get-HashArchivo $temporal) -ne $Hash) {
        [IO.File]::Delete($temporal)
        throw 'la copia no calza con el original (hash distinto); se reintenta en la próxima sincronización'
    }
    if ($Respaldo) {
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Respaldo))
        [IO.File]::Move($Destino, $Respaldo)
        try { [IO.File]::Move($temporal, $Destino) } catch { [IO.File]::Move($Respaldo, $Destino); throw }
    } else {
        [IO.File]::Move($temporal, $Destino)
    }
}

function Get-CopiasConflicto {
    # "nombre (conflicto USB ...).ext" junto al archivo del maestro.
    param([Parameter(Mandatory)][string]$Ruta)
    $dir = [IO.Path]::GetDirectoryName($Ruta)
    if (-not [IO.Directory]::Exists($dir)) { return }
    $prefijo = '{0} (conflicto USB ' -f [IO.Path]::GetFileNameWithoutExtension($Ruta)
    $fin = ')' + [IO.Path]::GetExtension($Ruta)
    foreach ($f in [IO.Directory]::GetFiles($dir)) {
        $n = [IO.Path]::GetFileName($f)
        if ($n.StartsWith($prefijo, [StringComparison]::OrdinalIgnoreCase) -and $n.EndsWith($fin, [StringComparison]::OrdinalIgnoreCase)) { $f }
    }
}

function Confirm-CopiaEnMaestro {
    # ¿Hay en el maestro una copia idéntica (hash recalculado) de este archivo del USB? Vale la de su
    # lugar o una copia de conflicto. Si el maestro cambió el archivo después de recibir esta versión
    # (p. ej. un informe regenerado allá), esta versión se guarda verificada en _sincronizacion\anteriores.
    # Sin archivo en su lugar del maestro no vale nada: esa copia no llegó.
    # Devuelve dónde está: 'lugar', 'conflicto', 'anteriores' o 'guardada' (recién copiada); '' si no está.
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RutaUsb,
        [Parameter(Mandatory)][string]$Maestro,
        [Parameter(Mandatory)][string]$Rel,
        [Parameter(Mandatory)][hashtable]$Base,
        [Parameter(Mandatory)][string]$Anteriores
    )
    $enMaestro = Join-Path $Maestro $Rel
    if (-not [IO.File]::Exists($enMaestro)) { return '' }
    $h = Get-HashArchivo $RutaUsb
    if ((Get-HashArchivo $enMaestro) -eq $h) { return 'lugar' }
    foreach ($c in @(Get-CopiasConflicto $enMaestro)) { if ((Get-HashArchivo $c) -eq $h) { return 'conflicto' } }
    if ($Base[$Rel] -ne $h) { return '' }
    $dirAnteriores = Split-Path -Parent $Anteriores
    if ([IO.Directory]::Exists($dirAnteriores)) {
        foreach ($d in [IO.Directory]::GetDirectories($dirAnteriores)) {
            $a = Join-Path $d $Rel
            if ([IO.File]::Exists($a) -and (Get-HashArchivo $a) -eq $h) { return 'anteriores' }
        }
    }
    Copy-ArchivoVerificado -Origen $RutaUsb -Destino (Join-Path $Anteriores $Rel) -Hash $h
    'guardada'
}

function Remove-EntregadasUsb {
    # Borra del USB las atenciones entregadas cuyos archivos tienen copia idéntica en el maestro, uno
    # por uno. Si falta uno solo (o cambió mientras tanto), esa atención queda entera en el USB.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Clientes,
        [Parameter(Mandatory)][string]$Maestro,
        [Parameter(Mandatory)][hashtable]$Base,
        [Parameter(Mandatory)][string]$Anteriores,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Resultado,
        [Parameter(Mandatory)][scriptblock]$Escribir,
        [scriptblock]$AlAvance = {}
    )
    $largo = $Clientes.TrimEnd('\').Length + 1
    foreach ($dirExp in [IO.Directory]::GetDirectories($Clientes)) {
        $id = [IO.Path]::GetFileName($dirExp)
        if ($id.StartsWith('_') -or -not [IO.File]::Exists((Join-Path $dirExp 'ficha.json'))) { continue }
        try { $exp = Read-Expediente $dirExp } catch { $Resultado.NoLiberadas.Add("${id}: ficha ilegible ($($_.Exception.Message))"); continue }
        $lista = @(Get-ListaAtenciones -Expediente $exp)
        $carpetas = @($lista | Where-Object { $_['entregado'] } | ForEach-Object { $_['carpeta'] } | Where-Object { [IO.Directory]::Exists((Join-Path $dirExp $_)) })
        $fotos = Join-Path $dirExp 'fotos_recepcion'
        if (@($lista | Where-Object { -not $_['entregado'] }).Count -eq 0 -and [IO.Directory]::Exists($fotos) -and [IO.Directory]::GetFiles($fotos, '*', 'AllDirectories').Count) { $carpetas += 'fotos_recepcion' }
        foreach ($c in $carpetas) {
            $rel = "$id\$c"
            & $AlAvance "Verificando $rel en el maestro..."
            $origen = Join-Path $dirExp $c
            if (@([IO.Directory]::GetDirectories($origen, '*_en_curso', 'AllDirectories')).Count) {
                $Resultado.NoLiberadas.Add("${rel}: tiene una medición a medias (carpeta _en_curso)")
                & $Escribir 'NO LIBERADO' "$rel (tiene una medición a medias)"
                continue
            }
            $verificados = New-Object System.Collections.Generic.List[object]
            $faltan = New-Object System.Collections.Generic.List[string]
            $guardadas = 0
            foreach ($f in [IO.Directory]::GetFiles($origen, '*', 'AllDirectories')) {
                $info = New-Object IO.FileInfo $f
                $donde = 'lugar'
                if ($info.Name -notmatch $script:PatronTransitorio) {
                    try { $donde = Confirm-CopiaEnMaestro -RutaUsb $f -Maestro $Maestro -Rel $f.Substring($largo) -Base $Base -Anteriores $Anteriores } catch { $donde = '' }
                }
                if (-not $donde) { $faltan.Add($f.Substring($largo)); continue }
                if ($donde -eq 'guardada') { $guardadas++ }
                $verificados.Add($info)
            }
            if ($guardadas) { & $Escribir 'ANTERIORES' "$rel ($(Get-TextoArchivos $guardadas) cambiaron después en el maestro: la versión del USB quedó en $script:CarpetaSync\anteriores)" }
            if ($faltan.Count) {
                $Resultado.NoLiberadas.Add("${rel}: $(Get-TextoArchivos $faltan.Count) sin copia idéntica en el maestro (ej.: $($faltan[0]))")
                & $Escribir 'NO LIBERADO' "$rel ($(Get-TextoArchivos $faltan.Count) sin copia idéntica en el maestro; ej.: $($faltan[0]))"
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($origen, 'Borrar del USB (verificada en el maestro)')) { continue }
            $bytes = [long]0
            $cambiados = 0
            foreach ($info in $verificados) {
                # Si cambió después de verificarlo (alguien escribió justo ahora), no se borra.
                $ahora = New-Object IO.FileInfo $info.FullName
                if (-not $ahora.Exists -or $ahora.Length -ne $info.Length -or $ahora.LastWriteTimeUtc -ne $info.LastWriteTimeUtc) { $cambiados++; continue }
                $bytes += $info.Length
                [IO.File]::Delete($info.FullName)
            }
            # Carpetas vacías de abajo hacia arriba; fotos_recepcion se deja (vacía) para las próximas fotos.
            foreach ($d in @([IO.Directory]::GetDirectories($origen, '*', 'AllDirectories') | Sort-Object Length -Descending)) {
                if (@([IO.Directory]::GetFileSystemEntries($d)).Count -eq 0) { [IO.Directory]::Delete($d) }
            }
            if ($c -ne 'fotos_recepcion' -and @([IO.Directory]::GetFileSystemEntries($origen)).Count -eq 0) { [IO.Directory]::Delete($origen) }
            $Resultado.BytesLiberados += $bytes
            if ($cambiados) {
                $Resultado.NoLiberadas.Add("${rel}: $(Get-TextoArchivos $cambiados) cambiaron mientras se verificaba; quedaron en el USB")
                & $Escribir 'NO LIBERADO' "$rel ($(Get-TextoArchivos $cambiados) cambiaron durante la verificación; quedaron en el USB)"
            } else {
                $Resultado.Liberadas.Add($rel)
                & $Escribir 'LIBERADO' "$rel ($(Format-Tamano $bytes) en $(Get-TextoArchivos $verificados.Count), verificados por hash en el maestro)"
            }
        }
    }
}

function Invoke-Sincronizacion {
    # Copia clientes\ del USB al maestro. -LiberarUsb: después deja en el USB solo las atenciones abiertas.
    # $AlAvance recibe textos cortos para mostrar el avance. Devuelve el resumen (también queda en el log).
    param(
        [Parameter(Mandatory)][string]$Clientes,
        [Parameter(Mandatory)][string]$Maestro,
        [switch]$LiberarUsb,
        [scriptblock]$AlAvance = {}
    )
    $Clientes = [IO.Path]::GetFullPath($Clientes).TrimEnd('\')
    $Maestro = [IO.Path]::GetFullPath($Maestro).TrimEnd('\')
    if (-not [IO.Directory]::Exists($Clientes)) { throw "No existe la carpeta de expedientes del USB: $Clientes" }
    if ($Maestro -eq $Clientes -or $Maestro.StartsWith("$Clientes\", [StringComparison]::OrdinalIgnoreCase) -or $Clientes.StartsWith("$Maestro\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "El maestro ($Maestro) no puede ser la carpeta de expedientes del USB ni estar una dentro de la otra."
    }
    if (-not [IO.Directory]::Exists([IO.Path]::GetPathRoot($Maestro))) { throw "No está la unidad del maestro ($([IO.Path]::GetPathRoot($Maestro))). Revisa config.json -> sincronizacion.ruta_maestro." }
    $dirSync = Join-Path $Maestro $script:CarpetaSync
    $null = [IO.Directory]::CreateDirectory((Join-Path $dirSync 'logs'))
    $marca = (Get-Date).ToString('yyyy-MM-dd_HHmmss', $script:Invariante)
    $rutaCandado = Join-Path $dirSync 'sincronizando.lock'
    try { $candado = [IO.File]::Open($rutaCandado, 'OpenOrCreate', 'ReadWrite', 'None') } catch { throw 'Ya hay otra sincronización en curso con este maestro. Espera a que termine.' }
    $rutaLog = Join-Path (Join-Path $dirSync 'logs') "${marca}_sincronizacion.log"
    $log = New-Object IO.StreamWriter($rutaLog, $false, $script:Utf8Bom)
    $log.AutoFlush = $true
    $escribir = { param([string]$Tipo, [string]$Texto) $log.WriteLine(('{0} | {1,-12} | {2}' -f (Get-Date).ToString('HH:mm:ss'), $Tipo, ($Texto -replace '\s*\r?\n\s*', ' '))) }
    $r = [ordered]@{
        Kit = $null; Equipo = $env:COMPUTERNAME; Usb = $Clientes; Maestro = $Maestro; Archivos = 0
        Nuevos = 0; Iguales = 0; Actualizados = 0; MaestroMasNuevo = 0
        Conflictos = New-Object System.Collections.Generic.List[string]; Errores = New-Object System.Collections.Generic.List[string]; EnCurso = @()
        Liberar = [bool]$LiberarUsb; Liberadas = New-Object System.Collections.Generic.List[string]; NoLiberadas = New-Object System.Collections.Generic.List[string]
        BytesLiberados = [long]0; Log = $rutaLog
    }
    try {
        $r.Kit = Get-IdKit -Clientes $Clientes
        $rutaEstado = Join-Path $dirSync "estado_$($r.Kit).tsv"
        $base = Read-EstadoSincronizacion -Ruta $rutaEstado
        & $escribir 'INICIO' "USB $Clientes -> maestro $Maestro (kit $($r.Kit), equipo $env:COMPUTERNAME)"
        & $AlAvance 'Buscando archivos en el USB...'
        $lista = Get-ArchivosExpedientes -Clientes $Clientes
        $r.EnCurso = @($lista.EnCurso)
        foreach ($d in $r.EnCurso) { & $escribir 'OMITIDO' "$d (medición en curso: se copia cuando termine)" }
        $total = @($lista.Archivos).Count
        $r.Archivos = $total
        $anteriores = Join-Path (Join-Path $dirSync 'anteriores') $marca
        $n = 0
        try {
            foreach ($a in $lista.Archivos) {
                $n++
                if ($n -eq 1 -or $n % 25 -eq 0 -or $n -eq $total) { & $AlAvance "Copiando al maestro: $n de $total archivos..." }
                $destino = Join-Path $Maestro $a.Rel
                try {
                    $hu = Get-HashArchivo $a.Ruta
                    if (-not [IO.File]::Exists($destino)) {
                        Copy-ArchivoVerificado -Origen $a.Ruta -Destino $destino -Hash $hu
                        $base[$a.Rel] = $hu; $r.Nuevos++
                        & $escribir 'NUEVO' $a.Rel
                        continue
                    }
                    $hm = Get-HashArchivo $destino
                    if ($hm -eq $hu) { $base[$a.Rel] = $hu; $r.Iguales++; continue }
                    $hb = $base[$a.Rel]
                    if ($hb -and $hb -eq $hm) {
                        Copy-ArchivoVerificado -Origen $a.Ruta -Destino $destino -Hash $hu -Respaldo (Join-Path $anteriores $a.Rel)
                        $base[$a.Rel] = $hu; $r.Actualizados++
                        & $escribir 'ACTUALIZADO' "$($a.Rel) (cambió en el USB; la versión anterior del maestro quedó en $script:CarpetaSync\anteriores\$marca)"
                        continue
                    }
                    if ($hb -and $hb -eq $hu) {
                        $r.MaestroMasNuevo++
                        & $escribir 'MAESTRO' "$($a.Rel) (cambió en el maestro y no en el USB: se deja el del maestro)"
                        continue
                    }
                    # Cambió en los dos lados (o este kit nunca lo había sincronizado): se conservan ambos.
                    $ya = $null
                    foreach ($c in @(Get-CopiasConflicto $destino)) { if ((Get-HashArchivo $c) -eq $hu) { $ya = $c; break } }
                    if ($ya) {
                        & $escribir 'CONFLICTO' "$($a.Rel) (la versión del USB ya estaba guardada como $([IO.Path]::GetFileName($ya)))"
                    } else {
                        $copia = Join-Path ([IO.Path]::GetDirectoryName($destino)) ('{0} (conflicto USB {1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($destino), $marca, [IO.Path]::GetExtension($destino))
                        Copy-ArchivoVerificado -Origen $a.Ruta -Destino $copia -Hash $hu
                        & $escribir 'CONFLICTO' "$($a.Rel): el del maestro no se tocó y el del USB quedó como $([IO.Path]::GetFileName($copia))"
                    }
                    # Desde ahora manda el del maestro: solo vuelve a avisar si el del USB cambia otra vez.
                    $base[$a.Rel] = $hu
                    $r.Conflictos.Add($a.Rel)
                } catch {
                    $r.Errores.Add("$($a.Rel): $($_.Exception.Message)")
                    & $escribir 'ERROR' "$($a.Rel): $($_.Exception.Message)"
                }
            }
        } finally {
            Save-EstadoSincronizacion -Ruta $rutaEstado -Base $base
        }
        if ($LiberarUsb) {
            & $AlAvance 'Verificando por hash antes de liberar el USB...'
            Remove-EntregadasUsb -Clientes $Clientes -Maestro $Maestro -Base $base -Anteriores $anteriores -Resultado $r -Escribir $escribir -AlAvance $AlAvance
        }
        & $escribir 'FIN' ('{0} archivos: {1} nuevos, {2} iguales, {3} actualizados, {4} más nuevos en el maestro, {5} conflictos, {6} errores{7}' -f $total, $r.Nuevos, $r.Iguales, $r.Actualizados, $r.MaestroMasNuevo, $r.Conflictos.Count, $r.Errores.Count, $(if ($LiberarUsb) { "; liberadas del USB: $($r.Liberadas.Count) ($(Format-Tamano $r.BytesLiberados)), no liberadas: $($r.NoLiberadas.Count)" } else { '' }))
    } catch {
        & $escribir 'ERROR' "La sincronización se cortó: $($_.Exception.Message)"
        throw
    } finally {
        $log.Dispose()
        $candado.Dispose()
        try { [IO.File]::Delete($rutaCandado) } catch { Write-Verbose "No se pudo borrar $rutaCandado : $($_.Exception.Message)" }
    }
    # Copia del log en el USB, para saber desde el kit qué se sincronizó y cuándo.
    try {
        $dirLogUsb = Join-Path (Join-Path $Clientes $script:CarpetaSync) 'logs'
        $null = [IO.Directory]::CreateDirectory($dirLogUsb)
        [IO.File]::Copy($rutaLog, (Join-Path $dirLogUsb ([IO.Path]::GetFileName($rutaLog))), $true)
    } catch { $r.Errores.Add("No se pudo copiar el log al USB: $($_.Exception.Message)") }
    foreach ($k in 'Conflictos', 'Errores', 'Liberadas', 'NoLiberadas') { $r[$k] = $r[$k].ToArray() }
    [pscustomobject]$r
}

function Get-ListaExpedientes {
    # Una fila por expediente de la carpeta (USB o maestro), para elegirlo en la interfaz.
    param([Parameter(Mandatory)][string]$Carpeta, [switch]$EsUsb)
    if (-not [IO.Directory]::Exists($Carpeta)) { return }
    foreach ($dir in [IO.Directory]::GetDirectories($Carpeta)) {
        if ([IO.Path]::GetFileName($dir).StartsWith('_') -or -not [IO.File]::Exists((Join-Path $dir 'ficha.json'))) { continue }
        try { $e = Read-Expediente $dir } catch { [pscustomobject]@{ Ruta = $dir; Cliente = '(ficha ilegible)'; Comuna = ''; Equipo = [IO.Path]::GetFileName($dir); Serie = ''; Atenciones = ''; Ultima = '' }; continue }
        $f = $e.Ficha
        $lista = @(Get-ListaAtenciones -Expediente $e)
        $abiertas = @($lista | Where-Object { -not $_['entregado'] }).Count
        $sinCarpeta = @($lista | Where-Object { -not [IO.Directory]::Exists((Join-Path $dir $_['carpeta'])) }).Count
        $texto = "$($lista.Count)"
        if ($abiertas) { $texto += " ($abiertas abierta$(if ($abiertas -gt 1) { 's' }))" }
        if ($sinCarpeta) { $texto += $(if ($EsUsb) { " · $sinCarpeta en el maestro" } else { " · $sinCarpeta sin carpeta" }) }
        [pscustomobject]@{
            Ruta = $dir; Cliente = "$($f['cliente']['nombre'])"; Comuna = "$($f['cliente']['comuna'])"
            Equipo = "$($f['equipo']['fabricante']) $($f['equipo']['modelo'])"; Serie = "$($f['equipo']['serie'])"
            Atenciones = $texto; Ultima = $(if ($lista.Count) { "$($lista[-1]['fecha'])" } else { '' })
        }
    }
}
