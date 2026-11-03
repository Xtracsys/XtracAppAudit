import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public let timedOut: Bool
}
public enum ProcessRunner {
    // Only fixed Apple tool paths are used by callers; inspected app code is never executed.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 12) -> CommandResult {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "LANG": "C"]) { _, new in new }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return CommandResult(status: -1, output: error.localizedDescription, timedOut: false) }
        // Drain concurrently so a verbose tool cannot fill its pipe and deadlock.
        let collector = OutputCollector()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                collector.append(chunk)
            }
            drained.signal()
        }
        let expired = exited.wait(timeout: .now() + timeout) == .timedOut
        if expired {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL); _ = exited.wait(timeout: .now() + 1) }
        }
        _ = drained.wait(timeout: .now() + 1)
        let text = String(decoding: collector.data, as: UTF8.self)
        return CommandResult(status: process.isRunning ? -1 : process.terminationStatus, output: text, timedOut: expired)
    }
}
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if bytes.count < 2_000_000 { bytes.append(data.prefix(2_000_000 - bytes.count)) }
    }
}
