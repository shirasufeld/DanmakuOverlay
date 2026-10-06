import DanmakuCore
import Foundation

/// Finds danmaku files for the media being played and remembers per-media offsets.
enum MediaLibrary {
    /// Danmaku next to the video (`movie.xml`, `movie.danmaku.xml`, `movie.so`…) or in library folders.
    static func danmakuFile(for media: MediaIdentity, libraryFolders: [String]) -> URL? {
        let fm = FileManager.default
        var stems: [(dir: URL?, stem: String)] = []
        if let path = media.path {
            let url = URL(fileURLWithPath: path)
            stems.append((url.deletingLastPathComponent(), url.deletingPathExtension().lastPathComponent))
        }
        if let title = media.title, !title.isEmpty {
            stems.append((nil, (title as NSString).deletingPathExtension))
        }
        let folders = libraryFolders.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        for (dir, stem) in stems {
            let dirs = (dir.map { [$0] } ?? []) + folders
            for d in dirs {
                for suffix in [".xml", ".danmaku.xml", ".so", ".pb"] {
                    let candidate = d.appending(path: stem + suffix)
                    if fm.fileExists(atPath: candidate.path) { return candidate }
                }
            }
        }
        return nil
    }

    private static let offsetsKey = "mediaOffsets"

    static func offset(for media: MediaIdentity) -> Double? {
        guard let key = media.key else { return nil }
        return (UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Double])?[key]
    }

    static func setOffset(_ offset: Double, for media: MediaIdentity) {
        guard let key = media.key else { return }
        var all = UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Double] ?? [:]
        all[key] = offset == 0 ? nil : offset
        if all.count > 500 { all.removeAll() }
        UserDefaults.standard.set(all, forKey: offsetsKey)
    }
}
