// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DanmakuKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DanmakuCore", targets: ["DanmakuCore"]),
        .library(name: "DanmakuText", targets: ["DanmakuText"]),
    ],
    targets: [
        .target(
            name: "DanmakuCore",
            resources: [.copy("Resources/pinyin.bin")]
        ),
        .target(name: "DanmakuText", dependencies: ["DanmakuCore"]),
        .testTarget(
            name: "DanmakuCoreTests",
            dependencies: ["DanmakuCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DanmakuTextTests", dependencies: ["DanmakuText"]),
    ]
)
