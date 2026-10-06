import Foundation

/// Minimal protobuf wire-format reader (varint, 64-bit, length-delimited, 32-bit).
/// Unknown fields are skipped, so it tolerates schema additions.
public struct ProtoReader {
    public enum WireType: UInt8 {
        case varint = 0, fixed64 = 1, lengthDelimited = 2, startGroup = 3, endGroup = 4, fixed32 = 5
    }

    public enum ReadError: Error {
        case truncated
        case invalidWireType(UInt8)
    }

    private let bytes: [UInt8]
    private var index: Int
    private let end: Int

    public init(_ data: Data) {
        bytes = [UInt8](data)
        index = 0
        end = bytes.count
    }

    private init(bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes
        index = range.lowerBound
        end = range.upperBound
    }

    public var isAtEnd: Bool { index >= end }

    /// Reads the next field key; `nil` at the end of the message.
    public mutating func nextField() throws -> (number: Int, wireType: WireType)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        let raw = UInt8(key & 0x7)
        guard let type = WireType(rawValue: raw) else { throw ReadError.invalidWireType(raw) }
        return (Int(key >> 3), type)
    }

    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < end else { throw ReadError.truncated }
            let b = bytes[index]
            index += 1
            if shift < 64 { result |= UInt64(b & 0x7F) << shift }
            if b & 0x80 == 0 { return result }
            shift += 7
        }
    }

    public mutating func readLengthDelimited() throws -> Range<Int> {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= end else { throw ReadError.truncated }
        defer { index += length }
        return index..<(index + length)
    }

    public mutating func readString() throws -> String {
        let r = try readLengthDelimited()
        return String(decoding: bytes[r], as: UTF8.self)
    }

    /// A reader over a nested message.
    public mutating func readMessage() throws -> ProtoReader {
        ProtoReader(bytes: bytes, range: try readLengthDelimited())
    }

    public mutating func skip(_ type: WireType) throws {
        switch type {
        case .varint: _ = try readVarint()
        case .fixed64: try advance(8)
        case .fixed32: try advance(4)
        case .lengthDelimited: _ = try readLengthDelimited()
        case .startGroup, .endGroup: break
        }
    }

    private mutating func advance(_ n: Int) throws {
        guard index + n <= end else { throw ReadError.truncated }
        index += n
    }
}
