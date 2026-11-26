// SPDX-License-Identifier: GPL-2.0-only
/* nekodrop's USB half of the radio, for the RTL8821CU (0BDA:C820).
 *
 * winawdl's radio daemon (radio/winawdl_radio.cpp) only ever opened the PCIe
 * register proxy, which is what the RTL8852CE on an M.2 card needs. A USB
 * dongle has no BAR: it needs libusb over WinUSB, and devourer already drives
 * the 8821C silicon (Jaguar2, chip-id 0x09) through exactly that transport.
 * So the daemon keeps its AWDL/block-ack/session logic and swaps the bus:
 * this header is the whole difference, kept out of the patched upstream file.
 *
 * The caller owns libusb, so it also owns the teardown order (destroy the
 * IRadio first — it quiesces TX — then release the interface, close the
 * handle, exit libusb; getting it backwards crashes inside libusb, not
 * leaks). devourer::DeviceSession, the demos' header-only holder, is that
 * order in one object: declare it before the radio and every early return
 * unwinds correctly.
 *
 * Logs start with "radio: " because the service and the diagnostic report
 * parse those lines (``radio: ready on channel N``, ``radio: bring-up
 * failed: <why>``).
 */

#ifndef NEKODROP_USB_SESSION_H
#define NEKODROP_USB_SESSION_H

#include <cstdint>
#include <memory>
#include <string>
#include <utility>

#include <libusb.h>

#include "DeviceSession.h" /* devourer's libusb teardown order holder */
#include "IRadio.h"
#include "UsbOpen.h" /* find_wifi_interface, claim_interface_reset_reopen */
#include "WiFiDriver.h"
#include "logger.h"

namespace nekodrop_usb {

/* The product IDs a RTL8821CU dongle is usually sold under. The chip is
 * dispatched by SYS_CFG2 (0x09), never by the PID, so the list is only the
 * search order used when the caller passes none. */
inline constexpr uint16_t kRtl8821CuPids[] = {0xC820, 0xC821};

class UsbSession {
public:
  UsbSession(Logger_t logger, uint16_t vid, uint16_t pid,
             std::string lock_dir)
      : _logger{std::move(logger)}, _vid{vid}, _pid{pid},
        _lock_dir{std::move(lock_dir)} {}

  UsbSession(const UsbSession &) = delete;
  UsbSession &operator=(const UsbSession &) = delete;
  ~UsbSession() = default; /* DeviceSession tears down, in order */

  /* Opens the adapter, takes the exclusive lock and claims the Wi-Fi
   * interface, then builds the radio for whatever chip answers. nullptr (with
   * a ``radio: bring-up failed:`` line already logged) on any failure. */
  std::unique_ptr<IRadio> create_radio(const devourer::DeviceConfig &config) {
    libusb_context *ctx = nullptr;
    if (libusb_init(&ctx) != LIBUSB_SUCCESS) {
      _logger->error("radio: bring-up failed: libusb_init failed");
      return nullptr;
    }
    _session.adopt_context(ctx);

    const uint16_t vid = _vid != 0 ? _vid : 0x0BDA;
    libusb_device_handle *handle = find_device(ctx, vid, _pid);
    if (handle == nullptr) {
      _logger->error(
          "radio: bring-up failed: no {:04x}:{:04x} found on USB. Is the "
          "dongle plugged in, bound to the nekodrop WinUSB driver "
          "(driver/winusb), and not held by another program?",
          vid, _pid);
      return nullptr;
    }
    describe(handle, vid, _pid);

    /* The vendor Wi-Fi interface, not 0: a composite 8821CU keeps Bluetooth
     * on interfaces 0/1 (src/UsbOpen.h). The reopen variant survives a reset
     * that re-enumerates the dongle (the handle comes back under the same
     * bus/port), and hands the exclusive lock in for the device's lifetime. */
    std::shared_ptr<devourer::UsbDeviceLock> lock;
    const int rc = devourer::claim_interface_reset_reopen(
        ctx, handle, _logger, /*do_reset=*/true, lock, _lock_dir);
    if (rc != 0) {
      if (handle != nullptr) libusb_close(handle);
      _logger->error(
          "radio: bring-up failed: cannot claim the adapter ({}: {}). "
          "Unplug it and plug it back in, and close anything else using it.",
          rc, libusb_error_name(rc));
      return nullptr;
    }
    const int iface = devourer::find_wifi_interface(handle);
    _session.adopt_handle(handle, iface);
    _session.adopt_lock(lock);
    _logger->info("radio: USB {:04x}:{:04x} on interface {}, WinUSB", vid,
                  _pid, iface);

    WiFiDriver driver(_logger);
    std::unique_ptr<IRadio> radio =
        driver.CreateRadio(handle, ctx, lock, config);
    if (!radio) {
      _logger->error("radio: bring-up failed: no supported Realtek chip behind "
                     "{:04x}:{:04x} (this daemon drives the RTL8821CU)",
                     vid, _pid);
    }
    return radio;
  }

private:
  /* Opens `pid` when given, else the first of the known 8821CU PIDs. */
  libusb_device_handle *find_device(libusb_context *ctx, uint16_t vid,
                                    uint16_t pid) {
    if (pid != 0)
      return libusb_open_device_with_vid_pid(ctx, vid, pid);
    for (uint16_t candidate : kRtl8821CuPids) {
      if (libusb_device_handle *handle =
              libusb_open_device_with_vid_pid(ctx, vid, candidate))
        return handle;
    }
    return nullptr;
  }

  /* Bus and port path, for a report: which socket the dongle is in. */
  void describe(libusb_device_handle *handle, uint16_t vid, uint16_t pid) {
    libusb_device *device = libusb_get_device(handle);
    if (device == nullptr) return;
    uint8_t ports[8];
    const int count = libusb_get_port_numbers(device, ports, sizeof(ports));
    std::string port;
    for (int i = 0; i < count; i++)
      port += (port.empty() ? "" : ".") + std::to_string(ports[i]);
    _logger->info("radio: USB {:04x}:{:04x} on bus {}{}", vid, pid,
                  libusb_get_bus_number(device),
                  port.empty() ? "" : " port " + port);
  }

  Logger_t _logger;
  uint16_t _vid;
  uint16_t _pid;
  std::string _lock_dir;
  devourer::DeviceSession _session{_logger};
};

} /* namespace nekodrop_usb */

#endif /* NEKODROP_USB_SESSION_H */
