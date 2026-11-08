#Requires -Version 5.1
<#
.SYNOPSIS
    Corre todas las baterías con Pester 3.4 (viene con Windows) y deja un informe: resultado.xml (NUnit),
    resumen.md y la salida de cada batería. Sale con código 1 si algo falla.
.DESCRIPTION
    Es lo mismo que corre GitHub en cada push (.github\workflows\pruebas.yml). En GitHub, además, agrega el
    resumen a la página de la corrida y marca cada falla como error.
.PARAMETER Salida
    Carpeta del informe (por defecto %TEMP%\kit_pruebas).
.PARAMETER Solo
    Nombres de baterías a correr, por ejemplo "test_faseH,test_sensores". Sin él, todas.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\pruebas\correr_baterias.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param([string]$Salida = (Join-Path $env:TEMP 'kit_pruebas'), [string]$Solo)

$ErrorActionPreference = 'Stop'
$aqui = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$null = [IO.Directory]::CreateDirectory($Salida)
$env:KIT_PRUEBAS_SALIDA = $Salida
$pester = @(Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -le 4 } | Sort-Object Version -Descending)[0]
if (-not $pester) { throw 'Falta Pester 3 o 4 (Windows trae el 3.4.0).' }
Import-Module $pester.Path -Force
"Pester $($pester.Version) | PowerShell $($PSVersionTable.PSVersion) | cultura $([Globalization.CultureInfo]::CurrentCulture.Name)"

$parametros = @{}
if ($Solo) { $parametros['Solo'] = @($Solo -split '[,; ]+' | Where-Object { $_ }) }
$xml = Join-Path $Salida 'resultado.xml'
$r = Invoke-Pester -Script @{ Path = (Join-Path $aqui 'Baterias.Tests.ps1'); Parameters = $parametros } -PassThru -OutputFile $xml -OutputFormat NUnitXml

# Resumen por batería, en Markdown.
$md = New-Object System.Collections.Generic.List[string]
$md.Add('## Pruebas del kit (Windows PowerShell 5.1)')
$md.Add('')
$md.Add("**$($r.PassedCount) OK · $($r.FailedCount) fallas · $($r.SkippedCount) omitidas** (las omitidas usan archivos que solo están en el PC de Isaac)")
$md.Add('')
$md.Add('| Batería | OK | Fallas | Omitidas |')
$md.Add('|---|---:|---:|---:|')
foreach ($g in @($r.TestResult | Group-Object Describe)) {
    $md.Add(('| {0} | {1} | {2} | {3} |' -f $g.Name, @($g.Group | Where-Object Result -EQ 'Passed').Count, @($g.Group | Where-Object Result -EQ 'Failed').Count, @($g.Group | Where-Object Result -EQ 'Skipped').Count))
}
$fallas = @($r.TestResult | Where-Object Result -EQ 'Failed')
if ($fallas.Count) {
    $md.Add('')
    $md.Add('### Fallas')
    foreach ($f in $fallas) { $md.Add("- **$($f.Describe)**: $($f.Name)") }
}
[IO.File]::WriteAllLines((Join-Path $Salida 'resumen.md'), $md, (New-Object Text.UTF8Encoding($true)))
if ($env:GITHUB_STEP_SUMMARY) { [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, (($md -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false))) }
if ($env:GITHUB_ACTIONS) {
    foreach ($f in $fallas) { [Console]::Out.WriteLine(('::error title={0}::{1}' -f $f.Describe, ($f.Name -replace '[\r\n]+', ' '))) }
    # Si una batería se cortó, sus últimas líneas van como error: así se ven sin bajar el informe.
    foreach ($d in @($fallas | Select-Object -ExpandProperty Describe -Unique)) {
        $txt = Join-Path $Salida "$d.txt"
        if ([IO.File]::Exists($txt)) {
            $cola = @([IO.File]::ReadAllLines($txt) | Where-Object { $_ -match '\S' } | Select-Object -Last 15) -join '%0A'
            [Console]::Out.WriteLine(('::error title={0} (últimas líneas)::{1}' -f $d, ($cola -replace '::', ': ')))
        }
    }
}

''
"Resultado: $($r.PassedCount) OK, $($r.FailedCount) fallas, $($r.SkippedCount) omitidas | informe en $Salida"
if ($r.FailedCount -gt 0) { exit 1 }
exit 0
