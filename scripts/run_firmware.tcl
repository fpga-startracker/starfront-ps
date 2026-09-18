#=============================================================================
# run_firmware.tcl - Load and execute baremetal firmware on Zynq-7000 via XSCT
#
# Usage:
#   xsct scripts/run_firmware.tcl [app_name | elf_path] [core_id]
#
# Examples:
#   .\run.bat                         # Defaults to eth_receiver on Core 0
#   .\run.bat eth_receiver            # Run eth_receiver on Core 0
#   .\run.bat my_app                  # Run my_app on Core 0
#   .\run.bat my_app 1                # Run my_app on Core 1 (Dual-Core AMP)
#   .\run.bat path/to/firmware.elf 0  # Run arbitrary ELF on Core 0
#=============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file dirname $script_dir]

# -----------------------------------------------------------------------------
# 1. Parse Arguments
# -----------------------------------------------------------------------------
set app_arg "eth_receiver"
set core_id "0"

if {[llength $argv] > 0} {
    set first_arg [lindex $argv 0]
    if {$first_arg == "-h" || $first_arg == "--help" || $first_arg == "help"} {
        puts {=================================================================}
        puts { Star Tracker PS Firmware Loader (XSCT / JTAG)}
        puts {=================================================================}
        puts {Usage:}
        puts {  run.bat [app_name | elf_path] [core_id]}
        puts {}
        puts {Arguments:}
        puts {  app_name   Name of the application component (default: eth_receiver)}
        puts {             OR a direct relative/absolute path to an .elf file.}
        puts {  core_id    ARM Cortex-A9 core: 0 or 1 (default: 0)}
        puts {}
        puts {Examples:}
        puts {  .\run.bat                    Load eth_receiver on Core 0}
        puts {  .\run.bat eth_receiver       Load eth_receiver on Core 0}
        puts {  .\run.bat sensor_app         Load sensor_app on Core 0}
        puts {  .\run.bat tracker_dsp 1      Load tracker_dsp on Core 1 (AMP)}
        puts {  .\run.bat path\to\app.elf 0  Load custom ELF file on Core 0}
        puts {=================================================================}
        exit 0
    }
    set app_arg $first_arg
}

if {[llength $argv] > 1} {
    set core_id [lindex $argv 1]
    if {$core_id != "0" && $core_id != "1"} {
        error "ERROR: Invalid core_id '$core_id'. Expected 0 or 1."
    }
}

# -----------------------------------------------------------------------------
# 2. Resolve ELF path dynamically
# -----------------------------------------------------------------------------
set elf_path ""
set app_name ""

if {[string match -nocase "*.elf" $app_arg] && [file exists $app_arg]} {
    set elf_path [file normalize $app_arg]
    set app_name [file rootname [file tail $app_arg]]
} else {
    set app_name $app_arg
    set candidates [list \
        "$proj_dir/$app_name/build/$app_name.elf" \
        "$proj_dir/$app_name/$app_name.elf" \
        "$proj_dir/build/$app_name.elf" \
    ]
    foreach c $candidates {
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
    puts stderr "Make sure to build the application first, e.g.:"
    puts stderr "  .\\scripts\\build_firmware.bat"
    puts stderr "================================================================="
    exit 1
}

# -----------------------------------------------------------------------------
# 3. Connect to Hardware Server & Target Core
# -----------------------------------------------------------------------------
puts "================================================================="
puts " Target: Cortex-A9 Core #$core_id"
puts " Application: $app_name"
puts " ELF File: $elf_path"
puts "================================================================="

connect
set target_filter "*Cortex-A9*#$core_id*"
set matched_targets [targets -filter "name =~ \"$target_filter\""]

if {[llength $matched_targets] == 0} {
    puts stderr "ERROR: No target matching '$target_filter' found on JTAG chain."
    puts stderr "Available targets:"
    puts stderr [targets]
    exit 1
}

targets -set -nocase -filter "name =~ \"$target_filter\""

# -----------------------------------------------------------------------------
# 4. Suspend Core (with auto-recovery if locked/sleeping)
# -----------------------------------------------------------------------------
if {[catch {stop} err]} {
    puts "INFO: Processor halt timed out on Core $core_id ($err). Resetting processor core..."
    catch {rst -processor}
    after 300
    catch {stop}
}

# -----------------------------------------------------------------------------
# 5. Download and Run
# -----------------------------------------------------------------------------
puts "INFO: Downloading $elf_path to Cortex-A9 Core $core_id..."
dow $elf_path

puts "INFO: Resuming processor execution on Core $core_id..."
con

puts ""
puts "================================================================="
puts " SUCCESS: '$app_name' is running on Cortex-A9 Core #$core_id"
puts " Check UART serial terminal (115200 baud) for application logs."
puts "================================================================="
exit 0
