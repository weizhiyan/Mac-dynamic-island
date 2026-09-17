using System.Net.Http;
using System.Text.Json;
using DynamicIsland.Native;

namespace DynamicIsland.Core;

/// <summary>
/// 对照 GitHub Release 检查 Windows 版是否有新版本。
/// 更新包是同一仓库 Release 上的 <c>Windows-Dynamic-Island-*.zip</c>，不另开仓库。
/// </summary>
public static class UpdateService
{
    public const string Repo = "weizhiyan/Mac-dynamic-island";
    public const string ReleasesUrl = "https://github.com/" + Repo + "/releases";

    private const string LatestApi = "https://api.github.com/repos/" + Repo + "/releases/latest";

    private static readonly HttpClient Http = CreateClient();

    public static string CurrentVersion
    {
        get
        {
            var v = typeof(UpdateService).Assembly.GetName().Version;
            return v == null ? "1.0.2" : $"{v.Major}.{v.Minor}.{v.Build}";
        }
    }

    public static async Task<UpdateCheckResult> CheckAsync()
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, LatestApi);
            using var resp = await Http.SendAsync(req).ConfigureAwait(false);
            resp.EnsureSuccessStatusCode();
            await using var stream = await resp.Content.ReadAsStreamAsync().ConfigureAwait(false);
            using var doc = await JsonDocument.ParseAsync(stream).ConfigureAwait(false);
            var root = doc.RootElement;

            string tag = root.GetProperty("tag_name").GetString() ?? "";
            string latest = tag.StartsWith("v", StringComparison.OrdinalIgnoreCase) ? tag[1..] : tag;
            string htmlUrl = root.TryGetProperty("html_url", out var html) ? html.GetString() ?? ReleasesUrl : ReleasesUrl;

            string? zipUrl = null;
            if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
            {
                foreach (var asset in assets.EnumerateArray())
                {
                    string name = asset.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    if (!name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) continue;
                    if (name.Contains("Windows", StringComparison.OrdinalIgnoreCase) ||
                        name.Contains("灵动岛", StringComparison.Ordinal))
                    {
                        zipUrl = asset.TryGetProperty("browser_download_url", out var u) ? u.GetString() : null;
                        if (!string.IsNullOrEmpty(zipUrl)) break;
                    }
                }
            }

            bool hasUpdate = TryVersion(latest, out var remote)
                             && TryVersion(CurrentVersion, out var local)
                             && remote > local;

            return new UpdateCheckResult
            {
                LatestVersion = latest,
                HasUpdate = hasUpdate,
                DownloadUrl = zipUrl,
                ReleaseUrl = htmlUrl,
            };
        }
        catch (Exception ex)
        {
            DebugLog.Write("检查更新失败: " + ex.Message);
            return new UpdateCheckResult { Error = ex.Message };
        }
    }

    public static void OpenUrl(string url)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            DebugLog.Write("打开更新链接失败: " + ex.Message);
        }
    }

    private static bool TryVersion(string text, out Version version)
    {
        var parts = (text ?? "").Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        while (parts.Length < 3)
            parts = parts.Append("0").ToArray();
        return Version.TryParse(string.Join('.', parts.Take(4)), out version!);
    }

    private static HttpClient CreateClient()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("DynamicIsland-Windows/" + CurrentVersion);
        http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return http;
    }
}

public sealed class UpdateCheckResult
{
    public string LatestVersion { get; init; } = "";
    public bool HasUpdate { get; init; }
    public string? DownloadUrl { get; init; }
    public string? ReleaseUrl { get; init; }
    public string? Error { get; init; }
    public bool Failed => !string.IsNullOrEmpty(Error);
    public string OpenUrl => DownloadUrl ?? ReleaseUrl ?? UpdateService.ReleasesUrl;
}
