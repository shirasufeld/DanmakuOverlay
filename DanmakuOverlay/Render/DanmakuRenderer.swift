import AppKit
import DanmakuCore
import DanmakuText
import QuartzCore

/// Statistics shown in the HUD.
struct RenderStats: Equatable {
    var liveLayers = 0
    var cachedImages = 0
    var cacheMegabytes = 0.0
}

/// Core Animation danmaku renderer: keeps CALayers only for danmaku on screen or about to appear and lets the
/// render server animate them.
final class DanmakuRenderer {
    let rootLayer = CALayer()
    let timelineLayer = TimelineLayer()

    private(set) var timeline = PlacedTimeline.empty
    private var items: [Danmaku] = []
    private(set) var viewSize = CGSize.zero
    private var live: [Int: CALayer] = [:]
    private var pool: [CALayer] = []
    private let cache: GlyphCache
    private var timer: Timer?
    private var backingScale: CGFloat = 2

    /// Called every scheduler tick (≈4 Hz) before scheduling; lets the clock finish slews.
    var onTick: (() -> Void)?

    /// Maximum simultaneous layers; beyond this the newest danmaku are skipped.
    var maxLiveLayers = 800
    private(set) var stats = RenderStats()

    init(style: RasterStyle) {
        cache = GlyphCache(style: style)
        rootLayer.isGeometryFlipped = true
        rootLayer.addSublayer(timelineLayer)
        timelineLayer.anchorPoint = .zero
    }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Inputs

    /// Replaces the timeline (after a load, filter or layout change) and rebuilds what is on screen.
    func load(timeline: PlacedTimeline, items: [Danmaku], viewSize: CGSize) {
        self.timeline = timeline
        self.items = items
        setViewSize(viewSize)
        resync()
    }

    func setViewSize(_ size: CGSize) {
        guard size != viewSize else { return }
        viewSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.bounds = CGRect(origin: .zero, size: size)
        timelineLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()
    }

    func apply(anchor: Anchor, userOffset: Double) {
        timelineLayer.apply(anchor: anchor, userOffset: userOffset)
    }

    func setOpacity(_ opacity: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timelineLayer.opacity = Float(opacity)
        CATransaction.commit()
    }

    func setStyle(_ style: RasterStyle) {
        backingScale = style.scale
        cache.setStyle(style)
        resync()
    }

    /// Drops every live layer and schedules from scratch (after seeks and layout changes).
    func resync() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (_, layer) in live { recycle(layer) }
        live.removeAll()
        CATransaction.commit()
        tick()
    }

    // MARK: Scheduling

    func tick() {
        onTick?()
        guard !timeline.items.isEmpty, viewSize.width > 0 else {
            updateStats()
            return
        }
        let now = timelineLayer.danmakuTime()
        let ms = Int(now * 1000)
        let rate = max(abs(timelineLayer.anchor.rate), 1)
        let lookaheadMs = Int(max(2.0, 1.5 * rate) * 1000)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Remove finished danmaku and those far in the future (left over from a backward jump).
        for (index, layer) in live {
            let p = timeline.items[index]
            if p.endMs < ms - 500 || p.startMs > ms + 2 * lookaheadMs {
                recycle(layer)
                live[index] = nil
            }
        }

        var wanted = timeline.activeIndices(at: ms)
        wanted.append(contentsOf: timeline.indices(startingIn: (ms + 1)..<(ms + lookaheadMs)))
        for index in wanted where live[index] == nil {
            guard live.count < maxLiveLayers else { break }
            if let layer = makeLayer(for: index) {
                timelineLayer.addSublayer(layer)
                live[index] = layer
            }
        }
        CATransaction.commit()

        // Rasterize what comes next in the background.
        let ahead = timeline.indices(startingIn: (ms + lookaheadMs)..<(ms + lookaheadMs + 4000))
        cache.prefetch(ahead.prefix(300).compactMap { glyphKey(for: $0) })
        updateStats()
    }

    private func glyphKey(for index: Int) -> GlyphKey? {
        let p = timeline.items[index]
        guard p.sourceIndex < items.count else { return nil }
        let d = items[p.sourceIndex]
        if p.kind == .advanced, let a = d.advanced {
            let scale =
                a.isRelative
                ? min(
                    viewSize.width / AdvancedDanmaku.referenceStage.width,
                    viewSize.height / AdvancedDanmaku.referenceStage.height)
                : AdvancedDanmaku.stageTransform(for: viewSize).scale
            return GlyphKey(
                text: a.text, fontSize: (CGFloat(d.fontSize) * scale).rounded(), color: d.color, colorful: d.colorful,
                fontName: a.fontName.isEmpty ? nil : a.fontName, outlineOverride: a.outline)
        }
        return GlyphKey(text: d.text, fontSize: p.fontSize, color: d.color, colorful: d.colorful)
    }

    private func makeLayer(for index: Int) -> CALayer? {
        guard let key = glyphKey(for: index), let image = cache.image(for: key) else { return nil }
        let p = timeline.items[index]
        let layer = pool.popLast() ?? Self.newLayer()
        layer.contents = image.image
        layer.contentsScale = backingScale
        layer.bounds = CGRect(origin: .zero, size: image.size)
        layer.opacity = 0
        layer.transform = CATransform3DIdentity
        if p.kind == .advanced, let a = items[p.sourceIndex].advanced {
            AnimationFactory.configureAdvanced(layer, placed: p, advanced: a, viewSize: viewSize)
        } else {
            AnimationFactory.configure(layer, placed: p, viewWidth: viewSize.width)
        }
        return layer
    }

    private static func newLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.contentsGravity = .resize
        layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "opacity": NSNull()]
        return layer
    }

    private func recycle(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        layer.contents = nil
        if pool.count < 400 { pool.append(layer) }
    }

    private func updateStats() {
        stats = RenderStats(
            liveLayers: live.count, cachedImages: cache.count,
            cacheMegabytes: Double(cache.byteCount) / 1_048_576)
    }
}
