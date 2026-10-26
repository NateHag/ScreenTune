// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ScreenTune",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ScreenTune", path: "Sources/ScreenTune")
    ]
)
