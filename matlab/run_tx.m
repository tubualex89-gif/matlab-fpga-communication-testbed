% 第三步：接收端提示就绪后，发送已准备好的波形。
root=fileparts(mfilename('fullpath')); addpath(root); setup_platform(); cfg=platform_config();
file=fullfile(root,'data','tx_passband.mat'); assert(isfile(file),'请先运行 prepare_tx_frame。');
d=load(file,'passband','algorithmInfo','algorithmName');
assert(strcmp(d.algorithmName,cfg.algorithm),'发射文件和当前算法不匹配；请重新准备波形。');
send_waveform(d.passband,d.algorithmInfo,cfg);
