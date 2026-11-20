# Paquetes.ps1 - Catálogo de packs que se ofrecen (config.json, "paquetes") con su precio (config_local.json,
# "precios": solo en el PC del técnico, el repositorio es público). Lo usan la ficha (elegir el paquete por
# número), los informes (precio de cada servicio propuesto) y remoto\armar_envios.ps1 (carpetas para mandar).
# Sin precio en config_local.json, el precio queda $null y los informes no muestran montos.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

function Get-CatalogoPaquetes {
    # Lista ordenada por número, cada uno con su Precio (o $null si no está en config_local.json).
    $cfg = $script:Ctx.Config
    if (-not $cfg -or -not $cfg.paquetes) { return }
    $precios = $cfg.PSObject.Properties['precios']
    foreach ($p in @($cfg.paquetes.lista | Where-Object { $_ } | Sort-Object { [int]$_.numero })) {
        $precio = $null
        if ($precios -and $precios.Value.PSObject.Properties[$p.id]) { $precio = [double]$precios.Value.($p.id) }
        [pscustomobject][ordered]@{
            Id = $p.id; Numero = [int]$p.numero; Nombre = $p.nombre; Modo = $p.modo; Mandar = $p.mandar; Descuenta = [bool]$p.descuenta
            PiezaAparte = [bool]$p.pieza_aparte; Resumen = $p.resumen; QueHace = @($p.que_hace); Duracion = $p.duracion; Precio = $precio
        }
    }
}

function Get-PaqueteCatalogo {
    param([Parameter(Mandatory)][string]$Id)
    @(Get-CatalogoPaquetes | Where-Object Id -EQ $Id) | Select-Object -First 1
}

function Resolve-PaqueteTexto {
    # Lo que escribe el técnico en "Paquete": un número del catálogo, el id o el nombre exacto. Si no calza, $null
    # (el texto queda como texto libre).
    param([AllowEmptyString()][string]$Texto)
    $t = "$Texto".Trim()
    if (-not $t) { return $null }
    $cat = @(Get-CatalogoPaquetes)
    if ($t -match '^\d+$') { return @($cat | Where-Object Numero -EQ ([int]$t)) | Select-Object -First 1 }
    @($cat | Where-Object { $_.Id -ieq $t -or $_.Nombre -ieq $t }) | Select-Object -First 1
}

function Format-PrecioPaquete {
    # "$10.000", "sin costo", "$15.000 + la pieza" o "a convenir" (sin precio configurado).
    param($Paquete)
    if (-not $Paquete -or $null -eq $Paquete.Precio) { return 'a convenir' }
    if ([double]$Paquete.Precio -eq 0) { return 'sin costo' }
    '$' + (Format-Numero ([double]$Paquete.Precio) 0) + $(if ($Paquete.PiezaAparte) { ' + la pieza' } else { '' })
}

function Format-CatalogoTexto {
    # Líneas para la consola: "  1) Diagnóstico a distancia (a distancia) ........ $10.000".
    foreach ($p in @(Get-CatalogoPaquetes)) {
        $izq = '{0,3}) {1} ({2})' -f $p.Numero, $p.Nombre, $p.Modo
        '{0} {1} {2}' -f $izq, ('.' * [math]::Max(2, 58 - $izq.Length)), (Format-PrecioPaquete $p)
    }
}
