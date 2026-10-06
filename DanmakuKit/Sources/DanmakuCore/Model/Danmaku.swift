import Foundation

/// Bilibili danmaku mode. Modes 1–3 are all ordinary right-to-left scrolling danmaku.
public enum DanmakuMode: Int, Sendable, Codable, CaseIterable {
    case roll = 1
    case roll2 = 2
    case roll3 = 3
    case bottom = 4
    case top = 5
    case inverse = 6
    case advanced = 7
    case code = 8
    case bas = 9

    /// How the danmaku is laid out and animated.
    public var kind: DanmakuKind {
        switch self {
        case .roll, .roll2, .roll3: .roll
        case .bottom: .bottom
        case .top: .top
        case .inverse: .inverse
        case .advanced: .advanced
        case .code, .bas: .unsupported
        }
    }
}

public enum DanmakuKind: Int, Sendable, Codable, CaseIterable {
    case roll, top, bottom, inverse, advanced, unsupported
}

/// Danmaku pool. 0: normal, 1: subtitle, 2: special (code / BAS).
public enum DanmakuPool: Int, Sendable, Codable {
    case normal = 0
    case subtitle = 1
    case advanced = 2
}

/// Danmaku attribute bits (`attr` field): bit0 protected, bit1 from live, bit2 highly liked.
public struct DanmakuAttributes: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let protected = DanmakuAttributes(rawValue: 1 << 0)
    public static let fromLive = DanmakuAttributes(rawValue: 1 << 1)
    public static let highLike = DanmakuAttributes(rawValue: 1 << 2)
}

/// One danmaku comment as loaded from a source, before layout.
public struct Danmaku: Sendable, Hashable {
    public var id: UInt64
    public var text: String
    /// Appearance time in media milliseconds.
    public var timeMs: Int
    public var mode: DanmakuMode
    /// Font size in Bilibili units (25 = normal, 18 = small, 36 = large).
    public var fontSize: Int
    /// 0xRRGGBB.
    public var color: UInt32
    public var pool: DanmakuPool
    public var attributes: DanmakuAttributes
    public var userHash: String
    /// Bilibili VIP gradient colour.
    public var colorful: Bool
    /// Unix timestamp the danmaku was sent.
    public var sendTime: Int64
    /// Shield weight [1, 10]; 0 when unknown.
    public var weight: Int
    /// Parsed payload of a mode-7 danmaku, `nil` for other modes or when invalid.
    public var advanced: AdvancedDanmaku?
    /// Number of original danmaku merged into this one (set by the combiner).
    public var mergeCount: Int

    public init(
        id: UInt64 = 0,
        text: String,
        timeMs: Int,
        mode: DanmakuMode = .roll,
        fontSize: Int = 25,
        color: UInt32 = 0xFFFFFF,
        pool: DanmakuPool = .normal,
        attributes: DanmakuAttributes = [],
        userHash: String = "",
        colorful: Bool = false,
        sendTime: Int64 = 0,
        weight: Int = 0,
        advanced: AdvancedDanmaku? = nil,
        mergeCount: Int = 1
    ) {
        self.id = id
        self.text = text
        self.timeMs = timeMs
        self.mode = mode
        self.fontSize = fontSize
        self.color = color
        self.pool = pool
        self.attributes = attributes
        self.userHash = userHash
        self.colorful = colorful
        self.sendTime = sendTime
        self.weight = weight
        self.advanced = advanced
        self.mergeCount = mergeCount
    }

    public var kind: DanmakuKind { mode.kind }

    /// The text actually displayed (mode-7 danmaku carry their text inside a JSON payload).
    public var displayText: String { advanced?.text ?? text }

    /// Parses the mode-7 payload if this is an advanced danmaku.
    public mutating func parseAdvancedIfNeeded() {
        guard mode == .advanced, advanced == nil else { return }
        advanced = AdvancedDanmaku.parse(text)
    }
}

/// An ordered collection of danmaku from one source.
public struct DanmakuTrack: Sendable {
    public var items: [Danmaku]
    public var title: String?

    public init(items: [Danmaku], title: String? = nil) {
        self.items = items
        self.title = title
    }

    /// Sorts by time, then id, so that layout is deterministic.
    public mutating func sort() {
        items.sort { ($0.timeMs, $0.id) < ($1.timeMs, $1.id) }
    }

    public var lastTimeMs: Int { items.last?.timeMs ?? 0 }
}
