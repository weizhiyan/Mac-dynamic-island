using System.Windows.Media;
using DynamicIsland.Core;

namespace DynamicIsland.Island;

/// <summary>
/// 驱动岛体形状形变动画。通过 CompositionTarget.Rendering 以显示器刷新率推进 raw 进度 u，
/// 再用对应贝塞尔曲线缓动得到几何进度 p，重建合并路径并回调应用方。
/// 展开与收起各用自己的时长与曲线，1:1 还原 Mac 的 CABasicAnimation。
/// </summary>
public sealed class ShapeMorpher : IDisposable
{
    private readonly IslandSettings _settings;
    private readonly Action<Geometry> _apply;

    private bool _active;
    private bool _expanding;
    private double _u;          // raw 进度：0 收缩 / 1 展开
    private double _startU;
    private long _startTicks;
    private long _durationMs;
    private BezierEase _ease = new(0.65, 0, 0.35, 1);   // 占位默认值，动画开始时会被替换

    public ShapeMorpher(IslandSettings settings, Action<Geometry> apply)
    {
        _settings = settings;
        _apply = apply;
    }

    public bool IsAnimating => _active;

    /// <summary>立即跳转到某状态（不带动画），并应用几何。</summary>
    public void JumpTo(bool expanded)
    {
        Stop();
        _u = expanded ? 1 : 0;
        Apply();
    }

    public void Expand()
    {
        Start(direction: true);
    }

    public void Collapse()
    {
        Start(direction: false);
    }

    private void Start(bool direction)
    {
        _startU = _u;
        _expanding = direction;
        double target = _expanding ? 1 : 0;
        // 若本来就在目标态则直接跳转
        _durationMs = (long)((_expanding ? _settings.ExpandDuration : _settings.CollapseDuration) * 1000);
        _ease = _expanding ? _settings.ExpandEase : _settings.CollapseEase;
        if (_startU == target) { Apply(); return; }

        _startTicks = Environment.TickCount64;
        if (!_active)
        {
            _active = true;
            CompositionTarget.Rendering += OnRendering;
        }
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        long now = Environment.TickCount64;
        if (_startTicks == 0) _startTicks = now;
        double target = _expanding ? 1 : 0;
        double elapsed = now - _startTicks;
        double frac = _durationMs <= 0 ? 1 : Math.Clamp(elapsed / _durationMs, 0, 1);
        _u = _startU + (target - _startU) * frac;

        Apply();

        if (frac >= 1)
        {
            _u = target;
            Stop();
            Apply();
            Completed?.Invoke(_expanding);
        }
    }

    private void Apply()
    {
        double p = _ease.Ease(_u);
        var geo = IslandShape.Build(_settings, p);
        geo.Freeze();
        _apply(geo);
    }

    private void Stop()
    {
        if (_active)
        {
            _active = false;
            CompositionTarget.Rendering -= OnRendering;
        }
    }

    /// <summary>动画方向完成时触发（参数 true=展开完成，false=收起完成）。</summary>
    public event Action<bool>? Completed;

    public void Dispose() => Stop();
}