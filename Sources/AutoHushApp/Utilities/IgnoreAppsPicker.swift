import AppKit
import AutoHushKit

/// The panel that picks apps to ignore, several at once (the user,
/// 2026-10-18): Settings → Sound Sources' Ignore Another App… and the
/// menu's, under the ignored apps.
@MainActor
enum IgnoreAppsPicker {
    /// The button's and the menu row's title.
    static var title: String {
        String(localized: "Ignore Another App…",
               comment: "Settings → Sound Sources' button, and the menu's row under the ignored apps: opens a panel to pick apps that never pause your player")
    }

    /// Asks for apps, then ignores each one (`ignore`) AutoHush can tell
    /// apart, and says which it can't.
    static func run(ignore: (AudioSource) -> Void) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an App to Ignore", comment: "Title of the panel that picks an app")
        panel.prompt = String(localized: "Ignore", comment: "Button of the panel that picks an app to ignore")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        // From the menu, AutoHush isn't the active app: the panel comes in front.
        NSApp.becomeActive()
        guard panel.runModal() == .OK else { return }
        for url in ignoreApps(at: panel.urls, ignore: ignore) {
            let alert = unidentifiedAppAlert(url: url)
            InfoAlert.show(alert.title, alert.message)
        }
    }

    /// Ignores each app at `urls` AutoHush can tell apart; the others, which
    /// don't identify themselves as Mac apps do.
    static func ignoreApps(at urls: [URL], ignore: (AudioSource) -> Void) -> [URL] {
        urls.filter { url in
            guard let source = ProcessAudioSourceIdentifier.source(forBundleAt: url) else { return true }
            ignore(source)
            return false
        }
    }

    /// An app chosen to ignore has no bundle identifier, which is how
    /// AutoHush tells apps' sound apart: it can't be ignored.
    static func unidentifiedAppAlert(url: URL) -> (title: String, message: String) {
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return (String(localized: "Couldn’t Ignore \(name)",
                       comment: "Settings → Sound Sources: title of the alert after Ignore Another App… when the chosen app can't be ignored; %@ is the app's name"),
                String(localized: "\(name) doesn’t identify itself as Mac apps do, so AutoHush can’t tell when it plays.",
                       comment: "Settings → Sound Sources: the alert after Ignore Another App…, when the chosen app has no bundle identifier (the ID a Mac app has, which AutoHush tells apps' sound apart by); %@ is the app's name"))
    }
}
