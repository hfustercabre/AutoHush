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
/// element, follows it (`KeyHighlight.followFocus`, past the echo of a
/// key's own arrival: W-2). Where VoiceOver lands on what can't take the
/// focus, the highlights go by SwiftUI's report, a step late
/// (`takesLateReport`). Without Accessibility, no notification comes:
/// while VoiceOver is on and a window of AutoHush's is key, it looks at
/// the focused element five times a second instead (in this process, which
/// needs no permission), and the highlight follows the focus the same way
/// (D-1, the user's A, 2026-11-11: SwiftUI's late report left the
/// highlight on the control VoiceOver had left, and Return acted on it).
@MainActor
final class VoiceOverCursor {
    static let shared = VoiceOverCursor()

    private var observer: AXObserver?
    private var highlights: [Weak] = []
    /// When the focus last moved with VoiceOver on.
    private var lastFocus: ContinuousClock.Instant?
    /// Whether VoiceOver is on, watched to look only while it is.
    private var voiceOverWatch: NSKeyValueObservation?
    /// AutoHush's windows becoming key and giving it up: the look runs only
    /// while one of them is key. Kept for the app's life, as the cursor is.
    private var keyWatches: [any NSObjectProtocol] = []
    /// The look at the focused element without Accessibility.
    private var look: Timer?
    /// The focused element seen last by `lookAtFocus`, and where it was.
    private var lookedAt: (element: ObjectIdentifier, frame: CGRect)?
    /// The control `lookAtFocus` found the focus in last: a frame that moved
    /// alone (a scroll, a caption) is no move of the focus (R2).
    private var lookedControl: (highlight: ObjectIdentifier, id: UUID)?

    private struct Weak {
        weak var highlight: KeyHighlight?
    }

    /// A highlight that knows where its controls are on screen
    /// (`KeyHighlight.screenFrame`) follows VoiceOver from now on.
    func follow(_ highlight: KeyHighlight) {
        highlights.removeAll { $0.highlight == nil || $0.highlight === highlight }
        highlights.append(Weak(highlight: highlight))
        startIfAllowed()
        if voiceOverWatch == nil {
            // On whatever thread the change comes: to the main actor.
            voiceOverWatch = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial]) { _, _ in
                Task { @MainActor in VoiceOverCursor.shared.looksWhileNeeded() }
            }
            // A window of AutoHush's becoming key or giving it up (the menu
            // too, a panel that leaves the app in front as it was).
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                keyWatches.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { VoiceOverCursor.shared.looksWhileNeeded() }
                })
            }
        }
    }

    /// Whether it tells the highlights where VoiceOver lands: Accessibility
    /// is allowed and it listens (checked each time: it can be taken away).
    func watches() -> Bool {
        startIfAllowed()
        return observer != nil && AXIsProcessTrusted()
    }

    /// Whether SwiftUI's report that VoiceOver landed on a control is taken
    /// (`Highlightable`): only while it watches, and unless the focus moved
    /// within the last half second, as SwiftUI's late report is then of
    /// where VoiceOver was before, and would take the highlight back a step.
    /// Without Accessibility, never: the focus is followed (`lookAtFocus`).
    func takesLateReport() -> Bool {
        guard watches() else { return false }
        guard let lastFocus else { return true }
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

    /// The focused element changed (Accessibility's notification): with
    /// VoiceOver on, the highlight of the control it's in follows it. Read
    /// in this process (no message to itself), as the notification comes on
    /// the main run loop.
    private func focusChanged() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        lastFocus = .now
        guard let element = NSApp.accessibilityFocusedUIElement as AnyObject?,
              let frame = element.accessibilityFrame?(), let found = place(of: frame) else { return }
        for highlight in found.highlights {
            // As the look's: not the late echo of a key's own arrival (W-2).
            if let id = highlight.control(around: found.onScreen) {
                highlight.followFocus(to: id)
                return
            }
        }
    }

    /// Looks at the focused element five times a second while it's needed:
    /// VoiceOver on, no Accessibility (its notification tells otherwise),
    /// and a window of AutoHush's key; no timer otherwise, so no wakeups
    /// (the 1.4.0 review's W-3, 2026-11-11: it ran whenever VoiceOver was).
    private func looksWhileNeeded() {
        // A window giving the key up tells it while it's still key: look next turn.
        Task { @MainActor in VoiceOverCursor.shared.startOrStopLook() }
    }

    private func startOrStopLook() {
        guard NSWorkspace.shared.isVoiceOverEnabled, !watches(), NSApp.keyWindow != nil else {
            look?.invalidate()
            look = nil
            // What it saw last stays while VoiceOver is on: coming back to
            // the same focus is no move (the diff review's R3, 2026-11-11).
            if !NSWorkspace.shared.isVoiceOverEnabled {
                lookedAt = nil
                lookedControl = nil
            }
            return
        }
        guard look == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { VoiceOverCursor.shared.lookAtFocus() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        look = timer
    }

    /// Without Accessibility: the focus, which VoiceOver moves where it
    /// lands, moved since the last look: the highlight of the control it's
    /// in follows it, or, onto no control, the one the focus lit goes out.
    private func lookAtFocus() {
        // A key window, not an active app: the menu is a panel that leaves
        // the app in front as it was (the diff review's R1).
        guard NSApp.keyWindow != nil, !watches(), let element = NSApp.accessibilityFocusedUIElement as AnyObject?,
              let frame = element.accessibilityFrame?() else { return }
        let seen = (element: ObjectIdentifier(element), frame: frame)
        guard seen.element != lookedAt?.element || seen.frame != lookedAt?.frame else { return }
        lookedAt = seen
        guard let found = place(of: frame) else { return }
        for highlight in found.highlights {
            if let id = highlight.control(around: found.onScreen) {
                let control = (highlight: ObjectIdentifier(highlight), id: id)
                guard control.highlight != lookedControl?.highlight || control.id != lookedControl?.id else { return }
                lookedControl = control
                highlight.followFocus(to: id)
                return
            }
        }
        lookedControl = nil
        found.highlights.forEach { $0.focusGone() }
    }

    /// The highlights of the window an element is in (the frontmost there:
    /// closed windows keep their controls, and a window may lie over
    /// another's), and its frame in the top-left screen coordinates
    /// `KeyHighlight.screenFrame` gives. `nil` off this app's visible windows.
    private func place(of frame: CGRect) -> (highlights: [KeyHighlight], onScreen: CGRect)? {
        guard frame != .zero, let top = NSScreen.screens.first?.frame.maxY else { return nil }
        let number = NSWindow.windowNumber(at: CGPoint(x: frame.midX, y: frame.midY), belowWindowWithWindowNumber: 0)
        guard let window = NSApp.window(withWindowNumber: number), window.isVisible else { return nil }
        highlights.removeAll { $0.highlight == nil }
        let inWindow = highlights.compactMap(\.highlight).filter { $0.window === window }
        return (inWindow, CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height))
    }
}
