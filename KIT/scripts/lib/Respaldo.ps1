# Respaldo.ps1 - Copia cifrada del maestro de expedientes, solo en los equipos del técnico (después de
# sincronizar, o con respaldar_maestro.ps1). Todo con .NET Framework: nada que instalar.
#
# Formato .kitresp (versión 1):
#   "KITRESP1" | iteraciones (int32) | sal (16) | iv (16) | HMAC-SHA256 (32) | datos cifrados (AES-256-CBC)
#   Los datos, comprimidos con GZip, son una lista de archivos: largo de la ruta (int32), ruta en UTF-8,
#   tamaño (int64), SHA-256 (32) y el contenido; termina con largo -1. Las claves de cifrado y de firma
#   salen de la contraseña con PBKDF2-SHA256. La firma cubre todo menos ella misma: si el archivo se daña
#   o la contraseña no es la correcta, no se abre.
# La contraseña la escribe el técnico; se guarda cifrada con DPAPI (solo su usuario en ese PC) para que el
# respaldo corra solo después de sincronizar. Para restaurar en otro PC hay que escribirla.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español: la regla pluraliza en inglés')]
param()

$script:MagiaRespaldo = [Text.Encoding]::ASCII.GetBytes('KITRESP1')

function Get-ConfigRespaldo {
    # destino y conservar de config.json -> respaldo, o $null si no hay respaldo configurado.
    $c = $script:Ctx.Config.respaldo
    if (-not $c -or -not $c.destino) { return $null }
    [pscustomobject]@{ Destino = [Environment]::ExpandEnvironmentVariables([string]$c.destino); Conservar = $(if ($c.conservar) { [int]$c.conservar } else { 10 }) }
}

function Get-RutaClaveRespaldo {
    # Fuera del pendrive: en el perfil del técnico, en su PC.
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'kitservicio\respaldo.clave'
}

function Set-ClaveRespaldo {
    # Guarda la contraseña cifrada con DPAPI: solo este usuario, en este PC, puede leerla.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][securestring]$Clave, [string]$Ruta = (Get-RutaClaveRespaldo))
    if (-not $PSCmdlet.ShouldProcess($Ruta, 'Guardar la contraseña del respaldo (DPAPI)')) { return }
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Ruta))
    [IO.File]::WriteAllText($Ruta, (ConvertFrom-SecureString -SecureString $Clave), (New-Object Text.UTF8Encoding($false)))
}

function Get-ClaveRespaldo {
    # La contraseña guardada, o $null si no hay (o si es de otro usuario o PC).
    [OutputType([securestring])]
    param([string]$Ruta = (Get-RutaClaveRespaldo))
    if (-not [IO.File]::Exists($Ruta)) { return $null }
    try { ConvertTo-SecureString -String ([IO.File]::ReadAllText($Ruta).Trim()) } catch { $null }
}

function Get-ClavesRespaldo {
    # 32 bytes para cifrar y 32 para firmar, con PBKDF2-SHA256.
    param([Parameter(Mandatory)][securestring]$Clave, [Parameter(Mandatory)][byte[]]$Sal, [Parameter(Mandatory)][int]$Iteraciones)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Clave)
    try {
        $texto = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($texto, $Sal, $Iteraciones, [Security.Cryptography.HashAlgorithmName]::SHA256)
        $b = $kdf.GetBytes(64)
        $kdf.Dispose()
        [pscustomobject]@{ Cifrado = [byte[]]$b[0..31]; Firma = [byte[]]$b[32..63] }
    } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-FirmaRespaldo {
    # HMAC-SHA256 del encabezado (sin la firma) y de los datos cifrados, leyendo el archivo por partes.
    param([Parameter(Mandatory)][string]$Ruta, [Parameter(Mandatory)][byte[]]$ClaveFirma)
    $h = New-Object Security.Cryptography.HMACSHA256(, $ClaveFirma)
    $fs = [IO.File]::OpenRead($Ruta)
    try {
        $enc = New-Object byte[] 44
        if ($fs.Read($enc, 0, 44) -ne 44) { throw 'El respaldo está incompleto' }
        $null = $h.TransformBlock($enc, 0, 44, $null, 0)
        $null = $fs.Seek(32, [IO.SeekOrigin]::Current)
        $buf = New-Object byte[] 1048576
        while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) { $null = $h.TransformBlock($buf, 0, $n, $null, 0) }
        $null = $h.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        , $h.Hash
    } finally { $fs.Dispose(); $h.Dispose() }
}

function Get-ArchivosMaestro {
    # Archivos del maestro con su ruta relativa y SHA-256, en orden.
    param([Parameter(Mandatory)][string]$Maestro)
    $raiz = [IO.Path]::GetFullPath($Maestro).TrimEnd('\')
    foreach ($f in @([IO.Directory]::GetFiles($raiz, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)) {
        [pscustomobject]@{ Relativa = $f.Substring($raiz.Length + 1); Ruta = $f; Hash = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash; Bytes = (New-Object IO.FileInfo($f)).Length }
    }
}

function Open-LectorRespaldo {
    # Comprueba firma y contraseña y devuelve el lector de la lista de archivos (descifrado y descomprimido).
    param([Parameter(Mandatory)][string]$Ruta, [Parameter(Mandatory)][securestring]$Clave)
    $fs = [IO.File]::OpenRead($Ruta)
    $enc = New-Object byte[] 76
    if ($fs.Read($enc, 0, 76) -ne 76) { $fs.Dispose(); throw 'El respaldo está incompleto' }
    $magia = [Text.Encoding]::ASCII.GetString($enc, 0, 8)
    if ($magia -ne 'KITRESP1') { $fs.Dispose(); throw 'No es un respaldo del kit (o es de una versión que este kit no conoce)' }
    $iter = [BitConverter]::ToInt32($enc, 8)
    $sal = [byte[]]$enc[12..27]; $iv = [byte[]]$enc[28..43]; $firma = [byte[]]$enc[44..75]
    $k = Get-ClavesRespaldo -Clave $Clave -Sal $sal -Iteraciones $iter
    $fs.Dispose()
    $calculada = Get-FirmaRespaldo -Ruta $Ruta -ClaveFirma $k.Firma
    if ([Convert]::ToBase64String($calculada) -ne [Convert]::ToBase64String($firma)) { throw 'La contraseña no es la correcta o el respaldo está dañado' }
    $fs = [IO.File]::OpenRead($Ruta)
    $null = $fs.Seek(76, [IO.SeekOrigin]::Begin)
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $k.Cifrado; $aes.IV = $iv
    $cs = New-Object Security.Cryptography.CryptoStream($fs, $aes.CreateDecryptor(), [Security.Cryptography.CryptoStreamMode]::Read)
    $gz = New-Object IO.Compression.GZipStream($cs, [IO.Compression.CompressionMode]::Decompress)
    New-Object IO.BinaryReader($gz, [Text.Encoding]::UTF8)
}

function Read-ArchivosRespaldo {
    # Recorre el respaldo archivo por archivo, comprueba el SHA-256 de cada uno y, con -Destino, lo escribe.
    # Devuelve la lista (Relativa, Hash, Bytes). Lanza un error si algo no cuadra.
    param([Parameter(Mandatory)][string]$Ruta, [Parameter(Mandatory)][securestring]$Clave, [string]$Destino)
    $br = Open-LectorRespaldo -Ruta $Ruta -Clave $Clave
    $lista = New-Object System.Collections.Generic.List[object]
    $buf = New-Object byte[] 1048576
    try {
        while ($true) {
            $largo = $br.ReadInt32()
            if ($largo -lt 0) { break }
            $rel = [Text.Encoding]::UTF8.GetString($br.ReadBytes($largo))
            if ($rel -match '(^|\\)\.\.(\\|$)' -or [IO.Path]::IsPathRooted($rel)) { throw "Ruta no válida en el respaldo: $rel" }
            $tam = $br.ReadInt64()
            $hashGuardado = -join ($br.ReadBytes(32) | ForEach-Object { $_.ToString('X2') })
            $sha = [Security.Cryptography.SHA256]::Create()
            $sal = $null
            if ($Destino) {
                $final = Join-Path $Destino $rel
                $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $final))
                $sal = [IO.File]::Open($final, [IO.FileMode]::CreateNew)
            }
            try {
                $resto = $tam
                while ($resto -gt 0) {
                    $n = $br.Read($buf, 0, [int][math]::Min($buf.Length, $resto))
                    if ($n -le 0) { throw 'El respaldo se corta antes de tiempo' }
                    $null = $sha.TransformBlock($buf, 0, $n, $null, 0)
                    if ($sal) { $sal.Write($buf, 0, $n) }
                    $resto -= $n
                }
                $null = $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
                $hash = -join ($sha.Hash | ForEach-Object { $_.ToString('X2') })
            } finally { if ($sal) { $sal.Dispose() }; $sha.Dispose() }
            if ($hash -ne $hashGuardado) { throw "El archivo $rel no cuadra con su SHA-256" }
            $lista.Add([pscustomobject]@{ Relativa = $rel; Hash = $hash; Bytes = $tam })
        }
    } finally { $br.Dispose() }
    $lista.ToArray()
}

function New-RespaldoMaestro {
    # Escribe <Destino>\maestro_<fecha_hora>.kitresp, lo vuelve a leer desde el disco y compara cada archivo
    # con el original. Recién entonces le pone su nombre final y borra los respaldos más antiguos que
    # pasen de -Conservar. Devuelve Ruta, Archivos, Bytes y Borrados.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Maestro,
        [Parameter(Mandatory)][string]$Destino,
        [Parameter(Mandatory)][securestring]$Clave,
        [int]$Conservar = 10,
        [int]$Iteraciones = 200000
    )
    if (-not [IO.Directory]::Exists($Maestro)) { throw "No existe el maestro $Maestro" }
    $raizDestino = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destino))
    if (-not [IO.Directory]::Exists($raizDestino)) { throw "No está la unidad del respaldo ($raizDestino)" }
    if (-not $PSCmdlet.ShouldProcess($Destino, 'Respaldar el maestro')) { return }
    $null = [IO.Directory]::CreateDirectory($Destino)
    $archivos = @(Get-ArchivosMaestro -Maestro $Maestro)
    $final = Join-Path $Destino ('maestro_{0}.kitresp' -f (Get-Date).ToString('yyyyMMdd_HHmmss'))
    $parcial = "$final.parcial"
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $sal = New-Object byte[] 16; $iv = New-Object byte[] 16
    $rng.GetBytes($sal); $rng.GetBytes($iv); $rng.Dispose()
    $k = Get-ClavesRespaldo -Clave $Clave -Sal $sal -Iteraciones $Iteraciones
    $fs = $null; $bw = $null
    try {
        $fs = [IO.File]::Open($parcial, [IO.FileMode]::CreateNew)
        $fs.Write($script:MagiaRespaldo, 0, 8)
        $fs.Write([BitConverter]::GetBytes([int]$Iteraciones), 0, 4)
        $fs.Write($sal, 0, 16); $fs.Write($iv, 0, 16)
        $fs.Write((New-Object byte[] 32), 0, 32)   # la firma se escribe al final
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $k.Cifrado; $aes.IV = $iv
        $cs = New-Object Security.Cryptography.CryptoStream($fs, $aes.CreateEncryptor(), [Security.Cryptography.CryptoStreamMode]::Write)
        $gz = New-Object IO.Compression.GZipStream($cs, [IO.Compression.CompressionMode]::Compress)
        $bw = New-Object IO.BinaryWriter($gz, [Text.Encoding]::UTF8)
        try {
            foreach ($a in $archivos) {
                $nombre = [Text.Encoding]::UTF8.GetBytes($a.Relativa)
                $bw.Write([int]$nombre.Length); $bw.Write($nombre)
                $bw.Write([long]$a.Bytes)
                $bw.Write([byte[]]@(for ($i = 0; $i -lt 64; $i += 2) { [Convert]::ToByte($a.Hash.Substring($i, 2), 16) }))
                $bw.Flush()
                $src = [IO.File]::OpenRead($a.Ruta)
                try { $src.CopyTo($gz) } finally { $src.Dispose() }
            }
            $bw.Write([int]-1)
        } finally { $bw.Dispose(); $bw = $null; $fs = $null }   # cierra GZip, CryptoStream (bloque final) y el archivo
        $firma = Get-FirmaRespaldo -Ruta $parcial -ClaveFirma $k.Firma
        $fs = [IO.File]::Open($parcial, [IO.FileMode]::Open, [IO.FileAccess]::Write)
        try { $null = $fs.Seek(44, [IO.SeekOrigin]::Begin); $fs.Write($firma, 0, 32) } finally { $fs.Dispose() }

        # Verificación: se lee de vuelta desde el disco y cada archivo tiene que calzar con el original.
        $leidos = @(Read-ArchivosRespaldo -Ruta $parcial -Clave $Clave)
        if ($leidos.Count -ne $archivos.Count) { throw "El respaldo tiene $($leidos.Count) archivos y el maestro $($archivos.Count)" }
        for ($i = 0; $i -lt $archivos.Count; $i++) {
            if ($leidos[$i].Relativa -ne $archivos[$i].Relativa -or $leidos[$i].Hash -ne $archivos[$i].Hash) { throw "El archivo $($archivos[$i].Relativa) cambió mientras se respaldaba: vuelve a respaldar" }
        }
        [IO.File]::Move($parcial, $final)
    } catch {
        $original = $_
        if ($bw) { try { $bw.Dispose() } catch { Write-Verbose 'ya cerrado' } } elseif ($fs) { try { $fs.Dispose() } catch { Write-Verbose 'ya cerrado' } }
        try { if ([IO.File]::Exists($parcial)) { [IO.File]::Delete($parcial) } } catch { Write-Verbose "No se pudo borrar $parcial" }
        throw $original
    }
    $borrados = @()
    if ($Conservar -gt 0) {
        $viejos = @(Get-ChildItem -LiteralPath $Destino -File -Filter 'maestro_*.kitresp' | Sort-Object Name -Descending | Select-Object -Skip $Conservar)
        foreach ($v in $viejos) { [IO.File]::Delete($v.FullName); $borrados += $v.Name }
    }
    [pscustomobject]@{ Ruta = $final; Archivos = $archivos.Count; Bytes = (New-Object IO.FileInfo($final)).Length; Borrados = $borrados }
}

function Restore-RespaldoMaestro {
    # Descifra un respaldo en una carpeta NUEVA (o vacía), comprobando cada archivo. Nunca escribe sobre el
    # maestro: después se revisa y se reemplaza a mano.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Array])]
    param([Parameter(Mandatory)][string]$Ruta, [Parameter(Mandatory)][string]$Destino, [Parameter(Mandatory)][securestring]$Clave)
    if ([IO.Directory]::Exists($Destino) -and @([IO.Directory]::GetFileSystemEntries($Destino)).Count) { throw "La carpeta $Destino no está vacía: elige una nueva" }
    if (-not $PSCmdlet.ShouldProcess($Destino, 'Restaurar el respaldo')) { return }
    $null = [IO.Directory]::CreateDirectory($Destino)
    @(Read-ArchivosRespaldo -Ruta $Ruta -Clave $Clave -Destino $Destino)
}
