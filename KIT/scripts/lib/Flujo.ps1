# Flujo.ps1 - Qué le falta a la atención y a qué panel ir. Lo usan la ventana (franja "Siguiente") y el
# menú de consola de trabajo. Solo lee. Requiere lib\Expediente y motivos\calor.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

function Get-SiguientePaso {
    # Devuelve el primer pendiente de la atención, en el orden en que se trabaja: Codigo (para pruebas),
    # Texto (para el técnico), Panel y Momento (adónde lleva el botón de la ventana) y Boton (su texto).
    param($Expediente, [string]$Atencion)
    $paso = { param($Codigo, $Texto, $Panel, $Momento, $Boton) [pscustomobject][ordered]@{ Codigo = $Codigo; Texto = $Texto; Panel = $Panel; Momento = $Momento; Boton = $Boton } }
    $a = if ($Expediente -and $Atencion) { Get-EntradaAtencion -Expediente $Expediente -Carpeta $Atencion } else { $null }
    $motivos = @(if ($a) { $a['motivos'] | Where-Object { $_ } })
    if (-not $a -or $motivos.Count -eq 0) { return & $paso 'motivos' 'Marca por qué viene el equipo.' 'pnlInicio' $null 'Ir a Inicio' }
    if ($a['entregado']) { return & $paso 'entregada' "Atención entregada el $($a['entregado']). En tu PC, sincroniza con el maestro." $null $null $null }

    $faltaFicha = @(Test-FichaCompleta -Expediente $Expediente -Atencion $Atencion | Where-Object { $_.Campo -notin 'paquete', 'precio', 'tecnico.nombre', 'tecnico.contacto' })
    if ($faltaFicha.Count) { return & $paso 'ficha' "Completa la ficha: $(($faltaFicha | ForEach-Object { $_.Texto }) -join ', ')." 'pnlFicha' $null 'Ir a ① Ficha' }

    $calor = $motivos -contains 'CALOR'
    $pendienteMedicion = {
        param([string]$Momento)
        $nombre = $Momento.ToUpperInvariant() -replace 'DESPUES', 'DESPUÉS'
        $boton = if ($Momento -eq 'antes') { 'Ir a ② Antes' } else { 'Ir a ④ Después' }
        if (-not (Test-Medicion -Expediente $Expediente -Atencion $Atencion -Momento $Momento)) { return & $paso "diagnostico_$Momento" "Haz el diagnóstico $nombre." 'pnlMedicion' $Momento $boton }
        if (-not $calor) { return $null }
        if (-not (Read-SensoresMedicion -Expediente $Expediente -Atencion $Atencion -Momento $Momento)) {
            $como = if ($Momento -eq 'antes') { '5 minutos de reposo, HWiNFO grabando y OCCT 10 minutos' } else { 'la misma prueba del ANTES' }
            return & $paso "csv_$Momento" "Mide la temperatura $nombre ($como) y toca Importar CSV de sensores, a la derecha." 'pnlMedicion' $Momento $boton
        }
        if (@(Get-CondicionesFaltantes -Condiciones $a['condiciones_medicion'][$Momento]).Count) { return & $paso "condiciones_$Momento" "Completa las condiciones de la medición $nombre y toca Guardar condiciones." 'pnlMedicion' $Momento $boton }
        $null
    }
    $p = & $pendienteMedicion 'antes'
    if ($p) { return $p }
    if (-not $a['trabajo_terminado']) { return & $paso 'trabajo' 'Haz el trabajo y toca Marcar trabajo terminado.' 'pnlTrabajo' $null 'Ir a ③ Trabajo' }
    $p = & $pendienteMedicion 'despues'
    if ($p) { return $p }

    $faltaInforme = @(Test-FichaCompleta -Expediente $Expediente -Atencion $Atencion)
    if ($faltaInforme.Count) { return & $paso 'ficha_informe' "Para los informes falta: $(($faltaInforme | ForEach-Object { $_.Texto }) -join ', ')." 'pnlFicha' $null 'Ir a ① Ficha' }
    if (-not [IO.File]::Exists((Join-Path (Join-Path $Expediente.Ruta $Atencion) 'informe_cliente.html'))) { return & $paso 'informe' 'Genera los informes.' 'pnlInforme' $null 'Ir a ⑤ Informe' }
    & $paso 'entregar' 'Muéstrale el resultado al cliente y marca la atención como entregada.' 'pnlFicha' $null 'Ir a ① Ficha'
}
