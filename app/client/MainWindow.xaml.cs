// SPDX-License-Identifier: GPL-2.0-only
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Shape = System.Windows.Shapes.Shape;

namespace NekoDrop;

/// <summary>
/// The main window: its own title bar (status pill with the quick controls,
/// Wi-Fi, settings), a newer-version bar, someone asking to send, nearby
/// devices (radar or list), the files to send, what came in lately, and where
/// it is saved.
/// </summary>
public partial class MainWindow : Window
{
    static App A => App.Instance;

    public MainWindow()
    {
        InitializeComponent();
        Native.Chrome(this, caption: 0); // docked to the screen's edge: nothing to drag
        // A tool, not an app of its own: it slides out at the right edge of
        // the screen and goes away when something else is clicked.
        // Only when another program takes the focus: opening settings, Wi-Fi
        // or the tray menu (windows of nekodrop) keeps it out.
        Application.Current.Deactivated += OnAppDeactivated;
        DataContext = A.Model;
        A.Model.Files.CollectionChanged += OnFiles;
        A.Model.History.CollectionChanged += OnHistory;
        A.Model.PropertyChanged += OnModel;
        Drop += OnDrop;
        DragEnter += (_, _) => _dragAt = DateTime.UtcNow;
        DragOver += (_, e) => { e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
        Closed += (_, _) =>
        {
            A.Model.Files.CollectionChanged -= OnFiles;
            A.Model.History.CollectionChanged -= OnHistory;
            A.Model.PropertyChanged -= OnModel;
            Application.Current.Deactivated -= OnAppDeactivated;
            A.WindowClosed();
        };
        FolderChanged();
        OnFiles(null, null);
        OnHistory(null, null);
        ShowState();
    }

    public void FolderChanged() => FolderText.Text = L.T("main.saveTo") + " " + A.Settings.SaveFolder;

    void OnModel(object? s, PropertyChangedEventArgs e) => ShowState();

    /// <summary>The status pill and the Wi-Fi button.</summary>
    void ShowState()
    {
        var m = A.Model;
        var (label, dot) = Status(m.Air);
        StatusText.Text = label;
        StatusDot.SetResourceReference(Shape.FillProperty, dot);
        StatusPill.ToolTip = m.Air == "ready" ? L.F("status.on", m.Channel) : label;
        WifiText.Text = m.Mode == "concurrent" && m.Ssid != "" ? m.Ssid : "Wi-Fi";
        ShowMark();
    }

    /// <summary>The words and dot colour of a state (the design's status pill).</summary>
    public static (string Label, string Dot) Status(string air) => air switch
    {
        "ready" => (L.T("pill.ready"), "Success"),
        "starting" => (L.T("status.starting"), "Warn"),
        "standby" => (L.T("pill.standby"), "Text3"),
        "off" => (L.T("pill.off"), "Text3"),
        "error" => (L.T("status.error"), "Error"),
        "no_adapter" => (L.T("radar.noCard"), "Warn"),
        _ => (L.T("status.noService"), "Error"),
    };

    // ------------------------------------------------------- quick controls

    void StatusPill_Checked(object sender, RoutedEventArgs e)
    {
        AllowToggle.IsChecked = A.Model.Allow;
        UpdateAutoAcceptUi();
        ModeList.Children.Clear();
        foreach (var (key, text) in new[] { ("concurrent", L.T("mode.concurrent.short")), ("ondemand", L.T("mode.ondemand.short")), ("off", L.T("mode.off.short")) })
            ModeList.Children.Add(ModeChoice(key, text, A.Model.Mode == key));
        ChannelTip.Text = A.Model.Air == "ready" ? L.F("status.on", A.Model.Channel) : Status(A.Model.Air).Label;
        StatusPopup.IsOpen = true;
    }

    void UpdateAutoAcceptUi()
    {
        var m = A.Settings.AutoAcceptMode;
        AutoAcceptToggle.IsChecked = m != "off";
        AutoAcceptSub.Text = m switch
        {
            "everyone" => L.T("set.autoAccept.everyone"),
            "contacts" => L.T("set.autoAccept.contacts"),
            _ => L.T("set.autoAccept.off"),
        };
    }

    void AutoAccept_Click(object sender, RoutedEventArgs e)
    {
        A.SetAutoAccept(AutoAcceptToggle.IsChecked == true ? "everyone" : "off");
        UpdateAutoAcceptUi();
    }

    Button ModeChoice(string key, string text, bool chosen) =>
        Choice(text, chosen, () => { A.Service.SetMode(key); StatusPopup.IsOpen = false; });

    // ------------------------------------------------- who can send to this PC

    void Mark_Click(object sender, RoutedEventArgs e)
    {
        var mode = AppleId.Receiving;
        ReceiveList.Children.Clear();
        // Contacts Only shows once the experimental Apple ID switch is on.
        var choices = A.Settings.AppleIdOn
            ? new[] { ("off", L.T("recv.off")), ("contacts", L.T("aid.contacts")), ("everyone", L.T("recv.everyone")) }
            : new[] { ("off", L.T("recv.off")), ("everyone", L.T("recv.everyone")) };
        foreach (var (key, text) in choices)
            ReceiveList.Children.Add(Choice(text, mode == key, () =>
            {
                ReceivePopup.IsOpen = false;
                if (key == "contacts" && !AppleId.Present) { A.ShowSettings("appleid"); return; }
                A.SetReceive(key);
            }));
        ReceiveTip.Text = !A.Settings.AppleIdOn ? L.T("recv.enableHint") : AppleId.Present ? "" : L.T("recv.needIdentity");
        ReceiveTip.Visibility = ReceiveTip.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        ReceivePopup.IsOpen = true;
    }

    /// <summary>The mark in the accent while receiving, grey while not, and what it means on hover.</summary>
    public void ShowMark()
    {
        var mode = AppleId.Receiving;
        Mark.SetResourceReference(AirDropMark.BrushProperty, mode == "off" ? "Text3" : "Accent");
        MarkButton.ToolTip = L.T("recv.title") + ": " +
            (mode == "off" ? L.T("recv.off") : mode == "contacts" ? L.T("aid.contacts") : L.T("recv.everyone"));
    }

    /// <summary>A row with a radio dot: the chosen one in the accent.</summary>
    Button Choice(string text, bool chosen, Action pick)
    {
        var dot = new Grid { Width = 12, Height = 12, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        var ring = new System.Windows.Shapes.Ellipse { StrokeThickness = 1.5 };
        ring.SetResourceReference(Shape.StrokeProperty, chosen ? "Accent" : "Text3");
        dot.Children.Add(ring);
        if (chosen)
        {
            var fill = new System.Windows.Shapes.Ellipse { Width = 6, Height = 6 };
            fill.SetResourceReference(Shape.FillProperty, "Accent");
            dot.Children.Add(fill);
        }
        var label = new TextBlock { Text = text, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        if (chosen) { label.FontWeight = FontWeights.SemiBold; label.SetResourceReference(TextBlock.ForegroundProperty, "Accent"); }
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(dot);
        row.Children.Add(label);
        var b = new Button
        {
            Style = (Style)FindResource("TitleButton"),
            Width = double.NaN,
            Height = double.NaN,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8, 6, 8, 6),
            Content = row,
        };
        if (chosen) b.SetResourceReference(BackgroundProperty, "AccentSubtle");
        b.Click += (_, _) => pick();
        return b;
    }

    void StatusPopup_Closed(object? sender, EventArgs e) => StatusPill.IsChecked = false;
    void Allow_Click(object sender, RoutedEventArgs e) => A.SetDiscoverable(AllowToggle.IsChecked == true);

    // ----------------------------------------------------------- the files

    void OnFiles(object? s, NotifyCollectionChangedEventArgs? e)
    {
        var n = A.Model.Files.Count;
        FilesRow.Visibility = n == 0 ? Visibility.Collapsed : Visibility.Visible;
        ClearButton.Visibility = n == 0 ? Visibility.Collapsed : Visibility.Visible;
        FilesCount.Text = L.F("main.count", n);
        FilesOutline.StrokeDashArray = n == 0 ? new DoubleCollection { 4, 3 } : null;
    }

    void OnHistory(object? s, NotifyCollectionChangedEventArgs? e)
    {
        if (ReceivedList is null) return;
        var sent = RecentSentTab?.IsChecked == true;
        var shown = A.Model.History.Where(r => sent ? r.IsSent : r.IsReceived).Take(3).ToList();
        NothingReceived.Text = L.T(sent ? "main.sentNone" : "main.receivedNone");
        NothingReceived.Visibility = shown.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ReceivedList.ItemsSource = shown;
    }

    void RecentTab_Checked(object sender, RoutedEventArgs e) => OnHistory(null, null);
    void History_Click(object sender, RoutedEventArgs e) => A.ShowHistory();

    void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] paths)
            foreach (var p in paths) if (!A.Model.Files.Contains(p)) A.Model.Files.Add(p);
    }

    void Add_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = L.T("pick.files") };
        if (Modal(() => Native.ShowDialog(this, dlg, dlg.Title)) == true)
            foreach (var f in dlg.FileNames) if (!A.Model.Files.Contains(f)) A.Model.Files.Add(f);
    }

    void Clear_Click(object sender, RoutedEventArgs e) => A.Model.Files.Clear();

    void RemoveFile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is string f) A.Model.Files.Remove(f);
    }

    // ------------------------------------------------------------ the rest

    void Settings_Click(object sender, RoutedEventArgs e) => A.ShowSettings("general");
    void Wifi_Click(object sender, RoutedEventArgs e) => A.ShowWifi();
    void Report_Click(object sender, RoutedEventArgs e) { StatusPopup.IsOpen = false; App.RunReport(); }
    void Close_Click(object sender, RoutedEventArgs e) => Shut();

    bool _dialog;

    /// <summary>
    /// Another program took the focus: go away, except just after opening.
    /// A double click on the tray icon, or Explorer taking the focus back
    /// after starting nekodrop from a shortcut, would otherwise close it at once.
    /// </summary>
    void OnAppDeactivated(object? sender, EventArgs e)
    {
        if (_dialog || !IsVisible) return;
        var left = Grace - (DateTime.UtcNow - ShownAt);
        if (left <= TimeSpan.Zero)
        {
            // #45: pressing on a file in Explorer to drag it here takes the focus
            // first. While the button is held, wait: a drag that reaches the
            // panel keeps it out, a plain click elsewhere closes it on release.
            if (Native.LeftButtonDown()) WaitForRelease();
            else Shut();
            return;
        }
        // Take the focus back once things settle, so a later click elsewhere still closes it.
        var t = new System.Windows.Threading.DispatcherTimer { Interval = left };
        t.Tick += (_, _) =>
        {
            t.Stop();
            if (IsVisible && !Application.Current.Windows.OfType<Window>().Any(w => w.IsActive)) Activate();
        };
        t.Start();
    }

    public static readonly TimeSpan Grace = TimeSpan.FromMilliseconds(600);

    /// <summary>When a drag last came over the panel.</summary>
    DateTime _dragAt = DateTime.MinValue;

    /// <summary>The focus went while the left button was down: decide when it comes up.</summary>
    void WaitForRelease()
    {
        var since = DateTime.UtcNow;
        var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
        t.Tick += (_, _) =>
        {
            if (!IsVisible || _closing) { t.Stop(); return; }
            if (Native.LeftButtonDown()) return;
            t.Stop();
            if (_dragAt >= since) Activate(); // dropped here (or dragged across): stay
            else if (!IsActive) Shut();
        };
        t.Start();
    }

    /// <summary>When it last came out.</summary>
    public DateTime ShownAt { get; private set; }

    /// <summary>When it last went away, so a click on the tray icon that took the focus from it does not bring it straight back.</summary>
    public DateTime ShutAt { get; private set; }

    /// <summary>Hides the panel (it is kept, with what it shows).</summary>
    public void Shut()
    {
        if (_closing) return;
        StatusPopup.IsOpen = false;
        ShutAt = DateTime.UtcNow;
        _closing = true;
        // Slides down and fades, then hides.
        Motion.FadeOut(Root, 14, () => { _closing = false; Hide(); A.WindowClosed(); });
    }

    bool _closing;

    /// <summary>Comes out: its content rises and fades in from the taskbar's side.</summary>
    public void Reveal() => Motion.FadeIn(Root, 18, 260);

    /// <summary>
    /// In the bottom-right corner of the work area of the screen under the
    /// mouse, next to the tray like Windows' own flyouts; shorter on a small screen.
    /// </summary>
    public void DockRight()
    {
        // Before the first Show there is no PresentationSource yet, so
        // TransformFromDevice is still Identity and WorkArea would be read at
        // 96 dpi. On a 125 % screen that puts the panel one screen to the right
        // until it is hidden and shown again. Wait for the HWND to be connected
        // to its composition target, then place it with the real DPI.
        if (PresentationSource.FromVisual(this) is null)
        {
            if (!_dockPending)
            {
                _dockPending = true;
                SourceInitialized += (_, _) =>
                {
                    _dockPending = false;
                    DockRight();
                };
            }
            return;
        }
        Native.DockBottomRight(this, Width, 700, 12);
        ShownAt = DateTime.UtcNow;
    }

    bool _dockPending;

    /// <summary>A file or folder dialog takes the focus without the panel going away.</summary>
    T Modal<T>(Func<T> show)
    {
        _dialog = true;
        try { return show(); }
        finally { _dialog = false; Activate(); }
    }

    void ChangeFolder_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = L.T("pick.folder"), InitialDirectory = A.Settings.SaveFolder };
        if (Modal(() => Native.ShowDialog(this, dlg, dlg.Title)) != true) return;
        A.Settings.SaveFolder = dlg.FolderName;
        A.Settings.Save();
        A.Engine.Apply(A.Settings);
        FolderChanged();
    }

    void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(A.Settings.SaveFolder);
        Process.Start("explorer.exe", $"\"{A.Settings.SaveFolder}\"");
    }

    void Open_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is TransferRecord record)
            MediaHelper.OpenRecord(record);
    }

    async void Copy_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not TransferRecord record) return;
        if (MediaHelper.CopyToClipboard(record.Paths, record.Url, out _, out _) &&
            sender is Button btn && btn.Content is TextBlock tb)
        {
            var prev = tb.Text;
            tb.Text = "\uE73E";
            await Task.Delay(1200);
            tb.Text = prev;
        }
    }
}

/// <summary>A path's last part, for the file chips.</summary>
public sealed class FileName : System.Windows.Data.IValueConverter
{
    public static readonly FileName Instance = new();
    public object? Convert(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture) =>
        value is string s ? Path.GetFileName(s.TrimEnd('\\')) : "";
    public object? ConvertBack(object? value, Type targetType, object? parameter, System.Globalization.CultureInfo culture) =>
        throw new NotSupportedException();
}
