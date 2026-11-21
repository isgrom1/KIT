# DatosPersonales.ps1 - Ley 21.719 (fase J): consentimiento, retención y derechos del cliente.
# - Consentimiento: el texto vive en config\consentimiento.json (con versión). La ficha guarda la fecha
#   en que el cliente aceptó (cliente.consentimiento), la versión del texto y si quiere el aviso anual.
# - Retención: config.json -> datos_personales.retencion_meses (18) desde la última atención. Pasado
#   ese plazo, Clear-DatosCliente deja el expediente sin datos que identifiquen al cliente.
# - Olvidar: Remove-ExpedienteCliente borra el expediente completo y anota su huella en _olvidados.txt
#   (la sincronización no lo vuelve a copiar). Entregar: Export-DatosCliente arma un ZIP para el cliente.
# - Registro: <clientes>\_registro_privacidad.csv con fecha, acción y la huella del expediente (sin la
#   serie ni el nombre).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:ArchivoOlvidados = '_olvidados.txt'
$script:ArchivoRegistroPrivacidad = '_registro_privacidad.csv'

function Get-Consentimiento {
    # El texto aprobado (config\consentimiento.json). $null si no está.
    param([string]$RaizScripts = $script:Ctx.RaizScripts)
    $ruta = Join-Path $RaizScripts 'config\consentimiento.json'
    if (-not [IO.File]::Exists($ruta)) { return $null }
    Read-JsonKit $ruta
}

function Get-MesesRetencion {
    $m = 18
    $c = $script:Ctx.Config
    if ($c -and $c.datos_personales -and $c.datos_personales.retencion_meses) { $m = [int]$c.datos_personales.retencion_meses }
    $m
}

function Get-HuellaExpediente {
    # 12 caracteres del SHA-256 del ID: identifica el expediente en los registros sin guardar la serie.
    param([Parameter(Mandatory)][string]$Id)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Id.ToUpperInvariant())) } finally { $sha.Dispose() }
    (-join ($h[0..5] | ForEach-Object { $_.ToString('x2') }))
}

function Add-RegistroPrivacidad {
    param([Parameter(Mandatory)][string]$Clientes, [Parameter(Mandatory)][string]$Accion, [Parameter(Mandatory)][string]$Id, [string]$Detalle)
    $ruta = Join-Path $Clientes $script:ArchivoRegistroPrivacidad
    $null = [IO.Directory]::CreateDirectory($Clientes)
    $nuevo = -not [IO.File]::Exists($ruta)
    $linea = '{0};{1};{2};{3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $script:Invariante), $Accion, (Get-HuellaExpediente $Id), ($Detalle -replace '[;\r\n]', ' ')
    $texto = $(if ($nuevo) { "fecha;accion;huella_expediente;detalle`r`n" } else { '' }) + $linea + "`r`n"
    [IO.File]::AppendAllText($ruta, $texto, $script:Utf8Bom)
}

function Get-HuellasOlvidadas {
    # Huellas de los expedientes olvidados en una o más carpetas de expedientes.
    param([string[]]$Carpetas)
    $h = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in @($Carpetas | Where-Object { $_ })) {
        $ruta = Join-Path $c $script:ArchivoOlvidados
        if (-not [IO.File]::Exists($ruta)) { continue }
        foreach ($l in [IO.File]::ReadAllLines($ruta)) { $t = $l.Trim(); if ($t -match '^[0-9a-f]{12}$') { [void]$h.Add($t) } }
    }
    , $h
}

function Get-FechaUltimaAtencion {
    # La fecha más reciente entre las atenciones (fecha o entrega) y la creación del expediente.
    param([Parameter(Mandatory)]$Expediente)
    $fechas = New-Object System.Collections.Generic.List[datetime]
    $d = [datetime]::MinValue
    foreach ($a in @(Get-ListaAtenciones -Expediente $Expediente)) {
        foreach ($k in 'fecha', 'entregado') {
            if ($a[$k] -and [datetime]::TryParseExact("$($a[$k])", 'yyyy-MM-dd', $script:Invariante, [Globalization.DateTimeStyles]::None, [ref]$d)) { $fechas.Add($d) }
        }
    }
    $creado = "$($Expediente.Ficha['creado'])"
    if ($creado.Length -ge 10 -and [datetime]::TryParseExact($creado.Substring(0, 10), 'yyyy-MM-dd', $script:Invariante, [Globalization.DateTimeStyles]::None, [ref]$d)) { $fechas.Add($d) }
    if (-not $fechas.Count) { return $null }
    ($fechas | Sort-Object -Descending | Select-Object -First 1)
}

function Test-ClienteConDatos {
    param([Parameter(Mandatory)]$Expediente)
    $c = $Expediente.Ficha['cliente']
    [bool]($c -and ($c['nombre'] -or $c['contacto'] -or $c['comuna']))
}

function Get-RevisionDatosPersonales {
    # Una fila por expediente: cuándo fue la última atención, si venció la retención, si tiene
    # consentimiento y si quiere el aviso anual. -Hoy es para las pruebas.
    param([Parameter(Mandatory)][string]$Clientes, [datetime]$Hoy = (Get-Date), [int]$Meses = (Get-MesesRetencion))
    if (-not [IO.Directory]::Exists($Clientes)) { return }
    $limite = $Hoy.Date.AddMonths(-$Meses)
    foreach ($dir in [IO.Directory]::GetDirectories($Clientes)) {
        if ([IO.Path]::GetFileName($dir).StartsWith('_') -or -not [IO.File]::Exists((Join-Path $dir 'ficha.json'))) { continue }
        try { $e = Read-Expediente $dir } catch { continue }
        $c = $e.Ficha['cliente']
        $ultima = Get-FechaUltimaAtencion -Expediente $e
        $abiertas = @(Get-ListaAtenciones -Expediente $e | Where-Object { -not $_['entregado'] }).Count
        [pscustomobject]@{
            Id              = $e.Id
            Ruta            = $dir
            Cliente         = "$($c['nombre'])"
            ConDatos        = (Test-ClienteConDatos -Expediente $e)
            Anonimizado     = [bool]$c['anonimizado']
            Ultima          = $ultima
            Vencido         = [bool]($ultima -and $ultima -lt $limite -and $abiertas -eq 0)
            Abiertas        = $abiertas
            Consentimiento  = "$($c['consentimiento'])"
            AvisoAnual      = [bool]$c['aviso_anual']
        }
    }
}

function Find-ExpedienteCliente {
    # Busca por ID exacto, parte del ID (serie) o nombre del cliente. Devuelve las rutas que calzan.
    param([Parameter(Mandatory)][string]$Clientes, [Parameter(Mandatory)][string]$Texto)
    $t = $Texto.Trim()
    if (-not $t -or -not [IO.Directory]::Exists($Clientes)) { return }
    foreach ($dir in [IO.Directory]::GetDirectories($Clientes)) {
        $id = [IO.Path]::GetFileName($dir)
        if ($id.StartsWith('_') -or -not [IO.File]::Exists((Join-Path $dir 'ficha.json'))) { continue }
        if ($id -ieq $t -or $id.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $dir; continue }
        try { $e = Read-Expediente $dir } catch { continue }
        if ("$($e.Ficha['cliente']['nombre'])".IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $dir }
    }
}

function Clear-DatosCliente {
    # Deja el expediente sin datos que identifiquen al cliente: borra nombre, contacto, comuna y
    # consentimiento de la ficha, las fotos de recepción y los informes y mensajes (llevan el nombre).
    # Quedan los datos técnicos del equipo y las mediciones, que no identifican a la persona.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$Ruta, [string]$Motivo = 'retencion')
    $e = Read-Expediente $Ruta
    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Quitar los datos del cliente')) { return }
    $borrados = 0
    $fotos = Join-Path $Ruta 'fotos_recepcion'
    if ([IO.Directory]::Exists($fotos)) { foreach ($f in [IO.Directory]::GetFiles($fotos)) { [IO.File]::Delete($f); $borrados++ } }
    foreach ($a in @(Get-ListaAtenciones -Expediente $e)) {
        $dir = Join-Path $Ruta $a['carpeta']
        if (-not [IO.Directory]::Exists($dir)) { continue }
        foreach ($f in [IO.Directory]::GetFiles($dir, '*', 'AllDirectories')) {
            if ([IO.Path]::GetExtension($f) -match '^\.(html?|pdf|txt|png|jpe?g)$') { [IO.File]::Delete($f); $borrados++ }
        }
        foreach ($k in 'sintoma', 'notas', 'estado_fisico') { $a[$k] = $null }
        $a['carpetas_protegidas'] = @()
    }
    $c = $e.Ficha['cliente']
    foreach ($k in 'nombre', 'contacto', 'comuna', 'consentimiento', 'consentimiento_version', 'aviso_anual') { $c[$k] = $null }
    $c['anonimizado'] = (Get-Date).ToString('yyyy-MM-dd', $script:Invariante)
    Save-Ficha -Expediente $e
    $bak = Join-Path $Ruta 'ficha.json.bak'
    if ([IO.File]::Exists($bak)) { [IO.File]::Delete($bak) }   # el respaldo todavía tenía el nombre
    Add-RegistroPrivacidad -Clientes (Split-Path -Parent $Ruta) -Accion 'ANONIMIZAR' -Id $e.Id -Detalle "$Motivo; $borrados archivos borrados"
    $borrados
}

function Remove-ExpedienteCliente {
    # "Olvidar cliente": borra el expediente completo y anota su huella para que la sincronización
    # no lo vuelva a traer desde otro pendrive. Los respaldos cifrados viejos lo tienen hasta rotar.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Ruta)
    $id = [IO.Path]::GetFileName($Ruta.TrimEnd('\'))
    $clientes = Split-Path -Parent $Ruta.TrimEnd('\')
    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Borrar el expediente completo')) { return }
    [IO.Directory]::Delete($Ruta, $true)
    [IO.File]::AppendAllText((Join-Path $clientes $script:ArchivoOlvidados), (Get-HuellaExpediente $id) + "`r`n", [Text.Encoding]::ASCII)
    Add-RegistroPrivacidad -Clientes $clientes -Accion 'OLVIDAR' -Id $id -Detalle 'pedido del cliente'
}

function Export-DatosCliente {
    # "Entregar sus datos": un ZIP con lo que el kit guarda del cliente (sus datos y las atenciones,
    # sin notas internas) y sus informes. Devuelve la ruta del ZIP.
    param([Parameter(Mandatory)][string]$Ruta, [Parameter(Mandatory)][string]$Destino)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $e = Read-Expediente $Ruta
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('kit_datos_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = [IO.Directory]::CreateDirectory($tmp)
    try {
        $c = $e.Ficha['cliente']; $eq = $e.Ficha['equipo']
        $atenciones = foreach ($a in @(Get-ListaAtenciones -Expediente $e)) {
            [ordered]@{ fecha = $a['fecha']; motivos = $a['motivos']; sintoma = $a['sintoma']; paquete = $a['paquete']; precio = $a['precio']; entregado = $a['entregado']; garantia_hasta = $a['garantia_hasta'] }
        }
        $datos = [ordered]@{
            generado = (Get-Date).ToString('yyyy-MM-dd HH:mm', $script:Invariante)
            cliente  = [ordered]@{ nombre = $c['nombre']; contacto = $c['contacto']; comuna = $c['comuna']; consentimiento = $c['consentimiento']; version_texto = $c['consentimiento_version']; aviso_anual = $c['aviso_anual'] }
            equipo   = [ordered]@{ fabricante = $eq['fabricante']; modelo = $eq['modelo']; serie = $eq['serie']; cpu = $eq['cpu']; ram_gb = $eq['ram_gb'] }
            atenciones = @($atenciones)
        }
        [IO.File]::WriteAllText((Join-Path $tmp 'mis_datos.json'), ($datos | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
        foreach ($a in @(Get-ListaAtenciones -Expediente $e)) {
            $dir = Join-Path $Ruta $a['carpeta']
            if (-not [IO.Directory]::Exists($dir)) { continue }
            foreach ($f in [IO.Directory]::GetFiles($dir)) {
                $n = [IO.Path]::GetFileName($f)
                if ($n -match '^informe_cliente.*\.(html|pdf)$') { [IO.File]::Copy($f, (Join-Path $tmp "$($a['carpeta'])_$n"), $true) }
            }
        }
        $null = [IO.Directory]::CreateDirectory($Destino)
        $zip = Join-Path $Destino ('Mis_datos_{0}.zip' -f (Get-Date).ToString('yyyyMMdd_HHmm', $script:Invariante))
        if ([IO.File]::Exists($zip)) { [IO.File]::Delete($zip) }
        [IO.Compression.ZipFile]::CreateFromDirectory($tmp, $zip)
        Add-RegistroPrivacidad -Clientes (Split-Path -Parent $Ruta) -Accion 'ENTREGAR' -Id $e.Id -Detalle 'copia de sus datos'
        $zip
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
