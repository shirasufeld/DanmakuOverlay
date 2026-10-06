import Foundation

/// Parses a Bilibili `DmSegMobileReply` protobuf segment (`seg.so`).
///
/// Field numbers from `bilibili.community.service.dm.v1.DanmakuElem`:
/// 1 id, 2 progress, 3 mode, 4 fontsize, 5 color, 6 midHash, 7 content, 8 ctime, 9 weight,
/// 11 pool, 13 attr, 24 colorful (60001 = VIP gradient).
public enum BiliSegParser {
    public static func parse(_ data: Data) throws -> DanmakuTrack {
        var reader = ProtoReader(data)
        var items: [Danmaku] = []
        while let (number, type) = try reader.nextField() {
            if number == 1, type == .lengthDelimited {
                var message = try reader.readMessage()
                if let d = try parseElem(&message) { items.append(d) }
            } else {
                try reader.skip(type)
            }
        }
        var track = DanmakuTrack(items: items)
        track.sort()
        return track
    }

    /// Concatenated segments (several `seg.so` files) parse into one track.
    public static func parse(segments: [Data]) throws -> DanmakuTrack {
        var all: [Danmaku] = []
        for s in segments { all += try parse(s).items }
        var track = DanmakuTrack(items: all)
        track.sort()
        return track
    }

    static func parseElem(_ r: inout ProtoReader) throws -> Danmaku? {
        var d = Danmaku(text: "", timeMs: 0)
        var modeRaw = 1
        while let (number, type) = try r.nextField() {
            switch (number, type) {
            case (1, .varint): d.id = try r.readVarint()
            case (2, .varint): d.timeMs = Int(Int32(truncatingIfNeeded: try r.readVarint()))
            case (3, .varint): modeRaw = Int(try r.readVarint())
            case (4, .varint): d.fontSize = Int(try r.readVarint())
            case (5, .varint): d.color = UInt32(truncatingIfNeeded: try r.readVarint())
            case (6, .lengthDelimited): d.userHash = try r.readString()
            case (7, .lengthDelimited): d.text = try r.readString()
            case (8, .varint): d.sendTime = Int64(bitPattern: try r.readVarint())
            case (9, .varint): d.weight = Int(try r.readVarint())
            case (11, .varint): d.pool = DanmakuPool(rawValue: Int(try r.readVarint())) ?? .normal
            case (13, .varint): d.attributes = DanmakuAttributes(rawValue: Int(try r.readVarint()))
            case (24, .varint): d.colorful = try r.readVarint() == 60001
            default: try r.skip(type)
            }
        }
        guard let mode = DanmakuMode(rawValue: modeRaw) else { return nil }
        d.mode = mode
        d.timeMs = max(d.timeMs, 0)
        if d.fontSize <= 0 { d.fontSize = 25 }
        d.parseAdvancedIfNeeded()
        return d
    }
}
