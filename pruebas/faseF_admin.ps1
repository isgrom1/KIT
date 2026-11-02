#Requires -Version 5.1
# Fase F — ayudante con admin (un solo UAC para toda la prueba).
# 1. Crea un disco virtual de prueba de 2 GB en X:\kitservicio_prueba\faseF, en exFAT, con la letra K:
#    (el "USB" de la prueba; la letra la ven tanto los procesos con admin como los sin admin).
# 2. Corre SOLO trabajos fijos que se piden con un archivo en faseF\cola (nada de comandos libres):
#      e2.json        -> escenario 2 (LENTO) con admin
#      e1_admin.json  -> respaldo si se rechaza el UAC al relanzar: sigue el escenario 1 con admin
#                        ({"atencion": "AAAA-MM-DD_atencion[_n]"})
# 3. Con faseF\fin.txt (o a las 4 horas) desmonta el disco virtual y lo borra.
$ErrorActionPreference = 'Stop'
$base = 'X:\kitservicio_prueba\faseF'
$vhd = Join-Path $base 'kit_faseF.vhdx'
$cola = Join-Path $base 'cola'
$res = Join-Path $base 'resultados'
$pruebas = Split-Path -Parent $PSCommandPath
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$kitPs = 'K:\KIT\scripts\gui\kit.ps1'
$maestro = Join-Path $base 'maestro\clientes'
foreach ($d in $cola, $res) { $null = [IO.Directory]::CreateDirectory($d) }
$log = Join-Path $base 'admin.log'
function Add-Linea([string]$t) { [IO.File]::AppendAllText($log, "$(Get-Date -Format HH:mm:ss) $t`r`n", (New-Object Text.UTF8Encoding($true))) }
function Invoke-Diskpart([string[]]$Ordenes) {
    $f = Join-Path $base 'diskpart.txt'
    [IO.File]::WriteAllLines($f, $Ordenes, (New-Object Text.ASCIIEncoding))
    $s = & "$env:SystemRoot\System32\diskpart.exe" /s $f 2>&1 | Out-String
    Add-Linea "diskpart: código $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { Add-Linea $s }
}
try {
    Add-Linea "Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
    if (Test-Path 'K:\') { throw 'La letra K: ya está en uso' }
    if (Test-Path $vhd) { throw "Ya existe $vhd" }
    Invoke-Diskpart @("create vdisk file=`"$vhd`" maximum=2048 type=expandable", "select vdisk file=`"$vhd`"", 'attach vdisk', 'convert mbr', 'create partition primary', 'format fs=exfat label=KITFASEF quick', 'assign letter=K')
    $t0 = Get-Date
    while (-not (Test-Path 'K:\') -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500 }
    $vol = Get-Volume -DriveLetter K
    Add-Linea "K: $($vol.FileSystemType) $([math]::Round($vol.Size / 1MB)) MB"
    if ($vol.FileSystemType -ne 'exFAT') { throw "K: no quedó en exFAT ($($vol.FileSystemType))" }
    [IO.File]::WriteAllText((Join-Path $base 'listo_admin.txt'), (Get-Date -Format s))

    $t0 = Get-Date
    while (-not (Test-Path (Join-Path $base 'fin.txt')) -and ((Get-Date) - $t0).TotalHours -lt 4) {
        foreach ($f in @(Get-ChildItem -LiteralPath $cola -Filter '*.json' | Sort-Object Name)) {
            $trabajo = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            $datos = try { Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { $null }
            [IO.File]::Delete($f.FullName)
            $argumentos = $null
            switch ($trabajo) {
                'e2' { $argumentos = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$kitPs`" -Captura `"$base\capturas\e2`" -Escenario `"$pruebas\faseF_e2.ps1`" -RutaMaestro `"$maestro`"" }
                'e1_admin' {
                    if ($datos -and "$($datos.atencion)" -match '^\d{4}-\d{2}-\d{2}_atencion(_\d+)?$') {
                        $argumentos = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$kitPs`" -Atencion `"$($datos.atencion)`" -Captura `"$base\capturas\e1\admin`" -Escenario `"$pruebas\faseF_e1.ps1`" -RutaMaestro `"$maestro`""
                    }
                }
            }
            if (-not $argumentos) { Add-Linea "Trabajo rechazado: $trabajo"; continue }
            Add-Linea "Trabajo $trabajo"
            $p = Start-Process -FilePath $ps -ArgumentList $argumentos -PassThru -RedirectStandardError (Join-Path $res "$trabajo.err")
            if (-not $p.WaitForExit(20 * 60 * 1000)) { try { $p.Kill() } catch { Add-Linea "No se pudo cerrar $trabajo" }; Add-Linea "Trabajo ${trabajo}: tiempo agotado" }
            [IO.File]::WriteAllText((Join-Path $res "$trabajo.fin"), "$($p.ExitCode)")
            Add-Linea "Trabajo $trabajo terminó (código $($p.ExitCode))"
        }
        Start-Sleep -Seconds 2
    }
} catch {
    Add-Linea "ERROR: $($_.Exception.Message) (línea $($_.InvocationInfo.ScriptLineNumber))"
    [IO.File]::WriteAllText((Join-Path $base 'listo_admin.txt'), "ERROR $($_.Exception.Message)")
} finally {
    if (Test-Path $vhd) {
        Invoke-Diskpart @("select vdisk file=`"$vhd`"", 'detach vdisk')
        Start-Sleep -Seconds 2
        try { [IO.File]::Delete($vhd); Add-Linea 'Disco virtual desmontado y borrado.' } catch { Add-Linea "Disco virtual desmontado; no se pudo borrar: $($_.Exception.Message)" }
    }
    Add-Linea 'FIN'
}
