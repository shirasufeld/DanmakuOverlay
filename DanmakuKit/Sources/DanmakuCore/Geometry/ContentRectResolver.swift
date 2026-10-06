import CoreGraphics

/// How danmaku are fitted inside the target window.
public enum ContentFit: String, Sendable, Codable, CaseIterable {
    /// Cover the whole window (minus insets).
    case window
    /// Cover only the video picture (aspect-fit), when its size is known.
    case video
}

/// Insets in points.
public struct Insets: Sendable, Hashable, Codable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = Insets()
}

public enum ContentRectResolver {
    /// Rect, in window-local top-left coordinates, where danmaku should be drawn.
    public static func contentRect(
        windowSize: CGSize, fit: ContentFit, geometry: VideoGeometry?, insets: Insets
    ) -> CGRect {
        let base = CGRect(origin: .zero, size: windowSize)
        var rect = CGRect(
            x: insets.left, y: insets.top,
            width: max(windowSize.width - insets.left - insets.right, 0),
            height: max(windowSize.height - insets.top - insets.bottom, 0))
        guard fit == .video else { return rect }
        if let f = geometry?.contentFraction, f.width > 0.05, f.height > 0.05 {
            let reported = CGRect(
                x: f.minX * windowSize.width, y: f.minY * windowSize.height,
                width: f.width * windowSize.width, height: f.height * windowSize.height)
            return reported.intersection(base)
        }
        if let video = geometry?.videoSize, video.width > 0, video.height > 0 {
            rect = aspectFit(video, in: rect)
        }
        return rect
    }

    public static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
