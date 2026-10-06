import Foundation

/// Pinyin (initial, final) codes for common Hanzi, from pakku.js via DanmakuPlayer. Loaded lazily from
/// `pinyin.bin` (see Tools/gen-pinyin.swift).
public enum PinyinTable {
    public static let shared: [UInt32: (UInt8, UInt8)] = load()

    static func load() -> [UInt32: (UInt8, UInt8)] {
        guard let url = Bundle.module.url(forResource: "pinyin", withExtension: "bin"),
            let data = try? Data(contentsOf: url), data.count >= 4
        else { return [:] }
        let bytes = [UInt8](data)
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
        }
        let count = Int(u32(0))
        guard data.count >= 4 + count * 6 else { return [:] }
        var table: [UInt32: (UInt8, UInt8)] = [:]
        table.reserveCapacity(count)
        for i in 0..<count {
            let o = 4 + i * 6
            table[u32(o)] = (bytes[o + 4], bytes[o + 5])
        }
        return table
    }
}
