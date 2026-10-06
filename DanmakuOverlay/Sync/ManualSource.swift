import DanmakuCore
import Foundation

/// An internal clock driven by the HUD, hotkeys and (optionally) mirrored player keys.
actor ManualSource: PlaybackSource {
    nonisolated let kind = SourceKind.manual
    nonisolated let capabilities: SourceCapabilities = [.canSeek, .canPlayPause, .providesRate]
    nonisolated let events: AsyncStream<SourceEvent>
    private let continuation: AsyncStream<SourceEvent>.Continuation

    private var position: Double
    private var hostTime: Double
    private var rate: Double
    private var playing: Bool
    private var duration: Double?

    init(position: Double = 0, rate: Double = 1, playing: Bool = false, duration: Double? = nil) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
        self.position = position
        self.hostTime = HostClock.now()
        self.rate = rate
        self.playing = playing
        self.duration = duration
    }

    func start() {
        continuation.yield(.status(.connected(detail: "Manual clock")))
        publish(discontinuity: true)
    }

    func stop() {
        continuation.finish()
    }

    func setDuration(_ duration: Double?) {
        self.duration = duration
        publish(discontinuity: false)
    }

    func send(_ command: PlaybackCommand) {
        let now = HostClock.now()
        position = currentPosition(at: now)
        hostTime = now
        var discontinuity = false
        switch command {
        case .play: playing = true
        case .pause: playing = false
        case .togglePlayPause: playing.toggle()
        case .seek(let to):
            position = clamp(to)
            discontinuity = true
        case .step(let by):
            position = clamp(position + by)
            discontinuity = true
        case .setRate(let r): rate = min(max(r, 0.1), 16)
        }
        publish(discontinuity: discontinuity)
    }

    private func clamp(_ p: Double) -> Double {
        let upper = duration ?? .greatestFiniteMagnitude
        return min(max(p, 0), upper)
    }

    private func currentPosition(at t: Double) -> Double {
        clamp(position + (playing ? (t - hostTime) * rate : 0))
    }

    private func publish(discontinuity: Bool) {
        continuation.yield(
            .state(
                PlaybackState(
                    position: position, rate: rate, isPlaying: playing, hostTime: hostTime, duration: duration,
                    discontinuity: discontinuity)))
    }
}
