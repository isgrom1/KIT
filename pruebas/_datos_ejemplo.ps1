# Datos de ejemplo para las baterías, para que corran en cualquier Windows (también en GitHub) sin los
# archivos reales de Isaac ni series de equipos. Se carga con un punto desde cada batería que lo necesite.
# - Write-CsvHwinfoEs: CSV de HWiNFO en español con las mañas del real: hora sin ceros a la izquierda,
#   columnas con el mismo nombre ("CPU Entera [°C]" dos veces), UTF-8 con BOM, y al final el encabezado
#   repetido y la fila de grupos ("Sistema: <equipo>", "CPU [#0]: <cpu>"), que dice de qué equipo es.
# - Write-DiscosEjemplo: discos.txt de CrystalDiskInfo con un NVMe y un HDD inventados.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nombres en español')]
param()

function Write-CsvHwinfoEs {
    # Una fila cada 2 s. La temperatura de CPU sube y baja ±1 °C alrededor de $Temp (la media queda en $Temp).
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [double]$Temp = 91.1,
        [double]$Mhz = 1900,
        [int]$PctDesaceleracion = 20,
        [double]$Uso = 100,
        [int]$Minutos = 10,
        [string]$Sistema = 'Equipo de ejemplo',
        [string]$Cpu = 'Intel Core i5-1135G7',
        [switch]$SinBom
    )
    $cultura = [Globalization.CultureInfo]::InvariantCulture
    $columnas = @('Uso total de CPU [%]', 'CPU Entera [°C]', 'Desaceleración térmica del núcleo (avg) [Yes/No]', 'Relojes efectivos núcleo (avg) [MHz]', 'CPU Entera [°C]', 'Desaceleración térmica del paquete/anillo [Yes/No]', 'Reloj efectivo promedio [MHz]')
    $encabezado = 'Date,Time,' + (($columnas | ForEach-Object { '"' + $_ + '"' }) -join ',')
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add($encabezado)
    $inicio = [datetime]'2026-10-26 20:05:04'
    $filas = $Minutos * 30
    for ($i = 0; $i -lt $filas; $i++) {
        $t = $inicio.AddSeconds(2 * $i)
        $delta = (-1, 0, 1)[$i % 3]
        $grados = $Temp + $delta   # no $temp: pisaría a $Temp (las variables no distinguen mayúsculas)
        $des = if (($i % 100) -lt $PctDesaceleracion) { 'Yes' } else { 'No' }
        $l.Add(('{0},{1}:{2}:{3}.935,{4},{5},{6},{7},{8},{9},{10}' -f $t.ToString('dd.MM.yyyy', $cultura), $t.Hour, $t.Minute, $t.Second,
                $Uso.ToString('0.0', $cultura), $grados.ToString('0.0', $cultura), $des, $Mhz.ToString('0.0', $cultura), ($grados - 6).ToString('0.0', $cultura), $des, $Mhz.ToString('0.0', $cultura)))
    }
    $l.Add($encabezado)
    # Como en el real: primero el grupo del sistema, después los de la CPU (y los discos, con su serie).
    $grupos = @("Sistema: $Sistema", "CPU [#0]: $Cpu", "CPU [#0]: ${Cpu}: DTS", "CPU [#0]: ${Cpu}: Enhanced", "CPU [#0]: ${Cpu}: DTS", "S.M.A.R.T.: DISCO DE EJEMPLO (EJEMPLO-0001) [C:]", "CPU [#0]: ${Cpu}: Enhanced")
    $l.Add(',,' + ($grupos -join ','))
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Ruta))
    $cod = if ($SinBom) { [Text.Encoding]::Default } else { New-Object Text.UTF8Encoding($true) }
    [IO.File]::WriteAllLines($Ruta, $l, $cod)
}

function Write-DiscosEjemplo {
    # NVMe con 152 errores de medio y 95 % de salud; HDD SATA con 8 reasignados y 2 pendientes.
    param([Parameter(Mandatory)][string]$Ruta)
    $texto = @'
----------------------------------------------------------------------------
CrystalDiskInfo 9.7.2 (C) 2008-2025 hiyohiyo (texto de ejemplo para las pruebas)
----------------------------------------------------------------------------

-- Disk List ---------------------------------------------------------------
 (1) DISCO NVME DE EJEMPLO 512GB : 512,1 GB [0/0/0, pd1] - nv
 (2) DISCO HDD DE EJEMPLO 1TB : 1000,2 GB [1/0/0, pd1]

----------------------------------------------------------------------------
 (1) DISCO NVME DE EJEMPLO 512GB
----------------------------------------------------------------------------
           Model : DISCO NVME DE EJEMPLO 512GB
        Firmware : 1.0EJ
   Serial Number : EJEMPLO-NVME-0001
       Interface : NVM Express
           Disk Size : 512,1 GB
     Temperature : 41 C (105 F)
  Power On Hours : 3200 hours
   Health Status : Bueno (95 %)

-- S.M.A.R.T. --------------------------------------------------------------
ID RawValues(6) Attribute Name
01 000000000000 Critical Warning
02 000000000140 Composite Temperature
03 000000000064 Available Spare
05 000000000005 Percentage Used
0D 00000000000A Unsafe Shutdowns
0E 000000000098 Media and Data Integrity Errors

----------------------------------------------------------------------------
 (2) DISCO HDD DE EJEMPLO 1TB
----------------------------------------------------------------------------
           Model : DISCO HDD DE EJEMPLO 1TB
        Firmware : 0001EJ
   Serial Number : EJEMPLO-HDD-0002
       Interface : Serial ATA
     Temperature : 38 C (100 F)
  Power On Hours : 15000 hours
   Health Status : Precaución

-- S.M.A.R.T. --------------------------------------------------------------
ID Cur Wor Thr RawValues(6) Attribute Name
01 100 100 _51 000000000000 Read Error Rate
05 100 100 _10 000000000008 Reallocated Sectors Count
09 _83 _83 __0 000000003A98 Power-On Hours
C5 100 100 __0 000000000002 Current Pending Sector Count
C6 100 100 __0 000000000000 Uncorrectable Sector Count
'@
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Ruta))
    [IO.File]::WriteAllText($Ruta, ($texto -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))
}
