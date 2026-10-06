import DanmakuCore
import Foundation
import Observation

/// The single source of truth for "where is the video now". Consumes one `PlaybackSource`, runs the drift
/// policy and publishes anchors to the renderer.
@Observable
final class PlaybackClock {
    private(set) var anchor = Anchor(hostTime: HostClock.now(), mediaTime: 0, rate: 0)
    /// Nominal rate reported by the player (ignores slewing); 0 when paused.
    private(set) var nominalRate = 0.0
    private(set) var reportedRate = 1.0
    private(set) var duration: Double?
    private(set) var media: MediaIdentity?
    private(set) var geometry: VideoGeometry?
    private(set) var status = SourceStatus.idle
    private(set) var sourceKind: SourceKind?
    /// Recent prediction error against the player (milliseconds, median of the last samples).
    private(set) var driftMs = 0.0
    @ObservationIgnored private var recentErrors: [Double] = []
    /// Positive values delay danmaku relative to the video.
    var userOffset = 0.0 {
        didSet { onAnchor?(anchor, userOffset, false) }
    }

    var isPlaying: Bool { nominalRate > 0 }

    @ObservationIgnored private var model = ClockModel()
    @ObservationIgnored private(set) var source: (any PlaybackSource)?
    @ObservationIgnored private var consumer: Task<Void, Never>?

    /// (anchor, userOffset, isJump)
    @ObservationIgnored var onAnchor: ((Anchor, Double, Bool) -> Void)?
    @ObservationIgnored var onMediaChange: ((MediaIdentity?) -> Void)?
    @ObservationIgnored var onGeometryChange: ((VideoGeometry?) -> Void)?
    @ObservationIgnored var onRateChange: ((Double) -> Void)?

    /// Media time now, without the user offset.
    var mediaTime: Double { anchor.mediaTime(at: HostClock.now()) }

    func attach(_ newSource: any PlaybackSource) {
        detach()
        source = newSource
        sourceKind = newSource.kind
        status = .connecting
        model = ClockModel()
        let stream = newSource.events
        consumer = Task { [weak self] in
            await newSource.start()
            for await event in stream {
                guard let self else { break }
                self.handle(event)
            }
        }
    }

    func detach() {
        consumer?.cancel()
        consumer = nil
        if let old = source {
            Task { await old.stop() }
        }
        source = nil
        sourceKind = nil
        status = .idle
    }

    func send(_ command: PlaybackCommand) {
        guard let source else { return }
        Task {
            do {
                try await source.send(command)
            } catch {
                Log.sync.error("Command \(String(describing: command)) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Periodic housekeeping (ends slews on time).
    func tick() {
        apply(model.tick(now: HostClock.now()))
    }

    private func handle(_ event: SourceEvent) {
        switch event {
        case .status(let s):
            if s != status {
                Log.sync.info("\(self.sourceKind?.rawValue ?? "-"): \(String(describing: s), privacy: .private)")
            }
            status = s
        case .state(let s):
            if s.duration != duration { duration = s.duration }
            if s.media != media {
                media = s.media
                onMediaChange?(s.media)
            }
            if s.geometry != geometry {
                geometry = s.geometry
                onGeometryChange?(s.geometry)
            }
            if s.isPlaying, s.rate > 0, abs(s.rate - reportedRate) > 1e-4 {
                reportedRate = s.rate
                onRateChange?(s.rate)
            }
            apply(model.ingest(s, now: HostClock.now()))
            recordDrift(s)
            if case .connecting = status { status = .connected(detail: "") }
        }
    }

    private func recordDrift(_ s: PlaybackState) {
        guard s.isPlaying, !s.discontinuity else { return }
        recentErrors.append(model.lastError * 1000)
        if recentErrors.count > 9 { recentErrors.removeFirst() }
        let median = recentErrors.sorted()[recentErrors.count / 2]
        if abs(median - driftMs) > 0.5 { driftMs = median }
        #if DEBUG
            if recentErrors.count == 9 {
                Log.sync.info(
                    "drift median \(median, format: .fixed(precision: 1)) ms, last \(self.model.lastError * 1000, format: .fixed(precision: 1)) ms, rate \(self.anchor.rate)"
                )
                recentErrors.removeFirst(4)
            }
        #endif
    }

    private func apply(_ decision: ClockModel.Decision) {
        switch decision {
        case .keep:
            return
        case .retime(let a):
            anchor = a
            onAnchor?(a, userOffset, false)
        case .jump(let a):
            anchor = a
            nominalRate = a.rate
            onAnchor?(a, userOffset, true)
        }
    }
}
