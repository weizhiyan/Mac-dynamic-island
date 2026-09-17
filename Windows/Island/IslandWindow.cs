using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using DynamicIsland.Core;
using DynamicIsland.Native;
using Forms = System.Windows.Forms;
// System.Windows.Shapes.Path 与 System.IO.Path 同名，统一用别名引用，避免二义性
using ShapePath = System.Windows.Shapes.Path;

namespace DynamicIsland.Island;

/// <summary>
/// gooey 绘制窗口：承载黑色岛体形状，全程置顶、不激活、整窗穿透点击（WS_EX_TRANSPARENT）。
/// 仅作视觉层，交互内容由 ContentIslandWindow 承担。
/// </summary>
public sealed class IslandWindow : Window
{
    private readonly IslandSettings _settings;
    private readonly ShapePath _island = new();
    /// <summary>常驻的触发区预览红条（设置面板里勾选后存在）。</summary>
    private Window? _zonePreview;

    public ShapeMorpher Morpher { get; }
    public ShapePath IslandPath => _island;

    public IslandWindow(IslandSettings settings)
    {
        _settings = settings;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowActivated = false;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        IsHitTestVisible = true; // 整窗穿透由 WS_EX_TRANSPARENT 负责

        _island.Fill = Brushes.Black;
        // 不做投影：整块纯黑 + 无阴影才是 mac 灵动岛/刘海的观感（投影会让矩形边界显形）

        var canvas = new Canvas { Background = Brushes.Transparent };
        Canvas.SetZIndex(_island, 0);
        canvas.Children.Add(_island);
        Content = canvas;

        Morpher = new ShapeMorpher(settings, geo =>
        {
            if (Dispatcher.CheckAccess())
            {
                _island.Data = geo;
            }
            else
            {
                Dispatcher.InvokeAsync(() => _island.Data = geo);
            }
        });
    }

    /// <summary>应用当前几何（初始/屏幕变化）。</summary>
    public void RenderCompact() => Morpher.JumpTo(false);

    public void ShowAtTopCenter()
    {
        ApplyWindowRect(expanded: false);
        Show();
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd != IntPtr.Zero)
        {
            Win32.SetClickThrough(hwnd, transparent: true);
            Win32.ForceTopmost(hwnd);
        }
    }

    /// <summary>按当前屏幕与布局设置窗口尺寸与位置（贴工作区顶部居中，可整体位移）。</summary>
    public void ApplyWindowRect(bool expanded)
    {
        double w = IslandShape.WindowWidth(_settings);
        double h = IslandShape.WindowHeight(_settings);
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double cx = screen.Left + screen.Width / 2.0;
        Left = cx - w / 2;
        Top = DpiHelper.IslandTop() + _settings.IslandYOffset;
        Width = w;
        Height = h;
        UpdateTriggerZonePreview();   // 常驻红条跟随几何变化
    }

    /// <summary>
    /// 重新把自己提到最顶层。其他置顶窗口（任务栏、某些游戏/工具）可能把自己插到我们之上，
    /// 而绘制层一旦被压住，黑色岛体就会缺一块（内容层的按钮仍在最上面，看起来像浮在面板外）。
    /// 本窗口是整窗点击穿透的，重新置顶不影响按钮交互。
    /// </summary>
    public void BringToFront()
    {
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd != IntPtr.Zero) Win32.ForceTopmost(hwnd);
        }
        catch { /* 忽略置顶失败 */ }
    }

    /// <summary>预览触发区域：顶部一条红色半透明条（3 秒后自动消失）。</summary>
    public void ShowTriggerZonePreview()
    {
        var win = BuildTriggerZoneWindow();
        win.Show();
        var hwnd = new WindowInteropHelper(win).Handle;
        Win32.SetClickThrough(hwnd, true);

        // 3 秒后消失
        var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        t.Tick += (_, _) => { t.Stop(); win.Close(); };
        t.Start();
    }

    /// <summary>
    /// 常驻显示触发区（设置面板里勾选后用）：红条跟随触发区参数实时更新，
    /// 这样一边拖「触发区偏移/尺寸」一边就能看到位置对不对。
    /// </summary>
    public void SetTriggerZonePreviewVisible(bool visible)
    {
        if (!visible)
        {
            _zonePreview?.Close();
            _zonePreview = null;
            return;
        }
        if (_zonePreview == null)
        {
            _zonePreview = BuildTriggerZoneWindow();
            _zonePreview.Show();
            var hwnd = new WindowInteropHelper(_zonePreview).Handle;
            Win32.SetClickThrough(hwnd, true);
        }
        UpdateTriggerZonePreview();
    }

    /// <summary>让常驻红条跟上当前几何（尺寸/位置变化时调用）。</summary>
    private void UpdateTriggerZonePreview()
    {
        if (_zonePreview == null) return;
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double zx = _settings.HoverZoneWidth;
        double zy = Math.Max(_settings.HoverZoneHeight, 3);
        double cx = screen.Left + screen.Width / 2.0;
        _zonePreview.Width = zx;
        _zonePreview.Height = zy;
        _zonePreview.Left = cx - zx / 2;
        _zonePreview.Top = TriggerZoneTop();
    }

    private Window BuildTriggerZoneWindow()
    {
        var win = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            Width = _settings.HoverZoneWidth,
            Height = Math.Max(_settings.HoverZoneHeight, 3),
            Left = 0,
            Top = TriggerZoneTop(),
            Opacity = 0.7,
        };
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        win.Left = screen.Left + screen.Width / 2.0 - win.Width / 2;
        var rect = new Rectangle { Fill = new SolidColorBrush(Color.FromArgb(0xAA, 0xFF, 0x3B, 0x30)), RadiusX = 3, RadiusY = 3 };
        win.Content = rect;
        return win;
    }

    /// <summary>触发区在屏幕上的纵向位置（与 HoverDetector 计算保持一致，基准是岛体顶端）。</summary>
    public double TriggerZoneTop()
    {
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double islandTop = DpiHelper.IslandTop() + _settings.IslandYOffset;
        double top = islandTop + _settings.HoverZoneYOffset - _settings.HoverZoneHeight;
        return Math.Max(islandTop, Math.Min(top, screen.Bottom - _settings.HoverZoneHeight));
    }
}