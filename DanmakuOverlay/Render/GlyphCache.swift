import CoreGraphics
import DanmakuText
import Foundation

/// Byte-bounded LRU cache of danmaku bitmaps, with background prefetching.
final class GlyphCache {
    private struct Entry {
        var image: GlyphImage
        var lastUse: UInt64
    }

    private var entries: [GlyphKey: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0
    private var inFlight: Set<GlyphKey> = []
    private var generation = 0
    private(set) var style: RasterStyle
    let budgetBytes: Int

    init(style: RasterStyle, budgetBytes: Int = 128 << 20) {
        self.style = style
        self.budgetBytes = budgetBytes
    }

    var count: Int { entries.count }
    var byteCount: Int { bytes }

    func setStyle(_ style: RasterStyle) {
        guard style != self.style else { return }
        self.style = style
        removeAll()
    }

    func removeAll() {
        entries.removeAll()
        bytes = 0
        inFlight.removeAll()
        generation += 1
    }

    /// Returns the bitmap, rasterizing synchronously on a miss.
    func image(for key: GlyphKey) -> GlyphImage? {
        clock += 1
        if var e = entries[key] {
            e.lastUse = clock
            entries[key] = e
            return e.image
        }
        guard let image = DanmakuRasterizer.render(key, style: style) else { return nil }
        insert(key, image)
        return image
    }

    func cached(_ key: GlyphKey) -> GlyphImage? { entries[key]?.image }

    /// Rasterizes missing keys off the main thread.
    func prefetch(_ keys: [GlyphKey]) {
        let missing = Array(Set(keys.filter { entries[$0] == nil && !inFlight.contains($0) }).prefix(256))
        guard !missing.isEmpty else { return }
        inFlight.formUnion(missing)
        let style = self.style
        let generation = self.generation
        Task { [weak self] in
            let rendered = await Self.rasterize(missing, style: style)
            guard let self, self.generation == generation else { return }
            for key in missing { self.inFlight.remove(key) }
            for (key, image) in rendered { self.insert(key, image) }
        }
    }

    @concurrent
    private static func rasterize(_ keys: [GlyphKey], style: RasterStyle) async -> [GlyphKey: GlyphImage] {
        var out: [GlyphKey: GlyphImage] = [:]
        for key in keys {
            if Task.isCancelled { break }
            if let image = DanmakuRasterizer.render(key, style: style) { out[key] = image }
        }
        return out
    }

    private func insert(_ key: GlyphKey, _ image: GlyphImage) {
        clock += 1
        if let old = entries[key] { bytes -= old.image.byteCount }
        entries[key] = Entry(image: image, lastUse: clock)
        bytes += image.byteCount
        if bytes > budgetBytes { evict() }
    }

    private func evict() {
        let sorted = entries.sorted { $0.value.lastUse < $1.value.lastUse }
        for (key, entry) in sorted {
            guard bytes > budgetBytes * 3 / 4 else { break }
            entries[key] = nil
            bytes -= entry.image.byteCount
        }
    }
}
