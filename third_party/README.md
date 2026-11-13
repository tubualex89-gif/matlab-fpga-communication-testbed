# Vitis lwIP 软件仓库

`local_sw_repo_lwip220.zip` 是本平台已使用的 Vitis 2026.1 本地软件仓库，提供 lwip220 组件。将压缩包解压后，在 Vitis 的 **Vitis → Embedded SW Repositories → Local Repositories** 中添加解压得到的 `local_sw_repo` 目录，扫描仓库，然后在 Platform 对应 standalone 域的 BSP 中启用 lwip220。

目录结构：

```text
local_sw_repo/
└── ThirdParty/sw_services/lwip220/
    ├── data/
    ├── examples/
    └── src/
```

此包来自本项目使用的本地仓库；其对应源码与本机 Vitis 2026.1 官方 lwip220_v1_4 文件曾做内容对照，已发现 data/lwip220.yaml 的文件开头 BOM 不同。保留各文件原有版权与许可证；lwIP 的许可证见 `src/lwip-2.2.0/COPYING`。使用前请阅读完整许可声明；本包不代表 AMD 官方发布的独立包。

添加仓库后，新建或重新生成平台的 BSP，再配置 lwip220 与 xiltimer。如果使用 Echo Server 模板，其模板创建校验可能要求 DHCP 等参数；本平台发射应用使用静态 IP 时需按应用要求重新配置并构建 BSP。
