// SPDX-License-Identifier: GPL-2.0-only
using System.Reflection;

namespace NekoDrop;

/// <summary>
/// This build's version (0.1.16 of "0.1.16+commit"), shown in Settings → About
/// and in the window title.
/// </summary>
/// <remarks>
/// This fork has no updater: it neither checks nor installs releases, so nothing
/// here talks to the network and nothing replaces the installed files. A newer
/// build is installed by running its installer.
/// </remarks>
public static class AppVersion
{
    public static Version Current { get; } = Read();

    static Version Read()
    {
        var info = Assembly.GetEntryAssembly()
            ?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        var text = (info ?? "0.0.0").Split('+')[0];
        return Version.TryParse(text, out var v) ? v : new Version(0, 0, 0);
    }
}
