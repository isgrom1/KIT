# Fase F — escenario 1 (pruebas 1 y 5): cliente nuevo con CALOR. Sin admin: ficha, ANTES, CSV de antes y
# condiciones; ahí se toca "Relanzar como admin" y la ventana elevada sigue la MISMA atención: ANTES con
# admin, checklist físico, DESPUÉS, CSV de después, informes, mostrar al cliente y entregado.
# Se carga dentro de kit.ps1 (-Captura -Escenario): usa $paso, $clic y Save-Captura.
# CSV: el de antes es el real de Isaac (reg.CSV). El de después real (59/71 °C) no existe: se usa otro CSV
# real de este equipo (asdasd.CSV) como reemplazo, y así se informa.
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }
$escDocs = [Environment]::GetFolderPath('MyDocuments')
$escCsvAntes = Join-Path $escDocs '08 Datos sueltos (csv-json)\reg.CSV'
$escCsvDespues = Join-Path $escDocs 'asdasd.CSV'

if (-not $script:Ctx.Admin.Elevado) {
    & $paso 1 { & $escAnotar "inicio: expediente previo=$([bool]$script:G.Exp) | '$($script:Ui.txtCliente.Text)' | $($script:Ui.txtAdmin.Text)"; & $escFoto 'e1_01_inicio_cliente_nuevo' }
    & $paso 0.3 { $script:Ui.tgCalor.IsChecked = $true }
    & $paso 0.5 {
        & $escAnotar "atención creada: $($script:G.At) en $($script:G.Exp.Ruta)"
        Show-Panel 'pnlFicha'
        $u = $script:Ui
        $u.txtNombre.Text = 'Cliente Prueba F1'; $u.txtContacto.Text = '+56 9 5555 0001'; $u.txtComuna.Text = 'Maipú'
        $u.txtSintoma.Text = 'Se calienta y baja los FPS jugando'; $u.txtEstadoFisico.Text = 'Rejillas con polvo, sin golpes'
        $u.txtPaquete.Text = 'Mantención por temperatura'; $u.txtPrecio.Text = '35000'; $u.cmbRespaldo.SelectedIndex = 1
        foreach ($k in @($script:G.Chk.Keys)) { $script:G.Chk[$k].SelectedIndex = 1 }
        & $clic 'btnGuardarFicha'
    }
    & $paso 0.8 { & $escAnotar "ficha: '$($script:Ui.txtFichaEstado.Text)'"; & $escFoto 'e1_02_ficha' }
    & $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar' }
    & $paso 6 { & $escFoto 'e1_03_antes_en_curso' }
    & $paso 1 { & $escAnotar "ANTES sin admin: '$($script:Ui.txtMedicionEstado.Text)' | alertas=$($script:Ui.lstAlertas.Items.Count)"; & $escFoto 'e1_04_antes_sin_admin' } { -not $script:G.Tarea }
    & $paso 0.3 { Invoke-TareaKit -Accion 'importar_sensores' -Parametros @{ momento = 'antes'; ruta = $escCsvAntes } -Texto 'Leyendo el CSV de sensores...' -AlResultado { param($r) & $escAnotar "CSV antes: $($r | ConvertTo-Json -Compress)"; Show-Medicion; Show-Estado } }
    & $paso 0.5 {
        $u = $script:Ui
        $u.cmbEnchufado.SelectedIndex = 1; $u.txtCondPlan.Text = 'Equilibrado'; $u.txtCondVentiladores.Text = 'Automático'; $u.txtCondSuperficie.Text = 'Mesa dura'
        $u.txtCondAmbiente.Text = '22'; $u.txtCondCarga.Text = 'Juego (prueba)'; $u.txtCondDuracion.Text = '108'
        & $clic 'btnGuardarCondiciones'
    } { -not $script:G.Tarea }
    & $paso 0.8 { & $escAnotar "sensores: '$($script:Ui.txtSensores.Text)' | condiciones: '$($script:Ui.txtCondEstado.Text)'"; & $escFoto 'e1_05_antes_csv_condiciones' }
    & $paso 0.3 { & $escAnotar "relanzando como admin a mitad de la atención $($script:G.At)"; & $clic 'btnRelanzar' }
} else {
    & $paso 1 { & $escAnotar "relanzada: $($script:Ui.txtAdmin.Text) | atención=$($script:G.At) | '$($script:Ui.txtCliente.Text)'"; & $escFoto 'e1_06_relanzada_admin' }
    & $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion' }
    & $paso 0.5 { & $escAnotar "ANTES previo: '$($script:Ui.txtMedicionEstado.Text)'"; & $clic 'btnDiagnosticar' }
    & $paso 1 { & $escAnotar "ANTES con admin: '$($script:Ui.txtMedicionEstado.Text)' | alertas=$($script:Ui.lstAlertas.Items.Count) | sensores: '$($script:Ui.txtSensores.Text)'"; & $escFoto 'e1_07_antes_con_admin' } { -not $script:G.Tarea }
    & $paso 0.3 {
        Show-Panel 'pnlTrabajo'
        $u = $script:Ui
        $u.chkDesarme.IsChecked = $true; $u.chkLimpieza.IsChecked = $true; $u.chkFotosAntes.IsChecked = $true; $u.chkFotosDespues.IsChecked = $true
        $u.txtPasta.Text = 'Arctic MX-4'; $u.txtPutty.Text = 'Pads 1 mm'; $u.txtMateriales.Text = 'alcohol isopropílico; aire comprimido'
        & $clic 'btnGuardarChecklist'
    }
    & $paso 0.8 { & $escAnotar "checklist: '$($script:Ui.txtEstado.Text)'"; & $escFoto 'e1_08_trabajo_checklist' }
    & $paso 0.3 { & $clic 'btnTrabajoTerminado' }
    & $paso 0.8 { & $escAnotar "trabajo terminado -> panel $($script:G.Panel) momento=$($script:G.Momento)"; & $clic 'btnDiagnosticar' }
    & $paso 1 { & $escAnotar "DESPUÉS con admin: '$($script:Ui.txtMedicionEstado.Text)'"; & $escFoto 'e1_09_despues' } { -not $script:G.Tarea }
    & $paso 0.3 { Invoke-TareaKit -Accion 'importar_sensores' -Parametros @{ momento = 'despues'; ruta = $escCsvDespues } -Texto 'Leyendo el CSV de sensores...' -AlResultado { param($r) & $escAnotar "CSV después (reemplazo): $($r | ConvertTo-Json -Compress)"; Show-Medicion; Show-Estado } }
    & $paso 0.5 { & $escAnotar "condiciones propuestas para el después: plan='$($script:Ui.txtCondPlan.Text)' duración='$($script:Ui.txtCondDuracion.Text)'"; $script:Ui.txtCondDuracion.Text = '112'; & $clic 'btnGuardarCondiciones' } { -not $script:G.Tarea }
    & $paso 0.8 { & $escAnotar "sensores después: '$($script:Ui.txtSensores.Text)' | '$($script:Ui.txtCondEstado.Text)'"; & $escFoto 'e1_10_despues_csv' }
    & $paso 0.3 { Show-Panel 'pnlInforme'; & $clic 'btnGenerar' }
    & $paso 1 { & $escAnotar "informes: '$($script:Ui.txtEstado.Text)' | '$($script:Ui.txtInforme.Text)'"; & $escFoto 'e1_11_informe' } { -not $script:G.Tarea }
    & $paso 0.3 { Show-VistaCliente }
    & $paso 1 { Save-Captura $script:G.VentanaCliente.Content 'e1_12_mostrar_cliente'; $script:G.VentanaCliente.Close() }
    & $paso 0.3 { Show-Panel 'pnlFicha'; & $clic 'btnEntregado' }
    & $paso 0.8 { & $escAnotar "entregado: '$($script:Ui.txtFichaEstado.Text)'"; Show-Panel 'pnlInicio' }
    & $paso 0.8 { & $escAnotar "final: '$($script:Ui.txtAtencion.Text)'"; & $escFoto 'e1_13_inicio_entregado' }
}
