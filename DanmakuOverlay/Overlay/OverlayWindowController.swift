import AppKit
import QuartzCore

/// Positions the overlay panel (Cocoa screen coordinates) and cuts out windows that cover the target.
final class OverlayWindowController {
    let panel = OverlayPanel()
    private let host: OverlayHostView
    private let rootLayer: CALayer
    private let maskLayer = CAShapeLayer()
    private(set) var isShown = false

    /// Called when the panel's backing scale changes (moved to another display).
    var onBackingScaleChange: ((CGFloat) -> Void)?
    private var scaleObserver: NSObjectProtocol?

    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        host = OverlayHostView(rootLayer: rootLayer)
        panel.contentView = host
        maskLayer.fillRule = .evenOdd
        scaleObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onBackingScaleChange?(self.backingScale)
            }
        }
    }

    var backingScale: CGFloat { panel.backingScaleFactor > 0 ? panel.backingScaleFactor : 2 }

    /// Moves the overlay to `frame` (Cocoa coordinates).
    func setFrame(_ frame: NSRect) {
        guard frame.width >= 1, frame.height >= 1 else { return }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    /// Hides quickly without ordering out (used while the target window is being dragged).
    func setTransientlyHidden(_ hidden: Bool) {
        panel.alphaValue = hidden ? 0 : 1
    }

    /// Masks out `occluders` (rects in panel-local, top-left coordinates) so the overlay appears behind them.
    func setOccluders(_ occluders: [CGRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if occluders.isEmpty {
            rootLayer.mask = nil
        } else {
            let bounds = CGRect(origin: .zero, size: panel.frame.size)
            let path = CGMutablePath()
            path.addRect(bounds)
            for r in occluders { path.addRect(r.intersection(bounds)) }
            maskLayer.frame = bounds
            maskLayer.path = path
            rootLayer.mask = maskLayer
        }
        CATransaction.commit()
    }
}
