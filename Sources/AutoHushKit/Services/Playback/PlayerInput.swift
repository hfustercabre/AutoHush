import AppKit
import os

/// Whether the user played or paused the media player since a moment: a key
/// pressed or a click while the player was already the frontmost app (not
/// the click or keys that bring it forward: Apple TV plays its trailer again
/// as it comes forward), or a media key (Play/Pause on the keyboard). Otherwise a start is the app's own (an
/// autoplay, the next trailer). Read from macOS's input on the Mac's own
/// keyboard, mouse and trackpad: moving the pointer doesn't count, nor events
/// apps post (AutoHush's own presses). A headphones' button sends no such
/// event, so a play from one counts as the app's.
package final class PlayerInput: NSObject, Sendable {
    private let bundleID: String
    /// When the player was the frontmost app, the last 10 minutes; an open
    /// span while it still is.
    private let spans = OSAllocatedUnfairLock<[FrontSpan]>(initialState: [])
    typealias FrontSpan = (from: Date, to: Date?)
    /// A click that brings another app forward comes a moment before macOS
    /// says it's frontmost.
    static let activationLag: TimeInterval = 0.5

    package init(bundleID: String) {
        self.bundleID = bundleID
        super.init()
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            spans.withLock { $0 = [(Date(), nil)] }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    @objc private func activated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let id = app?.bundleIdentifier, date = Date()
        spans.withLock { spans in
            if id == bundleID {
                if spans.last.map({ $0.to != nil }) ?? true { spans.append((date, nil)) }
            } else if let last = spans.last, last.to == nil {
                spans[spans.count - 1].to = date
            }
            spans.removeAll { ($0.to ?? .distantFuture) < date.addingTimeInterval(-600) }
        }
    }

    private func wasFrontmost(at date: Date) -> Bool {
        spans.withLock { Self.inFront(at: date, spans: $0) }
    }

    /// Whether input at `date` came while the player was already in front:
    /// the click or keys that bring it forward come before macOS says it's
    /// frontmost, so they don't (the user, 2026-10-25: "only input while
    /// it's already in front"), and a click that brings another app forward
    /// is that app's, though macOS says so a moment later.
    static func inFront(at date: Date, spans: [FrontSpan]) -> Bool {
        spans.contains {
            $0.from <= date && date < ($0.to.map { $0.addingTimeInterval(-activationLag) } ?? .distantFuture)
        }
    }

    /// Whether the user pressed a key or clicked in the player, or pressed a
    /// media key, after `date`.
    package func since(_ date: Date) -> Bool {
        let now = Date()
        if let input = UserInput.last(of: UserInput.keysAndClicks, now: now), input > date, wasFrontmost(at: input) { return true }
        return UserInput.lastMediaKey(now: now).map { $0 > date } ?? false
    }
}

/// When the user last pressed a key or clicked, as macOS counts it for the
/// Mac's own keyboard, mouse and trackpad (`hidSystemState`).
package enum UserInput {
    static let keysAndClicks: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    static let buttons: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                         .otherMouseDown, .otherMouseUp]
    /// System-defined events: the keyboard's media keys (its volume keys
    /// too), but also every mouse button going down or up (measured on the
    /// user's Mac, 2026-10-24: its time equals the last click's).
    static let systemDefined = CGEventType(rawValue: 14)!
    /// A system-defined event this close to a mouse button's is that button's.
    static let sameEvent: TimeInterval = 0.05

    /// When a media key was last pressed: the last system-defined event,
    /// unless it was a mouse button's. A click after a media key hides it.
    static func lastMediaKey(now: Date) -> Date? {
        guard let event = last(of: [systemDefined], now: now) else { return nil }
        let buttons = buttons.compactMap { last(of: [$0], now: now) }
        return buttons.contains(where: { abs($0.timeIntervalSince(event)) < sameEvent }) ? nil : event
    }

    static func last(of kinds: [CGEventType], now: Date) -> Date? {
        let ago = kinds.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .infinity
        return ago.isFinite ? now.addingTimeInterval(-ago) : nil
    }
}
