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
