# Fase F — escenario 4 (pruebas 4 y 5): CALOR + LENTO en una sola atención, sin admin. LENTO aplica solo la
# entrada de prueba KitPruebaInicio (sin admin el kit pide confirmar que sigue sin punto de restauración).
# Un solo informe tiene que traer ambas secciones. Al final se deshace LENTO.
# Se carga dentro de kit.ps1 (-Captura -Escenario).
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }
$escDocs = [Environment]::GetFolderPath('MyDocuments')
$escCsvAntes = Join-Path $escDocs '08 Datos sueltos (csv-json)\reg.CSV'
$escCsvDespues = Join-Path $escDocs 'asdasd.CSV'

& $paso 1 { & $escAnotar "inicio: $($script:Ui.txtAdmin.Text) | '$($script:Ui.txtCliente.Text)'"; & $escFoto 'e4_01_inicio' }
& $paso 0.3 { $script:Ui.tgCalor.IsChecked = $true }
& $paso 0.3 { $script:Ui.tgLento.IsChecked = $true }
& $paso 0.5 {
    & $escAnotar "atención nueva: $($script:G.At) | motivos: $(@((Get-Entrada)['motivos']) -join ', ')"
    Show-Panel 'pnlFicha'
    $script:Ui.txtSintoma.Text = 'Se calienta y además está lento'; $script:Ui.txtPaquete.Text = 'Mantención completa'; $script:Ui.txtPrecio.Text = '50000'
    & $clic 'btnGuardarFicha'
}
& $paso 0.8 { & $escAnotar "ficha: '$($script:Ui.txtFichaEstado.Text)'"; & $escFoto 'e4_02_ficha' }
& $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar' }
& $paso 1 { & $escAnotar "ANTES sin admin: '$($script:Ui.txtMedicionEstado.Text)'" } { -not $script:G.Tarea }
& $paso 0.3 { Invoke-TareaKit -Accion 'importar_sensores' -Parametros @{ momento = 'antes'; ruta = $escCsvAntes } -Texto 'Leyendo el CSV...' -AlResultado { param($r) Show-Medicion; Show-Estado } }
& $paso 0.5 {
    $u = $script:Ui
    $u.cmbEnchufado.SelectedIndex = 1; $u.txtCondPlan.Text = 'Equilibrado'; $u.txtCondVentiladores.Text = 'Automático'; $u.txtCondSuperficie.Text = 'Mesa dura'
    $u.txtCondAmbiente.Text = '22'; $u.txtCondCarga.Text = 'Juego (prueba)'; $u.txtCondDuracion.Text = '108'
    & $clic 'btnGuardarCondiciones'
} { -not $script:G.Tarea }
& $paso 0.8 { & $escAnotar "sensores antes: '$($script:Ui.txtSensores.Text)'"; & $escFoto 'e4_03_antes_calor' }
& $paso 0.3 {
    Show-Panel 'pnlTrabajo'
    & $escAnotar "grupos visibles: CALOR=$($script:Ui.grpTrabajoCalor.Visibility) LENTO=$($script:Ui.grpTrabajoLento.Visibility) ARCHIVOS=$($script:Ui.grpTrabajoArchivos.Visibility)"
    $script:Ui.chkDesarme.IsChecked = $true; $script:Ui.chkLimpieza.IsChecked = $true; $script:Ui.txtPasta.Text = 'Arctic MX-4'
    & $clic 'btnGuardarChecklist'
    & $clic 'btnBuscarAcciones'
}
& $paso 0.8 {
    $script:G.GpuPrueba = $null
    foreach ($row in $script:G.TablaAcciones.Rows) {
        $id = "$($row['Id'])"
        if ($id -eq 'inicio|HKCU|Run|KitPruebaInicio') { $row['Aplicar'] = $true }
        elseif (-not $script:G.GpuPrueba -and $id -like 'gpu|*') { $row['Aplicar'] = $true; $script:G.GpuPrueba = $id.Substring(4) }
    }
    & $escAnotar "sin admin: se aplican KitPruebaInicio y la GPU de $($script:G.GpuPrueba)"
    & $clic 'btnAplicarAcciones'
}
& $paso 1 {
    $reg = Read-RegistroLento -Expediente $script:G.Exp -Atencion $script:G.At
    & $escAnotar "aplicadas sin admin: $(@($reg['acciones'] | Where-Object { $_ }).Count) | punto: $($reg['punto_restauracion'] | ConvertTo-Json -Compress) | '$($script:Ui.txtLento.Text)'"
    if ($script:G.GpuPrueba) {
        $real = ConvertFrom-RutaProtegida $script:G.GpuPrueba
        & $escAnotar "GPU aplicada: valor real ($real) = '$(Get-ValorRegistro -Colmena HKCU -Ruta 'Software\Microsoft\DirectX\UserGpuPreferences' -Nombre $real)' | valor con nombre enmascarado = '$(Get-ValorRegistro -Colmena HKCU -Ruta 'Software\Microsoft\DirectX\UserGpuPreferences' -Nombre $script:G.GpuPrueba)'"
    }
    & $escFoto 'e4_04_trabajo_calor_lento'
} { -not $script:G.Tarea }
& $paso 0.3 { & $clic 'btnTrabajoTerminado' }
& $paso 0.8 { & $clic 'btnDiagnosticar' }
& $paso 1 { & $escAnotar "DESPUÉS sin admin: '$($script:Ui.txtMedicionEstado.Text)'" } { -not $script:G.Tarea }
& $paso 0.3 { Invoke-TareaKit -Accion 'importar_sensores' -Parametros @{ momento = 'despues'; ruta = $escCsvDespues } -Texto 'Leyendo el CSV...' -AlResultado { param($r) Show-Medicion; Show-Estado } }
& $paso 0.5 { $script:Ui.txtCondDuracion.Text = '112'; & $clic 'btnGuardarCondiciones' } { -not $script:G.Tarea }
& $paso 0.8 { & $escAnotar "sensores después: '$($script:Ui.txtSensores.Text)'"; & $escFoto 'e4_05_despues' }
& $paso 0.3 { Show-Panel 'pnlInforme'; & $clic 'btnGenerar' }
& $paso 1 { & $escAnotar "informes: '$($script:Ui.txtEstado.Text)'"; & $escFoto 'e4_06_informe' } { -not $script:G.Tarea }
& $paso 0.3 { Show-VistaCliente }
& $paso 1 { Save-Captura $script:G.VentanaCliente.Content 'e4_07_mostrar_cliente'; $script:G.VentanaCliente.Close() }
& $paso 0.3 { Show-Panel 'pnlTrabajo'; & $clic 'btnDeshacerLento' }
& $paso 1 {
    & $escAnotar "LENTO deshecho: '$($script:Ui.txtLento.Text)'"
    if ($script:G.GpuPrueba) { $real = ConvertFrom-RutaProtegida $script:G.GpuPrueba; & $escAnotar "GPU deshecha: valor real = '$(Get-ValorRegistro -Colmena HKCU -Ruta 'Software\Microsoft\DirectX\UserGpuPreferences' -Nombre $real)'" }
} { -not $script:G.Tarea }
& $paso 0.3 { Show-Panel 'pnlFicha'; & $clic 'btnEntregado' }
& $paso 0.8 { Show-Panel 'pnlInicio' }
& $paso 0.5 { & $escAnotar "final: '$($script:Ui.txtAtencion.Text)'"; & $escFoto 'e4_08_entregado' }
