using System.Windows;
using System.Windows.Threading;
using DynamicIsland.Core;
using DynamicIsland.Native;
using Forms = System.Windows.Forms;

namespace DynamicIsland.Island;

/// <summary>
/// 悬停检测：全局轮询光标，判定是否进入触发区/已展开岛体并驱动展开与收起。
/// state machine 与 Mac 版 HoverDetectorWindowController 一致：
/// 进入 zone（防抖 hoverEnterDelay）→ onEnter；离开（防抖 hideDelay）→ onLeave。
/// </summary>
public sealed class HoverDetector : IDisposable
{
    private readonly IslandSettings _settings;
    private readonly Func<Rect?> _islandFrameProvider;
    private readonly Action _onEnter;
    private readonly Action _onLeave;
    private readonly Action<Point> _onCursor;

    private readonly DispatcherTimer _timer;
    private readonly DispatcherTimer _enterWork;
    private readonly DispatcherTimer _leaveWork;
    private bool _inside;
    private bool _enterScheduled;

    /// <summary>触发区纵向位置：基准是岛体顶端（让开顶部任务栏，并叠加整体位移）。</summary>
    public double HoverZoneTop()
    {
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double islandTop = DpiHelper.IslandTop() + _settings.IslandYOffset;
        double top = islandTop + _settings.HoverZoneYOffset - _settings.HoverZoneHeight;
        return Math.Max(islandTop, Math.Min(top, screen.Bottom - _settings.HoverZoneHeight));
    }

    public HoverDetector(
        IslandSettings settings,
        Func<Rect?> islandFrameProvider,
        Action onEnter,
        Action onLeave,
        Action<Point> onCursor)
    {
        _settings = settings;
        _islandFrameProvider = islandFrameProvider;
        _onEnter = onEnter;
        _onLeave = onLeave;
        _onCursor = onCursor;

        _enterWork = new DispatcherTimer { Interval = TimeSpan.FromSeconds(settings.HoverEnterDelay) };
        _enterWork.Tick += (_, _) => { _enterWork.Stop(); _enterScheduled = false; DoEnter(); };

        _leaveWork = new DispatcherTimer { Interval = TimeSpan.FromSeconds(settings.HideDelay) };
        _leaveWork.Tick += (_, _) => { _leaveWork.Stop(); DoLeave(); };

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.0 / 30.0) };
        _timer.Tick += (_, _) => Poll();
        _timer.Start();
    }

    private void Poll()
    {
        Win32.GetCursorPos(out var pt);
        var cursor = DpiHelper.ToDipPoint(pt);
        _onCursor(cursor);

        var zone = ActivationZone();
        var islandFrame = _islandFrameProvider();

        if (islandFrame is { } frame && frame.Contains(cursor))
        {
            if (!_inside)
            {
                _inside = true;
                _leaveWork.Stop();
                _enterWork.Stop();
                _enterScheduled = false;
                _onEnter();
            }
            return;
        }

        if (zone.Contains(cursor))
        {
            _leaveWork.Stop();
            if (!_enterScheduled && !_inside)
            {
                _enterScheduled = true;
                _enterWork.Interval = TimeSpan.FromSeconds(_settings.HoverEnterDelay);
                _enterWork.Stop();
                _enterWork.Start();
            }
            return;
        }

        _enterWork.Stop();
        _enterScheduled = false;

        if (_inside)
        {
            _inside = false;
            _leaveWork.Interval = TimeSpan.FromSeconds(_settings.HideDelay);
            _leaveWork.Stop();
            _leaveWork.Start();
        }
    }

    private void DoEnter()
    {
        if (!_inside)
        {
            _inside = true;
            _onEnter();
        }
    }

    private void DoLeave()
    {
        _inside = false;
        _onLeave();
    }

    private Rect ActivationZone()
    {
        var screen = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
        double cx = screen.Left + screen.Width / 2.0;
        double top = HoverZoneTop();
        return new Rect(cx - _settings.HoverZoneWidth / 2, top, _settings.HoverZoneWidth, _settings.HoverZoneHeight);
    }

    public void Dispose()
    {
        _timer.Stop();
        _enterWork.Stop();
        _leaveWork.Stop();
    }
}