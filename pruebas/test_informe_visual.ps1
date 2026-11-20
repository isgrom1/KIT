#Requires -Version 5.1
<#
.SYNOPSIS
    Informe visual para el cliente (lib\InformeVisual.ps1): nombre del modelo, puntaje por área, recomendaciones,
    programas al inicio, papelera, gráficos SVG con números en formato invariante y el HTML completo.
.DESCRIPTION
    Todo con datos sintéticos (equipo inventado con la forma de diagnostico.json y un CSV de HWiNFO armado aquí).
    No lee el equipo. El PDF solo se prueba si hay Edge; si no, sale como OMITIDA.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Sensores', 'Mejoras', 'Informe', 'InformeVisual') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0; $script:omitidas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }

function New-DocPrueba {
    # Notebook sano por defecto. -LibrePct baja el espacio de C:, -Apagados agrega eventos, -Papelera pone GB en
    # la papelera de D: (como subcarpeta de usuario, nivel 2, que es como la deja el top de carpetas).
    param([double]$LibrePct = 60, [int]$Apagados = 0, [double]$Papelera = 0, [double]$Bateria = 95, [double]$ArranqueSeg = 35, [string]$SaludDisco = 'Healthy')
    $eventos = @(for ($i = 0; $i -lt $Apagados; $i++) { [pscustomobject]@{ Fecha = '2026-11-1{0} 10:00:00' -f $i; Tipo = 'Apagado inesperado (Kernel-Power 41)'; Detalle = '' } })
    $top = @([pscustomobject]@{ Unidad = 'D:'; Carpeta = 'D:\Juegos'; TamanoGB = 80.5; Nivel = 1 }, [pscustomobject]@{ Unidad = 'D:'; Carpeta = 'D:\Descargas\Instaladores'; TamanoGB = 40.2; Nivel = 2 })
    if ($Papelera -gt 0) { $top += [pscustomobject]@{ Unidad = 'D:'; Carpeta = 'D:\$RECYCLE.BIN\S-1-5-21-1'; TamanoGB = $Papelera; Nivel = 2 } }
    [pscustomobject]@{
        kit     = [pscustomobject]@{ generado = '2026-11-19 16:00:54'; version = 'prueba' }
        alertas = @()
        mejoras = @()
        datos   = [pscustomobject]@{
            equipo       = [pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Nitro AN515-43'; Familia = 'Nitro 5'; Tipo = 'Notebook'; NombreEquipo = 'PRUEBA'; Serie = 'SERIE-SECRETA-123' }
            hardware     = [pscustomobject]@{
                Cpu      = [pscustomobject]@{ Nombre = 'AMD Ryzen 5 3550H with Radeon Vega Mobile Gfx'; Nucleos = 4; Hilos = 8 }
                Ram      = [pscustomobject]@{ TotalGB = 16; CantidadModulos = 2; Slots = 2; Modulos = @([pscustomobject]@{ CapacidadGB = 8; Tipo = 'DDR4'; VelocidadMTs = 2400 }, [pscustomobject]@{ CapacidadGB = 8; Tipo = 'DDR4'; VelocidadMTs = 2400 }) }
                Gpu      = @([pscustomobject]@{ Nombre = 'NVIDIA GeForce GTX 1650'; VramGB = 4 })
                Discos   = @([pscustomobject]@{ Disco = 0; Modelo = 'SSD-1'; Tipo = 'SSD'; Bus = 'SATA'; TamanoGB = 224; Salud = $SaludDisco; DesgastePct = 0; Letras = 'C'; Sistema = $true; DelKit = $false; HorasEncendido = 4000 },
                    [pscustomobject]@{ Disco = 1; Modelo = 'HDD-1'; Tipo = 'HDD'; Bus = 'SATA'; TamanoGB = 932; Salud = 'Healthy'; DesgastePct = $null; Letras = 'D'; Sistema = $false; DelKit = $false })
                Baterias = @([pscustomobject]@{ Id = '0x41,0x50,0x31,0x38,0x45,0x38,0x4D'; Fabricante = 'LG'; SaludPct = $Bateria; DisenoMWh = 57488; CargaCompletaMWh = 57488 * $Bateria / 100 })
            }
            windows      = [pscustomobject]@{ Nombre = 'Windows 11 Home'; Version = '25H2'; Licencia = [pscustomobject]@{ Estado = 'Activado'; Canal = 'OEM:DM' }; Soporte = [pscustomobject]@{ EnTabla = $true; Vigente = $true; Fin = '2027-10-12' } }
            seguridad    = [pscustomobject]@{ Defender = [pscustomobject]@{ Antivirus = $true; TiempoReal = $true; FirmasDias = 0; FirmasFecha = '2026-11-19' }; Antivirus = @(); BitLocker = @(); SecureBoot = [pscustomobject]@{ Firmware = 'UEFI'; Activo = $true }; Tpm = [pscustomobject]@{ Presente = $true; Activado = $true; Version = '2.0' } }
            energia      = [pscustomobject]@{ Hibernacion = [pscustomobject]@{ HiberfilGB = 5.6 } }
            arranque     = [pscustomobject]@{
                Entradas       = @([pscustomobject]@{ Nombre = 'Steam'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Empresa = 'Valve Corporation' },
                    [pscustomobject]@{ Nombre = 'btweb'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Empresa = 'BitTorrent Limited' },
                    [pscustomobject]@{ Nombre = 'DAEMON Tools Lite Automount'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Empresa = 'Disc Soft' },
                    [pscustomobject]@{ Nombre = 'MicrosoftEdgeAutoLaunch_ABC'; Ubicacion = 'HKCU\Run'; Habilitado = $true; Empresa = 'Microsoft Corporation' },
                    [pscustomobject]@{ Nombre = 'Delete Cached Update Binary'; Ubicacion = 'HKCU\RunOnce'; Habilitado = $true; Empresa = 'Microsoft Corporation' },
                    [pscustomobject]@{ Nombre = 'Apagado'; Ubicacion = 'HKCU\Run'; Habilitado = $false; Empresa = 'Otro' })
                AppsStore      = @([pscustomobject]@{ Nombre = 'TeamsTfwStartupTask'; Ubicacion = 'Store: MSTeams'; Habilitado = $true })
                TiempoArranque = [pscustomobject]@{ Disponible = $true; UltimoSeg = $ArranqueSeg; Ultimos = @([pscustomobject]@{ Fecha = '2026-11-19 15:48:06'; TotalSeg = $ArranqueSeg }, [pscustomobject]@{ Fecha = '2026-11-05 21:38:33'; TotalSeg = 121.8 }, [pscustomobject]@{ Fecha = '2026-07-18 14:46:00'; TotalSeg = 60.2 }) }
            }
            uso          = [pscustomobject]@{ Memoria = [pscustomobject]@{ TotalGB = 13.9; UsadaGB = 6.9; UsoPct = 49.3 } }
            espacio      = [pscustomobject]@{ Volumenes = @([pscustomobject]@{ Unidad = 'C:'; Medio = 'SSD'; TotalGB = 222.5; LibreGB = 222.5 * $LibrePct / 100; LibrePct = $LibrePct; EsSistema = $true; EsKit = $false },
                    [pscustomobject]@{ Unidad = 'D:'; Medio = 'HDD'; TotalGB = 931.5; LibreGB = 705.5; LibrePct = 75.7; EsSistema = $false; EsKit = $false }); TopCarpetas = $top
            }
            dispositivos = [pscustomobject]@{ ConError = @() }
            estabilidad  = [pscustomobject]@{ Dias = 30; Apagados = $Apagados; Pantallazos = 0; ErroresDisco = 0; Eventos = $eventos }
        }
    }
}

function New-CsvPrueba {
    # HWiNFO en español: 2 min de reposo (55 °C, 5 %), 8 min al 100 % subiendo de 75 a 89 °C, cada 2 s.
    param([string]$Ruta)
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('"Date","Time","CPU (Tctl/Tdie) [°C]","Uso total de CPU [%]","Reloj efectivo promedio [MHz]","Potencia total de CPU [W]","CPU [RPM]","Desaceleración térmica (HTC) [Yes/No]",')
    $t0 = [datetime]'2026-11-19 16:00:00'
    for ($s = 0; $s -le 600; $s += 2) {
        $carga = $s -ge 120
        $temp = if ($carga) { 75 + 14 * ($s - 120) / 480 } else { 55 }
        $uso = if ($carga) { 100 } else { 5 }
        $mhz = if ($carga) { 3200 } else { 900 }
        $rpm = if ($carga) { 4000 } else { 3000 }
        $t = $t0.AddSeconds($s)
        [void]$sb.AppendLine(('{0},{1},{2},{3},{4},{5},{6},No,' -f $t.ToString('d.M.yyyy', [Globalization.CultureInfo]::InvariantCulture), $t.ToString('H:m:s.fff', [Globalization.CultureInfo]::InvariantCulture), $temp.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture), $uso, $mhz, '15.5', $rpm))
    }
    [IO.File]::WriteAllText($Ruta, $sb.ToString(), [Text.Encoding]::GetEncoding(1252))
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('kit_visual_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = [IO.Directory]::CreateDirectory($tmp)
try {
    '== Nombre del modelo'
    Assert 'Acer + familia Nitro 5' ((Get-NombreModeloVisual -Equipo ([pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Nitro AN515-43'; Familia = 'Nitro 5' })) -eq 'Acer Nitro 5 AN515-43')
    Assert 'sin familia' ((Get-NombreModeloVisual -Equipo ([pscustomobject]@{ Fabricante = 'Dell'; Modelo = 'Inspiron 3493'; Familia = '' })) -eq 'Dell Inspiron 3493')
    Assert 'familia ya incluida' ((Get-NombreModeloVisual -Equipo ([pscustomobject]@{ Fabricante = 'Lenovo'; Modelo = 'IdeaPad 3 15ITL6'; Familia = 'IdeaPad 3' })) -eq 'Lenovo IdeaPad 3 15ITL6')
    Assert 'familia basura se ignora' ((Get-NombreModeloVisual -Equipo ([pscustomobject]@{ Fabricante = 'HP'; Modelo = 'HP 240 G8'; Familia = 'To Be Filled By O.E.M.' })) -eq 'HP 240 G8')

    '== Puntaje por área'
    $areas = @(Get-AreasSalud -Doc (New-DocPrueba))
    $temp = $areas | Where-Object Clave -EQ 'temperatura'
    Assert 'sin CSV la temperatura no se mide' ($null -eq $temp.Puntaje)
    Assert 'equipo sano: todas las medidas sobre 84' (@($areas | Where-Object { $null -ne $_.Puntaje -and $_.Puntaje -lt 85 }).Count -eq 0) (($areas | ForEach-Object { "$($_.Clave)=$($_.Puntaje)" }) -join ' ')
    Assert 'puntaje general ignora lo no medido' ((Get-PuntajeGeneral -Areas $areas) -ge 85)
    $areas = @(Get-AreasSalud -Doc (New-DocPrueba -LibrePct 14.9 -Apagados 2 -Bateria 70.6 -ArranqueSeg 93))
    Assert 'C: 14,9 % libre = 50' ((($areas | Where-Object Clave -EQ 'almacenamiento').Puntaje) -eq 50)
    Assert '2 apagados = 80' ((($areas | Where-Object Clave -EQ 'estabilidad').Puntaje) -eq 80)
    Assert 'batería 70,6 % = 71' ((($areas | Where-Object Clave -EQ 'bateria').Puntaje) -eq 71)
    Assert 'arranque 93 s = 55' ((($areas | Where-Object Clave -EQ 'arranque').Puntaje) -eq 55)
    $areas = @(Get-AreasSalud -Doc (New-DocPrueba -SaludDisco 'Warning'))
    Assert 'disco con falla baja almacenamiento a 30 o menos' ((($areas | Where-Object Clave -EQ 'almacenamiento').Puntaje) -le 30)

    '== Programas al inicio'
    $ini = @(Get-InicioCliente -Doc (New-DocPrueba))
    Assert 'sin RunOnce ni deshabilitados' (@($ini | Where-Object { $_.Nombre -match 'Delete Cached|Apagado' }).Count -eq 0)
    Assert 'nombres para el cliente' (@($ini | Where-Object Nombre -EQ 'BitTorrent Web').Count -eq 1 -and @($ini | Where-Object Nombre -EQ 'Microsoft Edge').Count -eq 1)
    Assert 'incluye apps de la Store' (@($ini | Where-Object Nombre -EQ 'Microsoft Teams').Count -eq 1)
    Assert 'Edge y Teams marcados como de Microsoft' (@($ini | Where-Object { $_.Windows }).Count -eq 2)

    '== Papelera'
    Assert 'suma la papelera de nivel 2' ((Get-PapeleraGB -Doc (New-DocPrueba -Papelera 42.6)) -eq 42.6)
    Assert 'sin papelera = 0' ((Get-PapeleraGB -Doc (New-DocPrueba)) -eq 0)

    '== Recomendaciones'
    $r = @(Get-RecomendacionesVisual -Doc (New-DocPrueba))
    Assert 'equipo sano: sin liberar espacio ni apagados' (@($r | Where-Object { $_.Titulo -match 'espacio|apagados' }).Count -eq 0) (($r | ForEach-Object Titulo) -join ' | ')
    $r = @(Get-RecomendacionesVisual -Doc (New-DocPrueba -LibrePct 14.9 -Apagados 2 -Papelera 42.6 -ArranqueSeg 93))
    $esp = $r | Where-Object Titulo -EQ 'Liberar espacio'
    Assert 'liberar espacio con la papelera y la hibernación' ($esp -and $esp.Detalle -match '42,6 GB' -and $esp.Detalle -match '5,6 GB') "$($esp.Detalle)"
    Assert 'ordenar el inicio con ejemplos' (@($r | Where-Object { $_.Titulo -match 'inicio' -and $_.Detalle -match 'Steam' }).Count -eq 1)
    Assert 'revisar apagados' (@($r | Where-Object Titulo -EQ 'Revisar los apagados').Count -eq 1)
    $imp = @($r | ForEach-Object { [int]$_.Impacto })
    Assert 'ordenadas por impacto' ((($imp | Sort-Object -Descending) -join ',') -eq ($imp -join ','))

    '== Con prueba de temperatura'
    $csv = Join-Path $tmp 'sensores.csv'
    New-CsvPrueba -Ruta $csv
    $sens = Read-SensoresCsv -Ruta $csv
    Assert 'lee el ventilador' ($null -ne $sens.metricas.ventilador_cpu -and $sens.metricas.ventilador_cpu.max -eq 4000)
    Assert 'la serie trae ventilador y uso' ($null -ne $sens.serie[0].ventilador_cpu -and $null -ne $sens.serie[0].cpu_uso)
    $rep = Get-ReposoSensores -Sensores $sens
    Assert 'reposo a 55 °C' ($rep -and $rep.temp -eq 55)
    $areas = @(Get-AreasSalud -Doc (New-DocPrueba) -Sensores $sens)
    Assert 'temperatura 89 °C = 73' ((($areas | Where-Object Clave -EQ 'temperatura').Puntaje) -eq 73) "$(($areas | Where-Object Clave -EQ 'temperatura').Puntaje)"
    $r = @(Get-RecomendacionesVisual -Doc (New-DocPrueba) -Sensores $sens)
    Assert 'mantención preventiva sobre 85 °C' (@($r | Where-Object Titulo -EQ 'Mantención térmica preventiva').Count -eq 1)
    $svg = Get-SvgTemperatura -Sensores $sens
    Assert 'gráfico con franja de carga' ($svg -match 'Procesador al 100 %')
    Assert 'gráfico con la curva del ventilador' ($svg -match "stroke='#1f5fa8'")
    $zoom = Get-SvgZoomCarga -Sensores $sens
    Assert 'zoom con relleno degradado y franjas' ($zoom -match 'zcRelleno' -and $zoom -match 'CALIENTE')
    Assert 'zoom dice cuánto subió' ([Net.WebUtility]::HtmlDecode($zoom) -match '\+\d+ °C en \d+ min')

    '== HTML completo (cultura es-CL)'
    $cultura = [Threading.Thread]::CurrentThread.CurrentCulture
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]'es-CL'
    try { $html = ConvertTo-InformeVisual -Doc (New-DocPrueba -LibrePct 14.9 -Apagados 2 -Papelera 42.6) -Sensores $sens } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $cultura }
    Assert 'números del SVG con punto' (-not [regex]::IsMatch($html, "(?:x|y|x1|x2|y1|y2|cx|cy|r|width|height)='-?\d+,\d")) ([regex]::Match($html, "(?:x|y|x1|x2|y1|y2|cx|cy|r|width|height)='-?\d+,\d").Value)
    Assert 'trazos del SVG con punto' (-not [regex]::IsMatch($html, "d='M[^']*\d,\d"))
    Assert 'portada con el modelo' ($html -match 'Acer Nitro 5 AN515-43')
    Assert 'sin la serie del equipo' ($html -notmatch 'SERIE-SECRETA')
    Assert 'sin nombres de carpetas del cliente' ($html -cnotmatch 'D:\\Juegos|Instaladores') ([regex]::Match($html, 'D:\\Juegos|Instaladores').Value)
    Assert 'explica para qué sirve cada disco' ([Net.WebUtility]::HtmlDecode($html) -match 'Para qué sirve cada disco')
    $dec = [Net.WebUtility]::HtmlDecode($html)
    Assert 'secciones principales' ($dec -match 'Cómo está cada área' -and $dec -match 'Prueba de temperatura<small>' -and $dec -match 'Espacio en disco' -and $dec -match 'Lo que te propongo')
    Assert 'nada de NaN ni Infinity' ($html -cnotmatch '\bNaN\b|\bInfinity\b')
    $txt = [Net.WebUtility]::HtmlDecode($html)
    Assert 'el cliente no ve el cómo ni "sin costo"' ($txt -notmatch '(?i)sin costo|administrador de tareas|aplicaciones de arranque|vaciar la papelera|desactivar' -and $txt -cnotmatch 'LENTO') ([regex]::Match($txt, '(?i)sin costo|administrador de tareas|aplicaciones de arranque|vaciar la papelera|desactivar').Value)
    Assert 'servicios propuestos' ($txt -match 'Lo que te propongo' -and $txt -match 'Optimización de Windows' -and $txt -match 'Mantención térmica' -and $txt -match 'Lo que encontré' -and $txt -match 'Qué ganas')

    '== Servicios y hoja técnica'
    $sv = @(Get-ServiciosCliente -Doc (New-DocPrueba -LibrePct 14.9 -Apagados 2 -Papelera 42.6 -ArranqueSeg 93) -Sensores $sens)
    Assert 'optimización primero, con espacio, inicio y apagados' ($sv[0].Titulo -eq 'Optimización de Windows' -and @($sv[0].Hallazgos).Count -eq 4) "$($sv | ForEach-Object Titulo)"
    Assert 'mantención térmica como servicio' (@($sv | Where-Object { $_.Titulo -eq 'Mantención térmica' -and $_.Tipo -eq 'Servicio' }).Count -eq 1)
    Assert 'equipo sano: sin optimización' (@(Get-ServiciosCliente -Doc (New-DocPrueba)).Count -eq 0)
    $tec = ConvertTo-HojaTecnica -Doc (New-DocPrueba -LibrePct 14.9 -Papelera 42.6 -ArranqueSeg 93) -Sensores $sens
    Assert 'hoja técnica con los programas a desactivar' ($tec -match 'Candidatos a desactivar' -and $tec -match 'BitTorrent Web' -and $tec -match 'DAEMON Tools')
    Assert 'hoja técnica con papelera e hibernación' ($tec -match 'Papelera: 42,6 GB' -and $tec -match 'hiberfil.sys: 5,6 GB')
    $html2 = ConvertTo-InformeVisual -Doc (New-DocPrueba)
    Assert 'sin CSV no hay página de temperatura' ($html2 -notmatch 'Prueba de temperatura<small>')

    '== PDF'
    $json = Join-Path $tmp 'diagnostico.json'
    [IO.File]::WriteAllText($json, ((New-DocPrueba -LibrePct 14.9) | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
    if (Find-Edge) {
        $res = Export-InformeVisual -Diagnostico $json -CsvSensores $csv -Salida (Join-Path $tmp 'informe.pdf')
        Assert 'genera HTML, PDF y hoja técnica' ([IO.File]::Exists($res.Html) -and [IO.File]::Exists($res.Tecnico) -and $res.Pdf -and (Get-Item $res.Pdf).Length -gt 20000) "$($res.Error)"
    } else { $script:omitidas++; '  OMITIDA PDF (sin Edge)' }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

''
"Resultado: $script:ok OK, $script:fallas fallas$(if ($script:omitidas) { ", $script:omitidas omitidas" }) ($($script:ok + $script:fallas) comprobaciones)"
if ($script:fallas) { exit 1 }
exit 0
