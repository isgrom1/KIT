# Fase H — escenario de la ventana: CSV encontrado solo, PDF y mensaje del pre-informe, paquete de soporte.
# Se carga dentro de kit.ps1 (-Captura -Escenario) corriendo desde una copia del kit hecha con
# actualizar_pendrive.ps1 -Destino X:\kitservicio_prueba\... Deja un CSV sintético de HWiNFO (90 °C) en la
# carpeta KIT de esa copia, como si el técnico lo hubiera guardado ahí. Usa $paso, $clic y Save-Captura.
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }
$escCsv = Join-Path $script:Ctx.RaizKit 'antes_prueba.CSV'
# Uno de otro equipo, más nuevo: termina con la fila de grupos de HWiNFO de un Dell. No se debe ofrecer.
$escOtro = Join-Path $script:Ctx.RaizKit 'otro_equipo.CSV'
$escOtro2 = Join-Path $script:Ctx.RaizKit 'otro_despues.CSV'

& $paso 1 {
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add('Date,Time,"CPU Package [°C]","Average Effective Clock [MHz]","Total CPU Usage [%]"')
    for ($i = 0; $i -lt 300; $i++) { $l.Add(('8.11.2026,10:{0:00}:{1:00}.000,{2}.0,3000.0,100.0' -f [int][math]::Floor($i * 2 / 60), (($i * 2) % 60), (90 + ($i % 3)))) }
    [IO.File]::WriteAllLines($escCsv, $l, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::SetLastWriteTime($escCsv, (Get-Date).AddMinutes(-1))
    $o = New-Object System.Collections.Generic.List[string]; $o.AddRange($l); $o.Add($l[0])
    $o.Add(',,Sistema: DELL Inspiron 3493,CPU [#0]: Intel Core i3-1005G1,CPU [#0]: Intel Core i3-1005G1: DTS')
    [IO.File]::WriteAllLines($escOtro, $o, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::SetLastWriteTime($escOtro, (Get-Date).AddSeconds(-30))
    & $escAnotar "versión: '$($script:Ui.txtVersion.Text)' | CSV de prueba en $escCsv"
    $script:Ui.tgCalor.IsChecked = $true
}
& $paso 0.6 {
    Show-Panel 'pnlFicha'
    $u = $script:Ui
    $u.txtNombre.Text = 'Cliente Prueba H'; $u.txtContacto.Text = '+56 9 5555 0008'; $u.txtComuna.Text = 'Maipú'
    $u.txtSintoma.Text = 'Se calienta'; $u.txtPaquete.Text = 'Mantención por temperatura'; $u.txtPrecio.Text = '35000'
    foreach ($k in @($script:G.Chk.Keys)) { $script:G.Chk[$k].SelectedIndex = 1 }
    & $clic 'btnGuardarFicha'
}
& $paso 0.6 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar' }
& $paso 1 {
    Show-Medicion
    & $escAnotar "ANTES listo | aviso CSV: $($script:Ui.bdCsvDetectado.Visibility) '$($script:Ui.txtCsvDetectado.Text)' | botón habilitado: $($script:Ui.btnImportarDetectado.IsEnabled)"
    & $escFoto 'h_01_csv_encontrado'
} { -not $script:G.Tarea }
& $paso 0.3 { & $clic 'btnImportarDetectado' }
& $paso 1 {
    & $escAnotar "importado: '$($script:Ui.txtSensores.Text)' | original sigue: $([IO.File]::Exists($escCsv)) | aviso CSV: $($script:Ui.bdCsvDetectado.Visibility) | estado: '$($script:Ui.txtEstado.Text)'"
    $u = $script:Ui
    $u.cmbEnchufado.SelectedIndex = 1; $u.txtCondPlan.Text = 'Equilibrado'; $u.txtCondVentiladores.Text = 'Automático'; $u.txtCondSuperficie.Text = 'Mesa dura'
    $u.txtCondAmbiente.Text = '22'; $u.txtCondCarga.Text = 'OCCT CPU'; $u.txtCondDuracion.Text = '10'
    & $clic 'btnGuardarCondiciones'
} { -not $script:G.Tarea }
& $paso 0.8 { & $escFoto 'h_02_csv_importado'; & $clic 'btnPdfPre' }
& $paso 1 {
    $pdf = Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'pre_informe.pdf'
    & $escAnotar "PDF del pre-informe: existe=$([IO.File]::Exists($pdf)) $(if ([IO.File]::Exists($pdf)) { "$([math]::Round((Get-Item -LiteralPath $pdf).Length / 1KB)) KB" }) | estado: '$($script:Ui.txtEstado.Text)'"
    & $clic 'btnMensajePre'
} { -not $script:G.Tarea }
& $paso 0.5 { Show-Panel 'pnlTecnico'; & $clic 'btnSoporte' }
& $paso 0.8 { & $escAnotar "soporte: '$($script:Ui.txtEstado.Text)'"; & $escFoto 'h_03_soporte' }
& $paso 0.3 { Show-Panel 'pnlInforme' }
& $paso 0.5 { & $escFoto 'h_04_informe_botones' }
& $paso 0.5 {
    # DESPUÉS con solo un CSV de otro equipo a la vista: avisa de cuál es y no muestra el botón.
    [IO.File]::Copy($escOtro, $escOtro2, $true)
    # Un segundo después de importar el ANTES: el DESPUÉS solo mira los posteriores a eso.
    $resAntes = Join-Path (Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'antes') 'sensores_resumen.json'
    [IO.File]::SetLastWriteTime($escOtro2, [IO.File]::GetLastWriteTime($resAntes).AddSeconds(1))
    $script:G.Momento = 'despues'; Show-Panel 'pnlMedicion'; Show-Medicion
    $u = $script:Ui
    & $escAnotar "DESPUÉS, solo otro equipo | aviso CSV: $($u.bdCsvDetectado.Visibility) '$($u.txtCsvDetectado.Text)' | botón: $($u.btnImportarDetectado.Visibility)"
}
& $paso 0.5 { & $escFoto 'h_05_csv_otro_equipo' }
