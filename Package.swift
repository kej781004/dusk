// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dusk",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic. No AppKit, no IOKit — everything here is testable by DuskCheck.
        .target(name: "DuskCore"),

        // The menu bar app itself.
        .executableTarget(name: "Dusk", dependencies: ["DuskCore"]),

        // Xcode isn't installed on this Mac, so XCTest is unavailable.
        // Verification runs as a plain executable: `swift run DuskCheck`.
        .executableTarget(name: "DuskCheck", dependencies: ["DuskCore"]),
    ]
)
