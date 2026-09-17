using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using DynamicIsland.Core;
using DynamicIsland.Native;
using DynamicIsland.Ui;
using Forms = System.Windows.Forms;

namespace DynamicIsland.Island;

/// <summary>
/// 悬停应用名气泡：浅色 NSPopover。置顶、不激活、点击穿透。
/// 锚在图标下方，水平居中；带三角箭头、轻投影、弹出缩放。
/// 投影打在后面一层剪影上，文字层不加 Effect，避免 WPF 把字一起栅格化变糊。
/// </summary>
public sealed class ToolTipPopup
{
    private const double ArrowWidth = 14;
    private const double ArrowHeight = 7;
    private const double BorderWidth = 1;

    private readonly Window _win;
    private readonly Grid _visual;
    private readonly Border _bubble;
    private readonly Border _shadowBubble;
    private readonly System.Windows.Shapes.Path _arrowTop;
    private readonly System.Windows.Shapes.Path _arrowBottom;
    private readonly System.Windows.Shapes.Path _shadowArrowTop;
    private readonly System.Windows.Shapes.Path _shadowArrowBottom;
    private readonly TextBlock _text;
    private readonly ScaleTransform _scale = new(1, 1);
    private readonly TranslateTransform _arrowTopShift = new();
    private readonly TranslateTransform _arrowBottomShift = new();
    private readonly TranslateTransform _shadowArrowTopShift = new();
    private readonly TranslateTransform _shadowArrowBottomShift = new();

    private AppItem? _current;
    private bool _hiding;
    private int _token;

    public ToolTipPopup()
    {
        _text = new TextBlock
        {
            FontFamily = AppleTheme.Font,
            FontSize = AppleTheme.TooltipTextSize,
            FontWeight = AppleTheme.WeightMedium,
            Foreground = AppleTheme.TextPrimary,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        TextOptions.SetTextRenderingMode(_text, TextRenderingMode.ClearType);
        TextOptions.SetTextFormattingMode(_text, TextFormattingMode.Display);

        _bubble = new Border
        {
            Background = AppleTheme.TooltipBg,
            BorderBrush = AppleTheme.TooltipBorder,
            BorderThickness = new Thickness(BorderWidth),
            CornerRadius = new CornerRadius(AppleTheme.TooltipRadius),
            Padding = AppleTheme.TooltipPadding,
            SnapsToDevicePixels = true,
            Child = _text,
        };

        _shadowBubble = new Border
        {
            Background = AppleTheme.TooltipBg,
            CornerRadius = new CornerRadius(AppleTheme.TooltipRadius),
            SnapsToDevicePixels = true,
        };

        _arrowTop = MakeArrow(pointingUp: true);
        _arrowTop.RenderTransform = _arrowTopShift;
        _arrowTop.Margin = new Thickness(0, 0, 0, -1);
        _arrowBottom = MakeArrow(pointingUp: false);
        _arrowBottom.RenderTransform = _arrowBottomShift;
        _arrowBottom.Margin = new Thickness(0, -1, 0, 0);

        _shadowArrowTop = MakeArrow(pointingUp: true);
        _shadowArrowTop.RenderTransform = _shadowArrowTopShift;
        _shadowArrowTop.Margin = new Thickness(0, 0, 0, -1);
        _shadowArrowBottom = MakeArrow(pointingUp: false);
        _shadowArrowBottom.RenderTransform = _shadowArrowBottomShift;
        _shadowArrowBottom.Margin = new Thickness(0, -1, 0, 0);

        var shadowLayout = MakeArrowLayout(_shadowArrowTop, _shadowBubble, _shadowArrowBottom);
        shadowLayout.Effect = new DropShadowEffect
        {
            Color = Color.FromArgb(0x3D, 0, 0, 0),
            BlurRadius = 18,
            ShadowDepth = 1.2,
            Direction = 270,
            Opacity = 1,
            RenderingBias = RenderingBias.Quality,
        };

        var layout = MakeArrowLayout(_arrowTop, _bubble, _arrowBottom);

        _visual = new Grid
        {
            RenderTransform = _scale,
            RenderTransformOrigin = new Point(0.5, 0),
        };
        _visual.Children.Add(shadowLayout);
        _visual.Children.Add(layout);

        var host = new Border
        {
            Padding = new Thickness(AppleTheme.TooltipShadowPad),
            Background = Brushes.Transparent,
            Child = _visual,
            IsHitTestVisible = false,
        };

        _win = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Topmost = true,
            ShowActivated = false,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            IsHitTestVisible = false,
            UseLayoutRounding = true,
            SnapsToDevicePixels = true,
            Content = host,
            Opacity = 0,
        };
        _win.SourceInitialized += (_, _) => ApplyClickThrough();
    }

    public void Show(AppItem item, Point anchor)
    {
        _token++;
        _hiding = false;
        _text.Text = item.Name;
        _current = item;

        bool below = Place(anchor);
        _visual.RenderTransformOrigin = below ? new Point(0.5, 0) : new Point(0.5, 1);

        if (!_win.IsVisible)
        {
            _win.Show();
            ApplyClickThrough();
        }

        var hwnd = new WindowInteropHelper(_win).Handle;
        if (hwnd != IntPtr.Zero) Win32.ForceTopmost(hwnd);

        AnimateIn();
    }

    public void Hide(AppItem item)
    {
        if (_current != null && ReferenceEquals(_current, item))
            HideAll();
    }

    public void HideAll()
    {
        _current = null;
        if (!_win.IsVisible || _hiding) return;
        AnimateOut();
    }

    private bool Place(Point anchor)
    {
        double maxInner = AppleTheme.TooltipMaxWidth
            - AppleTheme.TooltipPadding.Left - AppleTheme.TooltipPadding.Right;
        _text.MaxWidth = maxInner;
        Size textSize = MeasureText();
        double bubbleW = Math.Max(Math.Ceiling(textSize.Width)
            + AppleTheme.TooltipPadding.Left + AppleTheme.TooltipPadding.Right
            + BorderWidth * 2, AppleTheme.TooltipMinWidth);
        _bubble.Width = bubbleW;
        _shadowBubble.Width = bubbleW;
        double bubbleH = Math.Ceiling(textSize.Height)
            + AppleTheme.TooltipPadding.Top + AppleTheme.TooltipPadding.Bottom
            + BorderWidth * 2;
        _shadowBubble.Height = bubbleH;

        double pad = AppleTheme.TooltipShadowPad;
        double winW = bubbleW + pad * 2;
        double winH = bubbleH + ArrowHeight + pad * 2;

        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double left = anchor.X - winW / 2;
        left = Math.Max(screen.Left + 4, Math.Min(left, screen.Right - winW - 4));

        double belowTop = anchor.Y + AppleTheme.TooltipAnchorGap - pad;
        double aboveTop = anchor.Y - AppleTheme.TooltipAnchorGap - (winH - pad);
        bool below = belowTop + winH - pad <= screen.Bottom - 4;
        if (!below && aboveTop < screen.Top + 4) below = true;
        double top = below ? belowTop : aboveTop;
        top = Math.Max(screen.Top + 2, Math.Min(top, screen.Bottom - winH - 2));

        var arrowVis = below ? Visibility.Visible : Visibility.Collapsed;
        var otherVis = below ? Visibility.Collapsed : Visibility.Visible;
        _arrowTop.Visibility = arrowVis;
        _shadowArrowTop.Visibility = arrowVis;
        _arrowBottom.Visibility = otherVis;
        _shadowArrowBottom.Visibility = otherVis;

        // 箭头对准图标中心；窗口被屏幕夹住时只移动箭头，不带动整块气泡。
        double tipX = anchor.X - left - pad;
        double arrowLeft = Math.Clamp(tipX - ArrowWidth / 2, 8, bubbleW - ArrowWidth - 8);
        double shift = arrowLeft - (bubbleW - ArrowWidth) / 2.0;
        _arrowTopShift.X = shift;
        _arrowBottomShift.X = shift;
        _shadowArrowTopShift.X = shift;
        _shadowArrowBottomShift.X = shift;

        _win.Width = winW;
        _win.Height = winH;
        _win.Left = left;
        _win.Top = top;
        return below;
    }

    private Size MeasureText()
    {
        _text.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        double w = _text.DesiredSize.Width;
        double maxInner = AppleTheme.TooltipMaxWidth
            - AppleTheme.TooltipPadding.Left - AppleTheme.TooltipPadding.Right;
        if (w > maxInner)
        {
            _text.Measure(new Size(maxInner, double.PositiveInfinity));
        }
        return _text.DesiredSize;
    }

    private void AnimateIn()
    {
        _win.BeginAnimation(UIElement.OpacityProperty, null);
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        _scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);

        double from = _win.Opacity;
        var fade = new DoubleAnimation(from, 1.0, TimeSpan.FromMilliseconds(140))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        };
        double fromScale = from < 0.5 ? 0.92 : 1.0;
        var grow = new DoubleAnimation(fromScale, 1.0, TimeSpan.FromMilliseconds(180))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        _win.BeginAnimation(UIElement.OpacityProperty, fade);
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        _scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
    }

    private void AnimateOut()
    {
        _hiding = true;
        int token = _token;
        _win.BeginAnimation(UIElement.OpacityProperty, null);
        var fade = new DoubleAnimation(_win.Opacity, 0.0, TimeSpan.FromMilliseconds(90))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn },
        };
        fade.Completed += (_, _) =>
        {
            if (token != _token) return;
            _hiding = false;
            if (_current == null && _win.IsVisible) _win.Hide();
            _win.BeginAnimation(UIElement.OpacityProperty, null);
            _win.Opacity = 0;
        };
        _win.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    private void ApplyClickThrough()
    {
        var hwnd = new WindowInteropHelper(_win).Handle;
        if (hwnd == IntPtr.Zero) return;
        long style = Win32.GetWindowLongLong(hwnd, Win32.GWL_EXSTYLE);
        style |= Win32.WS_EX_TRANSPARENT | Win32.WS_EX_NOACTIVATE | Win32.WS_EX_TOOLWINDOW;
        Win32.SetWindowLongLong(hwnd, Win32.GWL_EXSTYLE, style);
    }

    private static Grid MakeArrowLayout(
        System.Windows.Shapes.Path arrowTop,
        FrameworkElement bubble,
        System.Windows.Shapes.Path arrowBottom)
    {
        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(arrowTop, 0);
        Grid.SetRow(bubble, 1);
        Grid.SetRow(arrowBottom, 2);
        Panel.SetZIndex(bubble, 0);
        Panel.SetZIndex(arrowTop, 1);
        Panel.SetZIndex(arrowBottom, 1);
        layout.Children.Add(bubble);
        layout.Children.Add(arrowTop);
        layout.Children.Add(arrowBottom);
        return layout;
    }

    /// <summary>
    /// 纯填充三角（不描边）。叠在气泡上并压进 1px，盖住气泡描边，避免接缝上再出现一条线。
    /// </summary>
    private static System.Windows.Shapes.Path MakeArrow(bool pointingUp)
    {
        var geo = pointingUp
            ? Geometry.Parse($"M 0,{ArrowHeight} L {ArrowWidth / 2},0 L {ArrowWidth},{ArrowHeight} Z")
            : Geometry.Parse($"M 0,0 L {ArrowWidth / 2},{ArrowHeight} L {ArrowWidth},0 Z");
        geo.Freeze();
        return new System.Windows.Shapes.Path
        {
            Data = geo,
            Fill = AppleTheme.TooltipBg,
            Stroke = Brushes.Transparent,
            StrokeThickness = 0,
            Width = ArrowWidth,
            Height = ArrowHeight,
            Stretch = Stretch.Fill,
            HorizontalAlignment = HorizontalAlignment.Center,
            SnapsToDevicePixels = true,
        };
    }
}
