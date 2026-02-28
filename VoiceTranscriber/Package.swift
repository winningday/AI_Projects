// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceTranscriber",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoiceTranscriber", targets: ["VoiceTranscriber"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceTranscriber",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "VoiceTranscriber",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
