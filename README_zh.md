# MATLAB-FPGA 通信算法实测平台

[English](README.md) | 中文

本平台面向使用 MATLAB 开发通信算法的工程师和学生，帮助使用者通过 MATLAB 控制 FPGA 收发硬件，在真实信道中验证算法性能，无须为了开展实测先将每一种算法重新用 Verilog 实现。对于一些直接部署到 FPGA 较困难的 AI 通信算法，这种方式尤其方便。

FPGA 负责波形发射和采集的硬件接口，调制、同步、解调、AI 推理和性能分析等处理可以保留在使用者的 MATLAB 流程中。接入时，算法仍需生成符合硬件采样率等要求的实数通带波形，并自行处理接收到的采样数据。

## 工作方式

```text
MATLAB 算法 → TCP → FPGA 发射端 → DAC → 实际信道
MATLAB 算法 ← TCP ← FPGA 接收端 ← ADC ← 实际信道
```

MATLAB 生成波形并通过网络发送给发射板；发射板添加硬件同步信号和保护间隔。接收板捕获信号后将采样数据发送回 MATLAB，供算法处理。

## 当前参考配置

- 基于 PYNQ-Z2 的发射端和接收端，连接外部 DAC、ADC 模块。
- 通带采样率：**1 MHz**；当前接收滤波器目标频带：**20～30 kHz**。
- 当前实测场景：约 **25 kHz** 中心频率的单帧实验，包含水声信道。
- MATLAB 内置 FSK、OFDM 示例，并提供用户算法接口示例。
- 原开发工具：**Vivado/Vitis 2026.1**。MATLAB 版本和工具箱要求请参阅 [MATLAB 用户手册](matlab/README.md)。

如需扩展频段、带宽或更换板卡、模拟前端，需要按目标硬件修改配置并重新验证。本目录目前为首版候选，完整的干净环境重建流程和第三方文件授权仍待核查。

## 目录说明

```text
matlab/          MATLAB 平台、算法及用户手册
hardware/tx/     FPGA 发射工程、RTL 和约束
hardware/rx/     FPGA 接收工程、RTL 和约束
hardware/ip_repo/ 自定义 FPGA 控制 IP
firmware/tx/     发射端 PS 应用源码
firmware/rx/     接收端 PS 应用源码
docs/            发布检查清单及相关文档
third_party/     本地 lwIP 仓库包及安装说明（如已提供）
```

## 视频教程

可参考 [B 站平台复现视频教程](https://www.bilibili.com/video/BV1ayWi6HEUV/)了解工程搭建与使用流程。

## 单帧测试概要

请先参考 [MATLAB 用户手册](matlab/README.md)完成硬件接线、网络设置和算法配置，然后使用两个 MATLAB 会话：

1. 在发送会话选择算法并运行 `prepare_tx_frame`。
2. 在接收会话运行 `run_rx`，等待提示接收端就绪。
3. 在发送会话运行 `run_tx`，查看接收波形和算法结果。

两个会话应使用匹配配置，后续测试可能覆盖生成的 MAT 文件。仓库已提供收发两端 PS 源码，但从零创建 Vitis 平台和配置 BSP 的完整流程仍需进一步验证。

## 当前限制

参考接收端使用固定的硬件捕获流程和滤波器；实际发射帧包含 FPGA 添加的 LFM 和保护间隔。输出电压取决于 DAC、模拟电路、负载及标定。发送和捕获长度、异常恢复能力及工具版本兼容性均需结合实际硬件确认。

公开发布前，请检查[发布检查清单](docs/RELEASE_CHECKLIST.md)及第三方文件的版权和许可证。

## 许可证

项目原创贡献采用 [MIT 许可证](LICENSE)。第三方文件仍适用其原有条款，详见[第三方说明](THIRD_PARTY_NOTICES.md)。
