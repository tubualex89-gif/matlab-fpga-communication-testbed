function cfg = algorithm_config()
% 在此文件中修改当前算法参数，修改后重新生成发射波形。
cfg.fc = 25e3;             % 载波频率 Hz
cfg.bandwidth = 5e3;       % 基带采样率及标称带宽 Hz
cfg.Nfft = 256;            % FFT 点数
cfg.Ncp = 64;              % 循环前缀，保持 12.8 ms
cfg.nSym = 50;             % OFDM 数据符号数
cfg.modulation = 'qpsk';   % 当前仅支持 QPSK
cfg.seed = 42;             % 随机比特种子
cfg.fsPassband = 1e6;    % 通带采样率 Hz
cfg.lfmDuration = 10e-3;   % LFM 时长 s
end
