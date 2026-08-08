[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ExeFile,
    # Puerto COM de la UART de FTDI (canal B en la Nexys A7). Si se omite y solo
    # hay un puerto disponible, se usa ese.
    [string]$Port,
    [int]$Baud = 115200,
    # Enviar "e" al final para ejecutar el programa recién cargado.
    [switch]$NoExecute
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ExeFile)) {
    throw "No existe '$ExeFile'. Compile primero: cmake --build --preset debug"
}
[byte[]]$binary = [IO.File]::ReadAllBytes($ExeFile)
if ($binary.Length -lt 16 -or
    $binary[0] -ne 0x4E -or $binary[1] -ne 0x45 -or $binary[2] -ne 0x4F -or $binary[3] -ne 0x21) {
    throw "'$ExeFile' no lleva la cabecera 'NEO!'; no es un ejecutable de bootloader NEORV32."
}

if (-not $Port) {
    $available = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if ($available.Count -eq 1) {
        $Port = $available[0]
    }
    elseif ($available.Count -eq 0) {
        throw "No se detectó ningún puerto serie. Conecte la placa."
    }
    else {
        throw ("Hay varios puertos ({0}). Indique cuál con -Port, p. ej. -Port {1}." -f
            ($available -join ", "), $available[-1])
    }
}

Write-Host ("Puerto {0} @ {1} 8N1 | {2} bytes" -f $Port, $Baud, $binary.Length)
$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$serial.ReadTimeout = 3000
$serial.WriteTimeout = 10000
$serial.Open()
try {
    Start-Sleep -Milliseconds 300

    # Abortar el arranque automático y vaciar lo que haya impreso el bootloader.
    $serial.Write(" ")
    Start-Sleep -Milliseconds 500
    $serial.DiscardInBuffer()

    # Iniciar la carga.
    $serial.Write("u")
    Start-Sleep -Milliseconds 400
    $prompt = ""
    if ($serial.BytesToRead -gt 0) { $prompt = $serial.ReadExisting() }
    if ($prompt -notmatch "Awaiting") {
        throw ("El bootloader no respondió al comando 'u'. Recibido: '{0}'" -f $prompt.Trim())
    }

    Write-Host "Cargando..." -NoNewline
    $serial.Write($binary, 0, $binary.Length)
    Start-Sleep -Seconds 3
    $result = ""
    if ($serial.BytesToRead -gt 0) { $result = $serial.ReadExisting() }
    Write-Host (" " + $result.Trim())
    if ($result -match "ERR") {
        throw "El bootloader rechazó la imagen (checksum o tamaño). Revise IMEM_SIZE."
    }

    if (-not $NoExecute) {
        $serial.Write("e")
        Start-Sleep -Milliseconds 800
        if ($serial.BytesToRead -gt 0) { Write-Host $serial.ReadExisting().Trim() }
        Write-Host "Ejecutando."
    }
}
finally {
    $serial.Close()
    $serial.Dispose()
}
