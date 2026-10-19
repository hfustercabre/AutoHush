import AppKit
import PlayerCheckKit
import WebAppPlayers

// MARK: - How the app shows its page, as AutoHush tells it (`PageAccess`)

/// The switches for assistive tools: attributes set on an app to have it
/// show its interface to Accessibility, AutoHush's (`PageAccess`). Electron's
/// is documented (electronjs.org, Accessibility); VoiceOver's is the one
/// VoiceOver sets.
let manualAccessibility = PageAccess.electronSwitch
let enhancedUserInterface = PageAccess.voiceOverSwitch
func switchName(_ attribute: String, of interface: HiddenInterface? = hiddenInterface) -> String {
    if attribute == manualAccessibility { return "Electron's switch" }
    if case .chromiumWebApp(_, let browser)? = interface { return "\(browser)'s VoiceOver switch" }
    return "VoiceOver's switch"
}

/// How the app shows its page: as AutoHush tells it from its bundle
/// (`PageAccess.interface(ofAppAt:)`), and so what AutoHush would read.
let pageAccess = PageAccess(interface: PageAccess.interface(ofAppAt: appURL), switchAttribute: nil)

/// An interface the app keeps out of Accessibility until an assistive tool
/// asks for it, with the switches that ask, in the order they're tried,
/// AutoHush's (`PageAccess.switches(for:)`):
/// - Electron: its own, `AXManualAccessibility`;
/// - Chromium Embedded Framework (CEF): none of its own, as each app
///   decides: Electron's, else VoiceOver's `AXEnhancedUserInterface`, which
///   CEF's sample app listens to (some take only that one);
/// - Flutter: VoiceOver's only (Flutter's engine listens for it);
/// - a Chromium browser's web app (Chrome's, Brave's): VoiceOver's, set on
///   the browser (`switchTarget`), whose own process serves the page shown
///   in the web app's window; Chromium turns its complete mode on for all
///   its windows and tabs 2 s later (chrome_browser_application_mac.mm).
/// Electron's, CEF's and a browser's web app's interface is a web page, as a
/// Safari web app's; Flutter's is the window's own elements. Any other app's
/// web page (as in a Tauri app, Safari's WebKit, or Qt WebEngine) shows as
/// it is. Here with what the report names: Electron's version, the browser's name.
enum HiddenInterface {
    case electron(version: String), cef, flutter
    /// The web app's browser: its bundle ID and name.
    case chromiumWebApp(browserID: String, browser: String)
    var name: String {
        switch self {
        case .electron(let version): "Electron \(version)"
        case .cef: "Chromium (CEF)"
        case .flutter: "Flutter"
        case .chromiumWebApp(_, let browser): "\(browser) web app"
        }
    }
    var interface: PageAccess.Interface {
        switch self {
        case .electron: .electron
        case .cef: .cef
        case .flutter: .flutter
        case .chromiumWebApp(let browserID, _): .chromiumWebApp(browserID: browserID)
        }
    }
    var switches: [String] { PageAccess.switches(for: interface) }
    /// The app's, as AutoHush tells it.
    static func of(_ appURL: URL) -> HiddenInterface? {
        switch PageAccess.interface(ofAppAt: appURL) {
        case .webKit, .qtWebEngine:
            return nil
        case .electron:
            let framework = appURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            return .electron(version: Bundle(url: framework)?.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        case .cef:
            return .cef
        case .flutter:
            return .flutter
        case .chromiumWebApp(let browserID):
            return .chromiumWebApp(browserID: browserID, browser: BundleNames.name(of: browserID))
        }
    }
}
let hiddenInterface = HiddenInterface.of(appURL)
var isFlutter: Bool { if case .flutter? = hiddenInterface { true } else { false } }
var isElectron: Bool { if case .electron? = hiddenInterface { true } else { false } }
/// A Chromium browser's web app: its browser's name; nil for any other app.
var webAppBrowser: String? { if case .chromiumWebApp(_, let browser)? = hiddenInterface { browser } else { nil } }

/// The process a switch is set on, as AutoHush sets it
/// (`AccessibilityWebPage.switchTarget`): a Chromium browser's web app's
/// browser (its own process serves the page; set on the web app, nothing
/// shows), else the app itself. Its sound and keep-awake assertions are the
/// browser's too (`soundOwner`).
func switchTarget(_ pid: pid_t) -> pid_t { AccessibilityWebPage.switchTarget(pid, access: pageAccess) }

/// Whether its page is Safari's WebKit: a Safari web app's, or the app's
/// own (a Tauri app's), not Chromium inside Qt (Qt
/// WebEngine): as AutoHush tells it (`PageAccess.wordsCurrentOutOfSight`).
/// Out of sight, WebKit keeps its words current: a Tauri app and a Safari
/// web app, on another desktop, showed each change within
/// 0.5 s, also after minutes there.
let pageIsWebKit: Bool = {
    if isWebApp { return true }
    guard pageAccess.wordsCurrentOutOfSight, let binary = Bundle(url: appURL)?.executableURL else { return false }
    return MachOFile.linkedFrameworks(binary).contains("WebKit")
}()
