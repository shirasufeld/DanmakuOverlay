import AppKit
import CoreGraphics

/// A window as reported by the window server (no Screen Recording permission needed for these fields).
struct WindowInfo: Sendable, Hashable, Identifiable {
    var id: CGWindowID
    var pid: pid_t
    var ownerName: String
    /// Core Graphics global coordinates (top-left origin).
    var bounds: CGRect
    var layer: Int
    var isOnScreen: Bool
    var alpha: Double

    init?(_ dict: [String: Any]) {
        guard let number = dict[kCGWindowNumber as String] as? CGWindowID,
            let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
            let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }
        id = number
        self.pid = pid
        ownerName = dict[kCGWindowOwnerName as String] as? String ?? ""
        self.bounds = bounds
        layer = dict[kCGWindowLayer as String] as? Int ?? 0
        isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
        alpha = dict[kCGWindowAlpha as String] as? Double ?? 1
    }
}

/// A window the user can attach the overlay to.
struct CandidateWindow: Identifiable, Hashable {
    var info: WindowInfo
    var title: String
    var bundleID: String?
    var appName: String
    var id: CGWindowID { info.id }
}

enum WindowCatalog {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    static func info(for id: CGWindowID) -> WindowInfo? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []
        return list.lazy.compactMap(WindowInfo.init).first { $0.id == id }
    }

    /// Normal on-screen windows of other apps, front to back.
    static func onScreenWindows() -> [WindowInfo] {
        let list =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap(WindowInfo.init).filter { $0.pid != ownPID }
    }

    /// Windows that may host a video: normal level, reasonably large, visible.
    static func candidates() -> [CandidateWindow] {
        let apps = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        return onScreenWindows()
            .filter { $0.layer == 0 && $0.alpha > 0 && $0.bounds.width >= 200 && $0.bounds.height >= 120 }
            .map { w in
                let app = apps[w.pid]
                let title = AXSupport.isTrusted ? AXSupport.title(ofWindow: w.id, pid: w.pid) : nil
                return CandidateWindow(
                    info: w, title: title ?? "", bundleID: app?.bundleIdentifier,
                    appName: app?.localizedName ?? w.ownerName)
            }
    }

    /// Rects (CG coordinates) of windows stacked above `id` that intersect it, excluding our own windows and
    /// system chrome (Dock, menu bar).
    static func occluders(above id: CGWindowID, bounds: CGRect) -> [CGRect] {
        let list =
            CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], id)
            as? [[String: Any]] ?? []
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        return list.compactMap(WindowInfo.init).compactMap { w in
            guard w.pid != ownPID, w.layer >= 0, w.layer < dockLevel, w.alpha > 0.05,
                w.bounds.width > 4, w.bounds.height > 4
            else { return nil }
            let r = w.bounds.intersection(bounds)
            return r.isNull || r.isEmpty ? nil : r
        }
    }
}
