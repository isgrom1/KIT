# 06 Software: programas instalados (HKLM 64/32 + HKCU), apps de la Store del usuario actual y
# detección de optimizadores, actualizadores de drivers, activadores, PUP y bloatware
# (lista editable en config\software_conocido.json).

function Get-DatosSoftware {
    $d = [ordered]@{}
    $d.Programas = Invoke-Paso 'programas' { Get-ProgramasKit }
    Add-Tabla -Nombre 'programas' -Filas $d.Programas
    $d.AppsStore = Invoke-Paso 'apps de la Store' {
        @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework -and "$($_.SignatureKind)" -ne 'System' }) | ForEach-Object {
            $editor = if ("$($_.Publisher)" -match 'O=([^,]+)') { $Matches[1] } elseif ("$($_.Publisher)" -match 'CN=([^,]+)') { $Matches[1] } else { $_.Publisher }
            [pscustomobject][ordered]@{
                Nombre      = $_.Name
                Version     = "$($_.Version)"
                Editor      = $editor.Trim('"', ' ')
                Firma       = "$($_.SignatureKind)"
                NoRemovible = [bool]$_.NonRemovable
            }
        } | Sort-Object Nombre
    }
    Add-Tabla -Nombre 'apps_store' -Filas $d.AppsStore

    $hallazgos = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($d.Programas | Where-Object { $_ })) {
        $h = Find-SoftwareConocido -Textos $p.Nombre, $p.Editor
        if ($h) { $hallazgos.Add((ConvertTo-FilaHallazgo -Hallazgo $h -Nombre $p.Nombre -Donde $p.Origen)) }
    }
    foreach ($a in @($d.AppsStore | Where-Object { $_ })) {
        $h = Find-SoftwareConocido -Textos $a.Nombre
        if ($h) { $hallazgos.Add((ConvertTo-FilaHallazgo -Hallazgo $h -Nombre $a.Nombre -Donde 'Store')) }
    }
    $d.Detectados = $hallazgos.ToArray()
    Add-Tabla -Nombre 'software_detectado' -Filas $d.Detectados

    $dias = Get-Umbral 'eventos_dias'
    $desde = (Get-Date).AddDays(-$dias).ToString('yyyy-MM-dd', $script:Invariante)
    $d.Recientes = @($d.Programas | Where-Object { $_ -and $_.InstaladoEl -and $_.InstaladoEl -ge $desde } | Sort-Object InstaladoEl -Descending)
    $d
}

function ConvertTo-FilaHallazgo {
    param($Hallazgo, [string]$Nombre, [string]$Donde)
    [pscustomobject][ordered]@{
        Categoria = $Hallazgo.Categoria
        Severidad = $Hallazgo.Severidad
        Texto     = $Hallazgo.Texto
        Nombre    = $Nombre
        Donde     = $Donde
    }
}

function Get-ProgramasKit {
    $ruta = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $fuentes = @([pscustomobject]@{ Colmena = 'HKLM'; Vista = 64; Origen = 'HKLM 64' })
    if ([Environment]::Is64BitOperatingSystem) { $fuentes += [pscustomobject]@{ Colmena = 'HKLM'; Vista = 32; Origen = 'HKLM 32' } }
    $fuentes += [pscustomobject]@{ Colmena = 'HKCU'; Vista = 64; Origen = 'HKCU' }
    $filas = foreach ($f in $fuentes) {
        foreach ($sub in (Get-SubclavesRegistro -Colmena $f.Colmena -Ruta $ruta -Vista $f.Vista)) {
            $v = Get-ValoresRegistro -Colmena $f.Colmena -Ruta "$ruta\$sub" -Vista $f.Vista
            $nombre = "$($v['DisplayName'])".Trim()
            if (-not $nombre) { continue }
            if ($v['SystemComponent'] -eq 1 -or $v['ParentKeyName'] -or "$($v['ReleaseType'])" -match 'Update|Hotfix') { continue }
            $fecha = $null
            if ("$($v['InstallDate'])" -match '^(\d{4})(\d{2})(\d{2})$') { $fecha = '{0}-{1}-{2}' -f $Matches[1], $Matches[2], $Matches[3] }
            [pscustomobject][ordered]@{
                Nombre      = $nombre
                Version     = "$($v['DisplayVersion'])".Trim()
                Editor      = "$($v['Publisher'])".Trim()
                InstaladoEl = $fecha
                TamanoMB    = $(if ($v['EstimatedSize']) { [math]::Round([double]$v['EstimatedSize'] / 1024, 0) } else { $null })
                Origen      = $f.Origen
                Ubicacion   = "$($v['InstallLocation'])".Trim()
            }
        }
    }
    @($filas | Sort-Object Nombre, Origen)
}

function Test-AlertasSoftware {
    $d = $script:Ctx.Datos.software
    Add-AlertasSoftwareConocido -Hallazgos $d.Detectados -Prefijo 'SW'
}

function Format-ResumenSoftware {
    $d = $script:Ctx.Datos.software
    $p = @($d.Programas | Where-Object { $_ })
    $porOrigen = @($p | Group-Object Origen | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
    "Programas  : $($p.Count) ($porOrigen) | apps de la Store (usuario actual, sin sistema ni frameworks): $(@($d.AppsStore | Where-Object { $_ }).Count)"
    if (@($d.Detectados).Count -eq 0) { 'Detectados : nada de la lista de software conocido' }
    foreach ($h in @($d.Detectados | Where-Object { $_ })) { "Detectado  : [$($h.Categoria)] $($h.Nombre) ($($h.Donde))" }
    $r = @($d.Recientes)
    "Recientes  : $($r.Count) programas instalados o actualizados en los últimos $(Get-Umbral 'eventos_dias') días"
    foreach ($x in ($r | Select-Object -First 10)) { "             - $($x.InstaladoEl) $($x.Nombre) $($x.Version)" }
    if ($r.Count -gt 10) { "             (lista completa en csv\06_programas.csv)" }
}
