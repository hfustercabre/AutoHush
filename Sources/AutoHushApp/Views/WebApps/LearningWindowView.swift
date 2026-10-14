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
                             description: Text(String(localized: "Web apps have no controls AutoHush can use directly, so it learns which of \(name)’s buttons plays and pauses it.",
                                                      comment: "The learning window, at its top beside the web app's icon; %@ is the web app")))
                NoteLabel(PlayerOption.webAppsWarning)
                    .padding(.top, 8)
                SectionHeading(AddWebAppView.stepsHeading).padding(.top, 8)
                Card {
                    // Without the permission AutoHush can't watch the player:
                    // asking for it comes first, and the steps unlock once it's allowed.
                    let state = model.permissions
                    if let control = state.control, !state.controlAccess.isSatisfied {
                        LearningPermissionStep(model: model, permission: control, access: state.controlAccess, name: name)
                    }
                    LearningSteps(name: name, hasPlayed: hasPlayed, hasPaused: learned,
                                  locked: state.control != nil && !state.controlAccess.isSatisfied, announces: true,
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
            BottomBar(margin: HostedWindowController.margin) {
                Spacer()
                Button {
                    later()
                } label: {
                    Text("Later", comment: "Button that closes it for now: an update alert, or a window that learns a web app's controls (the learning window, the Add a Web App window)")
                }
                .buttonStyle(.chip)
                .keyboardShortcut(.cancelAction)
            }
        }
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
            // The step to do now, as a checklist marks it (`StepSymbol`).
            Image(systemName: "arrow.forward.circle.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: permission.statusLine)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: Self.note(name))
                        .captionStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(verbatim: StepState.current.voiceOverValue))
                PermissionButton(model: model, permission: permission, access: access, long: true, prominent: true)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Why the steps wait, under the permission.
    static func note(_ name: String) -> String {
        String(localized: "AutoHush needs it to see \(name)’s buttons. The steps below unlock once it’s allowed.",
               comment: "The learning window, under the permission it needs first; %@ is the web app")
    }

    /// What VoiceOver announces while the steps wait: the permission, then why.
    static func announcement(_ permission: Permission, name: String) -> String {
        [permission.statusLine, note(name)].joined(separator: "\n")
    }
}
