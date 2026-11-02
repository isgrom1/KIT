# Fase F — escenario 3 (prueba 3): ARCHIVOS sin admin, SOLO sobre la carpeta de prueba K:\perfil_prueba
# (nunca carpetas reales): analizar -> mover a _PARA_BORRAR -> deshacer. faseF_hashes.ps1 compara después
# que todo volvió igual. Se carga dentro de kit.ps1 (-Captura -Escenario).
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }
$escPerfil = 'K:\perfil_prueba'

& $paso 1 { & $escAnotar "inicio: $($script:Ui.txtAdmin.Text) | '$($script:Ui.txtCliente.Text)'"; & $escFoto 'e3_01_inicio' }
& $paso 0.3 { $script:Ui.tgArchivos.IsChecked = $true }
& $paso 0.5 {
    & $escAnotar "atención nueva: $($script:G.At)"
    Show-Panel 'pnlFicha'
    & $escAnotar "grupo Archivos visible en la ficha: $($script:Ui.grpFichaArchivos.Visibility)"
    $script:Ui.txtSintoma.Text = 'Se quedó sin espacio y tiene archivos repetidos'; $script:Ui.txtPaquete.Text = 'Orden y espacio'; $script:Ui.txtPrecio.Text = '20000'
    $script:Ui.cmbConsentimiento.SelectedIndex = 2
    $script:Ui.txtProtegidas.Text = "$escPerfil\Documents\Tesis"
    & $clic 'btnGuardarFicha'
}
& $paso 0.8 { & $escAnotar "ficha: '$($script:Ui.txtFichaEstado.Text)'"; & $escFoto 'e3_02_ficha_archivos' }
& $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar' }
& $paso 1 { & $escAnotar "ANTES: '$($script:Ui.txtMedicionEstado.Text)'"; & $escFoto 'e3_03_antes' } { -not $script:G.Tarea }
& $paso 0.3 { Show-Panel 'pnlTrabajo'; $script:G.PerfilPrueba = $escPerfil; & $clic 'btnAnalizar' }
& $paso 1 {
    & $escAnotar "análisis: '$($script:Ui.txtArchivos.Text)'"
    foreach ($row in $script:G.TablaArchivos.Rows) { & $escAnotar ("  [{0}] {1} | {2} | {3}" -f $(if ($row['Mover']) { 'mover' } else { '  -  ' }), $row['Categoria'], $row['Ruta'], $row['Motivo']) }
    & $escFoto 'e3_04_analisis'
} { -not $script:G.Tarea }
& $paso 0.3 { & $clic 'btnMover' }
& $paso 1 {
    $pb = @(Get-ChildItem 'K:\_PARA_BORRAR' -Recurse -File -ErrorAction SilentlyContinue)
    & $escAnotar "movidos: en K:\_PARA_BORRAR hay $($pb.Count) archivos: $(($pb | ForEach-Object { $_.Name }) -join ', ')"
    & $escAnotar "Tesis (protegida) intacta: $([IO.File]::Exists("$escPerfil\Documents\Tesis\capitulo1.docx")) | Escritorio intacto: $([IO.File]::Exists("$escPerfil\Desktop\informe.pdf"))"
    & $escFoto 'e3_05_movidos'
} { -not $script:G.Tarea }
& $paso 0.3 { & $clic 'btnDeshacerArchivos' }
& $paso 1 {
    $pb = @(Get-ChildItem 'K:\_PARA_BORRAR' -Recurse -File -ErrorAction SilentlyContinue)
    & $escAnotar "después de deshacer: en K:\_PARA_BORRAR quedan $($pb.Count) archivos: $(($pb | ForEach-Object { $_.Name }) -join ', ')"
    & $escFoto 'e3_06_deshecho'
} { -not $script:G.Tarea }
& $paso 0.3 { Show-Panel 'pnlFicha'; & $clic 'btnEntregado' }
& $paso 0.8 { Show-Panel 'pnlInicio' }
& $paso 0.5 { & $escAnotar "final: '$($script:Ui.txtAtencion.Text)'"; & $escFoto 'e3_07_entregado' }
