import CoreGraphics
import Foundation
import Testing

@testable import DanmakuCore

/// Deterministic generator for synthetic danmaku.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func syntheticDanmaku(
    count: Int, spanMs: Int, seed: UInt64 = 1, modes: [DanmakuMode] = [.roll, .roll, .roll, .top, .bottom, .inverse]
)
    -> [Danmaku]
{
    var rng = SplitMix(state: seed)
    let words = ["哈哈哈", "awsl", "前方高能", "233333", "这就是青春吗", "好耶", "名场面", "泪目", "?", "来了来了来了来了"]
    var items: [Danmaku] = []
    for i in 0..<count {
        let text = String(repeating: words[Int(rng.next() % UInt64(words.count))], count: Int(rng.next() % 3) + 1)
        items.append(
            Danmaku(
                id: UInt64(i), text: text, timeMs: Int(rng.next() % UInt64(spanMs)),
                mode: modes[Int(rng.next() % UInt64(modes.count))],
                fontSize: [18, 25, 25, 25, 36][Int(rng.next() % 5)]))
    }
    var track = DanmakuTrack(items: items)
    track.sort()
    return track.items
}

struct LayoutTests {
    let measurer = EstimatingTextMeasurer()

    func rowsOverlap(_ a: PlacedDanmaku, _ b: PlacedDanmaku, spacing: CGFloat) -> Bool {
        a.y < b.y + b.height + spacing - 0.001 && b.y < a.y + a.height + spacing - 0.001
    }

    /// Left edge of a scrolling danmaku at `t`.
    func x(_ d: PlacedDanmaku, _ t: Int, width: CGFloat) -> Double {
        Double(width) - Double(width + d.width) * Double(t - d.startMs) / Double(d.durationMs)
    }

    @Test func scrollingDanmakuNeverCollideWithoutOverlap() throws {
        let config = LayoutConfig(viewSize: CGSize(width: 1280, height: 720), rollDurationMs: 8000, lineSpacing: 2)
        let items = syntheticDanmaku(count: 4000, spanMs: 120_000, modes: [.roll])
        let timeline = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        #expect(timeline.items.count > 1000)
        #expect(timeline.items.count + timeline.droppedCount == items.count)

        let rolls = timeline.items
        for (i, a) in rolls.enumerated() {
            for b in rolls[(i + 1)...] {
                if b.startMs >= a.endMs { break }
                guard rowsOverlap(a, b, spacing: config.lineSpacing) else { continue }
                // Gap is linear in time, so checking both ends of the shared lifetime suffices.
                for t in [max(a.startMs, b.startMs), min(a.endMs, b.endMs)] {
                    let (front, back) = a.startMs <= b.startMs ? (a, b) : (b, a)
                    let gap = x(back, t, width: 1280) - (x(front, t, width: 1280) + Double(front.width))
                    #expect(gap >= -0.01, "collision at \(t): \(front) vs \(back)")
                }
            }
        }
    }

    @Test func staticDanmakuNeverOverlap() throws {
        let config = LayoutConfig(viewSize: CGSize(width: 1280, height: 720), staticDurationMs: 4000)
        let items = syntheticDanmaku(count: 3000, spanMs: 60_000, modes: [.top, .bottom])
        let timeline = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        #expect(timeline.items.count > 250)  // ~22 rows × 15 lifetimes per minute
        let statics = timeline.items
        for (i, a) in statics.enumerated() {
            #expect(a.y >= 0 && a.y + a.height <= 720.001)
            for b in statics[(i + 1)...] {
                if b.startMs >= a.endMs { break }
                #expect(!rowsOverlap(a, b, spacing: 0), "\(a) overlaps \(b)")
            }
        }
        // Bottom danmaku fill from the bottom.
        let firstBottom = try #require(statics.first { $0.kind == .bottom })
        #expect(firstBottom.y + firstBottom.height > 690)
    }

    @Test func overlapModePlacesEverything() throws {
        let config = LayoutConfig(viewSize: CGSize(width: 800, height: 300), allowOverlap: true)
        let items = syntheticDanmaku(count: 2000, spanMs: 10_000, modes: [.roll, .top, .bottom, .inverse])
        let timeline = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        #expect(timeline.droppedCount == 0)
        #expect(timeline.items.allSatisfy { $0.y >= 0 && $0.y + $0.height <= 300.001 })
    }

    @Test func countLimitsAreRespected() throws {
        var config = LayoutConfig(viewSize: CGSize(width: 1920, height: 1080), allowOverlap: true)
        config.limits = KindLimits(roll: 5)
        let items = syntheticDanmaku(count: 500, spanMs: 20_000, modes: [.roll])
        let timeline = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        for t in stride(from: 0, to: 30_000, by: 250) {
            #expect(timeline.activeIndices(at: t).count <= 5)
        }
    }

    @Test func layoutIsDeterministic() throws {
        let config = LayoutConfig(viewSize: CGSize(width: 1280, height: 720))
        let items = syntheticDanmaku(count: 2000, spanMs: 60_000)
        let a = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        let b = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        #expect(a.items == b.items)
    }

    @Test func timeWindowQueriesMatchBruteForce() throws {
        let config = LayoutConfig(viewSize: CGSize(width: 1280, height: 720), allowOverlap: true)
        let items = syntheticDanmaku(count: 3000, spanMs: 90_000)
        let timeline = try LayoutEngine(config: config, measurer: measurer).layoutSync(items)
        for t in stride(from: -1000, to: 100_000, by: 777) {
            let brute = timeline.items.indices.filter {
                timeline.items[$0].startMs <= t && timeline.items[$0].endMs > t
            }
            #expect(timeline.activeIndices(at: t) == brute)
            let window = timeline.indices(startingIn: t..<(t + 2000))
            let bruteWindow = timeline.items.indices.filter { (t..<(t + 2000)).contains(timeline.items[$0].startMs) }
            #expect(Array(window) == bruteWindow)
        }
    }

    @Test func advancedDanmakuUseTheirOwnDuration() throws {
        var d = Danmaku(text: #"[0.5,0.5,"1-1",3.5,"abc",0,0,0.5,0.5,0,0,0,"",0]"#, timeMs: 1000, mode: .advanced)
        d.parseAdvancedIfNeeded()
        let timeline = try LayoutEngine(
            config: LayoutConfig(viewSize: CGSize(width: 100, height: 100)), measurer: measurer
        )
        .layoutSync([d])
        #expect(timeline.items.first?.kind == .advanced)
        #expect(timeline.items.first?.endMs == 4500)
    }

    @Test func cancellationStopsLayout() async throws {
        let items = syntheticDanmaku(count: 50_000, spanMs: 600_000)
        let engine = LayoutEngine(config: LayoutConfig(viewSize: CGSize(width: 1280, height: 720)), measurer: measurer)
        let task = Task { try await engine.layout(items) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func layoutOf100kIsFast() throws {
        let items = syntheticDanmaku(count: 100_000, spanMs: 1_440_000)
        let engine = LayoutEngine(config: LayoutConfig(viewSize: CGSize(width: 1920, height: 1080)), measurer: measurer)
        let start = Date()
        let timeline = try engine.layoutSync(items)
        let elapsed = Date().timeIntervalSince(start)
        #expect(timeline.items.count > 10_000)
        #expect(elapsed < 2.0, "took \(elapsed)s")  // debug build; release is several times faster
    }
}
