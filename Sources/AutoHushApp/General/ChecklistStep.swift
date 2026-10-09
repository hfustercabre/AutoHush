import SwiftUI

/// Where a step of a window's checklist stands (adding a web app, learning
/// its controls). The check, arrow, circle or cross beside it shows that on
/// screen; VoiceOver reads it after the step's words.
enum StepState: Equatable {
    case done, current, todo
    /// AutoHush tried it and couldn't (pausing a web app itself).
    case failed

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
        case .failed:
            String(localized: "Failed",
                   comment: "VoiceOver, after a step of a checklist (learning a web app's controls): AutoHush tried the step and couldn't do it")
        }
    }
}

/// What the user clicks in a checklist step while it's the one to do, to say
/// it's done (learning: the song plays, it's paused) or to go on (adding).
enum StepButton: Equatable, Sendable {
    case itsPlaying, itsPaused, addToDock
    /// AutoHush couldn't pause the web app itself: it tries again, or the
    /// user pauses it.
    case tryAgain, pauseManually

    var title: String {
        switch self {
        case .itsPlaying:
            String(localized: "It’s Playing",
                   comment: "Button under the step “Play a song in %@” while AutoHush learns a web app's controls: the song itself plays now")
        case .itsPaused:
            String(localized: "It’s Paused",
                   comment: "Button under the step “Pause it yourself” while AutoHush learns a web app's controls: the user has paused it")
        case .tryAgain:
            String(localized: "Try Again",
                   comment: "Button under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself: it tries again")
        case .pauseManually:
            String(localized: "Pause It Manually",
                   comment: "Button under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself: the user pauses it instead (a step “Pause it yourself” follows)")
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
    /// What the user clicks while it's the one to do (blue), and another way
    /// on beside it (grey).
    var button: StepButton?
    var secondaryButton: StepButton?
    /// Why the last try didn't go on, under the lines (a `NoteLabel`).
    var warning: String?
    /// How long is left to do it, as a sentence: a tinted line that stands
    /// out (`CountdownBanner`).
    var countdown: String?
    /// AutoHush is doing it now: a spinner instead of its circle.
    var isBusy = false
    /// What VoiceOver says once it's the step to do now: its title, unless
    /// the step goes on in another way (“Now pause it.”).
    var announcement: String?
}

extension [ChecklistStep] {
    /// What VoiceOver says about the step to do now (or, with none, the one
    /// that failed, which offers what to do next); `nil` when there's none.
    var currentAnnouncement: String? {
        (first { $0.state == .current } ?? first { $0.state == .failed }).map { $0.announcement ?? $0.title }
    }
}

extension View {
    /// A checklist step as one VoiceOver element: its words and the lines
    /// under them as its label, then where it stands as its value. (Combined
    /// text keeps its words in its value, which the state would replace.)
    func checklistStepAccessibility(_ step: ChecklistStep) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(Text(verbatim: ([step.title] + step.notes + [step.warning, step.countdown].compactMap { $0 })
                .joined(separator: "\n")))
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
    /// Grey, as the other way on beside the blue one.
    var secondary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: button.title).font(secondary ? .appBody : .appBody.weight(.semibold)).padding(.horizontal, 6)
                .fixedSize() // one line: two that don't fit go one under the other
        }
        .buttonStyle(ChipButtonStyle(filled: true, isSelected: !secondary, padded: true))
        .padding(.top, 2)
    }
}

/// How long is left to do a step, as a sentence on an orange-tinted line
/// with a timer, so it stands out among the step's grey lines.
struct CountdownBanner: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "timer")
        }
        .font(.appCallout.weight(.semibold))
        .foregroundStyle(.appWarning)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.warningBadgeFill))
        .padding(.vertical, 2)
    }
}

/// The symbol beside a checklist step: a check once done, a cross once
/// failed, a spinner while AutoHush does it, else `current` for the step to
/// do now and a circle (a lock while it waits on a permission) for the rest.
struct StepSymbol: View {
    let step: ChecklistStep
    var locked = false
    /// The current step's symbol: a circle in lists, an arrow in the Add a
    /// Web App window, which marks it.
    var current = Image(systemName: "circle")
    var currentStyle: AnyShapeStyle = AnyShapeStyle(.appSecondary)

    var body: some View {
        if step.isBusy {
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        } else {
            switch step.state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.appWarning)
            case .current: current.foregroundStyle(currentStyle)
            case .todo: Image(systemName: locked ? "lock.circle" : "circle").foregroundStyle(.appSecondary)
            }
        }
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
                    if let countdown = step.countdown { CountdownBanner(text: countdown).padding(.top, 2) }
                }
                .checklistStepAccessibility(step)
                if step.button != nil || step.secondaryButton != nil {
                    // Side by side when they fit on one line each, else one under the other.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { buttons }
                        VStack(alignment: .leading, spacing: 6) { buttons }
                    }
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if let button = step.button { StepActionButton(button: button) { action(button) } }
        if let other = step.secondaryButton { StepActionButton(button: other, secondary: true) { action(other) } }
    }
}
