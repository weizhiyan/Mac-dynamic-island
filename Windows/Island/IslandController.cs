using System.Windows;
using System.Windows.Threading;
using DynamicIsland.Core;
using DynamicIsland.Native;
using Forms = System.Windows.Forms;

namespace DynamicIsland.Island;

/// <summary>
/// 职责编排：连接 绘制窗口(gooey) + 内容窗口 + 悬停检测 + 形状动画。
/// 展开 → 形状膨胀 + 内容延迟淡入；收起 → 形状收缩 + 内容淡出。
/// </summary>
public sealed class IslandController : IDisposable
{
    private readonly IslandSettings _settings;
    private readonly AppStore _store;

    private readonly IslandWindow _gooey;
    private readonly ContentIslandWindow _content;
    private readonly HoverDetector _detector;
    private readonly System.ComponentModel.PropertyChangedEventHandler _storeHandler;

    private bool _isExpanded;
    /// <summary>实时预览：设置面板打开时保持展开，方便边调边看。</summary>
    private bool _previewPinned;

    public bool IsExpanded => _isExpanded;

    public IslandWindow Gooey => _gooey;
    public ContentIslandWindow Content => _content;

    public IslandController(
        IslandSettings settings,
        AppStore store,
        Action onSettings,
        Action onAddApp)
    {
        _settings = settings;
        _store = store;

        _gooey = new IslandWindow(settings);
        _content = new ContentIslandWindow(settings, store, onSettings, onAddApp);

        _gooey.ShowAtTopCenter();

        _detector = new HoverDetector(
            settings,
            IslandFrameProvider,
            onEnter: () => OnDispatcher(ShowIsland),
            onLeave: () => OnDispatcher(HideIsland),
            onCursor: p => OnDispatcher(() => ForwardCursor(p)));

        settings.Changed += OnCompactRebuild;
        _storeHandler = (_, _) => OnDispatcher(OnCompactRebuild);
        store.PropertyChanged += _storeHandler;
    }

    private void OnDispatcher(Action a)
    {
        if (_gooey.Dispatcher.CheckAccess()) a();
        else _gooey.Dispatcher.InvokeAsync(a);
    }

    /// <summary>
    /// 展开态「保持展开」的区域 = 可见面板（内容窗）+ 顶部横条。
    /// 以前直接返回整个 gooey 窗口矩形，而该窗口比面板宽且完全透明，
    /// 导致鼠标离岛体两侧很远时也被判定为「还在岛上」而迟迟不收起。
    /// </summary>
    private Rect? IslandFrameProvider()
    {
        if (!_isExpanded) return null;

        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double cx = screen.Left + screen.Width / 2.0;
        double islandTop = DpiHelper.IslandTop() + _settings.IslandYOffset;
        double barW = IslandShape.BarWidth(_settings);
        var bar = new Rect(cx - barW / 2, islandTop, barW, _settings.TopBarHeight);

        if (!_content.IsVisible || _content.ActualWidth <= 0 || _content.Height <= 0) return bar;

        var body = new Rect(_content.Left, _content.Top, _content.ActualWidth, _content.Height);
        return Rect.Union(bar, body);
    }

    private void ForwardCursor(Point p)
    {
        if (_isExpanded) _content.SetCursorPosition(p);
    }

    /// <summary>
    /// 实时预览开关：设置面板里调宽度/圆角/融合半径时保持岛体展开，
    /// 这样每次改动都能立刻看到效果（关掉后再恢复正常的悬停展开/收起）。
    /// </summary>
    public void SetPreviewPinned(bool pinned)
    {
        if (_previewPinned == pinned) return;
        _previewPinned = pinned;
        DebugLog.Write($"preview pinned = {pinned}");
        if (pinned) ShowIsland();
        else HideIsland();
    }

    public void ShowIsland()
    {
        if (_isExpanded) return;
        _isExpanded = true;
        _gooey.Morpher.Expand();
        _content.ShowContent(_settings.RevealDelay, _settings.ContentFadeInDuration, _settings.CollapseDuration);

        // 顺序很关键，不能反：
        // 1) 先让绘制层（黑色岛体）置顶，避免被任务栏之类的置顶窗口压住；
        // 2) 再把内容层（图标/按钮）提到绘制层之上。
        // 如果只做第 1 步，黑色面板会盖住图标与按钮 —— 界面看起来就是「一团黑」。
        _gooey.BringToFront();
        _content.BringToFront();
        DebugLog.Write("show island");
    }

    public void HideIsland()
    {
        if (!_isExpanded) return;
        if (_previewPinned) return;   // 预览中不收起
        _isExpanded = false;
        _gooey.Morpher.Collapse();
        _content.HideContent(_settings.ContentFadeOutDuration, _settings.CollapseDuration);
        DebugLog.Write("hide island");
    }

    public void ForceShowForPreview()
    {
        ShowIsland();
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.2) };
        t.Tick += (_, _) => { t.Stop(); HideIsland(); };
        t.Start();
    }

    private void OnCompactRebuild()
    {
        // 设置/应用变化：窗口重定位，并**按当前状态重画形状**。
        // 展开态下也要重画（JumpTo(true)），否则在设置里拖滑杆时形状不会实时更新。
        _gooey.ApplyWindowRect(_isExpanded);
        _gooey.Morpher.JumpTo(_isExpanded);
        _content.ApplyWindowRect();
        _content.RebuildForSettingsChange();
        DebugLog.Write($"rebuild: expanded={_isExpanded} bar={IslandShape.BarWidth(_settings):0} body={IslandShape.BodyWidth(_settings):0} barH={_settings.TopBarHeight:0}");
    }

    public void HideImmediate()
    {
        _isExpanded = false;
        _gooey.Morpher.JumpTo(false);
        _content.HideImmediate();
    }

    public void Dispose()
    {
        _settings.Changed -= OnCompactRebuild;
        _store.PropertyChanged -= _storeHandler;
        _detector.Dispose();
        _gooey.Close();
        _content.Close();
    }
}