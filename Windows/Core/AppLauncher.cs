using System.Diagnostics;
using System.IO;

namespace DynamicIsland.Core;

/// <summary>启动快捷应用。支持 .exe 与 .lnk 快捷方式。</summary>
public static class AppLauncher
{
    public static void Launch(AppItem item)
    {
        if (string.IsNullOrEmpty(item.Path)) return;
        try
        {
            if (Path.GetExtension(item.Path).Equals(".lnk", StringComparison.OrdinalIgnoreCase))
            {
                using var shell = new ShellLinkResolver();
                var target = shell.Target(item.Path);
                if (!string.IsNullOrEmpty(target))
                {
                    Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
                    return;
                }
            }
            Process.Start(new ProcessStartInfo(item.Path) { UseShellExecute = true });
        }
        catch { /* 启动失败忽略 */ }
    }
}

/// <summary>解析 .lnk 快捷方式的目标路径（通过 Windows Script Host）。</summary>
public sealed class ShellLinkResolver : IDisposable
{
    private dynamic? _shell;

    public ShellLinkResolver()
    {
        _shell = System.Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")!);
    }

    public string? Target(string lnkPath)
    {
        try
        {
            if (_shell is null) return null;
            return (string?)_shell.CreateShortcut(lnkPath).TargetPath;
        }
        catch { return null; }
    }

    public void Dispose()
    {
        try { _shell = null; } catch { }
    }
}