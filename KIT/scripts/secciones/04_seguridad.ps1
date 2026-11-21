# 04 Seguridad: antivirus (Security Center y Defender), BitLocker / cifrado de dispositivo por volumen,
# VBS/HVCI, hipervisor (hypervisorlaunchtype), Secure Boot, TPM y control de aplicaciones
# (Smart App Control, WDAC, AppLocker, bloqueo de PowerShell). Solo se informa: nunca se desactiva nada.

$script:BitLockerShell = @{ 0 = 'Sin cifrar'; 1 = 'Activado'; 2 = 'Desactivado'; 3 = 'Cifrando'; 4 = 'Descifrando'; 5 = 'Suspendido'; 6 = 'Activado (bloqueado)'; 8 = 'Esperando activación' }
$script:BitLockerConversion = @{ 0 = 'Descifrado'; 1 = 'Cifrado'; 2 = 'Cifrando'; 3 = 'Descifrando'; 4 = 'Cifrado en pausa'; 5 = 'Descifrado en pausa' }
$script:Protector = @{ 0 = 'Desconocido'; 1 = 'TPM'; 2 = 'Clave externa'; 3 = 'Contraseña de recuperación'; 4 = 'TPM+PIN'; 5 = 'TPM+clave de inicio'; 6 = 'TPM+PIN+clave de inicio'; 7 = 'Clave pública'; 8 = 'Frase de contraseña'; 9 = 'Certificado TPM'; 10 = 'Cuenta/SID' }
$script:ServicioVbs = @{ 1 = 'Credential Guard'; 2 = 'Integridad de memoria (HVCI)'; 3 = 'System Guard Secure Launch'; 4 = 'Medición de firmware SMM'; 5 = 'Protección de pila por hardware'; 6 = 'Traducción de paginación por hipervisor' }
$script:EstadoSac = @{ 0 = 'Apagado'; 1 = 'Activado'; 2 = 'Evaluación' }
$script:EstadoCi = @{ 0 = 'Apagado'; 1 = 'Auditoría'; 2 = 'Obligatorio' }
$script:ModoAppLocker = @{ 0 = 'solo auditoría'; 1 = 'obligatorio' }

function Get-DatosSeguridad {
    $d = [ordered]@{}
    $d.Antivirus = Invoke-Paso 'Security Center' {
        @(Get-Cim -Namespace 'root/SecurityCenter2' -Clase AntiVirusProduct -Propiedades displayName, productState, pathToSignedProductExe) | ForEach-Object {
            $estado = [int64]$_.productState
            [pscustomobject][ordered]@{
                Nombre      = $_.displayName
                Activo      = (($estado -band 0x1000) -ne 0)
                FirmasAlDia = (($estado -band 0x10) -eq 0)
                EstadoHex   = '0x{0:X6}' -f $estado
                Ejecutable  = $_.pathToSignedProductExe
            }
        }
    }
    Add-Tabla -Nombre 'antivirus' -Filas $d.Antivirus
    $d.Defender = Get-DefenderKit
    $d.BitLocker = Invoke-Paso 'BitLocker' { Get-BitLockerKit }
    Add-Tabla -Nombre 'bitlocker' -Filas $d.BitLocker
    $d.Vbs = Invoke-Paso 'VBS' {
        $g = Get-Cim -Namespace 'root/Microsoft/Windows/DeviceGuard' -Clase Win32_DeviceGuard -Propiedades VirtualizationBasedSecurityStatus, SecurityServicesRunning, SecurityServicesConfigured
        $nombres = { param($lista) @($lista | Where-Object { $_ -gt 0 } | ForEach-Object { $n = $script:ServicioVbs[[int]$_]; if ($n) { $n } else { "servicio $_" } }) }
        [pscustomobject][ordered]@{
            Estado       = switch ([int]$g.VirtualizationBasedSecurityStatus) { 0 { 'Desactivado' } 1 { 'Configurado, no corriendo' } 2 { 'Corriendo' } default { "código $_" } }
            Corriendo    = ([int]$g.VirtualizationBasedSecurityStatus -eq 2)
            Servicios    = & $nombres $g.SecurityServicesRunning
            Configurados = & $nombres $g.SecurityServicesConfigured
            Hvci         = (@($g.SecurityServicesRunning) -contains 2)
        }
    }
    $d.Hipervisor = Invoke-Paso 'hipervisor' { Get-HipervisorKit }
    $d.SecureBoot = Invoke-Paso 'Secure Boot' {
        $v = Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Nombre 'UEFISecureBootEnabled'
        [pscustomobject][ordered]@{
            Firmware = $env:firmware_type
            Activo   = $(if ($null -eq $v) { $null } else { [int]$v -eq 1 })
            Estado   = $(if ($null -eq $v) { 'No soportado (BIOS Legacy o sin dato)' } elseif ([int]$v -eq 1) { 'Activado' } else { 'Desactivado' })
        }
    }
    $d.Tpm = Invoke-Paso 'TPM' { Get-TpmKit }
    $d.ControlApps = Invoke-Paso 'control de aplicaciones' { Get-ControlAppsKit }
    $d.Asr = Invoke-Paso 'reglas ASR' { Get-AsrKit }
    $d.Windows11 = Invoke-Paso 'apto para Windows 11' { Get-AptoWindows11 -SecureBoot $d.SecureBoot -Tpm $d.Tpm }
    # En las ediciones Home, BitLocker solo existe como "Cifrado de dispositivo".
    $d.NombreCifrado = if ($script:Ctx.Datos['windows'] -and $script:Ctx.Datos.windows.GrupoEdicion -eq 'hogar') { 'Cifrado de dispositivo' } else { 'BitLocker' }
    $d
}

function Get-ControlAppsKit {
    # Todo se lee del registro, de Win32_DeviceGuard y de Get-ExecutionPolicy: nada requiere admin.
    $sac = Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\CI\Policy' -Nombre 'VerifiedAndReputablePolicyState'
    $ciUsuario = $null
    $ciKernel = $null
    try {
        $g = Get-Cim -Namespace 'root/Microsoft/Windows/DeviceGuard' -Clase Win32_DeviceGuard -Propiedades UsermodeCodeIntegrityPolicyEnforcementStatus, CodeIntegrityPolicyEnforcementStatus
        $ciUsuario = $g.UsermodeCodeIntegrityPolicyEnforcementStatus
        $ciKernel = $g.CodeIntegrityPolicyEnforcementStatus
    } catch { Write-LogKit -Nivel AVISO -Mensaje "Win32_DeviceGuard no respondió: $($_.Exception.Message)" }
    # AppLocker: una subclave por colección (Exe, Script, Msi, Dll, Appx) con una subclave por regla.
    $raiz = 'SOFTWARE\Policies\Microsoft\Windows\SrpV2'
    $colecciones = foreach ($c in @(Get-SubclavesRegistro -Colmena HKLM -Ruta $raiz)) {
        $reglas = @(Get-SubclavesRegistro -Colmena HKLM -Ruta "$raiz\$c").Count
        if ($reglas -eq 0) { continue }
        $modo = Get-ValorRegistro -Colmena HKLM -Ruta "$raiz\$c" -Nombre 'EnforcementMode'
        '{0}: {1} reglas ({2})' -f $c, $reglas, $(if ($null -ne $modo -and $script:ModoAppLocker.ContainsKey([int]$modo)) { $script:ModoAppLocker[[int]$modo] } else { 'modo sin definir' })
    }
    $appId = Get-Cim -Clase Win32_Service -Filtro "Name='AppIDSvc'" -Propiedades State
    # UAC: desactivado o sin escritorio seguro (típico de optimizadores). Con el aviso en el escritorio
    # normal, una ventana puede tapar el aviso o quedarse con las teclas.
    $pol = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $uac = [ordered]@{
        Activo          = (Get-ValorRegistro -Colmena HKLM -Ruta $pol -Nombre 'EnableLUA') -ne 0
        EscritorioSeguro = (Get-ValorRegistro -Colmena HKLM -Ruta $pol -Nombre 'PromptOnSecureDesktop') -ne 0
        AvisoAdmin      = Get-ValorRegistro -Colmena HKLM -Ruta $pol -Nombre 'ConsentPromptBehaviorAdmin'
    }
    $gpo = @('MachinePolicy', 'UserPolicy' | ForEach-Object {
            $p = Get-ExecutionPolicy -Scope $_
            if ("$p" -ne 'Undefined') { "$_=$p" }
        })
    $texto = { param($tabla, $v) if ($null -eq $v) { $null } elseif ($tabla.ContainsKey([int]$v)) { $tabla[[int]$v] } else { "código $v" } }
    [pscustomobject][ordered]@{
        SmartAppControl   = $(if ($null -eq $sac) { 'No disponible (Windows 10 o build anterior)' } else { & $texto $script:EstadoSac $sac })
        SacActivo         = ($null -ne $sac -and [int]$sac -eq 1)
        WdacUsuario       = & $texto $script:EstadoCi $ciUsuario
        WdacKernel        = & $texto $script:EstadoCi $ciKernel
        AppLocker         = @($colecciones)
        AppLockerServicio = $(if ($appId) { "$($appId.State)" } else { $null })
        ModoLenguaje      = "$($ExecutionContext.SessionState.LanguageMode)"
        BloqueoPowerShell = [Environment]::GetEnvironmentVariable('__PSLockdownPolicy', 'Machine')
        PoliticaGpo       = $gpo
        Uac               = [pscustomobject]$uac
    }
}

function Get-DefenderKit {
    # Si hay otro antivirus, Defender puede estar en pasivo o apagado y la consulta fallar: no es error del kit.
    try {
        $m = Get-Cim -Namespace 'root/Microsoft/Windows/Defender' -Clase MSFT_MpComputerStatus -Propiedades AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated, AntivirusSignatureAge, AMRunningMode, IsTamperProtected, AMProductVersion, AntivirusSignatureVersion
        [pscustomobject][ordered]@{
            Disponible       = $true
            Modo             = $m.AMRunningMode
            Antivirus        = [bool]$m.AntivirusEnabled
            TiempoReal       = [bool]$m.RealTimeProtectionEnabled
            ProteccionAlteraciones = [bool]$m.IsTamperProtected
            FirmasDias       = $m.AntivirusSignatureAge
            FirmasFecha      = ConvertTo-TextoFecha $m.AntivirusSignatureLastUpdated -SoloFecha
            VersionFirmas    = $m.AntivirusSignatureVersion
            VersionMotor     = $m.AMProductVersion
            Motivo           = $null
        }
    } catch {
        Write-LogKit -Nivel AVISO -Mensaje "Defender no respondió: $($_.Exception.Message)"
        [pscustomobject][ordered]@{ Disponible = $false; Modo = $null; Antivirus = $false; TiempoReal = $false; ProteccionAlteraciones = $null; FirmasDias = $null; FirmasFecha = $null; VersionFirmas = $null; VersionMotor = $null; Motivo = $_.Exception.Message.Trim() }
    }
}

function Get-BitLockerKit {
    if ($script:Ctx.Admin.Elevado) {
        $vols = @(Get-Cim -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -Clase Win32_EncryptableVolume)
        foreach ($v in $vols) {
            $tipos = @()
            try {
                $ids = (Invoke-CimMethod -InputObject $v -MethodName GetKeyProtectors -Arguments @{ KeyProtectorType = [uint32]0 } -ErrorAction Stop).VolumeKeyProtectorID
                foreach ($id in @($ids)) {
                    $t = (Invoke-CimMethod -InputObject $v -MethodName GetKeyProtectorType -Arguments @{ VolumeKeyProtectorID = $id } -ErrorAction Stop).KeyProtectorType
                    $tipos += $(if ($script:Protector[[int]$t]) { $script:Protector[[int]$t] } else { "tipo $t" })
                }
            } catch {
                Write-LogKit -Nivel AVISO -Mensaje "No se pudieron leer los protectores de $($v.DriveLetter): $($_.Exception.Message)"
            }
            [pscustomobject][ordered]@{
                Volumen     = $(if ($v.DriveLetter) { $v.DriveLetter } else { '(sin letra)' })
                Estado      = $(if ($script:BitLockerConversion[[int]$v.ConversionStatus]) { $script:BitLockerConversion[[int]$v.ConversionStatus] } else { "código $($v.ConversionStatus)" })
                Protegido   = ([int]$v.ProtectionStatus -eq 1)
                Cifrado     = ([int]$v.ConversionStatus -in 1, 2, 4)
                Protectores = @($tipos | Sort-Object -Unique)
                Fuente      = 'Win32_EncryptableVolume'
            }
        }
        return
    }
    Add-Incompleto -Parte 'BitLocker (protectores y estado exacto)'
    $shell = New-Object -ComObject Shell.Application
    try {
        foreach ($ld in @(Get-Cim -Clase Win32_LogicalDisk -Filtro 'DriveType=3' -Propiedades DeviceID)) {
            $valor = $shell.NameSpace("$($ld.DeviceID)\").Self.ExtendedProperty('System.Volume.BitLockerProtection')
            $codigo = if ($null -eq $valor) { -1 } else { [int]$valor }
            [pscustomobject][ordered]@{
                Volumen     = $ld.DeviceID
                Estado      = $(if ($script:BitLockerShell.ContainsKey($codigo)) { $script:BitLockerShell[$codigo] } else { "código $codigo" })
                Protegido   = ($codigo -in 1, 6)
                Cifrado     = ($codigo -in 1, 3, 5, 6, 8)
                Protectores = @()
                Fuente      = "Shell (sin admin, código $codigo)"
            }
        }
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function Get-HipervisorKit {
    $cs = Get-Cim -Clase Win32_ComputerSystem -Propiedades HypervisorPresent
    $caracteristicas = @(Get-Cim -Clase Win32_OptionalFeature -Filtro "InstallState=1 AND (Name='Microsoft-Hyper-V-All' OR Name='Microsoft-Hyper-V-Hypervisor' OR Name='VirtualMachinePlatform' OR Name='Microsoft-Windows-Subsystem-Linux' OR Name='HypervisorPlatform' OR Name='Containers-DisposableClientVM')" -Propiedades Name) |
        ForEach-Object { $_.Name }
    $lanzamiento = $null
    if ($script:Ctx.Admin.Elevado) {
        $r = Invoke-Externo -Exe (Get-RutaSistema 'bcdedit.exe') -Argumentos '/enum {current}'
        if ($r.Codigo -eq 0) {
            $m = [regex]::Match($r.Salida, '(?im)^hypervisorlaunchtype\s+(\S+)')
            $lanzamiento = if ($m.Success) { $m.Groups[1].Value } else { 'no definido' }
        } else {
            Write-LogKit -Nivel AVISO -Mensaje "bcdedit terminó con código $($r.Codigo): $($r.Salida.Trim()) $($r.Error.Trim())"
        }
    } else {
        Add-Incompleto -Parte 'hypervisorlaunchtype (bcdedit)'
    }
    [pscustomobject][ordered]@{
        Presente              = [bool]$cs.HypervisorPresent
        Hypervisorlaunchtype  = $lanzamiento
        Caracteristicas       = @($caracteristicas)
    }
}

function Get-TpmKit {
    $pnp = @(Get-Cim -Clase Win32_PnPEntity -Filtro "PNPClass='SecurityDevices'" -Propiedades Name, PNPDeviceID, ConfigManagerErrorCode)
    $nombre = $null
    $version = $null
    if ($pnp.Count -gt 0) {
        $nombre = $pnp[0].Name
        if ($nombre -match '(\d\.\d)\s*$') { $version = $Matches[1] }
    }
    $r = [ordered]@{ Presente = ($pnp.Count -gt 0); Nombre = $nombre; Version = $version; Habilitado = $null; Activado = $null; Fabricante = $null; Fuente = 'PnP' }
    if ($script:Ctx.Admin.Elevado) {
        $t = Invoke-Paso 'Win32_Tpm' { Get-Cim -Namespace 'root/cimv2/Security/MicrosoftTpm' -Clase Win32_Tpm }
        if ($t) {
            $r.Presente = $true
            $r.Version = ("$($t.SpecVersion)" -split ',')[0].Trim()
            $r.Habilitado = [bool]$t.IsEnabled_InitialValue
            $r.Activado = [bool]$t.IsActivated_InitialValue
            $r.Fabricante = "$($t.ManufacturerIdTxt) $($t.ManufacturerVersion)".Trim()
            $r.Fuente = 'Win32_Tpm'
        }
    } else {
        Add-Incompleto -Parte 'TPM (habilitado/activado)'
    }
    [pscustomobject]$r
}

$script:NombreAsr = @{
    '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'controladores vulnerables firmados'
    '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Adobe Reader crea procesos hijos'
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Office crea procesos hijos'
    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'robo de credenciales de LSASS'
    'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'ejecutables desde el correo'
    '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'ejecutables poco comunes'
    '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'scripts ofuscados'
    'd3e037e1-3eb8-44c8-a917-57927947596d' = 'JavaScript/VBScript que lanza descargas'
    '3b576869-a4ec-4529-8536-b80a7769e899' = 'Office crea ejecutables'
    '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Office inyecta código'
    '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Outlook crea procesos hijos'
    'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'persistencia por WMI'
    'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'procesos desde PSExec y WMI'
    '33ddedf1-c6e0-47cb-833e-de6133960387' = 'reinicio en modo seguro'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'procesos sin firma desde USB'
    'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 'herramientas de sistema copiadas'
    'a8f5898e-1dc8-49a9-9878-85004b8a61e6' = 'webshells en servidores'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'llamadas Win32 desde macros'
    'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'protección avanzada contra ransomware'
}

function Get-AsrKit {
    # Reglas de reducción de la superficie de ataque (ASR) de Defender. Solo lee: 0 apagada, 1 bloquear,
    # 2 auditar, 6 advertir. Sin Defender activo no aplican.
    $p = Get-Cim -Namespace 'root/Microsoft/Windows/Defender' -Clase MSFT_MpPreference -Propiedades AttackSurfaceReductionRules_Ids, AttackSurfaceReductionRules_Actions
    $ids = @($p.AttackSurfaceReductionRules_Ids | Where-Object { $_ })
    $acc = @($p.AttackSurfaceReductionRules_Actions)
    $reglas = for ($i = 0; $i -lt $ids.Count; $i++) {
        $a = if ($i -lt $acc.Count) { [int]$acc[$i] } else { 0 }
        $id = "$($ids[$i])".ToLowerInvariant()
        [pscustomobject][ordered]@{
            Id     = $id
            Nombre = $(if ($script:NombreAsr[$id]) { $script:NombreAsr[$id] } else { 'regla ' + $id.Substring(0, 8) })
            Modo   = switch ($a) { 0 { 'Apagada' } 1 { 'Bloquear' } 2 { 'Auditar' } 6 { 'Advertir' } default { "código $a" } }
        }
    }
    $reglas = @($reglas)
    [pscustomobject][ordered]@{
        Reglas    = $reglas
        Bloquear  = @($reglas | Where-Object { $_.Modo -in 'Bloquear', 'Advertir' }).Count
        Auditar   = @($reglas | Where-Object { $_.Modo -eq 'Auditar' }).Count
    }
}

function Test-CpuWindows11 {
    # Aproximación por el nombre a la lista de CPU de Windows 11: 'si', 'no' o 'revisar'.
    param([AllowEmptyString()][string]$Nombre)
    $n = "$Nombre"
    if ($n -match 'Core\(TM\)\s*Ultra|Core Ultra|Intel\(R\) N\d{2,3}\b|\bi3-N\d{3}\b|Ryzen AI') { return 'si' }
    if ($n -match '\bi[3579]-(\d{4,5})') {
        $num = $Matches[1]
        $gen = if ($num.Length -eq 5) { [int]$num.Substring(0, 2) } else { [int]$num.Substring(0, 1) }
        if ($gen -ge 8) { return 'si' } else { return 'no' }
    }
    if ($n -match 'Core\(TM\)\s*[3579]\s+\d{3}') { return 'si' }   # Core 5 120U, Core 7 150U (2023+)
    if ($n -match 'Ryzen\s+(Threadripper\s+)?(AI\s+)?[3579]?\s*(PRO\s+)?(\d)\d{3}') {
        $g = [int]$Matches[4]
        if ($n -match 'Ryzen AI') { return 'si' }
        if ($g -ge 3) { return 'si' } elseif ($g -eq 2) { return 'revisar' } else { return 'no' }
    }
    if ($n -match 'Ryzen\s+(AI\s+)?\d\s+\d{3}\b') { return 'si' }   # Ryzen 5 220, Ryzen AI 9 365
    if ($n -match 'Core\(TM\)2|Core 2|Pentium\(R\) (Dual|D)|Athlon\(tm\) II|Phenom|\bA(4|6|8|10|12)-\d{4}') { return 'no' }
    'revisar'
}

function Get-AptoWindows11 {
    # Requisitos de Windows 11: CPU de la lista, TPM 2.0, UEFI con Secure Boot posible, 4 GB de RAM y
    # 64 GB de disco. Sirve para ofrecer la actualización a equipos que todavía tienen Windows 10.
    param($SecureBoot, $Tpm)
    $hw = $script:Ctx.Datos['hardware']
    $cpu = if ($hw -and @($hw.Cpu).Count) { "$(@($hw.Cpu)[0].Nombre)" } else { '' }
    $ram = if ($hw -and $hw.Ram) { [double]$hw.Ram.TotalGB } else { $null }
    $disco = if ($hw) { @($hw.Discos | Where-Object { $_ -and $_.Sistema }) | Select-Object -First 1 } else { $null }
    $req = [ordered]@{
        Cpu        = Test-CpuWindows11 $cpu
        Tpm        = $(if (-not $Tpm) { 'revisar' } elseif ($Tpm.Presente -and "$($Tpm.Version)" -like '2*') { 'si' } elseif ($Tpm.Presente -or $null -eq $Tpm.Presente) { 'no' } else { 'revisar' })
        Uefi       = $(if ($SecureBoot -and "$($SecureBoot.Firmware)" -eq 'UEFI') { 'si' } elseif ($SecureBoot -and "$($SecureBoot.Firmware)" -eq 'Legacy') { 'no' } else { 'revisar' })
        SecureBoot = $(if ($SecureBoot -and $SecureBoot.Activo) { 'si' } elseif ($SecureBoot -and "$($SecureBoot.Firmware)" -eq 'UEFI') { 'activable' } else { 'revisar' })
        Ram        = $(if ($null -eq $ram -or $ram -le 0) { 'revisar' } elseif ($ram -ge 4) { 'si' } else { 'no' })
        Disco      = $(if (-not $disco) { 'revisar' } elseif ([double]$disco.TamanoGB -ge 64) { 'si' } else { 'no' })
    }
    $valores = @($req.Values)
    $faltan = @($req.Keys | Where-Object { $req[$_] -eq 'no' })
    $dudas = @($req.Keys | Where-Object { $req[$_] -eq 'revisar' })
    $veredicto = if ($faltan.Count) { 'No' } elseif ($dudas.Count) { 'Revisar' } else { 'Sí' }
    $nota = if ($valores -contains 'activable' -and -not $faltan.Count) { 'Secure Boot está apagado: hay que activarlo en la BIOS antes de actualizar.' } else { $null }
    [pscustomobject][ordered]@{
        Apto       = $veredicto
        Requisitos = [pscustomobject]$req
        Faltan     = $faltan
        Revisar    = $dudas
        Cpu        = $cpu
        Nota       = $nota
    }
}

function Test-AlertasSeguridad {
    $d = $script:Ctx.Datos.seguridad
    $av = @($d.Antivirus | Where-Object { $_ })
    $activos = @($av | Where-Object { $_.Activo })
    $defenderProtege = $d.Defender -and $d.Defender.TiempoReal
    if (($av.Count -gt 0 -and $activos.Count -eq 0) -or ($av.Count -eq 0 -and -not $defenderProtege)) {
        Add-Alerta -Severidad CRITICO -Codigo 'SEG-SIN-AV' -Texto 'Ningún antivirus activo (Defender apagado y nada activo en Seguridad de Windows)'
    }
    if ($activos.Count -gt 1) {
        Add-Alerta -Severidad AVISO -Codigo 'SEG-AV-MULTIPLE' -Texto "Más de un antivirus activo: $(@($activos | ForEach-Object { $_.Nombre }) -join ', ')"
    }
    foreach ($a in $activos) {
        if (-not $a.FirmasAlDia -and $a.Nombre -notmatch 'Defender') {
            Add-Alerta -Severidad AVISO -Codigo 'SEG-AV-FIRMAS' -Texto "$($a.Nombre) reporta firmas desactualizadas"
        }
    }
    if ($d.Defender -and $d.Defender.Disponible -and $d.Defender.Modo -eq 'Normal' -and $null -ne $d.Defender.FirmasDias) {
        $dias = Get-Umbral 'defender_firmas_dias'
        if ($d.Defender.FirmasDias -gt $dias) {
            Add-Alerta -Severidad AVISO -Codigo 'SEG-AV-FIRMAS' -Texto "Firmas de Defender con $($d.Defender.FirmasDias) días (último: $($d.Defender.FirmasFecha))"
        }
    }
    foreach ($b in @($d.BitLocker | Where-Object { $_ })) {
        if ($b.Protegido) {
            $prot = if ($b.Protectores.Count -gt 0) { " (protectores: $($b.Protectores -join ', '))" } else { '' }
            Add-Alerta -Severidad AVISO -Codigo 'SEG-BITLOCKER' -Texto "$($d.NombreCifrado) activo en $($b.Volumen)$prot. Confirma la clave de recuperación ANTES de tocar BIOS, TPM o arranque (cuenta Microsoft: aka.ms/myrecoverykey)"
        } elseif ($b.Cifrado) {
            Add-Alerta -Severidad INFO -Codigo 'SEG-BITLOCKER' -Texto "Volumen $($b.Volumen) cifrado pero sin protección activa ($($b.Estado))"
        }
    }
    if ($d.Vbs -and $d.Vbs.Corriendo) {
        $serv = if ($d.Vbs.Servicios.Count -gt 0) { " ($($d.Vbs.Servicios -join ', '))" } else { '' }
        Add-Alerta -Severidad INFO -Codigo 'SEG-VBS' -Texto "VBS activo${serv}: puede restar FPS en juegos; es una función de seguridad, no un error"
    }
    if ($d.Hipervisor -and ($d.Hipervisor.Presente -or ($d.Hipervisor.Hypervisorlaunchtype -and $d.Hipervisor.Hypervisorlaunchtype -notin 'Off', 'no definido'))) {
        $partes = @()
        if ($d.Hipervisor.Hypervisorlaunchtype) { $partes += "hypervisorlaunchtype=$($d.Hipervisor.Hypervisorlaunchtype)" }
        if ($d.Hipervisor.Caracteristicas.Count -gt 0) { $partes += "características: $($d.Hipervisor.Caracteristicas -join ', ')" }
        Add-Alerta -Severidad INFO -Codigo 'SEG-HIPERVISOR' -Texto ("Hipervisor activo" + $(if ($partes) { ' (' + ($partes -join '; ') + ')' } else { '' }))
    }
    if ($d.SecureBoot -and $d.SecureBoot.Activo -ne $true) {
        Add-Alerta -Severidad AVISO -Codigo 'SEG-SECUREBOOT' -Texto "Secure Boot: $($d.SecureBoot.Estado). Lo exigen Windows 11 y anti-cheats como Valorant y Battlefield 6"
    }
    if ($d.Tpm -and (-not $d.Tpm.Presente -or ($d.Tpm.Version -and $d.Tpm.Version -notlike '2*'))) {
        $txt = if ($d.Tpm.Presente) { "TPM $($d.Tpm.Version)" } else { 'Sin TPM visible (puede estar apagado en la BIOS)' }
        Add-Alerta -Severidad AVISO -Codigo 'SEG-TPM' -Texto "$txt. Windows 11 y algunos anti-cheats piden TPM 2.0"
    }
    if ($d.Asr -and $d.Asr.Bloquear -gt 0) {
        Add-Alerta -Severidad INFO -Codigo 'SEG-ASR' -Texto "Defender con $($d.Asr.Bloquear) regla(s) ASR bloqueando ($(@($d.Asr.Reglas | Where-Object { $_.Modo -in 'Bloquear', 'Advertir' } | ForEach-Object { $_.Nombre }) -join '; ')): equipo endurecido, pueden frenar herramientas portables o scripts. No las desactives"
    }
    $w11 = $d.Windows11
    $win = $script:Ctx.Datos['windows']
    if ($w11 -and $win -and [int]$win.Build -gt 0 -and [int]$win.Build -lt 22000) {
        switch ($w11.Apto) {
            'Sí' { Add-Alerta -Severidad INFO -Codigo 'SEG-WIN11' -Texto "Apto para Windows 11: se puede ofrecer la actualización (Windows 10 ya no recibe actualizaciones de seguridad)$(if ($w11.Nota) { '. ' + $w11.Nota })" }
            'No' { Add-Alerta -Severidad AVISO -Codigo 'SEG-WIN11' -Texto "No cumple los requisitos de Windows 11 (falta: $($w11.Faltan -join ', ')): conversar opciones con el cliente (cambio de equipo o de pieza, o seguir con Windows 10 sabiendo el riesgo)" }
            default { Add-Alerta -Severidad INFO -Codigo 'SEG-WIN11' -Texto "Windows 11: revisar a mano $($w11.Revisar -join ', ') (CPU: $($w11.Cpu))" }
        }
    }
    $c = $d.ControlApps
    if ($c) {
        if ($c.SacActivo) {
            Add-Alerta -Severidad AVISO -Codigo 'SEG-SAC' -Texto 'Smart App Control activado: puede bloquear herramientas portables sin firma reconocida. No lo desactives en el equipo del cliente; usa las que sí abran'
        } elseif ($c.SmartAppControl -eq 'Evaluación') {
            Add-Alerta -Severidad INFO -Codigo 'SEG-SAC' -Texto 'Smart App Control en evaluación: Windows decidirá si lo activa; si se activa, puede bloquear herramientas portables'
        }
        if (-not $c.SacActivo -and $c.WdacUsuario -in 'Obligatorio', 'Auditoría') {
            $sev = if ($c.WdacUsuario -eq 'Obligatorio') { 'AVISO' } else { 'INFO' }
            Add-Alerta -Severidad $sev -Codigo 'SEG-WDAC' -Texto "Control de aplicaciones (WDAC) en modo $($c.WdacUsuario.ToLower()): equipo administrado; puede bloquear herramientas y scripts"
        }
        if ($c.AppLocker.Count -gt 0) {
            $sev = if ($c.AppLockerServicio -eq 'Running') { 'AVISO' } else { 'INFO' }
            Add-Alerta -Severidad $sev -Codigo 'SEG-APPLOCKER' -Texto "AppLocker con reglas ($($c.AppLocker -join '; ')), servicio AppIDSvc: $($c.AppLockerServicio)"
        }
        if ($c.Uac -and -not $c.Uac.Activo) {
            Add-Alerta -Severidad AVISO -Codigo 'SEG-UAC' -Texto 'Control de cuentas de usuario (UAC) desactivado: cualquier programa corre con permisos de administrador. Sugiere al cliente volver a activarlo'
        } elseif ($c.Uac -and (-not $c.Uac.EscritorioSeguro -or $c.Uac.AvisoAdmin -eq 0)) {
            Add-Alerta -Severidad AVISO -Codigo 'SEG-UAC' -Texto "UAC rebajado ($(if (-not $c.Uac.EscritorioSeguro) { 'aviso fuera del escritorio seguro' } else { 'eleva sin preguntar' })), típico de optimizadores: sugiere al cliente dejarlo en el nivel predeterminado"
        }
        if ($c.BloqueoPowerShell -or $c.PoliticaGpo.Count -gt 0) {
            $partes = @($c.PoliticaGpo)
            if ($c.BloqueoPowerShell) { $partes += "__PSLockdownPolicy=$($c.BloqueoPowerShell)" }
            Add-Alerta -Severidad INFO -Codigo 'SEG-PS-POLITICA' -Texto "PowerShell restringido por política ($($partes -join ', ')): -ExecutionPolicy Bypass no pasa por encima de esto"
        }
    }
}

function Format-ResumenSeguridad {
    $d = $script:Ctx.Datos.seguridad
    foreach ($a in @($d.Antivirus | Where-Object { $_ })) { "Antivirus  : $($a.Nombre) | activo: $(if ($a.Activo) { 'sí' } else { 'no' }) | firmas al día: $(if ($a.FirmasAlDia) { 'sí' } else { 'no' }) ($($a.EstadoHex))" }
    if ($d.Defender) {
        if ($d.Defender.Disponible) { "Defender   : modo $($d.Defender.Modo) | tiempo real: $(if ($d.Defender.TiempoReal) { 'sí' } else { 'no' }) | protección contra alteraciones: $(if ($d.Defender.ProteccionAlteraciones) { 'sí' } else { 'no' }) | firmas $($d.Defender.FirmasFecha) ($($d.Defender.FirmasDias) días)" }
        else { "Defender   : no responde ($($d.Defender.Motivo))" }
    }
    foreach ($b in @($d.BitLocker | Where-Object { $_ })) { "Cifrado    : $($d.NombreCifrado) $($b.Volumen) $($b.Estado) | protegido: $(if ($b.Protegido) { 'sí' } else { 'no' })$(if ($b.Protectores.Count) { ' | ' + ($b.Protectores -join ', ') }) | fuente: $($b.Fuente)" }
    if ($d.Vbs) { "VBS        : $($d.Vbs.Estado)$(if ($d.Vbs.Servicios.Count) { ' | ' + ($d.Vbs.Servicios -join ', ') })" }
    if ($d.Hipervisor) { "Hipervisor : presente: $(if ($d.Hipervisor.Presente) { 'sí' } else { 'no' }) | hypervisorlaunchtype: $(if ($d.Hipervisor.Hypervisorlaunchtype) { $d.Hipervisor.Hypervisorlaunchtype } else { '(requiere admin)' }) | $(if ($d.Hipervisor.Caracteristicas.Count) { $d.Hipervisor.Caracteristicas -join ', ' } else { 'sin características de virtualización' })" }
    if ($d.SecureBoot) { "Secure Boot: $($d.SecureBoot.Estado) | firmware $($d.SecureBoot.Firmware)" }
    if ($d.Tpm) { "TPM        : $(if ($d.Tpm.Presente) { "$($d.Tpm.Nombre) | versión $($d.Tpm.Version)" } else { 'no visible' })$(if ($null -ne $d.Tpm.Habilitado) { " | habilitado: $($d.Tpm.Habilitado) | activado: $($d.Tpm.Activado) | $($d.Tpm.Fabricante)" })" }
    if ($d.Asr) { "ASR        : $(if (@($d.Asr.Reglas).Count) { "$($d.Asr.Bloquear) bloqueando, $($d.Asr.Auditar) en auditoría, de $(@($d.Asr.Reglas).Count) configuradas" } else { 'sin reglas configuradas' })" }
    if ($d.Windows11) {
        $rq = $d.Windows11.Requisitos
        "Windows 11 : apto: $($d.Windows11.Apto) | CPU $($rq.Cpu) | TPM 2.0 $($rq.Tpm) | UEFI $($rq.Uefi) | Secure Boot $($rq.SecureBoot) | RAM $($rq.Ram) | disco $($rq.Disco)"
    }
    $c = $d.ControlApps
    if ($c) {
        "Control app: Smart App Control $($c.SmartAppControl) | WDAC usuario $($c.WdacUsuario) / kernel $($c.WdacKernel) | AppLocker: $(if ($c.AppLocker.Count) { $c.AppLocker -join '; ' } else { 'sin reglas' })"
        "PowerShell : modo $($c.ModoLenguaje) | política por GPO: $(if ($c.PoliticaGpo.Count) { $c.PoliticaGpo -join ', ' } else { 'ninguna' })$(if ($c.BloqueoPowerShell) { " | __PSLockdownPolicy=$($c.BloqueoPowerShell)" })"
    }
}
