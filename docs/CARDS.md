# Supported cards and adding new ones

English · [简体中文](CARDS.zh-CN.md) · [Back to README](../README.md)

## Supported hardware

nekodrop talks to the Wi-Fi chip directly through modular backends (`CardCatalog` + `radio_backend.h`), one user-mode radio per card family:

- **Intel** 22000 / AX210 families and the experimental **BE200** (`nekodrop-radio.exe`, ported from [ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm)'s `hal_iwx`): Concurrent or on demand.
- **Realtek RTL8852CE** (`nekodrop-radio-rtl.exe`, built from [winawdl](https://github.com/raph559/winawdl)/[devourer](https://github.com/raph559/devourer)): on demand.
- **Realtek RTL8821CU USB dongle** (`nekodrop-radio-usb.exe`, the same winawdl radio over devourer's libusb transport): always on (started with the service), experimental. **This fork only** — upstream nekodrop supports PCIe cards and has no USB path.
- **MediaTek MT7902** (`nekodrop-radio-mt.exe`) and **MT7921 / MT7922** (`nekodrop-radio-mtk.exe`), user-mode ports of Linux mt76: Concurrent (5 GHz) or on demand.

The table says which have been tested on real hardware. Cards outside it: see [Supporting a new card](#supporting-a-new-card).

**Full multi-vendor compatibility matrix (Intel / Realtek / MediaTek / Qualcomm): [docs/COMPATIBILITY.md](COMPATIBILITY.md)** · **Release history: [CHANGELOG.md](../CHANGELOG.md)** · **Driver architecture: [docs/HARDWARE.md](HARDWARE.md)**

Quick summary of currently active cards:

| Card | PCI IDs | Firmware / Backend | Status |
|---|---|---|---|
| **Intel Wi-Fi 6 AX201** 160 MHz (CNVi) | `8086:` `02F0` `06F0` `34F0` `3DF0` `4DF0` `43F0` `A0F0` | `Qu/QuZ-hr-b0-68` (`iwx`, Concurrent & On-Demand) | ✅ **tested** (QuZ on `43F0`) |
| Intel Wireless-AC 9560 / 9462 / 9461 on Qu/QuZ (CNVi) | same IDs as AX201 | `Qu/QuZ-jf-b0-68` (`iwx`, Concurrent & On-Demand) | ✅ works in a user report (9560, [#45](../../../issues/45)) |
| Intel Wi-Fi 6 AX200 (discrete) | `8086:2723` | `cc-a0-68` (`iwx`, Concurrent & On-Demand) | ✅ two-way AirDrop in user reports ([#1](../../../issues/1), [#4](../../../issues/4)); 9–25 MiB/s to an iPhone with A-MPDU ([#4](../../../issues/4)) |
| Intel Wi-Fi 6E AX210 (discrete) | `8086:2725` | `ty-a0-gf-a0-68` + PNVM (`iwx`, Concurrent & On-Demand) | ✅ two-way AirDrop in user reports ([#14](../../../issues/14), [#18](../../../issues/18), [#11](../../../issues/11)) |
| Intel Wi-Fi 6E AX211 (CNVi, 12th gen+) | `8086:` `7AF0` `7A70` `51F0` `51F1` `54F0` `7F70` | `so-a0-gf-a0-68` + PNVM (`iwx`, Concurrent & On-Demand) | ✅ two-way AirDrop in user reports ([#9](../../../issues/9), [#29](../../../issues/29)); iPhones list the PC since 0.1.31 ([#24](../../../issues/24)) |
| Intel Wi-Fi 6E AX411 / Killer AX1690 (CNVi) | same IDs as AX211 | `so-a0-gf4-a0-68` + PNVM (`iwx`, Concurrent & On-Demand) | ✅ works in a user report ([#37](../../../issues/37)) |
| Intel Wi-Fi 6 AX203 / 9560 on So | same IDs as AX211 | `so-a0-hr/jf-b0-68` (`iwx`, Concurrent & On-Demand) | ⚠️ untested |
| **Realtek RTL8852CE** | `10EC:C852` | embedded (`devourer`, On-Demand only) | ✅ built in; two-way AirDrop confirmed in user reports up to **~24.5 MB/s** ([#61](../../../issues/61)) |
| **Realtek RTL8821CU** (USB) | `0BDA:C820` `0BDA:C821` | embedded (`devourer` over libusb, always on) | 🧪 **fork only**, experimental: WinUSB on the dongle's `MI_02`, iPhone → PC AirDrop verified (149 / 20 MHz, 14.2 MB Live Photo bundle at 339 KB/s); PC → iPhone untested ([RTL8821CU.md](RTL8821CU.md)) |
| Intel SnJ `2726`, QnJ `2720`, Meteor Lake `7E40`/`2729` | `8086:` | not shipped upstream | ❌ |
| **Intel Wi-Fi 7 BE200** (discrete) | `8086:272B` | linux-firmware `gl-c0-fm-c0-100` (`iwx` Bz/MLD path, Concurrent & On-Demand) | 🧪 experimental, built in; bring-up hardening + dual-LMAC diagnostics in `v2.2.9` ([#53](../../../issues/53), [docs/BE200.md](BE200.md)) |
| Intel BE201 / BE211 (Wi-Fi 7, CNVi) | `8086:` `A840` `7740` | needs CNVi hardware | ❌ |
| **MediaTek MT7902** | `14C3:7902` | linux-firmware `WIFI_RAM_CODE_MT7902_1` (`mt76` port, Concurrent (5 GHz Wi-Fi) & On-Demand) | ✅ built in; AirDrop both ways (~15 MB/s receive, ~5 MB/s send) and Concurrent tested on hardware ([#34](../../../pull/34), [#47](../../../pull/47)) |
| **MediaTek MT7922 / AMD RZ616** | `14C3:0616` `14C3:7922` | linux-firmware `WIFI_RAM_CODE_MT7922_1` (`mtkradio`, Concurrent (5 GHz Wi-Fi, experimental) & On-Demand) | 🧪 experimental, built in; two-way AirDrop tested ([#40](../../../pull/40), [docs/MT7922.md](MT7922.md)); HE80 2SS LWTBL, scan `FIF_BIT_CLR`, firmware RA & RX A-MSDU fixes in `v2.2.8`–`v2.2.9` ([#65](../../../pull/65), [#66](../../../issues/66)) |
| **MediaTek MT7921 / AMD RZ608** | `14C3:7961` `14C3:0608` | linux-firmware `WIFI_RAM_CODE_MT7961_1` (`mtkradio`, Concurrent (5 GHz Wi-Fi, experimental) & On-Demand) | ⚠️ experimental, built in; untested on hardware (On-Demand and Concurrent) |
| Other Realtek, MediaTek, Qualcomm, Broadcom | | | ❌ |

To check your card: *Device Manager → Network adapters*. On a PC without a supported Wi-Fi card, the installer refuses and lists each detected wireless card, its PCI/USB ID, why nekodrop does not run on it, and how to run `installer/report.ps1`. On an untested card (including the built-in Realtek RTL8852CE backend), nekodrop may fail to start the radio; if it does, the card stays usable: run **restore** ([One-click restore](SUPPORT.md)) and please report the log in an [issue](../../../issues).

Cards are recognized by their PCI ID. When yours is not, *Settings > Wi-Fi card* lets you pick the card and its model by hand (for hardware IDs the driver package lists). To add a new card family to nekodrop, see [docs/ADDING-A-CARD.md](ADDING-A-CARD.md).

Not sure which card you have, or want another card supported? The [diagnostic report](SUPPORT.md#reporting-a-problem-the-diagnostic-report) works without nekodrop installed: download [`installer/report.ps1`](../installer/report.ps1) and run `powershell -ExecutionPolicy Bypass -File report.ps1`. It lists every wireless card with its PCI ID, chip, driver and why nekodrop does or does not run on it; please post it in an [issue](../../../issues). On an installed nekodrop, `NekoDropService.exe --status` prints the matched card profile, capabilities and bound driver provider, and `NekoDropService.exe --selftest` runs offline catalog and radio-launch checks across all 22 active profiles without a card or administrator rights. Intel's radio logs one `backend …` line at start and runs `iwx_selftest` on every build; the Realtek radio build runs its own offline unit tests (`block_ack_test`, `reorder_buffer_test`, `outgoing_session_test`, `dma_address_test`) on every build; `install.ps1 -SelfTest`, `restore.ps1 -SelfTest` and `report.ps1 -SelfTest` likewise run offline under Windows PowerShell 5.1 on every build. What other cards would take: [docs/HARDWARE.md](HARDWARE.md).

## Supporting a new card

nekodrop supports the cards in the table above and nothing else. **Requests to support another card, without code, are closed** with a pointer here. We can only add a card that we have, or that someone ports and tests on real hardware. New laptop Wi-Fi (Intel Wi-Fi 7 CNVi such as BE201/BE211, Panther Lake `8086:E440`, which Windows calls "AX211", Qualcomm, Broadcom) needs a new driver port, not a new ID.

If you have the card and want to port it, pull requests are welcome:

- **The process, step by step:** [`.claude/skills/add-wifi-card/SKILL.md`](../.claude/skills/add-wifi-card/SKILL.md). It is written as a skill for AI coding agents (Claude Code picks it up from this repository on its own), and reads fine as a guide for people. It covers identifying the card, the radio daemon, the service, the register proxy, installer and firmware pinning, Concurrent mode, verification and what a PR needs. It was distilled from the AX210-family, RTL8852CE, MT7902, MT7922/MT7921 and BE200 ports.
- **The architecture:** [docs/ADDING-A-CARD.md](ADDING-A-CARD.md).
- **A PR needs a diagnostic report from a real run:** AirDrop both ways, with speeds. Code that only compiles ships as experimental.
