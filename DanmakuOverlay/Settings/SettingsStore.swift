import DanmakuCore
import Foundation
import Observation
import SwiftUI

/// Owns `AppSettings`, persists them as JSON in Application Support and reports the impact of every change.
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings

    /// Called after every change with the old and new settings.
    @ObservationIgnored var onChange: ((AppSettings, AppSettings, SettingsImpact) -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(fileURL: URL = SettingsStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
            let loaded = try? JSONMerge.decode(AppSettings.self, from: data, defaults: AppSettings())
        {
            settings = loaded
        } else {
            settings = AppSettings()
        }
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "DanmakuOverlay/settings.json")
    }

    func update(_ body: (inout AppSettings) -> Void) {
        let old = settings
        var new = settings
        body(&new)
        guard new != old else { return }
        settings = new
        onChange?(old, new, SettingsImpact.between(old, new))
        scheduleSave()
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func resetToDefaults() { update { $0 = AppSettings() } }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Saving settings failed: \(error.localizedDescription)")
        }
    }
}
