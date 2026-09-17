# 灵动岛

灵动岛是一个轻量级 macOS 刘海快捷启动工具。它会在屏幕顶部刘海区域展开黑色的动态卡片，让常用应用可以从顶部快速打开。

<img width="829" height="257" alt="202607188223739" src="https://github.com/user-attachments/assets/6ebf3349-53f7-4e46-86f5-e0df9e975cbc" />


## 功能

- 黑色灵动岛界面，与 MacBook 刘海自然融合
- 鼠标滑到顶部触发快捷入口，避免占用桌面空间
- 自定义快捷应用，支持添加、删除和拖拽排序
- 可调整图标大小、展示数量、间距、触发区域和动画速度
- 支持应用内检查更新，后续版本可直接从软件里更新
- 支持显示触发区域预览，方便校准顶部悬停范围
- 设置里可开启开机自启动
- 启动后隐藏 Dock 图标，只保留菜单栏入口

## 安装

在 [Releases](https://github.com/weizhiyan/Mac-dynamic-island/releases) 下载最新版本：

- `Mac-Dynamic-Island-1.0.2.pkg`：Apple Silicon
- `Mac-Dynamic-Island-1.0.2-intel.pkg`：Intel
- `Windows-Dynamic-Island-1.0.2.zip`：Windows 10 / 11（解压后运行 `DynamicIsland.exe`）

Mac 也可以双击 `安装灵动岛.command` 覆盖安装到 `/Applications/灵动岛.app`，或把 `灵动岛.app` 拖进 Applications。安装脚本会清理旧版 `DynamicIsland.app` 和重复的 `灵动岛.app`。

已安装 1.0.1 的 Mac 用户可在菜单栏或设置里点「检查更新」。Windows 用户同样可在托盘或设置里检查更新。

## 从源码运行

```bash
swift build
./LaunchDynamicIsland.command
```

需要 macOS 14 或更高版本。

## 项目结构

- `Sources/DynamicIsland`：Mac 应用源码
- `Sources/DynamicIsland/Resources`：应用图标、状态栏图标和资源
- `Windows`：Windows 版（C# / WPF），不另开仓库
- `Scripts/build-dmg.command`：构建可安装 DMG
- `Scripts/build-pkg.command`：构建 macOS `.pkg` 安装包
- `Scripts/install-local.command`：本地覆盖安装脚本
- `Scripts/release.sh`：生成安装包、更新 `appcast.xml`，并通过 git 推送到 GitHub
- `Scripts/generate-appcast.command`：生成 Sparkle 更新源，需要本机 Keychain 里有对应私钥，或设置 `SPARKLE_ED_PRIVATE_KEY`
- `appcast.xml`：Mac Sparkle 更新源
- `Docs/releases`：发布说明
