import DanmakuCore
import Foundation

/// Known players and the sync adapters that work with them, best first.
nonisolated enum PlayerCatalog {
    static let iina = "com.colliderli.iina"
    static let mpv = "io.mpv"
    static let vlc = "org.videolan.vlc"
    static let infuse = "com.firecore.infuse"
    static let safari = "com.apple.Safari"
    static let safariPreview = "com.apple.SafariTechnologyPreview"

    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
    ]
    static let otherNowPlaying: Set<String> = ["org.mozilla.firefox", "com.apple.TV", "com.apple.QuickTimePlayerX"]

    static func isKnownPlayer(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return !adapters(for: bundleID).isEmpty
    }

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == safari || bundleID == safariPreview || chromiumBrowsers.contains(bundleID)
    }

    /// Adapters to try for an app, in order of preference (Manual is always the final fallback).
    static func adapters(for bundleID: String) -> [SourceKind] {
        switch bundleID {
        case iina: [.mpv, .nowPlaying]
        case mpv: [.mpv]
        case vlc: [.vlc, .nowPlaying]
        case infuse: [.nowPlaying]
        case _ where isBrowser(bundleID): [.browser, .nowPlaying]
        case _ where otherNowPlaying.contains(bundleID): [.nowPlaying]
        default: []
        }
    }
}
