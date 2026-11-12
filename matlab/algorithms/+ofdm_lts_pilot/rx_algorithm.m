function result = rx_algorithm(passband, algorithmInfo, txReference, cfg)
% OFDM 接收算法：接收平台提供原始采集波形。
%% 输入文件与接收参数（可修改）
% 数据由平台以参数传入。
FFT_win_shift = 8;         % FFT 窗口相对有效符号起点前移的基带采样点
syncDelay = 16;            % STS 自相关延时，基带采样点
syncWindow = 48;           % STS 自相关窗口，基带采样点
syncThreshold = 0.70;      % 粗同步阈值
maxTimeScaleDeviation = 0.02; % 首尾 LFM 间隔允许的最大相对变化
coarseCfoOffset = 2*16;       % 相对粗同步位置，避开短导码起始边界
coarseCfoLength = 4*16;       % 使用 4 个短周期估计粗频偏
soundSpeedMps = 1500;        % 水中声速 m/s，可根据实验环境修改
edgeTrimSeconds = 0.020;   % 从接收文件首尾各去除 20 ms
fineSearchRadius = 32;        % 长导码精同步搜索半径（基带采样点）
pilotMinChannelRatio = 0.10; % 低于最强导频幅度的 10% 时不参与拟合
tailGuardSeconds = 0.010;     % 尾部 LFM 起点之后保留的实际采样时长
% 载波、采样率、帧结构等收发共同参数从发射文件 rxConfig 读取。
%% 接收处理
waveform = struct('passband',passband,'rxConfig',algorithmInfo);
if ~isempty(txReference), waveform.txReference = txReference; end
if ~isfield(waveform, 'passband') || ~isreal(waveform.passband) || ~isvector(waveform.passband) || any(~isfinite(waveform.passband(:)))
    error('Waveform file must contain a finite real vector named passband.');
end
if ~isfield(waveform, 'rxConfig'), error('Waveform file must contain rxConfig.'); end
txInfo = waveform.rxConfig;
if isfield(txInfo,'channelEstimation') && strcmp(txInfo.channelEstimation,'symbol_pilot_linear_1_2')
    error('当前数据由 1/2 导频算法生成，请使用 pilot_interp 接收脚本。');
end
rxPB = double(waveform.passband(:));
if ~isscalar(edgeTrimSeconds) || ~isfinite(edgeTrimSeconds) || edgeTrimSeconds < 0
    error('首尾截取时长必须是非负有限数。');
end
trimSamples = round(edgeTrimSeconds * txInfo.fsPassband);
if 2*trimSamples >= numel(rxPB)
    error('接收文件长度不足，无法从首尾各截去 %.3f ms。', edgeTrimSeconds*1000);
end
rxPB = rxPB(trimSamples+1:end-trimSamples);
fprintf('接收文件首尾各截去 %d 点（%.3f ms），剩余 %d 点。\n', ...
    trimSamples, 1000*trimSamples/txInfo.fsPassband, numel(rxPB));
N = txInfo.Nfft;
Ncp = txInfo.Ncp;
if ~isscalar(FFT_win_shift) || ~isreal(FFT_win_shift) || ~isfinite(FFT_win_shift) || ...
        FFT_win_shift ~= fix(FFT_win_shift) || FFT_win_shift < 0 || FFT_win_shift > Ncp
    error('FFT_win_shift 必须是 0 到 CP 长度 %d 之间的整数。', Ncp);
end

% 1. 互相关查找首尾 LFM。使用 FFT 卷积，以峰对间隔约束区分帧首和帧尾。
lfm = double(txInfo.lfm(:));
if numel(rxPB) < numel(lfm), error('接收文件短于一个 LFM。'); end
nfftCorr = 2^nextpow2(numel(rxPB) + numel(lfm) - 1);
corrFull = ifft(fft(rxPB, nfftCorr) .* fft(flipud(lfm), nfftCorr), 'symmetric');
corrValid = abs(corrFull(numel(lfm):numel(rxPB)));
[peakValue, peakPos] = findpeaks(corrValid, 'MinPeakDistance', max(1, round(0.005*txInfo.fsPassband)));
% findpeaks 不返回端点；理想回环中两段 LFM 恰好位于相关序列端点。
if numel(corrValid) >= 2 && corrValid(1) >= corrValid(2)
    peakPos(end+1,1) = 1; peakValue(end+1,1) = corrValid(1);
end
if numel(corrValid) >= 2 && corrValid(end) >= corrValid(end-1)
    peakPos(end+1,1) = numel(corrValid); peakValue(end+1,1) = corrValid(end);
end
if numel(peakPos) < 2, error('未检测到足够的 LFM 相关峰。'); end
% 保留整个接收文件中的全部候选峰，包括前后静默段之间的信号。
[peakPos, order] = sort(peakPos);
peakValue = peakValue(order);
nominalSeparation = txInfo.lfmStartSeparation;
% 对截取后的整个接收文件搜索首尾 LFM 峰对，只限制峰间距。
bestScore = -inf; firstLfm = 0; lastLfm = 0;
for i = 1:numel(peakPos)
    separation = peakPos - peakPos(i);
    candidates = find(separation > 0 & ...
        abs(separation/nominalSeparation - 1) <= maxTimeScaleDeviation);
    if ~isempty(candidates)
        [secondPeak, k] = max(peakValue(candidates));
        score = min(peakValue(i), secondPeak);
        if score > bestScore && score > 0
            bestScore = score; firstLfm = peakPos(i); lastLfm = peakPos(candidates(k));
        end
    end
end
if firstLfm == 0, error('未找到间隔满足约束的 LFM 峰对；请检查信号或调整搜索范围。'); end
% stretch > 1 表示接收帧拉长；alpha=1/stretch 为频率尺度。
stretch = (lastLfm-firstLfm) / nominalSeparation;
alphaEstimate = 1/stretch;
if ~isscalar(soundSpeedMps) || ~isfinite(soundSpeedMps) || soundSpeedMps <= 0
    error('水中声速必须为正的有限数值。');
end
% 假设发射端相对介质静止、接收端沿径向运动：正值代表靠近。
radialVelocityMmps = soundSpeedMps * (alphaEstimate - 1) * 1000;
if radialVelocityMmps > 0
    motionDirection = '靠近';
elseif radialVelocityMmps < 0
    motionDirection = '远离';
else
    motionDirection = '无径向相对运动';
end
% 在尾 LFM 起点之后继续读取实际采样，容纳互相关和同步定位误差。
% 截止于文件最后一个可插值采样点，不通过补零伪造缺失数据。
tailGuardSamples = round(tailGuardSeconds * txInfo.fsPassband);
availableOutputSamples = floor((numel(rxPB) - firstLfm) / stretch) + 1;
outputSamples = min(nominalSeparation + tailGuardSamples, availableOutputSamples);
query = firstLfm + (0:outputSamples-1).' * stretch;
rxCorrectedPB = interp1((1:numel(rxPB)).', rxPB, query, 'linear');
rxOfdmPB = rxCorrectedPB(txInfo.lfmSamples+1:end);
t = (0:numel(rxOfdmPB)-1).' / txInfo.fsPassband;
rxMixed = rxOfdmPB .* exp(-1j*2*pi*txInfo.fc*t);
decimation = round(txInfo.fsPassband / txInfo.fsBB);
rx = resample(rxMixed, 1, decimation);

% 2. 短导码延迟自相关粗同步。
D = syncDelay; L = syncWindow;
metric = zeros(numel(rx)-L-D+1, 1);
for ii = 1:numel(metric)
    a = rx(ii:ii+L-1); b = rx(ii+D:ii+D+L-1);
    metric(ii) = abs(sum(conj(a).*b)) / (sqrt(sum(abs(a).^2)*sum(abs(b).^2)) + eps);
end
coarseStart = find(metric > syncThreshold, 1, 'first');
if isempty(coarseStart), error('短导码粗同步失败。'); end

% 3. 用粗同步后较靠内部的 4 个短周期计算并校正粗频偏。
coarseWindowStart = coarseStart + coarseCfoOffset;
coarseWindowEnd = coarseWindowStart + coarseCfoLength - 1;
if coarseWindowEnd + D > numel(rx), error('短导码频偏估计窗口超出接收数据。'); end
a = rx(coarseWindowStart:coarseWindowEnd);
b = rx(coarseWindowStart+D:coarseWindowEnd+D);
coarseCfoHz = angle(sum(conj(a).*b))*txInfo.fsBB/(2*pi*D);
n = (0:numel(rx)-1).';
rxCoarse = rx .* exp(-1j*2*pi*coarseCfoHz*n/txInfo.fsBB);

% 4. 长导码互相关精同步。联合两次长导码的相关峰，减少选错峰的可能。
c = abs(conv(rxCoarse, flipud(conj(txInfo.ltsTime))));
expected = coarseStart + txInfo.stsLength + Ncp;
candidates = (expected-fineSearchRadius):(expected+fineSearchRadius);
candidates = candidates(candidates >= 1 & candidates+2*N-1 <= numel(rxCoarse));
if isempty(candidates), error('长导码搜索范围超出接收数据。'); end
score = c(candidates+N-1) + c(candidates+2*N-1);
[~, best] = max(score);
ltsStart = candidates(best);
ltsFftStart = ltsStart - FFT_win_shift;
if ltsFftStart < 1, error('FFT 窗口前移后超出接收数据，请检查同步位置。'); end
lts1 = rxCoarse(ltsFftStart:ltsFftStart+N-1);
lts2 = rxCoarse(ltsFftStart+N:ltsFftStart+2*N-1);

% 5. 两个长导码估计残余频偏并再次补偿。
fineCfoHz = angle(sum(conj(lts1).*lts2))*txInfo.fsBB/(2*pi*N);
rxCfoCorrected = rxCoarse .* exp(-1j*2*pi*fineCfoHz*n/txInfo.fsBB);
lts1 = rxCfoCorrected(ltsFftStart:ltsFftStart+N-1);
lts2 = rxCfoCorrected(ltsFftStart+N:ltsFftStart+2*N-1);
% 重复长导码信噪比：细频偏补偿后，差分消除相同信号。
% 假设两段长导码的信道不变，且噪声等功率、互不相关。
ltsNoisePower = mean(abs(lts1 - lts2).^2) / 2;
ltsReceivedPower = (mean(abs(lts1).^2) + mean(abs(lts2).^2)) / 2;
ltsSignalPower = max(ltsReceivedPower - ltsNoisePower, 0);
if ltsNoisePower == 0
    if ltsSignalPower > 0, ltsSnrDb = Inf; else, ltsSnrDb = NaN; end
elseif ltsSignalPower == 0
    ltsSnrDb = -Inf;
else
    ltsSnrDb = 10*log10(ltsSignalPower / ltsNoisePower);
end

fprintf('\n长导码信噪比估计 SNR：%.2f dB（基带，细频偏校正后）\n', ltsSnrDb);
if ltsStart + 2*N + txInfo.nSym*txInfo.symbolLength - 1 > numel(rx)
    error(['接收帧数据不足：需要 %d 个基带采样点，实际 %d；' ...
        '首/尾 LFM=%d/%d，STS=%d，LTS=%d，时间尺度=%.9f。' ...
        '请检查同步定位及接收文件是否完整。'], ...
        ltsStart + 2*N + txInfo.nSym*txInfo.symbolLength - 1, numel(rx), ...
        firstLfm + trimSamples, lastLfm + trimSamples, coarseStart, ltsStart, stretch);
end

Ylts = (fftshift(fft(lts1)) + fftshift(fft(lts2))) / 2;
Hest = ones(N, 1);
valid = abs(txInfo.ltsFreq) > eps;
Hest(valid) = Ylts(valid) ./ txInfo.ltsFreq(valid);

rawData = zeros(numel(txInfo.dataIdx), txInfo.nSym);
cfoData = zeros(numel(txInfo.dataIdx), txInfo.nSym);
channelEqualized = zeros(numel(txInfo.dataIdx), txInfo.nSym);
rxData = zeros(numel(txInfo.dataIdx), txInfo.nSym);
% fftshift 后将 MATLAB 下标转换为以 DC 为 0 的有符号子载波编号。
pilotSubcarriers = double(txInfo.pilotIdx(:)) - (N/2 + 1);
dataSubcarriers = double(txInfo.dataIdx(:)) - (N/2 + 1);
[sortedPilots, pilotOrder] = sort(pilotSubcarriers);
phaseSlope = zeros(1, txInfo.nSym);      % rad / 子载波
phaseIntercept = zeros(1, txInfo.nSym);  % rad，线性模型在 k=0 的截距
for ell = 1:txInfo.nSym
    startIndex = ltsStart + 2*N + (ell-1)*txInfo.symbolLength;
    rawWithCP = rx(startIndex:startIndex+txInfo.symbolLength-1);
    symbolWithCP = rxCfoCorrected(startIndex:startIndex+txInfo.symbolLength-1);
    fftIndices = (Ncp + 1 - FFT_win_shift):(Ncp + N - FFT_win_shift);
    rawY = fftshift(fft(rawWithCP(fftIndices)));
    useful = symbolWithCP(fftIndices);
    Y = fftshift(fft(useful));

    rawData(:,ell) = rawY(txInfo.dataIdx);
    cfoData(:,ell) = Y(txInfo.dataIdx);
    equalizedData = Y(txInfo.dataIdx) ./ Hest(txInfo.dataIdx);
    equalizedPilots = Y(txInfo.pilotIdx) ./ Hest(txInfo.pilotIdx);
    if isfield(txInfo, 'pilotSymbols')
        pilotSymbols = txInfo.pilotSymbols(:);
    elseif numel(txInfo.pilotIdx) == 4
        pilotSymbols = [1; 1; 1; -1]; % 兼容原始 64 点帧
    else
        error('接收配置缺少导频参考符号。');
    end
    if numel(pilotSymbols) ~= numel(txInfo.pilotIdx), error('导频参考符号数量不匹配。'); end
    knownPilots = (1 - 2*mod(ell-1, 2)) * pilotSymbols;
    pilotResidual = equalizedPilots(:) .* conj(knownPilots);
    % 排除深衰落及无效导频后，再进行相位展开和信道功率加权拟合。
    sortedResidual = pilotResidual(pilotOrder);
    pilotH = Hest(txInfo.pilotIdx); pilotH = pilotH(pilotOrder);
    validPilot = isfinite(sortedResidual) & isfinite(pilotH) & ...
        abs(sortedResidual) > eps & abs(pilotH) > eps;
    if any(validPilot)
        validPilot = validPilot & abs(pilotH) >= pilotMinChannelRatio * max(abs(pilotH(validPilot)));
    end
    if ~any(validPilot), error('第 %d 个 OFDM 符号没有可用导频。', ell); end
    kGood = sortedPilots(validPilot); zGood = sortedResidual(validPilot);
    weights = abs(pilotH(validPilot)).^2;
    if numel(kGood) >= 2
        pilotPhase = unwrap(angle(zGood));
        design = [kGood, ones(size(kGood))];
        coefficients = (design .* sqrt(weights)) \ (pilotPhase .* sqrt(weights));
        phaseFit = coefficients.';
    else
        % 只有一个可靠导频时无法估计斜率，退化为公共相位校正。
        phaseFit = [0, angle(zGood)];
    end
    phaseSlope(ell) = phaseFit(1);
    phaseIntercept(ell) = phaseFit(2);
    dataPhase = polyval(phaseFit, dataSubcarriers);
    channelEqualized(:,ell) = equalizedData;
    rxData(:,ell) = equalizedData .* exp(-1j*dataPhase);
end

rxBits = qpsk_demap(rxData(:));
% Decision-directed EVM: does not require transmitted bits.
reference = ((1 - 2*(real(rxData(:)) < 0)) + 1j*(1 - 2*(imag(rxData(:)) < 0))) / sqrt(2);
evmRms = sqrt(mean(abs(rxData(:) - reference).^2) / mean(abs(reference).^2));

info = struct();
info.alphaEstimate = alphaEstimate;
info.soundSpeedMps = soundSpeedMps;
info.radialVelocityMmps = radialVelocityMmps;
info.motionDirection = motionDirection;
info.timeStretch = stretch;
info.firstLfm = firstLfm + trimSamples; % 原始接收文件中的位置
info.lastLfm = lastLfm + trimSamples;
info.edgeTrimSamples = trimSamples;
info.coarseCfoHz = coarseCfoHz;
info.fineCfoHz = fineCfoHz;
info.coarseStart = coarseStart;
info.ltsStart = ltsStart;
info.FFT_win_shift = FFT_win_shift;
info.ltsFftStart = ltsFftStart;
info.cfoHz = coarseCfoHz + fineCfoHz;
info.Hest = Hest;
info.ltsNoisePower = ltsNoisePower;
info.ltsSignalPower = ltsSignalPower;
info.ltsReceivedPower = ltsReceivedPower;
info.ltsSnrDb = ltsSnrDb;
info.constellationRaw = rawData;
info.constellationCfoCorrected = cfoData;
info.constellationChannelEqualized = channelEqualized;
info.constellationFinal = rxData;
info.pilotPhaseSlope = phaseSlope;
info.pilotPhaseIntercept = phaseIntercept;
info.evmRms = evmRms;

fprintf('\n========== 接收结果 ==========\n');
fprintf('估计径向速度：%.3f mm/s（%s，声速 %.1f m/s）\n', ...
    abs(radialVelocityMmps), motionDirection, soundSpeedMps);
if isfield(waveform, 'txReference') && numel(waveform.txReference.bits) == numel(rxBits)
    errors = sum(rxBits ~= waveform.txReference.bits(:));
    ref = waveform.txReference.constellation(:);
    refEvm = sqrt(mean(abs(info.constellationFinal(:)-ref).^2)/mean(abs(ref).^2));
    fprintf('误码数：%d / %d，BER：%.3e\n', errors, numel(rxBits), errors/numel(rxBits));
    fprintf('参考星座 RMS EVM：%.3e (%.2f dB)\n', refEvm, 20*log10(max(refEvm, eps)));
else
    fprintf('未提供匹配的发射参考比特，无法计算 BER。\n');
end

figure('Name', 'OFDM 回环接收结果', 'Color', 'w', 'Position', [100 100 1350 700]);
subplot(2,3,1);
plot(real(info.constellationRaw(:)), imag(info.constellationRaw(:)), 'k.');
grid on; axis equal; title('频偏校正前'); xlabel('I'); ylabel('Q');
subplot(2,3,2);
plot(real(info.constellationCfoCorrected(:)), imag(info.constellationCfoCorrected(:)), 'b.');
grid on; axis equal; title('频偏校正后、均衡前'); xlabel('I'); ylabel('Q');
subplot(2,3,3);
plot(real(info.constellationChannelEqualized(:)), imag(info.constellationChannelEqualized(:)), 'r.');
grid on; axis equal; title('信道均衡后'); xlabel('I'); ylabel('Q');
subplot(2,3,4);
plot(real(info.constellationFinal(:)), imag(info.constellationFinal(:)), 'm.');
grid on; axis equal; title('导频线性相位校正后'); xlabel('I'); ylabel('Q');
% 仅显示 LTS 实际估计的子载波，避免把未使用位置的占位值误作 CSI。
valid = find(abs(txInfo.ltsFreq) > eps);
subcarrier = valid - (txInfo.Nfft/2 + 1);
subplot(2,3,5);
plot(subcarrier, 20*log10(abs(info.Hest(valid)) + eps), 'o-');
grid on; xlabel('子载波编号'); ylabel('幅度 (dB)'); title('LTS 信道估计幅度');
subplot(2,3,6);
plot(subcarrier, unwrap(angle(info.Hest(valid))), 'o-');
grid on; xlabel('子载波编号'); ylabel('相位 (rad)'); title('LTS 信道估计相位');


result = info; result.rxBits = rxBits;
if exist('errors','var'), result.bitErrors = errors; result.ber = errors / numel(rxBits); result.referenceEvm = refEvm; end
end

function bits = qpsk_demap(symbols)
bits = zeros(2*numel(symbols), 1);
bits(1:2:end) = real(symbols) < 0;
bits(2:2:end) = imag(symbols) < 0;
end

