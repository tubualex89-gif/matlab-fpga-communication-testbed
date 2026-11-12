function [passband, rxControl] = receive_waveform(cfg)
assert(isscalar(cfg.corrThreshold) && isfinite(cfg.corrThreshold) && cfg.corrThreshold>0 && cfg.corrThreshold<=1, '相关阈值必须在 (0,1]。');
assert(isscalar(cfg.corrMinEnergy) && isfinite(cfg.corrMinEnergy) && cfg.corrMinEnergy>=0 && cfg.corrMinEnergy<=2^40-1 && cfg.corrMinEnergy==fix(cfg.corrMinEnergy), '最小能量无效。');
q=max(1,round(cfg.corrThreshold*32768)); energy=uint64(cfg.corrMinEnergy); e=zeros(1,5,'uint8');
for k=1:5, e(k)=uint8(bitand(bitshift(energy,-8*(5-k)),uint64(255))); end
request=[uint8('RXC1'),uint8(floor(q/256)),uint8(mod(q,256)),e,uint8(0)];
fprintf('连接接收板 %s:%d ...\n',cfg.rxIp,cfg.rxPort);
connection=tcpclient(cfg.rxIp,cfg.rxPort,'Timeout',cfg.rxIdleTimeout);
write(connection,request,'uint8'); reply=read_exact(connection,5,cfg);
assert(isequal(reply(1:4).',uint8('RXA1')),'接收板配置响应不匹配。');
if reply(5)~=0, error('接收板配置失败，状态 %d；请检查 PS/PL 版本和串口。',reply(5)); end
fprintf('接收端就绪；现在可运行发送入口。\n');
header=read_exact(connection,4,cfg);
n=double(header(1))*2^24+double(header(2))*2^16+double(header(3))*2^8+double(header(4));
assert(n>0 && n<=cfg.rxMaxSamples && n==fix(n),'接收采样数无效：%.0f',n);
fprintf('接收 %.0f 个采样点。\n',n); bytes=read_exact(connection,2*n,cfg);
samples=typecast(uint8(bytes),'int16'); [~,~,e]=computer; if e=='B', samples=swapbytes(samples); end
passband=double(samples(:));
rxControl=struct('corrThreshold',cfg.corrThreshold,'corrThresholdQ15',q,'corrMinEnergy',cfg.corrMinEnergy);
if cfg.plotRx
    figure('Name','完整接收通带波形'); plot((0:n-1)/cfg.fsPassband,passband);
    xlabel('Time (s)'); ylabel('ADC counts'); grid on;
end
end
function bytes=read_exact(c,n,cfg)
bytes=zeros(n,1,'uint8'); pos=1; lastData=tic;
while pos<=n
    avail=double(c.NumBytesAvailable);
    if avail>0
        count=min([avail,n-pos+1,cfg.chunkBytes]); part=read(c,count,'uint8');
        if isempty(part), error('TCP 连接未返回数据。'); end
        bytes(pos:pos+numel(part)-1)=part(:); pos=pos+numel(part); lastData=tic;
    elseif toc(lastData)>cfg.rxIdleTimeout
        error('等待接收数据超时，已收到 %d / %d 字节，请检查接收板串口。',pos-1,n);
    else
        pause(0.005);
    end
end
end
