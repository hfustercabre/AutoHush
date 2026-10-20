import AppKit
import Foundation
import Testing
@testable import AutoHushApp

/// On a policy, a notification center and windows of its own: other tests'
/// windows, shown or closed meanwhile, change nothing here.
@Suite("DockPresence")
@MainActor
struct DockPresenceTests {
    @MainActor
    private final class Bench {
        var policy = NSApplication.ActivationPolicy.accessory
        var windows: [NSWindow] = []
        let center = NotificationCenter()
        private(set) lazy var dock = DockPresence(policy: { [unowned self] in self.policy }, setPolicy: { [unowned self] in self.policy = $0 },
                                                  center: center, windows: { [unowned self] in self.windows })

        func window(titled: Bool = true) -> NSWindow {
            let window = NSWindow(contentRect: .zero, styleMask: titled ? [.titled, .closable] : [.borderless], backing: .buffered, defer: true)
            windows.append(window)
            return window
        }

        func close(_ window: NSWindow) {
            center.post(name: NSWindow.willCloseNotification, object: window)
            windows.removeAll { $0 === window }
        }
    }

    @Test("in the Dock once a window shows, and only in the menu bar again once the last one closes")
    func inTheDockWhileAWindowIsOpen() {
        let bench = Bench()
        let window = bench.window()
        bench.dock.windowWillShow(window)
        #expect(bench.policy == .regular && bench.dock.isShown(window))
        bench.close(window)
        #expect(bench.policy == .accessory && !bench.dock.isShown(window))
    }

    @Test("a window shown and not closed (minimized, or AutoHush hidden) keeps it in the Dock; a borderless one doesn't")
    func openWindowsKeepIt() {
        let bench = Bench()
        let first = bench.window(), second = bench.window()
        bench.dock.windowWillShow(first)
        bench.dock.windowWillShow(second) // not on screen: as minimized or hidden
        bench.close(first)
        #expect(bench.policy == .regular)
        let menu = bench.window(titled: false)
        bench.dock.windowWillShow(menu)
        bench.close(second)
        #expect(bench.policy == .accessory) // the menu's window isn't one to keep it for
    }

    @Test("a process that is neither in the Dock nor an accessory app stays as it is")
    func regularStays() {
        let bench = Bench()
        bench.policy = .prohibited
        let window = bench.window()
        bench.dock.windowWillShow(window)
        bench.close(window)
        #expect(bench.policy == .prohibited)
    }
}
