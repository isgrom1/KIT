# 01 Equipo: fabricante, modelo, serie, BIOS, tipo de equipo, uptime y permisos.

function Get-DatosEquipo {
    $cs = Get-Cim -Clase Win32_ComputerSystem -Propiedades Manufacturer, Model, SystemFamily, SystemSKUNumber, PCSystemType, PartOfDomain, Domain, Name
    $bios = Get-Cim -Clase Win32_BIOS -Propiedades SMBIOSBIOSVersion, ReleaseDate, Manufacturer
    $os = Get-Cim -Clase Win32_OperatingSystem -Propiedades LastBootUpTime
    $placa = Invoke-Paso 'placa base' { Get-Cim -Clase Win32_BaseBoard -Propiedades Manufacturer, Product }
    $bateria = Invoke-Paso 'batería presente' { @(Get-Cim -Clase Win32_Battery -Propiedades DeviceID).Count -gt 0 }
    $energia = Invoke-Paso 'inicio rápido' {
        [pscustomobject]@{
            Hibernacion = Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Power' -Nombre 'HibernateEnabled'
            Hiberboot   = Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Nombre 'HiberbootEnabled'
        }
    }

    $uptime = (Get-Date) - $os.LastBootUpTime
    $tipo = switch ([int]$cs.PCSystemType) { 1 { 'Escritorio' } 2 { 'Notebook' } 3 { 'Workstation' } 8 { 'Tablet' } default { 'Otro' } }
    $id = $script:Ctx.Identidad
    $placaTexto = $null
    if ($placa) { $placaTexto = ("$($placa.Manufacturer) $($placa.Product)").Trim() }
    $firmware = 'Desconocido'
    if ($env:firmware_type) { $firmware = $env:firmware_type }

    $d = [ordered]@{
        Fabricante             = $id.Fabricante
        Modelo                 = $id.Modelo
        FabricanteSmbios       = "$($cs.Manufacturer)".Trim()
        ModeloSmbios           = "$($cs.Model)".Trim()
        Familia                = "$($cs.SystemFamily)".Trim()
        Sku                    = "$($cs.SystemSKUNumber)".Trim()
        Serie                  = $id.Serie
        Tipo                   = $tipo
        TieneBateria           = [bool]$bateria
        PlacaBase              = $placaTexto
        BiosVersion            = "$($bios.SMBIOSBIOSVersion)".Trim()
        BiosFecha              = ConvertTo-TextoFecha $bios.ReleaseDate -SoloFecha
        BiosFabricante         = "$($bios.Manufacturer)".Trim()
        Firmware               = $firmware
        NombreEquipo           = $cs.Name
        EnDominio              = [bool]$cs.PartOfDomain
        Dominio                = $(if ($cs.PartOfDomain) { $cs.Domain } else { $null })
        UltimoArranque         = ConvertTo-TextoFecha $os.LastBootUpTime
        UptimeDias             = [math]::Round($uptime.TotalDays, 1)
        UptimeTexto            = '{0} d {1} h {2} min' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        InicioRapidoEfectivo   = [bool]($energia -and $energia.Hiberboot -eq 1 -and $energia.Hibernacion -eq 1)
        Elevado                = $script:Ctx.Admin.Elevado
        MiembroAdministradores = $script:Ctx.Admin.MiembroAdministradores
        PowerShell             = $PSVersionTable.PSVersion.ToString()
        Proceso64Bits          = [Environment]::Is64BitProcess
    }
    $serie = if ($d.Serie) { $d.Serie } else { '(sin serie)' }
    $d.Linea = "Equipo     : $($d.Fabricante) $($d.Modelo) ($($d.Tipo)) | S/N $serie | BIOS $($d.BiosVersion) ($($d.BiosFecha))"
    $d
}

function Test-AlertasEquipo {
    $d = $script:Ctx.Datos.equipo
    $dias = Get-Umbral 'uptime_dias'
    if ($d.UptimeDias -gt $dias) {
        $t = "Uptime de $($d.UptimeTexto) (más de $dias días sin reiniciar)"
        if ($d.InicioRapidoEfectivo) { $t += '; con inicio rápido activo, Apagar no reinicia: hay que usar Reiniciar' }
        Add-Alerta -Severidad AVISO -Codigo 'EQ-UPTIME' -Texto $t
    }
    if ($d.BiosFecha) {
        $fecha = [datetime]::ParseExact($d.BiosFecha, 'yyyy-MM-dd', $script:Invariante)
        $meses = Get-Umbral 'bios_meses'
        if ($fecha -lt (Get-Date).AddMonths(-$meses)) {
            Add-Alerta -Severidad INFO -Codigo 'EQ-BIOS' -Texto "BIOS $($d.BiosVersion) del $($d.BiosFecha) (más de $meses meses). Informar al cliente; actualización solo en servicio oficial."
        }
    }
}

function Format-ResumenEquipo {
    $d = $script:Ctx.Datos.equipo
    $dominio = if ($d.EnDominio) { "en dominio $($d.Dominio)" } else { 'sin dominio' }
    "Modelo     : $($d.FabricanteSmbios) / $($d.ModeloSmbios) | familia: $($d.Familia) | SKU: $($d.Sku)"
    "Placa base : $($d.PlacaBase) | firmware $($d.Firmware) | BIOS $($d.BiosFabricante) $($d.BiosVersion) del $($d.BiosFecha)"
    "Nombre     : $($d.NombreEquipo) ($dominio) | batería: $(if ($d.TieneBateria) { 'sí' } else { 'no' })"
    "Uptime     : $($d.UptimeTexto) (último arranque $($d.UltimoArranque)) | inicio rápido efectivo: $(if ($d.InicioRapidoEfectivo) { 'sí' } else { 'no' })"
}
