import AppKit
import Carbon.HIToolbox

/// Mirrors the player's own transport keys (Space, ←, →) onto the manual clock while the followed player is
/// the front-most app. Listen-only: the keys still reach the player. Requires Accessibility.
final class KeyMirror {
    enum Event { case togglePlayPause, step(Double) }

    var onEvent: ((Event) -> Void)?
    private var monitor: Any?

    func start(pid: pid_t, step: Double) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                    event.modifierFlags.intersection([.command, .control, .option]).isEmpty, !event.isARepeat
                else { return }
                switch Int(event.keyCode) {
                case kVK_Space: self?.onEvent?(.togglePlayPause)
                case kVK_LeftArrow: self?.onEvent?(.step(-step))
                case kVK_RightArrow: self?.onEvent?(.step(step))
                default: break
                }
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
