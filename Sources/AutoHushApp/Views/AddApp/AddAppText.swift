import Foundation
import CheckedPlayers

/// What the Add an App window (W2), the warning before its check (W6) and
/// the check's panel say. `app` is the chosen app's name.
enum AddAppText {
    // MARK: - The window

    static var description: String {
        String(localized: "AutoHush checks how it can pause and play an app it doesn’t support yet, so that app can be your player.",
               comment: "Add an App window, at its top beside AutoHush's icon")
    }

    static var stepsHeading: String {
        String(localized: "How the Check Goes", comment: "Add an App window: the heading over its numbered steps")
    }

    static var cancel: String {
        String(localized: "Cancel", comment: "Add a Web App and Add an App windows: stops adding and closes the window; and the alert that asks to reopen the media player")
    }

    // MARK: Step 1: the app

    static var chooseTitle: String {
        String(localized: "Choose the app", comment: "Add an App window: the first step's title")
    }

    static var chooseNote: String {
        String(localized: "One that plays music, podcasts or videos. If it isn’t open, AutoHush opens it in the background.",
               comment: "Add an App window, under the step “Choose the app”")
    }

    static func chosen(_ app: String, traits: CheckedAppTraits?, browser: String? = nil) -> String {
        switch traits?.framework {
        case .electron?: String(localized: "\(app), built with Electron", comment: "Add an App window, under the step “Choose the app” once done; %@ is the app")
        case .chromium?: String(localized: "\(app), built with Chromium", comment: "Add an App window, under the step “Choose the app” once done; %@ is the app")
        case .flutter?: String(localized: "\(app), built with Flutter", comment: "Add an App window, under the step “Choose the app” once done; %@ is the app")
        case .browserWebApp?:
            browser.map { browser in String(localized: "\(app), a web app of \(browser)", comment: "Add an App window, under the step “Choose the app” once done: a web app made by Chrome or another Chromium browser; the first %@ is the app, the second the browser, e.g. Brave Browser") }
                ?? String(localized: "\(app), a browser’s web app", comment: "Add an App window, under the step “Choose the app” once done: a web app of Chrome or another Chromium browser; %@ is the app")
        case nil: app
        }
    }

    static func opening(_ app: String) -> String {
        String(localized: "Opening \(app)…", comment: "Add an App window, under the step “Choose the app” while the chosen app opens in the background; %@ is the app")
    }

    static func couldNotOpen(_ app: String) -> String {
        String(localized: "\(app) couldn’t be opened.", comment: "Add an App window, warning under the step “Choose the app”; %@ is the app")
    }

    static var chooseApp: String {
        String(localized: "Choose an App…", comment: "Add an App window: button under the step “Choose the app” that opens the window listing the apps")
    }

    static var changeApp: String {
        String(localized: "Change…", comment: "Add an App window: button under the step “Choose the app” once done, which chooses another app")
    }

    static var chooserTitle: String {
        String(localized: "Choose an App", comment: "Title of the window that lists the apps Add an App can check")
    }

    static var chooserDescription: String {
        String(localized: "Choose the app that plays your music, podcasts or videos. Other App… finds one that isn’t listed.",
               comment: "The window that lists the apps Add an App can check, at its top; “Other App…” is its button")
    }

    static var otherApp: String {
        String(localized: "Other App…", comment: "Button in the window that lists the apps Add an App can check: picks an app in the Finder's open panel")
    }

    static var choose: String {
        String(localized: "Choose", comment: "The main button of the window that lists the apps Add an App can check")
    }

    static func otherAppProblem(_ problem: OtherAppProblem) -> String {
        switch problem {
        case .notAnApp:
            String(localized: "That isn’t an app AutoHush can check.", comment: "The window that lists the apps Add an App can check, after Other App… picked something else than an app")
        case .supported(let name):
            String(localized: "AutoHush supports \(name) already: choose it among the media players.",
                   comment: "The window that lists the apps Add an App can check, after Other App… picked a supported player; %@ is it")
        case .autoHush:
            String(localized: "That’s AutoHush itself.", comment: "The window that lists the apps Add an App can check, after Other App… picked AutoHush")
        }
    }

    /// Under a Chromium browser's web app in the list of apps.
    static func browserWebApp(_ browser: String) -> String {
        String(localized: "\(browser) web app", comment: "The window that lists the apps Add an App can check, under a web app made by Chrome or another Chromium browser (its icon carries the browser's): %@ is the browser, e.g. Google Chrome")
    }

    static var nowPlayingSection: String {
        String(localized: "In Now Playing", comment: "Add an App window: over the apps in macOS's Now Playing list, in the list of apps to choose")
    }

    static var otherAppsSection: String {
        String(localized: "Other apps that can play", comment: "Add an App window: over the other apps that can play, in the list of apps to choose")
    }

    static var playingLabel: String {
        String(localized: "Playing", comment: "At the top of the menu, under the media player: it's playing; and under an app that plays now in the Add an App window's list")
    }

    static var lookingForApps: String {
        String(localized: "Looking for apps that can play…", comment: "Add an App window, while it reads which apps can play")
    }

    static var noApps: String {
        String(localized: "No other app that can play was found.", comment: "Add an App window, instead of the list of apps when there's none to check")
    }

    static var continueButton: String {
        String(localized: "Continue", comment: "Button in the welcome window and the Add a Web App and Add an App windows: goes on with what's chosen or typed")
    }

    // MARK: Step 2: permissions

    static var allowTitle: String {
        String(localized: "Allow what the check needs", comment: "Add an App window: the step that asks for the permissions the check needs")
    }

    static var allowNote: String {
        String(localized: "Only what that app needs, all at once: Accessibility and Audio Recording, and Automation if it can be scripted.",
               comment: "Add an App window, under the step “Allow what the check needs” before the app is chosen")
    }

    static func notScriptable(_ app: String) -> String {
        String(localized: "\(app) can’t be scripted, so Automation isn’t asked for.",
               comment: "Add an App window, under the step “Allow what the check needs”; %@ is the app")
    }

    static var neededInCheck: String {
        String(localized: "The check needs every one of these allowed.",
               comment: "Add an App window, warning under the step “Allow what the check needs” when the check found one missing")
    }

    static var neededBadge: String {
        String(localized: "Needed", comment: "Add an App window: badge after a permission the check can't go without (Accessibility)")
    }

    static var optionalLabel: String {
        String(localized: "Optional", comment: "Add an App window: after a permission the check can go without, checking less")
    }

    static func accessibilityNeeded(_ app: String) -> String {
        String(localized: "Accessibility is needed: without it, the check can’t read \(app)’s menus or page, try the Now Playing panel or move its window.",
               comment: "Add an App window, warning under the permissions while Accessibility isn't allowed; %@ is the app")
    }

    /// What the check does without `permission`.
    static func without(_ permission: CheckPermission, app: String) -> String {
        switch permission {
        case .audioRecording:
            String(localized: "Without Audio Recording, \(app) isn’t muted during the check: you’ll hear it pause and play, and whether it plays is told by other signs.",
                   comment: "Add an App window, warning above Continue while Audio Recording isn't allowed; %@ is the app")
        case .automation:
            String(localized: "Without Automation, its AppleScript, the surest way to pause and play \(app), isn’t tried.",
                   comment: "Add an App window, warning above Continue while Automation for the app isn't allowed; %@ is the app")
        case .accessibility:
            accessibilityNeeded(app)
        }
    }

    static func goOnWithout(_ count: Int) -> String {
        count > 1
            ? String(localized: "Allow them now, or go on without them.", comment: "Add an App window, last in the warning above Continue while two permissions the check can go without aren't allowed")
            : String(localized: "Allow it now, or go on without it.", comment: "Add an App window, last in the warning above Continue while a permission the check can go without isn't allowed")
    }

    static var accessibilityTitle: String {
        String(localized: "Accessibility", comment: "Add an App window: the Accessibility permission (macOS's name for it)")
    }

    static func accessibilityUse(_ app: String) -> String {
        String(localized: "Reads \(app)’s menus and page, moves its window, and blocks the mouse and keyboard.",
               comment: "Add an App window, under “Accessibility”: what the check uses it for; %@ is the app")
    }

    static func audioUse(_ app: String) -> String {
        String(localized: "Hears whether \(app) plays, and mutes it.",
               comment: "Add an App window, under “Audio Recording”: what the check uses it for; %@ is the app")
    }

    static var automationUse: String {
        String(localized: "Pauses and plays it by AppleScript.",
               comment: "Add an App window, under “Control %@” (Automation): what the check uses it for")
    }

    static var allowButton: String {
        String(localized: "Allow…", comment: "Welcome window and Add an App window: button that asks for a permission (macOS's prompt, or System Settings)")
    }

    static var allowedLabel: String {
        String(localized: "Allowed", comment: "Diagnostics, the welcome window and the Add an App window: a permission that is granted")
    }

    static func allowed(automation: Bool) -> String {
        let names = [accessibilityTitle, PermissionText.audioTitle]
            + (automation ? [String(localized: "Automation", comment: "Add an App window, in the list of permissions allowed: macOS's Automation permission")] : [])
        return names.formatted(.list(type: .and))
    }

    // MARK: Step 3: reopening

    static func reopenTitle(_ app: String) -> String {
        String(localized: "Reopen \(app)", comment: "Add an App window: the step, and its button, that quits the app and opens it again with the option its page needs; the same button in the menu's card and in the alert that asks for it; %@ is the app")
    }

    /// Why an app opened without its option needs reopening: the Reopen
    /// step's warning, the alert's message, the card's button's help.
    static func reopenReason(_ app: String) -> String {
        String(localized: "\(app) was opened without an option it needs: without it, AutoHush can pause and play \(app) only while its window can be seen, not while it’s covered, on another desktop or in full screen.",
               comment: "Add an App's Reopen step (as a warning), the alert that asks to reopen the media player, and the help of the menu card's Reopen button; both %@ are the app")
    }

    static var reopenWhy: String {
        String(localized: "It was opened without the option its page needs to be pressed while it’s covered or on another desktop.",
               comment: "Add an App window, under the step “Reopen %@”")
    }

    static var reopenAsks: String {
        String(localized: "AutoHush asks before it quits and reopens it.", comment: "Add an App window, under the step “Reopen %@” before it's the one to do")
    }

    static var reopenStops: String {
        String(localized: "Reopening it stops whatever it plays.", comment: "Add an App window, under the step “Reopen %@” while it's the one to do")
    }

    static func reopening(_ app: String) -> String {
        String(localized: "Reopening \(app)…", comment: "Add an App window, under the step “Reopen %@” while it reopens; %@ is the app")
    }

    static var reopened: String {
        String(localized: "Reopened with its page’s option", comment: "Add an App window, under the step “Reopen %@” once done")
    }

    static var notReopened: String {
        String(localized: "Not reopened: its page may not take presses while it’s covered or on another desktop",
               comment: "Add an App window, under the step “Reopen %@” once skipped")
    }

    static func didNotQuit(_ app: String) -> String {
        String(localized: "\(app) didn’t quit (it may be asking something). Quit it yourself, then try again.",
               comment: "Add an App window, warning under the step “Reopen %@”; %@ is the app")
    }

    static var skip: String {
        String(localized: "Skip", comment: "Add an App window: button under the step “Reopen %@” that goes on without reopening the app")
    }

    // MARK: Step 4: playing

    static func playTitle(_ app: String?) -> String {
        guard let app else { return String(localized: "Play something in it", comment: "Add an App window: the step that waits for the app to play, before the app is chosen") }
        return String(localized: "Play something in \(app)", comment: "The first step while AutoHush learns a web app's controls, ticked once the user clicks “It’s Playing”; and the Add an App window's step that waits for the app to play; %@ is the web app or app")
    }

    static var playWaits: String {
        String(localized: "AutoHush waits up to 2 minutes for it to play.", comment: "Add an App window, under the step “Play something in %@” before it's the one to do")
    }

    static func playNow(_ app: String) -> String {
        String(localized: "Start something playing in \(app): AutoHush goes on as soon as it hears it.",
               comment: "Add an App window, under the step “Play something in %@” while it waits; %@ is the app")
    }

    static func timeLeft(_ remaining: TimeInterval) -> String {
        let time = Duration.seconds(max(0, Int(remaining.rounded(.up)))).formatted(.time(pattern: .minuteSecond))
        return String(localized: "\(time) left", comment: "Add an App window and the check's panel, on a tinted line: the time left to do what's asked; %@ is e.g. 1:45")
    }

    static func didNotPlay(_ app: String) -> String {
        String(localized: "\(app) didn’t play within 2 minutes.", comment: "Add an App window, under the step “Play something in %@” once the wait ended; %@ is the app")
    }

    static var tryAgain: String {
        String(localized: "Try Again", comment: "Button under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself: it tries again; and under Add an App's “Play something in %@” once the app didn't play in time")
    }

    static var playingNote: String {
        String(localized: "It plays", comment: "Add an App window, under the step “Play something in %@” once done")
    }

    // MARK: Step 5: the check

    static var checkTitle: String {
        String(localized: "AutoHush tries every way to pause and play it", comment: "Add an App window: the step of the check itself")
    }

    static func checkNote(_ app: String?) -> String {
        guard let app else {
            return String(localized: "About 3 minutes, with the app muted and its window moving. You’re told more before it starts.",
                          comment: "Add an App window, under the step “AutoHush tries every way to pause and play it”, before the app is chosen")
        }
        return String(localized: "About 3 minutes, with \(app) muted and its window moving. You’re told more before it starts.",
                      comment: "Add an App window, under the step “AutoHush tries every way to pause and play it”; %@ is the app")
    }

    static var switchNote: String {
        String(localized: "Its accessibility switch is turned on to read its page, and stays on while it’s your player.",
               comment: "Add an App window, under the step “AutoHush tries every way to pause and play it”, for an app built with Electron, Chromium or Flutter")
    }

    static var continueToCheck: String {
        String(localized: "Continue…", comment: "Add an App window: button under the step “AutoHush tries every way to pause and play it”, which shows what the check does before it starts")
    }

    static var stopHint: String {
        String(localized: "Escape or the panel’s Stop ends the check.", comment: "Add an App window, under the check's step while it runs: the panel shows the check's progress at the bottom right of the screen")
    }

    static var stoppedNote: String {
        String(localized: "Stopped. Everything was put back as it was.", comment: "Add an App window, under the check's step once it was stopped")
    }

    static var failedNote: String {
        String(localized: "The check couldn’t finish.", comment: "Add an App window, under the check's step when it ended without a result")
    }

    static var putBackNote: String {
        String(localized: "Everything was put back as it was.", comment: "Add an App window, under the check's step once done")
    }

    static var checkAgain: String {
        String(localized: "Check Again", comment: "Add an App window: button that runs the check again, from the app playing")
    }

    // MARK: Step 6: what worked

    static var useTitle: String {
        String(localized: "See what worked, and use it", comment: "Add an App window: the last step's title")
    }

    static var useWaits: String {
        String(localized: "Windows, desktops and sound are put back as they were first, also if you stop the check.",
               comment: "Add an App window, under the step “See what worked, and use it” before it's the one to do")
    }

    static var useOrder: String {
        String(localized: "AutoHush uses the first way that works, and the next if it doesn’t.",
               comment: "Add an App window, under the step “See what worked, and use it”, over the ways the check found")
    }

    static func nothingWorked(_ app: String) -> String {
        String(localized: "No way to pause and play \(app) worked.", comment: "Add an App window, under the last step when the check found no way; %@ is the app")
    }

    static func muteInstead(_ app: String) -> String {
        String(localized: "AutoHush can mute \(app) instead while other apps play: it keeps playing, silent, and is heard again when they stop. Pausing it and playing it again yourself unmutes it.",
               comment: "Add an App window, under the last step when no way could pause the app; %@ is the app")
    }

    static var muteItInstead: String {
        String(localized: "Mute It Instead", comment: "Add an App window: button under the last step when no way could pause the app: AutoHush will mute it while other apps play")
    }

    static var muteNeedsAudio: String {
        String(localized: "Muting needs Audio Recording.", comment: "Add an App window, warning above “Allow…” in the last step while Audio Recording isn't allowed")
    }

    static func use(_ app: String) -> String {
        String(localized: "Use \(app)", comment: "Add an App window: button that makes the checked app the player; %@ is the app")
    }

    static func wayTitle(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: String(localized: "AppleScript", comment: "Add an App window, a way to pause and play the app: its AppleScript commands")
        case .menu: String(localized: "Its playback menu", comment: "Add an App window, a way to pause and play the app: the Play/Pause item of its menu bar's playback menu")
        case .page: String(localized: "Its page’s Play/Pause", comment: "Add an App window, a way to pause and play the app: the Play/Pause button of the page it shows")
        case .panel: String(localized: "The menu bar’s Now Playing panel", comment: "Add an App window, a way to pause and play the app: its row in macOS's Now Playing panel")
        }
    }

    static func wayNote(_ way: CheckResult.WayResult, app: String) -> String {
        switch way.mark {
        case .works:
            way.kind == .panel
                ? String(localized: "In every window state. Used only if nothing else works: it opens on screen for a moment.",
                         comment: "Add an App window, under “The menu bar’s Now Playing panel” when it worked")
                : String(localized: "In every window state", comment: "Add an App window, under a way that paused and played the app wherever its window was")
        case .some:
            String(localized: "Not with its window \(way.failedStates.map(stateInSentence).formatted(.list(type: .or)))",
                   comment: "Add an App window, under a way that worked in some window states; %@ lists the others, e.g. “covered or on another desktop”")
        case .none:
            String(localized: "It didn’t pause and play \(app)", comment: "Add an App window, under a way that was tried and didn't work; %@ is the app")
        case .notThere:
            switch way.kind {
            case .script: String(localized: "\(app) can’t be scripted", comment: "Add an App window, under “AppleScript”; %@ is the app")
            case .menu: String(localized: "\(app) has no playback menu", comment: "Add an App window, under “Its playback menu”; %@ is the app")
            case .page: String(localized: "It shows no page with a Play/Pause", comment: "Add an App window, under “Its page’s Play/Pause” when the app shows no page, or none with a Play/Pause button")
            case .panel: String(localized: "\(app) doesn’t show in Now Playing", comment: "Add an App window, under “The menu bar’s Now Playing panel”; %@ is the app")
            }
        case .notTried:
            String(localized: "Not tried", comment: "Add an App window, under a way the check found but didn't try")
        case .notChecked:
            String(localized: "Not checked", comment: "Add an App window, under a way the check couldn't look for")
        }
    }

    /// After “Not with its window …”.
    static func stateInSentence(_ state: CheckResult.WindowState) -> String {
        switch state {
        case .visible: String(localized: "in view", comment: "Add an App window, in “Not with its window %@”: a window state")
        case .covered: String(localized: "covered", comment: "Add an App window, in “Not with its window %@”: a window state")
        case .otherDesktop: String(localized: "on another desktop", comment: "Add an App window, in “Not with its window %@”: a window state")
        case .otherDesktopCovered: String(localized: "covered on another desktop", comment: "Add an App window, in “Not with its window %@”: a window state")
        case .fullScreen: String(localized: "in full screen", comment: "Add an App window, in “Not with its window %@”: a window state")
        case .minimized: String(localized: "minimized", comment: "Add an App window, in “Not with its window %@”: a window state")
        case .hidden: String(localized: "hidden", comment: "Add an App window, in “Not with its window %@”: a window state (the app hidden)")
        }
    }

    // MARK: - The warning before the check (W6), and the panel

    /// As a tile's label (the warning) and the panel's step.
    static func stateLabel(_ state: CheckResult.WindowState) -> String {
        switch state {
        case .visible: String(localized: "Seen", comment: "The window states a check moves the app's window through (the warning before it, its panel): the window in view")
        case .covered: String(localized: "Covered", comment: "The window states a check moves the app's window through: another window over it")
        case .otherDesktop: String(localized: "On another desktop", comment: "The window states a check moves the app's window through")
        case .otherDesktopCovered: String(localized: "Covered there", comment: "The window states a check moves the app's window through: on another desktop, another window over it")
        case .fullScreen: String(localized: "Full screen", comment: "The window states a check moves the app's window through")
        case .minimized: String(localized: "Minimized", comment: "The window states a check moves the app's window through")
        case .hidden: String(localized: "Hidden", comment: "The window states a check moves the app's window through: the app hidden")
        }
    }

    static func warningTitle(_ app: String) -> String {
        String(localized: "Check \(app)", comment: "Title of the window shown before a check starts (Add an App); %@ is the app")
    }

    static func warningDescription(_ app: String) -> String {
        String(localized: "For about 3 minutes, AutoHush takes over your Mac to pause and play \(app) every way it can.",
               comment: "The window shown before a check starts, at its top beside the app's icon; %@ is the app")
    }

    static func statesHeading(_ app: String) -> String {
        String(localized: "\(app)’s Window Goes Through 7 States", comment: "The window shown before a check starts: heading over the window states; %@ is the app")
    }

    static func statesNote(_ app: String) -> String {
        String(localized: "In each, AutoHush pauses and plays \(app) every way it can, the menu bar’s Now Playing panel too (it opens for a moment).",
               comment: "The window shown before a check starts, under the window states; %@ is the app")
    }

    static var movingHeading: String {
        String(localized: "While It Moves Them", comment: "The window shown before a check starts: heading over what happens while the check moves windows")
    }

    static var blockedTitle: String {
        String(localized: "Mouse and keyboard are blocked", comment: "The window shown before a check starts: what happens while it moves windows")
    }

    static var blockedDetail: String {
        String(localized: "The screen dims, except the panel with the progress. The pointer still moves, except while AutoHush drags a window. Escape or the panel’s Stop ends the check; when AutoHush asks you something, they work again.",
               comment: "The window shown before a check starts, under “Mouse and keyboard are blocked”")
    }

    static var aboutThreeMinutes: String {
        String(localized: "About 3 minutes", comment: "The window shown before a check starts: how long the check takes")
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
        String(localized: "Checking \(app)", comment: "The check's panel (Add an App), at its top; %@ is the app")
    }

    static var waitingForYou: String {
        String(localized: "Waiting for you", comment: "The check's panel (Add an App), while the check asks the user to do something (shown under it)")
    }

    static var stopping: String {
        String(localized: "Stopping: putting everything back…", comment: "The check's panel (Add an App), once Stop was pressed")
    }

    static func stage(_ stage: CheckProgress.Stage) -> String {
        switch stage {
        case .reading: String(localized: "Reading its dictionary, menus and sound", comment: "The check's panel: what the check does now")
        case .permissions: String(localized: "Checking permissions", comment: "The check's panel: what the check does now")
        case .playing: String(localized: "Checking that it plays", comment: "The check's panel: what the check does now")
        case .movingWindow: String(localized: "Moving its window to where the test starts", comment: "The check's panel: what the check does now")
        case .readingPage: String(localized: "Reading its page", comment: "The check's panel: what the check does now")
        case .testing: String(localized: "Testing its window states", comment: "The check's panel: what the check does now")
        case .finishing: String(localized: "Writing down what worked", comment: "The check's panel: what the check does now")
        }
    }

    static func activity(_ activity: CheckProgress.Activity) -> String {
        switch activity {
        case .moving: String(localized: "Moving its window there", comment: "The check's panel, under the window state it tests")
        case .pausing(let way): String(localized: "By \(wayInSentence(way)): pausing it", comment: "The check's panel, under the window state it tests; %@ is a way, e.g. “its playback menu”")
        case .playingAgain(let way): String(localized: "By \(wayInSentence(way)): playing it again", comment: "The check's panel, under the window state it tests; %@ is a way, e.g. “its playback menu”")
        case .untested: String(localized: "This state can’t be tested here", comment: "The check's panel, under a window state it can't test (no other desktop, say)")
        }
    }

    private static func wayInSentence(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: String(localized: "AppleScript", comment: "Add an App window, a way to pause and play the app: its AppleScript commands")
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
