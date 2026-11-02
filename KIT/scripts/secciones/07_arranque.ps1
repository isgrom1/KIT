# 07 Arranque: Run/RunOnce + carpetas Inicio con su estado en StartupApproved, tareas de inicio de
# apps de la Store, tareas programadas de inicio de sesión/arranque que no son de Microsoft y
# servicios automáticos que no son de Microsoft. Marca entradas sospechosas y huérfanas.
# Con admin, también la duración de los últimos arranques (Diagnostics-Performance, evento 100).

$script:ReglasSospecha = @(
    @{ Patron = '(?i)\\(AppData\\Local\\)?Temp\\'; Motivo = 'ejecuta desde una carpeta temporal' }
    @{ Patron = '(?i)\bpowershell(\.exe)?\b.*\s-(e|ec|enc\w*)\s'; Motivo = 'PowerShell con comando codificado (-enc)' }
    @{ Patron = '(?i)\bpowershell(\.exe)?\b.*\s-w\w*\s+(h\w*|1)\b'; Motivo = 'PowerShell con ventana oculta' }
    @{ Patron = '(?i)\bmshta(\.exe)?\b'; Motivo = 'usa mshta' }
    @{ Patron = '(?i)\b[wc]script(\.exe)?\b.*\\(AppData|Users\\Public|ProgramData)\\'; Motivo = 'script VBS/JS desde AppData o ProgramData' }
    @{ Patron = '(?i)\brundll32(\.exe)?\b.*\\(AppData|Users\\Public|Temp)\\'; Motivo = 'rundll32 con DLL en carpeta de usuario' }
    @{ Patron = '(?i)\bregsvr32(\.exe)?\b.*(/i:|scrobj)'; Motivo = 'regsvr32 con scriptlet' }
    @{ Patron = '(?i)\\Users\\Public\\'; Motivo = 'ejecuta desde C:\Users\Public' }
    @{ Patron = '(?i)\bcertutil(\.exe)?\b.*-urlcache'; Motivo = 'certutil descargando archivos' }
    @{ Patron = '(?i)\bbitsadmin(\.exe)?\b.*/transfer'; Motivo = 'bitsadmin descargando archivos' }
    @{ Patron = '(?i)\b(curl|wget|iwr|Invoke-WebRequest|DownloadString|DownloadFile)\b'; Motivo = 'descarga algo al iniciar' }
)
$script:EstadoTarea = @{ 0 = 'Desconocido'; 1 = 'Deshabilitada'; 2 = 'En cola'; 3 = 'Lista'; 4 = 'Ejecutando' }

function Get-MotivoSospecha {
    param([AllowEmptyString()][string]$Comando)
    if (-not $Comando) { return $null }
    $motivos = @($script:ReglasSospecha | Where-Object { $Comando -match $_.Patron } | ForEach-Object { $_.Motivo })
    if ($motivos.Count -eq 0) { return $null }
    $motivos -join '; '
}

function Test-AprobadoInicio {
    # StartupApproved: primer byte par = habilitado, impar = deshabilitado. Sin valor = habilitado.
    param([object[]]$Valores)
    foreach ($v in $Valores) {
        if ($v -is [byte[]] -and $v.Length -gt 0 -and ($v[0] -band 1) -eq 1) { return $false }
    }
    $true
}

function ConvertTo-FilaArranque {
    param([string]$Nombre, [string]$Ubicacion, [string]$Comando, [string]$Ejecutable, [bool]$Habilitado)
    $exe = Resolve-RutaEjecutable $Ejecutable
    $existe = $null
    if ($exe -and $exe -match '^[A-Za-z]:\\') { $existe = [IO.File]::Exists($exe) }
    [pscustomobject][ordered]@{
        Nombre     = $Nombre
        Ubicacion  = $Ubicacion
        Habilitado = $Habilitado
        Comando    = $Comando
        Ejecutable = $exe
        Existe     = $existe
        Empresa    = Get-EmpresaArchivo $exe
        Sospecha   = Get-MotivoSospecha $Comando
    }
}

function Get-DatosArranque {
    $d = [ordered]@{}
    $d.Entradas = Invoke-Paso 'Run y carpetas Inicio' { @(Get-EntradasRunKit) + @(Get-CarpetasInicioKit) }
    $d.AppsStore = Invoke-Paso 'tareas de inicio de la Store' { Get-InicioStoreKit }
    Add-Tabla -Nombre 'arranque' -Filas (@($d.Entradas) + @($d.AppsStore))
    $d.Tareas = Invoke-Paso 'tareas programadas' { Get-TareasInicioKit }
    Add-Tabla -Nombre 'tareas_inicio' -Filas $d.Tareas
    $d.Servicios = Invoke-Paso 'servicios' { Get-ServiciosTercerosKit }
    if ($d.Servicios) { Add-Tabla -Nombre 'servicios_terceros' -Filas $d.Servicios.Terceros }
    $d.TiempoArranque = Invoke-Paso 'tiempo de arranque' { Get-TiempoArranqueKit }
    if ($d.TiempoArranque) { Add-Tabla -Nombre 'tiempos_arranque' -Filas $d.TiempoArranque.Ultimos }

    $hallazgos = New-Object System.Collections.Generic.List[object]
    foreach ($e in @(@($d.Entradas) + @($d.Tareas) | Where-Object { $_ })) {
        $h = Find-SoftwareConocido -Textos $e.Nombre, $e.Comando
        if ($h) { $hallazgos.Add([pscustomobject]@{ Categoria = $h.Categoria; Severidad = $h.Severidad; Texto = "Arranca con Windows - $($h.Texto)"; Nombre = $e.Nombre; Donde = $e.Ubicacion }) }
    }
    if ($d.Servicios) {
        foreach ($s in @($d.Servicios.Terceros)) {
            $h = Find-SoftwareConocido -Textos $s.Servicio, $s.Nombre, $s.Comando
            if ($h) { $hallazgos.Add([pscustomobject]@{ Categoria = $h.Categoria; Severidad = $h.Severidad; Texto = "Servicio automático - $($h.Texto)"; Nombre = $s.Nombre; Donde = 'servicio' }) }
        }
    }
    $d.Detectados = $hallazgos.ToArray()
    $d
}

function Get-TiempoArranqueKit {
    # Evento 100 de Diagnostics-Performance: duración de cada arranque medida por Windows.
    # El registro solo lo puede leer un administrador.
    if (-not $script:Ctx.Admin.Elevado) {
        Add-Incompleto -Parte 'Tiempo de arranque (Diagnostics-Performance)'
        return [pscustomobject][ordered]@{ Disponible = $false; Vigente = $false; Motivo = 'requiere admin'; UltimoSeg = $null; EscritorioSeg = $null; PosteriorSeg = $null; Fecha = $null; MedianaSeg = $null; Ultimos = @() }
    }
    $consulta = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery('Microsoft-Windows-Diagnostics-Performance/Operational', [System.Diagnostics.Eventing.Reader.PathType]::LogName, '*[System[EventID=100]]')
    $consulta.ReverseDirection = $true
    $lector = New-Object System.Diagnostics.Eventing.Reader.EventLogReader($consulta)
    $filas = New-Object System.Collections.Generic.List[object]
    $fechaUltimo = $null
    try {
        while ($filas.Count -lt 10 -and $null -ne ($e = $lector.ReadEvent())) {
            try {
                if ($null -eq $fechaUltimo) { $fechaUltimo = $e.TimeCreated }
                $x = [xml]$e.ToXml()
                $v = @{}
                foreach ($dato in $x.Event.EventData.Data) { $v[$dato.Name] = $dato.'#text' }
                $filas.Add([pscustomobject][ordered]@{
                        Fecha         = ConvertTo-TextoFecha $e.TimeCreated
                        TotalSeg      = [math]::Round([double]$v['BootTime'] / 1000, 1)
                        EscritorioSeg = [math]::Round([double]$v['MainPathBootTime'] / 1000, 1)
                        PosteriorSeg  = [math]::Round([double]$v['BootPostBootTime'] / 1000, 1)
                    })
            } finally { $e.Dispose() }
        }
    } finally { $lector.Dispose() }
    if ($filas.Count -eq 0) {
        return [pscustomobject][ordered]@{ Disponible = $false; Vigente = $false; Motivo = 'sin eventos de arranque registrados'; UltimoSeg = $null; EscritorioSeg = $null; PosteriorSeg = $null; Fecha = $null; MedianaSeg = $null; Ultimos = @() }
    }
    # Windows puede dejar de registrar el evento 100: si el último es muy anterior al arranque
    # actual, la medida no sirve para comparar antes/después.
    $vigente = $true
    $motivo = $null
    $arranqueActual = (Get-Cim -Clase Win32_OperatingSystem -Propiedades LastBootUpTime).LastBootUpTime
    if ($arranqueActual -and $fechaUltimo -and ($arranqueActual - $fechaUltimo).TotalDays -gt 7) {
        $vigente = $false
        $motivo = "el último arranque medido por Windows es del $(ConvertTo-TextoFecha $fechaUltimo -SoloFecha); los recientes no quedaron registrados"
    }
    $orden = @($filas | Select-Object -First 5 | ForEach-Object { $_.TotalSeg } | Sort-Object)
    [pscustomobject][ordered]@{
        Disponible    = $true
        Vigente       = $vigente
        Motivo        = $motivo
        UltimoSeg     = $filas[0].TotalSeg
        EscritorioSeg = $filas[0].EscritorioSeg
        PosteriorSeg  = $filas[0].PosteriorSeg
        Fecha         = $filas[0].Fecha
        MedianaSeg    = $orden[[int][math]::Floor($orden.Count / 2)]
        Ultimos       = $filas.ToArray()
    }
}

function Get-EntradasRunKit {
    $base = 'Software\Microsoft\Windows\CurrentVersion'
    $aprobado = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $fuentes = @(
        @{ Colmena = 'HKCU'; Vista = 64; Clave = 'Run'; Aprob = 'Run'; Etiqueta = 'HKCU\Run' }
        @{ Colmena = 'HKCU'; Vista = 64; Clave = 'RunOnce'; Aprob = $null; Etiqueta = 'HKCU\RunOnce' }
        @{ Colmena = 'HKLM'; Vista = 64; Clave = 'Run'; Aprob = 'Run'; Etiqueta = 'HKLM\Run' }
        @{ Colmena = 'HKLM'; Vista = 64; Clave = 'RunOnce'; Aprob = $null; Etiqueta = 'HKLM\RunOnce' }
    )
    if ([Environment]::Is64BitOperatingSystem) {
        $fuentes += @{ Colmena = 'HKLM'; Vista = 32; Clave = 'Run'; Aprob = 'Run32'; Etiqueta = 'HKLM\Run (32 bits)' }
        $fuentes += @{ Colmena = 'HKLM'; Vista = 32; Clave = 'RunOnce'; Aprob = $null; Etiqueta = 'HKLM\RunOnce (32 bits)' }
    }
    foreach ($f in $fuentes) {
        $valores = Get-ValoresRegistro -Colmena $f.Colmena -Ruta "$base\$($f.Clave)" -Vista $f.Vista
        $aprobHkcu = @{}
        $aprobHklm = @{}
        if ($f.Aprob) {
            $aprobHkcu = Get-ValoresRegistro -Colmena HKCU -Ruta "$aprobado\$($f.Aprob)"
            $aprobHklm = Get-ValoresRegistro -Colmena HKLM -Ruta "$aprobado\$($f.Aprob)"
        }
        foreach ($nombre in $valores.Keys) {
            if (-not $nombre) { continue }
            $comando = "$($valores[$nombre])"
            $habilitado = Test-AprobadoInicio @($aprobHkcu[$nombre], $aprobHklm[$nombre])
            ConvertTo-FilaArranque -Nombre $nombre -Ubicacion $f.Etiqueta -Comando $comando -Ejecutable (Get-RutaDesdeComando $comando) -Habilitado $habilitado
        }
    }
}

function Get-CarpetasInicioKit {
    $aprobado = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    $carpetas = @(
        @{ Ruta = [Environment]::GetFolderPath('Startup'); Colmena = 'HKCU'; Etiqueta = 'Inicio (usuario)' }
        @{ Ruta = [Environment]::GetFolderPath('CommonStartup'); Colmena = 'HKLM'; Etiqueta = 'Inicio (todos)' }
    )
    $shell = $null
    try {
        foreach ($c in $carpetas) {
            if (-not $c.Ruta -or -not [IO.Directory]::Exists($c.Ruta)) { continue }
            $aprob = Get-ValoresRegistro -Colmena $c.Colmena -Ruta $aprobado
            foreach ($archivo in ([IO.DirectoryInfo]$c.Ruta).GetFiles()) {
                if ($archivo.Name -ieq 'desktop.ini') { continue }
                $comando = $archivo.FullName
                $exe = $archivo.FullName
                if ($archivo.Extension -ieq '.lnk') {
                    if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                    # CreateShortcut sobre un .lnk existente solo lo lee (no se llama a Save).
                    $lnk = $shell.CreateShortcut($archivo.FullName)
                    $exe = $lnk.TargetPath
                    $comando = ("`"$($lnk.TargetPath)`" $($lnk.Arguments)").Trim()
                }
                ConvertTo-FilaArranque -Nombre $archivo.Name -Ubicacion $c.Etiqueta -Comando $comando -Ejecutable $exe -Habilitado (Test-AprobadoInicio @($aprob[$archivo.Name]))
            }
        }
    } finally {
        if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}

function Get-InicioStoreKit {
    # Tareas de inicio de apps empaquetadas (Teams, Spotify de la Store, etc.).
    # State: 0 deshabilitada, 1 deshabilitada por el usuario, 2 habilitada, 3 deshabilitada por política, 4 habilitada por política.
    $raiz = 'Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
    foreach ($paquete in (Get-SubclavesRegistro -Colmena HKCU -Ruta $raiz)) {
        foreach ($tarea in (Get-SubclavesRegistro -Colmena HKCU -Ruta "$raiz\$paquete")) {
            $estado = Get-ValorRegistro -Colmena HKCU -Ruta "$raiz\$paquete\$tarea" -Nombre 'State'
            if ($null -eq $estado) { continue }
            [pscustomobject][ordered]@{
                Nombre     = $tarea
                Ubicacion  = "Store: $($paquete -replace '_[a-z0-9]{13}$', '')"
                Habilitado = ([int]$estado -in 2, 4)
                Comando    = $paquete
                Ejecutable = $null
                Existe     = $null
                Empresa    = $null
                Sospecha   = $null
            }
        }
    }
}

function Get-TareasInicioKit {
    if (-not $script:Ctx.Admin.Elevado) { Add-Incompleto -Parte 'Tareas programadas protegidas o de otros usuarios' -Motivo 'sin admin algunas carpetas no son visibles' }
    $tareas = @(Get-Cim -Namespace 'Root/Microsoft/Windows/TaskScheduler' -Clase MSFT_ScheduledTask -Propiedades TaskName, TaskPath, Author, State, Triggers, Actions, Principal)
    foreach ($t in $tareas) {
        if ("$($t.TaskPath)" -like '\Microsoft\*') { continue }
        $disparadores = @()
        foreach ($tr in @($t.Triggers)) {
            if (-not $tr -or $tr.Enabled -eq $false) { continue }
            switch ($tr.CimClass.CimClassName) {
                'MSFT_TaskLogonTrigger' { $disparadores += 'inicio de sesión' }
                'MSFT_TaskBootTrigger' { $disparadores += 'arranque' }
            }
        }
        if ($disparadores.Count -eq 0) { continue }
        $accion = @($t.Actions) | Select-Object -First 1
        $exe = ''
        $comando = ''
        if ($accion -and $accion.CimClass.CimClassName -eq 'MSFT_TaskExecAction') {
            $exe = [Environment]::ExpandEnvironmentVariables("$($accion.Execute)".Trim('"'))
            $comando = ("`"$exe`" $($accion.Arguments)").Trim()
        } elseif ($accion) {
            $comando = "COM $($accion.ClassId)"
        }
        $exe = Resolve-RutaEjecutable $exe
        $empresa = Get-EmpresaArchivo $exe
        if ($empresa -match '^Microsoft' -or ("$($t.Author)" -match '^Microsoft' -and -not $exe)) { continue }
        [pscustomobject][ordered]@{
            Nombre     = "$($t.TaskPath)$($t.TaskName)"
            Ubicacion  = 'Tarea programada'
            Disparador = ($disparadores | Sort-Object -Unique) -join ', '
            Estado     = $script:EstadoTarea[[int]$t.State]
            Habilitado = ([int]$t.State -ne 1)
            Comando    = $comando
            Ejecutable = $exe
            Existe     = $(if ($exe -match '^[A-Za-z]:\\') { [IO.File]::Exists($exe) } else { $null })
            Empresa    = $empresa
            Autor      = $t.Author
            Usuario    = $(if ($t.Principal) { $t.Principal.UserId } else { $null })
            Sospecha   = Get-MotivoSospecha $comando
        }
    }
}

function Get-ServiciosTercerosKit {
    $servicios = @(Get-Cim -Clase Win32_Service -Filtro "StartMode='Auto'" -Propiedades Name, DisplayName, State, PathName, StartName)
    $terceros = foreach ($s in $servicios) {
        $exe = Resolve-RutaEjecutable (Get-RutaDesdeComando "$($s.PathName)")
        $binario = $exe
        $clave = "SYSTEM\CurrentControlSet\Services\$($s.Name)"
        if ($exe -match '(?i)\\svchost\.exe$') {
            # Algunas claves de servicios protegidos niegan la lectura: se sigue con el resto.
            $dll = $null
            try {
                $dll = Get-ValorRegistro -Colmena HKLM -Ruta "$clave\Parameters" -Nombre 'ServiceDll'
                if (-not $dll) { $dll = Get-ValorRegistro -Colmena HKLM -Ruta $clave -Nombre 'ServiceDll' }
            } catch {
                Write-LogKit -Mensaje "Sin acceso a ServiceDll de $($s.Name): $($_.Exception.Message)"
            }
            if ($dll) { $binario = [Environment]::ExpandEnvironmentVariables($dll) }
        }
        $empresa = Get-EmpresaArchivo $binario
        if ($empresa -match '^Microsoft') { continue }
        $retrasado = $false
        try { $retrasado = (Get-ValorRegistro -Colmena HKLM -Ruta $clave -Nombre 'DelayedAutostart') -eq 1 } catch { $retrasado = $false }
        [pscustomobject][ordered]@{
            Servicio   = $s.Name
            Nombre     = $s.DisplayName
            Estado     = $(if ($s.State -eq 'Running') { 'Corriendo' } elseif ($s.State -eq 'Stopped') { 'Detenido' } else { $s.State })
            Inicio     = $(if ($retrasado) { 'Automático (retrasado)' } else { 'Automático' })
            Comando    = $s.PathName
            Binario    = $binario
            Existe     = $(if ($binario -match '^[A-Za-z]:\\') { [IO.File]::Exists($binario) } else { $null })
            Empresa    = $empresa
            Cuenta     = $s.StartName
            Sospecha   = Get-MotivoSospecha "$($s.PathName)"
        }
    }
    [pscustomobject][ordered]@{ TotalAutomaticos = $servicios.Count; Terceros = @($terceros | Sort-Object Nombre) }
}

function Test-AlertasArranque {
    $d = $script:Ctx.Datos.arranque
    $habilitadas = @(@($d.Entradas) + @($d.AppsStore) | Where-Object { $_ -and $_.Habilitado -and $_.Ubicacion -notlike '*RunOnce*' })
    $max = Get-Umbral 'arranque_max'
    if ($habilitadas.Count -gt $max) {
        $nombres = @($habilitadas | ForEach-Object { $_.Nombre } | Select-Object -First 15) -join ', '
        Add-Alerta -Severidad AVISO -Codigo 'ARR-CANTIDAD' -Texto "$($habilitadas.Count) programas arrancan con Windows (más de $max): $nombres"
    }
    $todo = @(@($d.Entradas) + @($d.Tareas) | Where-Object { $_ })
    if ($d.Servicios) { $todo += @($d.Servicios.Terceros | Where-Object { $_ }) }
    foreach ($e in ($todo | Where-Object { $_.Sospecha })) {
        $nombre = if ($e.PSObject.Properties['Servicio']) { "servicio $($e.Servicio)" } else { "$($e.Nombre) ($($e.Ubicacion))" }
        $cmd = "$($e.Comando)"
        if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) + '...' }
        Add-Alerta -Severidad AVISO -Codigo 'ARR-SOSPECHOSO' -Texto "Arranque sospechoso: $nombre - $($e.Sospecha). Comando: $cmd"
    }
    $huerfanas = @($todo | Where-Object { $_.Existe -eq $false } | ForEach-Object { if ($_.PSObject.Properties['Servicio']) { "servicio $($_.Servicio)" } else { $_.Nombre } })
    if ($huerfanas.Count -gt 0) {
        Add-Alerta -Severidad INFO -Codigo 'ARR-HUERFANA' -Texto "Entradas de arranque que apuntan a archivos que no existen: $($huerfanas -join ', ')"
    }
    if ($d.Servicios) {
        # Los actualizadores (Google, Brave, Edge...) se detienen solos después de revisar: no cuentan.
        $detenidos = @($d.Servicios.Terceros | Where-Object { $_ -and $_.Estado -eq 'Detenido' -and $_.Inicio -eq 'Automático' -and "$($_.Servicio) $($_.Nombre)" -notmatch '(?i)updat|actualiza' } | ForEach-Object { $_.Nombre })
        if ($detenidos.Count -gt 0) {
            Add-Alerta -Severidad INFO -Codigo 'ARR-SERVICIO-DETENIDO' -Texto "Servicios automáticos de terceros detenidos (¿fallaron al iniciar?): $($detenidos -join ', ')"
        }
    }
    Add-AlertasSoftwareConocido -Hallazgos $d.Detectados -Prefijo 'ARR'
}

function Format-ResumenArranque {
    $d = $script:Ctx.Datos.arranque
    $t0 = $d.TiempoArranque
    if ($t0) {
        if ($t0.Disponible -and -not $t0.Vigente) { "Arranque   : sin medición reciente ($($t0.Motivo); ese arranque tardó $(Format-Numero $t0.UltimoSeg 1) s)" }
        elseif ($t0.Disponible) { "Arranque   : último $(Format-Numero $t0.UltimoSeg 1) s ($(Format-Numero $t0.EscritorioSeg 1) s hasta el escritorio + $(Format-Numero $t0.PosteriorSeg 1) s hasta quedar en reposo) el $($t0.Fecha) | mediana de los últimos 5: $(Format-Numero $t0.MedianaSeg 1) s" }
        else { "Arranque   : tiempo no disponible ($($t0.Motivo))" }
    }
    $entradas = @(@($d.Entradas) + @($d.AppsStore) | Where-Object { $_ })
    $hab = @($entradas | Where-Object { $_.Habilitado })
    "Al inicio  : $($hab.Count) habilitadas de $($entradas.Count) (Run, RunOnce, carpetas Inicio y apps de la Store)"
    foreach ($e in $hab) { "             + $($e.Nombre) [$($e.Ubicacion)]$(if ($e.Empresa) { ' - ' + $e.Empresa })$(if ($e.Existe -eq $false) { ' (NO EXISTE)' })" }
    $des = @($entradas | Where-Object { -not $_.Habilitado })
    if ($des.Count) { "             deshabilitadas: $(@($des | ForEach-Object { $_.Nombre }) -join ', ')" }
    $t = @($d.Tareas | Where-Object { $_ })
    "Tareas     : $($t.Count) tareas de terceros al iniciar sesión/arranque"
    foreach ($x in $t) { "             + $($x.Nombre) [$($x.Disparador), $($x.Estado)]$(if ($x.Empresa) { ' - ' + $x.Empresa })" }
    if ($d.Servicios) {
        $s = @($d.Servicios.Terceros)
        "Servicios  : $($d.Servicios.TotalAutomaticos) automáticos, $($s.Count) de terceros"
        foreach ($x in $s) { "             + $($x.Nombre) ($($x.Servicio)) [$($x.Estado), $($x.Inicio)]$(if ($x.Empresa) { ' - ' + $x.Empresa } else { ' - (sin empresa en el archivo)' })" }
    }
}
