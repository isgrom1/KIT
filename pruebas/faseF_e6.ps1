# Fase F — escenario 6 (prueba 6): sincronizar al maestro de prueba liberando el USB, abrir desde el maestro
# la atención de la prueba 1 (modo consulta) y regenerar su informe allá. Sin admin.
# Se carga dentro de kit.ps1 (-Captura -Escenario -RutaMaestro <maestro de prueba>).
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }

& $paso 0.5 { Show-Panel 'pnlExpedientes' }
& $paso 0.8 { & $escAnotar "USB: $($script:G.TablaExp.Rows.Count) expedientes | '$($script:Ui.txtExpedientes.Text)' | maestro: '$($script:Ui.txtMaestro.Text)'"; & $escFoto 'e6_01_expedientes_usb' }
& $paso 0.3 { $script:Ui.chkLiberarUsb.IsChecked = $true; & $clic 'btnSincronizar' }
& $paso 1 { & $escAnotar "sincronización: '$($script:Ui.txtSync.Text)'"; & $escFoto 'e6_02_sincronizado' } { -not $script:G.Tarea }
& $paso 0.3 { $script:Ui.rbFuenteMaestro.IsChecked = $true }
& $paso 0.8 {
    & $escAnotar "maestro: $($script:G.TablaExp.Rows.Count) expedientes | atenciones en la lista: $(@($script:Ui.cmbAtencionExp.Items | ForEach-Object { $_.Content }) -join ' || ')"
    $primera = @($script:Ui.cmbAtencionExp.Items | Where-Object { $_.IsEnabled }) | Select-Object -First 1
    $script:Ui.cmbAtencionExp.SelectedItem = $primera
    & $escFoto 'e6_03_maestro'
}
& $paso 0.3 { & $clic 'btnAbrirExp' }
& $paso 0.8 {
    & $escAnotar "consulta: ajeno=$($script:G.Ajeno) origen=$($script:G.Origen) atención=$($script:G.At) | Antes=$($script:Ui.navAntes.IsEnabled) Trabajo=$($script:Ui.navTrabajo.IsEnabled) Después=$($script:Ui.navDespues.IsEnabled) Informe=$($script:Ui.navInforme.IsEnabled)"
    & $escFoto 'e6_04_consulta_maestro'
}
& $paso 0.3 {
    $script:G.InformeF = Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'informe_cliente.html'
    $script:G.InformeFAntes = (Get-Item -LiteralPath $script:G.InformeF).LastWriteTime
    Show-Panel 'pnlInforme'; & $clic 'btnGenerar'
}
& $paso 1 {
    $nuevo = (Get-Item -LiteralPath $script:G.InformeF).LastWriteTime
    & $escAnotar "informe regenerado en el maestro: $($nuevo -gt $script:G.InformeFAntes) ($($script:G.InformeF)) | '$($script:Ui.txtEstado.Text)'"
    & $escFoto 'e6_05_informe_regenerado'
} { -not $script:G.Tarea }
& $paso 0.3 { & $clic 'btnVolverEquipo' }
& $paso 0.8 { & $escAnotar "vuelta: ajeno=$($script:G.Ajeno) | '$($script:Ui.txtEquipo.Text)' | '$($script:Ui.txtCliente.Text)'"; & $escFoto 'e6_06_vuelta_equipo' }
