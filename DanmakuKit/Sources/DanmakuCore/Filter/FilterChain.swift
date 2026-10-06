import Foundation

/// A pure transformation of the danmaku list.
public protocol DanmakuFilter: Sendable {
    func apply(_ items: [Danmaku]) throws -> [Danmaku]
}

/// Hides danmaku by kind, pool, colour and shield weight.
public struct KindFilter: DanmakuFilter {
    public var settings: FilterSettings
    public init(settings: FilterSettings) { self.settings = settings }

    public func apply(_ items: [Danmaku]) throws -> [Danmaku] {
        let s = settings
        return items.filter { d in
            switch d.kind {
            case .roll: guard s.showRoll else { return false }
            case .top: guard s.showTop else { return false }
            case .bottom: guard s.showBottom else { return false }
            case .inverse: guard s.showInverse else { return false }
            case .advanced: guard s.showAdvanced, d.advanced != nil else { return false }
            case .unsupported: return false
            }
            if d.pool == .advanced { return false }
            if !s.showSubtitlePool, d.pool == .subtitle { return false }
            if !s.showColored, d.color & 0xFFFFFF != 0xFFFFFF { return false }
            if s.minimumWeight > 0, d.weight > 0, d.weight < s.minimumWeight { return false }
            return true
        }
    }
}

/// Hides danmaku containing blocked keywords (case-insensitive), matching regexes or from blocked users.
public struct BlocklistFilter: DanmakuFilter {
    public let keywords: [String]
    public let regexes: [NSRegularExpression]
    public let users: Set<String>
    /// Patterns that failed to compile.
    public let invalidPatterns: [String]

    public init(settings: FilterSettings) {
        keywords = settings.keywords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        var compiled: [NSRegularExpression] = []
        var invalid: [String] = []
        for p in settings.regexes where !p.isEmpty {
            if let r = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                compiled.append(r)
            } else {
                invalid.append(p)
            }
        }
        regexes = compiled
        invalidPatterns = invalid
        users = Set(settings.userHashes.filter { !$0.isEmpty })
    }

    public var isEmpty: Bool { keywords.isEmpty && regexes.isEmpty && users.isEmpty }

    public func apply(_ items: [Danmaku]) throws -> [Danmaku] {
        guard !isEmpty else { return items }
        var out: [Danmaku] = []
        out.reserveCapacity(items.count)
        for (i, d) in items.enumerated() {
            if i & 0xFFF == 0 { try Task.checkCancellation() }
            if users.contains(d.userHash) { continue }
            let text = d.displayText
            if !keywords.isEmpty {
                let lower = text.lowercased()
                if keywords.contains(where: { lower.contains($0) }) { continue }
            }
            if !regexes.isEmpty {
                let range = NSRange(text.startIndex..., in: text)
                if regexes.contains(where: { $0.firstMatch(in: text, range: range) != nil }) { continue }
            }
            out.append(d)
        }
        return out
    }
}

/// Runs all filters in order: kind → blocklists → merge (merging what remains, as pakku does).
public struct FilterChain: Sendable {
    public var filters: [any DanmakuFilter]

    public init(filter: FilterSettings, merge: MergeSettings) {
        filters = [KindFilter(settings: filter), BlocklistFilter(settings: filter), MergeFilter(settings: merge)]
    }

    @concurrent
    public func run(_ items: [Danmaku]) async throws -> [Danmaku] {
        var current = items
        for f in filters {
            try Task.checkCancellation()
            current = try f.apply(current)
        }
        return current
    }
}

public struct MergeFilter: DanmakuFilter {
    public var settings: MergeSettings
    public init(settings: MergeSettings) { self.settings = settings }
    public func apply(_ items: [Danmaku]) throws -> [Danmaku] { try Combiner(settings: settings).combine(items) }
}
