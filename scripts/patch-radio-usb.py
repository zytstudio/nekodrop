# Applies nekodrop's USB transport to winawdl's radio daemon sources
# (radio/winawdl_radio.cpp) before the RTL8821CU daemon is built.
# Usage: python patch-radio-usb.py <winawdl folder>
#
# The upstream daemon owns the card through devourer's Windows PCIe transport
# (the register proxy, for the RTL8852CE). nekodrop ships the same AWDL session
# for a USB dongle (RTL8821CU), where libusb/WinUSB replaces the proxy and
# send_packet submits a frame directly instead of ringing a TX-ring doorbell.
# Everything here is additive and compiled only with -DNEKODROP_USB, so the
# RTL8852CE daemon built from the same patched file is unchanged:
#
#   - the bus is a Doorbell (kick/defer) that serve_client uses instead of
#     PcieTransport: the PCIe build binds it to the same tx_kick() /
#     set_tx_kick_deferred() calls the radio made before, the USB build to
#     nothing (send_packet already told the card);
#   - main() picks the transport under #ifdef NEKODROP_USB: libusb through
#     usbradio/src/nekodrop_usb_session.h, else the register proxy as before;
#   - --usb VID:PID / --usb-lock-dir DIR;
#   - the "auto" rate ladder asks for a 1SS VHT rate on the 1T1R 8821CU.
#
# Run patch-radio-rtl.py before or after: the two patches touch different
# anchors and are both idempotent.
#
# Exits with an error when the source no longer matches.
import pathlib
import sys

NL = chr(10)
radio = pathlib.Path(sys.argv[1]) / 'radio' / 'winawdl_radio.cpp'
text = radio.read_text(encoding='utf-8')


def block(*lines):
    """An anchor/replacement as source lines, newline-terminated."""
    return NL.join(lines) + NL


MARKER = 'nekodrop (usb)'
TIMES = [
    ('the PcieTransport include',
     block('#include "PcieTransport.h"'),
     block('#ifndef NEKODROP_USB',
           '#include "PcieTransport.h"',
           '#else',
           '#include "nekodrop_usb_session.h" /* nekodrop (usb) */',
           '#endif')),
    ('the deque include',
     block('#include <deque>'),
     block('#include <deque>',
           '#include <functional> /* nekodrop (usb): Doorbell */')),
    ('the retry constant',
     block('constexpr int kMostRetries = 62;'),
     block('constexpr int kMostRetries = 62;',
           '#ifdef NEKODROP_USB',
           '/* nekodrop (usb): the RTL8821CU is 1T1R, so the "auto" ladder tops out at a',
           ' * 1SS VHT rate; a 2SS spec would describe a stream the chip cannot send. */',
           'constexpr bool kSingleStream = true;',
           '#else',
           'constexpr bool kSingleStream = false;',
           '#endif')),
    ('the client loop',
     block('/* Serves client messages until the client leaves or the daemon stops. Returns',
           ' * false for a client that sent nothing, such as a probe for the pipe. */',
           'bool serve_client(PipeServer &pipe, IRadio &radio, devourer::PcieTransport &bus,',
           '                  Session &session, FrameCapture *capture, uint8_t channel,',
           '                  Logger_t logger) {'),
     block('/* nekodrop (usb): what the client loop needs from the bus. On PCIe the frames',
           " * wait in the card's ring until the radio rings its doorbell (batched",
           ' * submission); the USB transport submits inside send_packet, so its doorbell',
           ' * does nothing and the same code drives both. */',
           'struct Doorbell {',
           '  std::function<uint64_t()> kick = [] { return uint64_t{0}; };',
           '  std::function<void(bool)> defer = [](bool) {};',
           '};',
           '',
           '/* Serves client messages until the client leaves or the daemon stops. Returns',
           ' * false for a client that sent nothing, such as a probe for the pipe. */',
           'bool serve_client(PipeServer &pipe, IRadio &radio, const Doorbell &bell,',
           '                  Session &session, FrameCapture *capture, uint8_t channel,',
           '                  Logger_t logger) {')),
    ('the doorbell ring',
     block('    tellings += bus.tx_kick();'),
     block('    tellings += bell.kick(); /* nekodrop (usb) */')),
    ('the auto ladder signature',
     block('std::optional<std::vector<DataRate>> data_rates(const std::string &spec,',
           '                                                uint8_t width_mhz) {'),
     block('std::optional<std::vector<DataRate>> data_rates(const std::string &spec,',
           '                                                uint8_t width_mhz,',
           '                                                bool single_stream) {')),
    ('the auto ladder',
     block('  if (width_mhz == 80)',
           '    rates.push_back(*data_rate("VHT2SS_MCS7/80/SGI", width_mhz));'),
     block('  if (width_mhz == 80) /* nekodrop (usb): 1SS on the 8821CU */',
           '    rates.push_back(*data_rate(single_stream ? "VHT1SS_MCS7/80/SGI"',
           '                                             : "VHT2SS_MCS7/80/SGI",',
           '                               width_mhz));')),
    ('the option fields',
     block('  bool aggregate = true;',
           '  bool quick_submit = true;',
           '};'),
     block('  bool aggregate = true;',
           '  bool quick_submit = true;',
           '#ifdef NEKODROP_USB',
           "  /* nekodrop (usb): the dongle's VID:PID (0: the known RTL8821CU ids), and",
           "   * where the per-adapter lock file goes (the service's run folder). */",
           '  uint16_t usb_vid = 0;',
           '  uint16_t usb_pid = 0;',
           '  std::string usb_lock_dir;',
           '#endif',
           '};')),
    ('the --data-rate option',
     block('    else if (argument == "--data-rate" && i + 1 < argc)',
           '      options.data_rate = argv[++i];',
           '    else',
           '      return std::nullopt;'),
     block('    else if (argument == "--data-rate" && i + 1 < argc)',
           '      options.data_rate = argv[++i];',
           '#ifdef NEKODROP_USB',
           '    else if (argument == "--usb" && i + 1 < argc) { /* nekodrop (usb) */',
           '      const std::string spec = argv[++i];',
           "      const auto colon = spec.find(':');",
           '      if (colon == std::string::npos) return std::nullopt;',
           '      options.usb_vid = static_cast<uint16_t>(',
           '          std::strtoul(spec.substr(0, colon).c_str(), nullptr, 16));',
           '      options.usb_pid = static_cast<uint16_t>(',
           '          std::strtoul(spec.substr(colon + 1).c_str(), nullptr, 16));',
           '      if (!options.usb_vid || !options.usb_pid) return std::nullopt;',
           '    } else if (argument == "--usb-lock-dir" && i + 1 < argc)',
           '      options.usb_lock_dir = argv[++i];',
           '#endif',
           '    else',
           '      return std::nullopt;')),
    ('the 1SS rate check',
     block('  if (!data_rates(options.data_rate, options.width_mhz)) return std::nullopt;'),
     block('  if (!data_rates(options.data_rate, options.width_mhz, kSingleStream))',
           '    return std::nullopt;')),
    ('the usage line',
     block('                 "[--no-quick-submit]\\n",'),
     block('                 "[--no-quick-submit]"',
           '#ifdef NEKODROP_USB',
           '                 " [--usb VID:PID] [--usb-lock-dir DIR]"',
           '#endif',
           '                 "\\n",')),
    ('the transport',
     block('  devourer::PcieTransport::Config bus;',
           '  bus.tx_quick_submit = options->quick_submit;',
           '  auto transport = devourer::PcieTransport::Open("win", logger, bus);',
           '  if (!transport) return 1;',
           '  /* The driver owns it from here on; this is for the calls no radio has. */',
           '  const std::shared_ptr<devourer::PcieTransport> card = transport;',
           '  WiFiDriver driver(logger);',
           '  devourer::DeviceConfig config;',
           '  config.tx.retry_limit = options->retries;',
           '  auto radio = driver.CreateRadioPcie(std::move(transport), config);',
           '  if (!radio) return 1;'),
     block('  devourer::DeviceConfig config;',
           '  config.tx.retry_limit = options->retries;',
           '  std::unique_ptr<IRadio> radio;',
           '  Doorbell bell;',
           '#ifdef NEKODROP_USB',
           '  /* nekodrop (usb): libusb over WinUSB. The session is declared before the',
           '   * radio so the radio (which quiesces TX) is destroyed first, and the',
           '   * libusb context last. */',
           '  config.usb.lock_dir = options->usb_lock_dir;',
           '  nekodrop_usb::UsbSession usb(logger, options->usb_vid, options->usb_pid,',
           '                           options->usb_lock_dir);',
           '  radio = usb.create_radio(config);',
           '  if (!radio) return 1;',
           '#else',
           '  devourer::PcieTransport::Config bus;',
           '  bus.tx_quick_submit = options->quick_submit;',
           '  auto transport = devourer::PcieTransport::Open("win", logger, bus);',
           '  if (!transport) return 1;',
           '  /* The driver owns it from here on; this is for the calls no radio has. */',
           '  const std::shared_ptr<devourer::PcieTransport> card = transport;',
           '  WiFiDriver driver(logger);',
           '  radio = driver.CreateRadioPcie(std::move(transport), config);',
           '  if (!radio) return 1;',
           '  bell.kick = [&card] { return card->tx_kick(); };',
           '  bell.defer = [&card](bool deferred) {',
           '    card->set_tx_kick_deferred(deferred);',
           '  };',
           '#endif')),
    ('the rate ladder in main',
     block('  session.data_rates = *data_rates(options->data_rate, options->width_mhz);'),
     block('  session.data_rates =',
           '      *data_rates(options->data_rate, options->width_mhz, kSingleStream);')),
    ('the first tx_kick_deferred',
     block('    card->set_tx_kick_deferred(options->quick_submit);'),
     block('    bell.defer(options->quick_submit); /* nekodrop (usb) */')),
    ('the client call',
     block('    served = serve_client(pipe, *radio, *card, session, capture.get(), channel,',
           '                          logger);'),
     block('    served = serve_client(pipe, *radio, bell, session, capture.get(), channel,',
           '                          logger);')),
    ('the second tx_kick_deferred',
     block('    card->set_tx_kick_deferred(false);'),
     block('    bell.defer(false); /* nekodrop (usb) */')),
]

def apply(path, marker, times, done):
    text = path.read_text(encoding='utf-8')
    if marker in text:
        print(f'{path.name}: {done} (already patched)')
        return
    for what, old, _ in times:
        if text.count(old) != 1:
            sys.exit(f'{path.name}: {what} moved ({text.count(old)} matches); '
                     'update patch-radio-usb.py')
    for _, old, new in times:
        text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8')
    print(f'{path.name}: {done}')


apply(radio, MARKER, TIMES, 'the radio can drive a USB adapter over libusb')

# The block-ack window granted to the phone. The 8821CU's hardware block-ack
# scoreboard can wedge after one lost frame on a long aggregate stream: the phone
# keeps the rest of its window unacknowledged and the upload dies at the HTTP
# timeout (measured: a 42 MB upload stopped at 6.7 MB and then nothing arrived for
# 30 s). A small window keeps every agreement short-lived and its loss small, so
# the stream keeps moving; the phone's own ADDBA request decides the rest.
ba_window = [
    ('granted_frames signature',
     'inline uint16_t granted_frames(const Request &request) {\n'
     '  return request.buffer_frames == 0\n'
     '             ? kMaxBufferFrames\n'
     '             : std::min(request.buffer_frames, kMaxBufferFrames);\n'
     '}\n',
     '/* How many frames of window to grant for a request. `cap` is the most this\n'
     ' * receiver is willing to hold; nekodrop (usb) grants a small one so the\n'
     ' * 8821CU block-ack scoreboard never carries a long stream. */\n'
     'inline uint16_t granted_frames(const Request &request,\n'
     '                               uint16_t cap = kMaxBufferFrames) {\n'
     '  return request.buffer_frames == 0\n'
     '             ? cap\n'
     '             : std::min(request.buffer_frames, cap);\n'
     '}\n'),
    ('response signature',
     'inline std::vector<uint8_t> response(const Request &request, const Mac &own,\n'
     '                                     const Mac &bssid) {\n',
     'inline std::vector<uint8_t> response(const Request &request, const Mac &own,\n'
     '                                     const Mac &bssid,\n'
     '                                     uint16_t cap = kMaxBufferFrames) {\n'),
    ('response window',
     '(granted_frames(request) << kParamBufferShift)',
     '(granted_frames(request, cap) << kParamBufferShift)'),
]
apply(pathlib.Path(sys.argv[1]) / 'radio' / 'block_ack.h',
      'nekodrop (usb) grants a small one', ba_window,
      'the window granted to the phone can be capped')

# nekodrop (usb) ba window: the radio caps that window for the dongle only; the
# RTL8852CE build keeps OWL's 64 because NEKODROP_USB is not defined there.
radio_window = [
    ('peer_window_cap',
     'void answer_block_ack(IRadio &radio, PipeServer &pipe, Session &session,\n',
     '/* nekodrop (usb) ba window: how many frames of window to grant the phone. */\n'
     'uint16_t peer_window_cap() {\n'
     '#ifdef NEKODROP_USB\n'
     '  static const uint16_t cap = [] {\n'
     '    const char *value = std::getenv("NEKODROP_USB_BA_WINDOW");\n'
     '    const int asked = value ? std::atoi(value) : 0;\n'
     '    return static_cast<uint16_t>(asked > 0 && asked <= 64 ? asked : 8);\n'
     '  }();\n'
     '  return cap;\n'
     '#else\n'
     '  return block_ack::kMaxBufferFrames;\n'
     '#endif\n'
     '}\n'
     '\n'
     'void answer_block_ack(IRadio &radio, PipeServer &pipe, Session &session,\n'),
    ('accept window',
     '  if (!radio.AcceptBlockAck({request->peer}, request->tid,\n'
     '                            request->start_sequence,\n'
     '                            block_ack::granted_frames(*request)))\n'
     '    return;\n',
     '  const uint16_t window = block_ack::granted_frames(*request, peer_window_cap());\n'
     '  if (!radio.AcceptBlockAck({request->peer}, request->tid,\n'
     '                            request->start_sequence, window))\n'
     '    return;\n'),
    ('answer window',
     '  send_frame(radio, capture, rates, block_ack::response(*request, own, bssid));\n',
     '  send_frame(radio, capture, rates,\n'
     '             block_ack::response(*request, own, bssid, window));\n'),
]
apply(radio, 'nekodrop (usb) ba window', radio_window,
      'the block-ack window granted to the phone is capped')