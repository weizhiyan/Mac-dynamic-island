# Windows 版灵动岛

基于 macOS 版「灵动岛」用 C# / WPF 复刻的快捷启动工具：鼠标滑到屏幕顶部即展开黑色岛体、露出应用图标网格，点击启动应用。目标是与 Mac 版观感 1:1。

> 源码在 Mac 仓库的 `Windows/` 目录。安装包是 GitHub Release 上的 `Windows-Dynamic-Island-*.zip`，不另开仓库。

## 环境要求

- Windows 10 / 11（x64，推荐 100% / 150% 缩放）
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

> 注意：WPF 只能在 Windows 上编译运行（macOS 无法编译本工程）。

## 构建与运行

### 一键脚本（推荐）

| 脚本 | 作用 |
|---|---|
| `启动.bat` | 一键启动：关闭旧实例 → 编译 Release → 启动；编译失败会停住并显示报错 |
| `停止.bat` | 一键停止（灵动岛没有任务栏按钮，也可右键托盘图标退出） |
| `发布-exe.bat` | 一键发布免安装独立 exe |

> - `启动.bat debug` 改用 Debug 配置编译。
> - 未安装 .NET SDK 但已发布过独立版时，`启动.bat` 会直接启动已发布的那份。
> - 启动后灵动岛只在系统托盘显示图标，悬停屏幕顶部中间的胶囊即可展开。

### 手动

```bash
dotnet build
dotnet run
```

发布单文件：

```bash
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## UI 设计规范（重要）

所有界面改动都以 **`Ui/AppleTheme.cs`** 为准，**不要在页面里写死颜色/字号/圆角/间距**。

规范来源：**macOS System Settings**（Ventura+ 侧栏 + inset 分组）与浅色 **NSPopover**。设置窗口按桌面系统设置来，不要再套 apple.com 的网页字号。

1. **系统蓝** `#007AFF` 是唯一强调色；开关开启态用系统绿 `#34C759`。
2. **窗口是分组灰底** `#E8E8ED`，内容是白色 inset 分组；侧栏选中是浅灰块，不是白卡。
3. **正文 13px，页面标题 22px** —— 这是桌面设置，不是商店页。
4. **按钮是 6px 圆角的 AppKit push button**，不是网页胶囊。
5. **投影只给浮层（气泡）**；设置页卡片 / 按钮不加阴影。

| 项目 | 规范（token 名见 `AppleTheme.cs`） |
|---|---|
| 画布 | Window `#E8E8ED` · Sidebar `#E3E3E8` · Card `#FFFFFF` · Control `#F2F2F7` |
| 文字 | Ink `#1D1D1F` · Secondary `#6E6E73` · Tertiary `#8E8E93` |
| 强调色 | System Blue `#007AFF` · Toggle Green `#34C759` · Danger `#FF3B30` |
| 描边 | 分组 1px `rgba(0,0,0,0.10)` · 行分割 `rgba(0,0,0,0.08)` · 按钮/输入框 `rgba(0,0,0,0.16)` |
| 圆角 | `RadiusXs 5` / `RadiusSm 6`（按钮、输入框）/ `RadiusMd 8`（侧栏选中、磁贴）/ `RadiusLg 10`（分组卡片） |
| 字号 | `TitleSize 22`（页面标题）· `BodySize 13`（正文）· `CaptionSize 11`（说明/空状态） |
| 间距 | `SpaceXxs 4 / Xs 8 / Sm 12 / Md 16 / Lg 20 / Xl 24`；页面边距 22、卡片内边距 14、卡片间距 16、标签列宽 132 |
| 控件 | 按钮高 28 / 输入框 22 / 开关 40×24 / 滑杆 3px 轨道 + 16px 白钮 / 分段控件 26 |
| 字体 | `SF Pro Text → SF Pro Display → Segoe UI Variable Text` |
| 投影 | 只用于悬停气泡；设置页与岛体不加 |

**按钮语法**（`MakeButton`）：`Accent` = 系统蓝矩形主按钮 · `Tinted` = 白底蓝字 · `Plain` = 白底黑字细边 · `IconChip` = 灰圆白叉（移除）· `Danger` = 删除文字。尺寸档：`Regular`（28）/ `Compact`（22）/ `Micro`（16）。

**悬停气泡**（`ToolTipPopup`）：浅色 Popover（`#FAFAFA` 底 + 细描边 + 8px 圆角 + 三角箭头 + 轻投影）；**以应用图标为锚点**（水平居中、贴在图标下沿，箭头对准图标，不跟光标）；13px medium 单行，超过 320px 省略；弹出带淡入缩放，点击穿透。

页面组装只用：`GroupedSection` / `Row` / `MakeButton` / `MakeSegmented` / `Field` + `MakeTextBox` / `MakeSwitch` / `MakeSlider` / `Caption` / `ValueBadge` / `AddPageHeader` / `SidebarItem` / `MetricTile` / `EmptyState`。

### 代码约定（改 UI 前必读）

- **隐式 using 不覆盖全部命名空间**：`System`、`System.Collections.Generic` 可用；`System.IO`、`System.Windows.Shapes` 必须显式 `using`。`Path` 与 `System.IO.Path` 同名，岛体形状统一用别名 `ShapePath = System.Windows.Shapes.Path`。
- **纯代码构建 ControlTemplate 时，`FrameworkElementFactory.SetValue` 只能设置依赖属性**。像 `Track` 的 `Thumb` / `DecreaseRepeatButton` / `IncreaseRepeatButton` 是普通 CLR 属性（写 `Track.ThumbProperty` 会报 CS0117），必须在元素（`AppleTheme.SliderTrack`）的构造函数里装配，模板里只放 `x:Name="PART_Track"` 的实例。
- **自定义按钮模板必须把 `Control.Padding` 通过 `TemplateBinding` 透给 `Border.Padding`**，并且胶囊的内边距要 ≥ 高度的一半。WPF 的 `Border` 只按 `BorderThickness + Padding` 给子元素留位（**`CornerRadius` 完全不参与布局**，官方源码确认），漏掉这一行按钮宽度就只有文字宽，文字会压在圆角外面，看起来像"描边穿过文字"。
- **按钮必须显式设置 `BorderBrush` / `BorderThickness`**，否则会漏出 WPF 主题按钮的深灰 1px 描边（哪怕你换了 `Template`，未显式设置的属性仍会从主题样式继承）。
- **同一个元素实例不能反复挂到新的父级**：`Panel.Children.Add` 对已有逻辑父级的元素会抛 `InvalidOperationException`，所以每次重建页面都要新建容器（这类异常会被全局兜底吞掉，表现为"页面只剩标题"）。
- **WPF 的 TextBlock 没有 `letter-spacing`**，规范里的负字距 token（`-0.12 → -0.374px`）只在代码注释中记录，Windows 上靠字体本身体现；如要精确复刻需自绘 `GlyphRun`。
- **固定宽的标签列必须给 `TextTrimming`**：TextBlock 不裁剪，标签比列宽长时会直接压到右侧控件上。
- **控件高度按 AppKit 常规控件**：按钮 28、输入框 22、图标片 16（见 `*Height` 常量）。

## 功能

- 主屏顶部居中出现黑色横条（贴**工作区**顶部：任务栏停靠在顶部时会自动让开，不与任务栏抢位）；鼠标滑到横条附近的触发区（防抖延迟可调）即展开成圆角面板
- **顶栏比面板更宽**（默认比面板宽 20%，可在设置里精确填数字），顶栏与面板交界处是**内凹的融合颈部**——用解析几何复刻了 Mac 版的 gooey 融合观感（Mac 用 CIGaussianBlur + CIColorMatrix 阈值化实现，WPF 无 ColorMatrix，故改为矢量路径），融合半径可调（0 = 直角硬接缝）
- 应用图标网格 + 鼠标悬停磁吸放大 + 气泡提示 + 点击启动（.exe / .lnk）
- 顶部悬浮按钮：⚙️ 设置、＋ 添加应用
- 系统托盘：显示 / 隐藏、设置、检查更新、退出
- 对照 GitHub Release 检查更新（启动时静默提示，设置页可手动检查）
- 设置面板（侧边栏导航）：基础设置、应用过滤、外观布局、触发方式、动画
  - **实时预览（保持展开）**：一边拖滑杆一边看效果
  - **常驻触发区红条**：边调触发区偏移/尺寸边看位置
  - 应用网格：图标大小 / 列数 / 间距 / 顶部内边距
  - 岛屿形状：岛屿宽度（可填数字）/ 静止宽度 / 顶栏高度 / 整体位移 / 顶栏圆角 / 面板圆角 / 融合半径
  - 触发区尺寸与偏移、进入/隐藏延迟
  - 展开/收起时长与贝塞尔时间曲线（格式 `x1, y1, x2, y2`）
- 开机自启（注册表 Run）、JSON 持久化于 `%AppData%\DynamicIsland`
- 诊断日志：`%TEMP%\DynamicIsland.log`（记录窗口尺寸/面板宽度/单元格坐标，排查布局问题用）

## 说明

- 默认快捷应用为 Windows 常用应用（Edge、计算器等），可到设置里增删。
- 与 Mac 版的差异：无刘海，岛体改为挂在屏幕顶部；gooey 模糊融合以黑色合并路径近似还原；不含 macOS 独有的「菜单栏图标收纳」。
- 当前为单屏（主屏、系统 DPI 缩放）支持；多屏 / 混合 DPI 后续可扩展。