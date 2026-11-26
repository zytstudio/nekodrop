# 无线网卡兼容性列表

[English](COMPATIBILITY.md) · 简体中文 · [返回 README](../README.zh-CN.md) · [底层架构与多网卡路线（英文）](HARDWARE.md)

nekodrop 在用户态直接驱动无线网卡芯片，使 Windows 原生运行苹果 AWDL 协议。随着项目从 Intel 扩展至跨品牌多网卡支持，所有网卡族均通过模块化 `CardCatalog` 与 `radio_backend.h` 契约接入：

- **底层原生自带（不做默认关闭的实验开关）**：任一品牌网卡的真实后端一旦通过 CI 编译与离线自检，即内置原生启用，用户装上即可使用。
- **自动识别优先，不行再手动选择**：默认自动识别本机 PCIe 无线网卡；针对多无线网卡或未收录同族 PCI ID 的安装期弹窗手选与设置页切换正在逐步落地。
- **诚实标注验证状态**：严格区分 **作者实机已测**、**用户实机反馈可用**、**已内置待实测** 与 **开发中 / 规划中**。

## 能力与联网模式对照

| 联网模式 | 说明 | 所需底层能力 |
|---|---|---|
| **同时连 Wi-Fi（Concurrent）** | nekodrop 用同一块网卡同时跑 Wi-Fi 上网和 AWDL 隔空投送。 | 后端自带用户态 Wi-Fi 站点（`supports_station = true`）。 |
| **按需接管（On-Demand）** | 平时由 Windows 原厂驱动满速上网；仅在收发 AirDrop 时临时接管网卡，传完自动交还。 | 仅需基础 AWDL 监听/发包能力（无用户态 Wi-Fi 站点的网卡自动使用该模式）。 |

---

## Intel（`VEN_8086`）— `iwx` 后端

| 网卡 / 系列 | PCI Device ID | 固件 | 支持模式 | 状态 |
|---|---|---|---|---|
| **Intel Wi-Fi 6 AX201** 160 MHz（CNVi） | `02F0` `06F0` `34F0` `3DF0` `4DF0` `43F0` `A0F0` | `Qu/QuZ-hr-b0-68` | 同时连 Wi-Fi / 按需 | ✅ **作者实机已测**（`43F0` QuZ） |
| **Intel Wi-Fi 6 AX200**（独立网卡） | `2723` | `cc-a0-68` | 同时连 Wi-Fi / 按需 | ✅ **用户反馈双向可用**（[#1](../../../issues/1)、[#4](../../../issues/4)） |
| **Intel Wi-Fi 6E AX210**（独立网卡） | `2725` | `ty-a0-gf-a0-68` + PNVM | 同时连 Wi-Fi / 按需 | ✅ **用户反馈双向可用**（[#14](../../../issues/14)、[#18](../../../issues/18)、[#11](../../../issues/11)） |
| **Intel Wi-Fi 6E AX211**（CNVi，12 代+） | `7AF0` `7A70` `51F0` `51F1` `54F0` `7F70` | `so-a0-gf-a0-68` + PNVM | 同时连 Wi-Fi / 按需 | ✅ **用户反馈双向可用**（[#9](../../../issues/9)）；部分机型发现调优中（[#16](../../../issues/16)） |
| Intel Wireless-AC 9560 / 9462 / 9461（Qu/QuZ CNVi） | 同 AX201 | `Qu/QuZ-jf-b0-68` | 同时连 Wi-Fi / 按需 | ⚠️ 已内置，待实测 |
| Intel Wi-Fi 6E AX411 / Killer AX1690（CNVi） | 同 AX211 | `so-a0-gf4-a0-68` + PNVM | 同时连 Wi-Fi / 按需 | ⚠️ 已内置，待实测（[#7](../../../issues/7)） |
| Intel Wi-Fi 6 AX203 / 9560（So CNVi） | 同 AX211 | `so-a0-hr/jf-b0-68` | 同时连 Wi-Fi / 按需 | ⚠️ 已内置，待实测 |
| Intel Meteor Lake `Ma` / `SnJ` | `7E40` `2729` `2726` | `ma-b0`（`linux-firmware`） | 同时连 Wi-Fi / 按需 | 🚧 规划中（高优先级） |
| **Intel Wi-Fi 7 BE200**（`bz`/`gl` 族） | `272B` | API 100，MLD | 同时连 Wi-Fi / 按需 | 🧪 **已内置，实验性，还没在真机上跑过**（[BE200.md](BE200.md)）；BE201/BE211 CNVi（`A840` `7740` `E440`）需要 CNVi 硬件 |
| 老款 Intel 9260（`2526`）/ 8–9 代 9560（`9DF0`/`A370`） | `2526` `9DF0` `A370` | `iwm` 旧式 FH DMA | — | ❌ 暂不支持（上游 `hal_iwm` 无 AWDL 支持） |

---

## Realtek（`VEN_10EC` PCIe、`VID_0BDA` USB）— `devourer` 后端

| 网卡 / 系列 | Device ID | 支持模式 | 状态 |
|---|---|---|---|
| **Realtek RTL8852CE** | `10EC:C852` | 按需接管（原厂驱动照常连 Wi-Fi） | ⚠️ **已内置待实测**（原生内置 `nekodrop-radio-rtl.exe`，基于 [winawdl](https://github.com/raph559/winawdl)/`devourer` 完整 A-MPDU 后端；CI 已编译并通过离线单测，待在 nekodrop 内真机验证；Intel 默认行为 100% 不变） |
| **Realtek RTL8821CU**（USB 网卡） | `0BDA:C820` `0BDA:C821` | 常驻（网卡会一直归 nekodrop 的 WinUSB 驱动） | 🧪 **仅本分支，实验性**：WinUSB 绑到网卡 `MI_02`；已验证 iPhone → PC 隔空投送（149 / 20 MHz）；PC → iPhone 未测（[RTL8821CU.md](RTL8821CU.md)） |
| **Realtek RTL8852BE / RTL8851BE** | `10EC:B852` `B85B` `B851` | 按需接管 | 🚧 紧随 RTL8852CE 之后接入（基于 `OpenIPC/devourer` `KESTREL_8852B`） |
| Realtek RTL8852AE / RTL8922AE | `10EC:8852` `8922` | 按需接管 | 🗓️ 规划中 |
| Realtek RTL8821CE / RTL8822CE / RTL8822BE、其他 Realtek USB 网卡 | `10EC:*`、`0BDA:*` | — | ❌ 不支持 |

RTL8821CU 这一行是**本下游分支**新增的：上游 nekodrop 只提供 PCIe 网卡（有寄存器 BAR
可供驱动代理）。USB 网卡没有 BAR，所以需要本分支里的 libusb 传输。

---

## MediaTek（`VEN_14C3`）— `mt76`（`nekodrop-radio-mt.exe`）与 `mtkradio`（`nekodrop-radio-mtk.exe`）

| 网卡 / 系列 | PCI Device ID | 支持模式 | 状态 |
|---|---|---|---|
| **MediaTek MT7902** | `7902` | 同时连 Wi-Fi（仅 5 GHz）与按需接管 | ⚠️ 用户态 mt76/mt7921 移植（`mtradio/`）。一张卡上双向 AirDrop 实测可用（华硕台式机，`SUBSYS_60401A3B`）：双向 A-MPDU，接收约 15 MB/s，发送约 5 MB/s。同时连 Wi-Fi：固件同一时间只有一个信道，radio 在路由器和 AWDL 之间分时切换（约 3/4 时间在路由器上，AirDrop 传数据时减少；固件选速率并接收路由器的 A-MPDU，实测下载约 3.5 MB/s、上传约 1.3 MB/s，CCMP 在主机侧完成）。2.4 GHz 上需要 ACK 的帧发不出去，因此 Wi-Fi 只连 5 GHz。需要 linux-firmware 的 `WIFI_*_MT7902*`（Windows 驱动自带的那份不认 UNI 命令） |
| **MediaTek MT7922 / RZ616** | `7922` `0616` | 同时连 Wi-Fi（仅 5 GHz，实验性）与按需接管 | 🧪 **已内置，实验性**（`mtkradio/`，`nekodrop-radio-mtk.exe`）。已在 MT7922 / AMD RZ616（`14C3:0616`）上实测双向 AirDrop 可用（[#40](../../../pull/40)，[MT7922.md](MT7922.md)）。同时连 Wi-Fi（主机侧 CCMP、路由器与 AWDL 单信道分时切换、AP STA 记录与主机侧 RX BA 重排）**尚未在真机上测试**，目前限于 5 GHz。需要 linux-firmware 的 `WIFI_*_MT7922*` |
| **MediaTek MT7921 / RZ608** | `7961` `0608` | 同时连 Wi-Fi（仅 5 GHz，实验性）与按需接管 | ⚠️ **已内置，实验性，尚未在真机上测试**（`mtkradio/`，`nekodrop-radio-mtk.exe`；与 MT7922 共享 Connac2 WFDMA 与并发站点路径）。需要 linux-firmware 的 `WIFI_*_MT7961*` |
| MediaTek MT7925 | `7925` | 按需接管 | 🗓️ 规划中 |

---

## 高通 Qualcomm（`VEN_17CB`）与博通 Broadcom（`VEN_14E4`）

| 厂商 / 系列 | 状态 | 说明 |
|---|---|---|
| Qualcomm WCN6855 / QCNFA765 / WCN7850（`ath11k`/`ath12k`） | ❌ 当前用户态暂不可行 | 需完整 MHI + QMI + 数十 MB 物理连续 MSA 内存与 36-bit DMA 约束。 |
| Broadcom BCM43xx | ❌ 不支持 | 苹果博通卡的 AWDL 位于闭源专有固件内，无开源实现路径。 |

---

## 如何查看自己的网卡型号

不用安装 nekodrop，直接下载并运行诊断脚本即可查看完整 PCI ID、芯片与兼容结论：

```powershell
powershell -ExecutionPolicy Bypass -File installer\report.ps1
```

如果你的网卡尚未支持，欢迎把脱敏后的报告贴到 [Issues](../../../issues) 帮助排期。
