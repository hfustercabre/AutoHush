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

    /// What it reads of the system, the real ones but in tests (B-5 of
    /// 11-11): Accessibility allowed; VoiceOver on; the focused element
    /// (who it is, and its frame in Cocoa's screen coordinates); this app's
    /// visible window at a point on screen; the top of the first screen,
    /// which Cocoa's coordinates go up from; and Accessibility's focus
    /// notification started (its observer, `nil` if refused) and stopped;
    /// the clock.
    struct System {
        var isTrusted: @MainActor () -> Bool = { AXIsProcessTrusted() }
        var isVoiceOverOn: @MainActor () -> Bool = { NSWorkspace.shared.isVoiceOverEnabled }
        var focused: @MainActor () -> (element: ObjectIdentifier, frame: CGRect)? = VoiceOverCursor.focusedElement
        var windowAt: @MainActor (CGPoint) -> NSWindow? = VoiceOverCursor.visibleWindow(at:)
        var screenTop: @MainActor () -> CGFloat? = { NSScreen.screens.first?.frame.maxY }
        var listen: @MainActor () -> AnyObject? = VoiceOverCursor.listenToFocus
        var stopListening: @MainActor (AnyObject) -> Void = VoiceOverCursor.stopListening(_:)
        var now: @MainActor () -> ContinuousClock.Instant = { .now }
    }

    private let system: System
    private var observer: AnyObject?
    /// When Accessibility was allowed but its notification refused: not
    /// asked again at each highlight placed (B-5 of 11-11: every highlight
    /// in the tests made an observer again), but once the trust has
    /// changed, or `retryAfter` later (a refusal at launch isn't for good:
    /// the diff review's R4).
    private var refusedAt: ContinuousClock.Instant?
    static let retryAfter: Duration = .seconds(30)
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

    init(system: System = System()) {
        self.system = system
    }

    /// A highlight that knows where its controls are on screen
    /// (`KeyHighlight.screenFrame`) follows VoiceOver from now on.
    func follow(_ highlight: KeyHighlight) {
        highlights.removeAll { $0.highlight == nil || $0.highlight === highlight }
        highlights.append(Weak(highlight: highlight))
        startIfAllowed()
        if voiceOverWatch == nil {
            // On whatever thread the change comes: to the main actor.
            voiceOverWatch = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.looksWhileNeeded() }
            }
            // A window of AutoHush's becoming key or giving it up (the menu
            // too, a panel that leaves the app in front as it was).
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                keyWatches.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.looksWhileNeeded() }
                })
            }
        }
    }

    /// Whether it tells the highlights where VoiceOver lands: Accessibility
    /// is allowed and it listens (checked each time: it can be taken away).
    func watches() -> Bool {
        startIfAllowed()
        return observer != nil && system.isTrusted()
    }

    /// Whether SwiftUI's report that VoiceOver landed on a control is taken
    /// (`Highlightable`): only while it watches, and unless the focus moved
    /// within the last half second, as SwiftUI's late report is then of
    /// where VoiceOver was before, and would take the highlight back a step.
    /// Without Accessibility, never: the focus is followed (`lookAtFocus`).
    func takesLateReport() -> Bool {
        guard watches() else { return false }
        guard let lastFocus else { return true }
        return system.now() - lastFocus > .milliseconds(500)
    }

    /// Listens once Accessibility is allowed; a refusal is remembered until
    /// the trust is seen to change, or for `retryAfter`. Accessibility taken
    /// away, it stops listening, so it listens afresh once it's back: an
    /// observer made before isn't known to tell anything then
    /// (app-services-3, the 2026-11-19 bug hunt).
    private func startIfAllowed() {
        guard system.isTrusted() else {
            refusedAt = nil
            if let observer {
                system.stopListening(observer)
                self.observer = nil
            }
            return
        }
        guard observer == nil else { return }
        if let refusedAt, system.now() - refusedAt < Self.retryAfter { return }
        observer = system.listen()
        refusedAt = observer == nil ? system.now() : nil
        // Listening now (a retry that took): the look its refusal needed stops.
        if observer != nil, look != nil { looksWhileNeeded() }
    }

    /// Accessibility's "focused element changed" for this process, on the
    /// main run loop, to the shared cursor (the only one that listens for
    /// real); `nil` if it's refused.
    private static func listenToFocus() -> AnyObject? {
        let pid = getpid()
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, _ in
            MainActor.assumeIsolated { VoiceOverCursor.shared.focusChanged() }
        }, &created) == .success, let created,
            AXObserverAddNotification(created, AXUIElementCreateApplication(pid),
                                      kAXFocusedUIElementChangedNotification as CFString, nil) == .success
        else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        return created
    }

    /// Stops `listenToFocus`'s notification: its run loop source goes.
    private static func stopListening(_ observer: AnyObject) {
        guard CFGetTypeID(observer) == AXObserverGetTypeID() else { return }
        let observer = unsafeDowncast(observer, to: AXObserver.self)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// The focused element, read in this process (no message to itself).
    private static func focusedElement() -> (element: ObjectIdentifier, frame: CGRect)? {
        guard let element = NSApp.accessibilityFocusedUIElement as AnyObject?,
              let frame = element.accessibilityFrame?() else { return nil }
        return (ObjectIdentifier(element), frame)
    }

    /// The frontmost window at `point` (Cocoa's screen coordinates), if
    /// it's one of this app's and visible.
    private static func visibleWindow(at point: CGPoint) -> NSWindow? {
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard let window = NSApp.window(withWindowNumber: number), window.isVisible else { return nil }
        return window
    }

    /// The focused element changed (Accessibility's notification): with
    /// VoiceOver on, the highlight of the control it's in follows it. Read
    /// in this process (no message to itself), as the notification comes on
    /// the main run loop.
    func focusChanged() {
        guard system.isVoiceOverOn() else { return }
        lastFocus = system.now()
        guard let frame = system.focused()?.frame, let found = place(of: frame) else { return }
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
        Task { @MainActor [weak self] in self?.startOrStopLook() }
    }

    private func startOrStopLook() {
        guard system.isVoiceOverOn(), !watches(), NSApp.keyWindow != nil else {
            look?.invalidate()
            look = nil
            // What it saw last stays while VoiceOver is on: coming back to
            // the same focus is no move (the diff review's R3, 2026-11-11).
            if !system.isVoiceOverOn() {
                lookedAt = nil
                lookedControl = nil
            }
            return
        }
        guard look == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookAtFocus() }
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
        guard NSApp.keyWindow != nil, !watches(), let seen = system.focused() else { return }
        guard seen.element != lookedAt?.element || seen.frame != lookedAt?.frame else { return }
        lookedAt = seen
        guard let found = place(of: seen.frame) else { return }
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
        guard frame != .zero, let top = system.screenTop(),
              let window = system.windowAt(CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
        highlights.removeAll { $0.highlight == nil }
        let inWindow = highlights.compactMap(\.highlight).filter { $0.window === window }
        return (inWindow, CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height))
    }
}
