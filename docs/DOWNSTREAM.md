# This fork: USB Wi-Fi dongles

This repository is a **downstream fork** of
[zheznanohana/nekodrop](https://github.com/zheznanohana/nekodrop). It exists for
one reason: upstream targets **PCIe** Wi-Fi cards, and this fork adds **USB
dongles** on top.

## Why USB needs its own fork

nekodrop's radios reach a PCIe card through its register BAR: the in-box driver
maps the BAR, and a user-mode register proxy (`driver/regproxy`) forwards the
card's register accesses to the radio daemon. That works for every PCIe card
here — Intel, RTL8852CE, MediaTek.

A USB dongle has no BAR. Its silicon is reached through vendor control requests
and bulk endpoints, which a user-mode process can only get at by taking the
device over with WinUSB and talking to it through libusb. That is a second
transport (devourer's USB path instead of the register proxy), a second driver
package (a WinUSB INF instead of `winawdl_regproxy`), a device that cannot be
shared with Windows' own Wi-Fi driver, and a bring-up that writes ~12k PHY
registers one control transfer at a time (about 50 s). Upstream has decided not
to carry that complexity, which is why this support lives here.

## What the fork adds

| Path | What it is |
|---|---|
| `usbradio/` | `nekodrop-radio-usb.exe`: winawdl's radio daemon rebuilt with `-DNEKODROP_USB` over devourer's libusb transport |
| `driver/winusb/` | `nekodrop_winusb.inf`: WinUSB bound to the dongle's Wi-Fi function (`MI_02` only) |
| `scripts/patch-radio-usb.py`, `scripts/build-radio-usb.ps1`, `scripts/usb-card.ps1` | build/patch and take/give-back helpers |
| `app/service/*` | `AdapterBus.Usb`, `RadioBackendKind.RtlUsb`, the USB profile and its dedicated-card rules |
| `installer/*` | detection, report, restore and uninstall for `0BDA:C820`/`C821` |
| `docs/RTL8821CU.md` | design, verification record and limitations of the supported dongle |

Everything else tracks upstream. A PCIe card behaves exactly as upstream's
README, docs and changelog describe: the shared files gain USB branches that are
inert when no dongle is present (`CardCatalog`, `Card.Find`, `Supervisor`,
`installer/*.ps1`), and the patches the build applies to winawdl are either
compiled only with `-DNEKODROP_USB` or, for the longer first-greeting timeout,
only lengthen a timeout.

## Supported, and experimental

Only the **Realtek RTL8821CU** (`0BDA:C820` / `C821`, the `C821` variant is the
same silicon) is supported, and it is **experimental**:

- the dongle is dedicated to nekodrop (WinUSB on its Wi-Fi function) until
  restore/uninstall gives it back — it has no Wi-Fi of its own while AirDrop is
  available;
- it runs on 149 / 20 MHz, which is the configuration this chip's devourer path
  was validated with; expect a few hundred KB/s rather than the PCIe cards'
  tens of MB/s;
- iPhone → PC transfers are verified; PC → iPhone sending and sustained
  throughput are not.

Details, measurements and the recovery notes are in
[Realtek RTL8821CU (USB)](RTL8821CU.md).

## Reporting and pull requests

USB-specific issues and pull requests belong **in this repository**; upstream
works on PCIe cards and does not take USB changes. For a PCIe card, report
upstream instead — the fork's PCIe code is upstream's.

## Keeping up with upstream

The fork follows upstream `main`. To update:

```sh
git remote add upstream https://github.com/zheznanohana/nekodrop.git   # once
git fetch upstream
git merge upstream/main        # or: git rebase upstream/main
```

Resolve conflicts in the fork's own files by keeping this fork's USB work; the
shared files (`app/service/CardCatalog.cs`, `app/service/Supervisor.cs`,
`installer/*.ps1`, `README*`, `CHANGELOG.md`) are the ones that will conflict.
Build with the same toolchain as upstream (`scripts/build-installer.ps1`), which
builds the USB radio and its WinUSB package as well.
