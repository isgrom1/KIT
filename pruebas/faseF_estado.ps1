#Requires -Version 5.1
# Fase F — foto (solo lectura) de lo que tocan las acciones de LENTO, para comprobar que deshacer deja
# el equipo igual: inicio (Run y StartupApproved), hibernación, plan de energía y ajustes del procesador.
param([Parameter(Mandatory)][string]$Salida)
$ErrorActionPreference = 'Stop'
function Get-Valores([Microsoft.Win32.RegistryHive]$Colmena, [string]$Ruta) {
    $r = [ordered]@{}
    $b = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Colmena, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $k = $b.OpenSubKey($Ruta)
        if ($k) {
            try {
                foreach ($n in @($k.GetValueNames() | Sort-Object)) {
                    $v = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
                    $r[$n] = if ($v -is [byte[]]) { 'bin:' + [Convert]::ToBase64String($v) } else { "$v" }
                }
            } finally { $k.Close() }
        }
    } finally { $b.Close() }
    $r
}
function Get-AjusteAc([string]$Plan, [string]$Ajuste) {
    $s = & "$env:SystemRoot\System32\powercfg.exe" /qh $Plan '54533251-82be-4824-96c1-47b60b740d00' $Ajuste | Out-String
    $hex = @([regex]::Matches($s, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -ge 2) { [Convert]::ToInt32($hex[$hex.Count - 2], 16) } else { $null }
}
$hkcu = [Microsoft.Win32.RegistryHive]::CurrentUser; $hklm = [Microsoft.Win32.RegistryHive]::LocalMachine
$aprobado = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$plan = [regex]::Match((& "$env:SystemRoot\System32\powercfg.exe" /getactivescheme | Out-String), '[0-9a-fA-F-]{36}').Value.ToLowerInvariant()
$power = Get-Valores $hklm 'SYSTEM\CurrentControlSet\Control\Power'
$hiberfil = try { (Get-Item -LiteralPath 'C:\hiberfil.sys' -Force -ErrorAction Stop).Length } catch { $null }
$estado = [ordered]@{
    run_hkcu              = Get-Valores $hkcu 'Software\Microsoft\Windows\CurrentVersion\Run'
    aprobado_hkcu_run     = Get-Valores $hkcu "$aprobado\Run"
    aprobado_hkcu_carpeta = Get-Valores $hkcu "$aprobado\StartupFolder"
    aprobado_hklm_run     = Get-Valores $hklm "$aprobado\Run"
    aprobado_hklm_run32   = Get-Valores $hklm "$aprobado\Run32"
    gpu_preferencias      = Get-Valores $hkcu 'Software\Microsoft\DirectX\UserGpuPreferences'
    hibernacion           = [ordered]@{ HibernateEnabled = $power['HibernateEnabled']; HiberFileType = $power['HiberFileType']; HiberFileSizePercent = $power['HiberFileSizePercent']; hiberfil_existe = ($null -ne $hiberfil) }
    plan_activo           = $plan
    cpu_max_ac            = Get-AjusteAc $plan 'bc5038f7-23e0-4960-96da-33abaf5935ec'
    cpu_boost_ac          = Get-AjusteAc $plan 'be337238-0d82-4146-a960-4f3749d470c7'
}
[IO.File]::WriteAllText($Salida, ($estado | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
$estado | ConvertTo-Json -Depth 5 -Compress
