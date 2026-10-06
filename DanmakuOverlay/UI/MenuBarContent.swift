import DanmakuCore
import SwiftUI

/// Contents of the menu bar window.
struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            sourceSection
            TransportView(model: model)
            Divider()
            quickSettings
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "captions.bubble.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("DanmakuOverlay").font(.headline)
                Text(model.pipeline.title ?? String(localized: "No danmaku loaded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("Show", isOn: $model.danmakuVisible)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Show or hide danmaku")
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Open Danmaku…", systemImage: "doc.badge.plus") { model.presentOpenPanel() }
                Spacer()
                if model.pipeline.isBusy { ProgressView().controlSize(.small) }
            }
            if let error = model.pipeline.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(model.clock.status.isConnected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Menu {
                    ForEach(model.availableAdapters) { kind in
                        Button {
                            model.chooseAdapter(kind)
                        } label: {
                            if kind == model.clock.sourceKind {
                                Label(kind.displayName, systemImage: "checkmark")
                            } else {
                                Text(kind.displayName)
                            }
                        }
                    }
                } label: {
                    Text(model.clock.sourceKind?.displayName ?? String(localized: "No sync source"))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Sync adapter")
                Text(model.clock.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            PermissionHint(status: model.clock.status)
            HStack {
                TargetPickerMenu(model: model)
                if model.overlayMode != .off {
                    Button("Detach", systemImage: "xmark.circle") { model.turnOff() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Stop showing the overlay")
                }
            }
            .controlSize(.small)
            if model.tracker.isLost {
                Label("The followed window was closed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !AXSupport.isTrusted {
                Button {
                    AXSupport.requestTrust()
                    AXSupport.openAccessibilitySettings()
                } label: {
                    Label("Grant Accessibility for smooth window following", systemImage: "hand.raised")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Opacity") {
                Slider(value: model.settings.binding(\.display.opacity), in: 0.1...1)
                    .frame(width: 170)
            }
            LabeledContent("Font size") {
                Slider(value: model.settings.binding(\.display.fontScale), in: 0.5...2.5, step: 0.05)
                    .frame(width: 170)
            }
            LabeledContent("Speed") {
                Slider(value: model.settings.binding(\.display.rollDuration), in: 4...20, step: 0.5)
                    .frame(width: 170)
            }
            LabeledContent("Area") {
                Picker("Area", selection: model.settings.binding(\.display.displayArea)) {
                    Text("¼").tag(0.25)
                    Text("½").tag(0.5)
                    Text("¾").tag(0.75)
                    Text("Full").tag(1.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }
            if model.settings.settings.general.showStatistics {
                statistics
            }
        }
        .font(.callout)
    }

    private var statistics: some View {
        let c = model.pipeline.counts
        let r = model.renderStats
        return Text(
            "Loaded \(c.loaded) · shown \(c.afterFilter) · placed \(c.placed)\nLayers \(r.liveLayers) · images \(r.cachedImages) (\(r.cacheMegabytes, specifier: "%.1f") MB) · drift \(model.clock.driftMs, specifier: "%+.0f") ms"
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Button("Controls") { model.hud.toggle() }
                .help("Floating controls (⌃⌥H)")
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

/// Playback position, transport and danmaku offset.
struct TransportView: View {
    @Bindable var model: AppModel
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let now = model.clock.mediaTime
                let duration = model.clock.duration ?? model.pipeline.trackDuration ?? max(now, 1)
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { scrubbing ?? min(now, duration) },
                            set: { scrubbing = $0 }),
                        in: 0...max(duration, 1)
                    ) { editing in
                        if !editing, let target = scrubbing {
                            model.seek(to: target)
                            scrubbing = nil
                        }
                    }
                    .controlSize(.small)
                    HStack {
                        Text(TimeText.format(scrubbing ?? now))
                        Spacer()
                        Text(TimeText.format(duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                Button {
                    model.step(-model.settings.settings.sync.seekStep)
                } label: {
                    Image(systemName: Self.symbol("gobackward", step: model.settings.settings.sync.seekStep))
                }
                .help("Back")
                Button {
                    model.togglePlayPause()
                } label: {
                    Image(systemName: model.clock.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 20)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Play / Pause")
                Button {
                    model.step(model.settings.settings.sync.seekStep)
                } label: {
                    Image(systemName: Self.symbol("goforward", step: model.settings.settings.sync.seekStep))
                }
                .help("Forward")
                Spacer()
                OffsetControl(model: model)
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
    }
}

extension TransportView {
    /// SF Symbols only exist for some step sizes.
    static func symbol(_ base: String, step: Double) -> String {
        let s = Int(step)
        return [5, 10, 15, 30, 45, 60, 75, 90].contains(s) && Double(s) == step ? "\(base).\(s)" : base
    }
}

struct OffsetControl: View {
    @Bindable var model: AppModel

    var body: some View {
        let step = model.settings.settings.sync.offsetStep
        HStack(spacing: 4) {
            Button {
                model.adjustOffset(-step)
            } label: {
                Image(systemName: "minus.circle")
            }
            .help("Danmaku earlier")
            Button {
                model.resetOffset()
            } label: {
                Text(TimeText.offset(model.clock.userOffset))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 44)
            }
            .help("Danmaku delay — click to reset")
            Button {
                model.adjustOffset(step)
            } label: {
                Image(systemName: "plus.circle")
            }
            .help("Danmaku later")
        }
        .font(.body)
    }
}

/// Explains how to fix a sync adapter that lacks a permission or setup step.
struct PermissionHint: View {
    let status: SourceStatus

    var body: some View {
        switch status {
        case .needsPermission(.automation):
            Button("Open Automation Settings…") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            .buttonStyle(.link)
            .font(.caption)
        case .needsPermission(.browserJavaScript):
            Text(
                "Safari: Settings › Advanced › Show features for web developers, then Develop › Allow JavaScript from Apple Events. Chrome: View › Developer › Allow JavaScript from Apple Events."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .needsSetup(let hint) where hint.contains("IPC"):
            IINASetupHint()
        default:
            EmptyView()
        }
    }
}
