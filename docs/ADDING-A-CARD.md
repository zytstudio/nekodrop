# Adding a Wi-Fi card / 适配新网卡

nekodrop runs AirDrop on a card through three layers. Each has a small
interface, so a new card family touches each layer once and nothing else.

nekodrop 分三层驱动网卡，每层都有一个小接口。适配一个新的网卡家族时，每层各实现一次即可，其余代码不用动。

```
NekoDropService (C#)                     user-mode radio daemon (C++)          kernel
┌──────────────────────────┐   spawn    ┌──────────────────────────┐  IOCTL  ┌────────────────────┐
│ CardCatalog  (which card)│ ─────────▶ │ radio daemon             │ ──────▶ │ driver/regproxy    │
│ IRadioBackend (how start)│            │  speaks winawdl's radio  │         │ (UMDF register     │
│ Card / Supervisor        │            │  pipe to awdld           │         │  proxy, largest BAR)│
└──────────────────────────┘            └──────────────────────────┘         └────────────────────┘
```

Everything above the daemon (awdld, the AirDrop engine, the client) is the
same for every card: the daemon speaks winawdl's radio pipe
(`\\.\pipe\winawdl-radio`, `radio_link.h`) and nothing else.

radio 守护进程之上的部分（awdld、AirDrop 引擎、客户端）对所有网卡都一样：守护进程只需要实现 winawdl 的 radio 管道协议。

The step-by-step process, with the lessons from every port so far, is the skill
[`.claude/skills/add-wifi-card/SKILL.md`](../.claude/skills/add-wifi-card/SKILL.md)
(for AI coding agents, and readable by people).

完整的适配步骤和以往每次适配的经验，整理在 skill
[`.claude/skills/add-wifi-card/SKILL.md`](../.claude/skills/add-wifi-card/SKILL.md) 里（写给 AI 编程助手，人也可以直接读）。

## Today / 现状

| Backend (`RadioBackendKind`) | Daemon | Cards | Station (Wi-Fi beside AirDrop) |
|---|---|---|---|
| `Iwx` | `nekodrop-radio.exe` (`iwxradio/`, ported from ForbiddenItlwm) | Intel 22000 / AX210 families | yes |
| `Devourer` | `nekodrop-radio-rtl.exe` (winawdl `radio/` on raph559/devourer's Windows PCIe backend) | Realtek RTL8852CE | no: runs on demand |
| `Mt76` | `nekodrop-radio-mt.exe` (`mtradio/`, ported from Linux mt76) | MediaTek MT7902 | yes (5 GHz) |
| `MtkRadio` | `nekodrop-radio-mtk.exe` (`mtkradio/`) | MediaTek MT7922 / MT7921 | yes (5 GHz, experimental) |
| `RtlUsb` | `nekodrop-radio-usb.exe` (the same winawdl `radio/` over raph559/devourer's libusb transport) | Realtek RTL8821CU USB dongle | no: runs on demand, keeps the dongle |

## Checklist / 步骤

### 1. A radio daemon / radio 守护进程

Either an existing project that already speaks the radio pipe (winawdl's
radio did, so RTL8852CE needed no C++ in this repo), or a new backend inside
`iwxradio/`:

- implement the device calls and declare what it can do in
  `static constexpr RadioCapabilities kCapabilities` (`iwxradio/src/radio_backend.h`);
  every `supports_*` bit defaults to "cannot";
- `radio::check_backend_contract<Dev>()` (a `static_assert` in `radio_main.cpp`)
  fails the build if a declared capability lacks its calls;
- offline tests go in `iwxradio/tests/` (run by `iwx_selftest` in CI).

Unknown options make winawdl's daemon exit with status 2: the service passes a
backend only what its `IRadioBackend.BuildArgs` returns.

要么复用已经实现 radio 管道协议的现成项目（RTL8852CE 就是直接用 winawdl 的 radio，本仓库没写一行 C++），要么在 `iwxradio/` 里实现一个新后端：实现设备调用，在 `kCapabilities` 里声明能力；`check_backend_contract` 会在编译期检查声明的能力有没有对应的实现。

### 2. The service / 服务

- `app/service/CardCatalog.cs`: add a `RadioBackendKind` value (new daemon only)
  and an `AdapterProfile` per PCI ID with its `AdapterCapabilities`
  (`SupportsConcurrentWifi=false` makes Concurrent run on demand), its vendor's
  driver provider names (to give the card back), and `Active: true`.
- `app/service/RadioBackends.cs`: implement `IRadioBackend` (daemon file name,
  command line from `RadioStart`) and register it in `RadioBackends.All`.
- `CardCatalog.ManualModels`: add the model so users whose card is not
  recognized by its ID can pick it by hand (Settings > Wi-Fi card).
- `CardCatalog.SelfTest()` (`NekoDropService --selftest`, run by the build)
  checks that every profile and model has a registered backend.

在 `CardCatalog.cs` 里给每个 PCI ID 加一条 `AdapterProfile`（能力、厂商驱动名），在 `RadioBackends.cs` 里实现并注册 `IRadioBackend`，再在 `ManualModels` 里加上型号，供自动识别失败的用户手动选择。`--selftest` 会检查每个型号都有对应的后端。

### 3. The register proxy / 寄存器代理驱动

- `driver/regproxy/winawdl_regproxy.inf`: add `PCI\VEN_xxxx&DEV_yyyy`. Generic
  IDs rank below the vendor's driver, so this takes over nothing by itself.
  Windows binds a driver only to an ID its INF lists, so a card picked by hand
  also needs its ID here.
- `regproxy.c` maps the largest memory BAR of at least 8 KiB; raise
  `AdapterCapabilities.MinBarBytes` if the card needs more.

在 INF 里加上硬件 ID（通用 ID 的优先级低于厂商驱动，加上去不会抢任何网卡）。Windows 只会把驱动绑到 INF 里列出的 ID 上，所以手动选择的网卡也必须在这里。

### 4. Installer and diagnostics / 安装器和诊断报告

- `installer/install.ps1`: `$SupportedCardPattern` and `$WifiChips`
  (its `-SelfTest` runs in the build);
- `installer/report.ps1` and `installer/restore.ps1`: the same tables
  (their self-tests fail when they drift apart);
- `installer/install.ps1`, `uninstall.ps1`, `restore.ps1`: the daemon's process
  name in the lists of processes they stop;
- `scripts/build-installer.ps1`: build the daemon into `build\stage\radio\`,
  and copy its licence to `licenses\`.

### 5. Docs / 文档

The card tables in `README.md`, `README.zh-CN.md` and `docs/COMPATIBILITY*.md`.

## Candidates / 候选

From the 2026-11-22 survey. Only a card with a working Windows user-mode
driver ("a wheel") is a one-step addition; the rest are driver ports.

| Card | Status |
|---|---|
| Realtek RTL8852CE `10EC:C852` | done (winawdl + devourer) |
| Realtek RTL8821CU `0BDA:C820`/`C821` (USB) | done, experimental: `usbradio/` over devourer's libusb transport, `driver/winusb/` (WinUSB) instead of the register proxy; bring-up, RX and injection verified, AirDrop pending ([RTL8821CU.md](RTL8821CU.md)) |
| Realtek RTL8852BE `10EC:B852`/`B85B`, RTL8851BE `B851` | devourer has the 8852B HAL (USB); its PCIe power sequence and single-BDRAM table are not ported, and devourer refuses it on PCIe |
| Realtek USB adapters (RTL8812AU/8821AU/8812BU/8812CU/8852BU/8852CU…) | devourer drives them over libusb, but no daemon in this repo speaks their radio yet; the RTL8821CU is done (`usbradio/`, `0BDA:C820`/`C821`) and is the worked example of a USB card: a WinUSB package in `driver/winusb/` instead of the register proxy |
| Intel Meteor Lake `7E40`/`2729`, SnJ `2726` | `cards.h` knows them; needs the `ma`/`SnJ` firmware and API 72–83 command versions |
| MediaTek MT7921/MT7922 `14C3:7961`/`0608`/`7922`/`0616` | no Windows user-mode driver yet: a port of Linux mt76 |
| Intel BE200/BE201 | needs the MLD command set (API 86+) |
| Atheros AR9xxx (ath9k) | no firmware at all (the driver does everything), fully open: Linux `ath9k`, OpenBSD `athn`; old 802.11n cards |
| Qualcomm, Broadcom | not planned (MHI/QMI firmware stack; closed AWDL offload) |

Where the driver to port comes from: the Intel radio is ForbiddenItlwm's,
itself OpenBSD's iwx ported to macOS. No other card family has an open
Hackintosh driver (Broadcom and old Atheros cards there run Apple's own closed
drivers with patches), so the source to port is the Linux/BSD driver, as
itlwm did: `rtw89` (Realtek 8852AE/BE/CE, GPL-2.0 OR BSD-3-Clause),
`mt76` (MediaTek, ISC), `ath9k`/`athn`. A port is a new backend under
`iwxradio/` (or a separate daemon speaking the radio pipe) on the same
register proxy and user-mode DMA.

驱动从哪里移植：Intel 的 radio 来自 ForbiddenItlwm，而它本身是 OpenBSD iwx 驱动的 macOS 移植。其他牌子在黑苹果上都没有开源驱动（Broadcom 和老 Atheros 用的是苹果自己的闭源驱动加补丁），所以要像 itlwm 一样，从 Linux/BSD 驱动移植：`rtw89`（Realtek）、`mt76`（MediaTek）、`ath9k`/`athn`（Atheros）。
