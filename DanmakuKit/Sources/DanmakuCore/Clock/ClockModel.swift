import Foundation

/// A linear mapping from host time to media time: `media = mediaTime + (host − hostTime) · rate`.
public struct Anchor: Sendable, Equatable {
    public var hostTime: Double
    public var mediaTime: Double
    /// Media seconds per host second; 0 when paused.
    public var rate: Double

    public init(hostTime: Double, mediaTime: Double, rate: Double) {
        self.hostTime = hostTime
        self.mediaTime = mediaTime
        self.rate = rate
    }

    public func mediaTime(at host: Double) -> Double { mediaTime + (host - hostTime) * rate }
}

/// Follows an external player's samples and decides when to re-anchor the local media clock.
///
/// Small drifts are absorbed by briefly running a few percent faster or slower (slewing), so danmaku never
/// visibly jump; seeks, rate changes and large errors re-anchor immediately.
public struct ClockModel: Sendable {
    public enum Decision: Sendable, Equatable {
        case keep
        /// Continuous change (slew start/end, paused nudge); the picture does not jump.
        case retime(Anchor)
        /// Discontinuous change; visible danmaku must be rebuilt.
        case jump(Anchor)
    }

    public struct Tuning: Sendable {
        public var hardThreshold = 0.25
        public var exactThreshold = 0.03
        public var coarseThreshold = 0.08
        public var maxSlew = 0.05
        public var window = 5
        public init() {}
    }

    public private(set) var anchor: Anchor?
    /// Predicted minus reported position of the latest sample, in seconds (diagnostics).
    public private(set) var lastError: Double = 0
    public var tuning = Tuning()
    private var nominalRate = 0.0
    private var errors: [Double] = []
    private var slewEnd: Double?

    public init() {}

    public var isSlewing: Bool { slewEnd != nil }

    public func mediaTime(at host: Double) -> Double? { anchor?.mediaTime(at: host) }

    /// Forces an anchor (manual source, user seek).
    public mutating func reset(to anchor: Anchor) -> Decision {
        self.anchor = anchor
        nominalRate = anchor.rate
        errors.removeAll()
        slewEnd = nil
        return .jump(anchor)
    }

    public mutating func ingest(_ s: PlaybackState, now: Double) -> Decision {
        let reported = s.position(at: now)
        let rate = s.effectiveRate

        guard let current = anchor, !s.discontinuity, abs(rate - nominalRate) < 1e-4 else {
            return reset(to: Anchor(hostTime: now, mediaTime: reported, rate: rate))
        }

        let error = current.mediaTime(at: now) - reported
        lastError = error
        if abs(error) > tuning.hardThreshold {
            return reset(to: Anchor(hostTime: now, mediaTime: reported, rate: rate))
        }

        if rate == 0 {
            // Paused: re-anchoring is invisible as long as the error is tiny; snap exactly.
            guard abs(error) > 0.001 else { return .keep }
            return reset(to: Anchor(hostTime: now, mediaTime: reported, rate: 0)).asRetime
        }

        if let end = slewEnd {
            if now < end { return .keep }
            return finishSlew(at: now)
        }

        errors.append(error)
        if errors.count > tuning.window { errors.removeFirst(errors.count - tuning.window) }
        guard errors.count >= 3 else { return .keep }

        let median = errors.sorted()[errors.count / 2]
        let threshold = s.precision == .exact ? tuning.exactThreshold : tuning.coarseThreshold
        guard abs(median) > threshold else { return .keep }

        // Correct `median` seconds of error at up to `maxSlew` of the nominal rate.
        let correction = min(max(-median, -tuning.maxSlew * rate), tuning.maxSlew * rate)
        let duration = abs(median / correction)
        let slewed = Anchor(hostTime: now, mediaTime: current.mediaTime(at: now), rate: rate + correction)
        anchor = slewed
        slewEnd = now + duration
        errors.removeAll()
        return .retime(slewed)
    }

    /// Called periodically so a slew ends on time even without new samples.
    public mutating func tick(now: Double) -> Decision {
        guard let end = slewEnd, now >= end else { return .keep }
        return finishSlew(at: end)
    }

    private mutating func finishSlew(at host: Double) -> Decision {
        guard let current = anchor else { return .keep }
        slewEnd = nil
        let back = Anchor(hostTime: host, mediaTime: current.mediaTime(at: host), rate: nominalRate)
        anchor = back
        return .retime(back)
    }
}

extension ClockModel.Decision {
    fileprivate var asRetime: ClockModel.Decision {
        if case .jump(let a) = self { return .retime(a) }
        return self
    }
}
