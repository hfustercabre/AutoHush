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
                ? String(localized: "You’ll choose another player. The app stays on your Mac, and Add an App… can add it back.",
                         comment: "Message of the alert before the media player (an app added with Add an App) is removed")
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

    /// Before Learn Again stops a web app being added (Add a Web App
    /// floats where the learning window does, and goes with its add):
    /// Return stops the add and learns, Escape cancels.
    static func stopAddingWebApp(site: String, player: String) -> NSAlert {
        confirm(
            title: stopAddingTitle(site),
            message: String(localized: "Learning \(player)’s controls again stops adding it.",
                            comment: "Message of the alert when Learn Again is clicked while Add a Web App adds another web app; %@ is the chosen web app, e.g. YouTube Music"),
            button: stopAddingButton)
    }

    /// Before a suggested web app's tile adds it while Add a Web App adds
    /// another (the workflow audit, 2026-10-22): Return stops that add and
    /// starts this one, Escape cancels.
    static func stopAddingWebApp(site: String, for newSite: String) -> NSAlert {
        confirm(
            title: stopAddingTitle(site),
            message: String(localized: "Adding \(newSite) instead stops adding it.",
                            comment: "Message of the alert when a suggested web app is clicked while Add a Web App adds another web app; %@ is the address of the one clicked, e.g. soundcloud.com"),
            button: stopAddingButton)
    }

    private static func stopAddingTitle(_ site: String) -> String {
        String(localized: "Stop Adding \(site)?",
               comment: "Alert title when Learn Again (the chosen web app's controls), or a suggested web app, is clicked while Add a Web App adds another; %@ is the address being added, e.g. music.youtube.com")
    }

    private static var stopAddingButton: String {
        String(localized: "Stop Adding",
               comment: "Default button of the alert when Learn Again, or a suggested web app, is clicked while Add a Web App adds another web app: stops that add and learns the chosen one's controls again, or adds the one clicked")
    }

    /// When something the user asked for couldn't be done (the workflow
    /// audit, 2026-10-22): the menu's or Add an App's Reopen AutoHush, the
    /// card's Reopen and Unmute. Its title, and what to do.
    static var couldNotReopenAutoHush: (title: String, message: String) {
        (String(localized: "Couldn’t Reopen AutoHush",
                comment: "Alert title when Reopen AutoHush (the menu, or Add an App for Audio Recording) couldn't quit and open AutoHush again"),
         String(localized: "Quit AutoHush and open it again.",
                comment: "Message of the alert when Reopen AutoHush couldn't reopen it: what the user can do instead"))
    }

    static func couldNotReopen(_ player: String) -> (title: String, message: String) {
        (String(localized: "Couldn’t Reopen \(player)",
                comment: "Alert title when the media player couldn't be quit and opened again with what AutoHush needs (the menu card's Reopen, or Reopen in the alert asking for it); %@ is the player"),
         tryAgain)
    }

    static func couldNotUnmute(_ player: String) -> (title: String, message: String) {
        (String(localized: "Couldn’t Unmute \(player)",
                comment: "Alert title when the menu card's Unmute couldn't make the media player play again; %@ is the player"),
         tryAgain)
    }

    private static var tryAgain: String {
        String(localized: "Try again in a moment.",
               comment: "Message of the alerts when the media player couldn't be reopened or unmuted")
    }

    /// Before Add an App's Change… forgets a check that has run (the user,
    /// 2026-10-18: "Ask first"), the same way: Return chooses another app,
    /// Escape cancels.
    static func changeApp(_ app: String) -> NSAlert {
        confirm(title: AddAppText.changeAppTitle, message: AddAppText.changeAppDiscards(app), button: AddAppText.changeAppConfirm)
    }
}
