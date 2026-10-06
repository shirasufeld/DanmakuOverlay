import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "DanmakuOverlay"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let tracking = Logger(subsystem: subsystem, category: "tracking")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
}
