import AppKit
import ApplicationServices
import Observation
import QuartzCore

struct TrackedTarget: Hashable {
    var windowID: CGWindowID
    var pid: pid_t
    var bundleID: String?
    var appName: String
    var title: String
}

struct TrackedSnapshot: Equatable {
    /// Window frame in CG global coordinates.
    var frameCG: CGRect
    /// On the active Space, not minimised, app not hidden.
    var isVisible: Bool
    var isFullScreen: Bool
    /// The frame changed within the last moments (dragging / resizing / full-screen transition).
    var isMoving: Bool
    /// Windows of other apps covering the target (CG coordinates).
    var occludersCG: [CGRect]
}

/// Follows one window: AX notifications (when trusted) and a 10 Hz window-server poll trigger a per-frame
/// display-link burst while the window moves.
@Observable
final class WindowTracker {
    private(set) var target: TrackedTarget?
    private(set) var snapshot: TrackedSnapshot?
    /// The target window disappeared (closed or app quit).
    private(set) var isLost = false

    @ObservationIgnored var onSnapshot: ((TrackedSnapshot) -> Void)?

    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var linkDriver: DisplayLinkDriver?
    @ObservationIgnored private var lastChange: CFTimeInterval = 0
    @ObservationIgnored private var lastFrame: CGRect?
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var axWindow: AXUIElement?
    @ObservationIgnored private var fullScreen = false
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []

    func track(_ target: TrackedTarget) {
        stop()
        self.target = target
        isLost = false
        installObservers(for: target)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopBurst()
        removeObservers()
        target = nil
        snapshot = nil
        lastFrame = nil
    }

    // MARK: Polling

    private func poll() {
        guard let target else { return }
        guard let info = WindowCatalog.info(for: target.windowID) else {
            if !isLost {
                isLost = true
                Log.tracking.info("Target window \(target.windowID) disappeared")
                publish(
                    TrackedSnapshot(
                        frameCG: .zero, isVisible: false, isFullScreen: false, isMoving: false, occludersCG: []))
            }
            return
        }
        let now = CACurrentMediaTime()
        if info.bounds != lastFrame {
            if lastFrame != nil { startBurst() }
            lastFrame = info.bounds
            lastChange = now
            if let axWindow { fullScreen = AXSupport.isFullScreen(axWindow) }
        }
        let moving = now - lastChange < 0.25
        let visible = info.isOnScreen && info.alpha > 0
        let occluders = visible ? WindowCatalog.occluders(above: target.windowID, bounds: info.bounds) : []
        publish(
            TrackedSnapshot(
                frameCG: info.bounds, isVisible: visible, isFullScreen: fullScreen, isMoving: moving,
                occludersCG: occluders))
        if !moving, displayLink != nil, now - lastChange > 0.3 { stopBurst() }
    }

    private func publish(_ s: TrackedSnapshot) {
        guard s != snapshot else { return }
        snapshot = s
        onSnapshot?(s)
    }

    // MARK: Burst following

    private func startBurst() {
        guard displayLink == nil else { return }
        let driver = DisplayLinkDriver { [weak self] in self?.poll() }
        let screen = lastFrame.flatMap { ScreenGeometry.screen(containingCG: $0) } ?? NSScreen.main
        guard let link = screen?.displayLink(target: driver, selector: #selector(DisplayLinkDriver.step(_:))) else {
            return
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        linkDriver = driver
    }

    private func stopBurst() {
        displayLink?.invalidate()
        displayLink = nil
        linkDriver = nil
    }

    // MARK: Notifications

    private func installObservers(for target: TrackedTarget) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        ] {
            workspaceTokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.poll() }
                })
        }
        workspaceTokens.append(
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                MainActor.assumeIsolated {
                    if pid == self?.target?.pid { self?.poll() }
                }
            })

        guard AXSupport.isTrusted,
            let element = AXSupport.element(
                forWindow: target.windowID, pid: target.pid, bounds: WindowCatalog.info(for: target.windowID)?.bounds)
        else { return }
        axWindow = element
        fullScreen = AXSupport.isFullScreen(element)

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                tracker.startBurst()
                tracker.poll()
            }
        }
        guard AXObserverCreate(target.pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [
            kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        ] {
            AXObserverAddNotification(created, element, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private func removeObservers() {
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        axWindow = nil
    }
}

/// Target for `CADisplayLink`, which needs an Objective-C selector.
final class DisplayLinkDriver: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func step(_ link: CADisplayLink) { handler() }
}
