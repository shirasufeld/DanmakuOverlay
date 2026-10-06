import AppKit
import SwiftUI

/// A small floating Liquid Glass control panel. Non-activating, so the player keeps keyboard focus.
final class ControlHUD {
    private var panel: NSPanel?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 120),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: ControlHUDView(model: model, close: { [weak self] in self?.hide() }))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        return panel
    }

    /// Bottom centre of the danmaku area, or of the screen.
    private func position(_ panel: NSPanel) {
        var size = panel.contentView?.fittingSize ?? panel.frame.size
        if size.height < 10 { size = panel.frame.size }
        let area =
            model.overlayMode != .off && model.contentFrame.width > 0
            ? model.contentFrame : (NSScreen.main?.visibleFrame ?? .zero)
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + 24)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

struct ControlHUDView: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble.fill").foregroundStyle(.tint)
                Text(model.pipeline.title ?? String(localized: "No danmaku loaded"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(model.clock.sourceKind?.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show", isOn: $model.danmakuVisible).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            TransportView(model: model)
        }
        .padding(14)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openDanmakuFile(url)
            return true
        }
    }
}
