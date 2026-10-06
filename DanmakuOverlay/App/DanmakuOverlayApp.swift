import AppKit
import DanmakuCore
import SwiftUI

@main
struct DanmakuOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.danmakuVisible ? "captions.bubble.fill" : "captions.bubble")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    #if DEBUG
        private var previewWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("DanmakuOverlay started")
        #if DEBUG
            // Development hooks: DANMAKU_OPEN=<file> loads a file, DANMAKU_AUTOPLAY=<seconds> starts the manual
            // clock, DANMAKU_FOLLOW=1 attaches to the front-most known player, DANMAKU_SOURCE=<kind> picks an adapter,
            // DANMAKU_PREVIEW=hud|<settings tab> shows UI for screenshots.
            let env = ProcessInfo.processInfo.environment
            if let kind = env["DANMAKU_SOURCE"].flatMap(SourceKind.init(rawValue:)) {
                model.attach(kind, automatic: false)
            }
            switch env["DANMAKU_PREVIEW"] {
            case "hud":
                model.hud.show()
            case let tab?:
                let window = NSWindow(
                    contentViewController: NSHostingController(rootView: SettingsView(model: model, initialTab: tab)))
                window.title = "Settings preview"
                window.center()
                window.makeKeyAndOrderFront(nil)
                previewWindow = window
            case nil:
                break
            }
            if env["DANMAKU_FOLLOW"] != nil {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    model.followFrontmostPlayer()
                }
            }
            if let path = env["DANMAKU_OPEN"] {
                model.openDanmakuFile(URL(fileURLWithPath: path))
                if let start = env["DANMAKU_AUTOPLAY"].flatMap(Double.init) {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        model.seek(to: start)
                        model.togglePlayPause()
                    }
                }
            }
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.openDanmakuFile(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.settings.saveNow()
    }
}
