import SwiftUI

/// The symbol beside a step: a check once done, a cross once failed, a
/// spinner while AutoHush does it, an arrow in the accent color for the step
/// to do now (pointing forward, so it turns in right-to-left languages), and
/// a circle (a lock while it waits on a permission) for the rest. A numbered
/// step (Add an App's) shows its number in the circle instead, filled with
/// the accent color while it's the one to do. The same in every window that
/// shows steps.
struct StepSymbol: View {
    /// Where the step stands; a spinner while AutoHush is doing it.
    let status: StepStatus
    /// A numbered step's number (`NumberedStepRow`).
    var number: Int?
    var locked = false

    var body: some View {
        if status.isBusy {
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        } else {
            switch status.state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.appWarning)
            case .current:
                Image(systemName: number.map { "\($0).circle.fill" } ?? "arrow.forward.circle.fill").foregroundStyle(Color.accentColor)
            case .todo:
                Image(systemName: number.map { "\($0).circle" } ?? (locked ? "lock.circle" : "circle")).foregroundStyle(.appSecondary)
            }
        }
    }
}

extension StepSymbol {
    /// A checklist step's (adding a web app, learning its controls).
    init(step: ChecklistStep, locked: Bool = false) {
        self.init(status: step.status, locked: locked)
    }
}
