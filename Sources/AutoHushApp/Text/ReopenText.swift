import Foundation

/// Reopening an app with the option its page needs (one added with Add an
/// App, or the one Add an App checks): the alert that asks to reopen the
/// media player, the menu card's Reopen button, and Add an App's Reopen step.
enum ReopenText {
    static func title(_ app: String) -> String {
        String(localized: "Reopen \(app)", comment: "Add an App window: the step, and its button, that quits the app and opens it again with the option its page needs; the same button in the alert that asks for it; %@ is the app")
    }

    /// Why an app opened without its option needs reopening: the Reopen
    /// step's warning, the alert's message, the card's button's help.
    static func reason(_ app: String) -> String {
        String(localized: "Without an option it needs, AutoHush can pause \(app) only while its window is in view.",
               comment: "Add an App's Reopen step (as a warning), the alert that asks to reopen the media player, and the help of the menu card's Reopen button; %@ is the app")
    }

    /// The reopen alert's message: why, and that reopening stops what it
    /// plays, in one text (sentences joined in code read wrong in Chinese
    /// and Japanese).
    static func alertMessage(_ app: String) -> String {
        String(localized: "Without an option it needs, AutoHush can pause \(app) only while its window is in view. Reopening it stops what it plays.",
               comment: "Message of the alert that asks to reopen the media player (an app added with Add an App) with the option it needs; %@ is the app")
    }

    /// The reopen alert's checkbox: from then on, reopened without asking.
    static func always(_ app: String) -> String {
        String(localized: "Always reopen \(app) this way",
               comment: "Checkbox in the alert that asks to reopen the media player with the option it needs: from then on AutoHush reopens it so whenever it finds it opened without it, without asking; %@ is the app")
    }
}
