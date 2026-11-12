function [passband, algorithmInfo, txReference] = tx_algorithm(cfg)
% 示例：1 秒、25 kHz 通带正弦。可替换为同事自己的成帧算法。
assert(cfg.fsPassband == 1e6, '平台采样率应为 1 MHz。');
t=(0:round(cfg.durationSeconds*cfg.fsPassband)-1).'/cfg.fsPassband;
passband=cos(2*pi*25e3*t);
algorithmInfo=struct('fsPassband',cfg.fsPassband,'description','25 kHz 示例单音');
txReference=[];
end
