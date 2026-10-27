// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenJot",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Swift, no AppKit: palette quantization + GIF/LZW encoding.
        .target(
            name: "ScreenJotCore",
            path: "Sources/ScreenJotCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(
            name: "ScreenJot",
            dependencies: ["ScreenJotCore"],
            path: "Sources/ScreenJot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        // Command Line Tools ship without XCTest, so encoder tests live in a tiny executable.
        .executableTarget(
            name: "ScreenJotSelfTest",
            dependencies: ["ScreenJotCore"],
            path: "Sources/ScreenJotSelfTest"
        ),
    ]
)
