# 使用指南

[English](USAGE.md) · 简体中文 · [返回 README](../README.zh-CN.md)

## 功能

- **接收 iPhone、iPad、Mac 发来的文件**：电脑会像苹果设备一样出现在 AirDrop 列表里。文件存到你指定的文件夹（默认 `下载\nekodrop`），每次传输都可以在通知里选择接受或拒绝。
- **发送到苹果设备**：在资源管理器里右键文件，选 **用 nekodrop 发送**（Windows 11 第一级菜单、经典菜单和“发送到”里都有），再选附近的设备。
- **AirDrop 时照常上网**：在“同时联网和 AirDrop”模式下，nekodrop 自己驱动网卡，一个虚拟接口连你的 Wi-Fi，另一个跑 AWDL（苹果无线直连协议）。Windows 里上网走一块名叫 **nekodrop** 的“有线网卡”。
- **完整的 Wi-Fi 管理**：扫描、连接、隐藏网络、已保存网络和自动连接。会导入 Windows 里已保存的 Wi-Fi，还能识别酒店、机场、校园网这类需要网页登录的网络，并自动在浏览器里打开登录页。
- **自动恢复**：后台服务盯着 radio、AWDL 守护进程和 AirDrop 引擎，哪个停了就重启哪个。开机自动启动。
- **托盘旁的小面板**：中英双语，浅色 / 深色。点托盘图标或按快捷键（默认 Win+Shift+D，可以录入自己的组合键）从右下角弹出，点别处自动收起。附近设备显示在雷达（或列表）上，动效用 Windows 原生 Fluent 曲线：发送与接收时送出蓝色波纹、进度环匀速走满并显示实时传输速率（`MB/s` / `KB/s`，可在设置里开关），完成后变绿打勾。
- **点 AirDrop 标志切换谁能发给你**：点左上角的标志，选 **接收关闭**、**仅限联系人** 或 **所有人**，和 iPhone 一样。支持三档自动同意接收（关闭 / 仅限联系人 / 全部）、媒体格式偏好（兼容 JPEG/H.264 或原始 HEIC/HEVC 及可选自动转存 JPG 副本）、系统通知大图预览与一键复制，以及发完大文件后自动 BLE 重脉冲唤醒 iPhone。
- **仅限联系人（实验性）**：在电脑上登录 Apple ID（支持 `-27952` 与 2FA 503 自动重试，以及一键导出脱敏登录日志），或导入 Mac 的 AirDrop 证书，电脑就会像你的 Mac 一样出现在你自己的 iPhone 上，开了「仅限联系人」的 iPhone 也能用。见下方「仅限联系人」一节。
- **Windows「共享」菜单**：资源管理器和其他应用的分享面板里可以直接选 nekodrop。

## 界面截图

一个从托盘旁边弹出的小面板（点托盘图标或按快捷键打开，点别处自动收起）：附近的 iPhone 和 Mac 显示在雷达上（也可以切换成列表），左上角的 AirDrop 标志可以切换谁能发给你，标题栏里有状态和快捷开关，设置分五个标签页，主题色只有一种、可以切换（也可以选多彩），支持浅色和深色。接收文件时「本机」外圈转动显示进度，保存完成后变绿打勾。全局快捷键默认 Win+Shift+D，可以在设置里录入自己的组合键。

<table>
  <tr>
    <td align="center"><img src="screenshots/main-radar.png" width="280" alt="主窗口：雷达"><br><sub>雷达：待接受的请求、发送中、已发送、被拒绝</sub></td>
    <td align="center"><img src="screenshots/main-list-dark.png" width="280" alt="主窗口：列表（深色）"><br><sub>列表（深色）</sub></td>
    <td align="center"><img src="screenshots/send.png" width="230" alt="发送窗口"><br><sub>文件右键 →「用 nekodrop 发送」</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/settings.png" width="280" alt="设置"><br><sub>设置：主题色、自定义快捷键</sub></td>
    <td align="center"><img src="screenshots/settings-appleid.png" width="280" alt="设置：Apple ID"><br><sub>Apple ID 与仅限联系人（实验性）</sub></td>
    <td align="center"><img src="screenshots/wifi.png" width="250" alt="Wi-Fi 窗口"><br><sub>nekodrop 自己的 Wi-Fi</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/tray.png" width="260" alt="托盘菜单"><br><sub>托盘菜单</sub></td>
    <td align="center" colspan="2"><img src="screenshots/motion-send.png" width="560" alt="发送动画逐帧"><br><sub>发送动画逐帧：进度环走满、变绿、画出对号</sub></td>
  </tr>
</table>

## 安装

1. 从 [Releases](../../../releases) 下载 `nekodrop-<版本>-setup.exe` 并运行。
2. 安装程序会：
   - 把文件复制到 `C:\Program Files\nekodrop`；
   - **在你的电脑上**生成一个代码签名证书，用它给小小的寄存器代理驱动签名并信任它，然后**删除私钥**，这个证书以后再也签不了别的东西；
   - 创建名为 **nekodrop** 的 TAP 虚拟网卡（TAP-Windows，OpenVPN 签名）；
   - 添加两条只允许链路本地地址的入站防火墙规则（`TCP 8771-8779, 18771-18779, 28771-28779` 以避开 Hyper-V 保留端口段、`UDP 5353`）；
   - 安装并启动 **NekoDropService** 服务。
3. 托盘里会出现紫色小猫图标。打开它，确认 **允许接收** 已勾选。

第一次启动时，nekodrop 会从 Intel 驱动手里接管网卡，并自动连回 Windows 原来连着的网络。之后 Windows 自带的 Wi-Fi 图标会消失，改用 nekodrop 托盘菜单里的 **Wi-Fi…** 窗口管理网络。

### 更新

本分支**没有自动更新**：nekodrop 不会去 GitHub 检查新版本，也不会自己替换安装包。*设置 → 关于* 会显示当前版本并说明这一点；要换新版本时，直接运行新安装包覆盖安装即可，设置和已接收的文件都会保留。这是有意为之——本分支额外支持 USB 无线网卡，而自动更新到上游版本会让这份支持消失。

### 卸载

在 *设置 → 应用 → nekodrop → 卸载*，或者运行安装目录里的 `uninstall.ps1`。卸载时会先把网卡还给 Intel 驱动，再删除服务、驱动包、证书信任和防火墙规则。

## 使用

| 想做什么 | 怎么做 |
|---|---|
| 接收 | 保持接收开启（左上角 AirDrop 标志是彩色、不是灰色）。在 iPhone 上点 分享 → AirDrop，选你电脑的名字 |
| 选谁能发给我 | 点 AirDrop 标志：**接收关闭**、**仅限联系人**（实验性，设置 → Apple ID）或 **所有人** |
| 发送 | 右键文件 → **用 nekodrop 发送** → 选设备；也可以在资源管理器里选中文件后按快捷键（默认 Win+Shift+D） |
| 换 Wi-Fi | 托盘 → **Wi-Fi…**，选网络、输入密码、点连接 |
| 连隐藏网络 | **Wi-Fi…** → *隐藏网络*，输入网络名和密码 |
| 酒店 Wi-Fi 登录 | 直接连接，登录页会自动在浏览器里打开 |
| 把网卡还给 Windows | 托盘 → *联网方式* → **按需接管网卡** 或 **关闭 AirDrop** |
| 改设备名、保存位置、语言 | 托盘 → **设置…** |
| 改快捷键 | 设置 → 常规：点一下快捷键，按下新的组合键 |

### 联网方式

| 模式 | 上网 | AirDrop |
|---|---|---|
| **同时联网和 AirDrop**（默认） | 走 nekodrop 自己的 Wi-Fi 连接（“nekodrop”网卡） | 一直可用 |
| **按需接管网卡** | 正常的 Intel 驱动 | 附近 iPhone 打开 AirDrop 或你发送文件时才接管网卡，传输期间会断网 |
| **关闭 AirDrop** | 正常的 Intel 驱动 | 关闭 |

### 支持的 Wi-Fi 加密

| 网络类型 | 同时模式下 |
|---|---|
| 开放网络 | ✅ |
| WPA/WPA2 个人版 | ✅ |
| WPA2/WPA3 混合 | ✅（用 WPA2 连接） |
| 要求管理帧保护的 WPA2、WPA2-PSK-SHA256 | 🧪 0.1.12，未实机测试 |
| 需要网页登录的网络 | ✅ 自动识别并打开登录页 |
| 隐藏网络 | ✅ |
| 纯 WPA3 个人版（SAE） | 🧪 0.1.12，未实机测试（只接受 hash-to-element 的网络暂不支持，多见于 6 GHz） |
| 增强型开放（OWE） | 🧪 0.1.12，未实机测试 |
| WPA2/WPA3 企业版（802.1X、PEAP 等） | ❌ 暂不支持，会自动改用“按需”模式 |
| WEP、WPA/TKIP | ❌（不安全，不计划支持） |

### 仅限联系人（Apple ID，实验性）

设置 →「Apple ID」里先打开顶部的实验性开关，再选择谁可以给这台电脑发送：「所有人」或「仅限联系人」。「仅限联系人」需要一个和 Mac 一样的 AirDrop 身份，有两种方式获得：

- **用 Apple ID 登录**：nekodrop 像 Mac 一样向 Apple 申请 AirDrop 证书（WirDrop 的 `appleid`，MIT），自动续期并读取 iCloud 通讯录。第一次登录会从 Apple 下载 iCloud for Windows 的一个组件（约 160 MB，不安装 iCloud）。密码只用一次、不保存。
- **从 Mac 导入**：在登录了你 Apple ID 的 Mac 上用 [airdrop-keychain-extractor](https://github.com/seemoo-lab/airdrop-keychain-extractor) 导出 `certificate.pem`、`key.pem`、`validation_record.cms`（需要临时部分关闭 SIP），在设置里选中它们所在的文件夹，再导入一个 `.vcf` 通讯录。

有了身份，你自己的 iPhone 会像对待你的 Mac 一样列出这台电脑；对方 iPhone 开「仅限联系人」时，只要它的通讯录里有你 Apple ID 的邮箱或手机号，也能看到这台电脑。接收端的「仅限联系人」过滤只读对方的确认记录、不校验 Apple 签名，只是过滤，不是身份证明。维护者已在 2.1.0 上真机确认可用。

### 实验性功能

在 *设置 → 网卡与高级 → 实验性功能* 里，默认都关闭；关掉后行为和原来完全一样。（已经转正、始终打开的：聚合发送 A-MPDU，0.1.35 起；Intel 网卡的蓝牙与 Wi-Fi 均衡共存，0.1.37 起，让蓝牙信标发得出去，电脑几秒内就能找到 iPhone 和 Mac，感谢 [@XXD051030](https://github.com/XXD051030)，[#26](../../../pull/26)。）

- **高吞吐模式（Wi-Fi 6 HE80 + MTU 1500）**（参考 [`YiHoooong/owly`](https://github.com/YiHoooong/owly/tree/feat/windows-mtkradio)）：在 5 GHz 80 MHz 下广播 Apple AWDL Wi-Fi 6（HE80）能力并将 `awdl0` MTU 提至 `1500`。配合 4+4 MiB 无锁共享内存数据面、8 KiB 接收 DMA、8 MiB Wintun 环、`ev_win.c` 公平轮询与流式接收，AX201 实测双向均可达到 **50+ MiB/s（约 53 MB/s）**。
- **Wi-Fi 和 AirDrop 不在同一信道时按苹果的方式分时**：告诉 iPhone 电脑什么时候在路由器那边。nekodrop 连的 Wi-Fi 在另一个 5 GHz 信道时，一台 AX211 不开它一个 AirDrop 帧都收不到（[#35](../../../issues/35)）；一台 AX200 上速度时快时慢（[#4](../../../issues/4)）。
- **更快解锁被动 5 GHz 信道**：更早扫描，让拒绝国家码的网卡更快可以发射（[#11](../../../issues/11)）。
- **待机 BLE 广播（`NEKODROP_BLE_STANDBY=1`）**：可选环境变量开关（[#69](../../../pull/69)，默认关闭），开启后可在接收待命时维持低占空比 BLE AirDrop 广播。
