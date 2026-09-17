using System.Windows;
using DynamicIsland.Core;
using DynamicIsland.Island;
using DynamicIsland.Native;
using DynamicIsland.Ui;

namespace DynamicIsland;

public partial class App : Application
{
    public IslandSettings Settings { get; private set; } = null!;
    public AppStore Store { get; private set; } = null!;
    public IslandController Controller { get; private set; } = null!;

    private TrayIcon? _tray;
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 兜底：界面线程异常只记日志、不让程序退出（避免「点某个设置页就崩」），
        // 具体原因看 %TEMP%\DynamicIsland.log
        DispatcherUnhandledException += (_, args) =>
        {
            DebugLog.Write("UI 未处理异常: " + args.Exception);
            args.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            DebugLog.Write("致命异常: " + args.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            DebugLog.Write("未观察的任务异常: " + args.Exception);
            args.SetObserved();
        };

        Settings = SettingsManager.Load();
        Store = new AppStore();

        // 让岛体形状依赖真实可见应用数。
        IslandShape.GetVisibleCount = () => Store.VisibleApps.Count;

        DebugLog.Write($"=== 启动 === 应用={Store.VisibleApps.Count} 列数={Settings.Columns} 图标={Settings.IconSize:0} " +
                       $"顶栏宽设置={Settings.IslandWidth:0}(0=自动) 融合半径={Settings.GooeyBlurRadius:0} 位移={Settings.IslandYOffset:0}");

        // 用户开启过自启则每次启动确保注册表在。
        if (Settings.LaunchAtLoginEnabled) AutostartService.SetEnabled(true);

        Controller = new IslandController(
            Settings,
            Store,
            onSettings: OpenSettings,
            onAddApp: AddAppViaPicker);

        _tray = new TrayIcon(
            showIsland: () => Controller.ForceShowForPreview(),
            openSettings: OpenSettings,
            checkUpdates: () => _ = CheckForUpdatesAsync(interactive: true),
            quit: () => Shutdown());

        _ = CheckForUpdatesAsync(interactive: false);
    }

    internal async Task CheckForUpdatesAsync(bool interactive)
    {
        var result = await UpdateService.CheckAsync();
        await Dispatcher.InvokeAsync(() => ShowUpdateResult(result, interactive));
    }

    private void ShowUpdateResult(UpdateCheckResult result, bool interactive)
    {
        if (result.Failed)
        {
            if (interactive)
            {
                MessageBox.Show(
                    "暂时连不上 GitHub，请稍后再试。\n" + result.Error,
                    "检查更新",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            return;
        }

        if (!result.HasUpdate)
        {
            if (interactive)
            {
                MessageBox.Show(
                    $"当前已是最新版本 {UpdateService.CurrentVersion}。",
                    "检查更新",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            return;
        }

        if (!interactive)
        {
            _tray?.NotifyUpdate(result.LatestVersion, result.OpenUrl);
            return;
        }

        var answer = MessageBox.Show(
            $"发现新版本 {result.LatestVersion}（当前 {UpdateService.CurrentVersion}）。\n\n打开下载页？",
            "检查更新",
            MessageBoxButton.YesNo,
            MessageBoxImage.Information);
        if (answer == MessageBoxResult.Yes)
            UpdateService.OpenUrl(result.OpenUrl);
    }

    private void AddAppViaPicker()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog
        {
            Title = "选择应用（可多选 .exe / .lnk）",
            Filter = "应用程序|*.exe;*.lnk",
            Multiselect = true,
            CheckFileExists = true,
        };
        if (dlg.ShowDialog() == true)
        {
            foreach (var f in dlg.FileNames) Store.Add(f);
        }
    }

    private void OpenSettings()
    {
        _settingsWindow ??= new SettingsWindow(
            Settings,
            Store,
            showTriggerPreview: () => Controller.Gooey.ShowTriggerZonePreview(),
            setPreviewPinned: pinned => Controller.SetPreviewPinned(pinned),
            setTriggerPreview: visible => Controller.Gooey.SetTriggerZonePreviewVisible(visible),
            checkUpdates: () => _ = CheckForUpdatesAsync(interactive: true));
        _settingsWindow.Show();
        _settingsWindow.Activate();
        _settingsWindow.RefreshData();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SettingsManager.Save(Settings);
        if (_settingsWindow != null)
        {
            _settingsWindow.AllowClose = true;
            _settingsWindow.Close();
        }
        Controller.Dispose();
        _tray?.Dispose();
        base.OnExit(e);
    }
}