---
name: add-wifi-card
description: Add support for a new Wi-Fi card (or card family) to nekodrop, or add Concurrent mode to a supported one, end to end — radio daemon, service, register proxy, installer, firmware, docs — without changing any card that already works. Use when someone asks to support a card nekodrop refuses (installer says "no Wi-Fi card nekodrop supports"), to port a Linux/BSD driver into a radio daemon, or to bring a card from on-demand to Concurrent. Distilled from the AX210-family, RTL8852CE, MT7902, MT7922/MT7921 and BE200 ports.
---

# Adding a Wi-Fi card to nekodrop

nekodrop runs AirDrop on a card through three layers (see `docs/ADDING-A-CARD.md` for the diagram):
a **user-mode radio daemon** that speaks winawdl's radio pipe (`\\.\pipe\winawdl-radio`, `radio_link.h`)
to awdld, the **service** (`app/service`) that picks the card and starts the daemon, and the **register
proxy** (`driver/regproxy`, UMDF) that maps the card's largest memory BAR into the daemon. Everything above
the daemon (awdld, the AirDrop engine, the client) is the same for every card.

**Read `docs/ADDING-A-CARD.md` first.** This skill is the how-to and the lessons behind it.

## 0. Ground rules (non-negotiable)

1. **A card is only "supported" once it has run AirDrop on real hardware.** Code that only compiles ships
   as *experimental* and says so in the README, the compatibility table and the release notes. Ask the
   person for a diagnostic report (Start menu → *nekodrop - diagnostic report*) from a real run.
2. **Never change the behaviour of a card that already works.** Every new path is gated on the new
   family (a `CardInfo` flag such as `bz`, a backend kind, or a firmware capability/TLV the old firmware
   does not have). At the end, re-read every *removed or modified* line of shared code and prove the old
   path is byte-for-byte the same. When a gate is a firmware capability, check the shipped firmware
   files really lack it (parse their TLVs; see §6).
3. **No kernel driver.** `kdriver/` (WiFiCx) is a dead end by maintainer decision; don't propose it.
   But CI still compiles `iwxradio/src/{iwx,iwx_sta,iwx_scan,fw}.cpp` for it with **`/std:c++17 /W4 /WX`**:
   shared code must be C++17 and warning-free under MSVC W4 (a shadowed local, C4456, broke a release).
4. **Evidence, not guesses.** When a log can't tell two causes apart, add a diagnostic log line, ship it,
   and ask for a report. Don't "fix" blind.
5. **Firmware is fetched, never committed**, from a pinned commit with a SHA-256 per file. Apple
   components (iCloud for Windows) are never bundled either.
6. **One card family per branch**, small topic commits, `Co-Authored-By` for anyone whose code you port.

## 1. Identify the card precisely

- PCI vendor/device (and subsystem) from the report or Device Manager. The marketing name lies:
  Panther Lake `8086:E440` shows up as "AX211" but is a new MAC that needs the MLD API; Killer AX1650i
  is an AX201 (`06F0`); Killer AX1690 is an AX411.
- Find the family in the upstream driver:
  - Intel: Linux `iwlwifi` `pcie/drv.c` + `cfg/*.c` (MAC type, RF type, transport generation, firmware
    name prefix, API version) and OpenBSD `if_iwx.c`. iwxradio's table is `iwxradio/src/cards.h`.
  - MediaTek: Linux `mt76` (`mt7921/`, `mt7925/`, `mt76_connac*`).
  - Realtek: `rtw89` (Linux) and raph559/devourer.
- Check the firmware exists in linux-firmware at the pinned commit (see `scripts/fetch-deps.ps1`, `$lfw`)
  or in ForbiddenItlwm (Intel API 68 images). A card whose firmware isn't shipped anywhere can't be done.
- Decide the size honestly: a new ID on a known family is a one-day job; a new MAC generation or a new
  command API (Intel MLD, API 86+) is weeks and needs hardware. Write the plan down (BE200 →
  `docs/BE200.md`) before writing code.

## 2. The radio daemon

Pick one:
- **An existing daemon covers the family** → add a `cards.h` entry / family flag and keep the rest.
- **An existing project already speaks the radio pipe** (winawdl's radio drove RTL8852CE) → build it in
  `scripts/build-radio-*.ps1`, patch it at build time with an idempotent script that `sys.exit`s when the
  source moved (`scripts/patch-radio-rtl.py`).
- **A new port** → its own folder (`mtradio/`, `mtkradio/`), CMake + Ninja + MSVC `/MT`, reusing
  `iwxradio/src/{proxy,plat_win,pipe_server}` by relative path.
- **A USB card** (no BAR, so no register proxy) → the RTL8821CU is the worked example (`usbradio/`,
  `driver/winusb/`). USB support lives in this downstream fork only: upstream takes PCIe cards, whose
  register BAR can be proxied. The *same* winawdl radio source is built a second time with
  `-DNEKODROP_USB` (`scripts/patch-radio-usb.py` adds `--usb VID:PID`, a `Doorbell` in place of
  `PcieTransport`, and a 1SS rate for a 1T1R part), plus a WinUSB INF (`Include=winusb.inf,
  Needs=WINUSB.NT`) bound to the dongle's Wi-Fi **function** only (`MI_02`): listing the whole
  composite device makes winusb.sys replace usbccgp, and the Wi-Fi function then receives almost
  nothing. `usbradio/src/nekodrop_usb_session.h` owns libusb: `find_wifi_interface` (a composite
  dongle's Wi-Fi is `MI_02`, never 0), `claim_interface_reset_reopen`, `CreateRadio`, and the teardown
  order through devourer's `DeviceSession` (radio before context; getting it backwards crashes).
  A WinUSB device cannot also be a Windows network adapter: the dongle is taken for good
  (`AdapterCapabilities.HandsBackCard = false`) and only restore/uninstall rebinds the vendor driver.
  Inf2Cat needs elevation on Windows 11 26H1 and cannot read an INF under a directory named `driver`
  (stage it in `build\`), and never copy `winusb.inf` beside the INF.

What the service and the diagnostic report expect from any daemon (they parse these lines):

| Line (after the `radio: ` prefix) | Meaning |
|---|---|
| `ready on channel N, waiting for a client` | bring-up done; the service marks the radio On |
| `bring-up failed: <why>` | shown to the user and in the report |
| `event: peer-channel 44` / `149` | the phone's 5 GHz AWDL channel: the service moves there |
| `event: peer-country XX`, `event: country XX` | the regulatory country |
| `event: channel 149 passive` / `active` | passive 5 GHz channel handling (#11) |
| `transmitting allowed here` | a passive channel was unlocked |
| `rx: … N addressed to us` | keeps a channel move waiting during a transfer |
| `event: wifi connected`, `event: bss …`, `event: scan-done N` | the Wi-Fi station (Concurrent) |

A daemon whose log prefix is `mtkradio: ` still matches, since it contains `radio: `. Unknown command-line
options must be ignored or rejected *consistently*: the service passes only what its `IRadioBackend`
builds.

Hard-won bring-up lessons (Intel, but the shape repeats):
- **Notifications may arrive in another command group** than you expect. iwxradio normalises
  LONG_GROUP → legacy IDs because AX210 lost `INIT_COMPLETE` without it (#2). Log unhandled notification
  IDs once each so a missing one is visible.
- **Reserve every DMA buffer before the pool is trimmed** (the PNVM buffer came too late: "PNVM: out of
  DMA memory", then a firmware assert at NVM_ACCESS_COMPLETE, #2/#7/#8). Machines with fragmented
  locked memory need small rings: AX210-family TX rings are 128 entries, not 256 (#11).
- **Don't write registers the newer family doesn't expect**: `nic_config` must not run on the AX210
  family (OpenBSD skips it; the firmware asserted, #7).
- **Per-device transport quirks** come from the upstream config: xtal latency, LTR, IMR (Raptor Lake
  AX211). Copy them; don't generalise.
- **Strip a trailing FCS** before awdld sees a frame (AX210-family firmware appends it with the CRC
  filter; OWL then rejected the MIF and the PC was never listed, #24).
- **Arm the proxy's close ops** (stop DMA on process death) before the card can DMA into host memory.
- **Never enable `LOW_LATENCY_CMD` on AX211 API 68**: it crashes the firmware and takes Wi-Fi down.
- **The firmware's country notice** must be answered with its own country and source, or a passive
  channel stays passive (#11).
- **Report the peer's channel** (`event: peer-channel`), or the card sits on 2.4 GHz channel 6 and
  sending crawls (RTL8852CE, #32).

## 3. The service (`app/service`)

- `CardCatalog.cs`: a `RadioBackendKind` (new daemon only), one `AdapterProfile` per PCI ID with its
  `AdapterCapabilities` (`SupportsConcurrentWifi`, `SupportsFastSend`, `SupportsAggregate`,
  `SupportsKernelDriver`, `MinBarBytes`, `StationOn24GHz`), the vendor driver's provider names (to give
  the card back), `Active`, and `RadioFamily` when the daemon needs `--family`. Add a `ManualModels`
  entry so an unrecognised ID can be picked by hand.
- `RadioBackends.cs`: an `IRadioBackend` (exe name, `BuildArgs`) registered in `RadioBackends.All`. Pass
  only options the daemon accepts.
- `CardCatalog.SelfTest()` (`NekoDropService --selftest`, run by CI): update the active-profile count;
  add checks for the new profile (backend, BAR, capabilities, `EffectiveMode` on Concurrent, launch args
  with and without a station). Existing checks that used the new ID as an *unknown* ID must switch to
  another unknown ID.
- `SupportsConcurrentWifi = false` makes Concurrent run on demand automatically; the service also falls
  back to on demand when a station fails.

## 4. Register proxy, installer, report, restore

- `driver/regproxy/winawdl_regproxy.inf`: add `PCI\VEN_xxxx&DEV_yyyy` (generic IDs rank below the vendor
  driver, so nothing is taken by itself). The proxy maps the largest memory BAR ≥ 8 KiB; raise
  `MinBarBytes` if the card needs more (MediaTek: 1 MiB). Keep UMDF 2.31 (Windows 10 has no 2.33, #3).
- `installer/install.ps1` **and** `installer/report.ps1`: `$WifiChips`, `$WifiKinds`,
  `$SupportedIntelIds`, `$WifiVendors` must stay **byte-identical** between the two (install.ps1
  `-SelfTest` compares them) and **ASCII-only** (Windows PowerShell 5.1 reads a BOM-less file in the ANSI
  code page). `$SupportedCardPattern` keeps the 4-hex boundary `(?=&|\\|$)` so `DEV_43F01` never matches
  `43F0`; update its expected string in the self-test, the refusal text `$NoSupportedCard`, and the
  report's self-test cases.
- Process lists that stop the daemons (install, uninstall, restore, report): add the new exe.
- `installer/restore.ps1`: `$KnownCatalogIds` so one-click restore finds the card.
- `scripts/fetch-deps.ps1`: firmware from the pinned linux-firmware commit (GitLab raw URL, `Get-File`
  with SHA-256, compute it by downloading). `scripts/build-installer.ps1`: build the daemon, copy the exe
  and firmware to `build\stage\radio\`, and the licence.

## 5. Concurrent mode (Wi-Fi beside AirDrop)

- The station logic is shared: `iwxradio/src/wifi_sta.*` (`WifiStation`: join, WPA2/WPA3, TAP bridge)
  drives any backend through `iwxradio/src/sta_device.h` (`StaDevice`). Implement `StaDevice` for the new
  radio; reuse, don't fork. MediaTek host-side CCMP lives in `mtradio/src/ccmp.*` with its test.
- One-channel cards time-share between the router and AWDL (MT7902 #47 is the reference: power-save
  null before each move, RF-only channel switch, more entries to Wi-Fi when AirDrop is idle).
- `StationOn24GHz: false` when the card can't complete ACKed frames on 2.4 GHz (MT7902).

## 6. Verify before asking anyone to test

There is no Windows toolchain on the maintainer's Mac; CI is the build.

- Offline: `clang++ -std=c++17 -fsyntax-only -Wall -Wextra -Wshadow-all -Wsign-compare` with a scratch
  `windows.h` shim **outside the repo**, then filter the warnings to the lines you changed (macOS headers
  make `flsl` ambiguous and redefine `howmany`: not yours).
- Firmware gates: parse the TLVs of the old cards' firmware (header magic `0x0a4c5749`, TLVs from byte
  88; `IWL_UCODE_TLV_ENABLED_CAPABILITIES` = 30) to prove a capability-gated path can't trigger on them.
- Python checks: install.ps1/report.ps1 tables identical, install.ps1 ASCII.
- CI on the branch: `build.yml` (radios, client, service `--selftest`, kernel compile, installer),
  `report-test.yml`, `engine-test.yml`. All three green before merging.

## 7. Docs and release

- `README.md` + `README.zh-CN.md` card table and badge, `docs/COMPATIBILITY*.md`, a `docs/<CARD>.md` for
  anything non-trivial (what's done, what needs hardware), `CHANGELOG.md` (one line per item: 新增 xx 支持).
- Contributors section in both READMEs for whoever ported or tested it.
- Release as a **preview** until a real card has run it; the notes ask owners for a diagnostic report and
  point to *nekodrop - restore Windows Wi-Fi*.

## 8. What to send in a card PR

- The diagnostic report and full log from a real run: bring-up table all `ok`, AWDL frames heard, AirDrop
  both directions, speeds.
- CI green, the checks in §6, and a list of anything not verified.
