import CoreGraphics
import Foundation

public enum OutlineStyle: String, Sendable, Codable, CaseIterable {
    case stroke
    case shadow
    case strokeAndShadow
    case none
}

public enum FontWeightOption: String, Sendable, Codable, CaseIterable {
    case regular, medium, semibold, bold, heavy
}

public enum MergeMarkStyle: String, Sendable, Codable, CaseIterable {
    case off, prefix, suffix
}

/// Appearance and layout of danmaku.
public struct DisplaySettings: Sendable, Codable, Hashable {
    public var opacity = 0.85
    public var fontName = "PingFang SC"
    public var fontWeight = FontWeightOption.semibold
    /// Multiplier on Bilibili font sizes (1 → size 25 renders at 25 pt).
    public var fontScale = 1.0
    /// Additionally scale fonts with the danmaku area height (reference height 720 pt).
    public var scaleWithViewHeight = false
    /// Seconds a scrolling danmaku takes to cross the screen at 1× speed.
    public var rollDuration = 10.0
    /// Seconds a top/bottom danmaku stays on screen at 1× speed.
    public var staticDuration = 5.0
    /// When the player runs faster, keep danmaku crossing the screen at the same on-screen speed.
    public var keepScreenSpeedOnRateChange = true
    public var lineSpacing = 2.0
    public var outline = OutlineStyle.stroke
    public var strokeWidth = 1.0
    /// 0xRRGGBB.
    public var strokeColor: UInt32 = 0x000000
    public var colorfulGradient = true
    public var allowOverlap = false
    /// Fraction of the content height danmaku may use, from the top.
    public var displayArea = 1.0
    /// Keep the bottom of the picture free for subtitles.
    public var protectSubtitles = false
    public var subtitleSafeFraction = 0.15
    public var limits = KindLimits()
    public var contentFit = ContentFit.video
    public var hideWhileMoving = true

    public init() {}
}

/// Which danmaku are shown at all.
public struct FilterSettings: Sendable, Codable, Hashable {
    public var showRoll = true
    public var showTop = true
    public var showBottom = true
    public var showInverse = true
    public var showAdvanced = true
    public var showSubtitlePool = true
    public var showColored = true
    /// Bilibili shield level: hide danmaku whose weight is below this (0 = show all).
    public var minimumWeight = 0
    public var keywords: [String] = []
    public var regexes: [String] = []
    public var userHashes: [String] = []

    public init() {}
}

/// Similar-danmaku merging (pakku algorithm).
public struct MergeSettings: Sendable, Codable, Hashable {
    public var enabled = true
    /// Seconds within which similar danmaku are merged.
    public var timeWindow = 20
    public var maxEditDistance = 5
    /// Bigram cosine similarity threshold in tenths (0–10; 11 disables).
    public var maxCosineDistance = 6
    public var crossMode = false
    public var trimEnding = true
    public var trimSpace = true
    public var trimWidth = true
    public var usePinyin = true
    public var processSubtitlePool = true
    public var processBottom = true
    /// Which member of a cluster represents it, as a percentage of its position.
    public var representativePercent = 0
    public var modeElevation = false
    public var enlarge = true
    public var markStyle = MergeMarkStyle.suffix
    public var markUsesSubscript = true
    /// Clusters larger than this get a count mark.
    public var markThreshold = 1
    /// 0 disables density-based shrinking / dropping / scroll conversion.
    public var shrinkThreshold = 0
    public var dropThreshold = 0
    public var scrollThreshold = 0

    public init() {}
}

/// Synchronisation with external players.
public struct SyncSettings: Sendable, Codable, Hashable {
    /// Preferred adapter per bundle identifier (overrides the built-in order).
    public var preferredAdapters: [String: SourceKind] = [:]
    public var mpvSocketPath = "/tmp/danmakuoverlay-mpv.sock"
    /// Mirror Space / ←/→ to the manual clock while the target player is frontmost.
    public var mirrorKeys = true
    public var seekStep = 5.0
    public var offsetStep = 0.5
    public var autoLoadMatchingDanmaku = true
    public var libraryFolders: [String] = []
    public var vlcRoundsSeconds = false

    public init() {}
}

public struct GeneralSettings: Sendable, Codable, Hashable {
    public var showControlsOnAttach = true
    public var showStatistics = false
    public var hotkeysEnabled = true

    public init() {}
}

/// All persisted settings. New fields must have defaults; stored JSON is merged over defaults on load.
public struct AppSettings: Sendable, Codable, Hashable {
    public static let schemaVersion = 1

    public var schemaVersion = AppSettings.schemaVersion
    public var display = DisplaySettings()
    public var filter = FilterSettings()
    public var merge = MergeSettings()
    public var sync = SyncSettings()
    public var general = GeneralSettings()

    public init() {}
}

/// How much work a settings change requires, ordered by cost.
public enum SettingsImpact: Int, Sendable, Comparable {
    case none
    /// Global opacity / visibility only.
    case render
    /// Bitmaps must be redrawn (colours, outline) but positions are unchanged.
    case restyle
    /// Positions must be recomputed.
    case relayout
    /// The danmaku list must be re-filtered (and re-laid out).
    case refilter

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public static func between(_ old: AppSettings, _ new: AppSettings) -> SettingsImpact {
        if old.filter != new.filter || old.merge != new.merge { return .refilter }
        let o = old.display
        let n = new.display
        if o.fontName != n.fontName || o.fontWeight != n.fontWeight || o.fontScale != n.fontScale
            || o.scaleWithViewHeight != n.scaleWithViewHeight || o.rollDuration != n.rollDuration
            || o.staticDuration != n.staticDuration || o.keepScreenSpeedOnRateChange != n.keepScreenSpeedOnRateChange
            || o.lineSpacing != n.lineSpacing || o.allowOverlap != n.allowOverlap || o.displayArea != n.displayArea
            || o.protectSubtitles != n.protectSubtitles || o.subtitleSafeFraction != n.subtitleSafeFraction
            || o.limits != n.limits || o.contentFit != n.contentFit || o.outline != n.outline
            || o.strokeWidth != n.strokeWidth
        {
            return .relayout
        }
        if o.strokeColor != n.strokeColor || o.colorfulGradient != n.colorfulGradient { return .restyle }
        if o != n { return .render }
        return .none
    }
}

extension DisplaySettings {
    /// Builds the layout configuration for a content area of `size` at media playback `rate`.
    public func layoutConfig(viewSize size: CGSize, rate: Double) -> LayoutConfig {
        let rateFactor = keepScreenSpeedOnRateChange ? max(rate, 0.1) : 1
        var scale = fontScale
        if scaleWithViewHeight { scale *= min(max(size.height / 720, 0.6), 2.5) }
        var area = size.height * min(max(displayArea, 0.1), 1)
        if protectSubtitles { area = min(area, size.height * (1 - min(max(subtitleSafeFraction, 0), 0.5))) }
        return LayoutConfig(
            viewSize: size,
            areaHeight: area,
            rollDurationMs: Int(rollDuration * 1000 * rateFactor),
            staticDurationMs: Int(staticDuration * 1000 * rateFactor),
            fontScale: scale,
            lineSpacing: lineSpacing,
            allowOverlap: allowOverlap,
            limits: limits)
    }
}
