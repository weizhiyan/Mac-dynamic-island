using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Drawing = System.Drawing;
using Drawing2D = System.Drawing.Drawing2D;
using DrawingImaging = System.Drawing.Imaging;

namespace DynamicIsland.Core;

/// <summary>
/// 提取应用图标并缓存为 WPF ImageSource。
///
/// 取图优先级（全部是普通 Win32 API，不用 COM 互操作 —— 之前用 IImageList 取高清图标，
/// vtable 一旦不匹配会直接把进程打崩，托管 try/catch 拦不住）：
///   1) PrivateExtractIcons 按 256 → 128 → 64 → 48 → 32 依次取该尺寸的图标资源
///   2) SHGetFileInfo 大图标（32px）
///   3) Icon.ExtractAssociatedIcon
///   4) 首字母占位图
/// 全程走 HICON → CreateBitmapSourceFromHIcon / 32bpp BGRA 直拷，保留 alpha。
/// </summary>
public static class IconLoader
{
    private static readonly ConcurrentDictionary<string, ImageSource> Cache = new();

    private const uint SHGFI_ICON = 0x100;
    private const uint SHGFI_LARGEICON = 0x0;
    private const int MAX_PATH = 260;

    private static readonly int[] IconSizes = { 256, 128, 64, 48, 32 };

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEINFO
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MAX_PATH)]
        public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string szTypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbSizeFileInfo, uint uFlags);

    /// <summary>按指定尺寸提取图标（可拿到 256px 大图，不会像 GetHbitmap 那样丢 alpha）。</summary>
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint PrivateExtractIcons(string szFileName, int nIconIndex, int cxIcon, int cyIcon,
        IntPtr[] phicon, uint[]? piconid, uint nIcons, uint flags);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public static ImageSource IconFor(AppItem item)
    {
        var key = item.Path ?? item.Name;
        if (Cache.TryGetValue(key, out var cached)) return cached;

        var image = Load(item);
        Cache.TryAdd(key, image);
        return image;
    }

    private static ImageSource Load(AppItem item)
    {
        var path = ResolvePath(item.Path);
        if (!string.IsNullOrEmpty(path))
        {
            var large = FromHIcon(ExtractLarge(path));
            if (large != null) return large;

            var shell = FromHIcon(GetShellIcon(path));
            if (shell != null) return shell;

            var associated = ExtractAssociated(path);
            if (associated != null) return associated;
        }
        return CreateFallback(item.Name);
    }

    /// <summary>.lnk 快捷方式先解析出真实目标，才能取到目标程序的高清图标。</summary>
    private static string? ResolvePath(string? path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        try
        {
            if (Path.GetExtension(path).Equals(".lnk", StringComparison.OrdinalIgnoreCase))
            {
                using var shell = new ShellLinkResolver();
                var target = shell.Target(path);
                if (!string.IsNullOrEmpty(target) && File.Exists(target)) return target;
            }
            return File.Exists(path) ? path : null;
        }
        catch { return null; }
    }

    private static IntPtr ExtractLarge(string path)
    {
        foreach (int size in IconSizes)
        {
            try
            {
                var handles = new IntPtr[1];
                var count = PrivateExtractIcons(path, 0, size, size, handles, null, 1, 0);
                if (count > 0 && handles[0] != IntPtr.Zero) return handles[0];
            }
            catch { /* 换下一个尺寸 */ }
        }
        return IntPtr.Zero;
    }

    private static IntPtr GetShellIcon(string path)
    {
        try
        {
            var info = new SHFILEINFO();
            var result = SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf<SHFILEINFO>(), SHGFI_ICON | SHGFI_LARGEICON);
            if (result == IntPtr.Zero || info.hIcon == IntPtr.Zero) return IntPtr.Zero;
            return info.hIcon;
        }
        catch { return IntPtr.Zero; }
    }

    /// <summary>HICON → WPF 位图（CreateBitmapSourceFromHIcon 能正确保留 32bpp alpha）。</summary>
    private static ImageSource? FromHIcon(IntPtr hIcon)
    {
        if (hIcon == IntPtr.Zero) return null;
        try
        {
            var source = Imaging.CreateBitmapSourceFromHIcon(hIcon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        catch { return null; }
        finally { DestroyIcon(hIcon); }
    }

    private static ImageSource? ExtractAssociated(string path)
    {
        try
        {
            using var icon = Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon == null) return null;
            using var bmp = icon.ToBitmap();
            return ToImageSource(bmp);
        }
        catch { return null; }
    }

    /// <summary>Bitmap → BitmapSource：直接拷 32bpp BGRA 像素，不用 GetHbitmap（会丢 alpha）。</summary>
    private static ImageSource ToImageSource(Drawing.Bitmap bmp)
    {
        using var normalized = bmp.Clone(
            new Drawing.Rectangle(0, 0, bmp.Width, bmp.Height),
            DrawingImaging.PixelFormat.Format32bppArgb);
        var data = normalized.LockBits(
            new Drawing.Rectangle(0, 0, normalized.Width, normalized.Height),
            DrawingImaging.ImageLockMode.ReadOnly,
            DrawingImaging.PixelFormat.Format32bppArgb);
        try
        {
            int stride = Math.Abs(data.Stride);
            var source = BitmapSource.Create(
                normalized.Width, normalized.Height, 96, 96,
                PixelFormats.Bgra32, null,
                data.Scan0, stride * normalized.Height, stride);
            source.Freeze();
            return source;
        }
        finally
        {
            normalized.UnlockBits(data);
        }
    }

    /// <summary>找不到图标时的占位：圆角深灰方块 + 应用首字母。</summary>
    public static ImageSource CreateFallback(string name)
    {
        const int size = 128;
        const float radius = 28;
        using var bmp = new Drawing.Bitmap(size, size, DrawingImaging.PixelFormat.Format32bppArgb);
        using (var g = Drawing.Graphics.FromImage(bmp))
        {
            g.SmoothingMode = Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

            using var path = new Drawing2D.GraphicsPath();
            path.AddArc(0, 0, radius, radius, 180, 90);
            path.AddArc(size - radius, 0, radius, radius, 270, 90);
            path.AddArc(size - radius, size - radius, radius, radius, 0, 90);
            path.AddArc(0, size - radius, radius, radius, 90, 90);
            path.CloseFigure();
            using var fill = new Drawing.SolidBrush(Drawing.Color.FromArgb(255, 56, 56, 60));
            g.FillPath(fill, path);

            var text = string.IsNullOrEmpty(name) ? "?" : name.Substring(0, 1).ToUpperInvariant();
            using var font = new Drawing.Font("Segoe UI", 56, Drawing.FontStyle.Bold, Drawing.GraphicsUnit.Pixel);
            using var brush = new Drawing.SolidBrush(Drawing.Color.FromArgb(235, 255, 255, 255));
            using var format = new Drawing.StringFormat
            {
                Alignment = Drawing.StringAlignment.Center,
                LineAlignment = Drawing.StringAlignment.Center,
            };
            g.DrawString(text, font, brush, new Drawing.RectangleF(0, 0, size, size), format);
        }
        return ToImageSource(bmp);
    }
}
