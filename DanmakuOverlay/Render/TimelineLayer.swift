import DanmakuCore
import QuartzCore

/// Container layer whose local time is the danmaku timeline: `local = K + mediaTime − userOffset` (seconds).
///
/// Core Animation computes `local = (parentTime − beginTime) · speed + timeOffset`; the parent here runs on host
/// time, so mapping an `Anchor` is a matter of setting those three properties together. Every danmaku animation
/// is then scheduled at `K + start` in this local time and the render server moves it — pausing, rate changes
/// and drift correction never touch individual danmaku.
nonisolated final class TimelineLayer: CALayer {
    /// Keeps every animation `beginTime` strictly positive: CA treats 0 as "now".
    static let epoch: CFTimeInterval = 100_000

    private(set) var anchor = Anchor(hostTime: 0, mediaTime: 0, rate: 0)
    private(set) var userOffset: Double = 0

    override init() {
        super.init()
        masksToBounds = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Maps local time to the given anchor. Safe to call at any rate; positions do not jump unless the anchor does.
    func apply(anchor: Anchor, userOffset: Double) {
        self.anchor = anchor
        self.userOffset = userOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let parentNow = superlayer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
        let skew = parentNow - CACurrentMediaTime()
        speed = Float(anchor.rate)
        beginTime = anchor.hostTime + skew
        timeOffset = Self.epoch + anchor.mediaTime - userOffset
        CATransaction.commit()
    }

    /// Danmaku time (seconds, offset applied) at host time `host`.
    func danmakuTime(at host: CFTimeInterval = CACurrentMediaTime()) -> Double {
        anchor.mediaTime(at: host) - userOffset
    }

    /// Local layer time corresponding to danmaku time `seconds`.
    static func localTime(forDanmakuSeconds seconds: Double) -> CFTimeInterval { epoch + seconds }
}
