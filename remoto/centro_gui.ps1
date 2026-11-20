#Requires -Version 5.1
<#
.SYNOPSIS
    Centro remoto con ventana (estilo consola de DJ): abrir lo que llegó, armar trabajos con casillas y envíos.
.DESCRIPTION
    Deck A "LLEGÓ": los .kitdiag nuevos del pendrive, Descargas y Escritorio; ABRIR los abre con su informe.
    Deck B "TRABAJO": un diagnóstico ya abierto y sus acciones de LENTO con casillas (ninguna marcada);
    ARMAR deja el paquete en remoto\_salida y lo copia a PARA_ENVIAR del pendrive.
    Abajo: Para enviar, Remotos y Rearmar el diagnóstico. Los trabajos largos corren en otro proceso.
    Necesita -STA (CENTRO.cmd lo lanza así). -Captura <png> guarda una foto de la ventana y sale (pruebas).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'WPF viene con .NET Framework y se carga con Add-Type -AssemblyName')]
[CmdletBinding()]
param([string]$Captura)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$aqui = $PSScriptRoot
$scripts = Join-Path (Split-Path -Parent $aqui) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
. (Join-Path $scripts 'motivos\lento.ps1')
Initialize-Contexto -RaizScripts $scripts
$ps = Join-Path $PSHOME 'powershell.exe'

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Centro remoto - KIT SERVICIO" Width="1040" Height="660" WindowStartupLocation="CenterScreen" Background="#0B1124" FontFamily="Segoe UI">
  <Window.Resources>
    <LinearGradientBrush x:Key="Peligro" StartPoint="0,0" EndPoint="18,18" MappingMode="Absolute" SpreadMethod="Repeat">
      <GradientStop Color="#F5C400" Offset="0"/><GradientStop Color="#F5C400" Offset="0.5"/><GradientStop Color="#111111" Offset="0.5"/><GradientStop Color="#111111" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="Panel" StartPoint="0,0" EndPoint="0,1">
      <GradientStop Color="#22305A" Offset="0"/><GradientStop Color="#141D3A" Offset="1"/>
    </LinearGradientBrush>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#0B1124"/><Setter Property="FontWeight" Value="Black"/><Setter Property="FontSize" Value="15"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="4"/><Setter Property="Height" Value="44"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="22" BorderBrush="#0B1124" BorderThickness="3" Padding="18,0">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#FFE14D" Offset="0"/><GradientStop Color="#E0A800" Offset="1"/></LinearGradientBrush></Border.Background>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#4FD1FF"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Titulo" TargetType="TextBlock"><Setter Property="Foreground" Value="#F5C400"/><Setter Property="FontWeight" Value="Black"/><Setter Property="FontSize" Value="20"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="Foreground" Value="#8FA3D6"/><Setter Property="FontSize" Value="12"/></Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Height="14" Background="{StaticResource Peligro}"/>
    <Border DockPanel.Dock="Bottom" Height="14" Background="{StaticResource Peligro}"/>
    <Border DockPanel.Dock="Bottom" Background="#070B18" Padding="14,6">
      <TextBlock x:Name="txtEstado" Foreground="#4FD1FF" FontFamily="Consolas" FontSize="13" Text="Listo."/>
    </Border>
    <Grid Margin="16,10,16,8">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <DockPanel Grid.Row="0" Margin="4,0,4,10">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <StackPanel x:Name="vu" Orientation="Horizontal" VerticalAlignment="Bottom" Height="34" Margin="0,0,22,0"/>
          <Ellipse x:Name="ledPen" Width="16" Height="16" Fill="#555" Stroke="#0B1124" StrokeThickness="2" Margin="0,0,8,0"/>
          <TextBlock x:Name="txtPen" Foreground="#C9D6FF" FontSize="13" VerticalAlignment="Center" Text="Pendrive"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal">
          <Viewbox x:Name="vbLogo" Width="62" Height="45" Margin="0,0,12,0" VerticalAlignment="Center" ToolTip="KIT SERVICIO">
          <Canvas Width="64" Height="46">
            <Canvas.RenderTransform><TranslateTransform Y="-8"/></Canvas.RenderTransform>
            <Path Data="M3,38 A29,7.5 0 0 1 61,38" StrokeThickness="2" Opacity="0.38">
              <Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#06B6D4" Offset="0"/><GradientStop Color="#7C3AED" Offset="1"/></LinearGradientBrush></Path.Stroke>
            </Path>
            <Path Data="M10,38 A22,22 0 0 1 54,38 Z" Stroke="#64748B" StrokeThickness="1">
              <Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FFFFFF" Offset="0"/><GradientStop Color="#B8C4D4" Offset="1"/></LinearGradientBrush></Path.Fill>
            </Path>
            <Path Stroke="#94A3B8" StrokeThickness="0.8" StrokeLineJoin="Round" Clip="M10,38 A22,22 0 0 1 54,38 Z"
                  Data="M10,38 L21,27 L32,38 L43,27 L54,38 M13,27 L51,27 M32,27 L32,38 M21,27 L27,18 L32,27 L37,18 L43,27 M27,18 L37,18 M27,18 L16,23 M37,18 L48,23 M27,18 L32,15 L37,18"/>
            <Path Data="M3,38 A29,7.5 0 0 0 61,38" StrokeThickness="2.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
              <Path.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#06B6D4" Offset="0"/><GradientStop Color="#7C3AED" Offset="1"/></LinearGradientBrush></Path.Stroke>
            </Path>
            <Ellipse Canvas.Left="55.3" Canvas.Top="39.3" Width="4.6" Height="4.6" Fill="#06B6D4" Stroke="White" StrokeThickness="1"/>
          </Canvas>
        </Viewbox>

          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="CENTRO REMOTO" Foreground="#FFFFFF" FontWeight="Black" FontSize="26"/>
            <TextBlock Text="KIT SERVICIO · lo que llega, lo que se arma y lo que se manda" Style="{StaticResource Sub}"/>
          </StackPanel>
        </StackPanel>
      </DockPanel>
      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="18"/><ColumnDefinition Width="1.25*"/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="{StaticResource Panel}" CornerRadius="16" BorderBrush="#3A4C8C" BorderThickness="2" Padding="14">
          <DockPanel>
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,8">
              <TextBlock Text="DECK A · LLEGÓ" Style="{StaticResource Titulo}"/>
              <TextBlock Text=".kitdiag del pendrive, Descargas y Escritorio" Style="{StaticResource Sub}"/>
            </StackPanel>
            <StackPanel DockPanel.Dock="Bottom">
              <CheckBox x:Name="chkVer" Content="Mostrar también los ya abiertos" Foreground="#8FA3D6" Margin="2,6,0,4"/>
              <Button x:Name="btnAbrir" Content="ABRIR  ▶"/>
            </StackPanel>
            <ListBox x:Name="lstLlego" Background="#0B1124" Foreground="#E8EEFF" BorderBrush="#3A4C8C" FontFamily="Consolas" FontSize="13"/>
          </DockPanel>
        </Border>
        <Border Grid.Column="2" Background="{StaticResource Panel}" CornerRadius="16" BorderBrush="#3A4C8C" BorderThickness="2" Padding="14">
          <DockPanel>
            <StackPanel DockPanel.Dock="Top" Margin="0,0,0,8">
              <TextBlock Text="DECK B · TRABAJO" Style="{StaticResource Titulo}"/>
              <TextBlock Text="Marca lo que se aplica (amarillo = confírmalo con el cliente)" Style="{StaticResource Sub}"/>
              <ComboBox x:Name="cmbDiag" Margin="0,8,0,0" FontSize="13"/>
            </StackPanel>
            <Button x:Name="btnArmar" DockPanel.Dock="Bottom" Content="ARMAR TRABAJO  ▶  PENDRIVE"/>
            <Border Background="#0B1124" BorderBrush="#3A4C8C" BorderThickness="1" CornerRadius="6">
              <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="pnlAcciones" Margin="8"/></ScrollViewer>
            </Border>
          </DockPanel>
        </Border>
      </Grid>
      <UniformGrid Grid.Row="2" Columns="4" Margin="0,12,0,0">
        <Button x:Name="btnCodigo" Content="CÓDIGO CLIENTE"/>
        <Button x:Name="btnEnviar" Content="PARA ENVIAR"/>
        <Button x:Name="btnRemotos" Content="REMOTOS"/>
        <Button x:Name="btnRearmar" Content="REARMAR DIAGNÓSTICO"/>
      </UniformGrid>
    </Grid>
  </DockPanel>
</Window>
'@

function Initialize-IconoVentana {
    # Ícono de la ventana y de la barra de tareas: el logo vectorial (vbLogo) pasado a imagen, sin archivos aparte.
    param($Ventana)
    try {
        $logo = $Ventana.FindName('vbLogo')
        if (-not $logo) { return }
        $dv = New-Object Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.DrawRectangle((New-Object Windows.Media.VisualBrush $logo), $null, (New-Object Windows.Rect 0, 9, 64, 46))
        $dc.Close()
        $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap 64, 64, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($dv)
        $Ventana.Icon = $bmp
    } catch { Write-Verbose $_ }
}

$w = [Windows.Markup.XamlReader]::Parse($xaml)
$w.Add_ContentRendered({ Initialize-IconoVentana -Ventana $w })
$ui = @{}
foreach ($n in 'vu', 'txtEstado', 'ledPen', 'txtPen', 'chkVer', 'btnAbrir', 'lstLlego', 'cmbDiag', 'btnArmar', 'pnlAcciones', 'btnEnviar', 'btnRemotos', 'btnRearmar', 'btnCodigo') { $ui[$n] = $w.FindName($n) }
$script:Proc = $null
$script:AlTerminar = $null
$script:Acciones = @()

function Get-Pendrive {
    $repo = [IO.Path]::GetPathRoot($aqui)
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady -or $d.RootDirectory.FullName -eq $repo) { continue }
        if ([IO.File]::Exists((Join-Path $d.RootDirectory.FullName 'KIT\INICIAR.cmd'))) { return $d.RootDirectory.FullName }
    }
    $null
}
function Get-CarpetaRemotos {
    $m = "$($script:Ctx.Config.sincronizacion.ruta_maestro)"
    if ($m -and [IO.Directory]::Exists((Split-Path -Parent $m))) { return Join-Path (Split-Path -Parent $m) 'remotos' }
    $null
}
function Show-Estado([string]$Texto) { $ui.txtEstado.Text = $Texto }
function Switch-Ocupado([bool]$Si) { foreach ($b in 'btnAbrir', 'btnArmar', 'btnEnviar', 'btnRearmar') { $ui[$b].IsEnabled = -not $Si } }

function Show-Llego {
    $rem = Get-CarpetaRemotos
    $pen = Get-Pendrive
    $ui.ledPen.Fill = if ($pen) { '#3DDC84' } else { '#E5484D' }
    $ui.txtPen.Text = if ($pen) { "Pendrive en $pen" } else { 'Pendrive no conectado' }
    $ui.lstLlego.Items.Clear()
    $vistos = @{}
    $items = foreach ($l in @($pen, [Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'))) {
        if (-not $l -or -not [IO.Directory]::Exists($l)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $l -Filter '*.kitdiag' -File -ErrorAction SilentlyContinue)) {
            if ($vistos.ContainsKey($f.Name)) { continue }
            $vistos[$f.Name] = $true
            $abierto = $rem -and [IO.Directory]::Exists((Join-Path $rem $f.BaseName))
            if ($abierto -and -not $ui.chkVer.IsChecked) { continue }
            [pscustomobject]@{ Archivo = $f.FullName; Fecha = $f.LastWriteTime; Texto = ('{0:dd-MM HH:mm}  {1}{2}' -f $f.LastWriteTime, $f.Name, $(if ($abierto) { '  ✓' } else { '' })) }
        }
    }
    foreach ($i in @($items | Sort-Object Fecha -Descending)) {
        $li = New-Object Windows.Controls.ListBoxItem
        $li.Content = $i.Texto; $li.Tag = $i.Archivo; $li.Padding = '4,6,4,6'
        [void]$ui.lstLlego.Items.Add($li)
    }
    if ($ui.lstLlego.Items.Count) { $ui.lstLlego.SelectedIndex = 0 } else {
        $li = New-Object Windows.Controls.ListBoxItem; $li.Content = '(nada nuevo por ahora)'; $li.IsEnabled = $false; [void]$ui.lstLlego.Items.Add($li)
    }
}

function Show-Diagnosticos {
    $rem = Get-CarpetaRemotos
    $ui.cmbDiag.Items.Clear()
    if (-not $rem -or -not [IO.Directory]::Exists($rem)) { return }
    foreach ($d in @(Get-ChildItem -LiteralPath $rem -Directory -Filter 'Diagnostico_para_Isaac_*' | Sort-Object LastWriteTime -Descending | Select-Object -First 15)) {
        $ci = New-Object Windows.Controls.ComboBoxItem; $ci.Content = $d.Name; $ci.Tag = $d.FullName
        [void]$ui.cmbDiag.Items.Add($ci)
    }
    if ($ui.cmbDiag.Items.Count) { $ui.cmbDiag.SelectedIndex = 0 }
}

function Show-Acciones {
    $ui.pnlAcciones.Children.Clear()
    $script:Acciones = @()
    $sel = $ui.cmbDiag.SelectedItem
    if (-not $sel) { return }
    try {
        $clientes = Join-Path $sel.Tag 'diagnostico'
        $json = @(Get-ChildItem -LiteralPath $clientes -Recurse -Filter diagnostico.json | Where-Object { $_.Directory.Name -eq 'antes' }) | Select-Object -First 1
        $script:Ctx.CarpetaClientes = $clientes
        $exp = Read-Expediente $json.Directory.Parent.Parent.FullName
        $script:Acciones = @(Get-AccionesLento -Expediente $exp -Atencion $json.Directory.Parent.Name | Where-Object { $_.Tipo -ne 'manual' })
    } catch { Show-Estado "No se pudieron leer las acciones: $($_.Exception.Message)"; return }
    for ($i = 0; $i -lt $script:Acciones.Count; $i++) {
        $a = $script:Acciones[$i]
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Tag = $i + 1; $cb.Margin = '0,4,0,4'; $cb.FontSize = 13
        $cb.Foreground = if ($a.Riesgo -eq 'revisar') { '#F5C400' } else { '#E8EEFF' }
        $cb.Content = $a.Titulo + $(if ($a.RequiereAdmin) { '  [admin]' } else { '' })
        $cb.ToolTip = "$($a.QueHace)`nDeshacer: $($a.Deshacer)"
        [void]$ui.pnlAcciones.Children.Add($cb)
    }
    if (-not $script:Acciones.Count) { $t = New-Object Windows.Controls.TextBlock; $t.Text = 'Este equipo no tiene acciones que aplicar a distancia.'; $t.Foreground = '#8FA3D6'; [void]$ui.pnlAcciones.Children.Add($t) }
}

function Invoke-Proceso {
    # Corre un script en otro proceso (la ventana no se congela) y al terminar llama a $Despues con el código.
    param([string]$Texto, [string[]]$Argumentos, [scriptblock]$Despues, [switch]$Visible)
    Switch-Ocupado $true
    Show-Estado "$Texto..."
    $script:AlTerminar = $Despues
    $estilo = if ($Visible) { 'Normal' } else { 'Hidden' }
    $script:Proc = Start-Process -FilePath $ps -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass') + $Argumentos) -WindowStyle $estilo -PassThru
}

# Vúmetro: 16 barras; se mueven mientras corre un trabajo y quedan bajitas en reposo.
$script:Barras = @()
$azar = New-Object Random
for ($i = 0; $i -lt 16; $i++) {
    $r = New-Object Windows.Shapes.Rectangle
    $r.Width = 6; $r.Height = 4; $r.Margin = '1,0,1,0'; $r.VerticalAlignment = 'Bottom'; $r.RadiusX = 1; $r.RadiusY = 1
    $r.Fill = if ($i -lt 10) { '#3DDC84' } elseif ($i -lt 14) { '#F5C400' } else { '#E5484D' }
    [void]$ui.vu.Children.Add($r); $script:Barras += $r
}
$vuReloj = New-Object Windows.Threading.DispatcherTimer
$vuReloj.Interval = [TimeSpan]::FromMilliseconds(110)
$vuReloj.Add_Tick({
        $activo = [bool]$script:Proc
        for ($i = 0; $i -lt $script:Barras.Count; $i++) {
            $alto = if ($activo) { 6 + $azar.Next(0, 28) * (1 - [math]::Abs($i - 7.5) / 12) } else { 4 }
            $script:Barras[$i].Height = [math]::Max(4, $alto)
        }
    })
$vuReloj.Start()

$reloj = New-Object Windows.Threading.DispatcherTimer
$reloj.Interval = [TimeSpan]::FromMilliseconds(700)
$reloj.Add_Tick({
        if ($script:Proc -and $script:Proc.HasExited) {
            $cod = $script:Proc.ExitCode; $script:Proc = $null
            Switch-Ocupado $false
            if ($script:AlTerminar) { & $script:AlTerminar $cod }
        }
    })
$reloj.Start()

$ui.chkVer.Add_Click({ Show-Llego })
$ui.cmbDiag.Add_SelectionChanged({ Show-Acciones })
$ui.btnAbrir.Add_Click({
        $sel = $ui.lstLlego.SelectedItem
        if (-not $sel -or -not $sel.Tag) { Show-Estado 'Elige un .kitdiag de la lista.'; return }
        Invoke-Proceso -Texto "Abriendo $(Split-Path -Leaf $sel.Tag) (descifrar y armar el informe)" -Argumentos @('-File', (Join-Path $aqui 'abrir_diagnostico.ps1'), '-Archivo', $sel.Tag) -Despues {
            param($c)
            Show-Estado $(if ($c -eq 0) { 'Abierto: se abren el informe y la hoja técnica.' } else { "Algo falló al abrir (código $c)." })
            Show-Llego; Show-Diagnosticos
        }
    })
$ui.btnArmar.Add_Click({
        $sel = $ui.cmbDiag.SelectedItem
        $marcadas = @($ui.pnlAcciones.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.IsChecked } | ForEach-Object { $_.Tag })
        if (-not $sel -or -not $marcadas.Count) { Show-Estado 'Marca al menos una acción.'; return }
        $script:ZipsAntes = @(Get-ChildItem -LiteralPath (Join-Path $aqui '_salida') -Filter 'Trabajo_*.zip' -ErrorAction SilentlyContinue | ForEach-Object FullName)
        Invoke-Proceso -Texto "Armando el trabajo con $($marcadas.Count) acciones" -Argumentos @('-File', (Join-Path $aqui 'armar_trabajo.ps1'), '-Carpeta', $sel.Tag, '-Elegir', ($marcadas -join ',')) -Despues {
            param($c)
            $zip = @(Get-ChildItem -LiteralPath (Join-Path $aqui '_salida') -Filter 'Trabajo_*.zip' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $script:ZipsAntes } | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
            if ($c -ne 0 -or -not $zip) { Show-Estado "No se armó el trabajo (código $c)."; return }
            $pen = Get-Pendrive
            if ($pen) {
                $dest = Join-Path $pen 'PARA_ENVIAR'; $null = [IO.Directory]::CreateDirectory($dest)
                Copy-Item -LiteralPath $zip.FullName -Destination $dest -Force
                Show-Estado "Listo: $($zip.Name) copiado a $dest"
            } else { Show-Estado "Listo: $($zip.FullName) (conecta el pendrive para llevarlo)" }
        }
    })
$ui.btnCodigo.Add_Click({
        # Código para un cliente: lo pide la ventana del diagnóstico a distancia. El mensaje queda copiado.
        Add-Type -AssemblyName Microsoft.VisualBasic
        $nombre = [Microsoft.VisualBasic.Interaction]::InputBox('Nombre del cliente (para reconocerlo: Beli, JuanPerez):', 'Código para un cliente', '')
        if (-not "$nombre".Trim()) { return }
        try {
            $r = & (Join-Path $aqui 'codigo_cliente.ps1') -Nombre $nombre -PassThru
            Show-Estado "Código $($r.Codigo) (vence el $($r.Vence.ToString('dd-MM'))): mensaje copiado, pégalo en WhatsApp."
            [void][Windows.MessageBox]::Show($w, "$($r.Mensaje)`r`n`r`n(Ya está copiado: pégalo en WhatsApp.)", "Código $($r.Codigo)")
        } catch { Show-Estado "No se pudo crear el código: $($_.Exception.Message)" }
    })
$ui.btnEnviar.Add_Click({
        $pe = Join-Path $aqui '_salida\Para_enviar'
        if ([IO.Directory]::Exists($pe)) { Start-Process explorer.exe -ArgumentList "`"$pe`""; return }
        Invoke-Proceso -Texto 'Armando Para enviar' -Argumentos @('-File', (Join-Path $aqui 'armar_envios.ps1')) -Despues { Show-Estado 'Para enviar listo.'; Start-Process explorer.exe -ArgumentList "`"$(Join-Path $aqui '_salida\Para_enviar')`"" }
    })
$ui.btnRemotos.Add_Click({ $r = Get-CarpetaRemotos; if ($r) { $null = [IO.Directory]::CreateDirectory($r); Start-Process explorer.exe -ArgumentList "`"$r`"" } })
$ui.btnRearmar.Add_Click({
        Invoke-Proceso -Texto 'Rearmando el ZIP del diagnóstico (unos minutos)' -Argumentos @('-Command', "& '$(Join-Path $aqui 'armar_paquete.ps1')'; & '$(Join-Path $aqui 'armar_envios.ps1')'") -Despues {
            param($c)
            $zip = @(Get-ChildItem -LiteralPath (Join-Path $aqui '_salida') -Filter 'Diagnostico_remoto_*.zip' | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
            $pen = Get-Pendrive
            if ($zip -and $pen) {
                $dest = Join-Path $pen 'PARA_ENVIAR'; $null = [IO.Directory]::CreateDirectory($dest)
                Get-ChildItem -LiteralPath $dest -Filter 'Diagnostico_remoto_*.zip' | Where-Object Name -NE $zip.Name | Remove-Item -Force
                Copy-Item -LiteralPath $zip.FullName -Destination $dest -Force
                Show-Estado "Diagnóstico nuevo en $dest\$($zip.Name)"
            } else { Show-Estado "Diagnóstico rearmado (código $c)$(if (-not $pen) { '; conecta el pendrive para copiarlo' })." }
        }
    })

Show-Llego
Show-Diagnosticos
if ($Captura) {
    $w.Add_ContentRendered({
            $w.Dispatcher.Invoke([Action] {}, 'ApplicationIdle')
            $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$w.ActualWidth, [int]$w.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $rtb.Render($w)
            $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [IO.File]::Create($Captura); $enc.Save($fs); $fs.Close()
            $w.Close()
        })
}
[void]$w.ShowDialog()
