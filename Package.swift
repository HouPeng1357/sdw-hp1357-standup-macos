// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sdw-hp1357-standup-macos",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SDWStandup",
            path: "Sources/SDWStandup"
        )
    ]
)
