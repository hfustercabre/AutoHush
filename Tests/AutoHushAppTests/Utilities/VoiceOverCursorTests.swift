import AppKit
import Testing
@testable import AutoHushApp

/// Where VoiceOver's cursor lands, with the system it reads replaced (B-5
/// of 11-11): the highlight of the window the focus is in follows it, the
/// half second in which SwiftUI's late report is left out, and a refused
/// Accessibility notification not asked for again until the trust changes.
@Suite("VoiceOverCursor")
@MainActor
final class VoiceOverCursorTests {
    var trusted = true
    var voiceOver = true
    var focusedFrame: CGRect?
    var window: NSWindow?
    var listens: AnyObject? = NSObject()
    var listened = 0
    var now = ContinuousClock.now
    /// Cocoa's screen coordinates go up from the bottom of a screen this tall.
    let screenTop: CGFloat = 1000
    let element = NSObject()

    private func makeCursor() -> VoiceOverCursor {
        VoiceOverCursor(system: .init(
            isTrusted: { [weak self] in self?.trusted ?? false },
            isVoiceOverOn: { [weak self] in self?.voiceOver ?? false },
            focused: { [weak self] in
                guard let self, let focusedFrame else { return nil }
                return (ObjectIdentifier(element), focusedFrame)
            },
            windowAt: { [weak self] _ in self?.window },
            screenTop: { [weak self] in self?.screenTop },
            listen: { [weak self] in
                guard let self else { return nil }
                listened += 1
                return listens
            },
            now: { [weak self] in self?.now ?? .now }))
    }

    /// A highlight in its own window (not shown), its controls' frames the
    /// screen's, top-left, as `KeyHighlight.screenFrame` gives them.
    private func makeHighlight() -> (KeyHighlight, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = NSView()
        window.contentView = view
        let highlight = KeyHighlight()
        highlight.followsPointer = false
        highlight.place(in: { [weak view] in view })
        highlight.screenFrame = { $0 }
        return (highlight, window)
    }

    /// The control's frame (top-left) as Accessibility gives an element's: Cocoa's, up from the bottom.
    private func cocoa(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: screenTop - frame.maxY, width: frame.width, height: frame.height)
    }

    @Test("the focus moved with VoiceOver on: the highlight of the window it's in follows it, onto its control; not another window's, not off this app's windows, not a frame much larger, not with VoiceOver off")
    func focusFollowed() {
        let cursor = makeCursor()
        let (front, frontWindow) = makeHighlight()
        let (behind, _) = makeHighlight()
        let frame = CGRect(x: 20, y: 100, width: 120, height: 22)
        let control = UUID(), sameFrameBehind = UUID()
        front.register(control, .init(frame: frame))
        behind.register(sameFrameBehind, .init(frame: frame))
        cursor.follow(front)
        cursor.follow(behind)

        focusedFrame = cocoa(frame)
        voiceOver = false
        window = frontWindow
        cursor.focusChanged()
        #expect(front.highlighted == nil) // VoiceOver off: the focus is the user's
        voiceOver = true
        window = nil
        cursor.focusChanged()
        #expect(front.highlighted == nil) // off this app's windows
        window = frontWindow
        focusedFrame = cocoa(frame.insetBy(dx: -40, dy: -40)) // a page around it, its middle in the control
        cursor.focusChanged()
        #expect(front.highlighted == nil)
        focusedFrame = cocoa(frame.insetBy(dx: 4, dy: 2)) // the switch in the row
        cursor.focusChanged()
        #expect(front.highlighted == control && front.isLitByKeys)
        #expect(behind.highlighted == nil) // the window under it isn't the focus's
    }

    @Test("SwiftUI's late report is taken only while Accessibility's notification comes, and not within half a second of the focus moving")
    func lateReport() {
        let cursor = makeCursor()
        trusted = false
        #expect(!cursor.takesLateReport() && !cursor.watches()) // no Accessibility: the look follows the focus
        trusted = true
        #expect(cursor.watches() && cursor.takesLateReport()) // no focus move yet
        cursor.focusChanged()
        now += .milliseconds(400)
        #expect(!cursor.takesLateReport()) // the report is of where VoiceOver was before
        now += .milliseconds(200)
        #expect(cursor.takesLateReport())
        voiceOver = false
        cursor.focusChanged() // VoiceOver off: no move of its
        #expect(cursor.takesLateReport())
    }

    @Test("a refused notification isn't asked for again at each highlight, only once the trust has changed (B-5 of 11-11)")
    func refusedOnce() {
        let cursor = makeCursor()
        voiceOver = false // no look started meanwhile
        listens = nil // refused, though trusted
        let (highlight, _) = makeHighlight()
        cursor.follow(highlight)
        #expect(!cursor.watches() && !cursor.takesLateReport())
        cursor.follow(highlight)
        #expect(listened == 1)
        trusted = false
        #expect(!cursor.watches())
        trusted = true
        listens = NSObject()
        #expect(cursor.watches())
        #expect(listened == 2)
        #expect(cursor.watches() && listened == 2) // listening: once
    }
}
