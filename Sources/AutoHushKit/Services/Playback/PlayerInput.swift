import AppKit
import os

/// Whether the user played or paused the media player since a moment: a key
/// pressed or a click while the player was already the frontmost app (not
/// the click or keys that bring it forward: a player may play its trailer
/// again as it comes forward). Otherwise a start is the app's own (an
/// autoplay, the next trailer). Read from macOS's input on the Mac's own
/// keyboard, mouse and trackpad: moving the pointer doesn't count, nor
/// events apps post (AutoHush's own presses). Media keys don't count (the
/// user, 2026-10-25): while another app plays, macOS sends them to it, and
/// their time can't tell Play/Pause from the volume keys. A click in one of
/// the player's own windows while it isn't in front (its menu bar icon, its
/// menu) counts too (`PlayerWindowClicks`).
package final class PlayerInput: NSObject, Sendable {
    private let bundleID: String
    /// When the player was the frontmost app, the last 10 minutes; an open
    /// span while it still is.
    private let spans = OSAllocatedUnfairLock<[FrontSpan]>(initialState: [])
    typealias FrontSpan = (from: Date, to: Date?)
    /// A click that brings another app forward comes a moment before macOS
    /// says it's frontmost.
    static let activationLag: TimeInterval = 0.5
    /// How long the spans are kept.
    static let spanMemory: TimeInterval = 600
    /// How long ago the latest input of a kind came (`UserInput.secondsSince`).
    private let secondsSince: @Sendable (CGEventType) -> Double
    /// Clicks in the player's own windows while another app is in front.
    private let clicks: PlayerWindowClicks

    /// `frontmost`, the frontmost app's bundle ID, `activations`, where
    /// macOS says an app came forward, and `clicks` in its own windows
    /// (`nil`: watched for real): tests give their own (1.2.1's review:
    /// these were never tested).
    package init(bundleID: String,
                 secondsSince: @escaping @Sendable (CGEventType) -> Double = UserInput.secondsSince,
                 frontmost: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
                 activations: NotificationCenter = NSWorkspace.shared.notificationCenter,
                 clicks: PlayerWindowClicks? = nil) {
        self.bundleID = bundleID
        self.secondsSince = secondsSince
        self.clicks = clicks ?? PlayerWindowClicks(bundleID: bundleID, memory: Self.spanMemory)
        super.init()
        if frontmost() == bundleID {
            spans.withLock { $0 = [(Date(), nil)] }
        }
        activations.addObserver(
            self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    @objc private func activated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let id = app?.bundleIdentifier, date = Date()
        spans.withLock { $0 = Self.spans($0, afterActivating: id, player: bundleID, at: date) }
    }

    /// The spans once `activated` came forward at `date`: one opened as the
    /// player does, the open one closed as another app does; those ended
    /// longer than `spanMemory` ago forgotten.
    static func spans(_ spans: [FrontSpan], afterActivating activated: String?, player: String, at date: Date) -> [FrontSpan] {
        var spans = spans
        if activated == player {
            if spans.last.map({ $0.to != nil }) ?? true { spans.append((date, nil)) }
        } else if let last = spans.last, last.to == nil {
            spans[spans.count - 1].to = date
        }
        spans.removeAll { ($0.to ?? .distantFuture) < date.addingTimeInterval(-spanMemory) }
        return spans
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

    /// Whether the user pressed a key or clicked in the player after `date`.
    /// Each kind's latest is read on its own, so a key pressed elsewhere
    /// since doesn't hide a click in the player.
    package func since(_ date: Date) -> Bool {
        Self.played(since: date, now: Date(), spans: spans.withLock { $0 }, secondsSince: secondsSince) || clicks.since(date)
    }

    /// `since`, from the spans the player was in front and each kind of
    /// input's age.
    static func played(since date: Date, now: Date, spans: [FrontSpan], secondsSince: (CGEventType) -> Double) -> Bool {
        UserInput.keysAndClicks.contains { kind in
            guard let input = UserInput.last(kind, now: now, secondsSince: secondsSince) else { return false }
            return input > date && inFront(at: input, spans: spans)
        }
    }
}

/// When the user last pressed a key or clicked, as macOS counts it for the
/// Mac's own keyboard, mouse and trackpad (`hidSystemState`).
package enum UserInput {
    static let keysAndClicks: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// How long ago macOS saw the latest input of a kind.
    @Sendable package static func secondsSince(_ kind: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: kind)
    }

    /// When macOS saw the latest input of `kind`, if ever.
    static func last(_ kind: CGEventType, now: Date, secondsSince: (CGEventType) -> Double = secondsSince) -> Date? {
        let ago = secondsSince(kind)
        return ago.isFinite ? now.addingTimeInterval(-ago) : nil
    }
}
