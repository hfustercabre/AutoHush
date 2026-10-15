import Foundation
import ScriptablePlayers
import WebAppPlayers

/// What Add an App… needs to know about an app before its check, read from
/// its bundle: whether it can be scripted (the check then needs Automation
/// for it), what it's built with (its page shows only with a switch on),
/// and whether it must be opened with a launch option.
package struct CheckedAppTraits: Equatable, Sendable {
    /// What shows the app's page, when a switch must be on for it.
    package enum Framework: Equatable, Sendable {
        case electron, chromium, flutter
        /// A Chromium browser's web app (a Chrome app), its browser's bundle ID.
        case browserWebApp(browserID: String)
    }

    package var scriptable: Bool
    package var framework: Framework?
    /// Electron's apps take presses while covered or on another desktop
    /// only when opened with `PlayerSetup.launchOption`.
    package var needsLaunchOption: Bool

    package init(scriptable: Bool, framework: Framework?, needsLaunchOption: Bool) {
        self.scriptable = scriptable
        self.framework = framework
        self.needsLaunchOption = needsLaunchOption
    }

    /// The browser that made the app at `url`, when it's a Chromium
    /// browser's web app (a Chrome app, a Brave app…): its bundle ID.
    package static func browser(ofAppAt url: URL) -> String? {
        if case .chromiumWebApp(let browserID) = PageAccess.interface(ofAppAt: url) { browserID } else { nil }
    }

    /// The app at `url`'s.
    package static func of(appAt url: URL) -> CheckedAppTraits {
        let framework: Framework? = switch PageAccess.interface(ofAppAt: url) {
        case .webKit: nil
        case .electron: .electron
        case .cef: .chromium
        case .flutter: .flutter
        case .chromiumWebApp(let browserID): .browserWebApp(browserID: browserID)
        }
        return CheckedAppTraits(scriptable: ScriptingDictionary.isInBundle(at: url), framework: framework,
                                needsLaunchOption: framework == .electron)
    }
}

extension PlayerSetup {
    /// The option an Electron app is opened with so its page takes presses
    /// while its window is covered or on another desktop.
    package static let launchOption = "--disable-backgrounding-occluded-windows"
}

extension CheckedPlayers {
    /// Keeps what a check found: the setup of the ways that worked, and its
    /// page's Play/Pause as a web app's is kept. Nothing when none worked.
    package func keep(_ result: CheckResult, recipes: any PlayPauseRecipeStore = DefaultsRecipeStore()) {
        guard let setup = result.setup else { return }
        if let button = result.pageButton { recipes.save(button, for: setup.bundleID) }
        store.save(setup)
    }
}
