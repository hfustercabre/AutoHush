import SwiftUI
import AutoHushKit

// A player AutoHush must first learn to control (a Safari web app: which of
// its buttons plays and pauses it) asks the user to play it and say so
// (It's Playing). AutoHush then pauses it itself. When that doesn't take, the
// step is marked failed, with Try Again and Pause It Manually; the latter
// adds a step where the user pauses it and says so (It's Paused), within a
// minute.
// A window asks when it's chosen; until it has learned, the menu and
// Settings → General show the same steps, in case the window was closed.

/// What learning a player's controls says.
enum LearningText {
    static func title(_ name: String) -> String {
        String(localized: "Learning \(name)’s Controls",
               comment: "Menu and Settings, while AutoHush learns which button plays and pauses a web app; %@ is its name")
    }

    static func explanation(_ name: String) -> String {
        String(localized: "AutoHush learns which button plays and pauses \(name): tell it when the song plays, and it pauses the song to see which button changes.",
               comment: "Menu and Settings, under “Learning %@’s Controls”; %@ is the web app")
    }

    static func playStep(_ name: String) -> String {
        String(localized: "Play a song in \(name)",
               comment: "The first step while AutoHush learns a web app's controls, ticked once the user clicks “It’s Playing”; %@ is the web app")
    }

    /// The step after it plays: AutoHush pauses it itself.
    static var autoPauseStep: String {
        String(localized: "Let AutoHush pause it",
               comment: "The step after “Play a song in %@” while AutoHush learns a web app's controls: AutoHush pauses the web app itself (with the keyboard's Play/Pause key) to see which button changes")
    }

    /// The step the user does when AutoHush couldn't pause it.
    static var handPauseStep: String {
        String(localized: "Pause it yourself",
               comment: "The step after “Let AutoHush pause it” failed and the user chose “Pause It Manually”, while AutoHush learns a web app's controls: the user pauses the web app")
    }

    /// Under the play step until it's done: a site that needs an account
    /// plays nothing until you log in, and during an ad the player's own
    /// button may say it's paused (some sites' do).
    static func playTip(_ name: String) -> String {
        String(localized: "Log in first if \(name) asks you to. Ads don’t count: wait for the song itself. Then click It’s Playing.",
               comment: "Under the step “Play a song in %@” while AutoHush learns a web app's controls; %@ is the web app; “It’s Playing” is the button under it")
    }

    /// Under AutoHush's pause step while it pauses the player.
    static func autoPauseTip(_ name: String) -> String {
        String(localized: "AutoHush pauses \(name) for a moment, then plays it again.",
               comment: "Under the step “Let AutoHush pause it” while AutoHush pauses the web app itself to learn its controls; %@ is the web app")
    }

    /// Under AutoHush's pause step once it couldn't pause the player.
    static func autoPauseFailed(_ name: String) -> String {
        String(localized: "AutoHush couldn’t pause \(name).",
               comment: "Under the step “Let AutoHush pause it”, marked failed, when AutoHush couldn't pause the web app itself; “Try Again” and “Pause It Manually” follow; %@ is the web app")
    }

    /// Under the user's pause step until it's done.
    static var pauseTip: String {
        String(localized: "Then click It’s Paused. AutoHush sees which button changed.",
               comment: "Under the step “Pause it yourself” while AutoHush learns a web app's controls; “It’s Paused” is the button under it")
    }

    /// Under the user's pause step, standing out: how long is left before
    /// learning starts over from “Play a song in …”.
    static func countdown(_ remaining: TimeInterval) -> String {
        let time = Duration.seconds(Int(remaining.rounded(.up))).formatted(.time(pattern: .minuteSecond))
        return String(localized: "You have \(time) to pause it and click It’s Paused.",
                      comment: "Under the step “Pause it yourself” while AutoHush learns a web app's controls, on a tinted line: a countdown, after which learning starts over; %@ is the time left, e.g. 0:45; “It’s Paused” is the button under it")
    }

    // Learning them again, once learned (they may have been learned wrong).

    /// In the menu's player list and Settings' player pop-up, with the web
    /// app's name under it: the menu's width can't take the name in the
    /// title in most languages.
    static var learnAgainItem: String {
        String(localized: "Learn Controls Again…",
               comment: "The menu's player list and Settings' player pop-up: forgets the chosen web app's learned controls (its Play/Pause button) and learns them again; the web app's name shows under it")
    }

    /// Settings → General: the row's title.
    static var controlsTitle: String {
        String(localized: "Controls",
               comment: "Settings → General: title of the row about the chosen web app's learned controls (its Play/Pause button), under “Music player”")
    }

    /// Settings → General: under the row's title.
    static func controlsNote(_ name: String) -> String {
        String(localized: "Learned from \(name) playing and pausing. If AutoHush gets them wrong, learn them again.",
               comment: "Settings → General, under “Controls”: how the web app's controls were learned, and what to do if AutoHush gets them wrong; %@ is the web app's name")
    }

    /// Settings → General: the row's button.
    static var learnAgainButton: String {
        String(localized: "Learn Again",
               comment: "Settings → General, in the “Controls” row: button that forgets the web app's learned controls and learns them again")
    }
}

/// Why the user's last click didn't move the learning on, shown under its
/// step until the next one.
enum LearningNote: Equatable, Sendable {
    /// It's Playing, while the web app couldn't be heard.
    case notHeard
    /// It's Paused, while no button had changed since It's Playing.
    case nothingChanged
    /// It's Paused didn't come within `LearningStatus.pauseWait`.
    case timedOut
    /// The web app's page couldn't be read: it isn't running, has no window,
    /// or its window shows its buttons without their words.
    case cantSeePage

    func text(_ name: String) -> String {
        switch self {
        case .notHeard:
            String(localized: "AutoHush can’t hear \(name) yet. Play a song, then click It’s Playing again.",
                   comment: "Under the step “Play a song in %@” after “It’s Playing” was clicked while the web app was silent; %@ is the web app")
        case .nothingChanged:
            String(localized: "No button changed in \(name). Make sure it’s paused, then click It’s Paused again.",
                   comment: "Under the step “Pause it yourself” after “It’s Paused” was clicked while nothing had changed on the web app's page; %@ is the web app")
        case .timedOut:
            String(localized: "A minute went by without the pause. Play the song again, then click It’s Playing.",
                   comment: "Under the step “Play a song in %@” once learning went back to it: “It’s Paused” wasn't clicked within a minute")
        case .cantSeePage:
            String(localized: "AutoHush can’t see \(name)’s page. Open its window, or close it and open it again, then click It’s Playing again.",
                   comment: "Under the step “Play a song in %@” when AutoHush couldn't read the web app's page (not running, no window, or a window restored without its buttons' names); %@ is the web app")
        }
    }
}

/// How the pause goes once the song plays: AutoHush tries it itself first.
enum LearningPauseMode: Equatable, Sendable {
    /// AutoHush pauses it itself, once it plays.
    case automatic
    /// AutoHush is pausing it now.
    case trying
    /// AutoHush couldn't: the user picks Try Again or Pause It Manually.
    case failed
    /// The user pauses it and says so, within the minute.
    case byHand
}

/// What the user does while AutoHush learns, and what AutoHush does, each
/// ticked once done, with a tip and a button under the one to do now.
struct LearningSteps: View {
    let name: String
    let hasPlayed: Bool
    let hasPaused: Bool
    /// A permission is missing: the steps wait, locked, without tips.
    var locked = false
    /// Tells VoiceOver when the next step comes (in the learning window,
    /// not the menu or Settings).
    var announces = false
    /// Once it plays: when learning starts over without the pause.
    var deadline: Date?
    var note: LearningNote?
    var pauseMode = LearningPauseMode.automatic
    var action: @MainActor (StepButton) -> Void = { _ in }

    var body: some View {
        Group {
            if let deadline, hasPlayed, !hasPaused, !locked, pauseMode == .byHand {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    list(remaining: max(0, deadline.timeIntervalSince(context.date)))
                }
            } else {
                list(remaining: nil)
            }
        }
    }

    private func list(remaining: TimeInterval?) -> some View {
        let steps = Self.steps(name: name, hasPlayed: hasPlayed, hasPaused: hasPaused, locked: locked,
                               remaining: remaining, note: note, pauseMode: pauseMode)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(steps, id: \.title) { step($0) }
        }
        .announcesCurrentStep(announces ? steps.currentAnnouncement : nil)
    }

    /// Play, then AutoHush pauses it: the one to do now has its tip, its
    /// button, and the note about the last click. While AutoHush pauses it,
    /// its step spins; when it couldn't, the step is marked failed, with Try
    /// Again and Pause It Manually, and the latter adds the user's pause
    /// step, which counts down. Locked, none is to do yet.
    static func steps(name: String, hasPlayed: Bool, hasPaused: Bool, locked: Bool,
                      remaining: TimeInterval? = nil, note: LearningNote? = nil,
                      pauseMode: LearningPauseMode = .automatic) -> [ChecklistStep] {
        let mode = locked ? .automatic : pauseMode
        let play: StepState = hasPlayed || mode != .automatic ? .done : locked ? .todo : .current
        let playStep = ChecklistStep(title: LearningText.playStep(name), notes: play == .current ? [LearningText.playTip(name)] : [],
                                     state: play, button: play == .current ? .itsPlaying : nil,
                                     warning: play == .current && note != .nothingChanged ? note?.text(name) : nil)
        let autoPause: ChecklistStep
        switch mode {
        case .automatic:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, state: hasPaused ? .done : .todo)
        case .trying:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, notes: [LearningText.autoPauseTip(name)],
                                      state: hasPaused ? .done : .current, isBusy: !hasPaused)
        case .failed:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, state: .failed, button: .tryAgain,
                                      secondaryButton: .pauseManually, warning: LearningText.autoPauseFailed(name))
        case .byHand:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, notes: [LearningText.autoPauseFailed(name)], state: .failed)
        }
        guard mode == .byHand else { return [playStep, autoPause] }
        let handPause = ChecklistStep(title: LearningText.handPauseStep, notes: hasPaused ? [] : [LearningText.pauseTip],
                                      state: hasPaused ? .done : .current, button: hasPaused ? nil : .itsPaused,
                                      warning: !hasPaused && note == .nothingChanged ? note?.text(name) : nil,
                                      countdown: hasPaused ? nil : remaining.map(LearningText.countdown))
        return [playStep, autoPause, handPause]
    }

    private func step(_ step: ChecklistStep) -> some View {
        ChecklistStepRow(step: step, dimmed: step.state == .done || (locked && step.state == .todo),
                         bold: [.current, .failed].contains(step.state), action: action) {
            StepSymbol(step: step, locked: locked)
        }
    }
}

/// The steps with what they're for: in the menu, under the card, and in
/// Settings → General, under the player.
struct LearningSummary: View {
    let name: String
    let hasPlayed: Bool
    var deadline: Date?
    var note: LearningNote?
    var pauseMode = LearningPauseMode.automatic
    var action: @MainActor (StepButton) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: LearningText.title(name)).font(.appHeadline)
            Text(verbatim: LearningText.explanation(name)).captionStyle()
            LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: false, deadline: deadline, note: note,
                          pauseMode: pauseMode, action: action)
        }
    }
}
