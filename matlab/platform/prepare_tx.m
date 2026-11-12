function prepare_tx(cfg, root)
assert(isvarname(cfg.algorithm),'算法名称必须是 MATLAB 合法标识符。');
configFn=str2func([cfg.algorithm '.algorithm_config']);
txFn=str2func([cfg.algorithm '.tx_algorithm']);
algorithmCfg=configFn();
[passband, algorithmInfo, txReference]=txFn(algorithmCfg);
assert(isstruct(algorithmInfo) && isfield(algorithmInfo,'fsPassband'),'algorithmInfo.fsPassband 必须存在。');
validate_waveform(passband,algorithmInfo.fsPassband,cfg); passband=double(passband(:));
platformInfo=struct('fsPassband',cfg.fsPassband,'algorithm',cfg.algorithm,'createdAt',char(datetime('now')));
algorithmName=cfg.algorithm;
dataDir=fullfile(root,'data'); if ~exist(dataDir,'dir'), mkdir(dataDir); end
save(fullfile(dataDir,'tx_passband.mat'),'passband','platformInfo','algorithmName','algorithmInfo','txReference','-v7');
fprintf('波形已生成：%s，%d 点。\n',algorithmName,numel(passband));
end
