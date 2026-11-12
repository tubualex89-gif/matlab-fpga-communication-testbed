% 第二步：运行并等待接收板就绪；随后在另一个 MATLAB 会话运行 run_tx。
root=fileparts(mfilename('fullpath')); addpath(root); setup_platform(); cfg=platform_config();
capture_and_decode(cfg,root);
