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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WindowHeader(icon: player?.icon(size: 56),
                             description: Text(String(localized: "Web apps have no controls AutoHush can use, so it learns \(name)’s Play and Pause buttons.",
                                                      comment: "The learning window, at its top beside the web app's icon; %@ is the web app")))
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
            }
            .windowMargins()
            BottomBar {
                Spacer()
                Button { later() } label: { Text(verbatim: LaterText.title) }
                    .buttonStyle(.chip)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: AddWebAppView.width) // a guiding window's, as Add a Web App's
        .font(.appBody)
    }
}

/// The permission learning needs first, as the checklist's step to do now
/// with its button under it: in the learning window and the Add a Web App
/// window, above the steps it locks.
struct LearningPermissionStep: View {
    let model: SettingsModel
    let permission: Permission
    let access: PermissionAccess
    let name: String

    var body: some View {
        let step = Self.step(permission, name: name)
        ChecklistStepRow(step: step, dimmed: false, bold: true, action: { _ in }) {
            StepSymbol(step: step)
        } accessory: {
            PermissionButton(model: model, permission: permission, access: access, long: true, prominent: true)
                .padding(.top, 2)
        }
    }

    /// Why the steps wait, under the permission.
    static func note(_ name: String) -> String {
        String(localized: "AutoHush needs it to see \(name)’s buttons. The steps below unlock once it’s allowed.",
               comment: "The learning window, under the permission it needs first; %@ is the web app")
    }

    /// The step: the permission to allow, why the steps wait under it.
    static func step(_ permission: Permission, name: String) -> ChecklistStep {
        ChecklistStep(title: permission.statusLine, notes: [note(name)], state: .current)
    }

    /// What VoiceOver announces while the steps wait: the permission, then
    /// why, as the step reads.
    static func announcement(_ permission: Permission, name: String) -> String {
        let step = step(permission, name: name)
        return ([step.title] + step.notes).joined(separator: "\n")
    }
}
