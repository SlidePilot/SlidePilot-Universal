// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SlidePilotRendering",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SlidePilotRendering", targets: ["SlidePilotRendering"]),
    ],
    dependencies: [
        .package(path: "../SlidePilotCore"),
    ],
    targets: [
        .target(
            name: "SlidePilotRendering",
            dependencies: [
                .product(name: "SlidePilotCore", package: "SlidePilotCore"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SlidePilotRenderingTests",
            dependencies: ["SlidePilotRendering"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
