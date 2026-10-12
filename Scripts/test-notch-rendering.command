#!/bin/zsh
# 刘海渲染的确定性检查：只依赖 macOS Command Line Tools（swiftc），不需要 XCTest。
# 覆盖：紧凑带贴合刘海、原生刘海弧度、顶部裁切、无刘海隐藏、主屏固定、
#       3 根波纹的播放/暂停/停止与真实电平驱动、快速切换不重复建层、黑色主体回归。
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT_DIR/Sources/DynamicIsland"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FAILURES=0

pass() { print "  ✓ $1" }
fail() { print "  ✗ $1"; FAILURES=$((FAILURES + 1)) }

check_absent() {
  local label="$1" file="$2" pattern="$3"
  if grep -q -E "$pattern" "$file" 2>/dev/null; then
    fail "$label —— $file 命中禁止模式：$pattern"
  else
    pass "$label"
  fi
}

check_present() {
  local label="$1" file="$2" pattern="$3"
  if grep -q -E "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label —— $file 未找到：$pattern"
  fi
}

print "== 几何与波纹状态检查 =="
cat > "$WORK_DIR/main.swift" <<'SWIFT'
import AppKit
import QuartzCore

var failures = 0
func expect(_ label: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("  ✓ \(label)")
    } else {
        print("  ✗ \(label)\(detail.isEmpty ? "" : " —— \(detail)")")
        failures += 1
    }
}

func pulsingCount(_ layer: CALayer) -> Int {
    (layer.sublayers ?? []).filter { $0.animationKeys()?.contains(WaveformLayer.animationKey) == true }.count
}

func fakeNotch(width: CGFloat, height: CGFloat, screen: CGSize, centerX: CGFloat? = nil) -> NotchArea {
    let frame = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
    let x = (centerX ?? frame.midX) - width / 2
    let notchFrame = CGRect(x: x, y: frame.maxY - height, width: width, height: height)
    return NotchArea(
        frame: notchFrame,
        anchor: CGPoint(x: notchFrame.midX, y: notchFrame.maxY),
        screenWidth: frame.width,
        screenFrame: frame,
        topInset: height
    )
}

// 本机实测：主屏 1800x1169，刘海 221x38。
let screen = CGSize(width: 1800, height: 1169)
let realNotch = fakeNotch(width: 221, height: 38, screen: screen)
if let band = NotchDetector.compactBand(notch: realNotch, baseWidth: 140, limitWidth: 1053) {
    expect("紧凑带宽度等于刘海宽度（内容收进刘海内，不横向外扩）", abs(band.frame.width - 221) < 0.001, "得到 \(band.frame.width)")
    expect("紧凑带不小于内容宽度", band.frame.width >= 66, "得到 \(band.frame.width)")
    expect("紧凑带高度 = 刘海高度", abs(band.frame.height - 38) < 0.001, "得到 \(band.frame.height)")
    expect("紧凑带顶边贴屏幕顶端，不向屏幕外溢出", abs(band.frame.maxY - screen.height) < 0.001, "maxY=\(band.frame.maxY)")
    expect("紧凑带底边落在刘海底部 compactY", abs(band.frame.minY - 1131) < 0.001, "minY=\(band.frame.minY)")
    expect("紧凑带横向居中于刘海锚点", abs(band.frame.midX - realNotch.anchor.x) < 0.001)
    expect("底部圆角按原生刘海比例推导（约高度 0.28）", abs(band.bottomRadius - 38 * 0.28) < 0.001, "得到 \(band.bottomRadius)")
    expect("圆角小于高度一半，不会把紧凑带啃成两个半圆", band.bottomRadius < band.frame.height / 2)
    expect("紧凑带完整位于主屏内", realNotch.screenFrame.contains(band.frame))

    let manual = NotchDetector.compactBand(
        notch: realNotch,
        baseWidth: 140,
        limitWidth: 1053,
        widthOverride: 280,
        heightOverride: 34,
        topRadiusOverride: 6,
        bottomRadiusOverride: 10,
        verticalOffset: 2
    )
    expect("手动尺寸覆盖宽高", manual?.frame.width == 280 && manual?.frame.height == 34)
    expect("手动圆角覆盖顶部和底部", manual?.topRadius == 6 && manual?.bottomRadius == 10)
    expect("手动垂直偏移生效", manual?.frame.minY == 1137)
} else {
    expect("有刘海时返回紧凑带", false, "意外返回 nil")
}

let wideBase = NotchDetector.compactBand(notch: realNotch, baseWidth: 400, limitWidth: 1053)
expect("基础宽度大于刘海+两侧加宽时保留基础宽度", wideBase?.frame.width == 400, "得到 \(String(describing: wideBase?.frame.width))")
let clamped = NotchDetector.compactBand(notch: realNotch, baseWidth: 140, limitWidth: 200)
expect("紧凑带宽度不超过 limitWidth", clamped?.frame.width == 200, "得到 \(String(describing: clamped?.frame.width))")
let narrow = NotchDetector.compactBand(notch: realNotch, baseWidth: 140, limitWidth: 1053, sideExtension: 8)
expect("加宽量可由调用方收窄", narrow?.frame.width == 237, "得到 \(String(describing: narrow?.frame.width))")
if let small = NotchDetector.compactBand(notch: fakeNotch(width: 150, height: 20, screen: CGSize(width: 1200, height: 800)), baseWidth: 140, limitWidth: 1053) {
    expect("小刘海底部半径不超出自身尺寸", small.bottomRadius <= small.frame.height / 2)
} else {
    expect("小刘海底部半径不超出自身尺寸", false, "意外返回 nil")
}

// 无刘海主屏：不展示紧凑内容，调用方回退到基础宽度。
let flatScreen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
let noNotch = NotchArea(
    frame: CGRect(x: 0, y: flatScreen.maxY, width: 220, height: 0),
    anchor: CGPoint(x: 900, y: flatScreen.maxY),
    screenWidth: flatScreen.width,
    screenFrame: flatScreen,
    topInset: 0
)
expect("无刘海主屏返回 nil（隐藏紧凑内容层）",
       NotchDetector.compactBand(notch: noNotch, baseWidth: 140, limitWidth: 1053) == nil)

// 锚点贴近屏幕左边缘时收进屏幕，不出屏。
let edgeNotch = fakeNotch(width: 221, height: 38, screen: CGSize(width: 1460, height: 900), centerX: 120)
if let edgeBand = NotchDetector.compactBand(notch: edgeNotch, baseWidth: 140, limitWidth: 1053) {
    expect("紧凑带左边缘不出屏", edgeBand.frame.minX >= 0, "minX=\(edgeBand.frame.minX)")
    expect("紧凑带右边缘不出屏", edgeBand.frame.maxX <= 1460, "maxX=\(edgeBand.frame.maxX)")
} else {
    expect("偏心刘海仍返回紧凑带", false, "意外返回 nil")
}

// 波纹：3 根固定槽位 + 播放/暂停/停止 + 真实电平。
let waveform = WaveformLayer()
expect("波纹槽位固定为 3 根", waveform.barCount == 3 && waveform.sublayers?.count == 3, "得到 \(waveform.barCount)")
waveform.frame = CGRect(x: 0, y: 0, width: 100, height: 38)
waveform.relayout()
let slotHeights = (waveform.sublayers ?? []).map { $0.frame.height }
expect("波纹槽位高度不超过上限", slotHeights.allSatisfy { $0 > 0 && $0 <= waveform.maximumBarHeight })
expect("波纹收在内容槽位内不越界", (waveform.sublayers ?? []).allSatisfy { $0.frame.maxX <= waveform.bounds.maxX + 0.001 })

waveform.apply(mode: .playing, animate: true)
expect("伪节奏回退时 3 根波纹都在脉动", pulsingCount(waveform) == 3, "得到 \(pulsingCount(waveform))")
expect("播放时波纹层可见", waveform.mode == .playing && !waveform.isHidden)

waveform.apply(mode: .frozen, animate: true)
let scales = (waveform.sublayers ?? []).map { $0.transform.m22 }
expect("暂停时动画全部撤掉", pulsingCount(waveform) == 0, "得到 \(pulsingCount(waveform))")
expect("暂停时停在低幅静态值", scales.allSatisfy { abs($0 - 0.34) < 0.001 }, "得到 \(scales)")

// 真实电平驱动：只写 transform，不挂 CA 动画。
waveform.apply(mode: .playing, animate: false)
waveform.setLevels([0.9, 0.2, 1.6])
let levelScales = (waveform.sublayers ?? []).map { $0.transform.m22 }
expect("真实电平直接决定每根高度", abs(levelScales[0] - 0.9) < 0.001 && abs(levelScales[2] - 1.0) < 0.001, "得到 \(levelScales)")
expect("电平不会让波纹塌成小点", levelScales.allSatisfy { $0 >= 0.3 }, "得到 \(levelScales)")
expect("电平驱动不挂 CA 动画", pulsingCount(waveform) == 0, "得到 \(pulsingCount(waveform))")

waveform.apply(mode: .hidden, animate: true)
expect("停止/无曲目时隐藏且无残留动画", waveform.mode == .hidden && waveform.isHidden && pulsingCount(waveform) == 0)

// 快速反复切换：不重复建层，也不叠加动画。
for _ in 0..<30 {
    waveform.apply(mode: .playing, animate: true)
    waveform.apply(mode: .frozen, animate: true)
}
expect("快速切换 30 轮后仍只有 3 根波纹", waveform.sublayers?.count == 3, "得到 \(String(describing: waveform.sublayers?.count))")
expect("快速切换不叠加重复动画", pulsingCount(waveform) == 0, "得到 \(pulsingCount(waveform))")
waveform.apply(mode: .playing, animate: true)
expect("反复切换后仍能重新进入播放动画", pulsingCount(waveform) == 3, "得到 \(pulsingCount(waveform))")

// 波纹取色：跟随头像主色，黑白头像回退成白色。
func solidImage(red: UInt8, green: UInt8, blue: UInt8) -> NSImage? {
    let side = 32
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let data = rep.bitmapData else { return nil }
    for index in 0..<(side * side) {
        data[index * 4] = red
        data[index * 4 + 1] = green
        data[index * 4 + 2] = blue
        data[index * 4 + 3] = 255
    }
    let image = NSImage(size: NSSize(width: side, height: side))
    image.addRepresentation(rep)
    return image
}

let redAvatar = solidImage(red: 226, green: 61, blue: 68)
let grayAvatar = solidImage(red: 128, green: 128, blue: 128)
if let redAvatar, let redTint = ArtworkTint.color(from: redAvatar), let rgb = redTint.usingColorSpace(.sRGB) {
    let brightest = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    expect("彩色头像能取出主色且亮度足够压在黑底上", brightest >= 0.7, "得到 \(rgb)")
    let tinted = WaveformLayer()
    tinted.frame = CGRect(x: 0, y: 0, width: 100, height: 38)
    tinted.relayout()
    let beforeSlots = (tinted.sublayers ?? []).map { $0.frame }
    tinted.apply(mode: .playing, animate: true)
    tinted.setTint(redTint)
    expect("波纹颜色跟随头像主色", (tinted.sublayers ?? []).allSatisfy { $0.backgroundColor == redTint.cgColor })
    expect("换色不重建波纹槽位", (tinted.sublayers ?? []).map { $0.frame } == beforeSlots)
    expect("换色不打断播放动画", pulsingCount(tinted) == 3, "得到 \(pulsingCount(tinted))")
    tinted.setTint(nil)
    expect("无彩色头像时波纹回退白色", (tinted.sublayers ?? []).allSatisfy { $0.backgroundColor == NSColor.white.cgColor })
} else {
    expect("彩色头像能取出主色且亮度足够压在黑底上", false, "返回 nil")
}
if let grayAvatar {
    expect("黑白头像不产生彩色波纹（回退白色）", ArtworkTint.color(from: grayAvatar) == nil)
} else {
    expect("黑白头像不产生彩色波纹（回退白色）", false, "测试图像构造失败")
}

exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O \
  "$SRC/Utilities/NotchDetector.swift" \
  "$SRC/Utilities/ArtworkTint.swift" \
  "$SRC/Views/WaveformLayer.swift" \
  "$WORK_DIR/main.swift" \
  -o "$WORK_DIR/notch-rendering-check" 2> "$WORK_DIR/compile.log"; then
  fail "测试程序编译失败（未断言，环境或语法问题）"
  cat "$WORK_DIR/compile.log"
  print "\n失败 $FAILURES 项。"
  exit 1
fi

if "$WORK_DIR/notch-rendering-check"; then
  pass "几何与波纹状态断言汇总通过"
else
  fail "几何或波纹状态断言失败（见上方明细）"
fi

print "== 黑色主体与来源约束回归 =="
check_absent "紧凑内容层不参与 gooey 模糊/颜色矩阵" "$SRC/Views/CompactMediaView.swift" "CIFilter|CIGaussianBlur|CIColorMatrix"
check_absent "紧凑内容层不使用渐变流体" "$SRC/Views/CompactMediaView.swift" "CAGradientLayer|[gG]radient"
check_absent "波纹层不使用渐变流体或滤镜" "$SRC/Views/WaveformLayer.swift" "CAGradientLayer|CIFilter|[gG]radient"
check_absent "波纹层不申请麦克风" "$SRC/Views/WaveformLayer.swift" "AVCaptureDevice|AVAudioEngine|microphone"
check_absent "紧凑内容层不申请麦克风权限" "$SRC/Views/CompactMediaView.swift" "AVCaptureDevice|AVAudioEngine|microphone"
check_present "音频采集只走系统输出、不用麦克风" "$SRC/Managers/SystemAudioTap.swift" "capturesAudio = true"
check_absent "音频采集不申请麦克风权限" "$SRC/Managers/SystemAudioTap.swift" "AVCaptureDevice|requestMicrophone|kAudioDevicePropertyScope"
check_present "未授权时回退伪节奏动画" "$SRC/Window/IslandWindowController.swift" "SystemAudioTap.isAuthorized"
check_absent "灵动岛窗口不再叠加流光层" "$SRC/Window/IslandWindowController.swift" "CAGradientLayer|flowLight|流光"
check_absent "紧凑内容层不进入 gooeyContainer 滤镜链" "$SRC/Window/IslandWindowController.swift" "gooeyContainer\.addSublayer\((compactBandLayer|compactMediaView)"
check_present "紧凑带宽度由 NotchDetector 统一推导" "$SRC/Window/IslandWindowController.swift" "NotchDetector\.compactBand"
check_present "紧凑带用原生刘海轮廓而不是方角" "$SRC/Window/IslandWindowController.swift" "notchPath\(rect: bounds, topRadius"
check_present "紧凑层窗口忽略鼠标事件" "$SRC/Window/IslandWindowController.swift" "compactWindow\.ignoresMouseEvents = true"
check_present "主屏固定取 NSScreen.screens.first" "$SRC/Utilities/NotchDetector.swift" "screens\.first"
check_absent "刘海测量不按鼠标所在屏幕定位" "$SRC/Utilities/NotchDetector.swift" "mouseLocation"
check_present "紧凑层淡出复用 transitionID 中断保护" "$SRC/Window/IslandWindowController.swift" "transitionID == transition, !self\.compactContentWanted"
check_present "展开顶栏左侧是极简音乐摘要" "$SRC/Views/IslandRootView.swift" "struct MusicMiniSummary"
check_present "展开顶栏右侧是极简性能摘要" "$SRC/Views/IslandRootView.swift" "struct MetricsMiniSummary"
check_absent "展开态不再使用摘要卡片" "$SRC/Views/IslandRootView.swift" "ExpandedSummaryRow"
check_absent "展开态底部播放卡片已移除" "$SRC/Views/IslandRootView.swift" "struct MediaPlayerCard"
check_absent "展开态底部性能卡片已移除" "$SRC/Views/IslandRootView.swift" "struct SystemMetricsCard"
check_absent "展开高度不再叠加底部卡片占位" "$SRC/Window/IslandWindowController.swift" "isCardVisible \? 64 \+ 8"
check_absent "展开顶栏不再有设置按钮" "$SRC/Views/IslandRootView.swift" "IslandControlButton"
check_absent "菜单栏弹窗去掉了添加/自定义/更新" "$SRC/Views/MenuBarPopoverView.swift" "onAddApps|onCustomize|onCheckUpdates"
check_present "自定义面板入口在设置页" "$SRC/Views/SettingsView.swift" "openCustomizePanel"
check_present "检查更新入口在设置页" "$SRC/Views/SettingsView.swift" "checkForUpdates"
check_present "收纳开关写入设置" "$SRC/Managers/SettingsStore.swift" "menuBarStashEnabled"
check_present "关闭收纳时卸载分隔符" "$SRC/Managers/MenuBarIconManager.swift" "applyStashEnabled"
check_present "关闭收纳时阻止单图标收纳" "$SRC/Managers/MenuBarIconManager.swift" "guard SettingsStore.shared.menuBarStashEnabled"
check_present "设置页显示收纳开关" "$SRC/Views/SettingsView.swift" "菜单栏图标收纳"
check_present "预览收起态驱动真实岛屿" "$SRC/Window/IslandWindowController.swift" "setLivePreviewExpanded"
check_present "预览态变化接到面板" "$SRC/AppEntry.swift" "onPreviewModeChanged"
check_present "停在菜单栏上方的图标不算可见" "$SRC/Managers/MenuBarIconManager.swift" "frame.minY >= screenTop"
check_present "抬到菜单栏外的图标不进可恢复区" "$SRC/Managers/MenuBarIconManager.swift" "minY && abs\\(frame.minY - "
check_present "支持手动隐藏应用" "$SRC/Managers/MenuBarIconManager.swift" "func hideFromList"
check_present "被抬离菜单栏的图标两栏都不显示" "$SRC/Managers/MenuBarIconManager.swift" "isLiftedOffMenuBar"
check_present "封面地址只接受本地文件或 http(s) 链接" "$SRC/Managers/MediaPlayerStore.swift" "case \"http\", \"https\""
check_present "封面下载有体积上限" "$SRC/Managers/MediaPlayerStore.swift" "data.count <= Self.artworkByteLimit"
check_present "封面只在内存缓存，不落盘" "$SRC/Managers/MediaPlayerStore.swift" "diskCapacity: 0"

if [[ $FAILURES -eq 0 ]]; then
  print "\n全部通过。"
  exit 0
fi
print "\n失败 $FAILURES 项。"
exit 1
