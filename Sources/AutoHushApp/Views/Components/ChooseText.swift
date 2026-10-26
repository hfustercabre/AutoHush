import Foundation

/// The buttons that choose, then choose again: the media player (Settings →
/// General and Diagnostics) and Add an App's app.
enum ChooseText {
    /// Where no player is chosen yet: Diagnostics' button beside “Player”
    /// and Settings → General's beside “No player chosen”.
    static var choose: String {
        String(localized: "Choose…", comment: "Settings → Diagnostics' button beside “Player” while none is chosen or it's not installed, and Settings → General's beside “No player chosen”, which open Settings' Media Player page")
    }

    /// Add an App's app once chosen, or Settings → General's media player:
    /// choose another.
    static var change: String {
        String(localized: "Change…", comment: "Add an App window: button under the step “Choose the app” once done, which chooses another app; also under “Play something” and the check’s step when the app can’t be found any more. Also Settings → General, beside the media player: opens the page with every player, to choose another")
    }
}
