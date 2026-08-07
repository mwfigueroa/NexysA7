@echo off
REM Programar Nexys A7 desde WSL (OpenFPGALoader)
REM Requiere: placa conectada por USB, usbipd corriendo

echo ==============================================
echo   Nexys A7 - Fast Programmer (OpenFPGALoader)
echo ==============================================
echo.

echo [1] Detectando Nexys A7 en usbipd...
usbipd list | findstr Digilent > nul
if %errorlevel% neq 0 (
    echo   Nexys A7 NO detectada. Conecta la placa por USB.
    pause
    exit /b 1
)

for /f "tokens=1" %%a in ('usbipd list ^| findstr Digilent ^| findstr Nexys') do set BUSID=%%a
if "%BUSID%"=="" (
    echo   No se encontro Nexys A7. Buscando FTDI...
    for /f "tokens=1" %%a in ('usbipd list ^| findstr 0403:6010') do set BUSID=%%a
)

echo   BUSID: %BUSID%

echo [2] Forwardeando a WSL...
usbipd bind -b %BUSID% 2>nul
usbipd attach -w -b %BUSID%

echo [3] Programando...
wsl openFPGALoader -b nexys_a7 /mnt/p/NexysA7/bitstreams/top.bit

echo.
echo Listo.
pause
