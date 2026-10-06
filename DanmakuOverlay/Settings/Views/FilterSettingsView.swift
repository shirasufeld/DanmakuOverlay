import DanmakuCore
import SwiftUI

struct FilterSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section("Show") {
                Toggle("Scrolling", isOn: store.binding(\.filter.showRoll))
                Toggle("Top", isOn: store.binding(\.filter.showTop))
                Toggle("Bottom", isOn: store.binding(\.filter.showBottom))
                Toggle("Reverse", isOn: store.binding(\.filter.showInverse))
                Toggle("Advanced (mode 7)", isOn: store.binding(\.filter.showAdvanced))
                Toggle("Subtitle pool", isOn: store.binding(\.filter.showSubtitlePool))
                Toggle("Coloured", isOn: store.binding(\.filter.showColored))
                Stepper(value: store.binding(\.filter.minimumWeight), in: 0...10) {
                    LabeledContent(
                        "Shield level",
                        value: store.settings.filter.minimumWeight == 0
                            ? String(localized: "Off") : "\(store.settings.filter.minimumWeight)")
                }
            }
            Section {
                StringListEditor(placeholder: "Keyword", items: store.binding(\.filter.keywords))
            } header: {
                Text("Blocked keywords")
            } footer: {
                Text("Case-insensitive substring match.").foregroundStyle(.secondary)
            }
            Section("Blocked patterns (regular expressions)") {
                StringListEditor(placeholder: "Regular expression", items: store.binding(\.filter.regexes)) { pattern in
                    (try? NSRegularExpression(pattern: pattern)) == nil
                        ? String(localized: "Invalid regular expression") : nil
                }
            }
            Section("Blocked users (sender hash)") {
                StringListEditor(placeholder: "User hash", items: store.binding(\.filter.userHashes))
            }
        }
        .formStyle(.grouped)
    }
}

struct MergeSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Merge similar danmaku", isOn: store.binding(\.merge.enabled))
            } footer: {
                Text(
                    "Repeated or near-identical danmaku within the time window become one, marked with a count (pakku algorithm)."
                )
                .foregroundStyle(.secondary)
            }
            Group {
                Section("Similarity") {
                    Stepper(value: store.binding(\.merge.timeWindow), in: 1...120) {
                        LabeledContent("Time window", value: "\(store.settings.merge.timeWindow) s")
                    }
                    Stepper(value: store.binding(\.merge.maxEditDistance), in: 0...20) {
                        LabeledContent("Edit distance", value: "\(store.settings.merge.maxEditDistance)")
                    }
                    Stepper(value: store.binding(\.merge.maxCosineDistance), in: 0...11) {
                        LabeledContent(
                            "Word similarity",
                            value: store.settings.merge.maxCosineDistance > 10
                                ? String(localized: "Off") : "≥ \(store.settings.merge.maxCosineDistance * 10) %")
                    }
                    Toggle("Match homophones (pinyin)", isOn: store.binding(\.merge.usePinyin))
                    Toggle("Merge across types", isOn: store.binding(\.merge.crossMode))
                    Toggle("Ignore trailing punctuation", isOn: store.binding(\.merge.trimEnding))
                    Toggle("Ignore extra spaces", isOn: store.binding(\.merge.trimSpace))
                    Toggle("Treat full-width as half-width", isOn: store.binding(\.merge.trimWidth))
                    Toggle("Include subtitle pool", isOn: store.binding(\.merge.processSubtitlePool))
                    Toggle("Include bottom danmaku", isOn: store.binding(\.merge.processBottom))
                }
                Section("Result") {
                    Picker("Count mark", selection: store.binding(\.merge.markStyle)) {
                        Text("Off").tag(MergeMarkStyle.off)
                        Text("Before text").tag(MergeMarkStyle.prefix)
                        Text("After text").tag(MergeMarkStyle.suffix)
                    }
                    Toggle("Subscript digits", isOn: store.binding(\.merge.markUsesSubscript))
                    Stepper(value: store.binding(\.merge.markThreshold), in: 1...50) {
                        LabeledContent("Mark from", value: "\(store.settings.merge.markThreshold + 1) copies")
                    }
                    Toggle("Enlarge popular danmaku", isOn: store.binding(\.merge.enlarge))
                    Toggle("Promote to top/bottom if any copy is", isOn: store.binding(\.merge.modeElevation))
                }
                Section {
                    Stepper(value: store.binding(\.merge.shrinkThreshold), in: 0...200, step: 5) {
                        LabeledContent("Shrink above", value: thresholdText(store.settings.merge.shrinkThreshold))
                    }
                    Stepper(value: store.binding(\.merge.dropThreshold), in: 0...200, step: 5) {
                        LabeledContent("Thin out above", value: thresholdText(store.settings.merge.dropThreshold))
                    }
                    Stepper(value: store.binding(\.merge.scrollThreshold), in: 0...2000, step: 50) {
                        LabeledContent(
                            "Scroll long top/bottom wider than",
                            value: thresholdText(store.settings.merge.scrollThreshold, unit: " pt"))
                    }
                } header: {
                    Text("Density")
                } footer: {
                    Text("Density is measured over the last five seconds; 0 turns a rule off.").foregroundStyle(
                        .secondary)
                }
            }
            .disabled(!store.settings.merge.enabled)
        }
        .formStyle(.grouped)
    }

    private func thresholdText(_ v: Int, unit: String = "") -> String {
        v == 0 ? String(localized: "Off") : "\(v)\(unit)"
    }
}
