# Alertas.ps1 - Alertas, partes incompletas, errores por paso y umbrales de config.json.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:OrdenSeveridad = @{ CRITICO = 0; AVISO = 1; INFO = 2 }

function Add-Alerta {
    param(
        [Parameter(Mandatory)][ValidateSet('CRITICO', 'AVISO', 'INFO')][string]$Severidad,
        [Parameter(Mandatory)][string]$Codigo,
        [Parameter(Mandatory)][string]$Texto
    )
    $script:Ctx.Alertas.Add([pscustomobject][ordered]@{
            Severidad = $Severidad
            Codigo    = $Codigo
            Seccion   = $script:Ctx.SeccionActual
            Texto     = $Texto
        })
    $nivel = if ($Severidad -eq 'INFO') { 'INFO' } else { 'AVISO' }
    Write-LogKit -Nivel $nivel -Mensaje "Alerta $Codigo [$Severidad] $Texto"
}

function Get-AlertasOrdenadas {
    , @($script:Ctx.Alertas | Sort-Object { $script:OrdenSeveridad[$_.Severidad] }, Seccion, Codigo)
}

function Add-Incompleto {
    param(
        [Parameter(Mandatory)][string]$Parte,
        [string]$Motivo = 'requiere admin'
    )
    $script:Ctx.Incompletos.Add([pscustomobject][ordered]@{
            Seccion = $script:Ctx.SeccionActual
            Parte   = $Parte
            Motivo  = $Motivo
        })
    Write-LogKit -Nivel AVISO -Mensaje "Incompleto: $Parte ($Motivo)"
}

function Add-ErrorPaso {
    param(
        [Parameter(Mandatory)][string]$Paso,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Registro
    )
    $ubicacion = ''
    if ($Registro.InvocationInfo -and $Registro.InvocationInfo.ScriptName) {
        $ubicacion = '{0}:{1}' -f (Split-Path -Leaf $Registro.InvocationInfo.ScriptName), $Registro.InvocationInfo.ScriptLineNumber
    }
    $script:Ctx.Errores.Add([pscustomobject][ordered]@{
            Seccion   = $script:Ctx.SeccionActual
            Paso      = $Paso
            Mensaje   = $Registro.Exception.Message.Trim()
            Ubicacion = $ubicacion
        })
    Write-LogKit -Nivel ERROR -Mensaje "$Paso : $($Registro.Exception.Message.Trim()) ($ubicacion)"
}

function Invoke-Paso {
    # Ejecuta un paso dentro de una sección; si falla, registra el error y devuelve $null
    # para que la sección siga con lo demás.
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)][scriptblock]$Bloque
    )
    try { & $Bloque } catch { Add-ErrorPaso -Paso $Nombre -Registro $_; $null }
}

function Get-Umbral {
    param([Parameter(Mandatory)][string]$Nombre)
    $v = $script:Ctx.Config.umbrales.$Nombre
    if ($null -eq $v) { throw "Falta el umbral '$Nombre' en config.json" }
    $v
}
