import AppKit
import SwiftUI

/// Opens when a player that must learn is chosen: it asks the user to play
/// and pause it once, ticks each step as it's seen, and closes by itself
/// once AutoHush has learned. "Later" closes it; the Controls row of the
/// menu's card and of Settings opens a new one (`ControlsRow`). Its title
/// names the player.
@MainActor
final class LearningWindowController: HostedWindowController, LearningWindowPresenting, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    init(model: SettingsModel) {
        // Later closes the window, which exists only once this has run.
        let hosting = Self.sizedToFit(LearningWindowView(model: model, later: {}))
        // Floating: the web app comes in front while it's played and paused.
        super.init(content: hosting, title: Self.title(model.chosenPlayer?.name), floatsInCorner: true)
        hosting.rootView = LearningWindowView(model: model) { [weak self] in self?.close() }
        followTitle { Self.title(model.chosenPlayer?.name) }
        window?.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    /// In the title bar: what it learns, of which player.
    static func title(_ name: String?) -> String {
        guard let name else { return "AutoHush" }
        return String(localized: "Learn \(name)’s Controls",
                      comment: "Title of the window that asks to play and pause a web app once, in its title bar; %@ is its name")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
