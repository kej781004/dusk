# Dusk Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Dusk's right-click `NSMenu` with the approved black-and-white "Obsidian" popover, and turn the menu bar icon monochrome.

**Architecture:** A new `DuskUI` library target holds everything that only draws — the status icon, an `ObservableObject` model, and the SwiftUI popover view — so a `DuskPreview` executable can render the real view to PNG for checking. Pure ruler and countdown arithmetic goes in `DuskCore` under `DuskCheck`. The app target gains a borderless `NSPanel` that hosts the view, and `AppDelegate` swaps the menu for it, driving the same methods the menu drove.

**Tech Stack:** Swift 6.4 toolchain in Swift 5 language mode, SwiftPM, AppKit, SwiftUI (macOS 13), command-line tools only — no Xcode.

**Spec:** `docs/superpowers/specs/2026-10-02-dusk-popover-design.md`

## Global Constraints

- Platform floor stays macOS 13 (`.macOS(.v13)` in `Package.swift`).
- No `@State`, no `@Observable`, no `#Preview` — the macro plugins are not in the command-line tools. Shared state lives in `ObservableObject` / `@Published`.
- Colour: the Obsidian palette only — ground `#0B0B0C`, dial glow `#232325`, ink `#F4F4F2`, white hairlines at .07 / .08 / .12 opacity. No hue anywhere in the popover or the icon.
- Panel 320pt wide, corner radius 20.
- Nothing animates while the popover is closed; the pill highlight's `TimelineView` is capped at 30 fps and the countdown's at 1 s.
- Left click on the icon stays: on for 15 minutes / off. A click on the icon while the popover is open only closes it.
- Copy is English and exactly as in the spec's state table.
- Verification is `make check` (DuskCheck) — XCTest is unavailable. Install with `make install`.

## Review Focus

- Clicking the icon while the popover is open: it must close and stay closed, not close and reopen in the same click (the panel resigning key races the status item's mouse-up). Pinned in Task 7, Step 3.
- A privilege prompt or pmset error raised while the popover is open: the popover must close first so the alert is in front, never hidden behind a floating panel. Pinned in Task 6, Step 6.
- The status item sits at the far right of the menu bar: the panel must land fully on screen, not run off the edge. Pinned in Task 7, Step 2.
- A closed popover must cost nothing — no highlight or countdown still ticking in WindowServer. Pinned in Task 7, Step 5.
- A countdown running out while the popover is open must flip it to "Off", never show `0:00` with time left or a negative time. Pinned in Task 2, Step 1 (format) and Task 6, Step 3 (`syncPopover` on every refresh).

---

### Task 1: Ruler stops (`DurationScale`)

**Files:**
- Create: `Sources/DuskCore/DurationScale.swift`
- Test: `Sources/DuskCheck/main.swift` (append before `Check.summarize()`)

**Interfaces:**
- Produces: `DurationScale.count: Int`, `lastIndex: Int`, `labels: [DurationScale.Label]` (`Label.index: Int`, `Label.text: String`), `fraction(forStop: Int) -> Double`, `nearestStop(toFraction: Double) -> Int`, `minutes(atStop: Int) -> Int?`, `stop(forMinutes: Int?) -> Int`.

- [ ] **Step 1: Write the failing tests** — insert above the final `Check.summarize()` in `Sources/DuskCheck/main.swift`:

```swift
print("DurationScale")

Check.test("25 stops: five-minute steps to an hour, fifteen to four, then until-off") {
    Check.equal(DurationScale.count, 25)
    Check.equal(DurationScale.minutes(atStop: 0), 5)
    Check.equal(DurationScale.minutes(atStop: 11), 60)
    Check.equal(DurationScale.minutes(atStop: 12), 75)
    Check.equal(DurationScale.minutes(atStop: 23), 240)
    Check.equal(DurationScale.minutes(atStop: 24), nil)
}

Check.test("every label sits on the stop it names") {
    let expected: [String: Int?] = ["5m": 5, "30m": 30, "1h": 60, "2h": 120, "4h": 240, "∞": nil]
    Check.equal(DurationScale.labels.count, 6)
    for label in DurationScale.labels {
        Check.equal(DurationScale.minutes(atStop: label.index), expected[label.text]!, label.text)
    }
}

Check.test("the ends of the ruler are the first and last stops") {
    Check.close(Float(DurationScale.fraction(forStop: 0)), 0)
    Check.close(Float(DurationScale.fraction(forStop: 24)), 1)
    Check.close(Float(DurationScale.fraction(forStop: 12)), 0.5)
}

Check.test("a drag snaps to the nearer stop either side of the midpoint") {
    let gap = 1.0 / 24.0
    Check.equal(DurationScale.nearestStop(toFraction: 5 * gap + gap * 0.49), 5)
    Check.equal(DurationScale.nearestStop(toFraction: 5 * gap + gap * 0.51), 6)
}

Check.test("a drag past either end clamps instead of running off") {
    Check.equal(DurationScale.nearestStop(toFraction: -0.4), 0)
    Check.equal(DurationScale.nearestStop(toFraction: 1.7), 24)
}

Check.test("every stop survives a round trip through its position") {
    for i in 0..<DurationScale.count {
        Check.equal(DurationScale.nearestStop(toFraction: DurationScale.fraction(forStop: i)), i, "stop \(i)")
    }
}

Check.test("a duration finds its stop, or the nearest one") {
    Check.equal(DurationScale.stop(forMinutes: 15), 2)
    Check.equal(DurationScale.stop(forMinutes: 120), 15)
    Check.equal(DurationScale.stop(forMinutes: nil), 24)
    Check.equal(DurationScale.stop(forMinutes: 1), 0)
    Check.equal(DurationScale.stop(forMinutes: 1000), 23)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make check`
Expected: compile error, `cannot find 'DurationScale' in scope`.

- [ ] **Step 3: Implement** — create `Sources/DuskCore/DurationScale.swift`:

```swift
import Foundation

/// The stops on the popover's duration ruler.
///
/// Evenly spaced on screen but not in time: five-minute steps to an hour, then
/// fifteen-minute steps to four hours, then "until turned off". Short durations
/// are the common choice, so the first hour gets the left half of the ruler.
///
/// Pure arithmetic, kept out of the view so the snapping can be tested without
/// a mouse — the same reason `ThresholdScale` exists.
public enum DurationScale {
    /// One labelled stop under the ruler.
    public struct Label: Hashable {
        public let index: Int
        public let text: String
    }

    /// Minutes at each stop; `nil` is the last stop, "until turned off".
    public static let stops: [Int?] =
        Array(stride(from: 5, through: 60, by: 5)) + Array(stride(from: 75, through: 240, by: 15)) + [nil]

    public static var count: Int { stops.count }
    public static var lastIndex: Int { stops.count - 1 }

    public static let labels: [Label] = [
        Label(index: 0, text: "5m"), Label(index: 5, text: "30m"), Label(index: 11, text: "1h"),
        Label(index: 15, text: "2h"), Label(index: 23, text: "4h"), Label(index: 24, text: "∞"),
    ]

    /// Where a stop sits along the ruler, 0…1.
    public static func fraction(forStop index: Int) -> Double {
        Double(min(max(index, 0), lastIndex)) / Double(lastIndex)
    }

    /// The stop nearest a point on the ruler. Positions outside 0…1 clamp, so a
    /// drag that leaves the ruler still tracks the nearer end.
    public static func nearestStop(toFraction fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * Double(lastIndex)).rounded())
    }

    /// Minutes at a stop, or nil for "until turned off".
    public static func minutes(atStop index: Int) -> Int? {
        stops[min(max(index, 0), lastIndex)]
    }

    /// The stop showing a duration: exact where one exists, otherwise the
    /// nearest, so any stored value still lands somewhere sensible. nil is the
    /// last stop.
    public static func stop(forMinutes minutes: Int?) -> Int {
        guard let minutes else { return lastIndex }
        var best = 0
        var bestDistance = Int.max
        for (index, value) in stops.enumerated() {
            guard let value else { continue }
            let distance = abs(value - minutes)
            if distance < bestDistance { best = index; bestDistance = distance }
        }
        return best
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `make check`
Expected: `PASS — 63 checks` (56 existing + 7 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/DuskCore/DurationScale.swift Sources/DuskCheck/main.swift
git commit -m "feat: duration ruler stops for the popover"
```

---

### Task 2: Countdown text and the battery resume level

**Files:**
- Create: `Sources/DuskCore/CountdownFormat.swift`
- Modify: `Sources/DuskCore/AutoOffPolicy.swift` (the `decide` resume branch; new `resumeLevel`)
- Test: `Sources/DuskCheck/main.swift`

**Interfaces:**
- Produces: `CountdownFormat.string(seconds: TimeInterval) -> String`; `AutoOffPolicy.resumeLevel(threshold: Int, hysteresis: Int = 5) -> Int`.

- [ ] **Step 1: Write the failing tests** — insert above `Check.summarize()`:

```swift
print("CountdownFormat")

Check.test("minutes and seconds under an hour") {
    Check.equal(CountdownFormat.string(seconds: 720), "12:00")
    Check.equal(CountdownFormat.string(seconds: 59), "0:59")
}

Check.test("hours once there are any") {
    Check.equal(CountdownFormat.string(seconds: 3900), "1:05:00")
}

Check.test("rounds up, so time still left never reads 0:00") {
    Check.equal(CountdownFormat.string(seconds: 0.2), "0:01")
    Check.equal(CountdownFormat.string(seconds: 3599.4), "1:00:00")
}

Check.test("a countdown already over reads 0:00, never negative") {
    Check.equal(CountdownFormat.string(seconds: 0), "0:00")
    Check.equal(CountdownFormat.string(seconds: -5), "0:00")
}

print("AutoOffPolicy.resumeLevel")

Check.test("resumes five points above the floor") {
    Check.equal(AutoOffPolicy.resumeLevel(threshold: 20), 25)
}

Check.test("never asks for more than a full battery") {
    Check.equal(AutoOffPolicy.resumeLevel(threshold: 98), 100)
    Check.equal(AutoOffPolicy.resumeLevel(threshold: 100), 100)
}

Check.test("decide resumes exactly at the resume level, not before") {
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 24, onAC: true, threshold: 20), .none)
    Check.equal(AutoOffPolicy.decide(intent: true, suspended: true, percent: 25, onAC: true, threshold: 20), .resume)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make check`
Expected: compile errors for `CountdownFormat` and `resumeLevel`.

- [ ] **Step 3: Implement** — create `Sources/DuskCore/CountdownFormat.swift`:

```swift
import Foundation

/// A running countdown the way the popover's numerals show it.
public enum CountdownFormat {
    /// `12:00`, `1:05:00`, `0:59`. Rounds up to the whole second, so a countdown
    /// with any time left never reads `0:00`; one already over never goes
    /// negative.
    public static func string(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
```

In `Sources/DuskCore/AutoOffPolicy.swift`, replace

```swift
        if suspended, onAC, percent >= min(threshold + hysteresis, 100) {
```

with

```swift
        if suspended, onAC, percent >= resumeLevel(threshold: threshold, hysteresis: hysteresis) {
```

and add, after `shouldKeepOverride`:

```swift
    /// The charge at which a suspended Dusk comes back on: the floor plus the
    /// hysteresis, capped at a full battery. Exposed so the popover can say
    /// "resumes past 25%" from the same number `decide` acts on, rather than a
    /// second copy of the sum that could drift from it.
    public static func resumeLevel(threshold: Int, hysteresis: Int = 5) -> Int {
        min(threshold + hysteresis, 100)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `make check`
Expected: `PASS — 70 checks`.

- [ ] **Step 5: Commit**

```bash
git add Sources/DuskCore/CountdownFormat.swift Sources/DuskCore/AutoOffPolicy.swift Sources/DuskCheck/main.swift
git commit -m "feat: countdown text and battery resume level for the popover"
```

---

### Task 3: `DuskUI` target and the monochrome icon

**Files:**
- Modify: `Package.swift`
- Move: `Sources/Dusk/StatusIcon.swift` → `Sources/DuskUI/StatusIcon.swift` (make public, recolour)
- Modify: `Sources/Dusk/AppDelegate.swift:1-3` (import)

**Interfaces:**
- Produces: `public enum StatusIcon { public static func image(active: Bool, timer: Bool) -> NSImage }` in module `DuskUI`.

- [ ] **Step 1: Restructure the package** — `Package.swift` targets become:

```swift
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
```

Create `Sources/DuskPreview/main.swift` with a single line for now so the target builds: `print("DuskPreview")`.

- [ ] **Step 2: Move the icon and recolour it**

```bash
mkdir -p Sources/DuskUI && git mv Sources/Dusk/StatusIcon.swift Sources/DuskUI/StatusIcon.swift
```

In `Sources/DuskUI/StatusIcon.swift`:
- `enum StatusIcon {` → `public enum StatusIcon {`
- `static func image(active: Bool, timer: Bool) -> NSImage {` → `public static func image(active: Bool, timer: Bool) -> NSImage {`
- Replace the `indigo` constant with two:

```swift
    /// The "on" chip. Warm white rather than pure white, so it sits with the
    /// popover's ink instead of glaring next to it.
    private static let porcelain = NSColor(srgbRed: 0.949, green: 0.945, blue: 0.933, alpha: 1)
    /// What is drawn on the porcelain chip: the laptop and the countdown ring.
    private static let ink = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)
```

- In `draw(active:timer:)`, replace

```swift
        let chip = (active ? indigo : graphite).cgColor
        let white = NSColor.white.cgColor
```

with

```swift
        let chip = (active ? porcelain : graphite).cgColor
        // Drawn on the chip: ink on porcelain when on, white on graphite when off.
        let white = (active ? ink : NSColor.white).cgColor
```

  and `drawMoon(in: ctx, color: active ? indigo : .white)` with `drawMoon(in: ctx, color: active ? porcelain : .white)`.
- Update the doc comment's state list: `on  porcelain chip, ink laptop, moon knocked back out in the chip colour`.

- [ ] **Step 3: Import it in the app** — `Sources/Dusk/AppDelegate.swift` imports become `import AppKit`, `import UserNotifications`, `import DuskCore`, `import DuskUI`.

- [ ] **Step 4: Build, check and look at the icon**

Run: `make check && swift build -c release 2>&1 | tail -3`
Expected: `PASS — 70 checks`, `Build complete!`.

Render the three icons from the real code and inspect them (`design/` holds the earlier icon scripts):

```bash
mkdir -p .build/icon && cat > .build/icon/main.swift <<'SWIFT'
import AppKit
import DuskUI
for (a, t, n) in [(false, false, "off"), (true, false, "on"), (true, true, "on-timer")] {
    let img = StatusIcon.image(active: a, timer: t)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = img.size
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill(); NSRect(origin: .zero, size: img.size).fill(using: .copy)
    img.draw(in: NSRect(origin: .zero, size: img.size)); NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/icon/\(n).png"))
}
SWIFT
```

Then view `.build/icon/on-timer.png`: a warm-white chip, ink laptop, warm-white moon, ink ring.
(Compiling that script needs the module, so instead run the check through `DuskPreview` in Task 4 if this is awkward — the requirement is only that the three images are looked at before committing.)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/DuskUI Sources/DuskPreview Sources/Dusk/AppDelegate.swift
git commit -m "refactor: DuskUI target for drawing code; monochrome menu bar icon"
```

---

### Task 4: Popover model, view, and snapshots

**Files:**
- Create: `Sources/DuskUI/PopoverModel.swift`
- Create: `Sources/DuskUI/PopoverView.swift`
- Modify: `Sources/DuskPreview/main.swift`
- Modify: `Makefile` (add `preview`)

**Interfaces:**
- Consumes: `DurationScale`, `CountdownFormat`, `ThresholdScale`, `AutoOffPolicy.resumeLevel`, `StatusIcon.image(active:timer:)`.
- Produces (module `DuskUI`, all `public`):
  - `final class PopoverModel: ObservableObject` with `init()`, `enum Phase: Equatable { case off, countingDown(until: Date), indefinite, paused }`, `@Published phase: Phase`, `restingStop: Int`, `draggingStop: Int?`, `lowPower: Bool`, `dim: Bool`, `canDim: Bool`, `threshold: Int`, `draggingThreshold: Int?`, `clickMinutes: Int`, `isVisible: Bool`; closures `onCommitStop: (Int) -> Void`, `onSetLowPower: (Bool) -> Void`, `onSetDim: (Bool) -> Void`, `onSetThreshold: (Int) -> Void`, `onQuit: () -> Void`; computed `isLive: Bool`, `needleStop: Int`, `needleIsLive: Bool`.
  - `struct PopoverView: View` with `init(model: PopoverModel)`.

- [ ] **Step 1: Model** — create `Sources/DuskUI/PopoverModel.swift`:

```swift
import Foundation
import DuskCore

/// Everything the popover shows, and the calls it makes back to the app.
///
/// An `ObservableObject` rather than view `@State`: the `@State` macro needs a
/// compiler plugin the command-line tools do not ship, so nothing here may
/// lean on it.
public final class PopoverModel: ObservableObject {
    public enum Phase: Equatable {
        case off
        case countingDown(until: Date)
        case indefinite
        case paused
    }

    @Published public var phase: Phase = .off
    /// Where the ruler's needle rests when nobody is dragging it.
    @Published public var restingStop: Int = DurationScale.stop(forMinutes: 15)
    /// The stop under the pointer while the ruler is being dragged.
    @Published public var draggingStop: Int?
    @Published public var lowPower = true
    @Published public var dim = true
    @Published public var canDim = true
    @Published public var threshold = 0
    /// The slider's value while it is being dragged; it commits on release.
    @Published public var draggingThreshold: Int?
    /// What a left click on the icon keeps Dusk on for, shown when off.
    @Published public var clickMinutes = 15
    /// True only while the popover is on screen. Everything that moves is built
    /// only while this is set, so a closed popover costs nothing.
    @Published public var isVisible = false

    public var onCommitStop: (Int) -> Void = { _ in }
    public var onSetLowPower: (Bool) -> Void = { _ in }
    public var onSetDim: (Bool) -> Void = { _ in }
    public var onSetThreshold: (Int) -> Void = { _ in }
    public var onQuit: () -> Void = {}

    public init() {}

    /// Something is keeping the Mac awake right now.
    public var isLive: Bool {
        switch phase {
        case .countingDown, .indefinite: return true
        case .off, .paused: return false
        }
    }

    public var needleStop: Int { draggingStop ?? restingStop }

    /// Faint when the needle only remembers a past choice.
    public var needleIsLive: Bool { draggingStop != nil || isLive }
}
```

- [ ] **Step 2: View** — create `Sources/DuskUI/PopoverView.swift`:

```swift
import AppKit
import SwiftUI
import DuskCore

/// The Obsidian palette. No hue anywhere: the popover earns its look from the
/// thin, oversized numerals and the hairlines, the way a watch dial does.
enum Obsidian {
    static let ground = Color(red: 0.043, green: 0.043, blue: 0.047)     // #0B0B0C
    static let glow = Color(red: 0.137, green: 0.137, blue: 0.145)       // #232325
    static let ink = Color(red: 0.957, green: 0.957, blue: 0.949)        // #F4F4F2
    static let edge = Color.white.opacity(0.07)
    static let hair = Color.white.opacity(0.08)
    static let hairStrong = Color.white.opacity(0.12)
    static let tick = Color.white.opacity(0.22)
    static let tickLong = Color.white.opacity(0.55)
}

/// The popover that replaces the right-click menu. Layout C from the design:
/// a lit-dial hero over a body of controls that never moves between states.
public struct PopoverView: View {
    @ObservedObject var model: PopoverModel

    public init(model: PopoverModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            Hero(model: model)
            Controls(model: model)
        }
        .frame(width: 320)
        .foregroundStyle(Obsidian.ink)
        .background(Obsidian.ground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Obsidian.edge, lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Hero

struct Hero: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(spacing: 0) {
            StatusPill(model: model).padding(.bottom, 22)
            numerals
            Text(caption.uppercased())
                .font(.system(size: 10))
                .tracking(2.2)
                .opacity(0.45)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(dial)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var numerals: some View {
        switch model.phase {
        case .countingDown(let until):
            if model.isVisible {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Numerals(text: CountdownFormat.string(seconds: until.timeIntervalSince(context.date)))
                }
            } else {
                Numerals(text: CountdownFormat.string(seconds: until.timeIntervalSinceNow))
            }
        case .indefinite:
            Numerals(text: "∞", size: 72, weight: .thin)
        case .off:
            Numerals(text: "Off").opacity(0.32)
        case .paused:
            Numerals(text: "Paused").opacity(0.32)
        }
    }

    private var caption: String {
        switch model.phase {
        case .countingDown: return "Remaining"
        case .indefinite: return "Until turned off"
        case .off: return "Click the icon for \(model.clickMinutes) minutes"
        case .paused: return "Resumes when charging past \(AutoOffPolicy.resumeLevel(threshold: model.threshold))%"
        }
    }

    /// Lit from within only while something runs; cold otherwise.
    @ViewBuilder private var dial: some View {
        if model.isLive {
            RadialGradient(colors: [Obsidian.glow, Obsidian.ground],
                           center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 190)
        } else {
            Obsidian.ground
        }
    }
}

struct Numerals: View {
    let text: String
    var size: CGFloat = 64
    var weight: Font.Weight = .ultraLight

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .kerning(-1.2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

struct StatusPill: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
            Text(label).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 12)).monospacedDigit().opacity(0.55)
        }
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .frame(height: 32)
        .background(Capsule().fill(Obsidian.ground))
        .overlay(Capsule().strokeBorder(Obsidian.hair, lineWidth: 1))
        .overlay {
            if model.isLive && model.isVisible { Sheen() }
        }
    }

    private var icon: NSImage {
        switch model.phase {
        case .off, .paused: return StatusIcon.image(active: false, timer: false)
        case .countingDown: return StatusIcon.image(active: true, timer: true)
        case .indefinite: return StatusIcon.image(active: true, timer: false)
        }
    }

    private var label: String {
        switch model.phase {
        case .off: return "Dusk is off"
        case .paused: return "Paused"
        case .countingDown, .indefinite: return "Keeping awake"
        }
    }

    private var detail: String {
        switch model.phase {
        case .off: return "Mac sleeps normally"
        case .paused: return "battery below \(model.threshold)%"
        case .indefinite: return "no time limit"
        case .countingDown(let until): return "sleeps at \(Self.clock.string(from: until))"
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// One faint highlight travelling the pill's hairline.
///
/// Capped at 30 fps, and only built while the popover is open: a perpetual
/// animation once loaded WindowServer hard enough to lag the whole Mac, and
/// the cost lands on WindowServer, not on Dusk, so the app's own CPU never
/// shows it.
struct Sheen: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5
            Capsule().strokeBorder(
                AngularGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.8),
                    .init(color: Color.white.opacity(0.75), location: 0.92),
                    .init(color: .clear, location: 1),
                ], center: .center, angle: .degrees(turn * 360)),
                lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

struct Controls: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Keep awake for").padding(.bottom, -4)
            Ruler(model: model)
            VStack(spacing: 0) {
                ToggleRow(title: "Low Power Mode", isOn: model.lowPower, enabled: true) { model.onSetLowPower($0) }
                ToggleRow(title: "Dim the Screen", isOn: model.dim, enabled: model.canDim) { model.onSetDim($0) }
            }
            .overlay(alignment: .bottom) { Hairline() }
            ThresholdSlider(model: model)
            Footer(model: model)
        }
        .padding(16)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10)).tracking(2).opacity(0.45)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Obsidian.hair).frame(height: 1) }
}

/// The duration ruler. Dragging moves the needle across the stops; letting go
/// commits the stop under the pointer. A plain click commits too.
struct Ruler: View {
    @ObservedObject var model: PopoverModel
    /// Keeps the end labels inside the panel.
    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(0..<DurationScale.count, id: \.self) { index in
                    let long = DurationScale.labels.contains { $0.index == index }
                    Rectangle()
                        .fill(long ? Obsidian.tickLong : Obsidian.tick)
                        .frame(width: 1, height: long ? 14 : 7)
                        .position(x: x(of: index, in: width), y: long ? 21 : 24.5)
                }
                ForEach(DurationScale.labels, id: \.index) { label in
                    Text(label.text)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .opacity(0.5)
                        .position(x: x(of: label.index, in: width), y: 38)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(Obsidian.ink)
                    .frame(width: 2, height: 30)
                    .opacity(model.needleIsLive ? 1 : 0.35)
                    .position(x: x(of: model.needleStop, in: width), y: 13)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    model.draggingStop = DurationScale.nearestStop(toFraction: fraction(at: drag.location.x, in: width))
                }
                .onEnded { drag in
                    let stop = DurationScale.nearestStop(toFraction: fraction(at: drag.location.x, in: width))
                    model.onCommitStop(stop)
                    model.draggingStop = nil
                })
        }
        .frame(height: 44)
    }

    private func x(of stop: Int, in width: CGFloat) -> CGFloat {
        inset + CGFloat(DurationScale.fraction(forStop: stop)) * (width - inset * 2)
    }

    private func fraction(at x: CGFloat, in width: CGFloat) -> Double {
        Double((x - inset) / (width - inset * 2))
    }
}

struct ToggleRow: View {
    let title: String
    let isOn: Bool
    let enabled: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13.5))
            Spacer()
            Capsule()
                .fill(isOn ? Obsidian.ink : Color.white.opacity(0.14))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? Obsidian.ground : Obsidian.ink).frame(width: 16, height: 16).padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { set(!isOn) } }
        .opacity(enabled ? 1 : 0.35)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// The battery floor. Shows the live value while dragging and commits on
/// release — committing per step would re-run the battery policy, and a pmset
/// round-trip, for every pixel of travel.
struct ThresholdSlider: View {
    @ObservedObject var model: PopoverModel

    private var shown: Int { model.draggingThreshold ?? model.threshold }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Turn off below").font(.system(size: 13.5))
                Spacer()
                Text(shown == 0 ? "Off" : "\(shown)%").font(.system(size: 13)).monospacedDigit().opacity(0.7)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * CGFloat(ThresholdScale.fraction(of: shown))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Obsidian.hairStrong).frame(height: 2)
                    Rectangle().fill(Obsidian.ink).frame(width: x, height: 2)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Obsidian.ink)
                        .frame(width: 5, height: 18)
                        .shadow(color: Color.white.opacity(0.35), radius: 4)
                        .offset(x: x - 2.5)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        model.draggingThreshold = ThresholdScale.value(atFraction: Double(drag.location.x / width))
                    }
                    .onEnded { drag in
                        model.onSetThreshold(ThresholdScale.value(atFraction: Double(drag.location.x / width)))
                        model.draggingThreshold = nil
                    })
            }
            .frame(height: 18)
        }
    }
}

struct Footer: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        Button(action: { model.onQuit() }) {
            HStack {
                Text("Quit Dusk")
                Spacer()
                Text("⌘Q")
            }
            .font(.system(size: 12))
            .opacity(0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
        .padding(.top, 2)
    }
}
```

- [ ] **Step 3: Snapshot renderer** — replace `Sources/DuskPreview/main.swift`:

```swift
import AppKit
import SwiftUI
import DuskCore
import DuskUI

// Renders the popover in each state, plus the menu bar icons, from the real
// view code — checked without launching the app or capturing the screen.
// Usage: swift run DuskPreview <output directory>

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/preview")
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

@MainActor func write(_ cgImage: CGImage, _ name: String) {
    let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
    try! png.write(to: directory.appendingPathComponent("\(name).png"))
    print("wrote \(name).png  \(cgImage.width)×\(cgImage.height)")
}

@MainActor func popover(_ name: String, _ configure: (PopoverModel) -> Void) {
    let model = PopoverModel()
    model.isVisible = true
    model.threshold = 20
    configure(model)
    let view = PopoverView(model: model)
        .padding(24)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage else { print("could not render \(name)"); exit(1) }
    write(image, name)
}

@MainActor func icon(_ name: String, active: Bool, timer: Bool) {
    let image = StatusIcon.image(active: active, timer: timer)
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 4)]) else {
        print("could not render \(name)"); exit(1)
    }
    write(cg, name)
}

MainActor.assumeIsolated {
    popover("1-off") { $0.phase = .off }
    popover("2-counting") { $0.phase = .countingDown(until: Date().addingTimeInterval(720)) }
    popover("3-indefinite") { $0.phase = .indefinite; $0.restingStop = DurationScale.lastIndex }
    popover("4-paused") { $0.phase = .paused }
    popover("5-cannot-dim") { $0.phase = .off; $0.canDim = false; $0.threshold = 0 }
    icon("icon-off", active: false, timer: false)
    icon("icon-on", active: true, timer: false)
    icon("icon-on-timer", active: true, timer: true)
}
```

Add to the `Makefile` (and to `.PHONY`):

```make
# Renders the popover in every state, and the icons, to .build/preview/.
preview:
	swift run DuskPreview .build/preview
```

- [ ] **Step 4: Render and inspect**

Run: `make check && make preview`
Expected: `PASS — 70 checks`; eight `wrote …png` lines. Open each PNG in `.build/preview/` and confirm against the spec's state table: pill label and detail, numerals (`Off` faint, `12:00`, thin `∞`, `Paused` faint), caption text (`CLICK THE ICON FOR 15 MINUTES`, `REMAINING`, `UNTIL TURNED OFF`, `RESUMES WHEN CHARGING PAST 25%`), the needle (faint at 15m when off/paused, solid at ∞ when indefinite), `Dim the Screen` faded in `5-cannot-dim`, and the slider reading `Off` there. Icons: `icon-on*` warm-white chip with an ink laptop.

- [ ] **Step 5: Commit**

```bash
git add Sources/DuskUI Sources/DuskPreview Makefile
git commit -m "feat: Obsidian popover view and its model, with a snapshot renderer"
```

---

### Task 5: The panel that hosts the popover

**Files:**
- Create: `Sources/Dusk/DuskPanel.swift`

**Interfaces:**
- Consumes: `PopoverModel`, `PopoverView(model:)`.
- Produces: `final class DuskPanel: NSPanel` with `init(model: PopoverModel)`, `var onClose: () -> Void`, `var wasJustDismissed: Bool`, `func show(below button: NSStatusBarButton)`, `func dismiss()`; `isVisible` is `NSWindow`'s own.

- [ ] **Step 1: Implement** — create `Sources/Dusk/DuskPanel.swift`:

```swift
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
    }

    func dismiss() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        stopWatching()
        orderOut(nil)
        model.isVisible = false
        dismissedAt = Date()
        onClose()
    }

    /// A click into any other app moves key focus there.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    /// Clicks on the desktop or another app's menu bar item take no focus, so
    /// they are watched for directly; Esc arrives as a key event to this panel.
    private func watchForDismissal() {
        stopWatching()
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        escapeKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            MainActor.assumeIsolated { self?.dismiss() }
            return nil
        }
    }

    private func stopWatching() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        if let escapeKey { NSEvent.removeMonitor(escapeKey) }
        outsideClicks = nil
        escapeKey = nil
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c release 2>&1 | grep -E "error|Build complete"`
Expected: `Build complete!` (the panel is not wired yet).

- [ ] **Step 3: Commit**

```bash
git add Sources/Dusk/DuskPanel.swift
git commit -m "feat: borderless panel that hosts the popover under the status item"
```

---

### Task 6: Wire the popover into the app, retire the menu

**Files:**
- Modify: `Sources/Dusk/AppDelegate.swift`
- Modify: `Sources/Dusk/AutoOffTimer.swift:31`
- Delete: `Sources/Dusk/SwitchMenuItemView.swift`, `Sources/Dusk/ThresholdSliderView.swift`
- Modify: `README.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: `DuskPanel`, `PopoverModel`, `DurationScale`, `AutoOffTimer.deadline`.

- [ ] **Step 1: Expose the countdown deadline** — `Sources/Dusk/AutoOffTimer.swift`: `private var deadline: Date?` → `private(set) var deadline: Date?`.

- [ ] **Step 2: Properties** — in `AppDelegate`, delete `private let durationOptions = [15, 30, 60, 120]` and the `activeMenu` property with its comment. Add after `clickTimerMinutes`:

```swift
    private let popoverModel = PopoverModel()
    private lazy var popover = DuskPanel(model: popoverModel)
    /// Minutes of the countdown now running, for the ruler's needle.
    private var armedMinutes: Int?
    private let lastMinutesKey = "lastKeepAwakeMinutes"
    /// The duration last chosen on the ruler, where its needle rests when
    /// nothing is running. Persisted.
    private var lastMinutes: Int {
        get { UserDefaults.standard.object(forKey: lastMinutesKey) as? Int ?? clickTimerMinutes }
        set { UserDefaults.standard.set(newValue, forKey: lastMinutesKey) }
    }
```

- [ ] **Step 3: Wiring, sync and the ruler** — in `applicationDidFinishLaunching`, right after `controller.onChange = …`, add `wirePopover()`. Add these methods under a new `// MARK: - Popover`, replacing the whole `// MARK: - Menu` section (`showMenu`, `keepAwakeSubmenuItem`, `autoOffSubmenuItem`) — keep `durationLabel` and `formatRemaining`, the tooltip still uses them — and the `menuKeepAwakeFor` / `menuQuit` actions:

```swift
    // MARK: - Popover

    private func wirePopover() {
        popoverModel.clickMinutes = clickTimerMinutes
        popoverModel.onCommitStop = { [weak self] stop in self?.commitRuler(stop) }
        popoverModel.onSetLowPower = { [weak self] on in
            self?.setPreference { $0.engagesLowPower = on }
            self?.syncPopover()
        }
        popoverModel.onSetDim = { [weak self] on in
            self?.setPreference { $0.engagesDark = on }
            self?.syncPopover()
        }
        popoverModel.onSetThreshold = { [weak self] value in
            self?.setThreshold(value)
            self?.syncPopover()
        }
        popoverModel.onQuit = { NSApp.terminate(nil) }
        popover.onClose = { [weak self] in
            // Reaching the popover with the screen at zero meant pressing the
            // brightness key first, which opened a peek. Closing is the sign the
            // looking is done. Ending the peek per action instead would black the
            // screen out from under a popover that stays open across a toggle.
            self?.controller.takeScreenBack()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        syncPopover()
        popover.show(below: button)
    }

    /// Pushes the machine's state into the popover. Runs wherever the icon is
    /// refreshed, so an open popover follows changes — a countdown that runs
    /// out while it is up turns it to Off. Each value is set only when it
    /// changed, so a refresh with nothing new republishes nothing.
    private func syncPopover() {
        let phase: PopoverModel.Phase
        if suspendedForBattery {
            phase = .paused
        } else if !effectiveActive {
            phase = .off
        } else if let deadline = autoOffTimer.deadline {
            phase = .countingDown(until: deadline)
        } else {
            phase = .indefinite
        }
        let resting: Int
        switch phase {
        case .countingDown: resting = DurationScale.stop(forMinutes: armedMinutes ?? lastMinutes)
        case .indefinite: resting = DurationScale.lastIndex
        case .off, .paused: resting = DurationScale.stop(forMinutes: lastMinutes)
        }
        if popoverModel.phase != phase { popoverModel.phase = phase }
        if popoverModel.restingStop != resting { popoverModel.restingStop = resting }
        if popoverModel.lowPower != engagesLowPower { popoverModel.lowPower = engagesLowPower }
        if popoverModel.dim != engagesDark { popoverModel.dim = engagesDark }
        if popoverModel.canDim != controller.canDim { popoverModel.canDim = controller.canDim }
        if popoverModel.threshold != threshold { popoverModel.threshold = threshold }
    }

    /// A duration chosen on the ruler. The popover closes first — that ends the
    /// peek — and the change lands on the next pass of the run loop, so a
    /// privilege prompt or an error comes up in front of everything.
    private func commitRuler(_ stop: Int) {
        let minutes = DurationScale.minutes(atStop: stop)
        if let minutes { lastMinutes = minutes }
        popover.dismiss()
        DispatchQueue.main.async { [weak self] in self?.keepAwake(for: minutes) }
    }

    /// Keep awake for `minutes`, or with no limit when nil. Already on: only the
    /// countdown moves, skipping a pmset round-trip to a state already set.
    private func keepAwake(for minutes: Int?) {
        guard effectiveActive else {
            setIntent(true, timerMinutes: minutes)
            return
        }
        if let minutes {
            startCountdown(minutes: minutes)
        } else {
            autoOffTimer.cancel()
        }
        refreshStatusItem()
    }
```

In `startCountdown(minutes:)` add `armedMinutes = minutes` before `autoOffTimer.start(minutes: minutes)`. At the end of `refreshStatusItem()` add `syncPopover()`.

- [ ] **Step 4: Clicks** — `handleClick` becomes:

```swift
    /// Left click turns Dusk on or off; right click (a two-finger click on the
    /// trackpad) opens the popover. While the popover is up, a click on the icon
    /// of either kind only closes it.
    @objc private func handleClick() {
        if popover.isVisible || popover.wasJustDismissed {
            popover.dismiss()
            return
        }

        let event = NSApp.currentEvent
        let wantsPopover = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if wantsPopover {
            showPopover()
        } else if effectiveActive {
            setIntent(false)
        } else {
            // A left click turns on in timer mode, the same countdown the ruler
            // runs. Its far end, ∞, is there for an indefinite on.
            setIntent(true, timerMinutes: clickTimerMinutes)
        }
    }
```

- [ ] **Step 5: Riders** — in `setPreference`, delete `activeMenu?.cancelTracking()` and update its comment: the popover stays open; the work still runs on the next pass so a modal can come up. In `applyRiders`, delete the `self.controller.takeScreenBack()` line and its two-line comment (the popover's close does that now), and make the privilege branch close the popover first:

```swift
        if needsRoot, !hasPrivilege {
            popover.dismiss()
            withPrivilege { [weak self] in self?.applyRiders(target) }
            return
        }
```

- [ ] **Step 6: Alerts close the popover first** — add `popover.dismiss()` as the first line of `offerPrivilegeSetup(completion:)` and of `present(title:body:)` (which `presentError` goes through). Then pin it:

Run: `grep -n "runModal" Sources/Dusk/AppDelegate.swift` and, for each hit, confirm the enclosing function begins with `popover.dismiss()`.
Expected: two hits (`offerPrivilegeSetup`, `present`), both preceded in their function by `popover.dismiss()`.

- [ ] **Step 7: Retire the menu views**

```bash
git rm Sources/Dusk/SwitchMenuItemView.swift Sources/Dusk/ThresholdSliderView.swift
grep -rn "SwitchMenuItemView\|ThresholdSliderView\|activeMenu\|durationOptions\|menuKeepAwakeFor\|showMenu" Sources/
```
Expected: no matches.

- [ ] **Step 8: Docs** — `README.md`: the click table's right-click row becomes `| **Right click** (or two-finger click) | The popover: a duration ruler, what to bring along, low-battery cutoff |`; rename `### The menu` to `### The popover` and replace its first bullet with:

```markdown
- **Keep awake for** — drag the ruler and let go: 5 minutes to an hour in
  five-minute steps, then to four hours in fifteen, or **∞** at the far end for
  no countdown at all. Countdowns are wall-clock, so they stay honest if the
  Mac sleeps and wakes partway through.
```

Replace `The icon is the switch — a laptop with a crescent moon on its screen. Black means off, indigo means on, and a ring around it means a countdown is running.` with `The icon is the switch — a laptop with a crescent moon on its screen. A dark chip means off, a white chip means on, and a ring means a countdown is running.` In `CLAUDE.md`, `우클릭 = 메뉴(` → `우클릭 = 팝오버(`.

- [ ] **Step 9: Build and check**

Run: `make check && swift build -c release 2>&1 | grep -E "error|Build complete"`
Expected: `PASS — 70 checks`, `Build complete!`.

- [ ] **Step 10: Commit**

```bash
git add -A Sources README.md CLAUDE.md
git commit -m "feat: right click opens the Obsidian popover; the menu is retired"
```

---

### Task 7: Live verification

**Files:** none changed unless a check fails.

- [ ] **Step 1: Install and launch**

Run: `make install && open /Applications/Dusk.app && sleep 2 && pgrep -lf Applications/Dusk`
Expected: one Dusk process.

- [ ] **Step 2: Open it for real and check placement** — right-click the icon with a real event, then list Dusk's on-screen windows and the screen:

```swift
// .build/verify/windows.swift — prints Dusk's visible windows and the main screen
import AppKit
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in info where (w[kCGWindowOwnerName as String] as? String) == "Dusk" {
    print("window", w[kCGWindowLayer as String]!, w[kCGWindowBounds as String]!)
}
print("screen", NSScreen.main!.frame)
```

Expected: one window about 320pt wide whose bounds lie wholly inside the screen frame. Screenshot the region and compare with `.build/preview/1-off.png`.

- [ ] **Step 3: Icon click closes, and stays closed** — with the popover open, right-click the icon again; list windows. Expected: no Dusk window with layer 101 (`popUpMenu`). Repeat with a left click: closed, and `pmset -g | grep SleepDisabled` unchanged (the click did not also toggle Dusk).

- [ ] **Step 4: Ruler commits** — open the popover, drag the ruler to the 1h label and release. Expected: popover closes; Dusk log shows `intent -> true`; `SleepDisabled 1`; reopening shows a countdown near `1:00:00` and `sleeps at` an hour out. Then drag to ∞: reopening shows `∞`, `no time limit`. Esc closes it. Left-click the icon to turn Dusk off.

- [ ] **Step 5: A closed popover costs nothing** — with Dusk on (so the highlight would run), measure WindowServer CPU time over 15 s with the popover open, then closed:

```bash
WS=$(pgrep -x WindowServer); t0=$(ps -o time= -p $WS); sleep 15; t1=$(ps -o time= -p $WS); echo "$t0 -> $t1"
```

Expected: the closed run's increase matches a baseline taken before Dusk was turned on; the open run is allowed to be higher. If the closed run is higher than baseline, something is still animating — stop and find it.

- [ ] **Step 6: Leave the Mac as found** — Dusk off, brightness visible, `SleepDisabled 0`.

- [ ] **Step 7: Commit any fixes** made during this task with messages naming what the live check found.
