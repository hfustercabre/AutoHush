import SwiftUI
import AutoHushKit

// A player AutoHush must first learn to control (a Safari web app: which of
// its buttons plays and pauses it) asks the user to play it and say so
// (It's Playing). AutoHush then pauses it itself. When that doesn't take, the
// step is marked failed, with Try Again and Pause It Manually; the latter
// adds a step where the user pauses it and says so (It's Paused), within a
// minute.
// The steps show only in a window: the learning window, which asks when the
// player is chosen, or Add a Web App, once it has made the web app. The
// menu's card and Settings → General have a Controls row saying whether
// they're learned, with Learn Controls (or Learn Again once learned): a new
// learning window that starts over (the user may have closed the last one
// halfway).

/// What learning a player's controls says.
enum LearningText {
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
    /// learning starts over from “Play a song in …”.
    static func countdown(_ remaining: TimeInterval) -> String {
        let time = Duration.seconds(Int(remaining.rounded(.up))).formatted(.time(pattern: .minuteSecond))
        return String(localized: "You have \(time) to pause it and click It’s Paused.",
                      comment: "Under the step “Pause it yourself” while AutoHush learns a web app's controls, on a tinted line: a countdown, after which learning starts over; %@ is the time left, e.g. 0:45; “It’s Paused” is the button under it")
    }

    // The Controls row (the menu's card, Settings → General): whether
    // they're learned, and the way to learn them in a new learning window.

    /// The row's title.
    static var controlsTitle: String {
        String(localized: "Controls",
               comment: "The menu's card and Settings → General: title of the row about the chosen web app's controls (its Play/Pause button), under the media player")
    }

    /// Under the row's title, until they're learned.
    static func notLearnedNote(_ name: String) -> String {
        String(localized: "Not learned yet: AutoHush can’t pause \(name) until it has.",
               comment: "The menu's card and Settings → General, under “Controls”, while AutoHush hasn't learned the web app's Play/Pause button (the learning window was closed); “Learn Controls” follows; %@ is the web app's name")
    }

    /// Under the row's title, once they're learned.
    static var learnedNote: String {
        String(localized: "Learned. Learn them again if AutoHush gets them wrong.",
               comment: "The menu's card and Settings → General, under “Controls”: the web app's controls (its Play/Pause button) are learned, and what to do if AutoHush gets them wrong; “Learn Again” follows")
    }

    /// The row's button, until they're learned.
    static var learnButton: String {
        String(localized: "Learn Controls",
               comment: "The menu's card and Settings → General, in the “Controls” row while the web app's controls aren't learned yet: button that opens the window that learns them, from the first step. Keep it short: the row's title already says “Controls”, so “Learn” alone is fine")
    }

    /// The row's button, once they're learned.
    static var learnAgainButton: String {
        String(localized: "Learn Again",
               comment: "The menu's card and Settings → General, in the “Controls” row once the web app's controls are learned: button that learns them again in a new window; what was learned keeps working until the user clicks “It’s Playing” there")
    }
}

/// A web app's controls, in the menu's card and Settings → General: whether
/// they're learned, and Learn Controls (Learn Again once learned), which
/// opens a new learning window from the first step.
struct ControlsRow: View {
    let name: String
    let isLearned: Bool
    /// The button's text: the menu's are a step smaller than Settings'.
    var buttonFont: Font = .appBody
    let learn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(Text(verbatim: LearningText.controlsTitle),
                     subtitle: Text(verbatim: isLearned ? LearningText.learnedNote : LearningText.notLearnedNote(name)))
            Spacer(minLength: 8)
            Button(action: learn) {
                Text(verbatim: isLearned ? LearningText.learnAgainButton : LearningText.learnButton).font(buttonFont)
            }
            .buttonStyle(.chip)
            .fixedSize()
        }
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
    /// The same, at once: another app is Now Playing, so the Play/Pause key
    /// would have reached that one, and AutoHush didn't press it.
    case keyElsewhere

    /// The user pauses it (`byHand`, `keyElsewhere`).
    var pausesByHand: Bool { self == .byHand || self == .keyElsewhere }
}

/// What the user does while AutoHush learns, and what AutoHush does, each
/// ticked once done, with a tip and a button under the one to do now.
struct LearningSteps: View {
    let name: String
    let hasPlayed: Bool
    let hasPaused: Bool
    /// A permission is missing: the steps wait, locked, without tips.
    var locked = false
    /// Tells VoiceOver when the next step comes (in the learning window).
    var announces = false
    /// Once it plays: when learning starts over without the pause.
    var deadline: Date?
    var note: LearningNote?
    var pauseMode = LearningPauseMode.automatic
    var action: @MainActor (StepButton) -> Void = { _ in }

    var body: some View {
        Group {
            if let deadline, hasPlayed, !hasPaused, !locked, pauseMode.pausesByHand {
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
    /// step, which counts down. When the key would have reached another app,
    /// the user's pause step comes at once, saying so. Locked, none is to
    /// do yet.
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
        case .keyElsewhere:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, notes: [LearningText.keyElsewhere(name)], state: .failed)
        }
        guard mode.pausesByHand else { return [playStep, autoPause] }
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
