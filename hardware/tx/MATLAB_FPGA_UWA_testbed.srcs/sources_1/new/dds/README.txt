PL 发射核心说明

Test_bed_tx.v 是 100 MHz 同步核心，rst_n 为低有效同步复位。每 100 个时钟输出一个 1 MHz 采样使能 dac_sample_valid。输出 dac_sample 是 14 位无符号偏移二进制逻辑采样，100 MHz 时钟沿寄存，空闲码为 8192；dac_sample_valid 同步指示 1 MHz 采样更新。它还不是确定型号的 DAC 物理接口。

start 为单周期启动脉冲，payload_samples 是载荷采样点数，在启动时锁存；非零长度后先输出 10000 个 DDS LFM 点，再输出指定数量的载荷。payload_data/payload_valid/payload_ready 是同一 100 MHz 时钟域的 ready/valid 接口：源端应在 valid 为高时保持数据直至 ready 与 valid 同时为高的时钟沿。状态为 DATA 时，ready 仅在采样节拍为高。若采样时 valid 为低，核心立即输出零电平并中止，error_underflow 保持到下一次 start 或复位。长度为零时 error_zero_length 置位，不开始发射；done 为最后一个载荷采样输出时的单周期脉冲。busy 只在 LFM 和 DATA 阶段为高。上游须自行缓冲/预填充并保证持续供应：本版本没有 AXI DMA、FIFO、AXI-Lite、DAC 引脚接口、DAC 器件专用驱动或约束文件。

DDS 仅存储四分之一周期正弦查找表，通过相位象限重建完整正弦。48 位相位累加器从 22.5 kHz 起，以每采样约 0.5 Hz 的频率步进线性扫频；第 10000 个采样对应约 27.4995 kHz。固定初始相位为零（正弦）。LFM 与载荷内部使用 16 位有符号补码，转换时取高 14 位并翻转符号位：-32768、0、32767 对应 0、8192、16383。转换为截断而非四舍五入；实际 DAC 编码和接口时序仍需根据器件确认。

sim/tb_tx.v 为独立自检测试平台，可在 Vivado 中加入 Simulation Sources 后运行；工程已登记 DDS 的两个设计文件。该版本尚未验证仿真、综合和上板。

新增 dac_clk：由 100 MHz 同步分频的 1 MHz 时钟，复位时为低，正常时高低各 500 ns。dac_sample 与时钟下降沿同时由 100 MHz 寄存器更新，DAC 上升沿在约 500 ns 后；假定 DAC 在上升沿采样。done 指最后一个载荷更新到输出寄存器，而 DAC 对该点的上升沿采样随后约 500 ns 才发生。此时钟为逻辑时钟输出，必须根据 DAC 数据手册与实际引脚验证采样边沿、建立保持时间、时序约束和时钟输出资源，尚未完成仿真及板级验证。
