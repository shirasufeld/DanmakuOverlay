import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable global shortcuts", isOn: store.binding(\.general.hotkeysEnabled))
            }
            Section("Shortcuts") {
                ForEach(HotkeyCenter.Action.allCases) { action in
                    LabeledContent {
                        Text(action.shortcut).font(.body.monospaced()).foregroundStyle(.secondary)
                    } label: {
                        Text(action.title)
                    }
                }
            }
            .disabled(!store.settings.general.hotkeysEnabled)
        }
        .formStyle(.grouped)
    }
}
