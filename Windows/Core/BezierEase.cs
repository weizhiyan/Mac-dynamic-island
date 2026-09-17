using System;
using System.Globalization;

namespace DynamicIsland.Core;

/// <summary>
/// 4 控制点三次贝塞尔缓动（cubic-bezier），等价于 macOS 的 CAMediaTimingFunction。
/// 曲线字符串格式："x1, y1, x2, y2"，例如展开 "0.65, 0, 0.35, 1"。
/// </summary>
public sealed class BezierEase
{
    private readonly double _x1;
    private readonly double _y1;
    private readonly double _x2;
    private readonly double _y2;

    public BezierEase(double x1, double y1, double x2, double y2)
    {
        _x1 = x1;
        _y1 = y1;
        _x2 = x2;
        _y2 = y2;
    }

    /// <summary>解析 "x1,y1,x2,y2"。失败时用 fallback（展开默认）。</summary>
    public static BezierEase Parse(string raw)
    {
        var parts = (raw ?? "").Split(',');
        if (parts.Length == 4 &&
            double.TryParse(parts[0].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var x1) &&
            double.TryParse(parts[1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var y1) &&
            double.TryParse(parts[2].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var x2) &&
            double.TryParse(parts[3].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var y2))
        {
            return new BezierEase(x1, y1, x2, y2);
        }
        return new BezierEase(0.65, 0, 0.35, 1);
    }

    /// <summary>
    /// 在给定时间 t (0..1) 返回曲线在 y 轴上的插值结果（UI 动画需要的输出）。
    /// </summary>
    public double Ease(double t)
    {
        t = Math.Clamp(t, 0.0, 1.0);
        // 先求 t 对应的曲线 x 参数，再反解出 y。
        // 用牛顿-拉弗森迭代求解 bezier_x(u) = t。
        double u = t;
        for (int i = 0; i < 8; i++)
        {
            double x = Eval(_x1, _x2, u);
            double dx = Deriv(_x1, _x2, u);
            if (Math.Abs(dx) < 1e-6) break;
            double next = u - (x - t) / dx;
            if (next < 0) break;
            if (next > 1) break;
            u = next;
        }
        return Eval(_y1, _y2, u);
    }

    private static double Eval(double p1, double p2, double u)
    {
        // 3u(1-u)^2 p1 + 3u^2(1-u) p2 + u^3
        double v = 1 - u;
        return 3 * u * v * v * p1 + 3 * u * u * v * p2 + u * u * u;
    }

    private static double Deriv(double p1, double p2, double u)
    {
        double v = 1 - u;
        return 3 * v * v * p1 + 6 * v * u * (p2 - p1) + 3 * u * u * (1 - p2);
    }
}