// Presses the keyboard's Play/Pause key, as a user would: macOS sends it to
// the app it counts as playing now ("Now Playing"), whichever that is.
// Usage: mediakey [play]
import AppKit

/// NX_KEYTYPE_PLAY in IOKit's ev_keymap.h.
let playKey = 16

func post(down: Bool) {
    let state = down ? 0xA : 0xB
    let event = NSEvent.otherEvent(
        with: .systemDefined, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
        timestamp: 0, windowNumber: 0, context: nil,
        subtype: 8, data1: (playKey << 16) | (state << 8), data2: -1)
    event?.cgEvent?.post(tap: .cghidEventTap)
}

// Without the Accessibility permission macOS drops posted events silently.
print("may post keys: \(CGPreflightPostEventAccess() ? "yes" : "no")")
post(down: true)
usleep(50_000)
post(down: false)
print("pressed Play/Pause")
