import AppKit

/// The alert before an app added with Add an App is removed (R0, the user's
/// pick, 2026-10-15), and before Change… forgets a check: short, as the user asked. Remove is its default
/// button, blue, not red (the user, 2026-10-16): Return removes, Escape
/// cancels.
@MainActor
enum PlayerAlerts {
    /// Before an app added with Add an App is removed (its tile's ×, or
    /// Option in the menu). `isChosen`: it's the media player now.
    static func remove(_ app: String, isChosen: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove \(app)?",
                                   comment: "Alert title before an app added with Add an App is removed from AutoHush's media players; %@ is the app")
        alert.informativeText = isChosen
            ? String(localized: "It’s your current player, so you’ll choose another. \(app) won’t be offered as a player anymore. The app stays on your Mac. Add an App… can add it back.",
                     comment: "Message of the alert before the media player (an app added with Add an App) is removed; %@ is the app")
            : String(localized: "\(app) won’t be offered as a player anymore. The app stays on your Mac. Add an App… can add it back.",
                     comment: "Message of the alert before an app added with Add an App is removed from the media players; %@ is the app")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Remove", comment: "A button that removes: under Settings → Sound Sources' list (the selected app), in its confirmation for an app that's turned off, and in the alert before an app added with Add an App is removed"))
        alert.addButton(withTitle: AddAppText.cancel).keyEquivalent = "\u{1b}" // Escape
        return alert
    }

    /// Before Add an App's Change… forgets a check that has run (the user,
    /// 2026-10-18: "Ask first"), the same way: Return chooses another app,
    /// Escape cancels.
    static func changeApp(_ app: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = AddAppText.changeAppTitle
        alert.informativeText = AddAppText.changeAppDiscards(app)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AddAppText.changeAppConfirm)
        alert.addButton(withTitle: AddAppText.cancel).keyEquivalent = "\u{1b}" // Escape
        return alert
    }
}
