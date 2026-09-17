using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using DynamicIsland.Core;
using DynamicIsland.Native;

namespace DynamicIsland.Island;

/// <summary>
/// 单个快捷应用图标格：高清图标 + 悬停高亮底/轻微放大 + 点击启动 + 名称气泡。
/// 磁吸放大倍数由外部按全局光标距离写入（见 ContentIslandWindow.SetCursorPosition），
/// 放大中的格子会提到最上层，避免被相邻格子压住。
/// </summary>
public sealed class AppCell : Grid
{
    private const int MagnifiedZIndex = 100;

    private readonly AppItem _item;
    private readonly ToolTipPopup? _tooltip;
    private readonly Image _image;
    private readonly Border _highlight;

    private readonly TranslateTransform _translate = new();
    private readonly ScaleTransform _scale = new();
    private readonly ScaleTransform _hoverScale = new();
    private readonly TransformGroup _transform;

    private double _magnification = 1;

    public AppItem Item => _item;

    public AppCell(AppItem item, ToolTipPopup? tooltip)
    {
        _item = item;
        _tooltip = tooltip;

        VerticalAlignment = VerticalAlignment.Top;
        HorizontalAlignment = HorizontalAlignment.Left;
        Opacity = 0;   // 展开时由淡入动画驱动

        _transform = new TransformGroup();
        _transform.Children.Add(_translate);
        _transform.Children.Add(_scale);
        _transform.Children.Add(_hoverScale);
        RenderTransformOrigin = new Point(0.5, 0.5);
        RenderTransform = _transform;

        // 悬停高亮底：只做背景提亮，不裁切图标本体（画图、截图工具等非方形图标不会被切角）
        _highlight = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(12),
            Opacity = 0,
        };
        Children.Add(_highlight);

        _image = new Image
        {
            Stretch = Stretch.Uniform,
            Margin = new Thickness(4),
            IsHitTestVisible = false,
            // 不做投影：扁平是这套设计语言的基调（投影见 AppleTheme 规范）
        };
        RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
        Children.Add(_image);

        Cursor = Cursors.Hand;

        MouseEnter += (_, _) => { SetHover(true); _tooltip?.Show(_item, IconAnchor()); };
        MouseLeave += (_, _) => { SetHover(false); _tooltip?.Hide(_item); };
    }

    /// <summary>设置格子尺寸并加载图标。</summary>
    public void Configure(double size)
    {
        Width = Height = size;
        _highlight.CornerRadius = new CornerRadius(Math.Max(8, size * 0.22));
        _image.Source = IconLoader.IconFor(_item);
        UpdateTransform();
    }

    /// <summary>淡入/淡出：透明度 + 从下方 14px 归位。</summary>
    public void Reveal(bool visible)
    {
        Opacity = visible ? 1 : 0;
        _translate.Y = visible ? 0 : 14;
    }

    /// <summary>由 ContentIslandWindow 逐帧写入淡入/淡出透明度。</summary>
    public void ApplyRevealOpacity(double opacity)
        => Opacity = Math.Clamp(opacity, 0, 1);

    /// <summary>外部按光标到格子中心的距离写入放大倍数（磁吸）。</summary>
    public void SetMagnification(double mag)
    {
        if (Math.Abs(mag - _magnification) < 0.002) return;
        _magnification = mag;
        UpdateTransform();
        Panel.SetZIndex(this, mag > 1.01 ? MagnifiedZIndex : 0);
    }

    private void UpdateTransform()
    {
        _scale.ScaleX = _scale.ScaleY = _magnification;
    }

    private void SetHover(bool hovered)
    {
        _highlight.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation
        {
            To = hovered ? 1 : 0,
            Duration = TimeSpan.FromMilliseconds(hovered ? 90 : 70),
        });
        _hoverScale.BeginAnimation(ScaleTransform.ScaleXProperty, ScaleAnim(hovered ? 1.04 : 1.0));
        _hoverScale.BeginAnimation(ScaleTransform.ScaleYProperty, ScaleAnim(hovered ? 1.04 : 1.0));
    }

    private static DoubleAnimation ScaleAnim(double to) => new()
    {
        To = to,
        Duration = TimeSpan.FromMilliseconds(120),
        EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
    };

    /// <summary>
    /// 图标中心在屏幕上的位置（DIP），作为气泡锚点：水平居中于图标、贴在图标下沿。
    /// 格子由 Canvas.Left/Top 定位，所以用「窗口位置 + 画布坐标」算 ——
    /// 不再用光标位置（从斜角划进格子时，光标会贴着边缘，气泡就偏到图标一侧了）。
    /// </summary>
    private Point IconAnchor()
    {
        var win = Window.GetWindow(this);
        double x = win?.Left ?? 0;
        double y = win?.Top ?? 0;
        if (Parent is Canvas canvas)
        {
            x += Canvas.GetLeft(this);
            y += Canvas.GetTop(this);
        }

        double size = ActualWidth > 0 ? ActualWidth : (double.IsNaN(Width) ? 0 : Width);
        double mag = _magnification * _hoverScale.ScaleX;
        return new Point(x + size / 2, y + size / 2 + size / 2 * mag);
    }

    protected override void OnMouseDown(MouseButtonEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.ChangedButton == MouseButton.Left)
            AppLauncher.Launch(_item);
    }
}
