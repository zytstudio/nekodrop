// SPDX-License-Identifier: GPL-2.0-only
namespace NekoDrop.Service;

/// <summary>Which user-mode radio drives a card family.</summary>
public enum RadioBackendKind
{
    /// <summary>nekodrop-radio: the Intel 22000 / AX210 driver ported from ForbiddenItlwm (iwxradio).</summary>
    Iwx,
    /// <summary>winawdl's devourer (Realtek RTL8852CE): monitor and inject only, no station.</summary>
    Devourer,
    /// <summary>nekodrop-radio-usb: the same winawdl radio over devourer's libusb transport, for the
    /// Realtek RTL8821CU USB dongle (monitor and inject only, no station).</summary>
    RtlUsb,
    /// <summary>nekodrop-radio-mt: the MediaTek MT7902 driver ported from Linux mt76 (mtradio/): sniffer, inject,
    /// AWDL peer stations, and a 5 GHz Wi-Fi station on the host (the card moves between the router and AWDL).</summary>
    Mt76,
    /// <summary>nekodrop-radio-mtk: the MediaTek MT7922 / MT7921 user-mode driver (mtkradio/):
    /// AWDL monitor/inject and a 5 GHz Wi-Fi station on the host (experimental Concurrent mode,
    /// time-sharing the card's single channel with AWDL).</summary>
    MtkRadio,
}

/// <summary>Which bus a card sits on: a PCIe device the register proxy maps, or a USB device libusb drives.</summary>
public enum AdapterBus
{
    Pci,
    Usb,
}

/// <summary>
/// What a card family can do in nekodrop. The service asks these instead of
/// assuming Intel, so a card that cannot keep Wi-Fi beside AirDrop (no station
/// in its radio) runs on demand, and radio options it lacks are never passed.
/// </summary>
/// <param name="SupportsConcurrentWifi">the radio runs a Wi-Fi station beside AWDL (mode Concurrent)</param>
/// <param name="SupportsFastSend">the radio takes --tx-window (experimental faster sending)</param>
/// <param name="SupportsAggregate">the radio takes --aggregate (A-MPDU sending, always on since 0.1.35)</param>
/// <param name="SupportsKernelDriver">nekodrop-wlan.sys can own the card (Windows' Wi-Fi and AWDL on one driver)</param>
/// <param name="MinBarBytes">the smallest register BAR the register proxy must map (driver/regproxy MIN_BAR_LEN)</param>
/// <param name="StationOn24GHz">the radio's station joins 2.4 GHz networks too; without it a dual-band
/// network is joined at its 5 GHz access point</param>
/// <param name="HandsBackCard">the service gives the card back to the vendor's driver when AirDrop is
/// off; false for a USB dongle the user dedicated to nekodrop (restore/uninstall still returns it)</param>
public sealed record AdapterCapabilities(bool SupportsConcurrentWifi, bool SupportsFastSend, bool SupportsAggregate,
                                         bool SupportsKernelDriver, uint MinBarBytes, bool StationOn24GHz = true,
                                         bool HandsBackCard = true)
{
    /// <summary>
    /// The Intel cards nekodrop runs today. Also what the service assumes before
    /// it has seen a card, so a missing or unreadable card behaves as before.
    /// </summary>
    public static readonly AdapterCapabilities IntelDefault = new(true, true, true, true, 0x2000);
}

/// <summary>
/// One PCI device nekodrop knows: who makes it, which radio drives it, what it
/// can do, which register-proxy INF takes it, and how the vendor's own driver
/// is told apart from the proxy when the card is given back.
/// </summary>
/// <param name="VendorId">PCI vendor ID, four upper-case hex digits ("8086")</param>
/// <param name="DeviceId">PCI device ID, four upper-case hex digits ("43F0")</param>
/// <param name="VendorName">for logs and messages ("Intel's INF is not known")</param>
/// <param name="FamilyName">the chip family, for logs and --status ("AX200")</param>
/// <param name="Backend">which user-mode radio drives it</param>
/// <param name="Capabilities">what the service may ask of it (mode, radio options, kernel driver, BAR)</param>
/// <param name="ProxyInfName">the register proxy's INF in the install folder's driver\ directory</param>
/// <param name="ProxyService">the service a card bound to the proxy runs under</param>
/// <param name="ProxyProvider">the Provider in the proxy's INF: how it is told apart once Windows renamed it oemNN.inf</param>
/// <param name="VendorProviderPatterns">substrings of the vendor driver's ProviderName (OEM repackages included)</param>
/// <param name="Active">false: listed for diagnostics and the self-test only, never taken</param>
/// <param name="Bus">which bus the card is on: PCIe (register proxy) or USB (libusb over WinUSB)</param>
/// <param name="BindId">the hardware ID the driver package binds, when that is not the generic
/// one: a composite USB dongle's Wi-Fi function ("USB\VID_0BDA&amp;PID_C820&amp;MI_02"), never its
/// Bluetooth sibling or the composite parent</param>
public sealed record AdapterProfile(string VendorId, string DeviceId, string VendorName, string FamilyName,
                                    RadioBackendKind Backend, AdapterCapabilities Capabilities,
                                    string ProxyInfName, string ProxyService, string ProxyProvider,
                                    string[] VendorProviderPatterns, bool Active, string? RadioFamily = null,
                                    AdapterBus Bus = AdapterBus.Pci, string? BindId = null)
{
    /// <summary>The hardware ID that identifies the device (PCI or USB, without a function).</summary>
    public string HardwareId => Bus == AdapterBus.Usb
        ? $"USB\\VID_{VendorId}&PID_{DeviceId}"
        : $"PCI\\VEN_{VendorId}&DEV_{DeviceId}";

    /// <summary>The hardware ID a driver is bound to (UpdateDriverForPlugAndPlayDevices).</summary>
    public string BindTarget => BindId ?? HardwareId;

    /// <summary>The proxy INF's name without extension, as found inside a renamed oemNN.inf (issue #12).</summary>
    public string ProxyInfStem => Path.GetFileNameWithoutExtension(ProxyInfName);
}

/// <summary>
/// The service's single list of Wi-Fi cards and what each can do. Pure data and
/// logic (no SetupAPI, registry or files), so `NekoDropService --selftest` checks
/// it on a build machine without a card or administrator rights.
///
/// Keep the active Intel IDs in step with `kDeviceIds` in iwxradio/src/cards.h,
/// the register proxy's INF, `$SupportedIntelIds` in installer/report.ps1 and the
/// check in installer/install.ps1 (docs/HARDWARE.md).
/// </summary>
public static class CardCatalog
{
    // nekodrop's one register proxy (driver/regproxy): selects the largest
    // memory BAR (>= 8 KiB) so it covers both Intel (8 KiB BAR0) and
    // Realtek RTL8852CE (1 MiB BAR2).
    const string ProxyInf = "winawdl_regproxy.inf";
    const string ProxyService = "WUDFRd";
    const string ProxyProvider = "winairdrop project";
    // The USB dongle's driver: Microsoft's in-box WinUSB, bound through
    // driver/winusb's INF, because libusb (devourer) talks to the chip itself.
    // There is no BAR to map and no reflector service.
    const string WinUsbInf = "nekodrop_winusb.inf";
    const string WinUsbService = "WINUSB";
    // Killer (Rivet Networks) cards are Intel chips with Intel's driver repackaged.
    static readonly string[] IntelProviders = ["Intel", "Killer", "Rivet Networks"];
    // Intel BE200 (Bz/Gl, Wi-Fi 7): experimental MLD station (Concurrent &
    // on-demand, 2.4/5 GHz), no A-MPDU, no fast-send window, no kernel driver.
    static readonly AdapterCapabilities Be200Caps = new(true, false, false, false, 0x2000);

    /* The card completes no frame that waits for an acknowledgement on 2.4 GHz
     * (mtradio's --test-kinds), and a station's every frame does: 5 GHz only. */
    static readonly AdapterCapabilities MediaTekCaps = new(true, false, false, false, 0x10000, StationOn24GHz: false);
    static readonly string[] MediaTekProviders = ["MediaTek"];
    /* Same Connac2 / mt7921 family as MT7902: 2.4 GHz ACKed TX is unverified on
     * MT7922, so Concurrent Wi-Fi stays 5 GHz only. MT7921 (7961 / RZ608) runs
     * On-Demand only until verified safe across Windows reboots (#72): Windows
     * keeps the vendor driver at boot and when idle, and Dispose() always hands
     * the card back on shutdown. */
    static readonly AdapterCapabilities MtkRadioCaps = new(true, false, false, false, 0x100000, StationOn24GHz: false);
    static readonly AdapterCapabilities MtkRadioOnDemandCaps = new(false, false, false, false, 0x100000, StationOn24GHz: false);
    static readonly string[] MtkRadioProviders = ["MediaTek", "AMD"];

    /* The RTL8821CU is a USB dongle: libusb over WinUSB, so no register BAR
     * (MinBarBytes is unused), no station, and no handing the card back — the
     * user dedicated it to nekodrop, which binds it to WinUSB at the first take
     * and keeps it until restore/uninstall puts Realtek's driver back. */
    static readonly AdapterCapabilities RtlUsbCaps =
        new(false, false, false, false, 0x1000, StationOn24GHz: false, HandsBackCard: false);

    /// <summary>USB profiles: the dongle's Wi-Fi function, its radio, and WinUSB's INF/service.</summary>
    static AdapterProfile RtlUsb(string device) =>
        new("0BDA", device, "Realtek", "RTL8821CU (USB, experimental)", RadioBackendKind.RtlUsb, RtlUsbCaps,
            WinUsbInf, WinUsbService, ProxyProvider, ["Realtek"], Active: true, Bus: AdapterBus.Usb,
            BindId: $"USB\\VID_0BDA&PID_{device}&MI_02");

    static AdapterProfile Intel(string device, string family) =>
        new("8086", device, "Intel", family, RadioBackendKind.Iwx, AdapterCapabilities.IntelDefault,
            ProxyInf, ProxyService, ProxyProvider, IntelProviders, Active: true);

    /// <summary>Every card listed, taken or not.</summary>
    public static readonly IReadOnlyList<AdapterProfile> AllProfiles =
    [
        // Qu/QuZ CNVi: AX201, 9560 class.
        Intel("43F0", "AX201 / 9560 (Qu/QuZ)"), Intel("A0F0", "AX201 / 9560 (Qu/QuZ)"),
        Intel("02F0", "AX201 / 9560 (Qu/QuZ)"), Intel("06F0", "AX201 / 9560 (Qu/QuZ)"),
        Intel("34F0", "AX201 / 9560 (Qu/QuZ)"), Intel("3DF0", "AX201 / 9560 (Qu/QuZ)"),
        Intel("4DF0", "AX201 / 9560 (Qu/QuZ)"),
        Intel("2723", "AX200"),
        // The AX210 family (Ty/So): AX210, AX211, AX411.
        Intel("2725", "AX210 / AX211 / AX411"), Intel("7A70", "AX210 / AX211 / AX411"),
        Intel("7AF0", "AX210 / AX211 / AX411"), Intel("51F0", "AX210 / AX211 / AX411"),
        Intel("51F1", "AX210 / AX211 / AX411"), Intel("54F0", "AX210 / AX211 / AX411"),
        Intel("7F70", "AX210 / AX211 / AX411"),
        // Intel BE200 (Bz/Gl, Wi-Fi 7): experimental, untested on hardware; taken like
        // the other cards (the maintainer's call: restore gives the card back in one
        // step). Concurrent & on-demand, and --family be200 picks the Bz/MLD path in iwxradio.
        new AdapterProfile("8086", "272B", "Intel", "BE200 (experimental)", RadioBackendKind.Iwx, Be200Caps,
            ProxyInf, ProxyService, ProxyProvider, IntelProviders, Active: true, RadioFamily: "be200"),
        // Built-in on-demand backend (winawdl's devourer, nekodrop-radio-rtl.exe):
        // monitor and inject only (no station, so Concurrent runs OnDemand), and
        // its registers sit in a 1 MiB BAR (>= 64 KiB).
        new AdapterProfile("10EC", "C852", "Realtek", "RTL8852CE", RadioBackendKind.Devourer,
            new AdapterCapabilities(false, false, false, false, 0x10000),
            ProxyInf, ProxyService, ProxyProvider, ["Realtek"], Active: true),
        // Realtek RTL8821CU (USB, 1T1R + BT): the same winawdl radio as the
        // RTL8852CE, over devourer's libusb transport (nekodrop-radio-usb.exe)
        // instead of the register proxy. Taken once, kept: HandsBackCard is
        // false (see RtlUsbCaps). driver\winusb's INF lists these two IDs.
        RtlUsb("C820"), RtlUsb("C821"),
        // MediaTek MT7902 (nekodrop-radio-mt.exe, ported from Linux mt76/mt7921):
        // Concurrent with a 5 GHz network (the radio's host-side station shares the
        // card's one channel with AWDL); 1 MiB BAR0.
        new AdapterProfile("14C3", "7902", "MediaTek", "MT7902", RadioBackendKind.Mt76, MediaTekCaps,
            ProxyInf, ProxyService, ProxyProvider, MediaTekProviders, Active: true),
        // MediaTek MT7922 / MT7921 (nekodrop-radio-mtk.exe, mtkradio/):
        // Concurrent with a 5 GHz network (experimental, host-side station shares
        // the card's one channel with AWDL) & On-Demand; 1 MiB BAR0.
        new AdapterProfile("14C3", "0616", "MediaTek", "MT7922 (RZ616)", RadioBackendKind.MtkRadio, MtkRadioCaps,
            ProxyInf, ProxyService, ProxyProvider, MtkRadioProviders, Active: true),
        new AdapterProfile("14C3", "7922", "MediaTek", "MT7922", RadioBackendKind.MtkRadio, MtkRadioCaps,
            ProxyInf, ProxyService, ProxyProvider, MtkRadioProviders, Active: true),
        new AdapterProfile("14C3", "7961", "MediaTek", "MT7921", RadioBackendKind.MtkRadio, MtkRadioOnDemandCaps,
            ProxyInf, ProxyService, ProxyProvider, MtkRadioProviders, Active: true),
        new AdapterProfile("14C3", "0608", "MediaTek", "MT7921 (RZ608)", RadioBackendKind.MtkRadio, MtkRadioOnDemandCaps,
            ProxyInf, ProxyService, ProxyProvider, MtkRadioProviders, Active: true),
    ];

    /// <summary>The cards the service takes.</summary>
    public static readonly IReadOnlyList<AdapterProfile> ActiveProfiles = AllProfiles.Where(p => p.Active).ToArray();

    /// <summary>
    /// Reads the bus, vendor and device IDs from a PnP instance or hardware ID
    /// ("PCI\VEN_8086&amp;DEV_43F0&amp;SUBSYS_00748086&amp;REV_00\3&amp;11583659&amp;0&amp;A3",
    /// "USB\VID_0BDA&amp;PID_C820&amp;REV_0200&amp;MI_02\B&amp;1D92DF5B&amp;0&amp;0002"), in any
    /// case. The device ID must end at '&amp;', '\' or the end, so "DEV_43F01" is not
    /// "DEV_43F0" and "PID_C8201" is not "PID_C820".
    /// </summary>
    public static bool TryParseId(string instanceId, out AdapterBus bus, out string vendorId, out string deviceId)
    {
        var s = instanceId ?? "";
        bus = AdapterBus.Pci;
        if (ParseIds(s, "PCI\\VEN_", "&DEV_", out vendorId, out deviceId)) return true;
        if (!ParseIds(s, "USB\\VID_", "&PID_", out vendorId, out deviceId)) return false;
        bus = AdapterBus.Usb;
        return true;
    }

    static bool ParseIds(string s, string vendorPrefix, string deviceMarker, out string vendorId, out string deviceId)
    {
        vendorId = deviceId = "";
        var marker = vendorPrefix.Length + 4;
        if (s.Length < marker + deviceMarker.Length + 4 || !s.StartsWith(vendorPrefix, StringComparison.OrdinalIgnoreCase))
            return false;
        var v = s.Substring(vendorPrefix.Length, 4);
        if (!IsHex4(v) || string.Compare(s, marker, deviceMarker, 0, deviceMarker.Length, StringComparison.OrdinalIgnoreCase) != 0)
            return false;
        var at = marker + deviceMarker.Length;
        var d = s.Substring(at, 4);
        if (!IsHex4(d)) return false;
        if (s.Length > at + 4 && s[at + 4] is not ('&' or '\\')) return false;
        vendorId = v.ToUpperInvariant();
        deviceId = d.ToUpperInvariant();
        return true;
    }

    /// <summary>The PCI half of <see cref="TryParseId"/> (a USB ID is not a PCI ID).</summary>
    public static bool TryParsePciId(string instanceId, out string vendorId, out string deviceId) =>
        TryParseId(instanceId, out var bus, out vendorId, out deviceId) && bus == AdapterBus.Pci;

    /// <summary>
    /// Whether an instance ID names a USB function of a composite device
    /// ("USB\VID_0BDA&amp;PID_C820&amp;MI_02\...") rather than the device node a driver
    /// binds to ("USB\VID_0BDA&amp;PID_C820\..."). The dongle's WinUSB package is bound
    /// to the device, and that node is the one whose state says whether it is taken.
    /// </summary>
    public static bool IsUsbFunction(string instanceId)
    {
        var s = instanceId ?? "";
        const string prefix = "USB\\VID_";
        const string marker = "&PID_";
        var at = prefix.Length + 4 + marker.Length + 4;
        return s.Length > at && s.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
               string.Compare(s, prefix.Length + 4, marker, 0, marker.Length, StringComparison.OrdinalIgnoreCase) == 0 &&
               s[at] == '&';
    }

    static bool IsHex4(string s) => s.Length == 4 && s.All(Uri.IsHexDigit);

    /// <summary>The profile of a card the service takes, or null (unknown, Ethernet, or listed but not active).</summary>
    public static AdapterProfile? MatchActive(string instanceId) => Classify(instanceId) is { Active: true } p ? p : null;

    /// <summary>
    /// Any listed profile, active or not (diagnostics and the self-test). A profile
    /// bound to one USB function matches only that function's node: the dongle's
    /// Bluetooth sibling (MI_00/01) and its composite parent are not the card.
    /// </summary>
    public static AdapterProfile? Classify(string instanceId)
    {
        if (!TryParseId(instanceId, out var bus, out var v, out var d)) return null;
        var profile = AllProfiles.FirstOrDefault(p => p.Bus == bus && p.VendorId == v && p.DeviceId == d);
        if (profile?.BindId is { } bind && !instanceId.StartsWith(bind, StringComparison.OrdinalIgnoreCase))
            return null;
        return profile;
    }

    /// <summary>
    /// The mode the card can run: one whose radio has no station cannot keep
    /// Wi-Fi beside AirDrop, so Concurrent becomes OnDemand (Windows keeps
    /// Wi-Fi, the card is taken only for AirDrop). Every Intel card supports
    /// Concurrent, so for them this is the requested mode unchanged.
    /// </summary>
    public static NetMode EffectiveMode(NetMode requested, AdapterCapabilities caps) =>
        requested == NetMode.Concurrent && !caps.SupportsConcurrentWifi ? NetMode.OnDemand : requested;

    /// <summary>Executable name under radio\ and arguments for launching a card's radio daemon.</summary>
    public sealed record RadioLaunch(string ExeName, IReadOnlyList<string> Args);

    /// <summary>The radio daemon and its arguments for a card: its backend's (RadioBackends.cs).</summary>
    public static RadioLaunch BuildRadioLaunch(
        AdapterProfile profile, int channel, bool kernel,
        string country, string? staConf, bool aggregate, bool fastUnlock, bool coexPlan = false,
        bool btCoexBalanced = false, bool highThroughput = false)
    {
        var backend = RadioBackends.Get(profile.Backend);
        return new RadioLaunch(backend.ExeName,
            backend.BuildArgs(new RadioStart(profile, channel, kernel, country, staConf, aggregate, fastUnlock, coexPlan,
                                             btCoexBalanced, highThroughput)));
    }

    /// <summary>One model the user can pick when a card is not recognized by its ID.</summary>
    /// <param name="Key">stored in service.json and passed to the radio as --family (Intel)</param>
    public sealed record ManualModel(string Key, string Name, string VendorId, RadioBackendKind Backend,
                                     AdapterCapabilities Capabilities, string[] VendorProviderPatterns);

    static readonly AdapterCapabilities RealtekCaps = new(false, false, false, false, 0x10000);

    /// <summary>
    /// The models a card can be run as by hand (Settings, "Wi-Fi card"): each
    /// backend's families. The Intel keys are the radio's --family names
    /// (iwxradio/src/cards.h family_device).
    /// </summary>
    public static readonly IReadOnlyList<ManualModel> ManualModels =
    [
        new("qu", "Intel AX201 / 9560 (Qu, CNVi)", "8086", RadioBackendKind.Iwx, AdapterCapabilities.IntelDefault, IntelProviders),
        new("ax200", "Intel AX200", "8086", RadioBackendKind.Iwx, AdapterCapabilities.IntelDefault, IntelProviders),
        new("ax210", "Intel AX210 (discrete)", "8086", RadioBackendKind.Iwx, AdapterCapabilities.IntelDefault, IntelProviders),
        new("so", "Intel AX211 / AX411 (So, CNVi)", "8086", RadioBackendKind.Iwx, AdapterCapabilities.IntelDefault, IntelProviders),
        new("be200", "Intel BE200 (experimental)", "8086", RadioBackendKind.Iwx, Be200Caps, IntelProviders),
        new("rtl8852ce", "Realtek RTL8852CE", "10EC", RadioBackendKind.Devourer, RealtekCaps, ["Realtek"]),
        new("rtl8821cu", "Realtek RTL8821CU (USB, experimental)", "0BDA", RadioBackendKind.RtlUsb, RtlUsbCaps, ["Realtek"]),
        new("mt7902", "MediaTek MT7902", "14C3", RadioBackendKind.Mt76, MediaTekCaps, MediaTekProviders),
        new("mt7922", "MediaTek MT7922 / MT7921 (RZ616 / RZ608)", "14C3", RadioBackendKind.MtkRadio, MtkRadioCaps, MtkRadioProviders),
    ];

    /// <summary>
    /// A profile for a card the user matched to a model by hand, or null when
    /// the model is unknown, the card's vendor is not the model's, or the card is
    /// not on the bus the model's radio drives (a USB dongle as an Intel model).
    /// </summary>
    public static AdapterProfile? ManualProfile(string instanceOrHardwareId, string modelKey)
    {
        if (!TryParseId(instanceOrHardwareId, out var bus, out var v, out var d)) return null;
        var m = ManualModels.FirstOrDefault(x => x.Key == modelKey);
        if (m is null || m.VendorId != v) return null;
        if ((m.Backend == RadioBackendKind.RtlUsb ? AdapterBus.Usb : AdapterBus.Pci) != bus) return null;
        var usb = bus == AdapterBus.Usb;
        return new AdapterProfile(v, d, v switch { "8086" => "Intel", "14C3" => "MediaTek", _ => "Realtek" }, m.Name + " (chosen in settings)", m.Backend,
                                  m.Capabilities, usb ? WinUsbInf : ProxyInf, usb ? WinUsbService : ProxyService, ProxyProvider,
                                  m.VendorProviderPatterns,
                                  Active: true, RadioFamily: m.Backend == RadioBackendKind.Iwx ? m.Key : null, Bus: bus,
                                  BindId: usb ? $"USB\\VID_{v}&PID_{d}&MI_02" : null);
    }

    /// <summary>
    /// Whether a bound driver's provider is the card vendor's own driver: never
    /// the register proxy, otherwise any of the vendor's provider names.
    /// </summary>
    public static bool IsVendorProviderMatch(AdapterProfile profile, string provider)
    {
        if (string.IsNullOrWhiteSpace(provider)) return false;
        if (string.Equals(provider.Trim(), profile.ProxyProvider, StringComparison.OrdinalIgnoreCase)) return false;
        return profile.VendorProviderPatterns.Any(p => provider.Contains(p, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Offline checks of the list and the functions above; returns the failures (empty: all passed).</summary>
    public static IReadOnlyList<string> SelfTest()
    {
        var fail = new List<string>();
        void Check(bool ok, string what) { if (!ok) fail.Add(what); }

        // The 15 Intel IDs the service took before the catalog (Card.DeviceIds, 0.1.20)
        // plus Realtek RTL8852CE (10EC:C852), the Realtek RTL8821CU USB dongle
        // (0BDA:C820, C821), MediaTek MT7902 (14C3:7902), and MediaTek
        // MT7922/MT7921 (14C3:0616, 7922, 7961, 0608) = 24 active profiles.
        string[] intel = ["43F0", "A0F0", "02F0", "06F0", "34F0", "3DF0", "4DF0",
                          "2723", "2725", "7A70", "7AF0", "51F0", "51F1", "54F0", "7F70"];
        Check(ActiveProfiles.Count == intel.Length + 9, $"{ActiveProfiles.Count} active profiles, expected {intel.Length + 9}");
        Check(AllProfiles.Count == ActiveProfiles.Count, $"{AllProfiles.Count} total profiles, expected {ActiveProfiles.Count}");
        foreach (var dev in intel)
        {
            var id = $"PCI\\VEN_8086&DEV_{dev}&SUBSYS_00748086&REV_00\\3&11583659&0&A3";
            var p = MatchActive(id);
            if (p is null) { fail.Add($"8086:{dev} is not taken"); continue; }
            Check(p.HardwareId == $"PCI\\VEN_8086&DEV_{dev}", $"8086:{dev} hardware ID {p.HardwareId}");
            Check(p.VendorName == "Intel" && p.Backend == RadioBackendKind.Iwx, $"8086:{dev} vendor {p.VendorName} backend {p.Backend}");
            Check(p.Capabilities == AdapterCapabilities.IntelDefault, $"8086:{dev} capabilities {p.Capabilities}");
            Check(p.Capabilities.MinBarBytes == 0x2000, $"8086:{dev} BAR {p.Capabilities.MinBarBytes:x}");
            Check(p.ProxyInfName == "winawdl_regproxy.inf" && p.ProxyInfStem == "winawdl_regproxy",
                  $"8086:{dev} proxy INF {p.ProxyInfName}");
            Check(p.ProxyService == "WUDFRd" && p.ProxyProvider == "winairdrop project", $"8086:{dev} proxy service/provider");
            foreach (var m in Enum.GetValues<NetMode>())
                Check(EffectiveMode(m, p.Capabilities) == m, $"8086:{dev} mode {m} became {EffectiveMode(m, p.Capabilities)}");
        }

        // Parsing: case, boundaries, other buses.
        Check(TryParsePciId("pci\\ven_8086&dev_43f0&subsys_00748086\\3&1", out var v1, out var d1) && v1 == "8086" && d1 == "43F0",
              "lower-case instance ID not parsed");
        Check(MatchActive("pci\\ven_8086&dev_43f0&subsys_00748086\\3&1") is not null, "lower-case instance ID not taken");
        Check(TryParsePciId("PCI\\VEN_8086&DEV_43F0", out _, out _), "bare hardware ID not parsed");
        Check(TryParsePciId("PCI\\VEN_8086&DEV_43F0\\3&1", out _, out _), "ID ending in '\\' not parsed");
        Check(!TryParsePciId("PCI\\VEN_8086&DEV_43F01&SUBSYS_0", out _, out _), "five-digit device ID parsed");
        Check(!TryParsePciId("PCI\\VEN_8086&DEV_43F", out _, out _), "three-digit device ID parsed");
        Check(!TryParsePciId("PCI\\VEN_80G6&DEV_43F0", out _, out _), "non-hex vendor ID parsed");
        Check(!TryParsePciId("PCI\\VEN_8086&SUBSYS_00748086", out _, out _), "ID without DEV_ parsed");
        Check(!TryParsePciId("USB\\VID_0BDA&PID_8812\\1", out _, out _), "USB ID parsed");
        Check(TryParseId("USB\\VID_0BDA&PID_8812\\1", out var bus1, out var uv1, out var ud1) &&
              bus1 == AdapterBus.Usb && uv1 == "0BDA" && ud1 == "8812", "USB ID not parsed by TryParseId");
        Check(TryParseId("USB\\VID_0BDA&PID_C820&REV_0200&MI_02\\B&1D92DF5B&0&0002", out var bus2, out _, out var ud2) &&
              bus2 == AdapterBus.Usb && ud2 == "C820", "USB function instance ID not parsed");
        Check(IsUsbFunction("USB\\VID_0BDA&PID_C820&REV_0200&MI_02\\B&1D92DF5B&0&0002"), "USB function not recognized");
        Check(!IsUsbFunction("USB\\VID_0BDA&PID_C820\\123456"), "USB device node taken for a function");
        Check(!TryParseId("USB\\VID_0BDA&PID_C8201\\1", out _, out _, out _), "five-digit USB product ID parsed");
        Check(TryParseId("PCI\\VEN_10EC&DEV_C852\\4&1", out var bus3, out _, out _) && bus3 == AdapterBus.Pci,
              "PCI ID not parsed by TryParseId");
        Check(!TryParsePciId("", out _, out _), "empty ID parsed");

        // Built-in Realtek RTL8852CE: active, Devourer backend, forced to on demand.
        const string rtl = "PCI\\VEN_10EC&DEV_C852&SUBSYS_C85210EC\\4&1";
        var r = MatchActive(rtl);
        if (r is null) fail.Add("10EC:C852 is not active");
        else
        {
            Check(Classify(rtl) == r, "10EC:C852 Classify and MatchActive disagree");
            Check(MatchActive("pci\\ven_10ec&dev_c852&subsys_c85210ec\\4&1") == r, "lower-case 10EC:C852 not taken");
            Check(r.HardwareId == "PCI\\VEN_10EC&DEV_C852", $"10EC:C852 hardware ID {r.HardwareId}");
            Check(r.VendorName == "Realtek" && r.Backend == RadioBackendKind.Devourer, $"10EC:C852 vendor {r.VendorName} backend {r.Backend}");
            Check(!r.Capabilities.SupportsConcurrentWifi && !r.Capabilities.SupportsFastSend &&
                  !r.Capabilities.SupportsAggregate && !r.Capabilities.SupportsKernelDriver, "10EC:C852 capabilities");
            Check(r.Capabilities.MinBarBytes == 0x10000, $"10EC:C852 BAR {r.Capabilities.MinBarBytes:x}");
            Check(EffectiveMode(NetMode.Concurrent, r.Capabilities) == NetMode.OnDemand, "10EC:C852 Concurrent not forced to OnDemand");
            Check(EffectiveMode(NetMode.OnDemand, r.Capabilities) == NetMode.OnDemand, "10EC:C852 OnDemand changed");
            Check(EffectiveMode(NetMode.Off, r.Capabilities) == NetMode.Off, "10EC:C852 Off changed");
            Check(IsVendorProviderMatch(r, "Realtek Semiconductor Corp."), "Realtek provider not matched");
            Check(!IsVendorProviderMatch(r, "Intel"), "Intel provider matched as Realtek's");
            Check(!IsVendorProviderMatch(r, "winairdrop project"), "proxy provider matched as Realtek's");
        }

        // Realtek RTL8821CU (0BDA:C820): a USB dongle driven by devourer over
        // libusb, bound on its Wi-Fi FUNCTION (MI_02) so the composite parent and
        // the Bluetooth function stay on their own drivers. Active, forced to on
        // demand, never handed back, launched on 149 with 20/40 MHz.
        foreach (var pid in new[] { "C820", "C821" })
        {
            var usbId = $"USB\\VID_0BDA&PID_{pid}&MI_02\\B&1D92DF5B&0&0002";
            var usb = MatchActive(usbId);
            if (usb is null) { fail.Add($"0BDA:{pid} is not active"); continue; }
            Check(Classify(usbId) == usb, $"0BDA:{pid} Classify and MatchActive disagree");
            Check(MatchActive($"usb\\vid_0bda&pid_{pid.ToLowerInvariant()}&mi_02\\b&1") == usb,
                  $"lower-case 0BDA:{pid} Wi-Fi function not taken");
            Check(usb.HardwareId == $"USB\\VID_0BDA&PID_{pid}", $"0BDA:{pid} hardware ID {usb.HardwareId}");
            Check(usb.BindTarget == $"USB\\VID_0BDA&PID_{pid}&MI_02", $"0BDA:{pid} bind target {usb.BindTarget}");
            // The composite parent and the Bluetooth function are not the card.
            Check(MatchActive($"USB\\VID_0BDA&PID_{pid}\\123456") is null, $"0BDA:{pid} composite parent taken");
            Check(MatchActive($"USB\\VID_0BDA&PID_{pid}&MI_00\\B&1") is null, $"0BDA:{pid} Bluetooth function taken");
            Check(usb.Bus == AdapterBus.Usb && usb.VendorName == "Realtek" && usb.Backend == RadioBackendKind.RtlUsb,
                  $"0BDA:{pid} bus {usb.Bus} vendor {usb.VendorName} backend {usb.Backend}");
            Check(!usb.Capabilities.SupportsConcurrentWifi && !usb.Capabilities.SupportsFastSend &&
                  !usb.Capabilities.SupportsAggregate && !usb.Capabilities.SupportsKernelDriver &&
                  !usb.Capabilities.StationOn24GHz && !usb.Capabilities.HandsBackCard,
                  $"0BDA:{pid} capabilities");
            Check(usb.ProxyInfName == "nekodrop_winusb.inf" && usb.ProxyService == "WINUSB" &&
                  usb.ProxyProvider == "winairdrop project", $"0BDA:{pid} driver package {usb.ProxyInfName}");
            Check(EffectiveMode(NetMode.Concurrent, usb.Capabilities) == NetMode.OnDemand,
                  $"0BDA:{pid} Concurrent not forced to OnDemand");
            Check(EffectiveMode(NetMode.OnDemand, usb.Capabilities) == NetMode.OnDemand, $"0BDA:{pid} OnDemand changed");
            Check(IsVendorProviderMatch(usb, "Realtek Semiconductor Corp."), $"0BDA:{pid} Realtek provider not matched");
            Check(!IsVendorProviderMatch(usb, "winairdrop project"), $"0BDA:{pid} proxy provider matched as Realtek's");
            Check(SameLaunch(BuildRadioLaunch(usb, 6, false, "JP", @"C:\run\sta.conf", true, true),
                             "nekodrop-radio-usb.exe", "6", "--width", "20", "--usb", $"0bda:{pid.ToLowerInvariant()}"),
                  $"0BDA:{pid} ch 6 launch args (all Intel flags stripped)");
            Check(SameLaunch(BuildRadioLaunch(usb, 149, false, "", null, false, false, btCoexBalanced: true),
                             "nekodrop-radio-usb.exe", "149", "--width", "20", "--usb", $"0bda:{pid.ToLowerInvariant()}"),
                  $"0BDA:{pid} ch 149 launch args (20 MHz)");
        }
        var musb = ManualProfile("USB\\VID_0BDA&PID_C820", "rtl8821cu");
        if (musb is null) fail.Add("manual rtl8821cu on a 0BDA dongle refused");
        else
        {
            Check(musb is { Backend: RadioBackendKind.RtlUsb, RadioFamily: null, Bus: AdapterBus.Usb } &&
                  musb.ProxyService == "WINUSB" && !musb.Capabilities.HandsBackCard &&
                  musb.BindTarget == "USB\\VID_0BDA&PID_C820&MI_02", "manual rtl8821cu profile");
        }
        Check(ManualProfile("USB\\VID_0BDA&PID_C820", "qu") is null, "an Intel model accepted for a USB dongle");
        Check(ManualProfile("PCI\\VEN_10EC&DEV_C852", "rtl8821cu") is null, "a USB model accepted for a PCIe card");

        // Radio launch planning for Intel (Iwx) and Realtek (Devourer).
        static bool SameLaunch(RadioLaunch got, string exe, params string[] args) =>
            got.ExeName == exe && got.Args.SequenceEqual(args);

        var iwx = ActiveProfiles[0];
        Check(iwx.Backend == RadioBackendKind.Iwx, $"ActiveProfiles[0] backend {iwx.Backend}, expected Iwx");
        Check(SameLaunch(BuildRadioLaunch(iwx, 6, false, "", null, false, false),
                         "nekodrop-radio.exe", "6", "--width", "20", "--tx-window", "64"),
              "Iwx ch 6 default launch args");
        Check(SameLaunch(BuildRadioLaunch(iwx, 149, false, "JP", @"C:\run\sta.conf", true, true),
                         "nekodrop-radio.exe", "149", "--width", "80", "--country", "JP",
                         "--sta-config", @"C:\run\sta.conf", "--tx-window", "64", "--aggregate", "--fast-unlock"),
              "Iwx full flags launch args");
        Check(SameLaunch(BuildRadioLaunch(iwx, 149, false, "", @"C:\run\sta.conf", false, false, true),
                         "nekodrop-radio.exe", "149", "--width", "80", "--sta-config", @"C:\run\sta.conf",
                         "--tx-window", "64", "--coex-plan"),
              "Iwx coexistence plan launch args");
        Check(SameLaunch(BuildRadioLaunch(iwx, 44, true, "US", null, true, true, true),
                         "nekodrop-radio.exe", "44", "--width", "80", "--kernel", "--country", "US"),
              "Iwx kernel mode must suppress the user-mode radio's options");
        Check(SameLaunch(BuildRadioLaunch(iwx, 149, false, "", null, false, false, btCoexBalanced: true),
                         "nekodrop-radio.exe", "149", "--width", "80", "--tx-window", "64", "--bt-coex", "1"),
              "Iwx balanced Bluetooth coexistence launch args");
        Check(SameLaunch(BuildRadioLaunch(iwx, 149, true, "", null, false, false, btCoexBalanced: true),
                         "nekodrop-radio.exe", "149", "--width", "80", "--kernel"),
              "Iwx kernel mode must suppress --bt-coex");
        Check(SameLaunch(BuildRadioLaunch(iwx, 149, false, "", null, true, false, highThroughput: true),
                         "nekodrop-radio.exe", "149", "--width", "80", "--tx-window", "64", "--aggregate", "--he80"),
              "Iwx high-throughput launch args");
        Check(SameLaunch(BuildRadioLaunch(iwx, 149, true, "", null, true, false, highThroughput: true),
                         "nekodrop-radio.exe", "149", "--width", "80", "--kernel"),
              "Iwx kernel mode must suppress --he80");
        if (r is not null)
        {
            Check(SameLaunch(BuildRadioLaunch(r, 6, true, "JP", @"C:\run\sta.conf", true, true),
                             "nekodrop-radio-rtl.exe", "6", "--width", "20"),
                  "Devourer ch 6 must strip all Intel flags");
            Check(SameLaunch(BuildRadioLaunch(r, 149, false, "", null, false, false, btCoexBalanced: true),
                             "nekodrop-radio-rtl.exe", "149", "--width", "80"),
                  "Devourer must not get --bt-coex");
            Check(SameLaunch(BuildRadioLaunch(r, 149, false, "", null, false, false),
                             "nekodrop-radio-rtl.exe", "149", "--width", "80"),
                  "Devourer ch 149 default launch args");
        }

        // Built-in MediaTek MT7902: active, Mt76 backend, Concurrent kept; the station
        // config and the country go to the radio, no Intel option does.
        var mt = MatchActive("PCI\\VEN_14C3&DEV_7902&SUBSYS_60401A3B&REV_00\\6&1");
        if (mt is null) fail.Add("14C3:7902 is not active");
        else
        {
            Check(mt.VendorName == "MediaTek" && mt.Backend == RadioBackendKind.Mt76, $"14C3:7902 vendor {mt.VendorName} backend {mt.Backend}");
            Check(mt.Capabilities.SupportsConcurrentWifi && !mt.Capabilities.SupportsFastSend &&
                  !mt.Capabilities.SupportsAggregate && !mt.Capabilities.SupportsKernelDriver &&
                  !mt.Capabilities.StationOn24GHz, "14C3:7902 capabilities");
            Check(AdapterCapabilities.IntelDefault.StationOn24GHz, "Intel station must keep 2.4 GHz");
            Check(EffectiveMode(NetMode.Concurrent, mt.Capabilities) == NetMode.Concurrent, "14C3:7902 Concurrent changed");
            Check(SameLaunch(BuildRadioLaunch(mt, 44, false, "JP", @"C:\run\sta.conf", true, true, true, true),
                             "nekodrop-radio-mt.exe", "44", "--width", "80", "--country", "JP", "--sta-config", @"C:\run\sta.conf"),
                  "Mt76 launch args with a station");
            Check(SameLaunch(BuildRadioLaunch(mt, 6, false, "", null, false, false),
                             "nekodrop-radio-mt.exe", "6", "--width", "20"),
                  "Mt76 ch 6 default launch args");
        }

        // Built-in MediaTek MT7922 / MT7921: active, MtkRadio backend, 1 MiB BAR.
        // MT7922 keeps Concurrent (5 GHz only); MT7921 (7961/0608) is forced to OnDemand (#72).
        foreach (var (dev, family, concurrent) in new[] { ("0616", "MT7922 (RZ616)", true), ("7922", "MT7922", true),
                                                          ("7961", "MT7921", false), ("0608", "MT7921 (RZ608)", false) })
        {
            var id = $"PCI\\VEN_14C3&DEV_{dev}&SUBSYS_E0CD1A3B&REV_00\\4&1";
            var mtk = MatchActive(id);
            if (mtk is null) { fail.Add($"14C3:{dev} is not active"); continue; }
            Check(Classify(id) == mtk, $"14C3:{dev} Classify and MatchActive disagree");
            Check(MatchActive($"pci\\ven_14c3&dev_{dev.ToLowerInvariant()}&subsys_e0cd1a3b\\4&1") == mtk,
                  $"lower-case 14C3:{dev} not taken");
            Check(mtk.HardwareId == $"PCI\\VEN_14C3&DEV_{dev}", $"14C3:{dev} hardware ID {mtk.HardwareId}");
            Check(mtk.VendorName == "MediaTek" && mtk.FamilyName == family && mtk.Backend == RadioBackendKind.MtkRadio,
                  $"14C3:{dev} vendor {mtk.VendorName} family {mtk.FamilyName} backend {mtk.Backend}");
            Check(mtk.Capabilities.SupportsConcurrentWifi == concurrent && !mtk.Capabilities.SupportsFastSend &&
                  !mtk.Capabilities.SupportsAggregate && !mtk.Capabilities.SupportsKernelDriver &&
                  !mtk.Capabilities.StationOn24GHz,
                  $"14C3:{dev} capabilities");
            Check(mtk.Capabilities.MinBarBytes == 0x100000, $"14C3:{dev} BAR {mtk.Capabilities.MinBarBytes:x}");
            Check(EffectiveMode(NetMode.Concurrent, mtk.Capabilities) == (concurrent ? NetMode.Concurrent : NetMode.OnDemand),
                  $"14C3:{dev} Concurrent mode mismatch");
            Check(EffectiveMode(NetMode.OnDemand, mtk.Capabilities) == NetMode.OnDemand, $"14C3:{dev} OnDemand changed");
            Check(EffectiveMode(NetMode.Off, mtk.Capabilities) == NetMode.Off, $"14C3:{dev} Off changed");
            Check(IsVendorProviderMatch(mtk, "MediaTek, Inc."), $"14C3:{dev} MediaTek provider not matched");
            Check(IsVendorProviderMatch(mtk, "AMD"), $"14C3:{dev} AMD provider not matched");
            Check(!IsVendorProviderMatch(mtk, "Intel"), $"14C3:{dev} Intel provider matched as MediaTek's");
            Check(!IsVendorProviderMatch(mtk, "winairdrop project"), $"14C3:{dev} proxy provider matched as MediaTek's");
            Check(SameLaunch(BuildRadioLaunch(mtk, 149, true, "JP", @"C:\run\sta.conf", true, true, true, true),
                             "nekodrop-radio-mtk.exe", "149", "--width", "80", "--country", "JP",
                             "--sta-config", @"C:\run\sta.conf"),
                  $"MtkRadio 14C3:{dev} ch 149 launch args with a station");
            Check(SameLaunch(BuildRadioLaunch(mtk, 6, false, "ZZ", null, false, false),
                             "nekodrop-radio-mtk.exe", "6", "--width", "20"),
                  $"MtkRadio 14C3:{dev} ch 6 launch args (ZZ omitted)");
            Check(SameLaunch(BuildRadioLaunch(mtk, 44, false, "00", null, false, false),
                             "nekodrop-radio-mtk.exe", "44", "--width", "80"),
                  $"MtkRadio 14C3:{dev} ch 44 launch args (00 omitted)");
            Check(SameLaunch(BuildRadioLaunch(mtk, 149, false, "JP", null, false, false, highThroughput: true),
                             "nekodrop-radio-mtk.exe", "149", "--width", "80", "--country", "JP", "--he80"),
                  $"MtkRadio 14C3:{dev} high-throughput launch args");
        }

        // Every backend kind, profile and manual model has a registered radio backend.
        foreach (var k in Enum.GetValues<RadioBackendKind>())
            Check(RadioBackends.Registered.Any(b => b.Kind == k), $"no radio backend registered for {k}");
        foreach (var bk in AllProfiles.Select(x => x.Backend).Concat(ManualModels.Select(x => x.Backend)).Distinct())
            Check(RadioBackends.Registered.Any(b => b.Kind == bk), $"profile backend {bk} has no radio backend");

        // Manual models: by vendor, Intel ones pass --family, Realtek none.
        var mq = ManualProfile("PCI\\VEN_8086&DEV_9999&SUBSYS_00748086\\3&1", "qu");
        if (mq is null) fail.Add("manual qu on 8086:9999 refused");
        else
        {
            Check(mq.HardwareId == "PCI\\VEN_8086&DEV_9999" && mq.Backend == RadioBackendKind.Iwx && mq.RadioFamily == "qu",
                  $"manual qu profile {mq.HardwareId} {mq.Backend} {mq.RadioFamily}");
            Check(SameLaunch(BuildRadioLaunch(mq, 6, false, "", null, false, false),
                             "nekodrop-radio.exe", "6", "--width", "20", "--tx-window", "64", "--family", "qu"),
                  "manual qu launch args");
        }
        var mr = ManualProfile("PCI\\VEN_10EC&DEV_C852", "rtl8852ce");
        Check(mr is { Backend: RadioBackendKind.Devourer, RadioFamily: null }, "manual rtl8852ce profile");
        var mm = ManualProfile("PCI\\VEN_14C3&DEV_7922", "mt7922");
        Check(mm is { Backend: RadioBackendKind.MtkRadio, RadioFamily: null }, "manual mt7922 profile");
        Check(ManualProfile("PCI\\VEN_10EC&DEV_C852", "qu") is null, "an Intel model accepted for a Realtek card");
        Check(ManualProfile("PCI\\VEN_10EC&DEV_C852", "be200") is null, "be200 model accepted for a Realtek card");
        Check(ManualProfile("PCI\\VEN_8086&DEV_2723", "nope") is null, "an unknown model accepted");
        Check(ManualProfile("USB\\VID_0BDA&PID_8812", "rtl8852ce") is null, "a USB device accepted");
        Check(ManualModels.Select(x => x.Key).Distinct().Count() == ManualModels.Count, "duplicate manual model keys");

        // Experimental Intel BE200 (8086:272B): active like the other cards, Concurrent & on demand, --family be200.
        const string be200 = "PCI\\VEN_8086&DEV_272B&SUBSYS_00F48086&REV_1A\\4&1";
        var be = MatchActive(be200);
        Check(be is { Active: true, Backend: RadioBackendKind.Iwx, VendorName: "Intel", RadioFamily: "be200" }, "8086:272B active profile");
        if (be is not null)
        {
            Check(be.Capabilities.SupportsConcurrentWifi && be.Capabilities.StationOn24GHz &&
                  !be.Capabilities.SupportsFastSend && !be.Capabilities.SupportsAggregate &&
                  !be.Capabilities.SupportsKernelDriver && be.Capabilities.MinBarBytes == 0x2000,
                  "8086:272B capabilities");
            Check(EffectiveMode(NetMode.Concurrent, be.Capabilities) == NetMode.Concurrent, "8086:272B Concurrent changed");
            Check(EffectiveMode(NetMode.OnDemand, be.Capabilities) == NetMode.OnDemand, "8086:272B OnDemand changed");
            Check(SameLaunch(BuildRadioLaunch(be, 6, false, "", null, true, false),
                             "nekodrop-radio.exe", "6", "--width", "20", "--family", "be200"),
                  "8086:272B on-demand launch args");
            Check(SameLaunch(BuildRadioLaunch(be, 149, false, "JP", @"C:\run\sta.conf", true, false),
                             "nekodrop-radio.exe", "149", "--width", "80", "--country", "JP",
                             "--sta-config", @"C:\run\sta.conf", "--family", "be200"),
                  "8086:272B concurrent launch args");
        }
        var mbe = ManualProfile(be200, "be200");
        if (mbe is null) fail.Add("manual be200 on 8086:272B refused");
        else
        {
            Check(mbe.Active && mbe.Backend == RadioBackendKind.Iwx && mbe.RadioFamily == "be200",
                  $"manual be200 profile {mbe.HardwareId} {mbe.Backend} {mbe.RadioFamily}");
            Check(mbe.Capabilities.SupportsConcurrentWifi && mbe.Capabilities.StationOn24GHz &&
                  !mbe.Capabilities.SupportsFastSend && !mbe.Capabilities.SupportsAggregate &&
                  !mbe.Capabilities.SupportsKernelDriver && mbe.Capabilities.MinBarBytes == 0x2000,
                  "manual be200 capabilities");
            Check(EffectiveMode(NetMode.Concurrent, mbe.Capabilities) == NetMode.Concurrent, "be200 Concurrent changed");
            Check(SameLaunch(BuildRadioLaunch(mbe, 149, false, "JP", @"C:\run\sta.conf", true, true, true, true),
                             "nekodrop-radio.exe", "149", "--width", "80", "--country", "JP",
                             "--sta-config", @"C:\run\sta.conf", "--fast-unlock", "--coex-plan",
                             "--bt-coex", "1", "--family", "be200"),
                  "manual be200 launch args");
        }

        // Ethernet chips from the same vendors and Wi-Fi cards nekodrop does not know.
        foreach (var other in new[] { "PCI\\VEN_8086&DEV_15F3&SUBSYS_00008086\\1", "PCI\\VEN_10EC&DEV_8168&SUBSYS_00000000\\1",
                                      "PCI\\VEN_14C3&DEV_7925&SUBSYS_00000000\\1", "PCI\\VEN_8086&DEV_7E40&SUBSYS_00908086\\1" })
        {
            Check(MatchActive(other) is null, $"{other} would be taken");
            Check(Classify(other) is null, $"{other} is classified");
        }

        // The vendor's driver is told from the proxy's, OEM repackages included.
        var i = ActiveProfiles[0];
        Check(!IsVendorProviderMatch(i, "winairdrop project"), "proxy provider matched as Intel's");
        Check(!IsVendorProviderMatch(i, "WinAirDrop Project"), "proxy provider (other case) matched as Intel's");
        Check(!IsVendorProviderMatch(i, ""), "empty provider matched");
        Check(IsVendorProviderMatch(i, "Intel"), "\"Intel\" not matched");
        Check(IsVendorProviderMatch(i, "Intel Corporation"), "\"Intel Corporation\" not matched");
        Check(IsVendorProviderMatch(i, "Killer"), "\"Killer\" not matched");
        Check(!IsVendorProviderMatch(i, "Realtek Semiconductor Corp."), "Realtek provider matched as Intel's");

        // The list itself.
        var dup = AllProfiles.GroupBy(p => p.VendorId + ":" + p.DeviceId).Where(g => g.Count() > 1).Select(g => g.Key).ToArray();
        Check(dup.Length == 0, "duplicate IDs: " + string.Join(", ", dup));
        foreach (var p in AllProfiles)
        {
            var key = $"{p.VendorId}:{p.DeviceId}";
            Check(IsHex4(p.VendorId) && p.VendorId == p.VendorId.ToUpperInvariant() &&
                  IsHex4(p.DeviceId) && p.DeviceId == p.DeviceId.ToUpperInvariant(), $"{key}: IDs must be four upper-case hex digits");
            Check(p.VendorName != "" && p.FamilyName != "" && p.ProxyInfName != "" && p.ProxyService != "" &&
                  p.ProxyProvider != "" && p.VendorProviderPatterns.Length > 0 && p.VendorProviderPatterns.All(s => s != ""),
                  $"{key}: empty field");
            Check(p.Capabilities.MinBarBytes > 0, $"{key}: no minimum BAR");
            Check(TryParseId(p.HardwareId, out var hv, out var hvid, out var hdid) && hv == p.Bus &&
                  hvid == p.VendorId && hdid == p.DeviceId,
                  $"{key}: hardware ID {p.HardwareId} does not parse back");
        }
        return fail;
    }
}
