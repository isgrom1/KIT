# 08 Políticas de navegador: HKLM/HKCU\Software\Policies para Chrome, Edge y Brave, cada valor.
# Políticas que fuerzan extensiones, buscador, página de inicio o proxy son típicas de adware
# (o de la empresa, si el equipo está en dominio).

$script:Navegadores = @(
    @{ Nombre = 'Chrome'; Ruta = 'SOFTWARE\Policies\Google\Chrome' }
    @{ Nombre = 'Edge'; Ruta = 'SOFTWARE\Policies\Microsoft\Edge' }
    @{ Nombre = 'Brave'; Ruta = 'SOFTWARE\Policies\BraveSoftware\Brave' }
)
$script:PoliticasRiesgo = '(?i)(^|\\)(ExtensionInstallForcelist|ExtensionInstallSources|DefaultSearchProvider\w*|HomepageLocation|HomepageIsNewTabPage|NewTabPageLocation|RestoreOnStartup|RestoreOnStartupURLs|ProxySettings|ProxyServer|ProxyMode|ProxyPacUrl)(\\|$)'

function Get-PoliticasRecursivo {
    param([string]$Navegador, [string]$Colmena, [string]$Raiz, [string]$Relativa)
    $ruta = if ($Relativa) { "$Raiz\$Relativa" } else { $Raiz }
    $valores = Get-ValoresRegistro -Colmena $Colmena -Ruta $ruta
    foreach ($nombre in $valores.Keys) {
        $dato = $valores[$nombre]
        $texto = if ($dato -is [byte[]]) { 'hex:' + (($dato | Select-Object -First 32 | ForEach-Object { $_.ToString('x2') }) -join '') }
        elseif ($dato -is [string[]]) { $dato -join ' | ' }
        else { "$dato" }
        $clave = if ($Relativa) { $Relativa } else { '(raíz)' }
        $completo = if ($Relativa) { "$Relativa\$nombre" } else { $nombre }
        [pscustomobject][ordered]@{
            Navegador = $Navegador
            Ambito    = $Colmena
            Clave     = $clave
            Valor     = $nombre
            Dato      = $texto
            Riesgo    = ($completo -match $script:PoliticasRiesgo) -or ($nombre -eq 'ExtensionSettings' -and $texto -match 'force_installed')
        }
    }
    foreach ($sub in (Get-SubclavesRegistro -Colmena $Colmena -Ruta $ruta)) {
        $rel = if ($Relativa) { "$Relativa\$sub" } else { $sub }
        Get-PoliticasRecursivo -Navegador $Navegador -Colmena $Colmena -Raiz $Raiz -Relativa $rel
    }
}

function Get-DatosNavegador {
    $filas = foreach ($n in $script:Navegadores) {
        foreach ($colmena in 'HKLM', 'HKCU') {
            Invoke-Paso "políticas $($n.Nombre) $colmena" { Get-PoliticasRecursivo -Navegador $n.Nombre -Colmena $colmena -Raiz $n.Ruta -Relativa '' }
        }
    }
    $filas = @($filas | Where-Object { $_ })
    Add-Tabla -Nombre 'politicas_navegador' -Filas $filas
    $dominio = Invoke-Paso 'dominio' { [bool](Get-Cim -Clase Win32_ComputerSystem -Propiedades PartOfDomain).PartOfDomain }
    [ordered]@{
        Politicas = $filas
        EnDominio = [bool]$dominio
        PorNavegador = @($script:Navegadores | ForEach-Object {
                $nombre = $_.Nombre
                $propias = @($filas | Where-Object { $_.Navegador -eq $nombre })
                [pscustomobject][ordered]@{ Navegador = $nombre; Total = $propias.Count; Riesgosas = @($propias | Where-Object { $_.Riesgo }).Count }
            })
    }
}

function Test-AlertasNavegador {
    $d = $script:Ctx.Datos.navegador
    $nota = if ($d.EnDominio) { ' (equipo en dominio: puede ser política de la empresa)' } else { ' (posible hijack de adware; revisar si lo puso un antivirus o la empresa)' }
    foreach ($nav in $d.PorNavegador) {
        if ($nav.Total -eq 0) { continue }
        $riesgosas = @($d.Politicas | Where-Object { $_.Navegador -eq $nav.Navegador -and $_.Riesgo })
        if ($riesgosas.Count -gt 0) {
            $nombres = @($riesgosas | ForEach-Object { if ($_.Clave -ne '(raíz)') { ($_.Clave -split '\\')[0] } else { $_.Valor } } | Group-Object | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) ($($_.Count))" } else { $_.Name } })
            Add-Alerta -Severidad AVISO -Codigo 'NAV-RIESGO' -Texto "$($nav.Navegador) con políticas que fuerzan extensiones, buscador, inicio o proxy: $($nombres -join ', ')$nota"
        } else {
            Add-Alerta -Severidad INFO -Codigo 'NAV-POLITICAS' -Texto "$($nav.Navegador) administrado por $($nav.Total) políticas (ninguna de extensiones/buscador/inicio/proxy)"
        }
    }
}

function Format-ResumenNavegador {
    $d = $script:Ctx.Datos.navegador
    foreach ($nav in $d.PorNavegador) { "{0,-11}: {1} políticas ({2} de riesgo)" -f $nav.Navegador, $nav.Total, $nav.Riesgosas }
    foreach ($p in ($d.Politicas | Select-Object -First 30)) {
        $dato = "$($p.Dato)"
        if ($dato.Length -gt 90) { $dato = $dato.Substring(0, 90) + '...' }
        "             $(if ($p.Riesgo) { '!' } else { '-' }) $($p.Navegador) $($p.Ambito) $(if ($p.Clave -ne '(raíz)') { $p.Clave + '\' })$($p.Valor) = $dato"
    }
    if (@($d.Politicas).Count -gt 30) { '             (lista completa en csv\08_politicas_navegador.csv)' }
}
