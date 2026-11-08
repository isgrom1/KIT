# Fase G — escenario de la ventana: atención CALOR de punta a punta siguiendo SOLO la franja "Siguiente"
# (su botón lleva a cada panel). Anota en registro.txt el texto de la franja en cada paso, la versión de
# la barra de abajo y si se ve el aviso de integridad. Termina con "Mostrar al cliente" y entregado.
# Se carga dentro de kit.ps1 (-Captura -Escenario): usa $paso, $clic, Save-Captura y $Captura.
# Los CSV de sensores son sintéticos (90 °C antes, 70 °C después), generados en la carpeta de capturas.
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }
$escFranja = {
    param([string]$Cuando)
    $u = $script:Ui
    $s = $u.btnSiguiente.Tag
    & $escAnotar ("{0}: franja={1} | '{2}' | botón='{3}' ({4}) | codigo={5} | panel actual={6}" -f $Cuando, $u.bdSiguiente.Visibility, $u.txtSiguiente.Text, $u.btnSiguiente.Content, $u.btnSiguiente.Visibility, $(if ($s) { $s.Codigo }), $script:G.Panel)
}
$escCsv = {
    param([string]$Nombre, [int]$Temp)
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add('Date,Time,"CPU Package [°C]","Average Effective Clock [MHz]","Total CPU Usage [%]"')
    for ($i = 0; $i -lt 300; $i++) { $l.Add(('8.11.2026,10:{0:00}:{1:00}.000,{2}.0,3000.0,100.0' -f [int][math]::Floor($i * 2 / 60), (($i * 2) % 60), ($Temp + ($i % 3)))) }
    $r = Join-Path $Captura $Nombre
    [IO.File]::WriteAllLines($r, $l, (New-Object Text.UTF8Encoding($true)))
    $r
}
$escCondiciones = {
    param([string]$Duracion)
    $u = $script:Ui
    $u.cmbEnchufado.SelectedIndex = 1; $u.txtCondPlan.Text = 'Equilibrado'; $u.txtCondVentiladores.Text = 'Automático'; $u.txtCondSuperficie.Text = 'Mesa dura'
    $u.txtCondAmbiente.Text = '22'; $u.txtCondCarga.Text = 'OCCT CPU (prueba sintética)'; $u.txtCondDuracion.Text = $Duracion
    & $clic 'btnGuardarCondiciones'
}
$escImportar = {
    param([string]$Momento, [string]$Ruta)
    Invoke-TareaKit -Accion 'importar_sensores' -Parametros @{ momento = $Momento; ruta = $Ruta } -Texto 'Leyendo el CSV de sensores...' -AlResultado { param($r) & $escAnotar "CSV $($script:G.Momento): $($r | ConvertTo-Json -Compress)"; Show-Medicion; Show-Estado }
}

& $paso 1 {
    $i = $script:Integridad
    & $escAnotar "inicio: versión='$($script:Ui.txtVersion.Text)' | integridad=$($i.Estado) (franja $($script:Ui.bdIntegridad.Visibility)) | equipo previo=$([bool]$script:G.Exp)"
    & $escFranja 'inicio'; & $escFoto 'g_01_inicio'
}
& $paso 0.3 { $script:Ui.tgCalor.IsChecked = $true }
& $paso 0.6 { & $escFranja 'motivo CALOR'; & $escFoto 'g_02_motivo' }
& $paso 0.3 { & $clic 'btnSiguiente' }
& $paso 0.5 {
    & $escFranja 'clic en la franja'
    $u = $script:Ui
    $u.txtNombre.Text = 'Cliente Prueba G'; $u.txtContacto.Text = '+56 9 5555 0007'; $u.txtComuna.Text = 'Ñuñoa'
    $u.txtSintoma.Text = 'Se calienta con carga'; $u.txtEstadoFisico.Text = 'Sin golpes'
    foreach ($k in @($script:G.Chk.Keys)) { $script:G.Chk[$k].SelectedIndex = 1 }
    & $clic 'btnGuardarFicha'
}
& $paso 0.8 { & $escFranja 'ficha guardada (sin paquete ni precio)'; & $escFoto 'g_03_ficha' }
& $paso 0.3 { & $clic 'btnSiguiente' }
& $paso 0.5 {
    & $escAnotar "clic en la franja -> panel=$($script:G.Panel) momento=$($script:G.Momento)"
    $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar'
}
& $paso 1 { & $escAnotar "ANTES: '$($script:Ui.txtMedicionEstado.Text)'"; & $escFranja 'diagnóstico ANTES listo'; & $escFoto 'g_04_antes' } { -not $script:G.Tarea }
& $paso 0.3 { & $escImportar 'antes' (& $escCsv 'sensores_antes.csv' 90) }
& $paso 0.6 { & $escFranja 'CSV ANTES leído' } { -not $script:G.Tarea }
& $paso 0.3 { & $escCondiciones '10' }
& $paso 0.8 { & $escFranja 'condiciones ANTES guardadas'; & $escFoto 'g_05_antes_completo' }
& $paso 0.3 { & $clic 'btnSiguiente' }
& $paso 0.6 { & $escAnotar "clic en la franja -> panel=$($script:G.Panel)"; & $escFoto 'g_06_trabajo' }
& $paso 0.3 { & $clic 'btnTrabajoTerminado' }
& $paso 0.8 { & $escFranja 'trabajo terminado'; & $clic 'btnSiguiente' }
& $paso 0.5 { & $escAnotar "clic en la franja -> panel=$($script:G.Panel) momento=$($script:G.Momento)"; & $clic 'btnDiagnosticar' }
& $paso 1 { & $escAnotar "DESPUÉS: '$($script:Ui.txtMedicionEstado.Text)'"; & $escFranja 'diagnóstico DESPUÉS listo' } { -not $script:G.Tarea }
& $paso 0.3 { & $escImportar 'despues' (& $escCsv 'sensores_despues.csv' 70) }
& $paso 0.6 { & $escFranja 'CSV DESPUÉS leído' } { -not $script:G.Tarea }
& $paso 0.3 { & $escCondiciones '10' }
& $paso 0.8 { & $escFranja 'condiciones DESPUÉS guardadas'; & $escFoto 'g_07_despues_completo' }
& $paso 0.3 { & $clic 'btnSiguiente' }
& $paso 0.5 {
    & $escAnotar "clic en la franja -> panel=$($script:G.Panel)"
    $script:Ui.txtPaquete.Text = 'Mantención por temperatura'; $script:Ui.txtPrecio.Text = '35000'; $script:Ui.cmbRespaldo.SelectedIndex = 1
    & $clic 'btnGuardarFicha'
}
& $paso 0.8 { & $escFranja 'paquete y precio guardados'; & $clic 'btnSiguiente' }
& $paso 0.5 { & $escAnotar "clic en la franja -> panel=$($script:G.Panel)"; & $clic 'btnGenerar' }
& $paso 1 { & $escAnotar "informes: '$($script:Ui.txtEstado.Text)'"; & $escFranja 'informes generados'; & $escFoto 'g_08_informe' } { -not $script:G.Tarea }
& $paso 0.3 { Show-VistaCliente }
& $paso 1 { Save-Captura $script:G.VentanaCliente.Content 'g_09_mostrar_cliente'; $script:G.VentanaCliente.Close() }
& $paso 0.3 { & $clic 'btnSiguiente' }
& $paso 0.5 { & $escAnotar "clic en la franja -> panel=$($script:G.Panel)"; & $clic 'btnEntregado' }
& $paso 0.8 { & $escFranja 'entregada'; & $escFoto 'g_10_entregada' }
