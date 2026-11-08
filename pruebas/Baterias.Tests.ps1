#Requires -Version 5.1
<#
.SYNOPSIS
    Las baterías de pruebas\ como pruebas de Pester 3.4 (el que viene con Windows). Lo corre correr_baterias.ps1.
.DESCRIPTION
    Cada batería sigue siendo un script normal que se puede correr solo. Aquí cada una es una sección
    (Describe) y cada línea "OK" o "FALLA" que imprime es una prueba (It); "OMITIDA" queda como omitida (lo
    que necesita archivos que solo están en el PC de Isaac). Al final de cada sección se exige código de
    salida 0. La salida completa de cada batería queda en $env:KIT_PRUEBAS_SALIDA, si está definido.
    Sintaxis de Pester 3.4 (Should Be), que también entiende Pester 4.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param([string[]]$Solo)

$ErrorActionPreference = 'Continue'
$aqui = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# test_sin_antes no es una batería: marca atenciones reales de este equipo (ver LEEME).
$baterias = @(Get-ChildItem -LiteralPath $aqui -Filter 'test_*.ps1' | Where-Object { $_.Name -ne 'test_sin_antes.ps1' } | Sort-Object Name)
if ($Solo) { $baterias = @($baterias | Where-Object { $Solo -contains $_.BaseName -or $Solo -contains $_.Name }) }

foreach ($b in $baterias) {
    Describe $b.BaseName {
        $reloj = [Diagnostics.Stopwatch]::StartNew()
        $salida = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $b.FullName 2>&1 | ForEach-Object { "$_" })
        $codigo = $LASTEXITCODE
        if ($env:KIT_PRUEBAS_SALIDA) {
            [IO.File]::WriteAllLines((Join-Path $env:KIT_PRUEBAS_SALIDA "$($b.BaseName).txt"), [string[]]$salida, (New-Object Text.UTF8Encoding($true)))
        }
        $lineas = @($salida | ForEach-Object { if ($_ -match '^\s*(OK|FALLA|MAL|OMITIDA)\s+(.+?)\s*$') { [pscustomobject]@{ Estado = $Matches[1]; Texto = $Matches[2] } } })
        foreach ($l in $lineas) {
            if ($l.Estado -eq 'OMITIDA') { It $l.Texto -Skip { }; continue }
            $estado = $l.Estado
            It $l.Texto { $estado | Should Be 'OK' }
        }
        $resumen = '{0} comprobaciones, {1:n0} s' -f $lineas.Count, $reloj.Elapsed.TotalSeconds
        It "termina con código 0 ($resumen)" { $codigo | Should Be 0 }
    }
}
