# 13 Estabilidad: en el registro System de los últimos N días (config: eventos_dias), cuenta
# apagados inesperados (Kernel-Power 41), pantallazos azules (BugCheck 1001) y errores de disco
# (disk 7/51/153, Ntfs 55). Solo se guardan fecha, tipo y código: nunca el mensaje completo.

$script:NombreBugcheck = @{
    '0x0000000a' = 'IRQL_NOT_LESS_OR_EQUAL'; '0x0000001a' = 'MEMORY_MANAGEMENT'; '0x0000001e' = 'KMODE_EXCEPTION_NOT_HANDLED'
    '0x0000003b' = 'SYSTEM_SERVICE_EXCEPTION'; '0x00000050' = 'PAGE_FAULT_IN_NONPAGED_AREA'; '0x0000007a' = 'KERNEL_DATA_INPAGE_ERROR'
    '0x0000007e' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'; '0x0000009f' = 'DRIVER_POWER_STATE_FAILURE'; '0x000000d1' = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'
    '0x000000ef' = 'CRITICAL_PROCESS_DIED'; '0x00000101' = 'CLOCK_WATCHDOG_TIMEOUT'; '0x00000116' = 'VIDEO_TDR_FAILURE'
    '0x00000117' = 'VIDEO_TDR_TIMEOUT_DETECTED'; '0x00000124' = 'WHEA_UNCORRECTABLE_ERROR'; '0x00000133' = 'DPC_WATCHDOG_VIOLATION'
    '0x00000139' = 'KERNEL_SECURITY_CHECK_FAILURE'; '0x00000154' = 'UNEXPECTED_STORE_EXCEPTION'; '0x000000c2' = 'BAD_POOL_CALLER'
    '0x00000019' = 'BAD_POOL_HEADER'; '0x000000f4' = 'CRITICAL_OBJECT_TERMINATION'; '0x00000077' = 'KERNEL_STACK_INPAGE_ERROR'
}

function Get-EventosSistema {
    # Lee el registro System con XPath (no lanza error si no hay eventos, a diferencia de Get-WinEvent).
    param(
        [Parameter(Mandatory)][string]$Proveedores,
        [Parameter(Mandatory)][int[]]$Ids,
        [Parameter(Mandatory)][int]$Dias,
        [int]$Maximo = 500
    )
    $ms = [int64]$Dias * 86400000
    $filtroIds = ($Ids | ForEach-Object { "EventID=$_" }) -join ' or '
    $xpath = "*[System[($Proveedores) and ($filtroIds) and TimeCreated[timediff(@SystemTime) <= $ms]]]"
    $consulta = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery('System', [System.Diagnostics.Eventing.Reader.PathType]::LogName, $xpath)
    $consulta.ReverseDirection = $true
    $lector = New-Object System.Diagnostics.Eventing.Reader.EventLogReader($consulta)
    try {
        $n = 0
        while ($n -lt $Maximo -and $null -ne ($e = $lector.ReadEvent())) {
            try {
                [pscustomobject]@{ Id = $e.Id; Fecha = $e.TimeCreated; Proveedor = $e.ProviderName; Datos = @($e.Properties | ForEach-Object { $_.Value }) }
            } finally { $e.Dispose() }
            $n++
        }
    } finally { $lector.Dispose() }
}

function Get-DatosEstabilidad {
    $dias = [int](Get-Umbral 'eventos_dias')
    $filas = New-Object System.Collections.Generic.List[object]

    $apagados = @(Invoke-Paso 'Kernel-Power 41' { Get-EventosSistema -Proveedores "Provider[@Name='Microsoft-Windows-Kernel-Power']" -Ids 41 -Dias $dias })
    foreach ($e in ($apagados | Where-Object { $_ })) {
        $codigo = if ($e.Datos.Count -gt 0) { [int64]$e.Datos[0] } else { 0 }
        $filas.Add([pscustomobject][ordered]@{ Fecha = ConvertTo-TextoFecha $e.Fecha; Tipo = 'Apagado inesperado (Kernel-Power 41)'; Detalle = $(if ($codigo -ne 0) { 'bugcheck 0x{0:x8}' -f $codigo } else { '' }) })
    }

    $bsod = @(Invoke-Paso 'BugCheck 1001' { Get-EventosSistema -Proveedores "Provider[@Name='Microsoft-Windows-WER-SystemErrorReporting']" -Ids 1001 -Dias $dias })
    $codigos = New-Object System.Collections.Generic.List[string]
    foreach ($e in ($bsod | Where-Object { $_ })) {
        $codigo = ''
        if ($e.Datos.Count -gt 0 -and "$($e.Datos[0])" -match '^(0x[0-9a-fA-F]+)') { $codigo = $Matches[1].ToLower() }
        $nombre = $script:NombreBugcheck[$codigo]
        $texto = if ($nombre) { "$codigo $nombre" } else { $codigo }
        $codigos.Add($texto)
        $filas.Add([pscustomobject][ordered]@{ Fecha = ConvertTo-TextoFecha $e.Fecha; Tipo = 'Pantallazo azul (BugCheck 1001)'; Detalle = $texto })
    }

    $disco = @(Invoke-Paso 'errores de disco' {
            Get-EventosSistema -Proveedores "Provider[@Name='disk' or @Name='Ntfs' or @Name='Microsoft-Windows-Ntfs']" -Ids 7, 51, 153, 55 -Dias $dias
        })
    foreach ($e in ($disco | Where-Object { $_ })) {
        # disk 7/51/153 traen el dispositivo (\Device\Harddisk1\DR1) en el primer dato; Ntfs 55 trae el volumen.
        $dispositivo = if ($e.Datos.Count -gt 0) { "$($e.Datos[0])" } else { '' }
        if ($dispositivo.Length -gt 60) { $dispositivo = $dispositivo.Substring(0, 60) }
        $filas.Add([pscustomobject][ordered]@{ Fecha = ConvertTo-TextoFecha $e.Fecha; Tipo = "Error de disco ($($e.Proveedor) $($e.Id))"; Detalle = $dispositivo })
    }

    $todas = @($filas | Sort-Object Fecha -Descending)
    Add-Tabla -Nombre 'eventos' -Filas $todas
    [ordered]@{
        Dias              = $dias
        Apagados          = @($apagados | Where-Object { $_ }).Count
        UltimoApagado     = $(if ($apagados.Count -and $apagados[0]) { ConvertTo-TextoFecha $apagados[0].Fecha } else { $null })
        Pantallazos       = @($bsod | Where-Object { $_ }).Count
        CodigosPantallazo = @($codigos | Group-Object | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } })
        ErroresDisco      = @($disco | Where-Object { $_ }).Count
        Eventos           = $todas
    }
}

function Test-AlertasEstabilidad {
    $d = $script:Ctx.Datos.estabilidad
    if ($d.Pantallazos -gt 0) {
        $ultimo = ($d.Eventos | Where-Object { $_.Tipo -like 'Pantallazo*' } | Select-Object -First 1).Fecha
        Add-Alerta -Severidad AVISO -Codigo 'EST-BSOD' -Texto "$($d.Pantallazos) pantallazos azules en $($d.Dias) días (último $ultimo): $($d.CodigosPantallazo -join ', ')"
    }
    if ($d.Apagados -ge (Get-Umbral 'apagados_inesperados')) {
        Add-Alerta -Severidad AVISO -Codigo 'EST-APAGADOS' -Texto "$($d.Apagados) apagados inesperados (Kernel-Power 41) en $($d.Dias) días (último $($d.UltimoApagado)): corte de luz, botón mantenido, batería o inestabilidad"
    }
    if ($d.ErroresDisco -gt 0) {
        # \Device\HarddiskN corresponde al disco físico N: si la sección 2 corrió, se agrega modelo y letras.
        $discos = @()
        if ($script:Ctx.Datos['hardware'] -and $script:Ctx.Datos.hardware.Discos) { $discos = @($script:Ctx.Datos.hardware.Discos) }
        $resumen = @($d.Eventos | Where-Object { $_.Tipo -like 'Error de disco*' } | Group-Object Tipo, Detalle | ForEach-Object {
                $texto = $_.Name -replace ', ', ' en '
                if ($_.Name -match 'Harddisk(\d+)') {
                    $n = [int]$Matches[1]
                    $k = $discos | Where-Object { $_.Disco -eq $n } | Select-Object -First 1
                    if ($k) { $texto += " = disco $n $($k.Modelo) ($($k.Letras))" }
                }
                "$texto x$($_.Count)"
            }) -join '; '
        Add-Alerta -Severidad CRITICO -Codigo 'EST-DISCO' -Texto "$($d.ErroresDisco) errores de disco en $($d.Dias) días: $resumen"
    }
}

function Format-ResumenEstabilidad {
    $d = $script:Ctx.Datos.estabilidad
    "Últimos $($d.Dias) días: $($d.Apagados) apagados inesperados | $($d.Pantallazos) pantallazos azules | $($d.ErroresDisco) errores de disco"
    foreach ($e in ($d.Eventos | Select-Object -First 15)) { "             $($e.Fecha)  $($e.Tipo)$(if ($e.Detalle) { ' - ' + $e.Detalle })" }
    if (@($d.Eventos).Count -gt 15) { '             (lista completa en csv\13_eventos.csv)' }
}
