import AppKit
import SwiftUI

/// Menu listing windows the overlay can follow, known players first.
struct TargetPickerMenu: View {
    @Bindable var model: AppModel
    @State private var candidates: [CandidateWindow] = []

    var body: some View {
        Menu {
            if candidates.isEmpty {
                Text("No windows found")
            }
            ForEach(sorted, id: \.id) { c in
                Button {
                    model.follow(c)
                } label: {
                    Label {
                        Text(label(for: c))
                    } icon: {
                        icon(for: c)
                    }
                }
            }
            Divider()
            Button("Cover Screen Under Mouse") { model.useFreeMode() }
        } label: {
            Label(currentTitle, systemImage: "macwindow.on.rectangle")
                .lineLimit(1)
        }
        .menuStyle(.button)
        .onAppear { candidates = WindowCatalog.candidates() }
        .onHover { inside in if inside { candidates = WindowCatalog.candidates() } }
    }

    private var sorted: [CandidateWindow] {
        candidates.sorted { a, b in
            let pa = PlayerCatalog.isKnownPlayer(a.bundleID)
            let pb = PlayerCatalog.isKnownPlayer(b.bundleID)
            return pa != pb ? pa : false
        }
    }

    private var currentTitle: String {
        switch model.overlayMode {
        case .off: String(localized: "Attach to Window")
        case .free: String(localized: "Covering Screen")
        case .following: model.tracker.target.map { "\($0.appName)" } ?? String(localized: "Following")
        }
    }

    private func label(for c: CandidateWindow) -> String {
        let size = "\(Int(c.info.bounds.width))×\(Int(c.info.bounds.height))"
        return c.title.isEmpty ? "\(c.appName) — \(size)" : "\(c.appName) — \(c.title)"
    }

    private func icon(for c: CandidateWindow) -> Image {
        if let app = NSRunningApplication(processIdentifier: c.info.pid), let icon = app.icon {
            return Image(nsImage: icon)
        }
        return Image(systemName: "macwindow")
    }
}
