import DanmakuCore
import QuartzCore

/// Builds the Core Animation description of one danmaku, in timeline-layer local time.
enum AnimationFactory {
    static let groupKey = "danmaku"

    /// Exact cubic-Bézier forms of the M7 easings: s² and 2s − s².
    static let easeInQuad = CAMediaTimingFunction(controlPoints: 1.0 / 3, 0, 2.0 / 3, 1.0 / 3)
    static let easeOutQuad = CAMediaTimingFunction(controlPoints: 1.0 / 3, 2.0 / 3, 2.0 / 3, 1)

    /// Configures `layer` (bounds already set, anchor at top-left) for a normal danmaku.
    static func configure(_ layer: CALayer, placed p: PlacedDanmaku, viewWidth: CGFloat) {
        let begin = TimelineLayer.localTime(forDanmakuSeconds: Double(p.startMs) / 1000)
        let duration = Double(p.durationMs) / 1000
        let width = layer.bounds.width

        let group = CAAnimationGroup()
        group.beginTime = begin
        group.duration = duration
        group.isRemovedOnCompletion = false
        group.fillMode = .removed

        let visible = CABasicAnimation(keyPath: "opacity")
        visible.fromValue = 1
        visible.toValue = 1
        visible.duration = duration

        switch p.kind {
        case .roll, .inverse:
            let from = p.kind == .roll ? viewWidth : -width
            let to = p.kind == .roll ? -width : viewWidth
            layer.position = CGPoint(x: from, y: p.y)
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = from
            move.toValue = to
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(name: .linear)
            group.animations = [move, visible]
        default:
            layer.position = CGPoint(x: ((viewWidth - width) / 2).rounded(), y: p.y)
            group.animations = [visible]
        }
        layer.add(group, forKey: groupKey)
    }

    /// Configures `layer` for a mode-7 danmaku.
    static func configureAdvanced(
        _ layer: CALayer, placed p: PlacedDanmaku, advanced a: AdvancedDanmaku, viewSize: CGSize
    ) {
        let begin = TimelineLayer.localTime(forDanmakuSeconds: Double(p.startMs) / 1000)
        let duration = Double(max(a.durationMs, 1)) / 1000
        let start = a.viewPoint(a.start, in: viewSize)
        let end = a.viewPoint(a.end, in: viewSize)

        layer.position = start
        var transform = CATransform3DIdentity
        if a.yRotation != 0 { transform.m34 = -1 / max(viewSize.width, 500) }
        transform = CATransform3DRotate(transform, a.yRotation, 0, 1, 0)
        transform = CATransform3DRotate(transform, a.zRotation, 0, 0, 1)
        layer.transform = transform

        let group = CAAnimationGroup()
        group.beginTime = begin
        group.duration = duration
        group.isRemovedOnCompletion = false
        group.fillMode = .removed

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = a.startOpacity
        fade.toValue = a.endOpacity
        fade.duration = duration

        var animations: [CAAnimation] = [fade]
        if start != end {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = start
            move.toValue = end
            move.beginTime = Double(a.moveDelayMs) / 1000
            move.duration = max(Double(a.moveDurationMs) / 1000, 0.001)
            move.timingFunction = a.linearAccelerate ? easeInQuad : easeOutQuad
            move.fillMode = .both
            animations.append(move)
        }
        group.animations = animations
        layer.add(group, forKey: groupKey)
    }
}
