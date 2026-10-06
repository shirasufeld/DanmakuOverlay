import AppKit
import DanmakuCore
import DanmakuText
import Observation
import UniformTypeIdentifiers

/// Composition root: wires source → clock → pipeline → renderer → overlay.
@Observable
final class AppModel {
    enum OverlayMode: Equatable {
        case off
        /// Covers a fixed region (Cocoa screen coordinates) without following any window.
        case free(CGRect)
        /// Follows a player window.
        case following
    }

    let settings: SettingsStore
    let clock = PlaybackClock()
    let pipeline = PipelineController()
    let tracker = WindowTracker()

    private(set) var overlayMode = OverlayMode.off
    var danmakuVisible = true {
        didSet { updateVisibility() }
    }
    /// Danmaku area in Cocoa screen coordinates.
    private(set) var contentFrame: CGRect = .zero
    private(set) var renderStats = RenderStats()

    @ObservationIgnored let renderer: DanmakuRenderer
    @ObservationIgnored let overlay: OverlayWindowController
    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private let keyMirror = KeyMirror()
    @ObservationIgnored private(set) lazy var hud = ControlHUD(model: self)
    @ObservationIgnored private var layoutRate = 1.0
    @ObservationIgnored private var relayoutTask: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var autoLoadedURL: URL?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        let display = settings.settings.display
        renderer = DanmakuRenderer(style: Self.rasterStyle(display, scale: 2))
        overlay = OverlayWindowController(rootLayer: renderer.rootLayer)
        renderer.setOpacity(display.opacity)

        settings.onChange = { [weak self] old, new, impact in self?.settingsChanged(old, new, impact) }
        clock.onAnchor = { [weak self] anchor, offset, jump in
            guard let self else { return }
            self.renderer.apply(anchor: anchor, userOffset: offset)
            if jump { self.renderer.resync() }
            if anchor.rate > 0, abs(anchor.rate - self.layoutRate) > 0.01, !self.clockIsSlewing(anchor) {
                self.scheduleRelayout(delay: .milliseconds(100))
            }
        }
        renderer.onTick = { [weak self] in
            guard let self else { return }
            self.clock.tick()
            if self.renderStats != self.renderer.stats { self.renderStats = self.renderer.stats }
        }
        pipeline.onTimeline = { [weak self] timeline, items, size in
            guard let self else { return }
            self.renderer.load(timeline: timeline, items: items, viewSize: size)
        }
        overlay.onBackingScaleChange = { [weak self] scale in
            guard let self else { return }
            self.renderer.setStyle(Self.rasterStyle(self.settings.settings.display, scale: scale))
        }
        tracker.onSnapshot = { [weak self] snapshot in self?.apply(snapshot) }
        clock.onMediaChange = { [weak self] media in self?.mediaChanged(media) }
        clock.onGeometryChange = { [weak self] _ in
            guard let self, let snapshot = self.tracker.snapshot else { return }
            self.apply(snapshot)
        }
        hotkeys.onAction = { [weak self] action in self?.perform(action) }
        if settings.settings.general.hotkeysEnabled { hotkeys.enable() }
        keyMirror.onEvent = { [weak self] event in
            switch event {
            case .togglePlayPause: self?.togglePlayPause()
            case .step(let seconds): self?.step(seconds)
            }
        }
        renderer.start()
        attachManualSource()
    }

    func perform(_ action: HotkeyCenter.Action) {
        let sync = settings.settings.sync
        switch action {
        case .toggleDanmaku: danmakuVisible.toggle()
        case .playPause: togglePlayPause()
        case .seekBackward: step(-sync.seekStep)
        case .seekForward: step(sync.seekStep)
        case .offsetEarlier: adjustOffset(-sync.offsetStep)
        case .offsetLater: adjustOffset(sync.offsetStep)
        case .toggleControls: hud.toggle()
        case .attachFrontmost: followFrontmostPlayer()
        }
    }

    /// Mirrors the player's keys onto the manual clock when that is the active source.
    private func updateKeyMirror() {
        if clock.sourceKind == .manual, overlayMode == .following, settings.settings.sync.mirrorKeys,
            AXSupport.isTrusted, let pid = tracker.target?.pid
        {
            keyMirror.start(pid: pid, step: settings.settings.sync.seekStep)
        } else {
            keyMirror.stop()
        }
    }

    static func rasterStyle(_ d: DisplaySettings, scale: CGFloat) -> RasterStyle {
        RasterStyle(text: TextStyle(d), strokeColor: d.strokeColor, colorfulGradient: d.colorfulGradient, scale: scale)
    }

    /// Slewing changes the anchor rate by a few percent; that must not trigger a relayout.
    private func clockIsSlewing(_ anchor: Anchor) -> Bool {
        abs(anchor.rate - clock.nominalRate) > 1e-6 && clock.nominalRate > 0
    }

    // MARK: Sources

    /// Sync adapters that make sense for the current target, best first.
    var availableAdapters: [SourceKind] {
        AdapterRegistry.chain(for: tracker.target, settings: settings.settings.sync)
    }

    func attachManualSource() {
        attach(.manual, automatic: false)
    }

    /// Attaches a sync adapter. `automatic` attachments may fall back down the chain if the adapter cannot
    /// connect within a few seconds.
    func attach(_ kind: SourceKind, automatic: Bool) {
        fallbackTask?.cancel()
        let source = AdapterRegistry.make(
            kind, target: tracker.target, frameCG: tracker.snapshot?.frameCG, settings: settings.settings.sync,
            duration: pipeline.trackDuration)
        clock.attach(source)
        updateKeyMirror()
        if kind == .manual, overlayMode == .following, settings.settings.general.showControlsOnAttach { hud.show() }
        guard automatic, kind != .manual else { return }
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.clock.sourceKind == kind, !self.clock.status.isConnected else {
                return
            }
            let chain = self.availableAdapters
            if let i = chain.firstIndex(of: kind), i + 1 < chain.count {
                Log.sync.info("\(kind.rawValue) did not connect; falling back to \(chain[i + 1].rawValue)")
                self.attach(chain[i + 1], automatic: true)
            }
        }
    }

    /// User choice from the adapter menu; remembered per app.
    func chooseAdapter(_ kind: SourceKind) {
        if let bundle = tracker.target?.bundleID {
            settings.update { $0.sync.preferredAdapters[bundle] = kind }
        }
        attach(kind, automatic: false)
    }

    private func mediaChanged(_ media: MediaIdentity?) {
        guard let media else { return }
        clock.userOffset = MediaLibrary.offset(for: media) ?? 0
        let sync = settings.settings.sync
        guard sync.autoLoadMatchingDanmaku,
            let url = MediaLibrary.danmakuFile(for: media, libraryFolders: sync.libraryFolders),
            pipeline.descriptor != .localFile(url), autoLoadedURL != url
        else { return }
        autoLoadedURL = url
        Log.pipeline.info("Auto-loading \(url.lastPathComponent) for \(media.key ?? "")")
        openDanmakuFile(url)
    }

    // MARK: Danmaku files

    func openDanmakuFile(_ url: URL) {
        let source = LocalFileSource(url: url)
        Task {
            await pipeline.load(source, settings: settings.settings, viewSize: contentFrame.size, rate: layoutRate)
            if let manual = clock.source as? ManualSource {
                await manual.setDuration(pipeline.trackDuration)
            }
            if overlayMode == .off { useFreeMode() }
        }
    }

    func presentOpenPanel() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes =
            [.xml] + LocalFileSource.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "Choose a Bilibili danmaku file (.xml or protobuf .so)")
        if panel.runModal() == .OK, let url = panel.url { openDanmakuFile(url) }
    }

    // MARK: Overlay placement

    func useFreeMode(frame: CGRect? = nil) {
        if overlayMode == .following { attachManualSource() }
        tracker.stop()
        overlay.setOccluders([])
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let target = frame ?? screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        overlayMode = .free(target)
        setContentFrame(target)
        updateVisibility()
    }

    func turnOff() {
        keyMirror.stop()
        tracker.stop()
        overlayMode = .off
        overlay.setOccluders([])
        updateVisibility()
    }

    /// Attaches the overlay to a player window.
    func follow(_ candidate: CandidateWindow) {
        tracker.track(
            TrackedTarget(
                windowID: candidate.info.id, pid: candidate.info.pid, bundleID: candidate.bundleID,
                appName: candidate.appName, title: candidate.title))
        overlayMode = .following
        updateVisibility()
        attach(availableAdapters[0], automatic: true)
    }

    /// Follows the front-most window of a known player, if any.
    @discardableResult
    func followFrontmostPlayer() -> Bool {
        let candidates = WindowCatalog.candidates()
        guard let match = candidates.first(where: { PlayerCatalog.isKnownPlayer($0.bundleID) }) else { return false }
        follow(match)
        return true
    }

    private func apply(_ snapshot: TrackedSnapshot) {
        guard overlayMode == .following else { return }
        if snapshot.isVisible {
            let display = settings.settings.display
            let local = ContentRectResolver.contentRect(
                windowSize: snapshot.frameCG.size, fit: display.contentFit, geometry: clock.geometry, insets: .zero)
            let contentCG = local.offsetBy(dx: snapshot.frameCG.minX, dy: snapshot.frameCG.minY)
            setContentFrame(ScreenGeometry.cocoa(fromCG: contentCG))
            overlay.setOccluders(
                snapshot.occludersCG.map { $0.offsetBy(dx: -contentCG.minX, dy: -contentCG.minY) })
            overlay.setTransientlyHidden(display.hideWhileMoving && snapshot.isMoving)
        }
        updateVisibility()
    }

    /// Sets the danmaku area (Cocoa screen coordinates); relayouts when the size changes.
    func setContentFrame(_ frame: CGRect) {
        let sizeChanged = frame.size != contentFrame.size
        contentFrame = frame
        overlay.setFrame(frame)
        if sizeChanged { scheduleRelayout(delay: .milliseconds(150)) }
    }

    private var targetVisible: Bool {
        overlayMode != .following || (tracker.snapshot?.isVisible ?? false)
    }

    private func updateVisibility() {
        if overlayMode != .off, danmakuVisible, targetVisible {
            overlay.show()
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                    reason: "Rendering danmaku in sync with a player")
            }
        } else {
            overlay.hide()
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
        }
    }

    // MARK: Settings and layout

    private func settingsChanged(_ old: AppSettings, _ new: AppSettings, _ impact: SettingsImpact) {
        renderer.setOpacity(new.display.opacity)
        if old.general.hotkeysEnabled != new.general.hotkeysEnabled {
            new.general.hotkeysEnabled ? hotkeys.enable() : hotkeys.disable()
        }
        if old.sync.mirrorKeys != new.sync.mirrorKeys || old.sync.seekStep != new.sync.seekStep { updateKeyMirror() }
        switch impact {
        case .none, .render:
            break
        case .restyle:
            renderer.setStyle(Self.rasterStyle(new.display, scale: overlay.backingScale))
        case .relayout:
            renderer.setStyle(Self.rasterStyle(new.display, scale: overlay.backingScale))
            scheduleRelayout(delay: .milliseconds(200))
        case .refilter:
            renderer.setStyle(Self.rasterStyle(new.display, scale: overlay.backingScale))
            relayoutTask?.cancel()
            relayoutTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                self.pipeline.refilter(
                    settings: self.settings.settings, viewSize: self.contentFrame.size, rate: self.layoutRate)
            }
        }
    }

    private func scheduleRelayout(delay: Duration) {
        relayoutTask?.cancel()
        relayoutTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            if self.clock.nominalRate > 0 { self.layoutRate = self.clock.nominalRate }
            self.pipeline.relayout(
                settings: self.settings.settings, viewSize: self.contentFrame.size, rate: self.layoutRate)
        }
    }

    // MARK: Transport (manual clock and players that accept commands)

    func togglePlayPause() { clock.send(.togglePlayPause) }
    func seek(to seconds: Double) { clock.send(.seek(to: seconds)) }
    func step(_ seconds: Double) { clock.send(.step(by: seconds)) }
    func adjustOffset(_ delta: Double) { setOffset((clock.userOffset + delta).rounded(toPlaces: 3)) }
    func resetOffset() { setOffset(0) }

    private func setOffset(_ value: Double) {
        clock.userOffset = value
        if let media = clock.media { MediaLibrary.setOffset(value, for: media) }
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10, Double(places))
        return (self * p).rounded() / p
    }
}
