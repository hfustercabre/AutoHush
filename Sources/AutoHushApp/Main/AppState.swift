import Observation
import AutoHushKit

/// The one place the app's status is kept (see GLOSSARY.md). AppDelegate
/// writes it, and the menu gets a copy each time it changes. Settings and
/// the welcome, learning and Add a Web App windows read it through their
/// model, part by part: each part is followed on its own, so a window is
/// drawn again only when a part it shows changes, not each time the music
/// or the apps playing do.
@MainActor
@Observable
final class AppState {
    /// The whole status; the windows follow its parts below, not it.
    @ObservationIgnored var status = AppStatus() {
        didSet { showParts() }
    }

    // The parts the windows show (see `AppStatus`).
    private(set) var playerOptions: [PlayerOption] = []
    private(set) var chosenPlayerID: String?
    private(set) var chosenPlayer: PlayerOption?
    private(set) var learning: LearningStatus?
    private(set) var canLearnControlsAgain = false
    private(set) var learningPause = LearningPause()
    private(set) var statusLine = ""
    private(set) var needsAttention = false
    private(set) var autoPause = AppStatus.AutoPause.on
    private(set) var seenApps: [AudioSource] = []
    private(set) var ignoredApps: [AudioSource] = []

    init() {
        showParts()
    }

    /// Sets each part that changed, and only those.
    private func showParts() {
        show(\.playerOptions, status.playerOptions)
        show(\.chosenPlayerID, status.chosenPlayerID)
        show(\.chosenPlayer, status.chosenPlayer)
        show(\.learning, status.learning)
        show(\.canLearnControlsAgain, status.canLearnControlsAgain)
        show(\.learningPause, status.learningPause)
        show(\.statusLine, status.statusLine)
        show(\.needsAttention, status.needsAttention)
        show(\.autoPause, status.autoPause)
        show(\.seenApps, status.seenApps)
        show(\.ignoredApps, status.ignoredApps)
    }

    private func show<Part: Equatable>(_ part: ReferenceWritableKeyPath<AppState, Part>, _ value: Part) {
        if self[keyPath: part] != value { self[keyPath: part] = value }
    }
}
