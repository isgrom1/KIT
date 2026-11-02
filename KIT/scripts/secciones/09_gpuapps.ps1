# 09 Preferencias de GPU por app: HKCU\Software\Microsoft\DirectX\UserGpuPreferences
# (Configuración > Pantalla > Gráficos). GpuPreference: 0 Windows decide, 1 ahorro, 2 alto rendimiento.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:PreferenciaGpu = @{ 0 = 'Windows decide'; 1 = 'Ahorro de energía'; 2 = 'Alto rendimiento' }

function ConvertFrom-ParesDirectX {
    # "GpuPreference=2;SwapEffectUpgradeEnable=1;" -> diccionario
    param([AllowEmptyString()][string]$Texto)
    $r = [ordered]@{}
    foreach ($par in ($Texto -split ';')) {
        if ($par -match '^\s*([^=]+)=(.*)$') { $r[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    $r
}

function Get-DatosGpuApps {
    $valores = Get-ValoresRegistro -Colmena HKCU -Ruta 'Software\Microsoft\DirectX\UserGpuPreferences'
    $global = $null
    $apps = foreach ($nombre in $valores.Keys) {
        $pares = ConvertFrom-ParesDirectX "$($valores[$nombre])"
        if ($nombre -eq 'DirectXUserGlobalSettings') { $global = "$($valores[$nombre])"; continue }
        $pref = $null
        if ($pares.Contains('GpuPreference')) { $pref = [int]$pares['GpuPreference'] }
        $otros = @($pares.Keys | Where-Object { $_ -ne 'GpuPreference' } | ForEach-Object { "$_=$($pares[$_])" }) -join '; '
        [pscustomobject][ordered]@{
            Aplicacion   = $nombre
            Preferencia  = $(if ($null -eq $pref) { '(no definida)' } elseif ($script:PreferenciaGpu.ContainsKey($pref)) { $script:PreferenciaGpu[$pref] } else { "código $pref" })
            Codigo       = $pref
            OtrosAjustes = $otros
            Existe       = $(if ($nombre -match '^[A-Za-z]:\\') { [IO.File]::Exists($nombre) } else { $null })
        }
    }
    $apps = @($apps | Sort-Object Preferencia, Aplicacion)
    Add-Tabla -Nombre 'gpu_por_app' -Filas $apps
    $gpus = Invoke-Paso 'cantidad de GPU' { @(Get-Cim -Clase Win32_VideoController -Propiedades Name).Count }
    [ordered]@{ Apps = $apps; AjustesGlobales = $global; CantidadGpu = $gpus }
}

function Test-AlertasGpuApps {
    $d = $script:Ctx.Datos.gpu_apps
    if ($d.CantidadGpu -lt 2) { return }
    $ahorro = @($d.Apps | Where-Object { $_.Codigo -eq 1 } | ForEach-Object { Split-Path -Leaf $_.Aplicacion })
    if ($ahorro.Count -gt 0) {
        Add-Alerta -Severidad INFO -Codigo 'GPU-AHORRO' -Texto "Apps forzadas a la GPU de ahorro de energía (en equipo con $($d.CantidadGpu) GPU): $($ahorro -join ', ')"
    }
}

function Format-ResumenGpuApps {
    $d = $script:Ctx.Datos.gpu_apps
    "Apps       : $(@($d.Apps).Count) con preferencia guardada | GPU en el equipo: $($d.CantidadGpu)$(if ($d.AjustesGlobales) { ' | globales: ' + $d.AjustesGlobales })"
    foreach ($g in @($d.Apps | Group-Object Preferencia)) {
        $nombres = @($g.Group | ForEach-Object { (Split-Path -Leaf $_.Aplicacion) + $(if ($_.Existe -eq $false) { ' (no existe)' } else { '' }) })
        "             $($g.Name) ($($g.Count)): $($nombres -join ', ')"
    }
}
