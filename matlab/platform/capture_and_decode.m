function capture_and_decode(cfg, root)
dataDir=fullfile(root,'data'); txFile=fullfile(dataDir,'tx_passband.mat');
if isfile(txFile)
    txFileBefore = dir(txFile);
    metadata=load(txFile,'algorithmInfo','algorithmName','txReference');
    assert(isfield(metadata,'algorithmInfo') && isfield(metadata,'algorithmName'),'发射文件缺少算法配置。');
    assert(strcmp(metadata.algorithmName,cfg.algorithm),'所选算法与发射文件不匹配，请先用所选算法准备发射波形。');
    algorithmInfo=metadata.algorithmInfo;
    if isfield(metadata,'txReference'), txReference=metadata.txReference; else, txReference=[]; end
elseif isfield(cfg,'algorithmInfo') && ~isempty(cfg.algorithmInfo)
    algorithmInfo=cfg.algorithmInfo; txReference=[];
else
    error('未找到发射配置。请先运行 prepare_tx_frame，或在平台配置中提供 algorithmInfo。');
end
[passband, rxControl]=receive_waveform(cfg);
fileChanged = false;
if exist('txFileBefore','var')
    txFileAfter = dir(txFile);
    fileChanged = isempty(txFileAfter) || txFileAfter.bytes ~= txFileBefore.bytes || txFileAfter.datenum ~= txFileBefore.datenum;
end
platformInfo=struct('fsPassband',cfg.fsPassband,'algorithm',cfg.algorithm,'capturedAt',char(datetime('now')));
algorithmName=cfg.algorithm;
if ~exist(dataDir,'dir'),mkdir(dataDir);end
save(fullfile(dataDir,'rx_passband.mat'),'passband','platformInfo','algorithmName','algorithmInfo','txReference','rxControl','-v7');
fprintf('接收波形已保存。\n');
if fileChanged
    error('接收等待期间发射文件发生变化；原始采样已保存，但无法确认参考配置对应关系，请重新收发。');
end
rxFn=str2func([cfg.algorithm '.rx_algorithm']); result=rxFn(passband,algorithmInfo,txReference,cfg);
save(fullfile(dataDir,'result.mat'),'result','-v7');
end
