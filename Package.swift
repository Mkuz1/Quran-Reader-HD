// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MushafMac",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MushafMac",
            path: "Sources/MushafMac",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
