import AppKit
import DanmakuCore
import SwiftUI

/// Helps the user enable mpv's IPC socket in IINA (Settings › Advanced › Additional mpv options).
enum IINASetup {
    static let optionName = "input-ipc-server"

    static func optionValue(socketPath: String) -> String { socketPath }

    /// Whether IINA's stored mpv options already contain the IPC server.
    static func isConfigured(socketPath: String) -> Bool {
        let options =
            CFPreferencesCopyAppValue("userOptions" as CFString, PlayerCatalog.iina as CFString) as? [[String]]
        return options?.contains { $0.count == 2 && $0[0] == optionName && $0[1] == socketPath } ?? false
    }

    static var isIINARunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: PlayerCatalog.iina).isEmpty
    }

    /// Adds `input-ipc-server` to IINA's additional mpv options. IINA must not be running (it rewrites its
    /// preferences on quit) and needs advanced settings enabled.
    static func configure(socketPath: String) -> Bool {
        guard !isIINARunning else { return false }
        let app = PlayerCatalog.iina as CFString
        var options = CFPreferencesCopyAppValue("userOptions" as CFString, app) as? [[String]] ?? []
        options.removeAll { $0.first == optionName }
        options.append([optionName, socketPath])
        CFPreferencesSetAppValue("userOptions" as CFString, options as CFArray, app)
        CFPreferencesSetAppValue("enableAdvancedSettings" as CFString, true as CFBoolean, app)
        return CFPreferencesAppSynchronize(app)
    }
}

struct IINASetupHint: View {
    @State private var message: String?
    private let socketPath = SyncSettings().mpvSocketPath

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "For frame-accurate sync with IINA, add the mpv option “\(IINASetup.optionName)=\(socketPath)” in IINA › Settings › Advanced."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Copy Option") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(IINASetup.optionName)=\(socketPath)", forType: .string)
                    message = String(localized: "Copied")
                }
                Button("Configure IINA") {
                    message =
                        IINASetup.configure(socketPath: socketPath)
                        ? String(localized: "Done — open your video in IINA again")
                        : String(localized: "Quit IINA first, then try again")
                }
                .help("Writes the option into IINA's preferences. IINA must be quit.")
            }
            .controlSize(.small)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
