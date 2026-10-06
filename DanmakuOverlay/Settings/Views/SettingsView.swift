import DanmakuCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var tab: String

    init(model: AppModel, initialTab: String = "general") {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") { GeneralSettingsView(model: model) }
            Tab("Display", systemImage: "textformat.size", value: "display") {
                DisplaySettingsView(store: model.settings)
            }
            Tab("Filters", systemImage: "line.3.horizontal.decrease.circle", value: "filters") {
                FilterSettingsView(store: model.settings)
            }
            Tab("Merging", systemImage: "square.stack.3d.down.right", value: "merging") {
                MergeSettingsView(store: model.settings)
            }
            Tab("Sync", systemImage: "arrow.triangle.2.circlepath", value: "sync") {
                SyncSettingsView(store: model.settings)
            }
            Tab("Shortcuts", systemImage: "keyboard", value: "shortcuts") {
                ShortcutsSettingsView(store: model.settings)
            }
        }
        .frame(width: 600, height: 560)
    }
}

/// A list of strings with add / remove, optionally validating each entry.
struct StringListEditor: View {
    let placeholder: LocalizedStringKey
    @Binding var items: [String]
    var validate: (String) -> String? = { _ in nil }
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(placeholder, text: $draft)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error = validate(draft), !draft.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            ForEach(items.indices, id: \.self) { i in
                HStack {
                    Text(items[i]).font(.body.monospaced()).textSelection(.enabled)
                    if let error = validate(items[i]) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)
                    }
                    Spacer()
                    Button {
                        items.remove(at: i)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, validate(value) == nil, !items.contains(value) else { return }
        items.append(value)
        draft = ""
    }
}

extension Binding where Value == UInt32 {
    /// Bridges a 0xRRGGBB colour to SwiftUI's colour picker.
    var color: Binding<Color> {
        Binding<Color>(
            get: {
                let v = wrappedValue
                return Color(
                    .sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                    blue: Double(v & 0xFF) / 255)
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
                let r = UInt32((ns.redComponent * 255).rounded())
                let g = UInt32((ns.greenComponent * 255).rounded())
                let b = UInt32((ns.blueComponent * 255).rounded())
                wrappedValue = r << 16 | g << 8 | b
            })
    }
}

extension Binding where Value == Int? {
    /// Optional limit edited as "enabled + value".
    func limit(default value: Int) -> (enabled: Binding<Bool>, value: Binding<Int>) {
        (
            Binding<Bool>(get: { wrappedValue != nil }, set: { wrappedValue = $0 ? value : nil }),
            Binding<Int>(get: { wrappedValue ?? value }, set: { wrappedValue = $0 })
        )
    }
}
