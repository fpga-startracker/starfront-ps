# Dual-Core AMP Architecture & Memory Partitioning Guide

Comprehensive guide for developing, configuring, and executing **Asymmetric Multiprocessing (AMP)** applications on the **ALINX AX7010 (AMD Zynq-7000 XC7Z010)** system.

---

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Memory Footprint & Headroom Analysis](#2-memory-footprint--headroom-analysis)
3. [Memory Partitioning in `lscript.ld`](#3-memory-partitioning-in-lscriptld)
4. [Step-by-Step: Adding a Core 1 Application](#4-step-by-step-adding-a-core-1-application)
5. [Running Both Cores (CLI & Vitis IDE)](#5-running-both-cores-cli--vitis-ide)
6. [Hardware Resource Sharing & Peripheral Rules](#6-hardware-resource-sharing--peripheral-rules)
7. [Inter-Core Communication (IPC)](#7-inter-core-communication-ipc)
8. [Troubleshooting & Common Pitfalls](#8-troubleshooting--common-pitfalls)

---

## 1. Architecture Overview

The Zynq-7000 APU contains two identical **ARM Cortex-A9 MPCore processors** running at up to 667 MHz:

```text
                                ALINX AX7010 (XC7Z010)
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                 Processing System (PS)                           │
│                                                                                  │
│   ┌──────────────────────────────┐        ┌──────────────────────────────┐       │
│   │    ARM Cortex-A9 Core 0      │        │    ARM Cortex-A9 Core 1      │       │
│   │ ──────────────────────────── │        │ ──────────────────────────── │       │
│   │  - eth_receiver (lwIP 2.2.0) │        │  - star_solver / DSP app     │       │
│   │  - 1000 Mbps Ethernet (GEM0) │        │  - Autonomous computation    │       │
│   │  - USB-UART COM telemetry    │        │  - Zero network interrupts   │       │
│   └──────────────┬───────────────┘        └──────────────┬───────────────┘       │
│                  │                                       │                       │
│                  └───────────────┬───────────────────────┘                       │
│                                  ▼                                               │
│                     Snoop Control Unit (SCU) & L2                                │
│                                  │                                               │
│         ┌────────────────────────┴────────────────────────┐                      │
│         ▼                                                 ▼                      │
│   ┌───────────────┐                             ┌───────────────────┐            │
│   │  256 KB OCM   │                             │  512 MB DDR3 RAM  │            │
│   │ (0xFFFF0000)  │                             │ (0x00100000-0x1F) │            │
│   └───────────────┘                             └───────────────────┘            │
│                                                                                  │
│   ─────────────────────────── AXI Interconnect ────────────────────────────────  │
│                                  │                                               │
│   Programmable Logic (PL): Star Detector Pipeline + AXI-Stream FIFO + HDMI       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

In an **Asymmetric Multiprocessing (AMP)** design:
* **Core 0** runs independent baremetal code dedicated to I/O, networking, and feeding data to the PL.
* **Core 1** runs independent baremetal code (or FreeRTOS) dedicated to compute-heavy tasks (e.g. Star Identification, Lost-In-Space triangle matching, Kalman filters).
* Neither core blocks the other. Core 1 never suffers from Ethernet interrupt latency or packet jitter.

---

## 2. Memory Footprint & Headroom Analysis

The ALINX AX7010 provides **512 MB of DDR3 SDRAM** (Physical address space: `0x00000000` – `0x1FFFFFFF`).

Actual memory consumption of `eth_receiver`:

| Section | Description | Size |
| :--- | :--- | :--- |
| **`.text`** | Machine instructions & compiled code | ~133 KB |
| **`.data`** | Initialized global variables | ~3.5 KB |
| **`.bss`** | lwIP packet pools, DMA buffers, structs | ~3.02 MB |
| **Stack & Heap** | Linker-defined stack and dynamic heap | ~16 KB |
| **Total Used** | Total footprint in physical RAM | **~3.15 MB** |

> [!NOTE]
> `eth_receiver` only uses **0.6%** of the 512 MB RAM. Reducing its partition to 64 MB or 128 MB leaves **tens of megabytes of free headroom**, which has zero impact on network performance or throughput.

---

## 3. Memory Partitioning in `lscript.ld`

To prevent Core 1 from overwriting Core 0's memory, you must divide DDR3 in each application's `lscript.ld`.

### Partition Strategy A: Balanced (256 MB / 256 MB)

Best for general-purpose workloads where both cores need ample heap/buffers.

#### Core 0 Linker Script (`eth_receiver/src/lscript.ld`):
```ld
MEMORY
{
   ps7_ddr_0_memory_0 : ORIGIN = 0x00100000, LENGTH = 0x0FF00000 /* 255 MB for Core 0 */
   ps7_ram_0_memory_0 : ORIGIN = 0x0, LENGTH = 0x30000
   ps7_ram_1_memory_1 : ORIGIN = 0xffff0000, LENGTH = 0xfe00
}
```

#### Core 1 Linker Script (`<your_core1_app>/src/lscript.ld`):
```ld
MEMORY
{
   ps7_ddr_0_memory_0 : ORIGIN = 0x10000000, LENGTH = 0x10000000 /* 256 MB for Core 1 */
   ps7_ram_0_memory_0 : ORIGIN = 0x0, LENGTH = 0x30000
   ps7_ram_1_memory_1 : ORIGIN = 0xffff0000, LENGTH = 0xfe00
}
```

---

### Partition Strategy B: Compute-Heavy (64 MB Core 0 / 448 MB Core 1)

Best if Core 1 needs massive star catalogs, matrix workspaces, or machine learning models.

#### Core 0 Linker Script (`eth_receiver/src/lscript.ld`):
```ld
MEMORY
{
   ps7_ddr_0_memory_0 : ORIGIN = 0x00100000, LENGTH = 0x03F00000 /* ~63 MB for Core 0 */
}
```

#### Core 1 Linker Script (`<your_core1_app>/src/lscript.ld`):
```ld
MEMORY
{
   ps7_ddr_0_memory_0 : ORIGIN = 0x04000000, LENGTH = 0x1C000000 /* 448 MB for Core 1 */
}
```

---

## 4. Step-by-Step: Adding a Core 1 Application

### Step 1: Create the Component
1. In Vitis Unified IDE, click **File -> New Component -> Application Component**.
2. Name it (e.g. `star_solver`).
3. Select the existing `platform` component (standalone on `ps7_cortexa9_0` or create a `ps7_cortexa9_1` domain).

### Step 2: Configure the Linker Script
1. Open `<your_app>/src/lscript.ld`.
2. Locate the `MEMORY` block.
3. Set `ORIGIN = 0x10000000` and `LENGTH = 0x10000000` (or your chosen partition).
4. Save the file.

### Step 3: Write Core 1 Firmware
In Core 1's `main.c`:
```c
#include "xil_printf.h"
#include "xil_cache.h"

int main(void)
{
    /* Note: Core 0 has already initialized the board clocks & PLLs.
     * Core 1 only initializes its own private L1 cache.
     */
    Xil_ICacheEnable();
    Xil_DCacheEnable();

    xil_printf("[CORE 1] Star Solver algorithm running on Core 1!\r\n");

    while (1) {
        /* Computation loop */
    }

    return 0;
}
```

---

## 5. Running Both Cores (CLI & Vitis IDE)

### Method 1: Terminal / Command Line (Fastest)

Our updated [`scripts/run_firmware.tcl`](../scripts/run_firmware.tcl) supports core targeting directly:

```powershell
# 1. Download and run Core 0 (eth_receiver)
.\run.bat eth_receiver 0

# 2. Download and run Core 1 (your second app)
.\run.bat star_solver 1
```

*(On Linux / WSL / Git Bash, use `./run.sh eth_receiver 0` and `./run.sh star_solver 1`)*

### Method 2: Vitis Unified IDE (GUI)

In [`.vscode/launch.json`](../.vscode/launch.json), create a profile for Core 1:
```json
{
  "name": "star_solver (Run on Core 1)",
  "type": "tcf-debug",
  "request": "launch",
  "debugType": "baremetal-zynq",
  "targetSetup": {
    "resetSystem": false,
    "programDevice": false,
    "downloadElf": [
      {
        "core": "ps7_cortexa9_1",
        "resetProcessor": true,
        "elfFile": "${workspaceFolder}/star_solver/build/star_solver.elf",
        "stopAtEntry": false
      }
    ]
  }
}
```

---

## 6. Hardware Resource Sharing & Peripheral Rules

| Hardware Resource | Core 0 | Core 1 | Golden Rule |
| :--- | :--- | :--- | :--- |
| **Gigabit Ethernet (GEM0)** | Primary owner (`lwIP`) | Do NOT touch | Only Core 0 should register GEM interrupts and buffers. |
| **UART0 / UART1 (Serial)** | Primary owner (`xil_printf`) | Shared with care | If both cores call `xil_printf` at the same microsecond, characters interleave. Use a mutex or let Core 0 do all logging. |
| **AXI-Stream FIFO (PL)** | Primary writer / DMA feeder | Reader / Solver | Can be accessed by Core 1 if mapped into Core 1 address space. |
| **Private Watchdog & Timers** | Private (TTC0 / SCU Timer 0) | Private (TTC1 / SCU Timer 1) | Each Cortex-A9 core has its own private SCU Timer. |

---

## 7. Inter-Core Communication (IPC)

When Core 0 receives image packets from Ethernet and needs to notify Core 1:

### Option A: Shared Ring Buffer in On-Chip Memory (OCM) — *Recommended*
* **Location:** `0xFFFF0000` (256 KB).
* Ultra-low latency (~few nanoseconds), accessible by both cores simultaneously.
* Disable cache or use `volatile` pointers on OCM addresses:
  ```c
  #define SHARED_RING_BUF ((volatile shared_data_t *)0xFFFF0000)
  ```

### Option B: Shared DDR3 Window with Cache Flush
* Designate an address between the partitions (e.g. `0x0FFE0000`).
* **Producer (Core 0):**
  ```c
  memcpy((void*)SHARED_ADDR, new_data, size);
  Xil_DCacheFlushRange(SHARED_ADDR, size); /* Push out of L1 cache to RAM */
  ```
* **Consumer (Core 1):**
  ```c
  Xil_DCacheInvalidateRange(SHARED_ADDR, size); /* Discard stale cache line */
  process_data((void*)SHARED_ADDR);
  ```

---

## 8. Troubleshooting & Common Pitfalls

1. **`Cannot halt processor core, timeout`**
   * **Cause:** A previous session issued `rst -system` or a conflicting debugger is open.
   * **Fix:** `.\run.bat` automatically catches this and issues `rst -processor`. If permanently hung, press the **PS-RST** button on the board.

2. **Core 0 crashes immediately when Core 1 starts**
   * **Cause:** Overlapping DDR addresses in `lscript.ld`.
   * **Fix:** Double check that `ORIGIN` of Core 1 is greater than `ORIGIN + LENGTH` of Core 0.

3. **Core 1 sees stale data from Core 0**
   * **Cause:** L1 Data Cache incoherency.
   * **Fix:** Call `Xil_DCacheFlushRange()` on the sender and `Xil_DCacheInvalidateRange()` on the receiver.
