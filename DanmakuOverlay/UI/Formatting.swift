import DanmakuCore
import Foundation

enum TimeText {
    /// "1:02:03" / "2:03".
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(seconds, 0).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Signed offset such as "+0.5 s".
    static func offset(_ seconds: Double) -> String {
        seconds == 0 ? "0 s" : String(format: "%+.1f s", seconds)
    }

    /// Parses "90", "1:30", "1:02:03" (and decimals) into seconds.
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }
}

extension SourceKind {
    var displayName: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .mpv: "IINA / mpv"
        case .vlc: "VLC"
        case .browser: String(localized: "Browser")
        case .nowPlaying: String(localized: "Now Playing")
        }
    }
}

extension SourceStatus {
    var displayText: String {
        switch self {
        case .idle: String(localized: "Not connected")
        case .connecting: String(localized: "Connecting…")
        case .connected(let detail): detail.isEmpty ? String(localized: "Connected") : detail
        case .needsPermission(let p):
            switch p {
            case .accessibility: String(localized: "Needs Accessibility permission")
            case .automation(let id): String(localized: "Needs permission to control \(id)")
            case .browserJavaScript: String(localized: "Enable “Allow JavaScript from Apple Events” in the browser")
            }
        case .needsSetup(let hint): hint
        case .unavailable(let reason): reason
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
