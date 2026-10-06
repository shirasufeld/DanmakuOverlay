import DanmakuCore
import Foundation

/// VLC over Apple Events. VLC only reports whole seconds, so sub-second phase is recovered with
/// `TickPhaseEstimator` from the moments the reported second changes.
actor VLCSource: PlaybackSource {
    nonisolated let kind = SourceKind.vlc
    nonisolated let capabilities: SourceCapabilities = [.canSeek, .canPlayPause, .providesMediaPath]
    nonisolated let events: AsyncStream<SourceEvent>
    private let continuation: AsyncStream<SourceEvent>.Continuation

    private var helper: ScriptHelper?
    private var reader: Task<Void, Never>?
    private var estimator: TickPhaseEstimator
    private var lastSeconds: Int?
    private var lastPlaying: Bool?
    private var lastPath: String?

    init(roundsSeconds: Bool) {
        estimator = TickPhaseEstimator(rate: 1, rounds: roundsSeconds)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
    }

    func start() {
        do {
            let helper = try ScriptHelper(script: "vlc")
            self.helper = helper
            continuation.yield(.status(.connecting))
            reader = Task { [weak self] in
                for await line in helper.lines {
                    guard let self else { return }
                    await self.handle(line: line)
                }
                await self?.helperEnded(helper)
            }
        } catch {
            continuation.yield(.status(.unavailable(error.localizedDescription)))
        }
    }

    func stop() {
        reader?.cancel()
        helper?.terminate()
        helper = nil
        continuation.finish()
    }

    func send(_ command: PlaybackCommand) async throws {
        let script: String
        switch command {
        case .play, .pause, .togglePlayPause:
            // VLC's "play" toggles; only send it when the state must change.
            if command == .play, lastPlaying == true { return }
            if command == .pause, lastPlaying == false { return }
            script = "Application('VLC').play()"
        case .seek(let t): script = "Application('VLC').currentTime = \(Int(t.rounded()))"
        case .step(let d):
            script = "const v = Application('VLC'); v.currentTime = v.currentTime() + \(Int(d.rounded()))"
        case .setRate: throw PlaybackCommandError.unsupported
        }
        try await ScriptHelper.runOnce(script)
    }

    private func helperEnded(_ helper: ScriptHelper) {
        guard self.helper != nil else { return }
        continuation.yield(.status(Self.status(forError: helper.errorOutput())))
    }

    static func status(forError text: String) -> SourceStatus {
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not allowed") {
            return .needsPermission(.automation(bundleID: PlayerCatalog.vlc))
        }
        return .unavailable(text.isEmpty ? String(localized: "VLC helper stopped") : text)
    }

    private struct Line: Decodable {
        var running: Bool?
        var seconds: Int?
        var playing: Bool?
        var duration: Double?
        var path: String?
        var name: String?
        var at: Double?
        var rtt: Double?
        var error: String?
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8), let l = try? JSONDecoder().decode(Line.self, from: data) else {
            return
        }
        if let error = l.error {
            continuation.yield(.status(Self.status(forError: error)))
            return
        }
        guard l.running == true, let seconds = l.seconds, let at = l.at else {
            continuation.yield(.status(.needsSetup(String(localized: "VLC is not running"))))
            return
        }
        let playing = l.playing ?? false
        let host = ScriptHelper.hostTime(fromWall: at)
        var discontinuity = false
        if l.path != lastPath {
            discontinuity = true
            lastPath = l.path
        }
        if playing != lastPlaying || discontinuity {
            estimator.reset()
            lastPlaying = playing
        } else if let last = lastSeconds, seconds < last || seconds > last + 2 {
            estimator.reset()
            discontinuity = true
        }
        lastSeconds = seconds

        let position: Double
        let precision: SamplePrecision
        if playing {
            position = estimator.add(hostTime: host, seconds: seconds, uncertainty: (l.rtt ?? 0) / 2)
            precision = .coarse
        } else {
            position = Double(seconds)
            precision = .coarse
        }
        continuation.yield(
            .status(
                .connected(detail: estimator.isLocked || !playing ? "VLC" : String(localized: "VLC (calibrating…)"))))
        continuation.yield(
            .state(
                PlaybackState(
                    position: position, rate: 1, isPlaying: playing, hostTime: host, duration: l.duration,
                    media: MediaIdentity(path: l.path, title: l.name), discontinuity: discontinuity,
                    precision: precision)))
    }
}
