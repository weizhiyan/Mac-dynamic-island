using System.Drawing;
using DynamicIsland.Core;

namespace DynamicIsland.Ui;

/// <summary>
/// 系统托盘图标 + 上下文菜单。图标为一枚黑色胶囊（意象呼应灵动岛）。
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private readonly System.Windows.Forms.NotifyIcon _notify;

    private string? _pendingUpdateUrl;

    public TrayIcon(Action showIsland, Action openSettings, Action checkUpdates, Action quit)
    {
        _notify = new System.Windows.Forms.NotifyIcon
        {
            Text = "灵动岛",
            Icon = CreateIcon(),
            Visible = true,
        };

        var menu = new System.Windows.Forms.ContextMenuStrip();
        var miShow = new System.Windows.Forms.ToolStripMenuItem("显示 / 隐藏") { Font = new System.Drawing.Font("Segoe UI", 9F) };
        miShow.Click += (_, _) => showIsland();
        var miSettings = new System.Windows.Forms.ToolStripMenuItem("设置") { Font = new System.Drawing.Font("Segoe UI", 9F) };
        miSettings.Click += (_, _) => openSettings();
        var miUpdate = new System.Windows.Forms.ToolStripMenuItem("检查更新") { Font = new System.Drawing.Font("Segoe UI", 9F) };
        miUpdate.Click += (_, _) => checkUpdates();
        var miQuit = new System.Windows.Forms.ToolStripMenuItem("退出") { Font = new System.Drawing.Font("Segoe UI", 9F) };
        miQuit.Click += (_, _) => quit();
        menu.Items.Add(miShow);
        menu.Items.Add(miSettings);
        menu.Items.Add(miUpdate);
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(miQuit);
        _notify.ContextMenuStrip = menu;
        _notify.BalloonTipClicked += (_, _) =>
        {
            if (!string.IsNullOrEmpty(_pendingUpdateUrl))
                UpdateService.OpenUrl(_pendingUpdateUrl);
        };
    }

    public void NotifyUpdate(string version, string url)
    {
        _pendingUpdateUrl = url;
        _notify.BalloonTipTitle = "灵动岛";
        _notify.BalloonTipText = $"发现新版本 {version}，点击下载。";
        _notify.ShowBalloonTip(8000);
    }

    /// <summary>生成一枚黑色胶囊托盘图标。</summary>
    private static Icon CreateIcon()
    {
        var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            using var brush = new SolidBrush(Color.FromArgb(235, 235, 235));
            g.FillRoundedRectangle(brush, new Rectangle(4, 9, 24, 13), 6);
            g.FillEllipse(brush, new Rectangle(9, 6, 14, 5));
        }
        var hIcon = bmp.GetHicon();
        using var ico = Icon.FromHandle(hIcon);
        return (Icon)ico.Clone();
    }

    public void Dispose()
    {
        _notify.Visible = false;
        _notify.Dispose();
    }
}

internal static class GraphicsExtensions
{
    public static void FillRoundedRectangle(this Graphics g, Brush brush, Rectangle rect, int radius)
    {
        using var path = new System.Drawing.Drawing2D.GraphicsPath();
        int d = radius * 2;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(brush, path);
    }
}