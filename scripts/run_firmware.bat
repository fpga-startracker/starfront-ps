@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: run_firmware.bat - Load and execute eth_receiver.elf via XSCT / XSDB
:: =============================================================================

set "SCRIPT_DIR=%~dp0"
set "PROJ_DIR=%SCRIPT_DIR%.."

:: Autodetect XSCT / XSDB executable
set "XSCT="
where xsct >nul 2>&1
if %ERRORLEVEL% equ 0 (
    for /f "delims=" %%I in ('where xsct') do (
        if not defined XSCT set "XSCT=%%I"
    )
)

if not defined XSCT (
    where xsdb >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        for /f "delims=" %%I in ('where xsdb') do (
            if not defined XSCT set "XSCT=%%I"
        )
    )
)

if not defined XSCT (
    if exist "C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat" (
        set "XSCT=C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat"
    ) else if exist "C:\Xilinx\2025.2\Vitis\bin\xsct.bat" (
        set "XSCT=C:\Xilinx\2025.2\Vitis\bin\xsct.bat"
    ) else if exist "C:\Xilinx\Vitis\2025.2\bin\xsct.bat" (
        set "XSCT=C:\Xilinx\Vitis\2025.2\bin\xsct.bat"
    )
)

if not defined XSCT (
    echo ERROR: xsct or xsdb not found in PATH or standard Vitis installation directories. >&2
    exit /b 1
)

set "TCL_SCRIPT=%SCRIPT_DIR%run_firmware.tcl"
call "!XSCT!" "%TCL_SCRIPT%" %*
