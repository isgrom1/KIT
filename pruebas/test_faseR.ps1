#Requires -Version 5.1
<#
.SYNOPSIS
    Fase R: señales de malware (lib\Malware.ps1) con casos de ejemplo: Python escondido en ProgramData
    con nombre de marca falso, extensión sin empaquetar con host nativo .bat/.ps1 y carpetas con nombre al azar.
.DESCRIPTION
    Funciones puras con datos de ejemplo. La parte que lee carpetas y navegadores corre sobre un "perfil" falso:
    cambia LOCALAPPDATA, APPDATA, ProgramData y PUBLIC a carpetas temporales creadas aquí. No toca el registro
    ni el equipo.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'secciones\07_arranque.ps1')
Initialize-Contexto -RaizScripts $scripts
$script:Ctx.SeccionActual = '07 Arranque'
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }
$tmp = Join-Path $env:TEMP ("kit_faseR_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = [IO.Directory]::CreateDirectory($tmp)
$envAntes = @{ LOCALAPPDATA = $env:LOCALAPPDATA; APPDATA = $env:APPDATA; ProgramData = $env:ProgramData; PUBLIC = $env:PUBLIC }

try {
    '== Nombres al azar'
    $azar = @('HbXqZpWkT', 'QwRt8KXZ', 'KJTRxqPWNZbvG')
    $normales = @('PowerToys', 'Discord', 'EpicGamesLauncher', 'kitservicio', 'RadarComprasAgiles', 'TeraCopy', 'Microsoft', 'NVIDIA', 'Packages', 'OneDrive', 'BraveSoftware', 'Google')
    Assert 'reconoce nombres al azar' (-not @($azar | Where-Object { -not (Test-NombreAzar $_) }).Count) (($azar | Where-Object { -not (Test-NombreAzar $_) }) -join ', ')
    Assert 'no confunde carpetas normales' (-not @($normales | Where-Object { Test-NombreAzar $_ }).Count) (($normales | Where-Object { Test-NombreAzar $_ }) -join ', ')

    '== Lo que arranca solo'
    $mal = [pscustomobject]@{ Nombre = 'AdobeCloudSync'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\ProgramData\MicrosoftSvcHelper\pythonw.exe'; Empresa = 'Python Software Foundation'; Comando = '"C:\ProgramData\MicrosoftSvcHelper\pythonw.exe" "C:\ProgramData\MicrosoftSvcHelper\AdobeCloudSync.py"' }
    $s = @(Test-SenalInicio -Entrada $mal)
    Assert 'AdobeCloudSync: intérprete escondido e impostor, los dos ALTA' ($s.Count -eq 2 -and @($s | Where-Object Nivel -EQ 'ALTA').Count -eq 2 -and ($s.Tipo -contains 'interprete') -and ($s.Tipo -contains 'impostor')) (($s | ForEach-Object { "$($_.Nivel) $($_.Tipo)" }) -join '; ')
    Assert 'el impostor nombra la empresa real del archivo' (@($s | Where-Object { $_.Tipo -eq 'impostor' -and $_.Titulo -match 'Python Software Foundation' }).Count -eq 1)
    $tarea = [pscustomobject]@{ Nombre = '\MicrosoftCorporation'; Ubicacion = 'Tarea programada'; Ejecutable = 'C:\ProgramData\appsvcdata\pythonw.exe'; Empresa = 'Python Software Foundation'; Comando = '' }
    Assert 'la tarea MicrosoftCorporation con pythonw también' (@(Test-SenalInicio -Entrada $tarea | Where-Object Nivel -EQ 'ALTA').Count -eq 2)
    $buenas = @(
        [pscustomobject]@{ Nombre = 'Discord'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\Users\U\AppData\Local\Discord\Update.exe'; Empresa = 'Discord Inc.' }
        [pscustomobject]@{ Nombre = 'Teams'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\Users\U\AppData\Local\Microsoft\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe'; Empresa = '' }
        [pscustomobject]@{ Nombre = 'Steam'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\Program Files (x86)\Steam\steam.exe'; Empresa = 'Valve Corporation' }
        [pscustomobject]@{ Nombre = 'MicrosoftEdgeAutoLaunch_ABC'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'; Empresa = 'Microsoft Corporation' }
        [pscustomobject]@{ Nombre = 'Audio Realtek'; Ubicacion = 'HKLM\Run'; Ejecutable = 'C:\Windows\System32\RtkAudUService64.exe'; Empresa = 'Realtek Semiconductor' }
        [pscustomobject]@{ Nombre = 'electron.app.OP.GG'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\Users\U\AppData\Local\Programs\OP.GG\OP.GG.exe'; Empresa = 'OP.GG' }
    )
    $fp = @($buenas | ForEach-Object { Test-SenalInicio -Entrada $_ } | Where-Object { $_ })
    Assert 'programas normales (Discord, Teams de la Store, Steam, Edge, Realtek, OP.GG) sin señales' (-not $fp.Count) (($fp | ForEach-Object Titulo) -join ' | ')
    $sinEmpresa = [pscustomobject]@{ Nombre = 'Microsoft Update Helper'; Ubicacion = 'HKCU\Run'; Ejecutable = 'C:\ProgramData\MsUpd\helper.exe'; Empresa = '' }
    Assert 'marca sin empresa desde ProgramData: MEDIA' (@(Test-SenalInicio -Entrada $sinEmpresa | Where-Object { $_.Nivel -eq 'MEDIA' -and $_.Tipo -eq 'impostor' }).Count -eq 1)

    '== Hosts nativos y extensiones'
    $hn = Test-SenalHostNativo -Nombre 'com.ejemplo.hostfalso' -Navegador 'Chrome HKCU' -Manifiesto ([pscustomobject]@{ path = 'C:\Users\U\AppData\Local\QwRt8KXZ\host.bat'; allowed_origins = @('chrome-extension://abcdefghijklmnopabcdefghijklmnop/') })
    Assert 'host nativo que ejecuta un .bat: ALTA y nombra la extensión' ($hn.Nivel -eq 'ALTA' -and $hn.Detalle -match 'abcdefghijklmnopabcdefghijklmnop')
    $legit = @(
        (Test-SenalHostNativo -Nombre 'com.anthropic.claude_browser_extension' -Navegador 'Chrome HKCU' -Manifiesto ([pscustomobject]@{ path = 'C:\Users\U\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-NativeHost\chrome-native-host.exe' }))
        (Test-SenalHostNativo -Nombre 'com.microsoft.browsercore' -Navegador 'Chrome HKLM' -Manifiesto ([pscustomobject]@{ path = 'BrowserCore.exe' }) -RutaManifiesto 'C:\Windows\BrowserCore\manifest.json')
    ) | Where-Object { $_ }
    Assert 'hosts nativos normales (Claude, Microsoft) sin señales' (-not @($legit).Count)
    $espia = [pscustomobject]@{ name = 'Guardar en Drive'; permissions = @('scripting', 'tabs', 'history', 'cookies', 'nativeMessaging', 'clipboardRead', '<all_urls>'); host_permissions = @('*://*/*') }
    $se = Test-SenalExtension -Navegador 'Brave (Default)' -Ruta 'C:\Users\U\AppData\Local\HbXqZpWkT' -Manifiesto $espia
    Assert 'extensión falsa "Guardar en Drive": ALTA con sus permisos' ($se.Nivel -eq 'ALTA' -and $se.Titulo -match 'Guardar en Drive' -and $se.Detalle -match 'nativeMessaging' -and $se.Detalle -match 'todas las páginas') $se.Detalle
    $dev = Test-SenalExtension -Navegador 'Chrome (Default)' -Ruta 'D:\proyectos\mi_ext' -Manifiesto ([pscustomobject]@{ name = 'Mi extensión'; permissions = @('storage') })
    Assert 'extensión sin empaquetar inofensiva: solo MEDIA' ($dev.Nivel -eq 'MEDIA')

    '== Carpetas'
    Assert 'carpeta al azar con host.bat y host.ps1: MEDIA' ((Test-SenalCarpeta -Ruta 'C:\X\QwRt8KXZ' -Archivos @('com.ejemplo.hostfalso.json', 'host.bat', 'host.ps1')).Nivel -eq 'MEDIA')
    Assert 'carpeta al azar sin scripts ni manifest: nada' ($null -eq (Test-SenalCarpeta -Ruta 'C:\X\KJTRxqPWNZbvG' -Archivos @('datos.bin')))
    Assert 'carpeta normal con un .exe: nada' ($null -eq (Test-SenalCarpeta -Ruta 'C:\X\PowerToys' -Archivos @('PowerToys.exe')))
    Assert 'IP privadas y públicas' ((Test-IpPrivada '192.168.0.10') -and (Test-IpPrivada '10.1.2.3') -and (Test-IpPrivada '172.20.0.1') -and -not (Test-IpPrivada '203.0.113.50') -and -not (Test-IpPrivada '8.8.8.8'))

    '== Perfil falso'
    $loc = Join-Path $tmp 'Local'; $rom = Join-Path $tmp 'Roaming'; $pd = Join-Path $tmp 'ProgramData'; $pub = Join-Path $tmp 'Public'
    foreach ($d in $loc, $rom, $pd, $pub, "$loc\QwRt8KXZ", "$loc\HbXqZpWkT", "$pd\MicrosoftSvcHelper", "$pd\Microsoft", "$loc\Google\Chrome\User Data\Default", "$loc\PowerToys") { $null = [IO.Directory]::CreateDirectory($d) }
    foreach ($f in "$loc\QwRt8KXZ\host.bat", "$loc\QwRt8KXZ\host.ps1", "$pd\MicrosoftSvcHelper\pythonw.exe", "$pd\MicrosoftSvcHelper\AdobeCloudSync.py", "$loc\PowerToys\PowerToys.exe") { [IO.File]::WriteAllText($f, 'x') }
    [IO.File]::WriteAllText("$loc\HbXqZpWkT\manifest.json", ($espia | ConvertTo-Json))
    $prefs = '{"extensions":{"settings":{"abcdefghijklmnopabcdefghijklmnop":{"location":4,"path":"' + "$loc\HbXqZpWkT".Replace('\', '\\') + '"},"nmmhkkegccagdldgiimedpiccmgmieda":{"path":"nmmhkkegccagdldgiimedpiccmgmieda\\1.0_0"}}}}'
    [IO.File]::WriteAllText("$loc\Google\Chrome\User Data\Default\Secure Preferences", $prefs)
    $env:LOCALAPPDATA = $loc; $env:APPDATA = $rom; $env:ProgramData = $pd; $env:PUBLIC = $pub
    $car = @(Get-SenalesCarpetas)
    Assert 'encuentra las dos carpetas al azar con contenido' (@($car | Where-Object Tipo -EQ 'carpeta').Count -eq 2) (($car | ForEach-Object Titulo) -join ' | ')
    Assert 'encuentra el pythonw copiado a ProgramData junto a un .py (ALTA)' (@($car | Where-Object { $_.Tipo -eq 'interprete' -and $_.Nivel -eq 'ALTA' -and $_.Titulo -match 'AdobeCloudSync\.py' }).Count -eq 1)
    $ext = @(Get-SenalesExtension)
    Assert 'encuentra la extensión sin empaquetar del perfil de Chrome (y no la de la tienda)' ($ext.Count -eq 1 -and $ext[0].Nivel -eq 'ALTA' -and $ext[0].Titulo -match 'Chrome \(Default\)') (($ext | ForEach-Object Titulo) -join ' | ')
    $todo = Get-DatosMalware -Entradas @($mal) 6>$null
    Assert 'Get-DatosMalware junta todo y cuenta las fuertes' ($todo.Altas -ge 4 -and $todo.Medias -ge 2) "altas $($todo.Altas), medias $($todo.Medias)"
    Assert 'no repite la misma señal' (@($todo.Senales | Group-Object { "$($_.Tipo)|$($_.Ruta)" } | Where-Object Count -GT 1).Count -eq 0)

    '== Alertas'
    $script:Ctx.Alertas.Clear()
    $def = [pscustomobject]@{ Detecciones = @([pscustomobject]@{ Fecha = '2026-11-18 13:57:53'; Amenaza = 'HackTool:Win32/crack'; Archivos = @('programa_crack.exe'); Resuelta = $true }); Exclusiones = @('X:\JUEGOS'); ExclusionesLeidas = $true }
    Test-AlertasMalware -Malware ([pscustomobject]@{ Senales = $todo.Senales; Altas = $todo.Altas; Medias = $todo.Medias; Defender = $def })
    $al = $script:Ctx.Alertas.ToArray()
    Assert 'cada señal fuerte es una alerta CRÍTICA SEG-MALWARE' (@($al | Where-Object { $_.Codigo -eq 'SEG-MALWARE' -and $_.Severidad -eq 'CRITICO' }).Count -eq $todo.Altas)
    Assert 'las de revisar son AVISO' (@($al | Where-Object { $_.Codigo -eq 'SEG-MALWARE-REVISAR' -and $_.Severidad -eq 'AVISO' }).Count -eq $todo.Medias)
    Assert 'Defender reciente y exclusiones como INFO' (@($al | Where-Object { $_.Codigo -eq 'SEG-DEFENDER-RECIENTE' -and $_.Texto -match 'HackTool:Win32/crack' }).Count -eq 1 -and @($al | Where-Object Codigo -EQ 'SEG-DEFENDER-EXCLUSIONES').Count -eq 1)
    Assert 'el módulo solo lee (no hay Remove-, Stop-, Set-, New-Item ni Disable- en Malware.ps1)' ([IO.File]::ReadAllText((Join-Path $scripts 'lib\Malware.ps1')) -notmatch '(?i)\b(Remove-Item|Remove-ItemProperty|Stop-Process|Set-ItemProperty|New-Item|Disable-ScheduledTask|Unregister-ScheduledTask|Set-MpPreference)\b')
} finally {
    foreach ($k in $envAntes.Keys) { Set-Item -Path "Env:$k" -Value $envAntes[$k] }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

''
"Resultado: $script:ok OK, $script:fallas fallas ($($script:ok + $script:fallas) comprobaciones)"
if ($script:fallas) { exit 1 }
exit 0
