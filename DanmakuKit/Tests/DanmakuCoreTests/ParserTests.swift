import Foundation
import Testing

@testable import DanmakuCore

struct ParserTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func classicXML() throws {
        let track = try BiliXMLParser.parse(try fixture("classic.xml"))
        #expect(track.items.count == 8)  // "bad" is skipped
        #expect(track.title == "cid 12345")
        #expect(track.items.map(\.timeMs) == track.items.map(\.timeMs).sorted())

        let first = try #require(track.items.first { $0.text == "第一条" })
        #expect(first.timeMs == 12_500)
        #expect(first.id == 987_654_321)
        #expect(first.sendTime == 1_600_000_000)
        #expect(first.userHash == "abcd1234")
        #expect(first.weight == 10)
        #expect(first.kind == .roll)

        let top = try #require(track.items.first { $0.text == "顶部红色" })
        #expect(top.kind == .top)
        #expect(top.color == 0xFF0000)

        // Modes 2 and 3 are ordinary scrolling danmaku (the reference dropped them).
        #expect(track.items.first { $0.text == "mode two" }?.kind == .roll)
        let subtitle = try #require(track.items.first { $0.text == "字幕池" })
        #expect(subtitle.kind == .roll)
        #expect(subtitle.pool == .subtitle)
        #expect(subtitle.fontSize == 18)

        #expect(track.items.first { $0.text == "底部<绿>" }?.kind == .bottom)
        #expect(track.items.first { $0.text == "逆向" }?.kind == .inverse)
        #expect(track.items.first { $0.text == "code" }?.kind == .unsupported)

        let adv = try #require(track.items.first { $0.mode == .advanced }?.advanced)
        #expect(adv.text == "高级\n弹幕")
        #expect(adv.durationMs == 4500)
        #expect(adv.startOpacity == 1 && adv.endOpacity == 0)
        #expect(adv.isRelative)
        #expect(adv.moveDurationMs == 1000 && adv.moveDelayMs == 500)
        #expect(adv.outline)
        #expect(adv.fontName == "SimHei")
        #expect(!adv.linearAccelerate)
    }

    @Test func newFormatXML() throws {
        let xml = """
            <i><oid>42</oid><d p="111,0,61000,5,25,255,hash1,7,1">新格式</d></i>
            """
        let track = try BiliXMLParser.parse(Data(xml.utf8))
        let d = try #require(track.items.first)
        #expect(d.id == 111)
        #expect(d.timeMs == 61_000)
        #expect(d.kind == .top)
        #expect(d.color == 255)
        #expect(d.userHash == "hash1")
        // The reference read pool/ctime from the size/colour columns; they must keep their defaults here.
        #expect(d.pool == .normal)
    }

    @Test func controlCharactersAreTolerated() throws {
        let xml = "<i><d p=\"1,1,25,16777215,0,0,a,1\">bad\u{08}char</d></i>"
        let track = try BiliXMLParser.parse(Data(xml.utf8))
        #expect(track.items.first?.text == "badchar")
    }

    @Test func notXML() {
        #expect(throws: (any Error).self) { try BiliXMLParser.parse(Data("<html></html>".utf8)) }
    }

    @Test func protobufSegment() throws {
        var elem1 = ProtoWriter()
        elem1.varint(1, 555)
        elem1.varint(2, 2500)
        elem1.varint(3, 4)
        elem1.varint(4, 25)
        elem1.varint(5, 0x00FF00)
        elem1.string(6, "mid")
        elem1.string(7, "底部")
        elem1.varint(8, 1_700_000_000)
        elem1.varint(9, 8)
        elem1.string(10, "unknown action field")
        elem1.varint(11, 0)
        elem1.varint(13, 4)
        elem1.varint(24, 60001)
        var elem2 = ProtoWriter()
        elem2.varint(2, 1000)
        elem2.varint(3, 1)
        elem2.string(7, "滚动")
        var reply = ProtoWriter()
        reply.message(1, elem1)
        reply.message(1, elem2)
        reply.varint(2, 0)

        let track = try LocalFileSource.parse(reply.data)
        #expect(track.items.map(\.text) == ["滚动", "底部"])
        let b = track.items[1]
        #expect(b.id == 555)
        #expect(b.timeMs == 2500)
        #expect(b.kind == .bottom)
        #expect(b.color == 0x00FF00)
        #expect(b.userHash == "mid")
        #expect(b.weight == 8)
        #expect(b.attributes.contains(.highLike))
        #expect(b.colorful)
        #expect(track.items[0].fontSize == 25)
    }

    @Test func truncatedProtobufThrows() {
        var reply = ProtoWriter()
        var elem = ProtoWriter()
        elem.string(7, "hello")
        reply.message(1, elem)
        let truncated = reply.data.dropLast(2)
        #expect(throws: (any Error).self) { try BiliSegParser.parse(Data(truncated)) }
    }

    @Test func advancedAbsoluteCoordinatesFitStage() throws {
        let adv = try #require(AdvancedDanmaku.parse(#"[336,219,"1-1","3","中心",0,0,336,219,0,0,0,"",1]"#))
        #expect(!adv.isRelative)
        let p = adv.viewPoint(adv.start, in: CGSize(width: 1344, height: 876))
        #expect(abs(p.x - 672) < 0.001 && abs(p.y - 438) < 0.001)
        #expect(adv.linearAccelerate)
    }

    @Test func advancedEasing() throws {
        let adv = try #require(AdvancedDanmaku.parse(#"[0,0,"0.5-1",2,"x",0,0,1,1,1000,0,0,"",0]"#))
        #expect(adv.movementProgress(atMs: 0) == 0)
        #expect(abs(adv.movementProgress(atMs: 500) - 0.75) < 1e-9)  // 2s − s² at s = 0.5
        #expect(adv.movementProgress(atMs: 1500) == 1)
        #expect(abs(adv.opacity(atMs: 1000) - 0.75) < 1e-9)
    }

    @Test func invalidAdvancedPayload() {
        #expect(AdvancedDanmaku.parse("not json") == nil)
        #expect(AdvancedDanmaku.parse("[1,2]") == nil)
    }
}

/// Tiny protobuf encoder for building test fixtures.
struct ProtoWriter {
    var data = Data()

    mutating func rawVarint(_ v: UInt64) {
        var v = v
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        rawVarint(UInt64(field << 3))
        rawVarint(value)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        rawVarint(UInt64(field << 3 | 2))
        rawVarint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }
    mutating func message(_ field: Int, _ value: ProtoWriter) { bytes(field, value.data) }
}
