import AppKit
import DanmakuCore
import SwiftUI

struct SyncSettingsView: View {
    @Bindable var store: SettingsStore

    private let players: [(name: String, bundle: String)] = [
        ("IINA", PlayerCatalog.iina), ("VLC", PlayerCatalog.vlc), ("Infuse", PlayerCatalog.infuse),
        ("Safari", PlayerCatalog.safari), ("Google Chrome", "com.google.Chrome"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(players, id: \.bundle) { player in
                    Picker(player.name, selection: adapterBinding(player.bundle)) {
                        Text("Automatic").tag(SourceKind?.none)
                        ForEach(PlayerCatalog.adapters(for: player.bundle) + [.manual]) { kind in
                            Text(kind.displayName).tag(Optional(kind))
                        }
                    }
                }
            } header: {
                Text("Sync method")
            } footer: {
                Text("Automatic tries the most precise method first and falls back when it cannot connect.")
                    .foregroundStyle(.secondary)
            }
            Section("IINA and mpv") {
                TextField("IPC socket", text: store.binding(\.sync.mpvSocketPath))
                    .font(.body.monospaced())
                LabeledContent("IINA") {
                    if IINASetup.isConfigured(socketPath: store.settings.sync.mpvSocketPath) {
                        Label("Configured", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        IINASetupHint()
                    }
                }
                Text("For plain mpv, add “input-ipc-server=\(store.settings.sync.mpvSocketPath)” to mpv.conf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("VLC") {
                Toggle(
                    "VLC rounds the current time (instead of truncating)", isOn: store.binding(\.sync.vlcRoundsSeconds))
            }
            Section("Manual clock") {
                Toggle("Mirror Space and ←/→ while the player is in front", isOn: store.binding(\.sync.mirrorKeys))
                LabeledSlider(
                    "Seek step", value: store.binding(\.sync.seekStep), range: 1...30, step: 1,
                    format: { "\(Int($0)) s" })
                LabeledSlider(
                    "Offset step", value: store.binding(\.sync.offsetStep), range: 0.1...2, step: 0.1,
                    format: { String(format: "%.1f s", $0) })
            }
            Section {
                Toggle("Load danmaku files that match the video", isOn: store.binding(\.sync.autoLoadMatchingDanmaku))
                StringListEditor(placeholder: "Folder path", items: store.binding(\.sync.libraryFolders))
                Button("Add Folder…") { chooseFolder() }
            } header: {
                Text("Danmaku library")
            } footer: {
                Text("Looks for “video.xml”, “video.danmaku.xml” or “video.so” next to the video and in these folders.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func adapterBinding(_ bundle: String) -> Binding<SourceKind?> {
        Binding(
            get: { store.settings.sync.preferredAdapters[bundle] },
            set: { value in store.update { $0.sync.preferredAdapters[bundle] = value } })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        store.update { s in
            for url in panel.urls where !s.sync.libraryFolders.contains(url.path) {
                s.sync.libraryFolders.append(url.path)
            }
        }
    }
}
