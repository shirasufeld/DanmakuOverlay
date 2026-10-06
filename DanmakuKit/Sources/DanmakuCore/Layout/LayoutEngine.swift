import CoreGraphics

/// Precomputes the placement of every danmaku on the timeline for one view size and configuration.
///
/// The result is deterministic: the same inputs always yield the same timeline, so seeking anywhere shows the
/// same picture as playing through.
public struct LayoutEngine: Sendable {
    public let config: LayoutConfig
    public let measurer: any TextMeasurer

    public init(config: LayoutConfig, measurer: any TextMeasurer) {
        self.config = config
        self.measurer = measurer
    }

    /// Lays out `items` (must be sorted by time). Throws `CancellationError` when the task is cancelled.
    @concurrent
    public func layout(_ items: [Danmaku]) async throws -> PlacedTimeline {
        try layoutSync(items)
    }

    public func layoutSync(_ items: [Danmaku]) throws -> PlacedTimeline {
        let c = config
        let width = c.viewSize.width
        var roll = RollRoom(height: c.areaHeight, durationMs: c.rollDurationMs)
        var inverse = RollRoom(height: c.areaHeight, durationMs: c.rollDurationMs)
        var statics = StaticRoom(height: c.areaHeight)
        var limiters: [DanmakuKind: LiveCounter] = [:]
        for kind in [DanmakuKind.roll, .top, .bottom, .inverse] {
            if let limit = c.limits[kind] { limiters[kind] = LiveCounter(limit: limit) }
        }
        var sizeCache: [SizeKey: CGSize] = [:]

        var placed: [PlacedDanmaku] = []
        placed.reserveCapacity(items.count)
        var dropped = 0

        for (index, d) in items.enumerated() {
            if index & 0xFFF == 0 { try Task.checkCancellation() }

            let kind = d.kind
            let fontSize = c.fontSize(for: d)

            if kind == .advanced {
                guard let adv = d.advanced else {
                    dropped += 1
                    continue
                }
                let size = measured(adv.text, fontSize, &sizeCache)
                placed.append(
                    PlacedDanmaku(
                        startMs: d.timeMs, endMs: d.timeMs + max(adv.durationMs, 1), kind: .advanced, y: 0,
                        width: size.width, height: size.height, fontSize: fontSize, sourceIndex: index))
                continue
            }
            guard kind != .unsupported else {
                dropped += 1
                continue
            }

            let duration = (kind == .top || kind == .bottom) ? c.staticDurationMs : c.rollDurationMs
            if limiters[kind]?.isFull(at: d.timeMs) == true {
                dropped += 1
                continue
            }

            let size = measured(d.text, fontSize, &sizeCache)
            let slotHeight = size.height + c.lineSpacing
            let y: CGFloat?
            switch kind {
            case .roll:
                y = roll.placeTopDown(
                    timeMs: d.timeMs, width: size.width, height: slotHeight, viewWidth: width,
                    durationMs: duration, allowOverlap: c.allowOverlap)
            case .inverse:
                y = inverse.placeTopDown(
                    timeMs: d.timeMs, width: size.width, height: slotHeight, viewWidth: width,
                    durationMs: duration, allowOverlap: c.allowOverlap)
            case .top:
                y = statics.placeTopDown(
                    timeMs: d.timeMs, height: slotHeight, until: d.timeMs + duration, allowOverlap: c.allowOverlap)
            case .bottom:
                y = statics.placeBottomUp(
                    timeMs: d.timeMs, height: slotHeight, until: d.timeMs + duration, allowOverlap: c.allowOverlap
                ).map { $0 + c.lineSpacing }
            case .advanced, .unsupported:
                y = nil
            }
            guard let y else {
                dropped += 1
                continue
            }
            limiters[kind]?.insert(endMs: d.timeMs + duration)
            placed.append(
                PlacedDanmaku(
                    startMs: d.timeMs, endMs: d.timeMs + duration, kind: kind, y: y, width: size.width,
                    height: size.height, fontSize: fontSize, sourceIndex: index))
        }
        return PlacedTimeline(items: placed, config: c, droppedCount: dropped)
    }

    private struct SizeKey: Hashable {
        var text: String
        var fontSize: CGFloat
    }

    private func measured(_ text: String, _ fontSize: CGFloat, _ cache: inout [SizeKey: CGSize]) -> CGSize {
        let key = SizeKey(text: text, fontSize: fontSize)
        if let s = cache[key] { return s }
        let s = measurer.measure(text, fontSize: fontSize)
        cache[key] = s
        return s
    }
}

/// Counts danmaku of one kind still on screen. All danmaku of a kind share one duration and arrive in start
/// order, so their end times are non-decreasing and a queue suffices.
struct LiveCounter {
    let limit: Int
    private var ends: [Int] = []
    private var head = 0

    init(limit: Int) { self.limit = max(limit, 0) }

    mutating func isFull(at ms: Int) -> Bool {
        while head < ends.count, ends[head] < ms { head += 1 }
        if head > 4096 {
            ends.removeFirst(head)
            head = 0
        }
        return ends.count - head >= limit
    }

    mutating func insert(endMs: Int) { ends.append(endMs) }
}
