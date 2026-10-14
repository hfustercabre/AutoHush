import SwiftUI

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
    /// hear the checklist move on. The windows' checklists announce. `atOnce`
    /// also announces it as the window appears: a locked window says why.
    func announcesCurrentStep(_ announcement: String?, atOnce: Bool = false) -> some View {
        onChange(of: announcement, initial: atOnce) { _, announcement in
            guard let announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}

/// A checklist step's button: blue, as the window's next thing to do, under
/// the step's lines; Return presses it, as a window's main button. Outside
/// the step's VoiceOver element, so it's reached as a button of its own.
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
        .keyboardShortcut(secondary ? nil : .defaultAction)
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
/// failed, a spinner while AutoHush does it, an arrow in the accent color for
/// the step to do now (pointing forward, so it turns in right-to-left
/// languages), and a circle (a lock while it waits on a permission) for the
/// rest. The same in every window that shows steps.
struct StepSymbol: View {
    let step: ChecklistStep
    var locked = false

    var body: some View {
        if step.isBusy {
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        } else {
            switch step.state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.appWarning)
            case .current: Image(systemName: "arrow.forward.circle.fill").foregroundStyle(Color.accentColor)
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
