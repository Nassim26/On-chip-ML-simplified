## Overview

**Architecture summary**

- **Two independent AXI DMA instances**
  - **Control DMA**  
    - One-way (PS → PL)
    - Sends a *single compact control message* containing:
      - 3×3 kernel weights
      - bias
      - optional configuration / mux bits
      - ...for a CNN, but you should configure this to your own needs!
    - In RTL, the control word is latched into registers in a single clock cycle when `tvalid && tready`.
  - **Data DMA**
    - Used for streaming image data to the CNN and streaming results back
    - Handles large, contiguous buffers (e.g. MNIST images)

- **Host-side control via Python (PYNQ)**
  - DMA buffers allocated from contiguous memory
  - Kernel + image data transferred using standard `sendchannel` / `recvchannel` calls
  - Easily wrapped into a Python function callable from, e.g., PyTorch code

---

## Prerequisites

### Hardware
- Xilinx SoC platform with ARM + PL (e.g. KV260 / KR260 / Zynq UltraScale+)

### Software
- **Vivado** (version compatible with PYNQ release)
- **Linux on the FPGA**
  - Ubuntu 24.04 LTS for KV260 works well if you want a full desktop OS: <https://ubuntu.com/certified/202104-28895>
      - Though very slow in my experience; a more streamlined OS might do you well
  - Flash SD card using Rufus / Etcher / `dd`
- **Python + PYNQ**
  - Install `pynq` via `pip`
  - You do not need the full PYNQ Linux image; PYNQ is a Python library and works fine on Ubuntu LTS

### Required Vivado outputs
From your Vivado project:
- `.bit` — FPGA bitstream
- `.hwh` — hardware handoff file  

These must be placed next to your Python code on the microcontroller of the FPGA so PYNQ can discover the IPs. You can do this over git, I did it over Google Drive... (not recommended!)

---

## Getting Started

Before continuing, read Parts 1 & 2 of the official PYNQ DMA tutorial:

- Part 1 — Hardware design  
  <https://discuss.pynq.io/t/tutorial-pynq-dma-part-1-hardware-design/3133>

- Part 2 — Using DMA from Python  
  <https://discuss.pynq.io/t/tutorial-pynq-dma-part-2-using-the-dma-from-pynq/3134>

This README builds directly on that workflow.

---

## Repository Structure
- All CNN-related RTL lives under `/verilog` so you have an example to compare with
- The `.bit` and `.hwh` files come directly from Vivado
- Python code assumes these files are in the same directory
---

## Hardware Design Notes (Vivado)

### 1. Dual-DMA setup
- Instantiate **two AXI DMA IPs**
  - Control DMA: MM2S only (write-only)
  - Data DMA: MM2S + S2MM (read + write)
- Both connect to PS memory via AXI interconnect
- Stream interfaces connect to your PL logic

### 2. Control DMA semantics
- Control message is small and fixed-size
- Example payload, for the CNN (10 bytes, `uint8`):
  ```
  [w0, w1, w2,
  w3, w4, w5,
  w6, w7, w8,
  bias]
  ```

