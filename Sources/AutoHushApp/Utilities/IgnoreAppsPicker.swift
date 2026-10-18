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
    /// apart, and says in one alert which it can't.
    static func run(ignore: (AudioSource) -> Void) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Apps to Ignore",
                             comment: "Title of the panel that picks one or more apps to ignore (Settings → Sound Sources' and the menu's Ignore Another App…)")
        panel.prompt = String(localized: "Ignore", comment: "Button of the panel that picks one or more apps to ignore")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        // From the menu, AutoHush isn't the active app: the panel comes in front.
        NSApp.becomeActive()
        guard panel.runModal() == .OK,
              let alert = unidentifiedAppsAlert(urls: ignoreApps(at: panel.urls, ignore: ignore)) else { return }
        InfoAlert.show(alert.title, alert.message)
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

    /// Apps chosen to ignore that have no bundle identifier, which is how
    /// AutoHush tells apps' sound apart: they can't be ignored. One alert
    /// for all of them (the full check, 2026-10-18); `nil` for none.
    static func unidentifiedAppsAlert(urls: [URL]) -> (title: String, message: String)? {
        let names = urls.map { (FileManager.default.displayName(atPath: $0.path) as NSString).deletingPathExtension }
        switch names.count {
        case 0:
            return nil
        case 1:
            return (String(localized: "Couldn’t Ignore \(names[0])",
                           comment: "Settings → Sound Sources' or the menu's Ignore Another App…: title of the alert when the chosen app can't be ignored; %@ is the app's name"),
                    String(localized: "\(names[0]) doesn’t identify itself as Mac apps do, so AutoHush can’t tell when it plays.",
                           comment: "Settings → Sound Sources' or the menu's Ignore Another App…: the alert when the chosen app has no bundle identifier (the ID a Mac app has, which AutoHush tells apps' sound apart by); %@ is the app's name"))
        default:
            let list = ListFormatter.localizedString(byJoining: names)
            return (String(localized: "Couldn’t Ignore \(names.count) Apps",
                           comment: "Settings → Sound Sources' or the menu's Ignore Another App…: title of the alert when several of the chosen apps can't be ignored; %lld is how many (2 or more)"),
                    String(localized: "\(list) don’t identify themselves as Mac apps do, so AutoHush can’t tell when they play.",
                           comment: "Settings → Sound Sources' or the menu's Ignore Another App…: the alert when several chosen apps have no bundle identifier (the ID a Mac app has, which AutoHush tells apps' sound apart by); %@ is their names, already joined as a list (“A, B and C”)"))
        }
    }
}
