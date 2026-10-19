import SwiftUI

/// A window's main button: macOS's prominent push button, its title
/// semibold, and Return presses it (Continue, Done, Choose, Start the
/// Check). `secondary`: grey and regular, the other way on beside it, with
/// no key of its own. `cancels`: Escape presses it instead (the check's Stop).
struct MainButton: View {
    let title: String
    var secondary = false
    var cancels = false
    let action: () -> Void

    init(_ title: String, secondary: Bool = false, cancels: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.secondary = secondary
        self.cancels = cancels
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(secondary ? .appBody : .appBody.weight(.semibold)).padding(.horizontal, 6)
        }
        .buttonStyle(ChipButtonStyle(filled: true, isSelected: !secondary))
        .keyboardShortcut(cancels ? .cancelAction : secondary ? nil : .defaultAction)
    }
}

/// A step's button, under its lines (a checklist's, Add an App's): a
/// `MainButton` on one line, so two that don't fit side by side go one
/// under the other (`FlowingButtons`).
struct StepActionButton: View {
    let title: String
    var secondary = false
    var cancels = false
    let action: () -> Void

    init(_ title: String, secondary: Bool = false, cancels: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.secondary = secondary
        self.cancels = cancels
        self.action = action
    }

    var body: some View {
        MainButton(title, secondary: secondary, cancels: cancels, action: action)
            .fixedSize()
            .padding(.top, 2)
    }
}
