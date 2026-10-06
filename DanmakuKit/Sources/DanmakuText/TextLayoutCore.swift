import CoreGraphics
import CoreText
import DanmakuCore
import Foundation
import Synchronization

/// Typography shared by measuring and rasterizing. Both go through `TextLayoutCore.layout(...)` so the size
/// used for collision avoidance is exactly the size of the drawn bitmap.
public struct TextStyle: Sendable, Hashable {
    public var fontName: String
    public var weight: FontWeightOption
    public var outline: OutlineStyle
    public var strokeWidth: CGFloat

    public init(fontName: String, weight: FontWeightOption, outline: OutlineStyle, strokeWidth: CGFloat) {
        self.fontName = fontName
        self.weight = weight
        self.outline = outline
        self.strokeWidth = strokeWidth
    }

    public init(_ display: DisplaySettings) {
        self.init(
            fontName: display.fontName, weight: display.fontWeight, outline: display.outline,
            strokeWidth: display.strokeWidth)
    }

    var hasStroke: Bool { (outline == .stroke || outline == .strokeAndShadow) && strokeWidth > 0 }
    var hasShadow: Bool { outline == .shadow || outline == .strokeAndShadow }

    /// Empty space around the glyphs for the stroke and shadow.
    var padding: CGFloat {
        var p: CGFloat = 1
        if hasStroke { p = max(p, ceil(strokeWidth) + 1) }
        if hasShadow { p = max(p, 4) }
        return p
    }
}

/// Laid-out text: lines plus metrics in points.
struct TextLayout {
    var lines: [CTLine]
    var lineWidths: [CGFloat]
    var ascent: CGFloat
    var lineHeight: CGFloat
    var padding: CGFloat
    var size: CGSize
}

enum TextLayoutCore {
    private struct FontKey: Hashable {
        var name: String
        var weight: FontWeightOption
        var size: CGFloat
    }

    /// CTFont is immutable and documented thread-safe.
    private struct FontBox: @unchecked Sendable { let font: CTFont }

    private static let fontCache = Mutex<[FontKey: FontBox]>([:])

    static func font(name: String, weight: FontWeightOption, size: CGFloat) -> CTFont {
        let key = FontKey(name: name, weight: weight, size: size)
        if let cached = fontCache.withLock({ $0[key] }) { return cached.font }
        let box = FontBox(font: makeFont(name: name, weight: weight, size: size))
        fontCache.withLock { cache in
            if cache.count > 256 { cache.removeAll() }
            cache[key] = box
        }
        return box.font
    }

    static func weightValue(_ w: FontWeightOption) -> CGFloat {
        switch w {
        case .regular: 0
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        }
    }

    private static func makeFont(name: String, weight: FontWeightOption, size: CGFloat) -> CTFont {
        let traits: [CFString: Any] = [kCTFontWeightTrait: weightValue(weight)]
        let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: name, kCTFontTraitsAttribute: traits]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let family = CTFontCopyFamilyName(font) as String
        if family.caseInsensitiveCompare(name) == .orderedSame || name.isEmpty == false && family.contains(name) {
            return font
        }
        // Unknown family (e.g. a font only in M7 payloads): use the system UI font with the requested weight.
        let system =
            CTFontCreateUIFontForLanguage(.system, size, "zh-Hans" as CFString)
            ?? CTFontCreateWithName("PingFang SC" as CFString, size, nil)
        let systemDescriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(system), [kCTFontTraitsAttribute: traits] as CFDictionary)
        return CTFontCreateWithFontDescriptor(systemDescriptor, size, nil)
    }

    static func layout(_ text: String, fontSize: CGFloat, style: TextStyle, fontName: String? = nil) -> TextLayout {
        let font = font(name: fontName ?? style.fontName, weight: style.weight, size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [CTLine] = []
        var widths: [CGFloat] = []
        for raw in rawLines {
            let line = CTLineCreateWithAttributedString(attributed(String(raw), font: font, attributes: attributes))
            lines.append(line)
            widths.append(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        let ascent = CTFontGetAscent(font)
        let lineHeight = ceil(ascent + CTFontGetDescent(font) + CTFontGetLeading(font))
        let padding = style.padding
        let width = ceil(widths.max() ?? 0) + padding * 2
        let height = lineHeight * CGFloat(max(lines.count, 1)) + padding * 2
        return TextLayout(
            lines: lines, lineWidths: widths, ascent: ascent, lineHeight: lineHeight, padding: padding,
            size: CGSize(width: width, height: height))
    }
}

extension TextLayoutCore {
    /// CJK fonts lack the subscript digits used for merge counts (₍₁₂₎); the fallback font draws them
    /// full-size. Draw them with the system font, which has proper subscript glyphs.
    fileprivate static func attributed(
        _ text: String, font: CTFont, attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        let ns = text as NSString
        var location = 0
        while location < ns.length {
            let c = ns.character(at: location)
            if (0x2080...0x208F).contains(c) {
                var end = location + 1
                while end < ns.length, (0x2080...0x208F).contains(ns.character(at: end)) { end += 1 }
                let system = CTFontCreateUIFontForLanguage(.system, CTFontGetSize(font), nil) ?? font
                result.addAttribute(
                    NSAttributedString.Key(kCTFontAttributeName as String), value: system,
                    range: NSRange(location: location, length: end - location))
                location = end
            } else {
                location += 1
            }
        }
        return result
    }
}

/// Measures danmaku with Core Text; thread-safe.
public struct CoreTextMeasurer: TextMeasurer {
    public let style: TextStyle

    public init(style: TextStyle) { self.style = style }

    public func measure(_ text: String, fontSize: CGFloat) -> CGSize {
        TextLayoutCore.layout(text, fontSize: fontSize, style: style).size
    }
}
