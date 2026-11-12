function cfg = algorithm_config()
% 2FSK 参数，频率需处于接收端 PL 目标带通 20～30 kHz 内。
cfg.fsPassband = 1e6;
cfg.f0 = 23750;                 % bit 0 频率 Hz
cfg.f1 = 26250;                 % bit 1 频率 Hz
cfg.symbolDuration = 0.004;     % 每比特 4 ms，净比特率 250 bit/s
cfg.payloadBits = 256;
cfg.seed = 42;
cfg.lfmDuration = 0.010;       % MATLAB 首尾同步 LFM
cfg.lfmStartHz = 27500;        % 下扫频，与 PL 上扫频 LFM 不同
cfg.lfmEndHz = 22500;
end
