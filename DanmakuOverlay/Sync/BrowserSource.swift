import CoreGraphics
import DanmakuCore
import Foundation

/// The largest `<video>` element in a browser window (Safari and Chromium browsers), via Apple Events.
actor BrowserSource: PlaybackSource {
    nonisolated let kind = SourceKind.browser
    nonisolated let capabilities: SourceCapabilities = [.providesRate, .providesGeometry]
    nonisolated let events: AsyncStream<SourceEvent>
    private let continuation: AsyncStream<SourceEvent>.Continuation

    private let bundleID: String
    private let windowID: CGWindowID
    private let windowBounds: CGRect
    private var helper: ScriptHelper?
    private var reader: Task<Void, Never>?
    private var lastHref: String?
    private var last: (position: Double, host: Double, rate: Double)?

    init(bundleID: String, windowID: CGWindowID, windowBounds: CGRect) {
        self.bundleID = bundleID
        self.windowID = windowID
        self.windowBounds = windowBounds
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
    }

    func start() {
        let b = windowBounds
        do {
            let helper = try ScriptHelper(
                script: "browser",
                arguments: [bundleID, String(windowID)] + [b.minX, b.minY, b.width, b.height].map { String(Int($0)) })
            self.helper = helper
            continuation.yield(.status(.connecting))
            reader = Task { [weak self] in
                for await line in helper.lines {
                    guard let self else { return }
                    await self.handle(line: line)
                }
            }
        } catch {
            continuation.yield(.status(.unavailable(error.localizedDescription)))
        }
    }

    func stop() {
        reader?.cancel()
        helper?.terminate()
        helper = nil
        continuation.finish()
    }

    func send(_ command: PlaybackCommand) throws {
        throw PlaybackCommandError.unsupported
    }

    private struct Video: Decodable {
        var t: Double
        var p: Bool
        var r: Double
        var d: Double?
        var href: String?
        var title: String?
        var x, y, w, h: Double
        var vw, vh: Double
        var iw, ih, ow, oh: Double
        var fs: Bool
    }

    private struct Line: Decodable {
        var video: Video?
        var at: Double?
        var rtt: Double?
        var error: String?
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8), let l = try? JSONDecoder().decode(Line.self, from: data) else {
            return
        }
        if let error = l.error {
            continuation.yield(.status(status(forError: error)))
            return
        }
        guard let v = l.video, let at = l.at else {
            continuation.yield(.status(.needsSetup(String(localized: "No video found in the current tab"))))
            return
        }
        // Round trips above 150 ms make the timestamp too uncertain; skip those samples.
        if let rtt = l.rtt, rtt > 0.15 { return }
        let host = ScriptHelper.hostTime(fromWall: at)

        var discontinuity = v.href != lastHref
        lastHref = v.href
        if let last, !discontinuity {
            let expected = last.position + (host - last.host) * (v.p ? 0 : last.rate)
            discontinuity = abs(expected - v.t) > 1.5
        }
        last = (v.t, host, v.p ? 0 : v.r)

        var geometry = VideoGeometry(videoSize: v.vw > 0 ? CGSize(width: v.vw, height: v.vh) : nil)
        if v.ow > 0, v.oh > 0, v.w > 0, v.h > 0 {
            let chrome = v.fs ? 0 : max(v.oh - v.ih, 0)
            geometry.contentFraction = CGRect(
                x: v.x / v.ow, y: (chrome + v.y) / v.oh, width: v.w / v.ow, height: v.h / v.oh)
        }
        continuation.yield(.status(.connected(detail: v.title ?? "")))
        continuation.yield(
            .state(
                PlaybackState(
                    position: v.t, rate: v.r > 0 ? v.r : 1, isPlaying: !v.p, hostTime: host,
                    duration: (v.d?.isFinite ?? false) ? v.d : nil,
                    media: MediaIdentity(path: nil, title: v.title), geometry: geometry,
                    discontinuity: discontinuity, precision: .exact)))
    }

    private func status(forError text: String) -> SourceStatus {
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not allowed to send") {
            return .needsPermission(.automation(bundleID: bundleID))
        }
        if text.localizedCaseInsensitiveContains("JavaScript") || text.contains("-1728") || text.contains("-2700") {
            return .needsPermission(.browserJavaScript(bundleID: bundleID))
        }
        return .unavailable(text)
    }
}
