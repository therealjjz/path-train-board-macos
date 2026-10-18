// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tubes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        // Feed models and fetching. Foundation only, so it also builds on Linux.
        .library(name: "TubesFeed", targets: ["TubesFeed"]),
        // LED renderer, board layout and the polling store (SwiftUI, Apple platforms).
        .library(name: "TubesUI", targets: ["TubesUI"]),
        .executable(name: "TubesMac", targets: ["TubesMac"]),
    ],
    targets: [
        .target(name: "TubesFeed"),
        .target(name: "TubesUI", dependencies: ["TubesFeed"]),
        .executableTarget(name: "TubesMac", dependencies: ["TubesFeed", "TubesUI"]),
        .testTarget(name: "TubesFeedTests", dependencies: ["TubesFeed"]),
    ],
    swiftLanguageModes: [.v5]
)
