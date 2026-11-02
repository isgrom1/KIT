# Privacidad.ps1 - Enmascarar datos antes de escribir cualquier archivo.
# - Claves de producto: solo los últimos 5 caracteres (Get-UltimosCaracteres).
# - Perfiles: C:\Users\<nombre> -> C:\Users\<U1>, <U2>... (config.json: enmascarar_perfiles).
#   <U1> es siempre el usuario que corre el diagnóstico.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

function Initialize-Privacidad {
    $reemplazos = New-Object System.Collections.Generic.List[object]
    if ($script:Ctx.Config.enmascarar_perfiles) {
        $perfiles = New-Object System.Collections.Generic.List[string]
        $actual = [Environment]::GetFolderPath('UserProfile')
        if ($actual) { $perfiles.Add($actual) }
        $lista = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        foreach ($sid in (Get-SubclavesRegistro -Colmena HKLM -Ruta $lista)) {
            if ($sid -notmatch '^S-1-(5-21|12-1)-') { continue }
            $ruta = Get-ValorRegistro -Colmena HKLM -Ruta "$lista\$sid" -Nombre 'ProfileImagePath'
            if (-not $ruta) { continue }
            $ruta = [Environment]::ExpandEnvironmentVariables($ruta)
            if (-not ($perfiles -contains $ruta)) { $perfiles.Add($ruta) }
        }
        $hojas = New-Object System.Collections.Generic.List[object]
        $i = 1
        foreach ($p in $perfiles) {
            $alias = "<U$i>"
            $reemplazo = (Split-Path -Parent $p) + '\' + $alias
            $reemplazos.Add(@([regex]::new('(?i)' + [regex]::Escape($p) + '(?=$|[\\/"'';,\s)\]])'), $reemplazo))
            $hojas.Add(@((Split-Path -Leaf $p), $alias))
            $i++
        }
        if ($env:USERNAME) { $hojas.Add(@($env:USERNAME, '<U1>')) }
        # El nombre de usuario como componente de cualquier ruta (Z:\ISAAC\isaac\Documents, EQUIPO\usuario).
        # Se salta con nombres genéricos o muy cortos para no ensuciar rutas como C:\Program Files\HP.
        $genericos = '^(?i)(admin|administrador|administrator|user|usuario|owner|pc|hp|dell|acer|asus|lenovo|public|default|guest|invitado)$'
        foreach ($h in $hojas) {
            if ($h[0].Length -lt 3 -or $h[0] -match $genericos) { continue }
            $reemplazos.Add(@([regex]::new('(?i)(?<=^|[\\\s])' + [regex]::Escape($h[0]) + '(?=$|[\\/\s"'';,)\]])'), $h[1]))
        }
    }
    $script:Ctx.Reemplazos = $reemplazos.ToArray()
}

function Protect-Texto {
    param([AllowNull()][AllowEmptyString()][string]$Texto)
    if (-not $Texto) { return $Texto }
    foreach ($r in $script:Ctx.Reemplazos) { $Texto = $r[0].Replace($Texto, $r[1]) }
    $Texto
}

function Get-UltimosCaracteres {
    # Nunca devuelve el texto completo: si es igual o más corto que lo pedido, devuelve $null.
    param([AllowNull()][AllowEmptyString()][string]$Texto, [int]$Cantidad = 5)
    if (-not $Texto) { return $null }
    $limpio = $Texto.Trim()
    if ($limpio.Length -le $Cantidad) { return $null }
    $limpio.Substring($limpio.Length - $Cantidad)
}

function ConvertTo-Protegido {
    # Copia profunda del objeto con todas las cadenas enmascaradas y fechas en texto ISO.
    param([AllowNull()]$Objeto)
    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [string]) { return (Protect-Texto $Objeto) }
    if ($Objeto -is [datetime]) { return (ConvertTo-TextoFecha $Objeto) }
    if ($Objeto -is [enum] -or $Objeto -is [timespan] -or $Objeto -is [guid]) { return $Objeto.ToString() }
    if ($Objeto -is [System.Collections.IDictionary]) {
        $n = [ordered]@{}
        foreach ($k in $Objeto.Keys) { $n[$k] = ConvertTo-Protegido $Objeto[$k] }
        return $n
    }
    if ($Objeto -is [System.Management.Automation.PSCustomObject]) {
        $n = [ordered]@{}
        foreach ($p in $Objeto.PSObject.Properties) { $n[$p.Name] = ConvertTo-Protegido $p.Value }
        return [pscustomobject]$n
    }
    if ($Objeto -is [System.Collections.IEnumerable] -and $Objeto -isnot [byte[]]) {
        $lista = New-Object System.Collections.Generic.List[object]
        foreach ($i in $Objeto) { $lista.Add((ConvertTo-Protegido $i)) }
        return , $lista.ToArray()
    }
    $Objeto
}
