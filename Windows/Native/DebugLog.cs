using System.IO;

namespace DynamicIsland.Native;

/// <summary>
/// 轻量诊断日志：写到 %TEMP%\DynamicIsland.log。
/// 只在启动/重建/展开收起等关键节点写少量行，方便在看不到界面的情况下核对布局数值
/// （面板宽度、窗口位置、单元格坐标等）。超过 200KB 自动清空重建。
/// </summary>
public static class DebugLog
{
    private static readonly string FilePath = Path.Combine(Path.GetTempPath(), "DynamicIsland.log");
    private const long MaxBytes = 200 * 1024;

    public static void Write(string message)
    {
        try
        {
            var info = new FileInfo(FilePath);
            if (info.Exists && info.Length > MaxBytes) File.Delete(FilePath);
            File.AppendAllText(FilePath, $"{DateTime.Now:HH:mm:ss.fff}  {message}{Environment.NewLine}");
        }
        catch { /* 日志失败不影响功能 */ }
    }
}
