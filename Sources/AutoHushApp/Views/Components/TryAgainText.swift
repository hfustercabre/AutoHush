import Foundation

/// The button that tries again, in macOS's own word wherever one does
/// (E10, the full check, 2026-10-19; the card's said "Retry"). Add an App's
/// Check Again keeps its own: it says what it runs again.
enum TryAgainText {
    static var title: String {
        String(localized: "Try Again",
               comment: "Button that tries again: on the menu's card after a problem (starting again); under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself; under Add an App's “Play something in %@” once the app didn't play in time")
    }
}
