using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace DynamicIsland.Ui;

/// <summary>
/// Windows 版 UI 设计规范。设置窗口对齐 macOS System Settings；
/// 悬停气泡对齐浅色 NSPopover。页面不要写死颜色 / 字号 / 圆角 / 间距。
///
/// 信条：
///   1) 系统蓝 <c>#007AFF</c> 是唯一强调色；开关开启态用系统绿 <c>#34C759</c>。
///   2) 窗口是分组灰底，内容是白色 inset 分组；侧栏选中是浅灰块，不是白卡。
///   3) 正文 13px，页面标题 22px —— 这是桌面设置，不是 apple.com。
///   4) 按钮是 6px 圆角的 AppKit push button，不是网页胶囊。
///   5) 投影只给浮层（气泡）；设置页卡片 / 按钮不加阴影。
/// </summary>
public static class AppleTheme
{
    // ============================================================
    // 颜色 —— macOS System Settings（浅色）
    // ============================================================

    public static readonly Brush Accent = Frozen("#007AFF");
    public static readonly Brush AccentHover = Frozen("#0071EB");
    public static readonly Brush AccentPressed = Frozen("#0066D6");
    public static readonly Brush AccentSoft = Frozen("#14007AFF");
    public static readonly Brush ToggleOn = Frozen("#34C759");
    public static readonly Brush Danger = Frozen("#FF3B30");
    public static readonly Brush DangerHover = Frozen("#14FF3B30");
    public static readonly Brush DangerPressed = Frozen("#26FF3B30");

    /// <summary>系统设置窗口底 / 侧栏底。</summary>
    public static readonly Brush WindowBg = Frozen("#E8E8ED");
    /// <summary>侧栏比内容区略深一档，让分割更像原生。</summary>
    public static readonly Brush SidebarBg = Frozen("#E3E3E8");
    public static readonly Brush CardBg = Frozen("#FFFFFF");
    public static readonly Brush HoverBg = Frozen("#0A000000");
    public static readonly Brush PressedBg = Frozen("#14000000");
    public static readonly Brush SelectedBg = Frozen("#D8D8DE");
    public static readonly Brush SidebarHover = Frozen("#DCDCE2");
    public static readonly Brush TrackBg = Frozen("#D1D1D6");
    public static readonly Brush SurfaceControl = Frozen("#F2F2F7");

    public static readonly Brush TextPrimary = Frozen("#1D1D1F");
    public static readonly Brush TextSecondary = Frozen("#6E6E73");
    public static readonly Brush TextTertiary = Frozen("#8E8E93");
    public static readonly Brush InkMuted80 = Frozen("#3A3A3C");
    public static readonly Brush BodyOnDark = Frozen("#FFFFFF");

    /// <summary>分组卡片 1px 发丝。</summary>
    public static readonly Brush Separator = Frozen("#1A000000");
    /// <summary>行内分割，比卡片描边更淡。</summary>
    public static readonly Brush RowSeparator = Frozen("#14000000");
    public static readonly Brush FieldBorder = Frozen("#28000000");
    public static readonly Brush ButtonBorder = Frozen("#2E000000");

    public static readonly Brush TooltipBg = Frozen("#FFFAFAFA");
    public static readonly Brush TooltipBorder = Frozen("#2E000000");

    public static readonly Brush ChipFill = Frozen("#C7C7CC");
    public static readonly Brush ChipFillHover = Frozen("#B0B0B5");

    // ============================================================
    // 圆角
    // ============================================================
    public const double RadiusXs = 5;
    public const double RadiusSm = 6;
    public const double RadiusMd = 8;
    public const double RadiusLg = 10;
    public const double RadiusPill = 9999;

    public const double CardRadius = RadiusLg;
    public const double ControlRadius = RadiusSm;
    public const double SmallRadius = RadiusXs;

    // ============================================================
    // 间距
    // ============================================================
    public const double SpaceXxs = 4;
    public const double SpaceXs = 8;
    public const double SpaceSm = 12;
    public const double SpaceMd = 16;
    public const double SpaceLg = 20;
    public const double SpaceXl = 24;
    public const double SpaceXxl = 32;

    public const double CardPadding = 14;
    public const double CardGap = 16;
    public const double PagePadding = 22;
    public const double RowSpacing = 10;
    public const double LabelWidth = 132;
    public const double SidebarWidth = 196;
    public const double SidebarIconSize = 24;

    // ============================================================
    // 控件尺寸 —— 按 AppKit 常规控件，而不是网页 CTA
    // ============================================================
    public const double ControlHeight = 28;
    public const double UtilityHeight = 22;
    public const double CompactHeight = 22;
    public const double MicroHeight = 16;
    public const double SwitchWidth = 40;
    public const double SwitchHeight = 24;
    public const double KnobSize = 16;
    public const double SegmentHeight = 26;

    // ============================================================
    // 字体
    // ============================================================
    public static readonly FontFamily Font =
        new("SF Pro Text, SF Pro Display, Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily FontDisplay =
        new("SF Pro Display, SF Pro Text, Segoe UI Variable Display, Segoe UI");
    public static readonly FontFamily FontIcon =
        new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static readonly FontWeight WeightRegular = FontWeights.Normal;
    public static readonly FontWeight WeightMedium = FontWeights.Medium;
    public static readonly FontWeight WeightSemibold = FontWeights.SemiBold;

    public const double TitleSize = 22;
    public const double DisplayMdSize = TitleSize;
    public const double TaglineSize = 17;
    public const double BodySize = 13;
    public const double CaptionSize = 11;
    public const double FinePrintSize = 11;
    public const double SubtitleSize = CaptionSize;
    public const double BodyLineHeight = 1.35;
    public const double CaptionLineHeight = 1.35;

    public const double TooltipRadius = RadiusMd;
    public const double TooltipMaxWidth = 320;
    public const double TooltipMinWidth = 80;
    public const double TooltipTextSize = 13;
    public const double TooltipAnchorGap = 5;
    public const double TooltipShadowPad = 18;
    public static readonly Thickness TooltipPadding = new(14, 6, 14, 6);

    // ============================================================
    // 窗口
    // ============================================================

    public static void ApplyWindowChrome(Window window)
    {
        window.Background = WindowBg;
        window.FontFamily = Font;
        window.FontSize = BodySize;
        window.Foreground = TextPrimary;
        window.UseLayoutRounding = true;
        window.SnapsToDevicePixels = true;
        TextOptions.SetTextFormattingMode(window, TextFormattingMode.Display);
        TextOptions.SetTextRenderingMode(window, TextRenderingMode.ClearType);
    }

    public static void AddPageHeader(Panel host, string title, string subtitle)
    {
        host.Children.Add(new TextBlock
        {
            Text = title,
            FontFamily = FontDisplay,
            FontSize = TitleSize,
            FontWeight = WeightSemibold,
            Foreground = TextPrimary,
            Margin = new Thickness(1, 0, 0, 3),
        });
        host.Children.Add(new TextBlock
        {
            Text = subtitle,
            FontSize = BodySize,
            Foreground = TextSecondary,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = Math.Round(BodySize * BodyLineHeight),
            Margin = new Thickness(1, 0, 0, SpaceLg),
        });
    }

    /// <summary>
    /// macOS 分组：小标题在卡片上方，卡片 10px 圆角白底。
    /// <paramref name="insetList"/> 为 true 时，在 StackPanel 子项之间插入左侧缩进分割线。
    /// </summary>
    public static FrameworkElement GroupedSection(string? title, UIElement content, bool insetList = false)
    {
        if (insetList && content is Panel panel)
            ApplyInsetList(panel);

        var card = new Border
        {
            Background = CardBg,
            BorderBrush = Separator,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(CardRadius),
            Padding = insetList ? new Thickness(0) : new Thickness(CardPadding),
            SnapsToDevicePixels = true,
            Child = content,
        };

        var root = new StackPanel { Margin = new Thickness(0, 0, 0, CardGap) };
        if (!string.IsNullOrEmpty(title))
        {
            root.Children.Add(new TextBlock
            {
                Text = title,
                FontSize = BodySize,
                FontWeight = WeightSemibold,
                Foreground = TextSecondary,
                Margin = new Thickness(4, 0, 0, 6),
            });
        }
        root.Children.Add(card);
        return root;
    }

    public static FrameworkElement Card(string? title, UIElement content)
        => GroupedSection(title, content);

    public static Grid Row(string label, UIElement control, double labelWidth = LabelWidth)
    {
        var text = new TextBlock
        {
            Text = label,
            FontSize = BodySize,
            Foreground = TextPrimary,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var row = new Grid
        {
            MinHeight = 28,
            Margin = new Thickness(0, RowSpacing / 2, 0, RowSpacing / 2),
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(labelWidth) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(text, 0);
        Grid.SetColumn(control, 1);
        row.Children.Add(text);
        row.Children.Add(control);
        return row;
    }

    public enum ButtonKind { Accent, Tinted, Plain, IconChip, Danger }
    public enum ButtonSize { Regular, Compact, Micro }

    public static Button MakeButton(string text, ButtonKind kind, Action onClick,
        double minWidth = 0, ButtonSize size = ButtonSize.Regular)
    {
        bool micro = size == ButtonSize.Micro;
        bool compact = size == ButtonSize.Compact;
        bool icon = kind == ButtonKind.IconChip;

        double height = micro ? MicroHeight : compact ? CompactHeight : ControlHeight;
        double fontSize = micro || compact || icon ? CaptionSize : BodySize;
        double padH = icon || micro ? 0 : compact ? 8 : 12;

        var btn = new Button
        {
            Content = text,
            Height = height,
            MinWidth = minWidth,
            Padding = new Thickness(padH, 0, padH, 0),
            FontFamily = Font,
            FontSize = fontSize,
            FontWeight = WeightRegular,
            Cursor = Cursors.Hand,
            Focusable = false,
            SnapsToDevicePixels = true,
            BorderBrush = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Template = FlatButtonTemplate(kind),
        };

        switch (kind)
        {
            case ButtonKind.Accent:
                btn.Background = Accent;
                btn.Foreground = BodyOnDark;
                break;
            case ButtonKind.Tinted:
                btn.Background = CardBg;
                btn.Foreground = Accent;
                btn.BorderBrush = ButtonBorder;
                btn.BorderThickness = new Thickness(1);
                break;
            case ButtonKind.IconChip:
                btn.Background = ChipFill;
                btn.Foreground = BodyOnDark;
                break;
            case ButtonKind.Danger:
                btn.Background = Brushes.Transparent;
                btn.Foreground = Danger;
                break;
            default:
                btn.Background = CardBg;
                btn.Foreground = TextPrimary;
                btn.BorderBrush = ButtonBorder;
                btn.BorderThickness = new Thickness(1);
                break;
        }

        btn.Click += (_, _) => onClick();
        return btn;
    }

    /// <summary>macOS xmark.circle.fill：灰圆白叉，贴在应用磁贴右上角。</summary>
    public static Button MakeRemoveBadge(Action onClick)
    {
        var btn = MakeButton("×", ButtonKind.IconChip, onClick, size: ButtonSize.Micro);
        btn.Width = MicroHeight;
        btn.Height = MicroHeight;
        btn.FontSize = 11;
        btn.FontWeight = WeightSemibold;
        btn.Padding = new Thickness(0);
        btn.ToolTip = "移除";
        return btn;
    }

    public static Border Field(UIElement inner, double width = double.NaN)
    {
        if (inner is Control c) c.BorderThickness = new Thickness(0);
        return new Border
        {
            Background = CardBg,
            BorderBrush = FieldBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(RadiusSm),
            Padding = new Thickness(8, 0, 8, 0),
            Height = UtilityHeight,
            Width = width,
            SnapsToDevicePixels = true,
            Child = inner,
        };
    }

    public static TextBox MakeTextBox(string text, TextAlignment align = TextAlignment.Left)
    {
        return new TextBox
        {
            Text = text,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            FontFamily = Font,
            FontSize = BodySize,
            Foreground = TextPrimary,
            VerticalContentAlignment = VerticalAlignment.Center,
            TextAlignment = align,
            CaretBrush = Accent,
            SelectionBrush = Accent,
        };
    }

    public static CheckBox MakeSwitch(Func<bool> get, Action<bool> toggle)
    {
        var cb = new CheckBox
        {
            IsChecked = get(),
            VerticalAlignment = VerticalAlignment.Center,
            Cursor = Cursors.Hand,
            Template = SwitchTemplate(),
        };
        cb.Checked += (_, _) => toggle(true);
        cb.Unchecked += (_, _) => toggle(false);
        return cb;
    }

    public static Slider MakeSlider(double value, double min, double max, double step)
    {
        return new Slider
        {
            Value = value,
            Minimum = min,
            Maximum = max,
            TickFrequency = step,
            IsSnapToTickEnabled = true,
            VerticalAlignment = VerticalAlignment.Center,
            Height = 22,
            MinWidth = 120,
            Template = SliderTemplate(),
        };
    }

    public static TextBlock Caption(string text) => new()
    {
        Text = text,
        FontFamily = Font,
        FontSize = CaptionSize,
        Foreground = TextSecondary,
        TextWrapping = TextWrapping.Wrap,
        LineHeight = Math.Round(CaptionSize * CaptionLineHeight),
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static TextBlock ValueBadge(string text) => new()
    {
        Text = text,
        FontFamily = Font,
        FontSize = BodySize,
        Foreground = TextSecondary,
        TextAlignment = TextAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center,
        MinWidth = 52,
    };

    /// <summary>macOS 分段控件：灰槽 + 白块选中。</summary>
    public static FrameworkElement MakeSegmented(IReadOnlyList<string> labels, int selected, Action<int> onSelect)
    {
        var grid = new UniformGrid { Rows = 1, Columns = labels.Count };
        var cells = new Border[labels.Count];
        var texts = new TextBlock[labels.Count];
        int current = selected;

        void Paint()
        {
            for (int i = 0; i < labels.Count; i++)
            {
                bool on = i == current;
                cells[i].Background = on ? CardBg : Brushes.Transparent;
                cells[i].BorderBrush = on ? ButtonBorder : Brushes.Transparent;
                texts[i].FontWeight = on ? WeightSemibold : WeightRegular;
                texts[i].Foreground = TextPrimary;
            }
        }

        for (int i = 0; i < labels.Count; i++)
        {
            int index = i;
            texts[i] = new TextBlock
            {
                Text = labels[i],
                FontSize = BodySize,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            cells[i] = new Border
            {
                CornerRadius = new CornerRadius(RadiusSm),
                BorderThickness = new Thickness(1),
                Margin = new Thickness(1, 0, 1, 0),
                Child = texts[i],
                Cursor = Cursors.Hand,
                SnapsToDevicePixels = true,
            };
            cells[i].MouseEnter += (_, _) =>
            {
                if (index != current) cells[i].Background = HoverBg;
            };
            cells[i].MouseLeave += (_, _) =>
            {
                if (index != current) cells[i].Background = Brushes.Transparent;
            };
            cells[i].MouseLeftButtonUp += (_, _) =>
            {
                if (current == index) return;
                current = index;
                Paint();
                onSelect(index);
            };
            grid.Children.Add(cells[i]);
        }

        Paint();
        return new Border
        {
            Background = TrackBg,
            CornerRadius = new CornerRadius(RadiusMd),
            Padding = new Thickness(2),
            Height = SegmentHeight + 4,
            Child = grid,
            SnapsToDevicePixels = true,
        };
    }

    public static FrameworkElement EmptyState(string title, string glyph)
    {
        var icon = new TextBlock
        {
            Text = glyph,
            FontFamily = FontIcon,
            FontSize = 28,
            Foreground = TextTertiary,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var label = new TextBlock
        {
            Text = title,
            FontSize = BodySize,
            Foreground = TextSecondary,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 8, 0, 0),
        };
        var stack = new StackPanel { Margin = new Thickness(0, 18, 0, 18) };
        stack.Children.Add(icon);
        stack.Children.Add(label);
        return stack;
    }

    public static FrameworkElement MetricTile(string title, string value, string glyph)
    {
        var icon = new TextBlock
        {
            Text = glyph,
            FontFamily = FontIcon,
            FontSize = 16,
            Foreground = TextSecondary,
            Margin = new Thickness(0, 0, 0, 8),
        };
        var valueText = new TextBlock
        {
            Text = value,
            FontFamily = FontDisplay,
            FontSize = TaglineSize,
            FontWeight = WeightSemibold,
            Foreground = TextPrimary,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var caption = new TextBlock
        {
            Text = title,
            FontSize = CaptionSize,
            Foreground = TextSecondary,
            Margin = new Thickness(0, 1, 0, 0),
        };
        var stack = new StackPanel();
        stack.Children.Add(icon);
        stack.Children.Add(valueText);
        stack.Children.Add(caption);
        return new Border
        {
            Background = CardBg,
            BorderBrush = Separator,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(RadiusMd),
            Padding = new Thickness(14),
            Margin = new Thickness(0, 0, SpaceXs, 0),
            Child = stack,
        };
    }

    public static FrameworkElement SidebarItem(string title, string glyph, Color iconBg, bool selected, Action onClick)
    {
        var icon = new Border
        {
            Width = SidebarIconSize,
            Height = SidebarIconSize,
            CornerRadius = new CornerRadius(5),
            Background = new SolidColorBrush(iconBg),
            Child = new TextBlock
            {
                Text = glyph,
                FontFamily = FontIcon,
                FontSize = 13,
                Foreground = BodyOnDark,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        var label = new TextBlock
        {
            Text = title,
            FontSize = BodySize,
            FontWeight = selected ? WeightSemibold : WeightRegular,
            Foreground = TextPrimary,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 0, 0),
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(icon);
        row.Children.Add(label);

        var border = new Border
        {
            Background = selected ? SelectedBg : Brushes.Transparent,
            CornerRadius = new CornerRadius(RadiusMd),
            Padding = new Thickness(8, 6, 8, 6),
            Margin = new Thickness(10, 1, 10, 1),
            Child = row,
            Cursor = Cursors.Hand,
            SnapsToDevicePixels = true,
        };
        border.MouseEnter += (_, _) =>
        {
            if (!selected) border.Background = SidebarHover;
        };
        border.MouseLeave += (_, _) =>
        {
            border.Background = selected ? SelectedBg : Brushes.Transparent;
        };
        border.MouseLeftButtonUp += (_, _) => onClick();
        return border;
    }

    // ============================================================
    // 模板
    // ============================================================

    private static double RadiusOf(ButtonKind kind) => kind switch
    {
        ButtonKind.IconChip => RadiusPill,
        _ => RadiusSm,
    };

    private static ControlTemplate FlatButtonTemplate(ButtonKind kind)
    {
        var border = new FrameworkElementFactory(typeof(Border), "bd");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(RadiusOf(kind)));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
        border.SetValue(Border.BorderBrushProperty, new TemplateBindingExtension(Control.BorderBrushProperty));
        border.SetValue(Border.BorderThicknessProperty, new TemplateBindingExtension(Control.BorderThicknessProperty));
        border.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Control.PaddingProperty));

        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(presenter);

        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };

        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, HoverOf(kind), "bd"));
        template.Triggers.Add(hover);

        var pressed = new Trigger { Property = Button.IsPressedProperty, Value = true };
        pressed.Setters.Add(new Setter(Border.BackgroundProperty, PressedOf(kind), "bd"));
        template.Triggers.Add(pressed);

        var disabled = new Trigger { Property = UIElement.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.4));
        template.Triggers.Add(disabled);
        return template;
    }

    private static Brush HoverOf(ButtonKind kind) => kind switch
    {
        ButtonKind.Accent => AccentHover,
        ButtonKind.Tinted => AccentSoft,
        ButtonKind.IconChip => ChipFillHover,
        ButtonKind.Danger => DangerHover,
        _ => SurfaceControl,
    };

    private static Brush PressedOf(ButtonKind kind) => kind switch
    {
        ButtonKind.Accent => AccentPressed,
        ButtonKind.Tinted => Frozen("#1F007AFF"),
        ButtonKind.IconChip => Frozen("#9A9A9F"),
        ButtonKind.Danger => DangerPressed,
        _ => PressedBg,
    };

    private static ControlTemplate SwitchTemplate()
    {
        var track = new FrameworkElementFactory(typeof(Border), "track");
        track.SetValue(FrameworkElement.WidthProperty, SwitchWidth);
        track.SetValue(FrameworkElement.HeightProperty, SwitchHeight);
        track.SetValue(Border.CornerRadiusProperty, new CornerRadius(SwitchHeight / 2));
        track.SetValue(Border.BackgroundProperty, TrackBg);

        var knob = new FrameworkElementFactory(typeof(Border), "knob");
        knob.SetValue(FrameworkElement.WidthProperty, SwitchHeight - 4);
        knob.SetValue(FrameworkElement.HeightProperty, SwitchHeight - 4);
        knob.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Left);
        knob.SetValue(FrameworkElement.MarginProperty, new Thickness(2, 0, 0, 0));
        knob.SetValue(Border.CornerRadiusProperty, new CornerRadius((SwitchHeight - 4) / 2));
        knob.SetValue(Border.BackgroundProperty, Brushes.White);
        track.AppendChild(knob);

        var template = new ControlTemplate(typeof(CheckBox)) { VisualTree = track };
        var on = new Trigger { Property = ToggleButton.IsCheckedProperty, Value = true };
        on.Setters.Add(new Setter(Border.BackgroundProperty, ToggleOn, "track"));
        on.Setters.Add(new Setter(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Right, "knob"));
        on.Setters.Add(new Setter(FrameworkElement.MarginProperty, new Thickness(0, 0, 2, 0), "knob"));
        template.Triggers.Add(on);
        return template;
    }

    private static ControlTemplate SliderTemplate()
    {
        var track = new FrameworkElementFactory(typeof(SliderTrack), "PART_Track");
        track.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);

        var root = new FrameworkElementFactory(typeof(Grid));
        root.SetValue(FrameworkElement.HeightProperty, 22.0);
        root.AppendChild(track);
        return new ControlTemplate(typeof(Slider)) { VisualTree = root };
    }

    public sealed class SliderTrack : Track
    {
        public SliderTrack()
        {
            const double bar = 3;
            double knob = KnobSize;

            DecreaseRepeatButton = new RepeatButton
            {
                Height = bar,
                VerticalAlignment = VerticalAlignment.Center,
                Focusable = false,
                Command = Slider.DecreaseLarge,
                Template = BarTemplate(Accent, new CornerRadius(bar / 2, 0, 0, bar / 2)),
            };

            IncreaseRepeatButton = new RepeatButton
            {
                Height = bar,
                VerticalAlignment = VerticalAlignment.Center,
                Focusable = false,
                Command = Slider.IncreaseLarge,
                Template = BarTemplate(TrackBg, new CornerRadius(0, bar / 2, bar / 2, 0)),
            };

            Thumb = new Thumb
            {
                Width = knob,
                Height = knob,
                VerticalAlignment = VerticalAlignment.Center,
                Template = ThumbTemplate(),
            };
        }
    }

    private static ControlTemplate BarTemplate(Brush background, CornerRadius radius)
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.BackgroundProperty, background);
        border.SetValue(Border.CornerRadiusProperty, radius);
        return new ControlTemplate(typeof(RepeatButton)) { VisualTree = border };
    }

    private static ControlTemplate ThumbTemplate()
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.BackgroundProperty, Brushes.White);
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(KnobSize / 2));
        border.SetValue(Border.BorderThicknessProperty, new Thickness(1));
        border.SetValue(Border.BorderBrushProperty, Frozen("#33000000"));
        return new ControlTemplate(typeof(Thumb)) { VisualTree = border };
    }

    private static void ApplyInsetList(Panel panel)
    {
        var items = panel.Children.Cast<UIElement>().ToList();
        panel.Children.Clear();
        for (int i = 0; i < items.Count; i++)
        {
            if (i > 0)
            {
                panel.Children.Add(new Border
                {
                    Height = 1,
                    Background = RowSeparator,
                    Margin = new Thickness(12, 0, 0, 0),
                    SnapsToDevicePixels = true,
                });
            }

            var item = items[i];
            if (item is FrameworkElement fe)
                fe.Margin = new Thickness(12, 8, 12, 8);
            panel.Children.Add(item);
        }
    }

    private static SolidColorBrush Frozen(string hex)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)!);
        brush.Freeze();
        return brush;
    }
}
