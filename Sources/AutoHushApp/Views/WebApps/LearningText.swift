import Foundation

/// What learning a player's controls says.
enum LearningText {
    static func playStep(_ name: String) -> String {
        String(localized: "Play something in \(name)",
               comment: "The first step while AutoHush learns a web app's controls, ticked once the user clicks “It’s Playing”; and the Add an App window's step that waits for the app to play; %@ is the web app or app")
    }

    /// The step after it plays: AutoHush pauses it itself.
    static var autoPauseStep: String {
        String(localized: "Let AutoHush pause it",
               comment: "The step after “Play something in %@” while AutoHush learns a web app's controls: AutoHush pauses the web app itself (with the keyboard's Play/Pause key) to see which button changes")
    }

    /// The step the user does when AutoHush couldn't pause it.
    static var handPauseStep: String {
        String(localized: "Pause it yourself",
               comment: "The step after “Let AutoHush pause it” failed and the user chose “Pause It Yourself”, while AutoHush learns a web app's controls: the user pauses the web app")
    }

    /// Under the play step until it's done: a site that needs an account
    /// plays nothing until you log in, and during an ad the player's own
    /// button may say it's paused (some sites' do).
    static func playTip(_ name: String) -> String {
        String(localized: "Log in first if \(name) asks. Ads don’t count: wait for what you chose, then click It’s Playing.",
               comment: "Under the step “Play something in %@” while AutoHush learns a web app's controls; %@ is the web app; “It’s Playing” is the button under it")
    }

    /// Under AutoHush's pause step while it pauses the player.
    static func autoPauseTip(_ name: String) -> String {
        String(localized: "AutoHush pauses \(name) for a moment, then plays it again.",
               comment: "Under the step “Let AutoHush pause it” while AutoHush pauses the web app itself to learn its controls; %@ is the web app")
    }

    /// Under AutoHush's pause step once it couldn't pause the player.
    static func autoPauseFailed(_ name: String) -> String {
        String(localized: "AutoHush couldn’t pause \(name).",
               comment: "Under the step “Let AutoHush pause it”, marked failed, when AutoHush couldn't pause the web app itself; “Try Again” and “Pause It Yourself” follow; %@ is the web app")
    }

    /// Under AutoHush's pause step when it didn't press the key: another app
    /// is Now Playing.
    static func keyElsewhere(_ name: String) -> String {
        String(localized: "AutoHush didn’t pause \(name): the Play/Pause key would have reached another app.",
               comment: "Under the step “Let AutoHush pause it”, marked failed, when AutoHush didn't press the keyboard's Play/Pause key because macOS would have sent it to another app (the one in Now Playing); the step “Pause it yourself” follows; %@ is the web app")
    }

    /// Under the user's pause step until it's done.
    static var pauseTip: String {
        String(localized: "Then click It’s Paused. AutoHush sees which button changed.",
               comment: "Under the step “Pause it yourself” while AutoHush learns a web app's controls; “It’s Paused” is the button under it")
    }

    /// Under the user's pause step, standing out: how long is left before
    /// learning starts over from “Play something in …”.
    static func countdown(_ remaining: TimeInterval) -> String {
        let time = remaining.countdownText
        return String(localized: "You have \(time) to pause it and click It’s Paused.",
                      comment: "Under the step “Pause it yourself” while AutoHush learns a web app's controls, on a tinted line: a countdown, after which learning starts over; %@ is the time left, e.g. 0:45; “It’s Paused” is the button under it")
    }
}
