import ScriptablePlayers

/// The verdict's first part: which kind of player the app could be, said in
/// the words of AutoHush's kinds of player, never by naming one. With
/// --developer (the Player Check app passes it, Add an App… doesn't) it also
/// says how a built-in player of that kind would be made, with AutoHush's
/// own types: those lines are for whoever adds a player to the code.
package enum PlayerKindVerdict {
    /// What the check found that the verdict goes by.
    package struct Facts: Sendable {
        var bundleID: String
        package var isSafariWebApp = false
        /// A Chromium browser's web app: the browser, as its bundle names it.
        package var webAppBrowser: String?
        package var scripting: ScriptingDictionary?
        package var stateNotification: StateNotification = .notFollowed
        /// The first trial of each way, when the test tried it.
        package var scriptResult: TrialResult?
        /// Its state by script said it didn't play while it was heard.
        package var scriptStateWrong = false
        package var menuResult: TrialResult?
        /// Its playback menu's title, when it has one.
        package var menuTitle: String?
        package var isRunning = true
        package var pageHasPlayPause = false

        package init(bundleID: String) { self.bundleID = bundleID }
    }

    /// What the test saw of the app's state notification.
    package enum StateNotification: Equatable, Sendable {
        /// Not followed: no test ran.
        case notFollowed
        /// This one announced each pause and play.
        case announced(String)
        /// These came with a “Player State”, but didn't announce both.
        case seen([String])
        /// None came under the usual names.
        case noneSeen
    }

    /// The verdict's lines; `developer` adds those for whoever adds a player
    /// to the code.
    package static func lines(_ facts: Facts, developer: Bool) -> [String] {
        var lines: [String] = []
        func say(_ line: String) { lines.append(line) }
        func sayForDevelopers(_ line: String) { if developer { lines.append(line) } }
        let ownKind = "a player type of its own (an <App>Support module), as ScriptablePlayers doesn't fit it"

        if facts.isSafariWebApp {
            say("  A Safari web app: AutoHush learns its page's Play/Pause button.")
            sayForDevelopers("  WebAppPlayers controls it: test the site live, then add it to SupportedPlayers.testedWebApps.")
        } else if let browser = facts.webAppBrowser {
            // Any Chromium browser's (Chrome, Brave, Edge…): what Add an App does with it comes below.
            say("  A Chromium web app. Its sound is \(browser)'s, shared with its tabs:")
            say("  another page of \(browser) playing (a tab, a call, another web app) shows as one more “Playing audio” assertion.")
        } else if let scripting = facts.scripting, scripting.fitsScriptablePlayer, let suite = scripting.suite {
            if facts.scriptStateWrong {
                say("  A scriptable player: its own pause and play, but its state by script is wrong (not playing while it played), so AutoHush tells it by its other signs.")
                sayForDevelopers("  As a built-in player: \(ownKind), its state from its menu or sound.")
            } else {
                say("  A scriptable player, as the supported scriptable players are: its own pause and play, and its state.")
                sayForDevelopers("  As a built-in player: a ScriptablePlayerProfile with suite fourCharCode(\"\(suite)\").")
            }
            say("  " + (scripting.hasVolume ? "It has a volume, so it can fade." : "No volume: it pauses without fading."))
            if scripting.hasVolume {
                sayForDevelopers("  Measure its volume's curve: swift run measure-volume-curve \(facts.bundleID).")
            }
            switch facts.stateNotification {
            case .announced(let name):
                sayForDevelopers("  State notification: \(name), which announced each pause and play (the profile's stateNotification).")
            case .seen(let names):
                sayForDevelopers("  State notification: \(names.joined(separator: ", ")), but it didn't announce both a pause and a play in the test.")
            case .notFollowed:
                sayForDevelopers("  Its state notification (with “Player State”) isn't known yet: check it again while it plays.")
            case .noneSeen:
                sayForDevelopers("  No state notification with “Player State” under the usual names: unless it has one under another,")
                sayForDevelopers("  its state must be read once a second (PolledStateObserver), so the profile needs that option.")
            }
            switch facts.scriptResult {
            case .didNotPause?: say("  But its scripted pause didn't take: check it by hand before building on it.")
            case .pausedOnly?: say("  But its scripted play didn't bring it back: check it by hand before building on it.")
            default: break
            }
        } else if let title = facts.menuTitle {
            switch facts.menuResult {
            case .worked?:
                say("  A menu player, as the supported menu players are: its menu “\(title)”.")
                sayForDevelopers("  As a built-in player: a MenuPlayerProfile with menu “\(title)”, its words for Play and Pause")
                sayForDevelopers("  in every language read from the app, as each supported menu player's are.")
            case .pausedOnly?:
                say("  Its menu paused it, but pressing it again didn't play it: check it by hand before building on it.")
            case .didNotPause?:
                say("  Its menu has Play/Pause, but pressing it didn't take: not controllable that way.")
            case nil:
                say("  Probably a menu player, as the supported menu players are (menu “\(title)”): confirm by testing it while it plays.")
            }
            if let scripting = facts.scripting, hasPlayCommands(scripting) {
                say("  It's scriptable too, but not as the supported scriptable players are (see above).")
                sayForDevelopers("  As a built-in player by AppleScript: \(ownKind).")
            }
        } else if let scripting = facts.scripting, hasPlayCommands(scripting) {
            say("  Scriptable" + (scripting.playsDocuments ? " through its documents (its play and pause act on one)" : "")
                + ", but not as the supported scriptable players are: in a way of its own.")
            sayForDevelopers("  As a built-in player: \(ownKind).")
        } else if !facts.isRunning {
            say("  No usable scripting; open it and run again to look for a playback menu and a page.")
        } else if facts.pageHasPlayPause {
            say("  Neither scriptable nor with a playback menu.")
        } else {
            say("  Neither scriptable nor with a playback menu: AutoHush can't control it. If it has a website, try that as a Safari web app.")
        }
        return lines
    }

    /// Whether its dictionary has a play, a pause or a playpause command.
    static func hasPlayCommands(_ scripting: ScriptingDictionary) -> Bool {
        scripting.commands.values.contains { ["play", "pause", "playpause"].contains($0.lowercased()) }
    }
}
