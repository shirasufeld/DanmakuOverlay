import DanmakuCore
import Foundation

/// Creates sync sources for a followed window.
enum AdapterRegistry {
    /// Adapters to offer for `target`, best first; Manual is always last.
    static func chain(for target: TrackedTarget?, settings: SyncSettings) -> [SourceKind] {
        var kinds = target?.bundleID.map(PlayerCatalog.adapters(for:)) ?? []
        if let bundle = target?.bundleID, let preferred = settings.preferredAdapters[bundle] {
            kinds.removeAll { $0 == preferred }
            kinds.insert(preferred, at: 0)
        }
        if target != nil, !kinds.contains(.nowPlaying) { kinds.append(.nowPlaying) }
        kinds.append(.manual)
        return kinds
    }

    static func make(
        _ kind: SourceKind, target: TrackedTarget?, frameCG: CGRect?, settings: SyncSettings, duration: Double?
    ) -> any PlaybackSource {
        switch kind {
        case .manual: ManualSource(duration: duration)
        case .mpv: MPVIPCSource(socketPath: settings.mpvSocketPath)
        case .vlc: VLCSource(roundsSeconds: settings.vlcRoundsSeconds)
        case .nowPlaying: NowPlayingSource(expectedBundleID: target?.bundleID)
        case .browser:
            BrowserSource(
                bundleID: target?.bundleID ?? PlayerCatalog.safari, windowID: target?.windowID ?? 0,
                windowBounds: frameCG ?? .zero)
        }
    }
}
