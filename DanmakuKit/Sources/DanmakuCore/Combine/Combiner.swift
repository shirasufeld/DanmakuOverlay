import Foundation

/// Merges similar danmaku that appear close together (port of pakku.js via DanmakuPlayer, with changes:
/// danmaku join the cluster they actually matched, pinyin distance compares pinyin, and danmaku excluded from
/// merging are passed through instead of dropped).
public struct Combiner: Sendable {
    public var settings: MergeSettings

    public init(settings: MergeSettings) { self.settings = settings }

    /// `items` must be sorted by time; the result is sorted by time.
    public func combine(_ items: [Danmaku]) throws -> [Danmaku] {
        guard settings.enabled else { return items }
        let normalizer = TextNormalizer(
            trimEnding: settings.trimEnding, trimSpace: settings.trimSpace, trimWidth: settings.trimWidth)
        let checker = SimilarityChecker(
            maxEditDistance: settings.maxEditDistance, maxCosineDistance: settings.maxCosineDistance,
            usePinyin: settings.usePinyin)
        let windowMs = settings.timeWindow * 1000

        var passthrough: [Danmaku] = []
        var finished: [Cluster] = []
        // Open clusters, oldest first; only those whose first member is within the window can grow.
        var open: [Cluster] = []
        var openHead = 0

        for (i, d) in items.enumerated() {
            if i & 0x3FF == 0 { try Task.checkCancellation() }
            guard participates(d) else {
                passthrough.append(d)
                continue
            }

            while openHead < open.count, d.timeMs - open[openHead].firstTimeMs > windowMs {
                finished.append(open[openHead])
                openHead += 1
            }
            if openHead > 1024 {
                open.removeFirst(openHead)
                openHead = 0
            }

            let normalized = normalizer.normalize(d.displayText)
            let features = SimilarityFeatures(
                text: normalized, mode: d.kind, usePinyin: settings.usePinyin,
                useBigrams: settings.maxCosineDistance <= 10)

            var matched: Int?
            // Newest clusters first: recent repeats are the most likely match.
            for c in stride(from: open.count - 1, through: openHead, by: -1) {
                let candidate = open[c].features
                if !settings.crossMode, candidate.mode != features.mode { continue }
                if checker.similar(features, candidate) != nil {
                    matched = c
                    break
                }
            }
            if let matched {
                open[matched].members.append(Member(danmaku: d, normalized: normalized))
            } else {
                open.append(
                    Cluster(
                        features: features, firstTimeMs: d.timeMs, members: [Member(danmaku: d, normalized: normalized)]
                    ))
            }
        }
        finished.append(contentsOf: open[openHead...])
        finished.sort { $0.firstTimeMs < $1.firstTimeMs }

        var output = postProcess(finished)
        output.append(contentsOf: passthrough)
        output.sort { ($0.timeMs, $0.id) < ($1.timeMs, $1.id) }
        return output
    }

    private func participates(_ d: Danmaku) -> Bool {
        switch d.kind {
        case .advanced, .unsupported: return false
        case .bottom where !settings.processBottom: return false
        default: return settings.processSubtitlePool || d.pool != .subtitle
        }
    }

    struct Member {
        var danmaku: Danmaku
        var normalized: String
    }

    struct Cluster {
        var features: SimilarityFeatures
        var firstTimeMs: Int
        var members: [Member]

        /// Most frequent normalised text; ties resolved by the median length.
        var chosenText: String {
            if members.count == 1 { return members[0].normalized }
            var counts: [String: Int] = [:]
            var best: [String] = []
            var bestCount = 0
            for m in members {
                let c = (counts[m.normalized] ?? 0) + 1
                counts[m.normalized] = c
                if c > bestCount {
                    best = [m.normalized]
                    bestCount = c
                } else if c == bestCount {
                    best.append(m.normalized)
                }
            }
            if best.count == 1 { return best[0] }
            best.sort { $0.count < $1.count }
            return best[best.count / 2]
        }
    }

    private func postProcess(_ clusters: [Cluster]) -> [Danmaku] {
        let displayWindowMs = 5000
        let power = 0.35
        let maxShrink = 1.732
        let shrinkBase = pow(Double(max(settings.shrinkThreshold, 1)), power)
        var onScreen = 0.0
        var onScreenQueue: [(time: Int, value: Double)] = []
        var queueHead = 0
        var output: [Danmaku] = []
        output.reserveCapacity(clusters.count)

        for cluster in clusters {
            let count = cluster.members.count
            let repIndex = min(count * settings.representativePercent / 100, count - 1)
            let representative = cluster.members[repIndex].danmaku

            var size = representative.fontSize
            var mode = representative.mode
            for m in cluster.members {
                let d = m.danmaku
                if d.fontSize < 30 { size = max(size, d.fontSize) }
                if d.mode == .bottom {
                    mode = .bottom
                } else if d.mode == .top, mode != .bottom {
                    mode = .top
                }
            }
            var merged = representative
            merged.mergeCount = count
            if settings.modeElevation { merged.mode = mode }
            if settings.enlarge, count > 5 {
                merged.fontSize = Int((Double(size) * log(Double(count)) / log(5)).rounded(.up))
            } else {
                merged.fontSize = size
            }
            merged.text = markedText(cluster.chosenText, count: count)

            if settings.shrinkThreshold > 0 || settings.dropThreshold > 0 {
                while queueHead < onScreenQueue.count, merged.timeMs > onScreenQueue[queueHead].time {
                    onScreen -= onScreenQueue[queueHead].value
                    queueHead += 1
                }
                if settings.dropThreshold > 0,
                    shouldDrop(onScreen, threshold: Double(settings.dropThreshold), peers: count, seed: merged.id)
                {
                    continue
                }
                let value = Self.displayValue(merged)
                onScreen += value
                onScreenQueue.append((merged.timeMs + displayWindowMs, value))

                if settings.shrinkThreshold > 0, onScreen > Double(settings.shrinkThreshold) {
                    let rate = min(pow(onScreen, power) / shrinkBase, maxShrink)
                    merged.fontSize = Int(Double(merged.fontSize) / rate)
                }
            }

            if settings.scrollThreshold > 0, merged.kind == .top || merged.kind == .bottom,
                Self.estimatedWidth(merged.text, fontSize: merged.fontSize) > Double(settings.scrollThreshold)
            {
                merged.text = (merged.kind == .bottom ? "↓" : "↑") + merged.text
                merged.mode = .roll
            }
            output.append(merged)
        }
        return output
    }

    func markedText(_ text: String, count: Int) -> String {
        guard settings.markStyle != .off, count > settings.markThreshold else { return text }
        let mark = settings.markUsesSubscript ? "₍\(Self.subscriptDigits(count))₎" : "[x\(count)]"
        return settings.markStyle == .suffix ? text + mark : mark + text
    }

    static func subscriptDigits(_ n: Int) -> String {
        String(String(n).unicodeScalars.map { Character(Unicode.Scalar(0x2080 + ($0.value - 0x30))!) })
    }

    static func displayValue(_ d: Danmaku) -> Double {
        var small = 0
        for s in d.text.unicodeScalars {
            switch s.value {
            case 0x20...0x7E, 0x2080...0x2089, 0x208D, 0x208E, 0x2193, 0x2191: small += 1
            default: break
            }
        }
        let length = Double(d.text.unicodeScalars.count) - Double(small) / 2
        let sizeFactor = max(min(Double(d.fontSize) / 25, 2.5), 0.7)
        return sqrt(max(length, 0)) * pow(sizeFactor, 1.5)
    }

    /// Probabilistic drop under heavy density; deterministic per danmaku so relayouts are stable.
    func shouldDrop(_ current: Double, threshold: Double, peers: Int, seed: UInt64) -> Bool {
        guard threshold > 0, current > threshold else { return false }
        let rate = (current - threshold) / threshold + 0.25 - (sqrt(Double(peers)) - 1) / 5
        if rate >= 1 { return true }
        guard rate > 0 else { return false }
        var x = seed &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53) < rate
    }

    static func estimatedWidth(_ text: String, fontSize: Int) -> Double {
        text.unicodeScalars.reduce(0) { $0 + ((0x4E00...0x9FFF).contains($1.value) ? 1 : 0.5) } * Double(fontSize)
    }
}
