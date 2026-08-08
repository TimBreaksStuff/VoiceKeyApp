// swift-tools-version:5.10
// 5.10 deliberately: Swift 5 language mode, no strict-concurrency fights in audio callbacks
import PackageDescription

let package = Package(
    name: "VoiceKey",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        // Pure, testable logic — no AppKit, no WhisperKit
        .target(name: "VoiceKeyCore"),
        .executableTarget(
            name: "VoiceKey",
            dependencies: [
                "VoiceKeyCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(name: "VoiceKeyCoreTests", dependencies: ["VoiceKeyCore"]),
    ]
)
