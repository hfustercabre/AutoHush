import Foundation

/// What `SafariWebAppMaker` does in Safari. A protocol, so tests stand in.
package protocol SafariDriving: Sendable {
    func isTrusted(prompt: Bool) async -> Bool
    /// Opens the address in Safari, in front; `false` when it couldn't.
    func open(_ url: URL) async -> Bool
    /// Waits until the page in Safari's front window has loaded and can be
    /// added: that tab; `nil` after a while.
    func waitForPage() async -> SafariTab?
    /// The address of the page in Safari's front window; `nil` when it
    /// can't be read.
    func frontPageURL() async -> URL?
    /// The tab showing the page in Safari's front window now; `nil` when
    /// there's none.
    func frontTab() async -> SafariTab?
    /// Chooses File → Add to Dock, makes sure the dialog has `url` (the page
    /// may have moved), and waits while the user names the web app and
    /// clicks Add (or Cancel) there. If the task is cancelled meanwhile, it
    /// clicks the dialog's Cancel.
    func addToDock(_ url: URL) async -> AddToDockResult
    /// Closes `tab` (its window, when it's the window's only tab), if it's
    /// still the one in front showing the same page: never a tab the user
    /// moved to since.
    func closeTab(_ tab: SafariTab) async
}
