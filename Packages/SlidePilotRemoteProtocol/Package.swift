// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SlidePilotRemoteProtocol",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SlidePilotRemoteProtocol", targets: ["SlidePilotRemoteProtocol"]),
    ],
    dependencies: [
        .package(path: "../SlidePilotCore"),
    ],
    targets: [
        .target(
            name: "SlidePilotRemoteProtocol",
            dependencies: [
                .product(name: "SlidePilotCore", package: "SlidePilotCore"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SlidePilotRemoteProtocolTests",
            dependencies: ["SlidePilotRemoteProtocol"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
