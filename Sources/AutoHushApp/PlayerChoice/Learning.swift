import AppKit
import SwiftUI
import AutoHushKit

// A player AutoHush must first learn to control (a Safari web app: which of
// its buttons plays and pauses it) asks the user to play and pause it once.
// A window asks when it's chosen; until it has learned, the menu and
// Settings → General show the same steps, in case the window was closed.

/// What learning a player's controls says.
enum LearningText {
    static func title(_ name: String) -> String {
        String(localized: "Learning \(name)’s Controls",
               comment: "Menu and Settings, while AutoHush learns which button plays and pauses a web app; %@ is its name")
    }

    static func explanation(_ name: String) -> String {
        String(localized: "Use \(name) as usual. AutoHush watches which button plays and pauses it.",
               comment: "Menu and Settings, under “Learning %@’s Controls”; %@ is the web app")
    }

    static func playStep(_ name: String) -> String {
        String(localized: "Play something in \(name)",
               comment: "A step AutoHush waits for while it learns a web app's controls, ticked once done; %@ is the web app")
    }

    static var pauseStep: String {
        String(localized: "Pause it", comment: "The step after “Play something in %@”: pause the web app")
    }

    /// Under the play step until it's done: a start is told by the button
    /// changing as the sound comes on, and an ad's own controls aren't the
    /// player's.
    static var playTip: String {
        String(localized: "Let the music itself play for 5 to 10 seconds. Ads don’t count.",
               comment: "Under the step “Play something in %@” while AutoHush learns a web app's controls")
    }

    /// Under the pause step until it's done: a web app's sound goes off only
    /// about 8 seconds after a pause, and playing again before hides it.
    static var pauseTip: String {
        String(localized: "Wait for the tick before playing again. It can take up to 10 seconds.",
               comment: "Under the step “Pause it” while AutoHush learns a web app's controls")
    }
}

/// The two things the user does while AutoHush learns, each ticked once
/// seen, with a tip under the one to do now.
struct LearningSteps: View {
    let name: String
    let hasPlayed: Bool
    let hasPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(done: hasPlayed, LearningText.playStep(name), tip: hasPlayed ? nil : LearningText.playTip)
            step(done: hasPaused, LearningText.pauseStep, tip: hasPlayed && !hasPaused ? LearningText.pauseTip : nil)
        }
    }

    private func step(done: Bool, _ text: String, tip: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AnyShapeStyle(.appSuccess) : AnyShapeStyle(.appSecondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text)
                    .foregroundStyle(done ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if let tip {
                    Text(verbatim: tip)
                        .captionStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}

/// The steps with what they're for: in the menu, under the card, and in
/// Settings → General, under the player.
struct LearningSummary: View {
    let name: String
    let hasPlayed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: LearningText.title(name)).font(.appHeadline)
            Text(verbatim: LearningText.explanation(name)).captionStyle()
            LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: false)
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
final class LearningWindowController: NSWindowController, LearningWindowPresenting {
    init(model: SettingsModel) {
        // Later closes the window, which exists only once this has run.
        let hosting = NSHostingController(rootView: LearningWindowView(model: model, later: {}))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "AutoHush"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        hosting.rootView = LearningWindowView(model: model) { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if !isVisible { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
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
                LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: learned)
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
                    Text("Later", comment: "Button that closes it for now: an update alert, or the window that learns a web app's controls")
                }
                .buttonStyle(.chip)
            }
        }
        .padding(20)
        .frame(width: 440)
        .font(.appBody)
    }
}
