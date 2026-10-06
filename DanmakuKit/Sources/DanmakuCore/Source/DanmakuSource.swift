import Foundation

/// Where a danmaku track comes from. New kinds of sources plug in here.
public enum SourceDescriptor: Codable, Hashable, Sendable {
    case localFile(URL)

    public var displayName: String {
        switch self {
        case .localFile(let url): url.lastPathComponent
        }
    }
}

/// Loads a danmaku track.
public protocol DanmakuSource: Sendable {
    var descriptor: SourceDescriptor { get }
    func load() async throws -> DanmakuTrack
}

/// A local Bilibili XML or protobuf segment file. The format is sniffed from content, not extension.
public struct LocalFileSource: DanmakuSource {
    public let url: URL
    public init(url: URL) { self.url = url }

    public var descriptor: SourceDescriptor { .localFile(url) }

    public static let supportedExtensions: Set<String> = ["xml", "so", "pb", "bin"]

    public func load() async throws -> DanmakuTrack {
        let url = self.url
        return try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            var track = try Self.parse(data)
            track.title = url.deletingPathExtension().lastPathComponent
            return track
        }.value
    }

    public static func parse(_ data: Data) throws -> DanmakuTrack {
        if looksLikeXML(data) { return try BiliXMLParser.parse(data) }
        return try BiliSegParser.parse(data)
    }

    static func looksLikeXML(_ data: Data) -> Bool {
        for b in data.prefix(64) {
            if b == 0xEF || b == 0xBB || b == 0xBF || b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 { continue }
            return b == UInt8(ascii: "<")
        }
        return false
    }
}
