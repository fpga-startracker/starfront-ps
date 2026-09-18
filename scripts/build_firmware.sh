#!/usr/bin/env bash
#=============================================================================
# build_firmware.sh - Compile eth_receiver baremetal firmware using Ninja
#
#   ./scripts/build_firmware.sh
#=============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Autodetect ninja executable
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

if [ -z "$NINJA" ]; then
    echo "ERROR: ninja build tool not found in PATH or standard Vitis locations." >&2
    exit 1
fi

BUILD_DIR="$PROJ_DIR/eth_receiver/build"
if [ ! -d "$BUILD_DIR" ]; then
    echo "ERROR: Build directory $BUILD_DIR not found." >&2
    exit 1
fi

echo "Building eth_receiver firmware using $NINJA..."
"$NINJA" -C "$BUILD_DIR"

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
