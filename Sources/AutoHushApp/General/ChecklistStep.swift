import SwiftUI

/// Where a step of a window's checklist stands (adding a web app, learning
/// its controls). The check, arrow or circle beside it shows that on screen;
/// VoiceOver reads it after the step's words.
enum StepState: Equatable {
    case done, current, todo

    var voiceOverValue: String {
        switch self {
        case .done:
            String(localized: "Completed",
                   comment: "VoiceOver, after a step of a checklist (adding a web app, learning its controls): the step is done")
        case .current:
            String(localized: "In progress",
                   comment: "VoiceOver, after a step of a checklist (adding a web app, learning its controls): the step to do now")
        case .todo:
            String(localized: "To do",
                   comment: "VoiceOver, after a step of a checklist (adding a web app, learning its controls): a step still to come")
        }
    }
}

/// What the user clicks in a checklist step while it's the one to do, to say
/// it's done (learning: the song plays, it's paused) or to go on (adding).
enum StepButton: Equatable, Sendable {
    case itsPlaying, itsPaused, addToDock

    var title: String {
        switch self {
        case .itsPlaying:
            String(localized: "It’s Playing",
                   comment: "Button under the step “Play a song in %@” while AutoHush learns a web app's controls: the song itself plays now")
        case .itsPaused:
            String(localized: "It’s Paused",
                   comment: "Button under the step “Pause it” while AutoHush learns a web app's controls: the user has paused it")
        case .addToDock:
            String(localized: "Add to Dock",
                   comment: "Add a Web App window, under the step “Add it to the Dock”: adds the website shown in Safari as a web app (Safari's own menu item is called “Add to Dock…”)")
        }
    }
}

/// A step as a checklist shows it: its words, the lines under them, and
/// where it stands.
struct ChecklistStep: Equatable {
    let title: String
    var notes: [String] = []
    let state: StepState
    /// What the user clicks while it's the one to do.
    var button: StepButton?
    /// Why the last try didn't go on, under the lines (a `NoteLabel`).
    var warning: String?
    /// What VoiceOver says once it's the step to do now: its title, unless
    /// the step goes on in another way (“Now pause it.”).
    var announcement: String?
}

extension [ChecklistStep] {
    /// What VoiceOver says about the step to do now; `nil` when there's none.
    var currentAnnouncement: String? {
        first { $0.state == .current }.map { $0.announcement ?? $0.title }
    }
}

extension View {
    /// A checklist step as one VoiceOver element: its words and the lines
    /// under them as its label, then where it stands as its value. (Combined
    /// text keeps its words in its value, which the state would replace.)
    func checklistStepAccessibility(_ step: ChecklistStep) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(Text(verbatim: ([step.title] + step.notes + [step.warning].compactMap { $0 }).joined(separator: "\n")))
            .accessibilityValue(Text(verbatim: step.state.voiceOverValue))
    }

    /// Announces the step to do now whenever it changes, so VoiceOver users
    /// hear the checklist move on. Only a window's checklist announces: the
    /// menu and Settings show the same steps.
    func announcesCurrentStep(_ announcement: String?) -> some View {
        onChange(of: announcement) { _, announcement in
            guard let announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}

/// A checklist step's button: blue, as the window's next thing to do, under
/// the step's lines. Outside the step's VoiceOver element, so it's reached
/// as a button of its own.
struct StepActionButton: View {
    let button: StepButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: button.title).font(.appBody.weight(.semibold)).padding(.horizontal, 6)
        }
        .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
        .padding(.top, 2)
    }
}

/// A checklist step as a row: its icon, words, lines and warning (one
/// VoiceOver element), then its button while it's the one to do.
struct ChecklistStepRow<Icon: View>: View {
    let step: ChecklistStep
    /// Done (or waiting on a permission): its words in the secondary color.
    var dimmed: Bool
    /// The one to do now, in a window that marks it.
    var bold = false
    var action: (StepButton) -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: step.title)
                        .foregroundStyle(dimmed ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
                        .fontWeight(bold ? .semibold : .regular)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(step.notes, id: \.self) { Text(verbatim: $0).captionStyle().fixedSize(horizontal: false, vertical: true) }
                    if let warning = step.warning { NoteLabel(warning).padding(.top, 2) }
                }
                .checklistStepAccessibility(step)
                if let button = step.button { StepActionButton(button: button) { action(button) } }
            }
        }
    }
}
