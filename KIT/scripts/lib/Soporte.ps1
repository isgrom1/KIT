# Soporte.ps1 - Paquete de soporte: un .zip chico con lo necesario para revisar después, en el PC del técnico,
# qué pasó en una atención (registros, alertas, parámetros y estado del expediente). Sin el nombre, el
# contacto ni la comuna del cliente, y sin los CSV del diagnóstico, discos.txt, fotos ni informes.
# Requiere lib\Comun, lib\Expediente.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

Add-Type -AssemblyName System.IO.Compression

function Export-PaqueteSoporte {
    # Escribe <Destino>\soporte_<fabricante>-<modelo>_<fecha_hora>.zip y devuelve su ruta. Lleva todas las
    # atenciones del expediente (así se ven las duplicadas) y marca cuál estaba abierta.
    param(
        [Parameter(Mandatory)]$Expediente,
        [string]$Atencion,
        [string]$Destino = (Join-Path $script:Ctx.RaizKit 'soporte')
    )
    $f = (Read-Expediente $Expediente.Ruta).Ficha
    $cliente = $f['cliente']
    # Lo que hay que tapar en los textos: los datos del cliente tal como se escribieron.
    # Un teléfono se tapa aunque esté escrito con otros espacios o guiones (la ficha lo guarda sin espacios).
    $tapar = [ordered]@{}
    foreach ($k in 'nombre', 'contacto', 'comuna') {
        $v = if ($cliente) { "$($cliente[$k])".Trim() } else { '' }
        if ($v.Length -lt 3) { continue }
        $patron = if ($v -match '^\+?[\d\s\-\.]{6,}$') { (($v -replace '[^\d]', '').ToCharArray() | ForEach-Object { [string]$_ }) -join '[\s\-\.]*' } else { [regex]::Escape($v) }
        $tapar[$patron] = "<$($k.ToUpperInvariant())>"
    }
    $limpiar = {
        param([string]$Texto)
        foreach ($p in $tapar.Keys) { $Texto = [regex]::Replace($Texto, $p, $tapar[$p], 'IgnoreCase') }
        $Texto
    }

    $null = [IO.Directory]::CreateDirectory($Destino)
    $equipo = (@($f['equipo']['fabricante'], $f['equipo']['modelo']) | Where-Object { $_ }) -join '-'
    $equipo = [regex]::Replace($(if ($equipo) { $equipo } else { 'equipo' }), '[^\w\-]+', '-')
    $zip = Join-Path $Destino ('soporte_{0}_{1}.zip' -f $equipo, (Get-Date).ToString('yyyyMMdd_HHmmss'))
    $utf8 = New-Object Text.UTF8Encoding($true)
    $fs = [IO.File]::Open($zip, [IO.FileMode]::CreateNew)
    $z = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    $agregar = {
        param([string]$Nombre, [string]$Texto)
        $e = $z.CreateEntry($Nombre)
        $s = $e.Open()
        try { $b = $utf8.GetPreamble() + $utf8.GetBytes((& $limpiar $Texto)); $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
    }
    $leer = { param([string]$Ruta) if ([IO.File]::Exists($Ruta)) { [IO.File]::ReadAllText($Ruta, [Text.Encoding]::UTF8) } else { $null } }
    try {
        # Estado del kit y del equipo donde se armó.
        $i = Test-IntegridadKit -RaizKit $script:Ctx.RaizKit
        $os = [Environment]::OSVersion.Version
        $leeme = @(
            'PAQUETE DE SOPORTE - KIT SERVICIO'
            "Armado: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
            "Kit: $($script:Ctx.Version) | verificación: $($i.Estado)$(if ($i.Estado -eq 'cambios') { " ($(@($i.Cambiados + $i.Faltan + $i.Nuevos) -join ', '))" })"
            "PowerShell $($PSVersionTable.PSVersion) | Windows $($os.Major).$($os.Minor) build $($os.Build) | admin: $(if ($script:Ctx.Admin.Elevado) { 'sí' } else { 'no' }) | modo de lenguaje: $($ExecutionContext.SessionState.LanguageMode)"
            "Expediente: $($Expediente.Id)"
            "Atención abierta en la ventana: $(if ($Atencion) { $Atencion } else { '(ninguna)' })"
            ''
            'Lleva: ficha.json sin los datos del cliente, y por atención: trabajo.log, la lista de archivos, y de cada'
            'medición log.txt, resumen.txt, alertas.json (alertas y parámetros) y los resúmenes de sensores.'
            'No lleva: nombre, contacto ni comuna del cliente, CSV del diagnóstico, discos.txt, fotos ni informes.'
        ) -join "`r`n"
        & $agregar 'LEEME.txt' $leeme

        # La ficha tal como está en el pendrive (sin completar campos), con el cliente tapado.
        $copia = [IO.File]::ReadAllText((Join-Path $Expediente.Ruta 'ficha.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($copia.PSObject.Properties['cliente']) { $copia.cliente = [ordered]@{ nombre = '<NOMBRE>'; contacto = '<CONTACTO>'; comuna = '<COMUNA>' } }
        & $agregar 'ficha.json' ($copia | ConvertTo-Json -Depth 12)

        foreach ($dirAt in @(Get-ChildItem -LiteralPath $Expediente.Ruta -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_' } | Sort-Object Name)) {
            $n = $dirAt.Name
            $lista = @(Get-ChildItem -LiteralPath $dirAt.FullName -Recurse -File | ForEach-Object {
                    "{0}`t{1}`t{2}" -f $_.FullName.Substring($dirAt.FullName.Length + 1), $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                })
            & $agregar "$n/archivos.txt" ("ruta`tbytes`tmodificado`r`n" + ($lista -join "`r`n"))
            $t = & $leer (Join-Path $dirAt.FullName 'trabajo.log')
            if ($null -ne $t) { & $agregar "$n/trabajo.log" $t }
            foreach ($j in @(Get-ChildItem -LiteralPath $dirAt.FullName -File -Filter '*.json' | Where-Object { $_.Name -notlike '_gui*' })) { & $agregar "$n/$($j.Name)" (& $leer $j.FullName) }
            foreach ($m in @(Get-ChildItem -LiteralPath $dirAt.FullName -Directory | Where-Object { $_.Name -match '^(antes|despues)' })) {
                foreach ($x in 'log.txt', 'resumen.txt', 'sensores_resumen.json') {
                    $t = & $leer (Join-Path $m.FullName $x)
                    if ($null -ne $t) { & $agregar "$n/$($m.Name)/$x" $t }
                }
                $dj = Join-Path $m.FullName 'diagnostico.json'
                if ([IO.File]::Exists($dj)) {
                    try {
                        $d = (& $leer $dj) | ConvertFrom-Json
                        & $agregar "$n/$($m.Name)/alertas.json" ([ordered]@{ kit = $d.kit; alertas = $d.alertas } | ConvertTo-Json -Depth 8)
                    } catch { & $agregar "$n/$($m.Name)/alertas.json" "{ `"error`": `"diagnostico.json ilegible: $($_.Exception.Message -replace '"', "'")`" }" }
                }
            }
        }
    } finally {
        $z.Dispose()
        $fs.Dispose()
    }
    $zip
}
