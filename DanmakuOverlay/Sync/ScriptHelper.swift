import DanmakuCore
import Foundation

/// Runs a bundled JavaScript-for-Automation helper in `/usr/bin/osascript` and streams its stdout lines.
///
/// Helpers poll players in their own process, so slow or hung Apple Events never block the app. Apple Events
/// they send are attributed to this app for Automation permission. The helper dies with its pipe when the app
/// quits.
/// `Process` is safe to query and terminate from any thread.
nonisolated final class ScriptHelper: @unchecked Sendable {
    let lines: AsyncStream<String>
    private let process: Process
    private let stderr: Pipe

    /// - Parameters:
    ///   - script: resource name (without extension) of a `.js` file in the app bundle.
    ///   - arguments: passed to the helper's `run(argv)`.
    init(script: String, arguments: [String] = []) throws {
        guard let url = Bundle.main.url(forResource: script, withExtension: "js") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(script).js"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", url.path] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        self.process = process
        self.stderr = stderr
        let handle = stdout.fileHandleForReading
        lines = AsyncStream { continuation in
            let task = Task.detached {
                do {
                    for try await line in handle.bytes.lines { continuation.yield(line) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    var isRunning: Bool { process.isRunning }

    /// Last error text the helper printed (osascript reports script errors on stderr).
    func errorOutput() -> String {
        let data = stderr.fileHandleForReading.availableData
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// Runs a one-shot JXA snippet (used for player commands).
    static func runOnce(_ source: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", source]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let (done, signal) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in signal.finish() }
        try process.run()
        for await _ in done {}
    }

    /// Converts a helper's wall-clock timestamp (seconds since 1970) to `HostClock` time.
    static func hostTime(fromWall wall: Double) -> Double {
        HostClock.now() - (Date().timeIntervalSince1970 - wall)
    }
}
