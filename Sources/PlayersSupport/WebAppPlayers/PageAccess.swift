import AppKit
import Foundation

/// How an app shows its page to Accessibility, as Player Check finds it.
/// Safari's WebKit (a Safari web app's page, a Tauri app's) shows it as it
/// is; Electron, CEF and Flutter apps, and a Chromium browser's web apps,
/// only once a switch for assistive tools is on, which AutoHush then keeps
/// on while the app is its player (`AccessibilityWebPage`).
package struct PageAccess: Codable, Equatable, Sendable {
    /// What the app's interface is built with, as its bundle tells it
    /// (`interface(ofAppAt:)`): whether its page shows as it is or needs a
    /// switch (`switches(for:)`), and where that switch is set.
    package enum Interface: Codable, Equatable, Sendable {
        /// Safari's WebKit: shown as it is, its words current out of sight.
        case webKit
        /// A web page that shows with Electron's own switch.
        case electron
        /// The Chromium Embedded Framework (Spotify): a web page, with
        /// Electron's switch or VoiceOver's, as each app decides.
        case cef
        /// Flutter (Spotube): the window's own elements, with VoiceOver's switch.
        case flutter
        /// A Chromium browser's web app (Chrome's, Brave's): its page is
        /// served by the browser, `browserID`, which the switch is set on.
        case chromiumWebApp(browserID: String)
        /// Chromium inside Qt (Qt WebEngine): shown as it is, but its words
        /// current only while its window can be seen, as any Chromium page's.
        case qtWebEngine
    }

    package var interface: Interface
    /// The switch that showed its page in the check, set on the process
    /// that serves it; `nil` for WebKit.
    package var switchAttribute: String?

    package init(interface: Interface, switchAttribute: String?) {
        self.interface = interface
        self.switchAttribute = switchAttribute
    }

    /// A Safari web app's, or any WebKit page's.
    package static let webKit = PageAccess(interface: .webKit, switchAttribute: nil)
    /// Electron's own switch (documented on electronjs.org).
    package static let electronSwitch = "AXManualAccessibility"
    /// The switch VoiceOver sets, which CEF, Flutter and Chromium listen to.
    package static let voiceOverSwitch = "AXEnhancedUserInterface"

    /// The switches to try for `interface`, in order.
    package static func switches(for interface: Interface) -> [String] {
        switch interface {
        case .webKit, .qtWebEngine: []
        case .electron: [electronSwitch]
        case .cef: [electronSwitch, voiceOverSwitch]
        case .flutter, .chromiumWebApp: [voiceOverSwitch]
        }
    }

    /// Whether its page's words are current while none of its windows can be
    /// seen: WebKit's are (measured on Pake's YouTube Music and SoundCloud's
    /// web app on another desktop); Chromium builds and updates a page only
    /// while its window shows, and so does Flutter its interface.
    package var wordsCurrentOutOfSight: Bool { interface == .webKit }

    /// Its page is the window's own elements (Flutter's), not a web area.
    package var pageIsWindow: Bool { interface == .flutter }

    /// The browser that serves a Chromium web app's page; `nil` for any other.
    package var browserID: String? {
        if case .chromiumWebApp(let browserID) = interface { browserID } else { nil }
    }

    /// The interface of the app at `url`, by the frameworks in its bundle; a
    /// Chromium browser's web app by its launcher's Info.plist, which names
    /// the site it opens and its browser (Chromium writes both). `.webKit`
    /// for any other app: its page, if it has one, shows as it is. Player
    /// Check tells an app's interface with this.
    package static func interface(ofAppAt url: URL) -> Interface {
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        if info["CrAppModeShortcutURL"] != nil, let browserID = info["CrBundleIdentifier"] as? String {
            return .chromiumWebApp(browserID: browserID)
        }
        let frameworks = url.appendingPathComponent("Contents/Frameworks")
        func has(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("\(name).framework").path)
        }
        if has("Electron Framework") { return .electron }
        if has("Chromium Embedded Framework") { return .cef }
        if has("FlutterMacOS") { return .flutter }
        let bundled = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        if bundled.contains(where: { $0.hasPrefix("QtWebEngine") }) { return .qtWebEngine }
        return .webKit
    }
}
