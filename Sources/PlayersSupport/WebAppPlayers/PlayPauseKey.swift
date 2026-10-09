import AppKit
import OSLog

/// The keyboard's Play/Pause key, pressed as a user would. macOS sends it to
/// the app it counts as playing now ("Now Playing"), not to one AutoHush
/// picks: a web app playing a song is that app, but one that played last can
/// be too. Posting it needs Accessibility, which web apps need anyway.
enum PlayPauseKey {
    /// `NX_KEYTYPE_PLAY` in IOKit's ev_keymap.h.
    private static let playKey = 16

    private static let logger = Logger(category: "WebAppPlayer")

    /// Down, then up. On the main thread, where AppKit builds events.
    @MainActor
    static func press() {
        // Without it macOS drops the key silently: the log says why.
        if !CGPreflightPostEventAccess() { logger.error("macOS doesn't let AutoHush post the Play/Pause key") }
        post(down: true)
        post(down: false)
    }

    @MainActor
    private static func post(down: Bool) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: (playKey << 16) | (state << 8), data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
