import AppKit
import SwiftUI
import AutoHushKit

// The window that asks to play and pause a player AutoHush must learn, and
// the permission step that comes first (in the Add a Web App window too).
// The steps themselves are in Views/WebApps/LearningSteps.swift.

/// The learning window's content: the player, why AutoHush learns, the
/// steps, and Later at the foot.
struct LearningWindowView: View {
    let model: SettingsModel
    let later: () -> Void

    var body: some View {
        let player = model.chosenPlayer
        let name = player?.name ?? ""
        // Learning again (`.relearning`), it starts from the first step.
        let learned = model.learning == .learned
        let hasPlayed = learned || model.learning == .learning(hasPlayed: true)
        // A guiding window's width, as Add a Web App's.
        WindowPage(icon: player?.icon(size: 56),
                   description: Text(String(localized: "Web apps have no controls AutoHush can use, so it learns \(name)’s Play and Pause buttons.",
                                            comment: "The learning window, at its top beside the web app's icon; %@ is the web app")),
                   width: AddWebAppView.width) {
            NoteLabel(PlayerOption.webAppsWarning)
                .padding(.top, 8)
            SectionHeading(AddWebAppView.stepsHeading).padding(.top, 8)
            Card {
                // Without the permission AutoHush can't watch the player:
                // asking for it comes first, and the steps unlock once it's allowed.
                let state = model.permissions
                let locked = state.controlMissing(for: model.chosenPlayerID)
                if locked, let control = state.control {
                    LearningPermissionStep(model: model, permission: control, access: state.controlAccess, name: name)
                }
                LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: learned,
                              locked: locked, announces: true,
                              lockedAnnouncement: state.control.map { LearningPermissionStep.announcement($0, name: name) },
                              deadline: model.learningPauseDeadline, note: model.learningNote,
                              pauseMode: model.learningPauseMode, action: { model.learningSession.step($0) })
                // Learning again, the controls it learned still work
                // until It's Playing: the line would be untrue then.
                if model.learning != .relearning {
                    CardDivider()
                    Text("Until it has learned, AutoHush presses nothing on the page.",
                         comment: "The learning window, under the steps: until AutoHush has learned a web app's Play/Pause button, it presses none of the page's buttons (it pauses the web app once with the keyboard's Play/Pause key)")
                        .captionStyle()
                }
            }
        } bar: {
            Spacer()
            Button { later() } label: { Text(verbatim: LaterText.title) }
                .buttonStyle(.chip)
                .keyboardShortcut(.cancelAction)
        }
    }
}
