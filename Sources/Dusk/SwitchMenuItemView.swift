import AppKit

/// A menu row carrying an `NSSwitch` instead of a checkmark.
///
/// AppKit has no switch-style menu item, so the row is a custom view: title on
/// the left, switch on the right. Two things a view item does not get for free
/// and has to do itself — the whole row has to be clickable, not just the
/// switch, and it has to draw its own hover highlight, or it looks dead next to
/// the ordinary items above it.
@MainActor
final class SwitchMenuItemView: NSView {
    /// Lines the title up with the ordinary items, which reserve a column for
    /// the checkmark whether or not they are carrying one.
    private static let titleInset: CGFloat = 21
    private static let switchInset: CGFloat = 13
    private static let rowHeight: CGFloat = 26
    /// Only a floor: a menu is as wide as its widest item, and the submenu rows
    /// above this one are wider. Autoresizing stretches the view to match.
    private static let rowWidth: CGFloat = 220
    /// The inset and corner AppKit uses for its own highlight capsule.
    private static let highlightInset: CGFloat = 5
    private static let highlightRadius: CGFloat = 4

    private let label = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()
    private let onFlip: (Bool) -> Void
    private var hovered = false
    /// Set by the mouse down so the mouse up does not flip the same click back.
    private var flippedThisGesture = false

    init(title: String, isOn: Bool, isEnabled: Bool, onFlip: @escaping (Bool) -> Void) {
        self.onFlip = onFlip
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))
        autoresizingMask = [.width]

        label.stringValue = title
        label.font = .menuFont(ofSize: 0)
        label.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // No target/action: the switch is never allowed to receive a click, so it
        // could never fire one. See `hitTest` below.
        toggle.state = isOn ? .on : .off
        toggle.isEnabled = isEnabled
        toggle.controlSize = .mini
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.switchInset),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SwitchMenuItemView is created in code only") }

    /// Wraps the view in the menu item that carries it.
    static func item(title: String,
                     isOn: Bool,
                     isEnabled: Bool,
                     onFlip: @escaping (Bool) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SwitchMenuItemView(title: title, isOn: isOn, isEnabled: isEnabled, onFlip: onFlip)
        return item
    }

    // MARK: - Highlight

    // The menu window does deliver enter/exit while it is tracking, and this is
    // more dependable than watching `NSMenuItem.isHighlighted`, which AppKit does
    // not promise to redraw a view item for.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard toggle.isEnabled else { return }
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovered else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Self.highlightInset, dy: 0),
                     xRadius: Self.highlightRadius,
                     yRadius: Self.highlightRadius).fill()
    }

    // MARK: - Flipping

    /// The whole row answers to the mouse, the switch included.
    ///
    /// This is the bug the row shipped with. Left to itself, hit testing hands a
    /// click that lands on the switch straight to `NSSwitch`, which answers a
    /// mouse down by running its own tracking loop — and inside menu tracking that
    /// loop never sees the matching mouse up, so the gesture is swallowed and the
    /// switch does not move. Aiming at the switch, the one obvious target, was the
    /// one place that did nothing; hitting the title beside it worked.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let converted = superview?.convert(point, to: self) else { return nil }
        return bounds.contains(converted) ? self : nil
    }

    /// A menu decides for itself which half of a click reaches a view item, and
    /// does not promise both. Either half flips the row, and `flippedThisGesture`
    /// keeps a click that arrives whole from counting twice.
    override func mouseDown(with event: NSEvent) {
        guard toggle.isEnabled, contains(event) else { return }
        flippedThisGesture = true
        flip()
    }

    override func mouseUp(with event: NSEvent) {
        defer { flippedThisGesture = false }
        guard !flippedThisGesture, toggle.isEnabled, contains(event) else { return }
        flip()
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private func flip() {
        toggle.state = (toggle.state == .on) ? .off : .on
        onFlip(toggle.state == .on)
    }
}
