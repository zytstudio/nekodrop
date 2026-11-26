# 支持的网卡与适配新网卡

[English](CARDS.md) · 简体中文 · [返回 README](../README.zh-CN.md)

## 支持的网卡

nekodrop 通过模块化底层驱动后端（`CardCatalog` + `radio_backend.h`）直接驱动无线网卡芯片，每个网卡家族一个用户态 radio：

- **Intel** 22000 / AX210 族，以及实验性的 **BE200**（`nekodrop-radio.exe`，移植自 [ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm) 的 `hal_iwx`）：同时连 Wi-Fi 或按需接管。
- **Realtek RTL8852CE**（`nekodrop-radio-rtl.exe`，基于 [winawdl](https://github.com/raph559/winawdl)/[devourer](https://github.com/raph559/devourer)）：按需接管。
- **Realtek RTL8821CU USB 网卡**（`nekodrop-radio-usb.exe`，同一份 winawdl radio，走 devourer 的 libusb 传输）：常驻（随服务启动），实验性。**仅本分支**——上游 nekodrop 只支持 PCIe 网卡，没有 USB 路径。
- **MediaTek MT7902**（`nekodrop-radio-mt.exe`）和 **MT7921 / MT7922**（`nekodrop-radio-mtk.exe`），从 Linux mt76 移植到用户态：同时连 Wi-Fi（仅 5 GHz）或按需接管。

哪些在真机上测过，见下表。表外的网卡见[适配新网卡](#适配新网卡)。

**完整跨品牌网卡兼容性文档（Intel / Realtek / MediaTek / 高通）：[docs/COMPATIBILITY.zh-CN.md](COMPATIBILITY.zh-CN.md)** · **更新日志：[CHANGELOG.md](../CHANGELOG.md)** · **底层多网卡架构：[docs/HARDWARE.md](HARDWARE.md)**

当前已内置启用的网卡速览：

| 网卡 | PCI ID | 固件 / 后端 | 状态 |
|---|---|---|---|
| **Intel Wi-Fi 6 AX201** 160 MHz（CNVi） | `8086:` `02F0` `06F0` `34F0` `3DF0` `4DF0` `43F0` `A0F0` | `Qu/QuZ-hr-b0-68`（`iwx`，同时连 Wi-Fi / 按需） | ✅ **已实测**（`43F0` 上的 QuZ） |
| Qu/QuZ 上的 Intel Wireless-AC 9560 / 9462 / 9461（CNVi） | 与 AX201 相同 | `Qu/QuZ-jf-b0-68`（`iwx`，同时连 Wi-Fi / 按需） | ✅ 用户实测可用（9560，[#45](../../../issues/45)） |
| Intel Wi-Fi 6 AX200（独立网卡） | `8086:2723` | `cc-a0-68`（`iwx`，同时连 Wi-Fi / 按需） | ✅ 用户反馈双向 AirDrop 可用（[#1](../../../issues/1)、[#4](../../../issues/4)）；打开 A-MPDU 后发给 iPhone 9–25 MiB/s（[#4](../../../issues/4)） |
| Intel Wi-Fi 6E AX210（独立网卡） | `8086:2725` | `ty-a0-gf-a0-68` + PNVM（`iwx`，同时连 Wi-Fi / 按需） | ✅ 用户反馈双向 AirDrop 可用（[#14](../../../issues/14)、[#18](../../../issues/18)、[#11](../../../issues/11)） |
| Intel Wi-Fi 6E AX211（CNVi，第 12 代及以后） | `8086:` `7AF0` `7A70` `51F0` `51F1` `54F0` `7F70` | `so-a0-gf-a0-68` + PNVM（`iwx`，同时连 Wi-Fi / 按需） | ✅ 用户反馈双向 AirDrop 可用（[#9](../../../issues/9)、[#29](../../../issues/29)）；0.1.31 起 iPhone 能看到电脑（[#24](../../../issues/24)） |
| Intel Wi-Fi 6E AX411 / Killer AX1690（CNVi） | 与 AX211 相同 | `so-a0-gf4-a0-68` + PNVM（`iwx`，同时连 Wi-Fi / 按需） | ✅ 用户实测可用（[#37](../../../issues/37)） |
| So 平台上的 Intel Wi-Fi 6 AX203 / 9560 | 与 AX211 相同 | `so-a0-hr/jf-b0-68`（`iwx`，同时连 Wi-Fi / 按需） | ⚠️ 未测试 |
| **Realtek RTL8852CE** | `10EC:C852` | 内嵌固件（`devourer`，仅按需接管） | ✅ 已内置；用户实测双向可用，峰值约 **24.5 MB/s**（[#61](../../../issues/61)） |
| **Realtek RTL8821CU**（USB） | `0BDA:C820` `0BDA:C821` | 内嵌固件（`devourer` 走 libusb，常驻） | 🧪 **仅本分支**，实验性：WinUSB 绑到网卡 `MI_02`，已验证 iPhone → PC 隔空投送（149 / 20 MHz，14.2 MB Live Photo 包 339 KB/s）；PC → iPhone 未测（[RTL8821CU.md](RTL8821CU.md)） |
| **MediaTek MT7902** | `14C3:7902` | linux-firmware `WIFI_RAM_CODE_MT7902_1`（移植自 `mt76`，同时连 Wi-Fi（仅 5 GHz）与按需接管） | ✅ 已内置；双向 AirDrop（接收约 15 MB/s，发送约 5 MB/s）与同时连 Wi-Fi 均已真机实测（[#34](../../../pull/34)、[#47](../../../pull/47)） |
| **MediaTek MT7922 / AMD RZ616** | `14C3:0616` `14C3:7922` | linux-firmware `WIFI_RAM_CODE_MT7922_1`（`mtkradio`，同时连 Wi-Fi（仅 5 GHz，实验性）与按需接管） | 🧪 实验性，已内置；双向 AirDrop 已实测（[#40](../../../pull/40)，[docs/MT7922.md](MT7922.md)）；`v2.2.8`–`v2.2.9` 已补齐 HE80 2SS LWTBL、扫描 `FIF_BIT_CLR`、固件 RA 与 RX A-MSDU 修复（[#65](../../../pull/65)、[#66](../../../issues/66)） |
| **MediaTek MT7921 / AMD RZ608** | `14C3:7961` `14C3:0608` | linux-firmware `WIFI_RAM_CODE_MT7961_1`（`mtkradio`，同时连 Wi-Fi（仅 5 GHz，实验性）与按需接管） | ⚠️ 实验性，已内置；按需与同时连 Wi-Fi 均尚未在真机上测试 |
| Intel SnJ `2726`、QnJ `2720`、Meteor Lake `7E40`/`2729` | `8086:` | 上游没有固件 | ❌ |
| **Intel Wi-Fi 7 BE200**（独立网卡） | `8086:272B` | linux-firmware `gl-c0-fm-c0-100`（`iwx` 的 Bz/MLD 路径，同时连 Wi-Fi / 按需） | 🧪 实验性，已内置；`v2.2.9` 已加固 4096 字节页对齐与双 LMAC 诊断，欢迎实测反馈（[#53](../../../issues/53)、[docs/BE200.md](BE200.md)） |
| Intel BE201 / BE211（Wi-Fi 7，CNVi） | `8086:` `A840` `7740` | 需要 CNVi 硬件 | ❌ |
| 其他 Realtek、MediaTek、高通、博通 | | | ❌ |

怎么看自己的网卡：打开 *设备管理器 → 网络适配器*。没有受支持的无线网卡时，安装程序会拒绝安装，并列出本机检测到的无线网卡、PCI/USB ID 和不支持原因，以及运行 `installer/report.ps1` 的指引。在未实测的网卡上（包括新内置的 Realtek RTL8852CE 后端），nekodrop 可能启动不了 radio；这时网卡不会坏，运行**[一键回退](SUPPORT.zh-CN.md)**即可，也欢迎在 [Issues](../../../issues) 附上日志反馈。

网卡按 PCI ID 自动识别。没识别出来时，可以在 *设置 → 网卡* 里手动选择网卡和型号（只对驱动包里列出的硬件 ID 有效）。想给 nekodrop 适配新的网卡家族，见 [docs/ADDING-A-CARD.md](ADDING-A-CARD.md)。

不确定自己是什么网卡，或者希望支持别的网卡？[诊断报告](SUPPORT.zh-CN.md#反馈问题诊断报告)不装 nekodrop 也能用：下载 [`installer/report.ps1`](../installer/report.ps1)，运行 `powershell -ExecutionPolicy Bypass -File report.ps1`。它会列出每块无线网卡的 PCI ID、芯片、驱动，以及 nekodrop 为什么能或不能在上面运行；欢迎贴到 [Issues](../../../issues)。已安装 nekodrop 时，运行 `NekoDropService.exe --status` 可查看匹配到的网卡档案、能力与当前驱动提供者，`NekoDropService.exe --selftest` 可在无网卡、无管理员权限下校验全部 22 个活跃网卡档案以及多后端启动参数规划。Intel 的 radio 启动时会记一行 `backend …` 日志并在每次构建时运行 `iwx_selftest`；Realtek 的 radio 构建会同步运行四项离线单测（`block_ack_test`、`reorder_buffer_test`、`outgoing_session_test`、`dma_address_test`）；`install.ps1 -SelfTest`、`restore.ps1 -SelfTest` 和 `report.ps1 -SelfTest` 也会在每次构建时于 Windows PowerShell 5.1 下运行离线自检。支持其他网卡需要做什么，见 [docs/HARDWARE.md](HARDWARE.md)（英文）。

## 适配新网卡

nekodrop 只支持上表里的网卡。**单纯要求支持其他网卡、不附代码的 issue 会直接关闭**，并附上本节链接。我们只能适配手上有的网卡，或者有人移植并在真机上测过的网卡。新笔记本里的网卡，比如 Intel Wi-Fi 7 的 CNVi 版本（BE201/BE211、Panther Lake `8086:E440`，Windows 里显示为「AX211」）、高通、博通，都需要重新移植驱动，不是加一个设备 ID 就能支持的。

如果你手上有这张卡，想自己适配，欢迎提 PR：

- **完整流程：** [`.claude/skills/add-wifi-card/SKILL.md`](../.claude/skills/add-wifi-card/SKILL.md)。它是写给 AI 编程助手的 skill（Claude Code 打开这个仓库会自动识别），人直接读也能当教程用。内容包括：识别网卡、radio 驱动程序、服务、寄存器代理、安装程序和固件锁定、同时连 Wi-Fi 模式、验证方法，以及 PR 需要附带的东西。它是从 AX210 系列、RTL8852CE、MT7902、MT7922/MT7921 和 BE200 的实际适配过程中整理出来的。
- **架构说明：** [docs/ADDING-A-CARD.md](ADDING-A-CARD.md)。
- **PR 需要附上真机运行的诊断报告：** 双向 AirDrop，并写明速度。只编译通过的代码会作为实验性支持发布。
