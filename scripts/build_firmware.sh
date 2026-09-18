#!/usr/bin/env bash
#=============================================================================
# build_firmware.sh - Dynamic build script for eth_receiver baremetal firmware
#
# Usage:
#   ./scripts/build_firmware.sh          (incremental / auto-setup)
#   ./scripts/build_firmware.sh --full   (cleanly rebuilds platform & app)
#=============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# -----------------------------------------------------------------------------
# 1. Autodetect tools dynamically
# -----------------------------------------------------------------------------
VITIS=""
if command -v vitis >/dev/null 2>&1; then
    VITIS="$(command -v vitis)"
elif [ -f "/c/AMDDesignTools/2025.2/Vitis/bin/vitis.bat" ]; then
    VITIS="/c/AMDDesignTools/2025.2/Vitis/bin/vitis.bat"
elif [ -f "C:/AMDDesignTools/2025.2/Vitis/bin/vitis.bat" ]; then
    VITIS="C:/AMDDesignTools/2025.2/Vitis/bin/vitis.bat"
elif [ -f "/tools/Xilinx/2025.2/Vitis/bin/vitis" ]; then
    VITIS="/tools/Xilinx/2025.2/Vitis/bin/vitis"
fi

NINJA=""
if command -v ninja >/dev/null 2>&1; then
    NINJA="$(command -v ninja)"
elif [ -f "/c/AMDDesignTools/2025.2/Vitis/bin/ninja.exe" ]; then
    NINJA="/c/AMDDesignTools/2025.2/Vitis/bin/ninja.exe"
elif [ -f "C:/AMDDesignTools/2025.2/Vitis/bin/ninja.exe" ]; then
    NINJA="C:/AMDDesignTools/2025.2/Vitis/bin/ninja.exe"
elif [ -f "/tools/Xilinx/2025.2/Vitis/bin/ninja" ]; then
    NINJA="/tools/Xilinx/2025.2/Vitis/bin/ninja"
fi

if [ -z "$VITIS" ]; then
    echo "ERROR: Vitis executable not found in PATH or standard installation paths." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. Determine build mode
# -----------------------------------------------------------------------------
BUILD_DIR="$PROJ_DIR/eth_receiver/build"
XPFM_FILE="$PROJ_DIR/platform/export/platform/platform.xpfm"
FORCE_FULL=0

for arg in "$@"; do
    if [ "$arg" = "--full" ] || [ "$arg" = "--clean" ] || [ "$arg" = "-f" ]; then
        FORCE_FULL=1
    fi
done

if [ ! -f "$XPFM_FILE" ] || [ ! -f "$BUILD_DIR/build.ninja" ]; then
    FORCE_FULL=1
fi

if [ "$FORCE_FULL" -eq 1 ]; then
    echo "[build_firmware] Running full Vitis generation and build..."
    "$VITIS" -s "$SCRIPT_DIR/build_firmware.py" "$@"
else
    echo "[build_firmware] Running fast incremental build via Ninja..."
    if [ -n "$NINJA" ] && "$NINJA" -C "$BUILD_DIR"; then
        true
    else
        echo "[build_firmware] Incremental build failed; falling back to Vitis pipeline..."
        "$VITIS" -s "$SCRIPT_DIR/build_firmware.py" "$@"
    fi
fi

ELF_FILE="$BUILD_DIR/eth_receiver.elf"
if [ -f "$ELF_FILE" ]; then
    echo ""
    echo "======================================================="
    echo "BUILD SUCCESS: eth_receiver.elf is up to date!"
    echo "Location: $ELF_FILE"
    echo "======================================================="
else
    echo "ERROR: Expected output $ELF_FILE not found." >&2
    exit 1
fi
