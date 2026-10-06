import AppKit
import Carbon.HIToolbox

/// Global shortcuts. Carbon hot keys need no permission; every default uses ⌃⌥ because macOS rejects
/// hot keys whose only modifiers are ⌥ / ⌥⇧.
final class HotkeyCenter {
    enum Action: UInt32, CaseIterable, Identifiable {
        case toggleDanmaku = 1
        case playPause
        case seekBackward
        case seekForward
        case offsetEarlier
        case offsetLater
        case toggleControls
        case attachFrontmost

        var id: UInt32 { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .toggleDanmaku: "Show / hide danmaku"
            case .playPause: "Play / pause"
            case .seekBackward: "Seek backward"
            case .seekForward: "Seek forward"
            case .offsetEarlier: "Danmaku earlier"
            case .offsetLater: "Danmaku later"
            case .toggleControls: "Show / hide controls"
            case .attachFrontmost: "Attach to front-most player"
            }
        }

        /// (virtual key code, display string)
        var key: (code: Int, label: String) {
            switch self {
            case .toggleDanmaku: (kVK_ANSI_D, "D")
            case .playPause: (kVK_ANSI_P, "P")
            case .seekBackward: (kVK_LeftArrow, "←")
            case .seekForward: (kVK_RightArrow, "→")
            case .offsetEarlier: (kVK_ANSI_LeftBracket, "[")
            case .offsetLater: (kVK_ANSI_RightBracket, "]")
            case .toggleControls: (kVK_ANSI_H, "H")
            case .attachFrontmost: (kVK_ANSI_A, "A")
            }
        }

        var shortcut: String { "⌃⌥" + key.label }
    }

    var onAction: ((Action) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func enable() {
        guard refs.isEmpty else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, refcon in
            guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, let action = Action(rawValue: id.id) else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { center.onAction?(action) }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let modifiers = UInt32(controlKey | optionKey)
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x444D_4B4F), id: action.rawValue)  // 'DMKO'
            if RegisterEventHotKey(UInt32(action.key.code), modifiers, id, GetApplicationEventTarget(), 0, &ref)
                == noErr, let ref
            {
                refs.append(ref)
            } else {
                Log.app.error("Could not register hot key \(action.shortcut)")
            }
        }
    }

    func disable() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
