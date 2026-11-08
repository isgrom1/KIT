# 02 Hardware: CPU, RAM (módulos, velocidad, slots), GPU y driver, discos físicos y batería.

$script:TipoMemoria = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
$script:TipoMedio = @{ 0 = 'No especificado'; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
$script:TipoBus = @{ 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID/VMD'; 9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 16 = 'Storage Spaces'; 17 = 'NVMe'; 18 = 'SCM'; 19 = 'UFS' }
$script:SaludDisco = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy'; 5 = 'Unknown' }
$script:EstadoOperativo = @{ 2 = 'OK'; 3 = 'Degradado'; 5 = 'Falla predictiva'; 6 = 'Error'; 7 = 'Error no recuperable'; 10 = 'Detenido'; 12 = 'Sin contacto'; 13 = 'Perdió comunicación' }

function Get-DatosHardware {
    $d = [ordered]@{}

    $d.Cpu = Invoke-Paso 'CPU' {
        @(Get-Cim -Clase Win32_Processor -Propiedades Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L3CacheSize, SocketDesignation) | ForEach-Object {
            [pscustomobject][ordered]@{
                Nombre      = ("$($_.Name)" -replace '\s+', ' ').Trim()
                Fabricante  = $_.Manufacturer
                Nucleos     = $_.NumberOfCores
                Hilos       = $_.NumberOfLogicalProcessors
                MaxMHz      = $_.MaxClockSpeed
                L3MB        = [math]::Round($_.L3CacheSize / 1024, 1)
                Zocalo      = $_.SocketDesignation
            }
        }
    }
    Add-Tabla -Nombre 'cpu' -Filas $d.Cpu

    $d.Ram = Invoke-Paso 'RAM' {
        $modulos = @(Get-Cim -Clase Win32_PhysicalMemory -Propiedades BankLabel, DeviceLocator, Capacity, Speed, ConfiguredClockSpeed, Manufacturer, PartNumber, SMBIOSMemoryType, FormFactor)
        $arreglos = @(Get-Cim -Clase Win32_PhysicalMemoryArray -Propiedades MemoryDevices, Use)
        $sistema = @($arreglos | Where-Object { $_.Use -eq 3 })
        if ($sistema.Count -eq 0) { $sistema = $arreglos }
        $slots = ($sistema | Measure-Object -Property MemoryDevices -Sum).Sum
        $filas = foreach ($m in $modulos) {
            $tipo = $script:TipoMemoria[[int]$m.SMBIOSMemoryType]
            if (-not $tipo) { $tipo = "código $($m.SMBIOSMemoryType)" }
            [pscustomobject][ordered]@{
                Slot           = "$($m.DeviceLocator)".Trim()
                Banco          = "$($m.BankLabel)".Trim()
                CapacidadGB    = ConvertTo-GB $m.Capacity 1
                Tipo           = $tipo
                VelocidadMTs   = $m.Speed
                ConfiguradaMTs = $m.ConfiguredClockSpeed
                Fabricante     = "$($m.Manufacturer)".Trim()
                NumeroParte    = "$($m.PartNumber)".Trim()
            }
        }
        $cs = Get-Cim -Clase Win32_ComputerSystem -Propiedades TotalPhysicalMemory
        [ordered]@{
            TotalGB        = [math]::Round((($modulos | Measure-Object -Property Capacity -Sum).Sum) / 1GB, 1)
            UtilizableGB   = ConvertTo-GB $cs.TotalPhysicalMemory 1
            Modulos        = @($filas)
            CantidadModulos = $modulos.Count
            Slots          = [int]$slots
        }
    }
    if ($d.Ram) { Add-Tabla -Nombre 'ram' -Filas $d.Ram.Modulos }

    $d.Gpu = Invoke-Paso 'GPU' { Get-GpuKit }
    Add-Tabla -Nombre 'gpu' -Filas $d.Gpu

    $d.Discos = Invoke-Paso 'discos' { Get-DiscosKit }
    Add-Tabla -Nombre 'discos' -Filas $d.Discos

    $d.Baterias = Invoke-Paso 'batería' { Get-BateriaKit }
    Add-Tabla -Nombre 'bateria' -Filas $d.Baterias

    $partes = @()
    if ($d.Cpu) { $partes += ('{0} {1}C/{2}T' -f $d.Cpu[0].Nombre, $d.Cpu[0].Nucleos, $d.Cpu[0].Hilos) }
    if ($d.Ram) {
        $tipo = if ($d.Ram.Modulos.Count -gt 0) { $d.Ram.Modulos[0].Tipo } else { '' }
        $partes += ('{0} GB RAM {1} ({2} módulos)' -f (Format-Numero $d.Ram.TotalGB 0), $tipo, $d.Ram.CantidadModulos)
    }
    if ($d.Gpu) { $partes += (@($d.Gpu | ForEach-Object { $_.Nombre }) -join ' + ') }
    $d.Linea = 'Hardware   : ' + ($partes -join ' | ')
    $d
}

function Get-GpuKit {
    # VRAM real desde la clave de clase del driver (AdapterRAM de WMI se corta en 4 GB).
    $clase = 'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $drivers = foreach ($sub in (Get-SubclavesRegistro -Colmena HKLM -Ruta $clase)) {
        if ($sub -notmatch '^\d{4}$') { continue }
        $v = Get-ValoresRegistro -Colmena HKLM -Ruta "$clase\$sub"
        [pscustomobject]@{
            Descripcion = $v['DriverDesc']
            Coincide    = $v['MatchingDeviceId']
            Fecha       = $v['DriverDate']
            Vram        = $v['HardwareInformation.qwMemorySize']
        }
    }
    $controladores = @(Get-Cim -Clase Win32_VideoController -Propiedades Name, DriverVersion, DriverDate, PNPDeviceID, InfFilename, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, AdapterRAM, ConfigManagerErrorCode)
    foreach ($g in $controladores) {
        $drv = $drivers | Where-Object { $_.Coincide -and "$($g.PNPDeviceID)".StartsWith($_.Coincide, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if (-not $drv) { $drv = $drivers | Where-Object { $_.Descripcion -eq $g.Name } | Select-Object -First 1 }
        $fecha = $null
        if ($drv -and $drv.Fecha) {
            $f = [datetime]::MinValue
            if ([datetime]::TryParseExact($drv.Fecha, 'M-d-yyyy', $script:Invariante, 'None', [ref]$f)) { $fecha = $f }
        }
        if (-not $fecha -and $g.DriverDate) { $fecha = $g.DriverDate.ToUniversalTime().Date }
        $vram = $null
        if ($drv -and $drv.Vram) { $vram = ConvertTo-GB ([double]$drv.Vram) 1 }
        $resolucion = $null
        if ($g.CurrentHorizontalResolution) { $resolucion = '{0}x{1} @ {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate }
        [pscustomobject][ordered]@{
            Nombre          = $g.Name
            DriverVersion   = $g.DriverVersion
            DriverFecha     = ConvertTo-TextoFecha $fecha -SoloFecha
            VramGB          = $vram
            Resolucion      = $resolucion
            DriverGenerico  = ($g.InfFilename -eq 'display.inf' -or $g.Name -match '(?i)basic display|b.sico de microsoft')
            CodigoError     = $g.ConfigManagerErrorCode
        }
    }
}

function Get-DiscosKit {
    $ns = 'root/Microsoft/Windows/Storage'
    $particiones = @(Get-Cim -Namespace $ns -Clase MSFT_Partition -Propiedades DiskNumber, DriveLetter)
    $discos = @(Get-Cim -Namespace $ns -Clase MSFT_PhysicalDisk -Propiedades ObjectId, DeviceId, FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size, FirmwareVersion, SpindleSpeed)
    $letraSistema = "$env:SystemDrive".Substring(0, 1)
    # El USB del kit aparece entre los discos: se marca para no dar avisos sobre él como si fuera del cliente.
    $raizKit = if ($script:Ctx.RaizKit) { [IO.Path]::GetPathRoot([string]$script:Ctx.RaizKit) } else { '' }
    $letraKit = if ($raizKit -match '^([A-Za-z]):') { $Matches[1].ToUpperInvariant() } else { '' }
    $leerDesgaste = $script:Ctx.Admin.Elevado
    if (-not $leerDesgaste) { Add-Incompleto -Parte 'Desgaste y temperatura de discos' }
    foreach ($pd in ($discos | Sort-Object { [int]$_.DeviceId })) {
        $letras = @($particiones | Where-Object { "$($_.DiskNumber)" -eq "$($pd.DeviceId)" -and [int][char]$_.DriveLetter -gt 0 } |
                ForEach-Object { [string][char]$_.DriveLetter } | Sort-Object)
        $medio = $script:TipoMedio[[int]$pd.MediaType]
        if ([int]$pd.MediaType -eq 0) {
            if ($pd.SpindleSpeed -eq 0) { $medio = 'SSD (deducido)' }
            elseif ($pd.SpindleSpeed -gt 0 -and $pd.SpindleSpeed -lt [uint32]::MaxValue) { $medio = 'HDD (deducido)' }
        }
        $operativo = @($pd.OperationalStatus | ForEach-Object { $e = $script:EstadoOperativo[[int]$_]; if ($e) { $e } else { "código $_" } }) -join ', '
        $fila = [ordered]@{
            Disco            = [int]$pd.DeviceId
            Modelo           = "$($pd.FriendlyName)".Trim()
            Tipo             = $medio
            Bus              = $(if ($script:TipoBus[[int]$pd.BusType]) { $script:TipoBus[[int]$pd.BusType] } else { "código $($pd.BusType)" })
            TamanoGB         = ConvertTo-GB $pd.Size 0
            Salud            = $(if ($script:SaludDisco[[int]$pd.HealthStatus]) { $script:SaludDisco[[int]$pd.HealthStatus] } else { "código $($pd.HealthStatus)" })
            EstadoOperativo  = $operativo
            Firmware         = "$($pd.FirmwareVersion)".Trim()
            Letras           = ($letras -join ' ')
            Sistema          = ($letras -contains $letraSistema)
            # El disco de Windows nunca cuenta como del kit (en el PC del técnico el kit puede estar ahí).
            DelKit           = [bool]($letraKit -and $letras -contains $letraKit -and $letras -notcontains $letraSistema)
            DesgastePct      = $null
            TemperaturaC     = $null
            TemperaturaMaxC  = $null
            HorasEncendido   = $null
            ErroresLecturaNC = $null
            ErroresEscrituraNC = $null
            Smart            = $(if ($leerDesgaste) { 'sin datos' } else { 'requiere admin' })
        }
        if ($leerDesgaste) {
            $r = Invoke-Paso "confiabilidad disco $($pd.DeviceId)" {
                Get-CimAssociatedInstance -InputObject $pd -ResultClassName MSFT_StorageReliabilityCounter -OperationTimeoutSec ([int]$script:Ctx.Config.cim_timeout_seg) -ErrorAction Stop
            }
            # Detrás de Intel RST/VMD (bus RAID) Windows entrega valores de relleno: temperatura fija
            # (60 °C), máxima 0, desgaste 0 y sin horas. Sin horas ni máxima, los contadores no sirven.
            if ($r -and -not $r.PowerOnHours -and -not $r.TemperatureMax) {
                $fila.Smart = 'no confiable (el controlador no entrega SMART a Windows)'
                $r = $null
            }
            if ($r) {
                $fila.Smart = 'OK'
                $fila.DesgastePct = $r.Wear
                $fila.TemperaturaC = $r.Temperature
                $fila.TemperaturaMaxC = $r.TemperatureMax
                $fila.HorasEncendido = $r.PowerOnHours
                $fila.ErroresLecturaNC = $r.ReadErrorsUncorrected
                $fila.ErroresEscrituraNC = $r.WriteErrorsUncorrected
            }
        }
        [pscustomobject]$fila
    }
}

function Get-BateriaKit {
    $baterias = @(Get-Cim -Clase Win32_Battery -Propiedades DeviceID, Name, EstimatedChargeRemaining)
    if ($baterias.Count -eq 0) { return }
    $html = Join-Path $script:Ctx.CarpetaCliente 'bateria.html'
    $xml = Join-Path $script:Ctx.CarpetaCliente 'bateria.xml'
    $powercfg = Get-RutaSistema 'powercfg.exe'
    $r = Invoke-Externo -Exe $powercfg -Argumentos "/batteryreport /output `"$html`""
    if ($r.Codigo -ne 0) { Write-LogKit -Nivel AVISO -Mensaje "powercfg /batteryreport (html) terminó con código $($r.Codigo): $($r.Error.Trim())" }
    $r = Invoke-Externo -Exe $powercfg -Argumentos "/batteryreport /xml /output `"$xml`""
    if ($r.Codigo -ne 0 -or -not (Test-Path -LiteralPath $xml)) { throw "powercfg /batteryreport /xml falló (código $($r.Codigo)): $($r.Error.Trim())" }
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($xml)
    foreach ($b in $doc.SelectNodes("//*[local-name()='Batteries']/*[local-name()='Battery']")) {
        $valor = { param($n) $nodo = $b.SelectSingleNode("*[local-name()='$n']"); if ($nodo) { $nodo.InnerText.Trim() } else { $null } }
        $diseno = [double](& $valor 'DesignCapacity')
        $completa = [double](& $valor 'FullChargeCapacity')
        $salud = $null
        if ($diseno -gt 0) { $salud = [math]::Round(100 * $completa / $diseno, 1) }
        [pscustomobject][ordered]@{
            Id               = & $valor 'Id'
            Fabricante       = & $valor 'Manufacturer'
            Quimica          = & $valor 'Chemistry'
            DisenoMWh        = $diseno
            CargaCompletaMWh = $completa
            SaludPct         = $salud
            Ciclos           = $(if ("$(& $valor 'CycleCount')" -match '^\d+$') { [int](& $valor 'CycleCount') } else { $null })
            CargaActualPct   = $baterias[0].EstimatedChargeRemaining
        }
    }
}

function Test-AlertasHardware {
    $d = $script:Ctx.Datos.hardware
    if ($d.Ram) {
        $min = Get-Umbral 'ram_min_gb'
        if ($d.Ram.TotalGB -gt 0 -and $d.Ram.TotalGB -lt $min) {
            Add-Alerta -Severidad AVISO -Codigo 'HW-RAM-POCA' -Texto "RAM total $(Format-Numero $d.Ram.TotalGB 1) GB (menos de $min GB)"
        }
        if ($d.Ram.CantidadModulos -eq 1 -and $d.Ram.Slots -ge 2) {
            Add-Alerta -Severidad AVISO -Codigo 'HW-RAM-CANAL' -Texto "RAM en canal simple: 1 módulo y $($d.Ram.Slots) slots reportados (si una es soldada, el slot libre se puede completar)"
        }
        foreach ($m in $d.Ram.Modulos) {
            if ($m.VelocidadMTs -and $m.ConfiguradaMTs -and $m.ConfiguradaMTs -lt $m.VelocidadMTs) {
                Add-Alerta -Severidad INFO -Codigo 'HW-RAM-VEL' -Texto "RAM $($m.Slot) a $($m.ConfiguradaMTs) de $($m.VelocidadMTs) MT/s nominales (en notebooks suele ser límite de la plataforma)"
            }
        }
    }
    foreach ($disco in @($d.Discos)) {
        if (-not $disco) { continue }
        if ($disco.Salud -ne 'Healthy') {
            Add-Alerta -Severidad CRITICO -Codigo 'HW-DISCO-SALUD' -Texto "Disco $($disco.Disco) ($($disco.Modelo)) con salud $($disco.Salud) (estado: $($disco.EstadoOperativo))"
        } elseif ($disco.EstadoOperativo -and $disco.EstadoOperativo -ne 'OK') {
            Add-Alerta -Severidad AVISO -Codigo 'HW-DISCO-ESTADO' -Texto "Disco $($disco.Disco) ($($disco.Modelo)) con estado operativo: $($disco.EstadoOperativo)"
        }
        if ($disco.Sistema -and $disco.Tipo -like 'HDD*') {
            Add-Alerta -Severidad AVISO -Codigo 'HW-DISCO-HDD' -Texto "Windows está en disco mecánico ($($disco.Modelo)): candidato a cambio por SSD"
        }
        if ($null -ne $disco.DesgastePct -and $disco.DesgastePct -ge (Get-Umbral 'ssd_desgaste_pct')) {
            Add-Alerta -Severidad AVISO -Codigo 'HW-DISCO-DESGASTE' -Texto "Disco $($disco.Disco) ($($disco.Modelo)) con $($disco.DesgastePct) % de vida útil consumida"
        }
        if ($disco.TemperaturaC -and $disco.TemperaturaC -ge (Get-Umbral 'disco_temp_c')) {
            Add-Alerta -Severidad AVISO -Codigo 'HW-DISCO-TEMP' -Texto "Disco $($disco.Disco) ($($disco.Modelo)) a $($disco.TemperaturaC) °C"
        }
        $cdi = Find-SmartCrystal -Lista $d['SmartCrystal'] -Disco $disco
        if ($disco.Smart -like 'no confiable*' -and -not $cdi -and -not $disco.DelKit) {
            $quien = "Disco $($disco.Disco) ($($disco.Modelo), bus $($disco.Bus))"
            $texto = if ($d['DiscosTxt']) { "${quien}: ni Windows ni CrystalDiskInfo leen su SMART (pasa con pendrives y algunas cajas USB); no se pudo revisar su salud" }
            else { "${quien}: Windows no recibe SMART del controlador; con admin, el kit lo lee con CrystalDiskInfo" }
            Add-Alerta -Severidad INFO -Codigo 'HW-DISCO-SMART' -Texto $texto
        }
        if ($cdi) {
            # SMART leído por CrystalDiskInfo (discos.txt): vale aunque Windows no lo reciba.
            $nombre = "Disco $($disco.Disco) ($($disco.Modelo)$(if ($disco.Letras) { ', ' + $disco.Letras }))"
            if ($cdi.ErroresMedio -gt 0) {
                Add-Alerta -Severidad CRITICO -Codigo 'HW-SMART-MEDIO' -Texto "$nombre con $($cdi.ErroresMedio) errores de integridad de datos según SMART (aunque la salud diga '$($cdi.SaludTexto) $($cdi.SaludPct) %'): respaldar ya y planificar el cambio"
            }
            if ($cdi.AvisoCritico -gt 0) { Add-Alerta -Severidad CRITICO -Codigo 'HW-SMART-AVISO' -Texto "$nombre reporta un aviso crítico SMART (código $($cdi.AvisoCritico)): respaldar ya" }
            if ($cdi.Reasignados -gt 0 -or $cdi.Pendientes -gt 0 -or $cdi.NoCorregibles -gt 0) {
                Add-Alerta -Severidad CRITICO -Codigo 'HW-SMART-SECTORES' -Texto "$nombre con sectores dañados según SMART (reasignados $($cdi.Reasignados), pendientes $($cdi.Pendientes), no corregibles $($cdi.NoCorregibles)): respaldar ya"
            }
            if ($null -ne $cdi.UsoPct -and $cdi.UsoPct -ge (Get-Umbral 'ssd_desgaste_pct')) { Add-Alerta -Severidad AVISO -Codigo 'HW-DISCO-DESGASTE' -Texto "$nombre con $($cdi.UsoPct) % de vida útil consumida (SMART)" }
            if ($null -ne $cdi.RepuestoPct -and $cdi.RepuestoPct -lt 20) { Add-Alerta -Severidad AVISO -Codigo 'HW-SMART-REPUESTO' -Texto "$nombre con solo $($cdi.RepuestoPct) % de bloques de repuesto disponibles (SMART)" }
            if ($cdi.TemperaturaC -and $cdi.TemperaturaC -ge (Get-Umbral 'disco_temp_c')) { Add-Alerta -Severidad AVISO -Codigo 'HW-DISCO-TEMP' -Texto "$nombre a $($cdi.TemperaturaC) °C (SMART)" }
        }
        if ($disco.ErroresLecturaNC -gt 0 -or $disco.ErroresEscrituraNC -gt 0) {
            Add-Alerta -Severidad CRITICO -Codigo 'HW-DISCO-ERRORES' -Texto "Disco $($disco.Disco) ($($disco.Modelo)) con errores no corregidos (lectura $($disco.ErroresLecturaNC), escritura $($disco.ErroresEscrituraNC))"
        }
    }
    $meses = Get-Umbral 'gpu_driver_meses'
    foreach ($g in @($d.Gpu)) {
        if (-not $g) { continue }
        if ($g.DriverGenerico) {
            Add-Alerta -Severidad AVISO -Codigo 'HW-GPU-GENERICO' -Texto "GPU con driver genérico de Microsoft ($($g.Nombre)): falta el driver del fabricante"
        } elseif ($g.DriverFecha) {
            $fecha = [datetime]::ParseExact($g.DriverFecha, 'yyyy-MM-dd', $script:Invariante)
            if ($fecha -lt (Get-Date).AddMonths(-$meses)) {
                Add-Alerta -Severidad INFO -Codigo 'HW-GPU-DRIVER' -Texto "Driver de $($g.Nombre) del $($g.DriverFecha) (más de $meses meses)"
            }
        }
    }
    foreach ($b in @($d.Baterias)) {
        if (-not $b -or $null -eq $b.SaludPct) { continue }
        if ($b.SaludPct -lt (Get-Umbral 'bateria_critico_pct')) {
            Add-Alerta -Severidad CRITICO -Codigo 'HW-BATERIA' -Texto "Batería al $(Format-Numero $b.SaludPct 1) % de su capacidad de diseño ($($b.CargaCompletaMWh) de $($b.DisenoMWh) mWh): cambio recomendado"
        } elseif ($b.SaludPct -lt (Get-Umbral 'bateria_aviso_pct')) {
            Add-Alerta -Severidad AVISO -Codigo 'HW-BATERIA' -Texto "Batería al $(Format-Numero $b.SaludPct 1) % de su capacidad de diseño ($($b.CargaCompletaMWh) de $($b.DisenoMWh) mWh)"
        }
    }
}

function Format-ResumenHardware {
    $d = $script:Ctx.Datos.hardware
    foreach ($c in @($d.Cpu)) { if ($c) { "CPU        : $($c.Nombre) | $($c.Nucleos) núcleos / $($c.Hilos) hilos | máx $($c.MaxMHz) MHz | L3 $($c.L3MB) MB" } }
    if ($d.Ram) {
        "RAM        : $(Format-Numero $d.Ram.TotalGB 0) GB instalados ($(Format-Numero $d.Ram.UtilizableGB 1) GB utilizables) | $($d.Ram.CantidadModulos) módulos, $($d.Ram.Slots) slots según SMBIOS (en notebooks suele venir inflado)"
        foreach ($m in $d.Ram.Modulos) { "             - $($m.Slot): $($m.CapacidadGB) GB $($m.Tipo) $($m.VelocidadMTs) MT/s (config. $($m.ConfiguradaMTs)) $($m.Fabricante) $($m.NumeroParte)" }
    }
    foreach ($g in @($d.Gpu)) {
        if (-not $g) { continue }
        $vram = if ($g.VramGB) { "$($g.VramGB) GB" } else { 'compartida' }
        "GPU        : $($g.Nombre) | driver $($g.DriverVersion) del $($g.DriverFecha) | VRAM $vram | $($g.Resolucion)"
    }
    foreach ($k in @($d.Discos)) {
        if (-not $k) { continue }
        $extra = " | SMART: $($k.Smart)"
        if ($k.Smart -eq 'OK') {
            $partes = @()
            if ($null -ne $k.DesgastePct) { $partes += "desgaste $($k.DesgastePct) %" }
            if ($k.TemperaturaC) { $partes += "$($k.TemperaturaC) °C" }
            if ($k.HorasEncendido) { $partes += "$(Format-Numero $k.HorasEncendido 0) h encendido" }
            if ($partes) { $extra = ' | ' + ($partes -join ' | ') }
        }
        "Disco $($k.Disco)    : $($k.Modelo) | $($k.Tipo) $($k.Bus) | $($k.TamanoGB) GB | salud $($k.Salud) | letras $($k.Letras)$(if ($k.Sistema) { ' (sistema)' })$(if ($k.DelKit) { ' (USB del kit)' })$extra"
        $c = Find-SmartCrystal -Lista $d['SmartCrystal'] -Disco $k
        if ($c) {
            $partes = @("salud $($c.SaludTexto) $($c.SaludPct) %")
            if ($c.TemperaturaC) { $partes += "$($c.TemperaturaC) °C" }
            if ($c.HorasEncendido) { $partes += "$(Format-Numero $c.HorasEncendido 0) h" }
            if ($null -ne $c.UsoPct) { $partes += "uso $($c.UsoPct) %" }
            if ($null -ne $c.ErroresMedio) { $partes += "errores de medio $($c.ErroresMedio)" }
            if ($null -ne $c.Reasignados) { $partes += "reasignados $($c.Reasignados) / pendientes $($c.Pendientes) / no corregibles $($c.NoCorregibles)" }
            if ($null -ne $c.ApagadosNoSeguros) { $partes += "apagados no seguros $($c.ApagadosNoSeguros)" }
            "             CrystalDiskInfo: $($partes -join ' | ')"
        }
    }
    if ($d.Contains('DiscosTxt')) { "SMART      : $(if ($d.DiscosTxt) { 'informe de CrystalDiskInfo en discos.txt' } else { 'sin discos.txt (requiere admin y CrystalDiskInfo en herramientas)' })" }
    foreach ($b in @($d.Baterias)) {
        if ($b) { "Batería    : $($b.Fabricante) $($b.Id) | salud $(Format-Numero $b.SaludPct 1) % ($($b.CargaCompletaMWh)/$($b.DisenoMWh) mWh) | $($b.Ciclos) ciclos | carga actual $($b.CargaActualPct) % | informe: bateria.html" }
    }
    if (-not $d.Baterias) { 'Batería    : no tiene (o no se pudo leer)' }
}
