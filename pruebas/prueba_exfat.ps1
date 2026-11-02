#Requires -Version 5.1
# Prueba del kit en exFAT (como el USB Ventoy). Corre con admin: crea un disco virtual de prueba de 1 GB
# en X:\kitservicio_prueba\exfat, lo formatea exFAT con la letra L:, copia el kit con datos de prueba y
# corre (con admin) el diagnóstico y las pruebas de sincronización desde L:. Después avisa con
# listo_admin.txt y espera fin_usuario.txt (pruebas sin admin) para desmontar y borrar el disco virtual.
param([string]$Letra = 'L')
$ErrorActionPreference = 'Stop'
$sp = Split-Path -Parent $PSCommandPath
$base = 'X:\kitservicio_prueba\exfat'
$vhd = Join-Path $base 'kit_exfat.vhdx'
$res = Join-Path $base 'resultado_admin.txt'
$null = [IO.Directory]::CreateDirectory($base)
$lineas = New-Object System.Collections.Generic.List[string]
function Add-Linea([string]$t) { $lineas.Add("$(Get-Date -Format HH:mm:ss) $t"); [IO.File]::WriteAllLines($res, $lineas, (New-Object Text.UTF8Encoding($true))) }
function Invoke-Diskpart([string[]]$Ordenes) {
    $f = Join-Path $base 'diskpart.txt'
    [IO.File]::WriteAllLines($f, $Ordenes, (New-Object Text.ASCIIEncoding))
    $s = & "$env:SystemRoot\System32\diskpart.exe" /s $f 2>&1 | Out-String
    Add-Linea "diskpart ($($Ordenes[1])...): código $LASTEXITCODE"
    $s
}
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
try {
    Add-Linea "Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
    if (Test-Path "${Letra}:\") { throw "La letra $Letra ya está en uso" }
    if (Test-Path $vhd) { throw "Ya existe $vhd" }
    $null = Invoke-Diskpart @("create vdisk file=`"$vhd`" maximum=1024 type=expandable", "select vdisk file=`"$vhd`"", 'attach vdisk', 'convert mbr', 'create partition primary', 'format fs=exfat label=KITPRUEBA quick', "assign letter=$Letra")
    $t0 = Get-Date
    while (-not (Test-Path "${Letra}:\") -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500 }
    $vol = Get-Volume -DriveLetter $Letra
    Add-Linea "Volumen ${Letra}: sistema de archivos=$($vol.FileSystemType) etiqueta=$($vol.FileSystemLabel) tamaño=$([math]::Round($vol.Size / 1MB)) MB"
    if ($vol.FileSystemType -ne 'exFAT') { throw "No quedó en exFAT ($($vol.FileSystemType))" }

    $prep = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sp 'preparar_kit_prueba.ps1') -Destino "${Letra}:\" 2>&1 | Out-String
    Add-Linea "Preparar kit: $($prep.Trim())"

    # File.Replace en exFAT (Save-Ficha lo usa, con respaldo manual si falla).
    $a = "${Letra}:\prueba_replace.txt"; [IO.File]::WriteAllText($a, 'uno'); [IO.File]::WriteAllText("$a.tmp", 'dos')
    try { [IO.File]::Replace("$a.tmp", $a, "$a.bak"); Add-Linea "File.Replace en exFAT: funciona (contenido=$([IO.File]::ReadAllText($a)))" } catch { Add-Linea "File.Replace en exFAT: FALLA ($($_.Exception.Message)) -> Save-Ficha usa el respaldo manual" }
    Get-ChildItem "${Letra}:\prueba_replace*" | ForEach-Object { [IO.File]::Delete($_.FullName) }

    # Diagnóstico ANTES completo con admin desde exFAT.
    $sal = Join-Path $base 'diag_exfat_admin.txt'
    $p = Start-Process -FilePath $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"${Letra}:\KIT\scripts\diagnostico.ps1`" -Momento Antes -SinEspacio" -RedirectStandardOutput $sal -RedirectStandardError (Join-Path $base 'diag_exfat_admin_err.txt') -WindowStyle Hidden -PassThru -Wait
    Add-Linea "Diagnóstico admin desde ${Letra}: código $($p.ExitCode)"
    $dirNitro = (Get-ChildItem "${Letra}:\KIT\clientes" -Directory -Filter 'Acer_Nitro*' | Select-Object -First 1).FullName
    $exp = Join-Path $dirNitro '2026-11-01_atencion_2\antes'
    $diag = Get-Content (Join-Path $exp 'diagnostico.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Linea "  diagnostico.json: generado=$($diag.kit.generado) admin=$($diag.kit.admin.Elevado) alertas=$(@($diag.alertas).Count) | discos.txt=$(Test-Path (Join-Path $exp 'discos.txt')) | resumen.txt=$(Test-Path (Join-Path $exp 'resumen.txt')) | csv=$(@(Get-ChildItem (Join-Path $exp 'csv') -Filter *.csv).Count)"
    Add-Linea "  reemplazada la anterior: $(@(Get-ChildItem (Split-Path $exp) -Directory -Filter 'antes_reemplazado_*').Count) carpetas antes_reemplazado_* | ficha.json.bak=$(Test-Path (Join-Path $dirNitro 'ficha.json.bak'))"

    # Pruebas de sincronización con todo en exFAT.
    $st = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sp 'test_sincronizacion.ps1') -Kit "${Letra}:\KIT" -Base "${Letra}:\kitprueba sync ñ" 2>&1 | Out-String
    [IO.File]::WriteAllText((Join-Path $base 'test_sync_exfat_admin.txt'), $st, (New-Object Text.UTF8Encoding($true)))
    Add-Linea "Pruebas de sincronización en exFAT (admin): $((($st -split "`r?`n") | Where-Object { $_ -like 'Resultado:*' }) -join '')"
    foreach ($f in (($st -split "`r?`n") | Where-Object { $_ -like 'FALLA*' })) { Add-Linea "  $f" }
} catch {
    Add-Linea "ERROR: $($_.Exception.Message) (línea $($_.InvocationInfo.ScriptLineNumber))"
} finally {
    # Las pruebas sin admin usan la misma letra (es global). Se espera hasta 30 min.
    [IO.File]::WriteAllText((Join-Path $base 'listo_admin.txt'), (Get-Date -Format s))
    $t0 = Get-Date
    while (-not (Test-Path (Join-Path $base 'fin_usuario.txt')) -and ((Get-Date) - $t0).TotalMinutes -lt 30) { Start-Sleep -Seconds 2 }
    if (Test-Path $vhd) {
        $null = Invoke-Diskpart @("select vdisk file=`"$vhd`"", "select vdisk file=`"$vhd`"", 'detach vdisk')
        Start-Sleep -Seconds 2
        try { [IO.File]::Delete($vhd); Add-Linea 'Disco virtual desmontado y borrado.' } catch { Add-Linea "Disco virtual desmontado; no se pudo borrar: $($_.Exception.Message)" }
    }
    Add-Linea 'FIN'
}
