# Continuous receiver AXI4-Lite control IP

Use a 32-bit AXI4-Lite bus and 7-bit byte addresses. All signals are synchronous to s00_axi_aclk (the same 100 MHz clock and reset as Test_bed_rx). The receiver listens automatically after reset; there is no arm port.

| Offset | Register | Access | Description |
|---|---|---|---|
| 0x00 | STATUS_CLEAR | W | bit 0=1 with WSTRB[0] clears sticky done/timeout/overflow. Read zero. |
| 0x04 | CORR_THRESHOLD | RW | low 16 bits, Q1.15, reset 6554. 0 disables detections. |
| 0x08 | MIN_ENERGY_LO | RW | 40-bit minimum energy [31:0], default total 100000. |
| 0x0c | MIN_ENERGY_HI | RW | minimum energy [39:32] in bits [7:0]. |
| 0x10 | STATUS | RO | bit 0 busy (recording/draining), 1 sticky done, 2 sticky timeout, 3 sticky overflow, 4 processing overrun. |
| 0x14 | LAST_SAMPLE_COUNT | RO | sample count from most recently completed frame. |
| 0x18 | LAST_METRIC | RO | most recent valid normalized metric, continually updated. |
| 0x1c | COMPLETED_COUNT | RO | completed frames since reset; saturates at 0xffffffff. |

RX done is a one-cycle pulse; the control IP latches it and records the last frame's count. Event wins over a simultaneous status clear. A new frame can overwrite last count before software reads it; COMPLETED_COUNT reveals multiple events but this is not a per-frame metadata queue. processing_overrun is sticky until hardware reset and is not cleared by STATUS_CLEAR. Q15/energy writes while busy return SLVERR; undefined/read-only writes return SLVERR and undefined reads return zero. In WAIT_HEAD, busy=0 and configuration writes are allowed; do not change configuration near an incoming frame, since multiword writes are not atomic.

Connect rx_corr_threshold_q15 and rx_corr_min_energy to corresponding Test_bed_rx inputs; connect remaining inputs to same-name RX status outputs (without the rx_ prefix). No arm connection. Ensure DMA is ready independently; Simple DMA must be restarted by PS after every packet and can lose back-to-back frames. For continuous reception use SG descriptors and a DDR ring as a future integration, with error handling and adequate buffer capacity. Capture module cannot receive another frame while draining previous frame.
