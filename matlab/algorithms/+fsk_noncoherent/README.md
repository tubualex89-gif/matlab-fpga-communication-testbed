# 非相干 2FSK 算法

在 `config/platform_config.m` 中设置 `cfg.algorithm = 'fsk_noncoherent'`，然后按工程根目录 README 的硬件收发流程运行。

在 `algorithm_config.m` 中修改参数。默认 256 bit、250 bit/s，bit 0 为 23.75 kHz、bit 1 为 26.25 kHz，通带采样率 1 MHz。算法帧为 10 ms 下扫频 LFM + 2FSK 数据 + 10 ms 下扫频 LFM，发射板 PL 在其外侧继续添加自己的 LFM 和保护间隔。bit 由固定种子随机生成，接收端有参考比特时计算 BER。

接收端首尾默认各截取 20 ms，通过首尾 LFM 峰对估计整体时间尺度，线性插值补偿，再用两种频率的复相关能量作逐符号非相干判决。PL 捕获、同步门限、多径、时变多普勒及噪声影响需要上板验证。最大时间尺度偏差和首尾截取时间在接收函数顶部可修改。
