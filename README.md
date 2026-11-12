# MATLAB-FPGA Communication Testbed

基于 MATLAB 和 FPGA 的通信算法实测平台。MATLAB 生成通带波形并通过网络发送，FPGA 发射端完成波形输出；接收端采集实际信道信号并传回 MATLAB 进行处理。

当前参考实现面向 1 MHz 采样、约 25 kHz 中心频率的低频水声单帧实验。扩展频段需要根据目标频率、带宽及 ADC/DAC 和模拟前端能力重新设计并验证。

> 本目录为首版发布候选：Vivado/Vitis 从本目录重建、第三方文件授权及硬件复现尚待核查；不应视为已经完成的正式发布。

## 目录

- `matlab/`：MATLAB 平台、示例算法和[用户手册](matlab/README.md)。
- `hardware/tx/`、`hardware/rx/`：发射和接收 Vivado 工程源码及约束。
- `hardware/ip_repo/`：两端自定义 IP。
- `firmware/tx/`、`firmware/rx/`：两端 PS 应用源码，含原厂示例衍生文件。
- `docs/RELEASE_CHECKLIST.md`：发布前必须解决的事项。

## 单帧测试概要

先参考 `matlab/README.md` 完成硬件和网络配置，再运行 `prepare_tx_frame`，在接收会话运行 `run_rx` 并等待就绪，然后在发送会话运行 `run_tx`。使用两个 MATLAB 会话，保持算法配置一致；测试文件可能被后续测试覆盖。

本工程原开发工具版本为 Vivado/Vitis 2026.1；MATLAB 版本及工具箱要求需进一步核实。其他版本、板卡和频段尚未验证。
