// SPDX-License-Identifier: GPL-2.0-only
using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using Microsoft.Win32;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;

namespace NekoDrop;

/// <summary>Where nekodrop meets Windows: notifications, Explorer, startup.</summary>
public static class Shell
{
    /// <summary>The app's identity for notifications; the Start menu shortcut carries the same one.</summary>
    public const string Aumid = "nekodrop.app";

    static string Exe => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "nekodrop.exe");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SetCurrentProcessExplicitAppUserModelID(string id);

    public static void SetIdentity() => SetCurrentProcessExplicitAppUserModelID(Aumid);

    /// <summary>
    /// Per-user registrations, safe to repeat at every start:
    /// "用 nekodrop 发送" on files and folders (classic menu; Windows 11 shows it
    /// under "Show more options"), the nekodrop: protocol that notification
    /// buttons use, Send To, and starting with Windows.
    /// </summary>
    public static void Register(bool startWithWindows)
    {
        var exe = Exe;
        // Each step on its own: one refused write (security software guarding
        // the context menu) must not leave notifications without their
        // protocol (#17). The protocol goes first.
        Try(RegisterProtocol);
        Try(() =>
        {
            using var classes = Registry.CurrentUser.CreateSubKey(@"Software\Classes");
            foreach (var target in new[] { @"*\shell\nekodrop", @"Directory\shell\nekodrop" })
            {
                using var key = classes.CreateSubKey(target);
                key.SetValue("", L.T("verb"));
                key.SetValue("Icon", $"\"{exe}\",0");
                key.SetValue("MultiSelectModel", "Player");
                using var cmd = key.CreateSubKey("command");
                cmd.SetValue("", $"\"{exe}\" --send \"%1\"");
            }
        });
        Try(() =>
        {
            using var app = Registry.CurrentUser.CreateSubKey(@"Software\nekodrop");
            app.SetValue("Language", L.Zh ? "zh" : "en");
        });
        Try(() =>
        {
            using var run = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
            if (startWithWindows) run.SetValue("nekodrop", $"\"{exe}\" --background");
            else run.DeleteValue("nekodrop", false);
        });
        Try(() =>
        {
            var sendTo = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.SendTo), "nekodrop.lnk");
            if (!File.Exists(sendTo)) CreateShortcut(sendTo, exe, "--send");
        });
        _ = RegisterMenuPackage();
    }

    static void Try(Action step)
    {
        try { step(); } catch (Exception) { }
    }

    /// <summary>The nekodrop: protocol that notification clicks and buttons open; checked again before each notification.</summary>
    static void RegisterProtocol()
    {
        var command = $"\"{Exe}\" \"%1\"";
        using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Classes\nekodrop"))
        using (var existing = key?.OpenSubKey(@"shell\open\command"))
            if (key?.GetValue("URL Protocol") is not null && existing?.GetValue("") as string == command) return;
        using var proto = Registry.CurrentUser.CreateSubKey(@"Software\Classes\nekodrop");
        proto.SetValue("", "URL:nekodrop");
        proto.SetValue("URL Protocol", "");
        using var cmd = proto.CreateSubKey(@"shell\open\command");
        cmd.SetValue("", command);
    }

    const string MenuPackage = "nekodrop.shell";

    static IEnumerable<Windows.ApplicationModel.Package> MenuPackages() =>
        new Windows.Management.Deployment.PackageManager().FindPackagesForUser(string.Empty)
            .Where(p => p.Id.Name == MenuPackage);

    /// <summary>
    /// Windows 11 puts "用 nekodrop 发送" on the first level of the context menu
    /// only for a packaged app: registers, for this user, the sparse package
    /// that install.ps1 signed (external location = the install folder). Without
    /// it the classic verb above still works under "Show more options".
    /// </summary>
    static async Task RegisterMenuPackage()
    {
        try
        {
            var dir = Path.GetDirectoryName(Exe)!;
            var msix = Path.Combine(dir, "shell", "nekodrop-shell.msix");
            if (!File.Exists(msix) || !File.Exists(Path.Combine(dir, "nekodrop-shell.dll"))) return;
            // Registered already, unless with an older manifest (0.2: the Share sheet).
            if (MenuPackages().Any(p => p.Id.Version.Major > 0 || p.Id.Version.Minor >= 2)) return;
            var options = new Windows.Management.Deployment.AddPackageOptions
            {
                ExternalLocationUri = new Uri(dir + Path.DirectorySeparatorChar),
                ForceAppShutdown = true,
            };
            await new Windows.Management.Deployment.PackageManager().AddPackageByUriAsync(new Uri(msix), options);
        }
        catch (Exception) { /* unsigned (a development run) or sideloading turned off */ }
    }

    public static void Unregister()
    {
        var classes = Registry.CurrentUser.OpenSubKey(@"Software\Classes", true);
        classes?.DeleteSubKeyTree(@"*\shell\nekodrop", false);
        classes?.DeleteSubKeyTree(@"Directory\shell\nekodrop", false);
        classes?.DeleteSubKeyTree("nekodrop", false);
        Registry.CurrentUser.DeleteSubKeyTree(@"Software\nekodrop", false);
        using var run = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
        run?.DeleteValue("nekodrop", false);
        var sendTo = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.SendTo), "nekodrop.lnk");
        if (File.Exists(sendTo)) File.Delete(sendTo);
        try
        {
            var pm = new Windows.Management.Deployment.PackageManager();
            foreach (var p in MenuPackages().ToList())
                pm.RemovePackageAsync(p.Id.FullName).AsTask().Wait(TimeSpan.FromSeconds(30));
        }
        catch (Exception) { }
    }

    static void CreateShortcut(string path, string target, string args)
    {
        var type = Type.GetTypeFromProgID("WScript.Shell");
        if (type is null) return;
        dynamic shell = Activator.CreateInstance(type)!;
        dynamic link = shell.CreateShortcut(path);
        link.TargetPath = target;
        link.Arguments = args;
        link.IconLocation = target + ",0";
        link.Save();
    }

    static string X(string s) => SecurityElement.Escape(s) ?? "";

    static void Show(string xml, string? tag = null)
    {
        Try(RegisterProtocol);
        try
        {
            var doc = new XmlDocument();
            doc.LoadXml(xml);
            var toast = new ToastNotification(doc);
            if (tag is not null) { toast.Tag = tag; toast.Group = "nekodrop"; }
            ToastNotificationManager.CreateToastNotifier(Aumid).Show(toast);
        }
        catch (Exception) { /* no Start menu identity yet (a development run) */ }
    }

    /// <summary>"iPhone 想发送 2 张照片" with optional FileIcon hero preview and 接受 / 总是接受 / 拒绝.</summary>
    public static void AskToast(string id, string sender, string what, string? heroImagePath = null)
    {
        var accept = X($"nekodrop:answer?id={Uri.EscapeDataString(id)}&accept=1");
        var always = X($"nekodrop:answer?id={Uri.EscapeDataString(id)}&accept=1&always=1");
        var decline = X($"nekodrop:answer?id={Uri.EscapeDataString(id)}&accept=0");
        var heroXml = "";
        if (!string.IsNullOrEmpty(heroImagePath) && File.Exists(heroImagePath) && MediaHelper.IsToastPreviewable(heroImagePath))
            heroXml = $"\n                <image placement=\"hero\" src=\"{X(new Uri(heroImagePath).AbsoluteUri)}\"/>";
        Show($"""
            <toast scenario="reminder" launch="{X("nekodrop:open")}" activationType="protocol">
              <visual><binding template="ToastGeneric">
                <text>{X(L.F("ask.title", sender))}</text>
                <text>{X(what)}</text>{heroXml}
              </binding></visual>
              <actions>
                <action content="{X(L.T("accept"))}" arguments="{accept}" activationType="protocol"/>
                <action content="{X(L.T("accept.always"))}" arguments="{always}" activationType="protocol"/>
                <action content="{X(L.T("decline"))}" arguments="{decline}" activationType="protocol"/>
              </actions>
            </toast>
            """, "ask-" + id);
    }

    public static void DoneToast(string id, string title, string body, string? folder)
    {
        var launch = folder is null ? "nekodrop:open" : $"nekodrop:folder?path={Uri.EscapeDataString(folder)}";
        Show($"""
            <toast launch="{X(launch)}" activationType="protocol">
              <visual><binding template="ToastGeneric">
                <text>{X(title)}</text>
                <text>{X(body)}</text>
              </binding></visual>
            </toast>
            """);
        try { ToastNotificationManager.History.Remove("ask-" + id, "nekodrop", Aumid); }
        catch (Exception) { }
    }

    /// <summary>
    /// Rich notification after receiving files or links: optional hero image preview,
    /// one-click Copy to clipboard / Copy link, and Open link / Open folder.
    /// Hero preview + Copy to clipboard button UX inspired by DropBridge.
    /// </summary>
    public static void ReceivedToast(string id, string title, string body, string folder,
                                     string? recordId, string? heroImagePath = null, bool isLink = false,
                                     string? batchId = null, string? subtitle = null)
    {
        var launch = isLink && recordId is not null
            ? $"nekodrop:openurl?id={Uri.EscapeDataString(recordId)}"
            : $"nekodrop:folder?path={Uri.EscapeDataString(folder)}";
        var heroXml = "";
        if (!string.IsNullOrEmpty(heroImagePath) && File.Exists(heroImagePath) && MediaHelper.IsToastPreviewable(heroImagePath))
            heroXml = $"\n                <image placement=\"hero\" src=\"{X(new Uri(heroImagePath).AbsoluteUri)}\"/>";
        var subXml = string.IsNullOrEmpty(subtitle) ? "" : $"\n                <text>{X(subtitle)}</text>";

        var actionsXml = "";
        if (recordId is not null)
        {
            var copyArg = batchId is not null
                ? X($"nekodrop:copy?batch={Uri.EscapeDataString(batchId)}")
                : X($"nekodrop:copy?id={Uri.EscapeDataString(recordId)}");
            if (isLink)
            {
                var openUrlArg = X($"nekodrop:openurl?id={Uri.EscapeDataString(recordId)}");
                actionsXml = $"""
                  <actions>
                    <action content="{X(L.T("toast.openLink"))}" arguments="{openUrlArg}" activationType="protocol"/>
                    <action content="{X(L.T("toast.copyLink"))}" arguments="{copyArg}" activationType="protocol"/>
                  </actions>
                """;
            }
            else
            {
                var folderArg = X($"nekodrop:folder?path={Uri.EscapeDataString(folder)}");
                actionsXml = $"""
                  <actions>
                    <action content="{X(L.T("toast.copy"))}" arguments="{copyArg}" activationType="protocol"/>
                    <action content="{X(L.T("main.openFolder"))}" arguments="{folderArg}" activationType="protocol"/>
                  </actions>
                """;
            }
        }

        Show($"""
            <toast launch="{X(launch)}" activationType="protocol">
              <visual><binding template="ToastGeneric">
                <text>{X(title)}</text>
                <text>{X(body)}</text>{subXml}{heroXml}
              </binding></visual>
              {actionsXml}
            </toast>
            """);
        try { ToastNotificationManager.History.Remove("ask-" + id, "nekodrop", Aumid); }
        catch (Exception) { }
    }

    public static void CopiedToast(string title, string body)
    {
        Show($"""
            <toast launch="{X("nekodrop:open")}" activationType="protocol">
              <visual><binding template="ToastGeneric">
                <text>{X(title)}</text>
                <text>{X(body)}</text>
              </binding></visual>
            </toast>
            """, "copied");
    }

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    /// <summary>
    /// The files selected in the Explorer window in front, for the hotkey;
    /// none when Explorer is not in front or nothing is selected.
    /// </summary>
    public static string[] ExplorerSelection()
    {
        try
        {
            var front = GetForegroundWindow();
            if (Type.GetTypeFromProgID("Shell.Application") is not { } type || Activator.CreateInstance(type) is not { } shellApp) return [];
            dynamic shell = shellApp;
            foreach (dynamic window in shell.Windows())
            {
                try
                {
                    if (new IntPtr(Convert.ToInt64(window.HWND)) != front) continue;
                    var picked = new List<string>();
                    foreach (dynamic item in window.Document.SelectedItems()) picked.Add((string)item.Path);
                    return [.. picked];
                }
                catch (Exception) { /* not a folder window */ }
            }
        }
        catch (Exception) { }
        return [];
    }

    /// <summary>
    /// When Windows started nekodrop from the Share sheet (the sparse package's
    /// share target): the shared files' paths, and the sheet is told it is done.
    /// None for an ordinary start.
    /// </summary>
    public static string[] SharedFiles()
    {
        try
        {
            if (Windows.ApplicationModel.AppInstance.GetActivatedEventArgs() is not
                Windows.ApplicationModel.Activation.ShareTargetActivatedEventArgs share) return [];
            var op = share.ShareOperation;
            var items = op.Data.GetStorageItemsAsync().AsTask().GetAwaiter().GetResult();
            var paths = items.Select(i => i.Path).Where(p => !string.IsNullOrEmpty(p)).ToArray();
            op.ReportCompleted();
            return paths;
        }
        catch (Exception) { return []; /* not packaged, or not a share */ }
    }
}
