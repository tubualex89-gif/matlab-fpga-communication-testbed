# Third-party notices / 第三方说明

The root MIT License applies to project-owned contributions. Third-party files retain their original copyright notices and license terms; consult the notices in each file and package. This file is an initial inventory, not a substitute for those notices.

根目录 MIT 许可证适用于项目原创贡献。第三方文件仍适用其原有版权声明和许可条款，请以各文件及软件包内的声明为准。以下为初步清单。

- **AMD/Xilinx**: `firmware/tx/` and `firmware/rx/` include files derived from AMD/Xilinx examples. Retain the copyright and license text in the individual files. Vivado/Vitis, device support files and AMD IP are separate dependencies subject to their applicable terms.
- **lwIP and AMD/Xilinx lwIP integration**: `third_party/local_sw_repo_lwip220.zip` contains the local Vitis lwip220 software repository. lwIP copyright and license terms are in `local_sw_repo/ThirdParty/sw_services/lwip220/src/lwip-2.2.0/COPYING` inside that archive; retain other notices included with the source files. The repository was prepared from the locally installed AMD Vitis 2026.1 lwip220 component, with its YAML metadata adjusted by removal of a UTF-8 BOM. It is not presented as an official standalone AMD release.
- **Pin constraints**: The comment in `hardware/tx/MATLAB_FPGA_UWA_testbed.srcs/constrs_1/new/tx_dac.xdc` states that the pin mapping was adapted from a reference `tx_dac.xdc`. This project does not include openofdm as a runtime dependency. Confirm the provenance and applicable terms of any copied material before publication.
