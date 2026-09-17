using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DynamicIsland.Core;

/// <summary>
/// 全部可调参数（默认值与 Mac 版 SettingsStore 对齐 1:1）。
/// 实现 INotifyPropertyChanged，便于设置面板实时绑定与岛体即时重建。
/// </summary>
public sealed class IslandSettings : INotifyPropertyChanged
{
    public const int MinColumns = 3;
    public const int MaxColumns = 12;

    // ---- 应用网格 ----
    double _iconSize = 60;
    int _columns = 6;
    double _iconSpacing = 13;

    // ---- 悬停触发 ----
    double _hoverZoneWidth = 217;
    double _hoverZoneHeight = 7;
    double _hoverZoneYOffset = 39;
    double _hoverEnterDelay = 0;
    double _hideDelay = 0.12;

    // ---- 布局 ----
    double _topBarYOffset = 38;
    double _contentPadding = 16;
    double _contentTopPadding = 36;
    double _bottomPadding = 16;
    double _compactWidth = 140;
    double _compactHeight = 1;
    double _topBarHeight = 40;
    double _gooeyBlurRadius = 16;
    /// <summary>顶栏（岛体可见横条）宽度；0 = 自动（面板宽度 × 1.2，并夹到屏幕内）。</summary>
    double _islandWidth = 0;
    /// <summary>整体位移：在「工作区顶部」基础上整体上下移动，负数向上。</summary>
    double _islandYOffset = 0;

    // ---- 动画 ----
    double _expandDuration = 0.5;
    double _collapseDuration = 0.7;
    double _revealDelay = 0.31;
    double _contentFadeInDuration = 0.35;
    double _contentFadeOutDuration = 0.08;

    // ---- 时间曲线 ----
    string _expandTimingCurve = "0.65, 0, 0.35, 1";
    string _collapseTimingCurve = "0.25, 0.1, 0.25, 1";

    // ---- 圆角 ----
    // Windows 没有实体刘海，紧凑态不做「贴合刘海」的方角，改用一个圆角胶囊，
    // 与展开态的圆角衔接更自然（Mac 版默认 2 是为了和物理刘海对齐）。
    double _compactCornerRadius = 12;
    double _expandedCornerRadius = 16;

    // ---- 系统 ----
    bool _launchAtLoginEnabled;

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? Changed;

    // 应用网格
    public double IconSize { get => _iconSize; set => Set(ref _iconSize, value); }
    public int Columns
    {
        get => _columns;
        set => Set(ref _columns, Math.Clamp(value, MinColumns, MaxColumns));
    }
    public double IconSpacing { get => _iconSpacing; set => Set(ref _iconSpacing, value); }

    // 悬停触发
    public double HoverZoneWidth { get => _hoverZoneWidth; set => Set(ref _hoverZoneWidth, value); }
    public double HoverZoneHeight { get => _hoverZoneHeight; set => Set(ref _hoverZoneHeight, value); }
    public double HoverZoneYOffset { get => _hoverZoneYOffset; set => Set(ref _hoverZoneYOffset, value); }
    public double HoverEnterDelay { get => _hoverEnterDelay; set => Set(ref _hoverEnterDelay, value); }
    public double HideDelay { get => _hideDelay; set => Set(ref _hideDelay, value); }

    // 布局
    public double TopBarYOffset { get => _topBarYOffset; set => Set(ref _topBarYOffset, value); }
    public double ContentPadding { get => _contentPadding; set => Set(ref _contentPadding, value); }
    public double ContentTopPadding { get => _contentTopPadding; set => Set(ref _contentTopPadding, value); }
    public double BottomPadding { get => _bottomPadding; set => Set(ref _bottomPadding, value); }
    public double CompactWidth { get => _compactWidth; set => Set(ref _compactWidth, value); }
    public double CompactHeight { get => _compactHeight; set => Set(ref _compactHeight, value); }
    public double TopBarHeight { get => _topBarHeight; set { var v = Math.Max(27.0, Math.Ceiling(BoundTopBarHeight(value))); Set(ref _topBarHeight, v); } }
    public double GooeyBlurRadius { get => _gooeyBlurRadius; set => Set(ref _gooeyBlurRadius, value); }
    /// <summary>顶栏宽度。0 = 自动（面板宽度 × 1.2）。想要「顶栏比面板宽」就把它调大。</summary>
    public double IslandWidth { get => _islandWidth; set => Set(ref _islandWidth, Math.Max(0, value)); }
    /// <summary>整体位移（负数向上）。</summary>
    public double IslandYOffset { get => _islandYOffset; set => Set(ref _islandYOffset, value); }

    private static double BoundTopBarHeight(double value) => value;

    // 动画
    public double ExpandDuration { get => _expandDuration; set => Set(ref _expandDuration, value); }
    public double CollapseDuration { get => _collapseDuration; set => Set(ref _collapseDuration, value); }
    public double RevealDelay { get => _revealDelay; set => Set(ref _revealDelay, value); }
    public double ContentFadeInDuration { get => _contentFadeInDuration; set => Set(ref _contentFadeInDuration, value); }
    public double ContentFadeOutDuration { get => _contentFadeOutDuration; set => Set(ref _contentFadeOutDuration, value); }

    // 时间曲线
    public string ExpandTimingCurve { get => _expandTimingCurve; set => Set(ref _expandTimingCurve, value, () => ExpandEase = BezierEase.Parse(value)); }
    public string CollapseTimingCurve { get => _collapseTimingCurve; set => Set(ref _collapseTimingCurve, value, () => CollapseEase = BezierEase.Parse(value)); }

    [NonSerialized] public BezierEase ExpandEase = BezierEase.Parse("0.65, 0, 0.35, 1");
    [NonSerialized] public BezierEase CollapseEase = BezierEase.Parse("0.25, 0.1, 0.25, 1");

    // 圆角
    public double CompactCornerRadius { get => _compactCornerRadius; set => Set(ref _compactCornerRadius, value); }
    public double ExpandedCornerRadius { get => _expandedCornerRadius; set => Set(ref _expandedCornerRadius, value); }

    // 系统
    public bool LaunchAtLoginEnabled { get => _launchAtLoginEnabled; set => Set(ref _launchAtLoginEnabled, value); }

    // ---- 派生值（只读，按需计算）----
    /// <summary>
    /// 顶栏（岛体可见横条）宽度。默认自动 = 满列面板宽度 × 1.2，
    /// 也就是**比面板更宽**——Mac 版就是靠这点做出「宽横条 + 面板融合」的观感。
    /// 想要精确控制就在设置里直接填数字（IslandWidth）。
    /// </summary>
    public double TopBarWidth => IslandWidth > 1 ? IslandWidth : ExpandedWidth * 1.2;

    /// <summary>
    /// 按实际可见应用数计算面板宽度：不足一行时不收满列，避免右侧留一大片死白。
    /// 下限为顶部胶囊宽度，否则应用很少时展开的面板比胶囊还窄，会呈「倒 T」形。
    /// </summary>
    public double ContentWidth(int visibleAppCount)
    {
        int cols = Math.Max(1, Math.Min(Columns, Math.Max(1, visibleAppCount)));
        double content = cols * IconSize + (cols - 1) * IconSpacing + ContentPadding * 2;
        return Math.Max(CompactWidth, content);
    }

    /// <summary>满列宽（窗口宽度、字号换算等场景使用）。</summary>
    public double ExpandedWidth => ContentWidth(int.MaxValue);

    /// <summary>内容实际顶部留白，避免与悬浮控制按钮重叠（对照 Mac max(top,34)）。</summary>
    public double EffectiveContentTopPadding => Math.Max(ContentTopPadding, 34);

    /// <summary>展开态岛体高度（行数取决于可见应用数，见 AppStore）。</summary>
    public double ExpandedHeight(int visibleAppCount)
    {
        int cols = Math.Max(1, Columns);
        int rows = Math.Max(1, (int)Math.Ceiling((double)visibleAppCount / cols));
        return rows * IconSize + (rows - 1) * IconSpacing + EffectiveContentTopPadding + BottomPadding;
    }

    private void Set<T>(
        ref T field, T value,
        Action? afterChange = null,
        [CallerMemberName] string? name = null)
    {
        if (!EqualityComparer<T>.Default.Equals(field, value))
        {
            field = value;
            afterChange?.Invoke();
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
            Changed?.Invoke();
        }
    }

    /// <summary>恢复所有参数到默认值（对照 Mac restoreDefaults）。</summary>
    public void RestoreDefault()
    {
        IconSize = 60;
        Columns = 6;
        IconSpacing = 13;
        HoverZoneWidth = 217;
        HoverZoneHeight = 7;
        HoverZoneYOffset = 39;
        HoverEnterDelay = 0;
        HideDelay = 0.12;
        TopBarYOffset = 38;
        ContentPadding = 16;
        ContentTopPadding = 36;
        BottomPadding = 16;
        CompactWidth = 140;
        CompactHeight = 1;
        GooeyBlurRadius = 16;
        IslandWidth = 0;
        IslandYOffset = 0;
        TopBarHeight = 40;
        ExpandDuration = 0.5;
        CollapseDuration = 0.7;
        RevealDelay = 0.31;
        ContentFadeInDuration = 0.35;
        ContentFadeOutDuration = 0.08;
        ExpandTimingCurve = "0.65, 0, 0.35, 1";
        CollapseTimingCurve = "0.25, 0.1, 0.25, 1";
        CompactCornerRadius = 12;
        ExpandedCornerRadius = 16;
    }
}