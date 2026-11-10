import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("MenuRowButtonStyle", .application, .waitsTimeLimit)
@MainActor
struct MenuRowButtonStyleTests {
    @Test("in the menu, a row lights up only where the keys' highlight is: the arrow keys leave no second lit row under the pointer")
    func oneLitRow() {
        // The pointer rests on the row; ↓ moves the highlight to the next.
        #expect(!MenuRowButtonStyle.isLit(enabled: true, tinted: false, hovered: true, highlighted: false, followsKeys: true))
        #expect(MenuRowButtonStyle.isLit(enabled: true, tinted: false, hovered: false, highlighted: true, followsKeys: true))
        // Without the keys' highlight, the pointer lights it.
        #expect(MenuRowButtonStyle.isLit(enabled: true, tinted: false, hovered: true, highlighted: false, followsKeys: false))
        // Disabled, or tinted by the menu behind it: never itself.
        #expect(!MenuRowButtonStyle.isLit(enabled: false, tinted: false, hovered: true, highlighted: true, followsKeys: true))
        #expect(!MenuRowButtonStyle.isLit(enabled: true, tinted: true, hovered: true, highlighted: true, followsKeys: true))
    }

    // macOS 14.4 delivers no hover to this window under the test runner (it timed
    // out in the old-macOS round, 2026-11-10): the pure `isLit` test above
    // covers the rule there.
    @Test("drawn in a window with the menu's highlight, the row under the pointer goes dark once ↓ lights the next: one lit row (R-5)",
          .enabled(if: ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)),
                   "no hover reaches a test window on macOS 14"))
    func hostedRowLitByKeysOnly() async throws {
        let keys = KeyHighlight()
        let rows = VStack(spacing: 0) {
            MenuActionRow(action: {}) { Color.clear } content: { Text(verbatim: "First") }
            MenuActionRow(action: {}) { Color.clear } content: { Text(verbatim: "Second") }
        }
        .frame(width: 240)
        .environment(keys)
        // Its first row under the pointer, wherever it rests: SwiftUI tells a
        // view it's hovered from where the pointer is, not from events a test
        // could send (2026-11-10). Above other windows, the menus other suites
        // open at the same time included, so the row is what's under it.
        let pointer = NSEvent.mouseLocation
        let window = NSWindow(contentRect: NSRect(x: pointer.x - 120, y: pointer.y - 60, width: 240, height: 80), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        defer { window.close() }
        let hosting = NSHostingView(rootView: rows)
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        await TestWait.until { keys.rows.joined().count == 2 }
        let ids = Array(keys.rows.joined())
        let first = try #require(ids.first), second = try #require(ids.last)

        // The pointer on the first row: the highlight on it, and it lit.
        await TestWait.until { keys.highlighted == first && Self.isTinted(hosting, row: first, of: keys) }
        // ↓: the second lights up; the first, still under the pointer, goes dark.
        keys.move(1)
        #expect(keys.highlighted == second)
        await TestWait.until { Self.isTinted(hosting, row: second, of: keys) }
        let firstLit = Self.isTinted(hosting, row: first, of: keys)
        #expect(!firstLit)
    }

    /// Whether `row` is drawn with its tint: a pixel in its 6 pt inside,
    /// left of its picture, isn't clear.
    private static func isTinted(_ view: NSView, row: UUID, of keys: KeyHighlight) -> Bool {
        guard let frame = keys.controls[row]?.frame, frame != .zero,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let pixel = bitmap.colorAt(x: Int((frame.minX + 3) * scale), y: Int(frame.midY * scale))
        return (pixel?.alphaComponent ?? 0) > 0.01
    }
}
