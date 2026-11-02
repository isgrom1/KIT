# 03 Windows: edición, versión/build, soporte, activación, canal de licencia y clave OEM del firmware.
# De la clave OEM solo se guarda si existe y sus últimos 5 caracteres; la clave completa no sale de memoria.

$script:EstadoLicencia = @{ 0 = 'Sin licencia'; 1 = 'Activado'; 2 = 'Gracia inicial'; 3 = 'Gracia adicional'; 4 = 'Gracia no genuino'; 5 = 'Notificación (no activado)'; 6 = 'Gracia extendida' }
$script:IdWindows = '55c92734-d682-4d71-983e-d6ec3f16059f'

function Get-GrupoEdicion {
    param([AllowEmptyString()][string]$EditionId)
    switch -Regex ($EditionId) {
        '^IoTEnterpriseS' { return 'iot_ltsc' }
        '^Enterprise(S|SN)$' { return 'ltsc' }
        '^(Core|Professional)' { return 'hogar' }
        '^(Enterprise|Education|IoTEnterprise|ServerRdsh)' { return 'empresa' }
    }
    'hogar'
}

function Get-DatosWindows {
    $cv = Get-ValoresRegistro -Colmena HKLM -Ruta 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = Get-Cim -Clase Win32_OperatingSystem -Propiedades Caption, InstallDate, MUILanguages
    $build = [int]$cv['CurrentBuild']
    # ProductName del registro sigue diciendo "Windows 10" en Windows 11: se usa Caption y el build.
    $nombre = ("$($os.Caption)" -replace '^Microsoft\s+', '').Trim()
    if ($build -ge 22000 -and $nombre -match 'Windows 10') { $nombre = $nombre -replace 'Windows 10', 'Windows 11' }
    $version = if ($cv['DisplayVersion']) { $cv['DisplayVersion'] } else { $cv['ReleaseId'] }
    $arquitectura = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }

    $insider = Invoke-Paso 'Insider' {
        $a = Get-ValoresRegistro -Colmena HKLM -Ruta 'SOFTWARE\Microsoft\WindowsSelfHost\Applicability'
        $canal = (@($a['BranchName'], $a['Ring'], $a['ContentType']) | Where-Object { $_ }) -join ' / '
        [pscustomobject]@{ Inscrito = [bool]$canal; Canal = $canal }
    }

    $d = [ordered]@{
        Nombre          = $nombre
        EditionId       = $cv['EditionID']
        GrupoEdicion    = Get-GrupoEdicion $cv['EditionID']
        Version         = $version
        Build           = $build
        Ubr             = $cv['UBR']
        BuildCompleto   = "$build.$($cv['UBR'])"
        Rama            = $cv['BuildBranch']
        Arquitectura    = $arquitectura
        Idiomas         = @($os.MUILanguages)
        InstaladoEl     = ConvertTo-TextoFecha $os.InstallDate -SoloFecha
        Insider         = $insider
        Soporte         = Invoke-Paso 'ciclo de vida' { Get-SoporteWindows -Build $build -Grupo (Get-GrupoEdicion $cv['EditionID']) }
        Licencia        = Invoke-Paso 'activación' { Get-LicenciaWindows }
        ClaveOem        = Invoke-Paso 'clave OEM firmware' { Get-ClaveOemFirmware }
    }
    $estado = if ($d.Licencia) { "$($d.Licencia.Estado) ($($d.Licencia.Canal))" } else { 'activación desconocida' }
    $soporte = if ($d.Soporte -and $d.Soporte.Fin) { "soporte hasta $($d.Soporte.Fin)" } else { 'soporte: build fuera de tabla' }
    $d.Linea = "Windows    : $($d.Nombre) $($d.Version) (build $($d.BuildCompleto)) $($d.Arquitectura) | $estado | $soporte"
    $d
}

function Get-SoporteWindows {
    param([int]$Build, [string]$Grupo)
    $tabla = Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'ciclo_vida_windows.json')
    $v = $tabla.versiones | Where-Object { $_.build -eq $Build } | Select-Object -First 1
    if (-not $v) {
        $minimo = ($tabla.versiones | Measure-Object -Property build -Minimum).Minimum
        return [pscustomobject][ordered]@{
            EnTabla = $false; Producto = $null; Version = $null; Fin = $null; Nota = $null
            Vigente = $(if ($Build -lt $minimo) { $false } else { $null })
            Revisado = $tabla.revisado
        }
    }
    $campo = "fin_$Grupo"
    $fin = $v.$campo
    if (-not $fin) { $fin = $v.fin_hogar }
    $fecha = [datetime]::ParseExact($fin, 'yyyy-MM-dd', $script:Invariante)
    [pscustomobject][ordered]@{
        EnTabla       = $true
        Producto      = $v.producto
        Version       = $v.version
        Fin           = $fin
        DiasRestantes = [int][math]::Floor(($fecha - (Get-Date).Date).TotalDays)
        Vigente       = ($fecha -ge (Get-Date).Date)
        Nota          = $v.nota
        Revisado      = $tabla.revisado
    }
}

function Get-LicenciaWindows {
    $productos = @(Get-Cim -Clase SoftwareLicensingProduct -Filtro "ApplicationID='$script:IdWindows' AND PartialProductKey IS NOT NULL" -Propiedades Name, Description, LicenseStatus, PartialProductKey, ProductKeyChannel, GracePeriodRemaining, KeyManagementServiceMachine, DiscoveredKeyManagementServiceMachineName)
    $principal = $productos | Where-Object { $_.Name -notmatch 'ESU' } | Select-Object -First 1
    if (-not $principal) { $principal = $productos | Select-Object -First 1 }
    if (-not $principal) {
        return [pscustomobject][ordered]@{ Estado = 'Sin clave instalada'; CodigoEstado = 0; Canal = 'ninguno'; Kms = $false; ClaveUltimos5 = $null; Producto = $null; HostKms = $null; GraciaMinutos = $null; Esu = @() }
    }
    $estado = $script:EstadoLicencia[[int]$principal.LicenseStatus]
    if (-not $estado) { $estado = "código $($principal.LicenseStatus)" }
    $kms = ("$($principal.Description)" -match 'VOLUME_KMSCLIENT') -or ($principal.ProductKeyChannel -eq 'Volume:GVLK')
    $hostKms = (@($principal.KeyManagementServiceMachine, $principal.DiscoveredKeyManagementServiceMachineName) | Where-Object { $_ }) -join ' / '
    $canal = $principal.ProductKeyChannel
    if (-not $canal -and "$($principal.Description)" -match ',\s*(\S+)\s+channel') { $canal = $Matches[1] }
    [pscustomobject][ordered]@{
        Estado        = $estado
        CodigoEstado  = [int]$principal.LicenseStatus
        Canal         = $canal
        Kms           = [bool]$kms
        HostKms       = $hostKms
        ClaveUltimos5 = $principal.PartialProductKey
        Producto      = $principal.Name
        GraciaMinutos = $principal.GracePeriodRemaining
        Esu           = @($productos | Where-Object { $_.Name -match 'ESU' } | ForEach-Object { "$($_.Name): $($script:EstadoLicencia[[int]$_.LicenseStatus])" })
    }
}

function Get-ClaveOemFirmware {
    # La clave completa existe solo en estas variables locales; se descarta antes de devolver.
    $svc = Get-Cim -Clase SoftwareLicensingService -Propiedades OA3xOriginalProductKey, OA3xOriginalProductKeyDescription
    $clave = "$($svc.OA3xOriginalProductKey)".Trim()
    $descripcion = "$($svc.OA3xOriginalProductKeyDescription)".Trim()
    $existe = [bool]$clave
    if (-not $existe -and -not $script:Ctx.Admin.Elevado) {
        # Sin admin la clave puede venir vacía aunque exista: no se afirma que no hay.
        $existe = $null
        Add-Incompleto -Parte 'Clave OEM del firmware'
    }
    $resultado = [pscustomobject][ordered]@{
        Existe      = $existe
        Ultimos5    = Get-UltimosCaracteres $clave 5
        Descripcion = $descripcion
        Edicion     = $(if ($descripcion -match '\]\s*(\S+)') { $Matches[1] } else { $null })
    }
    $clave = $null
    $svc = $null
    $resultado
}

function Test-AlertasWindows {
    $d = $script:Ctx.Datos.windows
    $l = $d.Licencia
    if ($l) {
        if ($l.CodigoEstado -ne 1) {
            Add-Alerta -Severidad CRITICO -Codigo 'WIN-ACTIVACION' -Texto "Windows no activado (estado: $($l.Estado), canal: $($l.Canal))"
        }
        if ($l.Kms) {
            $hostTxt = if ($l.HostKms) { " (servidor KMS: $($l.HostKms))" } else { '' }
            if ($d.GrupoEdicion -eq 'hogar') {
                Add-Alerta -Severidad AVISO -Codigo 'WIN-KMS' -Texto "Activación por KMS en $($d.EditionId)${hostTxt}: típico de activadores no oficiales (KMSpico, KMSAuto)"
            } else {
                Add-Alerta -Severidad INFO -Codigo 'WIN-KMS' -Texto "Activación por KMS$hostTxt (normal en empresas con servidor KMS propio)"
            }
        }
    }
    $o = $d.ClaveOem
    if ($o -and $o.Existe -and $o.Edicion -and $d.EditionId -and $o.Edicion -ne $d.EditionId) {
        Add-Alerta -Severidad INFO -Codigo 'WIN-OEM-EDICION' -Texto "La clave OEM del firmware es para $($o.Edicion) y está instalado $($d.EditionId) (al reinstalar, usar la edición del firmware para que active sola)"
    }
    $s = $d.Soporte
    if ($s) {
        if (-not $s.EnTabla) {
            if ($s.Vigente -eq $false) {
                Add-Alerta -Severidad CRITICO -Codigo 'WIN-SOPORTE' -Texto "Build $($d.Build) es anterior a todas las versiones con soporte: sin actualizaciones de seguridad"
            } else {
                Add-Alerta -Severidad INFO -Codigo 'WIN-SOPORTE' -Texto "Build $($d.Build) no está en ciclo_vida_windows.json (revisado $($s.Revisado)): versión nueva o Insider, revisar la tabla"
            }
        } elseif (-not $s.Vigente) {
            $nota = if ($s.Nota) { " ($($s.Nota))" } else { '' }
            Add-Alerta -Severidad CRITICO -Codigo 'WIN-SOPORTE' -Texto "$($s.Producto) $($s.Version) sin actualizaciones desde el $($s.Fin)$nota"
        } elseif ($s.DiasRestantes -le (Get-Umbral 'soporte_aviso_dias')) {
            Add-Alerta -Severidad AVISO -Codigo 'WIN-SOPORTE' -Texto "$($s.Producto) $($s.Version) deja de recibir actualizaciones el $($s.Fin) (en $($s.DiasRestantes) días)"
        }
    }
    if ($d.Insider -and $d.Insider.Inscrito) {
        Add-Alerta -Severidad INFO -Codigo 'WIN-INSIDER' -Texto "Equipo inscrito en Windows Insider ($($d.Insider.Canal))"
    }
}

function Format-ResumenWindows {
    $d = $script:Ctx.Datos.windows
    "Edición    : $($d.Nombre) ($($d.EditionId), grupo $($d.GrupoEdicion)) | $($d.Version) build $($d.BuildCompleto) | rama $($d.Rama) | $($d.Arquitectura)"
    "Idioma     : $($d.Idiomas -join ', ') | instalado/actualizado el $($d.InstaladoEl) | Insider: $(if ($d.Insider -and $d.Insider.Inscrito) { $d.Insider.Canal } else { 'no' })"
    if ($d.Soporte -and $d.Soporte.EnTabla) { "Soporte    : hasta $($d.Soporte.Fin) ($($d.Soporte.DiasRestantes) días)$(if ($d.Soporte.Nota) { ' | ' + $d.Soporte.Nota })" }
    if ($d.Licencia) {
        $l = $d.Licencia
        "Activación : $($l.Estado) | canal $($l.Canal) | clave instalada ...$($l.ClaveUltimos5) | KMS: $(if ($l.Kms) { 'sí ' + $l.HostKms } else { 'no' })"
        if ($l.Esu.Count -gt 0) { "ESU        : $($l.Esu -join '; ')" }
    }
    if ($d.ClaveOem) {
        if ($d.ClaveOem.Existe) { "Clave OEM  : en firmware, termina en ...$($d.ClaveOem.Ultimos5) | $($d.ClaveOem.Descripcion)" }
        elseif ($null -eq $d.ClaveOem.Existe) { 'Clave OEM  : no se pudo leer sin admin' }
        else { 'Clave OEM  : no hay clave en el firmware (MSDM)' }
    }
}
