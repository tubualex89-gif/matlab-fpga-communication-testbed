% 第一步：选择 config/platform_config.m 中的算法，生成发射文件。
root=fileparts(mfilename('fullpath')); addpath(root); setup_platform();
cfg=platform_config(); prepare_tx(cfg,root);
