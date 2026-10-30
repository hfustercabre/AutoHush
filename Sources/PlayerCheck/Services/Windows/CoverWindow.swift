import AppKit

/// An opaque window over the app's, from this tool: another window covering
/// it, as Chromium counts one (an Electron player's page took no presses under it, as
/// under any window). Made while another desktop is current, it lands there.
@MainActor final class CoverWindow {
    private var window: NSWindow?
    var number: Int? { window.map { $0.windowNumber } }

    func show(over box: CGRect, naming name: String) {
        remove()
        NSApplication.shared.setActivationPolicy(.accessory)
        let area = box.insetBy(dx: -20, dy: -20)
        let top = NSScreen.screens.first?.frame.height ?? 0
        let made = NSWindow(contentRect: NSRect(x: area.minX, y: top - area.maxY, width: area.width, height: area.height),
                            styleMask: .borderless, backing: .buffered, defer: false)
        made.isOpaque = true
        made.backgroundColor = .windowBackgroundColor
        made.isReleasedWhenClosed = false
        // Named only for the Player Check app: AutoHush's own check (--result)
        // says what it does in its panel, in the user's language.
        if resultFile == nil {
            let label = NSTextField(labelWithString: "Player Check covers \(name) here for its test")
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.frame = NSRect(x: 24, y: area.height / 2 - 12, width: area.width - 48, height: 24)
            made.contentView?.addSubview(label)
        }
        made.orderFrontRegardless()
        made.display()
        window = made
        settle()
    }

    /// AppKit shows (or takes away) the window once its transaction is
    /// committed, which happens as the run loop turns: this tool's waits
    /// don't turn it.
    private func settle() {
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    func remove() {
        guard window != nil else { return }
        window?.orderOut(nil)
        window = nil
        settle()
    }
}
