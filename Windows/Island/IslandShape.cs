using System.Windows;
using System.Windows.Media;
using DynamicIsland.Core;
using DynamicIsland.Native;
using Forms = System.Windows.Forms;

namespace DynamicIsland.Island;

/// <summary>
/// 生成岛体黑色形状路径（Geometry）。
///
/// Mac 版的结构：**顶栏是一条比面板更宽的横条**（topBarWidth = expandedWidth × 1.5），
/// 面板挂在横条下沿；两者外套 CIGaussianBlur + CIColorMatrix（alpha×19−9）做阈值化 ——
/// 模糊让两块糊在一起、阈值再把边缘压硬，交界处自动长出一段内凹颈部，
/// 视觉上就是液体般的「融合」（gooey）。
///
/// WPF 的 Effects 只有 BlurEffect/DropShadowEffect，没有 ColorMatrix、也没法现编着色器，
/// 所以这里用**解析几何直接画出那条颈部曲线**（内凹 90° 圆弧 + 两侧相切，
/// 即 CSS 的 "inverted corner" 手法），半径 = GooeyBlurRadius × 展开进度。
/// 观感与 Mac 一致，边缘是矢量硬边、任意 DPI 都锐利，也没有滤镜开销。
///
/// 两种宽窄关系都支持：
///   1) 横条比面板宽（Mac 默认效果）→ 颈部在**面板的两个上角**
///   2) 面板比横条宽（把横条调窄时）→ 颈部在**横条的左下/右下角**
///   3) 两者等宽 → 无颈部，就是一根直角接缝的胶囊
///
/// 坐标原点 = gooey 窗口左上角。
/// </summary>
public static class IslandShape
{
    /// <summary>由 App 层注入当前可见应用数量（决定展开高度）。</summary>
    public static Func<int> GetVisibleCount = () => 6;

    private static int ClampedCount()
    {
        try { return Math.Max(1, GetVisibleCount()); }
        catch { return 1; }
    }

    /// <summary>顶栏宽度（用户可手填；默认自动 = 满列面板宽度 × 1.2），并夹进屏幕内。</summary>
    public static double BarWidth(IslandSettings s)
    {
        double w = s.TopBarWidth;
        double screen = 1920;
        try
        {
            var b = DpiHelper.ToDipRect(Forms.Screen.PrimaryScreen!.Bounds);
            if (b.Width > 100) screen = b.Width;
        }
        catch { /* 取不到屏幕就用默认上限 */ }
        return Math.Clamp(w, 200, Math.Max(320, screen - 32));
    }

    /// <summary>展开态面板（body）宽度：按实际可见应用数收窄，不足一行时不留死白。</summary>
    public static double BodyWidth(IslandSettings s) => s.ContentWidth(ClampedCount());

    /// <summary>窗口宽度：要能装下更宽的那一方。</summary>
    public static double WindowWidth(IslandSettings s) => Math.Max(BarWidth(s), BodyWidth(s));

    /// <summary>窗口高度 = 顶栏 + 面板（面板挂在顶栏下沿）。</summary>
    public static double WindowHeight(IslandSettings s)
        => s.TopBarHeight + s.ExpandedHeight(ClampedCount());

    /// <summary>用进度 p (0=收缩, 1=展开，已缓动) 生成融合路径。</summary>
    public static Geometry Build(IslandSettings s, double p)
    {
        double cx = WindowWidth(s) / 2;

        // ---- 顶栏（可见横条）----
        // Mac 上这条横条是静止的（藏在刘海/菜单栏区域里）；Windows 没有刘海遮挡，
        // 静止就铺一条近全屏黑条会很突兀，所以让宽度也参与动画：
        // 静止 = 小胶囊（CompactWidth），展开时拉宽到设定宽度（默认比面板宽 20%）。
        double barTarget = BarWidth(s);
        double barMin = Math.Clamp(Math.Min(s.CompactWidth, barTarget), 60, barTarget);
        double barW = Lerp(barMin, barTarget, p);
        double barH = s.TopBarHeight;
        double barR = Math.Min(Math.Max(s.CompactCornerRadius, 0), barH / 2);

        // ---- 面板（宽度/高度随进度伸缩；顶方角、底圆角，与 Mac 的 islandPath 一致）----
        double bodyStart = Math.Min(Math.Max(1, s.CompactWidth), barMin);   // 静止时面板不宽过横条
        double bodyW = Lerp(bodyStart, BodyWidth(s), p);
        double bodyH = Lerp(Math.Max(1, s.CompactHeight), s.ExpandedHeight(ClampedCount()), p);
        double bodyT = barH;
        double bodyB = bodyT + bodyH;
        double bodyR = Math.Min(s.ExpandedCornerRadius, Math.Max(0.5, bodyH / 2));

        // 两者单侧宽度差：颈部与凸圆角都要塞进这段空间，否则路径自交
        double extra = (barW - bodyW) / 2;
        bool barWider = extra > 0.5;
        bool bodyWider = extra < -0.5;
        double gap = Math.Abs(extra);

        // 融合颈部半径：收起态为 0 → 纯横条
        double neck = Math.Min(Math.Max(0, s.GooeyBlurRadius) * Math.Clamp(p, 0, 1), gap * 0.6);
        neck = Math.Min(neck, Math.Max(0, barH - barR));

        double barL = cx - barW / 2, barRr = cx + barW / 2;
        double bL = cx - bodyW / 2, bR = cx + bodyW / 2;

        var fig = new PathFigure
        {
            StartPoint = new Point(barL + barR, 0),
            IsClosed = true,
            IsFilled = true,
        };
        var segs = fig.Segments;

        // ===== 顶栏 =====
        segs.Add(new LineSegment(new Point(barRr - barR, 0), true));
        AddArc(segs, new Point(barRr, barR), barR, SweepDirection.Clockwise);

        if (barWider)
        {
            // 情况 1：横条更宽 —— 横条下角是凸圆角，颈部在面板上角
            double barBottomR = Math.Min(Math.Min(barR, Math.Max(0, barH - barR)), Math.Max(0, gap - neck));
            AddLine(segs, new Point(barRr, barH - barBottomR));
            AddArc(segs, new Point(barRr - barBottomR, barH), barBottomR, SweepDirection.Clockwise);
            AddLine(segs, new Point(bR + neck, barH));
            AddArc(segs, new Point(bR, barH + neck), neck, SweepDirection.Counterclockwise);
        }
        else if (bodyWider)
        {
            // 情况 2：面板更宽 —— 颈部在横条下角，面板上角是凸圆角
            double topR = Math.Min(bodyR, Math.Max(0, gap - neck));
            AddLine(segs, new Point(barRr, barH - neck));
            AddArc(segs, new Point(barRr + neck, barH), neck, SweepDirection.Counterclockwise);
            AddLine(segs, new Point(bR - topR, barH));
            AddArc(segs, new Point(bR, barH + topR), topR, SweepDirection.Clockwise);
        }
        else
        {
            // 情况 3：等宽，直接接上
            AddLine(segs, new Point(bR, barH));
        }

        // ===== 面板右侧 → 底边 =====
        AddLine(segs, new Point(bR, bodyB - bodyR));
        AddArc(segs, new Point(bR - bodyR, bodyB), bodyR, SweepDirection.Clockwise);
        AddLine(segs, new Point(bL + bodyR, bodyB));

        // ===== 面板左下角 → 左侧上行 =====
        AddArc(segs, new Point(bL, bodyB - bodyR), bodyR, SweepDirection.Clockwise);

        if (bodyWider)
        {
            double topR = Math.Min(bodyR, Math.Max(0, gap - neck));
            AddLine(segs, new Point(bL, barH + topR));
            AddArc(segs, new Point(bL + topR, barH), topR, SweepDirection.Clockwise);
            AddLine(segs, new Point(barL - neck, barH));
            AddArc(segs, new Point(barL, barH - neck), neck, SweepDirection.Counterclockwise);
        }
        else if (barWider)
        {
            double barBottomR = Math.Min(Math.Min(barR, Math.Max(0, barH - barR)), Math.Max(0, gap - neck));
            AddLine(segs, new Point(bL, barH + neck));
            AddArc(segs, new Point(bL - neck, barH), neck, SweepDirection.Counterclockwise);
            AddLine(segs, new Point(barL + barBottomR, barH));
            AddArc(segs, new Point(barL, barH - barBottomR), barBottomR, SweepDirection.Clockwise);
        }
        else
        {
            AddLine(segs, new Point(bL, barH));
        }

        // ===== 顶栏左侧上行 + 左上角 =====
        AddLine(segs, new Point(barL, barR));
        AddArc(segs, new Point(barL + barR, 0), barR, SweepDirection.Clockwise);

        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        geo.Freeze();
        return geo;
    }

    /// <summary>半径过小时退化成直线，避免零半径圆弧产生退化路径。</summary>
    private static void AddArc(PathSegmentCollection segs, Point to, double radius, SweepDirection sweep)
    {
        if (radius > 0.5)
            segs.Add(new ArcSegment(to, new Size(radius, radius), 0, false, sweep, true));
        else
            segs.Add(new LineSegment(to, true));
    }

    /// <summary>零长度线段直接跳过（颈部/圆角被夹到 0 时会出现）。</summary>
    private static void AddLine(PathSegmentCollection segs, Point to)
    {
        PathSegment? last = segs.Count > 0 ? segs[segs.Count - 1] : null;
        Point? from = last switch
        {
            ArcSegment a => a.Point,
            LineSegment l => l.Point,
            _ => null,
        };
        if (from is { } f && NearlySame(f, to)) return;
        segs.Add(new LineSegment(to, true));
    }

    private static bool NearlySame(Point a, Point b) => Math.Abs(a.X - b.X) < 0.01 && Math.Abs(a.Y - b.Y) < 0.01;

    private static double Lerp(double a, double b, double p) => a + (b - a) * Math.Clamp(p, 0, 1);
}
