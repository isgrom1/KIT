# 05 Energía: plan activo y lista (powercfg), estado máximo/mínimo y boost del procesador AC/DC,
# modo de energía de Windows 11, hibernación y tamaño de hiberfil.sys, inicio rápido y pagefile.
# powercfg se lee por GUID y valores hex: su texto viene traducido según el idioma del equipo.

$script:PlanesEstandar = @{
    '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Equilibrado'
    '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Alto rendimiento'
    'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Economizador'
    'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Máximo rendimiento'
}
$script:ModoEnergia = @{
    '00000000-0000-0000-0000-000000000000' = 'Equilibrado'
    '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Mejor eficiencia energética'
    '3af9b8d9-7c97-431d-ad78-34a8bfea439f' = 'Mejor rendimiento (equilibrado+)'
    'ded574b5-45a0-4f42-8737-46345c09c238' = 'Mejor rendimiento'
}
$script:Boost = @{ 0 = 'Desactivado'; 1 = 'Activado'; 2 = 'Agresivo'; 3 = 'Activado eficiente'; 4 = 'Agresivo eficiente'; 5 = 'Agresivo en garantizado'; 6 = 'Agresivo eficiente en garantizado' }

function Get-ValorEnergia {
    # Devuelve los índices AC y DC de un ajuste del plan activo (/qh incluye los ocultos, como el boost).
    param([Parameter(Mandatory)][string]$Subgrupo, [Parameter(Mandatory)][string]$Ajuste)
    $r = Invoke-Externo -Exe (Get-RutaSistema 'powercfg.exe') -Argumentos "/qh SCHEME_CURRENT $Subgrupo $Ajuste" -TimeoutSeg 20
    if ($r.Codigo -ne 0) { throw "powercfg /qh $Ajuste devolvió $($r.Codigo): $($r.Salida.Trim()) $($r.Error.Trim())" }
    $hex = @([regex]::Matches($r.Salida, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    [pscustomobject][ordered]@{ AC = [Convert]::ToInt32($hex[-2], 16); DC = [Convert]::ToInt32($hex[-1], 16) }
}

function Get-DatosEnergia {
    $d = [ordered]@{}
    $powercfg = Get-RutaSistema 'powercfg.exe'
    $d.Planes = Invoke-Paso 'planes' {
        $r = Invoke-Externo -Exe $powercfg -Argumentos '/list' -TimeoutSeg 20
        foreach ($m in [regex]::Matches($r.Salida, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+?)\)(\s*\*)?')) {
            $guid = $m.Groups[1].Value.ToLower()
            [pscustomobject][ordered]@{
                Guid     = $guid
                Nombre   = $m.Groups[2].Value.Trim()
                Activo   = $m.Groups[3].Success
                Estandar = $script:PlanesEstandar.ContainsKey($guid)
            }
        }
    }
    Add-Tabla -Nombre 'planes_energia' -Filas $d.Planes
    $d.PlanActivo = @($d.Planes | Where-Object { $_ -and $_.Activo }) | Select-Object -First 1

    $d.Procesador = Invoke-Paso 'procesador' {
        $max = Get-ValorEnergia -Subgrupo SUB_PROCESSOR -Ajuste PROCTHROTTLEMAX
        $min = Get-ValorEnergia -Subgrupo SUB_PROCESSOR -Ajuste PROCTHROTTLEMIN
        $boost = Get-ValorEnergia -Subgrupo SUB_PROCESSOR -Ajuste PERFBOOSTMODE
        $nombreBoost = { param($v) if ($null -eq $v) { $null } elseif ($script:Boost.ContainsKey($v)) { $script:Boost[$v] } else { "código $v" } }
        [pscustomobject][ordered]@{
            MaxAC   = $(if ($max) { $max.AC } else { $null })
            MaxDC   = $(if ($max) { $max.DC } else { $null })
            MinAC   = $(if ($min) { $min.AC } else { $null })
            MinDC   = $(if ($min) { $min.DC } else { $null })
            BoostAC = $(if ($boost) { $boost.AC } else { $null })
            BoostDC = $(if ($boost) { $boost.DC } else { $null })
            BoostACTexto = & $nombreBoost $(if ($boost) { $boost.AC } else { $null })
            BoostDCTexto = & $nombreBoost $(if ($boost) { $boost.DC } else { $null })
        }
    }

    $d.ModoWindows = Invoke-Paso 'modo de energía' {
        $v = Get-ValoresRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
        $nombre = { param($g) if (-not $g) { $null } elseif ($script:ModoEnergia.ContainsKey("$g".ToLower())) { $script:ModoEnergia["$g".ToLower()] } else { "$g" } }
        [pscustomobject][ordered]@{ AC = & $nombre $v['ActiveOverlayAcPowerScheme']; DC = & $nombre $v['ActiveOverlayDcPowerScheme'] }
    }

    $d.Hibernacion = Invoke-Paso 'hibernación' {
        $p = Get-ValoresRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Power'
        $hiberboot = Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Nombre 'HiberbootEnabled'
        $raiz = [IO.DirectoryInfo]("$env:SystemDrive\")
        $archivos = @{}
        foreach ($f in $raiz.GetFiles()) {
            if ($f.Name -match '^(?i)(hiberfil|pagefile|swapfile)\.sys$') { $archivos[$f.Name.ToLower()] = $f.Length }
        }
        $habilitada = ($p['HibernateEnabled'] -eq 1)
        [pscustomobject][ordered]@{
            Habilitada         = $habilitada
            TipoArchivo        = switch ($p['HiberFileType']) { 1 { 'Reducido' } 2 { 'Completo' } default { $null } }
            HiberfilGB         = $(if ($archivos.ContainsKey('hiberfil.sys')) { ConvertTo-GB $archivos['hiberfil.sys'] 1 } else { 0 })
            InicioRapido       = ($hiberboot -eq 1)
            InicioRapidoEfectivo = ($hiberboot -eq 1 -and $habilitada)
            PagefileRaizGB     = $(if ($archivos.ContainsKey('pagefile.sys')) { ConvertTo-GB $archivos['pagefile.sys'] 1 } else { 0 })
            SwapfileGB         = $(if ($archivos.ContainsKey('swapfile.sys')) { ConvertTo-GB $archivos['swapfile.sys'] 2 } else { 0 })
        }
    }

    $d.Pagefile = Invoke-Paso 'pagefile' {
        $cs = Get-Cim -Clase Win32_ComputerSystem -Propiedades AutomaticManagedPagefile
        $uso = @(Get-Cim -Clase Win32_PageFileUsage -Propiedades Name, AllocatedBaseSize, CurrentUsage, PeakUsage)
        $ajustes = @(Get-Cim -Clase Win32_PageFileSetting -Propiedades Name, InitialSize, MaximumSize)
        [pscustomobject][ordered]@{
            Automatico = [bool]$cs.AutomaticManagedPagefile
            Archivos   = @($uso | ForEach-Object {
                    $nombre = $_.Name
                    $aj = $ajustes | Where-Object { $_.Name -eq $nombre } | Select-Object -First 1
                    [pscustomobject][ordered]@{
                        Archivo    = $nombre
                        TamanoMB   = $_.AllocatedBaseSize
                        UsoMB      = $_.CurrentUsage
                        PicoMB     = $_.PeakUsage
                        InicialMB  = $(if ($aj) { $aj.InitialSize } else { $null })
                        MaximoMB   = $(if ($aj) { $aj.MaximumSize } else { $null })
                    }
                })
        }
    }
    if ($d.Pagefile) { Add-Tabla -Nombre 'pagefile' -Filas $d.Pagefile.Archivos }

    $d.DiscoSistema = Invoke-Paso 'espacio del disco del sistema' {
        $ld = Get-Cim -Clase Win32_LogicalDisk -Filtro "DeviceID='$env:SystemDrive'" -Propiedades Size, FreeSpace
        [pscustomobject][ordered]@{ Unidad = $env:SystemDrive; TotalGB = ConvertTo-GB $ld.Size 1; LibreGB = ConvertTo-GB $ld.FreeSpace 1; LibrePct = [math]::Round(100 * $ld.FreeSpace / $ld.Size, 1) }
    }
    $d
}

function Test-AlertasEnergia {
    $d = $script:Ctx.Datos.energia
    $plan = if ($d.PlanActivo) { " (plan '$($d.PlanActivo.Nombre)')" } else { '' }
    $p = $d.Procesador
    if ($p) {
        if ($null -ne $p.MaxAC -and $p.MaxAC -lt 100) {
            Add-Alerta -Severidad AVISO -Codigo 'ENE-MAX-AC' -Texto "Estado máx. del procesador < 100 % en AC = sin turbo (está en $($p.MaxAC) %$plan)"
        }
        if ($null -ne $p.MaxDC -and $p.MaxDC -lt 100) {
            Add-Alerta -Severidad INFO -Codigo 'ENE-MAX-DC' -Texto "Estado máx. del procesador en batería: $($p.MaxDC) % (sin turbo en batería)$plan"
        }
        if ($p.BoostAC -eq 0) {
            Add-Alerta -Severidad AVISO -Codigo 'ENE-BOOST-AC' -Texto "Modo de boost del procesador desactivado en AC = sin turbo$plan"
        }
        if ($p.BoostDC -eq 0) {
            Add-Alerta -Severidad INFO -Codigo 'ENE-BOOST-DC' -Texto "Modo de boost del procesador desactivado en batería$plan"
        }
        if ($p.MinAC -eq 100) {
            $nota = ''
            if ($d.PlanActivo -and $d.PlanActivo.Guid -in '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'e9a42b02-d5df-448d-aa00-03f14749eb61') { $nota = '; es lo normal de ese plan, en notebook Equilibrado calienta menos' }
            Add-Alerta -Severidad INFO -Codigo 'ENE-MIN-AC' -Texto "Estado mín. del procesador 100 % en AC: CPU siempre al máximo (más calor y ventilador)$plan$nota"
        }
    }
    $lista = Read-JsonKit (Join-Path $script:Ctx.CarpetaConfig 'software_conocido.json')
    $deOptimizador = { param($nombre) $lista.planes_energia | Where-Object { $nombre -match "(?i)$($_.patron)" } | Select-Object -First 1 }
    if ($d.PlanActivo) {
        $coincide = & $deOptimizador $d.PlanActivo.Nombre
        if ($coincide) {
            Add-Alerta -Severidad AVISO -Codigo 'ENE-PLAN' -Texto "Plan de energía activo creado por un optimizador ($($coincide.categoria)): '$($d.PlanActivo.Nombre)'"
        } elseif (-not $d.PlanActivo.Estandar) {
            Add-Alerta -Severidad INFO -Codigo 'ENE-PLAN' -Texto "Plan de energía no estándar activo: '$($d.PlanActivo.Nombre)' ($($d.PlanActivo.Guid))"
        }
    }
    $restos = @($d.Planes | Where-Object { $_ -and -not $_.Activo -and (& $deOptimizador $_.Nombre) } | Group-Object Nombre | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) (x$($_.Count))" } else { $_.Name } })
    if ($restos.Count -gt 0) {
        Add-Alerta -Severidad INFO -Codigo 'ENE-PLAN-RESTOS' -Texto "Planes de energía de optimizador instalados (inactivos): $($restos -join ', ')"
    }
    $h = $d.Hibernacion
    if ($h) {
        if ($h.HiberfilGB -ge (Get-Umbral 'hiberfil_gb')) {
            $sev = 'INFO'
            $extra = ''
            if ($d.DiscoSistema -and $d.DiscoSistema.LibrePct -lt (Get-Umbral 'libre_aviso_pct')) {
                $sev = 'AVISO'
                $extra = " y $($d.DiscoSistema.Unidad) tiene solo $(Format-Numero $d.DiscoSistema.LibrePct 1) % libre"
            }
            Add-Alerta -Severidad $sev -Codigo 'ENE-HIBERFIL' -Texto "hiberfil.sys ocupa $(Format-Numero $h.HiberfilGB 1) GB$extra"
        }
        if ($h.InicioRapidoEfectivo) {
            Add-Alerta -Severidad INFO -Codigo 'ENE-INICIO-RAPIDO' -Texto 'Inicio rápido activo: Apagar no reinicia el kernel (para diagnosticar, usar Reiniciar)'
        }
    }
    if ($d.Pagefile -and -not $d.Pagefile.Automatico -and $d.Pagefile.Archivos.Count -eq 0) {
        Add-Alerta -Severidad AVISO -Codigo 'ENE-SIN-PAGEFILE' -Texto 'Sin archivo de paginación: juegos y apps pesadas se pueden cerrar por falta de memoria virtual'
    }
}

function Format-ResumenEnergia {
    $d = $script:Ctx.Datos.energia
    if ($d.PlanActivo) { "Plan activo: $($d.PlanActivo.Nombre) ($($d.PlanActivo.Guid))$(if (-not $d.PlanActivo.Estandar) { ' [no estándar]' })" }
    $otros = @($d.Planes | Where-Object { $_ -and -not $_.Activo } | Group-Object Nombre | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) (x$($_.Count))" } else { $_.Name } })
    if ($otros.Count) { "Otros      : $($otros -join ', ')" }
    if ($d.ModoWindows -and ($d.ModoWindows.AC -or $d.ModoWindows.DC)) { "Modo Win11 : AC $($d.ModoWindows.AC) | batería $($d.ModoWindows.DC)" }
    if ($d.Procesador) {
        $p = $d.Procesador
        "Procesador : estado máx. AC $($p.MaxAC) % / DC $($p.MaxDC) % | mín. AC $($p.MinAC) % / DC $($p.MinDC) % | boost AC $($p.BoostACTexto) / DC $($p.BoostDCTexto)"
    }
    if ($d.Hibernacion) {
        $h = $d.Hibernacion
        "Hibernación: $(if ($h.Habilitada) { 'sí' } else { 'no' })$(if ($h.TipoArchivo) { " ($($h.TipoArchivo))" }) | hiberfil.sys $(Format-Numero $h.HiberfilGB 1) GB | inicio rápido: $(if ($h.InicioRapido) { 'sí' } else { 'no' })$(if ($h.InicioRapido -and -not $h.Habilitada) { ' (sin efecto: hibernación apagada)' })"
    }
    if ($d.Pagefile) {
        $archivos = @($d.Pagefile.Archivos | ForEach-Object { "$($_.Archivo) $($_.TamanoMB) MB (uso $($_.UsoMB), pico $($_.PicoMB))" })
        "Pagefile   : $(if ($d.Pagefile.Automatico) { 'automático' } else { 'manual' }) | $(if ($archivos.Count) { $archivos -join '; ' } else { 'ninguno' })"
    }
}
