import AppKit
import SwiftUI

/// The check's panel at the bottom right of the screen, on every desktop,
/// as Player Check's: a borderless panel that never takes the keyboard (the
/// check counts only ordinary windows as covering the app) and never comes
/// forward. While the check blocks the mouse and keyboard, a shade dims
/// every screen but the panel; the check lets clicks through on AutoHush's
/// windows above the ordinary ones that don't cover a whole display: the
/// panel, never the shade.
@MainActor
final class CheckPanelController {
    /// The shade's level, and the panel's while the screen is dimmed: above
    /// the menu bar, the Dock and Control Center's panels (the Now Playing
    /// panel a check opens), so the shade dims them all and the panel stays
    /// above it. Otherwise the panel floats, under menus and the Dock.
    static let shadeLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
    private var panel: NSPanel?
    private var shades: [NSWindow] = []

    func show(_ app: CheckableApp, model: AddAppModel) {
        hide()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: CheckPanelView(model: model, app: app, resized: { [weak panel] size in
            Self.fit(panel, to: size)
        }, dimmed: { [weak self] on in
            self?.dim(on)
        }))
        let radius: CGFloat = 20
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = content
            panel.contentView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            mask.resizingMode = .stretch
            effect.maskImage = mask
            content.frame = effect.bounds
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
            panel.contentView = effect
        }
        Self.fit(panel, to: content.fittingSize)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        shades.forEach { $0.orderOut(nil) }
        shades = []
    }

    /// Dims every screen but the panel, black at 50%, fading in or out. The
    /// shade lets the check's drags through (it ignores the mouse), and
    /// doesn't hide what's under it from the check: macOS still counts those
    /// windows as visible, and Accessibility's hit tests pass it by.
    private func dim(_ on: Bool) {
        guard panel != nil else { return }
        panel?.level = on ? Self.panelLevel : .floating
        if on, shades.isEmpty { shades = NSScreen.screens.map(Self.shade) }
        let shown = shades
        if !on { shades = [] }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            for shade in shown { shade.animator().alphaValue = on ? 1 : 0 }
        } completionHandler: {
            // On the main thread, where the animation ran.
            MainActor.assumeIsolated {
                if !on { shown.forEach { $0.orderOut(nil) } }
            }
        }
    }

    private static func shade(_ screen: NSScreen) -> NSWindow {
        let shade = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        shade.isOpaque = false
        shade.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        shade.alphaValue = 0
        shade.ignoresMouseEvents = true
        shade.hasShadow = false
        shade.level = shadeLevel
        shade.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        shade.canHide = false
        shade.hidesOnDeactivate = false
        shade.isReleasedWhenClosed = false
        shade.setFrame(screen.frame, display: false)
        shade.orderFrontRegardless()
        return shade
    }

    /// Its size for its content, its bottom right corner 16 pt from the
    /// main display's (above the Dock).
    private static func fit(_ panel: NSPanel?, to size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: screen.maxX - size.width - 16, y: screen.minY + 16, width: size.width, height: size.height), display: true)
    }
}
