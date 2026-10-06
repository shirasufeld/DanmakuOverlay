import CoreGraphics
import CoreText
import DanmakuCore
import Foundation

/// Everything that determines a danmaku bitmap.
public struct GlyphKey: Sendable, Hashable {
    public var text: String
    public var fontSize: CGFloat
    /// 0xRRGGBB.
    public var color: UInt32
    public var colorful: Bool
    /// Overrides the style's font (mode-7 payloads may name a font).
    public var fontName: String?
    public var outlineOverride: Bool?

    public init(
        text: String, fontSize: CGFloat, color: UInt32, colorful: Bool = false, fontName: String? = nil,
        outlineOverride: Bool? = nil
    ) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.colorful = colorful
        self.fontName = fontName
        self.outlineOverride = outlineOverride
    }
}

/// Appearance shared by all bitmaps of one render pass.
public struct RasterStyle: Sendable, Hashable {
    public var text: TextStyle
    /// 0xRRGGBB.
    public var strokeColor: UInt32
    public var colorfulGradient: Bool
    /// Device pixels per point.
    public var scale: CGFloat

    public init(text: TextStyle, strokeColor: UInt32, colorfulGradient: Bool, scale: CGFloat) {
        self.text = text
        self.strokeColor = strokeColor
        self.colorfulGradient = colorfulGradient
        self.scale = scale
    }
}

public struct GlyphImage: Sendable {
    public let image: CGImage
    /// Size in points.
    public let size: CGSize
    public var byteCount: Int { image.bytesPerRow * image.height }
}

public enum DanmakuRasterizer {
    /// Bilibili's VIP gradient.
    static let gradientColors: [CGColor] = [
        CGColor(srgbRed: 0xF2 / 255, green: 0x50 / 255, blue: 0x9E / 255, alpha: 1),
        CGColor(srgbRed: 0x30 / 255, green: 0x8B / 255, blue: 0xCD / 255, alpha: 1),
    ]

    public static func render(_ key: GlyphKey, style: RasterStyle) -> GlyphImage? {
        var textStyle = style.text
        if let override = key.outlineOverride {
            textStyle.outline = override ? .stroke : .shadow
            if override, textStyle.strokeWidth <= 0 { textStyle.strokeWidth = 1 }
        }
        let layout = TextLayoutCore.layout(key.text, fontSize: key.fontSize, style: textStyle, fontName: key.fontName)
        let scale = max(style.scale, 1)
        let pixelWidth = Int(ceil(layout.size.width * scale))
        let pixelHeight = Int(ceil(layout.size.height * scale))
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth < 16384, pixelHeight < 16384,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.textMatrix = .identity

        let fill = color(key.color, alpha: 1)
        let strokeColor = Self.strokeColor(for: key.color, preferred: style.strokeColor)

        func drawLines(_ mode: CGTextDrawingMode) {
            ctx.setTextDrawingMode(mode)
            for (i, line) in layout.lines.enumerated() {
                let baseline = layout.size.height - layout.padding - layout.ascent - CGFloat(i) * layout.lineHeight
                ctx.textPosition = CGPoint(x: layout.padding, y: baseline)
                CTLineDraw(line, ctx)
            }
        }

        if textStyle.hasStroke {
            ctx.setLineJoin(.round)
            ctx.setLineWidth(textStyle.strokeWidth * 2)
            ctx.setStrokeColor(strokeColor)
            drawLines(.stroke)
        }

        ctx.saveGState()
        if textStyle.hasShadow {
            ctx.setShadow(offset: CGSize(width: 1, height: -1), blur: 3, color: color(style.strokeColor, alpha: 0.9))
        }
        if key.colorful && style.colorfulGradient {
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawLines(.clip)
            if let gradient = CGGradient(colorsSpace: space, colors: gradientColors as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(
                    gradient, start: CGPoint(x: layout.padding, y: 0),
                    end: CGPoint(x: layout.size.width - layout.padding, y: 0), options: [])
            }
            ctx.endTransparencyLayer()
        } else {
            ctx.setFillColor(fill)
            drawLines(.fill)
        }
        ctx.restoreGState()

        guard let image = ctx.makeImage() else { return nil }
        return GlyphImage(image: image, size: layout.size)
    }

    static func color(_ rgb: UInt32, alpha: CGFloat) -> CGColor {
        CGColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }

    static func luminance(_ rgb: UInt32) -> CGFloat {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Dark text on a dark outline is unreadable; flip the outline to light in that case.
    static func strokeColor(for text: UInt32, preferred: UInt32) -> CGColor {
        if luminance(text) < 0.25, luminance(preferred) < 0.5 { return color(0xFFFFFF, alpha: 0.8) }
        return color(preferred, alpha: 0.75)
    }
}
