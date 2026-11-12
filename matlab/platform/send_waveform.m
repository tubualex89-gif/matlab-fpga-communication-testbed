function send_waveform(passband, algorithmInfo, cfg)
validate_waveform(passband, algorithmInfo.fsPassband, cfg);
x = double(passband(:)); N = numel(x);
assert(cfg.targetVpp > 0 && cfg.targetVpp <= 2 && cfg.dacFullScaleVpp >= cfg.targetVpp, 'DAC 幅值设置无效。');
fraction = cfg.targetVpp / cfg.dacFullScaleVpp * cfg.calibrationFactor;
assert(isfinite(fraction) && fraction > 0 && fraction <= 1, 'DAC 幅度缩放无效。');
samples = int16(round(x * (fraction * 32767 / max(abs(x)))));
if cfg.plotTx
    figure('Name','发送通带波形'); plot((0:N-1)/cfg.fsPassband,double(samples)/32768);
    xlabel('Time (s)'); ylabel('Normalized amplitude'); grid on; drawnow;
end
[~,~,endian] = computer; if endian=='B', samples=swapbytes(samples); end
payload=typecast(samples,'uint8'); payload=payload(:);
header=uint8([bitand(bitshift(uint32(N),-24),255),bitand(bitshift(uint32(N),-16),255), ...
    bitand(bitshift(uint32(N),-8),255),bitand(uint32(N),255)]);
fprintf('当前发射算法：%s\n', cfg.algorithm);
fprintf('正在连接发射板 %s:%d ...\n', cfg.txIp, cfg.txPort);
connection=tcpclient(cfg.txIp,cfg.txPort,'Timeout',cfg.txTimeout);
fprintf('发射板 TCP 连接成功：%s:%d。\n', cfg.txIp, cfg.txPort);
fprintf('正在发送 %d 个采样点。\n', N);
write(connection,header,'uint8');
for first=1:cfg.chunkBytes:numel(payload)
    write(connection,payload(first:min(first+cfg.chunkBytes-1,numel(payload))),'uint8');
end
started=tic;
while connection.NumBytesAvailable < 1
    if toc(started)>cfg.txTimeout, error('等待发射结果超时，请检查发射板串口。'); end
    pause(0.01);
end
status=read(connection,1,'uint8');
if status~=0, error('发射板返回错误状态 %d；请检查串口和 DMA/PL 状态。',status); end
fprintf('发射完成。\n');
end
