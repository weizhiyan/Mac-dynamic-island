using Forms = System.Windows.Forms;

namespace DynamicIsland.Native;

/// <summary>
/// DPI 辅助：统一坐标系为 WPF DIP。
/// WPF 窗口 Look/Top/Width/Height 是 DIP；GetCursorPos / Screen 边界是物理像素。
/// 用系统 DPI 把物理像素换算成 DIP，保证在 100%/150% 等常见缩放下一致。
/// </summary>
public static class DpiHelper
{
    private static readonly double Scale = GetScale();

    private static double GetScale()
    {
        try
        {
            return Win32.GetDpiForSystem() / 96.0;
        }
        catch { return 1.0; }
    }

    public static double ScaleFactor => Scale;

    public static double InputToDip(double physical) => physical / Scale;

    public static System.Windows.Rect ToDipRect(System.Drawing.Rectangle r)
        => new System.Windows.Rect(r.Left / Scale, r.Top / Scale, r.Width / Scale, r.Height / Scale);

    public static System.Windows.Point ToDipPoint(Win32.POINT p)
        => new System.Windows.Point(p.X / Scale, p.Y / Scale);

    /// <summary>
    /// 岛体顶端坐标：取工作区顶部而不是屏幕顶部。
    /// 任务栏停靠在顶部时（不少用户这么用），若岛体贴着屏幕 0 点，
    /// 上部胶囊会与任务栏重叠 —— 绘制层会被任务栏压住，而内容层（按钮）又在任务栏之上，
    /// 结果就是「按钮浮在面板外面」。这里自动让开任务栏。
    /// 任务栏在底部时工作区顶部 == 屏幕顶部，行为与之前一致。
    /// </summary>
    public static double IslandTop()
    {
        try
        {
            var screen = Forms.Screen.PrimaryScreen;
            if (screen == null) return 0;
            var bounds = ToDipRect(screen.Bounds);
            var work = ToDipRect(screen.WorkingArea);
            double top = Math.Max(bounds.Top, work.Top);
            // 任务栏几乎占满屏幕（异常情况）时不至于把岛体推到底部
            return top > bounds.Top + bounds.Height * 0.5 ? bounds.Top : top;
        }
        catch { return 0; }
    }
}