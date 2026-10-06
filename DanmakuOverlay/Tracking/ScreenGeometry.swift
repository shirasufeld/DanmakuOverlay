import AppKit

/// Conversions between Core Graphics global coordinates (top-left origin at the primary display) and Cocoa
/// screen coordinates (bottom-left origin).
enum ScreenGeometry {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
    }

    static func cocoa(fromCG r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cg(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The screen showing most of `cgRect`.
    static func screen(containingCG cgRect: CGRect) -> NSScreen? {
        let r = cocoa(fromCG: cgRect)
        return NSScreen.screens.max { a, b in
            a.frame.intersection(r).area < b.frame.intersection(r).area
        }
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
