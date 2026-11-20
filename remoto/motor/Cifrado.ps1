#Requires -Version 5.1
# Cifrado del diagnóstico remoto: solo lo abre quien tiene la llave privada (Isaac).
# Híbrido: una llave AES-256 al azar cifra el ZIP y una HMAC-SHA256 lo protege de cambios;
# esas dos llaves van cifradas con la llave pública RSA de 3072 bits (OAEP).
# Formato: "KITREM1" + 0 | largo del bloque RSA (int32) | bloque RSA | IV (16) | datos cifrados | HMAC (32).
# Sin Add-Type con código: solo clases de .NET Framework.

$script:MagiaRemoto = [Text.Encoding]::ASCII.GetBytes("KITREM1`0")

function Get-RutaLlavePrivada {
    # %LOCALAPPDATA%\kitservicio\remoto_llave_privada.dat. Si no está ahí, la busca en la carpeta privada de la
    # app Claude (Packages\Claude_*\LocalCache\Local\kitservicio): lo que se crea desde la consola de Claude queda
    # redirigido ahí y los programas normales no lo ven. $null si no está en ninguna.
    $normal = Join-Path $env:LOCALAPPDATA 'kitservicio\remoto_llave_privada.dat'
    if ([IO.File]::Exists($normal)) { return $normal }
    $paquetes = Join-Path $env:LOCALAPPDATA 'Packages'
    if ([IO.Directory]::Exists($paquetes)) {
        foreach ($d in @([IO.Directory]::GetDirectories($paquetes, 'Claude_*'))) {
            $r = Join-Path $d 'LocalCache\Local\kitservicio\remoto_llave_privada.dat'
            if ([IO.File]::Exists($r)) { return $r }
        }
    }
    $null
}

function Get-LlavesNuevasRemoto {
    # Devuelve un par de llaves nuevo (XML de .NET): Publica y Privada.
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider -ArgumentList 3072
    try {
        $rsa.PersistKeyInCsp = $false
        [pscustomobject]@{ Publica = $rsa.ToXmlString($false); Privada = $rsa.ToXmlString($true) }
    } finally { $rsa.Dispose() }
}

function Protect-DatosRemoto {
    param([Parameter(Mandatory)][byte[]]$Datos, [Parameter(Mandatory)][string]$LlavePublicaXml)
    $llaves = New-Object byte[] 64
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($llaves); $rng.Dispose()
    $kAes = New-Object byte[] 32; $kMac = New-Object byte[] 32
    [Array]::Copy($llaves, 0, $kAes, 0, 32); [Array]::Copy($llaves, 32, $kMac, 0, 32)
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($LlavePublicaXml)
        $bloque = $rsa.Encrypt($llaves, $true)
    } finally { $rsa.Dispose() }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $kAes; $aes.GenerateIV()
        $iv = $aes.IV
        $enc = $aes.CreateEncryptor()
        $cifrado = $enc.TransformFinalBlock($Datos, 0, $Datos.Length)
        $enc.Dispose()
    } finally { $aes.Dispose() }
    $ms = New-Object IO.MemoryStream
    $ms.Write($script:MagiaRemoto, 0, $script:MagiaRemoto.Length)
    $largo = [BitConverter]::GetBytes([int]$bloque.Length)
    $ms.Write($largo, 0, 4); $ms.Write($bloque, 0, $bloque.Length); $ms.Write($iv, 0, $iv.Length); $ms.Write($cifrado, 0, $cifrado.Length)
    $cuerpo = $ms.ToArray(); $ms.Dispose()
    $mac = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $kMac)
    $firma = $mac.ComputeHash($cuerpo); $mac.Dispose()
    [Array]::Clear($llaves, 0, 64); [Array]::Clear($kAes, 0, 32); [Array]::Clear($kMac, 0, 32)
    $salida = New-Object byte[] ($cuerpo.Length + 32)
    [Array]::Copy($cuerpo, 0, $salida, 0, $cuerpo.Length); [Array]::Copy($firma, 0, $salida, $cuerpo.Length, 32)
    , $salida
}

function Get-FirmaRemoto {
    # Firma RSA-3072 (SHA-256, PKCS#1 v1.5) de los datos con la llave privada de Isaac.
    param([Parameter(Mandatory)][byte[]]$Datos, [Parameter(Mandatory)][string]$LlavePrivadaXml)
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($LlavePrivadaXml)
        , $rsa.SignData($Datos, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } finally { $rsa.Dispose() }
}

function Test-FirmaRemoto {
    # $true solo si la firma corresponde a esos datos y a esa llave pública.
    param([Parameter(Mandatory)][byte[]]$Datos, [Parameter(Mandatory)][byte[]]$Firma, [Parameter(Mandatory)][string]$LlavePublicaXml)
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($LlavePublicaXml)
        $rsa.VerifyData($Datos, $Firma, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } catch { $false } finally { $rsa.Dispose() }
}

function Unprotect-DatosRemoto {
    param([Parameter(Mandatory)][byte[]]$Datos, [Parameter(Mandatory)][string]$LlavePrivadaXml)
    $m = $script:MagiaRemoto
    if ($Datos.Length -lt ($m.Length + 4 + 16 + 32)) { throw 'El archivo es muy corto: no es un diagnóstico remoto.' }
    for ($i = 0; $i -lt $m.Length; $i++) { if ($Datos[$i] -ne $m[$i]) { throw 'El archivo no es un diagnóstico remoto (falta la marca KITREM1).' } }
    $largo = [BitConverter]::ToInt32($Datos, $m.Length)
    $pos = $m.Length + 4
    if ($largo -le 0 -or ($pos + $largo + 16 + 32) -gt $Datos.Length) { throw 'El archivo está dañado (bloque de llaves).' }
    $bloque = New-Object byte[] $largo; [Array]::Copy($Datos, $pos, $bloque, 0, $largo); $pos += $largo
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($LlavePrivadaXml)
        try { $llaves = $rsa.Decrypt($bloque, $true) } catch { throw 'Este archivo no fue cifrado para esta llave (o está dañado).' }
    } finally { $rsa.Dispose() }
    $kAes = New-Object byte[] 32; $kMac = New-Object byte[] 32
    [Array]::Copy($llaves, 0, $kAes, 0, 32); [Array]::Copy($llaves, 32, $kMac, 0, 32)
    $finCuerpo = $Datos.Length - 32
    $mac = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $kMac)
    $firma = $mac.ComputeHash($Datos, 0, $finCuerpo); $mac.Dispose()
    $dif = 0
    for ($i = 0; $i -lt 32; $i++) { $dif = $dif -bor ($firma[$i] -bxor $Datos[$finCuerpo + $i]) }
    if ($dif -ne 0) { throw 'El archivo fue modificado o está dañado: la firma no coincide.' }
    $iv = New-Object byte[] 16; [Array]::Copy($Datos, $pos, $iv, 0, 16); $pos += 16
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $kAes; $aes.IV = $iv
        $dec = $aes.CreateDecryptor()
        $plano = $dec.TransformFinalBlock($Datos, $pos, $finCuerpo - $pos)
        $dec.Dispose()
    } finally { $aes.Dispose() }
    [Array]::Clear($llaves, 0, $llaves.Length); [Array]::Clear($kAes, 0, 32); [Array]::Clear($kMac, 0, 32)
    , $plano
}

# ---------------------------------------------------------------- paquete firmado y código de Isaac
# Al armar un paquete, Isaac firma la lista de sus archivos con su huella SHA-256 (motor\manifiesto.json y
# motor\manifiesto.firma). En el equipo del cliente, antes de pedir administrador, se comprueba la firma con la
# llave pública del paquete y cada huella. El "código de Isaac" sale de esa llave pública: es el mismo en todos
# sus paquetes y él lo manda por WhatsApp, así que un paquete con otra llave muestra otro código.
# Fuera del manifiesto: la llave pública (es el ancla, se comprueba con el código), el manifiesto y su firma, y
# en herramientas\ todo lo que no es .exe (OCCT y HWiNFO escriben su configuración al usarse).

function Get-CodigoIsaac {
    # 'XXXX-XXXX' a partir del módulo de la llave pública (no depende de cómo está escrito el XML).
    param([Parameter(Mandatory)][string]$LlavePublicaXml)
    $x = [xml]$LlavePublicaXml
    $mod = [Convert]::FromBase64String("$($x.RSAKeyValue.Modulus)".Trim())
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($mod) } finally { $sha.Dispose() }
    $hex = -join ($h[0..3] | ForEach-Object { $_.ToString('X2') })
    '{0}-{1}' -f $hex.Substring(0, 4), $hex.Substring(4, 4)
}

function Get-ArchivosManifiesto {
    # Rutas relativas (con \) de los archivos del paquete que van en el manifiesto, ordenadas.
    param([Parameter(Mandatory)][string]$Raiz)
    $base = $Raiz.TrimEnd('\').Length + 1
    $fuera = @('motor\llave_publica.xml', 'motor\manifiesto.json', 'motor\manifiesto.firma')
    @(Get-ChildItem -LiteralPath $Raiz -Recurse -File | ForEach-Object { $_.FullName.Substring($base) } |
            Where-Object { $fuera -notcontains $_ -and ($_ -notlike 'herramientas\*' -or $_ -like '*.exe') } | Sort-Object)
}

function Get-HuellaArchivo {
    param([Parameter(Mandatory)][string]$Ruta)
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::OpenRead($Ruta)
    try { -join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) } finally { $fs.Dispose(); $sha.Dispose() }
}

function Write-ManifiestoPaquete {
    # Escribe y firma el manifiesto de un paquete armado en $Raiz. Devuelve cuántos archivos cubre.
    param([Parameter(Mandatory)][string]$Raiz, [Parameter(Mandatory)][string]$LlavePrivadaXml)
    $lista = @(Get-ArchivosManifiesto -Raiz $Raiz | ForEach-Object { [ordered]@{ ruta = $_; sha256 = (Get-HuellaArchivo -Ruta (Join-Path $Raiz $_)) } })
    $man = [ordered]@{ formato = 'KITMANIF1'; creado = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); archivos = $lista }
    $bytes = (New-Object Text.UTF8Encoding $false).GetBytes(($man | ConvertTo-Json -Depth 4))
    $firma = Get-FirmaRemoto -Datos $bytes -LlavePrivadaXml $LlavePrivadaXml
    [IO.File]::WriteAllBytes((Join-Path $Raiz 'motor\manifiesto.json'), $bytes)
    [IO.File]::WriteAllText((Join-Path $Raiz 'motor\manifiesto.firma'), [Convert]::ToBase64String($firma), [Text.Encoding]::ASCII)
    $lista.Count
}

function Test-ManifiestoPaquete {
    # ¿Es un paquete de Isaac sin cambios? Devuelve Ok, Codigo (código de Isaac de la llave del paquete), Motivo
    # (en palabras para el cliente) y Archivos. Solo lee.
    param([Parameter(Mandatory)][string]$Raiz)
    $r = [pscustomobject]@{ Ok = $false; Codigo = $null; Motivo = $null; Archivos = 0 }
    try {
        $llave = Join-Path $Raiz 'motor\llave_publica.xml'
        $rm = Join-Path $Raiz 'motor\manifiesto.json'
        $rf = Join-Path $Raiz 'motor\manifiesto.firma'
        if (-not [IO.File]::Exists($llave)) { $r.Motivo = 'Falta la llave de Isaac en el paquete.'; return $r }
        $pub = [IO.File]::ReadAllText($llave)
        $r.Codigo = Get-CodigoIsaac -LlavePublicaXml $pub
        if (-not [IO.File]::Exists($rm) -or -not [IO.File]::Exists($rf)) { $r.Motivo = 'El paquete no trae la firma de Isaac.'; return $r }
        $bytes = [IO.File]::ReadAllBytes($rm)
        $firma = [Convert]::FromBase64String([IO.File]::ReadAllText($rf).Trim())
        if (-not (Test-FirmaRemoto -Datos $bytes -Firma $firma -LlavePublicaXml $pub)) { $r.Motivo = 'La firma de Isaac no coincide: el paquete fue modificado.'; return $r }
        $man = (New-Object Text.UTF8Encoding $false).GetString($bytes) | ConvertFrom-Json
        if ($man.formato -ne 'KITMANIF1') { $r.Motivo = 'Formato de firma desconocido: pídele a Isaac un paquete nuevo.'; return $r }
        foreach ($a in @($man.archivos)) {
            $ruta = Join-Path $Raiz $a.ruta
            if (-not [IO.File]::Exists($ruta)) { $r.Motivo = "Falta un archivo del paquete ($($a.ruta)): descomprímelo completo o pídele uno nuevo a Isaac."; return $r }
            if ((Get-HuellaArchivo -Ruta $ruta) -ne $a.sha256) { $r.Motivo = "La firma de Isaac no coincide: el archivo $($a.ruta) fue modificado."; return $r }
        }
        $r.Archivos = @($man.archivos).Count
        $r.Ok = $true
    } catch { $r.Motivo = "No se pudo comprobar la firma ($($_.Exception.Message))." }
    $r
}

function Read-LlavePrivadaIsaac {
    # La llave privada de Isaac (XML), guardada con DPAPI en su usuario. Solo en el PC de Isaac (para firmar).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleTypes', '', Justification = 'ProtectedData viene con .NET Framework y se carga con Add-Type -AssemblyName System.Security')]
    param()
    $ruta = Get-RutaLlavePrivada
    if (-not $ruta) { throw "No está la llave privada en este PC ($env:LOCALAPPDATA\kitservicio\remoto_llave_privada.dat)." }
    Add-Type -AssemblyName System.Security
    [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($ruta), $null, 'CurrentUser'))
}

# ---------------------------------------------------------------- código por cliente
# El diagnóstico a distancia pide un código que Isaac le da a cada cliente: NOMBRE-XXXX-XXXX.
# XXXX-XXXX (base32 de Crockford, sin I L O U) lleva el día de vencimiento (2 bytes, días desde 2026-01-01) y
# 3 bytes de HMAC-SHA256 de "NOMBRE|día" con una clave que está en el PC de Isaac y dentro del paquete
# (motor\codigos.dat), nunca en el repositorio. Es una barrera para que un link reenviado no sirva a
# cualquiera, no seguridad dura: el paquete funciona sin internet y alguien técnico podría sacar la clave.

$script:Base32Kit = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
$script:DiaCeroCodigos = [datetime]'2026-01-01'

function Get-NombreCodigo {
    # "Beli Pérez" -> "BELIPEREZ" (A-Z y 0-9, sin tildes, máximo 12).
    param([string]$Nombre)
    $s = -join ("$Nombre".Normalize([Text.NormalizationForm]::FormD).ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    $s = ($s.ToUpperInvariant() -replace '[^A-Z0-9]', '')
    if ($s.Length -gt 12) { $s = $s.Substring(0, 12) }
    $s
}

function Get-FirmaCodigo {
    # 5 bytes: día de vencimiento (2) + HMAC (3).
    param([string]$Nombre, [int]$Dia, [byte[]]$Clave)
    $mac = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $Clave)
    try { $h = $mac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$Nombre|$Dia")) } finally { $mac.Dispose() }
    [byte[]]@([byte](($Dia -shr 8) -band 255), [byte]($Dia -band 255), $h[0], $h[1], $h[2])
}

function ConvertTo-Base32Kit {
    param([byte[]]$Bytes)
    $n = [uint64]0
    foreach ($b in $Bytes) { $n = ($n -shl 8) -bor $b }
    $s = ''
    for ($i = 7; $i -ge 0; $i--) { $s += $script:Base32Kit[[int](($n -shr (5 * $i)) -band 31)] }
    $s
}

function New-CodigoCliente {
    # Código para un cliente: NOMBRE-XXXX-XXXX, vence en -Dias días (a las 23:59 de ese día).
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Nombre, [int]$Dias = 7, [Parameter(Mandatory)][byte[]]$Clave, [datetime]$Hoy = (Get-Date))
    $nom = Get-NombreCodigo $Nombre
    if (-not $nom) { throw 'El nombre del cliente tiene que tener letras o números.' }
    $dia = [int]($Hoy.Date.AddDays($Dias) - $script:DiaCeroCodigos).TotalDays
    if (-not $PSCmdlet.ShouldProcess($nom, 'Crear código')) { return }
    $c = ConvertTo-Base32Kit (Get-FirmaCodigo -Nombre $nom -Dia $dia -Clave $Clave)
    '{0}-{1}-{2}' -f $nom, $c.Substring(0, 4), $c.Substring(4, 4)
}

function Test-CodigoCliente {
    # ¿Código válido y vigente? Devuelve Ok, Nombre, Vence (fecha), Codigo (normalizado) y Motivo (para el cliente).
    param([string]$Codigo, [Parameter(Mandatory)][byte[]]$Clave, [datetime]$Hoy = (Get-Date))
    $r = [pscustomobject]@{ Ok = $false; Nombre = $null; Vence = $null; Codigo = $null; Motivo = 'Escribe el código que te dio Isaac.' }
    # Se perdona lo que se confunde al escribir: espacios, minúsculas, O por 0, I y L por 1.
    $s = ("$Codigo".ToUpperInvariant() -replace '[\s_]', '' -replace '[^A-Z0-9-]', '')
    if (-not $s) { return $r }
    $m = [regex]::Match($s, '^([A-Z0-9]{1,12})-?([A-Z0-9]{4})-?([A-Z0-9]{4})$')
    if (-not $m.Success) { $r.Motivo = 'El código no está completo: es NOMBRE-XXXX-XXXX.'; return $r }
    $nom = $m.Groups[1].Value
    $cuerpo = ($m.Groups[2].Value + $m.Groups[3].Value) -replace 'O', '0' -replace '[IL]', '1'
    $n = [uint64]0
    foreach ($ch in $cuerpo.ToCharArray()) {
        $v = $script:Base32Kit.IndexOf($ch)
        if ($v -lt 0) { $r.Motivo = 'El código tiene una letra que no corresponde: revísalo.'; return $r }
        $n = ($n -shl 5) -bor [uint64]$v
    }
    $bytes = [byte[]]@(4, 3, 2, 1, 0 | ForEach-Object { [byte](($n -shr (8 * $_)) -band 255) })
    $dia = ([int]$bytes[0] -shl 8) -bor [int]$bytes[1]
    $esperado = Get-FirmaCodigo -Nombre $nom -Dia $dia -Clave $Clave
    $dif = 0
    for ($i = 0; $i -lt 5; $i++) { $dif = $dif -bor ($esperado[$i] -bxor $bytes[$i]) }
    if ($dif -ne 0) { $r.Motivo = 'Ese código no es válido: revísalo o pídele uno a Isaac.'; return $r }
    $vence = $script:DiaCeroCodigos.AddDays($dia)
    $r.Nombre = $nom; $r.Vence = $vence; $r.Codigo = '{0}-{1}-{2}' -f $nom, $cuerpo.Substring(0, 4), $cuerpo.Substring(4, 4)
    if ($Hoy.Date -gt $vence) { $r.Motivo = "El código venció el $($vence.ToString('dd-MM-yyyy')): pídele uno nuevo a Isaac."; return $r }
    $r.Ok = $true; $r.Motivo = $null
    $r
}

function Get-ClaveCodigosPaquete {
    # La clave de códigos que viene en el paquete (motor\codigos.dat, base64). $null si no está.
    param([Parameter(Mandatory)][string]$Motor)
    $f = Join-Path $Motor 'codigos.dat'
    if (-not [IO.File]::Exists($f)) { return $null }
    , [Convert]::FromBase64String([IO.File]::ReadAllText($f).Trim())
}

function Get-RutaClaveCodigo {
    # En el PC de Isaac: <carpeta del maestro>\..\privado\clave_codigos.dat (fuera del repo y del pendrive).
    # -Crear la genera (32 bytes al azar) si no existe. $null si no hay maestro configurado.
    param([Parameter(Mandatory)][string]$Repo, [switch]$Crear)
    $cfg = Get-Content -LiteralPath (Join-Path $Repo 'KIT\scripts\config\config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $m = "$($cfg.sincronizacion.ruta_maestro)"
    if (-not $m -or -not [IO.Directory]::Exists((Split-Path -Parent $m))) { return $null }
    $ruta = Join-Path (Split-Path -Parent $m) 'privado\clave_codigos.dat'
    if ($Crear -and -not [IO.File]::Exists($ruta)) {
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $ruta))
        $b = New-Object byte[] 32
        $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
        $rng.GetBytes($b); $rng.Dispose()
        [IO.File]::WriteAllText($ruta, [Convert]::ToBase64String($b), [Text.Encoding]::ASCII)
    }
    $ruta
}
