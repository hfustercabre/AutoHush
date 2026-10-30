import Foundation

/// The buttons several windows say the same way: Cancel and Continue (the
/// welcome, Add a Web App and Add an App windows, the alerts), Allow… beside
/// a permission not allowed, and Open <app>.
enum ButtonText {
    static var cancel: String {
        String(localized: "Cancel", comment: "Button that closes the window without going on: the Add a Web App and Add an App windows (stopping what they do), the window listing the apps to check, the window shown before a check, and the alerts that ask to reopen the media player or to remove an app added with Add an App")
    }

    static var `continue`: String {
        String(localized: "Continue", comment: "Button in the welcome window and the Add a Web App and Add an App windows: goes on with what's chosen or typed")
    }

    /// Goes back: the welcome window's button, Settings' toolbar arrow and
    /// the View menu's item.
    static var back: String {
        String(localized: "Back", comment: "Welcome window: button that goes back to the list of media players. Also Settings: the toolbar's arrow and the View menu's item (⌘[) that show the page shown before; macOS's own word")
    }

    static var allow: String {
        String(localized: "Allow…", comment: "Welcome window, Add an App window, the menu's card (under “Needs Automation access” and the like) and Settings → Diagnostics (beside a permission not allowed): button that asks for a permission (macOS's prompt, or System Settings)")
    }

    /// Opens an app: the media player (so macOS can ask for Automation), or
    /// the app being checked once it quit.
    static func open(_ app: String) -> String {
        String(localized: "Open \(app)", comment: "Button that opens an app: the media player, so macOS can ask for Automation (Settings, the welcome window), or, in the Add an App window, the app being checked after it quit; %@ is the app")
    }
}
