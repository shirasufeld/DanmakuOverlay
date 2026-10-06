import CoreGraphics

/// A danmaku with its precomputed placement. Coordinates are in view points, top-left origin.
public struct PlacedDanmaku: Sendable, Hashable {
    public var startMs: Int
    public var endMs: Int
    public var kind: DanmakuKind
    /// Top edge (roll / inverse / top / bottom). Unused for advanced danmaku.
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var fontSize: CGFloat
    /// Index into the danmaku array the timeline was built from.
    public var sourceIndex: Int

    public var durationMs: Int { endMs - startMs }
}

/// The laid-out timeline, sorted by start time, with fast time-window queries.
public struct PlacedTimeline: Sendable {
    public let items: [PlacedDanmaku]
    public let maxDurationMs: Int
    public let config: LayoutConfig?
    /// Number of input danmaku that could not be placed (limits / no room without overlap).
    public let droppedCount: Int

    public init(items: [PlacedDanmaku], config: LayoutConfig? = nil, droppedCount: Int = 0) {
        self.items = items
        self.maxDurationMs = items.map(\.durationMs).max() ?? 0
        self.config = config
        self.droppedCount = droppedCount
    }

    public static let empty = PlacedTimeline(items: [])

    /// First index whose start time is >= `ms`.
    public func lowerBound(startMs ms: Int) -> Int {
        var lo = 0
        var hi = items.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if items[mid].startMs < ms { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Indices of danmaku starting within `range` (half-open).
    public func indices(startingIn range: Range<Int>) -> Range<Int> {
        lowerBound(startMs: range.lowerBound)..<lowerBound(startMs: range.upperBound)
    }

    /// Indices of danmaku visible at `ms` (start <= ms < end).
    public func activeIndices(at ms: Int) -> [Int] {
        let from = lowerBound(startMs: ms - maxDurationMs)
        let to = lowerBound(startMs: ms + 1)
        guard from < to else { return [] }
        return (from..<to).filter { items[$0].endMs > ms }
    }
}
