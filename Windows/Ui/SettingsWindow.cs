using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DynamicIsland.Core;
using DynamicIsland.Island;
using DynamicIsland.Native;

namespace DynamicIsland.Ui;

/// <summary>
/// 设置窗口：对齐 macOS 系统设置 —— 左侧带彩色图标的侧栏，右侧分组卡片。
/// 控件全部在代码中构建，绑定 IslandSettings；改动即时生效并持久化。
/// </summary>
public sealed class SettingsWindow : Window
{
    private static readonly (string Title, string Glyph, Color IconBg)[] Panes =
    {
        ("基础设置", "\uE713", Color.FromRgb(0x8E, 0x8E, 0x93)),
        ("应用过滤", "\uE71C", Color.FromRgb(0x00, 0x7A, 0xFF)),
        ("外观布局", "\uE790", Color.FromRgb(0xAF, 0x52, 0xDE)),
        ("触发方式", "\uE8B0", Color.FromRgb(0xFF, 0x95, 0x00)),
        ("动画",     "\uE8B7", Color.FromRgb(0x30, 0xD1, 0x58)),
    };

    private readonly IslandSettings _settings;
    private readonly AppStore _store;
    private readonly Action _showTriggerPreview;
    private readonly Action<bool> _setPreviewPinned;
    private readonly Action<bool> _setTriggerPreview;
    private readonly Action _checkUpdates;

    private readonly StackPanel _sidebar;
    private readonly StackPanel _detail;
    private int _selected;
    private bool _previewPinned;
    private bool _triggerPreviewOn;
    /// <summary>退出应用时允许真正关闭；平时点关闭只隐藏。</summary>
    internal bool AllowClose { get; set; }

    public SettingsWindow(IslandSettings settings, AppStore store,
        Action showTriggerPreview, Action<bool> setPreviewPinned, Action<bool> setTriggerPreview,
        Action checkUpdates)
    {
        _settings = settings;
        _store = store;
        _showTriggerPreview = showTriggerPreview;
        _setPreviewPinned = setPreviewPinned;
        _setTriggerPreview = setTriggerPreview;
        _checkUpdates = checkUpdates;

        Title = "灵动岛设置";
        Width = 800;
        Height = 620;
        MinWidth = 760;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        Closing += (_, e) =>
        {
            if (AllowClose) return;
            e.Cancel = true;
            Hide();
            StopPreviews();
        };

        _sidebar = new StackPanel
        {
            Width = AppleTheme.SidebarWidth,
            Background = AppleTheme.SidebarBg,
        };
        RebuildSidebar();

        _detail = new StackPanel { Margin = new Thickness(AppleTheme.PagePadding) };

        var sidebarHost = new Border
        {
            Background = AppleTheme.SidebarBg,
            BorderBrush = AppleTheme.Separator,
            BorderThickness = new Thickness(0, 0, 1, 0),
            Child = new ScrollViewer
            {
                Content = _sidebar,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Padding = new Thickness(0, 10, 0, 10),
            },
        };

        var split = new DockPanel();
        DockPanel.SetDock(sidebarHost, Dock.Left);
        split.Children.Add(sidebarHost);
        split.Children.Add(new ScrollViewer
        {
            Content = _detail,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Background = AppleTheme.WindowBg,
        });
        Content = split;

        AppleTheme.ApplyWindowChrome(this);
        _settings.Changed += () => SettingsManager.Save(_settings);
        RebuildDetail();
    }

    private void StopPreviews()
    {
        if (_previewPinned)
        {
            _previewPinned = false;
            _setPreviewPinned(false);
        }
        if (_triggerPreviewOn)
        {
            _triggerPreviewOn = false;
            _setTriggerPreview(false);
        }
    }

    private void RebuildSidebar()
    {
        _sidebar.Children.Clear();
        _sidebar.Children.Add(new TextBlock
        {
            Text = "设置",
            FontSize = AppleTheme.CaptionSize,
            FontWeight = AppleTheme.WeightSemibold,
            Foreground = AppleTheme.TextSecondary,
            Margin = new Thickness(18, 4, 12, 8),
        });
        for (int i = 0; i < Panes.Length; i++)
        {
            int index = i;
            var pane = Panes[i];
            _sidebar.Children.Add(AppleTheme.SidebarItem(
                pane.Title, pane.Glyph, pane.IconBg, index == _selected,
                () =>
                {
                    if (_selected == index) return;
                    _selected = index;
                    RebuildSidebar();
                    RebuildDetail();
                }));
        }
    }

    private void RebuildDetail()
    {
        _detail.Children.Clear();
        try
        {
            switch (_selected)
            {
                case 0: BuildOverview(); break;
                case 1: BuildFilter(); break;
                case 2: BuildAppearance(); break;
                case 3: BuildTrigger(); break;
                case 4: BuildAnimation(); break;
            }
        }
        catch (Exception ex)
        {
            DebugLog.Write($"设置页构建失败（第 {_selected} 页）: {ex}");
            _detail.Children.Add(new TextBlock
            {
                Text = "页面构建失败：" + ex.Message,
                FontSize = AppleTheme.BodySize,
                Foreground = AppleTheme.Danger,
                TextWrapping = TextWrapping.Wrap,
            });
        }
    }

    private void AddPageHeader(StackPanel p, string text, string subtitle)
        => AppleTheme.AddPageHeader(p, text, subtitle);

    private static FrameworkElement Group(string title, UIElement content, bool insetList = false)
        => AppleTheme.GroupedSection(title, content, insetList);

    private void AddSlider(StackPanel p, string title, Func<double> get, Action<double> set,
        double min, double max, double step, string suffix, int decimals = 0)
    {
        var valueText = AppleTheme.ValueBadge("");
        var slider = AppleTheme.MakeSlider(get(), min, max, step);
        UpdateValue(valueText, get(), suffix, decimals);

        slider.ValueChanged += (_, _) =>
        {
            set(Math.Round(slider.Value / step) * step);
            UpdateValue(valueText, get(), suffix, decimals);
        };

        var right = new Grid();
        right.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        right.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
        Grid.SetColumn(slider, 0);
        Grid.SetColumn(valueText, 1);
        right.Children.Add(slider);
        right.Children.Add(valueText);
        p.Children.Add(AppleTheme.Row(title, right));
    }

    private void AddStepper(StackPanel p, string title, Func<int> get, Action<int> set, int min, int max, string suffix)
    {
        var valueText = AppleTheme.ValueBadge($"{get()} {suffix}");
        var minus = AppleTheme.MakeButton("−", AppleTheme.ButtonKind.Plain, () =>
        {
            set(Math.Clamp(get() - 1, min, max));
            valueText.Text = $"{get()} {suffix}";
        }, size: AppleTheme.ButtonSize.Compact);
        var plus = AppleTheme.MakeButton("+", AppleTheme.ButtonKind.Plain, () =>
        {
            set(Math.Clamp(get() + 1, min, max));
            valueText.Text = $"{get()} {suffix}";
        }, size: AppleTheme.ButtonSize.Compact);
        minus.Width = plus.Width = 22;
        minus.Margin = new Thickness(6, 0, 4, 0);

        var bar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        bar.Children.Add(valueText);
        bar.Children.Add(minus);
        bar.Children.Add(plus);
        p.Children.Add(AppleTheme.Row(title, bar));
    }

    private void AddTextField(StackPanel p, string title, Func<string> get, Action<string> set)
    {
        var box = AppleTheme.MakeTextBox(get());
        box.LostFocus += (_, _) => set(box.Text);
        p.Children.Add(AppleTheme.Row(title, AppleTheme.Field(box)));
    }

    private void AddNumberField(StackPanel p, string title, Func<double> get, Action<double> set,
        double min, double max, string suffix, Func<string>? hint = null)
    {
        var box = AppleTheme.MakeTextBox(get().ToString("0"), TextAlignment.Right);
        var unit = AppleTheme.Caption(suffix);
        unit.Margin = new Thickness(4, 0, 0, 0);
        var boxRow = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        boxRow.Children.Add(box);
        boxRow.Children.Add(unit);
        var hintText = AppleTheme.Caption(hint?.Invoke() ?? "");
        hintText.Margin = new Thickness(AppleTheme.SpaceXs, 0, 0, 0);

        void Apply()
        {
            if (double.TryParse(box.Text.Trim(), out var v))
            {
                v = Math.Clamp(v, min, max);
                set(v);
            }
            box.Text = get().ToString("0");
            var next = hint?.Invoke() ?? "";
            if (!hintText.Text.Equals(next))
                Dispatcher.BeginInvoke(new Action(RebuildDetail));
        }

        box.LostFocus += (_, _) => Apply();
        box.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Enter)
            {
                Apply();
                e.Handled = true;
            }
        };

        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        right.Children.Add(AppleTheme.Field(boxRow, 108));
        right.Children.Add(hintText);
        p.Children.Add(AppleTheme.Row(title, right));
    }

    private static void UpdateValue(TextBlock t, double v, string suffix, int decimals)
        => t.Text = $"{v.ToString("F" + decimals)} {suffix}";

    private void BuildOverview()
    {
        AddPageHeader(_detail, "基础设置", "管理快捷应用，并调整岛屿展开后的基础布局。");

        var appPanel = new StackPanel();
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, AppleTheme.SpaceXs) };
        var countText = AppleTheme.Caption($"{_store.Apps.Count} 个应用");
        countText.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(countText, Dock.Left);
        var addBtn = AppleTheme.MakeButton("添加应用", AppleTheme.ButtonKind.Accent, AddApps);
        DockPanel.SetDock(addBtn, Dock.Right);
        header.Children.Add(addBtn);
        header.Children.Add(countText);

        appPanel.Children.Add(header);
        if (_store.Apps.Count == 0)
        {
            appPanel.Children.Add(AppleTheme.EmptyState("还没有快捷应用", "\uE8A9"));
        }
        else
        {
            var tiles = new WrapPanel();
            RefreshAppTiles(tiles, _store.Apps.OrderBy(a => a.Order), app =>
            {
                _store.Remove(app);
                RebuildDetail();
            });
            appPanel.Children.Add(tiles);
        }
        _detail.Children.Add(Group("应用", appPanel));

        var metric = new Grid { Margin = new Thickness(0, 0, 0, AppleTheme.CardGap) };
        for (int i = 0; i < 3; i++)
            metric.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var metrics = new (string Title, string Value, string Glyph)[]
        {
            ("快捷应用", _store.Apps.Count.ToString(), "\uE8A9"),
            ("展开尺寸", $"{_settings.ExpandedWidth:0} x {_settings.ExpandedHeight(_store.VisibleApps.Count):0}", "\uE740"),
            ("触发区", $"{_settings.HoverZoneWidth:0} x {_settings.HoverZoneHeight:0}", "\uE8B0"),
        };
        for (int i = 0; i < metrics.Length; i++)
        {
            var tile = AppleTheme.MetricTile(metrics[i].Title, metrics[i].Value, metrics[i].Glyph);
            if (i == metrics.Length - 1 && tile is FrameworkElement last)
                last.Margin = new Thickness(0);
            Grid.SetColumn(tile, i);
            metric.Children.Add(tile);
        }
        _detail.Children.Add(metric);

        var commonStack = new StackPanel();
        AddSlider(commonStack, "图标大小", () => _settings.IconSize, v => _settings.IconSize = v, 32, 72, 1, "px");
        AddStepper(commonStack, "每行列数", () => _settings.Columns, v => _settings.Columns = v, 3, 12, "列");
        AddSlider(commonStack, "图标间距", () => _settings.IconSpacing, v => _settings.IconSpacing = v, 6, 24, 1, "px");
        AddSlider(commonStack, "顶部内边距", () => _settings.ContentTopPadding, v => _settings.ContentTopPadding = v, 10, 46, 1, "px");
        _detail.Children.Add(Group("常用调整", commonStack, insetList: true));

        var sysStack = new StackPanel();
        sysStack.Children.Add(ToggleRow("开机自启动", () => AutostartService.IsEnabled, AutostartService.SetEnabled));
        _detail.Children.Add(Group("系统", sysStack, insetList: true));

        var updateStack = new StackPanel();
        updateStack.Children.Add(ActionRow($"当前版本 {UpdateService.CurrentVersion}", "检查更新", AppleTheme.ButtonKind.Tinted, _checkUpdates));
        _detail.Children.Add(Group("更新", updateStack, insetList: true));

        var mnt = new StackPanel();
        mnt.Children.Add(ActionRow("恢复所有参数到默认值", "恢复默认", AppleTheme.ButtonKind.Plain, () =>
        {
            _settings.RestoreDefault();
            RebuildDetail();
        }));
        mnt.Children.Add(ActionRow("恢复默认快捷应用", "恢复应用", AppleTheme.ButtonKind.Plain, () =>
        {
            _store.RestoreDefaults();
            RebuildDetail();
        }));
        _detail.Children.Add(Group("维护", mnt, insetList: true));
    }

    private Grid ToggleRow(string title, Func<bool> get, Action<bool> toggle)
    {
        var sw = AppleTheme.MakeSwitch(get, toggle);
        sw.HorizontalAlignment = HorizontalAlignment.Right;
        var text = new TextBlock
        {
            Text = title,
            FontSize = AppleTheme.BodySize,
            Foreground = AppleTheme.TextPrimary,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var row = new Grid { MinHeight = 28 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(sw, 1);
        row.Children.Add(text);
        row.Children.Add(sw);
        return row;
    }

    private static Grid ActionRow(string title, string button, AppleTheme.ButtonKind kind, Action action)
    {
        var text = new TextBlock
        {
            Text = title,
            FontSize = AppleTheme.BodySize,
            Foreground = AppleTheme.TextPrimary,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        var btn = AppleTheme.MakeButton(button, kind, action);
        btn.HorizontalAlignment = HorizontalAlignment.Right;
        var row = new Grid { MinHeight = 32 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(btn, 1);
        row.Children.Add(text);
        row.Children.Add(btn);
        return row;
    }

    private void RefreshAppTiles(WrapPanel host, IEnumerable<AppItem> apps, Action<AppItem> onRemove)
    {
        host.Children.Clear();
        foreach (var app in apps)
        {
            var cell = app;
            var del = AppleTheme.MakeRemoveBadge(() => onRemove(cell));
            del.HorizontalAlignment = HorizontalAlignment.Right;
            del.VerticalAlignment = VerticalAlignment.Top;
            del.Margin = new Thickness(0, 4, 4, 0);

            var icon = new System.Windows.Controls.Image
            {
                Source = IconLoader.IconFor(app),
                Width = 40,
                Height = 40,
                Stretch = Stretch.Uniform,
                HorizontalAlignment = HorizontalAlignment.Center,
            };
            var name = new TextBlock
            {
                Text = app.Name,
                FontSize = AppleTheme.CaptionSize,
                Foreground = AppleTheme.TextPrimary,
                TextAlignment = TextAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(4, 6, 4, 0),
            };
            var body = new StackPanel { HorizontalAlignment = HorizontalAlignment.Stretch };
            body.Children.Add(icon);
            body.Children.Add(name);

            var tile = new Border
            {
                Background = AppleTheme.SurfaceControl,
                BorderBrush = AppleTheme.Separator,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(AppleTheme.RadiusMd),
                Padding = new Thickness(8, 10, 8, 10),
                Margin = new Thickness(0, 0, AppleTheme.SpaceXs, AppleTheme.SpaceXs),
                Width = 96,
                MinHeight = 92,
                Child = body,
            };
            var wrap = new Grid();
            wrap.Children.Add(tile);
            wrap.Children.Add(del);
            host.Children.Add(wrap);
        }
    }

    private void AddApps()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog
        {
            Title = "选择应用（可多选 .exe / .lnk）",
            Filter = "应用程序|*.exe;*.lnk",
            Multiselect = true,
            CheckFileExists = true,
        };
        if (dlg.ShowDialog() == true)
        {
            foreach (var f in dlg.FileNames) _store.Add(f);
            RebuildDetail();
        }
    }

    private static string FilterSummary(AppFilterMode mode) => mode switch
    {
        AppFilterMode.Allowlist => "岛屿只显示过滤名单中的快捷应用。",
        AppFilterMode.Denylist => "岛屿会隐藏过滤名单中的快捷应用。",
        _ => "岛屿会显示快捷应用列表中的所有应用。",
    };

    private void BuildFilter()
    {
        AddPageHeader(_detail, "应用过滤", "设置岛屿展开时的应用显示规则。");

        var modeStack = new StackPanel();
        var labels = new[] { "不过滤", "仅显示名单应用", "隐藏名单应用" };
        int selected = _store.FilterMode switch
        {
            AppFilterMode.Allowlist => 1,
            AppFilterMode.Denylist => 2,
            _ => 0,
        };
        modeStack.Children.Add(AppleTheme.MakeSegmented(labels, selected, i =>
        {
            _store.FilterMode = i switch
            {
                1 => AppFilterMode.Allowlist,
                2 => AppFilterMode.Denylist,
                _ => AppFilterMode.None,
            };
            RebuildDetail();
        }));
        var summary = AppleTheme.Caption(FilterSummary(_store.FilterMode));
        summary.Margin = new Thickness(0, 8, 0, 0);
        modeStack.Children.Add(summary);
        if (_store.FilterMode == AppFilterMode.Allowlist && _store.FilterApps.Count == 0)
        {
            var warn = AppleTheme.Caption("仅显示名单应用时，名单为空会让岛屿不显示任何快捷应用。");
            warn.Foreground = AppleTheme.Danger;
            warn.Margin = new Thickness(0, 6, 0, 0);
            modeStack.Children.Add(warn);
        }
        _detail.Children.Add(Group("过滤方式", modeStack));

        var listPanel = new StackPanel();
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, AppleTheme.SpaceXs) };
        var countText = AppleTheme.Caption($"{_store.FilterApps.Count} 个应用");
        countText.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(countText, Dock.Left);
        var clear = AppleTheme.MakeButton("清空", AppleTheme.ButtonKind.Plain, () =>
        {
            _store.ClearFilter();
            RebuildDetail();
        });
        clear.IsEnabled = _store.FilterApps.Count > 0;
        DockPanel.SetDock(clear, Dock.Right);
        var addF = AppleTheme.MakeButton("添加应用", AppleTheme.ButtonKind.Accent, () =>
        {
            var dlg = new Microsoft.Win32.OpenFileDialog
            {
                Title = "选择过滤应用",
                Filter = "应用程序|*.exe;*.lnk",
                Multiselect = true,
            };
            if (dlg.ShowDialog() == true)
            {
                foreach (var f in dlg.FileNames) _store.AddFilter(f);
                RebuildDetail();
            }
        });
        addF.Margin = new Thickness(0, 0, 8, 0);
        DockPanel.SetDock(addF, Dock.Right);
        header.Children.Add(clear);
        header.Children.Add(addF);
        header.Children.Add(countText);
        listPanel.Children.Add(header);

        if (_store.FilterApps.Count == 0)
        {
            listPanel.Children.Add(AppleTheme.EmptyState("还没有过滤应用", "\uE71C"));
        }
        else
        {
            var wrap = new WrapPanel();
            RefreshAppTiles(wrap, _store.FilterApps.OrderBy(a => a.Order), app =>
            {
                _store.RemoveFilter(app);
                RebuildDetail();
            });
            listPanel.Children.Add(wrap);
        }
        _detail.Children.Add(Group("过滤名单", listPanel));
    }

    private void BuildAppearance()
    {
        AddPageHeader(_detail, "外观布局", "调整岛体形状、内容网格与实时预览。");

        var previewStack = new StackPanel();
        previewStack.Children.Add(ToggleRow("实时预览", () => _previewPinned, v =>
        {
            _previewPinned = v;
            _setPreviewPinned(v);
        }));
        var previewHint = AppleTheme.Caption("开启后岛体保持展开，调节参数可即时看到变化。");
        previewHint.Margin = new Thickness(0, 2, 0, 0);
        previewStack.Children.Add(previewHint);
        _detail.Children.Add(Group("预览", previewStack));

        var gridStack = new StackPanel();
        AddSlider(gridStack, "图标大小", () => _settings.IconSize, v => _settings.IconSize = v, 32, 72, 1, "px");
        AddStepper(gridStack, "每行列数", () => _settings.Columns, v => _settings.Columns = v, 3, 12, "列");
        AddSlider(gridStack, "图标间距", () => _settings.IconSpacing, v => _settings.IconSpacing = v, 6, 24, 1, "px");
        AddSlider(gridStack, "顶部内边距", () => _settings.ContentTopPadding, v => _settings.ContentTopPadding = v, 10, 46, 1, "px");
        _detail.Children.Add(Group("应用网格", gridStack, insetList: true));

        var shapeStack = new StackPanel();
        AddNumberField(shapeStack, "岛屿宽度", () => _settings.IslandWidth, v => _settings.IslandWidth = v,
            0, 4000, "px",
            () => $"生效 {IslandShape.BarWidth(_settings):0}px · 面板 {IslandShape.BodyWidth(_settings):0}px · 自动 {_settings.ExpandedWidth * 1.2:0}px（填 0 = 自动）");
        AddSlider(shapeStack, "静止宽度", () => _settings.CompactWidth, v => _settings.CompactWidth = v, 60, 400, 1, "px");
        AddSlider(shapeStack, "顶栏高度", () => _settings.TopBarHeight, v => _settings.TopBarHeight = v, 27, 70, 1, "px");
        AddSlider(shapeStack, "整体位移", () => _settings.IslandYOffset, v => _settings.IslandYOffset = v, -30, 40, 1, "px");
        AddSlider(shapeStack, "顶栏圆角", () => _settings.CompactCornerRadius, v => _settings.CompactCornerRadius = v, 0, 20, 1, "px");
        AddSlider(shapeStack, "面板圆角", () => _settings.ExpandedCornerRadius, v => _settings.ExpandedCornerRadius = v, 0, 32, 1, "px");
        AddSlider(shapeStack, "融合半径", () => _settings.GooeyBlurRadius, v => _settings.GooeyBlurRadius = v, 0, 40, 1, "px");
        _detail.Children.Add(Group("岛屿形状", shapeStack, insetList: true));
    }

    private void BuildTrigger()
    {
        AddPageHeader(_detail, "触发方式", "控制鼠标靠近屏幕顶部时的触发区域与响应延迟。");

        var zoneStack = new StackPanel();
        zoneStack.Children.Add(ActionRow("显示当前触发区域", "显示触发区域", AppleTheme.ButtonKind.Tinted, _showTriggerPreview));
        zoneStack.Children.Add(ToggleRow("常驻显示触发区域", () => _triggerPreviewOn, v =>
        {
            _triggerPreviewOn = v;
            _setTriggerPreview(v);
        }));
        AddSlider(zoneStack, "区域宽度", () => _settings.HoverZoneWidth, v => _settings.HoverZoneWidth = v, 120, 360, 1, "px");
        AddSlider(zoneStack, "区域高度", () => _settings.HoverZoneHeight, v => _settings.HoverZoneHeight = v, 3, 24, 1, "px");
        AddSlider(zoneStack, "纵向偏移", () => _settings.HoverZoneYOffset, v => _settings.HoverZoneYOffset = v, 16, 64, 1, "px");
        _detail.Children.Add(Group("触发区域", zoneStack, insetList: true));

        var timeStack = new StackPanel();
        AddSlider(timeStack, "进入延迟", () => _settings.HoverEnterDelay, v => _settings.HoverEnterDelay = v, 0, 0.35, 0.01, "s", 2);
        AddSlider(timeStack, "隐藏延迟", () => _settings.HideDelay, v => _settings.HideDelay = v, 0, 0.6, 0.01, "s", 2);
        _detail.Children.Add(Group("响应时间", timeStack, insetList: true));
    }

    private void BuildAnimation()
    {
        AddPageHeader(_detail, "动画", "调整展开、收起与内容淡入淡出的节奏。");

        var durStack = new StackPanel();
        AddSlider(durStack, "展开时长", () => _settings.ExpandDuration, v => _settings.ExpandDuration = v, 0.2, 1.2, 0.01, "s", 2);
        AddSlider(durStack, "收起时长", () => _settings.CollapseDuration, v => _settings.CollapseDuration = v, 0.12, 0.7, 0.01, "s", 2);
        AddSlider(durStack, "内容出现延迟", () => _settings.RevealDelay, v => _settings.RevealDelay = v, 0, 0.5, 0.01, "s", 2);
        AddSlider(durStack, "内容淡入", () => _settings.ContentFadeInDuration, v => _settings.ContentFadeInDuration = v, 0.05, 0.4, 0.01, "s", 2);
        AddSlider(durStack, "内容淡出", () => _settings.ContentFadeOutDuration, v => _settings.ContentFadeOutDuration = v, 0.03, 0.25, 0.01, "s", 2);
        _detail.Children.Add(Group("时长", durStack, insetList: true));

        var curveStack = new StackPanel();
        AddTextField(curveStack, "展开曲线", () => _settings.ExpandTimingCurve, v => _settings.ExpandTimingCurve = v);
        AddTextField(curveStack, "收起曲线", () => _settings.CollapseTimingCurve, v => _settings.CollapseTimingCurve = v);
        var hint = AppleTheme.Caption("格式：x1, y1, x2, y2，例如 0.65, 0, 0.35, 1");
        hint.Margin = new Thickness(0, 2, 0, 0);
        curveStack.Children.Add(hint);
        _detail.Children.Add(Group("时间曲线", curveStack));
    }

    public void RefreshData()
    {
        if (Dispatcher.CheckAccess()) RebuildDetail();
        else Dispatcher.InvokeAsync(RebuildDetail);
    }
}
