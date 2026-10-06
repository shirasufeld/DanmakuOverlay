import CoreGraphics

// Port of DanmakuPlayer's track allocation (Models/Danmaku.Position.cs, DanmakuContext.cs).
//
// The vertical space is a list of contiguous intervals. Interval i spans
// [bottom(i-1), bottom(i)] (bottom(-1) = 0) and remembers its latest occupant. A new danmaku looks for
// a run of consecutive intervals tall enough for it whose occupants it will never collide with.

/// Occupant of a scrolling room: the last danmaku that entered the interval.
struct RollOccupant {
    var timeMs: Int
    var width: CGFloat
}

/// Vertical intervals for scrolling danmaku (roll and inverse use separate rooms).
struct RollRoom {
    private(set) var bottoms: [CGFloat]
    private(set) var occupants: [RollOccupant]

    init(height: CGFloat, durationMs: Int) {
        bottoms = [height]
        occupants = [RollOccupant(timeMs: -durationMs, width: 0)]
    }

    /// Smallest horizontal gap between `prev` and a new danmaku over their common lifetime; negative = overlap.
    ///
    /// Both move at (viewWidth + width) / duration. A danmaku no wider than its predecessor is never faster,
    /// so the gap is smallest when it enters; a wider one catches up, so the gap is smallest when `prev` leaves.
    static func distance(
        newTime: Int, newWidth: CGFloat, prev: RollOccupant, viewWidth: CGFloat, durationMs: Int
    ) -> Double {
        let t = newWidth <= prev.width ? newTime : prev.timeMs + durationMs
        let d = Double(durationMs)
        func travelled(_ time: Int, _ width: CGFloat) -> Double {
            Double(t - time) * Double(viewWidth + width) / d
        }
        return travelled(prev.timeMs, prev.width) - travelled(newTime, newWidth) - Double(prev.width)
    }

    /// Places a danmaku from the top down. Returns its top edge, or `nil` if it must be dropped.
    mutating func placeTopDown(
        timeMs: Int, width: CGFloat, height: CGFloat, viewWidth: CGFloat, durationMs: Int, allowOverlap: Bool
    ) -> CGFloat? {
        var mostDistance = allowOverlap ? -Double.infinity : 0
        var lastPos: CGFloat = 0
        var best: (first: Int, last: Int, pos: CGFloat)?
        var overlapped = true

        outer: for i in bottoms.indices {
            var intervalLeast = Double.infinity
            for j in i..<bottoms.count {
                let dist = Self.distance(
                    newTime: timeMs, newWidth: width, prev: occupants[j], viewWidth: viewWidth,
                    durationMs: durationMs)
                if dist <= mostDistance { break }
                intervalLeast = min(intervalLeast, dist)
                if height <= bottoms[j] - lastPos {
                    best = (i, j, lastPos)
                    mostDistance = intervalLeast
                    overlapped = intervalLeast < 0
                    if !overlapped { break outer }
                    break
                }
            }
            lastPos = bottoms[i]
        }

        guard let best, !(overlapped && !allowOverlap) else { return nil }
        let newBottom = best.pos + height
        // The new danmaku replaces intervals first..<last; `last` keeps its occupant for what remains below.
        if bottoms[best.last] <= newBottom {
            bottoms.replaceSubrange(best.first...best.last, with: [newBottom])
            occupants.replaceSubrange(best.first...best.last, with: [RollOccupant(timeMs: timeMs, width: width)])
        } else {
            bottoms.replaceSubrange(best.first..<best.last, with: [newBottom])
            occupants.replaceSubrange(best.first..<best.last, with: [RollOccupant(timeMs: timeMs, width: width)])
        }
        return best.pos
    }
}

/// Vertical intervals for top/bottom danmaku; each interval remembers when it becomes free.
struct StaticRoom {
    private(set) var bottoms: [CGFloat]
    private(set) var freeAt: [Int]

    init(height: CGFloat) {
        bottoms = [height]
        freeAt = [Int.min / 2]
    }

    /// Places a top danmaku (scanning downward). Returns its top edge.
    mutating func placeTopDown(timeMs: Int, height: CGFloat, until: Int, allowOverlap: Bool) -> CGFloat? {
        var leastTime = allowOverlap ? Int.max : timeMs
        var lastPos: CGFloat = 0
        var best: (first: Int, last: Int, pos: CGFloat)?
        var overlapped = true

        outer: for i in bottoms.indices {
            var intervalMost = Int.min / 2
            for j in i..<bottoms.count {
                if freeAt[j] >= leastTime { break }
                intervalMost = max(intervalMost, freeAt[j])
                if height <= bottoms[j] - lastPos {
                    best = (i, j, lastPos)
                    leastTime = intervalMost
                    overlapped = timeMs < intervalMost
                    if !overlapped { break outer }
                    break
                }
            }
            lastPos = bottoms[i]
        }

        guard let best, !(overlapped && !allowOverlap) else { return nil }
        let newBottom = best.pos + height
        if bottoms[best.last] <= newBottom {
            bottoms.replaceSubrange(best.first...best.last, with: [newBottom])
            freeAt.replaceSubrange(best.first...best.last, with: [until])
        } else {
            bottoms.replaceSubrange(best.first..<best.last, with: [newBottom])
            freeAt.replaceSubrange(best.first..<best.last, with: [until])
        }
        return best.pos
    }

    /// Places a bottom danmaku (scanning upward). Returns its top edge.
    mutating func placeBottomUp(timeMs: Int, height: CGFloat, until: Int, allowOverlap: Bool) -> CGFloat? {
        var leastTime = allowOverlap ? Int.max : timeMs
        var best: (first: Int, last: Int, pos: CGFloat)?
        var overlapped = true

        outer: for i in bottoms.indices.reversed() {
            let startPos = bottoms[i]
            var intervalMost = Int.min / 2
            for j in stride(from: i, through: 0, by: -1) {
                if freeAt[j] >= leastTime { break }
                intervalMost = max(intervalMost, freeAt[j])
                let top = j > 0 ? bottoms[j - 1] : 0
                if height <= startPos - top {
                    best = (i, j, startPos)
                    leastTime = intervalMost
                    overlapped = timeMs < intervalMost
                    if !overlapped { break outer }
                    break
                }
            }
        }

        guard let best, !(overlapped && !allowOverlap) else { return nil }
        let top = best.pos - height
        // Intervals last...first are replaced by: the untouched upper part of `last`, then the new danmaku.
        let lastTop = best.last > 0 ? bottoms[best.last - 1] : 0
        if top <= lastTop {
            bottoms.replaceSubrange(best.last...best.first, with: [best.pos])
            freeAt.replaceSubrange(best.last...best.first, with: [until])
        } else {
            bottoms.replaceSubrange(best.last...best.first, with: [top, best.pos])
            freeAt.replaceSubrange(best.last...best.first, with: [freeAt[best.last], until])
        }
        return top
    }
}
