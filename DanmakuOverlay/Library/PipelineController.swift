import CoreGraphics
import DanmakuCore
import DanmakuText
import Foundation
import Observation

/// Turns a danmaku source into a laid-out timeline: load → filter/merge → layout. Each stage is cancellable
/// and stale results are discarded.
@Observable
final class PipelineController {
    struct Counts: Equatable {
        var loaded = 0
        var afterFilter = 0
        var placed = 0
        var dropped = 0
    }

    private(set) var descriptor: SourceDescriptor?
    private(set) var title: String?
    private(set) var counts = Counts()
    private(set) var isBusy = false
    private(set) var lastError: String?
    /// Duration covered by the loaded danmaku, in seconds.
    private(set) var trackDuration: Double?

    @ObservationIgnored private var raw: [Danmaku] = []
    @ObservationIgnored private(set) var filtered: [Danmaku] = []
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Delivers a new timeline together with the danmaku its `sourceIndex` values refer to.
    @ObservationIgnored var onTimeline: ((PlacedTimeline, [Danmaku], CGSize) -> Void)?

    var hasTrack: Bool { descriptor != nil }

    func load(_ source: any DanmakuSource, settings: AppSettings, viewSize: CGSize, rate: Double) async {
        isBusy = true
        lastError = nil
        do {
            let track = try await source.load()
            descriptor = source.descriptor
            title = track.title
            raw = track.items
            trackDuration = track.items.isEmpty ? nil : Double(track.lastTimeMs) / 1000 + settings.display.rollDuration
            counts = Counts(loaded: raw.count)
            refilter(settings: settings, viewSize: viewSize, rate: rate)
        } catch {
            isBusy = false
            lastError = error.localizedDescription
            Log.pipeline.error("Loading \(source.descriptor.displayName) failed: \(error.localizedDescription)")
        }
    }

    func unload() {
        filterTask?.cancel()
        layoutTask?.cancel()
        generation += 1
        descriptor = nil
        title = nil
        raw = []
        filtered = []
        counts = Counts()
        trackDuration = nil
        isBusy = false
        onTimeline?(.empty, [], .zero)
    }

    func refilter(settings: AppSettings, viewSize: CGSize, rate: Double) {
        guard hasTrack else { return }
        layoutTask?.cancel()
        filterTask?.cancel()
        generation += 1
        let generation = self.generation
        let chain = FilterChain(filter: settings.filter, merge: settings.merge)
        let input = raw
        isBusy = true
        filterTask = Task { [weak self] in
            do {
                let output = try await chain.run(input)
                guard let self, self.generation == generation else { return }
                self.filtered = output
                self.counts.afterFilter = output.count
                self.relayout(settings: settings, viewSize: viewSize, rate: rate)
            } catch {
                return
            }
        }
    }

    func relayout(settings: AppSettings, viewSize: CGSize, rate: Double) {
        guard hasTrack, viewSize.width >= 50, viewSize.height >= 50 else { return }
        layoutTask?.cancel()
        generation += 1
        let generation = self.generation
        let config = settings.display.layoutConfig(viewSize: viewSize, rate: rate)
        let engine = LayoutEngine(config: config, measurer: CoreTextMeasurer(style: TextStyle(settings.display)))
        let input = filtered
        isBusy = true
        let start = Date()
        layoutTask = Task { [weak self] in
            do {
                let timeline = try await engine.layout(input)
                guard let self, self.generation == generation else { return }
                self.counts.placed = timeline.items.count
                self.counts.dropped = timeline.droppedCount
                self.isBusy = false
                Log.pipeline.info(
                    "Laid out \(timeline.items.count) of \(input.count) danmaku in \(Date().timeIntervalSince(start) * 1000, format: .fixed(precision: 0)) ms"
                )
                self.onTimeline?(timeline, input, viewSize)
            } catch {
                return
            }
        }
    }
}
