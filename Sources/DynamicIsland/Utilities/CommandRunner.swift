import Foundation
import Darwin

struct CommandOutput {
    let data: Data
    let error: String
    let succeeded: Bool
}

enum CommandRunner {
    static func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return CommandOutput(data: Data(), error: error.localizedDescription, succeeded: false)
        }
        let output = OutputBuffer(limit: 8 * 1024 * 1024)
        let errors = OutputBuffer(limit: 8 * 1024)
        let readers = DispatchGroup()
        for (pipe, buffer) in [(outputPipe, output), (errorPipe, errors)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 16_384), !chunk.isEmpty {
                    buffer.append(chunk)
                }
            }
        }
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut, process.isRunning {
            process.terminate()
            if finished.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.3)
            }
        }
        _ = readers.wait(timeout: .now() + 0.5)
        let message = timedOut ? "播放器响应超时，请重试" : String(decoding: errors.data, as: UTF8.self)
        return CommandOutput(data: output.data, error: message, succeeded: !timedOut && !process.isRunning && process.terminationStatus == 0)
    }

    private final class OutputBuffer {
        private let lock = NSLock()
        private var storage = Data()
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(chunk.prefix(max(0, limit - storage.count)))
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
