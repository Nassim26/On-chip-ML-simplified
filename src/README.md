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
  - **Accelerator(s) of choice**
    - Of course, you will need to set-up your AXI4Stream-compatible accelerator(s) of choice in the PL

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
    - If you have multiple accelerators, you can use part of the control payload as control bit(s) of a mux routing data to a different accelerator accordingly!
- RTL behavior:
  - When `tvalid && tready`, latch payload directly into registers -- transfers occur only when `tvalid == 1'b1 && tready == 1'b1`
  - No buffering, no FSMs required
  - Single-cycle configuration latency
  - Avoid combinational dependencies between `tvalid` and `tready`
  - If DMA hangs, inspect these signals with an ILA

## Python / PYNQ Usage
### Loading the Overlay
Example:
```python
from pynq import Overlay

overlay = Overlay("cnn.bit")

dma_ctrl = overlay.control_dma   # name from .hwh
dma_data = overlay.axi_dma
```
If you can't find your IP, use `help(overlay)` to find them. 

### Buffer Allocation & Data Types
- Use `pynq.allocate` for DMA buffers
- Buffers are (e.g. NumPy) arrays backed by contiguous physical memory
- NumPy dtypes are preserved across DMA

Example:
```python
import numpy as np
from pynq import allocate

input_buffer  = allocate((28, 28), dtype=np.uint8)
output_buffer = allocate((26, 26), dtype=np.uint8)
```

End-to-end example:
```python
import numpy as np
from pynq import Overlay, allocate

overlay = Overlay("cnn.bit")
dma_ctrl = overlay.control_dma
dma_data = overlay.axi_dma

# Kernel + bias
kernel = np.array(
    [1,2,1,
     2,4,2,
     1,2,1,
     0],
    dtype=np.uint8
)

# Input image
input_buffer = allocate((28,28), dtype=np.uint8)
output_buffer = allocate((26,26), dtype=np.uint8)

input_buffer[:] = np.random.randint(0, 256, (28,28), dtype=np.uint8)

# Send control word
dma_ctrl.sendchannel.transfer(kernel)
dma_ctrl.sendchannel.wait()

# Send image, receive output
dma_data.sendchannel.transfer(input_buffer)
dma_data.recvchannel.transfer(output_buffer)

dma_data.sendchannel.wait()
dma_data.recvchannel.wait()

result = output_buffer.copy()
```
In the full CNN project, the code above is wrapped into a PyTorch compatible function: 
```python
def FPGA_conv(image_tensor, kernel_tensor):
    # Convert PyTorch → NumPy
    img = image_tensor.detach().cpu().numpy().astype(np.uint8)
    kernel = kernel_tensor.detach().cpu().numpy().astype(np.uint8)

    in_buf = allocate(img.shape, dtype=np.uint8)
    out_buf = allocate((img.shape[0]-2, img.shape[1]-2), dtype=np.uint8)

    in_buf[:] = img

    dma_ctrl.sendchannel.transfer(kernel)
    dma_ctrl.sendchannel.wait()

    dma_data.sendchannel.transfer(in_buf)
    dma_data.recvchannel.transfer(out_buf)
    dma_data.sendchannel.wait()
    dma_data.recvchannel.wait()

    return out_buf.copy()
```
This function is called in the `forward(...)` member function of a copy of the standard Conv2D class of PyTorch (conveniently titled FPGA_Conv2D), whilst preserving its `backward(...)` functionality. This effectively decouples the forward pass (now taking place in the PL) from the autograd backward pass, much like a surrogate gradient for quantized forward-passes or for SNNs would be implemented. This allows for seamless integration into PyTorch pipelines. 

### Batch Parallelism via Memory Layout

To process multiple images in parallel:
- Store (image) data as a 3D NumPy array, `(HEIGHT, WIDTH, N_IMAGES)` (in PyTorch, `N_IMAGES` could be your batch size, or number of channels)
- NumPy is row-major, so memory is laid out as:
```
img1_pixel0, img2_pixel0, ..., imgN_pixel0,
img1_pixel1, img2_pixel1, ..., imgN_pixel1,
...
```
If:
- N_IMAGES = 4
- each pixel = 8 bits

Then:
- You can configure each DMA beat to be 32 bits
- PL receives concatenated {img1_px, img2_px, img3_px, img4_px} every cycle
- Each byte can be routed to a separate accelerator instance
- Which allows you to exploit spatial parallelism! 

### Cache coherency note
On most modern PYNQ platforms, buffers allocated with pynq.allocate() are either non-cacheable or hardware-coherent, so explicit cache maintenance is not required.
If you are using a platform or memory configuration without PS–PL cache coherency, then:
- Call input_buffer.flush() before a DMA read (PS → PL)
- Call output_buffer.invalidate() after a DMA write (PL → PS)

But I have not had to use either, ever. 
