import Foundation

/// Precomputed features of one text for pakku-style similarity checks.
struct SimilarityFeatures {
    let text: String
    let mode: DanmakuKind
    let length: Int
    let characters: [UInt32: Int]
    let pinyin: [UInt32: Int]
    let pinyinLength: Int
    let bigrams: [Int: Int]

    init(text: String, mode: DanmakuKind, usePinyin: Bool, useBigrams: Bool) {
        self.text = text
        self.mode = mode
        let scalars = Array(text.unicodeScalars)
        length = scalars.count

        var chars: [UInt32: Int] = [:]
        for s in scalars { chars[s.value, default: 0] += 1 }
        characters = chars

        var py: [UInt32: Int] = [:]
        var pyLength = 0
        if usePinyin {
            let table = PinyinTable.shared
            let base: UInt32 = 0xE000  // Private Use Area keeps pinyin codes apart from real characters.
            for s in scalars {
                if let (initial, final) = table[s.value] {
                    py[base + UInt32(initial), default: 0] += 1
                    pyLength += 1
                    if final > 0 {
                        py[base + UInt32(final), default: 0] += 1
                        pyLength += 1
                    }
                } else {
                    var v = s.value
                    if (0x41...0x5A).contains(v) { v += 0x20 }
                    py[v, default: 0] += 1
                    pyLength += 1
                }
            }
        }
        pinyin = py
        pinyinLength = pyLength

        var grams: [Int: Int] = [:]
        if useBigrams, let last = scalars.last {
            let mod = 1007
            var previous = Int(last.value) % mod
            for s in scalars {
                let current = Int(s.value) % mod
                grams[previous * mod + current, default: 0] += 1
                previous = current
            }
        }
        bigrams = grams
    }
}

struct SimilarityChecker: Sendable {
    var maxEditDistance: Int
    /// 0–10; values above 10 disable the cosine check.
    var maxCosineDistance: Int
    var usePinyin: Bool

    /// Returns a short reason when `a` and `b` are similar, else `nil`.
    func similar(_ a: SimilarityFeatures, _ b: SimilarityFeatures) -> String? {
        if a.text == b.text { return "==" }

        let lengthSum = a.length + b.length
        let minSize = max(1, maxEditDistance * 2)
        let threshold = lengthSum < minSize ? maxEditDistance * lengthSum / minSize + 1 : maxEditDistance

        var editDistance = 0
        let checkedEdit = abs(a.length - b.length) <= maxEditDistance
        if checkedEdit {
            editDistance = Self.frequencyDistance(a.characters, b.characters)
            if editDistance <= threshold { return "≤\(editDistance)" }
        }

        if usePinyin, abs(a.pinyinLength - b.pinyinLength) <= maxEditDistance {
            let d = Self.frequencyDistance(a.pinyin, b.pinyin)
            if d <= threshold { return "≤\(d)py" }
        }

        // Texts sharing no characters at all cannot be cosine-similar.
        if maxCosineDistance <= 10, !(checkedEdit && editDistance >= lengthSum) {
            let cosine = Int(10 * Self.cosineSimilarity(a.bigrams, b.bigrams))
            if cosine >= maxCosineDistance { return "\(cosine * 10)%" }
        }
        return nil
    }

    /// "Edit distance" approximated by the L1 distance of character frequencies (O(n), as in pakku).
    static func frequencyDistance<K: Hashable>(_ a: [K: Int], _ b: [K: Int]) -> Int {
        var total = 0
        for (k, x) in a { total += abs(x - (b[k] ?? 0)) }
        for (k, y) in b where a[k] == nil { total += y }
        return total
    }

    /// Squared cosine similarity of two bigram vectors: (a·b)² / (|a|²|b|²).
    static func cosineSimilarity(_ a: [Int: Int], _ b: [Int: Int]) -> Double {
        var dot = 0
        var normA = 0
        var normB = 0
        for (k, x) in a {
            let y = b[k] ?? 0
            dot += x * y
            normA += x * x
        }
        for (_, y) in b { normB += y * y }
        guard normA > 0, normB > 0 else { return 0 }
        return Double(dot) * Double(dot) / Double(normA) / Double(normB)
    }
}
