function result = rx_algorithm(passband, algorithmInfo, txReference, cfg)
% 首尾 LFM 估计整体时间缩放，重采样后以双频复相关能量判决 2FSK。
edgeTrimSeconds = 0.020;       % 硬件采集首尾余量，视捕获条件调整
maxTimeScaleDeviation = 0.02; % 峰对允许的相对时间尺度偏差
info=algorithmInfo;
assert(isfield(info,'algorithmId') && strcmp(info.algorithmId,'fsk_noncoherent_v1'), '接收配置不是 FSK 配套配置。');
fs=info.fsPassband; x=double(passband(:));
assert(isreal(x) && ~isempty(x) && all(isfinite(x)), '接收波形无效。');
trim=round(edgeTrimSeconds*fs);
assert(2*trim<numel(x), '接收波形不足，无法截去首尾。');
x=x(trim+1:end-trim); ref=double(info.lfm(:)); M=numel(ref);
assert(numel(x)>=M, '接收波形短于同步 LFM。');
L=2^nextpow2(numel(x)+M-1);
r=abs(ifft(fft(x,L).*fft(flipud(ref),L),'symmetric')); r=r(M:numel(x));
[v,p]=findpeaks(r,'MinPeakDistance',max(1,round(.005*fs)));
if numel(r)>=2 && r(1)>=r(2), p(end+1,1)=1;v(end+1,1)=r(1);end
if numel(r)>=2 && r(end)>=r(end-1), p(end+1,1)=numel(r);v(end+1,1)=r(end);end
[p,order]=sort(p(:)); v=v(order); first=0; last=0; best=-Inf;
for k=1:numel(p)
    separation=p-p(k); candidates=find(separation>0 & abs(separation/info.lfmSeparation-1)<=maxTimeScaleDeviation);
    if ~isempty(candidates)
        [tail, j]=max(v(candidates)); score=min(v(k),tail);
        if score>best && score>0, best=score; first=p(k); last=p(candidates(j)); end
    end
end
assert(first>0,'未找到符合时间尺度约束的首尾 LFM 峰。');
stretch=(last-first)/info.lfmSeparation; samples=info.lfmSamples+info.symbolSamples*info.payloadBits;
query=first+(0:samples-1).'*stretch;
assert(query(end)<=numel(x), '接收波形不完整，无法提取所有 FSK 符号。');
corrected=interp1((1:numel(x)).',x,query,'linear');
data=reshape(corrected(info.lfmSamples+1:end),info.symbolSamples,info.payloadBits);
t=(0:info.symbolSamples-1).'/fs;
z0=exp(-1j*2*pi*info.f0*t); z1=exp(-1j*2*pi*info.f1*t);
energy0=abs(z0.'*data).^2; energy1=abs(z1.'*data).^2;
bits=double(energy1(:)>energy0(:));
result=struct('rxBits',bits,'energy0',energy0(:),'energy1',energy1(:), ...
    'firstLfm',first+trim,'lastLfm',last+trim,'timeStretch',stretch,'alphaEstimate',1/stretch);
fprintf('2FSK 已解调：%d bit。\n',numel(bits));
if ~isempty(txReference) && isstruct(txReference) && isfield(txReference,'bits') && numel(txReference.bits)==numel(bits)
    result.bitErrors=sum(bits~=txReference.bits(:)); result.ber=result.bitErrors/numel(bits);
    fprintf('误码数：%d / %d，BER：%.3e\n',result.bitErrors,numel(bits),result.ber);
else
    fprintf('没有匹配的参考比特，未计算 BER。\n');
end
figure('Name','2FSK 解调结果','Color','w');
subplot(2,1,1);plot(energy0,'b.-');hold on;plot(energy1,'r.-');grid on;
xlabel('比特序号');ylabel('相关能量');legend('f0','f1');title('逐比特双频相关能量');
subplot(2,1,2);stairs(bits,'LineWidth',1);ylim([-0.2 1.2]);grid on;
xlabel('比特序号');ylabel('判决比特');title('接收比特');
end
