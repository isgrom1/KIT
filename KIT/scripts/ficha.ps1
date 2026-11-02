#Requires -Version 5.1
<#
.SYNOPSIS
    Ficha del cliente desde la consola (respaldo de la interfaz gráfica).
.DESCRIPTION
    Reconoce el equipo, abre su expediente (o lo crea) y pregunta los datos de la atención abierta.
    Enter deja el valor actual y un guion (-) lo borra. Al final muestra lo que falta para los informes.
    Solo escribe ficha.json y trabajo.log dentro del expediente. Las fotos de recepción se copian a
    mano a la carpeta fotos_recepcion\ del expediente.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Formulario de consola')]
param()

$ErrorActionPreference = 'Stop'
$raizScripts = $PSScriptRoot
try {
    foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Expediente') { . (Join-Path $raizScripts "lib\$lib.ps1") }
    Initialize-Contexto -RaizScripts $raizScripts
    Initialize-Privacidad
} catch {
    Write-Host " No se pudo cargar el kit: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
$script:Cambiados = New-Object System.Collections.Generic.List[string]
$script:Letras = @{ C = 'CALOR'; L = 'LENTO'; A = 'ARCHIVOS'; R = 'REVISION' }

function Read-Linea {
    # Con la entrada redirigida (pruebas, o pegando respuestas) lee línea a línea.
    param([string]$Pregunta, [AllowNull()]$Actual, [string]$Ayuda)
    $mostrar = ''
    if ($Actual -is [array]) { if ($Actual.Count -gt 0) { $mostrar = " [$($Actual -join ', ')]" } }
    elseif ($null -ne $Actual -and "$Actual" -ne '') { $mostrar = " [$Actual]" }
    if ($Ayuda) { Write-Host "    $Ayuda" -ForegroundColor DarkGray }
    Write-Host ('  {0}{1}: ' -f $Pregunta, $mostrar) -NoNewline
    if ([Console]::IsInputRedirected) {
        $r = [Console]::In.ReadLine()
        Write-Host $r
    } else {
        $r = Read-Host
    }
    if ($null -eq $r) { return '' }
    $r.Trim()
}

function Get-ValorFicha {
    param($Exp, [string]$Atencion, [string]$Campo)
    if ($Campo -like 'cliente.*') { return $Exp.Ficha['cliente'][$Campo.Substring(8)] }
    $a = Get-EntradaAtencion -Expediente $Exp -Carpeta $Atencion
    if ($Campo -match '^(\w+)\.(\w+)$') { return $a[$Matches[1]][$Matches[2]] }
    , $a[$Campo]
}

function Request-Campo {
    # Pregunta hasta que el valor sirva. Enter = dejar como está; "-" = borrar.
    param($Exp, [string]$Atencion, [string]$Campo, [string]$Pregunta, [string]$Ayuda, [scriptblock]$Convertir)
    while ($true) {
        $r = Read-Linea -Pregunta $Pregunta -Actual (Get-ValorFicha -Exp $Exp -Atencion $Atencion -Campo $Campo) -Ayuda $Ayuda
        if ($r -eq '') { return }
        $valor = if ($r -eq '-') { $null } elseif ($Convertir) { & $Convertir $r } else { $r }
        try {
            Set-Ficha -Expediente $Exp -Atencion $Atencion -Valores @{ $Campo = $valor }
            $script:Cambiados.Add($Campo)
            return
        } catch {
            Write-Host ('    ' + ($_.Exception.Message -replace '^No se guardó la ficha:\s*-\s*', '')) -ForegroundColor Red
        }
    }
}

function Test-Si {
    param([string]$Texto)
    $Texto -match '^(?i)(s|si|sí)$'
}

# ------------------------------------------------------------------------------ inicio

Write-Host ''
Write-Host ' KIT SERVICIO - Ficha del cliente' -ForegroundColor Cyan
Write-Host ' --------------------------------' -ForegroundColor Cyan
try {
    $identidad = Get-IdentidadEquipo
    Move-CarpetasFase0
    $exp = Get-Expediente -Identidad $identidad
    if (-not $exp) {
        $exp = New-Expediente -Identidad $identidad
        Write-Host " Equipo sin expediente: se creó $($exp.Id)" -ForegroundColor Green
    }
} catch {
    Write-Host " No se pudo abrir el expediente: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
$hoy = (Get-Date).ToString('yyyy-MM-dd', $script:Invariante)
$atencion = Get-AtencionAbierta -Expediente $exp
if ($atencion) {
    $fecha = (Get-EntradaAtencion -Expediente $exp -Carpeta $atencion)['fecha']
    if ($fecha -ne $hoy) {
        # Enter o "s" sigue con la abierta (un trabajo que tomó varios días); "n" abre una nueva.
        $r = Read-Linea -Pregunta "La atención abierta es del $fecha. ¿Seguir con esa? (S/n)" -Actual $null
        if ($r -match '^(?i)n') { $atencion = $null }
    }
}
if (-not $atencion) {
    $atencion = New-Atencion -Expediente $exp
    Write-Host " Atención nueva: $atencion" -ForegroundColor Green
}

$eq = $exp.Ficha['equipo']
$a = Get-EntradaAtencion -Expediente $exp -Carpeta $atencion
Write-Host (" Equipo    : {0} {1} | S/N {2}" -f $eq['fabricante'], $eq['modelo'], $(if ($eq['serie']) { $eq['serie'] } else { '(genérica)' }))
Write-Host (" Expediente: {0}" -f $exp.Id)
Write-Host (" Atención  : {0} | antes: {1} | después: {2}" -f $atencion, $(if ($a['mediciones']['antes']) { $a['mediciones']['antes']['fecha'] } else { 'no' }), $(if ($a['mediciones']['despues']) { $a['mediciones']['despues']['fecha'] } else { 'no' }))
Write-Host ' Enter deja el valor como está; un guion (-) lo borra.' -ForegroundColor DarkGray
Write-Host ''

Write-Host ' CLIENTE (solo nombre, contacto y comuna: nada de RUT ni dirección)' -ForegroundColor White
Request-Campo -Exp $exp -Atencion $atencion -Campo 'cliente.nombre' -Pregunta 'Nombre'
Request-Campo -Exp $exp -Atencion $atencion -Campo 'cliente.contacto' -Pregunta 'Contacto' -Ayuda 'WhatsApp (+56 9 1234 5678) o correo'
Request-Campo -Exp $exp -Atencion $atencion -Campo 'cliente.comuna' -Pregunta 'Comuna'
Write-Host ''
Write-Host ' ATENCIÓN' -ForegroundColor White
Request-Campo -Exp $exp -Atencion $atencion -Campo 'motivos' -Pregunta 'Motivos' -Ayuda 'C = calor/ruido/se apaga, L = lento, A = archivos y espacio, R = revisión (ej: CL)' -Convertir {
    param($r)
    if ($r -match '^(?i)[CLAR]{1,4}$') { , @($r.ToUpperInvariant().ToCharArray() | ForEach-Object { $script:Letras["$_"] }) } else { $r }
}
Request-Campo -Exp $exp -Atencion $atencion -Campo 'sintoma' -Pregunta 'Síntoma (palabras del cliente)'
Request-Campo -Exp $exp -Atencion $atencion -Campo 'estado_fisico' -Pregunta 'Estado físico (golpes, piezas sueltas...)'
Request-Campo -Exp $exp -Atencion $atencion -Campo 'respaldo' -Pregunta '¿Tiene respaldo?' -Ayuda 's = sí, n = no, ? = no sabe'
$a = Get-EntradaAtencion -Expediente $exp -Carpeta $atencion
if ($a['bitlocker']['activo'] -ne $false) {
    $estado = if ($a['bitlocker']['activo']) { 'activo según el diagnóstico' } else { 'sin diagnóstico todavía' }
    Request-Campo -Exp $exp -Atencion $atencion -Campo 'bitlocker.clave_confirmada' -Pregunta "¿Clave de recuperación de BitLocker confirmada? ($estado)" -Ayuda 's / n'
}
if (Test-Si (Read-Linea -Pregunta '¿Llenar el checklist funcional? (s/N)' -Actual $null)) {
    Write-Host '    o = ok, f = falla, n = no aplica' -ForegroundColor DarkGray
    foreach ($item in $script:ItemsChecklist) { Request-Campo -Exp $exp -Atencion $atencion -Campo "checklist_funcional.$item" -Pregunta ('  ' + $item) }
}
$a = Get-EntradaAtencion -Expediente $exp -Carpeta $atencion
if (@($a['motivos']) -contains 'ARCHIVOS') {
    Write-Host ''
    Write-Host ' ARCHIVOS (obligatorio con este motivo)' -ForegroundColor White
    Request-Campo -Exp $exp -Atencion $atencion -Campo 'consentimiento_archivos' -Pregunta 'Consentimiento' -Ayuda 'l = solo leer, m = mover a _PARA_BORRAR, b = borrar aprobado'
    Request-Campo -Exp $exp -Atencion $atencion -Campo 'carpetas_protegidas' -Pregunta 'Carpetas protegidas' -Ayuda 'rutas separadas por ; (ej: C:\Users\Ana\Documents\Tesis;D:\Fotos)'
}
Write-Host ''
Write-Host ' TRABAJO' -ForegroundColor White
Request-Campo -Exp $exp -Atencion $atencion -Campo 'paquete' -Pregunta 'Paquete'
Request-Campo -Exp $exp -Atencion $atencion -Campo 'precio' -Pregunta 'Precio (pesos)'
Request-Campo -Exp $exp -Atencion $atencion -Campo 'notas' -Pregunta 'Notas'
if (-not $a['entregado'] -and (Test-Si (Read-Linea -Pregunta '¿Se entrega hoy el equipo? Cierra la atención (s/N)' -Actual $null))) {
    Set-Ficha -Expediente $exp -Atencion $atencion -Valores @{ entregado = $hoy }
    $script:Cambiados.Add('entregado')
    Write-Host "    Entregado hoy. Garantía hasta $((Get-EntradaAtencion -Expediente $exp -Carpeta $atencion)['garantia_hasta'])" -ForegroundColor Green
}

if ($script:Cambiados.Count -gt 0) {
    Write-TrabajoLog -Expediente $exp -Atencion $atencion -Texto ('FICHA | actualizados: ' + (@($script:Cambiados | Select-Object -Unique) -join ', '))
}
Write-Host ''
$faltan = @(Test-FichaCompleta -Expediente $exp -Atencion $atencion)
if ($faltan.Count -eq 0) {
    Write-Host ' Ficha completa: se pueden generar los informes.' -ForegroundColor Green
} else {
    Write-Host $(if ($faltan.Count -eq 1) { ' Falta 1 dato para los informes:' } else { " Faltan $($faltan.Count) datos para los informes:" }) -ForegroundColor Yellow
    foreach ($f in $faltan) { Write-Host "  - $($f.Texto)" -ForegroundColor Yellow }
}
Write-Host " Guardado en $(Join-Path $exp.Ruta 'ficha.json')"
exit 0
