#!/usr/bin/env python3
"""
build_firmware.py - Dynamic automated build script for starfront-ps.
Executes under Vitis Python ('vitis -s scripts/build_firmware.py') or standalone.
"""

import os
import sys
import shutil
import subprocess

def log(msg):
    print(f"[build_firmware] {msg}", flush=True)

def find_xsa(proj_dir, hdl_dir):
    candidates = [
        os.path.join(hdl_dir, "build", "ax7010_ps", "ax7010_ps_wrapper.xsa"),
        os.path.join(proj_dir, "platform", "hw", "ax7010_ps_wrapper.xsa")
    ]
    for c in candidates:
        if os.path.isfile(c):
            return os.path.abspath(c)
    return None

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    proj_dir = os.path.dirname(script_dir)
    hdl_dir = os.path.abspath(os.path.join(proj_dir, "..", "starfront-hdl"))

    force_full = "--full" in sys.argv or "--clean" in sys.argv or "-f" in sys.argv

    log(f"Project directory: {proj_dir}")
    log(f"HDL directory:     {hdl_dir}")

    # Resolve XSA
    xsa_path = find_xsa(proj_dir, hdl_dir)
    if not xsa_path:
        log("ERROR: ax7010_ps_wrapper.xsa not found in starfront-hdl build or platform/hw.")
        sys.exit(1)
    log(f"Using XSA: {xsa_path}")

    # Update platform/hw/ax7010_ps_wrapper.xsa copy
    local_hw_dir = os.path.join(proj_dir, "platform", "hw")
    os.makedirs(local_hw_dir, exist_ok=True)
    local_xsa = os.path.join(local_hw_dir, "ax7010_ps_wrapper.xsa")
    if os.path.abspath(xsa_path) != os.path.abspath(local_xsa):
        shutil.copy2(xsa_path, local_xsa)
        log(f"Synchronized XSA to {local_xsa}")

    import vitis

    client = vitis.create_client()
    try:
        client.set_workspace(path=proj_dir)
    except Exception:
        client.update_workspace(path=proj_dir)

    xpfm_file = os.path.join(proj_dir, "platform", "export", "platform", "platform.xpfm")
    needs_plat_build = force_full or (not os.path.isfile(xpfm_file))

    if not needs_plat_build and os.path.exists(local_xsa):
        if os.path.getmtime(local_xsa) > os.path.getmtime(xpfm_file):
            log("XSA is newer than platform export. Rebuilding platform...")
            needs_plat_build = True

    if needs_plat_build:
        log("Configuring and building platform component...")
        temp_xsa = os.path.join(proj_dir, "_active_hw.xsa")
        shutil.copy2(xsa_path, temp_xsa)

        try:
            client.delete_component(name="platform")
        except Exception:
            pass

        plat_dir = os.path.join(proj_dir, "platform")
        if os.path.exists(plat_dir):
            shutil.rmtree(plat_dir)

        plat = client.create_platform_component(
            name="platform",
            hw_design=temp_xsa,
            os="standalone",
            cpu="ps7_cortexa9_0",
            domain_name="standalone_ps7_cortexa9_0",
            compiler="gcc",
            no_boot_bsp=True
        )

        dom = plat.get_domain(name="standalone_ps7_cortexa9_0")
        log("Adding lwip220 library to standalone domain...")
        dom.set_lib(lib_name="lwip220")

        log("Compiling platform BSP...")
        plat_res = plat.build()
        if plat_res != 0 and plat_res is not None and plat_res is not True:
            log(f"ERROR: Platform build failed with status {plat_res}")
            sys.exit(1)

        os.makedirs(local_hw_dir, exist_ok=True)
        shutil.copy2(temp_xsa, local_xsa)
        if os.path.exists(temp_xsa):
            os.remove(temp_xsa)
        log("Platform build finished successfully.")
    else:
        log("Platform export is up to date.")

    # Update app.yaml domain_path dynamically if present
    app_yaml = os.path.join(proj_dir, "eth_receiver", "src", "app.yaml")
    domain_sw_dir = os.path.join(proj_dir, "platform", "export", "platform", "sw", "standalone_ps7_cortexa9_0")
    if os.path.isfile(app_yaml):
        with open(app_yaml, "r") as f:
            lines = f.readlines()
        new_lines = []
        for line in lines:
            if line.strip().startswith("domain_path:"):
                new_lines.append(f"domain_path: {domain_sw_dir}\n")
            else:
                new_lines.append(line)
        with open(app_yaml, "w") as f:
            f.writelines(new_lines)

    # Build eth_receiver
    log("Building eth_receiver application component...")
    try:
        app = client.get_component(name="eth_receiver")
    except Exception:
        app = client.create_app_component(
            name="eth_receiver",
            platform=xpfm_file,
            domain="standalone_ps7_cortexa9_0"
        )

    app_res = app.build()
    if app_res != 0 and app_res is not None and app_res is not True:
        log(f"ERROR: eth_receiver build failed with status {app_res}")
        sys.exit(1)

    elf_file = os.path.join(proj_dir, "eth_receiver", "build", "eth_receiver.elf")
    if not os.path.isfile(elf_file):
        log(f"ERROR: Expected binary not found: {elf_file}")
        sys.exit(1)

    size = os.path.getsize(elf_file)
    log("=" * 60)
    log("BUILD SUCCESS: eth_receiver.elf is ready!")
    log(f"Location: {elf_file}")
    log(f"Size:     {size:,} bytes")
    log("=" * 60)

    vitis.dispose()

if __name__ == "__main__":
    main()
