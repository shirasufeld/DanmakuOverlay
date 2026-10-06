import Foundation

/// Kinds of playback sources; also the persisted identifier of a sync adapter.
public enum SourceKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case manual
    case mpv
    case vlc
    case browser
    case nowPlaying

    public var id: String { rawValue }
}

public enum PermissionKind: Sendable, Hashable {
    case accessibility
    case automation(bundleID: String)
    case browserJavaScript(bundleID: String)
}

public enum SourceStatus: Sendable, Equatable {
    case idle
    case connecting
    case connected(detail: String)
    case needsPermission(PermissionKind)
    case needsSetup(String)
    case unavailable(String)
}

public enum SourceEvent: Sendable {
    case state(PlaybackState)
    case status(SourceStatus)
}

public struct SourceCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let canSeek = SourceCapabilities(rawValue: 1 << 0)
    public static let canPlayPause = SourceCapabilities(rawValue: 1 << 1)
    public static let providesMediaPath = SourceCapabilities(rawValue: 1 << 2)
    public static let providesGeometry = SourceCapabilities(rawValue: 1 << 3)
    public static let providesRate = SourceCapabilities(rawValue: 1 << 4)
}

public enum PlaybackCommand: Sendable, Equatable {
    case play
    case pause
    case togglePlayPause
    case seek(to: Double)
    case step(by: Double)
    case setRate(Double)
}

/// A provider of playback state for one external player. Implementations are actors; events are delivered
/// through a single `AsyncStream` consumed by the playback clock.
public protocol PlaybackSource: AnyObject, Sendable {
    nonisolated var kind: SourceKind { get }
    nonisolated var capabilities: SourceCapabilities { get }
    nonisolated var events: AsyncStream<SourceEvent> { get }

    func start() async
    func stop() async
    func send(_ command: PlaybackCommand) async throws
}

public enum PlaybackCommandError: Error {
    case unsupported
    case failed(String)
}
