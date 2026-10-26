import AppKit
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
    /// At once, not after a delay: VoiceOver skips an announcement from
    /// AutoHush once another app is in front, as the web app's window is a
    /// second after Add a Web App's Continue (heard in the VM, 2026-10-19).
    func announcesCurrentStep(_ announcement: String?, atOnce: Bool = false) -> some View {
        onChange(of: announcement, initial: atOnce) { _, announcement in
            guard let announcement else { return }
            postStepAnnouncement(announcement)
        }
    }
}

/// Posts a step's announcement at high priority: the focus change that
/// comes with a step (Add a Web App's field dimmed, the web app's window
/// opening) would otherwise cut it off before VoiceOver says it (heard in the
/// VM, 2026-10-18). Through AppKit: SwiftUI's announcement keeps a priority
/// inside its text, not in the notification's priority, which VoiceOver reads.
@MainActor
func postStepAnnouncement(_ text: String) {
    let element: NSObject = NSApp.keyWindow ?? NSApp
    NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: stepAnnouncementInfo(text))
}

/// The announcement's text and its high priority, as `NSAccessibility` takes them.
func stepAnnouncementInfo(_ text: String) -> [NSAccessibility.NotificationUserInfoKey: Any] {
    [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
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
