@echo off
setlocal enabledelayedexpansion
REM ===========================================================================
REM build_firmware.bat - Dynamic build script for eth_receiver baremetal firmware
REM
REM Usage:
REM   .\scripts\build_firmware.bat          (incremental / auto-setup)
REM   .\scripts\build_firmware.bat --full   (cleanly rebuilds platform & app)
REM ===========================================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "PROJ_DIR=%CD%"
popd

REM ---------------------------------------------------------------------------
REM 1. Detect Vitis & Ninja tools dynamically
REM ---------------------------------------------------------------------------
set "VITIS_BAT="
set "NINJA_EXE="

where vitis.bat >nul 2>&1 && for /f "delims=" %%i in ('where vitis.bat') do if not defined VITIS_BAT set "VITIS_BAT=%%i"
where ninja.exe >nul 2>&1 && for /f "delims=" %%i in ('where ninja.exe') do if not defined NINJA_EXE set "NINJA_EXE=%%i"

if not defined VITIS_BAT (
    if exist "C:\AMDDesignTools\2025.2\Vitis\bin\vitis.bat" set "VITIS_BAT=C:\AMDDesignTools\2025.2\Vitis\bin\vitis.bat"
    if exist "C:\Xilinx\2025.2\Vitis\bin\vitis.bat" set "VITIS_BAT=C:\Xilinx\2025.2\Vitis\bin\vitis.bat"
)
if not defined NINJA_EXE (
    if exist "C:\AMDDesignTools\2025.2\Vitis\bin\ninja.exe" set "NINJA_EXE=C:\AMDDesignTools\2025.2\Vitis\bin\ninja.exe"
    if exist "C:\Xilinx\2025.2\Vitis\bin\ninja.exe" set "NINJA_EXE=C:\Xilinx\2025.2\Vitis\bin\ninja.exe"
)

if not defined VITIS_BAT (
    echo ERROR: vitis.bat not found in PATH or standard install paths.
    exit /b 1
)

REM ---------------------------------------------------------------------------
REM 2. Determine build mode
REM ---------------------------------------------------------------------------
set "BUILD_DIR=%PROJ_DIR%\eth_receiver\build"
set "XPFM_FILE=%PROJ_DIR%\platform\export\platform\platform.xpfm"
set "FORCE_FULL=0"

if "%1"=="--full" set "FORCE_FULL=1"
if "%1"=="--clean" set "FORCE_FULL=1"
if "%1"=="-f" set "FORCE_FULL=1"

REM If platform export or ninja build files are missing, run full Vitis generation
if not exist "%XPFM_FILE%" set "FORCE_FULL=1"
if not exist "%BUILD_DIR%\build.ninja" set "FORCE_FULL=1"

if "%FORCE_FULL%"=="1" (
    echo [build_firmware] Running full Vitis generation and build...
    call "%VITIS_BAT%" -s "%SCRIPT_DIR%build_firmware.py" %*
    set "BUILD_STATUS=!ERRORLEVEL!"
) else (
    echo [build_firmware] Running fast incremental build via Ninja...
    "%NINJA_EXE%" -C "%BUILD_DIR%"
    if !ERRORLEVEL! equ 0 (
        set "BUILD_STATUS=0"
    ) else (
        echo [build_firmware] Incremental build failed; falling back to Vitis pipeline...
        call "%VITIS_BAT%" -s "%SCRIPT_DIR%build_firmware.py" %*
        set "BUILD_STATUS=!ERRORLEVEL!"
    )
)

if !BUILD_STATUS! equ 0 (
    echo.
    echo =======================================================
    echo BUILD SUCCESS: eth_receiver.elf is up to date!
    echo Location: %BUILD_DIR%\eth_receiver.elf
    echo =======================================================
    exit /b 0
) else (
    echo.
    echo ERROR: Build failed. Check compiler output above.
    exit /b !BUILD_STATUS!
)
