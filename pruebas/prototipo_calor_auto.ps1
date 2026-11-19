#Requires -Version 5.1
<#
.SYNOPSIS
    PROTOTIPO (no va al pendrive): prueba CALOR sola, sin tocar nada. HWiNFO graba el CSV de sensores
    mientras OCCT carga la CPU, y al final se revisa el CSV con el mismo lector del kit.
.DESCRIPTION
    Pasos: abre HWiNFO (Enter a su diálogo inicial) -> empieza a grabar (botón 1437 + "Guardar como") ->
    espera -ReposoMin en reposo -> abre OCCT y aprieta START dos veces (la versión gratis muestra ~10 s su
    pantalla de apoyo entre medio) -> carga -Minutos -> cierra OCCT -> detiene la grabación -> cierra HWiNFO.
    Necesita administrador (OCCT y HWiNFO lo piden). Usa un P/Invoke a user32 (PostMessage) para apretar el
    botón de grabar de HWiNFO: eso compila código en %TEMP%, algo que las reglas del kit no permiten; por eso
    vive en pruebas\ hasta que Isaac decida si la herramienta remota lleva esa excepción.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\pruebas\prototipo_calor_auto.ps1 -Minutos 1 -ReposoMin 0
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Prototipo de consola')]
param(
    [double]$Minutos = 10,
    [double]$ReposoMin = 5,
    [string]$Salida = (Join-Path $env:TEMP 'kit_calor_auto'),
    [string]$Herramientas = (Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\herramientas')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace KitProto -Name W32 -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint m, System.IntPtr w, System.IntPtr l);'
$A = [System.Windows.Automation.AutomationElement]
$cw = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
function Log([string]$t) { [Console]::WriteLine(('{0}  {1}' -f (Get-Date -Format HH:mm:ss), $t)) }
function Get-CpuTotal { [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average }
function Find-Ventana([string]$Patron, [string]$Proceso, [int]$Seg) {
    $fin = (Get-Date).AddSeconds($Seg)
    while ((Get-Date) -lt $fin) {
        $pids = @(Get-Process | Where-Object { $_.ProcessName -match $Proceso } | ForEach-Object Id)
        $v = @($A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cw)) | Where-Object { try { ($pids -contains $_.Current.ProcessId) -and $_.Current.Name -match $Patron } catch { $false } } | Select-Object -First 1
        if ($v) { return $v }
        Start-Sleep -Milliseconds 400
    }
    $null
}
function Get-PorId($Raiz, [string]$Id, [string]$Alcance = 'Children') {
    $Raiz.FindFirst([System.Windows.Automation.TreeScope]::$Alcance, (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, $Id)))
}
function Invoke-Elemento($e) { $p = $null; if ($e -and $e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return $true }; $false }
function Get-StartHabilitado($v) {
    # "START" en la pantalla de la prueba y "Start" en el diálogo "Enjoying OCCT?" de la versión gratis.
    $c = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    @($v.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)) | Where-Object { try { $_.Current.Name -ieq 'start' -and $_.Current.IsEnabled -and $_.Current.BoundingRectangle.Width -gt 0 } catch { $false } } | Select-Object -First 1
}
function Close-Proceso([string]$Patron) {
    foreach ($x in @(Get-Process | Where-Object { $_.ProcessName -match $Patron })) { try { $null = $x.CloseMainWindow() } catch {} }
    Start-Sleep -Seconds 4
    @(Get-Process | Where-Object { $_.ProcessName -match $Patron }) | Stop-Process -Force -ErrorAction SilentlyContinue
}

$null = [IO.Directory]::CreateDirectory($Salida)
$csv = Join-Path $Salida ('calor_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$hwExe = Join-Path $Herramientas 'HWiNFO\HWiNFO64.exe'
$occtExe = Join-Path $Herramientas 'OCCT\OCCT.exe'
$grabando = $false
try {
    # 1. HWiNFO en sensores
    $sens = Find-Ventana '(?i)sensor' '(?i)hwinfo' 1
    if (-not $sens) {
        Log 'Abriendo HWiNFO'
        $null = Start-Process -FilePath $hwExe
        $ini = Find-Ventana '(?i)HWiNFO' '(?i)hwinfo' 40
        if (-not $ini) { throw 'HWiNFO no abrió' }
        Start-Sleep -Milliseconds 800
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')   # "Iniciar" es el botón por defecto del diálogo
        $sens = Find-Ventana '(?i)sensor' '(?i)hwinfo' 40
        if (-not $sens) { throw 'No apareció la ventana de sensores de HWiNFO' }
    }
    $upd = Find-Ventana '(?i)update' '(?i)hwinfo' 2
    if ($upd) { try { $wp = $upd.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern); $wp.Close(); Log 'Cerré el aviso de actualización de HWiNFO' } catch {} }
    Log 'HWiNFO en sensores'

    # 2. Empezar a grabar
    $btn = Get-PorId $sens '1437'
    if (-not $btn) { throw 'No encontré el botón de grabar (1437)' }
    $null = [KitProto.W32]::PostMessage([IntPtr]$btn.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
    # El "Guardar como" (de HWiNFO, título "Guardar como"/"Save As"); dentro tiene ventanas internas que no sirven.
    $fin = (Get-Date).AddSeconds(10); $dlg = $null
    while (-not $dlg -and (Get-Date) -lt $fin) {
        $pids = @(Get-Process | Where-Object { $_.ProcessName -match '(?i)hwinfo' } | ForEach-Object Id)
        $dlg = @($A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cw)) | Where-Object { try { ($pids -contains $_.Current.ProcessId) -and $_.Current.Name -match '(?i)^(guardar como|save as)$' } catch { $false } } | Select-Object -First 1
        if (-not $dlg) { Start-Sleep -Milliseconds 300 }
    }
    if (-not $dlg) { throw 'No apareció el "Guardar como" de HWiNFO' }
    $ed = $null; $fin = (Get-Date).AddSeconds(10)
    # El campo es el Edit con id 1001 (hay otro elemento con el mismo id que no es Edit). El diálogo tarda en cargarlo.
    $cNombre = New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, '1001')), (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)))
    while (-not $ed -and (Get-Date) -lt $fin) { $ed = $dlg.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cNombre); if (-not $ed) { Start-Sleep -Milliseconds 300 } }
    $vp = $null
    if ($ed -and $ed.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
        $vp.SetValue($csv)
        $cGuardar = New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, '1')), (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
        if (-not (Invoke-Elemento ($dlg.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cGuardar)))) { throw 'No pude apretar Guardar' }
        Log 'Nombre puesto con UI Automation'
    } else {
        # Respaldo: el "Guardar como" abre con el cursor en el nombre de archivo. Se escribe la ruta y Enter.
        $n = @($dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)).Count
        Log "Campo del nombre no visible por UI Automation (el diálogo expone $n elementos): uso teclado"
        try { $dlg.SetFocus() } catch {}
        Start-Sleep -Milliseconds 400
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait(($csv -replace '([+^%~(){}\[\]])', '{$1}'))
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    }
    Start-Sleep -Seconds 2
    if ((Get-PorId (Find-Ventana '(?i)sensor' '(?i)hwinfo' 5) '1437').Current.Name -match '(?i)iniciar') { throw 'HWiNFO no empezó a grabar' }
    $grabando = $true
    Log "Grabando en $csv"

    # 3. Reposo
    if ($ReposoMin -gt 0) { Log "Reposo $ReposoMin min"; Start-Sleep -Seconds ([int]($ReposoMin * 60)) }

    # 4. OCCT: START, pantalla gratis, START
    # OCCT abre en la pestaña que quedó guardada (SelectedArea) y su menú no se ve por UI Automation.
    # Se cierra cualquier OCCT abierto (guarda la config al salir) y se fija 0 = STABILITY TEST, donde está START.
    Close-Proceso '^OCCT'
    $occtCfg = Join-Path (Split-Path -Parent $occtExe) 'OCCT.config.json'
    if ([IO.File]::Exists($occtCfg)) {
        $t = [IO.File]::ReadAllText($occtCfg)
        # WindowState 1 = minimizada: así OCCT no responde a START. 0 = normal.
        $n = [regex]::Replace([regex]::Replace($t, '"SelectedArea":\s*\d+', '"SelectedArea": 0'), '"WindowState":\s*\d+', '"WindowState": 0')
        if ($n -ne $t) { [IO.File]::WriteAllText($occtCfg, $n, (New-Object Text.UTF8Encoding $false)) }
    }
    Log 'Abriendo OCCT'
    $null = Start-Process -FilePath $occtExe
    $p = $null; $fin = (Get-Date).AddSeconds(90)
    while (-not $p -and (Get-Date) -lt $fin) { Start-Sleep -Milliseconds 500; $p = Get-Process -Name OCCTGUI -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1 }
    if (-not $p) { throw 'OCCT no abrió' }
    # La primera ventana de OCCTGUI puede ser una pantalla de carga: se busca cada vez la principal por su título.
    $v = $null; $st = $null; $fin = (Get-Date).AddSeconds(60)
    while (-not $st -and (Get-Date) -lt $fin) {
        Start-Sleep -Milliseconds 500
        $v = Find-Ventana '(?i)stability testing' '(?i)occt' 1
        if ($v) {
            # Aviso de actualización de OCCT ("Update" / "Cancel"): se cancela, no se actualiza nada.
            $cBtn = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
            $bts = @($v.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cBtn))
            $upd = $bts | Where-Object { try { $_.Current.Name -eq 'Update' } catch { $false } } | Select-Object -First 1
            $can = $bts | Where-Object { try { $_.Current.Name -eq 'Cancel' } catch { $false } } | Select-Object -First 1
            if ($upd -and $can) { if (Invoke-Elemento $can) { Log 'Cancelé el aviso de actualización de OCCT' }; Start-Sleep -Seconds 2; continue }
            $wp = $null
            if ($v.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp) -and $wp.Current.WindowVisualState -eq [System.Windows.Automation.WindowVisualState]::Minimized) {
                $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal); Log 'OCCT estaba minimizado: lo restauré'; Start-Sleep -Seconds 2
            }
            $st = Get-StartHabilitado $v
        }
    }
    if (-not $v) { throw 'No apareció la ventana principal de OCCT en 60 s' }
    if (-not $st) {
        $vis = @($v.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button))) | ForEach-Object { try { "'$($_.Current.Name)' hab=$($_.Current.IsEnabled)" } catch {} }) -join ' | '
        throw "No apareció START habilitado en 30 s. Botones: $vis"
    }
    Start-Sleep -Seconds 2
    if (-not (Invoke-Elemento (Get-StartHabilitado $v))) { throw 'No pude apretar START' }
    Start-Sleep -Seconds 2
    $fin = (Get-Date).AddSeconds(60); $ultimo = Get-Date; $foto = 0; $t0 = Get-Date
    while (-not (Get-StartHabilitado $v) -and (Get-Date) -lt $fin) {
        Start-Sleep -Milliseconds 500
        $seg = ((Get-Date) - $t0).TotalSeconds
        if (($foto -eq 0 -and $seg -ge 5) -or ($foto -eq 1 -and $seg -ge 20)) {
            $foto++
            try {
                Add-Type -AssemblyName System.Drawing
                try { $v.SetFocus() } catch {}
                Start-Sleep -Milliseconds 300
                $rr = $v.Current.BoundingRectangle
                $bmp = New-Object System.Drawing.Bitmap ([int]$rr.Width), ([int]$rr.Height)
                $gg = [System.Drawing.Graphics]::FromImage($bmp); $gg.CopyFromScreen([int]$rr.X, [int]$rr.Y, 0, 0, $bmp.Size)
                $bmp.Save((Join-Path $Salida "occt_tras_start_$foto.png")); $gg.Dispose(); $bmp.Dispose()
                Log "  foto $foto guardada"
            } catch { Log "  foto falló: $($_.Exception.Message)" }
        }
        if (((Get-Date) - $ultimo).TotalSeconds -ge 5) {
            $ultimo = Get-Date
            $v = Find-Ventana '(?i)stability testing' '(?i)occt' 1
            $pidsO = @(Get-Process | Where-Object { $_.ProcessName -match '(?i)occt' } | ForEach-Object Id)
            foreach ($w in @($A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cw) | Where-Object { try { $pidsO -contains $_.Current.ProcessId } catch { $false } })) {
                $bw = @($w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { try { $_.Current.Name -and $_.Current.Name -notmatch '^(Material|Avalonia|OcctCore)' -and $_.Current.BoundingRectangle.Width -gt 0 } catch { $false } } | Select-Object -First 12 | ForEach-Object { try { '{0}:{1}{2}' -f $_.Current.ControlType.ProgrammaticName.Replace('ControlType.', ''), $_.Current.Name, $(if ($_.Current.IsEnabled) { '' } else { '(off)' }) } catch {} }) -join ' | '
                Log "  ventana '$($w.Current.Name)' $($w.Current.BoundingRectangle): $bw"
                $sw = Get-StartHabilitado $w
                if ($sw -and $w.Current.Name -notmatch '(?i)stability testing') { Log '  START habilitado en otra ventana'; $v = $w }
            }
            $cTodo = [System.Windows.Automation.Condition]::TrueCondition
            $vis = @($v.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cTodo) | Where-Object { try { $_.Current.BoundingRectangle.Width -gt 0 -and $_.Current.Name -and $_.Current.Name -notmatch '^(Material|Avalonia|OcctCore)' -and $_.Current.Name -notmatch '^[\d.,]+$' } catch { $false } } | Select-Object -First 25 | ForEach-Object { try { '{0}:{1}{2}' -f $_.Current.ControlType.ProgrammaticName.Replace('ControlType.', ''), $_.Current.Name, $(if ($_.Current.IsEnabled) { '' } else { '(off)' }) } catch {} }) -join ' | '
            Log "  esperando: $vis"
        }
    }
    if (-not (Invoke-Elemento (Get-StartHabilitado $v))) { throw 'No pude apretar START después de la pantalla gratis' }
    Start-Sleep -Seconds 6
    $cpu = Get-CpuTotal
    Log "OCCT corriendo (CPU total $cpu %)"
    if ($cpu -lt 90) { Log 'Ojo: la CPU no llegó a 90 %: puede que la prueba no haya partido' }

    # 5. Carga
    $fin = (Get-Date).AddMinutes($Minutos)
    while ((Get-Date) -lt $fin) { Start-Sleep -Seconds ([math]::Min(30, [math]::Max(1, ($fin - (Get-Date)).TotalSeconds))); Log "  CPU $(Get-CpuTotal) %" }
    Close-Proceso '(?i)occt'
    Log 'OCCT cerrado'
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Close-Proceso '(?i)occt'
} finally {
    # 6. Detener la grabación y cerrar HWiNFO
    if ($grabando) {
        $s2 = Find-Ventana '(?i)sensor' '(?i)hwinfo' 5
        if ($s2) { $b2 = Get-PorId $s2 '1437'; $null = [KitProto.W32]::PostMessage([IntPtr]$b2.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Seconds 3; Log 'Grabación detenida' }
    }
    Close-Proceso '(?i)hwinfo'
    Log 'HWiNFO cerrado'
}

# 7. Revisar el CSV con el lector del kit
if (Test-Path $csv) {
    $scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
    foreach ($lib in 'Comun', 'Log', 'Sensores') { . (Join-Path $scripts "lib\$lib.ps1") }
    Initialize-Contexto -RaizScripts $scripts
    $r = Read-SensoresCsv -Ruta $csv
    $m = $r.metricas
    $cpuT = if ($m.cpu_temp_paquete) { $m.cpu_temp_paquete } else { $m.cpu_temp_nucleo_max }
    Log ("CSV: {0} | {1} filas, {2:N1} min | CPU {3} °C prom / {4} °C máx | carga detectada: {5}" -f $r.formato, $r.filas, $r.duracion_min, $(if ($cpuT) { $cpuT.media } else { '-' }), $(if ($cpuT) { $cpuT.max } else { '-' }), $(if ($r.carga) { "$([math]::Round($r.carga.minutos, 1)) min" } else { 'no' }))
    Log "Archivo: $csv"
} else { Log 'No quedó CSV' }
