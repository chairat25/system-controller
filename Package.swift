// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundControl",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SoundControl", targets: ["SoundControl"])
    ],
    targets: [
        // Pure value-type logic: models, synth, resolution rules. Swift 6 strict concurrency, fully unit tested.
        .target(name: "SoundControlCore"),
        // Catches NSExceptions that AVFAudio raises when the output device is gone.
        .target(name: "ObjCExceptionCatcher"),
        // The menu-bar app: system monitors (IOKit/CoreAudio C callbacks), audio engine, SwiftUI views.
        .executableTarget(
            name: "SoundControl",
            dependencies: ["SoundControlCore", "ObjCExceptionCatcher"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "SoundControlCoreTests", dependencies: ["SoundControlCore"]),
        .testTarget(name: "ObjCExceptionCatcherTests", dependencies: ["ObjCExceptionCatcher"])
    ]
)
