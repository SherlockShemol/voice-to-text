// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VoiceToText",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceToText",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/VoiceToText",
            resources: [
                .copy("Resources/polish_prompt")
            ]
        ),
        .testTarget(
            name: "VoiceToTextTests",
            dependencies: [
                "VoiceToText",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/VoiceToTextTests"
        )
    ]
)
