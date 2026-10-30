import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import Foundation

// What the Add an App window says from its step 4 on: playing, the check
// and what worked.
extension AddAppText {
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

    /// The countdown while AutoHush waits for the app to play (the window,
    /// the panel).
    static func timeToPlay(_ remaining: TimeInterval) -> String {
        String(localized: "You have \(remaining.countdownText) to start it playing.",
               comment: "Add an App window and the check's panel, on a tinted line counting down while AutoHush waits for the app to play; %@ is the time left, e.g. 1:45")
    }

    /// The panel's countdown for what the check asks.
    static func timeLeft(_ remaining: TimeInterval, for request: CheckProgress.Request) -> String {
        switch request {
        case .play: timeToPlay(remaining)
        case .pause:
            String(localized: "You have \(remaining.countdownText) to pause it.",
                   comment: "The check's panel, on a tinted line counting down while the check waits for the user to pause the app; %@ is the time left, e.g. 1:45")
        case .allowAccessibility:
            String(localized: "You have \(remaining.countdownText) to allow it.",
                   comment: "The check's panel, on a tinted line counting down while the check waits for Accessibility to be allowed; %@ is the time left, e.g. 1:45")
        }
    }

    /// After Check Again with the app's windows closed, while none is open (B2, 2026-10-29).
    static func waitsForWindow(_ app: String) -> String {
        String(localized: "AutoHush also waits for a window of \(app) to open.",
               comment: "Add an App window, under the step “Play something in %@” after “Check Again” following a check that found the app's windows closed, while none is open; %@ is the app")
    }

    /// The wait ended with no window open (B2, 2026-10-29).
    static func noWindowOpened(_ app: String) -> String {
        String(localized: "No window of \(app) opened within 2 minutes.",
               comment: "Add an App window, under the step “Play something in %@” once the wait after “Check Again” ended with none of the app's windows open; %@ is the app")
    }

    static func didNotPlay(_ app: String) -> String {
        String(localized: "\(app) didn’t play within 2 minutes.", comment: "Add an App window, under the step “Play something in %@” once the wait ended; %@ is the app")
    }

    /// As the learning step's (`StepButton.tryAgain`).
    static var tryAgain: String { StepButton.tryAgain.title }

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

    /// The check step's note when the Mac's sound is muted instead of the
    /// app's (no Audio Recording, or AntiDot mode).
    static func checkNoteMacMuted(_ app: String) -> String {
        String(localized: "About 3 minutes, with the Mac’s sound muted and \(app)’s window moving. You’re told more before it starts.",
               comment: "Add an App window, under the step “AutoHush tries every way to pause and play it” when the whole Mac's sound is muted during the check (the app itself can't be); %@ is the app")
    }

    /// The check step's note when nothing is muted (no Audio Recording, or
    /// AntiDot mode, and an output with no mute control).
    static func checkNoteHeard(_ app: String) -> String {
        String(localized: "About 3 minutes; you’ll hear \(app) pause and play as its window moves.",
               comment: "Add an App window, under the step “AutoHush tries every way to pause and play it” when the app won't be muted during the check; %@ is the app")
    }

    static var switchNote: String {
        String(localized: "AutoHush turns on its page’s accessibility, and leaves it on while it’s your player.",
               comment: "Add an App window, under the step “AutoHush tries every way to pause and play it”, for an app built with Electron, Chromium or Flutter")
    }

    static var continueToCheck: String {
        String(localized: "Continue…", comment: "Add an App window: button under the step “AutoHush tries every way to pause and play it”, which shows what the check does before it starts")
    }

    static var stopHint: String {
        String(localized: "Stop here, Stop in the panel or Escape ends the check.", comment: "Add an App window, under the check's step while it runs (a Stop button follows; the panel is the check's, at the bottom right of the screen)")
    }

    static var stoppedNote: String {
        String(localized: "Stopped. Everything was put back as it was.", comment: "Add an App window, under the check's step once it was stopped")
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

    static func chooseWay(_ app: String) -> String {
        String(localized: "Choose how AutoHush pauses and plays \(app):",
               comment: "Add an App window, under the step “See what worked, and use it”, over the ways that worked, one to choose; %@ is the app")
    }

    static var panelSoundOnly: String {
        String(localized: "Its row shows no state: only its sound tells, so not in AntiDot mode",
               comment: "Add an App window, under “The menu bar’s Now Playing panel” when the app's row there doesn't show whether it plays (AutoHush then judges it by its sound, which AntiDot mode doesn't hear)")
    }

    static var recommendedBadge: String {
        String(localized: "Recommended", comment: "Add an App window: a badge beside the way AutoHush recommends to pause and play the app, among those that worked")
    }

    static func nothingWorked(_ app: String) -> String {
        String(localized: "No way to pause and play \(app) worked.", comment: "Add an App window, under the last step when the check found no way; %@ is the app")
    }

    /// The only way that worked needs the app's sound (its Now Playing row
    /// shows no state), which AntiDot mode doesn't hear.
    static func nothingInAntiDot(_ app: String) -> String {
        String(localized: "No way to pause and play \(app) works in AntiDot mode.",
               comment: "Add an App window, under the last step while AntiDot mode is on, when the only way that worked needs the app's sound, which AntiDot mode doesn't hear; %@ is the app")
    }

    static func muteInstead(_ app: String) -> String {
        String(localized: "AutoHush can mute \(app) instead while other apps play, and unmute it when they stop.",
               comment: "Add an App window, under the last step when no way could pause the app; %@ is the app")
    }

    /// What VoiceOver says of a way that worked, in every window state or in
    /// some, whose mark it doesn't read (the 1.2.3 review's workflow note, P2,
    /// 2026-10-28; in some, the 1.2.4 review's, 2026-10-29).
    static var wayWorks: String {
        String(localized: "Works", comment: "Add an App window, VoiceOver only: the value of a way the check found working, in every window state or in some (its mark isn't read)")
    }

    /// Beside the steps after Check Again, until the new check starts (A1, 2026-10-29).
    static var backToResult: String {
        String(localized: "Back to Result", comment: "Add an App window: button in the steps after “Check Again”, until the new check starts: shows the last check's result again, with its Use button")
    }

    /// Above Check Again when a way didn't work, or wasn't checked, with the
    /// app's windows closed (B, 2026-10-29).
    static func openWindowFirst(_ app: String) -> String {
        String(localized: "To check again, open a window of \(app) first.",
               comment: "Add an App window, above “Check Again” in the last step, after a check that found the app's windows closed and a way that didn't work or couldn't be checked without a window; %@ is the app")
    }

    static var muteItInstead: String {
        String(localized: "Mute It Instead", comment: "Add an App window: button under the last step when no way could pause the app: AutoHush will mute it while other apps play")
    }

    static var turnOffAntiDot: String {
        String(localized: "Turn Off AntiDot Mode",
               comment: "Add an App window, button under the warning in the last step when no way that worked can be used in AntiDot mode: turns AntiDot mode off (Settings → Behavior), so muting or a way only the app's sound tells can be used")
    }

    static var muteNeedsAudio: String {
        String(localized: "Muting needs Audio Recording.", comment: "Add an App window, warning above “Allow…” in the last step while Audio Recording isn't allowed")
    }

    static func use(_ app: String) -> String {
        String(localized: "Use \(app)", comment: "Add an App window: button that makes the checked app the player; %@ is the app")
    }

    /// `windowsClosed`: the check found them closed, and tried it once (2026-10-27).
    static func wayNote(_ way: CheckResult.WayResult, app: String, windowsClosed: Bool = false) -> String {
        switch way.mark {
        case .works where windowsClosed:
            way.kind == .panel
                ? String(localized: "With its windows closed, but it opens on screen for a moment",
                         comment: "Add an App window, under “The menu bar’s Now Playing panel” when it worked in a check that found the app's windows closed (tried once, nothing moved)")
                : String(localized: "With its windows closed",
                         comment: "Add an App window, under a way that paused and played the app in a check that found its windows closed (tried once, nothing moved)")
        case .works:
            way.kind == .panel
                ? String(localized: "In every window state, but it opens on screen for a moment",
                         comment: "Add an App window, under “The menu bar’s Now Playing panel” when it worked: why it comes after the other ways")
                : String(localized: "In every window state", comment: "Add an App window, under a way that paused and played the app wherever its window was")
        case .some:
            String(localized: "Not with its window \(way.failedStates.map(stateInSentence).formatted(.list(type: .or)))",
                   comment: "Add an App window, under a way that worked in some window states; %@ lists the others, e.g. “covered or on another desktop”")
        // Tried only with its windows closed: it may work with one open (the
        // 1.2.3 review's workflow note, P2, the user's pick, 2026-10-28).
        case .none where windowsClosed:
            String(localized: "It didn’t pause and play \(app) with its windows closed",
                   comment: "Add an App window, under a way that was tried and didn't work in a check that found the app's windows closed (tried once, nothing moved); %@ is the app")
        case .none:
            String(localized: "It didn’t pause and play \(app)", comment: "Add an App window, under a way that was tried and didn't work; %@ is the app")
        case .notThere:
            switch way.kind {
            case .script: String(localized: "\(app) can’t be scripted", comment: "Add an App window, under “AppleScript”; %@ is the app")
            case .menu: String(localized: "\(app) has no playback menu", comment: "Add an App window, under “Its playback menu”; %@ is the app")
            case .page: String(localized: "It shows no page with a Play/Pause", comment: "Add an App window, under “Its page’s Play/Pause” when the app shows no page, or none with a Play/Pause button")
            case .panel: String(localized: "\(app) doesn’t show in Now Playing", comment: "Add an App window, under “The menu bar’s Now Playing panel”; %@ is the app")
            }
        case .menuBarHidden:
            String(localized: "Not tried: hidden in the menu bar; show it in \(ControlFailure.nowPlayingSettings), then check again",
                   comment: "Add an App window, under “The menu bar’s Now Playing panel” when Now Playing is hidden in the menu bar (a Check Again button follows); %@ is where the setting is, e.g. “System Settings → Menu Bar”")
        case .toggleOnly:
            String(localized: "Only toggles: AutoHush can’t tell when to send it",
                   comment: "Add an App window, under “AppleScript” when it paused and played the app but only by one Play/Pause command, and nothing tells AutoHush whether the app plays, so it can't be used")
        case .notTried:
            String(localized: "Not tried", comment: "Add an App window, under a way the check found but didn't try")
        case .noAutomation:
            String(localized: "Not checked: Automation isn’t allowed", comment: "Add an App window, under “AppleScript” when the check couldn't try it without the Automation permission")
        case .noAccessibility:
            String(localized: "Not checked: Accessibility isn’t allowed", comment: "Add an App window, under a way the check couldn't look for without the Accessibility permission")
        case .noWindow:
            String(localized: "Not checked: its windows were closed",
                   comment: "Add an App window, under “Its page’s Play/Pause” when the app's windows were closed, so its page couldn't be read (opening one and checking again would)")
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
        case .windowsClosed: String(localized: "closed", comment: "Add an App window, in “Not with its window %@”: a window state (no window open, as a menu bar player playing on)")
        }
    }
}
