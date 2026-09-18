#=============================================================================
# launch_system.tcl - Unified JTAG System Loader (PL Bitstream + PS Firmware)
#
# Modes:
#   1. Default:       Programs default bitstream in _ide/bitstream/, inits PS7,
#                     and downloads/runs PS firmware.
#   2. Custom Bit:    Programs custom bitstream (--bit <path>), inits PS7,
#                     and downloads/runs PS firmware.
#   3. PS Only:       Skips FPGA bitstream, only downloads/runs PS firmware
#                     (--ps-only or --ps).
#
# Usage:
#   xsct scripts/launch_system.tcl [options] [app_name | elf_path] [core_id]
#
# Options:
#   --bit <path>       Specify custom bitstream file (.bit)
#   --ps-only, --ps    Only upload PS firmware (skip FPGA programming)
#   --core <id>        Target ARM Cortex-A9 core: 0 or 1 (default: 0)
#   -h, --help         Show help documentation
#=============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file dirname $script_dir]

# -----------------------------------------------------------------------------
# 1. Parse Command Line Arguments
# -----------------------------------------------------------------------------
set app_arg    "eth_receiver"
set core_id    "0"
set bit_mode   "default"   ;# "default", "custom", or "none"
set custom_bit ""

set i 0
set argc [llength $argv]
while {$i < $argc} {
    set arg [lindex $argv $i]
    if {$arg == "-h" || $arg == "--help" || $arg == "help"} {
        puts {=================================================================}
        puts { Unified Star Tracker System Loader (PL + PS)}
        puts {=================================================================}
        puts {Usage:}
        puts {  run_all.bat [options] [app_name | elf_path] [core_id]}
        puts {}
        puts {Modes:}
        puts {  1. Default Mode (PL + PS):}
        puts {     .\run_all.bat}
        puts {     Programs default bitstream in _ide/bitstream/, inits PS7,}
        puts {     and runs eth_receiver on Core 0.}
        puts {}
        puts {  2. Custom Bitstream Mode (Custom PL + PS):}
        puts {     .\run_all.bat --bit ..\starfront-hdl\build\starfront_sim.bit}
        puts {     Programs specified bitstream, inits PS7, and runs firmware.}
        puts {}
        puts {  3. PS-Only Mode (Fast PS reflash):}
        puts {     .\run_all.bat --ps-only   (or use .\run.bat)}
        puts {     Skips FPGA programming, only downloads & runs PS firmware.}
        puts {}
        puts {Options:}
        puts {  --bit <path>       Path to custom .bit FPGA bitstream file}
        puts {  --ps-only, --ps    Only upload PS firmware (skip FPGA bitstream)}
        puts {  --core <0|1>       Target ARM Cortex-A9 core (default: 0)}
        puts {  app_name           Application name (default: eth_receiver) or .elf}
        puts {}
        puts {Examples:}
        puts {  .\run_all.bat}
        puts {  .\run_all.bat --bit path\to\design.bit}
        puts {  .\run_all.bat --ps-only}
        puts {  .\run_all.bat my_app --bit path\to\design.bit 1}
        puts {=================================================================}
        exit 0
    } elseif {$arg == "--ps-only" || $arg == "--ps" || $arg == "-ps"} {
        set bit_mode "none"
    } elseif {$arg == "--bit" || $arg == "-b"} {
        incr i
        if {$i >= $argc} {
            error "ERROR: Missing path argument for --bit"
        }
        set bit_mode "custom"
        set custom_bit [lindex $argv $i]
    } elseif {$arg == "--core" || $arg == "-c"} {
        incr i
        if {$i >= $argc} {
            error "ERROR: Missing core id argument for --core"
        }
        set core_id [lindex $argv $i]
    } elseif {$arg == "0" || $arg == "1"} {
        set core_id $arg
    } else {
        set app_arg $arg
    }
    incr i
}

if {$core_id != "0" && $core_id != "1"} {
    error "ERROR: Invalid core_id '$core_id'. Expected 0 or 1."
}

# -----------------------------------------------------------------------------
# 2. Resolve Bitstream File
# -----------------------------------------------------------------------------
set bit_file ""
if {$bit_mode == "custom"} {
    if {![file exists $custom_bit]} {
        error "ERROR: Custom bitstream file not found at: $custom_bit"
    }
    set bit_file [file normalize $custom_bit]
} elseif {$bit_mode == "default"} {
    # Search order for default bitstream
    set bit_candidates [list \
        "$proj_dir/eth_receiver/_ide/bitstream/ax7010_ps_wrapper.bit" \
        "$proj_dir/_ide/bitstream/ax7010_ps_wrapper.bit" \
        "$proj_dir/../starfront-hdl/build/starfront_sim.bit" \
        "$proj_dir/platform/export/platform/hw/ax7010_ps_wrapper.bit" \
    ]
    foreach b $bit_candidates {
        if {[file exists $b]} {
            set bit_file [file normalize $b]
            break
        }
    }
    if {$bit_file == ""} {
        puts "WARNING: No default bitstream found in _ide/bitstream/ or starfront-hdl."
        puts "Falling back to PS-only mode."
        set bit_mode "none"
    }
}

# -----------------------------------------------------------------------------
# 3. Resolve ELF Application Binary
# -----------------------------------------------------------------------------
set elf_path ""
set app_name ""

if {[string match -nocase "*.elf" $app_arg] && [file exists $app_arg]} {
    set elf_path [file normalize $app_arg]
    set app_name [file rootname [file tail $app_arg]]
} else {
    set app_name $app_arg
    set elf_candidates [list \
        "$proj_dir/$app_name/build/$app_name.elf" \
        "$proj_dir/$app_name/$app_name.elf" \
        "$proj_dir/build/$app_name.elf" \
    ]
    foreach c $elf_candidates {
        if {[file exists $c]} {
            set elf_path [file normalize $c]
            break
        }
    }
}

if {$elf_path == "" || ![file exists $elf_path]} {
    puts stderr "================================================================="
    puts stderr "ERROR: Firmware binary not found for '$app_arg'!"
    puts stderr "Checked locations:"
    puts stderr "  - $proj_dir/$app_name/build/$app_name.elf"
    puts stderr "  - $proj_dir/$app_name/$app_name.elf"
    puts stderr ""
    puts stderr "Make sure to compile the application first, e.g.:"
    puts stderr "  .\\scripts\\build_firmware.bat"
    puts stderr "================================================================="
    exit 1
}

# Resolve ps7_init.tcl
set ps7_init_tcl ""
set ps7_candidates [list \
    "$proj_dir/eth_receiver/_ide/psinit/ps7_init.tcl" \
    "$proj_dir/platform/export/platform/hw/ps7_init.tcl" \
    "$proj_dir/platform/export/platform/hw/sdt/ps7_init.tcl" \
]
foreach p $ps7_candidates {
    if {[file exists $p]} {
        set ps7_init_tcl [file normalize $p]
        break
    }
}

# -----------------------------------------------------------------------------
# 4. Display Execution Plan & Connect
# -----------------------------------------------------------------------------
puts "================================================================="
puts " Star Tracker Unified System Loader"
puts "================================================================="
if {$bit_mode != "none"} {
    puts " Mode:      PL Bitstream + PS Firmware"
    puts " Bitstream: $bit_file"
} else {
    puts " Mode:      PS Firmware Only (Bitstream skipped)"
}
puts " App:       $app_name"
puts " ELF File:  $elf_path"
puts " Target:    ARM Cortex-A9 Core #$core_id"
puts "================================================================="

connect

# -----------------------------------------------------------------------------
# 5. Program FPGA Bitstream & Initialize PS7 (if requested)
# -----------------------------------------------------------------------------
if {$bit_mode != "none"} {
    puts "INFO: Configuring FPGA with bitstream: $bit_file..."
    targets -set -nocase -filter {name =~ "*xc7z010*"}
    fpga -file $bit_file

    puts "INFO: Initializing PS7 subsystem (PLLs, DDR3, clocks)..."
    targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
    catch {stop}
    catch {configparams force-mem-accesses 1}
    if {$ps7_init_tcl != "" && [file exists $ps7_init_tcl]} {
        source $ps7_init_tcl
        ps7_init
        ps7_post_config
    } else {
        puts "WARNING: ps7_init.tcl not found, skipping PS7 peripheral re-init."
    }
}

# -----------------------------------------------------------------------------
# 6. Target Specific Core & Suspend
# -----------------------------------------------------------------------------
set target_filter "*Cortex-A9*#$core_id*"
set matched_targets [targets -filter "name =~ \"$target_filter\""]
if {[llength $matched_targets] == 0} {
    puts stderr "ERROR: No target matching '$target_filter' found on JTAG chain."
    exit 1
}

targets -set -nocase -filter "name =~ \"$target_filter\""

if {[catch {stop} err]} {
    puts "INFO: Core #$core_id halt timed out ($err). Issuing processor reset..."
    catch {rst -processor}
    after 300
    catch {stop}
}

# -----------------------------------------------------------------------------
# 7. Download ELF and Resume Execution
# -----------------------------------------------------------------------------
puts "INFO: Downloading $elf_path to Core #$core_id..."
dow $elf_path

puts "INFO: Resuming processor execution on Core #$core_id..."
con

puts ""
puts "================================================================="
puts " SUCCESS: System running on ALINX AX7010!"
if {$bit_mode != "none"} {
    puts " - FPGA PL configured with bitstream."
}
puts " - '$app_name' executing on Cortex-A9 Core #$core_id."
puts " - Check USB-UART terminal (115200 baud) for application logs."
puts "================================================================="
exit 0
