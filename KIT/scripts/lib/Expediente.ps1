# Expediente.ps1 - Un expediente por equipo en KIT\clientes\<ID>\: ficha.json, fotos_recepcion\ y una
# carpeta por atención (AAAA-MM-DD_atencion\ con antes\, despues\, archivos\, trabajo.log e informes).
# - <ID> = fabricante_modelo_serie. Con serie genérica: fabricante_modelo_<GUID corto>, y el equipo se
#   reconoce después por el UUID o la serie de la placa guardados en la ficha.
# - Del cliente solo se guarda nombre, contacto y comuna: nada de RUT ni dirección exacta.
# - La ficha se guarda con respaldo (ficha.json.bak) y sin pasar por el enmascarado: el nombre del
#   cliente podría coincidir con el usuario de Windows.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:VersionFicha = 1
$script:MotivosValidos = 'CALOR', 'LENTO', 'ARCHIVOS', 'REVISION'
$script:ItemsChecklist = 'enciende', 'pantalla', 'teclado', 'touchpad', 'usb', 'carga', 'bateria', 'wifi', 'audio', 'camara'
$script:PatronAtencion = '^(\d{4}-\d{2}-\d{2})_atencion(?:_(\d+))?$'
# 12.345.678-9 o 12345678-K: el guion es obligatorio para no confundirlo con un teléfono.
$script:PatronRut = '\b\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\b'

# ---------------------------------------------------------------- ficha.json

function ConvertTo-Diccionario {
    # JSON leído (PSCustomObject) a diccionarios ordenados, para editar la ficha y guardarla igual.
    param([AllowNull()]$Objeto)
    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [System.Management.Automation.PSCustomObject]) {
        $d = [ordered]@{}
        foreach ($p in $Objeto.PSObject.Properties) { $d[$p.Name] = ConvertTo-Diccionario $p.Value }
        return $d
    }
    if ($Objeto -is [System.Collections.IDictionary]) {
        $d = [ordered]@{}
        foreach ($k in $Objeto.Keys) { $d[$k] = ConvertTo-Diccionario $Objeto[$k] }
        return $d
    }
    if ($Objeto -is [System.Collections.IEnumerable] -and $Objeto -isnot [string]) {
        $lista = New-Object System.Collections.Generic.List[object]
        foreach ($i in $Objeto) { $lista.Add((ConvertTo-Diccionario $i)) }
        return , $lista.ToArray()
    }
    $Objeto
}

function Read-Expediente {
    param([Parameter(Mandatory)][string]$Ruta)
    $ficha = ConvertTo-Diccionario (Read-JsonKit (Join-Path $Ruta 'ficha.json'))
    if ([int]$ficha['version'] -gt $script:VersionFicha) { throw "ficha.json es versión $($ficha['version']) y este kit entiende hasta la $script:VersionFicha" }
    # Campos agregados después (p. ej. checklist_fisico): las atenciones antiguas los reciben vacíos.
    foreach ($a in @($ficha['atenciones'] | Where-Object { $_ })) {
        $plantilla = Get-PlantillaAtencion -Carpeta $a['carpeta'] -Fecha $a['fecha']
        foreach ($k in $plantilla.Keys) {
            if (-not $a.Contains($k)) { $a[$k] = $plantilla[$k] }
            elseif ($plantilla[$k] -is [System.Collections.IDictionary] -and $a[$k] -is [System.Collections.IDictionary]) {
                foreach ($k2 in $plantilla[$k].Keys) { if (-not $a[$k].Contains($k2)) { $a[$k][$k2] = $plantilla[$k][$k2] } }
            }
        }
    }
    [pscustomobject]@{ Id = (Split-Path -Leaf $Ruta); Ruta = $Ruta; Ficha = $ficha }
}

function Save-Ficha {
    # Escribe en un temporal y reemplaza: si se corta la luz a mitad, queda la ficha anterior.
    param([Parameter(Mandatory)]$Expediente)
    $Expediente.Ficha['actualizado'] = ConvertTo-TextoFecha (Get-Date)
    $destino = Join-Path $Expediente.Ruta 'ficha.json'
    $temporal = "$destino.tmp"
    [IO.File]::WriteAllText($temporal, ($Expediente.Ficha | ConvertTo-Json -Depth 10), $script:Utf8SinBom)
    if (-not [IO.File]::Exists($destino)) { [IO.File]::Move($temporal, $destino); return }
    try {
        [IO.File]::Replace($temporal, $destino, "$destino.bak")
    } catch {
        # File.Replace no funciona en todos los sistemas de archivos: se hace a mano.
        [IO.File]::Copy($destino, "$destino.bak", $true)
        [IO.File]::Delete($destino)
        [IO.File]::Move($temporal, $destino)
    }
}

function Get-PlantillaAtencion {
    param([Parameter(Mandatory)][string]$Carpeta, [Parameter(Mandatory)][string]$Fecha)
    $checklist = [ordered]@{}
    foreach ($i in $script:ItemsChecklist) { $checklist[$i] = $null }
    [ordered]@{
        carpeta                 = $Carpeta
        fecha                   = $Fecha
        motivos                 = @()
        sintoma                 = $null
        estado_fisico           = $null
        checklist_funcional     = $checklist
        respaldo                = $null
        bitlocker               = [ordered]@{ activo = $null; clave_confirmada = $null }
        consentimiento_archivos = $null
        carpetas_protegidas     = @()
        paquete                 = $null
        precio                  = $null
        materiales              = @()
        condiciones_medicion    = [ordered]@{ antes = $null; despues = $null }
        checklist_fisico        = [ordered]@{ desarme = $null; limpieza = $null; pasta = $null; putty_pads = $null; fotos_disipador_antes = $null; fotos_disipador_despues = $null }
        trabajo_terminado       = $null
        acciones_realizadas     = @()
        entregado               = $null
        garantia_hasta          = $null
        notas                   = $null
        mediciones              = [ordered]@{ antes = $null; despues = $null }
    }
}

# ---------------------------------------------------------------- expediente

function Get-IdExpediente {
    param([Parameter(Mandatory)]$Identidad, [string]$Sufijo)
    $serie = if ($Identidad.Serie) { Get-NombreArchivo $Identidad.Serie 40 } else { $Sufijo }
    '{0}_{1}_{2}' -f (Get-NombreArchivo $Identidad.Fabricante 20), (Get-NombreArchivo $Identidad.Modelo 40), $serie
}

function Get-Expediente {
    # Busca el expediente del equipo: por ID o, si no calza (serie genérica, modelo con otro nombre),
    # por la serie, el UUID o la serie de la placa guardados en las fichas. $null si no existe.
    param([Parameter(Mandatory)]$Identidad)
    $raiz = $script:Ctx.CarpetaClientes
    if (-not [IO.Directory]::Exists($raiz)) { return $null }
    if ($Identidad.Serie) {
        $ruta = Join-Path $raiz (Get-IdExpediente -Identidad $Identidad)
        if ([IO.File]::Exists((Join-Path $ruta 'ficha.json'))) { return Read-Expediente $ruta }
    }
    foreach ($dir in [IO.Directory]::GetDirectories($raiz)) {
        $archivo = Join-Path $dir 'ficha.json'
        if (-not [IO.File]::Exists($archivo)) { continue }
        try { $f = Read-JsonKit $archivo } catch { Write-LogKit -Nivel AVISO -Mensaje "Ficha ilegible en $archivo : $($_.Exception.Message)"; continue }
        $eq = $f.equipo
        if (-not $eq) { continue }
        $ids = $eq.identificadores
        if ($Identidad.Serie) {
            if ($eq.serie -eq $Identidad.Serie) { return Read-Expediente $dir }
        } elseif ($ids) {
            if ($Identidad.Uuid -and $ids.uuid -eq $Identidad.Uuid) { return Read-Expediente $dir }
            if ($Identidad.PlacaSerie -and $ids.placa_serie -eq $Identidad.PlacaSerie) { return Read-Expediente $dir }
        }
    }
    $null
}

function New-Expediente {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Identidad)
    $sufijo = if ($Identidad.Serie) { $null } else { [guid]::NewGuid().ToString('N').Substring(0, 8) }
    $id = Get-IdExpediente -Identidad $Identidad -Sufijo $sufijo
    $ruta = Join-Path $script:Ctx.CarpetaClientes $id
    if (-not $PSCmdlet.ShouldProcess($ruta, 'Crear expediente')) { return }
    $null = [IO.Directory]::CreateDirectory((Join-Path $ruta 'fotos_recepcion'))
    $ahora = ConvertTo-TextoFecha (Get-Date)
    $ficha = [ordered]@{
        version     = $script:VersionFicha
        id          = $id
        creado      = $ahora
        actualizado = $ahora
        cliente     = [ordered]@{ nombre = $null; contacto = $null; comuna = $null }
        equipo      = [ordered]@{
            fabricante        = $Identidad.Fabricante
            modelo            = $Identidad.Modelo
            serie             = $(if ($Identidad.Serie) { $Identidad.Serie } else { $null })
            identificadores   = [ordered]@{
                serie_generica = (-not $Identidad.Serie)
                serie_original = $(if ($Identidad.PSObject.Properties['SerieOriginal']) { $Identidad.SerieOriginal } else { $Identidad.Serie })
                uuid           = $(if ($Identidad.PSObject.Properties['Uuid']) { $Identidad.Uuid } else { $null })
                placa_serie    = $(if ($Identidad.PSObject.Properties['PlacaSerie']) { $Identidad.PlacaSerie } else { $null })
            }
            tipo              = $null
            cpu               = $null
            ram_gb            = $null
            gpu               = @()
            discos            = @()
            windows           = $null
            bios              = $null
            actualizado_desde = $null
        }
        atenciones  = @()
    }
    $exp = [pscustomobject]@{ Id = $id; Ruta = $ruta; Ficha = $ficha }
    Save-Ficha -Expediente $exp
    $exp
}

# ---------------------------------------------------------------- atenciones

function Get-ListaAtenciones {
    # Devuelve las entradas sueltas por el pipeline: quien necesite un arreglo usa @(...).
    param([Parameter(Mandatory)]$Expediente)
    $Expediente.Ficha['atenciones'] | Where-Object { $_ }
}

function Get-EntradaAtencion {
    param([Parameter(Mandatory)]$Expediente, [string]$Carpeta)
    $lista = @(Get-ListaAtenciones -Expediente $Expediente)
    if ($Carpeta) { return ($lista | Where-Object { $_['carpeta'] -eq $Carpeta } | Select-Object -First 1) }
    $lista | Select-Object -Last 1
}

function Test-Medicion {
    # Una medición existe si su carpeta tiene diagnostico.json (una corrida cortada no cuenta).
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)][string]$Momento)
    [IO.File]::Exists((Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) $Momento) 'diagnostico.json'))
}

function New-Atencion {
    # Crea AAAA-MM-DD_atencion (o _2, _3... si ese día ya hubo otra) y su entrada en la ficha.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Expediente, [datetime]$Fecha = (Get-Date))
    $dia = $Fecha.ToString('yyyy-MM-dd', $script:Invariante)
    $nombre = "${dia}_atencion"
    $n = 2
    while ([IO.Directory]::Exists((Join-Path $Expediente.Ruta $nombre)) -or (Get-EntradaAtencion -Expediente $Expediente -Carpeta $nombre)) {
        $nombre = "${dia}_atencion_$n"
        $n++
    }
    if (-not $PSCmdlet.ShouldProcess((Join-Path $Expediente.Ruta $nombre), 'Crear atención')) { return }
    $null = [IO.Directory]::CreateDirectory((Join-Path $Expediente.Ruta $nombre))
    $Expediente.Ficha['atenciones'] = @(Get-ListaAtenciones -Expediente $Expediente) + @(Get-PlantillaAtencion -Carpeta $nombre -Fecha $dia)
    Save-Ficha -Expediente $Expediente
    $nombre
}

function Get-AtencionAbierta {
    # La atención más reciente que no se ha entregado (la que se está trabajando). $null si no hay.
    # El diagnóstico suelto del modo técnico abre una atención aparte, sin motivos: no le quita el
    # lugar a la que se está trabajando ese mismo día.
    param([Parameter(Mandatory)]$Expediente)
    $abiertas = @(Get-ListaAtenciones -Expediente $Expediente | Where-Object { -not $_['entregado'] })
    if ($abiertas.Count -eq 0) { return $null }
    $ultima = $abiertas[$abiertas.Count - 1]
    if (@($ultima['motivos'] | Where-Object { $_ }).Count -eq 0) {
        $delDia = @($abiertas | Where-Object { $_['fecha'] -eq $ultima['fecha'] -and @($_['motivos'] | Where-Object { $_ }).Count -gt 0 } | Select-Object -Last 1)
        if ($delDia.Count -gt 0) { return $delDia[0]['carpeta'] }
    }
    $ultima['carpeta']
}

function Resolve-Atencion {
    # En qué atención escribe el diagnóstico:
    # - antes: la de hoy si existe, no está entregada y no tiene "después"; si no, una nueva.
    # - despues: la más reciente con "antes" que no esté entregada. Sin "antes" no hay "después" ($null).
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][ValidateSet('antes', 'despues')][string]$Momento,
        [switch]$Nueva
    )
    $lista = @(Get-ListaAtenciones -Expediente $Expediente)
    if ($Momento -eq 'antes') {
        if (-not $Nueva) {
            $hoy = (Get-Date).ToString('yyyy-MM-dd', $script:Invariante)
            $deHoy = $lista | Where-Object { $_['fecha'] -eq $hoy -and -not $_['entregado'] } | Select-Object -Last 1
            if ($deHoy -and -not (Test-Medicion -Expediente $Expediente -Atencion $deHoy['carpeta'] -Momento 'despues')) { return $deHoy['carpeta'] }
        }
        return New-Atencion -Expediente $Expediente
    }
    $candidata = $lista | Where-Object { -not $_['entregado'] -and (Test-Medicion -Expediente $Expediente -Atencion $_['carpeta'] -Momento 'antes') } | Select-Object -Last 1
    if ($candidata) { $candidata['carpeta'] } else { $null }
}

function Backup-Medicion {
    # Si ya hay una carpeta <momento>, la renombra (nunca se borra): <momento>_reemplazado_HHMMSS, o
    # <momento>_incompleto_HHMMSS si no tiene diagnostico.json. Devuelve el nombre nuevo o $null.
    param([Parameter(Mandatory)][string]$CarpetaAtencion, [Parameter(Mandatory)][string]$Momento, [string]$Hora)
    $ruta = Join-Path $CarpetaAtencion $Momento
    if (-not [IO.Directory]::Exists($ruta)) { return $null }
    if (-not $Hora) { $Hora = (Get-Date).ToString('HHmmss', $script:Invariante) }
    $tipo = if ([IO.File]::Exists((Join-Path $ruta 'diagnostico.json'))) { 'reemplazado' } else { 'incompleto' }
    $nombre = '{0}_{1}_{2}' -f $Momento, $tipo, $Hora
    $n = 2
    while ([IO.Directory]::Exists((Join-Path $CarpetaAtencion $nombre))) { $nombre = '{0}_{1}_{2}_{3}' -f $Momento, $tipo, $Hora, $n; $n++ }
    [IO.Directory]::Move($ruta, (Join-Path $CarpetaAtencion $nombre))
    $nombre
}

function Initialize-Medicion {
    # La medición se escribe en <momento>_en_curso y recién al terminar bien pasa a <momento>
    # (Complete-Medicion). Si se corta a mitad (luz, ventana cerrada), la medición anterior queda
    # intacta y lo cortado pasa a <momento>_incompleto_HHMMSS en la corrida siguiente.
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)][string]$Momento)
    $carpetaAtencion = Join-Path $Expediente.Ruta $Atencion
    $enCurso = Join-Path $carpetaAtencion "${Momento}_en_curso"
    if ([IO.Directory]::Exists($enCurso)) {
        [IO.Directory]::Move($enCurso, (Join-Path $carpetaAtencion ('{0}_incompleto_{1}' -f $Momento, (Get-Date).ToString('HHmmss', $script:Invariante))))
    }
    $null = [IO.Directory]::CreateDirectory((Join-Path $enCurso 'csv'))
    $enCurso
}

function Complete-Medicion {
    # Pasa <momento>_en_curso a <momento>; la medición anterior queda respaldada. Devuelve el nombre
    # del respaldo o $null si no había anterior.
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)][string]$Momento)
    $carpetaAtencion = Join-Path $Expediente.Ruta $Atencion
    $reemplazada = Backup-Medicion -CarpetaAtencion $carpetaAtencion -Momento $Momento
    $nueva = Join-Path $carpetaAtencion $Momento
    [IO.Directory]::Move((Join-Path $carpetaAtencion "${Momento}_en_curso"), $nueva)
    # Los sensores importados (CALOR) no los genera el diagnóstico: pasan a la medición nueva.
    if ($reemplazada) {
        foreach ($a in 'sensores.csv', 'sensores_resumen.json') {
            $origen = Join-Path (Join-Path $carpetaAtencion $reemplazada) $a
            if ([IO.File]::Exists($origen) -and -not [IO.File]::Exists((Join-Path $nueva $a))) { [IO.File]::Copy($origen, (Join-Path $nueva $a)) }
        }
    }
    $reemplazada
}

function Initialize-Expediente {
    # Lo que hace el diagnóstico al partir: migra carpetas de la fase 0, abre o crea el expediente,
    # elige la atención y prepara la carpeta de la medición. Con SinAntes = $true no se creó nada.
    param(
        [Parameter(Mandatory)]$Identidad,
        [ValidateSet('antes', 'despues')][string]$Momento = 'antes',
        [switch]$NuevaAtencion,
        [string]$Atencion
    )
    Move-CarpetasFase0
    $exp = Get-Expediente -Identidad $Identidad
    $nuevo = $false
    if (-not $exp) {
        if ($Momento -eq 'despues') { return [pscustomobject]@{ SinAntes = $true } }
        $exp = New-Expediente -Identidad $Identidad
        $nuevo = $true
    } else {
        # Expedientes migrados de la fase 0 no traen UUID ni serie de placa: se completan si faltan.
        $ids = $exp.Ficha['equipo']['identificadores']
        $cambio = $false
        foreach ($par in @{ uuid = 'Uuid'; placa_serie = 'PlacaSerie' }.GetEnumerator()) {
            $valor = if ($Identidad.PSObject.Properties[$par.Value]) { $Identidad.($par.Value) } else { $null }
            if ($valor -and -not $ids[$par.Key]) { $ids[$par.Key] = $valor; $cambio = $true }
        }
        if ($cambio) { Save-Ficha -Expediente $exp }
    }
    if ($Atencion -and (Get-EntradaAtencion -Expediente $exp -Carpeta $Atencion)) {
        # Atención indicada por la GUI: se respeta, pero sin "antes" no hay "después".
        if ($Momento -eq 'despues' -and -not (Test-Medicion -Expediente $exp -Atencion $Atencion -Momento 'antes')) { return [pscustomobject]@{ SinAntes = $true } }
        $atencion = $Atencion
    } else {
        $atencion = Resolve-Atencion -Expediente $exp -Momento $Momento -Nueva:$NuevaAtencion
    }
    if (-not $atencion) { return [pscustomobject]@{ SinAntes = $true } }
    $anterior = Join-Path (Join-Path (Join-Path $exp.Ruta $atencion) $Momento) 'diagnostico.json'
    $script:Ctx.CarpetaCliente = Initialize-Medicion -Expediente $exp -Atencion $atencion -Momento $Momento
    $script:Ctx.Expediente = [pscustomobject]@{
        Id = $exp.Id; Ruta = $exp.Ruta; Atencion = $atencion; Momento = $Momento; Nuevo = $nuevo; Objeto = $exp
        Anterior = $(if ([IO.File]::Exists($anterior)) { $anterior } else { $null }); Reemplazada = $null
    }
    Write-LogPendiente
    $script:Ctx.Expediente
}

# ---------------------------------------------------------------- después de medir

function Write-TrabajoLog {
    # trabajo.log de la atención: una línea por hecho (mediciones, acciones y cómo deshacerlas).
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)][string]$Texto)
    $ruta = Join-Path (Join-Path $Expediente.Ruta $Atencion) 'trabajo.log'
    $linea = '{0} | {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante), (Protect-Texto $Texto)
    [IO.File]::AppendAllText($ruta, $linea + "`r`n", $script:Utf8Bom)
}

function Update-FichaDesdeDiagnostico {
    # Completa ficha.equipo con lo medido y anota la medición en la atención. BitLocker se marca
    # solo si el técnico no lo había llenado.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][string]$Atencion,
        [Parameter(Mandatory)][string]$Momento,
        [Parameter(Mandatory)]$Datos,
        [string]$Generado,
        [bool]$Admin,
        [AllowNull()][object[]]$Alertas
    )
    $eq = $Expediente.Ficha['equipo']
    if ($Datos.equipo) {
        $eq['tipo'] = $Datos.equipo.Tipo
        $eq['bios'] = "$($Datos.equipo.BiosVersion) ($($Datos.equipo.BiosFecha))"
    }
    if ($Datos.hardware) {
        $cpu = @($Datos.hardware.Cpu | Where-Object { $_ }) | Select-Object -First 1
        if ($cpu) { $eq['cpu'] = $cpu.Nombre }
        if ($Datos.hardware.Ram) { $eq['ram_gb'] = $Datos.hardware.Ram.TotalGB }
        $eq['gpu'] = @($Datos.hardware.Gpu | Where-Object { $_ } | ForEach-Object { $_.Nombre })
        $eq['discos'] = @($Datos.hardware.Discos | Where-Object { $_ } | ForEach-Object { [ordered]@{ modelo = $_.Modelo; tipo = $_.Tipo; tamano_gb = $_.TamanoGB } })
    }
    if ($Datos.windows) { $eq['windows'] = "$($Datos.windows.Nombre) $($Datos.windows.Version) (build $($Datos.windows.BuildCompleto))" }
    $eq['actualizado_desde'] = "$Atencion/$Momento"

    $a = Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion
    if (-not $a) { throw "La ficha no tiene la atención $Atencion" }
    $cuenta = @{ CRITICO = 0; AVISO = 0; INFO = 0 }
    foreach ($x in @($Alertas | Where-Object { $_ })) { $cuenta["$($x.Severidad)"]++ }
    $a['mediciones'][$Momento] = [ordered]@{ fecha = $Generado; admin = $Admin; criticas = $cuenta.CRITICO; avisos = $cuenta.AVISO; info = $cuenta.INFO }
    $bl = @($Datos.seguridad.BitLocker | Where-Object { $_ })
    if ($null -eq $a['bitlocker']['activo'] -and $bl.Count -gt 0) {
        $a['bitlocker']['activo'] = (@($bl | Where-Object { $_.Protegido }).Count -gt 0)
    }
    if ($PSCmdlet.ShouldProcess((Join-Path $Expediente.Ruta 'ficha.json'), 'Actualizar equipo y medición')) { Save-Ficha -Expediente $Expediente }
}

# ---------------------------------------------------------------- ficha: validación

function ConvertTo-ValorFicha {
    # Valida y normaliza un valor. Si no sirve, lanza un error con un mensaje para el técnico.
    param([Parameter(Mandatory)][string]$Campo, [AllowNull()]$Valor)
    $esLista = $Campo -match '^(motivos|carpetas_protegidas|materiales|acciones_realizadas)$'
    if ($null -eq $Valor -or ($Valor -is [string] -and -not $Valor.Trim())) {
        if ($esLista) { return , @() }
        return $null
    }
    $texto = {
        param($v, [int]$max)
        $t = "$v".Trim()
        if ($t.Length -gt $max) { throw "máximo $max caracteres" }
        if ($t -match $script:PatronRut) { throw 'parece un RUT, y la ficha no guarda RUT' }
        $t
    }
    $fecha = {
        param($v)
        if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd', $script:Invariante) }
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact("$v".Trim(), [string[]]@('yyyy-MM-dd', 'dd-MM-yyyy', 'd-M-yyyy', 'dd/MM/yyyy', 'd/M/yyyy'), $script:Invariante, [Globalization.DateTimeStyles]::None, [ref]$d)) {
            return $d.ToString('yyyy-MM-dd', $script:Invariante)
        }
        throw 'fecha no válida (usa AAAA-MM-DD o DD-MM-AAAA)'
    }
    $siNo = {
        param($v)
        if ($v -is [bool]) { return $v }
        switch -Regex ("$v".Trim()) {
            '^(?i)(s|si|sí|true|1)$' { return $true }
            '^(?i)(n|no|false|0)$' { return $false }
        }
        throw 'responde sí o no'
    }
    $opcion = {
        param($v, [hashtable]$mapa, [string]$ayuda)
        $k = "$v".Trim().ToLowerInvariant() -replace '\s+', '_'
        if ($mapa.ContainsKey($k)) { return $mapa[$k] }
        throw "opciones: $ayuda"
    }
    switch -Regex ($Campo) {
        '^cliente\.nombre$' { return (& $texto $Valor 80) }
        '^cliente\.comuna$' {
            $t = & $texto $Valor 40
            if ($t -match '\d') { throw 'solo la comuna, sin dirección ni números' }
            return $t
        }
        '^cliente\.contacto$' {
            $t = "$Valor".Trim()
            if ($t -match '^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$') { return $t.ToLowerInvariant() }
            $n = $t -replace '[\s\-().]', ''
            if ($n -match '^(\+?56)?(9\d{8})$') { return "+56$($Matches[2])" }
            if ($n -match '^(\+?56)(2\d{8})$') { return "+56$($Matches[2])" }
            if ($n -match '^\+\d{8,15}$') { return $n }
            throw 'WhatsApp (+56 9 1234 5678) o correo'
        }
        '^(fecha|entregado|garantia_hasta)$' { return (& $fecha $Valor) }
        '^motivos$' {
            $lista = @($Valor | ForEach-Object { "$_" -split '[,;\s]+' } | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpperInvariant() -replace 'REVISIÓN', 'REVISION' })
            $malos = @($lista | Where-Object { $_ -notin $script:MotivosValidos })
            if ($malos.Count -gt 0) { throw "motivo no válido: $($malos -join ', ') (usa $($script:MotivosValidos -join ', '))" }
            return , @($lista | Select-Object -Unique)
        }
        '^(sintoma|estado_fisico)$' { return (& $texto $Valor 500) }
        '^notas$' { return (& $texto $Valor 2000) }
        '^paquete$' { return (& $texto $Valor 80) }
        '^precio$' {
            $t = "$Valor" -replace '[\s.$]', ''
            if ($t -notmatch '^\d{1,9}$') { throw 'en pesos, solo números (ej: 45000)' }
            return [int]$t
        }
        '^checklist_funcional\.(\w+)$' {
            if ($Matches[1] -notin $script:ItemsChecklist) { throw "ítem desconocido (usa $($script:ItemsChecklist -join ', '))" }
            return (& $opcion $Valor @{ ok = 'ok'; o = 'ok'; falla = 'falla'; f = 'falla'; no_aplica = 'no_aplica'; na = 'no_aplica'; 'n/a' = 'no_aplica'; n = 'no_aplica' } 'ok, falla o no_aplica')
        }
        '^respaldo$' { return (& $opcion $Valor @{ si = 'si'; 'sí' = 'si'; s = 'si'; no = 'no'; n = 'no'; no_sabe = 'no_sabe'; '?' = 'no_sabe' } 'si, no o no_sabe') }
        '^bitlocker\.(activo|clave_confirmada)$' { return (& $siNo $Valor) }
        '^checklist_fisico\.(desarme|limpieza|fotos_disipador_antes|fotos_disipador_despues)$' { return (& $siNo $Valor) }
        '^trabajo_terminado$' { return (& $siNo $Valor) }
        '^checklist_fisico\.(pasta|putty_pads)$' { return (& $texto $Valor 80) }
        '^consentimiento_archivos$' {
            return (& $opcion $Valor @{ solo_leer = 'solo_leer'; leer = 'solo_leer'; l = 'solo_leer'; mover = 'mover'; m = 'mover'; borrar_aprobado = 'borrar_aprobado'; b = 'borrar_aprobado' } 'solo_leer, mover o borrar_aprobado')
        }
        '^(carpetas_protegidas|materiales|acciones_realizadas)$' {
            $lista = @($Valor | ForEach-Object { if ($_ -is [string]) { $_ -split ';' } else { $_ } } | Where-Object { $_ -and "$_".Trim() } | ForEach-Object {
                    if ($_ -is [string]) { & $texto $_ 260 } else { ConvertTo-Diccionario $_ }
                })
            return , $lista
        }
        '^condiciones_medicion\.(antes|despues)$' {
            if ($Valor -is [System.Collections.IDictionary] -or $Valor -is [System.Management.Automation.PSCustomObject]) { return (ConvertTo-Diccionario $Valor) }
            throw 'se espera un objeto con las condiciones'
        }
    }
    throw 'campo desconocido'
}

function Set-Ficha {
    # Cambia campos de la ficha. -Valores usa rutas: 'cliente.nombre', y para la atención 'motivos',
    # 'checklist_funcional.teclado', 'bitlocker.clave_confirmada'... Si un valor no sirve, no se guarda
    # nada y el error dice cuál y por qué. -Atencion: carpeta de la atención (por defecto, la abierta).
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Valores,
        [string]$Atencion
    )
    $entrada = $null
    if (@($Valores.Keys | Where-Object { $_ -notlike 'cliente.*' }).Count -gt 0) {
        if (-not $Atencion) { $Atencion = Get-AtencionAbierta -Expediente $Expediente }
        if ($Atencion) { $entrada = Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion }
    }
    $errores = New-Object System.Collections.Generic.List[string]
    $cambios = New-Object System.Collections.Generic.List[object]
    foreach ($campo in @($Valores.Keys)) {
        try {
            $valor = ConvertTo-ValorFicha -Campo $campo -Valor $Valores[$campo]
            if ($campo -like 'cliente.*') {
                $destino = $Expediente.Ficha['cliente']
                $clave = $campo.Substring(8)
            } else {
                if (-not $entrada) { throw 'no hay una atención abierta (corre el diagnóstico ANTES o crea una)' }
                if ($campo -match '^(\w+)\.(\w+)$') { $destino = $entrada[$Matches[1]]; $clave = $Matches[2] } else { $destino = $entrada; $clave = $campo }
            }
            $cambios.Add([pscustomobject]@{ Destino = $destino; Clave = $clave; Valor = $valor })
        } catch {
            $errores.Add(('{0}: {1}' -f $campo, $_.Exception.Message))
        }
    }
    if ($errores.Count -gt 0) { throw ("No se guardó la ficha:`n- " + ($errores -join "`n- ")) }
    if (-not $PSCmdlet.ShouldProcess((Join-Path $Expediente.Ruta 'ficha.json'), ('Cambiar ' + (@($Valores.Keys) -join ', ')))) { return }
    foreach ($c in $cambios) { $c.Destino[$c.Clave] = $c.Valor }
    if ($entrada -and $Valores.Contains('entregado') -and $entrada['entregado'] -and -not $Valores.Contains('garantia_hasta')) {
        # Garantía por defecto: fecha de entrega + N días (config.json: expediente.garantia_dias).
        $dias = 30
        if ($script:Ctx.Config.expediente -and $script:Ctx.Config.expediente.garantia_dias) { $dias = [int]$script:Ctx.Config.expediente.garantia_dias }
        $entrada['garantia_hasta'] = [datetime]::ParseExact($entrada['entregado'], 'yyyy-MM-dd', $script:Invariante).AddDays($dias).ToString('yyyy-MM-dd', $script:Invariante)
    }
    Save-Ficha -Expediente $Expediente
}

function Test-FichaCompleta {
    # Lo obligatorio para generar informes. Devuelve lo que falta (nada = completa), cada ítem con
    # Campo (para la GUI) y Texto (para mostrar). Para contar: @(Test-FichaCompleta ...).Count
    param([Parameter(Mandatory)]$Expediente, [string]$Atencion)
    $faltan = New-Object System.Collections.Generic.List[object]
    $agregar = { param($c, $t) $faltan.Add([pscustomobject]@{ Campo = $c; Texto = $t }) }
    $cl = $Expediente.Ficha['cliente']
    if (-not $cl['nombre']) { & $agregar 'cliente.nombre' 'Nombre del cliente' }
    if (-not $cl['contacto']) { & $agregar 'cliente.contacto' 'Contacto del cliente (WhatsApp o correo)' }
    $tec = $script:Ctx.Config.tecnico
    if (-not $tec -or -not $tec.nombre) { & $agregar 'tecnico.nombre' 'Nombre del técnico (config_local.json o config.json: tecnico.nombre)' }
    if (-not $tec -or -not $tec.contacto) { & $agregar 'tecnico.contacto' 'Contacto del técnico (config_local.json: tecnico.contacto)' }
    if (-not $Atencion) { $Atencion = Get-AtencionAbierta -Expediente $Expediente }
    $a = if ($Atencion) { Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion } else { $null }
    if (-not $a) {
        & $agregar 'atencion' 'Una atención abierta'
        return $faltan.ToArray()
    }
    if (-not $a['fecha']) { & $agregar 'fecha' 'Fecha de la atención' }
    $motivos = @($a['motivos'] | Where-Object { $_ })
    if ($motivos.Count -eq 0) { & $agregar 'motivos' 'Motivo de consulta (CALOR, LENTO, ARCHIVOS o REVISION)' }
    if (-not $a['sintoma']) { & $agregar 'sintoma' 'Síntoma, en palabras del cliente' }
    if (-not $a['paquete']) { & $agregar 'paquete' 'Paquete' }
    if ($null -eq $a['precio']) { & $agregar 'precio' 'Precio' }
    if ($motivos -contains 'ARCHIVOS') {
        if (-not $a['consentimiento_archivos']) { & $agregar 'consentimiento_archivos' 'Consentimiento para archivos (solo_leer, mover o borrar_aprobado)' }
        if (@($a['carpetas_protegidas'] | Where-Object { $_ }).Count -eq 0) { & $agregar 'carpetas_protegidas' 'Carpetas protegidas (las que no se tocan)' }
    }
    $faltan.ToArray()
}

# ---------------------------------------------------------------- tarjetas para informes

function Get-TarjetaMetrica {
    # Una tarjeta antes -> después para el informe. Mejor = 'menor' o 'mayor'.
    param([string]$Titulo, $Antes, $Despues, [string]$Unidad, [ValidateSet('menor', 'mayor', 'si_no')][string]$Mejor)
    $mejoro = $null
    if ($null -ne $Antes -and $null -ne $Despues) {
        $mejoro = switch ($Mejor) {
            'menor' { [double]$Despues -lt [double]$Antes }
            'mayor' { [double]$Despues -gt [double]$Antes }
            # Si no cambió (No -> No o Sí -> Sí) no mejoró ni empeoró: queda en $null, sin color.
            'si_no' { if ($Antes -eq $Despues) { $null } else { ($Antes -eq $true) -and ($Despues -eq $false) } }
        }
        if ($Mejor -ne 'si_no' -and [double]$Despues -eq [double]$Antes) { $mejoro = $null }
    }
    [pscustomobject][ordered]@{ Titulo = $Titulo; Antes = $Antes; Despues = $Despues; Unidad = $Unidad; Mejor = $Mejor; Mejoro = $mejoro }
}

# ---------------------------------------------------------------- migración desde la fase 0

function Move-CarpetasFase0 {
    # La fase 0 guardaba cada corrida en clientes\AAAA-MM-DD_HHMM_<fab>_<modelo>_<serie4>. Se mueven al
    # expediente del equipo: la última del día queda como antes\ de la atención de esa fecha y las
    # anteriores como antes_reemplazado_HHMM00, igual que al repetir una medición.
    $raiz = $script:Ctx.CarpetaClientes
    if (-not [IO.Directory]::Exists($raiz)) { return }
    $viejas = foreach ($dir in [IO.Directory]::GetDirectories($raiz)) {
        $m = [regex]::Match((Split-Path -Leaf $dir), '^(\d{4}-\d{2}-\d{2})_(\d{4})_')
        if (-not $m.Success) { continue }
        $json = Join-Path $dir 'diagnostico.json'
        if (-not [IO.File]::Exists($json)) { continue }
        try { $doc = Read-JsonKit $json } catch { Write-LogKit -Nivel AVISO -Mensaje "No se pudo leer $json para migrarlo: $($_.Exception.Message)"; continue }
        if (-not $doc.datos -or -not $doc.datos.equipo) { continue }
        [pscustomobject]@{ Ruta = $dir; Nombre = (Split-Path -Leaf $dir); Fecha = $m.Groups[1].Value; Hora = $m.Groups[2].Value; Doc = $doc }
    }
    foreach ($grupo in @($viejas | Group-Object { '{0}|{1}|{2}|{3}' -f $_.Doc.datos.equipo.Fabricante, $_.Doc.datos.equipo.Modelo, $_.Doc.datos.equipo.Serie, $_.Fecha })) {
        $items = @($grupo.Group | Sort-Object Hora)
        $eq = $items[0].Doc.datos.equipo
        $identidad = [pscustomobject]@{ Fabricante = "$($eq.Fabricante)"; Modelo = "$($eq.Modelo)"; Serie = "$($eq.Serie)"; SerieOriginal = "$($eq.Serie)"; Uuid = $null; PlacaSerie = $null }
        $exp = Get-Expediente -Identidad $identidad
        if (-not $exp) { $exp = New-Expediente -Identidad $identidad }
        $fecha = $items[0].Fecha
        $at = Get-ListaAtenciones -Expediente $exp | Where-Object { $_['fecha'] -eq $fecha -and -not (Test-Medicion -Expediente $exp -Atencion $_['carpeta'] -Momento 'despues') } | Select-Object -Last 1
        $atencion = if ($at) { $at['carpeta'] } else { New-Atencion -Expediente $exp -Fecha ([datetime]::ParseExact($fecha, 'yyyy-MM-dd', $script:Invariante)) }
        $carpetaAt = Join-Path $exp.Ruta $atencion
        for ($i = 0; $i -lt $items.Count; $i++) {
            $ultima = ($i -eq $items.Count - 1)
            $nombre = if ($ultima) { 'antes' } else { 'antes_reemplazado_{0}00' -f $items[$i].Hora }
            if ($ultima) { $null = Backup-Medicion -CarpetaAtencion $carpetaAt -Momento 'antes' }
            $destino = Join-Path $carpetaAt $nombre
            $n = 2
            while ([IO.Directory]::Exists($destino)) { $destino = Join-Path $carpetaAt "${nombre}_$n"; $n++ }
            [IO.Directory]::Move($items[$i].Ruta, $destino)
            Write-LogKit -Mensaje "Migrada carpeta de la fase 0: $($items[$i].Nombre) -> $($exp.Id)\$atencion\$(Split-Path -Leaf $destino)"
        }
        $doc = $items[-1].Doc
        Update-FichaDesdeDiagnostico -Expediente $exp -Atencion $atencion -Momento 'antes' -Datos $doc.datos -Generado "$($doc.kit.generado)" -Admin ([bool]$doc.kit.admin.Elevado) -Alertas @($doc.alertas)
        Write-TrabajoLog -Expediente $exp -Atencion $atencion -Texto ('ANTES | migrado desde la fase 0 ({0} corridas: {1})' -f $items.Count, (@($items | ForEach-Object { $_.Nombre }) -join ', '))
    }
}
