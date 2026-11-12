function [passband, algorithmInfo, txReference] = tx_algorithm(cfg)
%% 生成帧
% 基带采样率等于设定带宽。
cfg.fsBB = cfg.bandwidth;
cfg.Tu = cfg.Nfft / cfg.fsBB;
cfg.Tcp = cfg.Ncp / cfg.fsBB;
cfg.Tsym = (cfg.Nfft + cfg.Ncp) / cfg.fsBB;
cfg.deltaF = cfg.fsBB / cfg.Nfft;

if cfg.Nfft ~= 256 || cfg.Ncp < 1 || cfg.Ncp > cfg.Nfft
    error('当前导频与长导码配置要求 256 点 FFT，且循环前缀长度须在 1 到 256 之间。');
end
if abs(cfg.fsPassband / cfg.fsBB - round(cfg.fsPassband / cfg.fsBB)) > eps
    error('fsPassband/fsBB must be an integer for this demonstration.');
end
if ~strcmpi(cfg.modulation, 'qpsk')
    error('This no-channel reference currently uses QPSK.');
end

rng(cfg.seed);
N = cfg.Nfft;
dc = N/2 + 1;
activeSC = [-104:-1 1:104].';       % 208 个有效子载波，保留 DC 和频带边缘
pilotSC = activeSC(1:2:end);         % 104 / 208 = 1/2
dataSC = setdiff(activeSC, pilotSC);
% 固定种子伪随机 BPSK 导频，避免规则交替相干叠加产生周期性尖峰。
payloadRng = rng; rng(271828, 'twister');
pilotSymbols = 2*randi([0 1], numel(pilotSC), 1) - 1;
rng(payloadRng);
pilotIdx = dc + pilotSC;
dataIdx = dc + dataSC;

% 802.11a-style short training sequence: a repeated 16-sample pattern.
stsN = 64; stsDc = stsN/2 + 1;
stsFreq = zeros(stsN, 1);
stsSC = [-24 -20 -16 -12 -8 -4 4 8 12 16 20 24].';
stsFreq(stsDc + stsSC) = [1;-1;1;-1;-1;1;-1;-1;1;1;1;1];
stsTime = ifft(ifftshift(stsFreq));
sts = repmat(stsTime(1:16), 10, 1);

% 确定性 BPSK 长导码：从固定种子候选中选择较低峰均比的序列。
ltsFreq = zeros(N, 1);
previousRng = rng; rng(314159, 'twister');
bestPeak = inf;
for candidate = 1:64
    candidateFreq = zeros(N, 1);
    candidateFreq(dc + activeSC) = 2*randi([0 1], numel(activeSC), 1) - 1;
    candidateTime = ifft(ifftshift(candidateFreq));
    candidatePapr = max(abs(candidateTime).^2) / mean(abs(candidateTime).^2);
    if candidatePapr < bestPeak
        bestPeak = candidatePapr; ltsFreq = candidateFreq; ltsTime = candidateTime;
    end
end
rng(previousRng);
fprintf('LTS baseband PAPR (%d samples): %.2f dB\n', N, 10*log10(bestPeak));
lts = [ltsTime(end-cfg.Ncp+1:end); ltsTime; ltsTime];

bitsPerCarrier = 2;
bitsPerSymbol = numel(dataIdx) * bitsPerCarrier;
txBits = randi([0 1], bitsPerSymbol * cfg.nSym, 1);
ofdm = zeros(N + cfg.Ncp, cfg.nSym);
dataConstellation = zeros(numel(dataIdx), cfg.nSym);

for ell = 1:cfg.nSym
    bitRange = (ell-1)*bitsPerSymbol + (1:bitsPerSymbol);
    dataSymbols = qpsk_map(txBits(bitRange));
    pilotPolarity = 1 - 2*mod(ell-1, 2);
    X = zeros(N, 1);
    X(dataIdx) = dataSymbols;
    X(pilotIdx) = pilotPolarity * pilotSymbols;
    xUseful = ifft(ifftshift(X));
    ofdm(:, ell) = [xUseful(end-cfg.Ncp+1:end); xUseful];
    dataConstellation(:, ell) = dataSymbols;
end

baseband = [sts; lts; ofdm(:)];
baseband = baseband / sqrt(mean(abs(baseband).^2));

upsampleFactor = round(cfg.fsPassband / cfg.fsBB);
bbPassbandRate = resample(baseband, upsampleFactor, 1);
tPB = (0:numel(bbPassbandRate)-1).' / cfg.fsPassband;
ofdmPassband = real(bbPassbandRate .* exp(1j*2*pi*cfg.fc*tPB));

% MATLAB 帧首尾采用相同的 10 ms 下扫频 LFM，与 PL 上扫频 LFM 区分。
lfmSamples = round(cfg.lfmDuration * cfg.fsPassband);
tLfm = (0:lfmSamples-1).' / cfg.fsPassband;
fStart = cfg.fc + cfg.bandwidth/2;
chirpRate = -cfg.bandwidth / cfg.lfmDuration;
lfm = cos(2*pi*(fStart*tLfm + 0.5*chirpRate*tLfm.^2));
passband = [lfm; ofdmPassband; lfm];

info = struct();
info.channelEstimation = 'symbol_pilot_linear_1_2';
info.Nfft = N;
info.Ncp = cfg.Ncp;
info.nSym = cfg.nSym;
info.fsBB = cfg.fsBB;
info.fc = cfg.fc;
info.fsPassband = cfg.fsPassband;
info.deltaF = cfg.deltaF;
info.dataIdx = dataIdx;
info.pilotIdx = pilotIdx;
info.pilotSymbols = pilotSymbols;
info.activeSC = activeSC;
info.pilotSC = pilotSC;
info.ltsTime = ltsTime;
info.ltsFreq = ltsFreq;
info.stsLength = numel(sts);
info.ltsLength = numel(lts);
info.symbolLength = N + cfg.Ncp;
info.dataStart = numel(sts) + numel(lts) + 1;
info.txBits = txBits;
info.dataConstellation = dataConstellation;
info.bitsPerSymbol = bitsPerSymbol;
info.dataSymbolDuration = cfg.Tsym;
info.lfm = lfm;
info.lfmDuration = cfg.lfmDuration;
info.lfmSamples = lfmSamples;
info.ofdmPassbandLength = numel(ofdmPassband);
info.lfmStartSeparation = lfmSamples + numel(ofdmPassband);

rxConfig = rmfield(info, {'txBits', 'dataConstellation'});
% 参考比特仅用于理想回环评估，不参与接收解调。
txReference = struct('bits', txBits, 'constellation', dataConstellation);
algorithmInfo = rxConfig;
fprintf('FFT=%d，CP=%d，有效子载波=%d，导频=%d，数据=%d，帧长=%.3f 秒\n', N, cfg.Ncp, numel(activeSC), numel(pilotSC), numel(dataSC), numel(passband)/cfg.fsPassband);

end

function out = qpsk_map(bits)
pairs = reshape(bits, 2, []).';
out = ((1 - 2*pairs(:,1)) + 1j*(1 - 2*pairs(:,2))) / sqrt(2);
end

