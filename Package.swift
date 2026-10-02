// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dusk",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic. No AppKit, no IOKit — everything here is testable by DuskCheck.
        .target(name: "DuskCore"),

        // Everything that only draws: the menu bar icon and the popover. Kept out
        // of the app so DuskPreview can render it without launching anything.
        .target(name: "DuskUI", dependencies: ["DuskCore"]),

        // The menu bar app itself.
        .executableTarget(name: "Dusk", dependencies: ["DuskCore", "DuskUI"]),

        // Xcode isn't installed on this Mac, so XCTest is unavailable.
        // Verification runs as a plain executable: `swift run DuskCheck`.
        .executableTarget(name: "DuskCheck", dependencies: ["DuskCore"]),

        // Renders the popover in each state to PNG from the real view code.
        .executableTarget(name: "DuskPreview", dependencies: ["DuskCore", "DuskUI"]),
    ]
)
