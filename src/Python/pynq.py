from pynq import Overlay, allocate 
import numpy as np

ol = Overlay("design.bit") # You need to have both your .bit file and the hardware-handoff (.hwh) 
                           # file in the same folder as your notebook for PYNQ to function correctly! 
data_dma = ol.axi_dma_0    # You can use whatever name you gave to the (DMA) module in Vivado! 
control_dma = ol.axi_dma_1 

dma_send = data_dma.sendchannel 
dma_recv = data_dma.recvchannel 
cont_dma_send = control_dma.sendchannel 

control_buffer = allocate(shape=(16,), dtype=np.uint8)
input_buffer = allocate(shape=(28,28), dtype=np.uint8) 
output_buffer = allocate(shape=(26,26), dtype=np.uint8) 

random_input = np.random.randint(0, 256, size=(28, 28), dtype=np.uint8) # generate a random test-sig

control_message = np.array([1,2,1,2,4,2,1,2,1,0,0,0,0,0,0,0], dtype=np.uint8) 
np.copyto(control_buffer, control_message)
control_dma_send.transfer(control_buffer) 
control_dma_send.wait()

np.copyto(input_buffer, random_input) # You need to get your data to the input_buffer 

dma_recv.transfer(output_buffer) # Perhaps counter-intuitively, you should(!) specify the buffer meant 
                                 # to receive the data first!!! 
dma_send.transfer(input_buffer)
dma_send.wait()
dma_recv.wait() 

output = np.zeros_like(output_buffer)
np.copyto(output, output_buffer)
del input_buffer, output_buffer, control_buffer
