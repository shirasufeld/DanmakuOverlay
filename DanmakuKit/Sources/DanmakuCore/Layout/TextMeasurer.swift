import CoreGraphics

/// Measures the on-screen size of a danmaku bitmap. Implementations must return exactly the size the renderer
/// rasterizes (including stroke/shadow padding), otherwise collision avoidance drifts from what is drawn.
public protocol TextMeasurer: Sendable {
    /// Size in points of `text` rendered at `fontSize` points.
    func measure(_ text: String, fontSize: CGFloat) -> CGSize
}

/// A crude measurer for tests and fallbacks: CJK = 1 em, everything else = 0.5 em.
public struct EstimatingTextMeasurer: TextMeasurer {
    public var lineHeightFactor: CGFloat

    public init(lineHeightFactor: CGFloat = 1.2) { self.lineHeightFactor = lineHeightFactor }

    public func measure(_ text: String, fontSize: CGFloat) -> CGSize {
        var lines: [Double] = [0]
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                lines.append(0)
                continue
            }
            lines[lines.count - 1] += scalar.value >= 0x2E80 ? 1 : 0.5
        }
        let width = (lines.max() ?? 0) * fontSize
        return CGSize(width: width, height: CGFloat(lines.count) * fontSize * lineHeightFactor)
    }
}
