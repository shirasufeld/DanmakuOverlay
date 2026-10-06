import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var trusted = AXSupport.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Interface") {
                Toggle("Show statistics in the menu", isOn: model.settings.binding(\.general.showStatistics))
                Toggle(
                    "Show controls when sync is manual", isOn: model.settings.binding(\.general.showControlsOnAttach))
            }
            Section {
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant…") {
                            AXSupport.requestTrust()
                            AXSupport.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text(
                    "Accessibility lets the overlay follow windows frame by frame, read window titles and mirror player keys. Without it the overlay still follows windows, a little less smoothly."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset All Settings…", role: .destructive) { model.settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .task {
            // Reflect a permission granted while the window is open.
            while !Task.isCancelled {
                trusted = AXSupport.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
