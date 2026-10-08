import AppKit
import SwiftUI
import AutoHushKit

// A player AutoHush must first learn to control (a Safari web app: which of
// its buttons plays and pauses it) asks the user to play it and say so
// (It's Playing), then pause it and say so (It's Paused), within a minute.
// A window asks when it's chosen; until it has learned, the menu and
// Settings → General show the same steps, in case the window was closed.

/// What learning a player's controls says.
enum LearningText {
    static func title(_ name: String) -> String {
        String(localized: "Learning \(name)’s Controls",
               comment: "Menu and Settings, while AutoHush learns which button plays and pauses a web app; %@ is its name")
    }

    static func explanation(_ name: String) -> String {
        String(localized: "AutoHush learns which button plays and pauses \(name): tell it when the song plays, and when you’ve paused it.",
               comment: "Menu and Settings, under “Learning %@’s Controls”; %@ is the web app")
    }

    static func playStep(_ name: String) -> String {
        String(localized: "Play a song in \(name)",
               comment: "The first step while AutoHush learns a web app's controls, ticked once the user clicks “It’s Playing”; %@ is the web app")
    }

    static var pauseStep: String {
        String(localized: "Pause it", comment: "The step after “Play something in %@”: pause the web app")
    }

    /// Under the play step until it's done: a site that needs an account
    /// plays nothing until you log in, and during an ad the player's own
    /// button may say it's paused (some sites' do).
    static func playTip(_ name: String) -> String {
        String(localized: "Log in first if \(name) asks you to. Ads don’t count: wait for the song itself. Then click It’s Playing.",
               comment: "Under the step “Play a song in %@” while AutoHush learns a web app's controls; %@ is the web app; “It’s Playing” is the button under it")
    }

    /// Under the pause step until it's done.
    static var pauseTip: String {
        String(localized: "Then click It’s Paused. AutoHush sees which button changed.",
               comment: "Under the step “Pause it” while AutoHush learns a web app's controls; “It’s Paused” is the button under it")
    }

    /// Under the pause step: how long is left before learning starts over
    /// from “Play a song in …”.
    static func countdown(_ remaining: TimeInterval) -> String {
        let time = Duration.seconds(Int(remaining.rounded(.up))).formatted(.time(pattern: .minuteSecond))
        return String(localized: "Back to the first step in \(time)",
                      comment: "Under the step “Pause it” while AutoHush learns a web app's controls: a countdown; %@ is the time left, e.g. 0:45")
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
        String(localized: "Learned from you playing and pausing \(name). If AutoHush gets them wrong, learn them again.",
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
                   comment: "Under the step “Pause it” after “It’s Paused” was clicked while nothing had changed on the web app's page; %@ is the web app")
        case .timedOut:
            String(localized: "A minute went by without the pause. Play the song again, then click It’s Playing.",
                   comment: "Under the step “Play a song in %@” once learning went back to it: “It’s Paused” wasn't clicked within a minute")
        case .cantSeePage:
            String(localized: "AutoHush can’t see \(name)’s page. Open its window, or close it and open it again, then click It’s Playing again.",
                   comment: "Under the step “Play a song in %@” when AutoHush couldn't read the web app's page (not running, no window, or a window restored without its buttons' names); %@ is the web app")
        }
    }
}

/// The two things the user does while AutoHush learns, each ticked once they
/// say it's done, with a tip and a button under the one to do now.
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
    var action: @MainActor (StepButton) -> Void = { _ in }

    var body: some View {
        Group {
            if let deadline, hasPlayed, !hasPaused, !locked {
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
                               remaining: remaining, note: note)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(steps, id: \.title) { step($0) }
        }
        .announcesCurrentStep(announces ? steps.currentAnnouncement : nil)
    }

    /// Play, then pause: the one to do now has its tip, its button, and the
    /// note about the last click; the pause step counts down. Locked, neither
    /// is to do yet.
    static func steps(name: String, hasPlayed: Bool, hasPaused: Bool, locked: Bool,
                      remaining: TimeInterval? = nil, note: LearningNote? = nil) -> [ChecklistStep] {
        let play: StepState = hasPlayed ? .done : locked ? .todo : .current
        let pause: StepState = hasPaused ? .done : hasPlayed && !locked ? .current : .todo
        var pauseNotes: [String] = []
        if pause == .current {
            pauseNotes.append(LearningText.pauseTip)
            if let remaining { pauseNotes.append(LearningText.countdown(remaining)) }
        }
        return [
            ChecklistStep(title: LearningText.playStep(name), notes: play == .current ? [LearningText.playTip(name)] : [],
                          state: play, button: play == .current ? .itsPlaying : nil,
                          warning: play == .current && note != .nothingChanged ? note?.text(name) : nil),
            ChecklistStep(title: LearningText.pauseStep, notes: pauseNotes,
                          state: pause, button: pause == .current ? .itsPaused : nil,
                          warning: pause == .current && note == .nothingChanged ? note?.text(name) : nil),
        ]
    }

    private func step(_ step: ChecklistStep) -> some View {
        let done = step.state == .done
        return ChecklistStepRow(step: step, dimmed: done || locked, action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : locked ? "lock.circle" : "circle")
                .foregroundStyle(done ? AnyShapeStyle(.appSuccess) : AnyShapeStyle(.appSecondary))
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
    var action: @MainActor (StepButton) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: LearningText.title(name)).font(.appHeadline)
            Text(verbatim: LearningText.explanation(name)).captionStyle()
            LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: false, deadline: deadline, note: note, action: action)
        }
    }
}

// MARK: - The learning window

/// What `AppDelegate` needs of the learning window; tests stand in for it,
/// so they never put a window on screen.
@MainActor
protocol LearningWindowPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func close()
}

/// Opens when a player that must learn is chosen: it asks the user to play
/// and pause it once, ticks each step as it's seen, and closes by itself
/// once AutoHush has learned. "Later" closes it; the menu and Settings keep
/// showing the steps.
@MainActor
final class LearningWindowController: HostedWindowController, LearningWindowPresenting {
    init(model: SettingsModel) {
        // Later closes the window, which exists only once this has run.
        let hosting = Self.sizedToFit(LearningWindowView(model: model, later: {}))
        super.init(content: hosting, title: "AutoHush")
        hosting.rootView = LearningWindowView(model: model) { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The learning window's content: the player, why AutoHush learns, the
/// steps, and Later.
struct LearningWindowView: View {
    let model: SettingsModel
    let later: () -> Void

    var body: some View {
        let player = model.chosenPlayer
        let name = player?.name ?? ""
        let learned = model.learning == .learned
        let hasPlayed = learned || model.learning == .learning(hasPlayed: true)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let player {
                    Image(nsImage: player.icon(size: 56))
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Learn \(name)’s Controls",
                                comment: "Title of the window that asks to play and pause a web app once; %@ is its name"))
                        .font(.appTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Web apps have no controls AutoHush can use directly, so it learns which of \(name)’s buttons plays and pauses it.",
                                comment: "The learning window, under its title; %@ is the web app"))
                        .captionStyle()
                }
            }
            NoteLabel(PlayerOption.webAppsWarning)
            Card {
                // Without the permission AutoHush can't watch the player:
                // asking for it comes first, and the steps unlock once it's allowed.
                let state = model.permissions
                if let control = state.control, !state.controlAccess.isSatisfied {
                    LearningPermissionStep(model: model, permission: control, access: state.controlAccess, name: name)
                }
                LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: learned,
                              locked: state.control != nil && !state.controlAccess.isSatisfied, announces: true,
                              deadline: model.learningPauseDeadline, note: model.learningNote,
                              action: { model.learningStep($0) })
                CardDivider()
                Text("AutoHush only watches; it doesn’t press anything until it has learned.",
                     comment: "The learning window, under the steps")
                    .captionStyle()
            }
            HStack {
                Spacer()
                Button {
                    later()
                } label: {
                    Text("Later", comment: "Button that closes it for now: an update alert, or a window that learns a web app's controls (the learning window, the Add a Web App window)")
                }
                .buttonStyle(.chip)
            }
        }
        .padding(20)
        .frame(width: 440)
        .font(.appBody)
    }
}

/// The permission learning needs first, as a step with its button: in the
/// learning window and the Add a Web App window, above the steps it locks.
struct LearningPermissionStep: View {
    let model: SettingsModel
    let permission: Permission
    let access: PermissionAccess
    let name: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle")
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: permission.statusLine)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "AutoHush needs it to see \(name)’s buttons. The steps below unlock once it’s allowed.",
                            comment: "The learning window, under the permission it needs first; %@ is the web app"))
                    .captionStyle()
                    .fixedSize(horizontal: false, vertical: true)
                PermissionButton(model: model, permission: permission, access: access, long: true, prominent: true)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
