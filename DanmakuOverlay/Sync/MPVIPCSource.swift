import DanmakuCore
import Foundation
import Network
import Synchronization

/// mpv JSON IPC over a Unix socket (`input-ipc-server`). Used for IINA and plain mpv. Exact: samples are
/// stamped on receipt of mpv's own property-change events.
actor MPVIPCSource: PlaybackSource {
    nonisolated let kind = SourceKind.mpv
    nonisolated let capabilities: SourceCapabilities = [
        .canSeek, .canPlayPause, .providesRate, .providesMediaPath, .providesGeometry,
    ]
    nonisolated let events: AsyncStream<SourceEvent>
    private let continuation: AsyncStream<SourceEvent>.Continuation

    let socketPath: String
    private var connection: NWConnection?
    private var loop: Task<Void, Never>?
    private var stopped = false
    private var buffer = Data()
    private var requestID = 100

    // Latest observed properties.
    private var timePos: Double?
    private var paused = true
    private var speed = 1.0
    private var duration: Double?
    private var path: String?
    private var title: String?
    private var videoSize: CGSize?
    private var osd: (w: Double, h: Double, ml: Double, mr: Double, mt: Double, mb: Double)?
    private var pendingDiscontinuity = true
    private var lastPublish = 0.0

    init(socketPath: String) {
        self.socketPath = socketPath
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }

    func start() {
        loop = Task { await self.run() }
    }

    func stop() {
        stopped = true
        loop?.cancel()
        connection?.cancel()
        continuation.finish()
    }

    func send(_ command: PlaybackCommand) throws {
        switch command {
        case .play: write(["set_property", "pause", false])
        case .pause: write(["set_property", "pause", true])
        case .togglePlayPause: write(["cycle", "pause"])
        case .seek(let t): write(["seek", t, "absolute+exact"])
        case .step(let d): write(["seek", d, "relative+exact"])
        case .setRate(let r): write(["set_property", "speed", r])
        }
    }

    // MARK: Connection loop

    private func run() async {
        while !stopped && !Task.isCancelled {
            if FileManager.default.fileExists(atPath: socketPath) {
                continuation.yield(.status(.connecting))
                await connectAndRead()
            }
            guard !stopped else { return }
            continuation.yield(
                .status(.needsSetup(String(localized: "Waiting for the player's IPC socket (\(socketPath))"))))
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func connectAndRead() async {
        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.connection = connection
        let ready = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let once = OnceFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.claim() { cont.resume(returning: true) }
                case .failed, .cancelled, .waiting: if once.claim() { cont.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        guard ready else {
            connection.cancel()
            return
        }
        pendingDiscontinuity = true
        for (id, name) in Self.observed.enumerated() { write(["observe_property", id + 1, name]) }
        continuation.yield(.status(.connected(detail: "mpv IPC")))

        while !stopped && !Task.isCancelled {
            guard let chunk = await receive(on: connection) else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                handle(line: Data(line))
            }
        }
        connection.cancel()
        self.connection = nil
        buffer.removeAll()
    }

    private func receive(on connection: NWConnection) async -> Data? {
        await withCheckedContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete || error != nil {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
    }

    private func write(_ command: [Any]) {
        guard let connection else { return }
        requestID += 1
        let payload: [String: Any] = ["command": command, "request_id": requestID]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: Messages

    static let observed = [
        "time-pos", "pause", "speed", "duration", "path", "media-title", "video-params", "osd-dimensions",
    ]

    private func handle(line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let event = json["event"] as? String
        else { return }
        let now = HostClock.now()
        switch event {
        case "property-change":
            guard let name = json["name"] as? String else { return }
            let value = json["data"]
            switch name {
            case "time-pos":
                timePos = (value as? NSNumber)?.doubleValue
                // Position changes every frame; four samples a second are plenty for the clock.
                if now - lastPublish < 0.25, !pendingDiscontinuity { return }
            case "pause": paused = (value as? Bool) ?? true
            case "speed": speed = (value as? NSNumber)?.doubleValue ?? 1
            case "duration": duration = (value as? NSNumber)?.doubleValue
            case "path":
                path = value as? String
                pendingDiscontinuity = true
            case "media-title": title = value as? String
            case "video-params":
                if let p = value as? [String: Any], let w = (p["dw"] as? NSNumber)?.doubleValue,
                    let h = (p["dh"] as? NSNumber)?.doubleValue, w > 0, h > 0
                {
                    videoSize = CGSize(width: w, height: h)
                } else {
                    videoSize = nil
                }
            case "osd-dimensions":
                if let o = value as? [String: Any] {
                    func v(_ k: String) -> Double { (o[k] as? NSNumber)?.doubleValue ?? 0 }
                    osd = (v("w"), v("h"), v("ml"), v("mr"), v("mt"), v("mb"))
                }
            default: break
            }
        case "seek", "playback-restart", "file-loaded":
            pendingDiscontinuity = true
            if event == "seek" { return }  // wait for playback-restart / the next time-pos
        case "end-file", "idle":
            timePos = nil
        default:
            return
        }
        publish(now: now)
    }

    private func publish(now: Double) {
        guard let timePos else { return }
        var geometry = VideoGeometry(videoSize: videoSize)
        if let o = osd, o.w > 0, o.h > 0 {
            geometry.contentFraction = CGRect(
                x: o.ml / o.w, y: o.mt / o.h, width: (o.w - o.ml - o.mr) / o.w, height: (o.h - o.mt - o.mb) / o.h)
        }
        continuation.yield(
            .state(
                PlaybackState(
                    position: timePos, rate: speed, isPlaying: !paused, hostTime: now, duration: duration,
                    media: MediaIdentity(path: path, title: title), geometry: geometry,
                    discontinuity: pendingDiscontinuity, precision: .exact)))
        pendingDiscontinuity = false
        lastPublish = now
    }
}

/// Resumes a continuation at most once from concurrent callbacks.
nonisolated final class OnceFlag: Sendable {
    private let state = Mutex(false)
    func claim() -> Bool {
        state.withLock { done in
            defer { done = true }; return !done
        }
    }
}
