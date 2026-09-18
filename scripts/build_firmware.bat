@echo off
REM ===========================================================================
REM build_firmware.bat - Compile eth_receiver baremetal firmware using Ninja
REM ===========================================================================

set SCRIPT_DIR=%~dp0
set PROJ_DIR=%SCRIPT_DIR%..
set NINJA_EXE=C:\AMDDesignTools\2025.2\Vitis\bin\ninja.exe

if not exist "%NINJA_EXE%" (
    echo ERROR: ninja.exe not found at %NINJA_EXE%
    exit /b 1
)

echo Building eth_receiver firmware...
"%NINJA_EXE%" -C "%PROJ_DIR%\eth_receiver\build"
if %ERRORLEVEL% equ 0 (
    echo.
    echo =======================================================
    echo BUILD SUCCESS: eth_receiver.elf is up to date!
    echo Location: %PROJ_DIR%\eth_receiver\build\eth_receiver.elf
    echo =======================================================
) else (
    echo.
    echo ERROR: Build failed. Check compiler output above.
    exit /b %ERRORLEVEL%
)
