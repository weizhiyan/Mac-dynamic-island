using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using DynamicIsland.Core;
using DynamicIsland.Native;
using Forms = System.Windows.Forms;

namespace DynamicIsland.Island;

/// <summary>
/// 内容交互窗口：顶部控制按钮（设置 / 添加）+ 应用图标网格 + 磁吸放大。
/// 仅在岛体展开时显示并接收点击；收缩时隐藏。
/// 布局说明：面板宽度按实际可见应用数收窄（不足一行不收满列），每行水平居中，
/// 单元格中心在 Rebuild 时一次性算好，供逐帧磁吸计算复用。
/// </summary>
public sealed class ContentIslandWindow : Window
{
    private readonly IslandSettings _settings;
    private readonly AppStore _store;
    private readonly ToolTipPopup _tooltip = new();

    private readonly Canvas _gridCanvas = new();
    private readonly Canvas _topControls = new();
    private readonly List<AppCell> _cells = new();
    /// <summary>单元格中心（窗口局部 DIP）：key = AppItem.Id（Guid）。</summary>
    private readonly Dictionary<Guid, Point> _cellCenters = new();

    private System.Windows.Threading.DispatcherTimer? _revealTimer;
    private System.Windows.Threading.DispatcherTimer? _delayTimer;
    private bool _expanded;
    private bool _visible;

    private readonly Action _onSettings;
    private readonly Action _onAdd;

    public ContentIslandWindow(IslandSettings settings, AppStore store, Action onSettings, Action onAdd)
    {
        _settings = settings;
        _store = store;
        _onSettings = onSettings;
        _onAdd = onAdd;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowActivated = false;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;

        // 网格先加、控制按钮后加（按钮在最上层，避免被网格 Canvas 抢走点击）
        var root = new Grid { Background = Brushes.Transparent };
        root.Children.Add(_gridCanvas);
        BuildTopControls();
        root.Children.Add(_topControls);
        Content = root;

        Rebuild();
    }

    /// <summary>由岛体控制器在设置/应用变化时触发重建网格。</summary>
    public void RebuildForSettingsChange() => Rebuild();

    public void ApplyWindowRect()
    {
        int count = _store.VisibleApps.Count;
        double w = _settings.ContentWidth(count);
        double h = _settings.ExpandedHeight(count);
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double cx = screen.Left + screen.Width / 2.0;
        Left = cx - w / 2;
        // 内容层贴在顶栏下沿（= 面板 body 的顶部），顶部按钮与图标因此都落在黑色面板内
        Top = DpiHelper.IslandTop() + _settings.IslandYOffset + _settings.TopBarHeight;
        Width = w;
        Height = h;
        DebugLog.Write($"content: apps={count} W={w:0} H={h:0} @({Left:0},{Top:0})  顶栏宽={IslandShape.BarWidth(_settings):0}");
    }

    /// <summary>
    /// 把自己提到最顶层。内容层必须始终高于绘制层（IslandWindow 的黑色面板），
    /// 否则黑色面板会盖住图标与按钮，看起来就是「一团黑」。
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

    /// <summary>展开：定位、显示、内容淡入（先延迟再淡入）。</summary>
    public void ShowContent(double revealDelay, double fadeInDuration, double collapseDuration)
    {
        if (_visible && _expanded) return;
        _expanded = true;
        _visible = true;
        ApplyWindowRect();
        Show();
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd != IntPtr.Zero) Win32.ForceTopmost(hwnd);

        // 先全部隐藏
        foreach (var c in _cells) c.Reveal(false);
        _topControls.Opacity = 0;

        // 延迟后淡入
        StartReveal(revealDelay, fadeInDuration);
    }

    private void StartReveal(double delay, double fadeDur)
    {
        _revealTimer?.Stop();
        double progress = 0;
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        timer.Tick += (_, _) =>
        {
            progress = Math.Min(1, progress + 16.0 / Math.Max(1, fadeDur * 1000.0));
            double eased = progress * progress * (3 - 2 * progress);
            foreach (var c in _cells)
            {
                c.Reveal(true);
                c.ApplyRevealOpacity(eased);
            }
            _topControls.Opacity = eased;
            if (progress >= 1)
            {
                timer.Stop();
                // 淡入完成后再次确保自己压在绘制层之上（防被其他置顶窗口打乱顺序）
                BringToFront();
            }
        };
        _revealTimer = timer;

        StartDelayTimer(delay, timer.Start);
    }

    private void StartDelayTimer(double delay, Action action)
    {
        _delayTimer?.Stop();
        if (delay <= 0) { action(); return; }
        var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(delay) };
        t.Tick += (_, _) => { t.Stop(); action(); };
        t.Start();
        _delayTimer = t;
    }

    /// <summary>收起：淡出后隐藏窗口。</summary>
    public void HideContent(double fadeOutDur, double collapseDuration)
    {
        if (!_expanded) return;
        _expanded = false;
        _revealTimer?.Stop();
        _delayTimer?.Stop();

        double done = 0;
        var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        t.Tick += (_, _) =>
        {
            done = Math.Min(1, done + 16.0 / Math.Max(1, fadeOutDur * 1000.0));
            double eased = Math.Max(0, 1 - done);
            foreach (var c in _cells) c.ApplyRevealOpacity(eased);
            _topControls.Opacity = eased;
            if (done >= 1)
            {
                t.Stop();
                Hide();
                _visible = false;
                _tooltip.HideAll();
            }
        };
        t.Start();
    }

    /// <summary>立即隐藏（不带动画）。</summary>
    public void HideImmediate()
    {
        _revealTimer?.Stop();
        _delayTimer?.Stop();
        _expanded = false;
        _visible = false;
        Hide();
        _tooltip.HideAll();
    }

    /// <summary>由 HoverDetector 每帧上报光标（屏幕 DIP），驱动磁吸放大。</summary>
    public void SetCursorPosition(Point screen)
    {
        if (!_expanded) return;
        double iconSize = _settings.IconSize;
        double radius = Math.Max(iconSize * 1.85, 96);
        double originX = Left;
        double originY = Top;

        foreach (var cell in _cells)
        {
            if (!_cellCenters.TryGetValue(cell.Item.Id, out var center)) continue;
            double dx = screen.X - (originX + center.X);
            double dy = screen.Y - (originY + center.Y);
            double dist = Math.Sqrt(dx * dx + dy * dy);

            double mag = 1;
            if (dist < radius)
            {
                double infl = 1 - dist / radius;
                double eased = infl * infl * (3 - 2 * infl);
                mag = 1 + eased * 0.28;
            }
            cell.SetMagnification(mag);
        }
    }

    private void Rebuild()
    {
        _gridCanvas.Children.Clear();
        _cells.Clear();
        _cellCenters.Clear();

        var apps = _store.VisibleApps.ToList();
        double iconSize = _settings.IconSize;
        double pitchX = iconSize + _settings.IconSpacing;
        double pitchY = iconSize + _settings.IconSpacing;
        int cols = Math.Max(1, _settings.Columns);
        double panelWidth = _settings.ContentWidth(apps.Count);
        double top = _settings.EffectiveContentTopPadding;

        for (int i = 0; i < apps.Count; i++)
        {
            int row = i / cols;
            int rowStart = row * cols;
            int countInRow = Math.Min(cols, apps.Count - rowStart);
            int colInRow = i - rowStart;

            // 每行水平居中：不足一行的尾行不会偏在左侧
            double rowWidth = countInRow * iconSize + (countInRow - 1) * _settings.IconSpacing;
            double rowLeft = (panelWidth - rowWidth) / 2;

            double x = rowLeft + colInRow * pitchX;
            double y = top + row * pitchY;

            var cell = new AppCell(apps[i], _tooltip);
            cell.Configure(iconSize);
            Canvas.SetLeft(cell, x);
            Canvas.SetTop(cell, y);

            _cells.Add(cell);
            _cellCenters[apps[i].Id] = new Point(x + iconSize / 2, y + iconSize / 2);
            _gridCanvas.Children.Add(cell);
        }

        _gridCanvas.Width = panelWidth;
        _gridCanvas.Height = Math.Max(top, _settings.ExpandedHeight(Math.Max(1, apps.Count)));

        // 顶部按钮的右对齐锚点：显式给 Canvas 宽度，避免依赖它在 Grid 里的拉伸行为
        _topControls.Width = panelWidth;

        var firstCenter = apps.Count > 0 && _cellCenters.TryGetValue(apps[0].Id, out var c0) ? c0 : new Point();
        DebugLog.Write($"rebuild: apps={apps.Count} cols={cols} panel={panelWidth:0} 首个格子中心=({firstCenter.X:0},{firstCenter.Y:0})");

        // 内容变化后同步窗口尺寸/位置，避免窗口尺寸与应用数不一致（图标被裁、按钮跑到面板外）
        ApplyWindowRect();
    }

    /// <summary>顶部悬浮控制按钮：设置（左）与添加应用（右）。</summary>
    private void BuildTopControls()
    {
        _topControls.Children.Clear();
        const double controlSize = 28;
        const double top = 5;

        var gear = MakeControlButton("\uE713", "设置", controlSize, () => _onSettings());
        Canvas.SetLeft(gear, _settings.ContentPadding - 2);
        Canvas.SetTop(gear, top);

        var plus = MakeControlButton("\uE710", "添加应用", controlSize, () => _onAdd());
        Canvas.SetRight(plus, _settings.ContentPadding - 2);
        Canvas.SetTop(plus, top);

        _topControls.Children.Add(gear);
        _topControls.Children.Add(plus);
    }

    private static Button MakeControlButton(string glyph, string tooltip, double size, Action action)
    {
        var btn = new Button
        {
            Width = size,
            Height = size,
            Content = new TextBlock
            {
                Text = glyph,
                FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromArgb(0xE0, 0xFF, 0xFF, 0xFF)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
            Background = new SolidColorBrush(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x2E, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            Cursor = Cursors.Hand,
            Focusable = false,
            ToolTip = tooltip,
            Template = CircleButtonTemplate(size),
            SnapsToDevicePixels = true,
        };
        btn.Click += (_, _) => action();
        return btn;
    }

    /// <summary>
    /// 圆形按钮模板：完全替换 WPF 默认按钮外观（默认模板会带浅灰描边、悬停变蓝，
    /// 在黑色岛体上非常突兀），只保留轻微提亮作为悬停/按下反馈。
    /// </summary>
    private static ControlTemplate CircleButtonTemplate(double size)
    {
        var border = new FrameworkElementFactory(typeof(Border), "bd");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(size / 2));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
        border.SetValue(Border.BorderBrushProperty, new TemplateBindingExtension(Control.BorderBrushProperty));
        border.SetValue(Border.BorderThicknessProperty, new TemplateBindingExtension(Control.BorderThicknessProperty));

        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(presenter);

        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };
        template.Triggers.Add(BackgroundTrigger(UIElement.IsMouseOverProperty, 0x33));
        template.Triggers.Add(BackgroundTrigger(Button.IsPressedProperty, 0x4D));
        return template;
    }

    private static Trigger BackgroundTrigger(DependencyProperty property, byte alpha)
    {
        var trigger = new Trigger { Property = property, Value = true };
        trigger.Setters.Add(new Setter(
            Border.BackgroundProperty,
            new SolidColorBrush(Color.FromArgb(alpha, 0xFF, 0xFF, 0xFF)),
            "bd"));
        return trigger;
    }
}
