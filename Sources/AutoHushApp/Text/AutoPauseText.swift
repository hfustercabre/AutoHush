import Foundation

/// The feature's name, wherever the app shows it: the menu card's switch
/// and its label, Settings → General's switch, Diagnostics' row. (The
/// Focus filter's, an App Intents resource, keeps its own literal.)
enum AutoPauseText {
    static var title: String {
        String(localized: "Auto-Pause", comment: "Auto-Pause, the feature's name: the switch's label in the menu's card and Settings → General, a Diagnostics row, the Focus filter's name, and the name of the Focus filter's On/Off choice")
    }
}
