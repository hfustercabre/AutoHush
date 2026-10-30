import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import Foundation

// What the warning before the check (W6) and the check's panel say.
extension AddAppText {
    // MARK: - The warning before the check (W6), and the panel

    /// As a tile's label (the warning) and the panel's step.
    static func stateLabel(_ state: CheckResult.WindowState) -> String {
        switch state {
        case .visible: String(localized: "In view", comment: "The window states a check moves the app's window through (the warning before it, its panel): the window in view")
        case .covered: String(localized: "Covered", comment: "The window states a check moves the app's window through: another window over it")
        case .otherDesktop: String(localized: "On another desktop", comment: "The window states a check moves the app's window through")
        case .otherDesktopCovered: String(localized: "Covered on another desktop", comment: "The window states a check moves the app's window through: on another desktop, another window over it")
        case .fullScreen: String(localized: "Full screen", comment: "The window states a check moves the app's window through")
        case .minimized: String(localized: "Minimized", comment: "The window states a check moves the app's window through")
        case .hidden: String(localized: "Hidden", comment: "The window states a check moves the app's window through: the app hidden")
        case .windowsClosed: String(localized: "Windows closed", comment: "The check's panel, as its window state: the app has no window open (a menu bar player playing on), so nothing is moved")
        }
    }

    static func warningTitle(_ app: String) -> String {
        String(localized: "Check \(app)", comment: "Title of the window shown before a check starts (Add an App); %@ is the app")
    }

    static func warningDescription(_ app: String) -> String {
        String(localized: "AutoHush takes over your Mac to pause and play \(app) every way it can.",
               comment: "The window shown before a check starts, at its top beside the app's icon (how long it takes is in its foot: “About 3 minutes”); %@ is the app")
    }

    static func statesHeading(_ app: String) -> String {
        String(localized: "\(app)’s Window Goes Through 7 States", comment: "The window shown before a check starts: heading over the window states; %@ is the app")
    }

    static func statesNote(_ app: String) -> String {
        String(localized: "In each, AutoHush pauses and plays \(app) every way it can, the Now Playing panel too (it opens for a moment).",
               comment: "The window shown before a check starts, under the window states; %@ is the app")
    }

    static var movingHeading: String {
        String(localized: "While It Moves Them", comment: "The window shown before a check starts: heading over what happens while the check moves windows")
    }

    static var blockedTitle: String {
        String(localized: "Mouse and keyboard are blocked", comment: "The window shown before a check starts: what happens while it moves windows")
    }

    static var blockedDetail: String {
        String(localized: "The screen dims except the progress panel. Escape or Stop ends the check; the mouse and keyboard work again whenever AutoHush asks you something.",
               comment: "The window shown before a check starts, under “Mouse and keyboard are blocked”")
    }

    static var aboutThreeMinutes: String {
        String(localized: "About 3 minutes", comment: "The window shown before a check starts: how long the check takes")
    }

    static func heardMeanwhile(_ app: String) -> String {
        String(localized: "\(app) heard meanwhile", comment: "The window shown before a check starts: nothing is muted during the check (no Audio Recording, or AntiDot mode, and the Mac's output has no mute control); %@ is the app")
    }

    static var macMutedMeanwhile: String {
        String(localized: "Your Mac muted meanwhile", comment: "The window shown before a check starts: the whole Mac's sound is muted during the check (the app itself can't be: no Audio Recording, or AntiDot mode)")
    }

    static func mutedMeanwhile(_ app: String) -> String {
        String(localized: "\(app) muted meanwhile", comment: "The window shown before a check starts: the app is muted during the check; %@ is the app")
    }

    static var allPutBack: String {
        String(localized: "All put back", comment: "The window shown before a check starts: windows, desktops and sound are put back at the end")
    }

    static var startCheck: String {
        String(localized: "Start the Check", comment: "The window shown before a check starts: its main button")
    }

    static var stop: String {
        String(localized: "Stop", comment: "The check's panel (Add an App): stops the check, which puts everything back first")
    }

    static func checking(_ app: String) -> String {
        String(localized: "Checking \(app)…", comment: "The check's panel (Add an App), at its top; %@ is the app")
    }

    static var waitingForYou: String {
        String(localized: "Waiting for you", comment: "The check's panel (Add an App), while the check asks the user to do something (shown under it)")
    }

    static var stopping: String {
        String(localized: "Stopping: putting everything back…", comment: "The check's panel (Add an App), once Stop was pressed")
    }

    static func stage(_ stage: CheckProgress.Stage) -> String {
        switch stage {
        case .reading: String(localized: "Reading its dictionary, menus and sound…", comment: "The check's panel: what the check does now")
        case .permissions: String(localized: "Checking permissions…", comment: "The check's panel: what the check does now")
        case .playing: String(localized: "Checking that it plays…", comment: "The check's panel: what the check does now")
        case .movingWindow: String(localized: "Moving its window to where the test starts…", comment: "The check's panel: what the check does now")
        case .readingPage: String(localized: "Reading its page…", comment: "The check's panel: what the check does now")
        case .testing: String(localized: "Testing its window states…", comment: "The check's panel: what the check does now")
        case .finishing: String(localized: "Writing down what worked…", comment: "The check's panel: what the check does now")
        }
    }

    static func activity(_ activity: CheckProgress.Activity) -> String {
        switch activity {
        case .moving: String(localized: "Moving its window there…", comment: "The check's panel, under the window state it tests")
        case .pausing(let way): String(localized: "By \(wayInSentence(way)): pausing it…", comment: "The check's panel, under the window state it tests; %@ is a way, e.g. “its playback menu”")
        case .playingAgain(let way): String(localized: "By \(wayInSentence(way)): playing it again…", comment: "The check's panel, under the window state it tests; %@ is a way, e.g. “its playback menu”")
        case .untested: String(localized: "This state can’t be tested here", comment: "The check's panel, under a window state it can't test (no other desktop, say)")
        }
    }

    private static func wayInSentence(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: WayText.title(.script)
        case .menu: String(localized: "its playback menu", comment: "The check's panel, in “By %@: pausing it”")
        case .page: String(localized: "its page’s button", comment: "The check's panel, in “By %@: pausing it”")
        case .panel: String(localized: "the Now Playing panel", comment: "The check's panel, in “By %@: pausing it”")
        }
    }

    static func stepOf(_ index: Int, _ count: Int) -> String {
        String(localized: "\(index) of \(count)", comment: "The check's panel: which window state it tests, e.g. “3 of 7”")
    }

    static func request(_ request: CheckProgress.Request, app: String) -> String {
        switch request {
        case .play: String(localized: "Start something playing in \(app)", comment: "The check's panel, while the check waits for the app to play; %@ is the app")
        case .pause: String(localized: "Pause \(app) with its own Pause", comment: "The check's panel, while the check waits for the user to pause the app (it learns its page's button from that); %@ is the app")
        case .allowAccessibility: String(localized: "Allow Accessibility for AutoHush in System Settings", comment: "The check's panel, while the check waits for the permission")
        }
    }

    static var blockedNote: String {
        String(localized: "Clicks, scrolling and keys are blocked until it ends. Escape or Stop ends the check.",
               comment: "The check's panel, while the check blocks the mouse and keyboard")
    }
}
