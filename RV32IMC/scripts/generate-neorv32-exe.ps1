[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$InputFile,
    [Parameter(Mandatory)] [string]$OutputFile,
    # El ELF del que se toma el punto de entrada, igual que hace el flujo oficial
    # de NEORV32 (image_gen -b $(readelf -h ... | Entry point address)).
    [string]$ElfFile,
    # Anula el punto de entrada del ELF si se indica explícitamente.
    [string]$BaseAddress
)

$ErrorActionPreference = "Stop"
[byte[]]$raw = [IO.File]::ReadAllBytes($InputFile)
if ($raw.Length -eq 0) { throw "El ELF aplanado está vacío." }

function Get-ElfEntryPoint([string]$path) {
    [byte[]]$elf = [IO.File]::ReadAllBytes($path)
    if ($elf.Length -lt 28) { throw "El ELF '$path' es demasiado corto." }
    if ($elf[0] -ne 0x7F -or $elf[1] -ne 0x45 -or $elf[2] -ne 0x4C -or $elf[3] -ne 0x46) {
        throw "'$path' no es un ELF (falta la firma \x7FELF)."
    }
    if ($elf[4] -ne 1) { throw "Se esperaba un ELF de 32 bits (EI_CLASS=1) en '$path'." }
    if ($elf[5] -ne 1) { throw "Se esperaba un ELF little-endian (EI_DATA=1) en '$path'." }
    # Elf32_Ehdr.e_entry: desplazamiento 24, 4 bytes little-endian.
    return [BitConverter]::ToUInt32($elf, 24)
}

if ($BaseAddress) {
    if ($BaseAddress -match '^0[xX]') {
        [uint32]$base = [Convert]::ToUInt32($BaseAddress.Substring(2), 16)
    }
    else {
        [uint32]$base = [Convert]::ToUInt32($BaseAddress, 10)
    }
}
elseif ($ElfFile) {
    [uint32]$base = Get-ElfEntryPoint $ElfFile
}
else {
    throw "Indique -ElfFile o -BaseAddress."
}

$paddedSize = [int](4 * [Math]::Ceiling($raw.Length / 4.0))
[byte[]]$image = New-Object byte[] $paddedSize
[Array]::Copy($raw, $image, $raw.Length)

[uint64]$checksum = 0
for ($offset = 0; $offset -lt $image.Length; $offset += 4) {
    [uint32]$word = [BitConverter]::ToUInt32($image, $offset)
    $checksum = ($checksum + [uint64]$word) % 4294967296
}
[uint32]$checksumComplement = [uint32](4294967295 - $checksum)

[byte[]]$header = New-Object byte[] 16
[Array]::Copy([BitConverter]::GetBytes([uint32]0x214f454e), 0, $header, 0, 4) # "NEO!"
[Array]::Copy([BitConverter]::GetBytes($base), 0, $header, 4, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$image.Length), 0, $header, 8, 4)
[Array]::Copy([BitConverter]::GetBytes($checksumComplement), 0, $header, 12, 4)

[byte[]]$output = New-Object byte[] ($header.Length + $image.Length)
[Array]::Copy($header, 0, $output, 0, $header.Length)
[Array]::Copy($image, 0, $output, $header.Length, $image.Length)
[IO.File]::WriteAllBytes($OutputFile, $output)
Write-Host ("NEORV32 EXE: {0} bytes @ 0x{1:X8}, checksum = 0x{2:X8}" -f $image.Length, $base, $checksumComplement)
