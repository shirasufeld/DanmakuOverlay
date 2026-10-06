import DanmakuCore
import QuartzCore
import Testing

@testable import DanmakuOverlay

@MainActor
struct TimelineLayerTests {
    /// The container's local time must equal epoch + media time − offset for any anchor and rate.
    @Test(arguments: [0.0, 1.0, 1.5, 0.5])
    func localTimeTracksMediaTime(rate: Double) {
        let root = CALayer()
        let timeline = TimelineLayer()
        root.addSublayer(timeline)
        let now = CACurrentMediaTime()
        timeline.apply(anchor: Anchor(hostTime: now - 2, mediaTime: 100, rate: rate), userOffset: 0.5)

        let host = CACurrentMediaTime()
        let local = timeline.convertTime(host, from: nil)
        let expected = TimelineLayer.epoch + 100 + (host - (now - 2)) * rate - 0.5
        #expect(abs(local - expected) < 1e-3)
        #expect(abs(timeline.danmakuTime(at: host) - (expected - TimelineLayer.epoch)) < 1e-6)
    }

    @Test func pausedLayerIsFrozen() {
        let root = CALayer()
        let timeline = TimelineLayer()
        root.addSublayer(timeline)
        timeline.apply(anchor: Anchor(hostTime: CACurrentMediaTime(), mediaTime: 42, rate: 0), userOffset: 0)
        let a = timeline.convertTime(CACurrentMediaTime(), from: nil)
        let b = timeline.convertTime(CACurrentMediaTime() + 10, from: nil)
        #expect(a == b)
        #expect(abs(a - (TimelineLayer.epoch + 42)) < 1e-9)
    }
}

@MainActor
struct SyncHelpersTests {
    @Test func adapterChains() {
        let iina = TrackedTarget(windowID: 1, pid: 1, bundleID: PlayerCatalog.iina, appName: "IINA", title: "")
        #expect(AdapterRegistry.chain(for: iina, settings: SyncSettings()) == [.mpv, .nowPlaying, .manual])
        var s = SyncSettings()
        s.preferredAdapters[PlayerCatalog.iina] = .nowPlaying
        #expect(AdapterRegistry.chain(for: iina, settings: s) == [.nowPlaying, .mpv, .manual])
        let infuse = TrackedTarget(windowID: 1, pid: 1, bundleID: PlayerCatalog.infuse, appName: "Infuse", title: "")
        #expect(AdapterRegistry.chain(for: infuse, settings: SyncSettings()) == [.nowPlaying, .manual])
        let unknown = TrackedTarget(windowID: 1, pid: 1, bundleID: "com.example", appName: "X", title: "")
        #expect(AdapterRegistry.chain(for: unknown, settings: SyncSettings()) == [.nowPlaying, .manual])
        #expect(AdapterRegistry.chain(for: nil, settings: SyncSettings()) == [.manual])
        #expect(PlayerCatalog.isBrowser("com.google.Chrome"))
    }

    @Test func nowPlayingJumpDetection() {
        #expect(!NowPlayingSource.jumped(from: 10, at: 100, to: 15, at: 105, rate: 1))
        #expect(NowPlayingSource.jumped(from: 10, at: 100, to: 60, at: 105, rate: 1))
        #expect(!NowPlayingSource.jumped(from: 10, at: 100, to: 10, at: 105, rate: 0))
    }

    @Test func timeText() {
        #expect(TimeText.parse("90") == 90)
        #expect(TimeText.parse("1:30") == 90)
        #expect(TimeText.parse("1:02:03.5") == 3723.5)
        #expect(TimeText.parse("abc") == nil)
        #expect(TimeText.parse("-5") == nil)
        #expect(TimeText.format(3723.9) == "1:02:03")
        #expect(TimeText.format(65) == "1:05")
        #expect(TimeText.offset(0.5) == "+0.5 s")
    }

    @Test func mediaLibraryFindsSiblingDanmaku() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dmk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appending(path: "Episode 01.mkv")
        try Data().write(to: video)
        #expect(MediaLibrary.danmakuFile(for: MediaIdentity(path: video.path), libraryFolders: []) == nil)
        let xml = dir.appending(path: "Episode 01.danmaku.xml")
        try Data("<i/>".utf8).write(to: xml)
        #expect(MediaLibrary.danmakuFile(for: MediaIdentity(path: video.path), libraryFolders: [])?.path == xml.path)
        // A title-only identity (Now Playing) is matched in library folders.
        #expect(
            MediaLibrary.danmakuFile(for: MediaIdentity(title: "Episode 01.mkv"), libraryFolders: [dir.path])?.path
                == xml.path)
    }
}
