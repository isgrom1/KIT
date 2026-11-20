#Requires -Version 5.1
<#
.SYNOPSIS
    Arma remoto\_salida\Para_enviar: una carpeta por pack del catálogo con lo que se le manda al cliente.
.DESCRIPTION
    En cada carpeta (01_Diagnostico_a_distancia, 02_..., ...):
      QUE_HACE.txt        para el cliente: qué hace, qué NO hace, cuánto demora y cuánto cuesta.
      MENSAJE_WHATSAPP.txt el texto listo para copiar y pegar.
      el archivo a mandar, si el pack lo tiene (el ZIP del diagnóstico remoto, enlazado sin copiar 200 MB).
      PASOS_ISAAC.txt     solo en los packs que llevan un paso tuyo (trabajo a distancia, presencial).
    Y en la raíz LEEME_ISAAC.txt: qué mandar según lo que pida el cliente.
    Los precios salen de config_local.json; sin ellos dice "a convenir".
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remoto\armar_envios.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de consola para Isaac')]
[CmdletBinding()]
param(
    [string]$Salida,
    [string]$ZipDiagnostico
)
$ErrorActionPreference = 'Stop'
if (-not $Salida) { $Salida = Join-Path $PSScriptRoot '_salida\Para_enviar' }
$kitScripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
. (Join-Path $kitScripts 'lib\Comun.ps1')
Initialize-Contexto -RaizScripts $kitScripts
if (-not $ZipDiagnostico) { $ZipDiagnostico = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '_salida') -Filter 'Diagnostico_remoto_*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object FullName) | Select-Object -First 1 }
$cat = @(Get-CatalogoPaquetes)
if (-not $cat.Count) { throw 'No hay catálogo de packs en config.json' }
$tec = $script:Ctx.Config.tecnico
$firma = "$($tec.nombre)$(if ($tec.contacto) { " · $($tec.contacto)" })"
$utf8 = New-Object Text.UTF8Encoding $true

if ([IO.Directory]::Exists($Salida)) { Remove-Item -LiteralPath $Salida -Recurse -Force }
$null = [IO.Directory]::CreateDirectory($Salida)

$noHace = @('No instala programas ni cambia nada sin mostrártelo antes.', 'No revisa documentos, fotos, contraseñas ni historial de navegación.', 'No borra archivos tuyos.')
$indice = New-Object System.Collections.Generic.List[string]
$indice.Add('PARA ENVIAR - qué mandarle a cada cliente')
$indice.Add('=========================================')
$indice.Add('')
foreach ($p in $cat) {
    # Sin tildes ni signos: "Diagnóstico a distancia" -> "Diagnostico_a_distancia".
    $sinTilde = -join ($p.Nombre.Normalize([Text.NormalizationForm]::FormD).ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    $nombreCarpeta = '{0:00}_{1}' -f $p.Numero, (($sinTilde -replace '[^A-Za-z0-9]+', '_').Trim('_'))
    $dir = Join-Path $Salida $nombreCarpeta
    $null = [IO.Directory]::CreateDirectory($dir)
    $precio = Format-PrecioPaquete $p

    # QUE_HACE.txt (para el cliente)
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add($p.Nombre.ToUpper())
    $l.Add(('=' * $p.Nombre.Length))
    $l.Add('')
    $l.Add($p.Resumen)
    $l.Add('')
    $l.Add("Precio: $precio$(if ($p.Descuenta -and $p.Id -ne 'diagnostico_remoto') { ' (si ya pagaste el diagnóstico a distancia, se descuenta)' })")
    $l.Add("Modalidad: $($p.Modo)")
    if ($p.Duracion) { $l.Add("Tiempo: $($p.Duracion)") }
    $l.Add('')
    $l.Add('QUÉ SE HACE')
    foreach ($x in $p.QueHace) { $l.Add("- $x") }
    if ($p.Mandar -ne 'nada') {
        $l.Add('')
        $l.Add('QUÉ NO SE HACE')
        foreach ($x in $noHace) { $l.Add("- $x") }
    }
    if ($p.Mandar -eq 'diagnostico') {
        $l.Add('')
        $l.Add('CÓMO SE USA')
        $l.Add('1. Descomprime el ZIP (clic derecho > Extraer todo).')
        $l.Add('2. Abre la carpeta y haz doble clic en DIAGNOSTICO.cmd. Acepta el permiso de administrador.')
        $l.Add('3. Espera sin usar el computador hasta que diga LISTO (se abren solos dos programas: no los toques).')
        $l.Add('4. Al final se abre sola la carpeta con el archivo "Diagnostico_para_Isaac_....kitdiag": mándamelo.')
    }
    $l.Add('')
    $l.Add($firma)
    [IO.File]::WriteAllText((Join-Path $dir 'QUE_HACE.txt'), ($l -join "`r`n") + "`r`n", $utf8)

    # MENSAJE_WHATSAPP.txt
    $m = switch ($p.Mandar) {
        'diagnostico' { "¡Hola! Te mando el $($p.Nombre.ToLower()) ($precio). $($p.Resumen) Descomprime el ZIP, abre DIAGNOSTICO.cmd, acepta el permiso y espera unos 20 minutos sin usar el computador. Al final me mandas el archivo .kitdiag que queda en tu Escritorio (va cifrado, solo yo lo puedo abrir). Te adjunto también QUE_HACE.txt con el detalle." }
        'trabajo' { "¡Hola! Te cuento de la $($p.Nombre.ToLower()) ($precio). $($p.Resumen) Primero te mando el diagnóstico a distancia; con eso te preparo un paquete solo para tu computador, que te muestra los cambios antes de aplicarlos y se puede deshacer. Te adjunto QUE_HACE.txt con el detalle." }
        default { "¡Hola! Te cuento del servicio $($p.Nombre.ToLower()) ($precio). $($p.Resumen) Te adjunto QUE_HACE.txt con el detalle. ¿Te acomoda que coordinemos?" }
    }
    [IO.File]::WriteAllText((Join-Path $dir 'MENSAJE_WHATSAPP.txt'), "$m`r`n`r`n$firma`r`n", $utf8)

    # Archivo a mandar y pasos para Isaac
    $mandar = 'solo el mensaje y QUE_HACE.txt'
    if ($p.Mandar -eq 'diagnostico') {
        if ($ZipDiagnostico -and [IO.File]::Exists($ZipDiagnostico)) {
            $destino = Join-Path $dir (Split-Path -Leaf $ZipDiagnostico)
            try { $null = New-Item -ItemType HardLink -Path $destino -Target $ZipDiagnostico -ErrorAction Stop } catch { Copy-Item -LiteralPath $ZipDiagnostico -Destination $destino }
            $mandar = "el ZIP $(Split-Path -Leaf $ZipDiagnostico) + QUE_HACE.txt"
        } else {
            $mandar = 'el ZIP del diagnóstico (falta: corre remoto\armar_paquete.ps1 y vuelve a correr este script)'
        }
    }
    $pasos = switch ($p.Mandar) {
        'trabajo' { @('1. Mándale el diagnóstico (carpeta 01) y espera su .kitdiag.', '2. Arrástralo sobre remoto\ABRIR_KITDIAG.cmd: revisa el informe y la hoja técnica.', '3. Arrastra la carpeta que quedó sobre remoto\ARMAR_TRABAJO.cmd y elige los cambios.', '4. Mándale el ZIP remoto\_salida\Trabajo_<equipo>_<fecha>.zip con este mensaje: "Descomprime, abre TRABAJO.cmd, escribe SI, reinicia y vuelve a abrir TRABAJO.cmd. Al final me mandas el archivo .kitdiag".', '5. Su .kitdiag final se abre igual (ABRIR_KITDIAG.cmd): sale el informe del antes y el después.') }
        'nada' { if ($p.Modo -eq 'presencial') { @('Presencial: coordina el retiro o la visita. En el equipo, INICIAR.cmd del pendrive y en la ficha el paquete con su número (el precio se llena solo).') } else { @('Pídele marca y modelo (o foto de la etiqueta de abajo) y respóndele qué comprar.', 'Si después compra o instala contigo, se descuenta.') } }
        default { @() }
    }
    if ($pasos.Count) { [IO.File]::WriteAllText((Join-Path $dir 'PASOS_ISAAC.txt'), ($pasos -join "`r`n") + "`r`n", $utf8) }
    if ($p.Mandar -eq 'trabajo') { $mandar = 'primero el diagnóstico (01); después el paquete que arma ARMAR_TRABAJO.cmd' }

    $indice.Add(('{0}) {1} - {2} - {3}' -f $p.Numero, $p.Nombre, $p.Modo, $precio))
    $indice.Add("   Si el cliente quiere: $($p.Resumen)")
    $indice.Add("   Mandar: $mandar")
    $indice.Add("   Carpeta: $nombreCarpeta")
    $indice.Add('')
}
$indice.Add('En cada carpeta: QUE_HACE.txt (para el cliente), MENSAJE_WHATSAPP.txt (copiar y pegar) y, si hay, el archivo.')
$indice.Add('Los precios salen de KIT\scripts\config\config_local.json ("precios"). Cambia ahí y vuelve a correr este script.')
[IO.File]::WriteAllText((Join-Path $Salida 'LEEME_ISAAC.txt'), ($indice -join "`r`n") + "`r`n", $utf8)
Write-Host "Listo: $Salida ($($cat.Count) packs)" -ForegroundColor Green
