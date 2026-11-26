# Wi-Fi cards beyond the supported Intel ones

nekodrop drives the Wi-Fi chip itself, from user mode, so every chip family
needs its own driver. Today that is the Intel 22000 / AX210 family, ported from
ForbiddenItlwm's `hal_iwx` (see the table in [Supported cards](CARDS.md#supported-hardware)).
This note records what it would take to support other cards, and why the first
step is only better detection in the diagnostic report.

## Which card do I have?

Run the diagnostic report (Start menu → *nekodrop - diagnostic report*). On a
PC without nekodrop, download [`installer/report.ps1`](../installer/report.ps1)
and run `powershell -ExecutionPolicy Bypass -File report.ps1`; it needs no
nekodrop install. Without a supported card, its *Summary* names the card it
found and its *Wi-Fi card* section lists every wireless card with its PCI ID
(`VEN_xxxx&DEV_xxxx`), chip, driver, Device Manager problem code and why
nekodrop does not run on it. The cards come from three sources: adapters whose
medium is native 802.11, known Wi-Fi chip IDs (which also finds a card that is
disabled or has no driver), and adapter names. Ethernet chips from the same
vendors (Realtek `10EC:8168`, Intel `8086:15xx`) are never listed.

Please post that report in an [issue](../../../issues) if you want your card
supported: real device IDs from real machines decide what comes next.

`report.ps1 -SelfTest` checks the classification against made-up IDs without
a card or administrator rights.

## Card families

| Cards | PCI IDs | Feasibility | What is missing |
|---|---|---|---|
| Intel QnJ, SnJ, Meteor Lake (Ma) | `8086:2720` `2726` `2729` `7E40` | depends on upstream | `iwxradio/src/cards.h` knows them, but ForbiddenItlwm ships no firmware for them (QuQnj API 48, SoSnj and Ma API 63). `8086:7E40` is often sold as "AX211". |
| Intel Wi-Fi 7: BE200, BE201/BE211 | `8086:272B` `A840` `7740` `E440` … | depends on upstream | ForbiddenItlwm has no Wi-Fi 7 driver. |
| Another Intel device ID | `8086:*` | maybe easy | If upstream has firmware for it, adding the ID to `cards.h`, `CardCatalog.cs`, the register proxy's INF and `install.ps1` may be all. The report says *an Intel device ID nekodrop does not know*: please post it. |
| **Realtek RTL8852CE** | `10EC:C852` | **built-in (on-demand)** | Native dual-binary backend (`nekodrop-radio-rtl.exe`, from winawdl/devourer) is built and offline-tested in CI; awaiting real-hardware confirmation inside nekodrop. See below. |
| Other Realtek (RTL8852AE/BE, RTL8851BE, RTL8922AE, RTL8821CE/8822CE…) | `10EC:*` | low | No user-mode Windows driver; winawdl's devourer is built only for the 8852C on Windows. |
| MediaTek MT7921/7922/7925/7927/7902, AMD RZ608/616/717 | `14C3:*` | low (long project) | No user-mode Windows driver exists. Would be a port of Linux `mt76` (registers, DMA, firmware, power) with nobody here owning the hardware. |
| Qualcomm (FastConnect 6800/6900/7800), Atheros | `17CB:*` `168C:*` | low | No user-mode Windows driver path. |
| Broadcom | `14E4:*` | very low | No open driver path on Windows. |
| **Realtek RTL8821CU USB dongle** (`0BDA:C820`/`C821`) | `USB\VID_0BDA&PID_*` | **built-in (on-demand, experimental)** | See below: libusb over WinUSB, no register proxy. |
| Other USB adapters | `USB\VID_*` | not planned | Every other family would need its own user-mode driver **and** a WinUSB package; devourer drives Realtek USB silicon only (plus an opt-in MediaTek MT7612U backend), and no daemon in this repo speaks its radio yet. |

### Realtek RTL8852CE

[winawdl](https://github.com/raph559/winawdl), which nekodrop is built on (its
radio pipe, awdld and AirDrop engine, and the register proxy in
`driver/regproxy`), runs AirDrop on the RTL8852CE in user mode through
[devourer](https://github.com/raph559/devourer)'s `winawdl/pcie-windows`
branch. Its register proxy's INF matches only `PCI\VEN_10EC&DEV_C852`, and its
radio build turns on only devourer's `KESTREL_8852C`. RTL8852CE owners can use
winawdl today: AirDrop only, with no Wi-Fi connection while it has the card.

nekodrop now ships RTL8852CE support **built-in** (not hidden behind an
off-by-default experimental switch) using a modular dual-binary dispatch:
Intel cards keep `radio\nekodrop-radio.exe` with 100% unchanged flags and
behavior, while RTL8852CE runs `radio\nekodrop-radio-rtl.exe` (winawdl's
`winawdl_radio.exe` backed by `raph559/devourer`, speaking the exact same
`\\.\pipe\winawdl-radio` v3 protocol and `regproxy_ioctl.h` v2 interface):

1. **Register window.** `driver/regproxy/regproxy.c` picks the largest
   memory BAR of at least 8 KiB (`MIN_BAR_LEN 0x2000`), covering both Intel's
   8 KiB BAR0 and the 8852CE's 1 MiB BAR2, and `winawdl_regproxy.inf` lists
   the generic `PCI\VEN_10EC&DEV_C852` ID (no `SUBSYS`, so it never takes over
   the card on install).
2. **Build.** `scripts/fetch-deps.ps1` pins `raph559/devourer` under
   `third_party\winawdl\upstream\devourer`; `scripts/build-radio-rtl.ps1`
   locates vcpkg across local and CI layouts, builds `winawdl_radio.exe`
   statically (`/MT`, `x64-windows-static`) and runs its four offline unit
   tests (`block_ack_test`, `reorder_buffer_test`, `outgoing_session_test`,
   `dma_address_test`); `scripts/build-installer.ps1` stages it as
   `radio\nekodrop-radio-rtl.exe` alongside `licenses\devourer-GPL-2.0.txt`.
3. **Wi-Fi beside AirDrop.** devourer only monitors and injects; it has no
   station. `CardCatalog.EffectiveMode` automatically downgrades
   `NetMode.Concurrent` to `NetMode.OnDemand` from the card's profile, while
   preserving the user's saved mode setting.
4. **Taking, launching and giving back the card.** `CardCatalog.cs` marks
   `10EC:C852` active (`RadioBackendKind.Devourer`) and provides
   `BuildRadioLaunch`, which strips Intel-only CLI flags when spawning
   `nekodrop-radio-rtl.exe`. `installer/install.ps1` and `installer/report.ps1`
   classify `10EC:C852` as `supported-rtl`, and `install.ps1`, `restore.ps1`,
   `uninstall.ps1` and `report.ps1` all include `nekodrop-radio-rtl`. All
   three scripts' `-SelfTest` suites run offline under Windows PowerShell 5.1
   in `scripts/build-installer.ps1`.

### Realtek RTL8821CU (USB dongle)

A USB dongle has no BAR, so the register proxy cannot reach it. It is still the
same user-mode radio: winawdl's `radio/winawdl_radio.cpp` over
[devourer](https://github.com/raph559/devourer)'s libusb transport, which drives
the 8821C silicon (Jaguar2, chip-id `0x09`) with vendor control requests and
bulk endpoints. What changes, and only for this card:

1. **Driver package.** `driver/winusb/nekodrop_winusb.inf` binds Microsoft's
   in-box WinUSB to `USB\VID_0BDA&PID_C820` (and `C821`), `Provider =
   winairdrop project`. It is catalogued at build time (`Inf2Cat`) and signed on
   the target PC with the same certificate and trusting steps the register proxy
   uses; `install.ps1` only adds it to the driver store, so nothing is taken over
   on install.
2. **Daemon.** `usbradio/` builds `nekodrop-radio-usb.exe` from the same radio
   source, with `-DNEKODROP_USB` (`scripts/patch-radio-usb.py` adds the libusb
   path, a `Doorbell` in place of `PcieTransport`, and `--usb VID:PID`), and only
   devourer's `JAGUAR2_8821C` backend. The RTL8852CE daemon is built from the
   same patched file without the macro and is unchanged.
3. **Taking and keeping it.** The service binds the WinUSB package the first time
   it needs the dongle. `AdapterCapabilities.HandsBackCard = false` keeps it
   there: a WinUSB device cannot also be a Windows network adapter, so this
   dongle is dedicated to AirDrop until restore/uninstall rebinds Realtek's
   driver (`$VendorProfiles['0BDA']` supplies the provider patterns).
4. **Catalog and installer.** `0BDA:C820`/`C821` are active profiles
   (`RadioBackendKind.RtlUsb`), `Card.Find` scans the USB enumerator after PCIe
   and skips a composite dongle's `MI_xx` function nodes (the device node is what
   the driver binds), and `install.ps1`/`report.ps1`/`restore.ps1` know the kind
   `supported-rtl-usb`.

Status, verification record and limitations: [RTL8821CU.md](RTL8821CU.md).

### The service's card catalog

`app/service/CardCatalog.cs` is the service's one list of cards. Each
`AdapterProfile` holds the PCI vendor and device ID, the vendor's name, the
radio that drives it (`Iwx` for Intel, `Devourer` for Realtek RTL8852CE), its
`AdapterCapabilities` (Wi-Fi beside AirDrop, faster sending, A-MPDU sending,
nekodrop-wlan.sys, the smallest register BAR), the register proxy's INF,
service and provider, and the provider names of the vendor's own driver.
`Card.cs` takes only *active* profiles; `Supervisor.cs` runs the mode the
card can run (`CardCatalog.EffectiveMode`: *together* becomes *on demand*
without a station) and uses `CardCatalog.BuildRadioLaunch` to select
`nekodrop-radio.exe` or `nekodrop-radio-rtl.exe` with only the options that
backend accepts. The 15 Intel profiles have every capability, so nothing
changes for them.

All 24 profiles (15 Intel, Realtek RTL8852CE `10EC:C852`, the Realtek RTL8821CU USB dongle `0BDA:C820`/`C821`, MediaTek MT7902, and MediaTek MT7922/MT7921) are active.
`NekoDropService.exe --selftest` (run by `scripts/build-installer.ps1`, so on
every CI build) checks the multi-vendor parsing, the forced *on demand* mode,
provider matching and `BuildRadioLaunch` across both `Iwx` and `Devourer`
without a card or administrator rights. `NekoDropService.exe --status` prints
the profile of the card it finds.

### The radio's backend contract

The radio daemon (`iwxradio/src/radio_main.cpp`) runs one AWDL engine over a
*backend*: `IwxDevice` (the user-mode Intel driver) or `KernelDevice`
(nekodrop-wlan.sys, `--kernel`). `iwxradio/src/radio_backend.h` is the
contract between them: the shared frame, rate and option types, and a
`RadioCapabilities` set that each backend declares as `kCapabilities`.
`radio_main.cpp` branches on those bits (`if constexpr`) instead of asking
whether the backend is `IwxDevice`, so a call a backend does not declare is
never compiled for it, and `radio::check_backend_contract<Dev>()` turns a
declared capability without its calls into a compile error.

| Capability | `iwx` | `kernel` | a Realtek backend (devourer) |
|---|---|---|---|
| Wi-Fi station beside AWDL | yes | Windows keeps it | no |
| Firmware scan for the Wi-Fi list | yes | no (beacons on the channel) | no |
| Receive Block Ack, promiscuous on/off | yes | yes | no |
| A-MPDU sending (experimental) | yes | no | no |
| Batched doorbell for faster sending | yes | no (the driver rings itself) | no |
| Firmware country notice | yes | no (the driver answers it) | no |
| Set country, passive-channel rule | yes | yes | no |
| Largest `--tx-window` | 64 | 64 | 8 |

At start the radio logs one line with its backend's set, for example
`radio: backend iwx: station yes, firmware-scan yes, rx-ba yes, …, tx-window up to 64`
(worded so the diagnostic report's and the service's patterns ignore it).
`iwx_selftest` (run by `scripts/build-radio.ps1`, so on every CI build)
checks the matrix, refuses inconsistent sets, checks each per-capability
policy against what the radio did before (TX window, passive channels,
discovery scan, scan end, station message), and compiles a stand-in for a
Realtek backend that has only the core listener calls, with no stubs. The
Intel and kernel paths behave exactly as before; nothing Realtek runs.

A new backend then means: a class with the core calls (`open`,
`start_monitor`, `set_channel`, `set_address`, `transmit`, `transmit_slot`,
the RX and TX-status handlers, `poll`, `check_health`, `healthy`,
`tx_stats`, `channel`, `width_mhz`, `hw_address`, `stop`), a
`kCapabilities` naming what else it has, and one more branch where
`radio_main.cpp` picks the backend. `WifiStation` is still written for
`IwxDevice`, so only it can declare a station.

## The steps

1. **Detection (done).** The diagnostic report names every wireless card, its
   chip and driver and why nekodrop does not run on it. Diagnostics and docs
   only: no driver, installer, service or radio change.
2. **Service card catalog (done).** `CardCatalog.cs` above: profiles and
   capabilities instead of Intel assumptions in `Card.cs` and
   `Supervisor.cs`, with an offline self-test. No change for Intel cards.
3. **Radio backend contract (done).** `radio_backend.h` above: capabilities
   instead of `IwxDevice` checks in `radio_main.cpp`, no Intel-only stubs in
   `KernelDevice`, with offline checks in `iwx_selftest`. No change for Intel
   cards or the kernel driver.
4. **Installer message (done).** `install.ps1` refuses unsupported cards with
   the same classification as `report.ps1`: every detected wireless card, its
   PCI/USB ID, why nekodrop does not run on it, an upstream `winawdl` pointer
   for an RTL8852CE (`10EC:C852`), and `installer/report.ps1` guidance, in pure
   ASCII for Inno Setup's error box, checked offline by `install.ps1 -SelfTest`.
5. **Built-in RTL8852CE (done, awaiting real-hardware confirmation inside nekodrop).**
   `regproxy.c` selects the largest memory BAR (`>= 8 KiB`), `winawdl_regproxy.inf`
   adds generic `PCI\VEN_10EC&DEV_C852`, `build-radio-rtl.ps1` builds and tests
   winawdl/devourer's `nekodrop-radio-rtl.exe`, `CardCatalog.cs` activates
   `10EC:C852` as a native built-in backend (not behind an off-by-default
   experimental switch) automatically downgraded to *on demand*, and
   `install.ps1`, `report.ps1`, `restore.ps1`, and `uninstall.ps1` all support
   it. Intel cards keep `nekodrop-radio.exe` and their exact existing behavior.

When adding IDs, keep `AllProfiles` in `app/service/CardCatalog.cs`,
`$SupportedIntelIds` (and `$SupportedCardPattern`) in `installer/report.ps1`,
`installer/install.ps1` and `installer/restore.ps1`, `kDeviceIds` in
`iwxradio/src/cards.h`, and the register proxy's INF in step. The service
self-test expects 24 active profiles (15 Intel, Realtek `10EC:C852`, the USB `0BDA:C820`/`C821`, MediaTek MT7902 and MT7922/MT7921), and the
installer self-tests keep the Intel ID table and multi-vendor classification
tables in sync across scripts.
