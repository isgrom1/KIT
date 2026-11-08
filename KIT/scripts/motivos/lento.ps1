# lento.ps1 - Motivo LENTO (arranca lento, se pega, mucha RAM o CPU en reposo).
# - Métricas desde metricas.json de antes\ y despues\: arranque, RAM en reposo, programas al inicio,
#   espacio libre en C:.
# - Acciones sugeridas a partir del diagnóstico ANTES. Ninguna viene marcada: el técnico elige.
#   Cada una dice qué hace y cómo se deshace; al aplicarla se guarda el valor anterior exacto en
#   <atención>\lento_acciones.json y una línea en trabajo.log. Antes de la primera, punto de restauración.
# - Nunca toca seguridad: Defender, Seguridad de Windows, antivirus, Smart App Control ni VBS.
# Requiere lib\Comun, Log, Privacidad y Expediente.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:GuidEquilibrado = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:SubProcesador = '54533251-82be-4824-96c1-47b60b740d00'
$script:AjusteMaxCpu = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
$script:AjusteBoost = 'be337238-0d82-4146-a960-4f3749d470c7'
$script:RutaAprobado = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$script:RutaGpu = 'Software\Microsoft\DirectX\UserGpuPreferences'
# Lo que nunca se ofrece desactivar al inicio, y lo que se ofrece con aviso (utilidades del fabricante).
$script:InicioIntocable = '(?i)securityhealth|windows ?defender|seguridad de windows|antivirus|avast|avg|kaspersky|eset|bitdefender|norton|mcafee|malwarebytes'
$script:InicioRevisar = '(?i)realtek|audio|synaptics|elan|touchpad|nitrosense|predatorsense|armoury|myasus|vantage|dell|hp |intel|nvidia|amd|radeon|logitech|lghub|razer|corsair|onedrive|vanguard|anti-?cheat|easyanticheat|battleye|faceit'
$script:CategoriasAccion = 'optimizador', 'driver_updater', 'limpiador', 'pup', 'bloat', 'activador'

# ---------------------------------------------------------------- métricas

function Read-MetricasMedicion {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)][string]$Momento)
    $r = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) $Momento) 'metricas.json'
    if ([IO.File]::Exists($r)) { Read-JsonKit $r } else { $null }
}

function Get-MetricasLento {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $ma = Read-MetricasMedicion -Expediente $Expediente -Atencion $Atencion -Momento 'antes'
    $md = Read-MetricasMedicion -Expediente $Expediente -Atencion $Atencion -Momento 'despues'
    $arranque = { param($m) if ($m -and $m.arranque -and $m.arranque.disponible) { $m.arranque.ultimo_seg } else { $null } }
    $ram = { param($m) if ($m -and $m.ram) { $m.ram.usada_gb } else { $null } }
    $inicio = { param($m) if ($m -and $m.inicio) { $m.inicio.programas_habilitados } else { $null } }
    $libreC = { param($m) if ($m) { (@($m.espacio) | Where-Object { $_.sistema } | Select-Object -First 1).libre_gb } else { $null } }
    $tarjetas = @(
        Get-TarjetaMetrica -Titulo 'Arranque' -Antes (& $arranque $ma) -Despues (& $arranque $md) -Unidad 's' -Mejor menor
        Get-TarjetaMetrica -Titulo 'RAM en reposo' -Antes (& $ram $ma) -Despues (& $ram $md) -Unidad 'GB' -Mejor menor
        Get-TarjetaMetrica -Titulo 'Programas al inicio' -Antes (& $inicio $ma) -Despues (& $inicio $md) -Unidad '' -Mejor menor
        Get-TarjetaMetrica -Titulo 'Espacio libre en C:' -Antes (& $libreC $ma) -Despues (& $libreC $md) -Unidad 'GB' -Mejor mayor
    )
    $adv = New-Object System.Collections.Generic.List[string]
    foreach ($par in @(@{ M = $ma; N = 'ANTES' }, @{ M = $md; N = 'DESPUÉS' })) {
        $m = $par.M
        if (-not $m) { $adv.Add("Falta el diagnóstico $($par.N)"); continue }
        if ($m.arranque -and -not $m.arranque.disponible) { $adv.Add("Tiempo de arranque $($par.N): $($m.arranque.motivo)") }
        if ($null -ne $m.minutos_desde_arranque -and $m.minutos_desde_arranque -lt 5) { $adv.Add("La RAM $($par.N) se midió a $($m.minutos_desde_arranque) min de encender (lo justo es esperar 5 min en reposo)") }
    }
    if ($md -and @($md.software_a_revisar).Count -gt 0) { $adv.Add("Sigue instalado: $(@($md.software_a_revisar) -join ', ')") }
    [pscustomobject][ordered]@{ Motivo = 'LENTO'; Tarjetas = $tarjetas; Advertencias = $adv.ToArray(); Antes = $ma; Despues = $md }
}

# ---------------------------------------------------------------- acciones sugeridas

function ConvertTo-AccionLento {
    param([string]$Id, [string]$Tipo, [string]$Titulo, [string]$QueHace, [string]$Deshacer, [bool]$Admin, [string]$Riesgo = 'bajo', [System.Collections.IDictionary]$Datos)
    [pscustomobject][ordered]@{ Id = $Id; Tipo = $Tipo; Titulo = $Titulo; QueHace = $QueHace; Deshacer = $Deshacer; RequiereAdmin = $Admin; Riesgo = $Riesgo; Datos = $Datos }
}

function Get-AccionesLento {
    # Lista lo que se puede hacer según el diagnóstico ANTES. Tipo 'manual' = recomendación que hace el
    # técnico (desinstalar, actualizar driver...), no se aplica sola.
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $ruta = Join-Path (Join-Path (Join-Path $Expediente.Ruta $Atencion) 'antes') 'diagnostico.json'
    if (-not [IO.File]::Exists($ruta)) { throw 'Falta el diagnóstico ANTES de esta atención' }
    $doc = Read-JsonKit $ruta
    $d = $doc.datos
    $acciones = New-Object System.Collections.Generic.List[object]
    $av = @($d.seguridad.Antivirus | Where-Object { $_ } | ForEach-Object { "$($_.Ejecutable)" })

    # Elementos de inicio (Run y carpetas Inicio). RunOnce y apps de la Store quedan fuera.
    $mapa = @{ 'HKCU\Run' = @('HKCU', 'Run'); 'HKLM\Run' = @('HKLM', 'Run'); 'HKLM\Run (32 bits)' = @('HKLM', 'Run32'); 'Inicio (usuario)' = @('HKCU', 'StartupFolder'); 'Inicio (todos)' = @('HKLM', 'StartupFolder') }
    foreach ($e in @($d.arranque.Entradas | Where-Object { $_ -and $_.Habilitado -and $mapa.ContainsKey("$($_.Ubicacion)") })) {
        $texto = "$($e.Nombre) $($e.Comando) $($e.Empresa)"
        if ($texto -match $script:InicioIntocable -or "$($e.Empresa)" -match '(?i)^microsoft' -or ($e.Ejecutable -and $av -contains $e.Ejecutable)) { continue }
        $m = $mapa["$($e.Ubicacion)"]
        $riesgo = if ($texto -match $script:InicioRevisar) { 'revisar' } else { 'bajo' }
        $titulo = if ($e.Existe -eq $false) { "Desactivar entrada de inicio huérfana: $($e.Nombre)" } else { "Desactivar al inicio: $($e.Nombre)$(if ($e.Empresa) { " ($($e.Empresa))" })" }
        $acciones.Add((ConvertTo-AccionLento -Id "inicio|$($m[0])|$($m[1])|$($e.Nombre)" -Tipo 'inicio' -Titulo $titulo -Admin ($m[0] -eq 'HKLM') -Riesgo $riesgo `
                    -QueHace 'La marca como deshabilitada al inicio (igual que el Administrador de tareas). El programa sigue instalado y se puede abrir a mano.' `
                    -Deshacer 'Se restaura el estado anterior del inicio.' -Datos ([ordered]@{ Colmena = $m[0]; Clave = $m[1]; Nombre = $e.Nombre })))
    }
    # Servicios y tareas de software conocido como innecesario (optimizadores, PUP, bloat...).
    foreach ($s in @($d.arranque.Servicios.Terceros | Where-Object { $_ -and "$($_.Inicio)" -like 'Autom*' })) {
        $h = Find-SoftwareConocido -Textos $s.Servicio, $s.Nombre, $s.Comando
        if (-not $h -or $h.Categoria -notin $script:CategoriasAccion) { continue }
        $acciones.Add((ConvertTo-AccionLento -Id "servicio|$($s.Servicio)" -Tipo 'servicio' -Titulo "Servicio a manual: $($s.Nombre) ($($h.Texto))" -Admin $true `
                    -QueHace 'Deja de arrancar solo con Windows; sigue instalado y arranca si el programa lo pide.' -Deshacer "Vuelve a inicio $($s.Inicio)." `
                    -Datos ([ordered]@{ Servicio = $s.Servicio })))
    }
    foreach ($t in @($d.arranque.Tareas | Where-Object { $_ -and $_.Habilitado })) {
        $h = Find-SoftwareConocido -Textos $t.Nombre, $t.Comando
        if (-not $h -or $h.Categoria -notin $script:CategoriasAccion) { continue }
        $acciones.Add((ConvertTo-AccionLento -Id "tarea|$($t.Nombre)" -Tipo 'tarea' -Titulo "Desactivar tarea: $($t.Nombre) ($($h.Texto))" -Admin $true `
                    -QueHace 'La tarea programada deja de ejecutarse al iniciar sesión.' -Deshacer 'Se vuelve a habilitar la tarea.' -Datos ([ordered]@{ Tarea = $t.Nombre })))
    }
    # Energía.
    $en = $d.energia
    if ($en -and $en.PlanActivo -and -not $en.PlanActivo.Estandar) {
        $patrones = @((Get-ListaSoftwareConocido).planes_energia | Where-Object { $_.categoria -eq 'optimizador' } | ForEach-Object { $_.patron })
        $esOpt = @($patrones | Where-Object { $en.PlanActivo.Nombre -match $_ }).Count -gt 0
        if ($esOpt -and @($en.Planes | Where-Object { $_.Guid -eq $script:GuidEquilibrado }).Count -gt 0) {
            $acciones.Add((ConvertTo-AccionLento -Id 'plan|equilibrado' -Tipo 'plan' -Titulo "Cambiar el plan de energía '$($en.PlanActivo.Nombre)' (de un optimizador) por Equilibrado" -Admin $false `
                        -QueHace 'Activa el plan Equilibrado de Windows. El plan del optimizador no se borra.' -Deshacer 'Se vuelve a activar el plan anterior.' -Datos ([ordered]@{ Plan = $script:GuidEquilibrado })))
        }
    }
    if ($en -and $en.Procesador) {
        if ($null -ne $en.Procesador.MaxAC -and $en.Procesador.MaxAC -lt 100) {
            $acciones.Add((ConvertTo-AccionLento -Id 'cpu|max_ac' -Tipo 'cpu_max' -Titulo "Estado máximo del procesador enchufado: de $($en.Procesador.MaxAC) % a 100 % (vuelve el turbo)" -Admin $false `
                        -QueHace 'Cambia el ajuste en el plan activo.' -Deshacer "Vuelve a $($en.Procesador.MaxAC) %." -Datos ([ordered]@{ Ajuste = $script:AjusteMaxCpu; Valor = 100 })))
        }
        if ($null -ne $en.Procesador.BoostAC -and $en.Procesador.BoostAC -eq 0) {
            $acciones.Add((ConvertTo-AccionLento -Id 'cpu|boost_ac' -Tipo 'cpu_boost' -Titulo 'Activar el turbo del procesador enchufado (estaba desactivado)' -Admin $false `
                        -QueHace 'Pone el modo de aumento del rendimiento en Agresivo en el plan activo.' -Deshacer 'Vuelve a desactivado.' -Datos ([ordered]@{ Ajuste = $script:AjusteBoost; Valor = 2 })))
        }
    }
    $c = @($d.espacio.Volumenes | Where-Object { $_ -and $_.EsSistema }) | Select-Object -First 1
    if ($en -and $en.Hibernacion -and $en.Hibernacion.HiberfilGB -ge [double]$script:Ctx.Config.umbrales.hiberfil_gb -and $c -and $c.LibrePct -lt [double]$script:Ctx.Config.umbrales.libre_aviso_pct) {
        $acciones.Add((ConvertTo-AccionLento -Id 'hibernacion|off' -Tipo 'hibernacion' -Titulo "Desactivar la hibernación (libera $($en.Hibernacion.HiberfilGB) GB en C:)" -Admin $true -Riesgo 'revisar' `
                    -QueHace 'Borra hiberfil.sys y desactiva el inicio rápido; el equipo ya no podrá hibernar.' -Deshacer 'powercfg /hibernate on' -Datos ([ordered]@{})))
    }
    # Apps forzadas a la GPU de ahorro en equipos con 2 GPU.
    if ($d.gpu_apps -and $d.gpu_apps.CantidadGpu -ge 2) {
        foreach ($g in @($d.gpu_apps.Apps | Where-Object { $_ -and $_.Codigo -eq 1 -and $_.Existe -ne $false })) {
            $acciones.Add((ConvertTo-AccionLento -Id "gpu|$($g.Aplicacion)" -Tipo 'gpu' -Titulo "Usar la GPU de alto rendimiento en $(Split-Path -Leaf $g.Aplicacion)" -Admin $false `
                        -QueHace 'Cambia la preferencia de gráficos de esa app (Configuración > Pantalla > Gráficos).' -Deshacer 'Se restaura la preferencia anterior.' -Datos ([ordered]@{ App = $g.Aplicacion })))
        }
    }
    # Recomendaciones manuales.
    foreach ($s in @($d.software.Detectados | Where-Object { $_ -and $_.Categoria -in $script:CategoriasAccion })) {
        $acciones.Add((ConvertTo-AccionLento -Id "manual|desinstalar|$($s.Nombre)" -Tipo 'manual' -Titulo "Desinstalar $($s.Nombre) ($($s.Texto))" -Admin $false -QueHace 'Desde Configuración > Aplicaciones, con el cliente de acuerdo.' -Deshacer 'Reinstalar desde el sitio oficial.' -Datos ([ordered]@{})))
    }
    foreach ($a in @($doc.alertas | Where-Object { $_.Codigo -in 'HW-GPU-DRIVER', 'HW-GPU-GENERICO', 'HW-RAM-POCA', 'HW-DISCO-HDD', 'ESP-LIBRE' })) {
        $acciones.Add((ConvertTo-AccionLento -Id "manual|$($a.Codigo)" -Tipo 'manual' -Titulo $a.Texto -Admin $false -QueHace $(switch ($a.Codigo) { 'ESP-LIBRE' { 'Liberar espacio con el motivo ARCHIVOS.' } 'HW-DISCO-HDD' { 'Ofrecer cambio a SSD.' } 'HW-RAM-POCA' { 'Ofrecer ampliación de RAM.' } default { 'Instalar el driver del sitio del fabricante.' } }) -Deshacer '' -Datos ([ordered]@{})))
    }
    $acciones.ToArray()
}

# ---------------------------------------------------------------- aplicar y deshacer

function Read-RegistroLento {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion)
    $r = Join-Path (Join-Path $Expediente.Ruta $Atencion) 'lento_acciones.json'
    if ([IO.File]::Exists($r)) { ConvertTo-Diccionario (Read-JsonKit $r) } else { [ordered]@{ punto_restauracion = $null; acciones = @() } }
}

function Save-RegistroLento {
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [Parameter(Mandatory)]$Registro)
    [IO.File]::WriteAllText((Join-Path (Join-Path $Expediente.Ruta $Atencion) 'lento_acciones.json'), ($Registro | ConvertTo-Json -Depth 8), $script:Utf8SinBom)
}

function Open-ClaveEscritura {
    param([ValidateSet('HKCU', 'HKLM')][string]$Colmena, [string]$Ruta)
    $hive = if ($Colmena -eq 'HKLM') { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
    [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64).CreateSubKey($Ruta)
}

function Get-PlanActivo {
    $r = Invoke-Externo -Exe (Get-RutaSistema 'powercfg.exe') -Argumentos '/getactivescheme'
    $m = [regex]::Match($r.Salida, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if (-not $m.Success) { throw 'No se pudo leer el plan activo' }
    $m.Value.ToLowerInvariant()
}

function Get-ValorAcPlan {
    param([string]$Plan, [string]$Ajuste)
    $r = Invoke-Externo -Exe (Get-RutaSistema 'powercfg.exe') -Argumentos "/qh $Plan $script:SubProcesador $Ajuste"
    $hex = @([regex]::Matches($r.Salida, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { throw "No se pudo leer el ajuste $Ajuste del plan $Plan" }
    [Convert]::ToInt32($hex[$hex.Count - 2], 16)
}

function Invoke-Powercfg {
    param([string]$Argumentos)
    $r = Invoke-Externo -Exe (Get-RutaSistema 'powercfg.exe') -Argumentos $Argumentos
    if ($r.Codigo -ne 0) { throw "powercfg $Argumentos falló (código $($r.Codigo)): $($r.Salida.Trim()) $($r.Error.Trim())" }
}

function Invoke-CambioLento {
    # Aplica una acción y devuelve lo necesario para deshacerla (leído en vivo, no del diagnóstico).
    param([Parameter(Mandatory)]$Accion)
    $x = $Accion.Datos
    switch ($Accion.Tipo) {
        'inicio' {
            $k = Open-ClaveEscritura -Colmena $x.Colmena -Ruta "$script:RutaAprobado\$($x.Clave)"
            try {
                $previo = $k.GetValue($x.Nombre)
                $nuevo = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()))
                $k.SetValue($x.Nombre, $nuevo, [Microsoft.Win32.RegistryValueKind]::Binary)
            } finally { $k.Close() }
            return [ordered]@{ previo = $(if ($previo) { [Convert]::ToBase64String([byte[]]$previo) } else { $null }) }
        }
        'servicio' {
            $s = Get-Cim -Clase Win32_Service -Filtro "Name='$($x.Servicio -replace "'", "''")'" -Propiedades StartMode
            $retrasado = (Get-ValorRegistro -Colmena HKLM -Ruta "SYSTEM\CurrentControlSet\Services\$($x.Servicio)" -Nombre 'DelayedAutostart') -eq 1
            $previo = if ($s.StartMode -eq 'Auto' -and $retrasado) { 'delayed-auto' } elseif ($s.StartMode -eq 'Auto') { 'auto' } elseif ($s.StartMode -eq 'Disabled') { 'disabled' } else { 'demand' }
            $r = Invoke-Externo -Exe (Get-RutaSistema 'sc.exe') -Argumentos "config `"$($x.Servicio)`" start= demand"
            if ($r.Codigo -ne 0) { throw "sc config falló (código $($r.Codigo)): $($r.Salida.Trim())" }
            return [ordered]@{ previo = $previo }
        }
        'tarea' {
            $ruta = $x.Tarea.Substring(0, $x.Tarea.LastIndexOf('\') + 1); $nombre = $x.Tarea.Substring($x.Tarea.LastIndexOf('\') + 1)
            $null = Disable-ScheduledTask -TaskPath $ruta -TaskName $nombre -ErrorAction Stop
            return [ordered]@{ previo = 'habilitada' }
        }
        'plan' {
            $previo = Get-PlanActivo
            Invoke-Powercfg "/setactive $($x.Plan)"
            return [ordered]@{ previo = $previo }
        }
        { $_ -in 'cpu_max', 'cpu_boost' } {
            $plan = Get-PlanActivo
            $previo = Get-ValorAcPlan -Plan $plan -Ajuste $x.Ajuste
            Invoke-Powercfg "/setacvalueindex $plan $script:SubProcesador $($x.Ajuste) $($x.Valor)"
            Invoke-Powercfg "/setactive $plan"
            return [ordered]@{ previo = $previo; plan = $plan }
        }
        'hibernacion' {
            Invoke-Powercfg '/hibernate off'
            return [ordered]@{ previo = 'on' }
        }
        'gpu' {
            # La ruta viene enmascarada del diagnóstico (C:\Users\<U1>\...): el valor real lleva el perfil real.
            $app = ConvertFrom-RutaProtegida $x.App
            $k = Open-ClaveEscritura -Colmena HKCU -Ruta $script:RutaGpu
            try {
                $previo = $k.GetValue($app)
                $nuevo = if ($previo -and "$previo" -match 'GpuPreference=\d;') { "$previo" -replace 'GpuPreference=\d;', 'GpuPreference=2;' } else { "GpuPreference=2;$previo" }
                $k.SetValue($app, $nuevo, [Microsoft.Win32.RegistryValueKind]::String)
            } finally { $k.Close() }
            return [ordered]@{ previo = $previo }
        }
    }
    throw "Acción de tipo '$($Accion.Tipo)' no se aplica sola"
}

function Undo-CambioLento {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Registro)
    $x = $Registro['datos']; $p = $Registro['deshacer']
    switch ($Registro['tipo']) {
        'inicio' {
            $k = Open-ClaveEscritura -Colmena $x['Colmena'] -Ruta "$script:RutaAprobado\$($x['Clave'])"
            try { if ($p['previo']) { $k.SetValue($x['Nombre'], [Convert]::FromBase64String($p['previo']), [Microsoft.Win32.RegistryValueKind]::Binary) } else { $k.DeleteValue($x['Nombre'], $false) } } finally { $k.Close() }
        }
        'servicio' {
            $r = Invoke-Externo -Exe (Get-RutaSistema 'sc.exe') -Argumentos "config `"$($x['Servicio'])`" start= $($p['previo'])"
            if ($r.Codigo -ne 0) { throw "sc config falló (código $($r.Codigo)): $($r.Salida.Trim())" }
        }
        'tarea' {
            $t = $x['Tarea']; $null = Enable-ScheduledTask -TaskPath $t.Substring(0, $t.LastIndexOf('\') + 1) -TaskName $t.Substring($t.LastIndexOf('\') + 1) -ErrorAction Stop
        }
        'plan' { Invoke-Powercfg "/setactive $($p['previo'])" }
        { $_ -in 'cpu_max', 'cpu_boost' } {
            Invoke-Powercfg "/setacvalueindex $($p['plan']) $script:SubProcesador $($x['Ajuste']) $($p['previo'])"
            Invoke-Powercfg "/setactive $(Get-PlanActivo)"
        }
        'hibernacion' { Invoke-Powercfg '/hibernate on' }
        'gpu' {
            $app = ConvertFrom-RutaProtegida $x['App']
            $k = Open-ClaveEscritura -Colmena HKCU -Ruta $script:RutaGpu
            try { if ($null -ne $p['previo']) { $k.SetValue($app, $p['previo'], [Microsoft.Win32.RegistryValueKind]::String) } else { $k.DeleteValue($app, $false) } } finally { $k.Close() }
        }
    }
}

# Las excepciones que empiezan así significan "Windows no deja crear el punto de restauración": la ventana
# y la consola le preguntan al técnico si aplica igual sin él (el kit no cambia esa configuración).
$script:PrefijoSinPunto = 'PUNTO_RESTAURACION: '

function Get-MotivoSinPunto {
    # Por qué Windows no deja crear el punto de restauración, en palabras simples. Solo lee.
    $vss = Get-Service -Name 'VSS' -ErrorAction SilentlyContinue
    if ($vss -and "$($vss.StartType)" -eq 'Disabled') { return 'el servicio Instantáneas de volumen está deshabilitado (típico de optimizadores)' }
    'la Protección del sistema parece desactivada en C:'
}

function Initialize-PuntoRestauracion {
    # Usa uno de las últimas 24 h si existe (Windows no crea otro antes) o crea uno nuevo. Necesita admin.
    if (-not $script:Ctx.Admin.Elevado) { throw 'El punto de restauración necesita admin: relanza como administrador' }
    $antes = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    $reciente = $antes | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt (Get-Date).AddHours(-24) } | Select-Object -Last 1
    if ($reciente) { return [ordered]@{ fecha = ConvertTo-TextoFecha ([Management.ManagementDateTimeConverter]::ToDateTime($reciente.CreationTime)); descripcion = $reciente.Description; creado_ahora = $false } }
    try {
        Checkpoint-Computer -Description 'KIT SERVICIO - antes de LENTO' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
    } catch {
        throw "$($script:PrefijoSinPunto)$(Get-MotivoSinPunto). Windows dice: $($_.Exception.Message)"
    }
    $nuevo = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
    if (-not $nuevo -or @($antes).Count -eq @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count) { throw "$($script:PrefijoSinPunto)$(Get-MotivoSinPunto)" }
    [ordered]@{ fecha = ConvertTo-TextoFecha ([Management.ManagementDateTimeConverter]::ToDateTime($nuevo.CreationTime)); descripcion = $nuevo.Description; creado_ahora = $true }
}

function Invoke-AccionesLento {
    # Aplica las acciones elegidas (objetos de Get-AccionesLento). Si una falla, se registra y sigue
    # con las demás. -SinPuntoRestauracion solo si el técnico lo decide (p. ej. protección desactivada).
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Expediente,
        [Parameter(Mandatory)][string]$Atencion,
        [Parameter(Mandatory)][object[]]$Acciones,
        [switch]$SinPuntoRestauracion
    )
    $reg = Read-RegistroLento -Expediente $Expediente -Atencion $Atencion
    $aplicables = @($Acciones | Where-Object { $_.Tipo -ne 'manual' })
    $faltaAdmin = @($aplicables | Where-Object { $_.RequiereAdmin -and -not $script:Ctx.Admin.Elevado })
    if ($faltaAdmin.Count -gt 0) { throw "Necesitan admin: $(($faltaAdmin | ForEach-Object { $_.Titulo }) -join '; ')" }
    if (-not $reg['punto_restauracion'] -and $aplicables.Count -gt 0) {
        if ($SinPuntoRestauracion) {
            $reg['punto_restauracion'] = [ordered]@{ fecha = $null; descripcion = 'omitido por el técnico'; creado_ahora = $false }
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto 'LENTO | sin punto de restauración (decisión del técnico)'
        } elseif ($PSCmdlet.ShouldProcess('equipo', 'Crear punto de restauración')) {
            $reg['punto_restauracion'] = Initialize-PuntoRestauracion
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "LENTO | punto de restauración: $($reg['punto_restauracion']['descripcion']) ($($reg['punto_restauracion']['fecha']))"
        }
        Save-RegistroLento -Expediente $Expediente -Atencion $Atencion -Registro $reg
    }
    $hechas = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Acciones) {
        if ($a.Tipo -eq 'manual') {
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "LENTO | manual: $($a.Titulo)"
            $hechas.Add($a.Titulo)
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($a.Titulo, 'Aplicar')) { continue }
        try {
            $deshacer = Invoke-CambioLento -Accion $a
            $reg['acciones'] = @($reg['acciones'] | Where-Object { $_ }) + @([ordered]@{ id = $a.Id; tipo = $a.Tipo; titulo = $a.Titulo; datos = $a.Datos; deshacer = $deshacer; aplicada = (ConvertTo-TextoFecha (Get-Date)); deshecha = $null })
            Save-RegistroLento -Expediente $Expediente -Atencion $Atencion -Registro $reg
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "LENTO | aplicada: $($a.Titulo) | deshacer: $($a.Deshacer)"
            $hechas.Add($a.Titulo)
        } catch {
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "LENTO | ERROR al aplicar '$($a.Titulo)': $($_.Exception.Message)"
            Write-Warning "No se pudo aplicar '$($a.Titulo)': $($_.Exception.Message)"
        }
    }
    if ($hechas.Count -gt 0) {
        $previas = @((Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion)['acciones_realizadas'] | Where-Object { $_ })
        Set-Ficha -Expediente $Expediente -Atencion $Atencion -Valores @{ acciones_realizadas = @($previas + $hechas.ToArray() | Select-Object -Unique) }
    }
    $hechas.ToArray()
}

function Undo-AccionesLento {
    # Deshace las acciones aplicadas (todas o las de -Ids), de la última a la primera.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Expediente, [Parameter(Mandatory)][string]$Atencion, [string[]]$Ids)
    $reg = Read-RegistroLento -Expediente $Expediente -Atencion $Atencion
    $lista = @($reg['acciones'] | Where-Object { $_ -and -not $_['deshecha'] -and (-not $Ids -or $_['id'] -in $Ids) })
    [array]::Reverse($lista)
    $deshechas = New-Object System.Collections.Generic.List[string]
    foreach ($r in $lista) {
        if (-not $PSCmdlet.ShouldProcess($r['titulo'], 'Deshacer')) { continue }
        try {
            Undo-CambioLento -Registro $r
            $r['deshecha'] = ConvertTo-TextoFecha (Get-Date)
            Save-RegistroLento -Expediente $Expediente -Atencion $Atencion -Registro $reg
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "LENTO | deshecha: $($r['titulo'])"
            $deshechas.Add($r['titulo'])
        } catch {
            Write-TrabajoLog -Expediente $Expediente -Atencion $Atencion -Texto "LENTO | ERROR al deshacer '$($r['titulo'])': $($_.Exception.Message)"
            Write-Warning "No se pudo deshacer '$($r['titulo'])': $($_.Exception.Message)"
        }
    }
    if ($deshechas.Count -gt 0) {
        $quedan = @((Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion)['acciones_realizadas'] | Where-Object { $_ -and $_ -notin $deshechas })
        Set-Ficha -Expediente $Expediente -Atencion $Atencion -Valores @{ acciones_realizadas = $quedan }
    }
    $deshechas.ToArray()
}
