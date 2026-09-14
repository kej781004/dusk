import AppKit

@main
struct DuskApp {
    /// NSApplication holds its delegate weakly, so it has to be owned somewhere
    /// that outlives the call to `run()`.
    @MainActor static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        // Menu bar only: no Dock icon, no app menu.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
