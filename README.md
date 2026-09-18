# Star Tracker: Embedded PS Firmware & Verification Suite

Baremetal embedded software repository for the **ALINX AX7010** (AMD Zynq XC7Z010CLG400-1) star tracker system.

Running on the **ARM Cortex-A9 Core 0 (`ps7_cortexa9_0`)**, this firmware receives high-speed UDP video frames from the host PC over 1000 Mbps Gigabit Ethernet (GEM0) via **lwIP 2.2.0**, and pushes them into the FPGA PL star detector pipeline via an AXI4-Stream FIFO. Supports dual-core **Asymmetric Multiprocessing (AMP)** with Core 1 for autonomous attitude solving.

---

## Repository Structure

```text
starfront-ps/
├── platform/                     # Vitis Platform Component
│   ├── vitis-comp.json           # Platform specification (Standalone OS, BSP libraries)
│   └── hw/
│       └── ax7010_ps_wrapper.xsa # Hardware handoff archive (PS-PL contract & base bitstream)
│
├── eth_receiver/                 # Core 0 Firmware Application Component
│   ├── vitis-comp.json           # Application component settings
│   └── src/                      # C source code & linker scripts
│       ├── main.c                # Entry point, board initialization, lwIP loop
│       ├── udp_receiver.c        # lwIP UDP receive callback & AXI FIFO streaming driver
│       ├── udp_receiver.h        # Stream buffer definitions
│       └── lscript.ld            # DDR3 memory layout linker script (Core 0 partition)
│
├── scripts/                      # Build & Automation Scripts
│   ├── build_firmware.bat        # Fast Ninja incremental build + Vitis CLI fallback (Win)
│   ├── build_firmware.sh         # Fast Ninja incremental build + Vitis CLI fallback (Linux)
│   ├── build_firmware.py         # Automated headless Vitis Unified CLI pipeline
│   ├── launch_system.bat         # Unified JTAG loader (PL bitstream + PS firmware)
│   ├── launch_system.sh          # Bash version of unified system loader
│   ├── launch_system.tcl         # XSCT script supporting Default, --bit, and --ps-only
│   ├── run_firmware.bat          # Fast dedicated PS-only loader (Win)
│   ├── run_firmware.sh           # Fast dedicated PS-only loader (Linux)
│   ├── run_firmware.tcl          # XSCT loader with processor auto-recovery & core selection
│   ├── send_star_frame.py        # Python live animated starfield streaming test tool
│   ├── stream_image.py           # Python tool to stream any PNG/JPG/BMP photo to board
│   └── test_udp_echo.py          # Basic UDP connectivity & round-trip echo check
│
├── Docs/                         # Documentation & Architectural Guides
│   └── README.md                 # Dual-Core AMP architecture, memory partitioning & IPC
│
├── DUST_fpga_set/                # Star dataset (real/synthetic test images & ground truth)
├── run_all.bat / run_all.sh      # Root forwarders: Full system load (PL Bitstream + PS Firmware)
├── run.bat / run.sh              # Root forwarders: Fast PS firmware loader (~2s)
├── build.sh                      # Root forwarder: Build firmware via Bash
├── .gitignore                    # Excludes build trees, local .vscode/, and temporary logs
└── README.md                     # This file
```

---

## Quick Start Guide

### 1. Build the Firmware
Compile `eth_receiver.elf` dynamically without opening the Vitis GUI:

* **Windows (CMD / PowerShell):**
  ```powershell
  .\scripts\build_firmware.bat          # Fast incremental build via Ninja (~2s)
  .\scripts\build_firmware.bat --full   # Cleanly regenerates platform & rebuilds
  ```
* **Linux / Git Bash / macOS:**
  ```bash
  ./build.sh                            # Fast incremental build
  ./build.sh --full                     # Full clean rebuild
  ```

---

### 2. Download and Run on Hardware (JTAG)
Ensure the board is powered on with jumper **J13 set to JTAG** and connected via USB and Ethernet:

#### Option A: Full System Loader (`run_all.bat` / `./run_all.sh`)
Loads both the FPGA PL bitstream and the ARM PS firmware in one shot:

```powershell
# Mode 1: Default PL + PS (programs bitstream in eth_receiver/_ide/bitstream/ + runs firmware)
.\run_all.bat

# Mode 2: Custom Bitstream PL + PS (programs specified bitstream + runs firmware)
.\run_all.bat --bit ..\starfront-hdl\build\starfront_sim.bit

# Mode 3: PS-Only Mode (skips FPGA programming, only downloads & runs firmware)
.\run_all.bat --ps-only
```

#### Option B: Fast Dedicated PS Loader (`run.bat` / `./run.sh`)
When developing C code and the FPGA PL is already running (LED1 blinking at ~1.5 Hz):

```powershell
.\run.bat                     # Runs eth_receiver on Core 0 (~2s)
.\run.bat <app_name>          # Runs another application on Core 0
.\run.bat <app_name> 1        # Runs application on Core 1 (Dual-Core AMP)
.\run.bat path\to\file.elf    # Runs arbitrary ELF directly
```
*(Pass `--help` to `run_all.bat` or `run.bat` to see all available flags)*

---

### 3. Verify Serial Output & Stream Test Images

1. Open your serial terminal (PuTTY, Tera Term, or VS Code Serial Monitor) on the board's COM port:
   * **Baud Rate:** `115200`, Data: `8-bit`, Parity: `None`, Stop: `1-bit`.
   * You will see the lwIP startup banner:
     ```text
     ====================================================
       Star Tracker PS - Ethernet UDP Receiver & Echo    
       Target: ALINX AX7010 (Zynq-7000 XC7Z010)          
     ====================================================
     [INIT] Initializing lwIP stack...
     [INIT] Board IP: 192.168.1.10:8080
     ```

2. From your host PC (configured with Static IP `192.168.1.50`), stream star images:
   ```powershell
   # Quick connectivity check:
   python scripts\test_udp_echo.py

   # Stream live animated synthetic stars at 10 FPS:
   python scripts\send_star_frame.py --fps 10

   # Stream a real photo to the HDMI display:
   python scripts\stream_image.py --file DUST_fpga_set\test_sample.png
   ```

---

### 4. Running / Debugging in Vitis Unified IDE (GUI)

If you prefer using the graphical debugger:
1. Open Vitis Unified IDE with the workspace:
   ```powershell
   & "C:\AMDDesignTools\2025.2\Vitis\bin\vitis.bat" -w "C:\Users\Win11\Desktop\Home\FPGA\StarTest\starfront-ps"
   ```
2. Open the **Run and Debug** view (`Ctrl+Shift+D`).
3. Select **`eth_receiver (Run on Hardware)`** or **`eth_receiver (Debug on Hardware)`**.
4. Press **F5** to start execution.

---

## Network Configuration

* **Board IP:** `192.168.1.10`
* **Board Port:** `8080` (UDP)
* **Host PC Static IP:** `192.168.1.50` (Subnet mask `255.255.255.0`)
* **Protocol:** 4-byte sync header (`0xAA55AA55`) followed by 640x480 RGB565 scanlines.

---

## Dual-Core AMP & Memory Architecture

The Zynq-7000 features dual ARM Cortex-A9 cores sharing 512 MB DDR3:
* **Core 0 (`ps7_cortexa9_0`):** Dedicated to Ethernet I/O, lwIP, and streaming scanlines to the PL FIFO. (Only consumes ~3.15 MB out of 512 MB).
* **Core 1 (`ps7_cortexa9_1`):** Dedicated to compute-heavy star identification and attitude determination without network interrupt latency.

For step-by-step instructions on partitioning DDR3 in `lscript.ld`, adding a Core 1 application, and setting up Inter-Core Communication (IPC), read the comprehensive [Dual-Core AMP Guide in `Docs/README.md`](Docs/README.md).
