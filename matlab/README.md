# MATLAB-FPGA 水声通信测试平台用户手册

## 平台复现视频

可参考 [B 站平台复现视频教程](https://www.bilibili.com/video/BV1ayWi6HEUV/)了解工程搭建与使用流程。

## 1. 使用教程：让 AI 帮助使用平台

如果 AI 助手可以读取本工程目录，请先将 MATLAB 当前文件夹切换到本工程根目录，再把下面的提示词复制给 AI。允许 AI 读取工程文件，并根据实际设备和实验目标补充信息。

### 1.1 快速了解并完成单帧测试

```text
请先阅读当前 MATLAB-FPGA 水声通信测试平台的 README.md，检查
config/platform_config.m、prepare_tx_frame.m、run_rx.m、run_tx.m，以及
platform 目录下相关函数。以当前代码和配置为准，帮助我完成一次单帧收发测试。

请先说明需要检查的硬件连接、发射和接收板 IP、端口、采样率及 MATLAB 依赖，
然后说明如何选择算法、生成波形、在两个 MATLAB 会话中先启动接收再启动发送，
以及如何查看和保存结果。解释本次使用的实际参数，不要假设硬件已经连接或测试通过。

请注意：发射 PL 会在 MATLAB 波形外侧添加 LFM 和保护间隔；接收信号由硬件捕获，
不能假定它只包含 MATLAB 波形。接收等待期间不要重新生成发射文件；data 中同名
MAT 文件会被后续测试覆盖。如发现配置不一致或硬件错误，请根据日志定位后再操作。
```

### 1.2 接入自己的通信算法

```text
请先阅读本工程 README.md、config/platform_config.m、algorithms/+example 中的
三个算法接口文件，以及 platform/prepare_tx.m 和 platform/capture_and_decode.m。

我要接入的算法是：[填写算法名称、调制方式、带宽和其他要求]。
请根据当前代码设计并实现匹配的发射和接收算法，放在独立的 MATLAB 包目录中，
遵循 algorithm_config、tx_algorithm、rx_algorithm 的接口。发射端输出实数通带
采样，并通过 algorithmInfo 保存接收所需配置；txReference 仅作为可选参考。

请遵守平台采样率和帧长限制，考虑 PL 附加的同步信号和保护间隔，明确参数、
依赖和运行步骤。请保留现有算法，并说明哪些验证已经完成、哪些仍需硬件测试；
如需改动平台接口或 FPGA/PS 协议，请先说明影响范围。
```

如果 AI 无法直接读取本工程，请将本手册、相关配置文件和准备修改的算法文件提供给它。提示词中的设备 IP、参数和运行状态应以当前配置及实际测试为准。

## 2. 平台用途

本平台用于将 MATLAB 生成的通带波形发送到 FPGA 发射机，并从 FPGA 接收机采集通带波形，交给 MATLAB 算法处理。平台负责波形检查、DAC 数据量化、TCP 通信、接收门限设置和数据保存；使用者负责自己的发射成帧和接收处理算法。

## 3. 目录说明

```text
UWAC_Algorithm_Platform/
├─ config/platform_config.m          平台和硬件参数
├─ platform/                          波形检查及网口收发函数
├─ algorithms/
│  ├─ +ofdm_lts_pilot/               长导码信道估计 OFDM
│  ├─ +ofdm_pilot_interp/            逐符号导频插值信道估计 OFDM
│  ├─ +fsk_noncoherent/              非相干 2FSK
│  └─ +example/                      算法接口示例
├─ data/                              本次收发的共享文件
├─ prepare_tx_frame.m                 生成发射波形
├─ run_rx.m                           连接接收机、接收并处理
├─ run_tx.m                           发送已生成的波形
└─ setup_platform.m                   加载平台路径
```

各算法目录中的 `algorithm_config.m` 用于修改本算法的发射参数；OFDM 接收算法的同步等参数目前位于相应 `rx_algorithm.m` 顶部。

## 4. 使用前配置

1. 确认 MATLAB 已安装 Signal Processing Toolbox；内置 OFDM 算法使用 `resample` 和 `findpeaks`。
2. 发射板、接收板正常上电并运行匹配的 PS/PL 程序，分别确认它们的网络地址。
3. 打开 `config/platform_config.m`，设置：
   - `cfg.algorithm`：选择 `ofdm_lts_pilot`、`ofdm_pilot_interp`、`fsk_noncoherent` 或自己添加的算法名称；
   - `cfg.txIp`、`cfg.txPort`：发射板 IP 与端口；
   - `cfg.rxIp`、`cfg.rxPort`：接收板 IP 与端口；
   - `cfg.corrThreshold`：接收 PL 归一化相关功率门限，范围 (0, 1]；
   - `cfg.corrMinEnergy`：接收 PL 最小窗口能量门限；
   - `cfg.targetVpp`、`cfg.dacFullScaleVpp`、`cfg.calibrationFactor`：DAC 输出缩放和测量校准参数；
   - `cfg.plotTx`、`cfg.plotRx`：是否绘制发送和接收通带波形。
4. 将 MATLAB 当前文件夹切换到本工程根目录。准备两个 MATLAB 会话，并在两个会话中选择相同的工程目录和配置。

默认配置的发射板 IP 为 `192.168.1.10:6001`，接收板 IP 为 `192.168.2.10:6002`；请根据实际串口输出和电脑网卡配置修改，保证电脑分别能访问两个地址。

## 5. 单帧收发步骤

接收会话在等待数据时会阻塞，因此使用两个 MATLAB 会话操作。

1. **准备波形**：在发送会话运行 `prepare_tx_frame`。程序调用选定算法，保存 `data/tx_passband.mat`。
2. **启动接收**：在接收会话运行 `run_rx`。程序连接接收板并设置检测门限；等到打印“接收端就绪”。
3. **发送波形**：在发送会话运行 `run_tx`。程序读取已经准备好的文件并发送；不要在接收会话等待期间重新生成发射文件。
4. **查看结果**：接收会话收到完整帧后保存 `data/rx_passband.mat`，调用对应接收算法，并保存 `data/result.mat`。内置 OFDM 算法还会打印信噪比、速度和误码等结果并绘图。

重新选择算法或修改发射参数后，需重新运行 `prepare_tx_frame`。两个会话使用的 `cfg.algorithm` 必须与发射文件中的算法名称一致。每次新收发会覆盖对应 MAT 文件；需要保留的数据请预先另存。

## 6. 接入自己的算法

复制 `algorithms/+example`，例如命名为 `algorithms/+my_algorithm`，将 `cfg.algorithm` 设置为 `my_algorithm`。目录名前的 `+` 是 MATLAB 包目录标识；算法名应是合法 MATLAB 标识符。

按以下接口实现三个文件：

```matlab
% algorithm_config.m：定义算法需要的发射参数
function cfg = algorithm_config()
end

% tx_algorithm.m：生成 MATLAB 要发送的完整通带波形
function [passband, algorithmInfo, txReference] = tx_algorithm(cfg)
end

% rx_algorithm.m：处理接收板传回的完整通带数据
function result = rx_algorithm(passband, algorithmInfo, txReference, cfg)
end
```

- `passband`：发送端输出为非空有限实数向量；接收端输入为完整捕获数据。
- `algorithmInfo`：结构体，必须包含 `fsPassband = 1e6`，其他字段由算法定义，用来保存接收所需参数和同步模板。
- `txReference`：可选发射参考；不需要时发射函数返回 `[]`。若在没有本地发射文件的情况下接收，可在 `platform_config.m` 中提供 `cfg.algorithmInfo`，此时参考为空。
- `result`：接收算法输出的结构体，字段由算法自己决定。
- `cfg`：接收函数获得的平台配置；发射函数获得的是该算法的 `algorithm_config`。

`+example` 生成 25 kHz 单音，接收时打印采样点数和 RMS，可作为接口示例。自定义算法需要自行实现实际调制、同步和解调。

## 7. 平台接口约束

- 当前硬件通带采样率为 **1 MHz**；发射波形最多 10000000 点，即 10 秒。接收捕获还受 PL 最大长度、前后缓存和多普勒影响，接近上限时需单独验证。
- 接收 PL 带通的目标频带为 **20～30 kHz**；具体频率响应和信号幅度应结合实际设备验证。
- 发射 PL 在 MATLAB 波形外侧添加首尾各 10 ms 的 PL LFM，以及各 30 ms 保护间隔。接收算法的输入包含 PL 带通滤波后的捕获数据，可能包含这些信号和前后冗余，不保证只包含算法自己的帧。
- DAC 输出 Vpp 配置依赖现有标定参数和负载，实际值请用示波器测量并调整。平台会按整个发射波形的最大值统一缩放。
- 当前网络协议不在波形中携带算法编号或帧编号。本地 MAT 文件只能记录选定配置，不能独立证明实际接收帧属于该次发射。
- 平台发现接收等待期间的发射文件大小或修改时间发生变化时，会保存已收到的波形并停止自动解调；仍需人工确保使用的是正确发射帧。
- 若主动停止接收后重连失败，请检查接收板串口和 DMA/PL 状态，必要时复位接收板。
