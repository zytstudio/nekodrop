// SPDX-License-Identifier: GPL-2.0-only
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace NekoDrop;

/// <summary>
/// Settings in four tabs (the design's pivot): general (name, folder,
/// language, accent, start with Windows, hotkey), network and receiving
/// (mode, ask first, always-accept list), card and advanced (detected or
/// chosen card, experimental switches, diagnostic report) and about.
/// Save keeps the window open and says so; Cancel closes it.
/// </summary>
public partial class SettingsWindow : Window
{
    static App A => App.Instance;
    string _folder;
    readonly List<string> _trusted;

    public SettingsWindow(string tab = "general")
    {
        InitializeComponent();
        Native.Chrome(this);
        var s = A.Settings;
        NameBox.Text = s.DeviceName;
        _folder = s.SaveFolder;
        FolderText.Text = _folder;
        (s.AutoAcceptMode switch
        {
            "everyone" => AutoAcceptEveryone,
            "contacts" => AutoAcceptContacts,
            _ => AutoAcceptOff,
        }).IsChecked = true;
        (s.MediaFormat == "original" ? MediaOriginal : MediaCompatible).IsChecked = true;
        AutoConvertHeicBox.IsChecked = s.AutoConvertHeic;
        StartupBox.IsChecked = s.StartWithWindows;
        HotkeyBox.IsChecked = s.Hotkey;
        ShowSpeedBox.IsChecked = s.ShowTransferSpeed;
        AppleIdOnBox.IsChecked = s.AppleIdOn;
        AppleIdOn_Changed(AppleIdOnBox, new RoutedEventArgs());
        ShowReceive();
        ShowIdentity();
        _hotkeyKeys = Hotkey.TryParse(s.HotkeyKeys, out _, out _) ? s.HotkeyKeys : Hotkey.Default;
        ShowHotkey();
        LanguageBox.SelectedIndex = s.Language switch { "zh" => 1, "en" => 2, _ => 0 };
        BuildAccents(s.Accent);
        (s.HubIcon switch { "desktop" => HubDesktop, "laptop" => HubLaptop, _ => HubAuto }).IsChecked = true;
        _trusted = [.. s.AlwaysAccept];
        ShowTrusted();
        var mode = (string?)A.Service.Last?["mode"] ?? "concurrent";
        ModeConcurrent.IsChecked = mode == "concurrent";
        ModeOnDemand.IsChecked = mode == "ondemand";
        ModeOff.IsChecked = mode == "off";
        FastUnlockBox.IsChecked = (bool?)A.Service.Last?["fastUnlock"] ?? false;
        CoexPlanBox.IsChecked = (bool?)A.Service.Last?["coexPlan"] ?? false;
        HighThroughputBox.IsChecked = (bool?)A.Service.Last?["highThroughput"] ?? false;
        BleStandbyBox.IsChecked = s.BleStandby;
        VersionText.Text = "nekodrop " + AppVersion.Current;
        Title = L.T("set.title") + " · nekodrop " + AppVersion.Current;
        ShowCard(A.Service.Last);
        A.Service.Reply += OnCardsReply;
        Closed += (_, _) => A.Service.Reply -= OnCardsReply;
        A.Service.RequestCards();
        (tab switch { "network" => TabNetwork, "appleid" => TabAppleId, "hardware" => TabHardware, "about" => TabAbout, _ => TabGeneral }).IsChecked = true;
    }

    void Tab_Checked(object sender, RoutedEventArgs e)
    {
        if (PageGeneral is null) return; // still loading
        PageGeneral.Visibility = TabGeneral.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PageNetwork.Visibility = TabNetwork.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PageAppleId.Visibility = TabAppleId.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PageHardware.Visibility = TabHardware.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PageAbout.Visibility = TabAbout.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    // ------------------------------------------------------------- accent

    /// <summary>
    /// One choice in one row: colourful first (each state in its own colour on
    /// Windows' accent), then "same as Windows" and the four accents of the design.
    /// </summary>
    void BuildAccents(string chosen)
    {
        var rainbow = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
        foreach (var (hex, at) in new[] { ("#0067C0", 0.0), ("#0F7B0F", 0.35), ("#FCE100", 0.65), ("#C42B1C", 1.0) })
            rainbow.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(hex)!, at));
        AccentPanel.Children.Add(new RadioButton
        {
            Style = (Style)FindResource("Swatch"),
            Tag = Theme.Colourful,
            GroupName = "accent",
            Background = rainbow,
            ToolTip = L.T("set.colourful") + " · " + L.T("set.colourfulHint"),
            IsChecked = chosen == Theme.Colourful,
            Margin = new Thickness(0, 0, 10, 0),
        });
        var system = new RadioButton
        {
            Style = (Style)FindResource("Segment"),
            Content = L.T("set.accent.system"),
            Tag = null,
            GroupName = "accent",
            IsChecked = chosen != Theme.Colourful && Theme.Accents.All(a => a.Key != chosen),
            Margin = new Thickness(0, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        system.SetValue(FrameworkElement.NameProperty, "AccentSystem");
        AccentPanel.Children.Add(system);
        foreach (var a in Theme.Accents)
        {
            AccentPanel.Children.Add(new RadioButton
            {
                Style = (Style)FindResource("Swatch"),
                Tag = a.Key,
                GroupName = "accent",
                Background = new SolidColorBrush(Theme.Dark ? a.Dark : a.Light),
                ToolTip = a.Key,
                IsChecked = a.Key == chosen,
            });
        }
    }

    string ChosenAccent() =>
        AccentPanel.Children.OfType<RadioButton>().FirstOrDefault(r => r.IsChecked == true && r.Tag is string)?.Tag as string ?? "";

    // ----------------------------------------------------- always accept

    /// <summary>
    /// The list could only shrink: nothing added to it (#45). Offers the
    /// senders that asked lately, by the same name and model the check uses.
    /// </summary>
    void TrustedAdd_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = TrustedAdd, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        foreach (var key in A.Settings.RecentSenders.Where(k => !_trusted.Contains(k)))
        {
            var item = new MenuItem { Header = key.Replace("|", " · ") };
            item.Click += (_, _) => { _trusted.Add(key); ShowTrusted(); };
            menu.Items.Add(item);
        }
        if (menu.Items.Count == 0) menu.Items.Add(new MenuItem { Header = L.T("set.trustedAddNone"), IsEnabled = false });
        menu.IsOpen = true;
    }

    void ShowTrusted()
    {
        TrustedTitle.Text = L.F("set.trustedCount", _trusted.Count);
        TrustedEmpty.Visibility = _trusted.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        TrustedList.Children.Clear();
        foreach (var t in _trusted)
        {
            var row = new DockPanel { Margin = new Thickness(0, 4, 0, 0) };
            var remove = new Button { Style = (Style)FindResource("WinButton"), Content = L.T("set.remove"), Padding = new Thickness(10, 4, 10, 4) };
            remove.Click += (_, _) => { _trusted.Remove(t); ShowTrusted(); };
            DockPanel.SetDock(remove, Dock.Right);
            row.Children.Add(remove);
            row.Children.Add(new TextBlock { Text = t.Replace("|", " · "), FontSize = 13, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
            TrustedList.Children.Add(row);
        }
    }

    // ------------------------------------------------------------ the card

    /// <summary>A row of the card or model list.</summary>
    sealed record Item(string Key, string Label, string Vendor = "");

    void ShowCard(JsonObject? state)
    {
        var card = (string?)state?["card"] ?? "";
        var manual = (string?)state?["manualCard"] ?? "";
        var found = card != "";
        CardStatus.Text = found ? (manual != "" ? L.F("set.card.manual", card) : card) : L.T("set.card.none");
        CardBadgeText.Text = found ? L.T("set.card.detectedBadge") : L.T("set.card.unrecognized");
        CardBadge.SetResourceReference(Border.BackgroundProperty, found ? "SuccessBg" : "WarnBg");
        CardBadgeText.SetResourceReference(TextBlock.ForegroundProperty, found ? "Success" : "Warn");
        // The manual choice is for a card nekodrop does not know; shown when none was found or one was chosen by hand.
        CardManual.Visibility = !found || manual != "" ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>The service's card list and models (the "cards" event); a manual choice's answer ("card-manual").</summary>
    void OnCardsReply(JsonObject o) => Dispatcher.BeginInvoke(() =>
    {
        var ev = (string?)o["event"];
        if (ev == "card-manual")
        {
            var error = (string?)o["error"] ?? "";
            CardError.Text = error == "" ? L.T("set.card.applied") : L.T("set.card.mismatch");
            return;
        }
        if (ev != "cards") return;
        var manualHw = (string?)A.Service.Last?["manualCard"] ?? "";
        var manualModel = (string?)A.Service.Last?["manualModel"] ?? "";
        CardBox.Items.Clear();
        foreach (var c in o["candidates"]?.AsArray() ?? [])
        {
            var hw = (string?)c?["hw"] ?? "";
            var name = (string?)c?["name"] ?? "";
            var tag = (bool?)c?["recognized"] == true ? L.T("set.card.recognized") : L.T("set.card.unrecognized");
            CardBox.Items.Add(new Item(hw, $"{(name == "" ? hw : name)} ({hw.Replace("PCI\\", "")}) · {tag}"));
        }
        ModelBox.Items.Clear();
        foreach (var m in o["models"]?.AsArray() ?? [])
            ModelBox.Items.Add(new Item((string?)m?["key"] ?? "", (string?)m?["name"] ?? "", (string?)m?["vendor"] ?? ""));
        CardBox.SelectedItem = CardBox.Items.Cast<Item>().FirstOrDefault(i => i.Key == manualHw) ??
                               CardBox.Items.Cast<Item>().FirstOrDefault();
        ModelBox.SelectedItem = ModelBox.Items.Cast<Item>().FirstOrDefault(i => i.Key == manualModel);
        if (CardBox.Items.Count == 0) CardError.Text = L.T("set.card.nolist");
    });

    void CardApply_Click(object sender, RoutedEventArgs e)
    {
        if (CardBox.SelectedItem is not Item card || ModelBox.SelectedItem is not Item model)
        {
            CardError.Text = L.T("set.card.pick");
            return;
        }
        CardError.Text = "";
        A.Service.SetManualCard(card.Key, model.Key);
    }

    void CardAuto_Click(object sender, RoutedEventArgs e)
    {
        CardError.Text = "";
        A.Service.SetManualCard("", "");
    }

    void Report_Click(object sender, RoutedEventArgs e) => App.RunReport();

    // ---------------------------------------------------------------- save

    void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = L.T("pick.folder"), InitialDirectory = _folder };
        if (Native.ShowDialog(this, dlg, dlg.Title) != true) return;
        _folder = dlg.FolderName;
        FolderText.Text = _folder;
    }

    async void Save_Click(object sender, RoutedEventArgs e)
    {
        var s = A.Settings;
        var name = NameBox.Text.Trim();
        if (name.Length > 0) s.DeviceName = name;
        s.SaveFolder = _folder;
        s.AutoAcceptMode = AutoAcceptEveryone.IsChecked == true ? "everyone" : AutoAcceptContacts.IsChecked == true ? "contacts" : "off";
        s.Ask = s.AutoAcceptMode != "everyone";
        var mediaFormat = MediaOriginal.IsChecked == true ? "original" : "compatible";
        var mediaChanged = mediaFormat != s.MediaFormat;
        s.MediaFormat = mediaFormat;
        s.AutoConvertHeic = AutoConvertHeicBox.IsChecked == true;
        s.StartWithWindows = StartupBox.IsChecked == true;
        var appleIdOn = AppleIdOnBox.IsChecked == true;
        var receive = appleIdOn && ReceiveContacts.IsChecked == true && AppleId.Present ? "contacts" : "everyone";
        var receiveChanged = receive != s.Receive || appleIdOn != s.AppleIdOn;
        s.AppleIdOn = appleIdOn;
        s.Receive = receive;
        var hotkeyChanged = (HotkeyBox.IsChecked == true) != s.Hotkey || _hotkeyKeys != s.HotkeyKeys;
        s.Hotkey = HotkeyBox.IsChecked == true;
        s.HotkeyKeys = _hotkeyKeys;
        s.ShowTransferSpeed = ShowSpeedBox.IsChecked == true;
        var bleStandby = BleStandbyBox.IsChecked == true;
        var bleStandbyChanged = bleStandby != s.BleStandby;
        s.BleStandby = bleStandby;
        var language = (LanguageBox.SelectedItem as ComboBoxItem)?.Tag as string ?? "auto";
        var languageChanged = language != s.Language;
        s.Language = language;
        s.AlwaysAccept = [.. _trusted];
        s.HubIcon = HubDesktop.IsChecked == true ? "desktop" : HubLaptop.IsChecked == true ? "laptop" : "auto";
        var accent = ChosenAccent();
        var accentChanged = accent != s.Accent;
        s.Accent = accent;
        s.Save();
        try { Shell.Register(s.StartWithWindows); } catch (Exception) { }
        A.Engine.Apply(s);
        var mode = ModeConcurrent.IsChecked == true ? "concurrent" : ModeOnDemand.IsChecked == true ? "ondemand" : "off";
        if (mode != (string?)A.Service.Last?["mode"]) A.Service.SetMode(mode);
        var fastUnlock = FastUnlockBox.IsChecked == true;
        if (fastUnlock != ((bool?)A.Service.Last?["fastUnlock"] ?? false)) A.Service.SetFastUnlock(fastUnlock);
        var coexPlan = CoexPlanBox.IsChecked == true;
        if (coexPlan != ((bool?)A.Service.Last?["coexPlan"] ?? false)) A.Service.SetCoexPlan(coexPlan);
        var highThroughput = HighThroughputBox.IsChecked == true;
        if (highThroughput != ((bool?)A.Service.Last?["highThroughput"] ?? false)) A.Service.SetHighThroughput(highThroughput);
        A.Window?.FolderChanged();
        var hotkeyTaken = hotkeyChanged && !A.ApplyHotkey();
        if (receiveChanged || mediaChanged || bleStandbyChanged) A.RestartEngine();
        A.Window?.ShowMark();
        if (accentChanged) A.ApplyTheme();
        if (languageChanged) { A.ApplyLanguage(); Close(); return; }
        SavedText.Text = hotkeyTaken ? L.F("set.hotkeyTaken", Hotkey.Show(_hotkeyKeys)) : "✓ " + L.T("set.saved");
        await Task.Delay(2000);
        SavedText.Text = "";
    }

    void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    // ------------------------------------------------ Apple ID, Contacts Only

    /// <summary>Who can send, as saved (also when the AirDrop mark changed it while this window is open).</summary>
    public void ShowReceive()
    {
        (A.Settings.Receive == "contacts" && AppleId.Present ? ReceiveContacts : ReceiveEveryone).IsChecked = true;
    }

    /// <summary>The page below the experimental switch works only while it is on.</summary>
    void AppleIdOn_Changed(object sender, RoutedEventArgs e)
    {
        if (AppleIdBody is null) return; // still loading
        AppleIdBody.IsEnabled = AppleIdOnBox.IsChecked == true;
        AppleIdBody.Opacity = AppleIdBody.IsEnabled ? 1 : 0.5;
    }

    /// <summary>What identity there is, and which buttons make sense with it.</summary>
    void ShowIdentity()
    {
        var present = AppleId.Present;
        ReceiveContacts.IsEnabled = present;
        if (!present) ReceiveEveryone.IsChecked = true;
        SignInButton.IsEnabled = AppleId.CanSignIn;
        SignInButton.ToolTip = AppleId.CanSignIn ? null : L.T("aid.noTool");
        ExportAppleIdLogButton.Visibility = AppleId.HasLog ? Visibility.Visible : Visibility.Collapsed;
        SignOutButton.Visibility = present || AppleId.HasLocalState ? Visibility.Visible : Visibility.Collapsed;
        ContactsButton.Visibility = AppleId.Source == "appleid" ? Visibility.Collapsed : Visibility.Visible;
        if (!present) { IdentityText.Text = L.T("aid.none"); return; }
        var until = AppleId.CertificateUntil is { } d ? d.ToString("yyyy-MM-dd") : "?";
        var who = AppleId.Source == "appleid" ? L.F("aid.signedIn", AppleId.Account) : L.T("aid.fromMac");
        IdentityText.Text = who + " · " + L.F("aid.until", until) + " · " + L.F("aid.contactCount", AppleId.ContactCount);
    }

    void IdentityChanged()
    {
        ShowIdentity();
        A.RestartEngine();
    }

    void SignIn_Click(object sender, RoutedEventArgs e)
    {
        var w = new AppleIdWindow { Owner = this };
        if (w.ShowDialog() == true)
        {
            IdentityChanged();
            SavedText.Text = "✓ " + L.T("aid.done");
        }
        else
        {
            ShowIdentity();
        }
    }

    void ExportAppleIdLog_Click(object sender, RoutedEventArgs e)
    {
        if (!AppleId.HasLog) { MessageBox.Show(this, L.T("aid.noLog"), "nekodrop", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var stamp = DateTime.Now.ToString("yyyyMMdd-HHmm");
        var dlg = new Microsoft.Win32.SaveFileDialog
        {
            Title = L.T("aid.exportLog"),
            Filter = "Log (*.txt)|*.txt",
            FileName = $"nekodrop-appleid-log-{stamp}.txt",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
        };
        if (Native.ShowDialog(this, dlg, dlg.Title) != true) return;
        try
        {
            AppleId.ExportLog(dlg.FileName);
            SavedText.Text = "✓ " + L.F("aid.logExported", System.IO.Path.GetFileName(dlg.FileName));
            try { System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{dlg.FileName}\""); } catch (Exception) { }
        }
        catch (Exception x) { MessageBox.Show(this, x.Message, "nekodrop", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    void ImportMac_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = L.T("aid.pickMac") };
        if (Native.ShowDialog(this, dlg, dlg.Title) != true) return;
        var why = AppleId.ImportFromMac(dlg.FolderName, null);
        if (why == "need_passphrase")
        {
            var pass = Microsoft.VisualBasic.Interaction.InputBox(L.T("aid.passphrase"), "nekodrop");
            if (pass.Length == 0) return;
            why = AppleId.ImportFromMac(dlg.FolderName, pass);
        }
        if (why is not null) { MessageBox.Show(this, why, "nekodrop", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        IdentityChanged();
        SavedText.Text = "✓ " + L.T("aid.imported");
    }

    void ImportContacts_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFileDialog { Title = L.T("aid.pickVcf"), Filter = "vCard (*.vcf)|*.vcf" };
        if (Native.ShowDialog(this, dlg, dlg.Title) != true) return;
        try
        {
            var people = AppleId.ImportContacts(dlg.FileName);
            IdentityChanged();
            SavedText.Text = "✓ " + L.F("aid.contactsImported", people);
        }
        catch (Exception x) { MessageBox.Show(this, x.Message, "nekodrop", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    void SignOut_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, L.T("aid.signOutAsk"), "nekodrop", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        try { AppleId.SignOut(); } catch (Exception x) { MessageBox.Show(this, x.Message, "nekodrop"); return; }
        if (A.Settings.Receive == "contacts") { A.Settings.Receive = "everyone"; A.Settings.Save(); }
        IdentityChanged();
    }

    // ------------------------------------------------- recording the shortcut

    string _hotkeyKeys = Hotkey.Default;
    bool _recording;

    void ShowHotkey() => HotkeyText.Text = _recording ? L.T("set.hotkeyPress") : Hotkey.Show(_hotkeyKeys);

    void HotkeyRecorder_Click(object sender, RoutedEventArgs e)
    {
        _recording = !_recording;
        ShowHotkey();
    }

    void HotkeyRecorder_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (!_recording) return;
        e.Handled = true;
        var key = e.Key == System.Windows.Input.Key.System ? e.SystemKey : e.Key;
        if (key == System.Windows.Input.Key.Escape) { _recording = false; ShowHotkey(); return; }
        // Keyboard.Modifiers leaves out Win; ask for it directly.
        var mods = System.Windows.Input.Keyboard.Modifiers;
        if (System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.LWin) || System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.RWin))
            mods |= System.Windows.Input.ModifierKeys.Windows;
        if (Hotkey.FromKeys(mods, key) is not { } combo) return; // only modifiers so far, or no modifier
        _hotkeyKeys = combo;
        _recording = false;
        ShowHotkey();
    }

    void HotkeyRecorder_LostFocus(object sender, System.Windows.Input.KeyboardFocusChangedEventArgs e)
    {
        if (!_recording) return;
        _recording = false;
        ShowHotkey();
    }

    void HotkeyReset_Click(object sender, RoutedEventArgs e)
    {
        _recording = false;
        _hotkeyKeys = Hotkey.Default;
        ShowHotkey();
    }
}
