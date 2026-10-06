import CoreGraphics
import Foundation

/// Bilibili mode-7 ("advanced") danmaku payload. Port of DanmakuPlayer's Models/AdvancedDanmaku.cs.
///
/// The payload is a JSON array:
/// `[x0, y0, "a0-a1", duration_s, text, zRotate_deg, yRotate_deg, x1, y1, action_ms, delay_ms,
///   outline, font, linearAccelerate, path]`. Numbers may be encoded as strings.
public struct AdvancedDanmaku: Sendable, Hashable {
    public var start: CGPoint
    public var end: CGPoint
    public var startOpacity: Double
    public var endOpacity: Double
    /// Total lifetime in milliseconds.
    public var durationMs: Int
    public var text: String
    /// Rotation around the screen normal, radians.
    public var zRotation: Double
    /// Rotation around the vertical axis, radians.
    public var yRotation: Double
    /// Duration of the movement in milliseconds.
    public var moveDurationMs: Int
    /// Delay before the movement starts, in milliseconds.
    public var moveDelayMs: Int
    public var outline: Bool
    public var fontName: String
    /// `true`: position follows s², otherwise 2s − s² (ease-out).
    public var linearAccelerate: Bool
    /// Coordinates are fractions of the stage when every coordinate is within [0, 1].
    public var isRelative: Bool

    /// Stage the absolute coordinates refer to (the classic Bilibili player size).
    public static let referenceStage = CGSize(width: 672, height: 438)

    public static func parse(_ payload: String) -> AdvancedDanmaku? {
        guard let data = payload.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any],
            array.count >= 5
        else { return nil }

        func number(_ i: Int) -> Double? {
            guard i < array.count else { return nil }
            switch array[i] {
            case let n as NSNumber: return n.doubleValue
            case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }
        func string(_ i: Int) -> String? {
            guard i < array.count else { return nil }
            switch array[i] {
            case let s as String: return s
            case let n as NSNumber: return n.stringValue
            default: return nil
            }
        }
        func bool(_ i: Int) -> Bool {
            guard i < array.count else { return false }
            switch array[i] {
            case let n as NSNumber: return n.doubleValue != 0
            case let s as String: return s == "true" || (Double(s) ?? 0) != 0
            default: return false
            }
        }

        guard let x0 = number(0), let y0 = number(1), let duration = number(3), duration > 0,
            let rawText = string(4)
        else { return nil }

        var a0 = 1.0
        var a1 = 1.0
        if let opacity = string(2) {
            let parts = opacity.split(separator: "-").compactMap { Double($0) }
            if parts.count >= 1 { a0 = parts[0] }
            a1 = parts.count >= 2 ? parts[1] : a0
        }
        let x1 = number(7) ?? x0
        let y1 = number(8) ?? y0
        let durationMs = Int(duration * 1000)
        let moveMs = number(9).map { Int($0) } ?? durationMs
        let delayMs = number(10).map { Int($0) } ?? 0
        let relative = [x0, y0, x1, y1].allSatisfy { $0 >= 0 && $0 <= 1 }

        return AdvancedDanmaku(
            start: CGPoint(x: x0, y: y0),
            end: CGPoint(x: x1, y: y1),
            startOpacity: min(max(a0, 0), 1),
            endOpacity: min(max(a1, 0), 1),
            durationMs: durationMs,
            text: rawText.replacingOccurrences(of: "/n", with: "\n"),
            zRotation: (number(5) ?? 0) * .pi / 180,
            yRotation: (number(6) ?? 0) * .pi / 180,
            moveDurationMs: max(moveMs, 0),
            moveDelayMs: max(delayMs, 0),
            outline: bool(11),
            fontName: string(12)?.trimmingCharacters(in: .whitespaces) ?? "",
            linearAccelerate: bool(13),
            isRelative: relative
        )
    }

    /// Maps a stage coordinate to view coordinates (top-left origin).
    public func viewPoint(_ p: CGPoint, in viewSize: CGSize) -> CGPoint {
        if isRelative {
            return CGPoint(x: p.x * viewSize.width, y: p.y * viewSize.height)
        }
        let transform = Self.stageTransform(for: viewSize)
        return CGPoint(x: p.x * transform.scale + transform.offset.x, y: p.y * transform.scale + transform.offset.y)
    }

    /// Aspect-fit transform from the reference stage into the view.
    public static func stageTransform(for viewSize: CGSize) -> (scale: Double, offset: CGPoint) {
        let scale = min(viewSize.width / referenceStage.width, viewSize.height / referenceStage.height)
        let offset = CGPoint(
            x: (viewSize.width - referenceStage.width * scale) / 2,
            y: (viewSize.height - referenceStage.height * scale) / 2)
        return (scale, offset)
    }

    /// Movement progress in [0, 1] after easing, at `ms` since the danmaku appeared.
    public func movementProgress(atMs ms: Int) -> Double {
        let t = ms - moveDelayMs
        if t <= 0 { return 0 }
        if moveDurationMs <= 0 || t >= moveDurationMs { return 1 }
        let s = Double(t) / Double(moveDurationMs)
        return linearAccelerate ? s * s : 2 * s - s * s
    }

    /// Stage position at `ms` since the danmaku appeared.
    public func position(atMs ms: Int) -> CGPoint {
        let k = movementProgress(atMs: ms)
        return CGPoint(x: start.x + (end.x - start.x) * k, y: start.y + (end.y - start.y) * k)
    }

    /// Opacity at `ms` since the danmaku appeared (linear over the whole lifetime).
    public func opacity(atMs ms: Int) -> Double {
        let s = min(max(Double(ms) / Double(max(durationMs, 1)), 0), 1)
        return startOpacity + (endOpacity - startOpacity) * s
    }
}
