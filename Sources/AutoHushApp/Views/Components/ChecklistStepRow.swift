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
}

/// A checklist step as a row: its icon, words, lines and warning (one
/// VoiceOver element), then its buttons while it's the one to do, and
/// `accessory` under them (the permission learning needs first: its
/// `PermissionButton`), each reached as a button of its own.
struct ChecklistStepRow<Icon: View, Accessory: View>: View {
    let step: ChecklistStep
    /// Done (or waiting on a permission): its words in the secondary color.
    var dimmed: Bool
    /// The one to do now, in a window that marks it.
    var bold = false
    var action: (StepButton) -> Void
    /// Where VoiceOver's cursor goes, by step title: the window moves it to
    /// the step to do now.
    var focus: AccessibilityFocusState<String?>.Binding?
    let icon: Icon
    let accessory: Accessory

    init(step: ChecklistStep, dimmed: Bool, bold: Bool = false, focus: AccessibilityFocusState<String?>.Binding? = nil,
         action: @escaping (StepButton) -> Void, @ViewBuilder icon: () -> Icon, @ViewBuilder accessory: () -> Accessory) {
        self.step = step
        self.dimmed = dimmed
        self.bold = bold
        self.focus = focus
        self.action = action
        self.icon = icon()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: step.title)
                        .foregroundStyle(dimmed ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
                        .fontWeight(bold ? .semibold : .regular)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(step.notes, id: \.self) { Text(verbatim: $0).captionStyle() }
                    if let warning = step.warning { NoteLabel(warning).padding(.top, 2) }
                    if let countdown = step.countdown { CountdownBanner(text: countdown).padding(.top, 2) }
                }
                .checklistStepAccessibility(step)
                .modifier(StepFocus(focus: focus, title: step.title))
                if step.button != nil || step.secondaryButton != nil {
                    FlowingButtons { buttons }
                }
                accessory
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if let button = step.button { MainButton(button.title, inStep: true) { action(button) } }
        if let other = step.secondaryButton { MainButton(other.title, secondary: true, inStep: true) { action(other) } }
    }
}

extension ChecklistStepRow where Accessory == EmptyView {
    init(step: ChecklistStep, dimmed: Bool, bold: Bool = false, focus: AccessibilityFocusState<String?>.Binding? = nil,
         action: @escaping (StepButton) -> Void, @ViewBuilder icon: () -> Icon) {
        self.init(step: step, dimmed: dimmed, bold: bold, focus: focus, action: action, icon: icon) { EmptyView() }
    }
}

/// A step's VoiceOver element, tied to its window's cursor when there's one.
private struct StepFocus: ViewModifier {
    let focus: AccessibilityFocusState<String?>.Binding?
    let title: String

    func body(content: Content) -> some View {
        if let focus {
            content.accessibilityFocused(focus, equals: title)
        } else {
            content
        }
    }
}
