# Realtek RTL8821CU (USB)

English · [Back to README](../README.md) · [Card compatibility](COMPATIBILITY.md)

A USB Wi-Fi dongle on AirDrop, driven from user mode, with no kernel driver of
ours: the radio talks to the chip through `libusb` over Microsoft's in-box
WinUSB driver. `rtw88`/`rtl8821cu` vendor drivers are never involved.

## The card

| | |
|---|---|
| Hardware ID | `USB\VID_0BDA&PID_C820` (`C821` on some dongles); nekodrop binds the Wi-Fi function `MI_02`, the composite parent and Bluetooth keep their own drivers |
| Silicon | RTL8821C (`RTL8811CU`/`RTL8821CU`), Jaguar2, SYS_CFG2 chip-id `0x09`, 1T1R + Bluetooth |
| Radio | `radio\nekodrop-radio-usb.exe` (`usbradio/`), winawdl's radio daemon over [devourer](https://github.com/raph559/devourer)'s USB transport |
| Driver package | `driver\winusb\nekodrop_winusb.inf` — WinUSB, `Provider=winairdrop project` |
| Channel | 149, 20 MHz (this chip's devourer path: 80 MHz does not work through it, and 40 MHz has a degraded mode that only a USB replug clears) |
| Mode | Always on: no station, so Concurrent is reported as on demand, but a dedicated dongle is started at boot and never idled out |

## How it works

nekodrop's radios all speak winawdl's radio pipe (`\\.\pipe\winawdl-radio`,
`radio_link.h`) to awdld, and everything above the pipe is card-independent. The
RTL8852CE's daemon gets at its card through the register proxy in
`driver/regproxy` (a PCIe BAR). A USB dongle has no BAR, so this daemon opens
the device with libusb instead and devourer drives the 8821C silicon over USB
vendor requests and bulk endpoints.

The AWDL session itself — block-ack grants, the reorder buffer, the rate
ladder, the phone's 5 GHz channel report — is winawdl's `radio/winawdl_radio.cpp`,
patched at build time (like the RTL8852CE's) to add the USB transport under
`-DNEKODROP_USB`; the PCIe daemon built from the same file is unchanged:

- `scripts/patch-radio-rtl.py` — the phone's AWDL channel report (both daemons).
- `scripts/patch-radio-usb.py` — `--usb VID:PID`, a `Doorbell` abstraction in
  place of `PcieTransport` (USB submits inside `send_packet`), and a 1SS rate
  for the 1T1R radio.
- `usbradio/src/nekodrop_usb_session.h` — the libusb half: open, claim the
  vendor interface, `CreateRadio`, and the teardown order (the radio before the
  USB context).

## The dongle is dedicated to nekodrop

A WinUSB device cannot also be a Windows network adapter: the vendor's Wi-Fi
driver has to be out of the way. So this is *not* the RTL8852CE's on-demand
give-back model:

- the first time the service takes the dongle it binds `nekodrop_winusb.inf` to
  the Wi-Fi **function** (`USB\VID_0BDA&PID_C820&MI_02`, `INSTALLFLAG_FORCE`),
  and that function is no longer a Windows network adapter. The composite
  parent keeps `usbccgp` and the Bluetooth function keeps its own driver: only
  the Wi-Fi function is WinUSB (the same binding DropBridge uses for this chip);
- `AdapterCapabilities.HandsBackCard = false`, so switching AirDrop off, or
  restarting the service, does **not** put Realtek's driver back;
- **Start menu → nekodrop - restore Windows Wi-Fi** (or uninstall) binds the
  vendor's driver again, exactly as for a PCIe card. Nothing is deleted from
  the driver store by taking it.

Binding the whole device instead (which is what the first build did) makes the
composite parent winusb.sys: the Wi-Fi then received almost nothing and the
dongle's Bluetooth vanished. The INF deliberately lists only the `MI_02` IDs.

## What was verified, and what was not

Verified on one machine (the maintainer's, Windows x64, one `0BDA:C820`
composite dongle):

- WinUSB package installs from the INF signed on that PC; libusb opens the
  device and reads SYS_CFG2 → `0x09` (RTL8821C);
- full bring-up: power-on, EFUSE, firmware download + boot, MAC/BB/RF tables,
  IQK, RX enabled, 8-URB RX ring;
- monitor RX on 2.4 GHz channel 6 (real beacons and ACKs, `rx.pkt` events) and,
  on **channel 149 at 20 MHz, AWDL sync with a real iPhone**: awdld reported
  `peers 1`, `rx action 2 → 69`, `rx data 1 → 6`, and the sync tree moved to the
  iPhone (`66:8a:…`) while its AirDrop sheet was open. On channel 6 it never
  heard a peer, which is why the card's default channel is 149;
- TX path submits (50 injected frames, 0 failures, `tx.stats`);
- the daemon itself reaches `radio: ready on channel 6, waiting for a client`;
- **the installed stack**: `nekodrop-2.2.12-setup.exe` installs, the service takes
  the dongle (WinUSB), launches `nekodrop-radio-usb.exe` and awdld, awdld greets
  the radio and creates its `awdl0` host interface, and the radio stays up
  (measured 14:27:41 wake → 14:28:32 awdld up, still running 4 minutes later).

- **iPhone → PC, end to end, on hardware**: with the radio on 149 at 40 MHz the
  iPhone appeared (`add peer fe:e5:…`, mDNS `_airdrop._tcp` queried and answered,
  `POST /Discover` 200), its request was accepted and a 228,844-byte PNG arrived
  (`POST /Upload` 200, stored in the receive folder) about 2 s after the accept.
  Peak throughput on this 1T1R dongle is low (~0.15 MB/s for that file) because
  the iPhone as sync master spends only part of its slots on 149.

**Not yet verified:** PC → iPhone sending on this dongle (the engine is the same
one the Intel cards send with; it needs an Apple identity for the receiving
iPhone to accept it), and sustained throughput. Until a run confirms sending,
this card ships as **experimental** (README, the compatibility table and the
release notes say so). Please run *nekodrop - diagnostic report* after the next
transfer and attach it to an issue.

## Bring-up is slow, and three timeouts were raised for it

The chip needs its ~12k PHY-table registers written one USB vendor control
transfer at a time, so the first start takes **~50 s** (measured: 14:21:53
"woken" → 14:22:44 awdld greeting). Everything that waits for that start had to
be told, all of it per-backend so no other card changes:

- awdld's radio greeting: `HELLO_TIMEOUT_MS` 10 s → 180 s
  (`scripts/patch-awdl.py`; Intel and the RTL8852CE greet in milliseconds);
- the service's "the radio never became ready" restart: 60 s → 240 s for
  `RadioBackendKind.RtlUsb` (`Supervisor.Watchdog`);
- the service's on-demand idle stop: **not applied to a dedicated card** at all
  (`AdapterCapabilities.HandsBackCard == false`), and such a card is **started at
  boot** instead of on the first wake. The ~50 s is paid once, when Windows
  starts, not on every AirDrop; a stop also no longer counts as "idle" the
  moment the radio comes up (`Supervisor.OnRadioLine`).

The radio therefore stays on channel 149 with awdld attached; after a reboot the
first minute is still a bring-up, but nothing has to happen per transfer.

## Speed: 1T1R, 20 MHz, and a small block-ack window

The iPhone stays the AWDL sync master and only some of its slots land on 149
(measured: 3 to 7 of 16), so throughput is bounded by its schedule; with the
fixes below a transfer runs at a few hundred KB/s. Three things matter:

- **`-s 1`** — the card is 1T1R, and announcing two spatial streams made the
  phone pick 2SS rates this receiver cannot decode, so every frame fell back to
  retries;
- **20 MHz** — devourer's 8821C path has a degraded 40 MHz mode that only a USB
  replug clears, and 20 MHz measured slightly faster too;
- **8-frame block-ack window** — see below.

### Block-ack window: the stall fix

A 42 MB iPhone upload used to stop dead after 6.7 MB and then time out
(`request body read timed out, nothing arrived for 30 s`, HTTP 408). The cause is
the 8821CU's hardware block-ack scoreboard: with the 64-frame window OWL grants
by default, one lost frame leaves the phone's window unacknowledged for the rest
of the upload. The radio now grants **8 frames** (`NEKODROP_USB_BA_WINDOW`,
passed by the service, `scripts/patch-radio-usb.py`), which keeps every
agreement short-lived. Measured after the change: a 14.2 MB Live Photo bundle
(6 files) completed in 40.4 s — **339 KB/s** average, no stall. `off` in that
variable restores OWL's 64.

## Limitations

- **1T1R, 20/40 MHz**: the card runs at 40 MHz on 5 GHz (devourer's 8821C path
  does not work at 80 MHz — the same finding as DropBridge) and 20 MHz on
  2.4 GHz. USB 2.0 host-push injection caps throughput; expect materially less
  than a 2T2R PCIe card.
- **The iPhone as sync master spends only some slots on 149**, so the radio hears
  it intermittently even once synced; that is a scheduling limit of a fixed-channel
  monitor, not of this port.
- **If the iPhone stops listing this PC**, the state that is stuck is on the phone:
  closing and reopening AirDrop did not help, restarting the phone did (seen twice
  on the same iPhone). Nothing on the PC needed a restart.
- **No station** (Concurrent is downgraded to On-Demand), like the RTL8852CE.
- **Two identical dongles**: the first one found is opened (the daemon takes
  `--usb VID:PID`, not a bus path).
- **ZeroCD dongles**: a stick that enumerates as `0BDA:1A2B` first
  (a USB drive holding a Windows installer) must be switched to its NIC id
  before nekodrop can use it; `0BDA:1A2B` is not in the catalog.
- **Channel moves restart the daemon**: the service moves to the phone's 44 or
  149 as for every card; the daemon never retunes in place.

## Building and testing

```powershell
.\scripts\fetch-deps.ps1        # winawdl + devourer at their pinned commits
.\scripts\build-radio-usb.ps1   # build\usbradio\nekodrop-radio-usb.exe
```

The daemon accepts `<channel> --width 20|40|80 --usb 0bda:c820`; without a
service it creates the radio pipe and waits for a client. The installer stages
it as `radio\nekodrop-radio-usb.exe` next to the WinUSB package in `driver\`,
and `NekoDropService --selftest` checks the catalog, the mode and the launch
arguments on every build (`CardCatalog.SelfTest`).
