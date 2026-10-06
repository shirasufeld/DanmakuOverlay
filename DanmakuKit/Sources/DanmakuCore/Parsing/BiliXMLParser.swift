import Foundation

/// Parses Bilibili danmaku XML (`<i><d p="...">text</d>...</i>`).
///
/// Two layouts of the `p` attribute exist:
/// * classic: `time_s, mode, size, color, ctime, pool, midHash, dmid[, weight]`
/// * "new" (documents containing an `<oid>` element): `dmid, ?, progress_ms, mode, size, color, midHash, ...`
public enum BiliXMLParser {
    public enum ParseError: Error, Equatable {
        case notDanmakuXML
        case malformed(String)
    }

    public static func parse(_ data: Data) throws -> DanmakuTrack {
        let parser = XMLParser(data: sanitize(data))
        let delegate = Delegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        if !parser.parse() && delegate.records.isEmpty {
            throw ParseError.malformed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        guard delegate.sawRoot else { throw ParseError.notDanmakuXML }

        var items: [Danmaku] = []
        items.reserveCapacity(delegate.records.count)
        for (p, text) in delegate.records {
            if let d = makeDanmaku(p: p, text: text, newFormat: delegate.sawOid) {
                items.append(d)
            }
        }
        var track = DanmakuTrack(items: items, title: delegate.chatID.map { "cid \($0)" })
        track.sort()
        return track
    }

    /// Builds one danmaku from the `p` attribute; returns `nil` for unparsable or unsupported entries.
    static func makeDanmaku(p: String, text: String, newFormat: Bool) -> Danmaku? {
        let f = p.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
        func int(_ i: Int) -> Int? { i < f.count ? Int(f[i]) : nil }
        func int64(_ i: Int) -> Int64? { i < f.count ? Int64(f[i]) : nil }
        func uint64(_ i: Int) -> UInt64? { i < f.count ? UInt64(f[i]) : nil }
        func str(_ i: Int) -> String { i < f.count ? f[i] : "" }

        var d: Danmaku
        if newFormat {
            guard let ms = int(2), let modeRaw = int(3), let mode = DanmakuMode(rawValue: modeRaw) else {
                return nil
            }
            d = Danmaku(
                id: uint64(0) ?? 0, text: text, timeMs: ms, mode: mode,
                fontSize: int(4) ?? 25, color: UInt32(truncatingIfNeeded: int(5) ?? 0xFFFFFF),
                userHash: str(6))
        } else {
            guard f.count >= 4, let seconds = Double(f[0]), let modeRaw = int(1),
                let mode = DanmakuMode(rawValue: modeRaw)
            else { return nil }
            d = Danmaku(
                id: uint64(7) ?? 0, text: text, timeMs: Int((seconds * 1000).rounded()), mode: mode,
                fontSize: int(2) ?? 25, color: UInt32(truncatingIfNeeded: int(3) ?? 0xFFFFFF),
                pool: DanmakuPool(rawValue: int(5) ?? 0) ?? .normal,
                userHash: str(6), sendTime: int64(4) ?? 0, weight: int(8) ?? 0)
        }
        d.timeMs = max(d.timeMs, 0)
        d.parseAdvancedIfNeeded()
        return d
    }

    /// Removes bytes that are illegal in XML 1.0 (Bilibili files occasionally contain control characters).
    static func sanitize(_ data: Data) -> Data {
        let illegal: (UInt8) -> Bool = { b in b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D }
        guard data.contains(where: illegal) else { return data }
        return Data(data.filter { !illegal($0) })
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var records: [(String, String)] = []
        var sawRoot = false
        var sawOid = false
        var chatID: String?
        private var currentP: String?
        private var buffer = ""
        private var inChatID = false

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes: [String: String] = [:]
        ) {
            switch name {
            case "i": sawRoot = true
            case "oid": sawOid = true
            case "chatid": inChatID = true; buffer = ""
            case "d":
                currentP = attributes["p"]
                buffer = ""
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if currentP != nil || inChatID { buffer += string }
        }

        func parser(
            _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?
        ) {
            if name == "d", let p = currentP {
                records.append((p, buffer))
                currentP = nil
            } else if name == "chatid" {
                chatID = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                inChatID = false
            }
        }
    }
}
