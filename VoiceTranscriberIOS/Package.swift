// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceTranscriberIOS",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ]
)
