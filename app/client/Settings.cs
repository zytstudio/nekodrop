// SPDX-License-Identifier: GPL-2.0-only
using System.IO;
using System.Text.Json;

namespace NekoDrop;

/// <summary>Per-user settings, in %LocalAppData%\nekodrop\settings.json.</summary>
public sealed class Settings
{
    public string DeviceName { get; set; } = Environment.MachineName;
    public string SaveFolder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "nekodrop");
    /// <summary>Ask before storing what someone sends (false when AutoAcceptMode == "everyone").</summary>
    public bool Ask { get; set; } = true;
    /// <summary>Auto-accept incoming transfers: "off" (ask), "contacts" (Apple ID contacts / own devices), or "everyone".</summary>
    public string AutoAcceptMode { get; set; } = "off";
    /// <summary>Media format negotiated with senders: "compatible" (JPEG/H.264) or "original" (HEIC/HEVC).</summary>
    public string MediaFormat { get; set; } = "compatible";
    /// <summary>When a .heic/.heif photo (e.g. Live Photo or original format) arrives, save a sibling .jpg copy.</summary>
    public bool AutoConvertHeic { get; set; } = true;
    /// <summary>Senders accepted without asking, by the name and model they give.</summary>
    public List<string> AlwaysAccept { get; set; } = [];
    /// <summary>The last senders that asked ("name|model", newest first), offered by Settings' Add (#45).</summary>
    public List<string> RecentSenders { get; set; } = [];
    public bool StartWithWindows { get; set; } = true;
    /// <summary>Visible to everyone for 10 minutes at a time, as on an iPhone.</summary>
    public bool Discoverable { get; set; } = true;
    /// <summary>"auto" (follow Windows), "zh" or "en".</summary>
    public string Language { get; set; } = "auto";
    /// <summary>The AirDrop receiver's mDNS instance name, kept so engine restarts stay one device.</summary>
    public string ServiceId { get; set; } = "";

    /// <summary>This PC's icon on the radar: "auto" (a laptop when there is a battery), "desktop" or "laptop".</summary>
    public string HubIcon { get; set; } = "auto";
    /// <summary>The global shortcut (Win+Shift+D unless recorded otherwise) opens the send window (with Explorer's selection) or the main window.</summary>
    public bool Hotkey { get; set; } = true;
    /// <summary>The global shortcut's keys, as the user recorded them ("Ctrl+Alt+K").</summary>
    public string HotkeyKeys { get; set; } = NekoDrop.Hotkey.Default;
    /// <summary>Show live transfer speed (MB/s or KB/s) next to send and receive progress.</summary>
    public bool ShowTransferSpeed { get; set; } = true;
    /// <summary>Experimental: keep the AirDrop BLE beacon advertising while receiving in standby (NEKODROP_BLE_STANDBY=1).</summary>
    public bool BleStandby { get; set; }
    /// <summary>Experimental: use the Apple ID identity (AppleId) at all. Off, the engine stays anonymous (Everyone).</summary>
    public bool AppleIdOn { get; set; }
    /// <summary>Who may send to this PC: "everyone", or "contacts" (needs AppleIdOn and an identity, see AppleId).</summary>
    public string Receive { get; set; } = "everyone";
    /// <summary>Nearby devices as a "radar" or a "list".</summary>
    public string DeviceView { get; set; } = "radar";
    /// <summary>
    /// The accent colour: "" follows Windows, blue, indigo, teal or rose; or
    /// "colourful", Windows' accent with each state in its own colour.
    /// </summary>
    public string Accent { get; set; } = "";

    static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "nekodrop");
    static string FilePath => Path.Combine(Folder, "settings.json");
    static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Options) ?? new();
                // Migrate legacy Ask == false to AutoAcceptMode == "everyone".
                if (!loaded.Ask && loaded.AutoAcceptMode == "off") loaded.AutoAcceptMode = "everyone";
                loaded.Ask = loaded.AutoAcceptMode != "everyone";
                return loaded;
            }
        }
        catch (Exception) { }
        return new();
    }

    public void Save()
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
    }
}
