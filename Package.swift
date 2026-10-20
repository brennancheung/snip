// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snip",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Snip", targets: ["Snip"]),
        .executable(name: "snip-cli", targets: ["snip-cli"]),
    ],
    targets: [
        // Models, settings, output naming and the ffmpeg CRF encoder. No UI, no ScreenCaptureKit.
        .target(name: "SnipCore"),
        // ScreenCaptureKit recording of a CaptureTarget to a high-quality intermediate file.
        .target(name: "SnipCapture", dependencies: ["SnipCore"]),
        // Hotkey, selection overlay, recording HUD, menu bar, settings window, app controller.
        .target(name: "SnipUI", dependencies: ["SnipCore", "SnipCapture"]),
        // The menu bar app (bundled into Snip.app by bin/build-app).
        .executableTarget(name: "Snip", dependencies: ["SnipUI"]),
        // Command-line driver for the capture and encode libraries, no UI.
        .executableTarget(name: "snip-cli", dependencies: ["SnipCore", "SnipCapture"]),
        .testTarget(name: "SnipCoreTests", dependencies: ["SnipCore"]),
    ],
    swiftLanguageModes: [.v5]
)
