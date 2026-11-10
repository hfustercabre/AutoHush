import AppKit
import SwiftUI

/// Settings' Back and Forward as stops of the page's highlight (R2, the
/// user, 2026-11-10: reach every control): Tab and Shift-Tab reach them,
/// first in the page's reading order, as the toolbar is over the page; ↑ ↓,
/// ← →, Page Up…End go past them, as before (`Control.tabOnly`, as a
/// search's ✕); Return or Space presses the lit one; dimmed with nothing
/// to go to, they're skipped. The arrows are AppKit's toolbar group, which
/// draws no highlight of ours: a ring over the lit one is drawn in a window
/// of its own on top of them (`Ring`), which the pointer goes through.
/// VoiceOver's cursor can't be moved onto them: as a key lights one,
/// VoiceOver says its name instead (R6 of the keyboard fixes' review,
/// 2026-11-10).
@MainActor
final class SettingsToolbarKeys {
    let back = UUID()
    let forward = UUID()
    private let highlight: KeyHighlight
    private let goBack: () -> Void
    private let goForward: () -> Void
    private let canGo: () -> (back: Bool, forward: Bool)
    private weak var window: NSWindow?
    /// The page's view, where the page's controls' frames are.
    private weak var pageView: NSView?
    /// The ring's window, while one of the arrows is lit.
    private var ring: NSWindow?
    private var resizeWatch: (any NSObjectProtocol)?
    /// Registered with the highlight, once the toolbar has laid them out:
    /// never with no frame, which would hold up a page's first control
    /// lit as it shows (`KeyHighlight.firstWhenReady`).
    private var registered = false
    /// Where the arrows are, in the window's coordinates; `nil` while
    /// they're not laid out (tests replace it).
    var arrowsFrame: @MainActor (NSWindow) -> CGRect? = SettingsToolbarKeys.findArrows
    /// Whether the window is laid out right to left (Arabic, Hebrew):
    /// Back is then the right one (tests replace it).
    var readsRightToLeft: @MainActor () -> Bool = { NSApp?.userInterfaceLayoutDirection == .rightToLeft }
    /// Says an arrow's name, as a key lights it, while VoiceOver is on
    /// (tests replace it).
    var announce: @MainActor (String) -> Void = { name in
        if NSWorkspace.shared.isVoiceOverEnabled { postStepAnnouncement(name) }
    }
    /// How many times a key had lit each arrow when its name was last said
    /// (`KeyHighlight.Light.arrivals`).
    private var announcedArrivals: [UUID: Int] = [:]

    init(highlight: KeyHighlight, goBack: @escaping () -> Void, goForward: @escaping () -> Void,
         canGo: @escaping () -> (back: Bool, forward: Bool)) {
        self.highlight = highlight
        self.goBack = goBack
        self.goForward = goForward
        self.canGo = canGo
    }

    /// The arrows of `window`'s toolbar, over `pageView`: registered with
    /// the page's highlight once they're laid out (`updateFrames`).
    func attach(to window: NSWindow?, pageView: NSView?) {
        self.window = window
        self.pageView = pageView
        resizeWatch = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFrames()
                self?.refresh()
            }
        }
    }

    /// Back and Forward dimmed, or not, as there's somewhere to go.
    func updateEnabled() {
        if registered {
            let can = canGo()
            highlight.update(back, isEnabled: can.back)
            highlight.update(forward, isEnabled: can.forward)
        }
        updateFrames()
        refresh()
    }

    /// Where the arrows are now, in the page's coordinates (above it, so
    /// first in its reading order): before each key, as the window shows
    /// or resizes and the page changes.
    func updateFrames() {
        guard let window, let pageView, let arrows = arrowsFrame(window) else { return }
        let (left, right) = Self.halves(arrows)
        let (backRect, forwardRect) = readsRightToLeft() ? (right, left) : (left, right)
        let backFrame = pageView.convert(backRect, from: nil), forwardFrame = pageView.convert(forwardRect, from: nil)
        guard registered else {
            registered = true
            let can = canGo()
            highlight.register(back, .init(frame: backFrame, band: .top, isEnabled: can.back,
                                           press: { [weak self] in self?.goBack() }, tabOnly: true))
            highlight.register(forward, .init(frame: forwardFrame, band: .top, isEnabled: can.forward,
                                              press: { [weak self] in self?.goForward() }, tabOnly: true))
            return
        }
        highlight.update(back, frame: backFrame)
        highlight.update(forward, frame: forwardFrame)
    }

    /// After a key: the ring over the lit arrow, none while neither is;
    /// its name said once a key lit it anew.
    func refresh() {
        sayLitArrow()
        guard let window, let lit = [back, forward].first(where: { highlight.highlighted == $0 }), window.isVisible,
              let arrows = arrowsFrame(window) else { return removeRing() }
        let (left, right) = Self.halves(arrows)
        let isLeft = (lit == back) != readsRightToLeft()
        let rect = (isLeft ? left : right).insetBy(dx: -Self.outset, dy: -Self.outset)
        let ring = ring ?? makeRing()
        ring.setFrame(window.convertToScreen(rect), display: true)
        if ring.parent == nil { window.addChildWindow(ring, ordered: .above) }
    }

    /// The lit arrow's name, said if a key lit it since it was last said
    /// (a press on it, which keeps it lit, says nothing): the toolbar's
    /// own words, Back and Forward.
    private func sayLitArrow() {
        guard let lit = highlight.highlighted, lit == back || lit == forward else { return }
        let light = highlight.light(lit)
        guard light.byKeys, announcedArrivals[lit] != light.arrivals else { return }
        announcedArrivals[lit] = light.arrivals
        announce(lit == back ? SettingsWindowController.backTitle : SettingsWindowController.forwardTitle)
    }

    /// The window the ring is drawn in now, if any (tests read it).
    var ringWindow: NSWindow? { ring }

    /// The window closes: no ring left over it.
    func removeRing() {
        guard let ring else { return }
        ring.parent?.removeChildWindow(ring)
        ring.orderOut(nil)
        self.ring = nil
    }

    /// How far out of an arrow the ring is drawn.
    private static let outset: CGFloat = 1

    private func makeRing() -> NSWindow {
        let ring = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        ring.isOpaque = false
        ring.backgroundColor = .clear
        ring.hasShadow = false
        ring.ignoresMouseEvents = true
        ring.isReleasedWhenClosed = false
        ring.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        ring.contentView = NSHostingView(rootView: Ring(highlight: highlight, arrows: [back, forward]))
        self.ring = ring
        return ring
    }

    /// The lit arrow's ring: outlined in the accent color, as a filled
    /// control's (P1), drawn only while the keys have it there.
    private struct Ring: View {
        let highlight: KeyHighlight
        let arrows: [UUID]

        var body: some View {
            let lit = arrows.contains { highlight.light($0).isOn && highlight.light($0).byKeys }
            GeometryReader { geometry in
                HighlightTint(isFocused: lit, byKeys: true, cornerRadius: min(geometry.size.width, geometry.size.height) / 2, ring: true)
            }
        }
    }

    /// The left and right arrows of the group, half of it each.
    private static func halves(_ rect: CGRect) -> (CGRect, CGRect) {
        let parts = rect.divided(atDistance: rect.width / 2, from: .minXEdge)
        return (parts.slice, parts.remainder)
    }

    /// The arrows' group in `window`'s toolbar: the segmented control there,
    /// the only one (an `NSSegmentedControl` before macOS 26, SwiftUI's
    /// hosted one in it), in the window's coordinates.
    static func findArrows(in window: NSWindow) -> CGRect? {
        guard let frame = window.contentView?.superview else { return nil }
        func toolbar(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)).contains("ToolbarView") { return view }
            return view.subviews.lazy.compactMap(toolbar).first
        }
        func segments(_ view: NSView) -> NSView? {
            if view is NSSegmentedControl || String(describing: type(of: view)).contains("SegmentedControl") { return view }
            return view.subviews.lazy.compactMap(segments).first
        }
        guard let bar = toolbar(frame), let arrows = segments(bar), !arrows.isHidden, arrows.bounds.width > 0 else { return nil }
        return arrows.convert(arrows.bounds, to: nil)
    }
}
