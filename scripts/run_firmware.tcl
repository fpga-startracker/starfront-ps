#=============================================================================
# run_firmware.tcl - Load and execute eth_receiver.elf on Core 0 via XSDB/XSCT
#
# Usage:
#   xsct scripts/run_firmware.tcl
#=============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file dirname $script_dir]
set elf_path   "$proj_dir/eth_receiver/build/eth_receiver.elf"

if {![file exists $elf_path]} {
    error "ERROR: ELF file not found at $elf_path. Run scripts/build_firmware.bat first!"
}

connect
targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}
stop
puts "INFO: Downloading $elf_path to Cortex-A9 Core 0..."
dow $elf_path
puts "INFO: Resuming processor execution..."
con
exit
