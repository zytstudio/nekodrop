# Wi-Fi Card Compatibility

English · [简体中文](COMPATIBILITY.zh-CN.md) · [Back to README](../README.md) · [Architecture & Driver Roadmap](HARDWARE.md)

nekodrop drives the Wi-Fi chip directly from user mode so Windows can speak Apple's AWDL protocol natively. As nekodrop expands beyond Intel into multi-vendor cards, every card family uses a modular backend behind `CardCatalog` and `radio_backend.h`:

- **Built-in native support (no hidden experimental switches)**: once a card family's backend passes CI build and offline self-tests, it ships built-in so users can install and use it out of the box.
- **Auto-detection first, manual selection fallback**: nekodrop automatically detects supported PCIe Wi-Fi cards; multi-NIC / unmatched-ID manual selection at install time and in Settings is actively being rolled out.
- **Honest verification status**: we distinguish **Author-tested**, **User-reported working**, **Built-in (untested)**, and **In development / Planned**.

## Networking Modes by Capability

| Mode | What it does | Required radio capability |
|---|---|---|
| **Wi-Fi + AirDrop together (Concurrent)** | nekodrop runs both your Wi-Fi connection and AWDL on one card. | Backend includes a user-mode Wi-Fi station (`supports_station = true`). |
| **On-Demand** | Windows' native driver runs Wi-Fi normally; nekodrop takes the card only while sending/receiving AirDrop and hands it right back. | Core AWDL listener/injector only (works for cards without a user-mode Wi-Fi station). |

---

## Intel (`VEN_8086`) — `iwx` backend

| Card / Family | PCI Device IDs | Firmware | Modes | Status |
|---|---|---|---|---|
| **Intel Wi-Fi 6 AX201** 160 MHz (CNVi) | `02F0` `06F0` `34F0` `3DF0` `4DF0` `43F0` `A0F0` | `Qu/QuZ-hr-b0-68` | Concurrent & On-Demand | ✅ **Author-tested** (`43F0` QuZ) |
| **Intel Wi-Fi 6 AX200** (discrete) | `2723` | `cc-a0-68` | Concurrent & On-Demand | ✅ **User-reported working** ([#1](../../../issues/1), [#4](../../../issues/4)) |
| **Intel Wi-Fi 6E AX210** (discrete) | `2725` | `ty-a0-gf-a0-68` + PNVM | Concurrent & On-Demand | ✅ **User-reported working** ([#14](../../../issues/14), [#18](../../../issues/18), [#11](../../../issues/11)) |
| **Intel Wi-Fi 6E AX211** (CNVi, 12th gen+) | `7AF0` `7A70` `51F0` `51F1` `54F0` `7F70` | `so-a0-gf-a0-68` + PNVM | Concurrent & On-Demand | ✅ **User-reported working** ([#9](../../../issues/9)); discovery tuning ([#16](../../../issues/16)) |
| Intel Wireless-AC 9560 / 9462 / 9461 (Qu/QuZ CNVi) | same as AX201 | `Qu/QuZ-jf-b0-68` | Concurrent & On-Demand | ⚠️ Built-in, untested |
| Intel Wi-Fi 6E AX411 / Killer AX1690 (CNVi) | same as AX211 | `so-a0-gf4-a0-68` + PNVM | Concurrent & On-Demand | ⚠️ Built-in, untested ([#7](../../../issues/7)) |
| Intel Wi-Fi 6 AX203 / 9560 (So CNVi) | same as AX211 | `so-a0-hr/jf-b0-68` | Concurrent & On-Demand | ⚠️ Built-in, untested |
| Intel Meteor Lake `Ma` / `SnJ` | `7E40` `2729` `2726` | `ma-b0` (`linux-firmware`) | Concurrent & On-Demand | 🚧 Planned (high priority) |
| **Intel Wi-Fi 7 BE200** (`bz`/`gl`) | `272B` | API 100, MLD | Concurrent & On-Demand | 🧪 **Built-in, experimental, not yet run on a real card** ([BE200.md](BE200.md)); BE201/BE211 CNVi (`A840` `7740` `E440`) need CNVi hardware |
| Legacy Intel 9260 (`2526`) / 8th–9th gen 9560 (`9DF0`/`A370`) | `2526` `9DF0` `A370` | `iwm` legacy FH DMA | — | ❌ Not supported (`hal_iwm` has no AWDL) |

---

## Realtek (`VEN_10EC` PCIe, `VID_0BDA` USB) — `devourer` backend

| Card / Family | Device IDs | Modes | Status |
|---|---|---|---|
| **Realtek RTL8852CE** | `10EC:C852` | On-Demand (native Wi-Fi kept by Windows) | ⚠️ **Built-in, untested inside nekodrop** (ships native `nekodrop-radio-rtl.exe` from [winawdl](https://github.com/raph559/winawdl)/`devourer` with A-MPDU; compiled and offline-tested in CI, awaiting real-hardware confirmation inside nekodrop; Intel default behavior unchanged) |
| **Realtek RTL8821CU** (USB dongle) | `0BDA:C820` `0BDA:C821` | On-Demand only (the dongle stays on nekodrop's WinUSB driver) | 🧪 **Built-in, experimental**: bring-up, monitor RX and injection verified on one dongle; AirDrop not yet run ([RTL8821CU.md](RTL8821CU.md)) |
| **Realtek RTL8852BE / RTL8851BE** | `B852` `B85B` `B851` | On-Demand | 🚧 Planned right after RTL8852CE (leverages `OpenIPC/devourer` `KESTREL_8852B`) |
| Realtek RTL8852AE / RTL8922AE | `8852` `8922` | On-Demand | 🗓️ Planned |
| Realtek RTL8821CE / RTL8822CE / RTL8822BE, other Realtek USB dongles | `10EC:*`, `0BDA:*` | — | ❌ Not supported |

---

## MediaTek (`VEN_14C3`) — `mt76` (`nekodrop-radio-mt.exe`) & `mtkradio` (`nekodrop-radio-mtk.exe`)

| Card / Family | PCI Device IDs | Modes | Status |
|---|---|---|---|
| **MediaTek MT7902** | `7902` | Concurrent (5 GHz Wi-Fi only) & On-Demand | ⚠️ user-mode mt76/mt7921 port (`mtradio/`). Concurrent: the firmware has one channel, so the radio time-shares it between the router and AWDL (about 3/4 of the time on the router, less while AirDrop moves data; ~3.5 MB/s download and ~1.3 MB/s upload measured with firmware rate control and the router's A-MPDUs, host-side CCMP). AirDrop both ways verified on one card (ASUS desktop, `SUBSYS_60401A3B`, iPhone on 5 GHz ch 44): A-MPDU both ways, ~15 MB/s receive, ~5 MB/s send. On 2.4 GHz frames needing an ACK never complete, so it sends without ACK there. Needs linux-firmware's `WIFI_*_MT7902*` (the Windows driver's copy ignores UNI commands) |
| **MediaTek MT7922 / RZ616** | `7922` `0616` | Concurrent (5 GHz Wi-Fi only, experimental) & On-Demand | 🧪 **Built-in, experimental** (`mtkradio/`, `nekodrop-radio-mtk.exe`). Two-way AirDrop tested on an MT7922 / AMD RZ616 (`14C3:0616`, [#40](../../../pull/40), [MT7922.md](MT7922.md)). Concurrent mode (host-side CCMP, time-sharing between the router and AWDL, AP STA record and RX BA reorder) is **untested on hardware**; gated to 5 GHz pending 2.4 GHz ACK testing. Needs linux-firmware's `WIFI_*_MT7922*` |
| **MediaTek MT7921 / RZ608** | `7961` `0608` | Concurrent (5 GHz Wi-Fi only, experimental) & On-Demand | ⚠️ **Built-in, experimental, untested on hardware** (`mtkradio/`, `nekodrop-radio-mtk.exe`; shares the Connac2 WFDMA and Concurrent station path with MT7922). Needs linux-firmware's `WIFI_*_MT7961*` |
| MediaTek MT7925 | `7925` | On-Demand | 🗓️ Planned |

---

## Qualcomm (`VEN_17CB`) & Broadcom (`VEN_14E4`)

| Vendor / Family | Status | Notes |
|---|---|---|
| Qualcomm WCN6855 / QCNFA765 / WCN7850 (`ath11k`/`ath12k`) | ❌ Not currently feasible in user mode | Requires MHI + QMI + large contiguous MSA memory + 36-bit DMA limits. |
| Broadcom BCM43xx | ❌ Not supported | Apple's Broadcom AWDL runs inside proprietary closed-source firmware. |

---

## How to Check Your Card

Run the standalone diagnostic script without installing nekodrop:

```powershell
powershell -ExecutionPolicy Bypass -File installer\report.ps1
```

It reports every wireless card's PCI ID, chip family, bound driver, and compatibility status. Please attach the redacted report in an [Issue](../../../issues) if your card is not yet supported.
