import AppKit
import PlayerCheckKit
import SwiftUI

/// The check's panel at the bottom right of the screen, on every desktop,
/// for AutoHush's Add an App… and the Player Check app alike: a borderless
/// panel that never takes the keyboard (the check counts only ordinary
/// windows as covering the app) and never comes forward, so its Stop leaves
/// the app in front where it is. While the check blocks the mouse and
/// keyboard, a shade dims every screen but the panel; the check lets clicks
/// through on the panel's windows above the ordinary ones that don't cover
/// a whole display (`CheckPanelWindows`): the panel, never the shade.
@MainActor
package final class CheckPanelController {
    /// The shade's level, and the panel's while the screen is dimmed: above
    /// the menu bar, the Dock and Control Center's panels (the Now Playing
    /// panel a check opens), so the shade dims them all and the panel stays
    /// above it. Otherwise the panel floats, under menus and the Dock.
    static let shadeLevel = NSWindow.Level(rawValue: CheckPanelWindows.shadeLevel)
    static let panelLevel = NSWindow.Level(rawValue: CheckPanelWindows.dimmedLevel)
    /// The panel while it's shown, and the shades while the screen is
    /// dimmed (tests read them: other panels may be shown in the process).
    private(set) var panel: NSPanel?
    private(set) var shades: [NSWindow] = []

    package init() {}

    /// Shows the panel with `content`, made with what it calls with its size
    /// (the panel fits it) and with whether the screen is to be dimmed (while
    /// the check blocks the mouse and keyboard).
    package func show<Content: View>(@ViewBuilder _ content: (_ resized: @escaping (CGSize) -> Void,
                                                             _ dimmed: @escaping (Bool) -> Void) -> Content) {
        hide()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: CheckPanelWindows.floatingLevel)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: content({ [weak panel] size in
            Self.fit(panel, to: size)
        }, { [weak self] on in
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

    package func hide() {
        panel?.orderOut(nil)
        panel = nil
        shades.forEach { $0.orderOut(nil) }
        shades = []
    }

    /// Dims every screen but the panel, black at 50%, fading in or out; not
    /// once the panel is hidden (a late call would leave a shade up with no
    /// panel over it). The shade lets the check's drags through (it ignores
    /// the mouse), and doesn't hide what's under it from the check: macOS
    /// still counts those windows as visible (a Chromium page under it takes
    /// presses), and Accessibility's hit tests pass it by.
    private func dim(_ on: Bool) {
        guard panel != nil else { return }
        panel?.level = on ? Self.panelLevel : NSWindow.Level(rawValue: CheckPanelWindows.floatingLevel)
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
