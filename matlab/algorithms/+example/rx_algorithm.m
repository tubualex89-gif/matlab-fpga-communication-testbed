function result = rx_algorithm(passband, algorithmInfo, txReference, cfg)
% 示例：完整捕获数据可能包含 PL LFM、保护间隔与前后冗余。
% 自己的算法可在此做同步、解调；txReference 可以为空。
result=struct('sampleCount',numel(passband),'rms',sqrt(mean(double(passband(:)).^2)));
fprintf('示例算法收到 %d 点，RMS %.3f ADC counts。\n',result.sampleCount,result.rms);
end
