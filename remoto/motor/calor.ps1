#Requires -Version 5.1
<#
.SYNOPSIS
    Prueba CALOR sin manos: HWiNFO graba los sensores, reposo, OCCT carga la CPU, se cierra todo.
.DESCRIPTION
    HWiNFO (Enter a su diálogo inicial, botón 1437 = grabar, "Guardar como" por teclado) -> reposo -ReposoMin ->
    OCCT en STABILITY TEST (SelectedArea 0, ventana normal) -> START -> diálogo "Enjoying OCCT?" de la versión
    gratis (~10 s) -> Start -> carga -Minutos -> cierra OCCT -> detiene la grabación -> cierra HWiNFO.
    Necesita administrador. Excepción a las reglas del kit (solo en la herramienta remota): un P/Invoke a
    user32 PostMessage para apretar el botón de grabar de HWiNFO, que no se puede apretar de otra forma.
    Escribe el avance en la consola (stdout); quien lo llama lo guarda en un log.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Consola')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'UIAutomation y Windows.Forms vienen con .NET Framework y se cargan con Add-Type -AssemblyName')]
[CmdletBinding()]
param(
    [double]$Minutos = 10,
    [double]$ReposoMin = 5,
    [Parameter(Mandatory)][string]$Salida,
    [Parameter(Mandatory)][string]$Herramientas,
    [string]$Scripts
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace KitRemoto -Name W32 -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint m, System.IntPtr w, System.IntPtr l);'
$A = [System.Windows.Automation.AutomationElement]
$T = [System.Windows.Automation.TreeScope]
$cw = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
$cBtn = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)

function Write-Paso([string]$Texto) {
    $l = '{0}  {1}' -f (Get-Date -Format HH:mm:ss), $Texto
    [Console]::WriteLine($l)
    try { [IO.File]::AppendAllText((Join-Path $Salida 'calor_pasos.log'), "$l`r`n", [Text.Encoding]::UTF8) } catch { Write-Verbose $_ }
}
function Get-CpuTotal { [int](Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average }
function Find-Ventana([string]$Patron, [string]$Proceso, [int]$Seg, [switch]$Profundo) {
    $fin = (Get-Date).AddSeconds($Seg)
    $alcance = if ($Profundo) { $T::Descendants } else { $T::Children }
    do {
        $pids = @(Get-Process | Where-Object { $_.ProcessName -match $Proceso } | ForEach-Object Id)
        $v = @($A::RootElement.FindAll($alcance, $cw)) | Where-Object { try { ($pids -contains $_.Current.ProcessId) -and $_.Current.Name -match $Patron } catch { $false } } | Select-Object -First 1
        if ($v) { return $v }
        Start-Sleep -Milliseconds 400
    } while ((Get-Date) -lt $fin)
    $null
}
function Get-PorId($Raiz, [string]$Id) { $Raiz.FindFirst($T::Children, (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, $Id))) }
function Invoke-Elemento($Elemento) {
    $p = $null
    if ($Elemento -and $Elemento.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return $true }
    $false
}
function Get-StartHabilitado($Ventana) {
    # "START" en la pantalla de la prueba y "Start" en el diálogo "Enjoying OCCT?" (UIA distingue mayúsculas).
    @($Ventana.FindAll($T::Descendants, $cBtn)) | Where-Object { try { $_.Current.Name -ieq 'start' -and $_.Current.IsEnabled -and $_.Current.BoundingRectangle.Width -gt 0 } catch { $false } } | Select-Object -First 1
}
function Close-Proceso([string]$Patron) {
    foreach ($x in @(Get-Process | Where-Object { $_.ProcessName -match $Patron })) { try { $null = $x.CloseMainWindow() } catch { Write-Verbose $_ } }
    Start-Sleep -Seconds 4
    @(Get-Process | Where-Object { $_.ProcessName -match $Patron }) | Stop-Process -Force -ErrorAction SilentlyContinue
}
function Send-ClicBoton($Boton) { $null = [KitRemoto.W32]::PostMessage([IntPtr]$Boton.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }   # BM_CLICK

$null = [IO.Directory]::CreateDirectory($Salida)
$csv = Join-Path $Salida 'sensores_calor.csv'
$hwExe = Join-Path $Herramientas 'HWiNFO\HWiNFO64.exe'
$occtExe = Join-Path $Herramientas 'OCCT\OCCT.exe'
foreach ($x in $hwExe, $occtExe) { if (-not [IO.File]::Exists($x)) { Write-Paso "ERROR: falta $x"; exit 3 } }
$grabando = $false
$ok = $false
try {
    # 1. HWiNFO en la ventana de sensores
    Close-Proceso -Patron '(?i)hwinfo'
    Write-Paso 'Abriendo HWiNFO'
    $null = Start-Process -FilePath $hwExe
    if (-not (Find-Ventana -Patron '(?i)HWiNFO' -Proceso '(?i)hwinfo' -Seg 40)) { throw 'HWiNFO no abrió' }
    Start-Sleep -Milliseconds 800
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')   # "Iniciar" es el botón por defecto del diálogo inicial
    # En algunos notebooks (ej. Acer Nitro AMD) HWiNFO avisa por el sensor del Embedded Controller antes de
    # mostrar los sensores y espera un clic. Se elige la opción que HWiNFO llama segura (no leer ese sensor):
    # la temperatura de la CPU sale del propio procesador; se pierden solo datos del EC (ej. RPM del ventilador).
    $sens = $null
    $fin = (Get-Date).AddSeconds(60)
    while (-not $sens -and (Get-Date) -lt $fin) {
        $aviso = Find-Ventana -Patron '(?i)^(warning|advertencia)$' -Proceso '(?i)hwinfo' -Seg 1
        if ($aviso) {
            $btns = @($aviso.FindAll($T::Descendants, $cBtn))
            $b = $btns | Where-Object { try { $_.Current.Name -match '(?i)no controle|deshabilit|desactiv|disable' } catch { $false } } | Select-Object -First 1
            if (-not $b) { $b = $btns | Where-Object { try { $_.Current.Name -match '(?i)continu' } catch { $false } } | Select-Object -First 1 }
            if ($b) {
                $nombre = $b.Current.Name
                if (-not (Invoke-Elemento -Elemento $b)) { Send-ClicBoton -Boton $b }
                Write-Paso "Aviso de sensor de HWiNFO: apreté '$nombre'"
                Start-Sleep -Seconds 1
                continue
            }
        }
        $sens = Find-Ventana -Patron '(?i)sensor' -Proceso '(?i)hwinfo' -Seg 1
    }
    if (-not $sens) { throw 'No apareció la ventana de sensores de HWiNFO' }
    $upd = Find-Ventana -Patron '(?i)update' -Proceso '(?i)hwinfo' -Seg 3
    if ($upd) { try { $upd.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); Write-Paso 'Cerré el aviso de actualización de HWiNFO' } catch { Write-Verbose $_ } }

    # 2. Grabar a CSV
    $btn = Get-PorId -Raiz $sens -Id '1437'
    if (-not $btn) { throw 'No encontré el botón de grabar de HWiNFO' }
    Send-ClicBoton -Boton $btn
    $dlg = Find-Ventana -Patron '(?i)^(guardar como|save as)$' -Proceso '(?i)hwinfo' -Seg 10 -Profundo
    if (-not $dlg) { throw 'No apareció el "Guardar como" de HWiNFO' }
    Start-Sleep -Seconds 1
    try { $dlg.SetFocus() } catch { Write-Verbose $_ }
    Start-Sleep -Milliseconds 400
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.SendKeys]::SendWait(($csv -replace '([+^%~(){}\[\]])', '{$1}'))
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    $fin = (Get-Date).AddSeconds(15)
    while (-not [IO.File]::Exists($csv) -and (Get-Date) -lt $fin) { Start-Sleep -Milliseconds 500 }
    if (-not [IO.File]::Exists($csv)) { throw 'HWiNFO no empezó a grabar' }
    $grabando = $true
    Write-Paso 'HWiNFO grabando los sensores'

    # 3. Reposo
    if ($ReposoMin -gt 0) { Write-Paso "Reposo de $ReposoMin min (no uses el computador)"; Start-Sleep -Seconds ([int]($ReposoMin * 60)) }

    # 4. OCCT en STABILITY TEST y en ventana normal (minimizado no responde a START)
    Close-Proceso -Patron '^OCCT'
    if ($Scripts) {
        try {
            # En su propio bloque: las librerías del kit tienen variables que pisarían las de este script ($T...).
            $r = & {
                foreach ($lib in 'Comun', 'Log', 'Herramientas') { . (Join-Path $Scripts "lib\$lib.ps1") }
                Initialize-Contexto -RaizScripts $Scripts
                Set-ConfigOcct -Carpeta (Split-Path -Parent $occtExe) -Base (Join-Path $Scripts 'config\occt_prueba.json')
            }
            Write-Paso "Prueba fija de OCCT: $($r.Estado)"
        } catch { Write-Paso "No pude fijar la prueba de OCCT con el kit: $($_.Exception.Message)" }
    }
    $occtCfg = Join-Path (Split-Path -Parent $occtExe) 'OCCT.config.json'
    if ([IO.File]::Exists($occtCfg)) {
        # Ojo: no llamar $t a esto (las variables no distinguen mayúsculas y $T es TreeScope).
        $txtCfg = [IO.File]::ReadAllText($occtCfg)
        $n = [regex]::Replace([regex]::Replace($txtCfg, '"SelectedArea":\s*\d+', '"SelectedArea": 0'), '"WindowState":\s*\d+', '"WindowState": 0')
        if ($n -ne $txtCfg) { [IO.File]::WriteAllText($occtCfg, $n, (New-Object Text.UTF8Encoding $false)) }
    }
    # Notebooks AMD + NVIDIA: OCCT se cae en vulkan-1.dll sin esta variable (ver CLAUDE.md).
    $env:DISABLE_LAYER_AMD_SWITCHABLE_GRAPHICS_1 = '1'
    Write-Paso 'Abriendo OCCT'
    $null = Start-Process -FilePath $occtExe
    $v = $null; $st = $null; $fin = (Get-Date).AddSeconds(120)
    while (-not $st -and (Get-Date) -lt $fin) {
        Start-Sleep -Milliseconds 500
        $v = Find-Ventana -Patron '(?i)stability testing' -Proceso '(?i)occt' -Seg 1
        if (-not $v) { continue }
        $bts = @($v.FindAll($T::Descendants, $cBtn))
        $upd = $bts | Where-Object { try { $_.Current.Name -eq 'Update' } catch { $false } } | Select-Object -First 1
        $can = $bts | Where-Object { try { $_.Current.Name -eq 'Cancel' } catch { $false } } | Select-Object -First 1
        if ($upd -and $can) { if (Invoke-Elemento -Elemento $can) { Write-Paso 'Cancelé el aviso de actualización de OCCT' }; Start-Sleep -Seconds 2; continue }
        $wp = $null
        if ($v.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp) -and $wp.Current.WindowVisualState -eq [System.Windows.Automation.WindowVisualState]::Minimized) {
            $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal); Start-Sleep -Seconds 2
        }
        $st = Get-StartHabilitado -Ventana $v
    }
    if (-not $st) { throw 'OCCT no mostró el botón START' }
    Start-Sleep -Seconds 2
    if (-not (Invoke-Elemento -Elemento (Get-StartHabilitado -Ventana $v))) { throw 'No pude apretar START' }
    Write-Paso 'START apretado; esperando la pantalla de la versión gratis (~10 s)'
    Start-Sleep -Seconds 3
    $fin = (Get-Date).AddSeconds(60)
    while (-not (Get-StartHabilitado -Ventana $v) -and (Get-Date) -lt $fin) { Start-Sleep -Milliseconds 500 }
    if (-not (Invoke-Elemento -Elemento (Get-StartHabilitado -Ventana $v))) { throw 'No pude apretar Start después de la pantalla gratis' }
    Start-Sleep -Seconds 8
    $cpu = Get-CpuTotal
    Write-Paso "OCCT cargando la CPU ($cpu %)"
    if ($cpu -lt 80) { Write-Paso 'Ojo: la CPU no llegó a 80 %: puede que la prueba no haya partido' }

    # 5. Carga
    $fin = (Get-Date).AddMinutes($Minutos)
    while ((Get-Date) -lt $fin) {
        Start-Sleep -Seconds ([math]::Max(1, [math]::Min(60, ($fin - (Get-Date)).TotalSeconds)))
        Write-Paso ("  carga: CPU {0} %, faltan {1:N0} min" -f (Get-CpuTotal), [math]::Max(0, ($fin - (Get-Date)).TotalMinutes))
    }
    Close-Proceso -Patron '(?i)occt'
    Write-Paso 'OCCT cerrado'
    $ok = $true
} catch {
    Write-Paso "ERROR: $($_.Exception.Message)"
    Close-Proceso -Patron '(?i)occt'
} finally {
    # 6. Detener la grabación (otro clic al mismo botón) y cerrar HWiNFO
    if ($grabando) {
        $s2 = Find-Ventana -Patron '(?i)sensor' -Proceso '(?i)hwinfo' -Seg 5
        if ($s2) { $b2 = Get-PorId -Raiz $s2 -Id '1437'; if ($b2) { Send-ClicBoton -Boton $b2; Start-Sleep -Seconds 3; Write-Paso 'Grabación detenida' } }
    }
    Close-Proceso -Patron '(?i)hwinfo'
}
if ($ok) { exit 0 } else { exit 1 }
