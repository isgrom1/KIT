#Requires -Version 5.1
<#
.SYNOPSIS
    Mejoras recomendadas (lib\Mejoras.ps1): SSD, RAM en dual channel, más RAM, disco más grande, batería,
    mantención térmica; y que salgan en el pre-informe sin repetir las recomendaciones de las alertas.
.DESCRIPTION
    Todo con datos sintéticos: equipos inventados, con la misma forma que diagnostico.json. No lee el equipo.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente', 'Sensores', 'Informe') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$N, [bool]$C, [string]$D = '') if ($C) { $script:ok++; "  OK     $N" } else { $script:fallas++; "  FALLA  $N  $D" } }

function New-DatosPrueba {
    # Equipo sano por defecto: notebook, SSD de 512 GB con 60 % libre, 2 x 8 GB DDR4, batería al 95 %.
    param([string]$TipoEquipo = 'Notebook', [string]$TipoDisco = 'SSD', [double]$DiscoGB = 512, [double]$LibrePct = 60,
        [object[]]$Modulos = @(@{ CapacidadGB = 8 }, @{ CapacidadGB = 8 }), [object]$Bateria = 95, [double]$UsoPct = 50)
    $mods = @(foreach ($m in $Modulos) { [pscustomobject]@{ Slot = 'ChannelA-DIMM0'; CapacidadGB = $m.CapacidadGB; Tipo = 'DDR4'; VelocidadMTs = 3200; NumeroParte = 'PARTE-1' } })
    $total = ($mods | Measure-Object CapacidadGB -Sum).Sum
    $bats = @(if ($null -ne $Bateria) { [pscustomobject]@{ Id = 'BAT01'; SaludPct = $Bateria; DisenoMWh = 48000 } })
    [pscustomobject]@{
        equipo   = [pscustomobject]@{ Fabricante = 'Marca'; Modelo = 'Modelo X'; Tipo = $TipoEquipo }
        hardware = [pscustomobject]@{
            Ram      = [pscustomobject]@{ TotalGB = $total; Modulos = $mods; CantidadModulos = $mods.Count; Slots = 2 }
            Discos   = @([pscustomobject]@{ Disco = 0; Modelo = 'DISCO-1'; Tipo = $TipoDisco; Bus = 'NVMe'; TamanoGB = $DiscoGB; Sistema = $true; Salud = 'Healthy' })
            Baterias = $bats
        }
        uso      = [pscustomobject]@{ Memoria = [pscustomobject]@{ UsoPct = $UsoPct } }
        espacio  = [pscustomobject]@{ Volumenes = @([pscustomobject]@{ Unidad = 'C:'; EsSistema = $true; LibrePct = $LibrePct }) }
    }
}
function Get-Codigos { param($Mejoras) @($Mejoras | ForEach-Object { $_.Codigo }) }

'== Equipo sano'
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba))
Assert 'sin mejoras' ($m.Count -eq 0) "($((Get-Codigos $m) -join ','))"
Assert 'el texto lo dice' (@(Format-MejorasTexto -Mejoras $m)[0] -match 'ninguna')

'== Disco mecánico'
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -TipoDisco 'HDD' -DiscoGB 931))
Assert 'recomienda SSD, prioridad alta' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-SSD' -and $m[0].Prioridad -eq 'Alta')
Assert 'SSD de 1 TB para un disco de 931 GB' ($m[0].Comprar -match '1 TB')
Assert 'en notebook dice 2,5"' ($m[0].Comprar -match '2,5')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -TipoDisco 'HDD' -DiscoGB 320))
Assert 'disco de 320 GB: SSD de 500 GB' ($m[0].Comprar -match '500 GB')

'== RAM'
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Modulos @(@{ CapacidadGB = 8 })))
Assert '1 módulo de 8 GB: segundo módulo igual, media' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-RAM-DUAL' -and $m[0].Prioridad -eq 'Media' -and $m[0].Comprar -match '1 módulo de 8 GB DDR4 3200 MT/s SO-DIMM' -and $m[0].Comprar -match 'PARTE-1')
Assert 'avisa de memoria soldada' ($m[0].Comprar -match 'soldada')
Assert 'queda con 16 GB' ($m[0].Beneficio -match '16 GB')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -TipoEquipo 'Escritorio' -Modulos @(@{ CapacidadGB = 4 })))
Assert '1 módulo de 4 GB en PC: 2 x 8 GB DIMM, alta' ($m[0].Codigo -eq 'MEJ-RAM-DUAL' -and $m[0].Prioridad -eq 'Alta' -and $m[0].Comprar -match '2 módulos de 8 GB DDR4 3200 MT/s DIMM')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Modulos @(@{ CapacidadGB = 2 }, @{ CapacidadGB = 2 })))
Assert '2 x 2 GB: más RAM, alta' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-RAM' -and $m[0].Prioridad -eq 'Alta')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Modulos @(@{ CapacidadGB = 4 }, @{ CapacidadGB = 4 }) -UsoPct 92))
Assert '2 x 4 GB usada al 92 %: más RAM opcional' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-RAM' -and $m[0].Prioridad -eq 'Opcional')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Modulos @(@{ CapacidadGB = 4 }, @{ CapacidadGB = 4 }) -UsoPct 40))
Assert '2 x 4 GB con uso bajo: nada' ($m.Count -eq 0)

'== Espacio'
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -DiscoGB 256 -LibrePct 8))
Assert 'SSD de 256 GB lleno: SSD de 500 GB' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-SSD-GRANDE' -and $m[0].Comprar -match '500 GB')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -DiscoGB 1000 -LibrePct 8))
Assert 'disco grande lleno: no pide comprar (alcanza con ordenar)' ($m.Count -eq 0)

'== Disco con fallas'
$al = @([pscustomobject]@{ Severidad = 'CRITICO'; Codigo = 'HW-SMART-SECTORES'; Texto = 'x' })
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -DiscoGB 256 -LibrePct 8) -Alertas $al)
Assert 'disco con sectores dañados: cambiarlo, alta' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-DISCO-FALLA' -and $m[0].Prioridad -eq 'Alta')

'== Batería'
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Bateria 65))
Assert 'batería al 65 %: media, con modelo y código' ($m.Count -eq 1 -and $m[0].Codigo -eq 'MEJ-BATERIA' -and $m[0].Prioridad -eq 'Media' -and $m[0].Comprar -match 'Marca Modelo X' -and $m[0].Comprar -match 'BAT01')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Bateria 40))
Assert 'batería al 40 %: alta' ($m[0].Prioridad -eq 'Alta')
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -Bateria $null -TipoEquipo 'Escritorio'))
Assert 'PC sin batería: nada' ($m.Count -eq 0)

Assert 'código en hexadecimal se traduce' ((ConvertTo-CodigoBateria '0x41,0x50,0x31,0x38,0x45,0x38,0x4D') -eq 'AP18E8M')
Assert 'código normal queda igual' ((ConvertTo-CodigoBateria ' DELL FDRHM08 ') -eq 'DELL FDRHM08')
Assert 'código con basura se omite' ((ConvertTo-CodigoBateria "x`0`u{1}y") -eq '')
Assert 'tipo de SSD por el modelo aunque el bus sea RAID/VMD' ((Get-TipoSsd ([pscustomobject]@{ Bus = 'RAID/VMD'; Modelo = 'NVMe SAMSUNG X' })) -eq 'NVMe M.2')
Assert 'tipo de SSD desconocido queda vacío' ((Get-TipoSsd ([pscustomobject]@{ Bus = 'RAID/VMD'; Modelo = 'KINGSTON X' })) -eq '')
Assert 'ADATA no se confunde con SATA' ((Get-TipoSsd ([pscustomobject]@{ Bus = 'RAID/VMD'; Modelo = 'ADATA SU650NS38' })) -eq '')

'== Temperatura'
Assert '85 °C: nada' ($null -eq (Get-MejoraTermica -TempMaxC 85))
Assert '91 °C: media' ((Get-MejoraTermica -TempMaxC 91).Prioridad -eq 'Media')
Assert '97 °C: alta' ((Get-MejoraTermica -TempMaxC 97).Prioridad -eq 'Alta')
Assert 'sin dato: nada' ($null -eq (Get-MejoraTermica -TempMaxC $null))

'== Orden y combinación'
$m = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -TipoDisco 'HDD' -Modulos @(@{ CapacidadGB = 8 }) -Bateria 65) -TempMaxC 97)
Assert 'cuatro mejoras' ($m.Count -eq 4) "($((Get-Codigos $m) -join ','))"
Assert 'las altas primero' ($m[0].Prioridad -eq 'Alta' -and $m[1].Prioridad -eq 'Alta' -and $m[-1].Prioridad -eq 'Media')

'== Datos como diccionario (durante el diagnóstico)'
$dic = @{ hardware = @{ Ram = @{ TotalGB = 8; Modulos = @(@{ CapacidadGB = 8; Tipo = 'DDR4'; VelocidadMTs = 2666 }) }; Discos = @(@{ Tipo = 'HDD'; TamanoGB = 500; Sistema = $true; Modelo = 'D' }) }; equipo = @{ Tipo = 'Escritorio' } }
$m = @(Get-MejorasRecomendadas -Datos $dic)
Assert 'lee diccionarios igual' (((Get-Codigos $m) -join ',') -eq 'MEJ-SSD,MEJ-RAM-DUAL') "($((Get-Codigos $m) -join ','))"

'== Texto'
$txt = Format-MejorasTexto -Mejoras @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -TipoDisco 'HDD'))
Assert 'texto con prioridad, por qué, comprar y gana' ($txt[0] -match '^\[ALTA\]' -and ($txt -join "`n") -match 'Por qué' -and ($txt -join "`n") -match 'Comprar' -and ($txt -join "`n") -match 'Gana')

'== Pre-informe sin repetir'
$recs = @(Get-RecomendacionesAlertas -Alertas @([pscustomobject]@{ Severidad = 'AVISO'; Codigo = 'HW-DISCO-HDD' }, [pscustomobject]@{ Severidad = 'AVISO'; Codigo = 'ESP-LIBRE' }) -Excluir '^(HW-DISCO-HDD)$')
Assert 'la recomendación del HDD no se repite' ($recs.Count -eq 1 -and $recs[0] -match 'espacio')
$html = ConvertTo-PreInforme -Datos ([pscustomobject]@{ Tecnico = @{ nombre = 'T'; contacto = 'c' }; Cliente = @{ nombre = 'C' }; Equipo = @{ fabricante = 'F'; modelo = 'M' }; Fecha = '2026-01-01'; Motivos = @('REVISION'); Sintoma = $null
        Semaforo = [pscustomobject]@{ Areas = @() }; Color = 'amarillo'; Frase = 'x'; Grupos = [ordered]@{}; Prueba = ''; Recomendaciones = @(); Paquete = $null; Precio = $null; Falta = @(); SinAdmin = $false; Alertas = @()
        Mejoras = @(Get-MejorasRecomendadas -Datos (New-DatosPrueba -TipoDisco 'HDD')) })
Assert 'el pre-informe muestra la sección de mejoras' ($html -match 'Mejoras que recomendamos' -and $html -match 'por un SSD' -and $html -match 'prio Alta')

''
"Resultado: $script:ok OK, $script:fallas fallas"
if ($script:fallas) { exit 1 }
