// SPDX-License-Identifier: GPL-2.0-only
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace NekoDrop;

public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
    protected void Raise(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>An AirDrop receiver nearby.</summary>
public sealed class Device : Observable
{
    public required string Id { get; init; }
    string _name = "", _model = "", _status = L.T("dev.ready");
    double _progress;
    bool _busy;
    public string Name { get => _name; set { Set(ref _name, value); Raise(nameof(Glyph)); } }
    public string Model { get => _model; set { Set(ref _model, value); Raise(nameof(Glyph)); } }
    public string Glyph
    {
        get
        {
            if (Model.StartsWith("Mac", StringComparison.OrdinalIgnoreCase)) return "\uE7F8";
            if (Model.StartsWith("iPad", StringComparison.OrdinalIgnoreCase)) return "\uE70A";
            if (Model.StartsWith("iPhone", StringComparison.OrdinalIgnoreCase)) return "\uE8EA";
            if (Name.Contains("iPad", StringComparison.OrdinalIgnoreCase)) return "\uE70A";
            if (Name.Contains("Mac", StringComparison.OrdinalIgnoreCase)) return "\uE7F8";
            return "\uE8EA";
        }
    }
    public string Status { get => _status; set => Set(ref _status, value); }
    public double Progress { get => _progress; set => Set(ref _progress, value); }
    public bool Busy { get => _busy; set => Set(ref _busy, value); }
    string _state = "";
    /// <summary>What became of the last send: "", asking, sending, sent, declined or failed (colours the radar).</summary>
    public string State { get => _state; set => Set(ref _state, value); }
    Request? _ask;
    /// <summary>This device asks to send to us: answered right under its icon on the radar.</summary>
    public Request? Ask { get => _ask; set => Set(ref _ask, value); }
    /// <summary>Put on the radar only for its request (it was not among the devices found).</summary>
    public bool ForAsk { get; init; }
}

/// <summary>Someone asking to send.</summary>
public sealed class Request : Observable
{
    public required string Id { get; init; }
    public required string Sender { get; init; }
    public required string Model { get; init; }
    public required string What { get; init; }
    string _status = L.T("req.waiting");
    double _progress;
    bool _receiving;
    public string Status { get => _status; set => Set(ref _status, value); }
    public double Progress { get => _progress; set => Set(ref _progress, value); }
    /// <summary>Accepted, and the files are coming in.</summary>
    public bool Receiving { get => _receiving; set => Set(ref _receiving, value); }
    /// <summary>"wants to send 3 photos", for the bubble under the sender's icon.</summary>
    public string Wants => L.F("ask.wants", What);
}

public sealed class AppModel : Observable
{
    public ObservableCollection<Device> Devices { get; } = [];
    public ObservableCollection<Request> Requests { get; } = [];
    public ObservableCollection<string> Files { get; } = [];
    public ObservableCollection<TransferRecord> History { get; } = [];
    /// <summary>Files sent to this PC were saved: the radar's hub turns green for a moment.</summary>
    public event EventHandler? Stored;
    public void RaiseStored() => Stored?.Invoke(this, EventArgs.Empty);
    string _status = L.T("status.connecting"), _detail = "";
    bool _looking, _discoveryBeaconUnavailable, _radioOn, _allow = true;
    string _air = "service_stopped", _mode = "", _ssid = "";
    int _channel;
    public string Status { get => _status; set => Set(ref _status, value); }
    public string Detail { get => _detail; set => Set(ref _detail, value); }
    public bool Looking { get => _looking; set => Set(ref _looking, value); }
    public bool DiscoveryBeaconUnavailable
    {
        get => _discoveryBeaconUnavailable;
        set => Set(ref _discoveryBeaconUnavailable, value);
    }
    /// <summary>The radio is on and AirDrop listens (the radar's ripples run).</summary>
    public bool RadioOn { get => _radioOn; set => Set(ref _radioOn, value); }
    /// <summary>
    /// What AirDrop is doing, as the design's states: ready, starting, standby
    /// (on demand), off, error, service_stopped, no_adapter.
    /// </summary>
    public string Air { get => _air; set => Set(ref _air, value); }
    /// <summary>concurrent, ondemand or off.</summary>
    public string Mode { get => _mode; set => Set(ref _mode, value); }
    public int Channel { get => _channel; set => Set(ref _channel, value); }
    /// <summary>The network nekodrop's own Wi-Fi is on, "" if none.</summary>
    public string Ssid { get => _ssid; set => Set(ref _ssid, value); }
    string _portal = "";
    /// <summary>A network that wants a web sign-in after joining ("" if none).</summary>
    public string Portal { get => _portal; set => Set(ref _portal, value); }
    /// <summary>Receiving allowed (visible to others).</summary>
    public bool Allow { get => _allow; set => Set(ref _allow, value); }
}
