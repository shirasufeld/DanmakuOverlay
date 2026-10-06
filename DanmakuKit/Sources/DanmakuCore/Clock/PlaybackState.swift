import CoreGraphics
import Foundation

/// Identifies what is being played, used to auto-load danmaku and remember offsets.
public struct MediaIdentity: Sendable, Hashable, Codable {
    public var path: String?
    public var title: String?

    public init(path: String? = nil, title: String? = nil) {
        self.path = path
        self.title = title
    }

    /// Stable key for per-media preferences.
    public var key: String? { path ?? title }
}

/// Where the video picture is drawn inside its window.
public struct VideoGeometry: Sendable, Hashable {
    /// Display size of the video in pixels, when known (gives the aspect ratio).
    public var videoSize: CGSize?
    /// Rect of the picture as a fraction of the window (top-left origin, 0…1), when the player reports it.
    public var contentFraction: CGRect?

    public init(videoSize: CGSize? = nil, contentFraction: CGRect? = nil) {
        self.videoSize = videoSize
        self.contentFraction = contentFraction
    }
}

public enum SamplePrecision: Sendable, Hashable {
    /// Position is exact at `hostTime` (mpv IPC, browser video element).
    case exact
    /// Position was extrapolated by the reporter (Now Playing).
    case extrapolated
    /// Position is quantised (VLC whole seconds) and refined by estimation.
    case coarse
}

/// A sample of the external player's playback state.
public struct PlaybackState: Sendable, Equatable {
    /// Media position in seconds at `hostTime`.
    public var position: Double
    /// Nominal playback rate while playing (1 = normal speed).
    public var rate: Double
    public var isPlaying: Bool
    /// `HostClock` time at which `position` was valid.
    public var hostTime: Double
    public var duration: Double?
    public var media: MediaIdentity?
    public var geometry: VideoGeometry?
    /// Seek or media change happened since the previous sample.
    public var discontinuity: Bool
    public var precision: SamplePrecision

    public init(
        position: Double, rate: Double = 1, isPlaying: Bool, hostTime: Double, duration: Double? = nil,
        media: MediaIdentity? = nil, geometry: VideoGeometry? = nil, discontinuity: Bool = false,
        precision: SamplePrecision = .exact
    ) {
        self.position = position
        self.rate = rate
        self.isPlaying = isPlaying
        self.hostTime = hostTime
        self.duration = duration
        self.media = media
        self.geometry = geometry
        self.discontinuity = discontinuity
        self.precision = precision
    }

    /// Effective speed of the media clock (0 when paused).
    public var effectiveRate: Double { isPlaying ? rate : 0 }

    /// Extrapolated media position at host time `t`.
    public func position(at t: Double) -> Double { position + (t - hostTime) * effectiveRate }
}
