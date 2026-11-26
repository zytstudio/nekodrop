<p align="center">
  <img src="app/assets/nekodrop.png" width="128" alt="nekodrop">
</p>

<h1 align="center">nekodrop</h1>

<p align="center">
  <b>用 Windows 上的无线网卡原生收发 AirDrop，Wi-Fi 照常上网。</b><br>
  不需要 Linux 虚拟机，也不需要 Mac —— PCIe 网卡 Wi-Fi 照常在线，USB 网卡是本分支新增的支持。
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文 · <a href="../../releases/latest">下载</a> · <a href="docs/COMPATIBILITY.zh-CN.md">网卡兼容性</a> · <a href="CHANGELOG.md">更新日志</a>
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011%20x64-0078d4">
  <img alt="speed" src="docs/badges/speed.zh-CN.svg">
  <img alt="card" src="docs/badges/card.svg">
  <img alt="license" src="https://img.shields.io/badge/license-GPL--2.0-blue">
</p>

<p align="center">
  <img src="docs/demo.gif" width="760" alt="实机拍摄：iPhone 与 Windows 11 用自带 Intel AX201 网卡双向收发原生 AirDrop，同时保持 Wi-Fi 在线">
  <br>
  <sub>实机拍摄：未装任何 App 的 iPhone ↔ Windows 11，自带 Intel AX201，全程 Wi-Fi 在线。</sub>
</p>

> ### 下游分支：支持 USB 无线网卡
>
> 本仓库是 [zheznanohana/nekodrop](https://github.com/zheznanohana/nekodrop) 的下游分支，
> 新增了 **USB 无线网卡**支持（目前是 Realtek RTL8821CU）。上游只面向 PCIe 网卡
> —— PCIe 网卡有寄存器 BAR，可以用系统自带驱动做代理；USB 网卡没有 —— 也不打算接收
> USB 支持，所以 USB 相关的问题和 PR 请提到**本仓库**，不要提到上游。其余内容跟随上游，
> PCIe 网卡的表现与上游 README 完全一致。范围、验证记录与同步上游的方法见
> [docs/DOWNSTREAM.md](docs/DOWNSTREAM.md)。

## 亮点

- **双向 53 MB/s**：Intel AX201 上 846 MB 文件约 16 秒传完，0 丢包（[详细数据](#速度)）。
- **AirDrop 时照常上网**：一张网卡同时连 Wi-Fi 和跑 AirDrop。
- **用你现有的网卡**：Intel AX200 / AX201 / AX210 / AX211 / 9560、Realtek RTL8852CE 或 RTL8821CU USB 网卡、MediaTek MT7902 / MT7921 / MT7922，PCIe 网卡无需额外购买 USB 网卡（[全部网卡](#支持的网卡)）。
- **像 Mac 一样用**：iPhone、iPad、Mac 的 AirDrop 列表里直接出现你的电脑；资源管理器右键 **用 nekodrop 发送**，或用 Windows 分享面板。
- **仅限联系人**（实验性）：登录 Apple ID 或导入 Mac 证书（[怎么用](docs/USAGE.zh-CN.md#仅限联系人apple-id实验性)）。
- **装上就不用管**：一个安装包、自动更新、服务自动恢复，出问题一键回退到 Windows 自带 Wi-Fi。

## 速度

Intel AX201、Windows 11、`v2.2.9+`，开启高吞吐模式（HE80 + MTU 1500）实测：

| 方向 | 速度 | 测试 |
|---|---|---|
| 电脑 → iPhone | **53.00 MB/s**（50.55 MiB/s） | 846 MB 用 15.97 秒，Block Ack 确认率 99.85%，0 丢包 |
| iPhone → 电脑 | 净传输 **53.28 MB/s**（50.81 MiB/s）· 端到端 49.66 MB/s | 846 MB 净收 15.84 秒 / 总计 17.00 秒，0 丢包 |

测试方法：[docs/TESTING.md](docs/TESTING.md)。

## 支持的网卡

| 厂商 | 型号 | 状态 |
|---|---|---|
| **Intel** | AX201 · AX200 · AX210 · AX211 · AX411 / Killer AX1690 · 9560 | 实测可用（AX201 作者实测，其余为用户反馈） |
| **Intel** | BE200（Wi-Fi 7） | 实验性 |
| **Realtek** | RTL8852CE | 用户实测，约 24.5 MB/s（按需接管） |
| **Realtek** | RTL8821CU USB 网卡（`0BDA:C820`/`C821`） | **本分支新增**，实验性：已验证 iPhone → PC 隔空投送（149 信道 / 20 MHz）；网卡会一直归 nekodrop 驱动 |
| **MediaTek** | MT7902 | 双向实测，可同时连 Wi-Fi |
| **MediaTek** | MT7922 / RZ616 · MT7921 / RZ608 | 实验性（MT7922 双向实测） |

表里没有的就是不支持（高通、博通、Intel BE201/BE211 等）。PCI ID、固件和每张卡的说明：**[网卡兼容性](docs/COMPATIBILITY.zh-CN.md)** · **[网卡状态与适配新网卡](docs/CARDS.zh-CN.md)**。

## 安装

1. Windows 10 2004+ / 11 x64，受支持的网卡，打开蓝牙。
2. 从 **[Releases](../../releases/latest)** 下载 `nekodrop-<版本>-setup.exe` 并运行。
3. 点托盘里的紫色小猫，打开 **允许接收**；iPhone 的隔空投送设为 **所有人（10 分钟）**。

出问题了？开始菜单 → **nekodrop - restore Windows Wi-Fi**，网卡就还给 Windows。更多：[常见问题](docs/SUPPORT.zh-CN.md)。

## 界面截图

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/main-radar.png" width="260" alt="主界面：雷达"><br><sub>雷达上的附近设备</sub></td>
    <td align="center"><img src="docs/screenshots/send.png" width="230" alt="发送窗口"><br><sub>右键 → 用 nekodrop 发送</sub></td>
    <td align="center"><img src="docs/screenshots/wifi.png" width="240" alt="Wi-Fi 窗口"><br><sub>nekodrop 自己的 Wi-Fi</sub></td>
  </tr>
</table>

更多截图和全部功能：[使用指南](docs/USAGE.zh-CN.md)。

## 文档

| | |
|---|---|
| [使用指南](docs/USAGE.zh-CN.md) | 功能、安装细节、联网方式、Wi-Fi 加密、仅限联系人、实验性功能、更新、卸载 |
| [常见问题](docs/SUPPORT.zh-CN.md) | 常见问题、一键回退、诊断报告 |
| [网卡兼容性](docs/COMPATIBILITY.zh-CN.md) · [网卡状态](docs/CARDS.zh-CN.md) | 每张卡的 PCI ID 和固件；怎么适配新网卡 |
| [工作原理](docs/HOW-IT-WORKS.zh-CN.md) | 架构、开发进度、从源码构建 |
| [致谢](docs/CREDITS.zh-CN.md) | 贡献者、代码来源、许可证 |
| [更新日志](CHANGELOG.md) | 版本历史 |

## 贡献者

感谢 [@BaiBaiAi](https://github.com/BaiBaiAi)、[@XXD051030](https://github.com/XXD051030)、[@GGBond-cer](https://github.com/GGBond-cer)、[@DaiJiequn](https://github.com/DaiJiequn)、[@sh17632](https://github.com/sh17632)、[@YiHoooong](https://github.com/YiHoooong)、[@Yanlyn](https://github.com/Yanlyn)，以及所有提交日志的朋友。每个人做了什么：[致谢](docs/CREDITS.zh-CN.md#贡献者)。

欢迎在 [Issues](../../issues) 反馈问题，请附上[诊断报告](docs/SUPPORT.zh-CN.md#反馈问题诊断报告)。社区友链：[LINUX DO](https://linux.do/)。

## 许可

**GPL-2.0**（[LICENSE](LICENSE)）；打包的组件保留各自的许可证（[详情](docs/CREDITS.zh-CN.md#许可)）。

nekodrop 是独立项目，与 Apple、Intel 无关，也未获得其认可。AirDrop、iPhone、iPad、Mac 是 Apple Inc. 的商标；Intel 是 Intel Corporation 的商标。nekodrop 运行时会替换你的 Wi-Fi 驱动。这是实验性软件，按原样提供，不提供任何担保。
