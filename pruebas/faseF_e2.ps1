# Fase F — escenario 2 (prueba 2): el mismo equipo vuelve con LENTO (con admin). Tiene que reconocerlo
# como cliente conocido, sugerir acciones, aplicarlas (con punto de restauración) y deshacerlas.
# Se aplican: la entrada de prueba KitPruebaInicio, una entrada de inicio real de riesgo bajo y, si las
# sugiere, hibernación y ajustes de energía/procesador. faseF_estado.ps1 compara antes y después.
# Se carga dentro de kit.ps1 (-Captura -Escenario).
$escAnotar = { param([string]$t) $script:G.Registro.Add("$(Get-Date -Format HH:mm:ss) $t") }
$escFoto = { param([string]$n) Save-Captura $script:Win.Content $n }

& $paso 1 { & $escAnotar "inicio: $($script:Ui.txtAdmin.Text) | '$($script:Ui.txtCliente.Text)' | '$($script:Ui.txtAtencion.Text)'"; & $escFoto 'e2_01_cliente_conocido' }
& $paso 0.3 { $script:Ui.tgLento.IsChecked = $true }
& $paso 0.5 {
    & $escAnotar "atención nueva: $($script:G.At)"
    Show-Panel 'pnlFicha'
    & $escAnotar "ficha precargada: nombre='$($script:Ui.txtNombre.Text)' contacto='$($script:Ui.txtContacto.Text)'"
    $script:Ui.txtSintoma.Text = 'Lento al encender y al abrir programas'; $script:Ui.txtPaquete.Text = 'Optimización'; $script:Ui.txtPrecio.Text = '25000'
    & $clic 'btnGuardarFicha'
}
& $paso 0.8 { & $escAnotar "ficha: '$($script:Ui.txtFichaEstado.Text)'"; & $escFoto 'e2_02_ficha' }
& $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; $script:Ui.chkEspacio.IsChecked = $false; & $clic 'btnDiagnosticar' }
& $paso 1 { & $escAnotar "ANTES: '$($script:Ui.txtMedicionEstado.Text)'"; & $escFoto 'e2_03_antes' } { -not $script:G.Tarea }
& $paso 0.3 { Show-Panel 'pnlTrabajo'; & $clic 'btnBuscarAcciones' }
& $paso 0.8 {
    foreach ($row in $script:G.TablaAcciones.Rows) { & $escAnotar "sugerida: $($row['Id']) | $($row['Titulo']) | $($row['Marcas'])" }
    & $escFoto 'e2_04_acciones_sugeridas'
}
& $paso 0.3 {
    $real = $null; $gpu = $null
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($row in $script:G.TablaAcciones.Rows) {
        $id = "$($row['Id'])"
        $marcar = $id -eq 'inicio|HKCU|Run|KitPruebaInicio' -or $id -like 'hibernacion|*' -or $id -like 'cpu|*' -or $id -like 'plan|*'
        if (-not $marcar -and -not $real -and $id -like 'inicio|HKCU|*' -and "$($row['Marcas'])" -notmatch 'revisar') { $marcar = $true; $real = $id }
        if (-not $marcar -and -not $gpu -and $id -like 'gpu|*') { $marcar = $true; $gpu = $id }
        if ($marcar) { $row['Aplicar'] = $true; $ids.Add($id) }
    }
    $script:G.IdsPrueba = $ids.ToArray()
    & $escAnotar "elegidas: $($ids -join ' ; ')"
    & $clic 'btnAplicarAcciones'
}
& $paso 1 {
    $reg = Read-RegistroLento -Expediente $script:G.Exp -Atencion $script:G.At
    $hechas = @($reg['acciones'] | Where-Object { $_ })
    & $escAnotar "aplicadas: $($hechas.Count) | punto de restauración: $(if ($reg['punto_restauracion']) { "$($reg['punto_restauracion']['descripcion']) $($reg['punto_restauracion']['fecha']) creado_ahora=$($reg['punto_restauracion']['creado_ahora'])" } else { 'ninguno' }) | '$($script:Ui.txtLento.Text)'"
    if ($hechas.Count -eq 0) {
        # Si Windows no creó el punto (protección del sistema apagada), se repite sin punto y se informa.
        & $escAnotar 'no se aplicó nada (¿falló el punto de restauración?): se repite sin punto'
        Invoke-TareaKit -Accion 'aplicar_lento' -Parametros @{ ids = $script:G.IdsPrueba; sin_punto = $true } -Texto 'Aplicando acciones...' -AlResultado { param($r) & $escAnotar "reintento sin punto: $($r | ConvertTo-Json -Compress)"; Show-Trabajo }
    }
} { -not $script:G.Tarea }
& $paso 1 {
    $reg = Read-RegistroLento -Expediente $script:G.Exp -Atencion $script:G.At
    foreach ($a in @($reg['acciones'] | Where-Object { $_ })) { & $escAnotar "registro: $($a['id']) aplicada=$($a['aplicada']) deshacer=$($a['deshacer'] | ConvertTo-Json -Compress)" }
    [IO.File]::WriteAllText((Join-Path $Captura 'aplicadas.flag'), (Get-Date -Format s))   # el orquestador saca la foto del estado
    & $escFoto 'e2_05_aplicadas'
} { -not $script:G.Tarea }
# Pausa para que el orquestador saque la foto del estado con las acciones aplicadas.
& $paso 20 { & $escAnotar 'deshaciendo'; & $clic 'btnDeshacerLento' }
& $paso 1 {
    $reg = Read-RegistroLento -Expediente $script:G.Exp -Atencion $script:G.At
    & $escAnotar "deshechas: $(@($reg['acciones'] | Where-Object { $_ -and $_['deshecha'] }).Count) de $(@($reg['acciones'] | Where-Object { $_ }).Count) | '$($script:Ui.txtLento.Text)'"
    & $escFoto 'e2_06_deshechas'
} { -not $script:G.Tarea }
& $paso 0.3 { & $clic 'btnTrabajoTerminado' }
& $paso 0.8 { & $clic 'btnDiagnosticar' }
& $paso 1 { & $escAnotar "DESPUÉS: '$($script:Ui.txtMedicionEstado.Text)'"; & $escFoto 'e2_07_despues' } { -not $script:G.Tarea }
& $paso 0.3 { Show-Panel 'pnlInforme'; & $clic 'btnGenerar' }
& $paso 1 { & $escAnotar "informes: '$($script:Ui.txtEstado.Text)'"; & $escFoto 'e2_08_informe' } { -not $script:G.Tarea }
& $paso 0.3 { Show-Panel 'pnlFicha'; & $clic 'btnEntregado' }
& $paso 0.8 { Show-Panel 'pnlInicio' }
& $paso 0.5 { & $escAnotar "final: '$($script:Ui.txtAtencion.Text)'"; & $escFoto 'e2_09_entregado' }
