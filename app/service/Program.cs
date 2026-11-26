// SPDX-License-Identifier: GPL-2.0-only
// NekoDropService: runs as LocalSystem, so taking the Wi-Fi card, locking DMA
// memory, creating the AWDL adapter and reading the Wi-Fi profile need no UAC.
using NekoDrop.Service;

// --selftest: checks the card catalog offline (no card, registry or administrator
// rights), so scripts\build-installer.ps1 runs it on the build machine.
if (args.Contains("--selftest"))
{
    var failures = CardCatalog.SelfTest();
    foreach (var f in failures) Console.Error.WriteLine("FAIL: " + f);
    Console.WriteLine(failures.Count == 0
        ? $"card catalog self-test passed ({CardCatalog.AllProfiles.Count} profiles, {CardCatalog.ActiveProfiles.Count} active)"
        : $"card catalog self-test: {failures.Count} failure(s)");
    Environment.ExitCode = failures.Count == 0 ? 0 : 1;
    return;
}

// The card the user matched to a model by hand, for every path below that looks for the card.
{
    var manual = ServiceConfig.Load();
    Card.Manual = (manual.ManualCard, manual.ManualModel);
}

// --give-back: hand the card to the vendor's driver (Intel's today) and exit (uninstall, recovery).
if (args.Contains("--give-back"))
{
    using var s = new Supervisor();
    s.Stop("--give-back", giveBack: true);
    // The process ends here: wait for the vendor driver's interface and restore in line.
    WlanBackup.Restore(Console.WriteLine, TimeSpan.FromSeconds(60));
    return;
}

// --status: what the service would work with (no keys are read or printed).
if (args.Contains("--status"))
{
    var card = Card.Find();
    // A USB dongle's instance ID ends in its serial (often its MAC): print the
    // hardware ID instead, as the service log does.
    var shown = card is null ? "" : card.Profile.Bus == AdapterBus.Usb ? card.Profile.HardwareId : card.InstanceId;
    Console.WriteLine(card is null ? "card: none found"
        : $"card: {shown}{Environment.NewLine}  driver service {card.Service}, INF {card.InfPath}, taken by nekodrop: {Card.TakenByProxy(card)}");
    if (card is not null)
    {
        var p = card.Profile;
        var c = p.Capabilities;
        Console.WriteLine($"  profile: {p.VendorName} {p.FamilyName} ({p.VendorId}:{p.DeviceId}), radio {p.Backend}, " +
                          $"concurrent Wi-Fi {c.SupportsConcurrentWifi}, register BAR >= 0x{c.MinBarBytes:x}");
        // Whether the bound driver looks like the vendor's own (only informative:
        // the service records any non-proxy driver to give the card back to).
        Console.WriteLine($"  bound driver provider \"{card.Provider}\": " +
                          (Card.BoundToProxy(card) ? (p.Bus == AdapterBus.Usb ? "nekodrop's WinUSB driver" : "nekodrop's register proxy")
                           : CardCatalog.IsVendorProviderMatch(p, card.Provider) ? $"{p.VendorName}'s driver" : "not recognised as the vendor's driver"));
    }
    var net = Wlan.Current(out var why, readKey: false);
    Console.WriteLine(net is null ? $"wifi: {why}"
        : $"wifi: \"{net.Ssid}\" {net.Bssid} channel {net.Channel}, {net.Security}{(why == "" ? "" : " - " + why)}");
    var cfg = ServiceConfig.Load();
    Console.WriteLine($"mode {cfg.Mode}, start channel {cfg.StartChannel}, country \"{cfg.Country}\", peer channel {cfg.PeerChannel}");
    return;
}

// The service owns the card and reads the Wi-Fi key: only as LocalSystem.
if (!System.Security.Principal.WindowsIdentity.GetCurrent().IsSystem)
{
    Console.Error.WriteLine("NekoDropService runs as a Windows service (LocalSystem). Use --status, --selftest or --give-back here.");
    return;
}

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(o => o.ServiceName = "NekoDropService");
builder.Services.AddSingleton<Supervisor>();
builder.Services.AddHostedService<Worker>();
builder.Build().Run();

sealed class Worker(Supervisor sup) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        sup.Boot();
        await new ControlPipe(sup).Run(stoppingToken);
    }

    public override Task StopAsync(CancellationToken cancellationToken)
    {
        sup.Dispose();
        return base.StopAsync(cancellationToken);
    }
}
