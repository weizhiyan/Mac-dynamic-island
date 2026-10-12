import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// 用 ScreenCaptureKit 抓系统输出音频，算出低/中/高三档电平，驱动收起态的 3 根波纹。
/// 需要「屏幕与系统录音」权限；未授权或采集失败时调用方回退到伪节奏动画。
final class SystemAudioTap: NSObject, @unchecked Sendable {
    static let shared = SystemAudioTap()

    /// 电平回调，主线程，约 30Hz，顺序为低/中/高，取值 0.3...1。
    var onLevels: (([CGFloat]) -> Void)?
    /// 采集失败或被系统停止时回调一次；本进程内不再重试。
    var onUnavailable: (() -> Void)?

    private(set) var isCapturing = false
    private var stream: SCStream?
    private var generation = 0
    private var didReportUnavailable = false

    private let queue = DispatchQueue(label: "dynamic-island.audio.tap", qos: .userInitiated)
    private var peak = [CGFloat](repeating: 0.05, count: 3)
    private var smoothed = [CGFloat](repeating: 0.3, count: 3)
    private var lastEmit: TimeInterval = 0

    private override init() { super.init() }

    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// 首次调用会触发系统授权框。
    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    /// 只能在主线程调用。
    func start() {
        guard stream == nil, !didReportUnavailable else { return }
        generation += 1
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.frame.origin == .zero }) ?? content.displays.first else {
                    await MainActor.run { self.reportUnavailable() }
                    return
                }
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.sampleRate = 48_000
                configuration.channelCount = 2
                configuration.queueDepth = 8
                // 只订阅音频输出，视频尺寸给到最小即可。
                configuration.width = 4
                configuration.height = 4
                let stream = SCStream(
                    filter: SCContentFilter(display: display, excludingWindows: []),
                    configuration: configuration,
                    delegate: AudioTapDelegate.shared
                )
                AudioTapDelegate.shared.owner = self
                try stream.addStreamOutput(AudioTapDelegate.shared, type: .audio, sampleHandlerQueue: self.queue)
                try await stream.startCapture()
                await MainActor.run {
                    guard token == self.generation, !self.didReportUnavailable else {
                        Task { try? await stream.stopCapture() }
                        return
                    }
                    self.stream = stream
                    self.isCapturing = true
                }
            } catch {
                await MainActor.run { self.reportUnavailable() }
            }
        }
    }

    /// 只能在主线程调用。
    func stop() {
        generation += 1
        guard let stream else { return }
        self.stream = nil
        isCapturing = false
        Task { try? await stream.stopCapture() }
    }

    @MainActor
    private func reportUnavailable() {
        guard !didReportUnavailable else { return }
        didReportUnavailable = true
        isCapturing = false
        stream = nil
        onUnavailable?()
    }

    fileprivate func handleLevelFailure() {
        Task { @MainActor in self.reportUnavailable() }
    }

    fileprivate func handle(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let bands = Self.bandEnergies(from: sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEmit >= 1.0 / 30.0 else { return }
        lastEmit = now

        // 自动增益：用缓慢衰减的峰值归一，避免要手调音量增益。
        for index in 0..<3 {
            let raw = CGFloat(min(max(bands[index], 0), 1))
            peak[index] = max(raw, peak[index] * 0.9995)
            let target = min(max(raw / max(peak[index], 0.01), 0.3), 1)
            let current = smoothed[index]
            smoothed[index] = target > current
                ? current + (target - current) * 0.55
                : current + (target - current) * 0.16
        }
        let snapshot = smoothed
        DispatchQueue.main.async { [weak self] in self?.onLevels?(snapshot) }
    }

    /// 三档频带的近似能量：低通后的 RMS 当低频、原始 RMS 当中频、相邻样本差的 RMS 当高频。
    private static func bandEnergies(from sampleBuffer: CMSampleBuffer) -> [Double]? {
        var needed = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        )
        guard sizeStatus == noErr, needed > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { raw.deallocate() }
        let listPointer = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let copyStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: listPointer, bufferListSize: needed,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer
        )
        guard copyStatus == noErr else { return nil }

        let bufferCount = Int(listPointer.pointee.mNumberBuffers)
        guard bufferCount > 0 else { return nil }

        var low = 0.0, mid = 0.0, high = 0.0, samples = 0
        var lowPass = 0.0, previous = 0.0
        let buffers = UnsafeMutableBufferPointer<AudioBuffer>(start: &listPointer.pointee.mBuffers, count: bufferCount)
        for buffer in buffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            data.withMemoryRebound(to: Float32.self, capacity: frameCount) { values in
                for index in 0..<frameCount {
                    let sample = Double(values[index])
                    guard sample.isFinite else { continue }
                    lowPass += 0.015 * (sample - lowPass)
                    let delta = sample - previous
                    previous = sample
                    low += lowPass * lowPass
                    mid += sample * sample
                    high += delta * delta
                    samples += 1
                }
            }
        }
        guard samples > 0 else { return nil }
        return [sqrt(low / Double(samples)), sqrt(mid / Double(samples)), sqrt(high / Double(samples))]
    }
}

/// SCStream 的输出/代理回调需要一个长期存在的 Objective-C 对象，用它转发回宿主。
private final class AudioTapDelegate: NSObject, SCStreamOutput, SCStreamDelegate {
    static let shared = AudioTapDelegate()
    weak var owner: SystemAudioTap?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        owner?.handle(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        owner?.handleLevelFailure()
    }
}
