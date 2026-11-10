import AppKit
import ApplicationServices

/// Where VoiceOver's cursor lands, at once, for the highlights that follow it
/// (K5, the user, 2026-11-10: "Find a way that works"). SwiftUI's
/// `AccessibilityFocusState` tells a view that VoiceOver landed on it only
/// at VoiceOver's next move (macOS 27.2, also in a bare SwiftUI app), so the
/// highlight trailed VoiceOver by a control. VoiceOver focuses the control
/// it lands on, and this app's own "focused element changed" notification
/// (an `AXObserver` on AutoHush itself, which needs Accessibility) comes
/// then: the highlight of the window it's in, whose control holds that
/// element, follows it (`KeyHighlight.followVoiceOver`). Where VoiceOver
/// lands on what can't take the focus (or without Accessibility), the
/// highlights go by SwiftUI's report, a step late (`takesLateReport`).
@MainActor
final class VoiceOverCursor {
    static let shared = VoiceOverCursor()

    private var observer: AXObserver?
    private var highlights: [Weak] = []
    /// When the focus last moved with VoiceOver on.
    private var lastFocus: ContinuousClock.Instant?

    private struct Weak {
        weak var highlight: KeyHighlight?
    }

    /// A highlight that knows where its controls are on screen
    /// (`KeyHighlight.screenFrame`) follows VoiceOver from now on.
    func follow(_ highlight: KeyHighlight) {
        highlights.removeAll { $0.highlight == nil || $0.highlight === highlight }
        highlights.append(Weak(highlight: highlight))
        startIfAllowed()
    }

    /// Whether SwiftUI's report that VoiceOver landed on a control is taken
    /// (`Highlightable`): always without Accessibility (nothing else tells);
    /// with it, unless the focus moved within the last half second, as
    /// SwiftUI's late report is then of where VoiceOver was before, and would
    /// take the highlight back a step.
    func takesLateReport() -> Bool {
        startIfAllowed()
        guard observer != nil, AXIsProcessTrusted(), let lastFocus else { return true }
        return ContinuousClock.now - lastFocus > .milliseconds(500)
    }

    private func startIfAllowed() {
        guard observer == nil, AXIsProcessTrusted() else { return }
        let pid = getpid()
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            MainActor.assumeIsolated { VoiceOverCursor.shared.focusChanged() }
        }, &created) == .success, let created,
            AXObserverAddNotification(created, AXUIElementCreateApplication(pid),
                                      kAXFocusedUIElementChangedNotification as CFString, nil) == .success
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    /// The focused element changed: with VoiceOver on, the highlight of the
    /// control it's in follows it. Read in this process (no message to
    /// itself), as the notification comes on the main run loop.
    private func focusChanged() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        lastFocus = .now
        guard let element = NSApp.accessibilityFocusedUIElement as AnyObject?,
              let frame = element.accessibilityFrame?(), frame != .zero,
              let top = NSScreen.screens.first?.frame.maxY else { return }
        // The window it's in: the frontmost there. Closed windows keep their
        // controls, and a window may lie over another's.
        let number = NSWindow.windowNumber(at: CGPoint(x: frame.midX, y: frame.midY), belowWindowWithWindowNumber: 0)
        guard let window = NSApp.window(withWindowNumber: number), window.isVisible else { return }
        // Cocoa's screen coordinates to the top-left ones `KeyHighlight.screenFrame` gives.
        let onScreen = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        highlights.removeAll { $0.highlight == nil }
        for case let highlight? in highlights.map(\.highlight) where highlight.window === window {
            if let id = highlight.control(around: onScreen) {
                highlight.followVoiceOver(to: id)
                return
            }
        }
    }
}
