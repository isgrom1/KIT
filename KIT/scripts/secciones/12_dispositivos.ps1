# 12 Dispositivos: equipos con error en el Administrador de dispositivos (ConfigManagerErrorCode).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:CodigoDispositivo = @{
    1 = 'Mal configurado'; 3 = 'Driver dañado o falta memoria'; 10 = 'No puede iniciar'; 12 = 'Sin recursos libres'
    14 = 'Requiere reiniciar'; 18 = 'Hay que reinstalar el driver'; 19 = 'Configuración del registro dañada'; 21 = 'Windows lo está quitando'
    22 = 'Deshabilitado'; 24 = 'No presente o sin todos sus drivers'; 28 = 'Sin driver'; 29 = 'Deshabilitado por el firmware'
    31 = 'El driver no funciona bien'; 32 = 'Servicio del driver deshabilitado'; 37 = 'El driver falló al iniciar'; 39 = 'Driver dañado o falta'
    40 = 'Clave de servicio del registro mal'; 41 = 'El driver cargó pero no encuentra el hardware'; 43 = 'Windows lo detuvo: reportó problemas'
    44 = 'Detenido por una app o servicio'; 47 = 'Preparado para quitar'; 48 = 'Driver bloqueado por incompatible'; 52 = 'Firma del driver no verificada'
}

function Get-DatosDispositivos {
    $lista = @(Get-Cim -Clase Win32_PnPEntity -Filtro 'ConfigManagerErrorCode <> 0' -Propiedades Name, PNPClass, PNPDeviceID, ConfigManagerErrorCode, Present)
    # 45 = "no conectado": dispositivos que estuvieron alguna vez (USB viejos, etc.); no son error.
    $filas = foreach ($x in ($lista | Where-Object { [int]$_.ConfigManagerErrorCode -ne 45 -and $_.Present -ne $false })) {
        $codigo = [int]$x.ConfigManagerErrorCode
        [pscustomobject][ordered]@{
            Dispositivo = $(if ($x.Name) { $x.Name } else { '(sin nombre)' })
            Clase       = $x.PNPClass
            Codigo      = $codigo
            Problema    = $(if ($script:CodigoDispositivo.ContainsKey($codigo)) { $script:CodigoDispositivo[$codigo] } else { "código $codigo" })
            Id          = $x.PNPDeviceID
        }
    }
    $filas = @($filas | Sort-Object Codigo, Dispositivo)
    Add-Tabla -Nombre 'dispositivos_con_error' -Filas $filas
    [ordered]@{ ConError = $filas }
}

function Test-AlertasDispositivos {
    $d = $script:Ctx.Datos.dispositivos
    $errores = @($d.ConError | Where-Object { $_.Codigo -ne 22 })
    if ($errores.Count -gt 0) {
        $lista = @($errores | ForEach-Object { "$($_.Dispositivo) ($($_.Problema), código $($_.Codigo))" }) -join '; '
        Add-Alerta -Severidad AVISO -Codigo 'DIS-ERROR' -Texto "$($errores.Count) dispositivos con error en el Administrador de dispositivos: $lista"
    }
    $deshab = @($d.ConError | Where-Object { $_.Codigo -eq 22 } | ForEach-Object { $_.Dispositivo })
    if ($deshab.Count -gt 0) {
        Add-Alerta -Severidad INFO -Codigo 'DIS-DESHABILITADO' -Texto "Dispositivos deshabilitados a mano: $($deshab -join ', ')"
    }
}

function Format-ResumenDispositivos {
    $d = $script:Ctx.Datos.dispositivos
    if (@($d.ConError).Count -eq 0) { 'Sin dispositivos con error'; return }
    foreach ($x in $d.ConError) { "Código $($x.Codigo)  : $($x.Dispositivo) [$($x.Clase)] - $($x.Problema)" }
}
