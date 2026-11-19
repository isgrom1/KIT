# Drivers — escenario de la ventana: ③ Trabajo muestra los links oficiales y un clic copia y "abre" (en modo
# captura solo lo anota). Se carga dentro de kit.ps1 (-Captura -Escenario) con -Clientes en una carpeta de prueba.
# Usa $paso, $clic y Save-Captura.
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }
$escBoton = {
    # Botón del link n.º $i dentro de la lista de drivers (está en una plantilla, no tiene nombre).
    param([int]$i)
    $cont = $script:Ui.icDrivers.ItemContainerGenerator.ContainerFromIndex($i)
    $pila = New-Object System.Collections.Generic.Stack[object]
    if ($cont) { $pila.Push($cont) }
    while ($pila.Count) {
        $x = $pila.Pop()
        if ($x -is [Windows.Controls.Button]) { return $x }
        for ($k = 0; $k -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($x); $k++) { $pila.Push([Windows.Media.VisualTreeHelper]::GetChild($x, $k)) }
    }
    $null
}

& $paso 1 { $script:Ui.tgRevision.IsChecked = $true }
& $paso 0.6 {
    Show-Panel 'pnlFicha'
    $u = $script:Ui
    $u.txtNombre.Text = 'Cliente Prueba Drivers'; $u.txtContacto.Text = '+56 9 5555 0010'; $u.txtComuna.Text = 'Ñuñoa'
    $u.txtSintoma.Text = 'Revisión'; $u.txtPaquete.Text = 'Revisión general'; $u.txtPrecio.Text = '15000'
    foreach ($k in @($script:G.Chk.Keys)) { $script:G.Chk[$k].SelectedIndex = 1 }
    & $clic 'btnGuardarFicha'
}
& $paso 0.6 { Show-Panel 'pnlTrabajo' }
& $paso 0.8 {
    & $escAnotar "sin diagnóstico | drivers: '$($script:Ui.txtDrivers.Text)' | links: $(@($script:Ui.icDrivers.ItemsSource).Count)"
    $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar'
}
& $paso 1 { Show-Panel 'pnlTrabajo' } { -not $script:G.Tarea }
& $paso 1 {
    $e = Read-Expediente $script:G.Exp.Ruta
    & $escAnotar "ficha: placa='$($e.Ficha['equipo']['placa'])' | drivers: '$($script:Ui.txtDrivers.Text)'"
    foreach ($it in @($script:Ui.icDrivers.ItemsSource)) { & $escAnotar "  link: $($it.Titulo) | habilitado: $($it.Habilitado)" }
    $script:Ui.grpDrivers.BringIntoView()
}
& $paso 0.8 { & $escFoto 'd_01_trabajo_drivers' }
& $paso 0.5 {
    $b = & $escBoton 1
    if ($b) { $b.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
    & $escAnotar "clic en el link 2 (botón encontrado: $([bool]$b)) | estado: '$($script:Ui.txtEstado.Text)'"
}
& $paso 0.5 { & $escFoto 'd_02_clic' }
