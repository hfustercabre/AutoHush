import AppKit

/// The alert before an app added with Add an App is removed (R0, the user's
/// pick, 2026-10-15), and before Change… forgets a check: short, as the user asked. Remove is its default
/// button, blue, not red (the user, 2026-10-16): Return removes, Escape
/// cancels. Each is a `confirm`, as is the one before a player is reopened.
@MainActor
enum PlayerAlerts {
    /// A warning that asks before doing something: `button` first, which
    /// Return presses, then Cancel, which Escape presses (X22, the full
    /// check, 2026-10-19).
    static func confirm(title: String, message: String, button: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: AddAppText.cancel).keyEquivalent = "\u{1b}" // Escape
        return alert
    }

    /// Before an app added with Add an App is removed (its tile's ×, or
    /// Option in the menu). `isChosen`: it's the media player now.
    static func remove(_ app: String, isChosen: Bool) -> NSAlert {
        confirm(
            title: String(localized: "Remove \(app)?",
                          comment: "Alert title before an app added with Add an App is removed from AutoHush's media players; %@ is the app"),
            message: isChosen
                ? String(localized: "It’s your current player, so you’ll choose another. \(app) won’t be offered as a player anymore. The app stays on your Mac. Add an App… can add it back.",
                         comment: "Message of the alert before the media player (an app added with Add an App) is removed; %@ is the app")
                : String(localized: "\(app) won’t be offered as a player anymore. The app stays on your Mac. Add an App… can add it back.",
                         comment: "Message of the alert before an app added with Add an App is removed from the media players; %@ is the app"),
            button: removeTitle
        )
    }

    /// Its default button, and Settings → Sound Sources' that removes the
    /// apps selected (and its confirmation's).
    static var removeTitle: String {
        String(localized: "Remove", comment: "A button that removes: under Settings → Sound Sources' list (the selected apps), in its confirmation for removing apps turned off, and in the alert before an app added with Add an App is removed")
    }

    /// Before Add an App's Change… forgets a check that has run (the user,
    /// 2026-10-18: "Ask first"), the same way: Return chooses another app,
    /// Escape cancels.
    static func changeApp(_ app: String) -> NSAlert {
        confirm(title: AddAppText.changeAppTitle, message: AddAppText.changeAppDiscards(app), button: AddAppText.changeAppConfirm)
    }
}
