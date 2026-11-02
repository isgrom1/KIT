# Pruebas de desarrollo de lib\Expediente.ps1 (no es parte del kit). Usa una carpeta temporal como
# KIT\clientes para no tocar la real.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'KIT\scripts'
foreach ($lib in 'Comun', 'Log', 'Privacidad', 'Alertas', 'Salidas', 'Expediente') { . (Join-Path $scripts "lib\$lib.ps1") }
Initialize-Contexto -RaizScripts $scripts
Initialize-Privacidad
$tmp = Join-Path $env:TEMP ('kit_prueba_exp_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$script:Ctx.CarpetaClientes = $tmp
$null = New-Item -ItemType Directory $tmp
$script:ok = 0; $script:fallas = 0
function Assert { param([string]$Nombre, [bool]$Condicion, [string]$Detalle = '')
    if ($Condicion) { $script:ok++; "  OK     $Nombre" } else { $script:fallas++; "  FALLA  $Nombre $Detalle" } }
function Assert-Error { param([string]$Nombre, [scriptblock]$Bloque, [string]$Esperado)
    try { & $Bloque; $script:fallas++; "  FALLA  $Nombre (no dio error)" } catch { if ($_.Exception.Message -match $Esperado) { $script:ok++; "  OK     $Nombre -> $($_.Exception.Message -replace '\s+', ' ')" } else { $script:fallas++; "  FALLA  $Nombre (otro error: $($_.Exception.Message))" } } }
function New-MedicionFalsa { param($Exp, $Atencion, $Momento) $r = Join-Path (Join-Path $Exp.Ruta $Atencion) $Momento; $null = [IO.Directory]::CreateDirectory($r); [IO.File]::WriteAllText((Join-Path $r 'diagnostico.json'), '{}') }

'== 1. Expediente con serie real'
$id1 = [pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Nitro AN515-57'; Serie = 'NHQTEST00000000000000X'; SerieOriginal = 'NHQTEST00000000000000X'; Uuid = 'AAAA-1'; PlacaSerie = 'P1' }
Assert 'no existe al inicio' ($null -eq (Get-Expediente -Identidad $id1))
$e1 = New-Expediente -Identidad $id1
Assert 'ID fabricante_modelo_serie' ($e1.Id -eq 'Acer_Nitro-AN515-57_NHQTEST00000000000000X') $e1.Id
Assert 'ficha.json y fotos_recepcion' ((Test-Path "$($e1.Ruta)\ficha.json") -and (Test-Path "$($e1.Ruta)\fotos_recepcion"))
$g1 = Get-Expediente -Identidad $id1
Assert 'Get-Expediente lo encuentra por ID' ($g1 -and $g1.Id -eq $e1.Id)
$id1b = [pscustomobject]@{ Fabricante = 'Acer'; Modelo = 'Nitro 5'; Serie = 'NHQTEST00000000000000X'; SerieOriginal = ''; Uuid = $null; PlacaSerie = $null }
Assert 'lo encuentra por serie aunque el modelo cambie de nombre' ((Get-Expediente -Identidad $id1b).Id -eq $e1.Id)

'== 2. Serie genérica'
$id2 = [pscustomobject]@{ Fabricante = 'Generico'; Modelo = 'Generico'; Serie = ''; SerieOriginal = 'To be filled by O.E.M.'; Uuid = '4C4C4544-0042-1234'; PlacaSerie = $null }
$e2 = New-Expediente -Identidad $id2
Assert 'ID con GUID corto' ($e2.Id -match '^Generico_Generico_[0-9a-f]{8}$') $e2.Id
Assert 'ficha marca serie_generica' ($e2.Ficha.equipo.identificadores.serie_generica -eq $true)
Assert 'se reconoce por UUID' ((Get-Expediente -Identidad $id2).Id -eq $e2.Id)
$id2c = [pscustomobject]@{ Fabricante = 'Generico'; Modelo = 'Generico'; Serie = ''; SerieOriginal = ''; Uuid = 'OTRO'; PlacaSerie = $null }
Assert 'otro equipo genérico no calza' ($null -eq (Get-Expediente -Identidad $id2c))

'== 3. Atenciones y reglas antes/después'
$hoy = (Get-Date).ToString('yyyy-MM-dd')
$a1 = Resolve-Atencion -Expediente $e1 -Momento antes
Assert 'antes crea la atención de hoy' ($a1 -eq "${hoy}_atencion") $a1
Assert 'después sin antes = $null' ($null -eq (Resolve-Atencion -Expediente $e1 -Momento despues))
New-MedicionFalsa $e1 $a1 'antes'
Assert 'antes otra vez continúa la misma' ((Resolve-Atencion -Expediente $e1 -Momento antes) -eq $a1)
Assert 'después usa la atención con antes' ((Resolve-Atencion -Expediente $e1 -Momento despues) -eq $a1)
$enCurso = Initialize-Medicion -Expediente $e1 -Atencion $a1 -Momento 'antes'
Assert 'la medición se escribe en antes_en_curso\csv' ($enCurso -like '*\antes_en_curso' -and (Test-Path (Join-Path $enCurso 'csv')))
[IO.File]::WriteAllText((Join-Path $enCurso 'diagnostico.json'), '{"nueva":1}')
$rem = Complete-Medicion -Expediente $e1 -Atencion $a1 -Momento 'antes'
Assert 'al completar, la anterior queda como antes_reemplazado_' ($rem -match '^antes_reemplazado_\d{6}$' -and (Test-Path (Join-Path (Join-Path $e1.Ruta $a1) $rem))) $rem
Assert 'y la nueva queda como antes\' ((Get-Content (Join-Path (Join-Path $e1.Ruta $a1) 'antes\diagnostico.json')) -match 'nueva')
$null = Initialize-Medicion -Expediente $e1 -Atencion $a1 -Momento 'antes'
Assert 'si se corta a mitad, antes\ sigue intacto' ((Test-Medicion -Expediente $e1 -Atencion $a1 -Momento 'antes') -and ((Get-Content (Join-Path (Join-Path $e1.Ruta $a1) 'antes\diagnostico.json')) -match 'nueva'))
$null = Initialize-Medicion -Expediente $e1 -Atencion $a1 -Momento 'antes'
Assert 'la corrida cortada queda como antes_incompleto_' (@(Get-ChildItem (Join-Path $e1.Ruta $a1) -Directory | Where-Object Name -match '^antes_incompleto_\d{6}$').Count -eq 1)
[IO.Directory]::Delete((Join-Path (Join-Path $e1.Ruta $a1) 'antes_en_curso'), $true)
New-MedicionFalsa $e1 $a1 'despues'
$a2 = Resolve-Atencion -Expediente $e1 -Momento antes
Assert 'antes con después ya hecho abre _2' ($a2 -eq "${hoy}_atencion_2") $a2
Assert '-Nueva fuerza otra (_3)' ((Resolve-Atencion -Expediente $e1 -Momento antes -Nueva) -eq "${hoy}_atencion_3")
Assert 'la ficha tiene 3 atenciones' (@(Get-ListaAtenciones -Expediente $e1).Count -eq 3)

'== 4. Initialize-Expediente (lo que llama el diagnóstico)'
$id3 = [pscustomobject]@{ Fabricante = 'HP'; Modelo = 'Pavilion 15'; Serie = '5CD1234XYZ'; SerieOriginal = '5CD1234XYZ'; Uuid = $null; PlacaSerie = $null }
$r = Initialize-Expediente -Identidad $id3 -Momento despues
Assert 'después en equipo sin expediente = SinAntes y no crea nada' ($r.SinAntes -and -not (Test-Path (Join-Path $tmp 'HP_Pavilion-15_5CD1234XYZ')))
$r = Initialize-Expediente -Identidad $id3 -Momento antes
Assert 'antes crea expediente nuevo y mide en antes_en_curso' ($r.Nuevo -and (Test-Path (Join-Path $script:Ctx.CarpetaCliente 'csv')) -and $script:Ctx.CarpetaCliente -like '*\antes_en_curso')
[IO.File]::WriteAllText((Join-Path $script:Ctx.CarpetaCliente 'diagnostico.json'), '{}')
$null = Complete-Medicion -Expediente $r.Objeto -Atencion $r.Atencion -Momento 'antes'

'== 5. Set-Ficha: validaciones'
$e3 = Get-Expediente -Identidad $id3
Assert-Error 'RUT en el nombre' { Set-Ficha -Expediente $e3 -Valores @{ 'cliente.nombre' = 'Juan 12.345.678-9' } } 'RUT'
Assert-Error 'RUT en notas' { Set-Ficha -Expediente $e3 -Valores @{ 'notas' = 'rut 9876543-K' } } 'RUT'
Assert-Error 'dirección en la comuna' { Set-Ficha -Expediente $e3 -Valores @{ 'cliente.comuna' = 'Av. Grecia 1234' } } 'sin dirección'
Assert-Error 'contacto inválido' { Set-Ficha -Expediente $e3 -Valores @{ 'cliente.contacto' = 'llamar en la tarde' } } 'WhatsApp'
Assert-Error 'motivo inválido' { Set-Ficha -Expediente $e3 -Valores @{ 'motivos' = 'CALOR,LIMPIEZA' } } 'LIMPIEZA'
Assert-Error 'campo inventado (rut)' { Set-Ficha -Expediente $e3 -Valores @{ 'cliente.rut' = '1' } } 'desconocido'
Assert-Error 'precio con letras' { Set-Ficha -Expediente $e3 -Valores @{ 'precio' = 'cuarenta mil' } } 'solo números'
Assert-Error 'un error no guarda nada' { Set-Ficha -Expediente $e3 -Valores @{ 'cliente.nombre' = 'Ana Pérez'; 'precio' = 'x' } } 'precio'
Assert 'el nombre no quedó guardado' ($null -eq (Get-Expediente -Identidad $id3).Ficha.cliente.nombre)
Set-Ficha -Expediente $e3 -Valores ([ordered]@{
        'cliente.nombre' = 'Ana Pérez'; 'cliente.contacto' = '+56 9 8765 4321'; 'cliente.comuna' = 'Ñuñoa'
        'motivos' = 'calor lento'; 'sintoma' = 'Se apaga jugando'; 'precio' = '$45.000'; 'respaldo' = 'no sabe'
        'checklist_funcional.teclado' = 'f'; 'bitlocker.clave_confirmada' = 'sí'
    })
$f3 = (Get-Expediente -Identidad $id3).Ficha
$at3 = Get-EntradaAtencion -Expediente (Get-Expediente -Identidad $id3)
Assert 'contacto normalizado' ($f3.cliente.contacto -eq '+56987654321') $f3.cliente.contacto
Assert 'comuna con ñ' ($f3.cliente.comuna -eq 'Ñuñoa')
Assert 'motivos en mayúsculas (arreglo)' (($at3.motivos -join ',') -eq 'CALOR,LENTO' -and $at3.motivos -is [array]) ($at3.motivos -join ',')
Assert 'precio $45.000 -> 45000' ($at3.precio -eq 45000) "$($at3.precio)"
Assert 'respaldo no_sabe / teclado falla / clave sí' ($at3.respaldo -eq 'no_sabe' -and $at3.checklist_funcional.teclado -eq 'falla' -and $at3.bitlocker.clave_confirmada -eq $true)
Assert 'ficha.json.bak existe' (Test-Path (Join-Path (Get-Expediente -Identidad $id3).Ruta 'ficha.json.bak'))

'== 6. Test-FichaCompleta y garantía'
$faltan = @(Test-FichaCompleta -Expediente (Get-Expediente -Identidad $id3))
"     falta: $(($faltan | ForEach-Object { $_.Campo }) -join ', ')"
Assert 'faltan paquete y contacto del técnico' (($faltan.Campo -contains 'paquete') -and ($faltan.Campo -contains 'tecnico.contacto') -and -not ($faltan.Campo -contains 'cliente.nombre'))
Set-Ficha -Expediente (Get-Expediente -Identidad $id3) -Valores @{ 'motivos' = 'ARCHIVOS'; 'paquete' = 'Mantención' }
$faltan = @(Test-FichaCompleta -Expediente (Get-Expediente -Identidad $id3))
Assert 'con ARCHIVOS pide consentimiento y carpetas protegidas' (($faltan.Campo -contains 'consentimiento_archivos') -and ($faltan.Campo -contains 'carpetas_protegidas'))
Set-Ficha -Expediente (Get-Expediente -Identidad $id3) -Valores @{ 'consentimiento_archivos' = 'm'; 'carpetas_protegidas' = 'C:\Users\Ana\Documents\Tesis;D:\Fotos' ; 'entregado' = '05-11-2026' }
$at3 = Get-EntradaAtencion -Expediente (Get-Expediente -Identidad $id3)
Assert 'carpetas protegidas como lista' (@($at3.carpetas_protegidas).Count -eq 2)
Assert 'entregado 05-11-2026 -> garantía 2026-12-05' ($at3.entregado -eq '2026-11-05' -and $at3.garantia_hasta -eq '2026-12-05') "$($at3.entregado) / $($at3.garantia_hasta)"
$solo = @(Test-FichaCompleta -Expediente (Get-Expediente -Identidad $id3) | Where-Object { $_.Campo -notlike 'tecnico.*' })
Assert 'una atención entregada ya no está abierta' ($solo.Campo -contains 'atencion') ($solo.Campo -join ',')
Assert 'después en atención entregada = $null' ($null -eq (Resolve-Atencion -Expediente (Get-Expediente -Identidad $id3) -Momento despues))

'== 7. trabajo.log'
Write-TrabajoLog -Expediente $e1 -Atencion $a1 -Texto ('ANTES | prueba con ruta C:\Users\' + $env:USERNAME + '\Desktop')
$log = [IO.File]::ReadAllText((Join-Path (Join-Path $e1.Ruta $a1) 'trabajo.log'))
Assert 'trabajo.log con BOM y ruta enmascarada' (([IO.File]::ReadAllBytes((Join-Path (Join-Path $e1.Ruta $a1) 'trabajo.log'))[0] -eq 0xEF) -and $log -notmatch [regex]::Escape($env:USERNAME)) $log

''
"Resultado: $script:ok OK, $script:fallas fallas"
Remove-Item $tmp -Recurse -Force
