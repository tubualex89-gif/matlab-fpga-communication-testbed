function [passband, algorithmInfo, txReference] = tx_algorithm(cfg)
assert(cfg.fsPassband == 1e6, '平台通带采样率必须为 1 MHz。');
assert(isscalar(cfg.payloadBits) && cfg.payloadBits>=1 && cfg.payloadBits==fix(cfg.payloadBits), '比特数必须为正整数。');
assert(all(isfinite([cfg.f0 cfg.f1])) && cfg.f0>=20000 && cfg.f0<=30000 && cfg.f1>=20000 && cfg.f1<=30000 && cfg.f0~=cfg.f1, '两个频率必须不同且位于 20–30 kHz。');
N=round(cfg.symbolDuration*cfg.fsPassband); M=round(cfg.lfmDuration*cfg.fsPassband);
assert(N>=2 && abs(N/cfg.fsPassband-cfg.symbolDuration)<1e-12, '符号时长必须对应整数采样点。');
assert(M>=2 && abs(M/cfg.fsPassband-cfg.lfmDuration)<1e-12, 'LFM 时长必须对应整数采样点。');
assert(M*2+N*cfg.payloadBits<=10000000, '发射波形超过 10 秒限制。');
oldRng=rng; cleanup=onCleanup(@()rng(oldRng)); rng(cfg.seed,'twister');
bits=randi([0 1],cfg.payloadBits,1);
t=(0:N-1).'/cfg.fsPassband;
tone0=cos(2*pi*cfg.f0*t); tone1=cos(2*pi*cfg.f1*t);
data=zeros(N,cfg.payloadBits);
data(:,bits==0)=repmat(tone0,1,sum(bits==0));
data(:,bits==1)=repmat(tone1,1,sum(bits==1));
tLfm=(0:M-1).'/cfg.fsPassband; rate=(cfg.lfmEndHz-cfg.lfmStartHz)/cfg.lfmDuration;
lfm=cos(2*pi*(cfg.lfmStartHz*tLfm+0.5*rate*tLfm.^2));
passband=[lfm; data(:); lfm];
algorithmInfo=struct('algorithmId','fsk_noncoherent_v1','fsPassband',cfg.fsPassband, ...
    'f0',cfg.f0,'f1',cfg.f1,'symbolSamples',N,'payloadBits',cfg.payloadBits, ...
    'lfm',lfm,'lfmSamples',M,'lfmSeparation',M+N*cfg.payloadBits);
txReference=struct('bits',bits);
fprintf('2FSK：%d bit，%.1f bit/s，%.2f / %.2f kHz，波形 %.3f s。\n', ...
    cfg.payloadBits, cfg.fsPassband/N, cfg.f0/1000,cfg.f1/1000,numel(passband)/cfg.fsPassband);
end
