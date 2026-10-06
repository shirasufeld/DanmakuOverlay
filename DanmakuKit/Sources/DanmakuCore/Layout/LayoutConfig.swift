import CoreGraphics

/// Per-kind on-screen count limits; `nil` means unlimited.
public struct KindLimits: Sendable, Hashable, Codable {
    public var roll: Int?
    public var top: Int?
    public var bottom: Int?
    public var inverse: Int?

    public init(roll: Int? = nil, top: Int? = nil, bottom: Int? = nil, inverse: Int? = nil) {
        self.roll = roll
        self.top = top
        self.bottom = bottom
        self.inverse = inverse
    }

    public subscript(kind: DanmakuKind) -> Int? {
        switch kind {
        case .roll: roll
        case .top: top
        case .bottom: bottom
        case .inverse: inverse
        case .advanced, .unsupported: nil
        }
    }
}

/// Everything the layout depends on. Changing any field requires a relayout.
public struct LayoutConfig: Sendable, Hashable {
    /// Size of the danmaku view in points.
    public var viewSize: CGSize
    /// Height (from the top of the view) danmaku may occupy, in points.
    public var areaHeight: CGFloat
    /// Time a scrolling danmaku takes to cross the view, in media milliseconds.
    public var rollDurationMs: Int
    /// Time a top/bottom danmaku stays on screen, in media milliseconds.
    public var staticDurationMs: Int
    /// Points per Bilibili font-size unit (1.0 → size 25 renders at 25 pt).
    public var fontScale: CGFloat
    /// Extra vertical gap between rows, in points.
    public var lineSpacing: CGFloat
    public var allowOverlap: Bool
    public var limits: KindLimits

    public init(
        viewSize: CGSize,
        areaHeight: CGFloat? = nil,
        rollDurationMs: Int = 10_000,
        staticDurationMs: Int = 5_000,
        fontScale: CGFloat = 1,
        lineSpacing: CGFloat = 2,
        allowOverlap: Bool = false,
        limits: KindLimits = KindLimits()
    ) {
        self.viewSize = viewSize
        self.areaHeight = areaHeight ?? viewSize.height
        self.rollDurationMs = max(rollDurationMs, 1)
        self.staticDurationMs = max(staticDurationMs, 1)
        self.fontScale = fontScale
        self.lineSpacing = lineSpacing
        self.allowOverlap = allowOverlap
        self.limits = limits
    }

    public func fontSize(for danmaku: Danmaku) -> CGFloat {
        CGFloat(danmaku.fontSize) * fontScale
    }
}
