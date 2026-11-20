#Requires -Version 5.1
<#
.SYNOPSIS
    Ventana de bienvenida del paquete de Isaac: se abre ANTES de pedir administrador.
.DESCRIPTION
    Comprueba la firma de Isaac sobre todos los archivos del paquete (motor\manifiesto.json) y muestra el
    código de Isaac, qué va a pasar y qué no se toca. Solo con el paquete verificado aparece "Empezar", que
    vuelve a abrir el .cmd con /admin y permiso de administrador. Si no hay ventanas (WPF bloqueado), lo mismo
    en la consola. -Captura <png> guarda una foto de la ventana y sale (pruebas).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Consola para el cliente')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Los parámetros de los manejadores de eventos los exige WPF')]
[CmdletBinding()]
param(
    [ValidateSet('Diagnostico', 'Trabajo')][string]$Modo = 'Diagnostico',
    [string]$Captura
)
$ErrorActionPreference = 'Stop'
$motor = $PSScriptRoot
$raiz = Split-Path -Parent $motor
. (Join-Path $motor 'Cifrado.ps1')
$cmd = Join-Path $raiz $(if ($Modo -eq 'Trabajo') { 'TRABAJO.cmd' } else { 'DIAGNOSTICO.cmd' })
$v = Test-ManifiestoPaquete -Raiz $raiz

$titulo = if ($Modo -eq 'Trabajo') { 'Trabajo de Isaac en tu computador' } else { 'Diagnóstico para Isaac' }
$intro = if ($Modo -eq 'Trabajo') { 'Isaac preparó cambios para que tu computador ande más rápido. En la ventana siguiente ves cada cambio y decides si aplicarlos. Después se reinicia y se mide cómo quedó.' }
else { 'Revisa cómo está tu computador y prueba su temperatura con carga, para que Isaac sepa qué tiene antes de proponerte algo.' }
$hace = if ($Modo -eq 'Trabajo') { @('Muestra los cambios y espera que escribas SI.', 'Crea un punto de restauración de Windows antes de cambiar nada.', 'Todo se puede deshacer con DESHACER.cmd.') }
else { @('Lee cómo está el equipo: disco, memoria, batería, temperatura, inicio de Windows.', 'Abre dos programas de prueba (HWiNFO y OCCT): no los toques.', 'Al final deja un archivo cifrado para Isaac y te abre tu informe.') }
$noHace = @('No instala programas.', 'No mira tus documentos, fotos, contraseñas ni historial.', 'No usa internet: el archivo lo mandas tú.')
$duracion = if ($Modo -eq 'Trabajo') { 'Unos 10 minutos y un reinicio.' } else { 'Unos 20 minutos. Si es notebook, déjalo enchufado.' }

function Start-PaqueteAdmin {
    # Vuelve a abrir el .cmd con permiso de administrador. $false si la persona dijo que no al permiso.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param()
    if (-not $PSCmdlet.ShouldProcess($cmd, 'Abrir con administrador')) { return $false }
    try { Start-Process -FilePath $cmd -ArgumentList '/admin' -Verb RunAs -WorkingDirectory $raiz; $true } catch { $false }
}

function Show-Consola {
    Write-Host ''
    Write-Host " $($titulo.ToUpper())" -ForegroundColor Cyan
    if ($v.Ok) {
        Write-Host ' Paquete verificado: es de Isaac y nadie lo cambió.' -ForegroundColor Green
        Write-Host " Código de Isaac: ISAAC · $($v.Codigo)   (compáralo con el que te mandó Isaac)" -ForegroundColor Green
    } else {
        Write-Host ' ESTE PAQUETE NO ES DE ISAAC O FUE MODIFICADO. No lo abras y avísale.' -ForegroundColor Red
        Write-Host " $($v.Motivo)" -ForegroundColor Red
        return
    }
    Write-Host " $intro"
    Write-Host " $duracion" -ForegroundColor Yellow
    $r = Read-Host ' Escribe SI y Enter para empezar (Windows te pedirá permiso de administrador)'
    if ("$r".Trim() -match '^(?i)s[ií]$') { if (-not (Start-PaqueteAdmin)) { Write-Host ' No se dio el permiso. Puedes volver a abrirlo cuando quieras.' -ForegroundColor Yellow } }
}

$wpf = $ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage' -and [Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'
if ($wpf) { try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase } catch { $wpf = $false } }
if (-not $wpf) { Show-Consola; exit $(if ($v.Ok) { 0 } else { 3 }) }

function ConvertTo-TextoXaml([string]$s) { [Security.SecurityElement]::Escape($s) }
$lista = { param($items, $color) ($items | ForEach-Object { "<DockPanel Margin='0,3,0,0'><TextBlock Text='$(if ($color -eq '#10B981') { '✓' } else { '✕' })' Foreground='$color' FontWeight='Bold' Width='18'/><TextBlock Text='$(ConvertTo-TextoXaml $_)' TextWrapping='Wrap' Foreground='#334155'/></DockPanel>" }) -join '' }
$okColor = if ($v.Ok) { '#10B981' } else { '#E5484D' }
$okFondo = if ($v.Ok) { '#ECFDF5' } else { '#FEF2F2' }
$okTitulo = if ($v.Ok) { 'Paquete verificado: es de Isaac y nadie lo cambió' } else { 'Este paquete NO es de Isaac o fue modificado' }
$okTexto = if ($v.Ok) { 'Compara este código con el que te mandó Isaac por WhatsApp. Si es el mismo, puedes seguir tranquilo.' } else { "No lo abras y avísale a Isaac. $($v.Motivo)" }
$codigoTxt = if ($v.Codigo) { "ISAAC · $($v.Codigo)" } else { 'sin código' }

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$(ConvertTo-TextoXaml $titulo)" Width="760" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Background="#F8FAFC" FontFamily="Segoe UI" FontSize="14">
  <Border Margin="18" Padding="26,22" Background="White" CornerRadius="22" BorderBrush="#E2E8F0" BorderThickness="1">
    <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="6" Opacity="0.10"/></Border.Effect>
    <StackPanel>
      <DockPanel>
        <Viewbox x:Name="vbLogo" Width="76" Height="55" Margin="0,0,16,0" VerticalAlignment="Center">
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
          <TextBlock Text="ISAAC · SERVICIO TÉCNICO" FontSize="11" FontWeight="Bold" Foreground="#6366F1"/>
          <TextBlock Text="$(ConvertTo-TextoXaml $titulo)" FontSize="26" FontWeight="SemiBold" Foreground="#0F172A"/>
        </StackPanel>
      </DockPanel>
      <TextBlock Text="$(ConvertTo-TextoXaml $intro)" TextWrapping="Wrap" Foreground="#475569" Margin="0,14,0,0"/>
      <Border Margin="0,16,0,0" Padding="16,12" CornerRadius="14" Background="$okFondo" BorderBrush="$okColor" BorderThickness="1.5">
        <DockPanel>
          <Border x:Name="bdCodigo" DockPanel.Dock="Right" Padding="14,8" CornerRadius="10" Background="#0F172A" VerticalAlignment="Center" Margin="12,0,0,0">
            <TextBlock x:Name="txtCodigo" Text="$(ConvertTo-TextoXaml $codigoTxt)" FontFamily="Cascadia Mono, Consolas" FontSize="17" FontWeight="Bold" Foreground="#5EEAD4"/>
          </Border>
          <StackPanel>
            <TextBlock Text="$(if ($v.Ok) { '✓ ' } else { '✕ ' })$(ConvertTo-TextoXaml $okTitulo)" FontWeight="Bold" Foreground="$okColor" TextWrapping="Wrap"/>
            <TextBlock Text="$(ConvertTo-TextoXaml $okTexto)" TextWrapping="Wrap" Foreground="#334155" FontSize="12.5" Margin="0,3,0,0"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Margin="0,16,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="18"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0"><TextBlock Text="QUÉ HACE" FontSize="11" FontWeight="Bold" Foreground="#64748B"/>$(& $lista $hace '#10B981')</StackPanel>
        <StackPanel Grid.Column="2"><TextBlock Text="QUÉ NO HACE" FontSize="11" FontWeight="Bold" Foreground="#64748B"/>$(& $lista $noHace '#E5484D')</StackPanel>
      </Grid>
      <TextBlock Text="⏱  $(ConvertTo-TextoXaml $duracion)" Foreground="#B45309" FontWeight="SemiBold" Margin="0,16,0,0"/>
      <DockPanel Margin="0,18,0,0" LastChildFill="False">
        <Button x:Name="btnCerrar" DockPanel.Dock="Right" Content="Cerrar" Padding="22,9" Margin="10,0,0,0" Background="White" BorderBrush="#CBD5E1"/>
        <Button x:Name="btnEmpezar" DockPanel.Dock="Right" Content="Empezar  ▶" Padding="26,9" FontWeight="Bold" Foreground="White" BorderThickness="0">
          <Button.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#06B6D4" Offset="0"/><GradientStop Color="#7C3AED" Offset="1"/></LinearGradientBrush></Button.Background>
        </Button>
        <TextBlock x:Name="txtNota" DockPanel.Dock="Left" VerticalAlignment="Center" TextWrapping="Wrap" MaxWidth="380" FontSize="12" Foreground="#64748B"
                   Text="Al apretar Empezar, Windows te pide permiso de administrador: es normal."/>
      </DockPanel>
    </StackPanel>
  </Border>
</Window>
"@

$w = [Windows.Markup.XamlReader]::Parse($xaml)
$btnEmpezar = $w.FindName('btnEmpezar')
$txtNota = $w.FindName('txtNota')
if (-not $v.Ok) { $btnEmpezar.Visibility = 'Collapsed'; $w.FindName('bdCodigo').Visibility = 'Collapsed'; $txtNota.Text = 'Por seguridad no se puede empezar.' }
$btnEmpezar.Add_Click({
        if (Start-PaqueteAdmin) { $w.Close() }
        else { $txtNota.Text = 'No se dio el permiso de administrador. Puedes volver a apretar Empezar.'; $txtNota.Foreground = '#B45309' }
    })
$w.FindName('btnCerrar').Add_Click({ $w.Close() })
$w.Add_ContentRendered({
        try {
            $logo = $w.FindName('vbLogo')
            $dv = New-Object Windows.Media.DrawingVisual
            $dc = $dv.RenderOpen()
            $dc.DrawRectangle((New-Object Windows.Media.VisualBrush $logo), $null, (New-Object Windows.Rect 0, 9, 64, 46))
            $dc.Close()
            $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap 64, 64, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
            $bmp.Render($dv)
            $w.Icon = $bmp
        } catch { Write-Verbose $_ }
    })
if ($Captura) {
    $w.Add_ContentRendered({
            $w.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::Background)
            $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$w.ActualWidth), ([int]$w.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
            $rtb.Render($w.Content)
            $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [IO.File]::Create($Captura); $enc.Save($fs); $fs.Close()
            $w.Close()
        })
}
[void]$w.ShowDialog()
exit $(if ($v.Ok) { 0 } else { 3 })
