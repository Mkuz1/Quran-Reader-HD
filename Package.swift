// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MushafMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MushafMac",
            path: "Sources/MushafMac",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
