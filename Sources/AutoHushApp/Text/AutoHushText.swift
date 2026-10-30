import Foundation

/// What several places say about AutoHush itself: Settings → About, its
/// sidebar, General and Diagnostics.
enum AutoHushText {
    static func version(_ version: String) -> String {
        String(localized: "Version \(version)", comment: "Settings → About, Settings' sidebar and Diagnostics; %@ is AutoHush's version")
    }

    static var launchAtLogin: String {
        String(localized: "Launch at login", comment: "Settings → General and Diagnostics: whether AutoHush opens when you log in")
    }
}
