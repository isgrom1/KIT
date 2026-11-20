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
