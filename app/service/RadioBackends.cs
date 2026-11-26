// SPDX-License-Identifier: GPL-2.0-only
namespace NekoDrop.Service;

/// <summary>What the service knows when it starts a card's radio daemon.</summary>
/// <param name="Profile">the card (CardCatalog): IDs, capabilities, and RadioFamily when chosen by hand</param>
/// <param name="Channel">the AWDL channel to start on (6, 44 or 149)</param>
/// <param name="Kernel">nekodrop-wlan.sys owns the card (Intel only)</param>
/// <param name="Country">two letters learned from a peer or a network, "" if none</param>
/// <param name="StaConf">the Wi-Fi station's config file (Concurrent mode), or null</param>
/// <param name="Aggregate">A-MPDU sending (always true from the service since 0.1.35; the radio
/// skips it by itself without DMA room for the extra ring)</param>
/// <param name="FastUnlock">experimental fast passive-channel unlock is on in the settings</param>
/// <param name="CoexPlan">experimental coexistence plan (router entries in the AWDL schedule) is on</param>
/// <param name="BtCoexBalanced">balanced Bluetooth coexistence (always true from the service since
/// 0.1.37: AX200 and AX211 data, nobody worse; Intel only, not on the kernel path)</param>
public sealed record RadioStart(AdapterProfile Profile, int Channel, bool Kernel, string Country, string? StaConf,
                                bool Aggregate, bool FastUnlock, bool CoexPlan = false, bool BtCoexBalanced = false,
                                bool HighThroughput = false)
{
    /// <summary>20 MHz on 2.4 GHz, 80 MHz on 5 GHz.</summary>
    public int Width => Channel <= 14 ? 20 : 80;
}

/// <summary>
/// One user-mode radio daemon: how the service starts it. Every daemon speaks
/// winawdl's radio pipe (\\.\pipe\winawdl-radio, radio_link.h) to awdld, and
/// talks to the card through the register proxy (driver/regproxy), so the rest
/// of the service is the same for every card. Adding a card family:
/// docs/ADDING-A-CARD.md.
/// </summary>
public interface IRadioBackend
{
    RadioBackendKind Kind { get; }
    /// <summary>The daemon's file name in the install folder's radio\ directory.</summary>
    string ExeName { get; }
    /// <summary>Its command line. Pass only options this daemon accepts: unknown ones make winawdl's exit with status 2.</summary>
    IReadOnlyList<string> BuildArgs(RadioStart s);
}

/// <summary>The backends the service can start, by kind.</summary>
public static class RadioBackends
{
    static readonly Dictionary<RadioBackendKind, IRadioBackend> All = new IRadioBackend[]
    {
        new IwxRadioBackend(),
        new DevourerRadioBackend(),
        new RtlUsbRadioBackend(),
        new Mt76RadioBackend(),
        new MtkRadioBackend(),
    }.ToDictionary(b => b.Kind);

    public static IRadioBackend Get(RadioBackendKind kind) =>
        All.TryGetValue(kind, out var b) ? b : throw new NotSupportedException($"no radio backend for {kind}");

    public static IEnumerable<IRadioBackend> Registered => All.Values;
}

/// <summary>
/// Intel 22000 / AX210 families: nekodrop-radio.exe (iwxradio, ported from
/// ForbiddenItlwm). Station, A-MPDU, kernel driver; faster sending (64 frames
/// in flight) always on since 0.1.25; --family when the model was chosen by hand.
/// </summary>
public sealed class IwxRadioBackend : IRadioBackend
{
    public RadioBackendKind Kind => RadioBackendKind.Iwx;
    public string ExeName => "nekodrop-radio.exe";

    public IReadOnlyList<string> BuildArgs(RadioStart s)
    {
        var args = new List<string> { s.Channel.ToString(), "--width", s.Width.ToString() };
        if (s.Kernel) args.Add("--kernel");
        if (!string.IsNullOrEmpty(s.Country)) args.AddRange(["--country", s.Country]);
        if (s.StaConf is not null) args.AddRange(["--sta-config", s.StaConf]);
        var caps = s.Profile.Capabilities;
        if (!s.Kernel && caps.SupportsFastSend) args.AddRange(["--tx-window", "64"]);
        if (s.Aggregate && !s.Kernel && caps.SupportsAggregate) args.Add("--aggregate");
        // The firmware scan and country notice it needs are the user-mode Intel radio's,
        // the radio that also runs the Wi-Fi station; not with nekodrop-wlan.sys.
        if (s.FastUnlock && !s.Kernel && caps.SupportsConcurrentWifi) args.Add("--fast-unlock");
        // Only the user-mode Intel radio runs the station whose channel the plan names.
        if (s.CoexPlan && !s.Kernel && caps.SupportsConcurrentWifi) args.Add("--coex-plan");
        // Balanced Wi-Fi/Bluetooth arbitration in the firmware the user-mode radio boots;
        // nekodrop-wlan.sys keeps its own.
        if (s.BtCoexBalanced && !s.Kernel) args.AddRange(["--bt-coex", "1"]);
        if (s.HighThroughput && !s.Kernel && caps.SupportsAggregate) args.Add("--he80");
        if (!s.Kernel && s.Profile.RadioFamily is { Length: > 0 } family) args.AddRange(["--family", family]);
        return args;
    }
}

/// <summary>
/// Realtek RTL8852CE: winawdl's radio (winawdl_radio.exe on raph559/devourer's
/// Windows PCIe backend), shipped as nekodrop-radio-rtl.exe. Monitor and
/// inject only, no station: CardCatalog runs it on demand.
/// </summary>
public sealed class DevourerRadioBackend : IRadioBackend
{
    public RadioBackendKind Kind => RadioBackendKind.Devourer;
    public string ExeName => "nekodrop-radio-rtl.exe";

    public IReadOnlyList<string> BuildArgs(RadioStart s) => [s.Channel.ToString(), "--width", s.Width.ToString()];
}

/// <summary>
/// Realtek RTL8821CU (USB dongle): the same winawdl radio as the RTL8852CE, but
/// over devourer's libusb transport instead of the PCIe register proxy,
/// shipped as nekodrop-radio-usb.exe. Monitor and inject only, no station, and
/// the dongle is never given back (CardCatalog: HandsBackCard false). The
/// dongle's own id goes to the daemon, which then needs no bus scan.
///
/// Width: 20 MHz. devourer's 8821C path has a degraded 40 MHz mode that only a
/// USB replug clears (measured on the reference implementation, DropBridge, with
/// this chip), and 20 MHz measured slightly faster there too.
/// </summary>
public sealed class RtlUsbRadioBackend : IRadioBackend
{
    public RadioBackendKind Kind => RadioBackendKind.RtlUsb;
    public string ExeName => "nekodrop-radio-usb.exe";

    public IReadOnlyList<string> BuildArgs(RadioStart s) =>
    [
        s.Channel.ToString(), "--width", "20",
        "--usb", $"0bda:{s.Profile.DeviceId.ToLowerInvariant()}",
    ];
}

/// <summary>
/// MediaTek MT7902: nekodrop-radio-mt.exe (mtradio/, ported from Linux mt76).
/// Takes the country for the firmware's channel domain and, in Concurrent
/// mode, the station config: its host-side station joins 5 GHz networks and
/// shares the card's one channel with AWDL. None of the Intel-only options.
/// </summary>
public sealed class Mt76RadioBackend : IRadioBackend
{
    public RadioBackendKind Kind => RadioBackendKind.Mt76;
    public string ExeName => "nekodrop-radio-mt.exe";

    public IReadOnlyList<string> BuildArgs(RadioStart s)
    {
        var args = new List<string> { s.Channel.ToString(), "--width", s.Width.ToString() };
        if (s.Country is { Length: 2 } c && c != "ZZ" && c != "00") args.AddRange(["--country", c]);
        if (s.StaConf is not null) args.AddRange(["--sta-config", s.StaConf]);
        return args;
    }
}

/// <summary>
/// MediaTek MT7922 / MT7921: nekodrop-radio-mtk.exe (mtkradio/).
/// Takes --country when known and, in Concurrent mode, --sta-config: its
/// host-side station joins 5 GHz networks and time-shares the card's single
/// channel with AWDL. None of the Intel-only options.
/// </summary>
public sealed class MtkRadioBackend : IRadioBackend
{
    public RadioBackendKind Kind => RadioBackendKind.MtkRadio;
    public string ExeName => "nekodrop-radio-mtk.exe";

    public IReadOnlyList<string> BuildArgs(RadioStart s)
    {
        var args = new List<string> { s.Channel.ToString(), "--width", s.Width.ToString() };
        if (s.Country is { Length: 2 } c && c != "ZZ" && c != "00") args.AddRange(["--country", c]);
        if (s.StaConf is not null) args.AddRange(["--sta-config", s.StaConf]);
        if (s.HighThroughput) args.Add("--he80");
        return args;
    }
}
