import AppKit
import SwiftUI
import DuskUI

/// The popover's window: borderless, floating just under the status item.
///
/// A panel rather than `NSPopover`, which adds a pointer arrow and forces its
/// own translucent material — both fight a design that is black by intent.
/// Non-activating, so opening it does not pull Dusk to the front, but allowed
/// to become key, so Esc reaches it.
@MainActor
final class DuskPanel: NSPanel {
    /// Called once each time the popover goes away, however it went.
    var onClose: () -> Void = {}

    private let model: PopoverModel
    private var outsideClicks: Any?
    private var escapeKey: Any?
    private var appSwitch: NSObjectProtocol?
    private var dismissedAt = Date.distantPast
    private var isDismissing = false

    init(model: PopoverModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = NSHostingView(rootView: PopoverView(model: model))
    }

    override var canBecomeKey: Bool { true }

    /// The click that took the popover's focus away can be the same click that
    /// lands on the status item a moment later. Without this the icon would
    /// close the popover and reopen it in one press.
    var wasJustDismissed: Bool { Date().timeIntervalSince(dismissedAt) < 0.3 }

    /// Places the popover under the status item, kept inside the screen — the
    /// icon sits at the far right of the menu bar, where a centred popover would
    /// otherwise run off the edge.
    func show(below button: NSStatusBarButton) {
        guard let anchorWindow = button.window,
              let screen = anchorWindow.screen ?? NSScreen.main,
              let content = contentView else { return }
        model.isVisible = true
        let size = content.fittingSize
        setContentSize(size)
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        setFrameOrigin(NSPoint(x: x, y: anchor.minY - 6 - size.height))
        makeKeyAndOrderFront(nil)
        invalidateShadow()
        watchForDismissal()
        Log.ui.notice("popover opened at \(NSStringFromRect(self.frame), privacy: .public), key=\(self.isKeyWindow, privacy: .public)")
    }

    func dismiss(_ reason: String = "app") {
        guard isVisible, !isDismissing else { return }
        Log.ui.notice("popover closed: \(reason, privacy: .public)")
        isDismissing = true
        defer { isDismissing = false }
        stopWatching()
        orderOut(nil)
        model.isVisible = false
        dismissedAt = Date()
        onClose()
    }

    /// Clicks anywhere outside, and switching to another app, are watched for
    /// directly; Esc arrives as a key event to this panel. Losing key focus is
    /// deliberately not a signal: the app in front can take key back on its own
    /// — measured: a window updating in the front app closed the popover 1.2s
    /// after it opened, with no click at all.
    private func watchForDismissal() {
        stopWatching()
        appSwitch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss("app switch") }
        }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss("outside click") }
        }
        escapeKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            MainActor.assumeIsolated { self?.dismiss("escape") }
            return nil
        }
    }

    private func stopWatching() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        if let escapeKey { NSEvent.removeMonitor(escapeKey) }
        if let appSwitch { NSWorkspace.shared.notificationCenter.removeObserver(appSwitch) }
        appSwitch = nil
        outsideClicks = nil
        escapeKey = nil
    }
}
