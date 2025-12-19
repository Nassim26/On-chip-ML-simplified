# How to navigate this directory?
This directory contains the necessary source code and instructions to set-up a project deploying the SoC FPGA co-designed ML system.

# Instructions
Copied from chat with Wenxuan. TODO: formalize.

Part 1 & part 2 of this tutorial series useful to set everything up: https://discuss.pynq.io/t/tutorial-pynq-dma-part-1-hardware-design/3133. 

So what I did, as you might remember, was initialize two separate DMA modules: one for the control path and one for the data path. Then, using the PYNQ code as described in pt.2 of this tutorial, I would use the control path to drive the "kernel" signal (containing the weights of the 3x3 kernel + 1 weight for the bias) as well as additional signals that could be used for, e.g., multiplexing between different accelerators in the PL. As soon as those were configured (the control DMA is one-way, write-only) I would use the data DMA to send over the (e.g., MNIST) image, which is stored in a 28x28 input buffer of datatype ```np.uint8``` (you can use numpy dtypes!) and then I had an output buffer of size 26x26 (also dtype ```uint8```) awaiting the result.  

So the input buffer the kernel made use of was a Python list with the kernel cast to a uint8 numpy array (something like ```np.array([1,2,1,2,4,2,1,2,1,0], dtype=np.uint8)```) which I then sent over 

I made sure the control DMA could send over the entire message in one clock cycle: in the control DMA Verilog code you'll find it just assigns the input directly to the relevant control signals within a single clock cycle the moment the slave asserts "valid"

You can find that code in the /CNN/ sub-directory! All the Verilog code related to the actual CNN are in the separate folder as they aren't "necessary" for DMA of course, I just included them to have a showcase of how to potentially use it.

I booted my FPGA with a GUI Ubuntu distro, there's a special one for the Xilinx KV260 FPGA, 24.04 LTS, that you can find here: https://ubuntu.com/certified/202104-28895. You can flash an SD card using, e.g., Rufus and just boot it up by connecting it to a monitor, keyboard, and mouse. You'll want to pip install PYNQ, as that's the library you need to communicate with the DMA. Don't bother with the actual PYNQ (Linux) image, PYNQ is a Python library that can be installed on any ARM SoC microcontroller anyway. You can find a very simple sample Python code in /Python/ that does what I describe above, but it's not an MNIST image but just a random 28x28 image. Be sure to set up the input & output buffer according to the correct dimensions! Also note that you'll need to get the ```.bit``` bitstream and ```.hwh``` hardware-handoff files specifically from your Vivado project and put them in the same folder as your ```pynq.py``` variant. I just set up Jupyter notebooks through Pynq which are automatically discoverable over the network if your FPGA is connected over ethernet, and then I'd just upload them directly from my own laptop over which I connected to the remote Jupyter notebook. Hardware-handoff files can be a bit annoying to find.

So what I did in the full version was wrap most of this around a function I just called ```FPGA_conv()``` which you could pass the PyTorch tensors containing the data & kernel weights and it would make sure the data got converted to an appropriate data-type and then transferred to the appropriate buffer. And then the PyTorch code I sent above could seamlessly interact with it! 

Another very useful hint that I discovered: if you want to send data in a batch-parallel fashion (so say, I could instantiate the CNN 4x in parallel in the RTL and then have it process 4 channels in parallel, i.e., the DMA data-stream would send me the 4 images), you should make use of the fact that NumPy stores data in row-major order in contiguous memory, which means the last dimension changes fastest in memory. So if I'd store a np array in 3D as (HEIGHT x WIDTH x N_IMAGES) (so, for MNIST e.g., 28x28x4), memory would be laid out like: 

```img1_pixel0, img2_pixel0, img3_pixel0, img4_pixel0,```

```img1_pixel1, img2_pixel1, img3_pixel1, img4_pixel1,```

... (and so on)
where ```imgN_pixelM``` represents the M-th pixel of the N-th image! AXI DMA transfers are linear: they read/write a single contiguous memory block. Packed pixels (N_IMAGES per beat) will be transferred as a flat 1D stream, but the PL needs to interpret the structure correctly. Let's say each pixel is 8 bits (a value between 0 and 255), then we could, for example, make the bytes transferred each beat in a word of 4x8 = 32 bits. Then, each clock cycle, the PL would receive the concatenation ```{img1_pixel0, img2_pixel0, img3_pixel0, img4_pixel0}``` and you can very easily just route the 8 constituent bits to the right, individual accelerator. 

NB: If you notice your data is acting up or being transceived incorrectly, you could use input_buffer.flush() after sending data and output_buffer.invalidate() after receiving, but I haven't had to use them per se.



`
