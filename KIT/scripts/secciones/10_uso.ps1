# 10 Uso actual: RAM libre/usada, top procesos por RAM y por CPU (muestra configurable, 5 s).
# La CPU se mide con contadores crudos de WMI (Win32_PerfRawData), que no dependen del idioma y
# ven también los procesos protegidos. Los procesos se agrupan por nombre (chrome x30 = una fila).
# No se guardan líneas de comando (pueden traer tokens o URLs).

function Get-DatosUso {
    $d = [ordered]@{}
    $d.Memoria = Invoke-Paso 'memoria' {
        $os = Get-Cim -Clase Win32_OperatingSystem -Propiedades TotalVisibleMemorySize, FreePhysicalMemory, TotalVirtualMemorySize, FreeVirtualMemory
        $total = [double]$os.TotalVisibleMemorySize * 1KB
        $libre = [double]$os.FreePhysicalMemory * 1KB
        $commitTotal = [double]$os.TotalVirtualMemorySize * 1KB
        $commitLibre = [double]$os.FreeVirtualMemory * 1KB
        [pscustomobject][ordered]@{
            TotalGB          = ConvertTo-GB $total 1
            UsadaGB          = ConvertTo-GB ($total - $libre) 1
            LibreGB          = ConvertTo-GB $libre 1
            UsoPct           = [math]::Round(100 * ($total - $libre) / $total, 1)
            ComprometidaGB   = ConvertTo-GB ($commitTotal - $commitLibre) 1
            LimiteCommitGB   = ConvertTo-GB $commitTotal 1
        }
    }
    $top = [int]$script:Ctx.Config.uso.top_procesos
    $d.TopRam = Invoke-Paso 'procesos por RAM' {
        @(Get-Process | Group-Object ProcessName | ForEach-Object {
                [pscustomobject][ordered]@{
                    Proceso    = $_.Name
                    Instancias = $_.Count
                    RamMB      = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 0)
                    PrivadaMB  = [math]::Round((($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB, 0)
                }
            } | Sort-Object RamMB -Descending | Select-Object -First $top)
    }
    Add-Tabla -Nombre 'top_ram' -Filas $d.TopRam
    $d.Cpu = Invoke-Paso 'procesos por CPU' { Get-MuestraCpu -Segundos ([int]$script:Ctx.Config.uso.muestra_cpu_seg) -Top $top }
    if ($d.Cpu) { Add-Tabla -Nombre 'top_cpu' -Filas $d.Cpu.Top }
    $d
}

function Get-MuestraCpu {
    param([int]$Segundos = 5, [int]$Top = 15)
    $props = 'Name', 'IDProcess', 'PercentProcessorTime', 'Timestamp_Sys100NS'
    $a = @(Get-Cim -Clase Win32_PerfRawData_PerfProc_Process -Propiedades $props)
    # El avance va en la barra de progreso para no descuadrar la línea de la sección.
    for ($s = 0; $s -lt $Segundos; $s++) {
        Show-Progreso -Actividad 'Uso actual' -Estado ('Muestra de CPU: {0} de {1} s' -f $s, $Segundos) -Porcentaje ([int](100 * $s / $Segundos))
        Start-Sleep -Seconds 1
    }
    Show-Progreso -Actividad 'Uso actual' -Estado 'listo' -Terminado
    $b = @(Get-Cim -Clase Win32_PerfRawData_PerfProc_Process -Propiedades $props)
    $nucleos = [Environment]::ProcessorCount
    $antes = @{}
    foreach ($p in $a) { $antes["$($p.Name)|$($p.IDProcess)"] = $p }
    $totalA = $a | Where-Object Name -EQ '_Total' | Select-Object -First 1
    $totalB = $b | Where-Object Name -EQ '_Total' | Select-Object -First 1
    $dt = [double]$totalB.Timestamp_Sys100NS - [double]$totalA.Timestamp_Sys100NS
    if ($dt -le 0) { throw 'La muestra de CPU no avanzó en el tiempo' }
    $medidas = foreach ($p in $b) {
        if ($p.Name -eq '_Total') { continue }
        $prev = $antes["$($p.Name)|$($p.IDProcess)"]
        if (-not $prev) { continue }
        $pct = 100 * ([double]$p.PercentProcessorTime - [double]$prev.PercentProcessorTime) / $dt / $nucleos
        # 0.0 y no 0: con un entero PowerShell elige Max(int, int) y redondea el porcentaje.
        [pscustomobject]@{ Nombre = ($p.Name -replace '#\d+$', ''); Pct = [math]::Max(0.0, $pct) }
    }
    $idle = ($medidas | Where-Object Nombre -EQ 'Idle' | Measure-Object Pct -Sum).Sum
    $filas = @($medidas | Where-Object Nombre -NE 'Idle' | Group-Object Nombre | ForEach-Object {
            [pscustomobject][ordered]@{
                Proceso    = $_.Name
                Instancias = $_.Count
                CpuPct     = [math]::Round(($_.Group | Measure-Object Pct -Sum).Sum, 1)
            }
        } | Sort-Object CpuPct -Descending | Select-Object -First $Top)
    [pscustomobject][ordered]@{
        MuestraSeg = $Segundos
        Nucleos    = $nucleos
        UsoTotalPct = [math]::Round([math]::Max(0.0, 100.0 - $idle), 1)
        Top        = $filas
    }
}

function Test-AlertasUso {
    $d = $script:Ctx.Datos.uso
    if ($d.Memoria -and $d.Memoria.UsoPct -gt (Get-Umbral 'ram_uso_pct')) {
        $quien = @($d.TopRam | Select-Object -First 3 | ForEach-Object { "$($_.Proceso) $(Format-Numero ($_.RamMB / 1024) 1) GB" }) -join ', '
        Add-Alerta -Severidad AVISO -Codigo 'USO-RAM' -Texto "RAM en uso al $(Format-Numero $d.Memoria.UsoPct 0) % ($(Format-Numero $d.Memoria.UsadaGB 1) de $(Format-Numero $d.Memoria.TotalGB 1) GB). Más pesados: $quien"
    }
    if ($d.Cpu) {
        $umbral = Get-Umbral 'proceso_cpu_pct'
        $altos = @($d.Cpu.Top | Where-Object { $_.CpuPct -gt $umbral } | ForEach-Object { "$($_.Proceso) $(Format-Numero $_.CpuPct 0) %" })
        if ($altos.Count -gt 0) {
            Add-Alerta -Severidad INFO -Codigo 'USO-CPU' -Texto "Procesos sobre $umbral % de CPU durante la muestra de $($d.Cpu.MuestraSeg) s: $($altos -join ', ')"
        }
    }
}

function Format-ResumenUso {
    $d = $script:Ctx.Datos.uso
    if ($d.Memoria) { "RAM        : $(Format-Numero $d.Memoria.UsadaGB 1) de $(Format-Numero $d.Memoria.TotalGB 1) GB en uso ($(Format-Numero $d.Memoria.UsoPct 0) %) | libre $(Format-Numero $d.Memoria.LibreGB 1) GB | comprometida $(Format-Numero $d.Memoria.ComprometidaGB 1) de $(Format-Numero $d.Memoria.LimiteCommitGB 1) GB" }
    if ($d.Cpu) { "CPU        : $(Format-Numero $d.Cpu.UsoTotalPct 0) % de uso total en la muestra de $($d.Cpu.MuestraSeg) s ($($d.Cpu.Nucleos) hilos)" }
    $ram = @($d.TopRam | Select-Object -First 10)
    $cpu = @(if ($d.Cpu) { $d.Cpu.Top | Select-Object -First 10 })
    '             {0,-38} {1,-30}' -f 'Top RAM (MB, instancias)', 'Top CPU (%)'
    for ($i = 0; $i -lt [math]::Max($ram.Count, $cpu.Count); $i++) {
        $izq = if ($i -lt $ram.Count) { '{0} {1:N0} (x{2})' -f $ram[$i].Proceso, $ram[$i].RamMB, $ram[$i].Instancias } else { '' }
        $der = if ($i -lt $cpu.Count) { '{0} {1}' -f $cpu[$i].Proceso, (Format-Numero $cpu[$i].CpuPct 1) } else { '' }
        '             {0,-38} {1,-30}' -f $izq, $der
    }
}
