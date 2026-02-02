// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WhisperClipMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WhisperClipMenuBar", targets: ["WhisperClipMenuBarApp"]),
    ],
    targets: [
        .executableTarget(
            name: "WhisperClipMenuBarApp",
            path: "Sources/WhisperClipMenuBarApp"
        ),
    ]
)
