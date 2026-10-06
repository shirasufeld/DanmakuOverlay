import DanmakuCore
import Foundation

/// Reads the system-wide Now Playing state (MediaRemote). Works for Infuse and any app that publishes a media
/// session. MediaRemote only answers Apple-signed processes, so the query runs in `/usr/bin/osascript` and
/// streams JSON lines back.
actor NowPlayingSource: PlaybackSource {
    nonisolated let kind = SourceKind.nowPlaying
    nonisolated let capabilities: SourceCapabilities = [.providesRate, .providesMediaPath]
    nonisolated let events: AsyncStream<SourceEvent>
    private let continuation: AsyncStream<SourceEvent>.Continuation

    /// Only accept sessions from this app (the followed player); `nil` accepts any.
    private let expectedBundleID: String?
    private var helper: ScriptHelper?
    private var reader: Task<Void, Never>?
    private var lastElapsed: Double?
    private var lastTimestamp: Double?

    init(expectedBundleID: String?) {
        self.expectedBundleID = expectedBundleID
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
    }

    func start() {
        do {
            let helper = try ScriptHelper(script: "nowplaying")
            self.helper = helper
            continuation.yield(.status(.connecting))
            reader = Task { [weak self] in
                for await line in helper.lines {
                    guard let self else { return }
                    await self.handle(line: line)
                }
                await self?.ended()
            }
        } catch {
            continuation.yield(
                .status(.unavailable("Cannot start the Now Playing helper: \(error.localizedDescription)")))
        }
    }

    func stop() {
        reader?.cancel()
        helper?.terminate()
        helper = nil
        continuation.finish()
    }

    func send(_ command: PlaybackCommand) throws {
        throw PlaybackCommandError.unsupported
    }

    private func ended() {
        guard helper != nil else { return }
        continuation.yield(.status(.unavailable("Now Playing helper exited")))
    }

    private struct Line: Decodable {
        var playing: Bool?
        var bundle: String?
        var pid: Int32?
        var elapsed: Double?
        var rate: Double?
        var duration: Double?
        var title: String?
        var url: String?
        var timestamp: Double?
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8), let l = try? JSONDecoder().decode(Line.self, from: data) else {
            return
        }
        if let expectedBundleID, l.bundle != expectedBundleID {
            let current = l.bundle ?? String(localized: "nothing")
            continuation.yield(
                .status(.needsSetup(String(localized: "Now Playing shows \(current), not the followed player"))))
            return
        }
        guard let elapsed = l.elapsed else {
            continuation.yield(.status(.needsSetup(String(localized: "Nothing is playing"))))
            return
        }
        let rate = l.rate ?? 1
        let playing = (l.playing ?? false) && rate > 0
        // The reporter extrapolates from (elapsed, timestamp); convert its wall-clock stamp to host time.
        let hostTime = l.timestamp.map(ScriptHelper.hostTime(fromWall:)) ?? HostClock.now()
        let discontinuity =
            lastElapsed != nil && l.timestamp != lastTimestamp
            && Self.jumped(
                from: lastElapsed!, at: lastTimestamp, to: elapsed, at: l.timestamp, rate: playing ? rate : 0)
        lastElapsed = elapsed
        lastTimestamp = l.timestamp

        var media = MediaIdentity(title: l.title)
        if let url = l.url.flatMap(URL.init(string:)), url.isFileURL { media.path = url.path }
        continuation.yield(.status(.connected(detail: l.title ?? l.bundle ?? "")))
        continuation.yield(
            .state(
                PlaybackState(
                    position: elapsed, rate: rate > 0 ? rate : 1, isPlaying: playing, hostTime: hostTime,
                    duration: l.duration, media: media, discontinuity: discontinuity, precision: .extrapolated)))
    }

    static func jumped(from a: Double, at ta: Double?, to b: Double, at tb: Double?, rate: Double) -> Bool {
        guard let ta, let tb else { return false }
        return abs((b - a) - (tb - ta) * rate) > 1.0
    }
}
