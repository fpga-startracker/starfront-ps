# Star Tracker: Embedded PS Firmware & Verification Suite

Baremetal embedded software repository for the **ALINX AX7010** (Zynq XC7Z010CLG400-1) star tracker system.

Running on the **ARM Cortex-A9 Core 0 (`ps7_cortexa9_0`)**, this firmware receives high-speed UDP video frames from the host PC over 1000 Mbps Gigabit Ethernet (GEM0) via **lwIP 2.2.0**, and pushes them into the FPGA PL star detector pipeline via an AXI4-Stream FIFO.

---

## Repository Structure

```text
star_tracker_ps/
├── platform/               # Vitis Platform Component
│   ├── vitis-comp.json     # Platform specification (Standalone OS, BSP libraries)
│   └── hw/
│       └── ax7010_ps_wrapper.xsa  # Hardware handoff archive (PS-PL contract & bitstream)
│
├── eth_receiver/           # Core 0 Firmware Application Component
│   ├── vitis-comp.json     # Application component settings
│   └── src/                # C source code & linker scripts
│       ├── main.c          # Entry point, board initialization, lwIP loop
│       ├── udp_receiver.c  # lwIP UDP receive callback & AXI FIFO streaming driver
│       ├── udp_receiver.h  # Stream buffer definitions
│       └── lscript.ld      # DDR3 memory layout linker script (Core 0 partition)
│
├── scripts/                # Build & Automation Scripts
│   ├── build_firmware.bat  # One-click Ninja build script for eth_receiver.elf
│   ├── run_firmware.tcl    # XSCT JTAG loader script to flash and launch firmware
│   ├── send_star_frame.py  # Python live animated starfield streaming test tool
│   ├── stream_image.py     # Python tool to stream any PNG/JPG/BMP photo to board
│   └── test_udp_echo.py    # Basic UDP connectivity check
│
├── DUST_fpga_set/          # Star dataset (real/synthetic test images & ground truth)
├── .gitignore              # Excludes generated BSP drivers, builds, and logs
└── README.md               # This file
```

---

## Quick Start Guide

### 1. Build the PS Firmware
To build `eth_receiver.elf` from the terminal without opening the Vitis GUI:

```powershell
.\scripts\build_firmware.bat
```
*(Or run `ninja -C eth_receiver/build`)*

### 2. Download and Run on the Board (JTAG)
Ensure your board is powered on and connected via JTAG and Ethernet:

```powershell
& "C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat" scripts\run_firmware.tcl
```
*(Or use `xsct run_ps.tcl`)*

### 3. Stream Images to the FPGA
Once the firmware is running (IP `192.168.1.10:8080`), stream star images from your PC:

```powershell
# Stream live animated synthetic stars at 10 FPS:
python send_star_frame.py --fps 10

# Or stream a real photo to the HDMI display:
python stream_image.py --file path/to/image.png
```

---

## Network Configuration
* **Board IP:** `192.168.1.10`
* **Board Port:** `8080` (UDP)
* **Host PC Static IP:** `192.168.1.50` (Subnet mask `255.255.255.0`)
* **Default Protocol:** 4-byte sync header (`0xAA55AA55`) followed by 640x480 RGB565 scanlines.
