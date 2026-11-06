#Requires -Version 5.1
<#
.SYNOPSIS
    Interfaz gráfica del kit (WPF). INICIAR.cmd la abre; si no se puede, cae al menú de consola.
.DESCRIPTION
    Flujo guiado: Inicio (motivos) -> Ficha -> Antes -> Trabajo -> Después -> Informe. Los trabajos
    largos (diagnóstico, análisis de archivos, acciones, informes) corren en un proceso aparte que la
    ventana lee con un temporizador: la ventana nunca queda en "No responde" y todo se puede cancelar.
    Sale con código 10 si PowerShell está restringido o WPF no carga (INICIAR muestra la consola).
.PARAMETER Atencion
    Atención a abrir (al relanzar como admin se conserva la misma).
.PARAMETER Clientes
    Carpeta de expedientes alternativa (por defecto KIT\clientes).
.PARAMETER RutaExpediente
    Expediente a abrir (del USB o del maestro). Si no es el de este equipo, se abre en modo consulta.
.PARAMETER RutaMaestro
    Carpeta maestra alternativa (por defecto config.json -> sincronizacion.ruta_maestro).
.PARAMETER Captura
    Solo pruebas: recorre los paneles, guarda una imagen PNG de cada uno en esta carpeta y se cierra.
    Con -RutaMaestro, además sincroniza, abre un expediente del maestro y regenera sus informes.
.PARAMETER CapturaDiag
    Solo pruebas, con -Captura: además corre un diagnóstico ANTES sin recorrido de carpetas.
.PARAMETER Escenario
    Solo pruebas, con -Captura: archivo con los pasos a recorrer (en vez del recorrido por defecto). Al
    relanzar como admin, la ventana nueva sigue el mismo escenario.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Los parámetros de los manejadores de eventos los exige WPF')]
param([string]$Atencion, [string]$Clientes, [string]$RutaExpediente, [string]$RutaMaestro, [string]$Captura, [switch]$CapturaDiag, [string]$Escenario)

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 10 }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { exit 10 }
try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase } catch { exit 10 }

$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path -Parent $PSScriptRoot
try {
    foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe', 'Herramientas', 'Sincronizacion') { . (Join-Path $script:Raiz "lib\$lib.ps1") }
    foreach ($m in 'calor', 'lento', 'archivos', 'revision') { . (Join-Path $script:Raiz "motivos\$m.ps1") }
    Initialize-Contexto -RaizScripts $script:Raiz
    if ($Clientes) { $script:Ctx.CarpetaClientes = $Clientes }
    Initialize-Privacidad
    $script:Ctx.Admin = Get-EstadoAdmin
    $script:Identidad = Get-IdentidadEquipo
    [xml]$xaml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'principal.xaml'))
    $script:Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
} catch {
    [Console]::Error.WriteLine("No se pudo abrir la interfaz: $($_.Exception.Message)")
    exit 10
}
$script:Ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@Name]')) { $script:Ui[$n.Name] = $script:Win.FindName($n.Name) }
$ui = $script:Ui
$script:PS = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
$script:G = @{ Exp = $null; At = $Atencion; Momento = 'antes'; Panel = 'pnlInicio'; Tarea = $null; Cargando = $false; Chk = @{}; Cancelado = $false
    TablaAcciones = $null; TablaArchivos = $null; TablaExp = $null; DiagN = 0; Registro = New-Object System.Collections.Generic.List[string]
    Ajeno = $false; Origen = 'USB' }   # Ajeno: expediente de otro equipo (o del maestro) abierto en modo consulta
$script:Colores = @{ CRITICO = '#CF222E'; AVISO = '#BC4C00'; INFO = '#6E7781'; rojo = '#CF222E'; amarillo = '#D4A72C'; verde = '#2DA44E'; gris = '#8C959F' }
$script:Pasos = @('Ficha', 'Antes', 'Trabajo', 'Después', 'Informe')
$script:NombresSecciones = 'Equipo', 'Hardware', 'Windows', 'Seguridad', 'Energía', 'Software', 'Arranque', 'Políticas navegador', 'GPU por app', 'Uso actual', 'Espacio', 'Dispositivos', 'Estabilidad'

# ------------------------------------------------------------------------------ utilidades

function Get-Pincel { param([string]$Color) (New-Object Windows.Media.BrushConverter).ConvertFromString($Color) }

function Show-Aviso {
    # MessageBox en lenguaje simple. En modo captura no muestra nada (respondería "Sí" y lo anota).
    param([string]$Texto, [string]$Titulo = 'KIT SERVICIO', [switch]$Pregunta, [switch]$EsError)
    if ($Captura) { $script:G.Registro.Add("[aviso] $Titulo | $Texto"); return $true }
    $botones = if ($Pregunta) { 'YesNo' } else { 'OK' }
    $icono = if ($EsError) { 'Warning' } elseif ($Pregunta) { 'Question' } else { 'Information' }
    [Windows.MessageBox]::Show($script:Win, $Texto, $Titulo, $botones, $icono) -eq 'Yes'
}

function Get-MensajeSimple {
    # Quita la jerga de los errores ("No se guardó la ficha: - cliente.nombre: ...").
    param([string]$Texto)
    $t = $Texto -replace '^No se guardó la ficha:\s*', 'No se guardó: ' -replace '(?m)^- ', '• '
    foreach ($par in @{ 'cliente.nombre' = 'Nombre'; 'cliente.contacto' = 'Contacto'; 'cliente.comuna' = 'Comuna'; 'precio' = 'Precio'; 'motivos' = 'Motivos'; 'carpetas_protegidas' = 'Carpetas protegidas' }.GetEnumerator()) { $t = $t.Replace("$($par.Key):", "$($par.Value):") }
    $t
}

function Write-Estado { param([string]$Texto) $script:Ui.txtEstado.Text = $Texto }

function Get-Entrada {
    if ($script:G.Exp -and $script:G.At) { Get-EntradaAtencion -Expediente $script:G.Exp -Carpeta $script:G.At } else { $null }
}

function Read-ExpedienteActual {
    # Vuelve a leer el expediente y elige la atención (la indicada, la abierta o ninguna todavía). En modo
    # consulta se relee el expediente abierto desde la lista. Una atención cuya carpeta ya no está (se
    # liberó al maestro) deja de estar elegida.
    $script:G.Exp = if ($script:G.Ajeno) { Read-Expediente $script:G.Exp.Ruta } else { Get-Expediente -Identidad $script:Identidad }
    if (-not $script:G.Exp) { $script:G.At = $null; return }
    $at = $script:G.At
    if (-not ($at -and (Get-EntradaAtencion -Expediente $script:G.Exp -Carpeta $at) -and [IO.Directory]::Exists((Join-Path $script:G.Exp.Ruta $at)))) {
        $script:G.At = if ($script:G.Ajeno) { $null } else { Get-AtencionAbierta -Expediente $script:G.Exp }
    }
}

function Open-Expediente {
    # Abre un expediente desde la lista (o -RutaExpediente). El de este equipo en el USB queda en el flujo
    # normal; cualquier otro (u otro equipo, o el maestro) en modo consulta.
    param([Parameter(Mandatory)][string]$Ruta, [string]$Carpeta)
    $propio = Get-Expediente -Identidad $script:Identidad
    $script:G.Ajeno = -not ($propio -and [IO.Path]::GetFullPath($propio.Ruta) -eq [IO.Path]::GetFullPath($Ruta))
    $maestro = Get-MaestroGui
    $script:G.Origen = if ($maestro -and [IO.Path]::GetFullPath($Ruta).StartsWith([IO.Path]::GetFullPath($maestro).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { 'maestro' } else { 'USB' }
    $script:G.Exp = Read-Expediente $Ruta
    $script:G.At = if ($Carpeta) { $Carpeta } else { $null }
    Show-Estado
}

function Get-MaestroGui { if ($RutaMaestro) { $RutaMaestro } else { Get-RutaMaestro } }

function Initialize-AtencionGui {
    # Crea expediente y atención si todavía no existen (al elegir motivos o guardar la ficha).
    # En modo consulta no se crea nada: se trabaja sobre la atención elegida en la lista.
    if ($script:G.Ajeno -and -not $script:G.At) { throw 'En modo consulta hay que elegir una atención en Expedientes.' }
    if (-not $script:G.Exp) { $script:G.Exp = New-Expediente -Identidad $script:Identidad }
    if (-not $script:G.At) { $script:G.At = New-Atencion -Expediente $script:G.Exp }
    $script:G.Exp = Read-Expediente $script:G.Exp.Ruta
}

function Get-EstadoPasos {
    $a = Get-Entrada
    $motivos = @(if ($a) { $a['motivos'] | Where-Object { $_ } })
    $fichaOk = $false
    if ($a) {
        $faltan = @(Test-FichaCompleta -Expediente $script:G.Exp -Atencion $script:G.At | Where-Object { $_.Campo -notin 'paquete', 'precio', 'tecnico.nombre', 'tecnico.contacto' })
        $fichaOk = $faltan.Count -eq 0
    }
    $antes = [bool]($a -and (Test-Medicion -Expediente $script:G.Exp -Atencion $script:G.At -Momento 'antes'))
    $despues = [bool]($a -and (Test-Medicion -Expediente $script:G.Exp -Atencion $script:G.At -Momento 'despues'))
    $informe = [bool]($a -and [IO.File]::Exists((Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'informe_cliente.html')))
    [pscustomobject]@{ Motivos = $motivos; Hecho = @($fichaOk, $antes, [bool]($a -and $a['trabajo_terminado']), $despues, $informe) }
}

# ------------------------------------------------------------------------------ estado general

function Show-Estado {
    $ui = $script:Ui
    Read-ExpedienteActual
    $id = $script:Identidad
    $ui.txtEquipo.Text = if ($script:G.Ajeno) {
        $eq = $script:G.Exp.Ficha['equipo']
        "CONSULTA ($($script:G.Origen))  ·  $($eq['fabricante']) $($eq['modelo'])  ·  S/N $(if ($eq['serie']) { $eq['serie'] } else { '(genérica)' })"
    } else { "$($id.Fabricante) $($id.Modelo)  ·  S/N $(if ($id.Serie) { $id.Serie } else { '(genérica)' })" }
    # Barra ámbar en consulta: que se note que no es el equipo que está enchufado.
    $ui.bdBarra.Background = Get-Pincel $(if ($script:G.Ajeno) { '#7A4A00' } else { '#0B3D75' })
    $ui.btnVolverEquipo.Visibility = if ($script:G.Ajeno) { 'Visible' } else { 'Collapsed' }
    $admin = $script:Ctx.Admin.Elevado
    $ui.txtAdmin.Text = if ($admin) { 'Admin: sí' } else { 'Admin: no' }
    $ui.bdAdmin.Background = Get-Pincel $(if ($admin) { '#2DA44E' } else { '#D4A72C' })
    $ui.btnRelanzar.Visibility = if ($admin) { 'Collapsed' } else { 'Visible' }
    $a = Get-Entrada
    $cliente = if ($script:G.Exp -and $script:G.Exp.Ficha['cliente']['nombre']) { "Cliente: $($script:G.Exp.Ficha['cliente']['nombre'])" } else { 'Cliente: (sin ficha todavía)' }
    $conocido = ''
    if ($script:G.Exp) {
        $previas = @(Get-ListaAtenciones -Expediente $script:G.Exp | Where-Object { $_['carpeta'] -ne $script:G.At -and $_['mediciones']['antes'] })
        if ($previas.Count -gt 0) {
            $u = $previas[-1]
            $clave = ''
            $s = Read-SensoresMedicion -Expediente $script:G.Exp -Atencion $u['carpeta'] -Momento 'despues'
            if ($s -and $s.metricas.cpu_temp_paquete) { $clave = ", CPU máx. $(Format-Numero $s.metricas.cpu_temp_paquete.max 0) °C" }
            $conocido = "   ·   Cliente conocido — última atención $($u['fecha']): $((@($u['motivos']) -join ', ').ToLower())$clave"
        }
    }
    $ui.txtCliente.Text = "$cliente$(if ($script:G.At) { "   ·   atención $($script:G.At)" })$conocido"

    $st = Get-EstadoPasos
    $script:G.Cargando = $true
    foreach ($par in @{ tgCalor = 'CALOR'; tgLento = 'LENTO'; tgArchivos = 'ARCHIVOS'; tgRevision = 'REVISION' }.GetEnumerator()) { $ui[$par.Key].IsChecked = $st.Motivos -contains $par.Value }
    $script:G.Cargando = $false
    $nav = @($ui.navFicha, $ui.navAntes, $ui.navTrabajo, $ui.navDespues, $ui.navInforme)
    # Cada paso se habilita al completar el anterior (Después también si ya se midió).
    $hab = @(($st.Motivos.Count -gt 0), ($st.Hecho[0]), ($st.Hecho[1]), ($st.Hecho[2] -or $st.Hecho[3]), ($st.Hecho[3]))
    # En consulta no se mide ni se trabaja sobre el equipo; ficha e informe sí (para regenerarlo).
    if ($script:G.Ajeno) { $hab = @([bool]$a, $false, $false, $false, [bool]$a) }
    $ui.wpPasos.Children.Clear()
    for ($i = 0; $i -lt 5; $i++) {
        $num = [char](0x2460 + $i)
        $nav[$i].Content = if ($st.Hecho[$i]) { "✓ $($script:Pasos[$i])" } else { "$num $($script:Pasos[$i])" }
        $nav[$i].IsEnabled = $hab[$i]
        $nav[$i].Foreground = Get-Pincel $(if ($st.Hecho[$i]) { '#1A7F37' } else { '#1F2328' })
        $b = New-Object Windows.Controls.Border
        $b.Padding = '12,8'; $b.Margin = '0,0,10,10'; $b.CornerRadius = 6; $b.BorderThickness = 1
        $b.BorderBrush = Get-Pincel $(if ($st.Hecho[$i]) { '#2DA44E' } else { '#D0D7DE' })
        $b.Background = Get-Pincel $(if ($st.Hecho[$i]) { '#DAFBE1' } elseif ($hab[$i]) { '#FFFFFF' } else { '#F6F8FA' })
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = if ($st.Hecho[$i]) { "✓ $($script:Pasos[$i])" } else { "$num $($script:Pasos[$i])" }
        $t.FontSize = 15
        $t.Foreground = Get-Pincel $(if ($hab[$i] -or $st.Hecho[$i]) { '#1F2328' } else { '#8C959F' })
        $b.Child = $t
        [void]$ui.wpPasos.Children.Add($b)
    }
    $ui.txtAtencion.Text = if ($script:G.At) {
        $m = $a['mediciones']
        "Atención $($script:G.At) · ANTES: $(if ($m['antes']) { $m['antes']['fecha'] } else { 'pendiente' }) · DESPUÉS: $(if ($m['despues']) { $m['despues']['fecha'] } else { 'pendiente' })$(if ($a['entregado']) { " · entregada el $($a['entregado'])" })"
    } elseif ($script:G.Ajeno) { 'Elige una atención en Expedientes.' } else { 'Al elegir los motivos se abre una atención nueva para este equipo.' }
    if ($script:G.Ajeno) { $ui.txtAtencion.Text = "Modo consulta: este expediente no es del equipo enchufado, así que no se mide ni se aplican acciones. Puedes completar la ficha y regenerar los informes.`n$($ui.txtAtencion.Text)" }
    foreach ($t in 'tgCalor', 'tgLento', 'tgArchivos', 'tgRevision') { $ui[$t].IsEnabled = -not ($script:G.Ajeno -and -not $script:G.At) }
    $vis = { param($m) if ($st.Motivos -contains $m) { 'Visible' } else { 'Collapsed' } }
    $ui.grpFichaArchivos.Visibility = & $vis 'ARCHIVOS'
    $ui.spCalorMedicion.Visibility = & $vis 'CALOR'
    $ui.grpTrabajoCalor.Visibility = & $vis 'CALOR'
    $ui.grpTrabajoLento.Visibility = & $vis 'LENTO'
    $ui.grpTrabajoArchivos.Visibility = & $vis 'ARCHIVOS'
    $ui.grpTrabajoRevision.Visibility = 'Visible'
}

function Show-Panel {
    param([string]$Nombre)
    foreach ($p in 'pnlInicio', 'pnlFicha', 'pnlMedicion', 'pnlTrabajo', 'pnlInforme', 'pnlTecnico', 'pnlHerramientas', 'pnlExpedientes') { $script:Ui[$p].Visibility = if ($p -eq $Nombre) { 'Visible' } else { 'Collapsed' } }
    $script:G.Panel = $Nombre
    switch ($Nombre) {
        'pnlFicha' { Show-Ficha }
        'pnlMedicion' { Show-Medicion }
        'pnlTrabajo' { Show-Trabajo }
        'pnlInforme' { Show-Informe }
        'pnlHerramientas' { Show-Herramientas }
        'pnlExpedientes' { Show-Expedientes }
    }
}

# ------------------------------------------------------------------------------ procesos en segundo plano

function Invoke-ProcesoFondo {
    # Corre un script en otro proceso y entrega cada línea de su salida a $AlLinea (en el hilo de la
    # ventana, vía temporizador). Al terminar llama a $AlTerminar con el código de salida.
    param([string]$Script, [string[]]$Argumentos, [Text.Encoding]$Codificacion, [scriptblock]$AlLinea, [scriptblock]$AlTerminar, [string]$Texto)
    if ($script:G.Tarea) { [void](Show-Aviso 'Ya hay un trabajo en curso. Espera a que termine o cancélalo.'); return }
    $psi = New-Object Diagnostics.ProcessStartInfo $script:PS
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $Script, (($Argumentos | ForEach-Object { if ("$_" -match '\s') { '"' + $_ + '"' } else { "$_" } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $Codificacion; $psi.StandardErrorEncoding = $Codificacion
    $p = [Diagnostics.Process]::Start($psi)
    $script:G.Cancelado = $false
    $script:G.Tarea = @{ P = $p; Linea = $p.StandardOutput.ReadLineAsync(); Err = $p.StandardError.ReadToEndAsync(); AlLinea = $AlLinea; AlTerminar = $AlTerminar }
    $script:Ui.prgTarea.IsIndeterminate = $true; $script:Ui.prgTarea.Visibility = 'Visible'; $script:Ui.btnCancelar.Visibility = 'Visible'
    Write-Estado $Texto
    $script:Temporizador.Start()
}

function Invoke-LecturaFondo {
    $t = $script:G.Tarea
    if (-not $t) { $script:Temporizador.Stop(); return }
    $n = 0
    while ($t.Linea.IsCompleted -and $n -lt 300) {
        $l = $t.Linea.Result
        if ($null -eq $l) { break }
        try { & $t.AlLinea $l } catch { $script:G.Registro.Add("error en AlLinea: $($_.Exception.Message)") }
        $t.Linea = $t.P.StandardOutput.ReadLineAsync()
        $n++
    }
    if ($t.Linea.IsCompleted -and $null -eq $t.Linea.Result -and $t.P.WaitForExit(50)) {
        $codigo = if ($script:G.Cancelado) { -1 } else { $t.P.ExitCode }
        $err = if ($t.Err.IsCompleted) { $t.Err.Result } else { '' }
        $script:G.Tarea = $null
        $script:Temporizador.Stop()
        $script:Ui.prgTarea.Visibility = 'Collapsed'; $script:Ui.btnCancelar.Visibility = 'Collapsed'
        try { & $t.AlTerminar $codigo $err } catch { [void](Show-Aviso "Algo salió mal al terminar: $($_.Exception.Message)" -EsError) }
    }
}

function Invoke-CancelarTarea {
    $t = $script:G.Tarea
    if (-not $t) { return }
    $script:G.Cancelado = $true
    # Se cierra el proceso y sus hijos (powercfg, CrystalDiskInfo...). Lo que estaba a medias queda
    # como "_incompleto_" y la medición anterior sigue intacta.
    Start-Process -FilePath "$env:SystemRoot\System32\taskkill.exe" -ArgumentList '/T', '/F', '/PID', $t.P.Id -WindowStyle Hidden -Wait
    Write-Estado 'Cancelando...'
}

function Invoke-TareaKit {
    # Corre gui\tarea.ps1 con una acción; $AlResultado recibe el objeto del resultado.
    param([string]$Accion, [System.Collections.IDictionary]$Parametros, [scriptblock]$AlResultado, [string]$Texto)
    $args2 = @('-Accion', $Accion, '-Expediente', $script:G.Exp.Ruta, '-Atencion', $script:G.At)
    if ($Parametros) {
        $script:G.ArchivoParametros = Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) '_gui_parametros.json'
        [IO.File]::WriteAllText($script:G.ArchivoParametros, ($Parametros | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        $args2 += @('-Parametros', $script:G.ArchivoParametros)
    }
    Invoke-ScriptKit -Script (Join-Path $PSScriptRoot 'tarea.ps1') -Argumentos $args2 -AlResultado $AlResultado -Texto $Texto
}

function Invoke-ScriptKit {
    # Corre un script que responde con "##LOG|", "##RESULTADO|json" o "##ERROR|" (tarea.ps1, sincronizar.ps1).
    param([string]$Script, [string[]]$Argumentos, [scriptblock]$AlResultado, [string]$Texto)
    $script:G.Resultado = $null; $script:G.ErrorTarea = $null; $script:G.AlResultado = $AlResultado
    Invoke-ProcesoFondo -Script $Script -Argumentos $Argumentos -Codificacion (New-Object System.Text.UTF8Encoding($false)) -Texto $Texto -AlLinea {
        param($l)
        if ($l -like '##LOG|*') { Write-Estado $l.Substring(6) }
        elseif ($l -like '##RESULTADO|*') { $script:G.Resultado = $l.Substring(12) | ConvertFrom-Json }
        elseif ($l -like '##ERROR|*') { $script:G.ErrorTarea = $l.Substring(8) }
    } -AlTerminar {
        param($codigo, $err)
        if ($script:G.ArchivoParametros -and [IO.File]::Exists($script:G.ArchivoParametros)) { [IO.File]::Delete($script:G.ArchivoParametros) }
        $script:G.ArchivoParametros = $null
        if ($codigo -eq -1) { Write-Estado 'Cancelado.'; return }
        if ($script:G.ErrorTarea -or $codigo -ne 0) { Write-Estado 'No se pudo terminar.'; [void](Show-Aviso (Get-MensajeSimple $(if ($script:G.ErrorTarea) { $script:G.ErrorTarea } else { "El trabajo terminó con código $codigo. $err" })) -EsError); return }
        Write-Estado 'Listo.'
        # El trabajo corrió en otro proceso y pudo cambiar ficha.json (acciones realizadas, archivos
        # apartados...): se relee antes de seguir, para no guardar después una copia vieja encima.
        if ($script:G.Exp) { try { $script:G.Exp = Read-Expediente $script:G.Exp.Ruta } catch { $script:G.Registro.Add("no se pudo releer el expediente: $($_.Exception.Message)") } }
        & $script:G.AlResultado $script:G.Resultado
    }
}

# ------------------------------------------------------------------------------ ficha

function Show-Ficha {
    $ui = $script:Ui
    $a = Get-Entrada
    $hayAtencion = [bool]$a
    if (-not $a) { $a = Get-PlantillaAtencion -Carpeta '-' -Fecha '-' }   # campos vacíos para el formulario
    $f = if ($script:G.Exp) { $script:G.Exp.Ficha } else { $null }
    $script:G.Cargando = $true
    $c = if ($f) { $f['cliente'] } else { @{} }
    $ui.txtNombre.Text = "$($c['nombre'])"; $ui.txtContacto.Text = "$($c['contacto'])"; $ui.txtComuna.Text = "$($c['comuna'])"
    $ui.txtSintoma.Text = "$($a['sintoma'])"; $ui.txtEstadoFisico.Text = "$($a['estado_fisico'])"; $ui.txtPaquete.Text = "$($a['paquete'])"
    $ui.txtPrecio.Text = if ($a -and $null -ne $a['precio']) { "$($a['precio'])" } else { '' }
    $ui.txtNotas.Text = "$($a['notas'])"
    $ui.cmbRespaldo.SelectedIndex = switch ("$($a['respaldo'])") { 'si' { 1 } 'no' { 2 } 'no_sabe' { 3 } default { 0 } }
    $ui.chkClaveBitlocker.IsChecked = [bool]$a['bitlocker']['clave_confirmada']
    foreach ($k in $script:G.Chk.Keys) { $script:G.Chk[$k].SelectedIndex = switch ("$($a['checklist_funcional'][$k])") { 'ok' { 1 } 'falla' { 2 } 'no_aplica' { 3 } default { 0 } } }
    $ui.cmbConsentimiento.SelectedIndex = switch ("$($a['consentimiento_archivos'])") { 'solo_leer' { 1 } 'mover' { 2 } 'borrar_aprobado' { 3 } default { 0 } }
    $ui.txtProtegidas.Text = (@($a['carpetas_protegidas'] | Where-Object { $_ }) -join "`r`n")
    $script:G.Cargando = $false
    $faltan = if ($hayAtencion) { @(Test-FichaCompleta -Expediente $script:G.Exp -Atencion $script:G.At) } else { @() }
    $ui.txtFichaEstado.Foreground = Get-Pincel '#57606A'
    $ui.txtFichaEstado.Text = if ($faltan.Count) { "Falta para los informes: $(($faltan | ForEach-Object { $_.Texto }) -join ' · ')" } else { 'Ficha completa.' }
}

function Save-FichaGui {
    $ui = $script:Ui
    Initialize-AtencionGui
    $v = [ordered]@{
        'cliente.nombre' = $ui.txtNombre.Text; 'cliente.contacto' = $ui.txtContacto.Text; 'cliente.comuna' = $ui.txtComuna.Text
        sintoma = $ui.txtSintoma.Text; estado_fisico = $ui.txtEstadoFisico.Text; paquete = $ui.txtPaquete.Text; precio = $ui.txtPrecio.Text; notas = $ui.txtNotas.Text
        respaldo = @($null, 'si', 'no', 'no_sabe')[[math]::Max(0, $ui.cmbRespaldo.SelectedIndex)]
        'bitlocker.clave_confirmada' = [bool]$ui.chkClaveBitlocker.IsChecked
    }
    foreach ($k in $script:G.Chk.Keys) { $v["checklist_funcional.$k"] = @($null, 'ok', 'falla', 'no_aplica')[[math]::Max(0, $script:G.Chk[$k].SelectedIndex)] }
    if ($ui.grpFichaArchivos.Visibility -eq 'Visible') {
        $v['consentimiento_archivos'] = @($null, 'solo_leer', 'mover', 'borrar_aprobado')[[math]::Max(0, $ui.cmbConsentimiento.SelectedIndex)]
        $v['carpetas_protegidas'] = (@($ui.txtProtegidas.Text -split "`r?`n" | Where-Object { $_.Trim() }) -join ';')
    }
    try {
        Set-Ficha -Expediente $script:G.Exp -Atencion $script:G.At -Valores $v
        Write-TrabajoLog -Expediente $script:G.Exp -Atencion $script:G.At -Texto 'FICHA | actualizada desde la interfaz'
        Show-Estado; Show-Ficha
        $ui.txtFichaEstado.Foreground = Get-Pincel '#1A7F37'
        $ui.txtFichaEstado.Text = 'Guardada. ' + $ui.txtFichaEstado.Text
    } catch {
        $ui.txtFichaEstado.Foreground = Get-Pincel '#CF222E'
        $ui.txtFichaEstado.Text = Get-MensajeSimple $_.Exception.Message
    }
}

# ------------------------------------------------------------------------------ antes / después

function Show-Medicion {
    $ui = $script:Ui
    $m = $script:G.Momento
    $ui.txtMedicionTitulo.Text = if ($m -eq 'antes') { '② Antes del trabajo' } else { '④ Después del trabajo' }
    $ui.btnDiagnosticar.Content = if ($m -eq 'antes') { 'Diagnosticar ANTES' } else { 'Diagnosticar DESPUÉS' }
    $ui.lstAlertas.Items.Clear()
    $a = Get-Entrada
    $carpeta = if ($a) { Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) $m } else { $null }
    $diag = if ($carpeta) { Read-JsonKitOpcional (Join-Path $carpeta 'diagnostico.json') } else { $null }
    $ui.btnPreInforme.Visibility = if ($m -eq 'antes') { 'Visible' } else { 'Collapsed' }
    $ui.btnPreInforme.IsEnabled = [bool]$diag
    if (-not $script:G.Tarea) {
        $ui.txtMedicionEstado.Text = if ($diag) { "Medición del $($diag.kit.generado) (admin: $(if ($diag.kit.admin.Elevado) { 'sí' } else { 'no' })). Puedes repetirla: la anterior queda de respaldo." } else { 'Todavía no hay diagnóstico.' }
        $ui.prgDiag.Value = if ($diag) { $ui.prgDiag.Maximum } else { 0 }
    }
    foreach ($al in @(if ($diag) { $diag.alertas })) {
        $sev = @{ CRITICO = 'CRÍTICO'; AVISO = 'AVISO'; INFO = 'INFO' }["$($al.Severidad)"]
        [void]$ui.lstAlertas.Items.Add([pscustomobject]@{ Linea = "[$sev] $($al.Texto)"; Color = (Get-Pincel $script:Colores["$($al.Severidad)"]); Texto = $al.Texto; Severidad = $sev })
    }
    $s = if ($a) { Read-SensoresMedicion -Expediente $script:G.Exp -Atencion $script:G.At -Momento $m } else { $null }
    $ui.txtSensores.Text = if ($s) {
        $cpu = if ($s.metricas.cpu_temp_paquete) { $s.metricas.cpu_temp_paquete } else { $s.metricas.cpu_temp_nucleo_max }
        $largoCsv = if ($s.carga) { "$(Format-Numero $s.duracion_min 0) min, $(Format-Numero $s.carga.minutos 0) bajo carga" } else { "$(Format-Numero $s.duracion_min 0) min" }
        $tempCpu = if ($cpu) { "CPU $(Format-Numero $cpu.media 1) / $(Format-Numero $cpu.max 1) °C" } else { 'CPU sin temperatura en el CSV' }
        "$($s.archivo) · $largoCsv · $tempCpu$(if ($s.metricas.gpu_temp) { " · GPU $(Format-Numero $s.metricas.gpu_temp.media 1) / $(Format-Numero $s.metricas.gpu_temp.max 1) °C" }) · pierde velocidad: $(if ($s.pierde_velocidad.valor) { 'sí' } elseif ($null -eq $s.pierde_velocidad.valor) { 'sin dato' } else { 'no' })"
    } else { 'Sin CSV todavía (HWiNFO o LibreHardwareMonitor).' }
    # Condiciones: el DESPUÉS propone las del ANTES.
    $cond = if ($a) { $a['condiciones_medicion'][$m] } else { $null }
    if (-not $cond -and $m -eq 'despues' -and $a) { $cond = $a['condiciones_medicion']['antes'] }
    if (-not $cond) { $cond = @{} }   # en 5.1, indexar $null es un error
    $ui.cmbEnchufado.SelectedIndex = if ($cond -and $cond['enchufado'] -eq $true) { 1 } elseif ($cond -and $cond['enchufado'] -eq $false) { 2 } else { 0 }
    $ui.txtCondPlan.Text = "$($cond['plan'])"; $ui.txtCondVentiladores.Text = "$($cond['ventiladores'])"; $ui.txtCondSuperficie.Text = "$($cond['superficie'])"
    $ui.txtCondAmbiente.Text = "$($cond['temp_ambiente_c'])"; $ui.txtCondCarga.Text = "$($cond['carga_tipo'])"; $ui.txtCondDuracion.Text = "$($cond['carga_duracion_min'])"
    $ui.txtCondEstado.Text = ''
}

function Invoke-PreInformeGui {
    # Genera el pre-informe con lo que haya. -Abrir lo muestra siempre (botón); -Auto lo muestra solo
    # cuando la medición ANTES ya está completa, para no abrirlo a medias.
    param([switch]$Abrir, [switch]$Auto)
    $ui = $script:Ui
    if (-not $script:G.Exp -or -not $script:G.At) { return }
    try {
        # Los trabajos de fondo pudieron cambiar ficha.json: se relee antes de generar.
        $script:G.Exp = Read-Expediente $script:G.Exp.Ruta
        $r = Export-PreInforme -Expediente $script:G.Exp -Atencion $script:G.At
        if (-not $r.Generado) {
            $ui.txtMedicionEstado.Text = 'Pre-informe: todavía falta el diagnóstico ANTES. Toca "Diagnosticar ANTES".'
            if ($Abrir) { [void](Show-Aviso 'Primero haz el diagnóstico ANTES.') }
            return
        }
        $falta = @($r.Falta)
        $ui.txtMedicionEstado.Text = if ($falta.Count) { "Pre-informe parcial. Todavía falta: $($falta -join ' y ')." } else { "Pre-informe listo. Si no se abre en el navegador, está en: $($r.Ruta)" }
        if ($Abrir -or ($Auto -and $falta.Count -eq 0)) {
            if ($Captura) { $script:G.Registro.Add("pre-informe: se abriría $($r.Ruta)") } else { Open-InformeNavegador -Ruta $r.Ruta }
        }
    } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
}

function Invoke-Diagnostico {
    param([string]$Momento, [string[]]$Extra = @(), [switch]$Suelto)
    $ui = $script:Ui
    if (-not $Suelto) {
        Initialize-AtencionGui
        if ($Momento -eq 'despues' -and -not (Test-Medicion -Expediente $script:G.Exp -Atencion $script:G.At -Momento 'antes')) { [void](Show-Aviso 'Primero hay que hacer el diagnóstico ANTES: no existe "después" sin "antes".'); return }
    }
    $args2 = @('-Momento', $(if ($Momento -eq 'antes') { 'Antes' } else { 'Despues' }), '-ProgresoGui') + $Extra
    if (-not $Suelto) { $args2 += @('-Atencion', $script:G.At) }
    if ($Clientes) { $args2 += @('-Clientes', $Clientes) }
    $ui.txtLog.Clear(); $ui.prgDiag.Value = 0; $script:G.DiagN = 0
    $ui.prgDiag.Maximum = 13
    $ui.txtMedicionEstado.Text = 'Partiendo...'
    $oem = [Text.Encoding]::GetEncoding([int](Get-ValorRegistro -Colmena HKLM -Ruta 'SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Nombre 'OEMCP'))
    $script:G.DiagSuelto = [bool]$Suelto
    Invoke-ProcesoFondo -Script (Join-Path $script:Raiz 'diagnostico.ps1') -Argumentos $args2 -Codificacion $oem -Texto "Diagnóstico $($Momento.ToUpperInvariant()) en curso..." -AlLinea {
        param($l)
        $ui = $script:Ui
        if ($l -like '##SECCION|*') {
            $p = $l.Split('|')
            $script:G.DiagN++
            $ui.prgDiag.Value = [math]::Min($ui.prgDiag.Maximum, $script:G.DiagN - 1)
            $ui.txtMedicionEstado.Text = "Sección $($p[1]) de 13: $($p[2])..."
            return
        }
        if ($l -like '##FIN|*') { $ui.prgDiag.Value = $ui.prgDiag.Maximum; return }
        $ui.txtLog.AppendText($l + "`r`n"); $ui.txtLog.ScrollToEnd()
    } -AlTerminar {
        param($codigo, $err)
        $ui = $script:Ui
        # Primero se refresca el panel y después se pone el mensaje, para que no lo tape.
        if (-not $script:G.DiagSuelto) { Show-Estado; Show-Medicion }
        switch ($codigo) {
            0 { $ui.txtMedicionEstado.Text = 'Diagnóstico listo.'; Write-Estado 'Diagnóstico listo.' }
            -1 { $ui.txtMedicionEstado.Text = 'Cancelado. La medición anterior (si había) quedó intacta.'; Write-Estado 'Cancelado.' }
            4 { $ui.txtMedicionEstado.Text = 'No hay un diagnóstico ANTES: hazlo primero.' }
            default { $ui.txtMedicionEstado.Text = "El diagnóstico terminó con un problema (código $codigo). Revisa el registro de abajo."; if ($err) { $ui.txtLog.AppendText($err) } }
        }
        if ($codigo -eq 0 -and -not $script:G.DiagSuelto -and $script:G.Momento -eq 'antes') { Invoke-PreInformeGui -Auto }
    }
}

# ------------------------------------------------------------------------------ trabajo

function Show-Trabajo {
    $ui = $script:Ui
    $a = Get-Entrada
    if (-not $a) { return }
    $cf = $a['checklist_fisico']
    $ui.chkDesarme.IsChecked = [bool]$cf['desarme']; $ui.chkLimpieza.IsChecked = [bool]$cf['limpieza']
    $ui.chkFotosAntes.IsChecked = [bool]$cf['fotos_disipador_antes']; $ui.chkFotosDespues.IsChecked = [bool]$cf['fotos_disipador_despues']
    $ui.txtPasta.Text = "$($cf['pasta'])"; $ui.txtPutty.Text = "$($cf['putty_pads'])"; $ui.txtMateriales.Text = (@($a['materiales'] | Where-Object { $_ }) -join '; ')
    $reg = Read-RegistroLento -Expediente $script:G.Exp -Atencion $script:G.At
    $vivas = @($reg['acciones'] | Where-Object { $_ -and -not $_['deshecha'] })
    $ui.txtLento.Text = if ($vivas.Count) { "Aplicadas: $(($vivas | ForEach-Object { $_['titulo'] }) -join ' · ')" } else { '' }
    Show-ReporteArchivos
    $momento = if (Test-Medicion -Expediente $script:G.Exp -Atencion $script:G.At -Momento 'despues') { 'despues' } else { 'antes' }
    $sem = Get-SemaforoRevision -Expediente $script:G.Exp -Atencion $script:G.At -Momento $momento
    $ui.icSemaforo.ItemsSource = @($sem.Areas | ForEach-Object { [pscustomobject]@{ Area = $_.Area; Frase = $_.Frase; Pincel = (Get-Pincel $script:Colores[$_.Color]) } })
}

function Show-ReporteArchivos {
    $ui = $script:Ui
    $rep = Read-ReporteArchivos -Expediente $script:G.Exp -Atencion $script:G.At
    if (-not $rep) { $ui.dgArchivos.ItemsSource = $null; $ui.txtArchivos.Text = 'Todavía no se analiza.'; return }
    $dt = New-Object System.Data.DataTable
    foreach ($c in @(@('Mover', [bool]), @('Id', [int]), @('Categoria', [string]), @('Tamano', [string]), @('Bytes', [long]), @('Ruta', [string]), @('Motivo', [string]), @('Seleccionable', [bool]))) { [void]$dt.Columns.Add($c[0], $c[1]) }
    foreach ($c in @($rep['candidatos'])) {
        [void]$dt.Rows.Add([bool]$c['seleccionado'], [int]$c['id'], $(if ($c['seleccionable']) { $c['categoria'] } else { "$($c['categoria']) (solo informe)" }), (Format-Tamano $c['tamano']), [long]$c['tamano'], $c['ruta'], $c['motivo'], [bool]$c['seleccionable'])
    }
    $script:G.TablaArchivos = $dt
    $ui.dgArchivos.ItemsSource = $dt.DefaultView
    $res = @($rep['resumen'].Keys | ForEach-Object { "$_ $($rep['resumen'][$_]['cantidad']) ($(Format-Tamano $rep['resumen'][$_]['bytes']))" })
    $ui.txtArchivos.Text = "Análisis del $($rep['generado'])$(if ($rep['parcial']) { ' (PARCIAL por tiempo)' }): $($res -join ' · '). Desmarca lo que no quieras mover."
}

# ------------------------------------------------------------------------------ informe, herramientas, cliente

function Show-Informe {
    $ui = $script:Ui
    $a = Get-Entrada
    if (-not $a) { $ui.txtInforme.Text = 'Todavía no hay atención.'; return }
    $faltan = @(Test-FichaCompleta -Expediente $script:G.Exp -Atencion $script:G.At)
    $ui.txtInforme.Foreground = Get-Pincel $(if ($faltan.Count) { '#BC4C00' } else { '#1A7F37' })
    $ui.txtInforme.Text = if ($faltan.Count) { "Para generar los informes falta: $(($faltan | ForEach-Object { $_.Texto }) -join ' · ')" } else { 'La ficha está completa: puedes generar los informes.' }
    $ui.btnGenerar.IsEnabled = ($faltan.Count -eq 0)
    $carpeta = Join-Path $script:G.Exp.Ruta $script:G.At
    foreach ($par in @(@{ W = $ui.wbCliente; F = 'informe_cliente.html' }, @{ W = $ui.wbTecnico; F = 'informe_tecnico.html' })) {
        $r = Join-Path $carpeta $par.F
        if ([IO.File]::Exists($r) -and -not $Captura) { $par.W.Navigate([uri]$r) }
    }
}

function Show-Herramientas {
    $ui = $script:Ui
    $ui.wpHerramientas.Children.Clear()
    foreach ($o in @(Get-OpcionesHerramientas -Carpeta (Join-Path $script:Ctx.RaizKit 'herramientas'))) {
        $b = New-Object Windows.Controls.Button
        $b.Content = "$($o.Nombre)`n$(if ($o.Version) { $o.Version } elseif (-not $o.Exe) { 'no está' } else { '' })"
        $b.Width = 190; $b.Height = 64; $b.IsEnabled = [bool]$o.Exe
        $b.Tag = $o
        $b.ToolTip = if ($o.Personal) { 'Solo con licencia comercial' } else { "Licencia: $($o.Licencia)" }
        $b.Add_Click({
                param($s, $e)
                $o = $s.Tag
                $script:Ui.txtHerramienta.Text = "$($o.Nombre) · licencia: $($o.Licencia)$(if ($o.Nota) { " · Ojo: $($o.Nota)" })"
                try { Start-Herramienta -Opcion $o } catch { [void](Show-Aviso "No se pudo abrir $($o.Nombre): $($_.Exception.Message)" -EsError) }
            })
        [void]$ui.wpHerramientas.Children.Add($b)
    }
}

function Show-VistaCliente {
    # Pantalla completa para mostrarle al cliente: semáforo, frase y tarjetas antes -> después.
    $a = Get-Entrada
    if (-not $a -or @($a['motivos']).Count -eq 0) { [void](Show-Aviso 'Primero elige los motivos y haz las mediciones.'); return }
    $d = Get-DatosInforme -Expediente $script:G.Exp -Atencion $script:G.At
    $w = New-Object Windows.Window
    $w.WindowStyle = 'None'; $w.WindowState = 'Maximized'; $w.Topmost = $true; $w.Background = Get-Pincel '#FFFFFF'; $w.FontFamily = 'Segoe UI'
    if ($Captura) { $w.WindowState = 'Normal'; $w.Width = 1180; $w.Height = 700 }
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = '60,40'
    $luces = New-Object Windows.Controls.StackPanel; $luces.Orientation = 'Horizontal'; $luces.Margin = '0,0,0,20'
    foreach ($c in 'rojo', 'amarillo', 'verde') { $e = New-Object Windows.Shapes.Ellipse; $e.Width = 46; $e.Height = 46; $e.Margin = '0,0,14,0'; $e.Fill = Get-Pincel $(if ($d.Color -eq $c) { $script:Colores[$c] } else { '#E6E8EB' }); [void]$luces.Children.Add($e) }
    [void]$sp.Children.Add($luces)
    $fr = New-Object Windows.Controls.TextBlock; $fr.Text = $d.Frase; $fr.FontSize = 40; $fr.FontWeight = 'SemiBold'; $fr.TextWrapping = 'Wrap'; $fr.Margin = '0,0,0,30'
    [void]$sp.Children.Add($fr)
    $wp = New-Object Windows.Controls.WrapPanel
    $principal = @($d.Metricas.Keys)[0]
    $metPrincipal = if ($principal) { $d.Metricas[$principal] } else { $null }
    $conDatos = { param($t) $t -and ($null -ne $t.Antes -or $null -ne $t.Despues) }
    $tarjetas = if ($metPrincipal -and $metPrincipal.PSObject.Properties['Pantalla']) { @($metPrincipal.Pantalla | Where-Object { & $conDatos $_ }) } elseif ($metPrincipal) { @($metPrincipal.Tarjetas | Where-Object { & $conDatos $_ } | Select-Object -First 4) } else { @() }
    foreach ($t in $tarjetas) {
        $b = New-Object Windows.Controls.Border; $b.Width = 360; $b.Margin = '0,0,24,24'; $b.Padding = '24'; $b.CornerRadius = 12; $b.BorderThickness = 2; $b.BorderBrush = Get-Pincel '#D0D7DE'
        $c = New-Object Windows.Controls.StackPanel
        $ti = New-Object Windows.Controls.TextBlock; $ti.Text = $t.Titulo; $ti.FontSize = 22; $ti.Foreground = Get-Pincel '#57606A'; $ti.TextWrapping = 'Wrap'
        $va = New-Object Windows.Controls.TextBlock; $va.FontSize = 40; $va.FontWeight = 'SemiBold'; $va.Margin = '0,12,0,0'
        $flecha = if ($null -eq $t.Mejoro) { '→' } elseif (($t.Mejor -eq 'mayor') -eq [bool]$t.Mejoro) { '▲' } else { '▼' }
        if ($t.Mejor -eq 'si_no' -and $null -ne $t.Mejoro) { $flecha = '→' }
        $va.Inlines.Add((New-Object Windows.Documents.Run((Format-ValorTarjeta $t.Antes $t.Unidad) + '  ')))
        $r2 = New-Object Windows.Documents.Run($flecha + '  '); $r2.Foreground = Get-Pincel $(if ($null -eq $t.Mejoro) { '#8C959F' } elseif ($t.Mejoro) { '#1A7F37' } else { '#CF222E' }); $va.Inlines.Add($r2)
        $va.Inlines.Add((New-Object Windows.Documents.Run((Format-ValorTarjeta $t.Despues $t.Unidad))))
        # El valor se achica si no cabe en la tarjeta (nunca se agranda ni se corta).
        $vb = New-Object Windows.Controls.Viewbox; $vb.StretchDirection = 'DownOnly'; $vb.HorizontalAlignment = 'Left'; $vb.Child = $va
        [void]$c.Children.Add($ti); [void]$c.Children.Add($vb); $b.Child = $c
        [void]$wp.Children.Add($b)
    }
    [void]$sp.Children.Add($wp)
    $pie = New-Object Windows.Controls.TextBlock; $pie.Text = 'Esc para salir'; $pie.Foreground = Get-Pincel '#8C959F'; $pie.Margin = '0,20,0,0'
    [void]$sp.Children.Add($pie)
    $w.Content = $sp
    $w.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $s.Close() } })
    $w.Owner = $script:Win
    $script:G.VentanaCliente = $w
    if ($Captura) { $w.Show() } else { [void]$w.ShowDialog() }
}

# ------------------------------------------------------------------------------ expedientes y sincronización

function Show-Expedientes {
    # Lista los expedientes del USB o del maestro. El maestro y Sincronizar solo aparecen en tus equipos.
    $ui = $script:Ui
    $tecnico = Test-EquipoTecnico
    $maestro = Get-MaestroGui
    $ui.rbFuenteMaestro.Visibility = if ($tecnico) { 'Visible' } else { 'Collapsed' }
    $ui.grpSincronizar.Visibility = if ($tecnico) { 'Visible' } else { 'Collapsed' }
    if (-not $tecnico) { $ui.rbFuenteUsb.IsChecked = $true }
    $ui.txtMaestro.Text = "USB: $($script:Ctx.CarpetaClientes)`nMaestro: $maestro$(if ($maestro -and -not [IO.Directory]::Exists($maestro)) { '  (todavía no existe: se crea al sincronizar)' })"
    $enMaestro = [bool]$ui.rbFuenteMaestro.IsChecked
    $carpeta = if ($enMaestro) { $maestro } else { $script:Ctx.CarpetaClientes }
    $dt = New-Object System.Data.DataTable
    foreach ($c in 'Ruta', 'Cliente', 'Comuna', 'Equipo', 'Serie', 'Atenciones', 'Ultima') { [void]$dt.Columns.Add($c, [string]) }
    $filas = if ($carpeta) { @(Get-ListaExpedientes -Carpeta $carpeta -EsUsb:(-not $enMaestro) | Sort-Object Ultima -Descending) } else { @() }
    foreach ($e in $filas) {
        [void]$dt.Rows.Add($e.Ruta, $e.Cliente, $e.Comuna, $e.Equipo, $e.Serie, $e.Atenciones, $e.Ultima)
    }
    $script:G.TablaExp = $dt
    $ui.dgExpedientes.ItemsSource = $dt.DefaultView
    Invoke-FiltroExpedientes
    $ui.txtExpedientes.Text = if ($carpeta -and [IO.Directory]::Exists($carpeta)) { "$($dt.Rows.Count) expedientes en $carpeta. Doble clic para abrir." } elseif ($carpeta) { "Todavía no existe $carpeta." } else { 'Falta config.json -> sincronizacion.ruta_maestro.' }
    if ($dt.Rows.Count) { $ui.dgExpedientes.SelectedIndex = 0 }
    Show-AtencionesExpediente
}

function Invoke-FiltroExpedientes {
    $dt = $script:G.TablaExp
    if (-not $dt) { return }
    $t = $script:Ui.txtBuscarExp.Text.Trim()
    if (-not $t) { $dt.DefaultView.RowFilter = ''; return }
    # En RowFilter, * % [ ] van entre corchetes y la comilla simple se duplica.
    $t = ($t -replace "'", "''") -replace '([\[\]\*%])', '[$1]'
    $dt.DefaultView.RowFilter = "Cliente LIKE '*{0}*' OR Comuna LIKE '*{0}*' OR Equipo LIKE '*{0}*' OR Serie LIKE '*{0}*'" -f $t
}

function Show-AtencionesExpediente {
    # Las atenciones del expediente marcado; las que ya se liberaron al maestro aparecen sin poder elegirse.
    $ui = $script:Ui
    $ui.cmbAtencionExp.Items.Clear()
    $ui.btnAbrirExp.IsEnabled = $false
    $fila = $ui.dgExpedientes.SelectedItem
    if (-not $fila) { return }
    try { $e = Read-Expediente $fila.Row['Ruta'] } catch { return }
    $elegida = $null
    foreach ($a in @(Get-ListaAtenciones -Expediente $e)) {
        $hay = [IO.Directory]::Exists((Join-Path $e.Ruta $a['carpeta']))
        $item = New-Object Windows.Controls.ComboBoxItem
        $motivos = (@($a['motivos'] | Where-Object { $_ }) -join ', ')
        $item.Content = "$($a['carpeta'])  ·  $(if ($motivos) { $motivos } else { 'sin motivos' })  ·  $(if ($a['entregado']) { "entregada el $($a['entregado'])" } else { 'abierta' })$(if (-not $hay) { '  ·  está en el maestro' })"
        $item.Tag = $a['carpeta']
        $item.IsEnabled = $hay
        [void]$ui.cmbAtencionExp.Items.Add($item)
        if ($hay) { $elegida = $item }
    }
    if ($elegida) { $ui.cmbAtencionExp.SelectedItem = $elegida; $ui.btnAbrirExp.IsEnabled = $true }
}

function Open-ExpedienteLista {
    $ui = $script:Ui
    $fila = $ui.dgExpedientes.SelectedItem
    $item = $ui.cmbAtencionExp.SelectedItem
    if (-not $fila -or -not $item) { return }
    if ($script:G.Tarea) { [void](Show-Aviso 'Espera a que termine el trabajo en curso.'); return }
    try {
        Open-Expediente -Ruta $fila.Row['Ruta'] -Carpeta $item.Tag
        Show-Panel 'pnlInicio'
        Write-Estado "Abierto: $($script:G.Exp.Id) · $($script:G.At)$(if ($script:G.Ajeno) { ' (consulta)' })"
    } catch { [void](Show-Aviso "No se pudo abrir: $($_.Exception.Message)" -EsError) }
}

function Invoke-SincronizarGui {
    $ui = $script:Ui
    if (-not (Test-EquipoTecnico)) { return }
    $maestro = Get-MaestroGui
    $liberar = [bool]$ui.chkLiberarUsb.IsChecked
    $texto = "Se copian los expedientes del USB al maestro:`n$maestro`n`nEn el maestro no se borra ni se pisa nada: si algo cambió en los dos lados, se guardan ambas versiones."
    if ($liberar) { $texto += "`n`nDespués se borran del USB las atenciones ENTREGADAS cuyos archivos estén idénticos en el maestro (verificado por hash). Las abiertas y las fichas se quedan." }
    if (-not (Show-Aviso "$texto`n`n¿Sincronizar?" -Pregunta)) { return }
    $args2 = @('-Maestro', $maestro, '-ProgresoGui')
    if ($liberar) { $args2 += '-LiberarUsb' }
    if ($Clientes) { $args2 += @('-Clientes', $Clientes) }
    $ui.txtSync.Text = 'Sincronizando...'
    Invoke-ScriptKit -Script (Join-Path $script:Raiz 'sincronizar.ps1') -Argumentos $args2 -Texto 'Sincronizando con el maestro...' -AlResultado {
        param($r)
        $ui = $script:Ui
        $partes = @("$($r.Archivos) archivos: $($r.Nuevos) nuevos, $($r.Actualizados) actualizados, $($r.Iguales) iguales")
        if ($r.MaestroMasNuevo) { $partes += "$($r.MaestroMasNuevo) más nuevos en el maestro (se dejaron)" }
        if (@($r.EnCurso).Count) { $partes += "$(@($r.EnCurso).Count) mediciones en curso sin copiar" }
        if ($r.Liberar) { $partes += "liberadas del USB: $(@($r.Liberadas).Count) ($(Format-Tamano $r.BytesLiberados))$(if (@($r.NoLiberadas).Count) { ", quedaron $(@($r.NoLiberadas).Count)" })" }
        $ui.txtSync.Text = "Sincronizado $(ConvertTo-TextoFecha (Get-Date)). $($partes -join ' · ')."
        $avisos = @()
        if (@($r.Conflictos).Count) { $avisos += "OJO: $(@($r.Conflictos).Count) archivos cambiaron en el USB y en el maestro. Se guardaron ambas versiones (la del USB como '(conflicto USB ...)'):`n- $((@($r.Conflictos) | Select-Object -First 5) -join "`n- ")" }
        if (@($r.Errores).Count) { $avisos += "No se pudieron copiar $(@($r.Errores).Count) (se reintentan la próxima vez):`n- $((@($r.Errores) | Select-Object -First 5) -join "`n- ")" }
        if (@($r.NoLiberadas).Count) { $avisos += "Quedaron en el USB:`n- $((@($r.NoLiberadas) | Select-Object -First 5) -join "`n- ")" }
        $script:G.Registro.Add("sincronizacion: $($ui.txtSync.Text)")
        [void](Show-Aviso ("$($ui.txtSync.Text)$(if ($avisos) { "`n`n" + ($avisos -join "`n`n") })`n`nLog: $($r.Log)") -EsError:([bool](@($r.Conflictos).Count -or @($r.Errores).Count)))
        Show-Estado
        Show-Expedientes
    }
}

# ------------------------------------------------------------------------------ construcción y eventos

foreach ($i in $script:ItemsChecklist) {
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '0,0,10,6'
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $i; $t.Foreground = Get-Pincel '#57606A'
    $cb = New-Object Windows.Controls.ComboBox
    foreach ($o in '', 'ok', 'falla', 'no aplica') { [void]$cb.Items.Add($o) }
    $cb.SelectedIndex = 0
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($cb)
    [void]$ui.ugChecklist.Children.Add($sp)
    $script:G.Chk[$i] = $cb
}
for ($n = 1; $n -le 13; $n++) {
    $cb = New-Object Windows.Controls.CheckBox; $cb.Content = "$n. $($script:NombresSecciones[$n - 1])"; $cb.IsChecked = $true; $cb.Tag = $n; $cb.Width = 200
    [void]$ui.wpSecciones.Children.Add($cb)
}

$script:Temporizador = New-Object Windows.Threading.DispatcherTimer
$script:Temporizador.Interval = [TimeSpan]::FromMilliseconds(150)
$script:Temporizador.Add_Tick({ Invoke-LecturaFondo })

$ui.navInicio.Add_Click({ Show-Panel 'pnlInicio' })
$ui.navFicha.Add_Click({ Show-Panel 'pnlFicha' })
$ui.navAntes.Add_Click({ $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion' })
$ui.navTrabajo.Add_Click({ Show-Panel 'pnlTrabajo' })
$ui.navDespues.Add_Click({ $script:G.Momento = 'despues'; Show-Panel 'pnlMedicion' })
$ui.navInforme.Add_Click({ Show-Panel 'pnlInforme' })
$ui.navTecnico.Add_Click({ Show-Panel 'pnlTecnico' })
$ui.navHerramientas.Add_Click({ Show-Panel 'pnlHerramientas' })
$ui.navExpedientes.Add_Click({ Show-Panel 'pnlExpedientes' })
$ui.rbFuenteUsb.Add_Checked({ if ($script:G.Panel -eq 'pnlExpedientes') { Show-Expedientes } })
$ui.rbFuenteMaestro.Add_Checked({ if ($script:G.Panel -eq 'pnlExpedientes') { Show-Expedientes } })
$ui.txtBuscarExp.Add_TextChanged({ Invoke-FiltroExpedientes })
$ui.dgExpedientes.Add_SelectionChanged({ Show-AtencionesExpediente })
$ui.dgExpedientes.Add_MouseDoubleClick({ Open-ExpedienteLista })
$ui.btnAbrirExp.Add_Click({ Open-ExpedienteLista })
$ui.btnSincronizar.Add_Click({ Invoke-SincronizarGui })
$ui.btnAbrirLogSync.Add_Click({
        $m = Get-MaestroGui
        $dirs = @($(if ($m) { Join-Path $m '_sincronizacion\logs' }), (Join-Path $script:Ctx.CarpetaClientes '_sincronizacion\logs')) | Where-Object { $_ }
        $log = $dirs | Where-Object { [IO.Directory]::Exists($_) } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.log' } | Sort-Object Name | Select-Object -Last 1
        if ($log) { Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$($log.FullName)`"" } else { [void](Show-Aviso 'Todavía no hay sincronizaciones.') }
    })
$ui.btnVolverEquipo.Add_Click({
        if ($script:G.Tarea) { [void](Show-Aviso 'Espera a que termine el trabajo en curso.'); return }
        $script:G.Ajeno = $false; $script:G.Origen = 'USB'; $script:G.Exp = $null; $script:G.At = $null
        Show-Estado; Show-Panel 'pnlInicio'
    })
$ui.navCliente.Add_Click({ try { Show-VistaCliente } catch { [void](Show-Aviso "No se pudo mostrar: $($_.Exception.Message)" -EsError) } })
$ui.btnCancelar.Add_Click({ if (Show-Aviso '¿Cancelar el trabajo en curso?' -Pregunta) { Invoke-CancelarTarea } })

$alMotivo = {
    if ($script:G.Cargando) { return }
    try {
        Initialize-AtencionGui
        $m = @(@{ tgCalor = 'CALOR'; tgLento = 'LENTO'; tgArchivos = 'ARCHIVOS'; tgRevision = 'REVISION' }.GetEnumerator() | Where-Object { $script:Ui[$_.Key].IsChecked } | ForEach-Object { $_.Value } | Sort-Object { @('CALOR', 'LENTO', 'ARCHIVOS', 'REVISION').IndexOf($_) })
        Set-Ficha -Expediente $script:G.Exp -Atencion $script:G.At -Valores @{ motivos = $m }
        Show-Estado
    } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
}
foreach ($t in 'tgCalor', 'tgLento', 'tgArchivos', 'tgRevision') { $ui[$t].Add_Checked($alMotivo); $ui[$t].Add_Unchecked($alMotivo) }

$ui.btnGuardarFicha.Add_Click({ Save-FichaGui })
$ui.btnFotos.Add_Click({
        try {
            Initialize-AtencionGui
            $dlg = New-Object Microsoft.Win32.OpenFileDialog; $dlg.Multiselect = $true; $dlg.Filter = 'Fotos (*.jpg;*.jpeg;*.png;*.heic)|*.jpg;*.jpeg;*.png;*.heic|Todos los archivos (*.*)|*.*'
            if (-not $dlg.ShowDialog($script:Win)) { return }
            $destino = Join-Path $script:G.Exp.Ruta 'fotos_recepcion'
            $null = [IO.Directory]::CreateDirectory($destino)
            foreach ($f in $dlg.FileNames) { [IO.File]::Copy($f, (Join-Path $destino ('{0}_{1}' -f (Get-Date).ToString('yyyyMMdd_HHmmss'), [IO.Path]::GetFileName($f))), $false) }
            Write-TrabajoLog -Expediente $script:G.Exp -Atencion $script:G.At -Texto "FICHA | $($dlg.FileNames.Count) fotos de recepción copiadas"
            [void](Show-Aviso "Se copiaron $($dlg.FileNames.Count) fotos a fotos_recepcion.")
        } catch { [void](Show-Aviso "No se pudieron copiar las fotos: $($_.Exception.Message)" -EsError) }
    })
$ui.btnEntregado.Add_Click({
        if (-not (Get-Entrada)) { return }
        if (-not (Show-Aviso '¿Marcar el equipo como entregado hoy? Cierra la atención y empieza la garantía.' -Pregunta)) { return }
        try {
            Initialize-AtencionGui   # relee la ficha: otro proceso pudo cambiarla
            Set-Ficha -Expediente $script:G.Exp -Atencion $script:G.At -Valores @{ entregado = (Get-Date).ToString('yyyy-MM-dd') }
            Write-TrabajoLog -Expediente $script:G.Exp -Atencion $script:G.At -Texto 'FICHA | entregado'
            $g = (Get-Entrada)['garantia_hasta']
            [void](Show-Aviso "Entregado. Garantía hasta $g.")
            Show-Estado; Show-Ficha
        } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
    })

$ui.btnDiagnosticar.Add_Click({ Invoke-Diagnostico -Momento $script:G.Momento -Extra $(if ($script:Ui.chkEspacio.IsChecked) { @() } else { @('-SinEspacio') }) })
$ui.lstAlertas.Add_MouseDoubleClick({ $s = $script:Ui.lstAlertas.SelectedItem; if ($s) { [void](Show-Aviso $s.Texto $s.Severidad) } })
$ui.btnImportarCsv.Add_Click({
        try {
            Initialize-AtencionGui
            $dlg = New-Object Microsoft.Win32.OpenFileDialog; $dlg.Filter = 'CSV de sensores (*.csv)|*.csv'
            if (-not $dlg.ShowDialog($script:Win)) { return }
            Invoke-TareaKit -Accion 'importar_sensores' -Parametros @{ momento = $script:G.Momento; ruta = $dlg.FileName } -Texto 'Leyendo el CSV de sensores...' -AlResultado { param($r) Show-Medicion; Show-Estado; if ($script:G.Momento -eq 'antes') { Invoke-PreInformeGui -Auto } }
        } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
    })
$ui.btnPreInforme.Add_Click({ Invoke-PreInformeGui -Abrir })
$ui.btnGuardarCondiciones.Add_Click({
        $ui = $script:Ui
        try {
            Initialize-AtencionGui
            Set-CondicionesCalor -Expediente $script:G.Exp -Atencion $script:G.At -Momento $script:G.Momento -Valores ([ordered]@{
                    enchufado = @($null, 'si', 'no')[[math]::Max(0, $ui.cmbEnchufado.SelectedIndex)]; plan = $ui.txtCondPlan.Text; ventiladores = $ui.txtCondVentiladores.Text; superficie = $ui.txtCondSuperficie.Text
                    temp_ambiente_c = $ui.txtCondAmbiente.Text; carga_tipo = $ui.txtCondCarga.Text; carga_duracion_min = $ui.txtCondDuracion.Text })
            $script:G.Exp = Read-Expediente $script:G.Exp.Ruta
            $ui.txtCondEstado.Foreground = Get-Pincel '#1A7F37'; $ui.txtCondEstado.Text = 'Condiciones guardadas.'
            if ($script:G.Momento -eq 'antes') {
                Invoke-PreInformeGui -Auto
                $ui.txtCondEstado.Text = "Condiciones guardadas. $($ui.txtMedicionEstado.Text)"
            }
        } catch { $ui.txtCondEstado.Foreground = Get-Pincel '#CF222E'; $ui.txtCondEstado.Text = Get-MensajeSimple $_.Exception.Message }
    })

$ui.btnGuardarChecklist.Add_Click({
        $ui = $script:Ui
        try {
            Initialize-AtencionGui   # relee la ficha: otro proceso pudo cambiarla
            Set-Ficha -Expediente $script:G.Exp -Atencion $script:G.At -Valores ([ordered]@{
                    'checklist_fisico.desarme' = [bool]$ui.chkDesarme.IsChecked; 'checklist_fisico.limpieza' = [bool]$ui.chkLimpieza.IsChecked
                    'checklist_fisico.fotos_disipador_antes' = [bool]$ui.chkFotosAntes.IsChecked; 'checklist_fisico.fotos_disipador_despues' = [bool]$ui.chkFotosDespues.IsChecked
                    'checklist_fisico.pasta' = $ui.txtPasta.Text; 'checklist_fisico.putty_pads' = $ui.txtPutty.Text; materiales = $ui.txtMateriales.Text })
            Write-TrabajoLog -Expediente $script:G.Exp -Atencion $script:G.At -Texto 'CALOR | checklist físico actualizado'
            Write-Estado 'Checklist guardado.'
        } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
    })
$ui.btnBuscarAcciones.Add_Click({
        try {
            $acc = @(Get-AccionesLento -Expediente $script:G.Exp -Atencion $script:G.At)
            $dt = New-Object System.Data.DataTable
            foreach ($c in @(@('Aplicar', [bool]), @('Titulo', [string]), @('Detalle', [string]), @('Marcas', [string]), @('Id', [string]))) { [void]$dt.Columns.Add($c[0], $c[1]) }
            foreach ($a in $acc) {
                $marcas = @(); if ($a.RequiereAdmin) { $marcas += 'admin' }; if ($a.Riesgo -eq 'revisar') { $marcas += 'revisar' }; if ($a.Tipo -eq 'manual') { $marcas += 'manual' }
                [void]$dt.Rows.Add($false, $a.Titulo, "$($a.QueHace)$(if ($a.Deshacer) { ' Deshacer: ' + $a.Deshacer })", ($marcas -join ', '), $a.Id)
            }
            $script:G.TablaAcciones = $dt
            $script:Ui.dgAcciones.ItemsSource = $dt.DefaultView
            $script:Ui.txtLento.Text = if ($acc.Count) { "$($acc.Count) acciones sugeridas. Ninguna viene marcada." } else { 'No hay acciones sugeridas para este equipo.' }
        } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
    })
$ui.btnAplicarAcciones.Add_Click({
        $dt = $script:G.TablaAcciones
        if (-not $dt) { return }
        $ids = @($dt.Rows | Where-Object { $_['Aplicar'] } | ForEach-Object { $_['Id'] })
        if ($ids.Count -eq 0) { [void](Show-Aviso 'Marca primero las acciones que quieres aplicar.'); return }
        $conAdmin = @($dt.Rows | Where-Object { $_['Aplicar'] -and $_['Marcas'] -match 'admin' })
        if ($conAdmin.Count -and -not $script:Ctx.Admin.Elevado) { [void](Show-Aviso 'Algunas acciones marcadas necesitan admin. Usa "Relanzar como admin" (arriba a la derecha).'); return }
        if (-not (Show-Aviso "¿Aplicar $($ids.Count) acciones? Antes se crea un punto de restauración; cada una se puede deshacer." -Pregunta)) { return }
        $sinPunto = $false
        if (-not $script:Ctx.Admin.Elevado) {
            $sinPunto = Show-Aviso 'Sin admin no se puede crear el punto de restauración. ¿Seguir igual? (lo recomendado es relanzar como admin)' -Pregunta
            if (-not $sinPunto) { return }
        }
        Invoke-TareaKit -Accion 'aplicar_lento' -Parametros @{ ids = $ids; sin_punto = $sinPunto } -Texto 'Aplicando acciones...' -AlResultado {
            param($r)
            [void](Show-Aviso ("Hechas: $(@($r.hechas).Count)." + $(if (@($r.errores).Count) { "`nNo se pudo: $(@($r.errores) -join '; ')" } else { '' })))
            Show-Trabajo
        }
    })
$ui.btnDeshacerLento.Add_Click({
        if (-not (Show-Aviso '¿Deshacer todas las acciones aplicadas?' -Pregunta)) { return }
        Invoke-TareaKit -Accion 'deshacer_lento' -Texto 'Deshaciendo acciones...' -AlResultado { param($r) [void](Show-Aviso "Deshechas: $(@($r.deshechas).Count)."); Show-Trabajo }
    })
$ui.btnAnalizar.Add_Click({
        $p = Get-PermisoArchivos -Expediente $script:G.Exp -Atencion $script:G.At
        if (-not $p.PuedeAnalizar) { [void](Show-Aviso "Falta en la ficha: $($p.Falta -join ', ')."); return }
        # PerfilPrueba: solo lo pone un escenario de prueba, para analizar una carpeta de prueba y no el perfil real.
        $param = if ($script:G.PerfilPrueba) { @{ perfil = $script:G.PerfilPrueba } } else { $null }
        Invoke-TareaKit -Accion 'analizar_archivos' -Parametros $param -Texto 'Analizando archivos...' -AlResultado { param($r) Show-ReporteArchivos }
    })
$ui.btnMover.Add_Click({
        $dt = $script:G.TablaArchivos
        if (-not $dt) { [void](Show-Aviso 'Primero analiza.'); return }
        $filas = @($dt.Rows | Where-Object { $_['Mover'] -and $_['Seleccionable'] })
        if ($filas.Count -eq 0) { [void](Show-Aviso 'No hay nada marcado para mover.'); return }
        $bytes = [long](($filas | ForEach-Object { $_['Bytes'] }) | Measure-Object -Sum).Sum
        if (-not (Show-Aviso "Se moverán $($filas.Count) elementos ($(Format-Tamano $bytes)) a _PARA_BORRAR en su mismo disco. No se borra nada y se puede deshacer. ¿Seguir?" -Pregunta)) { return }
        Invoke-TareaKit -Accion 'mover_archivos' -Parametros @{ ids = @($filas | ForEach-Object { [int]$_['Id'] }) } -Texto 'Moviendo archivos...' -AlResultado {
            param($r)
            [void](Show-Aviso ("Movidos $($r.movidos) ($(Format-Tamano $r.bytes)) a $(@($r.destinos) -join ', '). Para devolverlos: _DESHACER.ps1 en esa carpeta." + $(if (@($r.saltados).Count) { "`n$(@($r.saltados).Count) no se movieron (ver log)." } else { '' })))
            Show-ReporteArchivos
        }
    })
$ui.btnDeshacerArchivos.Add_Click({
        if (-not (Show-Aviso '¿Devolver a su lugar todo lo movido?' -Pregunta)) { return }
        Invoke-TareaKit -Accion 'deshacer_archivos' -Texto 'Devolviendo archivos...' -AlResultado { param($r) [void](Show-Aviso "Devueltos: $($r.devueltos).$(if (@($r.problemas).Count) { " Problemas: $(@($r.problemas).Count)." })") }
    })
$ui.btnTrabajoTerminado.Add_Click({
        try {
            Initialize-AtencionGui   # relee la ficha: otro proceso pudo cambiarla
            Set-Ficha -Expediente $script:G.Exp -Atencion $script:G.At -Valores @{ trabajo_terminado = $true }
            Write-TrabajoLog -Expediente $script:G.Exp -Atencion $script:G.At -Texto 'TRABAJO | terminado'
            Show-Estado
            $script:G.Momento = 'despues'; Show-Panel 'pnlMedicion'
        } catch { [void](Show-Aviso (Get-MensajeSimple $_.Exception.Message) -EsError) }
    })

$ui.btnGenerar.Add_Click({
        Invoke-TareaKit -Accion 'generar_informes' -Texto 'Generando informes...' -AlResultado {
            param($r)
            if (-not $r.generado) { [void](Show-Aviso "Falta: $(@($r.faltan) -join ' · ')"); return }
            Show-Estado; Show-Informe
            if (@($r.advertencias).Count) { [void](Show-Aviso "Informes listos. Ojo:`n- $(@($r.advertencias) -join "`n- ")") }
        }
    })
foreach ($par in @(@{ B = 'btnAbrirCliente'; F = 'informe_cliente.html' }, @{ B = 'btnAbrirTecnico'; F = 'informe_tecnico.html' })) {
    $f = $par.F
    $ui[$par.B].Tag = $f
    $ui[$par.B].Add_Click({ param($s, $e) $r = Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) $s.Tag; if ([IO.File]::Exists($r)) { try { Open-InformeNavegador -Ruta $r } catch { [void](Show-Aviso $_.Exception.Message -EsError) } } else { [void](Show-Aviso 'Todavía no se genera.') } })
}
$ui.btnAbrirCarpeta.Add_Click({ if ($script:G.Exp) { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$(Join-Path $script:G.Exp.Ruta $script:G.At)`"" } })

$ui.btnDiagSuelto.Add_Click({
        $secs = @($script:Ui.wpSecciones.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($secs.Count -eq 0) { return }
        $extra = @('-NuevaAtencion', '-Secciones', ($secs -join ','))
        if (-not $script:Ui.chkSueltoEspacio.IsChecked) { $extra += '-SinEspacio' }
        $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'
        Invoke-Diagnostico -Momento 'antes' -Extra $extra -Suelto
    })
$ui.btnAbrirExpediente.Add_Click({ if ($script:G.Exp) { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($script:G.Exp.Ruta)`"" } else { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($script:Ctx.CarpetaClientes)`"" } })
$ui.btnAbrirResumen.Add_Click({
        $r = if ($script:G.Exp) { Get-ChildItem -LiteralPath $script:G.Exp.Ruta -Recurse -Filter resumen.txt -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 } else { $null }
        if ($r) { Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$($r.FullName)`"" } else { [void](Show-Aviso 'Todavía no hay resumen.') }
    })
$ui.btnAbrirTrabajoLog.Add_Click({ $r = if ($script:G.At) { Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'trabajo.log' }; if ($r -and [IO.File]::Exists($r)) { Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$r`"" } })
$ui.btnAbrirLeeme.Add_Click({ Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$(Join-Path $script:Ctx.RaizKit 'docs\LEEME.md')`"" })
$ui.btnConsola.Add_Click({ Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/c', "`"$(Join-Path $script:Ctx.RaizKit 'INICIAR.cmd')`" consola" })
$ui.btnRelanzar.Add_Click({
        if ($script:G.Tarea) { [void](Show-Aviso 'Espera a que termine el trabajo en curso.'); return }
        try {
            # Se conserva la atención (y la carpeta de expedientes) al volver a abrir como admin.
            $partes = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', ('"' + $PSCommandPath + '"'))
            if ($script:G.At) { $partes += @('-Atencion', ('"' + $script:G.At + '"')) }
            if ($Clientes) { $partes += @('-Clientes', ('"' + $Clientes + '"')) }
            if ($script:G.Ajeno) { $partes += @('-RutaExpediente', ('"' + $script:G.Exp.Ruta + '"')) }
            if ($RutaMaestro) { $partes += @('-RutaMaestro', ('"' + $RutaMaestro + '"')) }
            if ($Captura) {
                # Prueba: la ventana elevada sigue el mismo escenario y guarda sus capturas en <Captura>\admin.
                $partes += @('-Captura', ('"' + (Join-Path $Captura 'admin') + '"'))
                if ($Escenario) { $partes += @('-Escenario', ('"' + $Escenario + '"')) }
                $script:G.Registro.Add("relanzar como admin: $($partes -join ' ')")
                [IO.File]::WriteAllLines((Join-Path $Captura 'registro.txt'), $script:G.Registro)
            }
            Start-Process -FilePath $script:PS -ArgumentList ($partes -join ' ') -Verb RunAs -ErrorAction Stop
            $script:Win.Close()
        } catch { [void](Show-Aviso 'No se elevó: se canceló el aviso o este usuario no es administrador.') }
    })
$script:Win.Add_Closing({
        param($s, $e)
        if ($script:G.Tarea -and -not $Captura) {
            if (Show-Aviso 'Hay un trabajo en curso. ¿Cancelarlo y salir?' -Pregunta) { Invoke-CancelarTarea } else { $e.Cancel = $true }
        }
    })

# ------------------------------------------------------------------------------ modo captura (pruebas)

function Save-Captura {
    param([Windows.FrameworkElement]$Elemento, [string]$Nombre)
    $Elemento.UpdateLayout()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$Elemento.ActualWidth, [int]$Elemento.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($Elemento)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $Captura "$Nombre.png"))
    try { $enc.Save($fs) } finally { $fs.Close() }
}

if ($Captura) {
    $null = [IO.Directory]::CreateDirectory($Captura)
    $clic = { param($b) $script:Ui[$b].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
    $colaCaptura = New-Object System.Collections.Generic.Queue[object]
    $paso = { param([double]$Espera, [scriptblock]$Accion, [scriptblock]$Hasta) $colaCaptura.Enqueue(@{ Espera = $Espera; Accion = $Accion; Hasta = $Hasta }) }
    if ($Escenario) { . $Escenario } else {
    & $paso 1 { Save-Captura $script:Win.Content '01_inicio_vacio' }
    & $paso 0.5 { $script:Ui.tgCalor.IsChecked = $true; $script:Ui.tgLento.IsChecked = $true }
    & $paso 0.5 { Save-Captura $script:Win.Content '02_inicio_motivos' }
    & $paso 0.3 { Show-Panel 'pnlFicha'; $script:Ui.txtNombre.Text = 'Cliente de prueba'; $script:Ui.txtContacto.Text = 'llamar tarde'; & $clic 'btnGuardarFicha' }
    & $paso 0.5 { Save-Captura $script:Win.Content '03_ficha_error' }
    & $paso 0.3 { $script:Ui.txtContacto.Text = '+56 9 1234 5678'; $script:Ui.txtSintoma.Text = 'Se calienta jugando'; $script:G.Chk['teclado'].SelectedIndex = 1; & $clic 'btnGuardarFicha' }
    & $paso 0.5 { Save-Captura $script:Win.Content '04_ficha_guardada' }
    if ($CapturaDiag) {
        & $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion'; & $clic 'btnDiagnosticar' }
        & $paso 6 { Save-Captura $script:Win.Content '05_antes_en_curso'; $script:G.Registro.Add("ventana viva durante el diagnóstico: $(Get-Date -Format HH:mm:ss)") }
        & $paso 1 { Save-Captura $script:Win.Content '06_antes_listo' } { -not $script:G.Tarea }
        # Cancelar a mitad: la medición anterior tiene que quedar intacta.
        & $paso 0.5 { $script:G.Previa = (Get-Item (Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'antes\diagnostico.json')).LastWriteTime; & $clic 'btnDiagnosticar' }
        & $paso 3 { Invoke-CancelarTarea }
        & $paso 1 {
            $carpeta = Join-Path $script:G.Exp.Ruta $script:G.At
            $intacta = (Get-Item (Join-Path $carpeta 'antes\diagnostico.json')).LastWriteTime -eq $script:G.Previa
            $script:G.Registro.Add("tras cancelar: antes intacto=$intacta | en_curso=$(Test-Path (Join-Path $carpeta 'antes_en_curso')) | estado='$($script:Ui.txtMedicionEstado.Text)'")
            Save-Captura $script:Win.Content '06b_cancelado'
        } { -not $script:G.Tarea }
    } else {
        & $paso 0.3 { $script:G.Momento = 'antes'; Show-Panel 'pnlMedicion' }
        & $paso 0.5 { Save-Captura $script:Win.Content '05_antes' }
    }
    & $paso 0.3 { Show-Panel 'pnlTrabajo'; & $clic 'btnBuscarAcciones' }
    & $paso 0.8 { Save-Captura $script:Win.Content '07_trabajo' }
    & $paso 0.3 { Show-Panel 'pnlInforme' }
    & $paso 0.5 { Save-Captura $script:Win.Content '08_informe' }
    & $paso 0.3 { Show-Panel 'pnlTecnico' }
    & $paso 0.5 { Save-Captura $script:Win.Content '09_tecnico' }
    & $paso 0.3 { Show-Panel 'pnlHerramientas' }
    & $paso 0.5 { Save-Captura $script:Win.Content '10_herramientas' }
    & $paso 0.3 { Show-VistaCliente }
    & $paso 1 { Save-Captura $script:G.VentanaCliente.Content '11_mostrar_cliente'; $script:G.VentanaCliente.Close() }
    if ($RutaMaestro) {
        # Sincronizar liberando el USB, abrir un expediente del maestro en consulta, regenerar sus informes y volver.
        $leer = { param($t) $script:G.Registro.Add($t) }
        & $paso 0.3 { Show-Panel 'pnlExpedientes' }
        & $paso 0.8 { Save-Captura $script:Win.Content '12_expedientes_usb'; & $leer "lista USB: $($script:G.TablaExp.Rows.Count) expedientes | grpSincronizar=$($script:Ui.grpSincronizar.Visibility)" }
        & $paso 0.3 { $script:Ui.chkLiberarUsb.IsChecked = $true; & $clic 'btnSincronizar' }
        & $paso 1 { Save-Captura $script:Win.Content '13_sincronizado' } { -not $script:G.Tarea }
        & $paso 0.3 { $script:Ui.rbFuenteMaestro.IsChecked = $true; $script:Ui.txtBuscarExp.Text = 'Nitro' }
        & $paso 0.8 {
            & $leer "lista maestro filtrada 'Nitro': $($script:G.TablaExp.DefaultView.Count) de $($script:G.TablaExp.Rows.Count) | atenciones en el combo: $($script:Ui.cmbAtencionExp.Items.Count)"
            Save-Captura $script:Win.Content '14_expedientes_maestro'
        }
        & $paso 0.3 {
            $primera = @($script:Ui.cmbAtencionExp.Items | Where-Object { $_.IsEnabled }) | Select-Object -First 1
            $script:Ui.cmbAtencionExp.SelectedItem = $primera
            & $clic 'btnAbrirExp'
        }
        & $paso 0.8 {
            & $leer "consulta: ajeno=$($script:G.Ajeno) origen=$($script:G.Origen) at=$($script:G.At) | nav antes=$($script:Ui.navAntes.IsEnabled) trabajo=$($script:Ui.navTrabajo.IsEnabled) despues=$($script:Ui.navDespues.IsEnabled) informe=$($script:Ui.navInforme.IsEnabled) | volver=$($script:Ui.btnVolverEquipo.Visibility)"
            Save-Captura $script:Win.Content '15_consulta_maestro'
        }
        & $paso 0.3 {
            $script:G.InformePrevio = Join-Path (Join-Path $script:G.Exp.Ruta $script:G.At) 'informe_cliente.html'
            $script:G.InformeAntes = if ([IO.File]::Exists($script:G.InformePrevio)) { (Get-Item -LiteralPath $script:G.InformePrevio).LastWriteTime } else { $null }
            Show-Panel 'pnlInforme'; & $clic 'btnGenerar'
        }
        & $paso 1 {
            $despues = if ([IO.File]::Exists($script:G.InformePrevio)) { (Get-Item -LiteralPath $script:G.InformePrevio).LastWriteTime } else { $null }
            & $leer "informe regenerado en el maestro: $([bool]($despues -and $despues -ne $script:G.InformeAntes)) ($($script:G.InformePrevio)) | estado='$($script:Ui.txtEstado.Text)'"
            Save-Captura $script:Win.Content '16_informe_maestro'
        } { -not $script:G.Tarea }
        & $paso 0.3 { & $clic 'btnVolverEquipo' }
        & $paso 0.8 {
            & $leer "vuelta: ajeno=$($script:G.Ajeno) exp=$(if ($script:G.Exp) { $script:G.Exp.Ruta }) at=$($script:G.At) | equipo='$($script:Ui.txtEquipo.Text)'"
            Save-Captura $script:Win.Content '17_vuelta_equipo'
        }
    }
    }
    & $paso 0.3 { [IO.File]::WriteAllLines((Join-Path $Captura 'registro.txt'), $script:G.Registro); $script:Win.Close() }
    $script:PasoActual = $null; $script:InicioPaso = Get-Date
    $tc = New-Object Windows.Threading.DispatcherTimer
    $tc.Interval = [TimeSpan]::FromMilliseconds(200)
    $tc.Add_Tick({
            if (-not $script:PasoActual) { if ($colaCaptura.Count -eq 0) { return }; $script:PasoActual = $colaCaptura.Dequeue(); $script:InicioPaso = Get-Date }
            $p = $script:PasoActual
            if (((Get-Date) - $script:InicioPaso).TotalSeconds -lt $p.Espera) { return }
            if ($p.Hasta -and -not (& $p.Hasta)) { return }
            $script:PasoActual = $null
            try { & $p.Accion } catch { $script:G.Registro.Add("error en paso: $($_.Exception.Message) ($($_.InvocationInfo.ScriptLineNumber))") }
        })
    $script:Win.Add_ContentRendered({ $tc.Start() })
}

if ($RutaExpediente) {
    try { Open-Expediente -Ruta $RutaExpediente -Carpeta $Atencion } catch { $script:G.Ajeno = $false; $script:G.Exp = $null; $script:G.Registro.Add("no se pudo abrir $RutaExpediente : $($_.Exception.Message)") }
}
Show-Estado
Show-Panel 'pnlInicio'
[void]$script:Win.ShowDialog()
exit 0
