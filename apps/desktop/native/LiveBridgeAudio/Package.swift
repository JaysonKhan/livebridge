// swift-tools-version:5.9
import PackageDescription

// The audio engine is a plain Swift package so it can be built, unit-tested and driven from a CLI (`lbaudio`)
// without Flutter. The Flutter macOS Runner links the `LiveBridgeAudioCore` library product.
let package = Package(
    name: "LiveBridgeAudio",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "LiveBridgeAudioCore", targets: ["LiveBridgeAudioCore"]),
        .executable(name: "lbaudio", targets: ["lbaudio"]),
    ],
    targets: [
        .target(name: "CAtomicsShim"),
        .target(name: "LiveBridgeAudioCore", dependencies: ["CAtomicsShim"]),
        .executableTarget(
            name: "lbaudio",
            dependencies: ["LiveBridgeAudioCore"],
            linkerSettings: [
                // Embeds the usage descriptions so the CLI can ask for microphone / system-audio access itself.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/lbaudio/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "LiveBridgeAudioCoreTests", dependencies: ["LiveBridgeAudioCore"]),
    ]
)
