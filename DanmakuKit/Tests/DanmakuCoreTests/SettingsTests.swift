import CoreGraphics
import Foundation
import Testing

@testable import DanmakuCore

struct SettingsTests {
    @Test func roundTrip() throws {
        var s = AppSettings()
        s.display.opacity = 0.5
        s.filter.keywords = ["a"]
        s.display.limits.roll = 20
        s.sync.preferredAdapters["com.colliderli.iina"] = .nowPlaying
        let data = try JSONEncoder().encode(s)
        let back = try JSONMerge.decode(AppSettings.self, from: data, defaults: AppSettings())
        #expect(back == s)
    }

    @Test func missingAndUnknownKeysLoad() throws {
        let json = #"{"display":{"opacity":0.3,"futureKey":1},"newSection":{"x":1}}"#
        let s = try JSONMerge.decode(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        #expect(s.display.opacity == 0.3)
        #expect(s.display.fontName == DisplaySettings().fontName)
    }

    @Test func wrongTypesFallBackPerSection() throws {
        let json = #"{"display":{"opacity":"oops"},"filter":{"keywords":["k"]}}"#
        let s = try JSONMerge.decode(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        #expect(s.display.opacity == DisplaySettings().opacity)
        #expect(s.filter.keywords == ["k"])
    }

    @Test func impactClassification() {
        let base = AppSettings()
        var s = base
        s.display.opacity = 0.2
        #expect(SettingsImpact.between(base, s) == .render)
        s = base
        s.display.strokeColor = 0xFFFFFF
        #expect(SettingsImpact.between(base, s) == .restyle)
        s = base
        s.display.fontScale = 1.5
        #expect(SettingsImpact.between(base, s) == .relayout)
        s = base
        s.merge.timeWindow = 3
        #expect(SettingsImpact.between(base, s) == .refilter)
        #expect(SettingsImpact.between(base, base) == SettingsImpact.none)
    }

    @Test func layoutConfigFromDisplay() {
        var d = DisplaySettings()
        d.displayArea = 0.5
        d.rollDuration = 8
        let c = d.layoutConfig(viewSize: CGSize(width: 1000, height: 600), rate: 2)
        #expect(c.areaHeight == 300)
        #expect(c.rollDurationMs == 16_000)
        d.keepScreenSpeedOnRateChange = false
        #expect(d.layoutConfig(viewSize: CGSize(width: 1000, height: 600), rate: 2).rollDurationMs == 8000)
    }

    @Test func contentRect() {
        let r = ContentRectResolver.contentRect(
            windowSize: CGSize(width: 1000, height: 1000), fit: .video,
            geometry: VideoGeometry(videoSize: CGSize(width: 1920, height: 1080)), insets: .zero)
        #expect(abs(r.height - 562.5) < 0.01 && abs(r.minY - 218.75) < 0.01)
        let f = ContentRectResolver.contentRect(
            windowSize: CGSize(width: 1000, height: 800), fit: .video,
            geometry: VideoGeometry(contentFraction: CGRect(x: 0, y: 0.1, width: 1, height: 0.8)), insets: .zero)
        #expect(f == CGRect(x: 0, y: 80, width: 1000, height: 640))
        let w = ContentRectResolver.contentRect(
            windowSize: CGSize(width: 1000, height: 1000), fit: .window, geometry: nil, insets: Insets(top: 28))
        #expect(w == CGRect(x: 0, y: 28, width: 1000, height: 972))
    }
}
