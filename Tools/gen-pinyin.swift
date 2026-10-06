// Converts DanmakuPlayer's pinyin dictionary (C#) into DanmakuCore/Resources/pinyin.bin.
//
// Usage: swift Tools/gen-pinyin.swift <DanmakuCombiner.PinYinDictionary.cs> <output pinyin.bin>
//
// Format: little-endian UInt32 count, then `count` records of (UInt32 scalar, UInt8 initial, UInt8 final),
// sorted by scalar.
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: gen-pinyin <input.cs> <output.bin>\n".utf8))
    exit(1)
}
let source = try String(contentsOfFile: args[1], encoding: .utf8)
let start = source.range(of: "_PinyinCache")!.upperBound
let pattern = try NSRegularExpression(pattern: #"\['(.)'\]\s*=\s*\((\d+),\s*(\d+)\)"#)
let body = String(source[start...])
var table: [UInt32: (UInt8, UInt8)] = [:]
for m in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
    let ch = String(body[Range(m.range(at: 1), in: body)!])
    let a = UInt8(body[Range(m.range(at: 2), in: body)!])!
    let b = UInt8(body[Range(m.range(at: 3), in: body)!])!
    table[ch.unicodeScalars.first!.value] = (a, b)
}
var out = Data()
func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
append(UInt32(table.count))
for key in table.keys.sorted() {
    append(key)
    out.append(table[key]!.0)
    out.append(table[key]!.1)
}
try out.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(table.count) entries, \(out.count) bytes")
