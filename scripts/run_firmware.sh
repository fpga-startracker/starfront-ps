#!/usr/bin/env bash
#=============================================================================
# run_firmware.sh - Load and execute eth_receiver.elf via XSCT / XSDB
#
#   ./scripts/run_firmware.sh
#=============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Autodetect XSCT / XSDB executable
XSCT=""
if command -v xsct >/dev/null 2>&1; then
    XSCT="$(command -v xsct)"
elif command -v xsdb >/dev/null 2>&1; then
    XSCT="$(command -v xsdb)"
elif [ -f "/c/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" ]; then
    XSCT="/c/AMDDesignTools/2025.2/Vitis/bin/xsct.bat"
elif [ -f "C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat" ]; then
    XSCT="C:/AMDDesignTools/2025.2/Vitis/bin/xsct.bat"
elif [ -f "/tools/Xilinx/2025.2/Vitis/bin/xsct" ]; then
    XSCT="/tools/Xilinx/2025.2/Vitis/bin/xsct"
fi

if [ -z "$XSCT" ]; then
    echo "ERROR: xsct or xsdb not found in PATH or standard Vitis locations." >&2
    exit 1
fi

TCL_SCRIPT="$SCRIPT_DIR/run_firmware.tcl"
echo "Launching firmware via XSCT: $XSCT..."
"$XSCT" "$TCL_SCRIPT"
