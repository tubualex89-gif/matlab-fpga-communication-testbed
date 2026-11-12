# RX control protocol

MATLAB connects to port 6002 and sends 12 bytes: ASCII `RXC1`, a big-endian
16-bit Q15 normalized correlation-power threshold, a big-endian 40-bit
minimum input energy, and a zero reserved byte. Q15 values 1..32768 are valid.
The PS replies with ASCII `RXA1` and a one-byte status before any waveform:
0 = active, 1 = control IP too old, 2 = readback mismatch, 3 = timeout.
On success subsequent frames are a big-endian 32-bit sample count followed
by signed 16-bit little-endian samples. Captures before configuration is active
are discarded. The PC should wait for MATLAB's ready message before transmitting.

The control IP registers 04/08/0c are configuration shadows. Writing 1 to 20
requests an atomic apply when idle. 20 bit 0 is pending, 24 is the apply
generation, 28/2c/30 are active values, and 34 reads 0x52584331. Do not
modify the shadows while an apply request is pending. The RX busy signal
includes the leading-LFM detection cycle, preventing an apply on frame start.

Vivado must repackage/refresh ps_ctrl and refresh the changed receiver RTL,
regenerate output products and the bitstream, and export a new XSA. Update the
Vitis platform, rebuild the platform and RX application, then load both the
new bitstream and ELF. Existing boot images must also be rebuilt for QSPI.
