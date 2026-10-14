import AppKit
import SwiftUI

/// What `AppDelegate` needs of the welcome window; tests stand in for it, so
/// they never put a window on screen.
@MainActor
protocol PlayerChooserPresenting: AnyObject {
    var isOpen: Bool { get }
    func show()
    func bringForward()
    func close()
}

/// The welcome window: asks which media player AutoHush controls, then for
/// the permissions it needs. It opens at launch while none is chosen, and
/// again when a supported player opens then. Closing it leaves AutoHush
/// waiting; the menu and Settings can choose too. Its title is its page's.
@MainActor
final class PlayerChooserWindowController: HostedWindowController, PlayerChooserPresenting {
    /// `tallestPage`: as for `PlayerChooserView`, else the screen's.
    init(model: SettingsModel, tallestPage: CGFloat? = nil) {
        let view = PlayerChooserView(model: model, tallestPage: tallestPage ?? PlayerChooserView.tallestOnScreen)
        super.init(content: Self.sizedToFit(view), title: Self.title(asksPermissions: model.welcomeAsksPermissions))
        followTitle { Self.title(asksPermissions: model.welcomeAsksPermissions) }
    }

    /// The page's title, in the title bar.
    static func title(asksPermissions: Bool) -> String {
        asksPermissions
            ? String(localized: "Allow AutoHush to Work",
                     comment: "Welcome window: the title (in its title bar) of the page that asks for the permissions AutoHush needs")
            : String(localized: "Choose Your Media Player", comment: "Welcome window: its title, in its title bar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
