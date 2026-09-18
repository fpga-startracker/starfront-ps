#!/usr/bin/env bash
#=============================================================================
# launch_system.sh - Unified JTAG System Loader (PL Bitstream + PS Firmware)
#
# Modes:
#   1. Default (PL + PS):  ./run_all.sh
#   2. Custom Bitstream:   ./run_all.sh --bit path/to/file.bit
#   3. PS Only (Fast):     ./run_all.sh --ps-only   (or ./run.sh)
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

TCL_SCRIPT="$SCRIPT_DIR/launch_system.tcl"
"$XSCT" "$TCL_SCRIPT" "$@"
