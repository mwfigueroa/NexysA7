[CmdletBinding()]
param(
    [string]$Version = "14.2.0-3",
    [string]$Neorv32Version = "v1.13.3"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root ".toolchains"
$archive = Join-Path $destination "xpack-riscv-none-elf-gcc-$Version-win32-x64.zip"
$folder = Join-Path $destination "xpack-riscv-none-elf-gcc-$Version"
$url = "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$Version/xpack-riscv-none-elf-gcc-$Version-win32-x64.zip"
$ninjaFolder = Join-Path $destination "ninja"
$ninjaArchive = Join-Path $destination "ninja-win.zip"
$neorv32Folder = Join-Path $destination "neorv32"

New-Item -ItemType Directory -Force -Path $destination | Out-Null
if (-not (Test-Path (Join-Path $folder "bin\riscv-none-elf-gcc.exe"))) {
    Write-Host "Descargando xPack GNU RISC-V Embedded GCC $Version..."
    Invoke-WebRequest -Uri $url -OutFile $archive
    Expand-Archive -Path $archive -DestinationPath $destination -Force
    Remove-Item -LiteralPath $archive
}
if (-not (Test-Path (Join-Path $ninjaFolder "ninja.exe"))) {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ninja-build/ninja/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -eq "ninja-win.zip" } | Select-Object -First 1
    if ($null -eq $asset) { throw "No se encontró ninja-win.zip en la última release de Ninja." }
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ninjaArchive
    New-Item -ItemType Directory -Force -Path $ninjaFolder | Out-Null
    Expand-Archive -Path $ninjaArchive -DestinationPath $ninjaFolder -Force
    Remove-Item -LiteralPath $ninjaArchive
}

# La biblioteca de periféricos, crt0.S y el linker script deben venir de la misma
# versión de NEORV32 que el RTL sintetizado en el bitstream. Si el checkout local
# apunta a otra etiqueta se descarta y se vuelve a clonar.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git es necesario para obtener NEORV32. Instálelo y vuelva a ejecutar este script."
}
$currentTag = $null
if (Test-Path (Join-Path $neorv32Folder ".git")) {
    $currentTag = (& git -C $neorv32Folder describe --tags 2>$null | Select-Object -First 1)
}
if ($currentTag -and $currentTag -ne $Neorv32Version) {
    Write-Host "NEORV32 local es $currentTag, se requiere $Neorv32Version. Reemplazando..."
    Remove-Item -LiteralPath $neorv32Folder -Recurse -Force
    $currentTag = $null
}
if (-not $currentTag -or -not (Test-Path (Join-Path $neorv32Folder "sw\common\neorv32.ld"))) {
    if (Test-Path $neorv32Folder) { Remove-Item -LiteralPath $neorv32Folder -Recurse -Force }
    Write-Host "Descargando NEORV32 $Neorv32Version..."
    & git clone --depth 1 --branch $Neorv32Version https://github.com/stnolting/neorv32.git $neorv32Folder
    if ($LASTEXITCODE -ne 0) { throw "No se pudo descargar NEORV32 $Neorv32Version." }
}
Write-Host "NEORV32: $Neorv32Version. Configure con: cmake --preset debug"
