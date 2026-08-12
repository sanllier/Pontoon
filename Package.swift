// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pontoon",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "Pontoon",
            targets: ["Pontoon"]
        )
    ],
    targets: [
        .target(
            name: "Pontoon",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PontoonTests",
            dependencies: ["Pontoon"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
