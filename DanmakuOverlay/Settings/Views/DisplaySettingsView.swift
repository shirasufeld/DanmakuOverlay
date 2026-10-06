import AppKit
import DanmakuCore
import SwiftUI

struct DisplaySettingsView: View {
    @Bindable var store: SettingsStore
    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section("Text") {
                Picker("Font", selection: store.binding(\.display.fontName)) {
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Picker("Weight", selection: store.binding(\.display.fontWeight)) {
                    Text("Regular").tag(FontWeightOption.regular)
                    Text("Medium").tag(FontWeightOption.medium)
                    Text("Semibold").tag(FontWeightOption.semibold)
                    Text("Bold").tag(FontWeightOption.bold)
                    Text("Heavy").tag(FontWeightOption.heavy)
                }
                LabeledSlider(
                    "Size", value: store.binding(\.display.fontScale), range: 0.5...3, step: 0.05,
                    format: { "\(Int(($0 * 100).rounded())) %" })
                Toggle("Scale with video height", isOn: store.binding(\.display.scaleWithViewHeight))
                LabeledSlider(
                    "Opacity", value: store.binding(\.display.opacity), range: 0.1...1, step: 0.05,
                    format: { "\(Int(($0 * 100).rounded())) %" })
            }
            Section("Outline") {
                Picker("Style", selection: store.binding(\.display.outline)) {
                    Text("Stroke").tag(OutlineStyle.stroke)
                    Text("Shadow").tag(OutlineStyle.shadow)
                    Text("Stroke + shadow").tag(OutlineStyle.strokeAndShadow)
                    Text("None").tag(OutlineStyle.none)
                }
                LabeledSlider(
                    "Stroke width", value: store.binding(\.display.strokeWidth), range: 0...4, step: 0.25,
                    format: { String(format: "%.2f pt", $0) })
                ColorPicker(
                    "Outline colour", selection: store.binding(\.display.strokeColor).color, supportsOpacity: false)
                Toggle("Gradient for VIP colourful danmaku", isOn: store.binding(\.display.colorfulGradient))
            }
            Section("Motion") {
                LabeledSlider(
                    "Scrolling duration", value: store.binding(\.display.rollDuration), range: 3...20, step: 0.5,
                    format: { String(format: "%.1f s", $0) })
                LabeledSlider(
                    "Top / bottom duration", value: store.binding(\.display.staticDuration), range: 1...12, step: 0.5,
                    format: { String(format: "%.1f s", $0) })
                Toggle(
                    "Keep on-screen speed when playback is faster",
                    isOn: store.binding(\.display.keepScreenSpeedOnRateChange))
            }
            Section("Area") {
                Picker("Display area", selection: store.binding(\.display.displayArea)) {
                    Text("Top quarter").tag(0.25)
                    Text("Top half").tag(0.5)
                    Text("Top three quarters").tag(0.75)
                    Text("Full").tag(1.0)
                }
                Toggle("Keep subtitles clear", isOn: store.binding(\.display.protectSubtitles))
                if store.settings.display.protectSubtitles {
                    LabeledSlider(
                        "Reserved at the bottom", value: store.binding(\.display.subtitleSafeFraction),
                        range: 0.05...0.4,
                        step: 0.01, format: { "\(Int(($0 * 100).rounded())) %" })
                }
                Picker("Fit to", selection: store.binding(\.display.contentFit)) {
                    Text("Video picture").tag(ContentFit.video)
                    Text("Whole window").tag(ContentFit.window)
                }
                LabeledSlider(
                    "Line spacing", value: store.binding(\.display.lineSpacing), range: 0...16, step: 1,
                    format: { "\(Int($0)) pt" })
                Toggle("Hide while the window moves", isOn: store.binding(\.display.hideWhileMoving))
            }
            Section {
                Toggle("Allow overlapping", isOn: store.binding(\.display.allowOverlap))
                LimitRow(title: "Scrolling", limit: store.binding(\.display.limits.roll))
                LimitRow(title: "Top", limit: store.binding(\.display.limits.top))
                LimitRow(title: "Bottom", limit: store.binding(\.display.limits.bottom))
                LimitRow(title: "Reverse", limit: store.binding(\.display.limits.inverse))
            } header: {
                Text("Density")
            } footer: {
                Text("Without overlapping, danmaku that find no free row are skipped.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(
        _ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
        format: @escaping (Double) -> String
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).frame(minWidth: 180)
                Text(format(value)).monospacedDigit().frame(width: 64, alignment: .trailing)
            }
        }
    }
}

struct LimitRow: View {
    let title: LocalizedStringKey
    @Binding var limit: Int?

    var body: some View {
        let parts = $limit.limit(default: 30)
        LabeledContent(title) {
            HStack {
                Toggle("Limit", isOn: parts.enabled).labelsHidden()
                Stepper(value: parts.value, in: 1...500, step: 5) {
                    Text(limit.map { "max \($0)" } ?? String(localized: "Unlimited")).monospacedDigit()
                }
                .disabled(limit == nil)
            }
        }
    }
}
