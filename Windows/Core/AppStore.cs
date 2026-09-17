using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text.Json;

namespace DynamicIsland.Core;

/// <summary>过滤方式：不过滤 / 仅显示名单 / 隐藏名单。</summary>
public enum AppFilterMode
{
    None,
    Allowlist,
    Denylist,
}

/// <summary>
/// 快捷应用列表 + 过滤名单，JSON 持久化到 %AppData%\DynamicIsland\apps.json。
/// </summary>
public sealed class AppStore : INotifyPropertyChanged
{
    private static readonly string Dir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DynamicIsland");

    private static readonly string AppsFile = Path.Combine(Dir, "apps.json");
    private static readonly string FilterFile = Path.Combine(Dir, "filter.json");

    private ObservableCollection<AppItem> _apps;
    private ObservableCollection<AppItem> _filterApps;
    private AppFilterMode _filterMode;

    public AppStore()
    {
        _apps = Load(AppsFile) ?? DefaultWindowsApps();
        _filterApps = Load(FilterFile) ?? new ObservableCollection<AppItem>();
        _apps.CollectionChanged += (_, _) => { Save(_apps, AppsFile); OnPropertyChanged(nameof(Apps)); };
        _filterApps.CollectionChanged += (_, _) => { Save(_filterApps, FilterFile); OnPropertyChanged(nameof(FilterApps)); };
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<AppItem> Apps => _apps;
    public ObservableCollection<AppItem> FilterApps => _filterApps;

    public AppFilterMode FilterMode
    {
        get => _filterMode;
        set { if (_filterMode != value) { _filterMode = value; OnPropertyChanged(nameof(FilterMode)); OnPropertyChanged(nameof(VisibleApps)); } }
    }

    /// <summary>按过滤方式返回最终显示的应用（按 Order 排序）。</summary>
    public ObservableCollection<AppItem> VisibleApps
    {
        get
        {
            var ordered = _apps.OrderBy(a => a.Order).ToList();
            switch (FilterMode)
            {
                case AppFilterMode.Allowlist:
                    ordered = ordered.Where(IsInFilterList).ToList();
                    break;
                case AppFilterMode.Denylist:
                    ordered = ordered.Where(a => !IsInFilterList(a)).ToList();
                    break;
            }
            return new ObservableCollection<AppItem>(ordered);
        }
    }

    public void Add(string path)
    {
        if (_apps.Any(a => string.Equals(a.Path, path, StringComparison.OrdinalIgnoreCase))) return;
        _apps.Add(new AppItem { Name = System.IO.Path.GetFileNameWithoutExtension(path), Path = path, Order = (_apps.Count == 0 ? 0 : _apps.Max(a => a.Order) + 1) });
        OnPropertyChanged(nameof(VisibleApps));
    }

    public void AddFilter(string path)
    {
        if (_filterApps.Any(a => string.Equals(a.Path, path, StringComparison.OrdinalIgnoreCase))) return;
        _filterApps.Add(new AppItem { Name = System.IO.Path.GetFileNameWithoutExtension(path), Path = path, Order = (_filterApps.Count == 0 ? 0 : _filterApps.Max(a => a.Order) + 1) });
        OnPropertyChanged(nameof(VisibleApps));
    }

    public void Remove(AppItem item) => _apps.Remove(item);
    public void RemoveFilter(AppItem item) => _filterApps.Remove(item);
    public void ClearFilter() => _filterApps.Clear();

    public void MoveBefore(AppItem moved, AppItem target)
    {
        if (moved.Id == target.Id) return;
        var ordered = _apps.OrderBy(a => a.Order).ToList();
        int s = ordered.FindIndex(a => a.Id == moved.Id);
        int t = ordered.FindIndex(a => a.Id == target.Id);
        if (s < 0 || t < 0) return;
        ordered.RemoveAt(s);
        t = ordered.FindIndex(a => a.Id == target.Id);
        ordered.Insert(t, moved);
        for (int i = 0; i < ordered.Count; i++) ordered[i].Order = i;
        OnPropertyChanged(nameof(Apps));
        OnPropertyChanged(nameof(VisibleApps));
        Save(_apps, AppsFile);
    }

    public void RestoreDefaults()
    {
        _apps = DefaultWindowsApps();
        Save(_apps, AppsFile);
        OnPropertyChanged(nameof(Apps));
        OnPropertyChanged(nameof(VisibleApps));
    }

    private bool IsInFilterList(AppItem item)
        => _filterApps.Any(f => string.Equals(f.Path, item.Path, StringComparison.OrdinalIgnoreCase));

    /// <summary>Windows 常用默认应用（用户可自行增删调整）。</summary>
    public static ObservableCollection<AppItem> DefaultWindowsApps()
    {
        string windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        // 旧版这里用的是 SystemApps\... 下的打包应用路径，那些路径在 Win10/11 上
        // 并不是可直接访问的文件，导致默认列表几乎全被过滤掉（只剩记事本）。
        // 改成用「几乎一定存在的系统可执行文件 + 常见安装路径」，逐项探测存在性。
        var candidates = new (string Name, string Path)[]
        {
            ("文件资源管理器", Path.Combine(windir, @"explorer.exe")),
            ("记事本", Path.Combine(windir, @"System32\notepad.exe")),
            ("画图", Path.Combine(windir, @"System32\mspaint.exe")),
            ("计算器", Path.Combine(windir, @"System32\calc.exe")),
            ("任务管理器", Path.Combine(windir, @"System32\Taskmgr.exe")),
            ("终端", Path.Combine(local, @"Microsoft\WindowsApps\wt.exe")),
            ("设置", Path.Combine(windir, @"ImmersiveControlPanel\SystemSettings.exe")),
            ("Edge", Path.Combine(pf86, @"Microsoft\Edge\Application\msedge.exe")),
            ("Edge", Path.Combine(pf, @"Microsoft\Edge\Application\msedge.exe")),
            ("Chrome", Path.Combine(pf, @"Google\Chrome\Application\chrome.exe")),
            ("Chrome", Path.Combine(pf86, @"Google\Chrome\Application\chrome.exe")),
            ("VS Code", Path.Combine(local, @"Programs\Microsoft VS Code\Code.exe")),
            ("微信", Path.Combine(pf, @"Tencent\WeChat\WeChat.exe")),
            ("Snipaste", Path.Combine(local, @"Programs\Snipaste\Snipaste.exe")),
        };
        var list = new ObservableCollection<AppItem>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        int order = 0;
        foreach (var (name, path) in candidates)
        {
            if (path.Length == 0 || !File.Exists(path)) continue;
            if (!seen.Add(path)) continue;   // 同一应用可能有多个候选路径，去重
            list.Add(new AppItem { Name = name, Path = path, Order = order++ });
        }
        if (list.Count == 0)
        {
            // 兜底：真找不到就退回记事本 + 资源管理器。
            string notepad = Path.Combine(windir, @"System32\notepad.exe");
            if (File.Exists(notepad))
                list.Add(new AppItem { Name = "记事本", Path = notepad, Order = order++ });
            string explorer = Path.Combine(windir, @"explorer.exe");
            if (File.Exists(explorer))
                list.Add(new AppItem { Name = "文件资源管理器", Path = explorer, Order = order++ });
        }
        return list;
    }

    private void OnPropertyChanged([System.Runtime.CompilerServices.CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private static ObservableCollection<AppItem>? Load(string file)
    {
        try
        {
            if (!File.Exists(file)) return null;
            var items = JsonSerializer.Deserialize<List<AppItem>>(File.ReadAllText(file));
            return items is null ? null : new ObservableCollection<AppItem>(items);
        }
        catch { return null; }
    }

    private static void Save(ObservableCollection<AppItem> list, string file)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(file, JsonSerializer.Serialize(list.OrderBy(a => a.Order).ToList()));
        }
        catch { /* 忽略持久化失败 */ }
    }
}