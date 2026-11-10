// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SlidePilotCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SlidePilotCore", targets: ["SlidePilotCore"]),
    ],
    targets: [
        .target(
            name: "SlidePilotCore",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SlidePilotCoreTests",
            dependencies: ["SlidePilotCore"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
