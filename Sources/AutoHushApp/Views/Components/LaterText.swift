import Foundation

/// The button that closes something for now, nothing lost (the style
/// guide's Later): the update alerts, the learning and Add a Web App
/// windows once the web app is made, and Add an App's window once its
/// check is done (the check is kept).
enum LaterText {
    static var title: String {
        String(localized: "Later", comment: "Button that closes it for now: an update alert, a window that learns a web app's controls (the learning window, the Add a Web App window), or the Add an App window once its check is done (the check is kept)")
    }
}
