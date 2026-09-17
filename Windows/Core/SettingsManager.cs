using System.IO;
using System.Text.Json;

namespace DynamicIsland.Core;

/// <summary>IslandSettings 的 JSON 持久化与加载。</summary>
public static class SettingsManager
{
    private static readonly string Dir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DynamicIsland");

    // 注意：字段名不能叫 File，否则会遮蔽 System.IO.File，导致 File.Exists(...) 解析到字符串字段上
    private static readonly string FilePath = Path.Combine(Dir, "settings.json");

    public static IslandSettings Load()
    {
        var settings = new IslandSettings();
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<IslandSettings>(File.ReadAllText(FilePath));
                if (loaded != null)
                {
                    settings = loaded;
                    // 反序列化后重建贝塞尔曲线
                    settings.ExpandEase = BezierEase.Parse(settings.ExpandTimingCurve);
                    settings.CollapseEase = BezierEase.Parse(settings.CollapseTimingCurve);
                }
            }
        }
        catch { /* 用默认值 */ }
        return settings;
    }

    public static void Save(IslandSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* 忽略 */ }
    }
}