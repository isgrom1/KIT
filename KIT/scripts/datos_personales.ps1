#Requires -Version 5.1
<#
.SYNOPSIS
    Datos personales de los clientes (Ley 21.719): revisar, anonimizar los vencidos, olvidar o entregar.
.DESCRIPTION
    Sin parámetros muestra la revisión: expedientes con la retención vencida (18 meses desde la última
    atención, config.json -> datos_personales.retencion_meses), sin consentimiento y con aviso anual.
    -Anonimizar  quita los datos del cliente de los expedientes vencidos (pregunta antes, salvo -Confirmar).
    -Olvidar     borra por completo el expediente de un cliente (nombre, serie o ID) y lo anota para que la
                 sincronización no lo vuelva a traer.
    -Entregar    arma un ZIP con sus datos e informes para entregárselo (en -Destino o el Escritorio).
    Trabaja sobre los expedientes de este kit y, en el PC del técnico, también sobre el maestro.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\KIT\scripts\datos_personales.ps1 -Olvidar "Juan Pérez"
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para el técnico')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Confirmar', Justification = 'Lo usa Confirm-Accion, en el mismo script')]
[CmdletBinding(DefaultParameterSetName = 'Revisar')]
param(
    [Parameter(ParameterSetName = 'Anonimizar')][switch]$Anonimizar,
    [Parameter(ParameterSetName = 'Olvidar', Mandatory)][string]$Olvidar,
    [Parameter(ParameterSetName = 'Entregar', Mandatory)][string]$Entregar,
    [Parameter(ParameterSetName = 'Entregar')][string]$Destino,
    [string[]]$Carpetas,      # carpetas de expedientes (por defecto: las del kit y el maestro)
    [switch]$Confirmar,       # no preguntar (pruebas)
    [datetime]$Hoy = (Get-Date)
)
$ErrorActionPreference = 'Stop'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente', 'DatosPersonales', 'Sincronizacion') { . (Join-Path $PSScriptRoot "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $PSScriptRoot

if (-not $Carpetas) {
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add($script:Ctx.CarpetaClientes)
    try { $m = Get-RutaMaestro; if ($m -and [IO.Directory]::Exists($m) -and $m -ne $script:Ctx.CarpetaClientes) { $l.Add($m) } } catch { Write-Verbose $_ }
    $Carpetas = $l.ToArray()
}
$Carpetas = @($Carpetas | Where-Object { $_ -and [IO.Directory]::Exists($_) })

function Confirm-Accion([string]$Pregunta) {
    if ($Confirmar) { return $true }
    (Read-Host " $Pregunta Escribe SI para seguir") -match '^(?i)\s*s[ií]\s*$'
}

$meses = Get-MesesRetencion
Write-Host ''
Write-Host " DATOS PERSONALES (retención: $meses meses desde la última atención)" -ForegroundColor Cyan
foreach ($c in $Carpetas) { Write-Host "  - $c" -ForegroundColor DarkGray }

switch ($PSCmdlet.ParameterSetName) {
    'Olvidar' {
        $rutas = @(foreach ($c in $Carpetas) { Find-ExpedienteCliente -Clientes $c -Texto $Olvidar })
        if (-not $rutas.Count) { Write-Host " No encontré expedientes para '$Olvidar'." -ForegroundColor Yellow; exit 1 }
        foreach ($r in $rutas) { Write-Host "  · $r" }
        if (-not (Confirm-Accion "Se borran por completo $($rutas.Count) expediente(s). No se puede deshacer.")) { Write-Host ' No se borró nada.'; exit 0 }
        foreach ($r in $rutas) { Remove-ExpedienteCliente -Ruta $r -Confirm:$false; Write-Host "  Borrado: $r" -ForegroundColor Green }
        Write-Host ' Ojo: los respaldos cifrados del maestro lo conservan hasta que se renueven (se guardan los últimos 10).' -ForegroundColor DarkGray
    }
    'Entregar' {
        $rutas = @(foreach ($c in $Carpetas) { Find-ExpedienteCliente -Clientes $c -Texto $Entregar })
        if (-not $rutas.Count) { Write-Host " No encontré expedientes para '$Entregar'." -ForegroundColor Yellow; exit 1 }
        if (-not $Destino) { $Destino = [Environment]::GetFolderPath('Desktop') }
        foreach ($r in ($rutas | Select-Object -Unique)) {
            $zip = Export-DatosCliente -Ruta $r -Destino (Join-Path $Destino ([IO.Path]::GetFileName($r)))
            Write-Host "  Listo: $zip" -ForegroundColor Green
        }
    }
    default {
        $filas = @(foreach ($c in $Carpetas) { Get-RevisionDatosPersonales -Clientes $c -Hoy $Hoy -Meses $meses })
        $vencidos = @($filas | Where-Object { $_.Vencido -and $_.ConDatos })
        $sinCons = @($filas | Where-Object { $_.ConDatos -and -not $_.Consentimiento })
        $anual = @($filas | Where-Object { $_.AvisoAnual })
        Write-Host ''
        Write-Host (" Expedientes: {0} | con la retención vencida: {1} | sin consentimiento registrado: {2} | quieren aviso anual: {3}" -f $filas.Count, $vencidos.Count, $sinCons.Count, $anual.Count)
        foreach ($x in $vencidos) { Write-Host ("  VENCIDO  {0}  (última atención {1})" -f $x.Id, $(if ($x.Ultima) { $x.Ultima.ToString('yyyy-MM-dd') } else { '?' })) -ForegroundColor Yellow }
        foreach ($x in $sinCons) { Write-Host "  SIN CONSENTIMIENTO  $($x.Id)  (pídeselo en la próxima atención)" -ForegroundColor DarkYellow }
        foreach ($x in $anual) { Write-Host ("  AVISO ANUAL  {0}  {1}  (última atención {2})" -f $x.Cliente, $x.Id, $(if ($x.Ultima) { $x.Ultima.ToString('yyyy-MM-dd') } else { '?' })) -ForegroundColor DarkCyan }
        if ($Anonimizar) {
            if (-not $vencidos.Count) { Write-Host ' No hay expedientes vencidos con datos del cliente.' -ForegroundColor Green; exit 0 }
            if (-not (Confirm-Accion "Se quitan los datos del cliente de $($vencidos.Count) expediente(s) (quedan los datos técnicos).")) { Write-Host ' No se cambió nada.'; exit 0 }
            foreach ($x in $vencidos) { $n = Clear-DatosCliente -Ruta $x.Ruta -Confirm:$false; Write-Host "  Anonimizado: $($x.Id) ($n archivos borrados)" -ForegroundColor Green }
        } elseif ($vencidos.Count) {
            Write-Host ' Para quitarles los datos: datos_personales.ps1 -Anonimizar' -ForegroundColor DarkGray
        }
    }
}
exit 0
